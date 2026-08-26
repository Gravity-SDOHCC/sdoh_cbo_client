module TasksHelper
  include SessionsHelper

  # A server we are pointed at may be down, unreachable, slow, mis-configured for
  # TLS, or simply not a FHIR server at all. None of those are recoverable by us,
  # but none of them may take the dashboard down either: every one has to become
  # a flash message and an empty task list.
  SERVER_ERRORS = [
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EHOSTUNREACH,
    Errno::ENETUNREACH,
    Errno::ETIMEDOUT,
    SocketError,
    Timeout::Error, # covers Net::OpenTimeout and Net::ReadTimeout
    RestClient::Exceptions::Timeout, # ...which rest-client re-raises as its own
    RestClient::ServerBrokeConnection,
    OpenSSL::SSL::SSLError,
    JSON::ParserError,
  ].freeze

  # Error bodies get interpolated into a flash message. A server that answers
  # with an HTML error page would otherwise put the whole page in the toast.
  MAX_ERROR_BODY_LENGTH = 300

  def save_tasks(tasks)
    Rails.cache.write(tasks_key, tasks, expires_in: 1.day)
  end

  def fetch_tasks
    client = get_fhir_client
    return [false, "Not connected to a FHIR server. Please connect to a server and try again."] if client.nil?

    # TODO: We are Not getting the include resources in the response
    begin
      response = client.search(FHIR::Task, search: task_search_params)
      code = response&.response&.[](:code)

      if code != 200
        Rails.logger.error("Failed to fetch referral tasks. Status: #{code} - #{error_body(response)}")

        return [false, "Failed to fetch referral tasks from #{requester_server_description}. Status: #{code} - #{error_body(response)}"]
      end

      bundle = response.resource
      if !bundle.is_a?(FHIR::Bundle)
        Rails.logger.error("#{requester_server_description} answered 200 but returned no FHIR Bundle: #{error_body(response)}")

        return [false, "#{requester_server_description} answered, but did not return a FHIR Bundle of Tasks. Check that the URL points at a FHIR endpoint, then log out and pick another server."]
      end

      entries = bundle.entry&.map(&:resource)
      task_entries = entries&.select { |entry| entry&.resourceType == "Task" }

      tasks = task_entries&.map { |entry| Task.new(entry, client) }

      grp = group_tasks(tasks)
      save_tasks(tasks)

      [true, grp]
    rescue *SERVER_ERRORS => e
      Rails.logger.error(e.full_message)

      [false, "Could not reach #{requester_server_description}. Check that the URL is correct and the server is up, then log out and pick another server. #{e.class}: #{e.message}"]
    rescue StandardError => e
      Rails.logger.error(e.full_message)

      [false, "Something went wrong talking to #{requester_server_description}. #{e.message}"]
    end
  end

  # The assessment findings already on the server for this referral's patient,
  # offered by the completion modal so this client can return them in
  # Task.output:AdditionalContent.
  #
  # Cached per patient: the dashboard polls every 30 seconds and re-renders every
  # modal, so without this it would be one search per resource type per task per
  # poll. Only the modal that offers "completed" asks for findings, which keeps
  # the searches to accepted and in-progress referrals rather than the whole
  # table.
  def assessment_findings(patient_id, category_codes = [])
    return if patient_id.blank?

    Rails.cache.fetch(findings_key(patient_id), expires_in: 5.minutes) do
      AssessmentFindings.load(
        fhir_client: get_fhir_client,
        patient_id: patient_id,
        category_codes: category_codes,
      )
    end
  end

  # An SDOH domain code as the modal shows it: "housing-instability" is not a
  # word anyone says out loud.
  def sdoh_domain_label(code)
    code.to_s.tr("-", " ").titleize
  end

  def findings_key(patient_id)
    "#{session_id}_findings_#{patient_id}"
  end

  # The program and enrollment status lists offered by the accepted-task modal.
  # They belong to TasksController, which is what writes the Observation, and
  # the modal is rendered from the dashboard, so a helper is how the view reaches
  # them instead of a second copy drifting out of step with the writer.
  def enrollment_programs
    TasksController::ENROLLMENT_PROGRAMS
  end

  def enrollment_statuses
    TasksController::ENROLLMENT_STATUSES
  end

  private

  # The base URL the session actually holds. SessionsHelper defines this one;
  # an undefined helper here would turn a recoverable connection failure into an
  # unrescued NoMethodError.
  def requester_server_description
    get_requester_server_base_url.presence || "the selected FHIR server"
  end

  def error_body(response)
    body = response&.response&.[](:body)
    return "no response body" if body.blank?

    body = body.to_s
    body.length > MAX_ERROR_BODY_LENGTH ? "#{body[0, MAX_ERROR_BODY_LENGTH]}..." : body
  end


  def group_tasks(tasks)
    grp = { "active" => [], "completed" => [], "cancelled" => [] }
    tasks&.each do |task|
      grp["active"] << task if task&.status != "completed" && task&.status != "cancelled" && task&.status != "rejected"
      grp["completed"] << task if task&.status == "completed"
      grp["cancelled"] << task if task&.status == "cancelled" || task&.status == "rejected"
    end
    grp
  end

  def task_search_params
    {
      parameters: {
        _profile: FhirProfiles::TASK_FOR_REFERRAL_MANAGEMENT,
        owner: "Organization/#{get_my_org_id}",
        _sort: "-_lastUpdated",
      },
    }
  end

  # "39y · male · b. Feb 20, 1987" - what a referral target needs to
  # identify the person, from US Core Patient.
  def patient_summary(fhir_patient)
    birth_date = parse_birth_date(fhir_patient&.birthDate)
    parts = []
    parts << "#{age_in_years(birth_date)}y" if birth_date
    parts << fhir_patient.gender if fhir_patient&.gender.present?
    parts << "b. #{birth_date.strftime("%b %-d, %Y")}" if birth_date
    parts.join(" · ")
  end

  def parse_birth_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def age_in_years(birth_date)
    today = Date.current
    age = today.year - birth_date.year
    age -= 1 if ([today.month, today.day] <=> [birth_date.month, birth_date.day]) == -1
    age
  end

end

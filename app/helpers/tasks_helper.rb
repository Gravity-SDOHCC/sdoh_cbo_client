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

  # Badge colours for the resource types Task.output:AdditionalContent may point
  # at, so a returned QuestionnaireResponse reads differently from a Condition.
  FINDING_BADGE_CLASSES = {
    "QuestionnaireResponse" => "bg-info text-dark",
    "Observation" => "bg-secondary",
    "Condition" => "bg-danger",
    "Goal" => "bg-success",
    "CarePlan" => "bg-dark",
  }.freeze

  def finding_badge_class(resource_type)
    FINDING_BADGE_CLASSES.fetch(resource_type, "bg-light text-dark border")
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
  def assessment_findings(patient_id)
    return [] if patient_id.blank?

    Rails.cache.fetch(findings_key(patient_id), expires_in: 5.minutes) do
      TasksController::ASSESSMENT_FINDING_TYPES.flat_map { |type| search_findings(type, patient_id) }
    end
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

  # One patient-scoped search per resource type. The most recent 25 of each are
  # offered; a referral target returning findings is picking something it just
  # recorded, not trawling a lifetime of records.
  #
  # A type the server does not implement is not an error here: the shared EHR
  # server answers CarePlan with HAPI-0302 "Unknown resource type", so CarePlan
  # simply contributes nothing to the picker there while staying valid in
  # Task.output:AdditionalContent for a server that does support it.
  def search_findings(resource_type, patient_id)
    fhir_class = FHIR.const_get(resource_type, false)
    response = get_fhir_client.search(
      fhir_class,
      search: { parameters: { patient: patient_id, _sort: "-_lastUpdated", _count: 25 } },
    )
    if response.response[:code].to_i != 200
      Rails.logger.info("No #{resource_type} findings for patient #{patient_id}: server answered #{response.response[:code]}")
      return []
    end

    Array(response.resource&.entry).filter_map { |entry| Finding.build(entry.resource) }
  rescue StandardError => e
    Rails.logger.warn("Unable to search #{resource_type} for patient #{patient_id}: #{e.message}")
    []
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
end

module TasksHelper
  include SessionsHelper

  def save_tasks(tasks)
    Rails.cache.write("tasks", tasks, expires_in: 1.day)
  end

  def fetch_tasks
    client = get_fhir_client
    search_params = {
      parameters: {
        _profile: "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-TaskForReferralManagement",
        owner: "Organization/#{get_my_org_id}",
        _sort: "-_lastUpdated",
      },
    }
    # TODO: We are Not getting the include resources in the response
    begin
      response = client.search(FHIR::Task, search: search_params)
      if response.response[:code] == 200
        entries = response.resource.entry.map(&:resource)
        task_entries = entries.select { |entry| entry.resourceType == "Task" }
        # sr_entries = entries.select { |entry| entry.resourceType == "ServiceRequest" }
        # consent_entries = entries.select { |entry| entry.resourceType == "Consent" }
        # requester_entries = entries.select { |entry| entry.resourceType == "Organization" || entry.resourceType == "PractitionerRole" }
        # patient_entries = entries.select { |entry| entry.resourceType == "Patient" }
        # if consent_entries.size == 0
        #   consent_entries = client.read_feed(FHIR::Consent).resource&.entry&.map(&:resource) || []
        # end
        tasks = task_entries.map { |entry| Task.new(entry) }
        # task_entries.each do |task|
        #   # focus_id = get_id_from_reference(task.focus)
        #   # focus = sr_entries.find { |sr| sr.id == focus_id }
        #   # # byebug
        #   # consent_id = get_id_from_reference(focus&.supportingInfo)
        #   # consent = consent_entries.find { |consent| consent.id == consent_id }
        #   # patient_id = get_id_from_reference(task.for)
        #   # patient = patient_entries.find { |patient| patient.id == patient_id }
        #   # requester_id = get_id_from_reference(task.requester)
        #   # requester = requester_entries.find { |requester| requester.id == requester_id }

        #   # TODO: This is temporary. with auth, the org id will be in the token and we can use it to filter
        #   if task.requester.reference.include?("SDOHCC-OrganizationCoordinationPlatformExample")
        #     cp_tasks << Task.new(task)
        #   else
        #     ehr_tasks << Task.new(task)
        #   end
        # end

        # Group tasks by status and org requesting
        # grp = { "cp_tasks" => group_tasks(cp_tasks), "ehr_tasks" => group_tasks(ehr_tasks) }
        grp = group_tasks(tasks)
        save_tasks(tasks)

        [true, grp]
      else
        [false, "Failed to fetch referral tasks. Status: #{response.response[:code]} - #{response.response[:body]}"]
      end
    rescue Errno::ECONNREFUSED => e
      [false, "Connection refused. Please check FHIR server's URL #{get_ehr_base_url} is up and try again. #{e.message}"]
    rescue StandardError => e
      [false, "Something went wrong. #{e.message}"]
    end
  end

  private

  def group_tasks(tasks)
    grp = { "active" => [], "completed" => [], "cancelled" => [] }
    tasks&.each do |task|
      grp["active"] << task if task.status != "completed" && task.status != "cancelled" && task.status != "rejected"
      grp["completed"] << task if task.status == "completed"
      grp["cancelled"] << task if task.status == "cancelled" || task.status == "rejected"
    end
    grp
  end

  def get_id_from_reference(ref_obj)
    ref_obj&.reference&.split("/")&.last
  end
end

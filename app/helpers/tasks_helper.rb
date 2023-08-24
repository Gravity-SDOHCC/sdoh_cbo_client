module TasksHelper
  include SessionsHelper

  def save_tasks(tasks)
    Rails.cache.write(tasks_key, tasks, expires_in: 1.day)
  end

  def fetch_tasks
    client = get_fhir_client

    # TODO: We are Not getting the include resources in the response
    begin
      response = client.search(FHIR::Task, search: task_search_params)
      if response.response[:code] == 200
        entries = response.resource.entry.map(&:resource)
        task_entries = entries.select { |entry| entry.resourceType == "Task" }

        tasks = task_entries.map { |entry| Task.new(entry, client) }

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

  def task_search_params
    search_params = {
      parameters: {
        _profile: "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-TaskForReferralManagement",
        owner: "Organization/#{get_my_org_id}",
        _sort: "-_lastUpdated",
      },
    }
  end
end

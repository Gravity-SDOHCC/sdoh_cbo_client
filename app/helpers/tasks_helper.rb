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
        entries = response.resource&.entry&.map(&:resource)
        task_entries = entries&.select { |entry| entry&.resourceType == "Task" }

        tasks = task_entries&.map { |entry| Task.new(entry, client) }

        grp = group_tasks(tasks)
        save_tasks(tasks)

        [true, grp]
      else
        Rails.logger.error("Failed to fetch referral tasks. Status: #{response.response[:code]} - #{response.response[:body]}")

        [false, "Failed to fetch referral tasks. Status: #{response.response[:code]} - #{response.response[:body]}"]
      end
    rescue Errno::ECONNREFUSED => e
      Rails.logger.error(e.full_message)

      [false, "Connection refused. Please check FHIR server's URL #{get_ehr_base_url} is up and try again. #{e.message}"]
    rescue StandardError => e
      Rails.logger.error(e.full_message)

      [false, "Something went wrong. #{e.message}"]
    end
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

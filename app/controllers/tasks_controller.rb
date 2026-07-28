class TasksController < ApplicationController
  before_action :require_fhir_client

  def update_task
    cached_tasks = Rails.cache.read(tasks_key)
    client = get_fhir_client
    begin
      task = cached_tasks.present? ? cached_tasks.find { |t| t.id == params[:id] }&.fhir_resource : client.read(FHIR::Task, params[:id]).resource
      sr_id = task.focus&.reference&.split("/")&.last
      service_request = client.read(FHIR::ServiceRequest, sr_id).resource
      if task.present?
        status = params[:status] == "status" ? params[:task_status] : params[:status]
        task.status = status
        if status == "accepted" || status == "in-progress"
          client.update(task, task.id)
        elsif status == "rejected" || status == "cancelled"
          task.statusReason = { text: params[:status_reason] }
          client.update(task, task.id)
        elsif status == "completed"
          procedure = create_procedure(task, service_request)
          task.output = [
            {
              type: {
                coding: [
                  {
                    system: "http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/SDOHCC-CodeSystemTemporaryCodes",
                    code: "resulting-activity",
                    display: "Resulting Activity",
                  },
                ],
              },
              valueReference: {
                reference: "Procedure/#{procedure.id}",
              },
            },
          ]
          # TODO create a procedure, attach it to task then save
          client.update(task, task.id)
        end

        flash[:success] = "Task has been marked as #{status}."
      else
        Rails.logger.error("Unable to update task: task not found")

        flash[:error] = "Unable to update task: task not found"
      end
    rescue => e
      Rails.logger.error(e.full_message)

      flash[:error] = "Unable to update task: #{e.message}"
    end
    Rails.cache.delete(tasks_key)
    redirect_to dashboard_path
  end

  def poll_tasks
    if !fhir_client_connected?
      Rails.logger.error("Session expired")

      render json: { error: "Session expired" }, status: 440 and return
    end
    cached_tasks = Rails.cache.read(tasks_key) || []
    Rails.cache.delete(tasks_key)
    success, result = fetch_tasks

    if success
      @active_tasks = result["active"] || []
      @completed_tasks = result["completed"] || []
      @cancelled_tasks = result["cancelled"] || []
      if get_capacity_status == "at-capacity"
        newly_rejected, @active_tasks = auto_reject_at_capacity(@active_tasks)
        @cancelled_tasks = newly_rejected + @cancelled_tasks
      end

      new_tasks_list = Rails.cache.read(tasks_key) || []
      # check if any active tasks have changed status
      updated_tasks = []
      new_tasks_list.each do |task|
        saved_task = cached_tasks.find { |t| t&.id == task&.id }
        if saved_task && saved_task.status != task.status
          updated_tasks << task
        end
      end
      @task_notifications = updated_tasks&.map do |t|
        msg =
          t&.status == "requested" ?
            "new referral source task requested" :
            "task #{t&.focus&.description} was updated to #{t&.status}"
        [msg, t&.id]
      end || []
      ActionCable.server.broadcast "notifications", { task_notifications: @task_notifications.to_json }
      render json: {
               active_tasks: render_to_string(partial: "dashboard/tasks_table", locals: { referrals: @active_tasks, type: "active" }),
               completed_tasks: render_to_string(partial: "dashboard/tasks_table", locals: { referrals: @completed_tasks, type: "completed" }),
               cancelled_tasks: render_to_string(partial: "dashboard/tasks_table", locals: { referrals: @cancelled_tasks, type: "cancelled" }),
             }
    else
      Rails.logger.error("Unable to fetch tasks: #{result}")

      render json: {
        error: "Unable to fetch tasks",
      }
    end
  end

  private

  def create_procedure(task, service_request)
    procedure = FHIR::Procedure.new
    procedure.meta = {
      "profile": [
        "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-Procedure",
      ],
    }
    procedure.basedOn = [{
      "reference": "ServiceRequest/#{service_request.id}",
    }]
    procedure.status = "completed"
    procedure.category = service_request.category&.first
    procedure.code = service_request.code
    procedure.subject = service_request.subject
    procedure.reasonReference = service_request.reasonReference
    procedure.performedDateTime = Time.now.utc.strftime("%Y-%m-%d")

    get_fhir_client.create(procedure).resource
  end

  def auto_reject_at_capacity(tasks)
    client = get_fhir_client
    at_capacity_since = get_capacity_status_set_at
    rejected, remaining = [], []
    tasks.each do |task|
      if task.status == "requested" && requested_after?(task, at_capacity_since)
        fhir_task = task.fhir_resource
        fhir_task.status = "rejected"
        fhir_task.statusReason = { text: "Rejected - at capacity" }
        client.update(fhir_task, fhir_task.id)
        rejected << Task.new(fhir_task, client)
      else
        remaining << task
      end
    end
    [rejected, remaining]
  end

  # Only tasks requested AFTER the organization went to capacity are
  # auto-rejected; requests already received keep their place in the queue.
  def requested_after?(task, at_capacity_since)
    return false if at_capacity_since.nil?

    authored_on = task.fhir_resource&.authoredOn
    return false if authored_on.blank?

    Time.parse(authored_on) > at_capacity_since
  rescue ArgumentError
    false
  end
end

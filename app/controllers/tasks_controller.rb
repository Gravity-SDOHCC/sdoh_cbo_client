class TasksController < ApplicationController
  before_action :require_fhir_client
  before_action :get_cbo_organizations, only: [:poll_tasks]

  def update_task
    cached_tasks = Rails.cache.read("tasks")
    begin
      task = cached_tasks.present? ? cached_tasks.find { |t| t.id == params[:id] }&.fhir_resource : FHIR::Task.read(params[:id])
      sr_id = task.focus&.reference&.split("/")&.last
      service_request = FHIR::ServiceRequest.read(sr_id)
      if task.present?
        status = params[:status] == "status" ? params[:task_status] : params[:status]
        task.status = status
        if status == "accepted" || status == "in-progress"
          task_result = task.update
        elsif status == "rejected" || status == "cancelled"
          task.statusReason = { text: params[:status_reason] }
          task.update
        elsif status == "completed"
          procedure = create_procedure(task, service_request)
          task.output = [
            {
              "type": {
                "coding": [
                  {
                    "system": "http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/SDOHCC-CodeSystemTemporaryCodes",
                    "code": "resulting-activity",
                    "display": "Resulting Activity",
                  },
                ],
              },
              "valueReference": {
                "reference": "Procedure/#{procedure.id}",
              },
            },
          ]
          # TODO create a procedure, attach it to task then save
          task.update
        end

        flash[:success] = "Task has been marked as #{status}."
      else
        flash[:error] = "Unable to update task: task not found"
      end
    rescue => e
      flash[:error] = "Unable to update task: #{e.message}"
    end
    Rails.cache.delete("tasks")
    redirect_to dashboard_path
  end

  def poll_tasks
    if !fhir_client_connected?
      render json: { error: "Session expired" }, status: 440 and return
    end
    cached_tasks = Rails.cache.read("tasks") || []
    Rails.cache.delete("tasks")
    success, result = fetch_tasks

    if success
      @active_tasks = result["active"] || []
      @completed_tasks = result["completed"] || []
      @cancelled_tasks = result["cancelled"] || []

      new_taks_list = Rails.cache.read("tasks") || []
      # check if any active tasks have changed status
      updated_tasks = []
      new_taks_list.each do |task|
        saved_task = cached_tasks.find { |t| t.id == task.id }
        if saved_task && saved_task.status != task.status
          updated_tasks << task
        end
      end
      @task_notifications = updated_tasks&.map do |t|
        msg = t.status == "requested" ? "new referral source task requested" : "task #{t.focus&.description} was updated to #{t.status}"
        [msg, t.id]
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
    procedure.create
  end
end

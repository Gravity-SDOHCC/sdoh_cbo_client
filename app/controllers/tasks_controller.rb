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
          append_output(task, type_code: FhirProfiles::RESULTING_ACTIVITY_CODE, reference: "Procedure/#{procedure.id}")
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
        FhirProfiles::PROCEDURE,
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

  # Adds one entry to Task.output.
  #
  # SDOHCC-TaskForReferralManagement slices Task.output and every slice is 0..*:
  # a completed referral can carry a Procedure reference alongside a program
  # enrollment status, assessment responses and anything a later step adds.
  # Assigning the array replaced whatever was already there, so this appends.
  #
  # The slices are closed over what they may point at, so the reference is
  # checked before it goes anywhere near the server: PerformedActivityReference
  # only accepts Reference(SDOHCC-Procedure), and AdditionalContent is for
  # everything except the performed activity itself.
  def append_output(task, type_code:, reference:)
    resource_type, = TaskIoEntry.parse_reference(reference)

    case type_code
    when FhirProfiles::RESULTING_ACTIVITY_CODE
      unless resource_type == "Procedure"
        raise ArgumentError, "#{reference} is not a Procedure: Task.output:PerformedActivityReference only accepts Reference(SDOHCC-Procedure)"
      end
      display = FhirProfiles::RESULTING_ACTIVITY_DISPLAY
    when FhirProfiles::ADDITIONAL_CONTENT_CODE
      if resource_type == "Procedure"
        raise ArgumentError, "#{reference} is a Procedure: a performed activity belongs in Task.output:PerformedActivityReference, not AdditionalContent"
      end
      display = FhirProfiles::ADDITIONAL_CONTENT_DISPLAY
    else
      raise ArgumentError, "Unsupported Task.output type code #{type_code.inspect}"
    end

    output = FHIR::Task::Output.new(
      type: {
        coding: [
          {
            system: FhirProfiles::TEMPORARY_CODE_SYSTEM,
            code: type_code,
            display: display,
          },
        ],
      },
      valueReference: {
        reference: reference,
      },
    )

    task.output = Array(task.output) + [output]
    task
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

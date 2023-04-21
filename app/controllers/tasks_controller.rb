class TasksController < ApplicationController
  before_action :require_fhir_client
  before_action :get_cbo_organizations, only: [:poll_tasks]

  def update_task
    # cached_ehr_tasks = Rails.cache.read("tasks")
    cached_tasks = Rails.cache.read("tasks")
    part_of_id = ""
    begin
      task = cached_tasks.find { |t| t.id == params[:id] }&.fhir_resource
      sr_id = task.focus&.reference&.split("/")&.last
      service_request = FHIR::ServiceRequest.read(sr_id)
      if task.present?
        status = params[:status] == "status" ? params[:task_status] : params[:status]
        part_of_id = task.partOf&.first&.reference&.split("/")&.last
        task.status = status
        if status == "accepted"
          task_result = task.update
          create_cp_task_service_request(task_result, service_request)
        elsif status == "in-progress"
          task.update
        elsif status == "rejected"
          task.statusReason = { text: params[:status_reason] }
          task.update
        elsif status == "completed"
          # cp_task = cached_cp_tasks.map(&:fhir_resource).find { |t| t.partOf.first&.reference&.include?(task.id) }
          # task.output = cp_task.output
          # TODO create a procedure, attach it to task then save
          task.update
        elsif status == "cancelled" && part_of_id.present?
          ehr_task = cached_tasks.find { |t| t.id == part_of_id }&.fhir_resource
          task.statusReason = ehr_task.statusReason
          task.update
        elsif status == "cancelled" && part_of_id.blank?
          cp_task = cached_cp_tasks.map(&:fhir_resource).find { |t| t.partOf.first&.reference&.include?(task.id) }
          task.statusReason = cp_task.statusReason
          task.update
        end

        flash[:success] = "Task has been marked as #{status}."
      else
        flash[:error] = "Unable to update task: task not found"
      end
    rescue => e
      flash[:error] = "Unable to update task: #{e.message}"
    end
    Rails.cache.delete("cp_tasks")
    Rails.cache.delete("ehr_tasks")
    tab = part_of_id.present? ? "our-tasks" : "service-requests"
    set_active_tab(tab)
    redirect_to dashboard_path
  end

  def poll_tasks
    if !fhir_client_connected?
      render json: { error: "Session expired" }, status: 440 and return
    end
    # cached_cp_tasks = Rails.cache.read("cp_tasks") || []
    # cached_ehr_tasks = Rails.cache.read("ehr_tasks") || []
    cached_tasks = Rails.cache.read("tasks") || []
    Rails.cache.delete("tasks")
    # Rails.cache.delete("ehr_tasks")
    success, result = fetch_tasks

    if success
      @active_ehr_tasks = result["ehr_tasks"]&.dig("active") || []
      @completed_ehr_tasks = result["ehr_tasks"]&.dig("completed") || []
      @cancelled_ehr_tasks = result["ehr_tasks"]&.dig("cancelled") || []
      # new_ehr_tasks = Rails.cache.read("tasks") || []
      new_taks_list = Rails.cache.read("tasks") || []
      # check if any active tasks have changed status
      updated_ehr_tasks = []
      new_taks_list.each do |task|
        saved_task = cached_tasks.find { |t| t.id == task.id }
        if saved_task && saved_task.status != task.status
          updated_ehr_tasks << task
        end
      end
      @ehr_task_notifications = updated_ehr_tasks&.map do |t|
        msg = t.status == "requested" ? "new referral source task requested" : "task #{t.focus&.description} was updated to #{t.status}"
        [msg, t.id]
      end || []
    else
      Rails.logger.error("Unable to fetch tasks: #{result}")
    end
    ActionCable.server.broadcast "notifications", { ehr_task_notifications: @ehr_task_notifications.to_json }
    render json: {
      active_ehr_tasks: render_to_string(partial: "dashboard/ehr_tasks_table", locals: { referrals: @active_ehr_tasks, type: "active" }),
      completed_ehr_tasks: render_to_string(partial: "dashboard/ehr_tasks_table", locals: { referrals: @completed_ehr_tasks, type: "completed" }),
      cancelled_ehr_tasks: render_to_string(partial: "dashboard/ehr_tasks_table", locals: { referrals: @cancelled_ehr_tasks, type: "cancelled" }),
    }
  end

  private

  def create_cp_task_service_request(ehr_task, ehr_request)
    # Creating CP request
    cp_request = ehr_request
    cp_request.basedOn = [{ reference: "ServiceRequest/#{ehr_request.id}" }]
    cp_request.intent = "original-order"
    cp_request.id = nil
    result_cp_request = cp_request.create
    # Creating CP task
    cp_task = ehr_task
    cp_task.partOf = [{ reference: "Task/#{ehr_task.id}" }]
    cp_task.status = "requested"
    cp_task.authoredOn = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
    # TODO cp_task.requester = {reference: "Organization/#{current_user.id}", display: current_user.name}
    cp_task.requester = {
      "reference": "Organization/SDOHCC-OrganizationCoordinationPlatformExample",
      "display": "ABC Coordination Platform",
    }
    cp_task.owner = {
      "reference": "Organization/#{params[:cbo_organization_id]}",
      "display": Rails.cache.read("cbo")&.find { |o| o.id == params[:cbo_organization_id] }&.name,
    }
    cp_task.focus = { reference: "ServiceRequest/#{result_cp_request.id}" }
    cp_task.id = nil
    cp_task.create
  end
end

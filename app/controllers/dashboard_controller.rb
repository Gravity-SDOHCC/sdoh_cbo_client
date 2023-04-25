class DashboardController < ApplicationController
  before_action :require_fhir_client, :set_tasks

  # GET /dashboard
  def main
    @active_tab = active_tab
  end

  private

  # Getting all resources associated with the given patient

  def set_tasks
    success, result = fetch_tasks
    if success
      @active_tasks = result["active"] || []
      @completed_tasks = result["completed"] || []
      @cancelled_tasks = result["cancelled"] || []
    else
      flash[:warning] = result
    end
  end
end

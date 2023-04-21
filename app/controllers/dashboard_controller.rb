class DashboardController < ApplicationController
  before_action :require_fhir_client, :set_tasks, :get_cbo_organizations

  # GET /dashboard
  def main
    @active_tab = active_tab
  end

  private

  # Getting all resources associated with the given patient

  def set_tasks
    success, result = fetch_tasks
    if success
      @active_ehr_tasks = result["active"] || []
      @completed_ehr_tasks = result["completed"] || []
      @cancelled_ehr_tasks = result["cancelled"] || []
    else
      flash[:warning] = result
    end
  end
end

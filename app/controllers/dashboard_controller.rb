class DashboardController < ApplicationController
  before_action :require_fhir_client, :set_tasks

  private

  # Getting all resources associated with the given patient

  def set_tasks
    success, result = fetch_tasks
    if success
      @active_tasks = result["active"] || []
      @completed_tasks = result["completed"] || []
      @cancelled_tasks = result["cancelled"] || []
    else
      # The server we are pointed at could not be read. Render the dashboard
      # with empty tables and say why, so the user can log out and pick another
      # server instead of being stuck on an error page.
      @active_tasks = []
      @completed_tasks = []
      @cancelled_tasks = []
      flash.now[:warning] = result
    end
  end
end

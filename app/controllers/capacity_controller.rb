class CapacityController < ApplicationController
  before_action :require_fhir_client

  # POST /capacity_status
  #
  # Writes the selection straight through to the organization's FHIR
  # HealthcareService; there is no session copy to keep in sync.
  def update
    status = params[:capacity_status]

    unless CapacityStatus.valid?(status)
      flash[:error] = "Invalid capacity status"
      return redirect_to dashboard_path
    end

    if save_capacity_status(status)
      flash[:success] = "Capacity status set to #{CapacityStatus.label_for(status)}"
    else
      flash[:error] = "Capacity status could not be saved to the FHIR server. Check the server connection and try again."
    end

    redirect_to dashboard_path
  end
end

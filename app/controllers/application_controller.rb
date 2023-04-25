class ApplicationController < ActionController::Base
  protect_from_forgery with: :null_session
  include ApplicationHelper

  def require_fhir_client
    if fhir_client_connected?
      get_fhir_client
    else
      reset_session
      Rails.cache.clear
      flash[:error] = "Your session has expired. Plesase connect to a FHIR server"
      redirect_to home_path
    end
  end
end

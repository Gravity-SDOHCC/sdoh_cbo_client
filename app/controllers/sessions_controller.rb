class SessionsController < ApplicationController
  before_action :require_fhir_client, only: %i[select_org set_org destroy]
  # Get /home
  def index
    if fhir_client_connected?
      flash[:notice] = "You are already connected to a FHIR server (#{get_requester_server_base_url}). Logout to connrct to another FHIR server"
      redirect_to dashboard_path
    else
      @fhir_servers = FhirServer.all
    end
  end

  # POST /connect
  def create
    setup_clients
    # TODO: Refactor this to handle Errno::ECONNREFUSED , took too long to connect, etc. Also if-else not needed.
    begin
      capability_statement = @fhir_client.capability_statement

      if capability_statement.present?
        save_fhir_client(@fhir_client)
        fhir_server = FhirServer.find_or_create_by(base_url: params[:fhir_server_base_url]) do |server|
          server.name = params[:fhir_server_name]
        end
        save_requester_server_base_url(fhir_server.base_url)
        save_user_id(TEST_PROVIDER_ID)

        flash[:success] = "Successfully connected to #{fhir_server.name}"
        redirect_to select_org_path
      else
        flash[:error] = "Failed to connect to the provided referral source server, verify the URL provided is correct."
        redirect_to home_path
      end
    rescue StandardError => e
      puts "Error happened:#{e.class} => #{e.message}"
      flash[:error] = "Failed to connect to the provided server, verify the URL provided is correct. Error: #{e.message}"
      redirect_to home_path
    end
  end

  def select_org
    @organizations = fetch_and_cache_organizations
    if @organizations&.empty?
      flash[:warning] = "There are no organizations on the server. You need to select an org to query tasks for."
      redirect_to dasboard_path
    end
  rescue => e
    reset_session
    Rails.cache.clear
    flash[:error] = e.message
    redirect_to home_path
  end

  def set_org
    save_my_org_id(params[:organization_id])
    redirect_to dashboard_path
  end

  # delete /disconnect
  def destroy
    reset_session
    Rails.cache.clear
    flash[:success] = "Successfully disconnected from the FHIR server"
    redirect_to root_path
  end

  private

  def setup_clients
    @fhir_client = FhirClient.setup_client(params[:fhir_server_base_url])
  end
end

module SessionsHelper
  DEFAULT_EHR_URL = "http://localhost:8080/fhir"
  TEST_PROVIDER_ID = "SDOHCC-OrganizationCoordinationPlatformExample".freeze

  def save_fhir_client(fhir_client)
    @fhir_client = Rails.cache.fetch(client_key, expires_in: 1.day) do
      fhir_client
    end
  end

  def get_fhir_client
    @fhir_client = Rails.cache.read(client_key)
  end

  def fhir_client_connected?
    !!Rails.cache.read(client_key)
  end

  def clear_cache
    Rails.cache.delete(client_key)
    Rails.cache.delete(tasks_key)
    Rails.cache.delete(organizations_key)
  end

  def save_requester_server_base_url(base_url)
    session[:requester_server_base_url] = base_url
  end

  def get_requester_server_base_url
    session[:requester_server_base_url]
  end

  def save_my_org_id(org_id)
    session[:org_id] = org_id
  end

  def get_my_org_id
    session[:org_id]
  end

  def save_user_id(user_id)
    session[:user_id] = user_id
  end

  def current_user_id
    session[:user_id]
  end

  def set_active_tab(tab)
    session[:active_tab] = tab
  end

  def active_tab
    session[:active_tab] || "service-requests"
  end

  def session_id
    session.id
  end

  def client_key
    "#{session_id}_client"
  end

  def tasks_key
    "#{session_id}_tasks"
  end

  def organizations_key
    "#{session_id}_organizations}"
  end
end

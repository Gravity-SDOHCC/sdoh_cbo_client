module ApplicationHelper
  include SessionsHelper
  include TasksHelper

  def fetch_and_cache_organizations
    Rails.cache.fetch(organizations_key, expires_in: 1.day) do
      client = get_fhir_client
      raise "Not connected to a FHIR server. Please connect to a server and try again." if client.nil?

      reply = client.search(FHIR::Organization)
      bundle = reply.resource

      if bundle.is_a?(FHIR::Bundle)
        entries = bundle.entry&.map(&:resource)
        entries&.map { |entry| Organization.new(entry) } || []
      else
        # `reply.resource` is the parsed resource, not the reply, so it has no
        # #response. Read the status off the reply instead, or a server that
        # answers with something other than a Bundle raises a NoMethodError
        # whose message tells the user nothing.
        status = reply&.response&.[](:code)
        Rails.logger.error("Error fetching organizations from FHIR server. Status code: #{status}")

        raise "Error fetching organizations from #{get_requester_server_base_url.presence || "the selected FHIR server"}. It did not return a FHIR Bundle of Organizations, so there is nothing to identify as. Status code: #{status}"
      end
    end
  end

  def bootstrap_class_for(flash_type)
    case flash_type.to_sym
    when :success
      "success"
    when :error
      "danger"
    when :alert
      "warning"
    when :notice
      "info"
    else
      flash_type.to_s
    end
  end

  def colorize_json(json)
    output = ""
    tokens = {
      "{" => "color: #ffc35f;",
      "}" => "color: #ffc35f;",
      "[" => "color: #ffc35f;",
      "]" => "color: #ffc35f;",
      "," => "color: #ffc35f;",
      ":" => "color: #0069ff;",
      "true" => "color: green;",
      "false" => "color: red;",
      "null" => "color: #baa2cd;",
    }

    json.scan(/(".*?"|{|}|[|]|,|:|true|false|null|-?\d+(\.\d+)?([eE][+-]?\d+)?|\s+)/) do |token|
      color = tokens[token.first] || ("color: #3ea4dc;" if token.first.start_with?('"')) || nil
      if color
        output += "<span style='#{color}'>#{ERB::Util.html_escape(token.first)}</span>"
      else
        output += ERB::Util.html_escape(token.first)
      end
    end

    output.html_safe
  end
end

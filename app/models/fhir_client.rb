# FhirClient Model
class FhirClient < FHIR::Client

  # This method runs every time a new FhirClient object is created (with a specific base URL)
  def initialize(base_url)
   super(base_url)
  end

  def self.setup_client(base_url)
    client = self.new(base_url)
    client.use_r4
    client
  end

end

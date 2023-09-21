class Organization
  include ModelHelper

  attr_reader :id, :name, :fhir_resource

  def initialize(fhir_organization)
    @id = fhir_organization.id
    @fhir_resource = fhir_organization
    remove_client_instances(@fhir_resource)
    @name = fhir_organization.name
  end
end

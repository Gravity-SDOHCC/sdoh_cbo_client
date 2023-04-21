class Organization
  attr_reader :id, :name, :fhir_resource

  def initialize(fhir_organization)
    @id = fhir_organization.id
    @fhir_resource = fhir_organization
    @code = fhir_organization.name
  end
end

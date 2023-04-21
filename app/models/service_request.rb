class ServiceRequest
  attr_reader :id, :status, :category, :description, :performer_name, :performer_reference, :priority, :fhir_resource

  def initialize(fhir_service_request)
    @id = fhir_service_request.id
    @fhir_resource = fhir_service_request
    @status = fhir_service_request.status
    @category = read_category(fhir_service_request.category)
    @description = read_codeable_concept(fhir_service_request.code)
    @performer_name = fhir_service_request.performer.first&.display
    @performer_reference = fhir_service_request.performer.first&.reference
    @priority = fhir_service_request.priority
  end

  private

  def read_category(category)
    category.map { |c| read_codeable_concept(c) }.join(", ")
  end

  def read_codeable_concept(codeable_concept)
    c = codeable_concept&.coding&.first
    c&.display ? c&.display : c&.code&.gsub("-", " ")&.titleize
  end
end

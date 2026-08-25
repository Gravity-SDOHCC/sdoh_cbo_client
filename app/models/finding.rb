# One resource already on the FHIR server that the referral target can return
# as an assessment finding in Task.output:AdditionalContent.
#
# rffa.html: "Task.output: When closing the loop, this element carries the
# results of the assessment ... This may include Observation Screening
# Responses, Questionnaire Response, Observation Assessments, Conditions,
# CarePlan, Goal, and Procedures."
#
# This is a picker row, not a clinical model: what the resource is, which
# resource on the server it is, and enough text for the user to tell two of them
# apart. The resources themselves are rendered by whoever receives them.
class Finding
  attr_reader :resource_type, :id, :label, :last_updated

  def self.build(fhir_resource)
    return if fhir_resource.blank? || fhir_resource.id.blank?

    new(fhir_resource)
  end

  def initialize(fhir_resource)
    @resource_type = fhir_resource.resourceType
    @id = fhir_resource.id
    @label = read_label(fhir_resource)
    @last_updated = read_last_updated(fhir_resource)
  end

  # The literal reference that goes into Task.output.valueReference. The picker
  # has to carry the resource type as well as the id: TaskIoEntry resolves an
  # output by the type in its reference, and reading an Observation as a
  # Procedure silently drops it.
  def reference
    "#{resource_type}/#{id}"
  end

  private

  # Each of these resources says what it is in a different element.
  def read_label(fhir_resource)
    text =
      case fhir_resource
      when FHIR::Goal then codeable_text(fhir_resource.description)
      when FHIR::CarePlan then fhir_resource.title.presence || codeable_text(fhir_resource.category&.first)
      when FHIR::QuestionnaireResponse then questionnaire_label(fhir_resource)
      else codeable_text(fhir_resource.code)
      end

    text.presence || "#{resource_type}/#{id}"
  end

  def codeable_text(codeable_concept)
    return if codeable_concept.blank?

    coding = Array(codeable_concept.coding).first
    codeable_concept.text.presence || coding&.display.presence || coding&.code
  end

  # QuestionnaireResponse.questionnaire is a canonical URL, so the last segment
  # is the closest thing to a name without reading the Questionnaire itself.
  def questionnaire_label(fhir_resource)
    fhir_resource.questionnaire.to_s.split("/").reject(&:blank?).last
  end

  def read_last_updated(fhir_resource)
    Date.parse(fhir_resource.meta&.lastUpdated.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end

class Task
  attr_reader :id, :status, :focus, :owner_reference, :owner_name, :requester_name,
              :requester_resource, :patient_name, :patient_resource, :outcome, :consent,
              :outcome_type, :authored_on, :status_reason, :fhir_resource

  def initialize(fhir_task)
    # byebug
    @id = fhir_task.id
    @fhir_resource = fhir_task
    @status = fhir_task.status
    sr_resource = get_fhir_resource(FHIR::ServiceRequest, fhir_task.focus) if fhir_task.focus.present?
    @focus = ServiceRequest.new(sr_resource) if sr_resource.present?
    @owner_reference = fhir_task.owner&.reference
    @owner_name = fhir_task.owner&.display
    @requester_name = fhir_task.requester&.display
    @requester_resource = fhir_task.requester&.reference&.include?("Organization") ? get_fhir_resource(FHIR::Organization, fhir_task.requester) : get_fhir_resource(FHIR::PractitionerRole, fhir_task.requester)
    @outcome = get_outcome(fhir_task.output&.first)
    @consent = get_consent(@focus&.fhir_resource)
    @authored_on = fhir_task.authoredOn&.to_date
    @status_reason = fhir_task.statusReason&.text
    @patient_name = fhir_task.for&.display
    @patient_resource = get_fhir_resource(FHIR::Patient, fhir_task.for)
  end

  private

  def get_outcome(outcome)
    return if outcome.nil?
    @outcome_type = outcome.type&.coding&.first&.code&.titleize
    fhir_outcome = get_fhir_resource(FHIR::Procedure, outcome.valueReference)
    Procedure.new(fhir_outcome) if fhir_outcome
  end

  def get_consent(focus)
    # byebug
    consent_ref = focus&.supportingInfo&.first
    fhir_consent = get_fhir_resource(FHIR::Consent, consent_ref)
    Consent.new(fhir_consent) if fhir_consent
  end

  def get_fhir_resource(fhir_class, ref)
    resource_id = get_id_from_reference(ref)
    fhir_resource = fhir_class.read(resource_id) if resource_id
    # sometimes for some reason read returns FHIR::Bundle
    fhir_resource = fhir_resource&.resource&.entry&.first&.resource if fhir_resource.is_a?(FHIR::Bundle)
    fhir_resource
  end

  def get_id_from_reference(ref_obj)
    ref_obj&.reference&.split("/")&.last
  end
end

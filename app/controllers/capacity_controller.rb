class CapacityController < ApplicationController
  before_action :require_fhir_client

  VALID_STATUSES = %w[capacity at-capacity has-waitlist assessment-required].freeze
  CAPACITY_EXTENSION_URL = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ExtensionHealthcareServiceCapacityStatus".freeze
  TEMPORARY_CODE_SYSTEM = "http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/SDOHCC-CodeSystemTemporaryCodes".freeze

  # SDOHCC-ExtensionHealthcareServiceCapacityStatus is a complex extension: the
  # code goes on a capacityStatus sub-extension (1..1) and a value on the outer
  # extension is prohibited (Extension.value[x] is 0..0).
  CAPACITY_STATUS_SUB_EXTENSION_URL = "capacityStatus".freeze

  # Map UI statuses to the codes defined in SDOHCC-CodeSystemTemporaryCodes.
  # That CodeSystem defines only no-capacity, capacity, waitlist and
  # additional-assessment-required -- "no-capacity-has-waitlist" was never one
  # of them, and referral clients bound to SDOHCC-ValueSetCapacityStatus will
  # not recognize it.
  STATUS_TO_CODE = {
    "capacity" => "capacity",
    "at-capacity" => "no-capacity",
    "has-waitlist" => "waitlist",
    "assessment-required" => "additional-assessment-required",
  }.freeze

  def update
    status = params[:capacity_status]
    if VALID_STATUSES.include?(status)
      save_capacity_status(status)
      update_fhir_healthcare_service(status)
      flash[:success] = "Capacity status set to #{status.titleize}"
    else
      flash[:error] = "Invalid capacity status"
    end
    redirect_to dashboard_path
  end

  private

  def update_fhir_healthcare_service(status)
    client = get_fhir_client
    org_id = get_my_org_id
    code = STATUS_TO_CODE.fetch(status)
    Rails.logger.info("Attempting to update FHIR HealthcareService: client=#{!!client}, org_id=#{org_id}")
    return unless client && org_id

    begin
      # Search for a HealthcareService provided by this organization
      Rails.logger.info("Searching for HealthcareService with organization=#{org_id}")
      bundle = client.search(FHIR::HealthcareService, search: { parameters: { organization: org_id } }).resource
      service = bundle&.entry&.map(&:resource)&.compact&.first
      is_new = service.nil?

      if is_new
        # No HealthcareService exists yet for this organization; create one so
        # referral clients can discover our capacity status.
        Rails.logger.info("No HealthcareService found for organization #{org_id}, creating one")
        service = FHIR::HealthcareService.new(
          active: true,
          providedBy: { reference: "Organization/#{org_id}" },
          name: "Services provided by Organization/#{org_id}"
        )
      end

      # Update or create the capacity extension
      service.extension ||= []
      service.extension.reject! { |e| e.url == CAPACITY_EXTENSION_URL }
      service.extension << FHIR::Extension.new(
        url: CAPACITY_EXTENSION_URL,
        extension: [
          FHIR::Extension.new(
            url: CAPACITY_STATUS_SUB_EXTENSION_URL,
            valueCodeableConcept: FHIR::CodeableConcept.new(
              coding: [
                FHIR::Coding.new(
                  system: TEMPORARY_CODE_SYSTEM,
                  code: code
                )
              ]
            )
          )
        ]
      )

      if is_new
        created = client.create(service)
        Rails.logger.info("Successfully created HealthcareService with capacity #{code}: #{created&.resource&.id || created.inspect}")
      else
        client.update(service, service.id)
        Rails.logger.info("Successfully updated HealthcareService #{service.id} capacity to #{code}")
      end
    rescue => e
      Rails.logger.error("Failed to update FHIR HealthcareService capacity: #{e.full_message}")
      Rails.logger.error(e.backtrace.join("\n"))
      # Don't fail the entire request if FHIR update fails
    end
  end
end

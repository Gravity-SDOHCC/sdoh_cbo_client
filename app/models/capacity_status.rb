# Reads and writes the CBO's capacity status.
#
# The organization's FHIR HealthcareService resource -- not the Rails session --
# is the source of truth. Keeping it in the session meant the dashboard toggle
# and the auto-rejection rules silently reset to "Capacity Available" on every
# new session, app restart or second user of the same CBO, even though the
# HealthcareService still said otherwise (CFRID-944).
class CapacityStatus
  EXTENSION_URL = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ExtensionHealthcareServiceCapacityStatus".freeze
  CODE_SYSTEM = "http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/SDOHCC-CodeSystemTemporaryCodes".freeze

  # SDOHCC-ExtensionHealthcareServiceCapacityStatus is a complex extension: the
  # code goes on a capacityStatus sub-extension (1..1) and a value on the outer
  # extension is prohibited (Extension.value[x] is 0..0).
  SUB_EXTENSION_URL = "capacityStatus".freeze

  # Single source of truth for the UI toggle and the FHIR codes. The codes are
  # the ones defined in SDOHCC-CodeSystemTemporaryCodes -- referral clients bound
  # to SDOHCC-ValueSetCapacityStatus will not recognize anything else.
  STATUSES = {
    "capacity" => { label: "Capacity Available", style: "success", code: "capacity" },
    "at-capacity" => { label: "At Capacity", style: "danger", code: "no-capacity" },
    "has-waitlist" => { label: "Has Waitlist", style: "warning", code: "waitlist" },
    "assessment-required" => { label: "Additional Assessment Required", style: "info", code: "additional-assessment-required" },
  }.freeze

  DEFAULT_STATUS = "capacity".freeze
  AT_CAPACITY = "at-capacity".freeze

  STATUS_TO_CODE = STATUSES.each_with_object({}) { |(status, meta), acc| acc[status] = meta[:code] }.freeze

  # Inverse map, plus tolerance for "no-capacity-has-waitlist", which an earlier
  # build of this feature wrote before the codes were corrected.
  CODE_TO_STATUS = STATUS_TO_CODE.invert.merge("no-capacity-has-waitlist" => "has-waitlist").freeze

  # Short TTL so the dashboard poll (every ~8s) does not hit the FHIR server on
  # every request, while a change made elsewhere still surfaces quickly. Our own
  # writes prime the cache directly, so they are visible immediately.
  CACHE_TTL = 30.seconds

  def self.valid?(status)
    STATUSES.key?(status)
  end

  def self.label_for(status)
    STATUSES.dig(status, :label) || status.to_s
  end

  def self.cache_key(org_id)
    "capacity_status_#{org_id}"
  end

  def initialize(client, org_id)
    @client = client
    @org_id = org_id
  end

  # The persisted status, e.g. "at-capacity". Falls back to DEFAULT_STATUS when
  # the org has no HealthcareService, no capacity extension, or the server is
  # unreachable.
  def status
    current["status"]
  end

  # When the status was last written, taken from HealthcareService.meta.lastUpdated
  # so that it survives sessions. Used to keep auto-rejection non-retroactive.
  def updated_at
    current["updated_at"]
  end

  # Persists the status on the organization's HealthcareService, creating the
  # resource when the org does not have one yet. Returns true on success.
  def save(status)
    return false unless usable?
    return false unless self.class.valid?(status)

    code = STATUS_TO_CODE.fetch(status)
    service = find_service
    is_new = service.nil?

    if is_new
      # No HealthcareService exists yet for this organization; create one so
      # referral clients can discover our capacity status.
      Rails.logger.info("No HealthcareService found for organization #{@org_id}, creating one")
      service = FHIR::HealthcareService.new(
        active: true,
        providedBy: { reference: "Organization/#{@org_id}" },
        name: "Services provided by Organization/#{@org_id}",
      )
    end

    apply_extension(service, code)

    saved = is_new ? @client.create(service) : @client.update(service, service.id)
    Rails.logger.info("Successfully #{is_new ? "created" : "updated"} HealthcareService #{saved&.resource&.id || service.id} capacity to #{code}")

    write_cache(status, timestamp_from(saved) || Time.now.utc)
    true
  rescue => e
    Rails.logger.error("Failed to update FHIR HealthcareService capacity: #{e.full_message}")
    expire_cache
    false
  end

  def expire_cache
    Rails.cache.delete(self.class.cache_key(@org_id)) if @org_id.present?
  end

  private

  def usable?
    @client.present? && @org_id.present?
  end

  def current
    return default_reading unless usable?

    Rails.cache.fetch(self.class.cache_key(@org_id), expires_in: CACHE_TTL) do
      read_from_fhir
    end
  rescue => e
    Rails.logger.error("Failed to read capacity status from FHIR: #{e.full_message}")
    default_reading
  end

  def read_from_fhir
    Rails.logger.info("Reading capacity status from HealthcareService for organization #{@org_id}")
    service = find_service
    return default_reading if service.nil?

    code = extract_code(service)
    status = CODE_TO_STATUS[code]
    if code.present? && status.nil?
      Rails.logger.warn("Unrecognized capacity status code '#{code}' on HealthcareService/#{service.id}; falling back to #{DEFAULT_STATUS}")
    end

    {
      "status" => status || DEFAULT_STATUS,
      "updated_at" => parse_time(service.meta && service.meta.lastUpdated),
    }
  end

  def find_service
    bundle = @client.search(FHIR::HealthcareService, search: { parameters: { organization: @org_id } }).resource
    bundle&.entry&.map(&:resource)&.compact&.first
  end

  def extract_code(service)
    outer = Array(service.extension).find { |e| e.url == EXTENSION_URL }
    return nil if outer.nil?

    sub = Array(outer.extension).find { |e| e.url == SUB_EXTENSION_URL }
    # Older builds wrote the CodeableConcept on the outer extension; read either.
    coding = Array(sub&.valueCodeableConcept&.coding)
    coding = Array(outer.valueCodeableConcept&.coding) if coding.empty?

    (coding.find { |c| c.system == CODE_SYSTEM } || coding.first)&.code
  end

  def apply_extension(service, code)
    service.extension ||= []
    service.extension.reject! { |e| e.url == EXTENSION_URL }
    service.extension << FHIR::Extension.new(
      url: EXTENSION_URL,
      extension: [
        FHIR::Extension.new(
          url: SUB_EXTENSION_URL,
          valueCodeableConcept: FHIR::CodeableConcept.new(
            coding: [FHIR::Coding.new(system: CODE_SYSTEM, code: code)],
          ),
        ),
      ],
    )
  end

  def write_cache(status, updated_at)
    return if @org_id.blank?

    Rails.cache.write(
      self.class.cache_key(@org_id),
      { "status" => status, "updated_at" => updated_at },
      expires_in: CACHE_TTL,
    )
  end

  def timestamp_from(reply)
    resource = reply&.resource
    return nil unless resource.is_a?(FHIR::HealthcareService)

    parse_time(resource.meta && resource.meta.lastUpdated)
  end

  def parse_time(value)
    return nil if value.blank?

    Time.parse(value.to_s).utc
  rescue ArgumentError
    nil
  end

  def default_reading
    { "status" => DEFAULT_STATUS, "updated_at" => nil }
  end
end

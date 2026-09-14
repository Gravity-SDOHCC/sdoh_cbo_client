# The candidates the completion modal offers as assessment findings, for one
# patient, grouped so a reader can tell an instrument from a derived result from
# a diagnosis.
#
# What may be offered is decided by the profile, not the resource type.
# SDOHCC-TaskForReferralManagement closes Task.output:AdditionalContent to
# Reference(SDOHCC Observation Program Enrollment Status | SDOHCC Observation
# Assessment | SDOHCC Observation Screening Response | SDOHCC Goal | SDOHCC
# Condition | QuestionnaireResponse | CarePlan), and "Observation" spans three
# of those plus six personal-characteristic profiles the slice does not accept
# at all. A search by resource type offered a patient's race, ethnicity, gender
# identity, pronouns, sexual orientation and recorded sex as assessment
# findings; the searches below ask for the two Observation profiles that belong
# instead, so the exclusion happens on the server.
#
# Program enrollment status is left out on purpose even though the slice accepts
# it: the modal already has its own control for enrollment, which writes a fresh
# Observation rather than attaching an old one.
class AssessmentFindings
  # One search per resource type, patient-scoped, most recent first. _profile
  # takes a comma-separated OR list, so filtering by profile costs no extra
  # round trips.
  #
  # CarePlan is in the slice and has no profile constraint, so it is searched
  # unfiltered — on the connectathon server it answers HAPI-0302 "Unknown
  # resource type", which is handled as "nothing to offer" rather than an error.
  SEARCHES = [
    {
      type: "QuestionnaireResponse",
      parameters: { _include: "QuestionnaireResponse:questionnaire" },
    },
    {
      type: "Observation",
      parameters: {
        _profile: [FhirProfiles::OBSERVATION_ASSESSMENT, FhirProfiles::OBSERVATION_SCREENING_RESPONSE].join(","),
      },
    },
    { type: "Condition", parameters: { _profile: FhirProfiles::CONDITION } },
    { type: "Goal", parameters: { _profile: FhirProfiles::GOAL } },
    { type: "CarePlan", parameters: {} },
  ].freeze

  # The most recent of each type. A referral target returning findings is
  # picking something it recorded recently, not trawling a lifetime of records;
  # the count is reported in the modal so a truncated list does not read as a
  # complete one.
  PAGE_SIZE = 25

  # Display order of the groups: what was administered, what was concluded from
  # it, what is on the problem list, what is being worked towards.
  GROUP_ORDER = %i[instrument answer assessment condition goal other].freeze

  attr_reader :groups, :truncated_types

  def self.load(fhir_client:, patient_id:, category_codes: [])
    new(fhir_client: fhir_client, patient_id: patient_id, category_codes: category_codes).tap(&:load)
  end

  def initialize(fhir_client:, patient_id:, category_codes: [])
    @fhir_client = fhir_client
    @patient_id = patient_id
    @category_codes = Array(category_codes).compact
    @groups = []
    @truncated_types = []
  end

  def load
    findings = SEARCHES.flat_map { |search| run(search) }
    findings = deduplicate(findings)
    answers_by_parent = findings.select { |finding| finding.kind == :answer }
                                .group_by(&:parent_reference)
    @groups = build_groups(findings, answers_by_parent)
    self
  end

  def any?
    groups.any? { |group| group[:rows].present? }
  end

  def total
    groups.sum { |group| group[:rows].sum { |row| 1 + row[:answers].size } }
  end

  private

  attr_reader :fhir_client, :patient_id, :category_codes

  def run(search)
    fhir_class = FHIR.const_get(search[:type], false)
    parameters = { patient: patient_id, _sort: "-_lastUpdated", _count: PAGE_SIZE }.merge(search[:parameters])
    response = fhir_client.search(fhir_class, search: { parameters: parameters })
    code = response.response[:code].to_i
    if code != 200
      Rails.logger.info("No #{search[:type]} findings for patient #{patient_id}: server answered #{code}")
      return []
    end

    bundle = response.resource
    entries = Array(bundle&.entry).map(&:resource).compact
    @truncated_types << search[:type] if bundle&.total.to_i > PAGE_SIZE
    titles = questionnaire_titles(entries)
    entries.filter_map do |fhir_resource|
      next unless offerable?(fhir_resource, search[:type])

      Finding.build(fhir_resource, questionnaire_titles: titles)
    end
  rescue StandardError => e
    Rails.logger.warn("Unable to search #{search[:type]} for patient #{patient_id}: #{e.message}")
    []
  end

  # _include brings the Questionnaires back in the same bundle, so a response
  # can be labelled with the instrument's own title without another read.
  def questionnaire_titles(entries)
    entries.grep(FHIR::Questionnaire).each_with_object({}) do |questionnaire, titles|
      name = questionnaire.title.presence || questionnaire.name.presence
      next if name.blank?

      titles[questionnaire.url.to_s] = name if questionnaire.url.present?
      titles["Questionnaire/#{questionnaire.id}"] = name if questionnaire.id.present?
    end
  end

  # Belt and braces on top of the _profile searches: a server that ignores
  # _profile, or data that does not declare its profile, must not put a
  # personal-characteristic Observation in front of someone. Observation.category
  # personal-characteristic is used by nothing else in this IG.
  def offerable?(fhir_resource, requested_type)
    return false unless fhir_resource.resourceType == requested_type
    return true unless fhir_resource.is_a?(FHIR::Observation)

    !personal_characteristic?(fhir_resource)
  end

  def personal_characteristic?(fhir_resource)
    profiles = Array(fhir_resource.meta&.profile).map(&:to_s)
    return true if (profiles & FhirProfiles::OBSERVATION_PERSONAL_CHARACTERISTIC_PROFILES).any?

    Array(fhir_resource.category).flat_map { |category| Array(category&.coding) }
      .any? { |coding| coding&.code == FhirProfiles::PERSONAL_CHARACTERISTIC_CATEGORY_CODE }
  end

  # Rows a reader could not tell apart collapse into one, which keeps its count
  # so nothing is dropped silently. The most recently updated instance wins,
  # because the searches are sorted newest first.
  def deduplicate(findings)
    findings.each_with_object({}) do |finding, kept|
      key = finding.duplicate_key
      kept.key?(key) ? kept[key].merge_duplicate : kept[key] = finding
    end.values
  end

  # Individual answers hang under the instrument they came from, through
  # Observation.derivedFrom. Sixteen screening-response Observations listed flat,
  # next to the QuestionnaireResponse they were derived from, is how someone ends
  # up ticking an instrument and its own answers by hand.
  def build_groups(findings, answers_by_parent)
    claimed = answers_by_parent.slice(*findings.select { |f| f.kind == :instrument }.map(&:reference))
    orphaned = answers_by_parent.except(*claimed.keys).values.flatten

    GROUP_ORDER.filter_map do |kind|
      rows =
        case kind
        when :instrument
          sort(findings.select { |f| f.kind == :instrument }).map do |finding|
            { finding: finding, answers: sort(claimed[finding.reference] || []) }
          end
        when :answer
          # Screening responses whose questionnaire response is not among the
          # candidates - it may be on another patient's chart, or the answer may
          # have been recorded without one. They are still answers, so they say
          # so rather than being filed under "other".
          sort(orphaned).map { |f| { finding: f, answers: [] } }
        else
          sort(findings.select { |f| f.kind == kind }).map { |f| { finding: f, answers: [] } }
        end
      next if rows.blank?

      { kind: kind, label: group_label(kind), rows: rows }
    end
  end

  def group_label(kind)
    return "Individual answers not linked to a completed instrument" if kind == :answer

    Finding::KINDS.dig(kind, :label)
  end

  # The referral's own domain first, then everything else, newest first within
  # each. Nothing is removed for being in another domain: the SDOH category
  # value set is a flat list of sibling codes — housing-instability,
  # homelessness and inadequate-housing are three separate categories with three
  # separate code value sets, not a hierarchy — so an equality filter would hide
  # a homelessness finding from a housing-instability referral, and any mapping
  # that avoided that would be invented here rather than read from the IG. A
  # comprehensive needs assessment also legitimately turns up a domain nobody
  # referred for. Each row shows its own domains, so the reader can judge.
  def sort(findings)
    findings.sort_by.with_index do |finding, index|
      [finding.in_domains?(category_codes) ? 0 : 1, index]
    end
  end
end

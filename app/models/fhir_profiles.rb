# Canonical URLs for the FHIR artifacts this client reads and writes.
#
# Every profile, extension and temporary-code-system URL used anywhere in the
# application is declared here so that a spec change is a one-line edit and so
# that no two call sites can disagree about a canonical URL. Nothing outside
# this module should carry one as a string literal.
#
# SDOH artifacts are from HL7 FHIR Implementation Guide "Social Determinants of
# Health Clinical Care" (hl7.fhir.us.sdoh-clinicalcare), STU 3 continuous build.
module FhirProfiles
  # --- SDOH Clinical Care profiles ---

  # SDOHCC Task For Referral Management
  TASK_FOR_REFERRAL_MANAGEMENT = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-TaskForReferralManagement".freeze
  # SDOHCC Procedure
  PROCEDURE = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-Procedure".freeze
  # SDOHCC Observation Program Enrollment Status
  OBSERVATION_PROGRAM_ENROLLMENT_STATUS = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationProgramEnrollmentStatus".freeze

  # The profiles Task.output:AdditionalContent.valueReference is closed to:
  # Reference(SDOHCC Observation Program Enrollment Status | SDOHCC Observation
  # Assessment | SDOHCC Observation Screening Response | SDOHCC Goal | SDOHCC
  # Condition | QuestionnaireResponse | CarePlan).
  OBSERVATION_ASSESSMENT = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationAssessment".freeze
  OBSERVATION_SCREENING_RESPONSE = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationScreeningResponse".freeze
  CONDITION = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-Condition".freeze
  GOAL = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-Goal".freeze

  # The personal-characteristic Observation profiles, which that slice does NOT
  # accept. They are a patient's race, ethnicity, gender identity, pronouns,
  # sexual orientation and recorded sex — never a finding of an assessment, and
  # returning one to a referral source would both be non-conformant and disclose
  # something nobody asked about.
  OBSERVATION_PERSONAL_CHARACTERISTIC_PROFILES = [
    "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationPersonalCharacteristic",
    "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationRaceOMB",
    "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationEthnicityOMB",
    "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationGenderIdentity",
    "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationPersonalPronouns",
    "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationSexualOrientation",
    "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationRecordedSexGender",
  ].freeze

  # --- SDOH Clinical Care extensions ---

  # SDOHCC Extension Healthcare Service Capacity Status
  CAPACITY_STATUS_EXTENSION = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ExtensionHealthcareServiceCapacityStatus".freeze

  # --- SDOH Clinical Care code system ---

  # SDOHCC CodeSystem Temporary Codes
  TEMPORARY_CODE_SYSTEM = "http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/SDOHCC-CodeSystemTemporaryCodes".freeze

  # The two SDOHCC-CodeSystemTemporaryCodes concepts that discriminate the
  # Task.input and Task.output slices in SDOHCC-TaskForReferralManagement.
  ADDITIONAL_CONTENT_CODE = "additional-content".freeze
  ADDITIONAL_CONTENT_DISPLAY = "Additional Content".freeze
  RESULTING_ACTIVITY_CODE = "resulting-activity".freeze
  RESULTING_ACTIVITY_DISPLAY = "Resulting Activity".freeze

  # SDOHCC-CodeSystemTemporaryCodes concept for Observation.category on
  # SDOHCC-ObservationProgramEnrollmentStatus, which fixes category[enrollment]
  # to program-enrollment. The category is what tells an enrollment status
  # Observation apart from the assessments, goals and conditions that share the
  # Task.output:AdditionalContent slice.
  PROGRAM_ENROLLMENT_CATEGORY_CODE = "program-enrollment".freeze
  PROGRAM_ENROLLMENT_CATEGORY_DISPLAY = "Program Enrollment Status".freeze

  # --- Terminology from outside this IG ---

  # US Core category code system. category[us-core] on the enrollment profile is
  # 1..* and has to include sdoh (constraint SDOH-Obs-4).
  US_CORE_CATEGORY_SYSTEM = "http://hl7.org/fhir/us/core/CodeSystem/us-core-category".freeze
  SDOH_CATEGORY_CODE = "sdoh".freeze
  SDOH_CATEGORY_DISPLAY = "SDOH".freeze

  # Observation.category on every personal-characteristic profile. Nothing else
  # in this IG uses it, so it identifies those Observations without depending on
  # meta.profile being present.
  PERSONAL_CHARACTERISTIC_CATEGORY_CODE = "personal-characteristic".freeze

  # SNOMED CT: the code system the social care program concepts bound to
  # Observation.code are drawn from.
  SNOMED_CT_SYSTEM = "http://snomed.info/sct".freeze
end

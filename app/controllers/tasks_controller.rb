class TasksController < ApplicationController
  before_action :require_fhir_client

  # Observation.value[x] on SDOHCC-ObservationProgramEnrollmentStatus, bound
  # (preferred) to SDOHCC-ValueSetEnrollmentStatus. All three concepts come from
  # SDOHCC-CodeSystemTemporaryCodes.
  #
  # not-enrolled-on-waitlist says THIS PERSON is waiting for a place in the
  # program. It is not the capacity code waitlist, which says THIS PROGRAM has a
  # waitlist: different value set, different meaning, same code system.
  ENROLLMENT_STATUSES = {
    "enrolled" => "Enrolled",
    "not-enrolled" => "Not Enrolled",
    "not-enrolled-on-waitlist" => "Not Enrolled - On Waitlist",
  }.freeze

  # Observation.code identifies the social care program. It is bound
  # (preferred) to the VSAC value set
  # http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113762.1.4.1247.312, whose
  # expansion needs UMLS credentials and is not reachable from this client:
  # there is no terminology service here either. This is the one concept the
  # IG's own enrollment status example uses, and the binding is preferred, so
  # adding a program the connectathon needs is a one-line change.
  ENROLLMENT_PROGRAMS = {
    "481021000124104" => "Adult protective service (qualifier value)",
  }.freeze

  # What Task.output:AdditionalContent is allowed to reference.
  #
  # SDOHCC-TaskForReferralManagement closes the slice to
  # Reference(SDOHCC Observation Program Enrollment Status |
  # SDOHCC Observation Assessment | SDOHCC Observation Screening Response |
  # SDOHCC Goal | SDOHCC Condition | QuestionnaireResponse | CarePlan), which is
  # these five resource types.
  #
  # Procedure is deliberately absent. rffa.html lists Procedures among the
  # results of an assessment, but the profile keeps them in
  # Task.output:PerformedActivityReference, whose target is closed to
  # Reference(SDOHCC Procedure) -- so the Procedure this client already creates
  # on completion stays where it is and nothing else goes there.
  ASSESSMENT_FINDING_TYPES = %w[QuestionnaireResponse Observation Condition Goal CarePlan].freeze

  # SDOHCC-ValueSetSDOHCategory, the required binding on category[SDOHCC].
  # The domain code is copied from the ServiceRequest being fulfilled rather
  # than asked for again, and it is checked against the value set first: a
  # ServiceRequest category carrying some other temporary code (a capacity or
  # enrollment code, say) would otherwise fail the binding on the way out.
  SDOH_DOMAIN_CATEGORY_CODES = %w[
    sdoh-category-unspecified food-insecurity housing-instability homelessness
    inadequate-housing transportation-insecurity financial-insecurity
    material-hardship educational-attainment employment-status veteran-status
    stress social-connection intimate-partner-violence elder-abuse
    personal-health-literacy health-insurance-coverage-status
    medical-cost-burden digital-literacy digital-access utility-insecurity
    incarceration-status language-access protective-factor
  ].freeze

  def update_task
    cached_tasks = Rails.cache.read(tasks_key)
    client = get_fhir_client
    begin
      task = cached_tasks.present? ? cached_tasks.find { |t| t.id == params[:id] }&.fhir_resource : client.read(FHIR::Task, params[:id]).resource
      sr_id = task.focus&.reference&.split("/")&.last
      service_request = client.read(FHIR::ServiceRequest, sr_id).resource
      if task.present?
        status = params[:status] == "status" ? params[:task_status] : params[:status]
        task.status = status
        if status == "accepted" || status == "in-progress"
          client.update(task, task.id)
        elsif status == "rejected" || status == "cancelled"
          task.statusReason = FHIR::CodeableConcept.new(text: params[:status_reason])
          client.update(task, task.id)
        elsif status == "completed"
          # Both resources are created before the Task is updated. A referral
          # completed with no outcome on it cannot be corrected from this UI, so
          # a failed create has to leave the Task where it was and say why.
          observation = create_enrollment_observation(task, service_request)
          procedure = create_procedure(task, service_request)
          append_output(task, type_code: FhirProfiles::RESULTING_ACTIVITY_CODE, reference: "Procedure/#{procedure.id}")
          if observation.present?
            append_output(task, type_code: FhirProfiles::ADDITIONAL_CONTENT_CODE, reference: "Observation/#{observation.id}")
          end
          attach_assessment_findings(task)
          client.update(task, task.id)
        end

        flash[:success] = "Task has been marked as #{status}."
      else
        Rails.logger.error("Unable to update task: task not found")

        flash[:error] = "Unable to update task: task not found"
      end
    rescue => e
      Rails.logger.error(e.full_message)

      flash[:error] = "Unable to update task: #{e.message}"
    end
    Rails.cache.delete(tasks_key)
    redirect_to dashboard_path
  end

  def poll_tasks
    if !fhir_client_connected?
      Rails.logger.error("Session expired")

      render json: { error: "Session expired" }, status: 440 and return
    end
    cached_tasks = Rails.cache.read(tasks_key) || []
    Rails.cache.delete(tasks_key)
    success, result = fetch_tasks

    if success
      @active_tasks = result["active"] || []
      @completed_tasks = result["completed"] || []
      @cancelled_tasks = result["cancelled"] || []
      # Read from the HealthcareService, not the session, so auto-rejection keeps
      # working across new sessions, restarts and other users of the same CBO.
      if get_capacity_status == CapacityStatus::AT_CAPACITY
        newly_rejected, @active_tasks = auto_reject_at_capacity(@active_tasks)
        @cancelled_tasks = newly_rejected + @cancelled_tasks
      end

      new_tasks_list = Rails.cache.read(tasks_key) || []
      # check if any active tasks have changed status
      updated_tasks = []
      new_tasks_list.each do |task|
        saved_task = cached_tasks.find { |t| t&.id == task&.id }
        if saved_task && saved_task.status != task.status
          updated_tasks << task
        end
      end
      @task_notifications = updated_tasks&.map do |t|
        msg =
          t&.status == "requested" ?
            "new referral source task requested" :
            "task #{t&.focus&.description} was updated to #{t&.status}"
        [msg, t&.id]
      end || []
      ActionCable.server.broadcast "notifications", { task_notifications: @task_notifications.to_json }
      render json: {
               active_tasks: render_to_string(partial: "dashboard/tasks_table", locals: { referrals: @active_tasks, type: "active" }),
               completed_tasks: render_to_string(partial: "dashboard/tasks_table", locals: { referrals: @completed_tasks, type: "completed" }),
               cancelled_tasks: render_to_string(partial: "dashboard/tasks_table", locals: { referrals: @cancelled_tasks, type: "cancelled" }),
             }
    else
      Rails.logger.error("Unable to fetch tasks: #{result}")

      render json: {
        error: "Unable to fetch tasks",
      }
    end
  end

  private

  # SDOHCC Observation Program Enrollment Status: the CBO's record of what
  # enrolling this patient in a social care program came to.
  #
  # enrollment.html, referral-triggered workflow: "If the CBO determines the
  # person needs to be enrolled in a program, the CBO creates a new Enrollment
  # Status Observation ... To close the loop on the referral, the CBO updates
  # the Task, pointing to the Enrollment Status Observation in Task.output."
  # The CBO is the Referral Target, so this client is the one that writes it.
  #
  # Enrollment is not part of every referral, so no status selected means no
  # Observation and a referral that completes with only its Procedure, exactly
  # as before.
  def create_enrollment_observation(task, service_request)
    status_code = params[:enrollment_status].presence
    return if status_code.blank?

    unless ENROLLMENT_STATUSES.key?(status_code)
      raise ArgumentError, "#{status_code} is not an SDOHCC-ValueSetEnrollmentStatus code"
    end

    program_code = params[:enrollment_program].presence
    raise ArgumentError, "Select the program the enrollment status is for" if program_code.blank?
    unless ENROLLMENT_PROGRAMS.key?(program_code)
      raise ArgumentError, "#{program_code} is not one of the programs this client can record"
    end

    observation = FHIR::Observation.new
    observation.meta = FHIR::Meta.new(profile: [FhirProfiles::OBSERVATION_PROGRAM_ENROLLMENT_STATUS])
    observation.status = "final"
    observation.category = enrollment_categories(service_request)
    observation.code = FHIR::CodeableConcept.new(
      coding: [
        FHIR::Coding.new(
          system: FhirProfiles::SNOMED_CT_SYSTEM,
          code: program_code,
          display: ENROLLMENT_PROGRAMS[program_code],
        ),
      ],
    )
    observation.subject = task.for.presence || service_request.subject
    observation.performer = [FHIR::Reference.new(reference: "Organization/#{get_my_org_id}")]
    observation.effectiveDateTime = Time.now.utc.iso8601
    observation.valueCodeableConcept = FHIR::CodeableConcept.new(
      coding: [
        FHIR::Coding.new(
          system: FhirProfiles::TEMPORARY_CODE_SYSTEM,
          code: status_code,
          display: ENROLLMENT_STATUSES[status_code],
        ),
      ],
    )
    note = params[:enrollment_note].presence
    observation.note = [FHIR::Annotation.new(text: note)] if note

    created = get_fhir_client.create(observation).resource
    if created.blank? || created.id.blank?
      raise "The FHIR server did not return a created Enrollment Status Observation"
    end

    created
  end

  # category[us-core] sdoh and category[enrollment] program-enrollment are both
  # fixed by the profile; the SDOH domain code comes from the referral.
  def enrollment_categories(service_request)
    categories = [
      FHIR::CodeableConcept.new(
        coding: [
          FHIR::Coding.new(
            system: FhirProfiles::US_CORE_CATEGORY_SYSTEM,
            code: FhirProfiles::SDOH_CATEGORY_CODE,
            display: FhirProfiles::SDOH_CATEGORY_DISPLAY,
          ),
        ],
      ),
      FHIR::CodeableConcept.new(
        coding: [
          FHIR::Coding.new(
            system: FhirProfiles::TEMPORARY_CODE_SYSTEM,
            code: FhirProfiles::PROGRAM_ENROLLMENT_CATEGORY_CODE,
            display: FhirProfiles::PROGRAM_ENROLLMENT_CATEGORY_DISPLAY,
          ),
        ],
      ),
    ]

    sdoh_domain_codings(service_request).each do |coding|
      categories << FHIR::CodeableConcept.new(coding: [coding])
    end

    categories
  end

  def sdoh_domain_codings(service_request)
    Array(service_request&.category).flat_map { |category| Array(category.coding) }
      .select { |coding| coding.system == FhirProfiles::TEMPORARY_CODE_SYSTEM }
      .select { |coding| SDOH_DOMAIN_CATEGORY_CODES.include?(coding.code) }
      .uniq(&:code)
      .map { |coding| FHIR::Coding.new(system: coding.system, code: coding.code, display: coding.display) }
  end

  def create_procedure(task, service_request)
    procedure = FHIR::Procedure.new
    procedure.meta = FHIR::Meta.new(profile: [FhirProfiles::PROCEDURE])
    procedure.basedOn = [FHIR::Reference.new(reference: "ServiceRequest/#{service_request.id}")]
    procedure.status = "completed"
    procedure.category = service_request.category&.first
    procedure.code = service_request.code
    procedure.subject = service_request.subject
    procedure.reasonReference = referenceable(service_request.reasonReference)
    procedure.performedDateTime = Time.now.utc.strftime("%Y-%m-%d")

    get_fhir_client.create(procedure).resource
  end

  # Drops references that name no resource.
  #
  # "Condition/" is not a reference, and copying one onto the Procedure makes
  # the FHIR server reject the whole resource: HAPI-0508 "Invalid resource
  # reference found at path[Procedure.reasonReference] - Does not contain
  # resource ID". The referral source client writes exactly that whenever a
  # referral is created with no problem selected, and the coordination platform
  # copies the ServiceRequest through unchanged, so a referral carrying one
  # could not be completed at all: the create failed, and fhir_client reported
  # it as "undefined method `each_element' for Hash" rather than as the 400 it
  # was.
  def referenceable(references)
    Array(references).select { |reference| TaskIoEntry.parse_reference(reference.reference).last.present? }.presence
  end

  # Adds one entry to Task.output.
  #
  # SDOHCC-TaskForReferralManagement slices Task.output and every slice is 0..*:
  # a completed referral can carry a Procedure reference alongside a program
  # enrollment status, assessment responses and anything a later step adds.
  # Assigning the array replaced whatever was already there, so this appends.
  #
  # The slices are closed over what they may point at, so the reference is
  # checked before it goes anywhere near the server: PerformedActivityReference
  # only accepts Reference(SDOHCC-Procedure), and AdditionalContent is for
  # everything except the performed activity itself.
  def append_output(task, type_code:, reference:)
    resource_type, = TaskIoEntry.parse_reference(reference)

    case type_code
    when FhirProfiles::RESULTING_ACTIVITY_CODE
      unless resource_type == "Procedure"
        raise ArgumentError, "#{reference} is not a Procedure: Task.output:PerformedActivityReference only accepts Reference(SDOHCC-Procedure)"
      end
      display = FhirProfiles::RESULTING_ACTIVITY_DISPLAY
    when FhirProfiles::ADDITIONAL_CONTENT_CODE
      if resource_type == "Procedure"
        raise ArgumentError, "#{reference} is a Procedure: a performed activity belongs in Task.output:PerformedActivityReference, not AdditionalContent"
      end
      display = FhirProfiles::ADDITIONAL_CONTENT_DISPLAY
    else
      raise ArgumentError, "Unsupported Task.output type code #{type_code.inspect}"
    end

    output = FHIR::Task::Output.new(
      type: {
        coding: [
          {
            system: FhirProfiles::TEMPORARY_CODE_SYSTEM,
            code: type_code,
            display: display,
          },
        ],
      },
      valueReference: {
        reference: reference,
      },
    )

    task.output = Array(task.output) + [output]
    task
  end

  # Returns the assessment findings selected in the completion modal through
  # Task.output:AdditionalContent.
  #
  # rffa.html: the referral for further assessment reuses the closed-loop
  # pattern unchanged, and what differs is that "when the loop is closed, the
  # information returned in Task.output consists of the findings from that
  # assessment". This client is the Referral Target, so it is the one that
  # returns them.
  #
  # This attaches findings that already exist on the server. Authoring
  # assessment content here -- an Observation Assessment builder, a CarePlan --
  # is a follow-on.
  #
  # The status form is a GET, so every selection is checked before it is
  # trusted: the resource type has to be one the slice accepts, the resource has
  # to exist, and it has to belong to this referral's patient. Without the last
  # check a hand-edited query string could attach one patient's records to
  # another patient's referral.
  def attach_assessment_findings(task)
    references = Array(params[:findings]).map(&:to_s).reject(&:blank?).uniq
    return if references.empty?

    patient_id = task.for&.reference_id
    raise ArgumentError, "This referral names no patient, so findings cannot be checked against it" if patient_id.blank?

    references.each do |reference|
      resource_type, resource_id = TaskIoEntry.parse_reference(reference)
      unless ASSESSMENT_FINDING_TYPES.include?(resource_type) && resource_id.present?
        raise ArgumentError, "#{reference} is not a kind of assessment finding Task.output:AdditionalContent accepts"
      end

      finding = read_finding(resource_type, resource_id)
      raise ArgumentError, "#{reference} was not found on the FHIR server" if finding.blank?

      if personal_characteristic?(finding)
        raise ArgumentError, "#{reference} is a personal characteristic, which Task.output:AdditionalContent does not accept"
      end

      subject_id = finding.subject&.reference_id
      unless subject_id == patient_id
        raise ArgumentError, "#{reference} belongs to #{subject_id.presence || "no patient"}, not to this referral's patient"
      end

      append_output(task, type_code: FhirProfiles::ADDITIONAL_CONTENT_CODE, reference: "#{resource_type}/#{resource_id}")
    end

    Rails.cache.delete(findings_key(patient_id))
  end

  # The slice accepts three Observation profiles and none of the six
  # personal-characteristic ones, so "it is an Observation" is not enough to let
  # one through. The picker no longer offers them, and this is the half that
  # matters: the status form is a GET, so what the picker shows and what Submit
  # accepts have to be narrowed together.
  def personal_characteristic?(fhir_resource)
    return false unless fhir_resource.is_a?(FHIR::Observation)

    profiles = Array(fhir_resource.meta&.profile).map(&:to_s)
    return true if (profiles & FhirProfiles::OBSERVATION_PERSONAL_CHARACTERISTIC_PROFILES).any?

    Array(fhir_resource.category).flat_map { |category| Array(category&.coding) }
      .any? { |coding| coding&.code == FhirProfiles::PERSONAL_CHARACTERISTIC_CATEGORY_CODE }
  end

  def read_finding(resource_type, resource_id)
    fhir_class = FHIR.const_get(resource_type, false)
    resource = get_fhir_client.read(fhir_class, resource_id).resource
    # sometimes for some reason read returns FHIR::Bundle
    resource = resource&.entry&.first&.resource if resource.is_a?(FHIR::Bundle)
    resource.is_a?(fhir_class) ? resource : nil
  rescue StandardError => e
    Rails.logger.warn("Unable to read #{resource_type}/#{resource_id}: #{e.message}")
    nil
  end

  def auto_reject_at_capacity(tasks)
    client = get_fhir_client
    at_capacity_since = get_capacity_status_set_at
    rejected, remaining = [], []
    tasks.each do |task|
      if task.status == "requested" && requested_after?(task, at_capacity_since)
        fhir_task = task.fhir_resource
        fhir_task.status = "rejected"
        fhir_task.statusReason = FHIR::CodeableConcept.new(text: "Rejected - at capacity")
        client.update(fhir_task, fhir_task.id)
        rejected << Task.new(fhir_task, client)
      else
        remaining << task
      end
    end
    [rejected, remaining]
  end

  # Only tasks requested AFTER the organization went to capacity are
  # auto-rejected; requests already received keep their place in the queue.
  # The cutoff is HealthcareService.meta.lastUpdated -- i.e. when the capacity
  # status was last written to FHIR -- so it is not lost with the session.
  def requested_after?(task, at_capacity_since)
    return false if at_capacity_since.nil?

    authored_on = task.fhir_resource&.authoredOn
    return false if authored_on.blank?

    Time.parse(authored_on) > at_capacity_since
  rescue ArgumentError
    false
  end
end

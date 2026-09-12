const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PROJECT_SLOT = /^project-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;

const BLOCK_PRESENTATION = Object.freeze({
  BLOCKED_INTAKE: Object.freeze({
    label: "Geblokkeerd",
    copy: "Intake nog niet afgerond",
    tone: "blocked",
  }),
  BLOCKED_M1_PAYMENT: Object.freeze({
    label: "Geblokkeerd",
    copy: "Eerste 40% nog niet bevestigd",
    tone: "blocked",
  }),
  READY_FOR_RELEASE: Object.freeze({
    label: "Geblokkeerd",
    copy: "Wacht op commerciële vrijgave",
    tone: "waiting",
  }),
  READY_TO_START: Object.freeze({
    label: "Groen",
    copy: "Klaar om project te starten",
    tone: "ready",
  }),
  STARTED: Object.freeze({
    label: "Project gestart",
    copy: "Website is in uitvoering",
    tone: "active",
  }),
  ADVANCED: Object.freeze({
    label: "Project gevorderd",
    copy: "Project bevindt zich voorbij de startfase",
    tone: "active",
  }),
});

const PROJECT_STATE_PRESENTATION = Object.freeze({
  PROJECT_RELEASED: "Klaar om project te starten",
  PREVIEW_READY: "Klaar voor review en feedback",
  M2_PAYMENT_RECEIVED: "Review en feedback",
  FINAL_APPROVAL_RECORDED: "Klant heeft definitief goedgekeurd",
  FULL_PAYMENT_RECEIVED: "Volledige betaling ontvangen",
  FINAL_TRANSFER_AUTHORIZED: "Klaar voor oplevering",
  DELIVERED: "Project opgeleverd",
  ARCHIVED: "Project afgerond",
});

const ACTIVITY_PRESENTATION = Object.freeze({
  RELEASE_PROJECT: "Project commercieel vrijgegeven",
  PROJECT_WORK_STARTED: "Project gestart",
  STATE_TRANSITION: "Projectstatus gewijzigd",
});

const PROGRESS_REASON_PRESENTATION = Object.freeze({
  INTAKE_AUTHORITY_COMPLETE: "Intake is volledig ingediend.",
  INTAKE_INCOMPLETE: "Intake is nog niet volledig ingediend.",
  INTAKE_REQUIRED: "Rond eerst de intake af.",
  M1_PAYMENT_CONFIRMED: "De eerste 40% is bevestigd.",
  M1_PAYMENT_NOT_CONFIRMED: "De eerste 40% is nog niet bevestigd.",
  PAYMENT_STATE_INCONSISTENT: "De betaalstatus is niet eenduidig.",
  M1_PAYMENT_REQUIRED: "Bevestig eerst de eerste 40%.",
  COMMERCIAL_RELEASE_REQUIRED: "Wacht op commerciële vrijgave.",
  START_GATE_OPEN: "Het project kan worden gestart.",
  PROJECT_WORK_STARTED: "De website is in uitvoering.",
  PREVIEW_AUTHORITY_REACHED: "De preview is gereed.",
  PREVIEW_STATE_INCONSISTENT: "De previewstatus botst met eerdere voorwaarden.",
  PROJECT_STATE_INCONSISTENT: "De projectstatus botst met eerdere voorwaarden.",
  PROJECT_START_STATE_INCONSISTENT: "De startstatus is niet eenduidig.",
  PREVIEW_REQUIRED: "Wacht tot de preview gereed is.",
  BUILD_AUTHORITY_INCONSISTENT: "De bouwfase bevat tegenstrijdige gegevens.",
  PREVIEW_READY: "De preview kan worden beoordeeld.",
  REVIEW_ACTIVITY_RECORDED: "Feedback of een revisie is actief.",
  FINAL_APPROVAL_RECORDED: "De klant heeft definitief goedgekeurd.",
  FINAL_APPROVAL_REQUIRED: "Wacht op definitieve klantgoedkeuring.",
  FULL_PAYMENT_REQUIRED: "De volledige betaling is nog niet bevestigd.",
  FINAL_TRANSFER_AUTHORIZATION_REQUIRED: "De overdracht moet nog worden geautoriseerd.",
  FINAL_TRANSFER_AUTHORIZED: "Alle voorwaarden voor oplevering zijn vervuld.",
  DELIVERY_RECORDED: "De oplevering is geregistreerd.",
  DELIVERY_PRECONDITION_MISSING: "Een vereiste oplevervoorwaarde ontbreekt.",
});

export function projectProgressReasonLabel(reason) {
  return PROGRESS_REASON_PRESENTATION[reason] ||
    "Status kan niet veilig worden bepaald.";
}

const AUTHORIZATION_FAILURES = new Set([
  "HUMAN_JWT_REQUIRED",
  "UNKNOWN_OPERATOR",
  "OPERATOR_DISABLED",
  "OPERATOR_REVOKED",
  "OPERATOR_INACTIVE",
  "PROJECT_SCOPE_DENIED",
  "COMMAND_PERMISSION_DENIED",
]);

function errorCode(error) {
  return String(error?.context?.code || error?.code || error?.message || "");
}

function assertContext(context, requireCommandState = false) {
  if (
    !UUID.test(String(context?.quoteRequestId || "")) ||
    !UUID.test(String(context?.projectId || "")) ||
    (requireCommandState &&
      (typeof context?.expectedState !== "string" ||
        !context.expectedState ||
        !Number.isSafeInteger(context?.expectedRevision) ||
        context.expectedRevision < 0))
  ) throw new Error("INVALID_PROJECT_WORKSPACE_CONTEXT");
  return context;
}

export function projectWorkspaceSlot(quoteRequestId) {
  if (!UUID.test(String(quoteRequestId || ""))) {
    throw new Error("INVALID_PROJECT_WORKSPACE_SLOT");
  }
  return `project-${String(quoteRequestId).toLowerCase()}`;
}

export function quoteRequestIdFromProjectWorkspaceSlot(slotKey) {
  return PROJECT_SLOT.exec(String(slotKey || ""))?.[1]?.toLowerCase() || null;
}

export function projectWorkspaceRequest(detail) {
  if (detail?.request_kind !== "website") return null;
  const quoteRequestId = String(detail?.quote_request_id || "");
  const projectId = String(detail?.project?.project_id || "");
  if (!UUID.test(quoteRequestId)) {
    throw new Error("INVALID_PROJECT_WORKSPACE_CONTEXT");
  }
  if (!projectId) return null;
  if (!UUID.test(projectId)) {
    throw new Error("INVALID_PROJECT_WORKSPACE_CONTEXT");
  }
  return Object.freeze({
    action: "get_project_workspace",
    quote_request_id: quoteRequestId,
    project_id: projectId,
  });
}

export function validateProjectWorkspace(value, expected) {
  assertContext(expected);
  const project = value?.project;
  const gate = value?.start_gate;
  if (
    !project || !gate ||
    project.project_id !== expected.projectId ||
    gate.project_id !== expected.projectId ||
    gate.quote_request_id !== expected.quoteRequestId ||
    typeof project.current_state !== "string" || !project.current_state ||
    !Number.isSafeInteger(project.revision) || project.revision < 0 ||
    !Array.isArray(project.financial_summary?.milestones) ||
    !Array.isArray(project.timeline) ||
    typeof gate.intake_complete !== "boolean" ||
    typeof gate.m1_confirmed !== "boolean" ||
    typeof gate.commercially_released !== "boolean" ||
    typeof gate.project_start_allowed !== "boolean" ||
    !Object.hasOwn(BLOCK_PRESENTATION, gate.block_reason) ||
    gate.current_project_state !== project.current_state ||
    (gate.project_start_allowed && gate.block_reason !== "READY_TO_START")
  ) throw new Error("INVALID_PROJECT_WORKSPACE_RESPONSE");
  return Object.freeze({ project, startGate: gate });
}

const REVIEW_STATES = new Set(["PREVIEW_READY", "M2_PAYMENT_RECEIVED"]);
const APPROVED_STATES = new Set([
  "FINAL_APPROVAL_RECORDED",
  "FULL_PAYMENT_RECEIVED",
  "FINAL_TRANSFER_AUTHORIZED",
  "DELIVERED",
  "ARCHIVED",
]);
const COMPLETE_STATES = new Set(["DELIVERED", "ARCHIVED"]);
const ADVANCED_STATES = new Set([
  ...REVIEW_STATES,
  ...APPROVED_STATES,
]);
const REVIEW_ACTIVITY = new Set([
  "ACTIVATE_PREVIEW_ACCESS",
  "SUBMIT_CUSTOMER_FEEDBACK",
  "CLASSIFY_FEEDBACK",
  "CREATE_REVISION",
  "MARK_REVISION_READY",
  "CREATE_PREVIEW_VERSION",
]);

function milestoneStatus(project, number) {
  const milestones = project?.financial_summary?.milestones;
  if (!Array.isArray(milestones)) return "UNKNOWN";
  const matches = milestones.filter(({ milestone }) => Number(milestone) === number);
  if (matches.length !== 1 || typeof matches[0]?.payment_status !== "string") {
    return "UNKNOWN";
  }
  return matches[0].payment_status;
}

function timelineEvents(project) {
  if (!Array.isArray(project?.timeline)) return new Set();
  return new Set(project.timeline.flatMap((event) => [
    event?.event_type,
    event?.action,
    event?.new_state,
  ]).filter(Boolean).map((value) => String(value).toUpperCase()));
}

function progressStep(id, label, status, reason, sourceState) {
  return Object.freeze({
    id,
    number: id,
    label,
    status,
    state: status,
    reason,
    source_state: String(sourceState || "UNKNOWN"),
  });
}

export function deriveProjectProgress(value) {
  const project = value?.project;
  const gate = value?.startGate || value?.start_gate;
  if (!project || !gate) throw new Error("INVALID_PROJECT_WORKSPACE_RESPONSE");
  const projectState = String(project.current_state || "UNKNOWN");
  const m1Status = milestoneStatus(project, 1);
  const m3Status = milestoneStatus(project, 3);
  const events = timelineEvents(project);
  const intakeDone = gate.intake_complete === true;
  const m1Done = m1Status === "CONFIRMED" && gate.m1_confirmed === true;
  const prerequisiteConflict = gate.m1_confirmed !== (m1Status === "CONFIRMED");
  const advanced = ADVANCED_STATES.has(projectState);
  const started = gate.block_reason === "STARTED" ||
    events.has("PROJECT_WORK_STARTED");

  const steps = [];
  steps.push(progressStep(
    "01",
    "Intake afgerond",
    intakeDone ? "done" : "blocked",
    intakeDone ? "INTAKE_AUTHORITY_COMPLETE" : "INTAKE_INCOMPLETE",
    intakeDone ? "SUBMITTED_OR_REVIEWED" : "INCOMPLETE",
  ));

  steps.push(progressStep(
    "02",
    "Eerste 40% ontvangen",
    !intakeDone ? "locked" : m1Done ? "done" : "blocked",
    !intakeDone
      ? "INTAKE_REQUIRED"
      : m1Done
      ? "M1_PAYMENT_CONFIRMED"
      : prerequisiteConflict
      ? "PAYMENT_STATE_INCONSISTENT"
      : "M1_PAYMENT_NOT_CONFIRMED",
    m1Status,
  ));

  let buildStatus = "locked";
  let buildReason = "COMMERCIAL_RELEASE_REQUIRED";
  if (!intakeDone || !m1Done || prerequisiteConflict) {
    buildStatus = advanced ? "blocked" : "locked";
    buildReason = advanced
      ? projectState === "PREVIEW_READY"
        ? "PREVIEW_STATE_INCONSISTENT"
        : "PROJECT_STATE_INCONSISTENT"
      : !intakeDone
      ? "INTAKE_REQUIRED"
      : "M1_PAYMENT_REQUIRED";
  } else if (advanced) {
    buildStatus = "done";
    buildReason = "PREVIEW_AUTHORITY_REACHED";
  } else if (projectState === "PROJECT_RELEASED" && started) {
    buildStatus = "in_progress";
    buildReason = "PROJECT_WORK_STARTED";
  } else if (projectState === "PROJECT_RELEASED" && gate.project_start_allowed) {
    buildStatus = "ready";
    buildReason = "START_GATE_OPEN";
  } else if (projectState === "PROJECT_RELEASED") {
    buildStatus = "blocked";
    buildReason = "PROJECT_START_STATE_INCONSISTENT";
  }
  steps.push(progressStep(
    "03",
    "Website in uitvoering",
    buildStatus,
    buildReason,
    started ? "PROJECT_WORK_STARTED" : projectState,
  ));

  let reviewStatus = "locked";
  let reviewReason = "PREVIEW_REQUIRED";
  if (buildStatus === "blocked") {
    reviewReason = "BUILD_AUTHORITY_INCONSISTENT";
  } else if (APPROVED_STATES.has(projectState)) {
    reviewStatus = "done";
    reviewReason = "FINAL_APPROVAL_RECORDED";
  } else if (REVIEW_STATES.has(projectState)) {
    const reviewActive = [...events].some((event) => REVIEW_ACTIVITY.has(event));
    reviewStatus = reviewActive ? "in_progress" : "ready";
    reviewReason = reviewActive ? "REVIEW_ACTIVITY_RECORDED" : "PREVIEW_READY";
  }
  steps.push(progressStep(
    "04",
    "Review en feedback",
    reviewStatus,
    reviewReason,
    projectState,
  ));

  let deliveryStatus = "locked";
  let deliveryReason = "FINAL_APPROVAL_REQUIRED";
  if (reviewStatus === "done") {
    if (COMPLETE_STATES.has(projectState)) {
      deliveryStatus = m3Status === "CONFIRMED" ? "done" : "blocked";
      deliveryReason = m3Status === "CONFIRMED"
        ? "DELIVERY_RECORDED"
        : "DELIVERY_PRECONDITION_MISSING";
    } else if (projectState === "FINAL_TRANSFER_AUTHORIZED") {
      deliveryStatus = m3Status === "CONFIRMED" ? "ready" : "blocked";
      deliveryReason = m3Status === "CONFIRMED"
        ? "FINAL_TRANSFER_AUTHORIZED"
        : "DELIVERY_PRECONDITION_MISSING";
    } else if (m3Status !== "CONFIRMED") {
      deliveryStatus = "blocked";
      deliveryReason = "FULL_PAYMENT_REQUIRED";
    } else {
      deliveryStatus = "blocked";
      deliveryReason = "FINAL_TRANSFER_AUTHORIZATION_REQUIRED";
    }
  }
  steps.push(progressStep(
    "05",
    "Oplevering",
    deliveryStatus,
    deliveryReason,
    `${projectState}:${m3Status}`,
  ));

  const phaseByState = {
    PROJECT_RELEASED: started ? "Website in uitvoering" : "Klaar om te starten",
    PREVIEW_READY: reviewStatus === "in_progress" ? "Review en feedback" : "Klaar voor review",
    M2_PAYMENT_RECEIVED: "Review en feedback",
    FINAL_APPROVAL_RECORDED: "Klant heeft definitief goedgekeurd",
    FULL_PAYMENT_RECEIVED: "Wacht op overdrachtsautorisatie",
    FINAL_TRANSFER_AUTHORIZED: "Klaar voor oplevering",
    DELIVERED: "Opgeleverd",
    ARCHIVED: "Afgerond",
  };
  const current = steps.find(({ status }) => status !== "done") || null;
  return Object.freeze({
    project_phase: phaseByState[projectState] || "Voorbereiding",
    current_step: current?.id || null,
    steps: Object.freeze(steps),
  });
}

function projectStatusLabel(project, gate) {
  if (gate.block_reason === "STARTED") return "Website in uitvoering";
  return PROJECT_STATE_PRESENTATION[project.current_state] ||
    deriveProjectProgress({ project, startGate: gate }).project_phase;
}

export function projectWorkspaceViewModel(value, assignment = null) {
  if (value == null) {
    return Object.freeze({
      state: "empty",
      message: "Geen project gekoppeld.",
    });
  }
  if (value.state === "denied" || value.state === "error") return value;
  const project = value.project;
  const gate = value.startGate || value.start_gate;
  const presentation = BLOCK_PRESENTATION[gate?.block_reason];
  if (!project || !gate || !presentation) {
    throw new Error("INVALID_PROJECT_WORKSPACE_RESPONSE");
  }
  const lastActivity = project.timeline[0] || null;
  const workStarted = timelineEvents(project).has("PROJECT_WORK_STARTED");
  const progress = deriveProjectProgress({ project, startGate: gate });
  const steps = progress.steps;
  const currentStep = steps.find(({ id }) => id === progress.current_step);
  return Object.freeze({
    state: "ready",
    projectId: project.project_id,
    quoteRequestId: gate.quote_request_id,
    revision: project.revision,
    projectStatus: project.current_state,
    startAllowed: gate.project_start_allowed,
    workStarted,
    blockReason: gate.block_reason,
    permissionLabel: presentation.label,
    permissionCopy: presentation.copy,
    permissionTone: presentation.tone,
    intakeStatus: gate.intake_complete ? "Afgerond" : "Niet afgerond",
    firstPaymentStatus: gate.m1_confirmed ? "Bevestigd" : "Niet bevestigd",
    currentPhase: progress.project_phase,
    currentStep: progress.current_step,
    currentStepLabel: currentStep?.label || "Project voltooid",
    projectStatusLabel: projectStatusLabel(project, gate),
    assignee: assignment?.assignee_display_name || "Niet beschikbaar",
    lastActivity: lastActivity?.occurred_at || null,
    lastActivityType: lastActivity?.event_type || lastActivity?.new_state || null,
    lastActivityLabel: ACTIVITY_PRESENTATION[
      lastActivity?.event_type || lastActivity?.new_state
    ] || "Projectactiviteit",
    completedSteps: steps.filter(({ status }) => status === "done").length,
    steps,
  });
}

export function projectWorkspaceWithAssignment(view, assignment) {
  if (view?.state !== "ready") return view;
  return Object.freeze({
    ...view,
    assignee: assignment?.assignee_display_name || "Niet toegewezen",
  });
}

export function projectSummaryMarkup() {
  return `<section class="panel dossiers-project-summary" data-dossiers-project hidden>
    <div class="panel__heading"><div><p class="eyebrow">Project</p><h2 data-project-summary-status>Project laden...</h2></div><span class="badge" data-project-status-badge></span></div>
    <p class="empty-state" data-project-empty>Project laden...</p>
    <div class="project-summary" data-project-content hidden>
      <dl class="project-summary__facts">
        <div><dt>Voortgang</dt><dd data-project-summary-progress></dd></div>
        <div><dt>Huidige stap</dt><dd data-project-summary-current-step></dd></div>
        <div><dt>Eerste 40%</dt><dd data-project-summary-payment></dd></div>
      </dl>
      <button type="button" class="primary-action primary-action--compact" data-operator-window-module="dossiers" data-project-open hidden>Project openen</button>
    </div>
  </section>`;
}

export function projectWorkspaceMarkup() {
  return `<section class="panel dossiers-project" data-dossiers-project hidden>
    <div class="panel__heading"><div><p class="eyebrow">Uitvoering</p><h2>Project</h2></div><span class="badge" data-project-status-badge></span></div>
    <p class="empty-state" data-project-empty>Project laden...</p>
    <div data-project-content hidden>
      <div class="project-permission" data-project-permission><strong data-project-permission-label></strong><span data-project-permission-copy></span></div>
      <ol class="project-progress" aria-label="Projectvoortgang">
        <li data-project-step="01"><span class="project-progress__mark" aria-hidden="true"></span><span class="project-progress__copy"><strong>01 Intake afgerond</strong><small data-project-step-reason></small></span></li>
        <li data-project-step="02"><span class="project-progress__mark" aria-hidden="true"></span><span class="project-progress__copy"><strong>02 Eerste 40% ontvangen</strong><small data-project-step-reason></small></span></li>
        <li data-project-step="03"><span class="project-progress__mark" aria-hidden="true"></span><span class="project-progress__copy"><strong>03 Website in uitvoering</strong><small data-project-step-reason></small></span></li>
        <li data-project-step="04"><span class="project-progress__mark" aria-hidden="true"></span><span class="project-progress__copy"><strong>04 Review en feedback</strong><small data-project-step-reason></small></span></li>
        <li data-project-step="05"><span class="project-progress__mark" aria-hidden="true"></span><span class="project-progress__copy"><strong>05 Oplevering</strong><small data-project-step-reason></small></span></li>
      </ol>
      <section class="project-workspace-requirements" data-project-requirements-summary hidden>
        <div><p class="eyebrow">Projectvereisten</p><h3>PROJECTVEREISTEN</h3></div>
        <p data-project-requirements-empty hidden></p>
        <div data-project-requirements-content>
          <strong class="project-workspace-requirements__progress" data-project-requirements-progress></strong>
          <dl class="project-workspace-requirements__facts">
            <div><dt>Afgerond</dt><dd data-project-requirements-completed></dd></div>
            <div><dt>Open</dt><dd data-project-requirements-open-count></dd></div>
            <div><dt>Geblokkeerd</dt><dd data-project-requirements-blocked></dd></div>
          </dl>
          <p data-project-requirements-preview></p>
        </div>
        <button type="button" class="secondary-action" data-project-requirements-open>Takenbord openen</button>
      </section>
      <dl class="application-detail project-facts">
        <div><dt>Projectstatus</dt><dd data-project-field="status"></dd></div>
        <div><dt>Starttoestemming</dt><dd data-project-field="permission"></dd></div>
        <div><dt>Intake status</dt><dd data-project-field="intake"></dd></div>
        <div><dt>Eerste 40% status</dt><dd data-project-field="m1"></dd></div>
        <div><dt>Huidige fase</dt><dd data-project-field="phase"></dd></div>
        <div><dt>Toegewezen operator</dt><dd data-project-field="assignee"></dd></div>
        <div class="application-detail__wide"><dt>Laatste projectactiviteit</dt><dd data-project-field="activity"></dd></div>
      </dl>
      <button type="button" class="primary-action primary-action--compact" data-project-start hidden>Project starten</button>
      <button type="button" class="primary-action primary-action--compact" data-project-website-open hidden>Website openen</button>
      <p class="action-message" data-project-message role="status" aria-live="polite"></p>
    </div>
  </section>`;
}

export async function loadProjectWorkspace(gateway, context) {
  assertContext(context);
  try {
    const value = await gateway({
      action: "get_project_workspace",
      quote_request_id: context.quoteRequestId,
      project_id: context.projectId,
    });
    return projectWorkspaceViewModel(validateProjectWorkspace(value, context));
  } catch (error) {
    if (AUTHORIZATION_FAILURES.has(errorCode(error))) {
      return Object.freeze({
        state: "denied",
        message: "Geen toegang tot dit project.",
      });
    }
    throw error;
  }
}

export async function startProjectAndReload(gateway, context, createIdempotencyKey) {
  assertContext(context, true);
  const idempotencyKey = createIdempotencyKey();
  if (!UUID.test(String(idempotencyKey || ""))) {
    throw new Error("INVALID_PROJECT_WORKSPACE_IDEMPOTENCY_KEY");
  }
  await gateway({
    action: "start_project_work",
    quote_request_id: context.quoteRequestId,
    project_id: context.projectId,
    expected_state: context.expectedState,
    expected_revision: context.expectedRevision,
    idempotency_key: idempotencyKey,
  });
  return await loadProjectWorkspace(gateway, context);
}

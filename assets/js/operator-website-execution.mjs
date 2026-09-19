const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const WEBSITE_SLOT = /^website-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;
const GITHUB_SEGMENT = /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,98}[A-Za-z0-9])?$/;
const BRANCH = /^(?:main|develop|work\/[a-z0-9][a-z0-9-]{0,39})$/;
const COMMIT_SHA = /^[0-9a-f]{40}$/i;
const WORKSPACE_STATES = [
  "PENDING_REPOSITORY", "REPOSITORY_PROVISIONING", "REPOSITORY_READY",
  "REPOSITORY_FAILED", "READY",
];
const REPOSITORY_OPERATION_STATES = [
  null, "CLAIMED", "CREATING", "EXTERNAL_CREATED", "VERIFYING",
  "RETRYABLE_FAILED", "RETRY_SCHEDULED", "BLOCKED", "QUARANTINED",
  "TERMINAL_FAILED", "COMPLETE",
];
const REPOSITORY_FAILURE_CATEGORIES = [
  null, "RETRYABLE", "BLOCKED", "QUARANTINED", "TERMINAL",
];
const REPOSITORY_RECOVERY_GUIDANCE = [
  null, "WAIT", "REFRESH_LATER", "CONTACT_OWNER", "RECONCILIATION_REQUIRED",
];
const WEBSITE_WORK_KEYS = [
  "state", "quote_request_id", "concept_id", "project_id",
  "website_work_context_id", "mode", "briefing_status",
  "commercially_released", "revision", "permitted_actions",
];
const ROOT_KEYS = [
  "contract_version", "mode", "quote_request_id", "concept_id", "project_id",
  "website_work_context_id", "context_revision", "briefing_status",
  "commercially_released", "project", "start_gate", "workspace", "requirements",
];
const WORKSPACE_KEYS = [
  "website_workspace_id", "website_work_context_id", "project_id",
  "quote_request_id", "workspace_state", "repository_operation_state",
  "repository_failure_category", "repository_recovery_guidance",
  "repository_provider", "repository_owner", "repository_name",
  "repository_navigation_url", "default_branch", "preview_branch",
  "preview_url", "last_commit_sha", "last_commit_at", "last_build_result",
  "last_build_at", "binding_revision", "provisioned_by", "provisioned_at",
  "created_at", "updated_at", "capabilities",
];

function exactKeys(value, keys) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length
    && keys.every((key)=>Object.hasOwn(value, key));
}

function validTimestamp(value) {
  return value === null || (typeof value === "string" && Number.isFinite(Date.parse(value)));
}

function optionalHttpsUrl(value) {
  if (value == null || value === "") return null;
  const url = new URL(String(value));
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new Error("INVALID_WEBSITE_EXECUTION_URL");
  }
  url.hash = "";
  return url.href;
}

export function websiteExecutionSlot(quoteRequestId) {
  if (!UUID.test(String(quoteRequestId || ""))) {
    throw new Error("INVALID_WEBSITE_EXECUTION_SLOT");
  }
  return `website-${String(quoteRequestId).toLowerCase()}`;
}

export function quoteRequestIdFromWebsiteExecutionSlot(slotKey) {
  return WEBSITE_SLOT.exec(String(slotKey || ""))?.[1]?.toLowerCase() || null;
}

export function websiteExecutionRequest(detail) {
  if (detail?.request_kind !== "website") return null;
  const quoteRequestId = String(detail?.quote_request_id || "");
  const work = detail?.website_work;
  if (!UUID.test(quoteRequestId) || !exactKeys(work, WEBSITE_WORK_KEYS)
    || work.quote_request_id !== quoteRequestId
    || !["PRE_PROJECT", "OFFICIAL_PROJECT"].includes(work.state)
    || work.mode !== work.state
    || !UUID.test(String(work.website_work_context_id || ""))
    || !["LIMITED", "COMPLETE"].includes(work.briefing_status)
    || typeof work.commercially_released !== "boolean"
    || !Number.isSafeInteger(work.revision) || work.revision < 1
    || !Array.isArray(work.permitted_actions)
    || new Set(work.permitted_actions).size !== work.permitted_actions.length
    || work.permitted_actions.length !== 1 || work.permitted_actions[0] !== "OPEN_WEBSITE"
    || (work.state === "PRE_PROJECT"
      && (!UUID.test(String(work.concept_id || "")) || work.project_id !== null
        || work.commercially_released))
    || (work.state === "OFFICIAL_PROJECT"
      && (!UUID.test(String(work.project_id || ""))
        || (work.concept_id !== null && !UUID.test(String(work.concept_id || "")))))) {
    throw new Error("INVALID_WEBSITE_EXECUTION_CONTEXT");
  }
  return Object.freeze({
    action: "get_website_execution_workspace",
    quote_request_id: quoteRequestId,
  });
}

export function websiteExecutionProvisionRequest(value) {
  if (!exactKeys(value, ["quoteRequestId", "idempotencyKey"])
    || !UUID.test(String(value.quoteRequestId || ""))
    || !UUID.test(String(value.idempotencyKey || ""))) {
    throw new Error("INVALID_WEBSITE_WORKSPACE_PROVISION_REQUEST");
  }
  return Object.freeze({
    action: "provision_website_execution_workspace",
    quote_request_id: value.quoteRequestId,
    idempotency_key: value.idempotencyKey,
  });
}

export function websiteConceptPromotionRequest(value) {
  if (!exactKeys(value, [
    "quoteRequestId", "websiteWorkContextId", "expectedContextRevision",
    "idempotencyKey",
  ]) || !UUID.test(String(value.quoteRequestId || ""))
    || !UUID.test(String(value.websiteWorkContextId || ""))
    || !Number.isSafeInteger(value.expectedContextRevision)
    || value.expectedContextRevision < 1
    || !UUID.test(String(value.idempotencyKey || ""))) {
    throw new Error("INVALID_WEBSITE_CONCEPT_PROMOTION_REQUEST");
  }
  return Object.freeze({
    action: "promote_website_concept",
    quote_request_id: value.quoteRequestId,
    website_work_context_id: value.websiteWorkContextId,
    expected_context_revision: value.expectedContextRevision,
    idempotency_key: value.idempotencyKey,
  });
}

export function validateWebsiteConceptPromotionResult(value, expected) {
  if (!exactKeys(expected, [
    "quoteRequestId", "websiteWorkContextId", "expectedContextRevision",
  ]) || !UUID.test(String(expected.quoteRequestId || ""))
    || !UUID.test(String(expected.websiteWorkContextId || ""))
    || !Number.isSafeInteger(expected.expectedContextRevision)
    || expected.expectedContextRevision < 1
    || !exactKeys(value, [
      "contract_version", "outcome", "quote_request_id",
      "website_work_context_id", "concept_id", "project_id",
      "previous_phase", "phase", "previous_context_revision",
      "context_revision", "website_workspace_id",
      "workspace_binding_revision", "requirements_board_id",
      "requirements_board_revision", "promotion_event_id", "promoted_at",
      "replayed",
    ]) || value.contract_version !== 1 || value.outcome !== "PROMOTED"
    || value.quote_request_id !== expected.quoteRequestId
    || value.website_work_context_id !== expected.websiteWorkContextId
    || !UUID.test(String(value.concept_id || ""))
    || !UUID.test(String(value.project_id || ""))
    || value.previous_phase !== "PRE_PROJECT"
    || value.phase !== "OFFICIAL_PROJECT"
    || value.previous_context_revision !== expected.expectedContextRevision
    || value.context_revision !== expected.expectedContextRevision + 1
    || !UUID.test(String(value.promotion_event_id || ""))
    || typeof value.promoted_at !== "string"
    || !Number.isFinite(Date.parse(value.promoted_at))
    || typeof value.replayed !== "boolean") {
    throw new Error("INVALID_WEBSITE_CONCEPT_PROMOTION_RESPONSE");
  }
  const workspacePairValid = value.website_workspace_id === null
    ? value.workspace_binding_revision === null
    : UUID.test(String(value.website_workspace_id || ""))
      && Number.isSafeInteger(value.workspace_binding_revision)
      && value.workspace_binding_revision >= 1;
  const requirementsPairValid = value.requirements_board_id === null
    ? value.requirements_board_revision === null
    : UUID.test(String(value.requirements_board_id || ""))
      && Number.isSafeInteger(value.requirements_board_revision)
      && value.requirements_board_revision >= 1;
  if (!workspacePairValid || !requirementsPairValid) {
    throw new Error("INVALID_WEBSITE_CONCEPT_PROMOTION_RESPONSE");
  }
  return Object.freeze(structuredClone(value));
}

export function createWebsiteConceptPromotionIntent(
  context,
  randomUUID = crypto.randomUUID,
) {
  if (!exactKeys(context, [
    "quoteRequestId", "websiteWorkContextId", "expectedContextRevision",
  ])) {
    throw new Error("INVALID_WEBSITE_CONCEPT_PROMOTION_REQUEST");
  }
  const idempotencyKey = randomUUID();
  const request = websiteConceptPromotionRequest({
    ...context,
    idempotencyKey,
  });
  return Object.freeze({
    idempotencyKey,
    request,
    quoteRequestId: context.quoteRequestId,
    websiteWorkContextId: context.websiteWorkContextId,
    expectedContextRevision: context.expectedContextRevision,
  });
}

function safeRepositoryNavigationUrl(value, repositoryOwner, repositoryName) {
  if (value === null && repositoryOwner === null && repositoryName === null) return null;
  if (!GITHUB_SEGMENT.test(String(repositoryOwner || ""))
    || !GITHUB_SEGMENT.test(String(repositoryName || ""))
    || typeof value !== "string") {
    throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
  }
  const url = new URL(value);
  const pathSegments = url.pathname.split("/").filter(Boolean);
  if (url.protocol !== "https:" || url.hostname !== "github.com"
    || url.port || url.username || url.password || url.search || url.hash
    || pathSegments.length !== 2
    || pathSegments[0] !== repositoryOwner || pathSegments[1] !== repositoryName) {
    throw new Error("INVALID_WEBSITE_EXECUTION_URL");
  }
  return url.href;
}

export function validateWebsiteExecutionWorkspace(value, expected) {
  if (!UUID.test(String(expected?.quoteRequestId || ""))
    || !UUID.test(String(expected?.websiteWorkContextId || ""))
    || !["PRE_PROJECT", "OFFICIAL_PROJECT"].includes(expected?.mode)
    || (expected.mode === "PRE_PROJECT"
      && (!UUID.test(String(expected?.conceptId || "")) || expected?.projectId !== null))
    || (expected.mode === "OFFICIAL_PROJECT"
      && (!UUID.test(String(expected?.projectId || ""))
        || (expected?.conceptId !== null && !UUID.test(String(expected?.conceptId || "")))))) {
    throw new Error("INVALID_WEBSITE_EXECUTION_CONTEXT");
  }
  if (!exactKeys(value, ROOT_KEYS) || value.contract_version !== 3
    || value.mode !== expected.mode
    || value.quote_request_id !== expected.quoteRequestId
    || value.website_work_context_id !== expected.websiteWorkContextId
    || !Number.isSafeInteger(value.context_revision) || value.context_revision < 1
    || !["LIMITED", "COMPLETE"].includes(value.briefing_status)
    || typeof value.commercially_released !== "boolean"
    || !exactKeys(value.requirements, ["state", "message"])) {
    throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
  }
  if (value.concept_id !== expected.conceptId || value.project_id !== expected.projectId) {
    throw new Error("WEBSITE_WORKSPACE_BINDING_MISMATCH");
  }
  if (value.mode === "PRE_PROJECT") {
    if (value.project !== null || value.start_gate !== null || value.commercially_released
      || value.requirements.state !== "NOT_AVAILABLE"
      || value.requirements.message !== "Requirements volgen na intake-sync.") {
      throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
    }
  } else if (!value.project || value.project.project_id !== expected.projectId
    || !value.start_gate || value.start_gate.project_id !== expected.projectId
    || value.start_gate.quote_request_id !== expected.quoteRequestId
    || value.requirements.state !== "PROJECT_BOUND"
    || value.requirements.message !== null) {
    throw new Error("WEBSITE_WORKSPACE_BINDING_MISMATCH");
  }

  let workspace = null;
  if (value.workspace !== null) {
    workspace = value.workspace;
    if (!exactKeys(workspace, WORKSPACE_KEYS)
      || !UUID.test(String(workspace.website_workspace_id || ""))
      || workspace.website_work_context_id !== expected.websiteWorkContextId
      || workspace.project_id !== expected.projectId
      || workspace.quote_request_id !== expected.quoteRequestId
      || !WORKSPACE_STATES.includes(workspace.workspace_state)
      || !REPOSITORY_OPERATION_STATES.includes(workspace.repository_operation_state)
      || !REPOSITORY_FAILURE_CATEGORIES.includes(workspace.repository_failure_category)
      || !REPOSITORY_RECOVERY_GUIDANCE.includes(workspace.repository_recovery_guidance)
      || workspace.repository_provider !== "GITHUB"
      || !BRANCH.test(String(workspace.default_branch || ""))
      || (workspace.preview_branch !== null && !BRANCH.test(String(workspace.preview_branch)))
      || (workspace.last_commit_sha !== null && !COMMIT_SHA.test(String(workspace.last_commit_sha)))
      || !validTimestamp(workspace.last_commit_at)
      || ![null, "PASS", "FAIL", "UNKNOWN"].includes(workspace.last_build_result)
      || !validTimestamp(workspace.last_build_at)
      || !Number.isSafeInteger(workspace.binding_revision) || workspace.binding_revision < 1
      || !UUID.test(String(workspace.provisioned_by || ""))
      || !validTimestamp(workspace.provisioned_at) || workspace.provisioned_at === null
      || !validTimestamp(workspace.created_at) || workspace.created_at === null
      || !validTimestamp(workspace.updated_at) || workspace.updated_at === null
      || !exactKeys(workspace.capabilities, ["project_files_read"])
      || typeof workspace.capabilities.project_files_read !== "boolean") {
      throw new Error("INVALID_WEBSITE_EXECUTION_RESPONSE");
    }
    workspace = {
      ...workspace,
      repository_navigation_url: safeRepositoryNavigationUrl(
        workspace.repository_navigation_url,
        workspace.repository_owner,
        workspace.repository_name,
      ),
      preview_url: optionalHttpsUrl(workspace.preview_url),
    };
  }
  return Object.freeze({
    ...structuredClone(value),
    startGate: value.start_gate,
    workspace: workspace === null ? null : Object.freeze(workspace),
  });
}

export function websiteExecutionView(value) {
  const productionUrl = optionalHttpsUrl(value.project?.site?.canonical_url);
  if (!value.workspace) {
    return Object.freeze({
      state: "empty",
      message: "Website workspace niet gekoppeld.",
      modeLabel: value.mode === "PRE_PROJECT" ? "Voorlopig concept" : "Officieel project",
      briefingLabel: value.briefing_status,
      releaseLabel: value.commercially_released
        ? "Commercieel vrijgegeven" : "Niet commercieel vrijgegeven",
      repository: "Repository niet gekoppeld",
      branch: "Niet beschikbaar",
      preview: "Preview nog niet beschikbaar",
      production: productionUrl || "Production URL nog niet beschikbaar",
      commit: "Nog geen commit geregistreerd",
      links: Object.freeze({ github: null, preview: null, production: productionUrl }),
    });
  }
  const workspace = value.workspace;
  if (workspace.workspace_state === "PENDING_REPOSITORY") {
    return Object.freeze({
      state: "pending_repository",
      message: "Technische werkruimte is aangemaakt. Repository provisioning is nog niet uitgevoerd.",
      modeLabel: value.mode === "PRE_PROJECT" ? "Voorlopig concept" : "Officieel project",
      briefingLabel: value.briefing_status,
      releaseLabel: value.commercially_released
        ? "Commercieel vrijgegeven" : "Niet commercieel vrijgegeven",
      repository: "Repository provisioning nog niet uitgevoerd",
      branch: workspace.default_branch,
      preview: "Preview nog niet beschikbaar",
      production: productionUrl || "Production URL nog niet beschikbaar",
      commit: "Nog geen commit geregistreerd",
      buildResult: "PENDING",
      links: Object.freeze({
        github: null,
        preview: null,
        production: productionUrl,
      }),
    });
  }
  return Object.freeze({
    state: workspace.workspace_state === "REPOSITORY_READY"
        && workspace.capabilities.project_files_read ? "ready" : "repository_unavailable",
    message: workspace.workspace_state === "REPOSITORY_READY"
        && workspace.capabilities.project_files_read ? "" : "Projectbestanden niet beschikbaar.",
    modeLabel: value.mode === "PRE_PROJECT" ? "Voorlopig concept" : "Officieel project",
    briefingLabel: value.briefing_status,
    releaseLabel: value.commercially_released
      ? "Commercieel vrijgegeven" : "Niet commercieel vrijgegeven",
    repository: `${workspace.repository_owner}/${workspace.repository_name}`,
    branch: workspace.preview_branch || workspace.default_branch,
    preview: workspace.preview_url || "Preview nog niet beschikbaar",
    production: productionUrl || "Production URL nog niet beschikbaar",
    commit: workspace.last_commit_sha || "Nog geen commit geregistreerd",
    buildResult: workspace.last_build_result || "UNKNOWN",
    links: Object.freeze({
      github: workspace.repository_navigation_url,
      preview: workspace.preview_url,
      production: productionUrl,
    }),
  });
}

export function websiteRequirementsSummary(value) {
  if (!Object.isFrozen(value) || !Object.isFrozen(value.items) ||
    (value.board !== null && !Object.isFrozen(value.board)) ||
    !Object.isFrozen(value.progress)) {
    throw new Error("UNVALIDATED_WEBSITE_REQUIREMENTS_RESPONSE");
  }
  if (value.empty_state === "NO_BOARD") {
    return Object.freeze({
      state: "NO_BOARD",
      requirements_board_id: null,
      board_revision: null,
      completed: 0,
      total: 0,
      open: 0,
      blocked: 0,
      review_required: false,
    });
  }
  if (value.empty_state === "INTAKE_NOT_ELIGIBLE") {
    return Object.freeze({
      state: "INTAKE_NOT_ELIGIBLE",
      requirements_board_id: null,
      board_revision: null,
      completed: null,
      total: null,
      open: null,
      blocked: null,
      review_required: false,
    });
  }
  const reviewRequired = value.board.sync_state === "REVIEW_REQUIRED";
  return Object.freeze({
    state: reviewRequired ? "REVIEW_REQUIRED" : "READY",
    requirements_board_id: value.board.requirements_board_id,
    board_revision: value.board.revision,
    completed: value.progress.required_completed,
    total: value.progress.required_total,
    open: value.progress.required_open,
    blocked: value.progress.required_blocked,
    review_required: reviewRequired,
  });
}
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REQUIREMENTS_SLOT = /^req-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;
const PROJECT_REQUIREMENTS_SLOT = /^project-req-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;
const STATUSES = new Set(["PENDING", "ACTIVE", "BLOCKED", "COMPLETED"]);
const MODES = new Set(["AUTO", "OPERATOR", "HYBRID", "EXTERNAL"]);
const CATEGORIES = new Set([
  "PAGE", "CONTENT", "DESIGN", "FORM", "SEO", "INTEGRATION", "AUTOMATION",
  "AUTH", "ECOMMERCE", "DOCUMENT_FLOW", "MULTIMEDIA", "TECHNICAL", "OTHER",
]);
const VERIFICATION_RESULTS = new Set(["UNKNOWN", "PASS", "FAIL", "NOT_APPLICABLE"]);
const WEBSITE_PHASES = new Set(["PRE_PROJECT", "OFFICIAL_PROJECT"]);
const WEBSITE_SYNC_STATES = new Set(["CURRENT", "REVIEW_REQUIRED"]);
const WEBSITE_SOURCE_REVIEW_STATES = new Set([
  "CURRENT", "CHANGE_PENDING", "REMOVAL_PENDING", "RETIRED",
]);
const WEBSITE_PERMITTED_ACTIONS = new Set([
  "start_website_requirement",
  "block_website_requirement",
  "complete_website_requirement",
  "reopen_website_requirement",
  "accept_website_requirement_source_change",
  "keep_existing_website_requirement_source",
  "retire_website_requirement_source",
]);
const PERMITTED_ACTIONS = new Set([
  "start_project_requirement",
  "block_project_requirement",
  "complete_project_requirement",
  "reopen_project_requirement",
]);
const FILTERS = new Set(["ALL", "ACTIVE", "OPEN", "COMPLETED"]);
const READINESS_STATES = new Set(["READY", "BLOCKED", "UNKNOWN"]);
const ROOT_KEYS = [
  "contract_version", "quote_request_id", "project_id", "context", "board",
  "items", "empty_state", "readiness", "actions",
];
const CONTEXT_KEYS = ["customer", "dossier_reference", "project_reference", "assigned_operator"];
const BOARD_KEYS = ["requirements_board_id", "status", "revision", "finalized_at"];
const ITEM_KEYS = [
  "requirement_id", "item_number", "title", "description", "category", "source",
  "linked_page_or_module", "status", "completion_mode", "sort_order", "required",
  "started_at", "completed_at", "verification_result", "blocked_reason", "revision",
  "permitted_actions",
];
const SOURCE_KEYS = ["authority_type", "label"];
const READINESS_KEYS = [
  "required_total", "required_completed", "required_open", "required_blocked",
  "active_requirement_id", "active_item_number", "ready_for_preview", "readiness", "reason",
];
const ACTION_KEYS = ["can_create_board", "can_create_item", "can_finalize"];
const ACTION_LABELS = Object.freeze({
  start_project_requirement: "Aan deze taak werken",
  block_project_requirement: "Blokkeren",
  complete_project_requirement: "Afronden",
  reopen_project_requirement: "Heropenen",
});
const STATUS_LABELS = Object.freeze({
  PENDING: "Pending",
  ACTIVE: "Actief",
  BLOCKED: "Geblokkeerd",
  COMPLETED: "Afgerond",
});
const VERIFICATION_LABELS = Object.freeze({
  UNKNOWN: "Verificatie vereist",
  PASS: "Geverifieerd",
  FAIL: "Verificatie afgekeurd",
  NOT_APPLICABLE: "Operatorcontrole",
});

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, keys) {
  return isRecord(value) && Object.keys(value).length === keys.length &&
    keys.every((key) => Object.hasOwn(value, key));
}

function validText(value, minimum, maximum) {
  return typeof value === "string" && value.trim().length >= minimum &&
    value.trim().length <= maximum;
}

function validNullableText(value, maximum) {
  return value === null || validText(value, 1, maximum);
}

function validTimestamp(value) {
  return value === null ||
    (typeof value === "string" && value.length > 0 && Number.isFinite(Date.parse(value)));
}

function fail(code = "INVALID_PROJECT_REQUIREMENTS_RESPONSE") {
  throw new Error(code);
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

function failWebsiteRequest() {
  throw new Error("INVALID_WEBSITE_REQUIREMENTS_REQUEST");
}

function failWebsiteResponse() {
  throw new Error("INVALID_WEBSITE_REQUIREMENTS_RESPONSE");
}

function websiteContextInput(value, extraKeys = []) {
  if (!exactKeys(value, ["quoteRequestId", "websiteWorkContextId", ...extraKeys]) ||
    !UUID.test(String(value.quoteRequestId || "")) ||
    !UUID.test(String(value.websiteWorkContextId || ""))) failWebsiteRequest();
  return {
    quote_request_id: value.quoteRequestId.toLowerCase(),
    website_work_context_id: value.websiteWorkContextId.toLowerCase(),
  };
}

function websiteMutationInput(value, extraKeys = []) {
  const context = websiteContextInput(value, [
    "requirementId", "expectedRevision", "idempotencyKey", ...extraKeys,
  ]);
  if (!UUID.test(String(value.requirementId || "")) ||
    !Number.isSafeInteger(value.expectedRevision) || value.expectedRevision < 1 ||
    !UUID.test(String(value.idempotencyKey || ""))) failWebsiteRequest();
  return {
    ...context,
    requirement_id: value.requirementId.toLowerCase(),
    expected_revision: value.expectedRevision,
    idempotency_key: value.idempotencyKey.toLowerCase(),
  };
}

function boundedWebsiteText(value) {
  const text = typeof value === "string" ? value.trim() : "";
  if (text.length < 1 || text.length > 500) failWebsiteRequest();
  return text;
}

export function websiteRequirementsBoardRequest(value) {
  return Object.freeze({
    action: "get_website_requirements_board",
    ...websiteContextInput(value),
  });
}

export function websiteRequirementsSyncRequest(value) {
  const context = websiteContextInput(value, [
    "expectedBoardRevision", "idempotencyKey",
  ]);
  if (!Number.isSafeInteger(value.expectedBoardRevision) || value.expectedBoardRevision < 0 ||
    !UUID.test(String(value.idempotencyKey || ""))) failWebsiteRequest();
  return Object.freeze({
    action: "sync_website_requirements_from_intake",
    ...context,
    expected_board_revision: value.expectedBoardRevision,
    idempotency_key: value.idempotencyKey.toLowerCase(),
  });
}

function websiteRequirementActionRequest(action, value) {
  return Object.freeze({ action, ...websiteMutationInput(value) });
}

function websiteRequirementReasonRequest(action, value) {
  return Object.freeze({
    action,
    ...websiteMutationInput(value, ["reason"]),
    reason: boundedWebsiteText(value.reason),
  });
}

export function websiteRequirementStartRequest(value) {
  return websiteRequirementActionRequest("start_website_requirement", value);
}

export function websiteRequirementBlockRequest(value) {
  return websiteRequirementReasonRequest("block_website_requirement", value);
}

export function websiteRequirementCompleteRequest(value) {
  const base = websiteMutationInput(value, ["attestation"]);
  if (!exactKeys(value.attestation, ["attestation"])) failWebsiteRequest();
  return deepFreeze({
    action: "complete_website_requirement",
    ...base,
    attestation: { attestation: boundedWebsiteText(value.attestation.attestation) },
  });
}

export function websiteRequirementReopenRequest(value) {
  return websiteRequirementReasonRequest("reopen_website_requirement", value);
}

export function websiteRequirementAcceptSourceChangeRequest(value) {
  return websiteRequirementReasonRequest(
    "accept_website_requirement_source_change",
    value,
  );
}

export function websiteRequirementKeepExistingSourceRequest(value) {
  return websiteRequirementReasonRequest(
    "keep_existing_website_requirement_source",
    value,
  );
}

export function websiteRequirementRetireSourceRequest(value) {
  return websiteRequirementReasonRequest(
    "retire_website_requirement_source",
    value,
  );
}

function validWebsiteCount(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function validateWebsiteExpected(expected, includeRequirement = false) {
  if (!exactKeys(expected, includeRequirement
    ? ["quoteRequestId", "websiteWorkContextId", "requirementId", "action"]
    : ["quoteRequestId", "websiteWorkContextId"]) ||
    !UUID.test(String(expected.quoteRequestId || "")) ||
    !UUID.test(String(expected.websiteWorkContextId || "")) ||
    (includeRequirement && !UUID.test(String(expected.requirementId || "")))) {
    failWebsiteResponse();
  }
}

function validateWebsiteBoardContext(value) {
  if (!exactKeys(value, ["customer", "dossier_reference", "assigned_operator"]) ||
    !validText(value.customer, 1, 200) || !validText(value.dossier_reference, 1, 80)) {
    failWebsiteResponse();
  }
  if (value.assigned_operator !== null &&
    (!exactKeys(value.assigned_operator, ["operator_id", "display_name"]) ||
      !UUID.test(String(value.assigned_operator.operator_id || "")) ||
      !validText(value.assigned_operator.display_name, 1, 160))) failWebsiteResponse();
}

function validateWebsiteBoard(value) {
  if (!exactKeys(value, [
    "requirements_board_id", "sync_state", "revision", "mapping_version",
    "current_intake_id", "current_intake_revision", "current_intake_snapshot_sha256",
  ]) || !UUID.test(String(value.requirements_board_id || "")) ||
    !WEBSITE_SYNC_STATES.has(value.sync_state) ||
    !Number.isSafeInteger(value.revision) || value.revision < 1 ||
    value.mapping_version !== 1 || !UUID.test(String(value.current_intake_id || "")) ||
    !Number.isSafeInteger(value.current_intake_revision) || value.current_intake_revision < 1 ||
    !/^[0-9a-f]{64}$/.test(String(value.current_intake_snapshot_sha256 || ""))) {
    failWebsiteResponse();
  }
}

function validateWebsiteSource(value) {
  if (!exactKeys(value, [
    "authority_type", "source_key", "intake_id", "intake_revision",
    "submitted_at", "mapping_version",
  ]) || value.authority_type !== "WEBSITE_INTAKE" ||
    !validText(value.source_key, 1, 200) || !UUID.test(String(value.intake_id || "")) ||
    !Number.isSafeInteger(value.intake_revision) || value.intake_revision < 1 ||
    !validTimestamp(value.submitted_at) || value.submitted_at === null ||
    value.mapping_version !== 1) failWebsiteResponse();
}

function validateWebsiteItem(value) {
  if (!exactKeys(value, [
    "requirement_id", "item_number", "title", "description", "category", "source",
    "linked_page_or_module", "status", "completion_mode", "sort_order", "required",
    "started_at", "completed_at", "verification_result", "blocked_reason", "revision",
    "source_review_state", "permitted_actions",
  ]) || !UUID.test(String(value.requirement_id || "")) ||
    !Number.isSafeInteger(value.item_number) || value.item_number < 1 ||
    !validText(value.title, 1, 120) || !validText(value.description, 1, 1200) ||
    !CATEGORIES.has(value.category) || !validNullableText(value.linked_page_or_module, 160) ||
    !STATUSES.has(value.status) || !MODES.has(value.completion_mode) ||
    !Number.isSafeInteger(value.sort_order) || value.sort_order < 0 ||
    typeof value.required !== "boolean" || !validTimestamp(value.started_at) ||
    !validTimestamp(value.completed_at) || !VERIFICATION_RESULTS.has(value.verification_result) ||
    !validNullableText(value.blocked_reason, 500) ||
    !Number.isSafeInteger(value.revision) || value.revision < 1 ||
    !WEBSITE_SOURCE_REVIEW_STATES.has(value.source_review_state) ||
    !Array.isArray(value.permitted_actions) ||
    new Set(value.permitted_actions).size !== value.permitted_actions.length ||
    value.permitted_actions.some((action) => !WEBSITE_PERMITTED_ACTIONS.has(action))) {
    failWebsiteResponse();
  }
  validateWebsiteSource(value.source);
}

export function validateWebsiteRequirementsBoard(value, expected) {
  validateWebsiteExpected(expected);
  if (!exactKeys(value, [
    "contract_version", "quote_request_id", "website_work_context_id", "project_id",
    "phase", "context", "board", "items", "progress", "readiness", "empty_state",
  ]) || value.contract_version !== 1 || !UUID.test(String(value.quote_request_id || "")) ||
    !UUID.test(String(value.website_work_context_id || "")) ||
    !WEBSITE_PHASES.has(value.phase) ||
    (value.phase === "PRE_PROJECT" ? value.project_id !== null :
      !UUID.test(String(value.project_id || "")))) failWebsiteResponse();
  if (value.quote_request_id !== expected.quoteRequestId ||
    value.website_work_context_id !== expected.websiteWorkContextId) {
    throw new Error("WEBSITE_REQUIREMENTS_BINDING_MISMATCH");
  }
  validateWebsiteBoardContext(value.context);
  if (!Array.isArray(value.items)) failWebsiteResponse();
  for (const item of value.items) validateWebsiteItem(item);
  if (!exactKeys(value.progress, [
    "required_total", "required_completed", "required_open", "required_blocked",
    "review_pending",
  ]) || Object.values(value.progress).some((count) => !validWebsiteCount(count)) ||
    !exactKeys(value.readiness, ["ready_for_preview", "readiness", "reason"]) ||
    typeof value.readiness.ready_for_preview !== "boolean" ||
    !READINESS_STATES.has(value.readiness.readiness) ||
    !validText(value.readiness.reason, 1, 100)) failWebsiteResponse();
  const progress = value.progress;
  if (progress.required_completed + progress.required_open + progress.required_blocked !==
    progress.required_total) throw new Error("INVALID_WEBSITE_REQUIREMENTS_PROGRESS");
  if (value.board === null) {
    if (!["NO_BOARD", "INTAKE_NOT_ELIGIBLE"].includes(value.empty_state) ||
      value.items.length !== 0 || Object.values(progress).some((count) => count !== 0)) {
      failWebsiteResponse();
    }
  } else {
    validateWebsiteBoard(value.board);
    if (value.empty_state !== null) failWebsiteResponse();
  }
  return deepFreeze(structuredClone(value));
}

export function validateWebsiteRequirementsSyncResult(value, expected) {
  validateWebsiteExpected(expected);
  const countKeys = [
    "created", "updated", "unchanged", "retired", "change_pending",
    "removal_pending", "revived",
  ];
  if (!exactKeys(value, [
    "contract_version", "outcome", "quote_request_id", "website_work_context_id",
    "requirements_board_id", "board_revision", "intake_id", "intake_revision",
    "intake_sha256", "mapping_version", "sync_run_id", "replayed",
    "review_required", "counts",
  ]) || value.contract_version !== 1 || value.mapping_version !== 1 ||
    !["SYNCED", "REPLAYED", "REVIEW_REQUIRED"].includes(value.outcome) ||
    !UUID.test(String(value.requirements_board_id || "")) ||
    !Number.isSafeInteger(value.board_revision) || value.board_revision < 1 ||
    !UUID.test(String(value.intake_id || "")) ||
    !Number.isSafeInteger(value.intake_revision) || value.intake_revision < 1 ||
    !/^[0-9a-f]{64}$/.test(String(value.intake_sha256 || "")) ||
    !UUID.test(String(value.sync_run_id || "")) || typeof value.replayed !== "boolean" ||
    typeof value.review_required !== "boolean" || !exactKeys(value.counts, countKeys) ||
    Object.values(value.counts).some((count) => !validWebsiteCount(count)) ||
    (value.outcome === "SYNCED" && (value.replayed || value.review_required)) ||
    (value.outcome === "REPLAYED" && (!value.replayed || value.review_required)) ||
    (value.outcome === "REVIEW_REQUIRED" && (value.replayed || !value.review_required))) {
    failWebsiteResponse();
  }
  if (value.quote_request_id !== expected.quoteRequestId ||
    value.website_work_context_id !== expected.websiteWorkContextId) {
    throw new Error("WEBSITE_REQUIREMENTS_BINDING_MISMATCH");
  }
  return deepFreeze(structuredClone(value));
}

export function validateWebsiteRequirementMutationResult(value, expected) {
  validateWebsiteExpected(expected, true);
  const command = expected.action === "accept_website_requirement_source_change"
    ? ["RESOLVE_SOURCE", "ACCEPT_CHANGE"]
    : expected.action === "keep_existing_website_requirement_source"
    ? ["RESOLVE_SOURCE", "KEEP_EXISTING"]
    : expected.action === "retire_website_requirement_source"
    ? ["RESOLVE_SOURCE", "RETIRE"]
    : expected.action === "start_website_requirement"
    ? ["START", null]
    : expected.action === "block_website_requirement"
    ? ["BLOCK", null]
    : expected.action === "complete_website_requirement"
    ? ["COMPLETE", null]
    : expected.action === "reopen_website_requirement"
    ? ["REOPEN", null]
    : null;
  if (!command || !exactKeys(value, [
    "contract_version", "command", "quote_request_id", "website_work_context_id",
    "requirements_board_id", "requirement_id", "previous_status", "status",
    "previous_source_review_state", "source_review_state", "resolution",
    "requirement_revision", "board_revision", "replayed",
  ]) || value.contract_version !== 1 || value.command !== command[0] ||
    value.resolution !== command[1] || !UUID.test(String(value.requirements_board_id || "")) ||
    !STATUSES.has(value.previous_status) || !STATUSES.has(value.status) ||
    !WEBSITE_SOURCE_REVIEW_STATES.has(value.previous_source_review_state) ||
    !WEBSITE_SOURCE_REVIEW_STATES.has(value.source_review_state) ||
    !Number.isSafeInteger(value.requirement_revision) || value.requirement_revision < 1 ||
    !Number.isSafeInteger(value.board_revision) || value.board_revision < 1 ||
    typeof value.replayed !== "boolean") failWebsiteResponse();
  if (value.quote_request_id !== expected.quoteRequestId ||
    value.website_work_context_id !== expected.websiteWorkContextId ||
    value.requirement_id !== expected.requirementId) {
    throw new Error("WEBSITE_REQUIREMENTS_BINDING_MISMATCH");
  }
  return deepFreeze(structuredClone(value));
}

export function createWebsiteRequirementMutationIntent(
  builder,
  builderArguments,
  randomUUID = crypto.randomUUID,
) {
  if (typeof builder !== "function" || !isRecord(builderArguments) ||
    Object.hasOwn(builderArguments, "idempotencyKey") || typeof randomUUID !== "function") {
    failWebsiteRequest();
  }
  const idempotencyKey = randomUUID();
  if (!UUID.test(String(idempotencyKey || ""))) failWebsiteRequest();
  const request = builder({ ...builderArguments, idempotencyKey });
  if (!Object.isFrozen(request)) failWebsiteRequest();
  return Object.freeze({ idempotencyKey, request });
}

function validateContext(value, projectId) {
  if (!exactKeys(value, CONTEXT_KEYS) ||
    !validText(value.customer, 1, 200) ||
    (value.dossier_reference !== null && !validText(value.dossier_reference, 1, 80)) ||
    value.project_reference !== projectId) fail();
  if (value.assigned_operator !== null &&
    (!exactKeys(value.assigned_operator, ["operator_id", "display_name"]) ||
      !UUID.test(String(value.assigned_operator.operator_id || "")) ||
      !validText(value.assigned_operator.display_name, 1, 160))) fail();
}

function validateBoard(value) {
  if (!exactKeys(value, BOARD_KEYS) ||
    !UUID.test(String(value.requirements_board_id || "")) ||
    !new Set(["DRAFT", "FINALIZED"]).has(value.status) ||
    !Number.isSafeInteger(value.revision) || value.revision < 1 ||
    !validTimestamp(value.finalized_at) ||
    (value.status === "DRAFT" && value.finalized_at !== null) ||
    (value.status === "FINALIZED" && value.finalized_at === null)) fail();
}

function validateItem(value) {
  if (!exactKeys(value, ITEM_KEYS) ||
    !UUID.test(String(value.requirement_id || "")) ||
    !Number.isSafeInteger(value.item_number) || value.item_number < 1 || value.item_number > 99 ||
    !validText(value.title, 1, 120) || !validText(value.description, 1, 1200) ||
    !CATEGORIES.has(value.category) || !exactKeys(value.source, SOURCE_KEYS) ||
    !new Set(["ACCEPTED_PROJECT_SCOPE", "ACCEPTED_LINE_ITEM"]).has(value.source.authority_type) ||
    !validText(value.source.label, 1, 160) || !validNullableText(value.linked_page_or_module, 160) ||
    !STATUSES.has(value.status) || !MODES.has(value.completion_mode) ||
    !Number.isSafeInteger(value.sort_order) || value.sort_order < 1 ||
    typeof value.required !== "boolean" || !validTimestamp(value.started_at) ||
    !validTimestamp(value.completed_at) || !VERIFICATION_RESULTS.has(value.verification_result) ||
    !validNullableText(value.blocked_reason, 500) ||
    !Number.isSafeInteger(value.revision) || value.revision < 1 ||
    !Array.isArray(value.permitted_actions)) fail();

  if (value.status === "BLOCKED" ? value.blocked_reason === null : value.blocked_reason !== null) fail();
  if (value.status === "COMPLETED" ? value.completed_at === null : value.completed_at !== null) fail();
  if (value.status === "ACTIVE" && value.started_at === null) fail();
  const uniqueActions = new Set(value.permitted_actions);
  if (uniqueActions.size !== value.permitted_actions.length ||
    value.permitted_actions.some((action) => !PERMITTED_ACTIONS.has(action))) {
    fail("INVALID_PROJECT_REQUIREMENTS_ACTIONS");
  }
}

function validateReadiness(value, items, board) {
  if (!exactKeys(value, READINESS_KEYS) ||
    [value.required_total, value.required_completed, value.required_open, value.required_blocked]
      .some((count) => !Number.isSafeInteger(count) || count < 0) ||
    typeof value.ready_for_preview !== "boolean" ||
    !READINESS_STATES.has(value.readiness) || !validText(value.reason, 1, 100) ||
    (value.active_requirement_id !== null && !UUID.test(String(value.active_requirement_id))) ||
    (value.active_item_number !== null &&
      (!Number.isSafeInteger(value.active_item_number) || value.active_item_number < 1))) {
    fail("INVALID_PROJECT_REQUIREMENTS_PROGRESS");
  }

  const requiredItems = items.filter((item) => item.required);
  const activeItems = items.filter((item) => item.status === "ACTIVE");
  const completed = requiredItems.filter((item) => item.status === "COMPLETED").length;
  const open = requiredItems.filter((item) => item.status === "PENDING" || item.status === "ACTIVE").length;
  const blocked = requiredItems.filter((item) => item.status === "BLOCKED").length;
  const active = activeItems[0] || null;
  if (requiredItems.length !== value.required_total || completed !== value.required_completed ||
    open !== value.required_open || blocked !== value.required_blocked ||
    completed + open + blocked !== value.required_total || activeItems.length > 1 ||
    (active?.requirement_id || null) !== value.active_requirement_id ||
    (active?.item_number || null) !== value.active_item_number ||
    (value.ready_for_preview &&
      (board?.status !== "FINALIZED" || value.required_total === 0 ||
        completed !== value.required_total || value.readiness !== "READY")) ||
    (!value.ready_for_preview && value.readiness === "READY")) {
    fail("INVALID_PROJECT_REQUIREMENTS_PROGRESS");
  }
}

export function requirementsBoardSlot(quoteRequestId) {
  if (!UUID.test(String(quoteRequestId || ""))) fail("INVALID_REQUIREMENTS_BOARD_SLOT");
  return `req-${String(quoteRequestId).toLowerCase()}`;
}

export function quoteRequestIdFromRequirementsBoardSlot(slotKey) {
  return REQUIREMENTS_SLOT.exec(String(slotKey || ""))?.[1]?.toLowerCase() || null;
}

export function projectRequirementsBoardSlot(quoteRequestId) {
  if (!UUID.test(String(quoteRequestId || ""))) {
    fail("INVALID_PROJECT_REQUIREMENTS_BOARD_SLOT");
  }
  return `project-req-${String(quoteRequestId).toLowerCase()}`;
}

export function quoteRequestIdFromProjectRequirementsBoardSlot(slotKey) {
  return PROJECT_REQUIREMENTS_SLOT.exec(String(slotKey || ""))?.[1]?.toLowerCase() || null;
}

export function requirementsInvalidationMatches(slotKey, expectedQuoteRequestId) {
  const value = String(slotKey || "");
  if (!value.startsWith("req-")) return true;
  return quoteRequestIdFromRequirementsBoardSlot(value) ===
    String(expectedQuoteRequestId || "").toLowerCase();
}

export function projectRequirementsInvalidationMatches(slotKey, expectedQuoteRequestId) {
  const value = String(slotKey || "");
  if (!value.startsWith("project-req-")) return true;
  return quoteRequestIdFromProjectRequirementsBoardSlot(value) ===
    String(expectedQuoteRequestId || "").toLowerCase();
}

export function projectRequirementsRequest(context) {
  const quoteRequestId = String(context?.quoteRequestId || "");
  const projectId = String(context?.projectId || "");
  if (!UUID.test(quoteRequestId) || !UUID.test(projectId)) {
    fail("INVALID_PROJECT_REQUIREMENTS_CONTEXT");
  }
  return Object.freeze({
    action: "get_project_requirements_board",
    quote_request_id: quoteRequestId.toLowerCase(),
    project_id: projectId.toLowerCase(),
  });
}

export function validateProjectRequirementsBoard(value, expected) {
  if (!exactKeys(value, ROOT_KEYS) || value.contract_version !== 1 ||
    !UUID.test(String(value.quote_request_id || "")) ||
    !UUID.test(String(value.project_id || ""))) fail();
  if (value.quote_request_id !== expected?.quoteRequestId || value.project_id !== expected?.projectId) {
    fail("PROJECT_REQUIREMENTS_BINDING_MISMATCH");
  }
  validateContext(value.context, value.project_id);
  if (!Array.isArray(value.items) || !exactKeys(value.actions, ACTION_KEYS) ||
    ACTION_KEYS.some((key) => typeof value.actions[key] !== "boolean")) fail();
  for (const item of value.items) validateItem(item);

  const identities = new Set(value.items.map((item) => item.requirement_id));
  const itemNumbers = value.items.map((item) => item.item_number);
  const sortOrders = value.items.map((item) => item.sort_order);
  if (identities.size !== value.items.length ||
    itemNumbers.some((number, index) => number !== index + 1) ||
    sortOrders.some((number, index) => index > 0 && number <= sortOrders[index - 1])) {
    fail("INVALID_PROJECT_REQUIREMENTS_ORDER");
  }

  if (value.board === null) {
    if (value.empty_state !== "NO_BOARD" || value.items.length !== 0 ||
      value.actions.can_create_item || value.actions.can_finalize) fail();
  } else {
    validateBoard(value.board);
    if (value.empty_state !== null) fail();
  }
  validateReadiness(value.readiness, value.items, value.board);
  return deepFreeze(structuredClone(value));
}

function cardFromRequirement(item) {
  return deepFreeze({
    requirementId: item.requirement_id,
    revision: item.revision,
    number: String(item.item_number).padStart(2, "0"),
    itemNumber: item.item_number,
    title: item.title,
    description: item.description,
    category: item.category,
    status: item.status,
    statusClass: item.status.toLowerCase(),
    statusLabel: STATUS_LABELS[item.status],
    completionMode: item.completion_mode,
    requiredLabel: item.required ? "Verplicht" : "Optioneel",
    source: { ...item.source },
    linkedPageOrModule: item.linked_page_or_module,
    verificationResult: item.verification_result,
    verificationLabel: VERIFICATION_LABELS[item.verification_result],
    blockedReason: item.blocked_reason,
    actions: item.permitted_actions.map((action) => ({
      action,
      label: ACTION_LABELS[action],
    })),
  });
}

export function projectRequirementsView(projection) {
  if (!Object.isFrozen(projection)) fail("UNVALIDATED_PROJECT_REQUIREMENTS_RESPONSE");
  const context = Object.freeze({
    customer: projection.context.customer,
    dossier: projection.context.dossier_reference || "Niet beschikbaar",
    project: projection.context.project_reference,
    operator: projection.context.assigned_operator?.display_name || "Niet toegewezen",
  });
  if (projection.board === null) {
    return deepFreeze({
      state: "empty",
      heading: "PROJECTVEREISTEN",
      message: "Nog geen projectvereisten beschikbaar.",
      context,
      progress: null,
      cards: [],
    });
  }
  return deepFreeze({
    state: projection.board.status === "DRAFT" ? "draft" : "ready",
    heading: "PROJECTVEREISTEN",
    message: null,
    context,
    progress: {
      value: `${String(projection.readiness.required_completed).padStart(2, "0")} / ${String(projection.readiness.required_total).padStart(2, "0")}`,
      label: "VEREISTEN AFGEROND",
      active: projection.items.filter((item) => item.status === "ACTIVE").length,
      open: projection.readiness.required_open,
      blocked: projection.readiness.required_blocked,
    },
    cards: projection.items.map(cardFromRequirement),
  });
}

export function projectRequirementsSummary(value, expected) {
  const projection = validateProjectRequirementsBoard(value, expected);
  if (projection.board === null) {
    return deepFreeze({
      state: "empty",
      heading: "PROJECTVEREISTEN",
      message: "Nog geen projectvereisten beschikbaar.",
    });
  }
  return deepFreeze({
    state: "ready",
    heading: "PROJECTVEREISTEN",
    completed: projection.readiness.required_completed,
    total: projection.readiness.required_total,
    open: projection.readiness.required_open,
    blocked: projection.readiness.required_blocked,
    readyForPreview: projection.readiness.ready_for_preview,
    progress: `${String(projection.readiness.required_completed).padStart(2, "0")} / ${String(projection.readiness.required_total).padStart(2, "0")}`,
  });
}

export function filterProjectRequirements(items, filter) {
  if (!Array.isArray(items) || !FILTERS.has(filter)) fail("INVALID_PROJECT_REQUIREMENTS_FILTER");
  const filtered = filter === "ALL"
    ? items
    : filter === "ACTIVE"
    ? items.filter((item) => item.status === "ACTIVE")
    : filter === "OPEN"
    ? items.filter((item) => ["PENDING", "ACTIVE", "BLOCKED"].includes(item.status))
    : items.filter((item) => item.status === "COMPLETED");
  return Object.freeze([...filtered]);
}

export function buildProjectRequirementAction(
  context,
  requirement,
  action,
  idempotencyKey,
  details = {},
) {
  const quoteRequestId = String(context?.quoteRequestId || "");
  const projectId = String(context?.projectId || "");
  if (!UUID.test(quoteRequestId) || !UUID.test(projectId) ||
    !UUID.test(String(requirement?.requirement_id || "")) ||
    !Number.isSafeInteger(requirement?.revision) || requirement.revision < 1 ||
    !UUID.test(String(idempotencyKey || "")) || !PERMITTED_ACTIONS.has(action)) {
    fail("INVALID_PROJECT_REQUIREMENT_ACTION");
  }
  if (!Array.isArray(requirement.permitted_actions) ||
    !requirement.permitted_actions.includes(action)) {
    fail("PROJECT_REQUIREMENT_ACTION_NOT_PERMITTED");
  }
  const base = {
    action,
    quote_request_id: quoteRequestId,
    project_id: projectId,
    requirement_id: requirement.requirement_id,
    expected_revision: requirement.revision,
    idempotency_key: idempotencyKey,
  };
  if (action === "start_project_requirement") {
    if (Object.keys(details).length !== 0) fail("INVALID_PROJECT_REQUIREMENT_ACTION");
    return deepFreeze(base);
  }
  if (!exactKeys(details, action === "complete_project_requirement" ? ["attestation"] : ["reason"])) {
    fail("INVALID_PROJECT_REQUIREMENT_ACTION");
  }
  if (action === "complete_project_requirement") {
    const attestation = typeof details.attestation === "string" ? details.attestation.trim() : "";
    if (attestation.length < 1 || attestation.length > 500) fail("INVALID_PROJECT_REQUIREMENT_ACTION");
    return deepFreeze({ ...base, evidence_reference: { attestation } });
  }
  const reason = typeof details.reason === "string" ? details.reason.trim() : "";
  if (reason.length < 1 || reason.length > 500) fail("INVALID_PROJECT_REQUIREMENT_ACTION");
  return deepFreeze({ ...base, reason });
}

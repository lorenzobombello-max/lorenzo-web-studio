const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REQUIREMENTS_SLOT = /^req-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;
const STATUSES = new Set(["PENDING", "ACTIVE", "BLOCKED", "COMPLETED"]);
const MODES = new Set(["AUTO", "OPERATOR", "HYBRID", "EXTERNAL"]);
const CATEGORIES = new Set([
  "PAGE", "CONTENT", "DESIGN", "FORM", "SEO", "INTEGRATION", "AUTOMATION",
  "AUTH", "ECOMMERCE", "DOCUMENT_FLOW", "MULTIMEDIA", "TECHNICAL", "OTHER",
]);
const VERIFICATION_RESULTS = new Set(["UNKNOWN", "PASS", "FAIL", "NOT_APPLICABLE"]);
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

export function requirementsInvalidationMatches(slotKey, expectedQuoteRequestId) {
  const value = String(slotKey || "");
  if (!value.startsWith("req-")) return true;
  return quoteRequestIdFromRequirementsBoardSlot(value) ===
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

import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";

const MAX_BODY_BYTES = 16 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const COMMANDS = new Set([
  "prepare_milestone_1",
  "record_payment_evidence",
  "reconcile_payment",
  "confirm_payment",
  "release_project",
  "record_preview_ready",
  "activate_preview_access",
  "revoke_preview_access",
  "classify_feedback",
  "create_revision",
  "mark_revision_ready",
  "create_preview_version",
  "require_change_order",
  "authorize_final_transfer",
  "record_delivery",
  "archive_project"
]);
const APPLICATION_ACTIONS = new Set([
  "get_current_operator_identity",
  "upsert_quotation_business_draft",
  "promote_quotation_business_draft_to_approval",
  "issue_and_deliver_approved_quotation",
  "list_applications",
  "list_applications_v2",
  "list_pending_intakes",
  "count_pending_intakes",
  "archive_pending_intake",
  "restore_pending_intake",
  "permanently_delete_pending_intake",
  "get_application_facets_v2",
  "get_application_detail",
  "get_assignment_operator_roster",
  "get_dossier_assignment",
  "get_my_assigned_dossiers",
  "get_dossier_document_manifest",
  "create_dossier_document_access",
  "list_customer_requests_for_dossier",
  "get_customer_request",
  "transition_customer_request",
  "create_customer_request_upload_link",
  "revoke_customer_request_upload_link",
  "assign_dossier",
  "get_project_dossier",
  "promote_accepted_application",
  "create_internal_e2e_run",
  "create_customer_request_smoke_fixture",
  "cleanup_internal_e2e_accepted_file",
  "finalize_internal_e2e_run",
  "interrupt_intake",
  "resume_intake",
  "cancel_intake",
  "reactivate_intake",
  "archive_dossier",
  "reactivate_dossier",
  "trash_dossier",
  "restore_dossier",
  "bind_project_site",
  "rotate_project_site"
]);
const OPERATOR_ZONES = new Set(["ACTIVE", "ARCHIVED", "TRASHED", "ACTIVE_ARCHIVED"]);
const OPERATOR_STATUSES = new Set([
  "CANCELLED", "SUBMITTED", "REVIEWED", "QUOTE_ACCEPTED",
  "M1_PAYMENT_PENDING", "M1_PAYMENT_RECEIVED", "PROJECT_RELEASED",
  "PREVIEW_READY", "M2_PAYMENT_RECEIVED", "FINAL_APPROVAL_RECORDED",
  "FULL_PAYMENT_RECEIVED", "FINAL_TRANSFER_AUTHORIZED", "DELIVERED", "ARCHIVED"
]);
const INTAKE_LIFECYCLE_ACTIONS = new Map([
  ["interrupt_intake", "INTERRUPTED"],
  ["resume_intake", "RESUMED"],
  ["cancel_intake", "CANCELLED"],
  ["reactivate_intake", "REACTIVATED"]
]);
const PENDING_INTAKE_RETENTION_ACTIONS = new Map([
  ["archive_pending_intake", "ARCHIVED"],
  ["restore_pending_intake", "RESTORED"],
]);
const DOSSIER_LIFECYCLE_ACTIONS = new Map([
  ["archive_dossier", "ARCHIVED"],
  ["reactivate_dossier", "REACTIVATED"],
  ["trash_dossier", "TRASHED"],
  ["restore_dossier", "RESTORED"]
]);
const PROJECT_SITE_ACTIONS = new Map([
  ["bind_project_site", "INITIAL_BIND"],
  ["rotate_project_site", "ROTATION"]
]);
const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;
const SUPPORT_REFERENCE = /^#?[0-9A-F]{8}$/i;
const CANONICAL_DOMAIN = /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
const CUSTOMER_REQUEST_WORK_COMMANDS = new Set(["START", "REQUIRE_CUSTOMER_RESPONSE", "RESUME"]);
type DossierLifecycleRpcResult = Readonly<{
  data: unknown;
  error: Readonly<{ message: string }> | null;
}>;
type DossierLifecycleRpcCall = (
  args: Record<string, unknown>
)=>PromiseLike<DossierLifecycleRpcResult>;
type DossierAssignmentRpcClient = Readonly<{
  rpc: (name: string, args: Record<string, unknown>)=>PromiseLike<DossierLifecycleRpcResult>;
}>;
type AssignmentRosterRow = Readonly<{
  operator_id?: unknown;
  display_name?: unknown;
  role?: unknown;
  status?: unknown;
}>;
type DossierAssignmentReadInput = Readonly<{
  action: "get_dossier_assignment";
  dossier_reference: string;
}>;
type DossierAssignmentMutationInput = Readonly<{
  action: "assign_dossier";
  dossier_reference: string;
  assignee_operator_id: string;
  expected_revision: number;
  idempotency_key: string;
  reason: string | null;
}>;
type OperatorPersonalQueueInput = Readonly<{
  action: "get_my_assigned_dossiers";
  cursor: string | null;
  limit: number;
}>;
type CurrentOperatorIdentity = Readonly<{
  display_name: string;
  role: "owner" | "operations_manager" | "operator" | "reviewer" | "read_only" | "admin";
  status: "ACTIVE";
}>;
export type CustomerRequestActionInput = Readonly<{
  action: "list_customer_requests_for_dossier";
  dossier_reference: string;
  cursor: string | null;
  limit: number;
}> | Readonly<{
  action: "get_customer_request";
  request_id: string;
}> | Readonly<{
  action: "transition_customer_request";
  request_id: string;
  command_type: "START" | "REQUIRE_CUSTOMER_RESPONSE" | "RESUME";
  expected_revision: number;
  idempotency_key: string;
}>;
export type CustomerRequestUploadOperatorActionInput = Readonly<{
  action: "create_customer_request_upload_link";
  request_id: string;
  idempotency_key: string;
}> | Readonly<{
  action: "revoke_customer_request_upload_link";
  upload_request_id: string;
  reason: string;
  idempotency_key: string;
}>;
export type InternalE2EAcceptedFileCleanupActionInput = Readonly<{
  action: "cleanup_internal_e2e_accepted_file";
  run_id: string;
  request_id: string;
  upload_request_id: string;
  uploaded_file_id: string;
  idempotency_key: string;
}>;
export type QuotationIssuanceActionInput = Readonly<{
  action: "issue_and_deliver_approved_quotation";
  quote_request_id: string;
}>;
export type DossierDocumentActionInput = Readonly<{
  action: "get_dossier_document_manifest";
  quote_request_id: string;
}> | Readonly<{
  action: "create_dossier_document_access";
  quote_request_id: string;
  source_type: "QUOTATION_ARTIFACT" | "CUSTOMER_UPLOAD";
  document_id: string;
}>;
type DossierLifecycleTransportInput = Readonly<{
  quote_request_id: string;
  event_type: string;
  expected_revision: number;
  idempotency_key: string;
  reason: string;
}>;
type UnvalidatedInput = Record<string, unknown> & Readonly<{
  action?: string;
  expected_revision?: number | null;
  limit?: number | null;
  offset?: number | null;
  year?: number | null;
  quarter?: string | null;
  zone?: string | null;
  operational_status?: string | null;
  request_kind?: string | null;
  ttl_minutes?: number | null;
  search?: unknown;
  cursor?: string | null;
  reason?: unknown;
  payload?: unknown;
  input?: unknown;
}>;
export type QuotationBusinessDraftActionInput = Readonly<{
  action: "upsert_quotation_business_draft";
  intake_id: string;
  expected_revision: number;
  idempotency_key: string;
  input: Record<string, unknown>;
}>;
export type QuotationBusinessApprovalPromotionActionInput = Readonly<{
  action: "promote_quotation_business_draft_to_approval";
  intake_id: string;
  expected_revision: number;
  idempotency_key: string;
}>;
type CommercialCommandInput = Readonly<{
  project_id: string;
  idempotency_key: string;
  command_type: string;
  expected_state: string;
  expected_revision: number;
  payload: Record<string, unknown>;
}>;
type OperatorListCoreResult = Readonly<{
  items: unknown[];
  has_more: boolean;
  next_position: Record<string, string> | null;
}>;
type CommercialOperatorDependencies = Readonly<{
  now(): number;
  verifyUser(jwt: string): PromiseLike<Readonly<{ id: string }> | null>;
  authorizeApplicationReader(jwt: string): PromiseLike<unknown>;
  verifyOperatorCursor(cursor: string, input: Record<string, unknown>): PromiseLike<unknown>;
  executeApplicationListV2(actorAuthUserId: string, input: Record<string, unknown>, position: unknown): PromiseLike<OperatorListCoreResult>;
  executePendingIntakes(
    actorAuthUserId: string,
    retentionState: string,
  ): PromiseLike<unknown>;
  executePendingIntakeCount(actorAuthUserId: string): PromiseLike<unknown>;
  signOperatorCursor(position: Record<string, string>, input: Record<string, unknown>): PromiseLike<string>;
  executeApplicationFacetsV2(actorAuthUserId: string, input: Record<string, unknown>): PromiseLike<unknown>;
  executeApplicationAction(jwt: string, input: Record<string, unknown>, actorAuthUserId: string): PromiseLike<unknown>;
  consumeRateLimit(jwt: string, projectId: string): PromiseLike<Readonly<{ allowed: boolean; retry_after_seconds: number }>>;
  executeCommand(jwt: string, input: CommercialCommandInput): PromiseLike<unknown>;
}>;
const FORBIDDEN_IDENTITY_FIELDS = new Set([
  "p_actor",
  "actor",
  "actor_id",
  "operator_id",
  "operator_role",
  "name",
  "email"
]);
class RequestError extends Error {
  status;
  code;
  constructor(status: number, code: string){
    super(code);
    this.status = status;
    this.code = code;
  }
}
function response(status: number, code: string, extra: Record<string, unknown> = {}) {
  return new Response(JSON.stringify({
    ok: status < 400,
    code,
    ...extra
  }), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer"
    }
  });
}
function bearer(request: Request): string {
  const match = (request.headers.get("authorization") || "").match(/^Bearer\s+([^\s]+)$/i);
  if (!match) throw new RequestError(401, "AUTHENTICATION_REQUIRED");
  return match[1];
}
function decodeClaims(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) throw new RequestError(401, "INVALID_JWT");
  try {
    const value = parts[1].replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(parts[1].length / 4) * 4, "=");
    return JSON.parse(atob(value));
  } catch  {
    throw new RequestError(401, "INVALID_JWT");
  }
}
async function body(request: Request): Promise<UnvalidatedInput> {
  if ((request.headers.get("content-type") || "").split(";", 1)[0].trim().toLowerCase() !== "application/json") throw new RequestError(415, "UNSUPPORTED_CONTENT_TYPE");
  const declared = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) throw new RequestError(413, "BODY_TOO_LARGE");
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) throw new RequestError(413, "BODY_TOO_LARGE");
  try {
    const parsed: unknown = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw 0;
    return parsed as UnvalidatedInput;
  } catch  {
    throw new RequestError(400, "INVALID_JSON");
  }
}
function validate(value: UnvalidatedInput): CommercialCommandInput {
  for (const key of FORBIDDEN_IDENTITY_FIELDS)if (key in value) throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
  if (!UUID.test(String(value.project_id || "")) || !UUID.test(String(value.idempotency_key || ""))) throw new RequestError(400, "INVALID_REQUEST");
  if (!COMMANDS.has(String(value.command_type || "")) || typeof value.expected_state !== "string" || !Number.isSafeInteger(value.expected_revision) || Number(value.expected_revision) < 0) throw new RequestError(400, "INVALID_REQUEST");
  if (!value.payload || typeof value.payload !== "object" || Array.isArray(value.payload)) throw new RequestError(400, "INVALID_REQUEST");
  for (const key of FORBIDDEN_IDENTITY_FIELDS)if (key in value.payload) throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
  return value as UnvalidatedInput & CommercialCommandInput;
}
function normalizeDossierReference(value: unknown) {
  const reference = typeof value === "string" ? value.trim().toUpperCase() : "";
  if (APPLICATION_REFERENCE.test(reference)) return reference;
  if (SUPPORT_REFERENCE.test(reference)) return `#${reference.replace(/^#/, "")}`;
  throw new RequestError(400, "INVALID_REQUEST");
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every((key)=>key in value);
}
function validatePendingIntakesResult(value: unknown) {
  const fields = [
    "quote_request_id",
    "intake_id",
    "name",
    "organization",
    "email",
    "phone",
    "request_kind",
    "website_type",
    "invitation_created_at",
    "invitation_sent_at",
    "intake_status",
    "effective_access",
    "access_token_expires_at",
    "lifecycle_revision",
    "retention_state",
    "archived_at",
    "retention_revision",
    "can_permanently_delete",
    "delete_block_reason",
  ];
  if (
    !isRecord(value) || !hasExactKeys(value, ["items"]) ||
    !Array.isArray(value.items)
  ) {
    throw new Error("INVALID_PENDING_INTAKES_RESPONSE");
  }
  for (const item of value.items) {
    if (
      !isRecord(item) || !hasExactKeys(item, fields) ||
      !UUID.test(String(item.quote_request_id || "")) ||
      !UUID.test(String(item.intake_id || "")) ||
      typeof item.name !== "string" || !item.name ||
      (item.organization !== null && typeof item.organization !== "string") ||
      typeof item.email !== "string" || !item.email ||
      (item.phone !== null && typeof item.phone !== "string") ||
      item.request_kind !== "website" ||
      typeof item.website_type !== "string" || !item.website_type ||
      typeof item.invitation_created_at !== "string" ||
      !item.invitation_created_at ||
      (item.invitation_sent_at !== null &&
        typeof item.invitation_sent_at !== "string") ||
      !["invited", "in_progress"].includes(String(item.intake_status)) ||
      !["ACTIVE", "INTERRUPTED", "EXPIRED", "CANCELLED"].includes(
        String(item.effective_access),
      ) ||
      typeof item.access_token_expires_at !== "string" ||
      !item.access_token_expires_at ||
      !Number.isSafeInteger(item.lifecycle_revision) ||
      Number(item.lifecycle_revision) < 0 ||
      !["ACTIVE", "ARCHIVED"].includes(String(item.retention_state)) ||
      (item.archived_at !== null && typeof item.archived_at !== "string") ||
      !Number.isSafeInteger(item.retention_revision) ||
      Number(item.retention_revision) < 0 ||
      typeof item.can_permanently_delete !== "boolean" ||
      (item.delete_block_reason !== null &&
        ![
          "NOT_FOUND",
          "INTAKE_SUBMITTED",
          "COMMERCIAL_FOLLOW_UP_EXISTS",
          "QUOTATION_EXISTS",
          "PROJECT_EXISTS",
          "INVOICE_EXISTS",
          "CUSTOMER_REQUEST_EXISTS",
          "FINANCIAL_DEPENDENCY_EXISTS",
        ].includes(String(item.delete_block_reason)))
    ) {
      throw new Error("INVALID_PENDING_INTAKES_RESPONSE");
    }
  }
  return value as { items: Record<string, unknown>[] };
}
function validatePendingIntakeCountResult(value: unknown) {
  if (
    !isRecord(value) || !hasExactKeys(value, ["active_count"]) ||
    !Number.isSafeInteger(value.active_count) || Number(value.active_count) < 0
  ) {
    throw new Error("INVALID_PENDING_INTAKE_COUNT_RESPONSE");
  }
  return value as { active_count: number };
}
function validateQuotationBusinessInput(value: unknown): Record<string, unknown> {
  const keys = [
    "commercial_lines", "discount", "scope", "payment_schedule", "validity_days"
  ];
  if (!isRecord(value) || !hasExactKeys(value, keys)
    || !Array.isArray(value.commercial_lines) || value.commercial_lines.length < 1
    || !isRecord(value.discount) || !isRecord(value.scope)
    || !isRecord(value.payment_schedule)) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  const lineKeys = ["rule_id", "quantity", "description_context"];
  if (value.commercial_lines.some((line)=>!isRecord(line) || !hasExactKeys(line, lineKeys)
    || typeof line.rule_id !== "string" || line.rule_id.trim().length < 1 || line.rule_id.length > 200
    || typeof line.quantity !== "number" || !Number.isFinite(line.quantity) || line.quantity <= 0
    || typeof line.description_context !== "string" || line.description_context.trim().length < 1
    || line.description_context.length > 2000)) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  if (!hasExactKeys(value.discount, ["discount_type", "discount_value_minor", "discount_reason"])
    || !Number.isSafeInteger(value.discount.discount_value_minor)
    || Number(value.discount.discount_value_minor) < 0
    || (value.discount.discount_type !== null && typeof value.discount.discount_type !== "string")
    || (value.discount.discount_reason !== null && typeof value.discount.discount_reason !== "string")
    || (Number(value.discount.discount_value_minor) > 0
      && (typeof value.discount.discount_type !== "string" || value.discount.discount_type.trim().length < 1
        || typeof value.discount.discount_reason !== "string" || value.discount.discount_reason.trim().length < 1))) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  const scopeKeys = [
    "project_title", "project_type", "scope_summary", "requested_languages",
    "included_page_count", "features", "copywriting", "seo", "hosting",
    "maintenance", "exclusions", "assumptions", "indicative_timing"
  ];
  if (!hasExactKeys(value.scope, scopeKeys)
    || typeof value.scope.project_title !== "string" || value.scope.project_title.trim().length < 1
    || typeof value.scope.project_type !== "string" || value.scope.project_type.trim().length < 1
    || typeof value.scope.scope_summary !== "string" || value.scope.scope_summary.trim().length < 1
    || !Array.isArray(value.scope.requested_languages)
    || !Number.isSafeInteger(value.scope.included_page_count) || Number(value.scope.included_page_count) < 0
    || !Array.isArray(value.scope.features) || !Array.isArray(value.scope.exclusions)
    || !Array.isArray(value.scope.assumptions)
    || !hasExactKeys(value.payment_schedule, ["milestones"])
    || !Array.isArray(value.payment_schedule.milestones)
    || (value.validity_days !== null
      && (!Number.isSafeInteger(value.validity_days) || Number(value.validity_days) < 1
        || Number(value.validity_days) > 365))) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  return value;
}
function validateApplicationAction(value: UnvalidatedInput) {
  for (const key of FORBIDDEN_IDENTITY_FIELDS)if (key in value) throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
  const action = String(value.action || "");
  if (!APPLICATION_ACTIONS.has(action)) throw new RequestError(400, "INVALID_REQUEST");
  const allowed = action === "list_applications"
    ? new Set(["action", "limit", "offset"])
    : action === "list_pending_intakes"
    ? new Set(["action", "retention_state"])
    : action === "count_pending_intakes"
    ? new Set(["action"])
    : PENDING_INTAKE_RETENTION_ACTIONS.has(action)
    ? new Set([
      "action",
      "intake_id",
      "expected_revision",
      "idempotency_key",
      "reason",
    ])
    : action === "permanently_delete_pending_intake"
    ? new Set([
      "action",
      "intake_id",
      "quote_request_id",
      "idempotency_key",
      "reason",
    ])
    : action === "list_applications_v2"
    ? new Set(["action", "zone", "operational_status", "year", "quarter", "request_kind", "search", "cursor", "limit"])
    : action === "get_application_facets_v2"
    ? new Set(["action", "zone", "operational_status", "request_kind", "search"])
    : action === "upsert_quotation_business_draft"
    ? new Set(["action", "intake_id", "expected_revision", "idempotency_key", "input"])
    : action === "promote_quotation_business_draft_to_approval"
    ? new Set(["action", "intake_id", "expected_revision", "idempotency_key"])
    : action === "issue_and_deliver_approved_quotation"
    ? new Set(["action", "quote_request_id"])
    : action === "create_internal_e2e_run"
    ? new Set(["action", "idempotency_key", "run_label", "ttl_minutes"])
    : action === "create_customer_request_smoke_fixture"
    ? new Set(["action", "idempotency_key"])
    : action === "cleanup_internal_e2e_accepted_file"
    ? new Set(["action", "run_id", "request_id", "upload_request_id", "uploaded_file_id", "idempotency_key"])
    : action === "finalize_internal_e2e_run"
    ? new Set(["action", "run_id", "terminal_status", "expected_revision", "idempotency_key"])
    : action === "get_project_dossier"
    ? new Set(["action", "project_id"])
    : action === "get_application_detail"
    ? new Set(["action", "quote_request_id", "application_reference", "support_reference"])
    : action === "get_assignment_operator_roster"
    ? new Set(["action"])
    : action === "get_current_operator_identity"
    ? new Set(["action"])
    : action === "get_my_assigned_dossiers"
    ? new Set(["action", "cursor", "limit"])
    : action === "get_dossier_document_manifest"
    ? new Set(["action", "quote_request_id"])
    : action === "create_dossier_document_access"
    ? new Set(["action", "quote_request_id", "source_type", "document_id"])
    : action === "list_customer_requests_for_dossier"
    ? new Set(["action", "dossier_reference", "cursor", "limit"])
    : action === "get_customer_request"
    ? new Set(["action", "request_id"])
    : action === "transition_customer_request"
    ? new Set(["action", "request_id", "command_type", "expected_revision", "idempotency_key"])
    : action === "create_customer_request_upload_link"
    ? new Set(["action", "request_id", "idempotency_key"])
    : action === "revoke_customer_request_upload_link"
    ? new Set(["action", "upload_request_id", "reason", "idempotency_key"])
    : action === "get_dossier_assignment"
    ? new Set(["action", "dossier_reference"])
    : action === "assign_dossier"
    ? new Set(["action", "dossier_reference", "assignee_operator_id", "expected_revision", "idempotency_key", "reason"])
    : PROJECT_SITE_ACTIONS.has(action)
    ? new Set(["action", "project_id", "expected_revision", "idempotency_key", "canonical_domain", "evidence"])
    : INTAKE_LIFECYCLE_ACTIONS.has(action)
    ? new Set(["action", "intake_id", "expected_revision", "idempotency_key", "reason"])
    : DOSSIER_LIFECYCLE_ACTIONS.has(action)
    ? new Set(["action", "quote_request_id", "expected_revision", "idempotency_key", "reason"])
    : new Set(["action", "quote_request_id", "application_reference", "idempotency_key"]);
  if (Object.keys(value).some((key)=>!allowed.has(key))) throw new RequestError(400, "INVALID_REQUEST");
  if (action === "upsert_quotation_business_draft") {
    const intakeId = String(value.intake_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    if (!UUID.test(intakeId) || !UUID.test(idempotencyKey)
      || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      intake_id: intakeId,
      expected_revision: expectedRevision as number,
      idempotency_key: idempotencyKey,
      input: validateQuotationBusinessInput(value.input)
    };
  }
  if (action === "promote_quotation_business_draft_to_approval") {
    const intakeId = String(value.intake_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    if (!UUID.test(intakeId) || !UUID.test(idempotencyKey)
      || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 1) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      intake_id: intakeId,
      expected_revision: expectedRevision as number,
      idempotency_key: idempotencyKey,
    };
  }
  if (action === "issue_and_deliver_approved_quotation") {
    const quoteRequestId = String(value.quote_request_id || "");
    if (!UUID.test(quoteRequestId)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, quote_request_id: quoteRequestId };
  }
  if (action === "list_pending_intakes") {
    const retentionState = value.retention_state ?? "ACTIVE";
    if (!["ACTIVE", "ARCHIVED"].includes(String(retentionState))) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, retention_state: String(retentionState) };
  }
  if (PENDING_INTAKE_RETENTION_ACTIONS.has(action)) {
    const intakeId = String(value.intake_id || "");
    const expectedRevision = value.expected_revision;
    const idempotencyKey = String(value.idempotency_key || "");
    const reason = typeof value.reason === "string" ? value.reason.trim() : "";
    if (
      !UUID.test(intakeId) || !UUID.test(idempotencyKey) ||
      !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0 ||
      reason.length < 1 || reason.length > 500
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      intake_id: intakeId,
      event_type: PENDING_INTAKE_RETENTION_ACTIONS.get(action),
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      reason,
    };
  }
  if (action === "permanently_delete_pending_intake") {
    const intakeId = String(value.intake_id || "");
    const quoteRequestId = String(value.quote_request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const reason = typeof value.reason === "string" ? value.reason.trim() : "";
    if (
      !UUID.test(intakeId) || !UUID.test(quoteRequestId) ||
      !UUID.test(idempotencyKey) || reason.length < 1 || reason.length > 500
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      intake_id: intakeId,
      quote_request_id: quoteRequestId,
      idempotency_key: idempotencyKey,
      reason,
    };
  }
  if (
    action === "get_assignment_operator_roster" ||
    action === "get_current_operator_identity" ||
    action === "count_pending_intakes"
  ) return { action };
  if (action === "get_my_assigned_dossiers") {
    const cursor = value.cursor ?? null;
    const limit = value.limit === undefined ? 25 : value.limit;
    if ((cursor !== null && (typeof cursor !== "string" || cursor.length < 1))
      || !Number.isSafeInteger(limit) || Number(limit) < 1 || Number(limit) > 100) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, cursor, limit };
  }
  if (action === "get_dossier_document_manifest") {
    const quoteRequestId = String(value.quote_request_id || "");
    if (!UUID.test(quoteRequestId)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, quote_request_id: quoteRequestId };
  }
  if (action === "create_dossier_document_access") {
    const quoteRequestId = String(value.quote_request_id || "");
    const documentId = String(value.document_id || "");
    const sourceType = String(value.source_type || "");
    if (!UUID.test(quoteRequestId) || !UUID.test(documentId)
      || !["QUOTATION_ARTIFACT", "CUSTOMER_UPLOAD"].includes(sourceType)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, quote_request_id: quoteRequestId, source_type: sourceType, document_id: documentId };
  }
  if (action === "list_customer_requests_for_dossier") {
    const cursor = value.cursor ?? null;
    const limit = value.limit === undefined ? 25 : value.limit;
    if ((cursor !== null && (typeof cursor !== "string" || cursor.length < 1 || cursor.length > 4096))
      || !Number.isSafeInteger(limit) || Number(limit) < 1 || Number(limit) > 100) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, dossier_reference: normalizeDossierReference(value.dossier_reference), cursor, limit };
  }
  if (action === "get_customer_request") {
    const requestId = String(value.request_id || "");
    if (!UUID.test(requestId)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, request_id: requestId };
  }
  if (action === "transition_customer_request") {
    const requestId = String(value.request_id || "");
    const commandType = String(value.command_type || "");
    const expectedRevision = value.expected_revision;
    const idempotencyKey = String(value.idempotency_key || "");
    if (!UUID.test(requestId) || !CUSTOMER_REQUEST_WORK_COMMANDS.has(commandType)
      || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0
      || !UUID.test(idempotencyKey)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      request_id: requestId,
      command_type: commandType as "START" | "REQUIRE_CUSTOMER_RESPONSE" | "RESUME",
      expected_revision: expectedRevision as number,
      idempotency_key: idempotencyKey,
    };
  }
  if (action === "create_customer_request_upload_link") {
    const requestId = String(value.request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    if (!UUID.test(requestId) || !UUID.test(idempotencyKey)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, request_id: requestId, idempotency_key: idempotencyKey };
  }
  if (action === "revoke_customer_request_upload_link") {
    const uploadRequestId = String(value.upload_request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const reason = typeof value.reason === "string" ? value.reason.trim() : "";
    if (!UUID.test(uploadRequestId) || !UUID.test(idempotencyKey) || reason.length < 1 || reason.length > 500) throw new RequestError(400, "INVALID_REQUEST");
    return { action, upload_request_id: uploadRequestId, reason, idempotency_key: idempotencyKey };
  }
  if (action === "get_dossier_assignment") {
    return { action, dossier_reference: normalizeDossierReference(value.dossier_reference) };
  }
  if (action === "assign_dossier") {
    const assigneeOperatorId = String(value.assignee_operator_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    if (!UUID.test(assigneeOperatorId) || !UUID.test(idempotencyKey)
      || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0
      || (value.reason !== undefined && value.reason !== null && typeof value.reason !== "string")) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    const reason = typeof value.reason === "string" ? value.reason.trim() || null : null;
    if (reason !== null && reason.length > 500) throw new RequestError(400, "INVALID_REQUEST");
    return {
      action,
      dossier_reference: normalizeDossierReference(value.dossier_reference),
      assignee_operator_id: assigneeOperatorId,
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      reason
    };
  }
  if (action === "list_applications_v2" || action === "get_application_facets_v2") {
    const zone = value.zone ?? "ACTIVE";
    const operationalStatus = value.operational_status ?? null;
    const requestKind = value.request_kind ?? null;
    const search = typeof value.search === "string" ? value.search.trim() || null : value.search ?? null;
    if (!OPERATOR_ZONES.has(zone)
      || (operationalStatus !== null && !OPERATOR_STATUSES.has(operationalStatus))
      || (requestKind !== null && !["website", "slimme_documentenflow"].includes(requestKind))
      || (search !== null && (typeof search !== "string" || search.length > 140))) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    if (action === "get_application_facets_v2") {
      return { action, zone, operational_status: operationalStatus, request_kind: requestKind, search };
    }
    const year = value.year ?? null;
    const quarter = value.quarter ?? null;
    const cursor = value.cursor ?? null;
    const limit = value.limit ?? 50;
    if ((year !== null && (!Number.isSafeInteger(year) || year < 1 || year > 9999))
      || (quarter !== null && (!year || !["Q1", "Q2", "Q3", "Q4"].includes(quarter)))
      || (cursor !== null && (typeof cursor !== "string" || cursor.length < 1 || cursor.length > 4096))
      || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action, zone, operational_status: operationalStatus, year, quarter,
      request_kind: requestKind, search, cursor, limit
    };
  }
  if (action === "list_applications") {
    const limit = value.limit ?? 100, offset = value.offset ?? 0;
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 200 || !Number.isSafeInteger(offset) || offset < 0) throw new RequestError(400, "INVALID_REQUEST");
    return { action, limit, offset };
  }
  if (action === "create_internal_e2e_run") {
    const idempotencyKey = String(value.idempotency_key || "");
    const runLabel = typeof value.run_label === "string" ? value.run_label.trim() : "";
    const ttlMinutes = value.ttl_minutes;
    if (!UUID.test(idempotencyKey) || runLabel.length < 1 || runLabel.length > 120
      || !Number.isSafeInteger(ttlMinutes) || Number(ttlMinutes) < 5 || Number(ttlMinutes) > 240) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, idempotency_key: idempotencyKey, run_label: runLabel, ttl_minutes: ttlMinutes };
  }
  if (action === "create_customer_request_smoke_fixture") {
    const idempotencyKey = String(value.idempotency_key || "");
    if (!UUID.test(idempotencyKey)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, idempotency_key: idempotencyKey };
  }
  if (action === "cleanup_internal_e2e_accepted_file") {
    const runId = String(value.run_id || "");
    const requestId = String(value.request_id || "");
    const uploadRequestId = String(value.upload_request_id || "");
    const uploadedFileId = String(value.uploaded_file_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    if (![runId, requestId, uploadRequestId, uploadedFileId, idempotencyKey].every((field)=>UUID.test(field))) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      run_id: runId,
      request_id: requestId,
      upload_request_id: uploadRequestId,
      uploaded_file_id: uploadedFileId,
      idempotency_key: idempotencyKey,
    };
  }
  if (action === "finalize_internal_e2e_run") {
    const runId = String(value.run_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const terminalStatus = String(value.terminal_status || "");
    const expectedRevision = value.expected_revision;
    if (!UUID.test(runId) || !UUID.test(idempotencyKey)
      || !new Set(["PASSED", "FAILED", "ABORTED", "EXPIRED"]).has(terminalStatus)
      || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, run_id: runId, terminal_status: terminalStatus, expected_revision: expectedRevision, idempotency_key: idempotencyKey };
  }
  if (action === "get_project_dossier") {
    const projectId = String(value.project_id || "");
    if (!UUID.test(projectId)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, project_id: projectId };
  }
  if (PROJECT_SITE_ACTIONS.has(action)) {
    const projectId = String(value.project_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    const canonicalDomain = typeof value.canonical_domain === "string" ? value.canonical_domain.trim() : "";
    const evidence = typeof value.evidence === "string" ? value.evidence.trim() : "";
    if (!UUID.test(projectId) || !UUID.test(idempotencyKey)
      || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0
      || !CANONICAL_DOMAIN.test(canonicalDomain) || canonicalDomain !== canonicalDomain.toLowerCase()
      || evidence.length < 1 || evidence.length > 500) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      project_id: projectId,
      operation: PROJECT_SITE_ACTIONS.get(action),
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      canonical_domain: canonicalDomain,
      evidence
    };
  }
  if (INTAKE_LIFECYCLE_ACTIONS.has(action)) {
    const intakeId = String(value.intake_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    const reason = typeof value.reason === "string" ? value.reason.trim() : "";
    if (!UUID.test(intakeId) || !UUID.test(idempotencyKey)
      || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0
      || reason.length < 1 || reason.length > 500) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      intake_id: intakeId,
      event_type: INTAKE_LIFECYCLE_ACTIONS.get(action),
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      reason
    };
  }
  if (DOSSIER_LIFECYCLE_ACTIONS.has(action)) {
    const quoteRequestId = String(value.quote_request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    const reason = typeof value.reason === "string" ? value.reason.trim() : "";
    if (!UUID.test(quoteRequestId) || !UUID.test(idempotencyKey)
      || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0
      || reason.length < 1 || reason.length > 500) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      quote_request_id: quoteRequestId,
      event_type: DOSSIER_LIFECYCLE_ACTIONS.get(action),
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      reason
    };
  }
  const quoteRequestId = value.quote_request_id == null ? null : String(value.quote_request_id);
  const applicationReference = value.application_reference == null ? null : String(value.application_reference);
  const rawSupportReference = value.support_reference == null ? null : String(value.support_reference).trim().toUpperCase();
  const supportReference = rawSupportReference === null
    ? null
    : `#${rawSupportReference.replace(/^#/, "")}`;
  const locatorCount = [quoteRequestId, applicationReference, supportReference].filter((locator)=>locator !== null).length;
  if (locatorCount !== 1 || (supportReference !== null && action !== "get_application_detail")) throw new RequestError(400, "INVALID_REQUEST");
  if (quoteRequestId !== null && !UUID.test(quoteRequestId)) throw new RequestError(400, "INVALID_REQUEST");
  if (applicationReference !== null && !APPLICATION_REFERENCE.test(applicationReference)) throw new RequestError(400, "INVALID_REQUEST");
  if (rawSupportReference !== null && !SUPPORT_REFERENCE.test(rawSupportReference)) throw new RequestError(400, "INVALID_REQUEST");
  if (action === "promote_accepted_application" && !UUID.test(String(value.idempotency_key || ""))) throw new RequestError(400, "INVALID_REQUEST");
  return {
    action,
    quote_request_id: quoteRequestId,
    application_reference: applicationReference,
    ...(action === "get_application_detail" ? { support_reference: supportReference } : {}),
    ...(action === "promote_accepted_application" ? { idempotency_key: String(value.idempotency_key) } : {})
  };
}
function mapDatabaseError(error: unknown) {
  const code = error instanceof Error ? error.message : "INTERNAL";
  if ([
    "HUMAN_JWT_REQUIRED",
    "UNKNOWN_OPERATOR",
    "OPERATOR_DISABLED",
    "OPERATOR_REVOKED",
    "OPERATOR_INACTIVE",
    "APPLICATION_SCOPE_DENIED",
    "QUOTATION_BUSINESS_SCOPE_DENIED",
    "QUOTATION_ORCHESTRATION_SCOPE_DENIED",
    "EDGE_DOSSIER_CAPABILITY_REQUIRED",
    "DOSSIER_ASSIGNMENT_ACTOR_REQUIRED",
    "DOSSIER_ASSIGNMENT_READER_REQUIRED",
    "OPERATOR_PERSONAL_QUEUE_READER_REQUIRED",
    "CUSTOMER_REQUEST_ACCESS_DENIED",
    "OPERATIONS_MANAGER_ROSTER_READER_REQUIRED"
    ,"PROJECT_SITE_OWNER_ADMIN_REQUIRED"
    ,"INTERNAL_E2E_OWNER_REQUIRED"
    ,"INTERNAL_E2E_CLEANUP_BINDING_REQUIRED"
    ,"INTERNAL_E2E_CLEANUP_AUTHORIZATION_REQUIRED"
    ,"DOSSIER_DOCUMENT_READER_REQUIRED"
    ,"DOSSIER_DOCUMENT_ACCESS_DENIED"
    ,"DOSSIER_DOCUMENT_NOT_DOWNLOADABLE"
    ,"DOSSIER_DOCUMENT_SOURCE_INVALID"
  ].includes(code)) return response(403, "OPERATOR_NOT_AUTHORIZED");
  if ([
    "PROJECT_SCOPE_DENIED",
    "COMMAND_PERMISSION_DENIED"
  ].includes(code)) return response(403, "INSUFFICIENT_PERMISSIONS");
  if (code === "IDEMPOTENCY_CONFLICT") return response(409, code);
  if (code === "STALE_BUSINESS_REVISION") return response(409, code);
  if (code === "APPROVAL_CONFLICT") return response(409, code);
  if (code === "CONCURRENT_MODIFICATION") return response(409, code);
  if (code === "APPLICATION_NOT_FOUND") return response(404, code);
  if (code === "APPROVAL_NOT_FOUND") return response(404, "QUOTATION_APPROVAL_NOT_FOUND");
  if (code === "AMBIGUOUS_SUPPORT_REFERENCE") return response(409, code);
  if (code === "INTAKE_NOT_FOUND") return response(404, code);
  if (code === "PENDING_INTAKE_NOT_FOUND") return response(404, code);
  if (code === "STALE_PENDING_INTAKE_RETENTION_REVISION") {
    return response(409, "CONCURRENT_MODIFICATION");
  }
  if (
    [
      "PENDING_INTAKE_DELETE_BLOCKED",
      "PENDING_INTAKE_REQUIRED",
      "INVALID_PENDING_INTAKE_RETENTION_TRANSITION",
    ].includes(code)
  ) {
    return response(409, "COMMAND_REJECTED");
  }
  if (code === "DOSSIER_NOT_FOUND") return response(404, code);
  if (code === "AMBIGUOUS_DOSSIER_REFERENCE") return response(409, code);
  if (code === "ASSIGNEE_OPERATOR_NOT_FOUND") return response(404, code);
  if (code === "ASSIGNEE_NOT_ELIGIBLE") return response(409, code);
  if (code === "OPERATOR_DOSSIER_ASSIGNMENT_STATE_REQUIRED") return response(409, "COMMAND_REJECTED");
  if (code === "INTERNAL_E2E_RUN_NOT_FOUND") return response(404, code);
  if (code === "PROJECT_NOT_FOUND") return response(404, code);
  if (code === "APPLICATION_NOT_ACCEPTED") return response(409, code);
  if (["PROJECT_SITE_ALREADY_BOUND", "PROJECT_SITE_NOT_BOUND"].includes(code)) return response(409, "COMMAND_REJECTED");
  if (["INTERNAL_E2E_RUN_FINALIZED", "INTERNAL_E2E_PROMOTION_DENIED", "INTERNAL_E2E_QUOTATION_DENIED"].includes(code)) return response(409, code);
  if ([
    "ACCEPTED_INTERNAL_E2E_FILE_REQUIRED",
    "INTERNAL_E2E_FILE_ALREADY_DELETED",
    "INTERNAL_E2E_FILE_CLEANUP_ALREADY_AUTHORIZED",
    "INTERNAL_E2E_FILE_CLEANUP_ALREADY_FINALIZED",
    "INTERNAL_E2E_STORAGE_OBJECT_STILL_EXISTS"
  ].includes(code)) return response(409, "COMMAND_REJECTED");
  if ([
    "INVALID_APPLICATION_REFERENCE",
    "INVALID_SUPPORT_REFERENCE",
    "INVALID_PROJECT_SITE_COMMAND",
    "EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED",
    "INVALID_PAGINATION",
    "IDEMPOTENCY_KEY_REQUIRED",
    "INVALID_INTAKE_LIFECYCLE_COMMAND"
    ,"INVALID_DOSSIER_LIFECYCLE_COMMAND"
    ,"INVALID_INTERNAL_E2E_REQUEST"
    ,"INVALID_OPERATOR_CURSOR_POSITION"
    ,"INVALID_OPERATOR_ZONE"
    ,"INVALID_OPERATOR_OPERATIONAL_STATUS_FILTER"
    ,"INVALID_OPERATOR_REQUEST_KIND_FILTER"
    ,"INVALID_OPERATOR_YEAR"
    ,"INVALID_OPERATOR_QUARTER"
    ,"INVALID_OPERATOR_PAGE_LIMIT"
    ,"INVALID_OPERATOR_SEARCH"
    ,"INVALID_DOSSIER_REFERENCE"
    ,"INVALID_DOSSIER_ASSIGNMENT_COMMAND"
    ,"REASSIGNMENT_REASON_REQUIRED"
    ,"INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT"
    ,"INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR"
    ,"INVALID_CUSTOMER_REQUEST_LIST_LIMIT"
    ,"INVALID_CUSTOMER_REQUEST_LIST_CURSOR"
    ,"INVALID_CUSTOMER_REQUEST_ACTION"
    ,"INVALID_CUSTOMER_REQUEST_COMMAND"
  ].includes(code)) return response(400, "INVALID_REQUEST");
  if (code === "INVALID_OPERATOR_CURSOR") return response(400, code);
  if (code === "OPERATOR_CURSOR_CONFIGURATION_ERROR" || code === "SERVER_CONFIGURATION_ERROR") {
    return response(500, "SERVER_CONFIGURATION_ERROR");
  }
  if ([
    "QUOTATION_ADMIN_CAPABILITY_UNAVAILABLE",
    "APPROVAL_INTEGRITY_INVALID",
    "QUOTATION_TEMPLATE_NOT_APPROVED",
    "QUOTATION_VAT_BINDING_REQUIRED",
    "SELLER_IDENTITY_INVALID"
  ].includes(code)) return response(409, "QUOTATION_NOT_ISSUABLE");
  if ([
    "QUOTATION_ORCHESTRATION_CONTEXT_INVALID",
    "QUOTATION_ISSUANCE_PREPARATION_INVALID",
    "QUOTATION_ISSUE_PAYLOAD_INVALID",
    "QUOTATION_TEMPLATE_HASH_INVALID",
    "QUOTATION_RENDER_INVALID",
    "QUOTATION_ARTIFACT_HASH_MISMATCH",
    "QUOTATION_ARTIFACT_COMMIT_INVALID"
  ].includes(code)) return response(500, "QUOTATION_GENERATION_FAILED");
  if ([
    "QUOTATION_ARTIFACT_UPLOAD_FAILED",
    "QUOTATION_ARTIFACT_ARCHIVE_INVALID"
  ].includes(code)) return response(500, "QUOTATION_ARCHIVE_FAILED");
  if (code === "QUOTATION_DELIVERY_FAILED") return response(502, code);
  if ([
    "INVALID_STATE",
    "PAYMENT_NOT_MATCHED",
    "ACCESS_DENIED",
    "INVALID_INTAKE_LIFECYCLE_TRANSITION",
    "INVALID_OPERATOR_DOSSIER_TRANSITION",
    "INVALID_OPERATOR_DOSSIER_RESTORE",
    "TRASHED_DOSSIER_BLOCKER_CREATION_DENIED"
    ,"INVALID_CUSTOMER_REQUEST_TRANSITION"
    ,"CUSTOMER_REQUEST_TERMINAL"
    ,"QUOTATION_INTAKE_NOT_AVAILABLE"
    ,"PRICING_INTEGRITY_INVALID"
    ,"QUOTATION_TERMS_NOT_APPROVED"
    ,"QUOTATION_VAT_DECISION_NOT_APPROVED"
    ,"PRICING_RULE_NOT_FOUND"
    ,"PRICING_RULE_NOT_EXACT"
    ,"PRICING_RULE_QUANTITY_MISMATCH"
    ,"PRICING_RULE_AMOUNT_MISMATCH"
    ,"QUOTATION_BUSINESS_PAYLOAD_INVALID"
  ].includes(code)) return response(409, "COMMAND_REJECTED");
  if (code.startsWith("LEGACY_TEST_CLEANUP_")) return response(409, "COMMAND_REJECTED");
  return response(500, "INTERNAL_ERROR");
}

export async function executeDossierAssignmentReadTransport(
  client: DossierAssignmentRpcClient,
  input: DossierAssignmentReadInput
): Promise<unknown> {
  const { data, error } = await client.rpc("get_operator_dossier_assignment_v1", {
    p_dossier_reference: input.dossier_reference,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function executeAssignmentOperatorRosterTransport(
  client: DossierAssignmentRpcClient
): Promise<ReadonlyArray<Readonly<{ operator_id: string; display_name: string }>>> {
  const { data, error } = await client.rpc("get_operations_manager_roster_v1", {});
  if (error) throw new Error(error.message);
  if (!Array.isArray(data)) throw new Error("INVALID_ASSIGNMENT_ROSTER_RESPONSE");
  return (data as AssignmentRosterRow[])
    .filter((row)=>row?.role === "operator"
      && row?.status === "ACTIVE"
      && UUID.test(String(row.operator_id || ""))
      && typeof row.display_name === "string"
      && row.display_name.length > 0)
    .map((row)=>({
      operator_id: String(row.operator_id),
      display_name: row.display_name as string,
    }));
}

export async function executeDossierAssignmentMutationTransport(
  client: DossierAssignmentRpcClient,
  input: DossierAssignmentMutationInput
): Promise<unknown> {
  const { data, error } = await client.rpc("assign_operator_dossier_v1", {
    p_dossier_reference: input.dossier_reference,
    p_assignee_operator_id: input.assignee_operator_id,
    p_expected_revision: input.expected_revision,
    p_idempotency_key: input.idempotency_key,
    p_reason: input.reason,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function executeDossierLifecycleTransport(
  issueCapability: DossierLifecycleRpcCall,
  executeCommand: DossierLifecycleRpcCall,
  actorAuthUserId: string,
  input: DossierLifecycleTransportInput
): Promise<unknown> {
  const capabilityResult = await issueCapability({
    p_actor_auth_user_id: actorAuthUserId,
    p_quote_request_id: input.quote_request_id,
    p_event_type: input.event_type,
    p_expected_revision: input.expected_revision,
    p_idempotency_key: input.idempotency_key,
    p_reason: input.reason,
  });
  if (capabilityResult.error || !UUID.test(String(capabilityResult.data || ""))) {
    throw new Error(capabilityResult.error?.message || "SERVER_CONFIGURATION_ERROR");
  }

  const commandResult = await executeCommand({
    p_quote_request_id: input.quote_request_id,
    p_event_type: input.event_type,
    p_expected_revision: input.expected_revision,
    p_idempotency_key: input.idempotency_key,
    p_reason: input.reason,
    p_edge_capability: capabilityResult.data,
  });
  if (commandResult.error) throw new Error(commandResult.error.message);
  return commandResult.data;
}

const DOSSIER_DOCUMENT_MANIFEST_FIELDS = [
  "document_id", "source_type", "document_type", "artifact_type", "title",
  "filename", "status", "created_at", "accepted_at", "source_record_id",
  "version", "sha256", "quote_request_id", "customer_id", "project_id",
  "can_open", "can_download",
];

function isNullableUuid(value: unknown): boolean {
  return value === null || UUID.test(String(value));
}

function isNullableString(value: unknown): boolean {
  return value === null || typeof value === "string";
}

function validateDossierDocumentManifest(value: unknown, quoteRequestId: string) {
  if (!Array.isArray(value)) throw new Error("INVALID_DOSSIER_DOCUMENT_MANIFEST_RESPONSE");
  return value.map((item)=>{
    if (!isRecord(item) || !hasExactKeys(item, DOSSIER_DOCUMENT_MANIFEST_FIELDS)
      || !UUID.test(String(item.document_id)) || !UUID.test(String(item.source_record_id))
      || item.quote_request_id !== quoteRequestId
      || !["QUOTATION", "QUOTATION_ARTIFACT", "CUSTOMER_UPLOAD"].includes(String(item.source_type))
      || !["QUOTATION", "CUSTOMER_UPLOAD"].includes(String(item.document_type))
      || !isNullableString(item.artifact_type) || typeof item.title !== "string" || item.title.length < 1
      || !isNullableString(item.filename) || typeof item.status !== "string" || item.status.length < 1
      || typeof item.created_at !== "string" || !Number.isFinite(Date.parse(item.created_at))
      || (item.accepted_at !== null && (typeof item.accepted_at !== "string" || !Number.isFinite(Date.parse(item.accepted_at))))
      || !isNullableString(item.version) || !isNullableString(item.sha256)
      || !isNullableUuid(item.customer_id) || !isNullableUuid(item.project_id)
      || typeof item.can_open !== "boolean" || typeof item.can_download !== "boolean"
      || (item.source_type === "QUOTATION" && (item.filename !== null || item.can_open || item.can_download))
      || (item.source_type === "QUOTATION_ARTIFACT" && (item.document_type !== "QUOTATION" || typeof item.artifact_type !== "string" || typeof item.filename !== "string"))
      || (item.source_type === "CUSTOMER_UPLOAD" && (item.document_type !== "CUSTOMER_UPLOAD" || item.artifact_type !== null || typeof item.filename !== "string"))) {
      throw new Error("INVALID_DOSSIER_DOCUMENT_MANIFEST_RESPONSE");
    }
    return item;
  });
}

export async function executeDossierDocumentManifestTransport(
  client: DossierAssignmentRpcClient,
  actorAuthUserId: string,
  input: Extract<DossierDocumentActionInput, { action: "get_dossier_document_manifest" }>,
): Promise<unknown> {
  const { data, error } = await client.rpc("get_operator_dossier_document_manifest_v1", {
    p_actor_auth_user_id: actorAuthUserId,
    p_quote_request_id: input.quote_request_id,
  });
  if (error) throw new Error(error.message);
  return validateDossierDocumentManifest(data, input.quote_request_id);
}

export async function executeDossierDocumentAccessTransport(
  client: DossierAssignmentRpcClient,
  actorAuthUserId: string,
  input: Extract<DossierDocumentActionInput, { action: "create_dossier_document_access" }>,
  createSignedUrl: (bucket: string, path: string, expiresInSeconds: number, filename: string)=>PromiseLike<string>,
  now: ()=>number = ()=>Date.now(),
): Promise<Readonly<{ signed_url: string; expires_at: string; filename: string }>> {
  const { data, error } = await client.rpc("authorize_operator_dossier_document_download_v1", {
    p_actor_auth_user_id: actorAuthUserId,
    p_quote_request_id: input.quote_request_id,
    p_source_type: input.source_type,
    p_document_id: input.document_id,
  });
  if (error) throw new Error(error.message);
  if (!isRecord(data) || !hasExactKeys(data, [
    "state", "document_id", "source_type", "storage_bucket_id",
    "storage_object_path", "filename", "expires_in_seconds",
  ]) || data.state !== "AUTHORIZED" || data.document_id !== input.document_id
    || data.source_type !== input.source_type || typeof data.storage_bucket_id !== "string"
    || data.storage_bucket_id.length < 1 || typeof data.storage_object_path !== "string"
    || data.storage_object_path.length < 1 || typeof data.filename !== "string"
    || data.filename.length < 1 || data.expires_in_seconds !== 60) {
    throw new Error("INVALID_DOSSIER_DOCUMENT_AUTHORIZATION_RESPONSE");
  }
  const signedUrl = await createSignedUrl(
    data.storage_bucket_id,
    data.storage_object_path,
    data.expires_in_seconds,
    data.filename,
  );
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(signedUrl);
  } catch {
    throw new Error("INVALID_DOSSIER_DOCUMENT_SIGNED_URL");
  }
  if (!["http:", "https:"].includes(parsedUrl.protocol)) throw new Error("INVALID_DOSSIER_DOCUMENT_SIGNED_URL");
  return {
    signed_url: signedUrl,
    expires_at: new Date(now() + 60_000).toISOString(),
    filename: data.filename,
  };
}

export async function handleCommercialOperator(request: Request, deps: CommercialOperatorDependencies): Promise<Response> {
  try {
    if (request.method !== "POST") throw new RequestError(405, "METHOD_NOT_ALLOWED");
    const jwt = bearer(request), claims = decodeClaims(jwt), sub = String(claims.sub || "");
    if (!UUID.test(sub) || typeof claims.exp !== "number" || claims.exp * 1000 <= deps.now()) throw new RequestError(401, "INVALID_JWT");
    if (claims.role === "service_role") throw new RequestError(401, "HUMAN_JWT_REQUIRED");
    const user = await deps.verifyUser(jwt);
    if (!user || user.id !== sub) throw new RequestError(401, "INVALID_JWT");
    const parsed = await body(request);
    if ("action" in parsed) {
      if (
        [
          "list_applications_v2",
          "get_application_facets_v2",
          "list_pending_intakes",
          "count_pending_intakes",
          "archive_pending_intake",
          "restore_pending_intake",
          "permanently_delete_pending_intake",
        ].includes(String(parsed.action))
      ) {
        await deps.authorizeApplicationReader(jwt);
      }
      const input = validateApplicationAction(parsed);
      if (input.action === "list_pending_intakes") {
        const result = validatePendingIntakesResult(
          await deps.executePendingIntakes(
            user.id,
            String(input.retention_state),
          ),
        );
        return response(200, "APPLICATION_ACTION_ACCEPTED", { result });
      }
      if (input.action === "count_pending_intakes") {
        const result = validatePendingIntakeCountResult(
          await deps.executePendingIntakeCount(user.id),
        );
        return response(200, "APPLICATION_ACTION_ACCEPTED", { result });
      }
      if (input.action === "list_applications_v2") {
        const cursorPosition = typeof input.cursor === "string"
          ? await deps.verifyOperatorCursor(input.cursor, input)
          : null;
        const raw = await deps.executeApplicationListV2(user.id, input, cursorPosition);
        if (!raw || typeof raw !== "object" || !Array.isArray(raw.items)
          || typeof raw.has_more !== "boolean"
          || (raw.has_more && (!raw.next_position || typeof raw.next_position !== "object"))
          || (!raw.has_more && raw.next_position !== null)) {
          throw new Error("INVALID_OPERATOR_CORE_RESPONSE");
        }
        const nextPosition = raw.next_position;
        const nextCursor = raw.has_more && nextPosition !== null
          ? await deps.signOperatorCursor(nextPosition, input)
          : null;
        return response(200, "APPLICATION_ACTION_ACCEPTED", {
          result: { items: raw.items, next_cursor: nextCursor }
        });
      }
      if (input.action === "get_application_facets_v2") {
        const result = await deps.executeApplicationFacetsV2(user.id, input);
        return response(200, "APPLICATION_ACTION_ACCEPTED", { result });
      }
      const result = await deps.executeApplicationAction(jwt, input, user.id);
      return response(200, "APPLICATION_ACTION_ACCEPTED", { result });
    }
    const input = validate(parsed);
    const limit = await deps.consumeRateLimit(jwt, input.project_id);
    if (!limit.allowed) return response(429, "RATE_LIMITED", {
      retry_after_seconds: limit.retry_after_seconds
    });
    const result = await deps.executeCommand(jwt, input);
    return response(200, "COMMAND_ACCEPTED", {
      result
    });
  } catch (error) {
    if (error instanceof RequestError) return response(error.status, error.code);
    return mapDatabaseError(error);
  }
}

export async function withCommercialOperatorCors(request: Request, next: ()=>Response | Promise<Response>): Promise<Response> {
  const origin = request.headers.get("origin");
  const blocked = rejectIfOriginNotAllowed(request);
  if (blocked) return blocked;
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  const response = await next();
  const headers = new Headers(response.headers);
  new Headers(corsHeaders(origin)).forEach((value, name)=>headers.set(name, value));
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}
export function createUnsignedTestJwt(payload: Record<string, unknown>): string {
  const encode = (value: Record<string, unknown>)=>btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  return `${encode({
    alg: "RS256",
    typ: "JWT"
  })}.${encode(payload)}.signature`;
}

export async function executeOperatorPersonalQueueTransport(
  client: DossierAssignmentRpcClient,
  input: OperatorPersonalQueueInput
): Promise<unknown> {
  const { data, error } = await client.rpc("get_operator_personal_dossier_queue_v1", {
    p_cursor: input.cursor,
    p_limit: input.limit,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function executeCustomerRequestTransport(
  client: DossierAssignmentRpcClient,
  input: CustomerRequestActionInput
): Promise<unknown> {
  const request = input.action === "list_customer_requests_for_dossier"
    ? client.rpc("get_customer_requests_for_dossier_v1", {
      p_dossier_reference: input.dossier_reference,
      p_cursor: input.cursor,
      p_limit: input.limit,
    })
    : input.action === "get_customer_request"
    ? client.rpc("get_customer_request_v1", { p_request_id: input.request_id })
    : client.rpc("transition_customer_request_v1", {
      p_request_id: input.request_id,
      p_command_type: input.command_type,
      p_expected_revision: input.expected_revision,
      p_idempotency_key: input.idempotency_key,
      p_payload: {},
    });
  const { data, error } = await request;
  if (error) throw new Error(error.message);
  return data;
}

export async function executeCurrentOperatorIdentityTransport(
  client: DossierAssignmentRpcClient
): Promise<CurrentOperatorIdentity> {
  const { data, error } = await client.rpc("get_current_operator_identity_v1", {});
  if (error) throw new Error(error.message);
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("INVALID_OPERATOR_IDENTITY_RESPONSE");
  const identity = data as Record<string, unknown>;
  if (Object.keys(identity).length !== 3
    || typeof identity.display_name !== "string" || !identity.display_name
    || !["owner", "operations_manager", "operator", "reviewer", "read_only", "admin"].includes(String(identity.role || ""))
    || identity.status !== "ACTIVE") {
    throw new Error("INVALID_OPERATOR_IDENTITY_RESPONSE");
  }
  return identity as CurrentOperatorIdentity;
}
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";

const MAX_BODY_BYTES = 16 * 1024;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
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
  "archive_project",
]);
const APPLICATION_ACTIONS = new Set([
  "get_current_operator_identity",
  "list_workforce_calendar",
  "list_recruitment_vacancies",
  "create_recruitment_vacancy",
  "update_recruitment_vacancy",
  "set_recruitment_vacancy_status",
  "get_recruitment_publication_state",
  "set_recruitment_publication_enabled",
  "upsert_quotation_business_draft",
  "promote_quotation_business_draft_to_approval",
  "issue_and_deliver_approved_quotation",
  "issue_sdf_approved_quotation",
  "prepare_sdf_quotation_delivery",
  "send_sdf_quotation_delivery",
  "prepare_sdf_m1_invoice",
  "list_applications",
  "list_applications_v2",
  "list_pending_intakes",
  "list_pending_sdf_qualification_intakes",
  "allow_sdf_qualification_intake",
  "reissue_sdf_qualification_intake",
  "inspect_sdf_qualification_intake",
  "transition_sdf_qualification_intake",
  "authorize_sdf_quotation_preparation_v1",
  "count_pending_intakes",
  "archive_pending_intake",
  "restore_pending_intake",
  "permanently_delete_pending_intake",
  "get_application_facets_v2",
  "get_application_detail",
  "get_dossier_substance",
  "get_assignment_operator_roster",
  "get_dossier_assignment",
  "get_my_assigned_dossiers",
  "get_dossier_document_manifest",
  "create_dossier_document_access",
  "create_sdf_customer_request",
  "list_customer_requests_for_dossier",
  "get_customer_request",
  "transition_customer_request",
  "create_customer_request_upload_link",
  "revoke_customer_request_upload_link",
  "promote_customer_request_upload_to_document_inbox",
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
  "rotate_project_site",
]);
const OPERATOR_ZONES = new Set([
  "ACTIVE",
  "ARCHIVED",
  "TRASHED",
  "ACTIVE_ARCHIVED",
]);
const OPERATOR_STATUSES = new Set([
  "CANCELLED",
  "SUBMITTED",
  "REVIEWED",
  "QUOTE_ACCEPTED",
  "M1_PAYMENT_PENDING",
  "M1_PAYMENT_RECEIVED",
  "PROJECT_RELEASED",
  "PREVIEW_READY",
  "M2_PAYMENT_RECEIVED",
  "FINAL_APPROVAL_RECORDED",
  "FULL_PAYMENT_RECEIVED",
  "FINAL_TRANSFER_AUTHORIZED",
  "DELIVERED",
  "ARCHIVED",
]);
const INTAKE_LIFECYCLE_ACTIONS = new Map([
  ["interrupt_intake", "INTERRUPTED"],
  ["resume_intake", "RESUMED"],
  ["cancel_intake", "CANCELLED"],
  ["reactivate_intake", "REACTIVATED"],
]);
const PENDING_INTAKE_RETENTION_ACTIONS = new Map([
  ["archive_pending_intake", "ARCHIVED"],
  ["restore_pending_intake", "RESTORED"],
]);
const DOSSIER_LIFECYCLE_ACTIONS = new Map([
  ["archive_dossier", "ARCHIVED"],
  ["reactivate_dossier", "REACTIVATED"],
  ["trash_dossier", "TRASHED"],
  ["restore_dossier", "RESTORED"],
]);
const PROJECT_SITE_ACTIONS = new Map([
  ["bind_project_site", "INITIAL_BIND"],
  ["rotate_project_site", "ROTATION"],
]);
const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;
const SUPPORT_REFERENCE = /^#?[0-9A-F]{8}$/i;
const CANONICAL_DOMAIN =
  /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
const CUSTOMER_REQUEST_WORK_COMMANDS = new Set([
  "START",
  "REQUIRE_CUSTOMER_RESPONSE",
  "RESUME",
]);
const CUSTOMER_REQUEST_TYPES = new Set([
  "CONTENT_CHANGE",
  "DESIGN_CHANGE",
  "TECHNICAL_CHANGE",
  "NEW_FEATURE",
  "CORRECTION",
  "FILE_DELIVERY",
  "OTHER",
]);
type DossierLifecycleRpcResult = Readonly<{
  data: unknown;
  error: Readonly<{ message: string }> | null;
}>;
type DossierLifecycleRpcCall = (
  args: Record<string, unknown>,
) => PromiseLike<DossierLifecycleRpcResult>;
type DossierAssignmentRpcClient = Readonly<{
  rpc: (
    name: string,
    args: Record<string, unknown>,
  ) => PromiseLike<DossierLifecycleRpcResult>;
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
  role:
    | "owner"
    | "operations_manager"
    | "operator"
    | "reviewer"
    | "read_only"
    | "admin";
  status: "ACTIVE";
}>;
export type WorkforceCalendarActionInput = Readonly<{
  action: "list_workforce_calendar";
  start_date: string;
  end_date: string;
}>;
export type RecruitmentVacancyActionInput =
  | Readonly<{
    action: "list_recruitment_vacancies";
  }>
  | Readonly<{
    action: "get_recruitment_publication_state";
  }>
  | Readonly<{
    action: "set_recruitment_publication_enabled";
    enabled: boolean;
  }>
  | Readonly<{
    action: "create_recruitment_vacancy";
    title: string;
    slug: string;
    department: string;
    location: string;
    employment_type: string;
    summary: string;
    description: string;
    requirements: string;
  }>
  | Readonly<{
    action: "update_recruitment_vacancy";
    vacancy_id: string;
    title: string;
    department: string;
    location: string;
    employment_type: string;
    summary: string;
    description: string;
    requirements: string;
  }>
  | Readonly<{
    action: "set_recruitment_vacancy_status";
    vacancy_id: string;
    status: "PUBLISHED" | "CLOSED";
  }>;
export type CustomerRequestActionInput =
  | Readonly<{
    action: "create_sdf_customer_request";
    quote_request_id: string;
    idempotency_key: string;
    request_type: string;
    title: string;
    description: string;
    priority: "LOW" | "NORMAL" | "HIGH" | "URGENT" | null;
  }>
  | Readonly<{
    action: "list_customer_requests_for_dossier";
    dossier_reference: string;
    cursor: string | null;
    limit: number;
  }>
  | Readonly<{
    action: "get_customer_request";
    request_id: string;
  }>
  | Readonly<{
    action: "transition_customer_request";
    request_id: string;
    command_type: "START" | "REQUIRE_CUSTOMER_RESPONSE" | "RESUME";
    expected_revision: number;
    idempotency_key: string;
  }>;
export type CustomerRequestUploadOperatorActionInput =
  | Readonly<{
    action: "create_customer_request_upload_link";
    request_id: string;
    idempotency_key: string;
  }>
  | Readonly<{
    action: "revoke_customer_request_upload_link";
    upload_request_id: string;
    reason: string;
    idempotency_key: string;
  }>;
export type CustomerRequestUploadInboxPromotionActionInput = Readonly<{
  action: "promote_customer_request_upload_to_document_inbox";
  uploaded_file_id: string;
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
export type SdfQuotationIssuanceActionInput = Readonly<{
  action: "issue_sdf_approved_quotation";
  quote_request_id: string;
  business_draft_id: string;
  approval_id: string;
  approval_version: number;
  approval_sha256: string;
  generation_contract_version: number;
}>;
export type SdfQuotationDeliveryPreparationActionInput = Readonly<{
  action: "prepare_sdf_quotation_delivery";
  business_draft_id: string;
  approval_id: string;
  approval_version: number;
  approval_sha256: string;
  issuance_id: string;
  artifact_id: string;
  artifact_sha256: string;
  artifact_bytes: number;
}>;
export type SdfQuotationDeliverySendActionInput = Readonly<{
  action: "send_sdf_quotation_delivery";
  business_draft_id: string;
  approval_id: string;
  approval_version: number;
  approval_sha256: string;
  issuance_id: string;
  artifact_id: string;
  artifact_sha256: string;
  artifact_bytes: number;
}>;
export type SdfM1InvoicePreparationActionInput = Readonly<{
  action: "prepare_sdf_m1_invoice";
  obligation_id: string;
  template_authority_id: string;
  idempotency_key: string;
}>;
export type DossierDocumentActionInput =
  | Readonly<{
    action: "get_dossier_document_manifest";
    quote_request_id: string;
  }>
  | Readonly<{
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
type UnvalidatedInput =
  & Record<string, unknown>
  & Readonly<{
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
  verifyOperatorCursor(
    cursor: string,
    input: Record<string, unknown>,
  ): PromiseLike<unknown>;
  executeApplicationListV2(
    actorAuthUserId: string,
    input: Record<string, unknown>,
    position: unknown,
  ): PromiseLike<OperatorListCoreResult>;
  executePendingIntakes(
    actorAuthUserId: string,
    retentionState: string,
  ): PromiseLike<unknown>;
  executePendingIntakeCount(actorAuthUserId: string): PromiseLike<unknown>;
  executeDossierSubstance(
    actorAuthUserId: string,
    quoteRequestId: string,
  ): PromiseLike<unknown>;
  signOperatorCursor(
    position: Record<string, string>,
    input: Record<string, unknown>,
  ): PromiseLike<string>;
  executeApplicationFacetsV2(
    actorAuthUserId: string,
    input: Record<string, unknown>,
  ): PromiseLike<unknown>;
  executeApplicationAction(
    jwt: string,
    input: Record<string, unknown>,
    actorAuthUserId: string,
  ): PromiseLike<unknown>;
  consumeRateLimit(
    jwt: string,
    projectId: string,
  ): PromiseLike<Readonly<{ allowed: boolean; retry_after_seconds: number }>>;
  executeCommand(
    jwt: string,
    input: CommercialCommandInput,
  ): PromiseLike<unknown>;
}>;
const FORBIDDEN_IDENTITY_FIELDS = new Set([
  "p_actor",
  "actor",
  "actor_id",
  "operator_id",
  "operator_role",
  "name",
  "email",
]);
class RequestError extends Error {
  status;
  code;
  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}
function response(
  status: number,
  code: string,
  extra: Record<string, unknown> = {},
) {
  return new Response(
    JSON.stringify({
      ok: status < 400,
      code,
      ...extra,
    }),
    {
      status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      },
    },
  );
}
function bearer(request: Request): string {
  const match = (request.headers.get("authorization") || "").match(
    /^Bearer\s+([^\s]+)$/i,
  );
  if (!match) throw new RequestError(401, "AUTHENTICATION_REQUIRED");
  return match[1];
}
function decodeClaims(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) throw new RequestError(401, "INVALID_JWT");
  try {
    const value = parts[1].replace(/-/g, "+").replace(/_/g, "/").padEnd(
      Math.ceil(parts[1].length / 4) * 4,
      "=",
    );
    return JSON.parse(atob(value));
  } catch {
    throw new RequestError(401, "INVALID_JWT");
  }
}
async function body(request: Request): Promise<UnvalidatedInput> {
  if (
    (request.headers.get("content-type") || "").split(";", 1)[0].trim()
      .toLowerCase() !== "application/json"
  ) throw new RequestError(415, "UNSUPPORTED_CONTENT_TYPE");
  const declared = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    throw new RequestError(413, "BODY_TOO_LARGE");
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new RequestError(413, "BODY_TOO_LARGE");
  }
  try {
    const parsed: unknown = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw 0;
    return parsed as UnvalidatedInput;
  } catch {
    throw new RequestError(400, "INVALID_JSON");
  }
}
function validate(value: UnvalidatedInput): CommercialCommandInput {
  for (const key of FORBIDDEN_IDENTITY_FIELDS) {
    if (key in value) throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
  }
  if (
    !UUID.test(String(value.project_id || "")) ||
    !UUID.test(String(value.idempotency_key || ""))
  ) throw new RequestError(400, "INVALID_REQUEST");
  if (
    !COMMANDS.has(String(value.command_type || "")) ||
    typeof value.expected_state !== "string" ||
    !Number.isSafeInteger(value.expected_revision) ||
    Number(value.expected_revision) < 0
  ) throw new RequestError(400, "INVALID_REQUEST");
  if (
    !value.payload || typeof value.payload !== "object" ||
    Array.isArray(value.payload)
  ) throw new RequestError(400, "INVALID_REQUEST");
  for (const key of FORBIDDEN_IDENTITY_FIELDS) {
    if (key in value.payload) {
      throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
    }
  }
  return value as UnvalidatedInput & CommercialCommandInput;
}
function normalizeDossierReference(value: unknown) {
  const reference = typeof value === "string" ? value.trim().toUpperCase() : "";
  if (APPLICATION_REFERENCE.test(reference)) return reference;
  if (SUPPORT_REFERENCE.test(reference)) {
    return `#${reference.replace(/^#/, "")}`;
  }
  throw new RequestError(400, "INVALID_REQUEST");
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).length === keys.length &&
    keys.every((key) => key in value);
}
const CALENDAR_DATE = /^\d{4}-\d{2}-\d{2}$/;
const WORKFORCE_CALENDAR_STATUSES = new Set([
  "WORKED_FULL_DAY",
  "WORKED_HALF_DAY_AM",
  "WORKED_HALF_DAY_PM",
  "LEAVE",
  "SICK",
  "OTHER_ABSENCE",
]);
function isValidCalendarDate(value: unknown): value is string {
  if (typeof value !== "string" || !CALENDAR_DATE.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value;
}
function validatedCalendarDate(value: unknown): string {
  if (!isValidCalendarDate(value)) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  return value as string;
}
function validatePendingIntakesResult(value: unknown) {
  const fields = [
    "quote_request_id",
    "intake_id",
    "name",
    "organization",
    "support_reference",
    "email",
    "phone",
    "request_kind",
    "sdf_package",
    "website_type",
    "invitation_created_at",
    "invitation_sent_at",
    "invitation_delivery_status",
    "intake_status",
    "effective_access",
    "access_token_expires_at",
    "lifecycle_revision",
    "retention_state",
    "archived_at",
    "retention_revision",
    "can_permanently_delete",
    "delete_block_reason",
    "started_at",
    "current_reminder_cycle",
    "reminder_1_sent_at",
    "reminder_2_sent_at",
    "last_activity_at",
    "dossier_state",
    "dossier_revision",
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
      typeof item.support_reference !== "string" || !/^#[0-9A-F]{8}$/.test(item.support_reference) ||
      typeof item.email !== "string" || !item.email ||
      (item.phone !== null && typeof item.phone !== "string") ||
      !["website", "slimme_documentenflow"].includes(String(item.request_kind)) ||
      (item.sdf_package !== null && !["start", "groei", "maatwerk"].includes(String(item.sdf_package))) ||
      typeof item.website_type !== "string" || !item.website_type ||
      typeof item.invitation_created_at !== "string" ||
      !item.invitation_created_at ||
      (item.invitation_sent_at !== null &&
        typeof item.invitation_sent_at !== "string") ||
      (item.invitation_delivery_status !== null &&
        !["pending", "processing", "sent", "retry_wait", "failed"].includes(String(item.invitation_delivery_status))) ||
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
        ].includes(String(item.delete_block_reason))) ||
      (item.started_at !== null && typeof item.started_at !== "string") ||
      !Number.isSafeInteger(item.current_reminder_cycle) ||
      Number(item.current_reminder_cycle) < 0 ||
      (item.reminder_1_sent_at !== null &&
        typeof item.reminder_1_sent_at !== "string") ||
      (item.reminder_2_sent_at !== null &&
        typeof item.reminder_2_sent_at !== "string") ||
      typeof item.last_activity_at !== "string" || !item.last_activity_at ||
      item.dossier_state !== "ACTIVE" ||
      !Number.isSafeInteger(item.dossier_revision) ||
      Number(item.dossier_revision) < 0
    ) {
      throw new Error("INVALID_PENDING_INTAKES_RESPONSE");
    }
  }
  return value as { items: Record<string, unknown>[] };
}
const WEBSITE_SUBSTANCE_FIELDS = [
  "business_description", "target_audience", "has_existing_website",
  "existing_website_url", "elements_to_keep", "improvement_areas",
  "website_goals", "primary_conversion_goal", "requested_pages",
  "other_pages", "requested_features", "shop_required", "shop_details",
  "booking_required", "booking_details", "languages", "primary_language",
  "additional_languages", "page_scope_details", "quote_form_details",
  "multilingual_details", "download_details", "newsletter_details",
  "content_media_details", "hosting_maintenance_details", "deadline_details",
  "seo_details", "design_styles", "brand_status", "logo_status",
  "brand_colors", "inspiration_sites", "disliked_styles", "content_status",
  "image_status", "image_support", "domain_status", "domain_name",
  "hosting_status", "hosting_support", "maintenance_interest", "seo_priority",
  "seo_keywords", "social_channels", "integrations", "deadline_date",
  "deadline_reason", "budget_confirmed", "budget_update_category",
  "budget_notes", "priorities", "additional_notes", "confirmation",
];
const WEBSITE_SUBSTANCE_OBJECT_FIELDS: Record<string, string[]> = {
  shop_details: ["approx_product_count", "complex_product_count", "payment_provider_count", "shipping_scope", "categories", "online_payments", "shipping", "pickup", "pickup_scope", "existing_catalog", "customer_accounts", "catalog_import", "erp_api"],
  booking_details: ["tier", "type", "existing_system", "existing_system_name", "calendar_integration"],
  page_scope_details: ["portfolio", "reviews", "blog", "jobs", "gallery", "jobs_application", "search"],
  quote_form_details: ["file_uploads", "database_workflow", "automated_processing", "review_approval", "custom_logic", "form_count", "structure_scope"],
  multilingual_details: ["final_translations_supplied", "same_structure", "translation_required", "seo_per_language", "advanced_seo_research", "language_specific_integrations", "complex_scope"],
  download_details: ["access"],
  newsletter_details: ["scope", "analytics", "custom_integration"],
  content_media_details: ["copywriting_scope", "copy_page_count", "image_work_scope", "paid_stock_handling", "branding_tier"],
  hosting_maintenance_details: ["hosting_support", "maintenance_interest", "domain_service", "maintenance_plan"],
  deadline_details: ["commercially_critical", "hard_deadline"],
  seo_details: ["scope", "extra_language_seo", "advanced_language_seo"],
};
function isNullableJsonValue(value: unknown): boolean {
  return value === null || typeof value === "string" ||
    typeof value === "number" || typeof value === "boolean" ||
    (Array.isArray(value) && value.every((item) =>
      item === null || typeof item === "string" || typeof item === "number" ||
      typeof item === "boolean" || isRecord(item)
    ));
}
function validateDossierSubstanceResult(value: unknown) {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["quote_request_id", "request_kind", "request", "customer", "intake", "documents"]) ||
    !UUID.test(String(value.quote_request_id || "")) ||
    !["website", "slimme_documentenflow"].includes(String(value.request_kind)) ||
    !isRecord(value.request) ||
    !hasExactKeys(value.request, ["reference", "original_text", "requested_service", "requested_at"]) ||
    typeof value.request.reference !== "string" || !value.request.reference ||
    (value.request.original_text !== null && typeof value.request.original_text !== "string") ||
    typeof value.request.requested_service !== "string" || !value.request.requested_service ||
    typeof value.request.requested_at !== "string" || !value.request.requested_at ||
    !isRecord(value.customer) ||
    !hasExactKeys(value.customer, ["name", "company", "email", "phone"]) ||
    typeof value.customer.name !== "string" || !value.customer.name ||
    (value.customer.company !== null && typeof value.customer.company !== "string") ||
    typeof value.customer.email !== "string" || !value.customer.email ||
    (value.customer.phone !== null && typeof value.customer.phone !== "string") ||
    !isRecord(value.intake) ||
    !hasExactKeys(value.intake, ["intake_id", "status", "invitation_state", "invited_at", "started_at", "submitted_at", "structured_answers"]) ||
    !UUID.test(String(value.intake.intake_id || "")) ||
    !["invited", "in_progress", "submitted", "reviewed", "under_review", "changes_requested", "qualification_complete", "closed"].includes(String(value.intake.status)) ||
    !["INVITED", "ACTIVATED"].includes(String(value.intake.invitation_state)) ||
    typeof value.intake.invited_at !== "string" || !value.intake.invited_at ||
    (value.intake.started_at !== null && typeof value.intake.started_at !== "string") ||
    (value.intake.submitted_at !== null && typeof value.intake.submitted_at !== "string") ||
    !isRecord(value.intake.structured_answers) ||
    !isRecord(value.documents) ||
    !hasExactKeys(value.documents, ["customer_request_count", "uploaded_document_count"]) ||
    !Number.isSafeInteger(value.documents.customer_request_count) || Number(value.documents.customer_request_count) < 0 ||
    !Number.isSafeInteger(value.documents.uploaded_document_count) || Number(value.documents.uploaded_document_count) < 0
  ) throw new Error("INVALID_DOSSIER_SUBSTANCE_RESPONSE");

  const answers = value.intake.structured_answers;
  if (value.request_kind === "website") {
    if (!hasExactKeys(answers, WEBSITE_SUBSTANCE_FIELDS)) {
      throw new Error("INVALID_DOSSIER_SUBSTANCE_RESPONSE");
    }
    for (const [key, fieldValue] of Object.entries(answers)) {
      const nestedFields = WEBSITE_SUBSTANCE_OBJECT_FIELDS[key];
      if (!nestedFields && !isNullableJsonValue(fieldValue)) throw new Error("INVALID_DOSSIER_SUBSTANCE_RESPONSE");
      if (nestedFields && fieldValue !== null &&
        (!isRecord(fieldValue) || !hasExactKeys(fieldValue, nestedFields) || !Object.values(fieldValue).every(isNullableJsonValue))) {
        throw new Error("INVALID_DOSSIER_SUBSTANCE_RESPONSE");
      }
    }
  } else {
    if (
      !hasExactKeys(answers, ["documentPurpose", "workflowCapabilities", "businessRequirements", "sampleDocumentMetadata", "commercialQualification"]) ||
      !isRecord(answers.documentPurpose) || !hasExactKeys(answers.documentPurpose, ["categories", "otherDescription"]) ||
      !Array.isArray(answers.documentPurpose.categories) || !answers.documentPurpose.categories.every((item) => typeof item === "string") ||
      !Array.isArray(answers.workflowCapabilities) || !answers.workflowCapabilities.every((item) => typeof item === "string") ||
      !isRecord(answers.businessRequirements) || !hasExactKeys(answers.businessRequirements, ["currentWorkflow", "desiredWorkflow", "volumeBand", "frequency", "relevantDocumentTypes", "rolesUsers"]) ||
      !Array.isArray(answers.businessRequirements.relevantDocumentTypes) || !answers.businessRequirements.relevantDocumentTypes.every((item) => typeof item === "string") ||
      !Array.isArray(answers.businessRequirements.rolesUsers) || !answers.businessRequirements.rolesUsers.every((item) => typeof item === "string") ||
      !isRecord(answers.sampleDocumentMetadata) || !hasExactKeys(answers.sampleDocumentMetadata, ["available", "requestedByLws", "uploadRequiredLater"]) ||
      !isRecord(answers.commercialQualification) || !hasExactKeys(answers.commercialQualification, ["packageDirection", "customComplexity", "documentVolumes", "flowCount", "userCount"]) ||
      !Array.isArray(answers.commercialQualification.documentVolumes) ||
      !answers.commercialQualification.documentVolumes.every((item) =>
        isRecord(item) && hasExactKeys(item, ["documentType", "documentCount", "period", "averagePagesPerDocument"]) &&
        Object.values(item).every(isNullableJsonValue)
      ) ||
      !Object.values(answers.documentPurpose).every(isNullableJsonValue) ||
      !Object.values(answers.businessRequirements).every(isNullableJsonValue) ||
      !Object.values(answers.sampleDocumentMetadata).every(isNullableJsonValue) ||
      !Object.values(answers.commercialQualification).every(isNullableJsonValue)
    ) throw new Error("INVALID_DOSSIER_SUBSTANCE_RESPONSE");
  }
  return value;
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
function validateQuotationBusinessInput(
  value: unknown,
): Record<string, unknown> {
  const keys = [
    "commercial_lines",
    "discount",
    "scope",
    "payment_schedule",
    "validity_days",
  ];
  if (
    !isRecord(value) || !hasExactKeys(value, keys) ||
    !Array.isArray(value.commercial_lines) ||
    value.commercial_lines.length < 1 ||
    !isRecord(value.discount) || !isRecord(value.scope) ||
    !isRecord(value.payment_schedule)
  ) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  const lineKeys = ["rule_id", "quantity", "description_context"];
  if (
    value.commercial_lines.some((line) =>
      !isRecord(line) || !hasExactKeys(line, lineKeys) ||
      typeof line.rule_id !== "string" || line.rule_id.trim().length < 1 ||
      line.rule_id.length > 200 ||
      typeof line.quantity !== "number" || !Number.isFinite(line.quantity) ||
      line.quantity <= 0 ||
      typeof line.description_context !== "string" ||
      line.description_context.trim().length < 1 ||
      line.description_context.length > 2000
    )
  ) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  if (
    !hasExactKeys(value.discount, [
      "discount_type",
      "discount_value_minor",
      "discount_reason",
    ]) ||
    !Number.isSafeInteger(value.discount.discount_value_minor) ||
    Number(value.discount.discount_value_minor) < 0 ||
    (value.discount.discount_type !== null &&
      typeof value.discount.discount_type !== "string") ||
    (value.discount.discount_reason !== null &&
      typeof value.discount.discount_reason !== "string") ||
    (Number(value.discount.discount_value_minor) > 0 &&
      (typeof value.discount.discount_type !== "string" ||
        value.discount.discount_type.trim().length < 1 ||
        typeof value.discount.discount_reason !== "string" ||
        value.discount.discount_reason.trim().length < 1))
  ) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  const scopeKeys = [
    "project_title",
    "project_type",
    "scope_summary",
    "requested_languages",
    "included_page_count",
    "features",
    "copywriting",
    "seo",
    "hosting",
    "maintenance",
    "exclusions",
    "assumptions",
    "indicative_timing",
  ];
  if (
    !hasExactKeys(value.scope, scopeKeys) ||
    typeof value.scope.project_title !== "string" ||
    value.scope.project_title.trim().length < 1 ||
    typeof value.scope.project_type !== "string" ||
    value.scope.project_type.trim().length < 1 ||
    typeof value.scope.scope_summary !== "string" ||
    value.scope.scope_summary.trim().length < 1 ||
    !Array.isArray(value.scope.requested_languages) ||
    !Number.isSafeInteger(value.scope.included_page_count) ||
    Number(value.scope.included_page_count) < 0 ||
    !Array.isArray(value.scope.features) ||
    !Array.isArray(value.scope.exclusions) ||
    !Array.isArray(value.scope.assumptions) ||
    !hasExactKeys(value.payment_schedule, ["milestones"]) ||
    !Array.isArray(value.payment_schedule.milestones) ||
    (value.validity_days !== null &&
      (!Number.isSafeInteger(value.validity_days) ||
        Number(value.validity_days) < 1 ||
        Number(value.validity_days) > 365))
  ) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  return value;
}
function validateApplicationAction(value: UnvalidatedInput) {
  for (const key of FORBIDDEN_IDENTITY_FIELDS) {
    if (key in value) throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
  }
  const action = String(value.action || "");
  if (!APPLICATION_ACTIONS.has(action)) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  const allowed = action === "list_applications"
    ? new Set(["action", "limit", "offset"])
    : action === "list_pending_sdf_qualification_intakes"
    ? new Set(["action"])
    : action === "allow_sdf_qualification_intake" || action === "reissue_sdf_qualification_intake"
    ? new Set(["action", "quote_request_id", "idempotency_key"])
    : action === "inspect_sdf_qualification_intake"
    ? new Set(["action", "quote_request_id"])
    : action === "transition_sdf_qualification_intake"
    ? new Set(["action", "quote_request_id", "transition", "reason", "idempotency_key"])
    : action === "authorize_sdf_quotation_preparation_v1"
    ? new Set(["action", "quote_request_id", "idempotency_key"])
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
    ? new Set([
      "action",
      "zone",
      "operational_status",
      "year",
      "quarter",
      "request_kind",
      "search",
      "cursor",
      "limit",
    ])
    : action === "get_application_facets_v2"
    ? new Set([
      "action",
      "zone",
      "operational_status",
      "request_kind",
      "search",
    ])
    : action === "upsert_quotation_business_draft"
    ? new Set([
      "action",
      "intake_id",
      "expected_revision",
      "idempotency_key",
      "input",
    ])
    : action === "promote_quotation_business_draft_to_approval"
    ? new Set(["action", "intake_id", "expected_revision", "idempotency_key"])
    : action === "issue_and_deliver_approved_quotation"
    ? new Set(["action", "quote_request_id"])
    : action === "issue_sdf_approved_quotation"
    ? new Set([
      "action",
      "quote_request_id",
      "business_draft_id",
      "approval_id",
      "approval_version",
      "approval_sha256",
      "generation_contract_version",
    ])
    : action === "prepare_sdf_quotation_delivery" ||
      action === "send_sdf_quotation_delivery"
    ? new Set([
      "action",
      "business_draft_id",
      "approval_id",
      "approval_version",
      "approval_sha256",
      "issuance_id",
      "artifact_id",
      "artifact_sha256",
      "artifact_bytes",
    ])
    : action === "prepare_sdf_m1_invoice"
    ? new Set([
      "action",
      "obligation_id",
      "template_authority_id",
      "idempotency_key",
    ])
    : action === "create_internal_e2e_run"
    ? new Set(["action", "idempotency_key", "run_label", "ttl_minutes"])
    : action === "create_customer_request_smoke_fixture"
    ? new Set(["action", "idempotency_key"])
    : action === "cleanup_internal_e2e_accepted_file"
    ? new Set([
      "action",
      "run_id",
      "request_id",
      "upload_request_id",
      "uploaded_file_id",
      "idempotency_key",
    ])
    : action === "finalize_internal_e2e_run"
    ? new Set([
      "action",
      "run_id",
      "terminal_status",
      "expected_revision",
      "idempotency_key",
    ])
    : action === "get_project_dossier"
    ? new Set(["action", "project_id"])
    : action === "get_application_detail"
    ? new Set([
      "action",
      "quote_request_id",
      "application_reference",
      "support_reference",
    ])
    : action === "get_dossier_substance"
    ? new Set(["action", "quote_request_id"])
    : action === "get_assignment_operator_roster"
    ? new Set(["action"])
    : action === "get_current_operator_identity"
    ? new Set(["action"])
    : action === "list_workforce_calendar"
    ? new Set(["action", "start_date", "end_date"])
    : action === "list_recruitment_vacancies"
    ? new Set(["action"])
    : action === "get_recruitment_publication_state"
    ? new Set(["action"])
    : action === "set_recruitment_publication_enabled"
    ? new Set(["action", "enabled"])
    : action === "create_recruitment_vacancy"
    ? new Set([
      "action",
      "title",
      "slug",
      "department",
      "location",
      "employment_type",
      "summary",
      "description",
      "requirements",
    ])
    : action === "update_recruitment_vacancy"
    ? new Set([
      "action",
      "vacancy_id",
      "title",
      "department",
      "location",
      "employment_type",
      "summary",
      "description",
      "requirements",
    ])
    : action === "set_recruitment_vacancy_status"
    ? new Set(["action", "vacancy_id", "status"])
    : action === "get_my_assigned_dossiers"
    ? new Set(["action", "cursor", "limit"])
    : action === "get_dossier_document_manifest"
    ? new Set(["action", "quote_request_id"])
    : action === "create_dossier_document_access"
    ? new Set(["action", "quote_request_id", "source_type", "document_id"])
    : action === "create_sdf_customer_request"
    ? new Set([
      "action",
      "quote_request_id",
      "idempotency_key",
      "request_type",
      "title",
      "description",
      "priority",
    ])
    : action === "list_customer_requests_for_dossier"
    ? new Set(["action", "dossier_reference", "cursor", "limit"])
    : action === "get_customer_request"
    ? new Set(["action", "request_id"])
    : action === "transition_customer_request"
    ? new Set([
      "action",
      "request_id",
      "command_type",
      "expected_revision",
      "idempotency_key",
    ])
    : action === "create_customer_request_upload_link"
    ? new Set(["action", "request_id", "idempotency_key"])
    : action === "revoke_customer_request_upload_link"
    ? new Set(["action", "upload_request_id", "reason", "idempotency_key"])
    : action === "promote_customer_request_upload_to_document_inbox"
    ? new Set(["action", "uploaded_file_id"])
    : action === "get_dossier_assignment"
    ? new Set(["action", "dossier_reference"])
    : action === "assign_dossier"
    ? new Set([
      "action",
      "dossier_reference",
      "assignee_operator_id",
      "expected_revision",
      "idempotency_key",
      "reason",
    ])
    : PROJECT_SITE_ACTIONS.has(action)
    ? new Set([
      "action",
      "project_id",
      "expected_revision",
      "idempotency_key",
      "canonical_domain",
      "evidence",
    ])
    : INTAKE_LIFECYCLE_ACTIONS.has(action)
    ? new Set([
      "action",
      "intake_id",
      "expected_revision",
      "idempotency_key",
      "reason",
    ])
    : DOSSIER_LIFECYCLE_ACTIONS.has(action)
    ? new Set([
      "action",
      "quote_request_id",
      "expected_revision",
      "idempotency_key",
      "reason",
    ])
    : new Set([
      "action",
      "quote_request_id",
      "application_reference",
      "idempotency_key",
    ]);
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  if (action === "upsert_quotation_business_draft") {
    const intakeId = String(value.intake_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    if (
      !UUID.test(intakeId) || !UUID.test(idempotencyKey) ||
      !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      intake_id: intakeId,
      expected_revision: expectedRevision as number,
      idempotency_key: idempotencyKey,
      input: validateQuotationBusinessInput(value.input),
    };
  }
  if (action === "promote_quotation_business_draft_to_approval") {
    const intakeId = String(value.intake_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    if (
      !UUID.test(intakeId) || !UUID.test(idempotencyKey) ||
      !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 1
    ) {
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
    if (!UUID.test(quoteRequestId)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, quote_request_id: quoteRequestId };
  }
  if (action === "issue_sdf_approved_quotation") {
    const quoteRequestId = String(value.quote_request_id || "");
    const businessDraftId = String(value.business_draft_id || "");
    const approvalId = String(value.approval_id || "");
    const approvalVersion = value.approval_version;
    const approvalSha256 = String(value.approval_sha256 || "");
    const generationContractVersion = value.generation_contract_version;
    if (!UUID.test(quoteRequestId) || !UUID.test(businessDraftId)
      || !UUID.test(approvalId) || !Number.isSafeInteger(approvalVersion)
      || Number(approvalVersion) < 1 || !/^[0-9a-f]{64}$/.test(approvalSha256)
      || generationContractVersion !== 1) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      quote_request_id: quoteRequestId,
      business_draft_id: businessDraftId,
      approval_id: approvalId,
      approval_version: approvalVersion as number,
      approval_sha256: approvalSha256,
      generation_contract_version: generationContractVersion,
    };
  }
  if (
    action === "prepare_sdf_quotation_delivery" ||
    action === "send_sdf_quotation_delivery"
  ) {
    const businessDraftId = String(value.business_draft_id || "");
    const approvalId = String(value.approval_id || "");
    const approvalVersion = value.approval_version;
    const approvalSha256 = String(value.approval_sha256 || "");
    const issuanceId = String(value.issuance_id || "");
    const artifactId = String(value.artifact_id || "");
    const artifactSha256 = String(value.artifact_sha256 || "");
    const artifactBytes = value.artifact_bytes;
    if (
      !UUID.test(businessDraftId) || !UUID.test(approvalId) ||
      !Number.isSafeInteger(approvalVersion) || Number(approvalVersion) < 1 ||
      !/^[0-9a-f]{64}$/.test(approvalSha256) || !UUID.test(issuanceId) ||
      !UUID.test(artifactId) || !/^[0-9a-f]{64}$/.test(artifactSha256) ||
      !Number.isSafeInteger(artifactBytes) || Number(artifactBytes) < 1
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      business_draft_id: businessDraftId,
      approval_id: approvalId,
      approval_version: approvalVersion as number,
      approval_sha256: approvalSha256,
      issuance_id: issuanceId,
      artifact_id: artifactId,
      artifact_sha256: artifactSha256,
      artifact_bytes: artifactBytes as number,
    };
  }
  if (action === "prepare_sdf_m1_invoice") {
    const obligationId = String(value.obligation_id || "");
    const templateAuthorityId = String(value.template_authority_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    if (
      !UUID.test(obligationId) || !UUID.test(templateAuthorityId) ||
      !UUID.test(idempotencyKey)
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      obligation_id: obligationId,
      template_authority_id: templateAuthorityId,
      idempotency_key: idempotencyKey,
    };
  }
  if (action === "list_pending_sdf_qualification_intakes") return { action };
  if (action === "inspect_sdf_qualification_intake") {
    const quoteRequestId = String(value.quote_request_id || "");
    if (!UUID.test(quoteRequestId)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, quote_request_id: quoteRequestId };
  }
  if (action === "allow_sdf_qualification_intake" || action === "reissue_sdf_qualification_intake" || action === "authorize_sdf_quotation_preparation_v1") {
    const quoteRequestId = String(value.quote_request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    if (!UUID.test(quoteRequestId) || !UUID.test(idempotencyKey)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, quote_request_id: quoteRequestId, idempotency_key: idempotencyKey };
  }
  if (action === "transition_sdf_qualification_intake") {
    const quoteRequestId = String(value.quote_request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const transition = String(value.transition || "");
    const reason = typeof value.reason === "string" ? value.reason.trim() : "";
    if (!UUID.test(quoteRequestId) || !UUID.test(idempotencyKey) || !["begin_review","request_more_information","mark_qualification_complete","close_qualification"].includes(transition) || ((transition === "request_more_information" || transition === "close_qualification") && (reason.length < 1 || reason.length > 2000)) || ((transition === "begin_review" || transition === "mark_qualification_complete") && reason.length > 0)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, quote_request_id: quoteRequestId, transition, reason: reason || null, idempotency_key: idempotencyKey };
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
  if (action === "list_workforce_calendar") {
    const startDate = validatedCalendarDate(value.start_date);
    const endDate = validatedCalendarDate(value.end_date);
    const rangeDays = (Date.parse(`${endDate}T00:00:00Z`) -
      Date.parse(`${startDate}T00:00:00Z`)) / 86_400_000;
    if (rangeDays < 0 || rangeDays > 365) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, start_date: startDate, end_date: endDate };
  }
  if (action === "list_recruitment_vacancies") return { action };
  if (action === "get_recruitment_publication_state") return { action };
  if (action === "set_recruitment_publication_enabled") {
    if (typeof value.enabled !== "boolean") {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, enabled: value.enabled };
  }
  if (
    action === "create_recruitment_vacancy" ||
    action === "update_recruitment_vacancy"
  ) {
    const vacancyId = action === "update_recruitment_vacancy"
      ? String(value.vacancy_id || "")
      : null;
    const fieldLimits = {
      title: 160,
      department: 120,
      location: 160,
      employment_type: 80,
      summary: 500,
      description: 20_000,
      requirements: 20_000,
    } as const;
    const fields = Object.fromEntries(
      Object.entries(fieldLimits).map(([key, limit]) => {
        const fieldValue = typeof value[key] === "string"
          ? value[key].trim()
          : "";
        if (fieldValue.length < 1 || fieldValue.length > limit) {
          throw new RequestError(400, "INVALID_REQUEST");
        }
        return [key, fieldValue];
      }),
    );
    if (vacancyId !== null && !UUID.test(vacancyId)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    if (action === "create_recruitment_vacancy") {
      const slug = typeof value.slug === "string" ? value.slug.trim() : "";
      if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || slug.length > 120) {
        throw new RequestError(400, "INVALID_REQUEST");
      }
      return { action, slug, ...fields };
    }
    return { action, vacancy_id: vacancyId, ...fields };
  }
  if (action === "set_recruitment_vacancy_status") {
    const vacancyId = String(value.vacancy_id || "");
    const status = String(value.status || "");
    if (!UUID.test(vacancyId) || !["PUBLISHED", "CLOSED"].includes(status)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, vacancy_id: vacancyId, status };
  }
  if (action === "get_my_assigned_dossiers") {
    const cursor = value.cursor ?? null;
    const limit = value.limit === undefined ? 25 : value.limit;
    if (
      (cursor !== null && (typeof cursor !== "string" || cursor.length < 1)) ||
      !Number.isSafeInteger(limit) || Number(limit) < 1 || Number(limit) > 100
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, cursor, limit };
  }
  if (action === "get_dossier_document_manifest") {
    const quoteRequestId = String(value.quote_request_id || "");
    if (!UUID.test(quoteRequestId)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, quote_request_id: quoteRequestId };
  }
  if (action === "create_dossier_document_access") {
    const quoteRequestId = String(value.quote_request_id || "");
    const documentId = String(value.document_id || "");
    const sourceType = String(value.source_type || "");
    if (
      !UUID.test(quoteRequestId) || !UUID.test(documentId) ||
      !["QUOTATION_ARTIFACT", "CUSTOMER_UPLOAD"].includes(sourceType)
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      quote_request_id: quoteRequestId,
      source_type: sourceType,
      document_id: documentId,
    };
  }
  if (action === "create_sdf_customer_request") {
    const quoteRequestId = String(value.quote_request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const requestType = String(value.request_type || "");
    const title = typeof value.title === "string" ? value.title.trim() : "";
    const description = typeof value.description === "string"
      ? value.description.trim()
      : "";
    const priority = value.priority == null
      ? null
      : typeof value.priority === "string"
      ? value.priority
      : "";
    if (
      !UUID.test(quoteRequestId) || !UUID.test(idempotencyKey) ||
      !CUSTOMER_REQUEST_TYPES.has(requestType) ||
      title.length < 1 || title.length > 160 ||
      description.length < 1 || description.length > 4000 ||
      (priority !== null &&
        !["LOW", "NORMAL", "HIGH", "URGENT"].includes(priority))
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      quote_request_id: quoteRequestId,
      idempotency_key: idempotencyKey,
      request_type: requestType,
      title,
      description,
      priority: priority as "LOW" | "NORMAL" | "HIGH" | "URGENT" | null,
    };
  }
  if (action === "list_customer_requests_for_dossier") {
    const cursor = value.cursor ?? null;
    const limit = value.limit === undefined ? 25 : value.limit;
    if (
      (cursor !== null &&
        (typeof cursor !== "string" || cursor.length < 1 ||
          cursor.length > 4096)) ||
      !Number.isSafeInteger(limit) || Number(limit) < 1 || Number(limit) > 100
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      dossier_reference: normalizeDossierReference(value.dossier_reference),
      cursor,
      limit,
    };
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
    if (
      !UUID.test(requestId) ||
      !CUSTOMER_REQUEST_WORK_COMMANDS.has(commandType) ||
      !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0 ||
      !UUID.test(idempotencyKey)
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      request_id: requestId,
      command_type: commandType as
        | "START"
        | "REQUIRE_CUSTOMER_RESPONSE"
        | "RESUME",
      expected_revision: expectedRevision as number,
      idempotency_key: idempotencyKey,
    };
  }
  if (action === "create_customer_request_upload_link") {
    const requestId = String(value.request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    if (!UUID.test(requestId) || !UUID.test(idempotencyKey)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, request_id: requestId, idempotency_key: idempotencyKey };
  }
  if (action === "revoke_customer_request_upload_link") {
    const uploadRequestId = String(value.upload_request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const reason = typeof value.reason === "string" ? value.reason.trim() : "";
    if (
      !UUID.test(uploadRequestId) || !UUID.test(idempotencyKey) ||
      reason.length < 1 || reason.length > 500
    ) throw new RequestError(400, "INVALID_REQUEST");
    return {
      action,
      upload_request_id: uploadRequestId,
      reason,
      idempotency_key: idempotencyKey,
    };
  }
  if (action === "promote_customer_request_upload_to_document_inbox") {
    const uploadedFileId = String(value.uploaded_file_id || "");
    if (!UUID.test(uploadedFileId)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, uploaded_file_id: uploadedFileId };
  }
  if (action === "get_dossier_assignment") {
    return {
      action,
      dossier_reference: normalizeDossierReference(value.dossier_reference),
    };
  }
  if (action === "assign_dossier") {
    const assigneeOperatorId = String(value.assignee_operator_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    if (
      !UUID.test(assigneeOperatorId) || !UUID.test(idempotencyKey) ||
      !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0 ||
      (value.reason !== undefined && value.reason !== null &&
        typeof value.reason !== "string")
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    const reason = typeof value.reason === "string"
      ? value.reason.trim() || null
      : null;
    if (reason !== null && reason.length > 500) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      dossier_reference: normalizeDossierReference(value.dossier_reference),
      assignee_operator_id: assigneeOperatorId,
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      reason,
    };
  }
  if (
    action === "list_applications_v2" || action === "get_application_facets_v2"
  ) {
    const zone = value.zone ?? "ACTIVE";
    const operationalStatus = value.operational_status ?? null;
    const requestKind = value.request_kind ?? null;
    const search = typeof value.search === "string"
      ? value.search.trim() || null
      : value.search ?? null;
    if (
      !OPERATOR_ZONES.has(zone) ||
      (operationalStatus !== null &&
        !OPERATOR_STATUSES.has(operationalStatus)) ||
      (requestKind !== null &&
        !["website", "slimme_documentenflow"].includes(requestKind)) ||
      (search !== null && (typeof search !== "string" || search.length > 140))
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    if (action === "get_application_facets_v2") {
      return {
        action,
        zone,
        operational_status: operationalStatus,
        request_kind: requestKind,
        search,
      };
    }
    const year = value.year ?? null;
    const quarter = value.quarter ?? null;
    const cursor = value.cursor ?? null;
    const limit = value.limit ?? 50;
    if (
      (year !== null &&
        (!Number.isSafeInteger(year) || year < 1 || year > 9999)) ||
      (quarter !== null &&
        (!year || !["Q1", "Q2", "Q3", "Q4"].includes(quarter))) ||
      (cursor !== null &&
        (typeof cursor !== "string" || cursor.length < 1 ||
          cursor.length > 4096)) ||
      !Number.isSafeInteger(limit) || limit < 1 || limit > 100
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      zone,
      operational_status: operationalStatus,
      year,
      quarter,
      request_kind: requestKind,
      search,
      cursor,
      limit,
    };
  }
  if (action === "list_applications") {
    const limit = value.limit ?? 100, offset = value.offset ?? 0;
    if (
      !Number.isSafeInteger(limit) || limit < 1 || limit > 200 ||
      !Number.isSafeInteger(offset) || offset < 0
    ) throw new RequestError(400, "INVALID_REQUEST");
    return { action, limit, offset };
  }
  if (action === "create_internal_e2e_run") {
    const idempotencyKey = String(value.idempotency_key || "");
    const runLabel = typeof value.run_label === "string"
      ? value.run_label.trim()
      : "";
    const ttlMinutes = value.ttl_minutes;
    if (
      !UUID.test(idempotencyKey) || runLabel.length < 1 ||
      runLabel.length > 120 ||
      !Number.isSafeInteger(ttlMinutes) || Number(ttlMinutes) < 5 ||
      Number(ttlMinutes) > 240
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      idempotency_key: idempotencyKey,
      run_label: runLabel,
      ttl_minutes: ttlMinutes,
    };
  }
  if (action === "create_customer_request_smoke_fixture") {
    const idempotencyKey = String(value.idempotency_key || "");
    if (!UUID.test(idempotencyKey)) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return { action, idempotency_key: idempotencyKey };
  }
  if (action === "cleanup_internal_e2e_accepted_file") {
    const runId = String(value.run_id || "");
    const requestId = String(value.request_id || "");
    const uploadRequestId = String(value.upload_request_id || "");
    const uploadedFileId = String(value.uploaded_file_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    if (
      ![runId, requestId, uploadRequestId, uploadedFileId, idempotencyKey]
        .every((field) => UUID.test(field))
    ) {
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
    if (
      !UUID.test(runId) || !UUID.test(idempotencyKey) ||
      !new Set(["PASSED", "FAILED", "ABORTED", "EXPIRED"]).has(
        terminalStatus,
      ) ||
      !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      run_id: runId,
      terminal_status: terminalStatus,
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
    };
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
    const canonicalDomain = typeof value.canonical_domain === "string"
      ? value.canonical_domain.trim()
      : "";
    const evidence = typeof value.evidence === "string"
      ? value.evidence.trim()
      : "";
    if (
      !UUID.test(projectId) || !UUID.test(idempotencyKey) ||
      !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0 ||
      !CANONICAL_DOMAIN.test(canonicalDomain) ||
      canonicalDomain !== canonicalDomain.toLowerCase() ||
      evidence.length < 1 || evidence.length > 500
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      project_id: projectId,
      operation: PROJECT_SITE_ACTIONS.get(action),
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      canonical_domain: canonicalDomain,
      evidence,
    };
  }
  if (INTAKE_LIFECYCLE_ACTIONS.has(action)) {
    const intakeId = String(value.intake_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
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
      event_type: INTAKE_LIFECYCLE_ACTIONS.get(action),
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      reason,
    };
  }
  if (DOSSIER_LIFECYCLE_ACTIONS.has(action)) {
    const quoteRequestId = String(value.quote_request_id || "");
    const idempotencyKey = String(value.idempotency_key || "");
    const expectedRevision = value.expected_revision;
    const reason = typeof value.reason === "string" ? value.reason.trim() : "";
    if (
      !UUID.test(quoteRequestId) || !UUID.test(idempotencyKey) ||
      !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0 ||
      reason.length < 1 || reason.length > 500
    ) {
      throw new RequestError(400, "INVALID_REQUEST");
    }
    return {
      action,
      quote_request_id: quoteRequestId,
      event_type: DOSSIER_LIFECYCLE_ACTIONS.get(action),
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      reason,
    };
  }
  const quoteRequestId = value.quote_request_id == null
    ? null
    : String(value.quote_request_id);
  const applicationReference = value.application_reference == null
    ? null
    : String(value.application_reference);
  const rawSupportReference = value.support_reference == null
    ? null
    : String(value.support_reference).trim().toUpperCase();
  const supportReference = rawSupportReference === null
    ? null
    : `#${rawSupportReference.replace(/^#/, "")}`;
  const locatorCount =
    [quoteRequestId, applicationReference, supportReference].filter((locator) =>
      locator !== null
    ).length;
  if (
    locatorCount !== 1 ||
    (supportReference !== null && action !== "get_application_detail")
  ) throw new RequestError(400, "INVALID_REQUEST");
  if (quoteRequestId !== null && !UUID.test(quoteRequestId)) {
    throw new RequestError(400, "INVALID_REQUEST");
  }
  if (
    applicationReference !== null &&
    !APPLICATION_REFERENCE.test(applicationReference)
  ) throw new RequestError(400, "INVALID_REQUEST");
  if (
    rawSupportReference !== null && !SUPPORT_REFERENCE.test(rawSupportReference)
  ) throw new RequestError(400, "INVALID_REQUEST");
  if (
    action === "promote_accepted_application" &&
    !UUID.test(String(value.idempotency_key || ""))
  ) throw new RequestError(400, "INVALID_REQUEST");
  return {
    action,
    quote_request_id: quoteRequestId,
    application_reference: applicationReference,
    ...(action === "get_application_detail"
      ? { support_reference: supportReference }
      : {}),
    ...(action === "promote_accepted_application"
      ? { idempotency_key: String(value.idempotency_key) }
      : {}),
  };
}
function mapDatabaseError(error: unknown) {
  const code = error instanceof Error ? error.message : "INTERNAL";
  if (
    [
      "HUMAN_JWT_REQUIRED",
      "UNKNOWN_OPERATOR",
      "OPERATOR_DISABLED",
      "OPERATOR_REVOKED",
      "OPERATOR_INACTIVE",
      "OPERATOR_NOT_ACTIVE",
      "APPLICATION_SCOPE_DENIED",
      "QUOTATION_BUSINESS_SCOPE_DENIED",
      "QUOTATION_ORCHESTRATION_SCOPE_DENIED",
      "EDGE_DOSSIER_CAPABILITY_REQUIRED",
      "DOSSIER_ASSIGNMENT_ACTOR_REQUIRED",
      "DOSSIER_ASSIGNMENT_READER_REQUIRED",
      "OPERATOR_PERSONAL_QUEUE_READER_REQUIRED",
      "CUSTOMER_REQUEST_ACCESS_DENIED",
      "SDF_CUSTOMER_REQUEST_ACCESS_DENIED",
      "OPERATIONS_MANAGER_ROSTER_READER_REQUIRED",
      "WORKFORCE_MANAGEMENT_READER_REQUIRED",
      "OWNER_REQUIRED",
      "RECRUITMENT_OWNER_REQUIRED",
      "PROJECT_SITE_OWNER_ADMIN_REQUIRED",
      "SDF_INVOICE_AUTHORITY_DENIED",
      "INTERNAL_E2E_OWNER_REQUIRED",
      "INTERNAL_E2E_CLEANUP_BINDING_REQUIRED",
      "INTERNAL_E2E_CLEANUP_AUTHORIZATION_REQUIRED",
      "DOSSIER_DOCUMENT_READER_REQUIRED",
      "DOSSIER_DOCUMENT_ACCESS_DENIED",
      "DOSSIER_DOCUMENT_NOT_DOWNLOADABLE",
      "DOSSIER_DOCUMENT_SOURCE_INVALID",
    ].includes(code)
  ) return response(403, "OPERATOR_NOT_AUTHORIZED");
  if (
    [
      "PROJECT_SCOPE_DENIED",
      "COMMAND_PERMISSION_DENIED",
    ].includes(code)
  ) return response(403, "INSUFFICIENT_PERMISSIONS");
  if (code === "IDEMPOTENCY_CONFLICT") return response(409, code);
  if (code === "STALE_BUSINESS_REVISION") return response(409, code);
  if (code === "APPROVAL_CONFLICT") return response(409, code);
  if (code === "CONCURRENT_MODIFICATION") return response(409, code);
  if (code === "APPLICATION_NOT_FOUND") return response(404, code);
  if (code === "CUSTOMER_REQUEST_UPLOAD_NOT_FOUND") return response(404, code);
  if (code === "APPROVAL_NOT_FOUND") {
    return response(404, "QUOTATION_APPROVAL_NOT_FOUND");
  }
  if (code === "AMBIGUOUS_SUPPORT_REFERENCE") return response(409, code);
  if (code === "INTAKE_NOT_FOUND") return response(404, code);
  if (code === "SDF_M1_OBLIGATION_REQUIRED") {
    return response(404, "NOT_FOUND");
  }
  if (code === "SDF_INVOICE_TEMPLATE_AUTHORITY_REQUIRED") {
    return response(404, "NOT_FOUND");
  }
  if (code === "SDF_M1_INVOICE_CANDIDATE_CONFLICT") {
    return response(409, "CONFLICT");
  }
  if (
    code === "SDF_APPLICATION_REFERENCE_REQUIRED" ||
    code === "SDF_M1_INVOICE_CANDIDATE_LINKAGE_MISMATCH"
  ) return response(409, "VALIDATION_FAILED");
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
  if (code === "OPERATOR_DOSSIER_ASSIGNMENT_STATE_REQUIRED") {
    return response(409, "COMMAND_REJECTED");
  }
  if (code === "INTERNAL_E2E_RUN_NOT_FOUND") return response(404, code);
  if (code === "PROJECT_NOT_FOUND") return response(404, code);
  if (code === "APPLICATION_NOT_ACCEPTED") return response(409, code);
  if (["PROJECT_SITE_ALREADY_BOUND", "PROJECT_SITE_NOT_BOUND"].includes(code)) {
    return response(409, "COMMAND_REJECTED");
  }
  if (
    [
      "INTERNAL_E2E_RUN_FINALIZED",
      "INTERNAL_E2E_PROMOTION_DENIED",
      "INTERNAL_E2E_QUOTATION_DENIED",
    ].includes(code)
  ) return response(409, code);
  if (
    [
      "ACCEPTED_INTERNAL_E2E_FILE_REQUIRED",
      "INTERNAL_E2E_FILE_ALREADY_DELETED",
      "INTERNAL_E2E_FILE_CLEANUP_ALREADY_AUTHORIZED",
      "INTERNAL_E2E_FILE_CLEANUP_ALREADY_FINALIZED",
      "INTERNAL_E2E_STORAGE_OBJECT_STILL_EXISTS",
    ].includes(code)
  ) return response(409, "COMMAND_REJECTED");
  if (
    [
      "INVALID_APPLICATION_REFERENCE",
      "INVALID_SUPPORT_REFERENCE",
      "INVALID_PROJECT_SITE_COMMAND",
      "EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED",
      "INVALID_PAGINATION",
      "IDEMPOTENCY_KEY_REQUIRED",
      "INVALID_INTAKE_LIFECYCLE_COMMAND",
      "INVALID_DOSSIER_LIFECYCLE_COMMAND",
      "INVALID_INTERNAL_E2E_REQUEST",
      "INVALID_OPERATOR_CURSOR_POSITION",
      "INVALID_OPERATOR_ZONE",
      "INVALID_OPERATOR_OPERATIONAL_STATUS_FILTER",
      "INVALID_OPERATOR_REQUEST_KIND_FILTER",
      "INVALID_OPERATOR_YEAR",
      "INVALID_OPERATOR_QUARTER",
      "INVALID_OPERATOR_PAGE_LIMIT",
      "INVALID_OPERATOR_SEARCH",
      "INVALID_DOSSIER_REFERENCE",
      "INVALID_DOSSIER_ASSIGNMENT_COMMAND",
      "REASSIGNMENT_REASON_REQUIRED",
      "INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT",
      "INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR",
      "INVALID_CUSTOMER_REQUEST_LIST_LIMIT",
      "INVALID_CUSTOMER_REQUEST_LIST_CURSOR",
      "INVALID_CUSTOMER_REQUEST_ACTION",
      "INVALID_CUSTOMER_REQUEST_COMMAND",
      "WORKFORCE_DATE_RANGE_REQUIRED",
      "WORKFORCE_DATE_RANGE_REVERSED",
      "WORKFORCE_DATE_RANGE_TOO_LARGE",
      "INVALID_RECRUITMENT_VACANCY_STATUS",
      "RECRUITMENT_VACANCY_DRAFT_REVERSION_DENIED",
      "RECRUITMENT_VACANCY_MUST_BE_PUBLISHED_BEFORE_CLOSE",
    ].includes(code)
  ) return response(400, "INVALID_REQUEST");
  if (code === "RECRUITMENT_VACANCY_NOT_FOUND") return response(404, code);
  if (code.includes("recruitment_vacancies_slug_key") || code === "23505") {
    return response(409, "RECRUITMENT_VACANCY_SLUG_CONFLICT");
  }
  if (code === "INVALID_OPERATOR_CURSOR") return response(400, code);
  if (
    code === "OPERATOR_CURSOR_CONFIGURATION_ERROR" ||
    code === "SERVER_CONFIGURATION_ERROR"
  ) {
    return response(500, "SERVER_CONFIGURATION_ERROR");
  }
  if (
    [
      "QUOTATION_ADMIN_CAPABILITY_UNAVAILABLE",
      "APPROVAL_INTEGRITY_INVALID",
      "QUOTATION_TEMPLATE_NOT_APPROVED",
      "QUOTATION_VAT_BINDING_REQUIRED",
      "SELLER_IDENTITY_INVALID",
    ].includes(code)
  ) return response(409, "QUOTATION_NOT_ISSUABLE");
  if (
    [
      "QUOTATION_ORCHESTRATION_CONTEXT_INVALID",
      "QUOTATION_ISSUANCE_PREPARATION_INVALID",
      "QUOTATION_ISSUE_PAYLOAD_INVALID",
      "QUOTATION_TEMPLATE_HASH_INVALID",
      "QUOTATION_RENDER_INVALID",
      "QUOTATION_ARTIFACT_HASH_MISMATCH",
      "QUOTATION_ARTIFACT_COMMIT_INVALID",
    ].includes(code)
  ) return response(500, "QUOTATION_GENERATION_FAILED");
  if (
    [
      "QUOTATION_ARTIFACT_UPLOAD_FAILED",
      "QUOTATION_ARTIFACT_ARCHIVE_INVALID",
    ].includes(code)
  ) return response(500, "QUOTATION_ARCHIVE_FAILED");
  if (code === "QUOTATION_DELIVERY_FAILED") return response(502, code);
  if (
    [
      "INVALID_STATE",
      "PAYMENT_NOT_MATCHED",
      "ACCESS_DENIED",
      "INVALID_INTAKE_LIFECYCLE_TRANSITION",
      "INVALID_OPERATOR_DOSSIER_TRANSITION",
      "INVALID_OPERATOR_DOSSIER_RESTORE",
      "TRASHED_DOSSIER_BLOCKER_CREATION_DENIED",
      "INVALID_CUSTOMER_REQUEST_TRANSITION",
      "CUSTOMER_REQUEST_TERMINAL",
      "CUSTOMER_REQUEST_UPLOAD_NOT_ACCEPTED",
      "CUSTOMER_REQUEST_UPLOAD_SOURCE_INVALID",
      "CUSTOMER_REQUEST_UPLOAD_SOURCE_OBJECT_NOT_FOUND",
      "CUSTOMER_REQUEST_UPLOAD_SOURCE_CONTENT_MISMATCH",
      "CUSTOMER_REQUEST_UPLOAD_PROMOTION_CONFLICT",
      "DOCUMENT_INBOX_PROMOTION_OBJECT_NOT_FOUND",
      "DOCUMENT_INBOX_PROMOTION_OBJECT_MISMATCH",
      "DOCUMENT_INBOX_BINARY_IDENTITY_MISMATCH",
      "QUOTATION_INTAKE_NOT_AVAILABLE",
      "PRICING_INTEGRITY_INVALID",
      "QUOTATION_TERMS_NOT_APPROVED",
      "QUOTATION_VAT_DECISION_NOT_APPROVED",
      "PRICING_RULE_NOT_FOUND",
      "PRICING_RULE_NOT_EXACT",
      "PRICING_RULE_QUANTITY_MISMATCH",
      "PRICING_RULE_AMOUNT_MISMATCH",
      "QUOTATION_BUSINESS_PAYLOAD_INVALID",
    ].includes(code)
  ) return response(409, "COMMAND_REJECTED");
  if (code === "CUSTOMER_REQUEST_UPLOAD_STORAGE_BRIDGE_FAILED") {
    return response(502, "STORAGE_OPERATION_FAILED");
  }
  if (code.startsWith("LEGACY_TEST_CLEANUP_")) {
    return response(409, "COMMAND_REJECTED");
  }
  return response(500, "INTERNAL_ERROR");
}

export async function executeSdfM1InvoicePreparationTransport(
  client: DossierAssignmentRpcClient,
  input: SdfM1InvoicePreparationActionInput,
): Promise<Readonly<Record<string, unknown>>> {
  const { data, error } = await client.rpc(
    "prepare_sdf_m1_invoice_candidate_v1",
    {
      p_obligation_id: input.obligation_id,
      p_template_authority_id: input.template_authority_id,
      p_idempotency_key: input.idempotency_key,
    },
  );
  if (error) throw new Error(error.message);
  if (
    !isRecord(data) ||
    !hasExactKeys(data, [
      "candidate_id",
      "candidate_state",
      "invoice_number",
      "was_created",
    ]) ||
    !UUID.test(String(data.candidate_id || "")) ||
    data.candidate_state !== "PREPARED" ||
    data.invoice_number !== null ||
    typeof data.was_created !== "boolean"
  ) {
    throw new Error("INVALID_SDF_M1_INVOICE_PREPARATION_RESPONSE");
  }
  return { obligation_id: input.obligation_id, ...data };
}

export async function executeDossierAssignmentReadTransport(
  client: DossierAssignmentRpcClient,
  input: DossierAssignmentReadInput,
): Promise<unknown> {
  const { data, error } = await client.rpc(
    "get_operator_dossier_assignment_v1",
    {
      p_dossier_reference: input.dossier_reference,
    },
  );
  if (error) throw new Error(error.message);
  return data;
}

export async function executeAssignmentOperatorRosterTransport(
  client: DossierAssignmentRpcClient,
): Promise<
  ReadonlyArray<Readonly<{ operator_id: string; display_name: string }>>
> {
  const { data, error } = await client.rpc(
    "get_operations_manager_roster_v1",
    {},
  );
  if (error) throw new Error(error.message);
  if (!Array.isArray(data)) {
    throw new Error("INVALID_ASSIGNMENT_ROSTER_RESPONSE");
  }
  return (data as AssignmentRosterRow[])
    .filter((row) =>
      row?.role === "operator" &&
      row?.status === "ACTIVE" &&
      UUID.test(String(row.operator_id || "")) &&
      typeof row.display_name === "string" &&
      row.display_name.length > 0
    )
    .map((row) => ({
      operator_id: String(row.operator_id),
      display_name: row.display_name as string,
    }));
}

export async function executeWorkforceCalendarTransport(
  client: DossierAssignmentRpcClient,
  actorAuthUserId: string,
  input: WorkforceCalendarActionInput,
): Promise<unknown> {
  const { data, error } = await client.rpc("list_workforce_calendar_v1", {
    p_actor_id: actorAuthUserId,
    p_start_date: input.start_date,
    p_end_date: input.end_date,
  });
  if (error) throw new Error(error.message);
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("INVALID_WORKFORCE_CALENDAR_RESPONSE");
  }
  const result = data as Record<string, unknown>;
  if (
    !hasExactKeys(result, ["start_date", "end_date", "employees"]) ||
    result.start_date !== input.start_date ||
    result.end_date !== input.end_date ||
    !Array.isArray(result.employees)
  ) throw new Error("INVALID_WORKFORCE_CALENDAR_RESPONSE");
  for (const employeeValue of result.employees) {
    if (
      !employeeValue || typeof employeeValue !== "object" ||
      Array.isArray(employeeValue)
    ) throw new Error("INVALID_WORKFORCE_CALENDAR_RESPONSE");
    const employee = employeeValue as Record<string, unknown>;
    if (
      !hasExactKeys(employee, [
        "employee_id",
        "display_name",
        "role_title",
        "team_name",
        "employment_status",
        "entries",
      ]) ||
      !UUID.test(String(employee.employee_id || "")) ||
      typeof employee.display_name !== "string" ||
      employee.display_name.length < 1 ||
      (employee.role_title !== null &&
        typeof employee.role_title !== "string") ||
      (employee.team_name !== null && typeof employee.team_name !== "string") ||
      !["ACTIVE", "INACTIVE"].includes(
        String(employee.employment_status || ""),
      ) ||
      !Array.isArray(employee.entries)
    ) throw new Error("INVALID_WORKFORCE_CALENDAR_RESPONSE");
    for (const entryValue of employee.entries) {
      if (
        !entryValue || typeof entryValue !== "object" ||
        Array.isArray(entryValue)
      ) throw new Error("INVALID_WORKFORCE_CALENDAR_RESPONSE");
      const entry = entryValue as Record<string, unknown>;
      if (
        !hasExactKeys(entry, ["date", "status"]) ||
        !isValidCalendarDate(entry.date) ||
        entry.date < input.start_date || entry.date > input.end_date ||
        !WORKFORCE_CALENDAR_STATUSES.has(String(entry.status || ""))
      ) {
        throw new Error("INVALID_WORKFORCE_CALENDAR_RESPONSE");
      }
    }
  }
  return result;
}

export async function executeDossierAssignmentMutationTransport(
  client: DossierAssignmentRpcClient,
  input: DossierAssignmentMutationInput,
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
  input: DossierLifecycleTransportInput,
): Promise<unknown> {
  const capabilityResult = await issueCapability({
    p_actor_auth_user_id: actorAuthUserId,
    p_quote_request_id: input.quote_request_id,
    p_event_type: input.event_type,
    p_expected_revision: input.expected_revision,
    p_idempotency_key: input.idempotency_key,
    p_reason: input.reason,
  });
  if (
    capabilityResult.error || !UUID.test(String(capabilityResult.data || ""))
  ) {
    throw new Error(
      capabilityResult.error?.message || "SERVER_CONFIGURATION_ERROR",
    );
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
  "document_id",
  "source_type",
  "document_type",
  "artifact_type",
  "title",
  "filename",
  "status",
  "created_at",
  "accepted_at",
  "source_record_id",
  "version",
  "sha256",
  "quote_request_id",
  "customer_id",
  "project_id",
  "can_open",
  "can_download",
];

function isNullableUuid(value: unknown): boolean {
  return value === null || UUID.test(String(value));
}

function isNullableString(value: unknown): boolean {
  return value === null || typeof value === "string";
}

function validateDossierDocumentManifest(
  value: unknown,
  quoteRequestId: string,
) {
  if (!Array.isArray(value)) {
    throw new Error("INVALID_DOSSIER_DOCUMENT_MANIFEST_RESPONSE");
  }
  return value.map((item) => {
    if (
      !isRecord(item) ||
      !hasExactKeys(item, DOSSIER_DOCUMENT_MANIFEST_FIELDS) ||
      !UUID.test(String(item.document_id)) ||
      !UUID.test(String(item.source_record_id)) ||
      item.quote_request_id !== quoteRequestId ||
      !["QUOTATION", "QUOTATION_ARTIFACT", "CUSTOMER_UPLOAD"].includes(
        String(item.source_type),
      ) ||
      !["QUOTATION", "CUSTOMER_UPLOAD"].includes(String(item.document_type)) ||
      !isNullableString(item.artifact_type) || typeof item.title !== "string" ||
      item.title.length < 1 ||
      !isNullableString(item.filename) || typeof item.status !== "string" ||
      item.status.length < 1 ||
      typeof item.created_at !== "string" ||
      !Number.isFinite(Date.parse(item.created_at)) ||
      (item.accepted_at !== null &&
        (typeof item.accepted_at !== "string" ||
          !Number.isFinite(Date.parse(item.accepted_at)))) ||
      !isNullableString(item.version) || !isNullableString(item.sha256) ||
      !isNullableUuid(item.customer_id) || !isNullableUuid(item.project_id) ||
      typeof item.can_open !== "boolean" ||
      typeof item.can_download !== "boolean" ||
      (item.source_type === "QUOTATION" &&
        (item.filename !== null || item.can_open || item.can_download)) ||
      (item.source_type === "QUOTATION_ARTIFACT" &&
        (item.document_type !== "QUOTATION" ||
          typeof item.artifact_type !== "string" ||
          typeof item.filename !== "string")) ||
      (item.source_type === "CUSTOMER_UPLOAD" &&
        (item.document_type !== "CUSTOMER_UPLOAD" ||
          item.artifact_type !== null || typeof item.filename !== "string"))
    ) {
      throw new Error("INVALID_DOSSIER_DOCUMENT_MANIFEST_RESPONSE");
    }
    return item;
  });
}

export async function executeDossierDocumentManifestTransport(
  client: DossierAssignmentRpcClient,
  actorAuthUserId: string,
  input: Extract<
    DossierDocumentActionInput,
    { action: "get_dossier_document_manifest" }
  >,
): Promise<unknown> {
  const { data, error } = await client.rpc(
    "get_operator_dossier_document_manifest_v1",
    {
      p_actor_auth_user_id: actorAuthUserId,
      p_quote_request_id: input.quote_request_id,
    },
  );
  if (error) throw new Error(error.message);
  return validateDossierDocumentManifest(data, input.quote_request_id);
}

export async function executeDossierDocumentAccessTransport(
  client: DossierAssignmentRpcClient,
  actorAuthUserId: string,
  input: Extract<
    DossierDocumentActionInput,
    { action: "create_dossier_document_access" }
  >,
  createSignedUrl: (
    bucket: string,
    path: string,
    expiresInSeconds: number,
    filename: string,
  ) => PromiseLike<string>,
  now: () => number = () => Date.now(),
): Promise<
  Readonly<{ signed_url: string; expires_at: string; filename: string }>
> {
  const { data, error } = await client.rpc(
    "authorize_operator_dossier_document_download_v1",
    {
      p_actor_auth_user_id: actorAuthUserId,
      p_quote_request_id: input.quote_request_id,
      p_source_type: input.source_type,
      p_document_id: input.document_id,
    },
  );
  if (error) throw new Error(error.message);
  if (
    !isRecord(data) || !hasExactKeys(data, [
      "state",
      "document_id",
      "source_type",
      "storage_bucket_id",
      "storage_object_path",
      "filename",
      "expires_in_seconds",
    ]) || data.state !== "AUTHORIZED" ||
    data.document_id !== input.document_id ||
    data.source_type !== input.source_type ||
    typeof data.storage_bucket_id !== "string" ||
    data.storage_bucket_id.length < 1 ||
    typeof data.storage_object_path !== "string" ||
    data.storage_object_path.length < 1 || typeof data.filename !== "string" ||
    data.filename.length < 1 || data.expires_in_seconds !== 60
  ) {
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
  if (!["http:", "https:"].includes(parsedUrl.protocol)) {
    throw new Error("INVALID_DOSSIER_DOCUMENT_SIGNED_URL");
  }
  return {
    signed_url: signedUrl,
    expires_at: new Date(now() + 60_000).toISOString(),
    filename: data.filename,
  };
}

export async function handleCommercialOperator(
  request: Request,
  deps: CommercialOperatorDependencies,
): Promise<Response> {
  try {
    if (request.method !== "POST") {
      throw new RequestError(405, "METHOD_NOT_ALLOWED");
    }
    const jwt = bearer(request),
      claims = decodeClaims(jwt),
      sub = String(claims.sub || "");
    if (
      !UUID.test(sub) || typeof claims.exp !== "number" ||
      claims.exp * 1000 <= deps.now()
    ) throw new RequestError(401, "INVALID_JWT");
    if (claims.role === "service_role") {
      throw new RequestError(401, "HUMAN_JWT_REQUIRED");
    }
    const user = await deps.verifyUser(jwt);
    if (!user || user.id !== sub) throw new RequestError(401, "INVALID_JWT");
    const parsed = await body(request);
    if ("action" in parsed) {
      if (
        [
          "list_applications_v2",
          "get_application_facets_v2",
          "get_dossier_substance",
          "list_pending_intakes",
          "list_pending_sdf_qualification_intakes",
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
      if (input.action === "get_dossier_substance") {
        const result = validateDossierSubstanceResult(
          await deps.executeDossierSubstance(user.id, String(input.quote_request_id)),
        );
        return response(200, "APPLICATION_ACTION_ACCEPTED", { result });
      }
      if (input.action === "list_applications_v2") {
        const cursorPosition = typeof input.cursor === "string"
          ? await deps.verifyOperatorCursor(input.cursor, input)
          : null;
        const raw = await deps.executeApplicationListV2(
          user.id,
          input,
          cursorPosition,
        );
        if (
          !raw || typeof raw !== "object" || !Array.isArray(raw.items) ||
          typeof raw.has_more !== "boolean" ||
          (raw.has_more &&
            (!raw.next_position || typeof raw.next_position !== "object")) ||
          (!raw.has_more && raw.next_position !== null)
        ) {
          throw new Error("INVALID_OPERATOR_CORE_RESPONSE");
        }
        const nextPosition = raw.next_position;
        const nextCursor = raw.has_more && nextPosition !== null
          ? await deps.signOperatorCursor(nextPosition, input)
          : null;
        return response(200, "APPLICATION_ACTION_ACCEPTED", {
          result: { items: raw.items, has_more: raw.has_more, next_cursor: nextCursor },
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
    if (!limit.allowed) {
      return response(429, "RATE_LIMITED", {
        retry_after_seconds: limit.retry_after_seconds,
      });
    }
    const result = await deps.executeCommand(jwt, input);
    return response(200, "COMMAND_ACCEPTED", {
      result,
    });
  } catch (error) {
    if (error instanceof RequestError) {
      return response(error.status, error.code);
    }
    return mapDatabaseError(error);
  }
}

export async function withCommercialOperatorCors(
  request: Request,
  next: () => Response | Promise<Response>,
): Promise<Response> {
  const origin = request.headers.get("origin");
  const blocked = rejectIfOriginNotAllowed(request);
  if (blocked) return blocked;
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  const response = await next();
  const headers = new Headers(response.headers);
  new Headers(corsHeaders(origin)).forEach((value, name) =>
    headers.set(name, value)
  );
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
export function createUnsignedTestJwt(
  payload: Record<string, unknown>,
): string {
  const encode = (value: Record<string, unknown>) =>
    btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(
      /=+$/g,
      "",
    );
  return `${
    encode({
      alg: "RS256",
      typ: "JWT",
    })
  }.${encode(payload)}.signature`;
}

export async function executeOperatorPersonalQueueTransport(
  client: DossierAssignmentRpcClient,
  input: OperatorPersonalQueueInput,
): Promise<unknown> {
  const { data, error } = await client.rpc(
    "get_operator_personal_dossier_queue_v1",
    {
      p_cursor: input.cursor,
      p_limit: input.limit,
    },
  );
  if (error) throw new Error(error.message);
  return data;
}

export async function executeCustomerRequestTransport(
  client: DossierAssignmentRpcClient,
  input: CustomerRequestActionInput,
): Promise<unknown> {
  const request = input.action === "create_sdf_customer_request"
    ? client.rpc("create_sdf_customer_request_v1", {
      p_quote_request_id: input.quote_request_id,
      p_idempotency_key: input.idempotency_key,
      p_request_type: input.request_type,
      p_title: input.title,
      p_description: input.description,
      p_priority: input.priority,
    })
    : input.action === "list_customer_requests_for_dossier"
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
  client: DossierAssignmentRpcClient,
): Promise<CurrentOperatorIdentity> {
  const { data, error } = await client.rpc(
    "get_current_operator_identity_v1",
    {},
  );
  if (error) throw new Error(error.message);
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("INVALID_OPERATOR_IDENTITY_RESPONSE");
  }
  const identity = data as Record<string, unknown>;
  if (
    Object.keys(identity).length !== 3 ||
    typeof identity.display_name !== "string" || !identity.display_name ||
    ![
      "owner",
      "operations_manager",
      "operator",
      "reviewer",
      "read_only",
      "admin",
    ].includes(String(identity.role || "")) ||
    identity.status !== "ACTIVE"
  ) {
    throw new Error("INVALID_OPERATOR_IDENTITY_RESPONSE");
  }
  return identity as CurrentOperatorIdentity;
}

const RECRUITMENT_VACANCY_KEYS = [
  "id",
  "title",
  "slug",
  "department",
  "location",
  "employment_type",
  "summary",
  "description",
  "requirements",
  "status",
  "published_at",
  "closed_at",
  "created_at",
  "updated_at",
];

function validateRecruitmentVacancy(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("INVALID_RECRUITMENT_VACANCY_RESPONSE");
  }
  const vacancy = value as Record<string, unknown>;
  if (
    !hasExactKeys(vacancy, RECRUITMENT_VACANCY_KEYS) ||
    !UUID.test(String(vacancy.id || "")) ||
    !["DRAFT", "PUBLISHED", "CLOSED"].includes(String(vacancy.status || "")) ||
    ![
      "title",
      "slug",
      "department",
      "location",
      "employment_type",
      "summary",
      "description",
      "requirements",
    ].every((key) =>
      typeof vacancy[key] === "string" && String(vacancy[key]).length > 0
    ) ||
    !["created_at", "updated_at"].every((key) =>
      typeof vacancy[key] === "string" &&
      Number.isFinite(Date.parse(String(vacancy[key])))
    ) ||
    !["published_at", "closed_at"].every((key) =>
      vacancy[key] === null ||
      (typeof vacancy[key] === "string" &&
        Number.isFinite(Date.parse(String(vacancy[key]))))
    )
  ) {
    throw new Error("INVALID_RECRUITMENT_VACANCY_RESPONSE");
  }
  return vacancy;
}

export async function executeRecruitmentVacancyTransport(
  client: DossierAssignmentRpcClient,
  input: RecruitmentVacancyActionInput,
): Promise<unknown> {
  const rpc = input.action === "get_recruitment_publication_state"
    ? ["get_public_recruitment_publication_state_v1", {}] as const
    : input.action === "set_recruitment_publication_enabled"
    ? ["set_recruitment_publication_enabled_v1", {
      p_enabled: input.enabled,
    }] as const
    : input.action === "list_recruitment_vacancies"
    ? ["list_owner_recruitment_vacancies_v1", {}] as const
    : input.action === "create_recruitment_vacancy"
    ? ["create_recruitment_vacancy_v1", {
      p_title: input.title,
      p_slug: input.slug,
      p_department: input.department,
      p_location: input.location,
      p_employment_type: input.employment_type,
      p_summary: input.summary,
      p_description: input.description,
      p_requirements: input.requirements,
    }] as const
    : input.action === "update_recruitment_vacancy"
    ? ["update_recruitment_vacancy_v1", {
      p_vacancy_id: input.vacancy_id,
      p_title: input.title,
      p_department: input.department,
      p_location: input.location,
      p_employment_type: input.employment_type,
      p_summary: input.summary,
      p_description: input.description,
      p_requirements: input.requirements,
    }] as const
    : ["set_recruitment_vacancy_status_v1", {
      p_vacancy_id: input.vacancy_id,
      p_status: input.status,
    }] as const;
  const { data, error } = await client.rpc(rpc[0], rpc[1]);
  if (error) throw new Error(error.message);
  if (
    input.action === "get_recruitment_publication_state" ||
    input.action === "set_recruitment_publication_enabled"
  ) {
    if (
      !data || typeof data !== "object" || Array.isArray(data) ||
      !hasExactKeys(data as Record<string, unknown>, ["enabled"]) ||
      typeof (data as Record<string, unknown>).enabled !== "boolean"
    ) {
      throw new Error("INVALID_RECRUITMENT_PUBLICATION_RESPONSE");
    }
    return data;
  }
  if (input.action === "list_recruitment_vacancies") {
    if (!Array.isArray(data)) {
      throw new Error("INVALID_RECRUITMENT_VACANCY_RESPONSE");
    }
    return data.map(validateRecruitmentVacancy);
  }
  const result = data as Record<string, unknown>;
  const expectedKeys = input.action === "set_recruitment_vacancy_status"
    ? ["id", "slug", "status", "published_at", "closed_at"]
    : ["id", "slug", "status"];
  if (
    !result || typeof result !== "object" || Array.isArray(result) ||
    !hasExactKeys(result, expectedKeys) ||
    !UUID.test(String(result.id || "")) ||
    typeof result.slug !== "string" ||
    !["DRAFT", "PUBLISHED", "CLOSED"].includes(String(result.status || "")) ||
    (input.action === "create_recruitment_vacancy" &&
      result.status !== "DRAFT") ||
    (input.action === "set_recruitment_vacancy_status" && (
      result.status !== input.status ||
      !["published_at", "closed_at"].every((key) =>
        result[key] === null ||
        (typeof result[key] === "string" &&
          Number.isFinite(Date.parse(String(result[key]))))
      )
    ))
  ) {
    throw new Error("INVALID_RECRUITMENT_VACANCY_RESPONSE");
  }
  return result;
}

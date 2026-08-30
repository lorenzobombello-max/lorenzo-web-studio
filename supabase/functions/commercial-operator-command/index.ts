import { createClient } from "npm:@supabase/supabase-js@2";
import {
  executeAssignmentOperatorRosterTransport,
  executeDossierAssignmentMutationTransport,
  executeDossierAssignmentReadTransport,
  executeDossierDocumentAccessTransport,
  executeDossierDocumentManifestTransport,
  executeDossierLifecycleTransport,
  executeCustomerRequestTransport,
  executeCurrentOperatorIdentityTransport,
  executeOperatorPersonalQueueTransport,
  executeRecruitmentVacancyTransport,
  executeWorkforceCalendarTransport,
  handleCommercialOperator,
  type InternalE2EAcceptedFileCleanupActionInput,
  type DossierDocumentActionInput,
  type CustomerRequestActionInput,
  type CustomerRequestUploadOperatorActionInput,
  type QuotationBusinessApprovalPromotionActionInput,
  type QuotationBusinessDraftActionInput,
  type QuotationIssuanceActionInput,
  type RecruitmentVacancyActionInput,
  type WorkforceCalendarActionInput,
  withCommercialOperatorCors
} from "./handler.ts";
import { deliverIssuedQuotation } from "../_shared/quotation-email-orchestration.ts";
import { orchestrateApprovedQuotation } from "./quotation-orchestrator.ts";
import {
  createQuotationRuntimeDependencies,
  type QuotationRuntimeOptions,
} from "./quotation-runtime.ts";
import { renderQuotationDocxBytes } from "./quotation-renderer-edge.ts";
import {
  enrichOperatorApplicationDetailWithOutput,
  loadSubmittedApplicationOutputForOperator,
} from "../_shared/submitted-application-output.ts";
import { buildCustomerRequestUploadUrl, deriveCustomerRequestUploadCapabilityToken, hashCustomerRequestUploadCapabilityToken } from "../_shared/customer-request-upload-capability.ts";
import {
  createApprovalTokenForIdempotencyKey,
  createInternalE2EIntakeTokenForIdempotencyKey,
  deriveAdminIntakeCapability,
  hashAdminIntakeToken,
  hashApprovalToken,
  hashIntakeToken,
} from "../_shared/security.ts";
import {
  signOperatorCursor,
  verifyOperatorCursor,
  type OperatorCursorPosition,
  type OperatorCursorRequest,
} from "../_shared/operator-cursor.ts";
import {
  createQuotationApprovalIntegrity,
  QUOTATION_APPROVAL_INTEGRITY_VERSION,
  verifyQuotationApprovalIntegrity,
  type QuotationApprovalIntegrity,
  type QuotationApprovalIntegrityRoot,
} from "../_shared/quotation-approval-integrity.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type OperatorApplicationCursorInput = Readonly<{
  zone: OperatorCursorRequest["zone"];
  operational_status: string | null;
  year?: number | null;
  quarter?: OperatorCursorRequest["quarter"];
  request_kind: OperatorCursorRequest["requestKind"];
  search: string | null;
}>;

type OperatorApplicationListV2Input = OperatorApplicationCursorInput & Readonly<{
  year: number | null;
  quarter: OperatorCursorRequest["quarter"];
  cursor: string | null;
  limit: number;
}>;

type OperatorApplicationFacetsV2Input = Omit<OperatorApplicationCursorInput, "year" | "quarter">;
type DossierAssignmentActionInput = Readonly<{
  action: "get_dossier_assignment";
  dossier_reference: string;
}> | Readonly<{
  action: "assign_dossier";
  dossier_reference: string;
  assignee_operator_id: string;
  expected_revision: number;
  idempotency_key: string;
  reason: string | null;
}>;
type DossierAssignmentClient = Parameters<typeof executeDossierAssignmentReadTransport>[0];
type DossierDocumentServiceClient = DossierAssignmentClient & Readonly<{
  storage: Readonly<{
    from(bucket: string): Readonly<{
      createSignedUrl(
        path: string,
        expiresIn: number,
        options: Readonly<{ download: string }>,
      ): PromiseLike<Readonly<{ data: Readonly<{ signedUrl: string }> | null; error: Readonly<{ message: string }> | null }>>;
    }>;
  }>;
}>;
type ValidatedApplicationActionInput = Record<string, unknown> & Readonly<{
  action: string;
  intake_id: string;
  event_type: string;
  expected_revision: number;
  idempotency_key: string;
  reason: string | null;
  quote_request_id: string | null;
  project_id: string;
  operation: string;
  canonical_domain: string;
  evidence: string;
  run_id: string;
  terminal_status: string;
  run_label: string;
  ttl_minutes: number;
  limit: number;
  cursor: string | null;
  offset: number;
  support_reference: string | null;
  application_reference: string | null;
  dossier_reference: string;
  assignee_operator_id: string;
  request_id: string;
  upload_request_id: string;
  uploaded_file_id: string;
  start_date: string;
  end_date: string;
  input: Record<string, unknown>;
}>;
type ValidatedDossierLifecycleActionInput = ValidatedApplicationActionInput & Readonly<{
  action: "archive_dossier" | "reactivate_dossier" | "trash_dossier" | "restore_dossier";
  quote_request_id: string;
  reason: string;
}>;
type ValidatedCommercialCommandInput = Readonly<{
  project_id: string;
  command_type: string;
  expected_state: string;
  expected_revision: number;
  idempotency_key: string;
  payload: Record<string, unknown>;
}>;

type OperatorCursorDatabasePosition = Readonly<{
  dossier_date: string;
  quote_request_id: string;
}>;

async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte)=>byte.toString(16).padStart(2, "0")).join("");
}

function isDossierLifecycleAction(input: ValidatedApplicationActionInput): input is ValidatedDossierLifecycleActionInput {
  return input.action === "archive_dossier"
    || input.action === "reactivate_dossier"
    || input.action === "trash_dossier"
    || input.action === "restore_dossier";
}

export async function executeCallerJwtDossierAssignmentAction(
  jwt: string,
  input: DossierAssignmentActionInput,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  const client = clientFor(jwt);
  return input.action === "get_dossier_assignment"
    ? await executeDossierAssignmentReadTransport(client, input)
    : await executeDossierAssignmentMutationTransport(client, input);
}

export async function executeCallerJwtAssignmentRosterAction(
  jwt: string,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  return await executeAssignmentOperatorRosterTransport(clientFor(jwt));
}

export async function executeCallerJwtOperatorPersonalQueueAction(
  jwt: string,
  input: Readonly<{ action: "get_my_assigned_dossiers"; cursor: string | null; limit: number }>,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  return await executeOperatorPersonalQueueTransport(clientFor(jwt), input);
}

export async function executeCallerJwtCurrentOperatorIdentityAction(
  jwt: string,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  return await executeCurrentOperatorIdentityTransport(clientFor(jwt));
}

export async function executeCallerJwtRecruitmentVacancyAction(
  jwt: string,
  input: RecruitmentVacancyActionInput,
  clientFor: (jwt: string)=>DossierAssignmentClient,
): Promise<unknown> {
  return await executeRecruitmentVacancyTransport(clientFor(jwt), input);
}

export async function executeServiceRoleWorkforceCalendarAction(
  actorAuthUserId: string,
  input: WorkforceCalendarActionInput,
  client: DossierAssignmentClient,
): Promise<unknown> {
  return await executeWorkforceCalendarTransport(client, actorAuthUserId, input);
}

export async function executeServiceRoleDossierDocumentAction(
  actorAuthUserId: string,
  input: DossierDocumentActionInput,
  client: DossierDocumentServiceClient,
  now: ()=>number = ()=>Date.now(),
): Promise<unknown> {
  if (input.action === "get_dossier_document_manifest") {
    return await executeDossierDocumentManifestTransport(client, actorAuthUserId, input);
  }
  return await executeDossierDocumentAccessTransport(
    client,
    actorAuthUserId,
    input,
    async (bucket, path, expiresInSeconds, filename)=>{
      const { data, error } = await client.storage.from(bucket).createSignedUrl(
        path,
        expiresInSeconds,
        { download: filename },
      );
      if (error || !data) throw new Error(error?.message || "INVALID_DOSSIER_DOCUMENT_SIGNED_URL");
      return data.signedUrl;
    },
    now,
  );
}

type QuotationBusinessDraftRpcClient = Readonly<{
  rpc(name: string, args: Record<string, unknown>): PromiseLike<Readonly<{
    data: unknown;
    error: Readonly<{ message: string }> | null;
  }>>;
}>;

type QuotationIssuanceRuntimeOptions = Omit<QuotationRuntimeOptions, "actorAuthUserId">;

export async function executeApprovedQuotationIssuanceAction(
  actorAuthUserId: string,
  input: QuotationIssuanceActionInput,
  options: QuotationIssuanceRuntimeOptions,
): Promise<unknown> {
  return await orchestrateApprovedQuotation(
    { actorAuthUserId, quoteRequestId: input.quote_request_id },
    createQuotationRuntimeDependencies({ actorAuthUserId, ...options }),
  );
}

export async function executeQuotationBusinessDraftAction(
  actorAuthUserId: string,
  input: QuotationBusinessDraftActionInput,
  client: QuotationBusinessDraftRpcClient
): Promise<unknown> {
  const { data, error } = await client.rpc("upsert_quotation_business_draft_v2", {
    p_actor_auth_user_id: actorAuthUserId,
    p_intake_id: input.intake_id,
    p_expected_revision: input.expected_revision,
    p_idempotency_key: input.idempotency_key,
    p_input: input.input,
  });
  if (error) throw new Error(error.message);
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("INVALID_QUOTATION_BUSINESS_DRAFT_RESPONSE");
  }
  const result = data as Record<string, unknown>;
  if (!UUID.test(String(result.approval_draft_id || ""))
    || !Number.isSafeInteger(result.business_revision) || Number(result.business_revision) < 1
    || !result.canonical_payload || typeof result.canonical_payload !== "object" || Array.isArray(result.canonical_payload)
    || typeof result.prepared_at !== "string" || typeof result.replayed !== "boolean") {
    throw new Error("INVALID_QUOTATION_BUSINESS_DRAFT_RESPONSE");
  }
  return {
    approval_draft_id: result.approval_draft_id,
    business_revision: result.business_revision,
    canonical_payload: result.canonical_payload,
    prepared_at: result.prepared_at,
    replayed: result.replayed,
  };
}

type QuotationBusinessApprovalPromotionOptions = Readonly<{
  createApprovalId(): string;
  getEnv(name: string): string | undefined;
}>;

const quotationBusinessApprovalPromotionDefaults: QuotationBusinessApprovalPromotionOptions = {
  createApprovalId: ()=>crypto.randomUUID(),
  getEnv: (name: string)=>Deno.env.get(name),
};

function promotionConfigurationError(): Error {
  return new Error("SERVER_CONFIGURATION_ERROR");
}

function promotionIntegritySecret(
  keyId: string,
  options: QuotationBusinessApprovalPromotionOptions,
): string {
  if (!/^v[1-9][0-9]*$/.test(keyId)) throw promotionConfigurationError();
  const secret = options.getEnv(`QUOTATION_APPROVAL_INTEGRITY_KEY_${keyId.toUpperCase()}`);
  if (!secret || new TextEncoder().encode(secret).byteLength < 32) throw promotionConfigurationError();
  return secret;
}

function requiredPromotionContext(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("APPROVAL_CONFLICT");
  const context = value as Record<string, unknown>;
  if (!new Set(["CREATE", "ADOPT"]).has(String(context.mode))
    || !UUID.test(String(context.business_draft_id || ""))
    || !Number.isSafeInteger(context.business_revision) || Number(context.business_revision) < 1
    || !UUID.test(String(context.approval_draft_id || ""))
    || !UUID.test(String(context.quote_request_id || ""))
    || !UUID.test(String(context.intake_id || ""))
    || !UUID.test(String(context.pricing_snapshot_id || ""))
    || context.contract_version !== 1
    || !/^[0-9a-f]{64}$/.test(String(context.payload_sha256 || ""))) {
    throw new Error("APPROVAL_CONFLICT");
  }
  return context;
}

function promotionRoot(context: Record<string, unknown>, approvalId: string): QuotationApprovalIntegrityRoot {
  return {
    approvalId,
    contractVersion: 1,
    intakeId: String(context.intake_id),
    integrityRootVersion: 1,
    payloadSha256: String(context.payload_sha256),
    pricingSnapshotId: String(context.pricing_snapshot_id),
    quoteRequestId: String(context.quote_request_id),
  };
}

function isExactPromotionRoot(
  value: unknown,
  expected: QuotationApprovalIntegrityRoot,
): value is QuotationApprovalIntegrityRoot {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const root = value as Record<string, unknown>;
  const keys = [
    "approvalId", "contractVersion", "intakeId", "integrityRootVersion",
    "payloadSha256", "pricingSnapshotId", "quoteRequestId",
  ];
  return Object.keys(root).length === keys.length
    && keys.every((key)=>key in root)
    && typeof root.approvalId === "string" && root.approvalId === expected.approvalId
    && typeof root.contractVersion === "number" && root.contractVersion === expected.contractVersion
    && typeof root.intakeId === "string" && root.intakeId === expected.intakeId
    && typeof root.integrityRootVersion === "number"
    && root.integrityRootVersion === expected.integrityRootVersion
    && typeof root.payloadSha256 === "string" && root.payloadSha256 === expected.payloadSha256
    && typeof root.pricingSnapshotId === "string"
    && root.pricingSnapshotId === expected.pricingSnapshotId
    && typeof root.quoteRequestId === "string" && root.quoteRequestId === expected.quoteRequestId;
}

function promotionResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("APPROVAL_CONFLICT");
  const result = value as Record<string, unknown>;
  if (!UUID.test(String(result.business_draft_id || ""))
    || !Number.isSafeInteger(result.business_revision) || Number(result.business_revision) < 1
    || !UUID.test(String(result.approval_id || ""))
    || !Number.isSafeInteger(result.approval_version) || Number(result.approval_version) < 1
    || result.status !== "APPROVED" || typeof result.approved_at !== "string"
    || typeof result.was_created !== "boolean") {
    throw new Error("APPROVAL_CONFLICT");
  }
  return {
    business_draft_id: result.business_draft_id,
    business_revision: result.business_revision,
    approval_id: result.approval_id,
    approval_version: result.approval_version,
    status: result.status,
    approved_at: result.approved_at,
    was_created: result.was_created,
  };
}

export async function executeQuotationBusinessApprovalPromotionAction(
  actorAuthUserId: string,
  input: QuotationBusinessApprovalPromotionActionInput,
  client: QuotationBusinessDraftRpcClient,
  options: QuotationBusinessApprovalPromotionOptions = quotationBusinessApprovalPromotionDefaults,
): Promise<unknown> {
  const resolved = await client.rpc("resolve_quotation_business_approval_promotion_context_v1", {
    p_actor_auth_user_id: actorAuthUserId,
    p_intake_id: input.intake_id,
    p_expected_revision: input.expected_revision,
  });
  if (resolved.error) throw new Error(resolved.error.message);
  const context = requiredPromotionContext(resolved.data);

  let approvalId: string;
  let integrity: QuotationApprovalIntegrity;
  if (context.mode === "CREATE") {
    approvalId = options.createApprovalId();
    if (!UUID.test(approvalId)) throw promotionConfigurationError();
    const keyId = options.getEnv("QUOTATION_APPROVAL_INTEGRITY_ACTIVE_KEY_ID") || "v1";
    try {
      integrity = await createQuotationApprovalIntegrity(
        promotionRoot(context, approvalId), keyId, promotionIntegritySecret(keyId, options),
      );
    } catch {
      throw promotionConfigurationError();
    }
  } else {
    approvalId = String(context.approval_id || "");
    const candidate = context.integrity;
    if (!UUID.test(approvalId) || !candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
      throw new Error("APPROVAL_CONFLICT");
    }
    integrity = candidate as QuotationApprovalIntegrity;
    if (integrity.algorithmVersion !== QUOTATION_APPROVAL_INTEGRITY_VERSION
      || !/^v[1-9][0-9]*$/.test(String(integrity.keyId || ""))
      || !/^[0-9a-f]{64}$/.test(String(integrity.mac || ""))
      || !isExactPromotionRoot(integrity.root, promotionRoot(context, approvalId))) {
      throw new Error("APPROVAL_CONFLICT");
    }
    if (!await verifyQuotationApprovalIntegrity(
      integrity, promotionIntegritySecret(integrity.keyId, options),
    )) throw new Error("APPROVAL_CONFLICT");
  }

  const promoted = await client.rpc("promote_quotation_business_draft_to_approval_v1", {
    p_actor_auth_user_id: actorAuthUserId,
    p_intake_id: input.intake_id,
    p_expected_revision: input.expected_revision,
    p_idempotency_key: input.idempotency_key,
    p_approval_id: approvalId,
    p_integrity: integrity,
  });
  if (promoted.error) throw new Error(promoted.error.message);
  return promotionResult(promoted.data);
}

export async function executeCallerJwtCustomerRequestAction(
  jwt: string,
  input: CustomerRequestActionInput,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  return await executeCustomerRequestTransport(clientFor(jwt), input);
}

export async function executeCallerJwtCustomerRequestSmokeFixtureAction(
  jwt: string,
  idempotencyKey: string,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  const { data, error } = await clientFor(jwt).rpc("create_customer_request_smoke_fixture_v1", {
    p_idempotency_key: idempotencyKey,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function executeCallerJwtCustomerRequestUploadAction(
  jwt: string,
  input: CustomerRequestUploadOperatorActionInput,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  const client = clientFor(jwt);
  if (input.action === "revoke_customer_request_upload_link") {
    const { data, error } = await client.rpc("revoke_customer_request_upload_request_v1", {
      p_upload_request_id: input.upload_request_id,
      p_reason: input.reason,
      p_idempotency_key: input.idempotency_key,
    });
    if (error) throw new Error(error.message);
    return data;
  }
  const token = await deriveCustomerRequestUploadCapabilityToken(input.request_id, input.idempotency_key);
  const tokenDigest = await hashCustomerRequestUploadCapabilityToken(token);
  const { data, error } = await client.rpc("create_customer_request_upload_request_v1", {
    p_request_id: input.request_id,
    p_token_digest: tokenDigest,
    p_requested_expires_at: null,
    p_idempotency_key: input.idempotency_key,
  });
  if (error || !data || typeof data !== "object" || Array.isArray(data) || (data as Record<string, unknown>).state !== "ACTIVE") {
    throw new Error(error?.message || "INVALID_UPLOAD_REQUEST_RESPONSE");
  }
  return { ...(data as Record<string, unknown>), upload_url: buildCustomerRequestUploadUrl(token) };
}

type InternalE2ECleanupStorageClient = Readonly<{
  storage: Readonly<{
    from(bucket: string): Readonly<{
      remove(paths: string[]): PromiseLike<Readonly<{
        data: unknown;
        error: Readonly<{ message: string }> | null;
      }>>;
    }>;
  }>;
}>;

export async function executeCallerJwtInternalE2EAcceptedFileCleanupAction(
  jwt: string,
  input: InternalE2EAcceptedFileCleanupActionInput,
  clientFor: (jwt: string)=>DossierAssignmentClient,
  serviceClient: ()=>InternalE2ECleanupStorageClient
): Promise<unknown> {
  const client = clientFor(jwt);
  const authorization = await client.rpc("authorize_internal_e2e_accepted_file_cleanup_v1", {
    p_run_id: input.run_id,
    p_request_id: input.request_id,
    p_upload_request_id: input.upload_request_id,
    p_uploaded_file_id: input.uploaded_file_id,
    p_idempotency_key: input.idempotency_key,
  });
  if (authorization.error || !authorization.data || typeof authorization.data !== "object" || Array.isArray(authorization.data)) {
    throw new Error(authorization.error?.message || "INVALID_INTERNAL_E2E_CLEANUP_AUTHORIZATION_RESPONSE");
  }
  const authorized = authorization.data as Record<string, unknown>;
  const cleanupAuthorizationId = String(authorized.cleanup_authorization_id || "");
  const bucket = String(authorized.storage_bucket_id || "");
  const path = String(authorized.storage_object_path || "");
  const expectedPath = new RegExp(
    `^requests/${input.request_id}/uploads/${input.upload_request_id}/files/${input.uploaded_file_id}\\.(?:pdf|png|jpg|jpeg)$`
  );
  if (authorized.state !== "AUTHORIZED" || !UUID.test(cleanupAuthorizationId)
      || bucket !== "customer-request-quarantine" || !expectedPath.test(path)) {
    throw new Error("INVALID_INTERNAL_E2E_CLEANUP_AUTHORIZATION_RESPONSE");
  }

  const removal = await serviceClient().storage.from(bucket).remove([path]);
  if (removal.error) throw new Error(removal.error.message);

  const finalization = await client.rpc("finalize_internal_e2e_accepted_file_cleanup_v1", {
    p_cleanup_authorization_id: cleanupAuthorizationId,
    p_idempotency_key: input.idempotency_key,
  });
  if (finalization.error) throw new Error(finalization.error.message);
  return finalization.data;
}

if (import.meta.main) Deno.serve((request)=>withCommercialOperatorCors(request, ()=>{
  const url = Deno.env.get("SUPABASE_URL"), anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) return new Response(JSON.stringify({
    ok: false,
    code: "SERVER_CONFIGURATION_ERROR"
  }), {
    status: 500,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store"
    }
  });
  const clientFor = (jwt: string)=>createClient(url, anonKey, {
      global: {
        headers: {
          Authorization: `Bearer ${jwt}`
        }
      },
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });
  const serviceClient = ()=>{
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceRoleKey) throw new Error("SERVER_CONFIGURATION_ERROR");
    return createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false }
    });
  };
  const cursorRequest = (input: OperatorApplicationCursorInput): OperatorCursorRequest=>({
    zone: input.zone,
    operationalStatus: input.operational_status,
    year: input.year ?? null,
    quarter: input.quarter ?? null,
    requestKind: input.request_kind,
    search: input.search,
  });
  return handleCommercialOperator(request, {
    now: ()=>Date.now(),
    verifyUser: async (jwt: string)=>{
      const { data, error } = await clientFor(jwt).auth.getUser(jwt);
      return error || !data.user ? null : {
        id: data.user.id
      };
    },
    authorizeApplicationReader: async (jwt: string)=>{
      const { error } = await clientFor(jwt).rpc("authorize_operator_application_reader_v2");
      if (error) throw new Error(error.message);
    },
    verifyOperatorCursor: async (cursor: string, input: OperatorApplicationListV2Input)=>
      await verifyOperatorCursor(cursor, cursorRequest(input)),
    signOperatorCursor: async (position: OperatorCursorDatabasePosition, input: OperatorApplicationListV2Input)=>await signOperatorCursor({
      dossierDate: position.dossier_date,
      quoteRequestId: position.quote_request_id,
    }, cursorRequest(input)),
    executeApplicationListV2: async (actorAuthUserId: string, input: OperatorApplicationListV2Input, position: OperatorCursorPosition | null)=>{
      const { data, error } = await serviceClient().rpc("list_operator_applications_v2", {
        p_actor_auth_user_id: actorAuthUserId,
        p_zone: input.zone,
        p_operational_status: input.operational_status,
        p_year: input.year,
        p_quarter: input.quarter,
        p_request_kind: input.request_kind,
        p_search: input.search,
        p_cursor_date: position?.dossierDate ?? null,
        p_cursor_id: position?.quoteRequestId ?? null,
        p_limit: input.limit,
      });
      if (error) throw new Error(error.message);
      return data;
    },
        executePendingIntakes: async (actorAuthUserId: string, retentionState: string) => {
          const { data, error } = await serviceClient().rpc(
            "list_operator_pending_intakes_v1",
            {
              p_actor_auth_user_id: actorAuthUserId,
              p_retention_state: retentionState,
            },
          );
          if (error) throw new Error(error.message);
          return data;
        },
        executePendingIntakeCount: async (actorAuthUserId: string) => {
          const { data, error } = await serviceClient().rpc(
            "count_operator_active_pending_intakes_v1",
            { p_actor_auth_user_id: actorAuthUserId },
          );
          if (error) throw new Error(error.message);
          return data;
        },
    executeApplicationFacetsV2: async (actorAuthUserId: string, input: OperatorApplicationFacetsV2Input)=>{
      const { data, error } = await serviceClient().rpc("get_operator_dossier_facets_v2", {
        p_actor_auth_user_id: actorAuthUserId,
        p_zone: input.zone,
        p_operational_status: input.operational_status,
        p_request_kind: input.request_kind,
        p_search: input.search,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    consumeRateLimit: async (jwt: string, projectId: string)=>{
      const { data, error } = await clientFor(jwt).rpc("consume_commercial_operator_rate_limit_v1", {
        p_project_id: projectId,
        p_max_requests: 60,
        p_window_seconds: 60
      });
      if (error) throw new Error(error.message);
      return data;
    },
    executeApplicationAction: async (jwt: string, input: ValidatedApplicationActionInput, actorAuthUserId: string)=>{
      if (input.action === "get_current_operator_identity") {
        return await executeCallerJwtCurrentOperatorIdentityAction(jwt, clientFor);
      }
      if (input.action === "get_assignment_operator_roster") {
        return await executeCallerJwtAssignmentRosterAction(jwt, clientFor);
      }
      if (input.action === "list_workforce_calendar") {
        return await executeServiceRoleWorkforceCalendarAction(
          actorAuthUserId,
          input as WorkforceCalendarActionInput,
          serviceClient(),
        );
      }
      if ([
        "list_recruitment_vacancies",
        "create_recruitment_vacancy",
        "update_recruitment_vacancy",
        "set_recruitment_vacancy_status",
        "get_recruitment_publication_state",
        "set_recruitment_publication_enabled",
      ].includes(input.action)) {
        return await executeCallerJwtRecruitmentVacancyAction(
          jwt,
          input as RecruitmentVacancyActionInput,
          clientFor,
        );
      }
      if (input.action === "upsert_quotation_business_draft") {
        return await executeQuotationBusinessDraftAction(
          actorAuthUserId,
          input as QuotationBusinessDraftActionInput,
          serviceClient()
        );
      }
      if (input.action === "promote_quotation_business_draft_to_approval") {
        return await executeQuotationBusinessApprovalPromotionAction(
          actorAuthUserId,
          input as QuotationBusinessApprovalPromotionActionInput,
          serviceClient()
        );
      }
      if (input.action === "issue_and_deliver_approved_quotation") {
        const from = Deno.env.get("FROM_EMAIL") || "";
        const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
        if (!from || !resendApiKey) throw new Error("SERVER_CONFIGURATION_ERROR");
        const quotationClient = serviceClient();
        const templateBytes = await Deno.readFile(new URL(
          "./assets/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx",
          import.meta.url,
        ));
        return await executeApprovedQuotationIssuanceAction(
          actorAuthUserId,
          input as QuotationIssuanceActionInput,
          {
            serviceClient: quotationClient,
            templateBytes,
            renderDocx: renderQuotationDocxBytes,
            deliver: (deliveryInput)=>deliverIssuedQuotation({
              supabase: quotationClient,
              ...deliveryInput,
            }),
            email: { from, resendApiKey },
          },
        );
      }
      if (input.action === "get_my_assigned_dossiers") {
        return await executeCallerJwtOperatorPersonalQueueAction(jwt, {
          action: "get_my_assigned_dossiers",
          cursor: input.cursor,
          limit: input.limit,
        }, clientFor);
      }
      if (input.action === "get_dossier_document_manifest" || input.action === "create_dossier_document_access") {
        return await executeServiceRoleDossierDocumentAction(
          actorAuthUserId,
          input as DossierDocumentActionInput,
          serviceClient(),
        );
      }
      if ([
        "list_customer_requests_for_dossier",
        "get_customer_request",
        "transition_customer_request",
      ].includes(input.action)) {
        return await executeCallerJwtCustomerRequestAction(jwt, input as CustomerRequestActionInput, clientFor);
      }
      if (input.action === "create_customer_request_upload_link" || input.action === "revoke_customer_request_upload_link") {
        return await executeCallerJwtCustomerRequestUploadAction(jwt, input as CustomerRequestUploadOperatorActionInput, clientFor);
      }
      if (input.action === "get_dossier_assignment" || input.action === "assign_dossier") {
        return await executeCallerJwtDossierAssignmentAction(jwt, input as DossierAssignmentActionInput, clientFor);
      }
      const client = clientFor(jwt);
          if (
            ["archive_pending_intake", "restore_pending_intake"].includes(
              input.action,
            )
          ) {
            const { data, error } = await serviceClient().rpc(
              "execute_operator_pending_intake_retention_v1",
              {
                p_actor_auth_user_id: actorAuthUserId,
                p_intake_id: input.intake_id,
                p_event_type: input.event_type,
                p_expected_revision: input.expected_revision,
                p_idempotency_key: input.idempotency_key,
                p_reason: input.reason,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "permanently_delete_pending_intake") {
            const { data, error } = await serviceClient().rpc(
              "permanently_delete_pending_intake_v1",
              {
                p_actor_auth_user_id: actorAuthUserId,
                p_intake_id: input.intake_id,
                p_quote_request_id: input.quote_request_id,
                p_idempotency_key: input.idempotency_key,
                p_reason: input.reason,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
      if (["interrupt_intake", "resume_intake", "cancel_intake", "reactivate_intake"].includes(input.action)) {
        const { data, error } = await client.rpc("execute_operator_intake_lifecycle_command_v1", {
          p_intake_id: input.intake_id,
          p_event_type: input.event_type,
          p_expected_revision: input.expected_revision,
          p_idempotency_key: input.idempotency_key,
          p_reason: input.reason,
        });
        if (error) throw new Error(error.message);
        return data;
      }
      if (isDossierLifecycleAction(input)) {
        return await executeDossierLifecycleTransport(
          (args)=>serviceClient().rpc("issue_operator_dossier_lifecycle_edge_capability_v1", args),
          (args)=>client.rpc("execute_operator_dossier_lifecycle_command_v1", args),
          actorAuthUserId,
          input
        );
      }
      if (["bind_project_site", "rotate_project_site"].includes(input.action)) {
        const { data, error } = await client.rpc("execute_operator_project_site_command_v1", {
          p_project_id: input.project_id,
          p_operation: input.operation,
          p_expected_revision: input.expected_revision,
          p_idempotency_key: input.idempotency_key,
          p_canonical_domain: input.canonical_domain,
          p_evidence: input.evidence,
        });
        if (error) throw new Error(error.message);
        return data;
      }
      if (input.action === "create_internal_e2e_run") {
        const approvalToken = await createApprovalTokenForIdempotencyKey(input.idempotency_key);
        const intakeToken = await createInternalE2EIntakeTokenForIdempotencyKey(input.idempotency_key);
        const intakeTokenHash = await hashIntakeToken(intakeToken);
        const adminToken = await deriveAdminIntakeCapability(intakeTokenHash);
        const requestFingerprint = await sha256(JSON.stringify({
          contract_version: 1,
          run_label: input.run_label,
          ttl_minutes: input.ttl_minutes,
        }));
        const { data, error } = await client.rpc("create_internal_e2e_run_v1", {
          p_idempotency_key: input.idempotency_key,
          p_request_fingerprint: requestFingerprint,
          p_run_label: input.run_label,
          p_ttl_minutes: input.ttl_minutes,
          p_approval_token_hash: await hashApprovalToken(approvalToken),
          p_intake_access_token_hash: intakeTokenHash,
          p_admin_access_token_hash: await hashAdminIntakeToken(adminToken),
        });
        if (error) throw new Error(error.message);
        return { ...data, intake_token: intakeToken, admin_intake_token: adminToken };
      }
      if (input.action === "create_customer_request_smoke_fixture") {
        return await executeCallerJwtCustomerRequestSmokeFixtureAction(jwt, input.idempotency_key, clientFor);
      }
      if (input.action === "cleanup_internal_e2e_accepted_file") {
        return await executeCallerJwtInternalE2EAcceptedFileCleanupAction(
          jwt,
          input as InternalE2EAcceptedFileCleanupActionInput,
          clientFor,
          serviceClient
        );
      }
      if (input.action === "finalize_internal_e2e_run") {
        const { data, error } = await client.rpc("finalize_internal_e2e_run_v1", {
          p_run_id: input.run_id,
          p_terminal_status: input.terminal_status,
          p_expected_revision: input.expected_revision,
          p_idempotency_key: input.idempotency_key,
        });
        if (error) throw new Error(error.message);
        return data;
      }
      const request = input.action === "list_applications"
        ? client.rpc("list_operator_applications_v1", {
          p_limit: input.limit,
          p_offset: input.offset
        })
        : input.action === "get_project_dossier"
        ? client.rpc("get_commercial_project_view_v2", {
          p_project_id: input.project_id
        })
        : input.action === "get_application_detail"
        ? input.support_reference
          ? client.rpc("get_operator_application_by_support_reference_v1", {
            p_support_reference: input.support_reference
          })
          : client.rpc("get_operator_application_v1", {
            p_quote_request_id: input.quote_request_id,
            p_application_reference: input.application_reference
          })
        : client.rpc("promote_operator_application_v1", {
          p_idempotency_key: input.idempotency_key,
          p_quote_request_id: input.quote_request_id,
          p_application_reference: input.application_reference
        });
      const { data, error } = await request;
      if (error) throw new Error(error.message);
      if (input.action === "get_application_detail" && data?.request_kind === "website") {
        const service = serviceClient();
        const context = await loadSubmittedApplicationOutputForOperator(service, data.quote_request_id);
        return enrichOperatorApplicationDetailWithOutput(data, context);
      }
      return data;
    },
    executeCommand: async (jwt: string, input: ValidatedCommercialCommandInput)=>{
      const { data, error } = await clientFor(jwt).rpc("execute_commercial_command_v2", {
        p_project_id: input.project_id,
        p_command_type: input.command_type,
        p_expected_state: input.expected_state,
        p_expected_revision: input.expected_revision,
        p_idempotency_key: input.idempotency_key,
        p_payload: input.payload
      });
      if (error) throw new Error(error.message);
      return data;
    }
  });
}));
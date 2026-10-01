import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  type CustomerRequestActionInput,
  type CustomerRequestUploadInboxPromotionActionInput,
  type CustomerRequestUploadOperatorActionInput,
  type DossierDocumentActionInput,
  executeAssignmentOperatorRosterTransport,
  executeCurrentOperatorIdentityTransport,
  executeCustomerRequestTransport,
  executeDossierAssignmentMutationTransport,
  executeDossierAssignmentReadTransport,
  executeDossierDocumentAccessTransport,
  executeDossierDocumentManifestTransport,
  executeDossierLifecycleTransport,
  executeOperatorPersonalQueueTransport,
  executeRecruitmentVacancyTransport,
  executeSdfM1InvoicePreparationTransport,
  executeWebsiteConceptPromotionTransport,
  executeWebsiteConceptStartTransport,
  executeWebsiteDeliveryPdfC3TrialTransport,
  executeWorkforceCalendarTransport,
  handleCommercialOperator,
  type InternalE2EAcceptedFileCleanupActionInput,
  type QuotationBusinessApprovalPromotionActionInput,
  type QuotationBusinessDraftActionInput,
  type QuotationIssuanceActionInput,
  type RecruitmentVacancyActionInput,
  type SdfM1InvoicePreparationActionInput,
  type SdfQuotationDeliveryPreparationActionInput,
  type SdfQuotationDeliverySendActionInput,
  type SdfQuotationIssuanceActionInput,
  validateWebsiteAgreementRegistrationStatusResult,
  validateWebsiteCommercialDocumentStatusResult,
  validateWebsiteQuotationApprovalStatusResult,
  type WebsiteAgreementConceptActionInput,
  type WebsiteAgreementRegistrationStatusActionInput,
  type WebsiteCommercialDocumentStatusActionInput,
  type WebsiteConceptPromotionActionInput,
  type WebsiteConceptStartActionInput,
  type WebsiteDeliveryDocumentActionInput,
  type WebsiteDeliveryDocumentViewActionInput,
  type WebsiteDeliveryPdfRerunActionInput,
  type WebsiteDeliveryPdfC3TrialActionInput,
  type WebsiteDeliveryPdfStatusActionInput,
  type WebsiteExecutionWorkspaceProvisionActionInput,
  type WebsiteInvoiceConceptActionInput,
  type WebsiteProjectDirectoryActionInput,
  type WebsiteProjectFileActionInput,
  type WebsiteProjectFileSaveActionInput,
  type WebsiteProjectPreviewBuildActionInput,
  type WebsiteProjectPreviewControlActionInput,
  type WebsiteProjectPreviewReadyActionInput,
  type WebsiteQuotationApprovalStatusActionInput,
  type WebsiteQuotationPricingStateActionInput,
  type WebsiteRepositoryProvisionActionInput,
  type WebsiteRepositoryRecoveryActionInput,
  type WebsiteRequirementsActionInput,
  withCommercialOperatorCors,
  type WorkforceCalendarActionInput,
} from "./handler.ts";
import {
  normalizeVatReadinessResponse,
  type VatReadinessActionInput,
} from "./vat-readiness.ts";
import {
  deliverIssuedQuotation,
  sendPreparedSdfQuotationDelivery,
} from "../_shared/quotation-email-orchestration.ts";
import { orchestrateApprovedQuotation } from "./quotation-orchestrator.ts";
import {
  createQuotationRuntimeDependencies,
  prepareSdfQuotationDelivery,
  type QuotationRuntimeOptions,
} from "./quotation-runtime.ts";
import { renderQuotationDocxBytes } from "./quotation-renderer-edge.ts";
import { renderSdfQuotationDocxBytes } from "./sdf-quotation-renderer-edge.ts";
import { renderWebsiteQuotationDocxBytes } from "./website-quotation-renderer-edge.ts";
import {
  renderWebsiteAgreementConceptDocxBytes,
  renderWebsiteCommercialConceptDocxBytes,
} from "./website-commercial-renderer-edge.ts";
import { renderWebsiteDeliveryDocumentDocxBytes } from "./website-delivery-renderer-edge.ts";
import {
  enrichOperatorApplicationDetailWithOutput,
  loadSubmittedApplicationOutputForOperator,
} from "../_shared/submitted-application-output.ts";

export function normalizeCommercialOperatorRateLimitResult(value: unknown) {
  const row = Array.isArray(value) && value.length === 1 ? value[0] : null;
  if (!row || typeof row !== "object"
    || typeof row.allowed !== "boolean"
    || !Number.isSafeInteger(row.retry_after_seconds)
    || row.retry_after_seconds < 0) {
    throw new Error("INVALID_COMMERCIAL_OPERATOR_RATE_LIMIT_RESULT");
  }
  return Object.freeze({
    allowed: row.allowed,
    retry_after_seconds: row.retry_after_seconds,
  });
}
import {
  buildCustomerRequestUploadUrl,
  deriveCustomerRequestUploadCapabilityToken,
  hashCustomerRequestUploadCapabilityToken,
} from "../_shared/customer-request-upload-capability.ts";
import {
  createApprovalTokenForIdempotencyKey,
  createInternalE2EIntakeTokenForIdempotencyKey,
  createRawIntakeToken,
  deriveAdminIntakeCapability,
  encryptIntakeInvitationToken,
  hashAdminIntakeToken,
  hashApprovalToken,
  hashIntakeToken,
} from "../_shared/security.ts";
import {
  type OperatorCursorPosition,
  type OperatorCursorRequest,
  signOperatorCursor,
  verifyOperatorCursor,
} from "../_shared/operator-cursor.ts";
import {
  createQuotationApprovalIntegrity,
  QUOTATION_APPROVAL_INTEGRITY_VERSION,
  type QuotationApprovalIntegrity,
  type QuotationApprovalIntegrityRoot,
  verifyQuotationApprovalIntegrity,
} from "../_shared/quotation-approval-integrity.ts";
import {
  getSupabasePublishableKey,
  getSupabaseServerSecretKey,
} from "../_shared/supabase-key-bindings.ts";
import {
  GitHubAppConfigurationError,
  GitHubProviderDisabledError,
  loadGitHubAppConfig,
  loadWebsiteDeliveryPdfDispatchAppConfig,
} from "../_shared/github-app-config.ts";
import { createGitHubAppTokenBroker } from "../_shared/github-app-token.ts";
import { createGitHubHttpClient } from "../_shared/github-http.ts";
import { createWebsiteDeliveryPdfWorkflowDispatch } from "../_shared/website-delivery-pdf-workflow-dispatch.ts";
import { createWebsiteDeliveryPdfWorkflowStarter } from "../_shared/website-delivery-pdf-workflow-starter.ts";
import {
  createWebsiteProjectFilesProvider,
  type WebsiteProjectFilesAuthority,
} from "../_shared/website-project-files-provider.ts";
import {
  createWebsiteProjectFilesService,
  type WebsiteProjectFilesService,
} from "../_shared/website-project-files-service.ts";
import {
  createWebsiteProjectPreviewBuilder,
  type WebsiteProjectPreviewBuildResult,
} from "../_shared/website-project-preview-builder.ts";
import { initializeGitHubAppInputSigner } from "../github-app-gate6-probe/runtime.ts";
import {
  createGitHubRepositoryRuntimeFromProvider,
  createGitHubTargetRepositoryProviderForRuntime,
} from "../_shared/github-repository-runtime.ts";
import { createRepositoryProvisioningStoreV2 } from "../_shared/repository-provisioning-store-v2.ts";
import {
  createProductionRepositoryRecovery,
  guardProductionRepositoryRecoveryStage,
  withProductionRepositoryRecoveryFailureLogging,
} from "../_shared/production-repository-recovery.ts";
import {
  hasValidatedGitHubTokenAcquireDiagnostic,
  hasValidatedGitHubTokenLeaseCheck,
  hasValidatedGitHubTokenResponseCheck,
  RepositoryProvisioningClaimDiagnosticError,
  RepositoryProvisioningProviderDiagnosticError,
  RepositoryProvisioningRuntimeDiagnosticError,
} from "../_shared/repository-provisioning-diagnostics.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type OperatorApplicationCursorInput = Readonly<{
  zone: OperatorCursorRequest["zone"];
  operational_status: string | null;
  year?: number | null;
  quarter?: OperatorCursorRequest["quarter"];
  request_kind: OperatorCursorRequest["requestKind"];
  search: string | null;
}>;

type OperatorApplicationListV2Input =
  & OperatorApplicationCursorInput
  & Readonly<{
    year: number | null;
    quarter: OperatorCursorRequest["quarter"];
    cursor: string | null;
    limit: number;
  }>;

type OperatorApplicationFacetsV2Input = Omit<
  OperatorApplicationCursorInput,
  "year" | "quarter"
>;
type SupabaseAuthClient = Readonly<{
  auth: Readonly<{
    getUser(jwt: string): PromiseLike<
      Readonly<{
        data: Readonly<{ user: Readonly<{ id: string }> | null }>;
        error: unknown;
      }>
    >;
  }>;
}>;

export async function verifySupabaseAuthUser(
  client: SupabaseAuthClient,
  jwt: string,
): Promise<Readonly<{ id: string }> | null> {
  const { data, error } = await client.auth.getUser(jwt);
  return error || !data.user ? null : { id: data.user.id };
}

type DossierAssignmentActionInput =
  | Readonly<{
    action: "get_dossier_assignment";
    dossier_reference: string;
  }>
  | Readonly<{
    action: "assign_dossier";
    dossier_reference: string;
    assignee_operator_id: string;
    expected_revision: number;
    idempotency_key: string;
    reason: string | null;
  }>;
type DossierAssignmentClient = Parameters<
  typeof executeDossierAssignmentReadTransport
>[0];
type DossierDocumentServiceClient =
  & DossierAssignmentClient
  & Readonly<{
    storage: Readonly<{
      from(bucket: string): Readonly<{
        createSignedUrl(
          path: string,
          expiresIn: number,
          options: Readonly<{ download: string }>,
        ): PromiseLike<
          Readonly<
            {
              data: Readonly<{ signedUrl: string }> | null;
              error: Readonly<{ message: string }> | null;
            }
          >
        >;
      }>;
    }>;
  }>;
type CustomerRequestUploadPromotionServiceClient =
  & DossierAssignmentClient
  & Readonly<{
    storage: Readonly<{
      from(bucket: string): Readonly<{
        download(path: string): PromiseLike<
          Readonly<{
            data: Blob | null;
            error: unknown;
          }>
        >;
        upload(
          path: string,
          bytes: Uint8Array,
          options: Readonly<{ contentType: string; upsert: boolean }>,
        ): PromiseLike<Readonly<{ data: unknown; error: unknown }>>;
      }>;
    }>;
  }>;
type ValidatedApplicationActionInput =
  & Record<string, unknown>
  & Readonly<{
    action: string;
    intake_id: string;
    event_type: string;
    expected_revision: number;
    expected_website_work_revision: number;
    idempotency_key: string;
    reason: string | null;
    quote_request_id: string | null;
    website_work_context_id: string;
    website_workspace_id: string;
    preview_build_id: string;
    requirement_id: string;
    expected_board_revision: number;
    expected_context_revision: number;
    attestation: Readonly<{ attestation: string }>;
    business_draft_id: string;
    approval_id: string;
    approval_version: number;
    approval_sha256: string;
    generation_contract_version: number;
    obligation_id: string;
    template_authority_id: string;
    issuance_id: string;
    artifact_id: string;
    artifact_sha256: string;
    artifact_bytes: number;
    project_id: string;
    internal_e2e_run_id: string;
    fixture_id: string;
    delivery_date: string;
    checklist: Record<string, "COMPLETED" | "NOT_APPLICABLE">;
    remarks_state: "NONE_CONFIRMED" | "RECORDED";
    remarks_text: string | null;
    contractor_signature_date: string;
    contractor_signature_place: string;
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
    expected_state: string;
  }>;
type ValidatedDossierLifecycleActionInput =
  & ValidatedApplicationActionInput
  & Readonly<{
    action:
      | "archive_dossier"
      | "reactivate_dossier"
      | "trash_dossier"
      | "restore_dossier";
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

type ApplicationDetailRpcClient = Readonly<{
  rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<
    Readonly<{ data: unknown; error: Readonly<{ message: string }> | null }>
  >;
}>;

export async function executeApplicationDetailRead(
  callerClient: ApplicationDetailRpcClient,
  input: Readonly<{
    quote_request_id: string | null;
    application_reference: string | null;
    support_reference: string | null;
  }>,
): Promise<
  Readonly<{ data: unknown; error: Readonly<{ message: string }> | null }>
> {
  const primary = input.support_reference
    ? await callerClient.rpc(
      "get_operator_application_by_support_reference_v1",
      {
        p_support_reference: input.support_reference,
      },
    )
    : await callerClient.rpc("get_operator_application_v1", {
      p_quote_request_id: input.quote_request_id,
      p_application_reference: input.application_reference,
    });
  const primaryError = String(
    (primary.error as { message?: unknown } | null)?.message || "",
  );
  if (
    !input.support_reference || primaryError !== "APPLICATION_NOT_FOUND"
  ) return primary;
  return await callerClient.rpc(
    "get_operator_trashed_website_intake_detail_caller_v1",
    {
      p_support_reference: input.support_reference,
    },
  );
}

async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(bytes)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function isDossierLifecycleAction(
  input: ValidatedApplicationActionInput,
): input is ValidatedDossierLifecycleActionInput {
  return input.action === "archive_dossier" ||
    input.action === "reactivate_dossier" ||
    input.action === "trash_dossier" ||
    input.action === "restore_dossier";
}

export async function executeCallerJwtDossierAssignmentAction(
  jwt: string,
  input: DossierAssignmentActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  const client = clientFor(jwt);
  return input.action === "get_dossier_assignment"
    ? await executeDossierAssignmentReadTransport(client, input)
    : await executeDossierAssignmentMutationTransport(client, input);
}

export async function executeCallerJwtAssignmentRosterAction(
  jwt: string,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeAssignmentOperatorRosterTransport(clientFor(jwt));
}

export async function executeCallerJwtOperatorPersonalQueueAction(
  jwt: string,
  input: Readonly<
    { action: "get_my_assigned_dossiers"; cursor: string | null; limit: number }
  >,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeOperatorPersonalQueueTransport(clientFor(jwt), input);
}

export async function executeCallerJwtCurrentOperatorIdentityAction(
  jwt: string,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeCurrentOperatorIdentityTransport(clientFor(jwt));
}

export async function executeCallerJwtRecruitmentVacancyAction(
  jwt: string,
  input: RecruitmentVacancyActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeRecruitmentVacancyTransport(clientFor(jwt), input);
}

export async function executeCallerJwtSdfM1InvoicePreparationAction(
  jwt: string,
  input: SdfM1InvoicePreparationActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeSdfM1InvoicePreparationTransport(clientFor(jwt), input);
}

export async function executeCallerJwtWebsiteConceptStartAction(
  jwt: string,
  input: WebsiteConceptStartActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeWebsiteConceptStartTransport(clientFor(jwt), input);
}

export async function executeCallerJwtWebsiteConceptPromotionAction(
  jwt: string,
  input: WebsiteConceptPromotionActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeWebsiteConceptPromotionTransport(clientFor(jwt), input);
}

export async function executeCallerJwtWebsiteProjectPreviewReadyAction(
  jwt: string,
  input: WebsiteProjectPreviewReadyActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  const { data, error } = await clientFor(jwt).rpc(
    "record_website_project_preview_ready_v1",
    {
      p_quote_request_id: input.quote_request_id,
      p_project_id: input.project_id,
      p_preview_build_id: input.preview_build_id,
      p_idempotency_key: input.idempotency_key,
    },
  );
  if (error) throw new Error(error.message);
  return data;
}

export async function executeCallerJwtWebsiteExecutionWorkspaceProvisionAction(
  jwt: string,
  input: WebsiteExecutionWorkspaceProvisionActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  const { data, error } = await clientFor(jwt).rpc(
    "provision_website_execution_workspace_v1",
    {
      p_quote_request_id: input.quote_request_id,
      p_idempotency_key: input.idempotency_key,
    },
  );
  if (error) throw new Error(error.message);
  return data;
}

export async function executeCallerJwtWebsiteRequirementsAction(
  jwt: string,
  input: WebsiteRequirementsActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  const client = clientFor(jwt);
  let rpcName: string;
  let parameters: Record<string, unknown>;
  switch (input.action) {
    case "get_website_requirements_board":
      rpcName = "get_website_requirements_board_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
      };
      break;
    case "sync_website_requirements_from_intake":
      rpcName = "sync_website_requirements_from_intake_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
        p_expected_board_revision: input.expected_board_revision,
        p_idempotency_key: input.idempotency_key,
      };
      break;
    case "start_website_requirement":
      rpcName = "start_website_requirement_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
        p_requirement_id: input.requirement_id,
        p_expected_revision: input.expected_revision,
        p_idempotency_key: input.idempotency_key,
      };
      break;
    case "block_website_requirement":
      rpcName = "block_website_requirement_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
        p_requirement_id: input.requirement_id,
        p_expected_revision: input.expected_revision,
        p_reason: input.reason,
        p_idempotency_key: input.idempotency_key,
      };
      break;
    case "complete_website_requirement":
      rpcName = "complete_website_requirement_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
        p_requirement_id: input.requirement_id,
        p_expected_revision: input.expected_revision,
        p_attestation: input.attestation,
        p_idempotency_key: input.idempotency_key,
      };
      break;
    case "reopen_website_requirement":
      rpcName = "reopen_website_requirement_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
        p_requirement_id: input.requirement_id,
        p_expected_revision: input.expected_revision,
        p_reason: input.reason,
        p_idempotency_key: input.idempotency_key,
      };
      break;
    case "accept_website_requirement_source_change":
      rpcName = "resolve_website_requirement_source_change_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
        p_requirement_id: input.requirement_id,
        p_expected_revision: input.expected_revision,
        p_resolution: "ACCEPT_CHANGE",
        p_reason: input.reason,
        p_idempotency_key: input.idempotency_key,
      };
      break;
    case "keep_existing_website_requirement_source":
      rpcName = "resolve_website_requirement_source_change_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
        p_requirement_id: input.requirement_id,
        p_expected_revision: input.expected_revision,
        p_resolution: "KEEP_EXISTING",
        p_reason: input.reason,
        p_idempotency_key: input.idempotency_key,
      };
      break;
    case "retire_website_requirement_source":
      rpcName = "resolve_website_requirement_source_change_v1";
      parameters = {
        p_quote_request_id: input.quote_request_id,
        p_website_work_context_id: input.website_work_context_id,
        p_requirement_id: input.requirement_id,
        p_expected_revision: input.expected_revision,
        p_resolution: "RETIRE",
        p_reason: input.reason,
        p_idempotency_key: input.idempotency_key,
      };
      break;
    default:
      throw new Error("INVALID_WEBSITE_REQUIREMENTS_ACTION");
  }
  const { data, error } = await client.rpc(rpcName, parameters);
  if (error) throw new Error(error.message);
  return data;
}

type WebsiteProjectFilesActionInput =
  | WebsiteProjectDirectoryActionInput
  | WebsiteProjectFileActionInput
  | WebsiteProjectFileSaveActionInput;

type WebsiteProjectPreviewBuildRpcClient = Readonly<{
  rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<
    Readonly<{
      data: unknown;
      error: Readonly<{ message: string }> | null;
    }>
  >;
}>;

type WebsiteProjectPreviewStorageClient = Readonly<{
  storage: Readonly<{
    from(bucket: string): Readonly<{
      upload(
        path: string,
        bytes: Uint8Array,
        options: Readonly<{ contentType: string; upsert: false }>,
      ): PromiseLike<
        Readonly<{
          data: unknown;
          error: Readonly<{ message: string }> | null;
        }>
      >;
      createSignedUrl(
        path: string,
        expiresInSeconds: number,
      ): PromiseLike<
        Readonly<{
          data: Readonly<{ signedUrl: string }> | null;
          error: Readonly<{ message: string }> | null;
        }>
      >;
    }>;
  }>;
}>;

type WebsiteProjectFilesRpcClient = Readonly<{
  rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<
    Readonly<{
      data: unknown;
      error: Readonly<{ message: string }> | null;
    }>
  >;
}>;

type WebsiteProjectFilesActionService = Readonly<{
  list(
    input: Parameters<WebsiteProjectFilesService["list"]>[0],
  ): PromiseLike<unknown>;
  read(
    input: Parameters<WebsiteProjectFilesService["read"]>[0],
  ): PromiseLike<unknown>;
  save(
    input: Parameters<WebsiteProjectFilesService["save"]>[0],
  ): PromiseLike<unknown>;
}>;

type WebsiteProjectFilesRuntimeDependencies = Readonly<{
  clientFor(jwt: string): WebsiteProjectFilesRpcClient;
  createService(
    signal: AbortSignal,
  ): PromiseLike<WebsiteProjectFilesActionService>;
  createDeadline?(): AbortSignal;
}>;

type WebsiteProjectPreviewBuilderService = Readonly<{
  build(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      expectedCommitSha: string;
      idempotencyKey: string;
    }>,
  ): PromiseLike<WebsiteProjectPreviewBuildResult>;
}>;

type WebsiteProjectPreviewRuntimeDependencies = Readonly<{
  clientFor(jwt: string): WebsiteProjectPreviewBuildRpcClient;
  createService(
    signal: AbortSignal,
  ): PromiseLike<WebsiteProjectPreviewBuilderService>;
  createDeadline?(): AbortSignal;
}>;

export async function executeCallerJwtWebsiteProjectPreviewControlAction(
  jwt: string,
  input: WebsiteProjectPreviewControlActionInput,
  dependencies: Readonly<{
    clientFor(jwt: string): WebsiteProjectPreviewBuildRpcClient;
    previewHostUrl?: string;
  }>,
): Promise<unknown> {
  const client = dependencies.clientFor(jwt);
  if (input.action === "request_website_project_preview_build") {
    const { data, error } = await client.rpc(
      "acquire_website_project_preview_build_v1",
      {
        p_quote_request_id: input.quote_request_id,
        p_expected_commit_sha: input.expected_commit_sha,
        p_idempotency_key: input.idempotency_key,
      },
    );
    if (error) throw new Error(error.message);
    const leaseId = (data as { leaseId?: unknown } | null)?.leaseId;
    const buildId = (data as { buildId?: unknown } | null)?.buildId;
    if (
      typeof leaseId !== "string" || !UUID.test(leaseId) ||
      typeof buildId !== "string" || !UUID.test(buildId)
    ) {
      throw new Error("PROJECT_PREVIEW_LEASE_RESPONSE_INVALID");
    }
    return {
      lease_id: leaseId,
      build_id: buildId,
      status: "BUILD_IN_PROGRESS",
    };
  }
  if (input.action === "get_website_project_preview_build_status") {
    const { data, error } = await client.rpc(
      "get_website_project_preview_build_status_v1",
      { p_lease_id: input.lease_id },
    );
    if (error) throw new Error(error.message);
    const status = (data as { buildStatus?: unknown } | null)?.buildStatus;
    const previewBuildId = (data as { previewBuildId?: unknown } | null)
      ?.previewBuildId;
    if (typeof status !== "string") {
      throw new Error("PROJECT_PREVIEW_STATUS_RESPONSE_INVALID");
    }
    return {
      status,
      preview_build_id: typeof previewBuildId === "string"
        ? previewBuildId
        : null,
    };
  }

  const previewHostUrl = String(dependencies.previewHostUrl || "").replace(
    /\/$/,
    "",
  );
  if (
    !/^https?:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?$/i.test(previewHostUrl) &&
    !/^https:\/\/[a-z0-9.-]+$/i.test(previewHostUrl)
  ) {
    throw new Error("PROJECT_PREVIEW_HOST_NOT_CONFIGURED");
  }
  const sessionToken = [...crypto.getRandomValues(new Uint8Array(32))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const sessionTokenHash = await sha256Hex(
    new TextEncoder().encode(sessionToken),
  );
  const { data, error } = await client.rpc(
    "create_website_project_preview_session_v1",
    {
      p_preview_build_id: input.preview_build_id,
      p_session_token_hash: sessionTokenHash,
    },
  );
  if (error) throw new Error(error.message);
  if (!(data as { previewSessionId?: unknown } | null)?.previewSessionId) {
    throw new Error("PROJECT_PREVIEW_SESSION_RESPONSE_INVALID");
  }
  return { handoff_url: `${previewHostUrl}/handoff?token=${sessionToken}` };
}

function projectFilesError(code: string): Error {
  return new Error(code);
}

export async function executeCallerJwtWebsiteProjectFilesAction(
  jwt: string,
  input: WebsiteProjectFilesActionInput,
  dependencies: WebsiteProjectFilesRuntimeDependencies,
): Promise<unknown> {
  const signal = (dependencies.createDeadline ??
    (() => AbortSignal.timeout(10_000)))();
  const isSave = input.action === "save_website_project_file";
  const client = dependencies.clientFor(jwt);
  const acquired = isSave
    ? await client.rpc("acquire_website_project_files_write_v1", {
      p_quote_request_id: input.quote_request_id,
      p_path: input.path,
      p_expected_commit_sha: input.expected_commit_sha,
      p_idempotency_key: input.idempotency_key,
    })
    : await client.rpc("acquire_website_project_files_read_v1", {
      p_quote_request_id: input.quote_request_id,
      p_read_kind: input.action === "list_website_project_directory"
        ? "DIRECTORY"
        : "FILE",
    });
  if (acquired.error) throw projectFilesError(acquired.error.message);
  if (
    !acquired.data || typeof acquired.data !== "object" ||
    Array.isArray(acquired.data) ||
    !UUID.test(String((acquired.data as { leaseId?: unknown }).leaseId || ""))
  ) throw projectFilesError("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");

  const authority = acquired.data as WebsiteProjectFilesAuthority;
  let finalized = false;
  let primaryError: unknown = null;
  try {
    if (signal.aborted) {
      throw projectFilesError("PROJECT_FILES_PROVIDER_TIMEOUT");
    }
    const service = await dependencies.createService(signal);
    const result = input.action === "list_website_project_directory"
      ? await service.list({
        authority,
        path: input.path,
        cursor: input.cursor,
      })
      : input.action === "read_website_project_file"
      ? await service.read({ authority, path: input.path })
      : await service.save({
        authority,
        path: input.path,
        content: input.content,
        expectedCommitSha: input.expected_commit_sha,
      });
    if (signal.aborted) {
      throw projectFilesError("PROJECT_FILES_PROVIDER_TIMEOUT");
    }

    if (isSave) {
      const saveResult = result as {
        snapshot?: { commit_sha?: unknown };
        file?: { created?: unknown };
      };
      const commitSha = String(saveResult.snapshot?.commit_sha || "");
      const created = saveResult.file?.created;
      if (!SHA.test(commitSha) || typeof created !== "boolean") {
        throw projectFilesError("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
      }
      const finalizedWrite = await client.rpc(
        "finalize_website_project_files_write_v1",
        {
          p_lease_id: authority.leaseId,
          p_path: input.path,
          p_expected_commit_sha: input.expected_commit_sha,
          p_commit_sha: commitSha,
          p_created: created,
        },
      );
      if (finalizedWrite.error) {
        throw projectFilesError(finalizedWrite.error.message);
      }
      finalized = true;
    }

    return result;
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    const releaseName = isSave
      ? "release_website_project_files_write_v1"
      : "release_website_project_files_read_v1";
    if (finalized) return;
    try {
      const released = await client.rpc(releaseName, {
        p_lease_id: authority.leaseId,
      });
      if (released.error && primaryError === null) {
        throw projectFilesError("PROJECT_FILES_PROVIDER_UNAVAILABLE");
      }
    } catch {
      if (primaryError === null) {
        throw projectFilesError("PROJECT_FILES_PROVIDER_UNAVAILABLE");
      }
    }
  }
}

export async function executeCallerJwtWebsiteProjectPreviewBuildAction(
  jwt: string,
  input: WebsiteProjectPreviewBuildActionInput,
  dependencies: WebsiteProjectPreviewRuntimeDependencies,
): Promise<WebsiteProjectPreviewBuildResult> {
  const signal = (dependencies.createDeadline ??
    (() => AbortSignal.timeout(10_000)))();
  const client = dependencies.clientFor(jwt);
  const acquired = await client.rpc(
    "acquire_website_project_preview_build_v1",
    {
      p_quote_request_id: input.quote_request_id,
      p_expected_commit_sha: input.expected_commit_sha,
      p_idempotency_key: input.idempotency_key,
    },
  );
  if (acquired.error) throw projectFilesError(acquired.error.message);
  if (
    !acquired.data || typeof acquired.data !== "object" ||
    Array.isArray(acquired.data) ||
    !UUID.test(String((acquired.data as { leaseId?: unknown }).leaseId || ""))
  ) throw projectFilesError("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");

  const authority = acquired.data as WebsiteProjectFilesAuthority;
  let finalized = false;
  let primaryError: unknown = null;
  try {
    if (signal.aborted) {
      throw projectFilesError("PROJECT_FILES_PROVIDER_TIMEOUT");
    }
    const service = await dependencies.createService(signal);
    const result = await service.build({
      authority,
      expectedCommitSha: input.expected_commit_sha,
      idempotencyKey: input.idempotency_key,
    });
    if (signal.aborted) {
      throw projectFilesError("PROJECT_FILES_PROVIDER_TIMEOUT");
    }
    const finalizedBuild = await client.rpc(
      "finalize_website_project_preview_build_v1",
      {
        p_lease_id: authority.leaseId,
        p_expected_commit_sha: input.expected_commit_sha,
        p_artifact_path: result.preview.storage_object_path,
        p_artifact_sha256: result.preview.sha256,
        p_artifact_bytes: result.preview.byte_count,
        p_build_status: result.build.status,
      },
    );
    if (finalizedBuild.error) {
      throw projectFilesError(finalizedBuild.error.message);
    }
    finalized = true;
    return result;
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    if (!finalized) {
      try {
        const released = await client.rpc(
          "release_website_project_preview_build_v1",
          {
            p_lease_id: authority.leaseId,
          },
        );
        if (released.error && primaryError === null) {
          throw projectFilesError("PROJECT_FILES_PROVIDER_UNAVAILABLE");
        }
      } catch {
        if (primaryError === null) {
          throw projectFilesError("PROJECT_FILES_PROVIDER_UNAVAILABLE");
        }
      }
    }
  }
}

export async function executeCallerJwtWebsiteExecutionWorkspaceReadAction(
  jwt: string,
  input: Readonly<{
    action: "get_website_execution_workspace";
    quote_request_id: string;
  }>,
  clientFor: (jwt: string) => WebsiteProjectFilesRpcClient,
): Promise<unknown> {
  const { data, error } = await clientFor(jwt).rpc(
    "get_website_execution_workspace_v5",
    { p_quote_request_id: input.quote_request_id },
  );
  if (error) throw new Error(error.message);
  return data;
}

export const WEBSITE_REPOSITORY_PROVISION_STAGES = [
  "CONFIG_LOAD",
  "TARGET_VALIDATE",
  "SIGNER_INIT",
  "STORE_INIT",
  "PROVIDER_INIT",
  "RUNTIME_PROVISION",
] as const;

export type WebsiteRepositoryProvisionStage =
  (typeof WEBSITE_REPOSITORY_PROVISION_STAGES)[number];

type WebsiteRepositoryProvisionFailureLog = Readonly<
  Record<string, string>
>;

function safeProvisionErrorName(error: unknown): string {
  try {
    const name = error instanceof Error ? error.name : "";
    return /^[A-Za-z][A-Za-z0-9]{0,63}$/.test(name)
      ? name
      : "UNKNOWN_THROWABLE";
  } catch {
    return "UNKNOWN_THROWABLE";
  }
}

export function websiteRepositoryProvisionFailureLog(
  stage: WebsiteRepositoryProvisionStage,
  error: unknown,
): WebsiteRepositoryProvisionFailureLog {
  const record: Record<string, string> = {
    event: "LWS_GIT001_PROVISION_FAILURE",
    action: "provision_website_repository",
    stage,
    error_name: safeProvisionErrorName(error),
    diagnostic_code: "UNCLASSIFIED",
  };
  if (error instanceof RepositoryProvisioningClaimDiagnosticError) {
    record.diagnostic_code = "REPOSITORY_PROVISIONING_CLAIM_FAILED";
    record.claim_phase = error.phase;
    if (/^[0-9A-Z]{2}$/.test(error.sqlstateClass || "")) {
      record.sqlstate_class = error.sqlstateClass!;
    }
  } else if (error instanceof RepositoryProvisioningRuntimeDiagnosticError) {
    record.diagnostic_code = error.phase;
  } else if (error instanceof RepositoryProvisioningProviderDiagnosticError) {
    record.diagnostic_code = error.phase;
    record.provider_phase = error.phase;
    if (error.subphase) record.provider_subphase = error.subphase;
    if (
      hasValidatedGitHubTokenAcquireDiagnostic(error) &&
      error.tokenAcquireSubphase
    ) {
      record.token_acquire_subphase = error.tokenAcquireSubphase;
    }
    if (hasValidatedGitHubTokenLeaseCheck(error)) {
      record.token_lease_check = error.tokenLeaseCheck;
    }
    if (hasValidatedGitHubTokenResponseCheck(error)) {
      record.token_response_check = error.tokenResponseCheck;
    }
  } else if (
    error instanceof GitHubAppConfigurationError ||
    error instanceof GitHubProviderDisabledError
  ) {
    record.diagnostic_code = error.code;
  } else if (
    error instanceof Error &&
    error.message === "PRODUCTION_GITHUB_AUTHORITY_REQUIRED"
  ) {
    record.diagnostic_code = "PRODUCTION_GITHUB_AUTHORITY_REQUIRED";
  }
  return Object.freeze(record);
}

export async function withWebsiteRepositoryProvisionFailureLogging<T>(
  action: (
    setStage: (stage: WebsiteRepositoryProvisionStage) => void,
  ) => Promise<T>,
  logger: (entry: string) => void = (entry) => console.error(entry),
): Promise<T> {
  let stage: WebsiteRepositoryProvisionStage = "CONFIG_LOAD";
  try {
    return await action((nextStage) => {
      stage = nextStage;
    });
  } catch (error) {
    logger(JSON.stringify(websiteRepositoryProvisionFailureLog(stage, error)));
    throw error;
  }
}

export async function executeCallerJwtWebsiteRepositoryProvisionAction(
  jwt: string,
  input: WebsiteRepositoryProvisionActionInput,
  clientFor: (jwt: string) => WebsiteProjectFilesRpcClient,
): Promise<unknown> {
  return await withWebsiteRepositoryProvisionFailureLogging(
    async (setStage) => {
      setStage("CONFIG_LOAD");
      const config = loadGitHubAppConfig();
      setStage("TARGET_VALIDATE");
      if (config.target !== "PRODUCTION") {
        throw new Error("PRODUCTION_GITHUB_AUTHORITY_REQUIRED");
      }
      setStage("SIGNER_INIT");
      const http = createGitHubHttpClient({ fetch });
      const signer = await initializeGitHubAppInputSigner(config.privateKey);
      const tokenBroker = createGitHubAppTokenBroker({
        now: Date.now,
        sign: (_privateKey, signingInput) => signer(signingInput),
        exchange: async (exchange) => {
          const result = await http.execute({
            kind: "TOKEN_EXCHANGE",
            installationId: exchange.installationId,
            appJwt: exchange.appJwt,
            repositoryIds: exchange.repositoryIds,
            permissions: exchange.permissions,
          });
          if (!("token" in result) || !("expiresAt" in result)) {
            throw new Error("GITHUB_TOKEN_EXCHANGE_FAILED");
          }
          return result;
        },
      });
      setStage("STORE_INIT");
      const store = createRepositoryProvisioningStoreV2({
        rpc: async (name, parameters) =>
          await clientFor(jwt).rpc(name, parameters),
      }, {
        claimRpcName: "claim_production_website_repository_provisioning_v1",
        bindRpcName: "bind_production_website_repository_v1",
        quoteRequestId: input.quote_request_id,
      });
      setStage("PROVIDER_INIT");
      const provider = createGitHubTargetRepositoryProviderForRuntime(
        config,
        config,
        { store, tokenBroker, http },
      );
      setStage("RUNTIME_PROVISION");
      return await createGitHubRepositoryRuntimeFromProvider(provider, store)
        .provision(Object.freeze({
          contractVersion: 2 as const,
          websiteWorkspaceId: input.website_workspace_id,
          websiteWorkContextId: input.website_work_context_id,
          idempotencyKey: input.idempotency_key,
          starter: Object.freeze({
            source: `${config.templateOwner}/${config.templateName}`,
            version: config.starterVersion,
            commitSha: config.starterCommitSha,
            templateRepositoryId: config.templateRepositoryId,
          }),
        }));
    },
  );
}

export async function executeCallerJwtWebsiteRepositoryRecoveryAction(
  jwt: string,
  actorAuthUserId: string,
  input: WebsiteRepositoryRecoveryActionInput,
  clientFor: (jwt: string) => WebsiteProjectFilesRpcClient,
  serviceClient: () => WebsiteProjectFilesRpcClient,
): Promise<unknown> {
  return await withProductionRepositoryRecoveryFailureLogging(async () => {
    const { config, http, tokenBroker } =
      await guardProductionRepositoryRecoveryStage(
        "CONFIG_LOAD",
        async () => {
          const config = loadGitHubAppConfig();
          if (config.target !== "PRODUCTION") {
            throw new Error("PRODUCTION_GITHUB_AUTHORITY_REQUIRED");
          }
          const http = createGitHubHttpClient({ fetch });
          const signer = await initializeGitHubAppInputSigner(
            config.privateKey,
          );
          const tokenBroker = createGitHubAppTokenBroker({
            now: Date.now,
            sign: (_privateKey, signingInput) => signer(signingInput),
            exchange: async (exchange) => {
              const result = await http.execute({
                kind: "TOKEN_EXCHANGE",
                installationId: exchange.installationId,
                appJwt: exchange.appJwt,
                repositoryIds: exchange.repositoryIds,
                permissions: exchange.permissions,
              });
              if (!("token" in result) || !("expiresAt" in result)) {
                throw new Error("GITHUB_TOKEN_EXCHANGE_FAILED");
              }
              return result;
            },
          });
          return { config, http, tokenBroker };
        },
      );
    const caller = clientFor(jwt);
    const service = serviceClient();
    const recovery = createProductionRepositoryRecovery({
      config,
      actor: Object.freeze({ authUserId: actorAuthUserId, aal: "aal2" }),
      callerRpc: async (name, parameters) => await caller.rpc(name, parameters),
      serviceRpc: async (name, parameters) =>
        await service.rpc(name, parameters),
      tokenBroker,
      http,
    });
    return await recovery.recover(Object.freeze({
      quoteRequestId: input.quote_request_id,
      websiteWorkContextId: input.website_work_context_id,
      websiteWorkspaceId: input.website_workspace_id,
    }));
  });
}

async function createWebsiteProjectFilesRuntimeService(
  signal: AbortSignal,
): Promise<WebsiteProjectFilesService> {
  const config = loadGitHubAppConfig();
  const httpClient = createGitHubHttpClient({
    fetch: (input, init) => fetch(input, { ...init, signal }),
  });
  const signer = await initializeGitHubAppInputSigner(config.privateKey);
  const tokenBroker = createGitHubAppTokenBroker({
    now: Date.now,
    sign: (_privateKey, signingInput) => signer(signingInput),
    exchange: async (input, exchangeSignal) => {
      const result = await httpClient.execute({
        kind: "TOKEN_EXCHANGE",
        installationId: input.installationId,
        appJwt: input.appJwt,
        repositoryIds: input.repositoryIds,
        permissions: input.permissions,
      }, exchangeSignal ?? signal);
      if (!("token" in result) || !("expiresAt" in result)) {
        throw projectFilesError("GITHUB_TOKEN_EXCHANGE_FAILED");
      }
      return result;
    },
  });
  const provider = createWebsiteProjectFilesProvider({
    config,
    signal,
    tokenBroker,
    httpClient,
  });
  return createWebsiteProjectFilesService({
    provider,
    cursorSecret: Deno.env.get(
      "LWS_WEBSITE_PROJECT_FILES_CURSOR_SIGNING_KEY_V1",
    ),
  });
}

async function createWebsiteProjectPreviewRuntimeService(
  signal: AbortSignal,
  storageClient: WebsiteProjectPreviewStorageClient,
): Promise<WebsiteProjectPreviewBuilderService> {
  const config = loadGitHubAppConfig();
  const httpClient = createGitHubHttpClient({
    fetch: (input, init) => fetch(input, { ...init, signal }),
  });
  const signer = await initializeGitHubAppInputSigner(config.privateKey);
  const tokenBroker = createGitHubAppTokenBroker({
    now: Date.now,
    sign: (_privateKey, signingInput) => signer(signingInput),
    exchange: async (input, exchangeSignal) => {
      const result = await httpClient.execute({
        kind: "TOKEN_EXCHANGE",
        installationId: input.installationId,
        appJwt: input.appJwt,
        repositoryIds: input.repositoryIds,
        permissions: input.permissions,
      }, exchangeSignal ?? signal);
      if (!("token" in result) || !("expiresAt" in result)) {
        throw projectFilesError("GITHUB_TOKEN_EXCHANGE_FAILED");
      }
      return result;
    },
  });
  const provider = createWebsiteProjectFilesProvider({
    config,
    signal,
    tokenBroker,
    httpClient,
  });
  const storage = storageClient.storage.from("website-project-previews");
  return createWebsiteProjectPreviewBuilder({
    provider,
    storage,
  });
}

export async function executeCallerJwtWorkforceCalendarAction(
  jwt: string,
  input: WorkforceCalendarActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeWorkforceCalendarTransport(
    clientFor(jwt),
    input,
  );
}

export async function executeCallerJwtDossierDocumentManifestAction(
  jwt: string,
  input: Extract<
    DossierDocumentActionInput,
    { action: "get_dossier_document_manifest" }
  >,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeDossierDocumentManifestTransport(clientFor(jwt), input);
}

export async function executeServiceRoleDossierDocumentAction(
  actorAuthUserId: string,
  input: Extract<
    DossierDocumentActionInput,
    { action: "create_dossier_document_access" }
  >,
  client: DossierDocumentServiceClient,
  now: () => number = () => Date.now(),
): Promise<unknown> {
  return await executeDossierDocumentAccessTransport(
    client,
    actorAuthUserId,
    input,
    async (bucket, path, expiresInSeconds, filename) => {
      const { data, error } = await client.storage.from(bucket).createSignedUrl(
        path,
        expiresInSeconds,
        { download: filename },
      );
      if (error || !data) {
        throw new Error(
          error?.message || "INVALID_DOSSIER_DOCUMENT_SIGNED_URL",
        );
      }
      return data.signedUrl;
    },
    now,
  );
}

type QuotationBusinessDraftRpcClient = Readonly<{
  rpc(name: string, args: Record<string, unknown>): PromiseLike<
    Readonly<{
      data: unknown;
      error: Readonly<{ message: string }> | null;
    }>
  >;
}>;

const SHA = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;

function isWebsitePricingDecisionResponse(
  value: unknown,
): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const result = value as Record<string, unknown>;
  const expected = [
    "decision_id",
    "resolved_rule_id",
    "currency",
    "known_minimum_minor",
    "owner_final_amount_minor",
    "decision_sha256",
    "decided_at",
  ];
  return Object.keys(result).length === expected.length &&
    expected.every((key) => key in result) &&
    UUID.test(String(result.decision_id || "")) &&
    typeof result.resolved_rule_id === "string" &&
    result.resolved_rule_id.length > 0 &&
    result.currency === "EUR" &&
    Number.isSafeInteger(result.known_minimum_minor) &&
    Number.isSafeInteger(result.owner_final_amount_minor) &&
    Number(result.owner_final_amount_minor) >=
      Number(result.known_minimum_minor) &&
    SHA256.test(String(result.decision_sha256 || "")) &&
    typeof result.decided_at === "string" && result.decided_at.length > 0;
}

function isWebsitePricingStateResponse(
  value: unknown,
): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const result = value as Record<string, unknown>;
  const expected = [
    "quote_request_id",
    "intake_id",
    "pricing_snapshot_id",
    "pricing_snapshot_sha256",
    "currency",
    "known_minimum_minor",
    "contains_from_pricing",
    "decision_required",
    "can_decide",
    "resolved",
    "decision",
    "quotation_draft_available",
    "billing_context_complete",
    "billing_context",
  ];
  const billing = result.billing_context as Record<string, unknown> | null;
  const billingKeys = [
    "billing_address",
    "billing_postal_code",
    "billing_city",
    "billing_country",
    "billing_email",
  ];
  return Object.keys(result).length === expected.length &&
    expected.every((key) => key in result) &&
    UUID.test(String(result.quote_request_id || "")) &&
    UUID.test(String(result.intake_id || "")) &&
    UUID.test(String(result.pricing_snapshot_id || "")) &&
    SHA256.test(String(result.pricing_snapshot_sha256 || "")) &&
    result.currency === "EUR" &&
    Number.isSafeInteger(result.known_minimum_minor) &&
    Number(result.known_minimum_minor) >= 0 &&
    [
      "contains_from_pricing",
      "decision_required",
      "can_decide",
      "resolved",
      "quotation_draft_available",
      "billing_context_complete",
    ]
      .every((key) => typeof result[key] === "boolean") &&
    billing !== null && typeof billing === "object" &&
    !Array.isArray(billing) &&
    Object.keys(billing).length === billingKeys.length &&
    billingKeys.every((key) =>
      key in billing &&
      (billing[key] === null || typeof billing[key] === "string")
    ) &&
    (result.decision === null ||
      isWebsitePricingDecisionResponse(result.decision));
}

export async function executeWebsiteQuotationPricingStateAction(
  actorAuthUserId: string,
  input: WebsiteQuotationPricingStateActionInput,
  client: QuotationBusinessDraftRpcClient,
): Promise<unknown> {
  const { data, error } = await client.rpc(
    "get_operator_website_quotation_pricing_state_v1",
    {
      p_actor_auth_user_id: actorAuthUserId,
      p_quote_request_id: input.quote_request_id,
      p_intake_id: input.intake_id,
    },
  );
  if (error) throw new Error(error.message);
  if (!isWebsitePricingStateResponse(data)) {
    throw new Error("INVALID_WEBSITE_PRICING_STATE_RESPONSE");
  }
  return data;
}

export async function executeWebsiteQuotationApprovalStatusAction(
  input: WebsiteQuotationApprovalStatusActionInput,
  options: Readonly<{ callerClient: QuotationBusinessDraftRpcClient }>,
): Promise<Record<string, unknown>> {
  const response = await options.callerClient.rpc(
    "get_website_quotation_approval_status_v1",
    {
      p_quote_request_id: input.quote_request_id,
      p_intake_id: input.intake_id,
    },
  );
  if (response.error) throw new Error(response.error.message);
  return validateWebsiteQuotationApprovalStatusResult(response.data, input);
}

export async function executeCallerJwtQuotationVatReadinessAction(
  jwt: string,
  input: VatReadinessActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  const { data, error } = await clientFor(jwt).rpc(
    "get_quotation_vat_readiness_v1",
    { p_quote_request_id: input.quote_request_id },
  );
  if (error) throw new Error(error.message);
  return normalizeVatReadinessResponse(data);
}

type QuotationIssuanceRuntimeOptions = Omit<
  QuotationRuntimeOptions,
  "actorAuthUserId"
>;

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

type WebsiteAgreementConceptRuntimeOptions = Readonly<{
  callerClient: QuotationBusinessDraftRpcClient;
  serviceClient: QuotationBusinessDraftRpcClient;
  templateBytes: Uint8Array;
  renderDocx(
    input: Readonly<{
      templateBytes: Uint8Array;
      payload: Record<string, unknown>;
    }>,
  ): PromiseLike<
    Readonly<{
      buffer: Uint8Array;
      sha256: string;
      templateSha256: string;
      agreementStatus: "UNSIGNED_CONCEPT";
      issuanceStatus: "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED";
    }>
  >;
}>;

type WebsiteDeliveryDocumentRuntimeOptions = Readonly<{
  callerClient: QuotationBusinessDraftRpcClient;
  serviceClient: QuotationBusinessDraftRpcClient & Readonly<{
    storage: Readonly<{
      from(bucket: string): Readonly<{
        upload(path: string, bytes: Uint8Array, options: Readonly<{ contentType: string; upsert: false }>): PromiseLike<Readonly<{ data: unknown; error: Readonly<{ message: string }> | null }>>;
        download(path: string): PromiseLike<Readonly<{ data: Blob | null; error: Readonly<{ message: string }> | null }>>;
        remove(paths: string[]): PromiseLike<Readonly<{ data: unknown; error: Readonly<{ message: string }> | null }>>;
      }>;
    }>;
  }>;
  templateBytes: Uint8Array;
  renderDocx(input: Readonly<{ templateBytes: Uint8Array; payload: Record<string, unknown> }>): PromiseLike<Readonly<{
    buffer: Uint8Array;
    sha256: string;
    templateSha256: string;
  }>>;
  startPdfConversion?(binding: Readonly<{
    artifactId: string;
    projectId: string;
    previewVersionId: string;
    documentVersion: number;
    sourceDocxSha256: string;
    generationPayloadSha256: string;
    runtimeTemplateSha256: string;
    idempotencyKey: string;
    actor: string;
  }>): PromiseLike<Readonly<{
    taskId: string;
    taskWasCreated: boolean;
    dispatchStatus: string;
  }>>;
}>;

const WEBSITE_DELIVERY_MIME =
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const WEBSITE_DELIVERY_RUNTIME_TEMPLATE_REFERENCE =
  "LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v2.docx";
const WEBSITE_DELIVERY_RUNTIME_TEMPLATE_VERSION = "v2";
const WEBSITE_DELIVERY_RUNTIME_TEMPLATE_SHA256 =
  "84f16839f584e6949c9fc6389d72894160e65fbf67746eb3bc0effb0d546706d";

type WebsiteDeliveryPdfBinding = Readonly<{
  artifactId: string;
  projectId: string;
  previewVersionId: string;
  documentVersion: number;
  sourceDocxSha256: string;
  generationPayloadSha256: string;
  runtimeTemplateSha256: string;
  idempotencyKey: string;
  actor: string;
}>;

export function createWebsiteDeliveryPdfRuntimeStarter(
  taskId: string,
  actor: string,
  client: QuotationBusinessDraftRpcClient,
  createProvider?: () =>
    | ReturnType<typeof createWebsiteDeliveryPdfWorkflowDispatch>
    | PromiseLike<ReturnType<typeof createWebsiteDeliveryPdfWorkflowDispatch>>,
) {
  let providerPromise: ReturnType<
    typeof createWebsiteDeliveryPdfWorkflowDispatch
  > | null = null;
  const provider = async () => {
    if (providerPromise) return providerPromise;
    if (createProvider) {
      providerPromise = await createProvider();
      return providerPromise;
    }
    const config = loadWebsiteDeliveryPdfDispatchAppConfig();
    const http = createGitHubHttpClient({ fetch });
    const signer = await initializeGitHubAppInputSigner(config.privateKey);
    const broker = createGitHubAppTokenBroker({
      now: Date.now,
      sign: (_privateKey, signingInput) => signer(signingInput),
      exchange: async (exchange) => {
        const result = await http.execute({
          kind: "TOKEN_EXCHANGE",
          installationId: exchange.installationId,
          appJwt: exchange.appJwt,
          repositoryIds: exchange.repositoryIds,
          permissions: exchange.permissions,
        });
        if (!("token" in result) || !("expiresAt" in result)) {
          throw new Error("GITHUB_TOKEN_EXCHANGE_FAILED");
        }
        return result;
      },
    });
    providerPromise = createWebsiteDeliveryPdfWorkflowDispatch({
      now: Date.now,
      fetch: (request) => fetch(request),
      acquireToken: () =>
        broker.issue(config, {
          websiteWorkContextId: taskId,
          target: "PRODUCTION",
          organization: config.organization,
          operation: "WEBSITE_DELIVERY_PDF_DISPATCH",
          repositoryIds: [config.repositoryId],
        }, {
          websiteWorkContextId: taskId,
          target: "PRODUCTION",
          organization: config.organization,
          repositoryIds: [config.repositoryId],
        }),
    });
    return providerPromise;
  };
  const rpcRecord = async (name: string, parameters: Record<string, unknown>) => {
    const response = await client.rpc(name, parameters);
    if (response.error) throw new Error(response.error.message);
    return websiteAgreementRecord(
      response.data,
      "INVALID_WEBSITE_DELIVERY_PDF_DISPATCH_RESPONSE",
    );
  };
  return createWebsiteDeliveryPdfWorkflowStarter({
    claim: async (claimedTaskId) =>
      await rpcRecord("claim_website_delivery_pdf_dispatch_v1", {
        p_task_id: claimedTaskId,
        p_actor: actor,
      }) as never,
    record: async (recordedTaskId, attemptId, result) =>
      await rpcRecord("record_website_delivery_pdf_dispatch_result_v1", {
        p_task_id: recordedTaskId,
        p_dispatch_attempt_id: attemptId,
        p_status: result.status,
        p_result_code: result.code,
        p_actor: actor,
      }) as never,
    status: async (statusTaskId) =>
      await rpcRecord("get_website_delivery_pdf_dispatch_status_v1", {
        p_task_id: statusTaskId,
      }) as never,
    reconcile: async (reconciledTaskId, evidence) =>
      await rpcRecord("reconcile_website_delivery_pdf_dispatch_unknown_v1", {
        p_task_id: reconciledTaskId,
        p_provider_run_id: evidence.providerRunId,
        p_provider_run_attempt: evidence.providerRunAttempt,
        p_provider_checked_at: evidence.checkedAt,
        p_reconciliation_id: crypto.randomUUID(),
        p_approved: false,
        p_actor: actor,
      }) as never,
    reconcileRerun: async (reconciledTaskId, recoveryId, evidence) =>
      await rpcRecord("reconcile_website_delivery_pdf_rerun_unknown_v1", {
        p_task_id: reconciledTaskId,
        p_recovery_id: recoveryId,
        p_provider_run_id: evidence.providerRunId,
        p_provider_run_attempt: evidence.providerRunAttempt,
        p_provider_status: evidence.providerRunStatus,
        p_provider_conclusion: evidence.providerRunConclusion,
        p_provider_checked_at: evidence.checkedAt,
        p_actor: actor,
      }) as never,
    claimRerun: async (recoveryTaskId, attemptId, evidence, approvalId) =>
      await rpcRecord("claim_website_delivery_pdf_rerun_v1", {
        p_task_id: recoveryTaskId,
        p_expected_dispatch_attempt_id: attemptId,
        p_provider_run_id: evidence.providerRunId,
        p_provider_run_attempt: evidence.providerRunAttempt,
        p_provider_status: evidence.providerRunStatus,
        p_provider_conclusion: evidence.providerRunConclusion,
        p_approval_id: approvalId,
        p_provider_checked_at: evidence.checkedAt,
        p_actor: actor,
      }) as never,
    recordRerun: async (recoveryTaskId, approvalId, result) =>
      await rpcRecord("record_website_delivery_pdf_rerun_result_v1", {
        p_task_id: recoveryTaskId,
        p_approval_id: approvalId,
        p_status: result.status,
        p_result_code: result.code,
        p_actor: actor,
      }) as never,
    dispatch: async (dispatchedTaskId) =>
      (await provider()).dispatch(dispatchedTaskId),
    rerun: async (recoveryTaskId, providerRunId) =>
      (await provider()).rerun(recoveryTaskId, providerRunId),
    findRun: async (readbackTaskId, dispatchStartedAt) =>
      (await provider()).findRun(readbackTaskId, dispatchStartedAt),
  });
}

async function startWebsiteDeliveryPdfConversion(
  binding: WebsiteDeliveryPdfBinding,
  client: QuotationBusinessDraftRpcClient,
): Promise<Readonly<{
  taskId: string;
  taskWasCreated: boolean;
  dispatchStatus: string;
}>> {
  const taskResponse = await client.rpc(
    "create_website_delivery_pdf_conversion_task_v1",
    {
      p_artifact_id: binding.artifactId,
      p_expected_project_id: binding.projectId,
      p_expected_preview_version_id: binding.previewVersionId,
      p_expected_document_version: binding.documentVersion,
      p_expected_source_docx_sha256: binding.sourceDocxSha256,
      p_expected_generation_payload_sha256: binding.generationPayloadSha256,
      p_expected_runtime_template_sha256: binding.runtimeTemplateSha256,
      p_idempotency_key: binding.idempotencyKey,
      p_actor: binding.actor,
    },
  );
  if (taskResponse.error) throw new Error(taskResponse.error.message);
  const task = websiteAgreementRecord(
    taskResponse.data,
    "INVALID_WEBSITE_DELIVERY_PDF_TASK_RESPONSE",
  );
  const taskId = String(task.task_id || "");
  if (
    !UUID.test(taskId) || task.artifact_id !== binding.artifactId ||
    task.project_id !== binding.projectId ||
    task.preview_version_id !== binding.previewVersionId ||
    task.document_version !== binding.documentVersion ||
    task.source_docx_sha256 !== binding.sourceDocxSha256 ||
    task.generation_payload_sha256 !== binding.generationPayloadSha256 ||
    task.runtime_template_sha256 !== binding.runtimeTemplateSha256 ||
    typeof task.was_created !== "boolean"
  ) throw new Error("INVALID_WEBSITE_DELIVERY_PDF_TASK_RESPONSE");

  const starter = createWebsiteDeliveryPdfRuntimeStarter(
    taskId,
    binding.actor,
    client,
  );
  const dispatch = await starter.start(taskId);
  return {
    taskId,
    taskWasCreated: task.was_created,
    dispatchStatus: dispatch.status,
  };
}

type WebsiteDeliveryDocumentViewRuntimeOptions = Readonly<{
  callerClient: QuotationBusinessDraftRpcClient;
  serviceClient: QuotationBusinessDraftRpcClient & Readonly<{
    storage: Readonly<{
      from(bucket: string): Readonly<{
        download(path: string): PromiseLike<Readonly<{
          data: Blob | null;
          error: Readonly<{ message: string }> | null;
        }>>;
      }>;
    }>;
  }>;
}>;

type WebsiteDeliveryPdfRecoveryStarter = Readonly<{
  read(taskId: string): Promise<Readonly<Record<string, unknown>>>;
  inspect(taskId: string): Promise<Readonly<Record<string, unknown>>>;
  recover(
    taskId: string,
    expectedDispatchAttemptId: string,
    approvalId: string,
  ): Promise<Readonly<Record<string, unknown>>>;
}>;

type WebsiteDeliveryPdfRecoveryRuntimeOptions = Readonly<{
  callerClient: QuotationBusinessDraftRpcClient;
  serviceClient: QuotationBusinessDraftRpcClient;
  createStarter(
    taskId: string,
    actor: string,
    serviceClient: QuotationBusinessDraftRpcClient,
  ): WebsiteDeliveryPdfRecoveryStarter | PromiseLike<WebsiteDeliveryPdfRecoveryStarter>;
}>;

const WEBSITE_DELIVERY_PDF_SAFE_STATUS_FIELDS = [
  "task_id",
  "document_version",
  "status",
  "result_code",
  "dispatch_attempt",
  "dispatch_attempt_id",
  "created_at",
  "dispatch_started_at",
  "dispatch_finished_at",
  "provider_checked_at",
  "running_at",
  "completed_at",
  "recovery_status",
  "recovery_result_code",
  "recovery_approved_at",
  "rerun_started_at",
  "rerun_finished_at",
  "allowed_action",
] as const;

function websiteDeliveryPdfSafeStatus(
  projectId: string,
  value: Record<string, unknown>,
): Record<string, unknown> {
  const result: Record<string, unknown> = { project_id: projectId };
  for (const field of WEBSITE_DELIVERY_PDF_SAFE_STATUS_FIELDS) {
    if (value[field] !== undefined) result[field] = value[field];
  }
  return result;
}

export async function executeWebsiteDeliveryPdfRecoveryAction(
  actorAuthUserId: string,
  input: WebsiteDeliveryPdfStatusActionInput | WebsiteDeliveryPdfRerunActionInput,
  options: WebsiteDeliveryPdfRecoveryRuntimeOptions,
): Promise<Record<string, unknown>> {
  const identityResponse = await options.callerClient.rpc(
    "get_current_operator_identity_v1",
    {},
  );
  if (identityResponse.error) throw new Error(identityResponse.error.message);
  const identity = websiteAgreementRecord(
    identityResponse.data,
    "INVALID_OPERATOR_IDENTITY_RESPONSE",
  );
  if (
    identity.status !== "ACTIVE" ||
    !["owner", "admin"].includes(String(identity.role || ""))
  ) throw new Error("OPERATOR_NOT_AUTHORIZED");

  const authorization = await options.callerClient.rpc(
    "get_operator_project_start_gate_v1",
    {
      p_quote_request_id: input.quote_request_id,
      p_project_id: input.project_id,
    },
  );
  if (authorization.error || !authorization.data) {
    throw new Error(authorization.error?.message || "OPERATOR_NOT_AUTHORIZED");
  }

  const statusResponse = await options.serviceClient.rpc(
    "get_website_delivery_pdf_operator_status_v1",
    { p_project_id: input.project_id },
  );
  if (statusResponse.error) throw new Error(statusResponse.error.message);
  const status = websiteAgreementRecord(
    statusResponse.data,
    "INVALID_WEBSITE_DELIVERY_PDF_STATUS_RESPONSE",
  );
  if (status.project_id !== input.project_id) {
    throw new Error("INVALID_WEBSITE_DELIVERY_PDF_STATUS_RESPONSE");
  }
  if (status.task_id === null) {
    if (input.action === "approve_website_delivery_pdf_rerun") {
      throw new Error("WEBSITE_DELIVERY_PDF_RECOVERY_STALE");
    }
    return websiteDeliveryPdfSafeStatus(input.project_id, status);
  }
  const taskId = String(status.task_id || "");
  const attemptId = String(status.dispatch_attempt_id || "");
  if (!UUID.test(taskId) || !UUID.test(attemptId)) {
    throw new Error("INVALID_WEBSITE_DELIVERY_PDF_STATUS_RESPONSE");
  }
  if (
    input.action === "approve_website_delivery_pdf_rerun" &&
    (input.task_id !== taskId || input.expected_dispatch_attempt_id !== attemptId)
  ) throw new Error("WEBSITE_DELIVERY_PDF_RECOVERY_STALE");

  const starter = await options.createStarter(
    taskId,
    actorAuthUserId,
    options.serviceClient,
  );
  if (input.action === "get_website_delivery_pdf_status") {
    if (status.allowed_action === "INSPECT_PROVIDER") {
      return websiteDeliveryPdfSafeStatus(
        input.project_id,
        { ...await starter.inspect(taskId) },
      );
    }
    return websiteDeliveryPdfSafeStatus(
      input.project_id,
      { ...status, ...await starter.read(taskId) },
    );
  }
  const recovery = await starter.recover(taskId, attemptId, input.approval_id);
  const recoveryStatus = String(
    recovery.recovery_status || recovery.status || "",
  );
  const recoveryResultCode = String(recovery.result_code || "");
  if (
    !/^(RERUN_UNKNOWN|RERUN_ACCEPTED|RERUN_FAILED|RUNNING|COMPLETED)$/.test(
      recoveryStatus,
    ) || !/^[A-Z][A-Z0-9_]{0,99}$/.test(recoveryResultCode)
  ) throw new Error("INVALID_WEBSITE_DELIVERY_PDF_RECOVERY_RESPONSE");
  return websiteDeliveryPdfSafeStatus(input.project_id, {
    ...status,
    recovery_status: recoveryStatus,
    recovery_result_code: recoveryResultCode,
    allowed_action: ["RERUN_UNKNOWN", "RERUN_ACCEPTED", "RUNNING"].includes(
        recoveryStatus,
      )
      ? "WAIT_FOR_RERUN"
      : "NONE",
  });
}

export async function executeWebsiteDeliveryDocumentViewAction(
  actorAuthUserId: string,
  input: WebsiteDeliveryDocumentViewActionInput,
  options: WebsiteDeliveryDocumentViewRuntimeOptions,
): Promise<Response> {
  const authorization = await options.callerClient.rpc(
    "get_operator_project_start_gate_v1",
    {
      p_quote_request_id: input.quote_request_id,
      p_project_id: input.project_id,
    },
  );
  if (authorization.error || !authorization.data) {
    throw new Error(authorization.error?.message || "OPERATOR_NOT_AUTHORIZED");
  }

  const resolvedResponse = await options.serviceClient.rpc(
    "resolve_current_website_delivery_document_view_v1",
    { p_project_id: input.project_id },
  );
  if (resolvedResponse.error || !resolvedResponse.data) {
    throw new Error(resolvedResponse.error?.message || "WEBSITE_DELIVERY_VIEW_NOT_FOUND");
  }
  const view = websiteAgreementRecord(
    resolvedResponse.data,
    "INVALID_WEBSITE_DELIVERY_VIEW_RESPONSE",
  );
  if (
    !UUID.test(String(view.view_derivative_id || "")) ||
    view.project_id !== input.project_id ||
    !Number.isSafeInteger(view.document_version) || Number(view.document_version) < 1 ||
    view.storage_bucket_id !== "website-delivery-document-views" ||
    typeof view.storage_object_path !== "string" || !view.storage_object_path ||
    view.content_type !== "application/pdf" ||
    !SHA256.test(String(view.source_docx_sha256 || "")) ||
    !SHA256.test(String(view.pdf_sha256 || "")) ||
    !Number.isSafeInteger(view.pdf_bytes) || Number(view.pdf_bytes) < 1
  ) throw new Error("INVALID_WEBSITE_DELIVERY_VIEW_RESPONSE");

  const downloaded = await options.serviceClient.storage
    .from(String(view.storage_bucket_id))
    .download(String(view.storage_object_path));
  if (downloaded.error || !downloaded.data) {
    throw new Error(downloaded.error?.message || "WEBSITE_DELIVERY_VIEW_DOWNLOAD_FAILED");
  }
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
  const actualSha256 = await sha256Hex(bytes);
  if (bytes.byteLength !== view.pdf_bytes || actualSha256 !== view.pdf_sha256) {
    throw new Error("WEBSITE_DELIVERY_VIEW_HASH_MISMATCH");
  }

  const receiptResponse = await options.serviceClient.rpc(
    "register_website_delivery_document_access_receipt_v1",
    {
      p_view_derivative_id: view.view_derivative_id,
      p_viewer_kind: "OPERATOR",
      p_operator_auth_user_id: actorAuthUserId,
      p_preview_session_id: null,
      p_served_pdf_sha256: actualSha256,
      p_served_pdf_bytes: bytes.byteLength,
      p_served_by: "commercial-operator-command",
    },
  );
  if (receiptResponse.error || !receiptResponse.data) {
    throw new Error(receiptResponse.error?.message || "WEBSITE_DELIVERY_VIEW_RECEIPT_FAILED");
  }

  return new Response(bytes, {
    status: 200,
    headers: {
      "cache-control": "private, no-store",
      "content-disposition": `inline; filename="opleverdocument-v${view.document_version}.pdf"`,
      "content-length": String(bytes.byteLength),
      "content-type": "application/pdf",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-lws-document-sha256": actualSha256,
      "x-lws-document-version": String(view.document_version),
      "x-lws-source-docx-sha256": String(view.source_docx_sha256),
    },
  });
}

export async function executeWebsiteDeliveryDocumentAction(
  actor: string,
  input: WebsiteDeliveryDocumentActionInput,
  options: WebsiteDeliveryDocumentRuntimeOptions,
): Promise<unknown> {
  const identityResponse = await options.callerClient.rpc(
    "get_current_operator_identity_v1",
    {},
  );
  if (identityResponse.error) throw new Error(identityResponse.error.message);
  const identity = websiteAgreementRecord(
    identityResponse.data,
    "INVALID_OPERATOR_IDENTITY_RESPONSE",
  );
  if (
    identity.status !== "ACTIVE" ||
    !["owner", "admin"].includes(String(identity.role || ""))
  ) throw new Error("OPERATOR_NOT_AUTHORIZED");

  const preparedResponse = await options.serviceClient.rpc(
    "prepare_website_delivery_document_v1",
    {
      p_project_id: input.project_id,
      p_delivery_date: input.delivery_date,
      p_checklist: input.checklist,
      p_remarks_state: input.remarks_state,
      p_remarks_text: input.remarks_text,
      p_contractor_signature_date: input.contractor_signature_date,
      p_contractor_signature_place: input.contractor_signature_place,
      // The customer signs date and place only on the accepted document; never before acceptance.
      p_customer_signature_date: null,
      p_customer_signature_place: null,
      p_idempotency_key: input.idempotency_key,
      p_actor: actor,
    },
  );
  if (preparedResponse.error) throw new Error(preparedResponse.error.message);
  const prepared = websiteAgreementRecord(
    preparedResponse.data,
    "INVALID_WEBSITE_DELIVERY_PREPARE_RESPONSE",
  );
  const candidateId = String(prepared.candidate_id || "");
  const documentVersion = Number(prepared.document_version);
  const generationPayloadSha256 = String(
    prepared.generation_payload_sha256 || "",
  );
  const payload = websiteAgreementRecord(
    prepared.generation_payload,
    "INVALID_WEBSITE_DELIVERY_PREPARE_RESPONSE",
  );
  const lineage = websiteAgreementRecord(
    payload.lineage,
    "INVALID_WEBSITE_DELIVERY_PREPARE_RESPONSE",
  );
  const previewVersionId = String(lineage.preview_version_id || "");
  if (
    !UUID.test(candidateId) || !Number.isSafeInteger(documentVersion) ||
    documentVersion < 1 || lineage.project_id !== input.project_id ||
    !UUID.test(previewVersionId) ||
    !SHA256.test(generationPayloadSha256) ||
    typeof prepared.was_created !== "boolean"
  ) throw new Error("INVALID_WEBSITE_DELIVERY_PREPARE_RESPONSE");

  const rendered = await options.renderDocx({
    templateBytes: options.templateBytes,
    payload,
  });
  if (
    !SHA256.test(rendered.sha256) ||
    await sha256Hex(rendered.buffer) !== rendered.sha256 ||
    rendered.templateSha256 !== WEBSITE_DELIVERY_RUNTIME_TEMPLATE_SHA256 ||
    rendered.buffer.byteLength < 1 || rendered.buffer.byteLength > 10_485_760
  ) throw new Error("INVALID_WEBSITE_DELIVERY_RENDER_RESPONSE");

  const bucket = "website-delivery-documents";
  const path = `projects/${input.project_id}/versions/${documentVersion}/${rendered.sha256}.docx`;
  const storage = options.serviceClient.storage.from(bucket);
  let uploadedByAttempt = false;
  if (prepared.was_created) {
    const uploaded = await storage.upload(path, rendered.buffer, {
      contentType: WEBSITE_DELIVERY_MIME,
      upsert: false,
    });
    uploadedByAttempt = !uploaded.error;
    if (uploaded.error) {
      const existing = await storage.download(path);
      if (existing.error || !existing.data) {
        throw new Error("WEBSITE_DELIVERY_STORAGE_UPLOAD_FAILED");
      }
    }
  }

  const readback = await storage.download(path);
  if (readback.error || !readback.data) {
    if (uploadedByAttempt) await storage.remove([path]);
    throw new Error("WEBSITE_DELIVERY_STORAGE_READBACK_FAILED");
  }
  const storedBytes = new Uint8Array(await readback.data.arrayBuffer());
  if (
    storedBytes.byteLength !== rendered.buffer.byteLength ||
    (readback.data.type && readback.data.type !== WEBSITE_DELIVERY_MIME) ||
    await sha256Hex(storedBytes) !== rendered.sha256
  ) {
    if (uploadedByAttempt) await storage.remove([path]);
    throw new Error("WEBSITE_DELIVERY_STORAGE_READBACK_MISMATCH");
  }

  const registrationInput = {
      p_candidate_id: candidateId,
      p_docx_sha256: rendered.sha256,
      p_docx_bytes: rendered.buffer.byteLength,
      p_content_type: WEBSITE_DELIVERY_MIME,
      p_runtime_template_reference: WEBSITE_DELIVERY_RUNTIME_TEMPLATE_REFERENCE,
      p_runtime_template_version: WEBSITE_DELIVERY_RUNTIME_TEMPLATE_VERSION,
      p_runtime_template_sha256: rendered.templateSha256,
      p_idempotency_key: candidateId,
      p_actor: actor,
  };
  let registeredResponse = await options.serviceClient.rpc(
    "register_website_delivery_document_artifact_v2",
    registrationInput,
  );
  if (registeredResponse.error) {
    registeredResponse = await options.serviceClient.rpc(
      "register_website_delivery_document_artifact_v2",
      registrationInput,
    );
    if (registeredResponse.error) throw new Error(registeredResponse.error.message);
  }
  const parseRegistered = (data: unknown) => {
    try {
      const value = websiteAgreementRecord(
        data,
        "INVALID_WEBSITE_DELIVERY_REGISTER_RESPONSE",
      );
      return UUID.test(String(value.artifact_id || "")) &&
          value.storage_bucket_id === bucket && value.storage_object_path === path &&
          value.docx_sha256 === rendered.sha256 &&
          value.docx_bytes === rendered.buffer.byteLength &&
          typeof value.was_created === "boolean"
        ? value
        : null;
    } catch {
      return null;
    }
  };
  let registered = parseRegistered(registeredResponse.data);
  if (!registered) {
    registeredResponse = await options.serviceClient.rpc(
      "register_website_delivery_document_artifact_v2",
      registrationInput,
    );
    if (registeredResponse.error) throw new Error(registeredResponse.error.message);
    registered = parseRegistered(registeredResponse.data);
    if (!registered) throw new Error("INVALID_WEBSITE_DELIVERY_REGISTER_RESPONSE");
  }
  // Once registration starts, an ambiguous response may hide a committed row.
  // Preserve verified bytes rather than risk deleting an object's successful evidence.
  uploadedByAttempt = false;
  const pdfConversion = options.startPdfConversion
    ? await options.startPdfConversion({
      artifactId: String(registered.artifact_id),
      projectId: input.project_id,
      previewVersionId,
      documentVersion,
      sourceDocxSha256: rendered.sha256,
      generationPayloadSha256,
      runtimeTemplateSha256: rendered.templateSha256,
      idempotencyKey: String(registered.artifact_id),
      actor,
    })
    : null;
  return {
    project_id: input.project_id,
    candidate_id: candidateId,
    artifact_id: registered.artifact_id,
    document_version: documentVersion,
    preview_version_id: previewVersionId,
    storage_bucket_id: bucket,
    storage_object_path: path,
    docx_sha256: rendered.sha256,
    docx_bytes: rendered.buffer.byteLength,
    generation_payload_sha256: generationPayloadSha256,
    runtime_template_sha256: rendered.templateSha256,
    candidate_was_created: prepared.was_created,
    artifact_was_created: registered.was_created,
    ...(pdfConversion
      ? {
        pdf_conversion_task_id: pdfConversion.taskId,
        pdf_conversion_task_was_created: pdfConversion.taskWasCreated,
        pdf_dispatch_status: pdfConversion.dispatchStatus,
      }
      : {}),
  };
}

type WebsiteInvoiceAction = WebsiteInvoiceConceptActionInput["action"];

type WebsiteInvoiceDocumentKind = "INVOICE_M1" | "INVOICE_M2" | "INVOICE_FINAL";

export const WEBSITE_INVOICE_ACTION_AUTHORITIES: Readonly<
  Record<
    WebsiteInvoiceAction,
    Readonly<{
      documentKind: WebsiteInvoiceDocumentKind;
      milestone: 1 | 2 | 3;
      filename: string;
    }>
  >
> = Object.freeze({
  prepare_website_invoice_m1_concept: {
    documentKind: "INVOICE_M1",
    milestone: 1,
    filename: "LWS_WEBSITE_INVOICE_M1_40_NONPRODUCTION_v1.docx",
  },
  prepare_website_invoice_m2_concept: {
    documentKind: "INVOICE_M2",
    milestone: 2,
    filename: "LWS_WEBSITE_INVOICE_M2_40_NONPRODUCTION_v1.docx",
  },
  prepare_website_invoice_final_concept: {
    documentKind: "INVOICE_FINAL",
    milestone: 3,
    filename: "LWS_WEBSITE_INVOICE_FINAL_REMAINDER_NONPRODUCTION_v1.docx",
  },
});

type WebsiteInvoiceConceptRuntimeOptions = Readonly<{
  callerClient: QuotationBusinessDraftRpcClient;
  serviceClient: QuotationBusinessDraftRpcClient;
  templateBytes: Uint8Array;
  renderDocx(
    input: Readonly<{
      templateBytes: Uint8Array;
      payload: Record<string, unknown>;
    }>,
  ): PromiseLike<
    Readonly<{
      buffer: Uint8Array;
      sha256: string;
      documentKind: WebsiteInvoiceDocumentKind | "AGREEMENT";
      templateSha256: string;
      issuanceStatus: "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED";
    }>
  >;
}>;

async function websiteInvoicePrepareKey(
  projectId: string,
  documentKind: WebsiteInvoiceDocumentKind,
): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(
        `website-invoice-concept-v1:${projectId}:${documentKind}`,
      ),
    ),
  ).slice(0, 16);
  digest[6] = (digest[6] & 0x0f) | 0x80;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = Array.from(digest, (value) => value.toString(16).padStart(2, "0"))
    .join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
}

function websiteAgreementRecord(
  value: unknown,
  code: string,
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(code);
  }
  return value as Record<string, unknown>;
}

function websiteExactRecord(
  value: unknown,
  keys: readonly string[],
  code: string,
): Record<string, unknown> {
  const result = websiteAgreementRecord(value, code);
  const actualKeys = Object.keys(result).sort();
  const expectedKeys = [...keys].sort();
  if (
    actualKeys.length !== expectedKeys.length ||
    actualKeys.some((key, index) => key !== expectedKeys[index])
  ) {
    throw new Error(code);
  }
  return result;
}

export async function executeWebsiteAgreementConceptAction(
  input: WebsiteAgreementConceptActionInput,
  options: WebsiteAgreementConceptRuntimeOptions,
): Promise<unknown> {
  const identityResponse = await options.callerClient.rpc(
    "get_current_operator_identity_v1",
    {},
  );
  if (identityResponse.error) throw new Error(identityResponse.error.message);
  const identity = websiteAgreementRecord(
    identityResponse.data,
    "INVALID_OPERATOR_IDENTITY_RESPONSE",
  );
  if (
    identity.status !== "ACTIVE" ||
    !["owner", "admin"].includes(String(identity.role || ""))
  ) {
    throw new Error("OPERATOR_NOT_AUTHORIZED");
  }

  const preparedResponse = await options.serviceClient.rpc(
    "prepare_website_commercial_document_concept_v1",
    {
      p_project_id: input.project_id,
      p_document_kind: "AGREEMENT",
      p_idempotency_key: input.project_id,
    },
  );
  if (preparedResponse.error) throw new Error(preparedResponse.error.message);
  const prepared = websiteAgreementRecord(
    preparedResponse.data,
    "INVALID_WEBSITE_AGREEMENT_PREPARE_RESPONSE",
  );
  const candidateId = String(prepared.candidate_id || "");
  const payloadSha256 = String(prepared.generation_payload_sha256 || "");
  const payload = websiteAgreementRecord(
    prepared.generation_payload,
    "INVALID_WEBSITE_AGREEMENT_PREPARE_RESPONSE",
  );
  const lineage = websiteAgreementRecord(
    payload.lineage,
    "INVALID_WEBSITE_AGREEMENT_PREPARE_RESPONSE",
  );
  const quoteRequestId = String(lineage.quote_request_id || "");
  if (
    !UUID.test(candidateId) || !SHA256.test(payloadSha256) ||
    prepared.issuance_status !== "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED" ||
    typeof prepared.was_created !== "boolean" ||
    payload.document_kind !== "AGREEMENT" ||
    lineage.project_id !== input.project_id ||
    !UUID.test(quoteRequestId)
  ) {
    throw new Error(
      lineage.project_id !== input.project_id
        ? "WEBSITE_COMMERCIAL_PROJECT_BINDING_MISMATCH"
        : "INVALID_WEBSITE_AGREEMENT_PREPARE_RESPONSE",
    );
  }

  const rendered = await options.renderDocx({
    templateBytes: options.templateBytes,
    payload,
  });
  const registeredResponse = await options.serviceClient.rpc(
    "register_website_commercial_document_render_v1",
    {
      p_candidate_id: candidateId,
      p_expected_generation_payload_sha256: payloadSha256,
      p_template_sha256: rendered.templateSha256,
      p_docx_sha256: rendered.sha256,
      p_docx_bytes: rendered.buffer.byteLength,
      p_idempotency_key: candidateId,
    },
  );
  if (registeredResponse.error) {
    throw new Error(registeredResponse.error.message);
  }
  const registered = websiteAgreementRecord(
    registeredResponse.data,
    "INVALID_WEBSITE_AGREEMENT_REGISTER_RESPONSE",
  );
  const artifactId = String(registered.artifact_id || "");
  if (
    !UUID.test(artifactId) || typeof registered.was_created !== "boolean" ||
    registered.issuance_status !== "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED"
  ) {
    throw new Error("INVALID_WEBSITE_AGREEMENT_REGISTER_RESPONSE");
  }
  return {
    project_id: input.project_id,
    quote_request_id: quoteRequestId,
    candidate_id: candidateId,
    artifact_id: artifactId,
    agreement_status: rendered.agreementStatus,
    render_status: "LOCAL_RENDER_ONLY",
    issuance_status: rendered.issuanceStatus,
    storage_status: "NOT_STORED",
    archive_status: "NOT_ARCHIVED",
    delivery_status: "NOT_DELIVERED",
    concept_was_created: prepared.was_created,
    registration_was_created: registered.was_created,
  };
}

export async function executeWebsiteInvoiceConceptAction(
  input: Readonly<{ action: WebsiteInvoiceAction; project_id: string }>,
  options: WebsiteInvoiceConceptRuntimeOptions,
): Promise<unknown> {
  const authority = WEBSITE_INVOICE_ACTION_AUTHORITIES[input.action];
  if (!authority) throw new Error("INVALID_WEBSITE_INVOICE_ACTION");

  const identityResponse = await options.callerClient.rpc(
    "get_current_operator_identity_v1",
    {},
  );
  if (identityResponse.error) throw new Error(identityResponse.error.message);
  const identity = websiteAgreementRecord(
    identityResponse.data,
    "INVALID_OPERATOR_IDENTITY_RESPONSE",
  );
  if (
    identity.status !== "ACTIVE" ||
    !["owner", "admin"].includes(String(identity.role || ""))
  ) {
    throw new Error("OPERATOR_NOT_AUTHORIZED");
  }

  const preparedResponse = await options.serviceClient.rpc(
    "prepare_website_commercial_document_concept_v1",
    {
      p_project_id: input.project_id,
      p_document_kind: authority.documentKind,
      p_idempotency_key: await websiteInvoicePrepareKey(
        input.project_id,
        authority.documentKind,
      ),
    },
  );
  if (preparedResponse.error) throw new Error(preparedResponse.error.message);
  const prepared = websiteExactRecord(
    preparedResponse.data,
    [
      "candidate_id",
      "generation_payload",
      "generation_payload_sha256",
      "issuance_status",
      "was_created",
    ],
    "INVALID_WEBSITE_INVOICE_PREPARE_RESPONSE",
  );
  const candidateId = String(prepared.candidate_id || "");
  const payloadSha256 = String(prepared.generation_payload_sha256 || "");
  const payload = websiteAgreementRecord(
    prepared.generation_payload,
    "INVALID_WEBSITE_INVOICE_PREPARE_RESPONSE",
  );
  const lineage = websiteAgreementRecord(
    payload.lineage,
    "INVALID_WEBSITE_INVOICE_PREPARE_RESPONSE",
  );
  const invoiceFiscal = websiteAgreementRecord(
    payload.invoice_fiscal,
    "INVALID_WEBSITE_INVOICE_PREPARE_RESPONSE",
  );
  const quoteRequestId = String(lineage.quote_request_id || "");
  if (
    !UUID.test(candidateId) || !SHA256.test(payloadSha256) ||
    prepared.issuance_status !== "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED" ||
    typeof prepared.was_created !== "boolean" ||
    payload.document_kind !== authority.documentKind ||
    lineage.project_id !== input.project_id ||
    !UUID.test(quoteRequestId) ||
    !UUID.test(String(lineage.obligation_id || "")) ||
    invoiceFiscal.obligation_id !== lineage.obligation_id ||
    invoiceFiscal.milestone !== authority.milestone
  ) {
    throw new Error(
      lineage.project_id !== input.project_id
        ? "WEBSITE_COMMERCIAL_PROJECT_BINDING_MISMATCH"
        : "INVALID_WEBSITE_INVOICE_PREPARE_RESPONSE",
    );
  }

  const rendered = await options.renderDocx({
    templateBytes: options.templateBytes,
    payload,
  });
  if (
    rendered.documentKind !== authority.documentKind ||
    rendered.issuanceStatus !== "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED"
  ) {
    throw new Error("INVALID_WEBSITE_INVOICE_RENDER_RESPONSE");
  }
  const registeredResponse = await options.serviceClient.rpc(
    "register_website_commercial_document_render_v1",
    {
      p_candidate_id: candidateId,
      p_expected_generation_payload_sha256: payloadSha256,
      p_template_sha256: rendered.templateSha256,
      p_docx_sha256: rendered.sha256,
      p_docx_bytes: rendered.buffer.byteLength,
      p_idempotency_key: candidateId,
    },
  );
  if (registeredResponse.error) {
    throw new Error(registeredResponse.error.message);
  }
  const registered = websiteExactRecord(
    registeredResponse.data,
    ["artifact_id", "issuance_status", "was_created"],
    "INVALID_WEBSITE_INVOICE_REGISTER_RESPONSE",
  );
  const artifactId = String(registered.artifact_id || "");
  if (
    !UUID.test(artifactId) || typeof registered.was_created !== "boolean" ||
    registered.issuance_status !== "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED"
  ) {
    throw new Error("INVALID_WEBSITE_INVOICE_REGISTER_RESPONSE");
  }

  return {
    project_id: input.project_id,
    quote_request_id: quoteRequestId,
    candidate_id: candidateId,
    artifact_id: artifactId,
    document_kind: authority.documentKind,
    milestone: authority.milestone,
    render_status: "LOCAL_RENDER_ONLY",
    issuance_status: rendered.issuanceStatus,
    storage_status: "NOT_STORED",
    archive_status: "NOT_ARCHIVED",
    delivery_status: "NOT_DELIVERED",
    concept_was_created: prepared.was_created,
    registration_was_created: registered.was_created,
  };
}

export async function executeWebsiteAgreementRegistrationStatusAction(
  input: WebsiteAgreementRegistrationStatusActionInput,
  options: Readonly<{ callerClient: QuotationBusinessDraftRpcClient }>,
): Promise<Record<string, unknown>> {
  const response = await options.callerClient.rpc(
    "get_website_agreement_registration_status_v1",
    {
      p_quote_request_id: input.quote_request_id,
      p_project_id: input.project_id,
    },
  );
  if (response.error) throw new Error(response.error.message);
  return validateWebsiteAgreementRegistrationStatusResult(response.data, input);
}

export async function executeWebsiteCommercialDocumentStatusAction(
  input: WebsiteCommercialDocumentStatusActionInput,
  options: Readonly<{ callerClient: QuotationBusinessDraftRpcClient }>,
): Promise<Record<string, unknown>> {
  const response = await options.callerClient.rpc(
    "get_website_commercial_document_status_v1",
    {
      p_quote_request_id: input.quote_request_id,
      p_project_id: input.project_id,
    },
  );
  if (response.error) throw new Error(response.error.message);
  return validateWebsiteCommercialDocumentStatusResult(response.data, input);
}

type SdfQuotationIssuanceRuntimeOptions = Pick<
  QuotationRuntimeOptions,
  "serviceClient" | "templateBytes" | "renderDocx"
>;

export async function executeSdfApprovedQuotationIssuanceAction(
  actorAuthUserId: string,
  input: SdfQuotationIssuanceActionInput,
  options: SdfQuotationIssuanceRuntimeOptions,
): Promise<unknown> {
  return await orchestrateApprovedQuotation(
    { actorAuthUserId, quoteRequestId: input.quote_request_id },
    createQuotationRuntimeDependencies({
      actorAuthUserId,
      ...options,
      route: "SDF",
      sdfAuthority: {
        businessDraftId: input.business_draft_id,
        approvalId: input.approval_id,
        approvalVersion: input.approval_version,
        approvalSha256: input.approval_sha256,
        generationContractVersion: input.generation_contract_version,
      },
    }),
  );
}

export async function executeSdfQuotationDeliveryPreparationAction(
  input: SdfQuotationDeliveryPreparationActionInput,
  client: QuotationBusinessDraftRpcClient,
): Promise<unknown> {
  return await prepareSdfQuotationDelivery({
    businessDraftId: input.business_draft_id,
    approvalId: input.approval_id,
    approvalVersion: input.approval_version,
    approvalSha256: input.approval_sha256,
    issuanceId: input.issuance_id,
    artifactId: input.artifact_id,
    artifactSha256: input.artifact_sha256,
    artifactBytes: input.artifact_bytes,
  }, { client });
}

export async function executeSdfQuotationDeliverySendAction(
  input: SdfQuotationDeliverySendActionInput,
  authorityClient: SupabaseClient,
  transportClient: SupabaseClient,
  email: Readonly<{ from: string; resendApiKey: string }>,
): Promise<unknown> {
  return await sendPreparedSdfQuotationDelivery({
    authorityClient,
    transportClient,
    authority: {
      businessDraftId: input.business_draft_id,
      approvalId: input.approval_id,
      approvalVersion: input.approval_version,
      approvalSha256: input.approval_sha256,
      issuanceId: input.issuance_id,
      artifactId: input.artifact_id,
      artifactSha256: input.artifact_sha256,
      artifactBytes: input.artifact_bytes,
    },
    ...email,
  });
}

export async function executeQuotationBusinessDraftAction(
  actorAuthUserId: string,
  input: QuotationBusinessDraftActionInput,
  client: QuotationBusinessDraftRpcClient,
): Promise<unknown> {
  const { data, error } = await client.rpc(
    "upsert_quotation_business_draft_v2",
    {
      p_actor_auth_user_id: actorAuthUserId,
      p_intake_id: input.intake_id,
      p_expected_revision: input.expected_revision,
      p_idempotency_key: input.idempotency_key,
      p_input: input.input,
    },
  );
  if (error) throw new Error(error.message);
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("INVALID_QUOTATION_BUSINESS_DRAFT_RESPONSE");
  }
  const result = data as Record<string, unknown>;
  if (
    !UUID.test(String(result.approval_draft_id || "")) ||
    !Number.isSafeInteger(result.business_revision) ||
    Number(result.business_revision) < 1 ||
    !result.canonical_payload || typeof result.canonical_payload !== "object" ||
    Array.isArray(result.canonical_payload) ||
    typeof result.prepared_at !== "string" ||
    typeof result.replayed !== "boolean"
  ) {
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

const quotationBusinessApprovalPromotionDefaults:
  QuotationBusinessApprovalPromotionOptions = {
    createApprovalId: () => crypto.randomUUID(),
    getEnv: (name: string) => Deno.env.get(name),
  };

function promotionConfigurationError(): Error {
  return new Error("SERVER_CONFIGURATION_ERROR");
}

function promotionIntegritySecret(
  keyId: string,
  options: QuotationBusinessApprovalPromotionOptions,
): string {
  if (!/^v[1-9][0-9]*$/.test(keyId)) throw promotionConfigurationError();
  const secret = options.getEnv(
    `QUOTATION_APPROVAL_INTEGRITY_KEY_${keyId.toUpperCase()}`,
  );
  if (!secret || new TextEncoder().encode(secret).byteLength < 32) {
    throw promotionConfigurationError();
  }
  return secret;
}

function requiredPromotionContext(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("APPROVAL_CONFLICT");
  }
  const context = value as Record<string, unknown>;
  if (
    !new Set(["CREATE", "ADOPT"]).has(String(context.mode)) ||
    !UUID.test(String(context.business_draft_id || "")) ||
    !Number.isSafeInteger(context.business_revision) ||
    Number(context.business_revision) < 1 ||
    !UUID.test(String(context.approval_draft_id || "")) ||
    !UUID.test(String(context.quote_request_id || "")) ||
    !UUID.test(String(context.intake_id || "")) ||
    !UUID.test(String(context.pricing_snapshot_id || "")) ||
    context.contract_version !== 1 ||
    !/^[0-9a-f]{64}$/.test(String(context.payload_sha256 || ""))
  ) {
    throw new Error("APPROVAL_CONFLICT");
  }
  return context;
}

function promotionRoot(
  context: Record<string, unknown>,
  approvalId: string,
): QuotationApprovalIntegrityRoot {
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
    "approvalId",
    "contractVersion",
    "intakeId",
    "integrityRootVersion",
    "payloadSha256",
    "pricingSnapshotId",
    "quoteRequestId",
  ];
  return Object.keys(root).length === keys.length &&
    keys.every((key) => key in root) &&
    typeof root.approvalId === "string" &&
    root.approvalId === expected.approvalId &&
    typeof root.contractVersion === "number" &&
    root.contractVersion === expected.contractVersion &&
    typeof root.intakeId === "string" && root.intakeId === expected.intakeId &&
    typeof root.integrityRootVersion === "number" &&
    root.integrityRootVersion === expected.integrityRootVersion &&
    typeof root.payloadSha256 === "string" &&
    root.payloadSha256 === expected.payloadSha256 &&
    typeof root.pricingSnapshotId === "string" &&
    root.pricingSnapshotId === expected.pricingSnapshotId &&
    typeof root.quoteRequestId === "string" &&
    root.quoteRequestId === expected.quoteRequestId;
}

function promotionResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("APPROVAL_CONFLICT");
  }
  const result = value as Record<string, unknown>;
  if (
    !UUID.test(String(result.business_draft_id || "")) ||
    !Number.isSafeInteger(result.business_revision) ||
    Number(result.business_revision) < 1 ||
    !UUID.test(String(result.approval_id || "")) ||
    !Number.isSafeInteger(result.approval_version) ||
    Number(result.approval_version) < 1 ||
    result.status !== "APPROVED" || typeof result.approved_at !== "string" ||
    typeof result.was_created !== "boolean"
  ) {
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
  options: QuotationBusinessApprovalPromotionOptions =
    quotationBusinessApprovalPromotionDefaults,
): Promise<unknown> {
  const resolved = await client.rpc(
    "resolve_quotation_business_approval_promotion_context_v1",
    {
      p_actor_auth_user_id: actorAuthUserId,
      p_intake_id: input.intake_id,
      p_expected_revision: input.expected_revision,
    },
  );
  if (resolved.error) throw new Error(resolved.error.message);
  const context = requiredPromotionContext(resolved.data);

  let approvalId: string;
  let integrity: QuotationApprovalIntegrity;
  if (context.mode === "CREATE") {
    approvalId = options.createApprovalId();
    if (!UUID.test(approvalId)) throw promotionConfigurationError();
    const keyId =
      options.getEnv("QUOTATION_APPROVAL_INTEGRITY_ACTIVE_KEY_ID") || "v1";
    try {
      integrity = await createQuotationApprovalIntegrity(
        promotionRoot(context, approvalId),
        keyId,
        promotionIntegritySecret(keyId, options),
      );
    } catch {
      throw promotionConfigurationError();
    }
  } else {
    approvalId = String(context.approval_id || "");
    const candidate = context.integrity;
    if (
      !UUID.test(approvalId) || !candidate || typeof candidate !== "object" ||
      Array.isArray(candidate)
    ) {
      throw new Error("APPROVAL_CONFLICT");
    }
    integrity = candidate as QuotationApprovalIntegrity;
    if (
      integrity.algorithmVersion !== QUOTATION_APPROVAL_INTEGRITY_VERSION ||
      !/^v[1-9][0-9]*$/.test(String(integrity.keyId || "")) ||
      !/^[0-9a-f]{64}$/.test(String(integrity.mac || "")) ||
      !isExactPromotionRoot(integrity.root, promotionRoot(context, approvalId))
    ) {
      throw new Error("APPROVAL_CONFLICT");
    }
    if (
      !await verifyQuotationApprovalIntegrity(
        integrity,
        promotionIntegritySecret(integrity.keyId, options),
      )
    ) throw new Error("APPROVAL_CONFLICT");
  }

  const promoted = await client.rpc(
    "promote_quotation_business_draft_to_approval_v1",
    {
      p_actor_auth_user_id: actorAuthUserId,
      p_intake_id: input.intake_id,
      p_expected_revision: input.expected_revision,
      p_idempotency_key: input.idempotency_key,
      p_approval_id: approvalId,
      p_integrity: integrity,
    },
  );
  if (promoted.error) throw new Error(promoted.error.message);
  return promotionResult(promoted.data);
}

export async function executeCallerJwtCustomerRequestAction(
  jwt: string,
  input: CustomerRequestActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  return await executeCustomerRequestTransport(clientFor(jwt), input);
}

export async function executeCallerJwtCustomerRequestSmokeFixtureAction(
  jwt: string,
  idempotencyKey: string,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  const { data, error } = await clientFor(jwt).rpc(
    "create_customer_request_smoke_fixture_v1",
    {
      p_idempotency_key: idempotencyKey,
    },
  );
  if (error) throw new Error(error.message);
  return data;
}

export async function executeCallerJwtCustomerRequestUploadAction(
  jwt: string,
  input: CustomerRequestUploadOperatorActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
): Promise<unknown> {
  const client = clientFor(jwt);
  if (input.action === "revoke_customer_request_upload_link") {
    const { data, error } = await client.rpc(
      "revoke_customer_request_upload_request_v1",
      {
        p_upload_request_id: input.upload_request_id,
        p_reason: input.reason,
        p_idempotency_key: input.idempotency_key,
      },
    );
    if (error) throw new Error(error.message);
    return data;
  }
  const token = await deriveCustomerRequestUploadCapabilityToken(
    input.request_id,
    input.idempotency_key,
  );
  const tokenDigest = await hashCustomerRequestUploadCapabilityToken(token);
  const { data, error } = await client.rpc(
    "create_customer_request_upload_request_v1",
    {
      p_request_id: input.request_id,
      p_token_digest: tokenDigest,
      p_requested_expires_at: null,
      p_idempotency_key: input.idempotency_key,
    },
  );
  if (
    error || !data || typeof data !== "object" || Array.isArray(data) ||
    (data as Record<string, unknown>).state !== "ACTIVE"
  ) {
    throw new Error(error?.message || "INVALID_UPLOAD_REQUEST_RESPONSE");
  }
  return {
    ...(data as Record<string, unknown>),
    upload_url: buildCustomerRequestUploadUrl(token),
  };
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function customerRequestUploadPromotionResult(
  value: unknown,
  uploadedFileId: string,
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_PROMOTION_RESPONSE");
  }
  const result = value as Record<string, unknown>;
  if (
    result.state !== "PROMOTED" ||
    result.uploaded_file_id !== uploadedFileId ||
    !UUID.test(String(result.document_inbox_item_id || "")) ||
    !["RECEIVED", "REVIEW_REQUIRED", "APPROVED", "PROCESSED", "REJECTED"]
      .includes(String(result.status || "")) ||
    typeof result.replayed !== "boolean"
  ) {
    throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_PROMOTION_RESPONSE");
  }
  return {
    uploaded_file_id: result.uploaded_file_id,
    document_inbox_item_id: result.document_inbox_item_id,
    status: result.status,
    replayed: result.replayed,
  };
}

export async function executeCustomerRequestUploadInboxPromotionAction(
  jwt: string,
  input: CustomerRequestUploadInboxPromotionActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
  serviceClient: () => CustomerRequestUploadPromotionServiceClient,
): Promise<unknown> {
  const callerClient = clientFor(jwt);
  const authorization = await callerClient.rpc(
    "authorize_customer_request_upload_inbox_promotion_v1",
    { p_uploaded_file_id: input.uploaded_file_id },
  );
  if (authorization.error) throw new Error(authorization.error.message);
  if (
    !authorization.data || typeof authorization.data !== "object" ||
    Array.isArray(authorization.data)
  ) {
    throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_PROMOTION_RESPONSE");
  }
  const authorized = authorization.data as Record<string, unknown>;
  if (authorized.state === "PROMOTED") {
    return customerRequestUploadPromotionResult(
      authorized,
      input.uploaded_file_id,
    );
  }

  const sourceBucket = String(authorized.source_bucket_id || "");
  const sourcePath = String(authorized.source_object_path || "");
  const destinationBucket = String(authorized.destination_bucket_id || "");
  const destinationPath = String(authorized.destination_object_path || "");
  const mimeType = String(authorized.mime_type || "");
  const expectedSha256 = String(authorized.sha256 || "");
  const expectedByteCount = Number(authorized.byte_count);
  if (
    authorized.state !== "AUTHORIZED" ||
    authorized.uploaded_file_id !== input.uploaded_file_id ||
    !UUID.test(String(authorized.customer_request_id || "")) ||
    !UUID.test(String(authorized.quote_request_id || "")) ||
    sourceBucket !== "customer-request-quarantine" ||
    destinationBucket !== "supplier-documents" ||
    !sourcePath || !destinationPath ||
    !["application/pdf", "image/png", "image/jpeg"].includes(mimeType) ||
    !/^[0-9a-f]{64}$/.test(expectedSha256) ||
    !Number.isSafeInteger(expectedByteCount) || expectedByteCount < 1 ||
    expectedByteCount > 8_388_608
  ) {
    throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_PROMOTION_RESPONSE");
  }

  const service = serviceClient();
  const source = await service.storage.from(sourceBucket).download(sourcePath);
  if (source.error || !source.data) {
    throw new Error("CUSTOMER_REQUEST_UPLOAD_SOURCE_OBJECT_NOT_FOUND");
  }
  const bytes = new Uint8Array(await source.data.arrayBuffer());
  if (
    bytes.byteLength !== expectedByteCount ||
    (source.data.type && source.data.type !== mimeType) ||
    await sha256Hex(bytes) !== expectedSha256
  ) {
    throw new Error("CUSTOMER_REQUEST_UPLOAD_SOURCE_CONTENT_MISMATCH");
  }

  const uploaded = await service.storage.from(destinationBucket).upload(
    destinationPath,
    bytes,
    { contentType: mimeType, upsert: false },
  );
  if (uploaded.error) {
    const existing = await service.storage.from(destinationBucket).download(
      destinationPath,
    );
    if (existing.error || !existing.data) {
      throw new Error("CUSTOMER_REQUEST_UPLOAD_STORAGE_BRIDGE_FAILED");
    }
    const existingBytes = new Uint8Array(await existing.data.arrayBuffer());
    if (
      existingBytes.byteLength !== expectedByteCount ||
      (existing.data.type && existing.data.type !== mimeType) ||
      await sha256Hex(existingBytes) !== expectedSha256
    ) {
      throw new Error("CUSTOMER_REQUEST_UPLOAD_STORAGE_BRIDGE_FAILED");
    }
  }

  const metadata = await service.rpc(
    "finalize_supplier_document_upload_object_v1",
    {
      p_storage_object_path: destinationPath,
      p_sha256: expectedSha256,
      p_mime_type: mimeType,
      p_byte_count: expectedByteCount,
    },
  );
  if (metadata.error || metadata.data !== true) {
    throw new Error("CUSTOMER_REQUEST_UPLOAD_STORAGE_BRIDGE_FAILED");
  }

  const finalized = await callerClient.rpc(
    "finalize_customer_request_upload_inbox_promotion_v1",
    { p_uploaded_file_id: input.uploaded_file_id },
  );
  if (finalized.error) throw new Error(finalized.error.message);
  return customerRequestUploadPromotionResult(
    finalized.data,
    input.uploaded_file_id,
  );
}

type InternalE2ECleanupStorageClient = Readonly<{
  storage: Readonly<{
    from(bucket: string): Readonly<{
      remove(paths: string[]): PromiseLike<
        Readonly<{
          data: unknown;
          error: Readonly<{ message: string }> | null;
        }>
      >;
    }>;
  }>;
}>;

export async function executeCallerJwtInternalE2EAcceptedFileCleanupAction(
  jwt: string,
  input: InternalE2EAcceptedFileCleanupActionInput,
  clientFor: (jwt: string) => DossierAssignmentClient,
  serviceClient: () => InternalE2ECleanupStorageClient,
): Promise<unknown> {
  const client = clientFor(jwt);
  const authorization = await client.rpc(
    "authorize_internal_e2e_accepted_file_cleanup_v1",
    {
      p_run_id: input.run_id,
      p_request_id: input.request_id,
      p_upload_request_id: input.upload_request_id,
      p_uploaded_file_id: input.uploaded_file_id,
      p_idempotency_key: input.idempotency_key,
    },
  );
  if (
    authorization.error || !authorization.data ||
    typeof authorization.data !== "object" || Array.isArray(authorization.data)
  ) {
    throw new Error(
      authorization.error?.message ||
        "INVALID_INTERNAL_E2E_CLEANUP_AUTHORIZATION_RESPONSE",
    );
  }
  const authorized = authorization.data as Record<string, unknown>;
  const cleanupAuthorizationId = String(
    authorized.cleanup_authorization_id || "",
  );
  const bucket = String(authorized.storage_bucket_id || "");
  const path = String(authorized.storage_object_path || "");
  const expectedPath = new RegExp(
    `^requests/${input.request_id}/uploads/${input.upload_request_id}/files/${input.uploaded_file_id}\\.(?:pdf|png|jpg|jpeg)$`,
  );
  if (
    authorized.state !== "AUTHORIZED" || !UUID.test(cleanupAuthorizationId) ||
    bucket !== "customer-request-quarantine" || !expectedPath.test(path)
  ) {
    throw new Error("INVALID_INTERNAL_E2E_CLEANUP_AUTHORIZATION_RESPONSE");
  }

  const removal = await serviceClient().storage.from(bucket).remove([path]);
  if (removal.error) throw new Error(removal.error.message);

  const finalization = await client.rpc(
    "finalize_internal_e2e_accepted_file_cleanup_v1",
    {
      p_cleanup_authorization_id: cleanupAuthorizationId,
      p_idempotency_key: input.idempotency_key,
    },
  );
  if (finalization.error) throw new Error(finalization.error.message);
  return finalization.data;
}

export function normalizePendingSeenStateItems(
  data: unknown,
): Record<string, unknown>[] | null {
  const items = (data as { items?: unknown[] } | null)?.items;
  if (!Array.isArray(items)) return null;
  return items.map((value) => ({ ...value as Record<string, unknown> }));
}

export function normalizeWebsitePendingItems(
  data: unknown,
): Record<string, unknown>[] | null {
  const items = normalizePendingSeenStateItems(data);
  if (!items) return null;
  return items.map((value) => {
    return {
      ...value,
      sdf_package: null,
      invitation_delivery_status: null,
      last_activity_at: value.invitation_created_at,
    };
  });
}

if (import.meta.main) {
  Deno.serve((request) =>
    withCommercialOperatorCors(request, () => {
      const url = Deno.env.get("SUPABASE_URL");
      const configurationError = () =>
        new Response(
          JSON.stringify({
            ok: false,
            code: "SERVER_CONFIGURATION_ERROR",
          }),
          {
            status: 500,
            headers: {
              "Content-Type": "application/json",
              "Cache-Control": "no-store",
            },
          },
        );
      if (!url) return configurationError();
      let publishableKey: ReturnType<typeof getSupabasePublishableKey>;
      try {
        publishableKey = getSupabasePublishableKey("default");
      } catch {
        return configurationError();
      }
      const clientFor = (jwt: string) =>
        createClient(url, publishableKey, {
          global: {
            headers: {
              Authorization: `Bearer ${jwt}`,
            },
          },
          auth: {
            persistSession: false,
            autoRefreshToken: false,
          },
        });
      const serviceClient = () => {
        const serviceRoleKey = getSupabaseServerSecretKey("default");
        return createClient(url, serviceRoleKey, {
          auth: { persistSession: false, autoRefreshToken: false },
        });
      };
      const cursorRequest = (
        input: OperatorApplicationCursorInput,
      ): OperatorCursorRequest => ({
        zone: input.zone,
        operationalStatus: input.operational_status,
        year: input.year ?? null,
        quarter: input.quarter ?? null,
        requestKind: input.request_kind,
        search: input.search,
      });
      return handleCommercialOperator(request, {
        now: () => Date.now(),
        verifyUser: async (jwt: string) =>
          await verifySupabaseAuthUser(clientFor(jwt), jwt),
        authorizeApplicationReader: async (jwt: string) => {
          const { error } = await clientFor(jwt).rpc(
            "authorize_operator_application_reader_v2",
          );
          if (error) throw new Error(error.message);
        },
        verifyOperatorCursor: async (
          cursor: string,
          input: OperatorApplicationListV2Input,
        ) => await verifyOperatorCursor(cursor, cursorRequest(input)),
        signOperatorCursor: async (
          position: OperatorCursorDatabasePosition,
          input: OperatorApplicationListV2Input,
        ) =>
          await signOperatorCursor({
            dossierDate: position.dossier_date,
            quoteRequestId: position.quote_request_id,
          }, cursorRequest(input)),
        executeApplicationListV2: async (
          jwt: string,
          actorAuthUserId: string,
          input: OperatorApplicationListV2Input,
          position: OperatorCursorPosition | null,
        ) => {
          const { data, error } = await clientFor(jwt).rpc(
            "list_operator_applications_v2",
            {
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
            },
          );
          if (error) throw new Error(error.message);
          return data;
        },
        executePendingIntakes: async (
          jwt: string,
          actorAuthUserId: string,
          retentionState: string,
        ) => {
          const { data, error } = await clientFor(jwt).rpc(
            "list_operator_pending_intakes_v1",
            {
              p_actor_auth_user_id: actorAuthUserId,
              p_retention_state: retentionState,
            },
          );
          if (error) throw new Error(error.message);
          const websiteItems = normalizeWebsitePendingItems(data);
          if (!websiteItems) {
            throw new Error("INVALID_PENDING_INTAKES_RESPONSE");
          }
          if (retentionState !== "ACTIVE") return { items: websiteItems };
          const sdf = await clientFor(jwt).rpc("list_operator_pending_sdf_intakes_v1",
            { p_actor_auth_user_id: actorAuthUserId },
          );
          if (sdf.error) throw new Error(sdf.error.message);
          const sdfItems = normalizePendingSeenStateItems(sdf.data);
          if (!sdfItems) throw new Error("INVALID_PENDING_INTAKES_RESPONSE");
          return {
            items: [...websiteItems, ...sdfItems].sort((left, right) =>
              String((right as Record<string, unknown>).last_activity_at)
                .localeCompare(
                  String((left as Record<string, unknown>).last_activity_at),
                )
            ),
          };
        },
        executePendingIntakeCount: async (
          jwt: string,
          actorAuthUserId: string,
        ) => {
          const { data, error } = await clientFor(jwt).rpc(
            "count_operator_active_pending_intakes_v1",
            { p_actor_auth_user_id: actorAuthUserId },
          );
          if (error) throw new Error(error.message);
          const sdf = await clientFor(jwt).rpc("list_operator_pending_sdf_intakes_v1",
            { p_actor_auth_user_id: actorAuthUserId },
          );
          if (sdf.error) throw new Error(sdf.error.message);
          const sdfItems = (sdf.data as { items?: unknown[] } | null)?.items;
          if (
            !Array.isArray(sdfItems) ||
            typeof (data as { active_count?: unknown } | null)?.active_count !==
              "number"
          ) throw new Error("INVALID_PENDING_INTAKE_COUNT_RESPONSE");
          return {
            active_count:
              Number((data as { active_count: number }).active_count) +
              sdfItems.length,
          };
        },
        executeDossierSubstance: async (
          jwt: string,
          actorAuthUserId: string,
          quoteRequestId: string,
        ) => {
          const { data, error } = await clientFor(jwt).rpc(
            "get_operator_dossier_substance_v1",
            {
              p_actor_auth_user_id: actorAuthUserId,
              p_quote_request_id: quoteRequestId,
            },
          );
          if (error) throw new Error(error.message);
          return data;
        },
        executeMarkDossierSeen: async (
          jwt: string,
          actorAuthUserId: string,
          quoteRequestId: string,
        ) => {
          const { data, error } = await clientFor(jwt).rpc(
            "mark_operator_dossier_seen_v1",
            {
              p_actor_auth_user_id: actorAuthUserId,
              p_quote_request_id: quoteRequestId,
            },
          );
          if (error) throw new Error(error.message);
          return data;
        },
        executeApplicationFacetsV2: async (
          jwt: string,
          actorAuthUserId: string,
          input: OperatorApplicationFacetsV2Input,
        ) => {
          const { data, error } = await clientFor(jwt).rpc(
            "get_operator_dossier_facets_v2",
            {
              p_actor_auth_user_id: actorAuthUserId,
              p_zone: input.zone,
              p_operational_status: input.operational_status,
              p_request_kind: input.request_kind,
              p_search: input.search,
            },
          );
          if (error) throw new Error(error.message);
          return data;
        },
        executeWebsiteProjectDirectoryList: async (
          jwt: string,
          input: WebsiteProjectDirectoryActionInput,
        ) =>
          await executeCallerJwtWebsiteProjectFilesAction(jwt, input, {
            clientFor,
            createService: createWebsiteProjectFilesRuntimeService,
          }),
        executeWebsiteProjectFileRead: async (
          jwt: string,
          input: WebsiteProjectFileActionInput,
        ) =>
          await executeCallerJwtWebsiteProjectFilesAction(jwt, input, {
            clientFor,
            createService: createWebsiteProjectFilesRuntimeService,
          }),
        executeWebsiteProjectFileSave: async (
          jwt: string,
          input: WebsiteProjectFileSaveActionInput,
        ) =>
          await executeCallerJwtWebsiteProjectFilesAction(jwt, input, {
            clientFor,
            createService: createWebsiteProjectFilesRuntimeService,
          }),
        executeWebsiteProjectPreviewBuild: async (
          jwt: string,
          input: WebsiteProjectPreviewBuildActionInput,
        ) =>
          await executeCallerJwtWebsiteProjectPreviewBuildAction(jwt, input, {
            clientFor,
            createService: async (signal) =>
              await createWebsiteProjectPreviewRuntimeService(
                signal,
                serviceClient(),
              ),
          }),
        executeWebsiteProjectPreviewControl: async (
          jwt: string,
          input: WebsiteProjectPreviewControlActionInput,
        ) =>
          await executeCallerJwtWebsiteProjectPreviewControlAction(jwt, input, {
            clientFor,
            previewHostUrl: Deno.env.get("LWS_PREVIEW_HOST_URL"),
          }),
        consumeRateLimit: async (jwt: string, projectId: string) => {
          const { data, error } = await clientFor(jwt).rpc(
            "consume_commercial_operator_rate_limit_v1",
            {
              p_project_id: projectId,
              p_max_requests: 60,
              p_window_seconds: 60,
            },
          );
          if (error) throw new Error(error.message);
          return normalizeCommercialOperatorRateLimitResult(data);
        },
        executeApplicationAction: async (
          jwt: string,
          input: ValidatedApplicationActionInput,
          actorAuthUserId: string,
        ) => {
          if (
            [
              "get_website_requirements_board",
              "sync_website_requirements_from_intake",
              "start_website_requirement",
              "block_website_requirement",
              "complete_website_requirement",
              "reopen_website_requirement",
              "accept_website_requirement_source_change",
              "keep_existing_website_requirement_source",
              "retire_website_requirement_source",
            ].includes(input.action)
          ) {
            return await executeCallerJwtWebsiteRequirementsAction(
              jwt,
              input as WebsiteRequirementsActionInput,
              clientFor,
            );
          }
          if (input.action === "get_current_operator_identity") {
            return await executeCallerJwtCurrentOperatorIdentityAction(
              jwt,
              clientFor,
            );
          }
          if (input.action === "list_pending_sdf_qualification_intakes") {
            const { data, error } = await clientFor(jwt).rpc("list_operator_pending_sdf_intakes_v1",
              { p_actor_auth_user_id: actorAuthUserId },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (
            input.action === "allow_sdf_qualification_intake" ||
            input.action === "reissue_sdf_qualification_intake"
          ) {
            const rawToken = createRawIntakeToken();
            const digest = await hashIntakeToken(rawToken);
            const encrypted = await encryptIntakeInvitationToken(
              rawToken,
              digest,
            );
            const rpcName = input.action === "allow_sdf_qualification_intake"
              ? "allow_sdf_qualification_intake_v1"
              : "reissue_sdf_qualification_intake_v1";
            const { data, error } = await clientFor(jwt).rpc(rpcName, {
              p_quote_request_id: input.quote_request_id,
              p_customer_capability_digest: digest,
              p_encrypted_capability: encrypted,
              p_idempotency_key: input.idempotency_key,
            });
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "inspect_sdf_qualification_intake") {
            const { data, error } = await clientFor(jwt).rpc(
              "inspect_sdf_qualification_intake_for_operator_v1",
              { p_quote_request_id: input.quote_request_id },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "transition_sdf_qualification_intake") {
            const { data, error } = await clientFor(jwt).rpc(
              "transition_sdf_qualification_intake_v1",
              {
                p_quote_request_id: input.quote_request_id,
                p_action: input.transition,
                p_reason: input.reason,
                p_idempotency_key: input.idempotency_key,
                p_encrypted_capability: null,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "authorize_sdf_quotation_preparation_v1") {
            const { data, error } = await clientFor(jwt).rpc(
              "authorize_sdf_quotation_preparation_v1",
              {
                p_quote_request_id: input.quote_request_id,
                p_idempotency_key: input.idempotency_key,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "prepare_sdf_m1_invoice") {
            return await executeCallerJwtSdfM1InvoicePreparationAction(
              jwt,
              input as SdfM1InvoicePreparationActionInput,
              clientFor,
            );
          }
          if (
            input.action === "create_website_delivery_pdf_c3_trial_fixture" ||
            input.action === "close_website_delivery_pdf_c3_trial_fixture"
          ) {
            return await executeWebsiteDeliveryPdfC3TrialTransport(
              clientFor(jwt),
              input as WebsiteDeliveryPdfC3TrialActionInput,
            );
          }
          if (input.action === "get_assignment_operator_roster") {
            return await executeCallerJwtAssignmentRosterAction(jwt, clientFor);
          }
          if (input.action === "list_workforce_calendar") {
            return await executeCallerJwtWorkforceCalendarAction(
              jwt,
              input as WorkforceCalendarActionInput,
              clientFor,
            );
          }
          if (
            [
              "list_recruitment_vacancies",
              "create_recruitment_vacancy",
              "update_recruitment_vacancy",
              "set_recruitment_vacancy_status",
              "get_recruitment_publication_state",
              "set_recruitment_publication_enabled",
            ].includes(input.action)
          ) {
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
              serviceClient(),
            );
          }
          if (input.action === "promote_quotation_business_draft_to_approval") {
            return await executeQuotationBusinessApprovalPromotionAction(
              actorAuthUserId,
              input as QuotationBusinessApprovalPromotionActionInput,
              serviceClient(),
            );
          }
          if (input.action === "issue_and_deliver_approved_quotation") {
            const from = Deno.env.get("FROM_EMAIL") || "";
            const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
            if (!from || !resendApiKey) {
              throw new Error("SERVER_CONFIGURATION_ERROR");
            }
            const quotationClient = serviceClient();
            const templateBytes = await Deno.readFile(
              new URL(
                "./assets/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx",
                import.meta.url,
              ),
            );
            const officialTemplateBytes = await Deno.readFile(
              new URL(
                "./assets/LWS_WEBSITE_QUOTATION_NL_BE_OFFICIAL_v1.docx",
                import.meta.url,
              ),
            );
            return await executeApprovedQuotationIssuanceAction(
              actorAuthUserId,
              input as QuotationIssuanceActionInput,
              {
                serviceClient: quotationClient,
                templateBytes,
                renderDocx: renderQuotationDocxBytes,
                additionalTemplates: [{
                  templateBytes: officialTemplateBytes,
                  renderDocx: renderWebsiteQuotationDocxBytes,
                }],
                deliver: (deliveryInput) =>
                  deliverIssuedQuotation({
                    supabase: quotationClient,
                    ...deliveryInput,
                  }),
                email: { from, resendApiKey },
              },
            );
          }
          if (input.action === "prepare_website_agreement_concept") {
            const agreementTemplateBytes = await Deno.readFile(
              new URL(
                "./assets/LWS_WEBSITE_AGREEMENT_NL_BE_CONCEPT_v1.docx",
                import.meta.url,
              ),
            );
            return await executeWebsiteAgreementConceptAction(
              input as WebsiteAgreementConceptActionInput,
              {
                callerClient: clientFor(jwt),
                serviceClient: serviceClient(),
                templateBytes: agreementTemplateBytes,
                renderDocx: renderWebsiteAgreementConceptDocxBytes,
              },
            );
          }
          if (input.action === "prepare_website_delivery_document") {
            const deliveryTemplateBytes = await Deno.readFile(
              new URL(
                "./assets/LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v2.docx",
                import.meta.url,
              ),
            );
            const deliveryServiceClient = serviceClient();
            return await executeWebsiteDeliveryDocumentAction(
              actorAuthUserId,
              input as WebsiteDeliveryDocumentActionInput,
              {
                callerClient: clientFor(jwt),
                serviceClient: deliveryServiceClient,
                templateBytes: deliveryTemplateBytes,
                renderDocx: renderWebsiteDeliveryDocumentDocxBytes,
                startPdfConversion: (binding) =>
                  startWebsiteDeliveryPdfConversion(
                    binding,
                    deliveryServiceClient,
                  ),
              },
            );
          }
          if (
            input.action === "get_website_delivery_pdf_status" ||
            input.action === "approve_website_delivery_pdf_rerun"
          ) {
            return await executeWebsiteDeliveryPdfRecoveryAction(
              actorAuthUserId,
              input as WebsiteDeliveryPdfStatusActionInput |
                WebsiteDeliveryPdfRerunActionInput,
              {
                callerClient: clientFor(jwt),
                serviceClient: serviceClient(),
                createStarter: (taskId, actor, client) =>
                  createWebsiteDeliveryPdfRuntimeStarter(taskId, actor, client),
              },
            );
          }
          if (input.action === "view_website_delivery_document") {
            return await executeWebsiteDeliveryDocumentViewAction(
              actorAuthUserId,
              input as WebsiteDeliveryDocumentViewActionInput,
              {
                callerClient: clientFor(jwt),
                serviceClient: serviceClient(),
              },
            );
          }
          if (input.action in WEBSITE_INVOICE_ACTION_AUTHORITIES) {
            const invoiceInput = input as WebsiteInvoiceConceptActionInput;
            const authority =
              WEBSITE_INVOICE_ACTION_AUTHORITIES[invoiceInput.action];
            const invoiceTemplateBytes = await Deno.readFile(
              new URL(`./assets/${authority.filename}`, import.meta.url),
            );
            return await executeWebsiteInvoiceConceptAction(
              invoiceInput,
              {
                callerClient: clientFor(jwt),
                serviceClient: serviceClient(),
                templateBytes: invoiceTemplateBytes,
                renderDocx: renderWebsiteCommercialConceptDocxBytes,
              },
            );
          }
          if (input.action === "get_website_agreement_registration_status") {
            return await executeWebsiteAgreementRegistrationStatusAction(
              input as WebsiteAgreementRegistrationStatusActionInput,
              { callerClient: clientFor(jwt) },
            );
          }
          if (input.action === "get_website_commercial_document_status") {
            return await executeWebsiteCommercialDocumentStatusAction(
              input as WebsiteCommercialDocumentStatusActionInput,
              { callerClient: clientFor(jwt) },
            );
          }
          if (input.action === "issue_sdf_approved_quotation") {
            const quotationClient = serviceClient();
            const templateBytes = await Deno.readFile(
              new URL(
                "./assets/LWS_SDF_QUOTATION_NL_BE_OFFICIAL_v1.docx",
                import.meta.url,
              ),
            );
            return await executeSdfApprovedQuotationIssuanceAction(
              actorAuthUserId,
              input as SdfQuotationIssuanceActionInput,
              {
                serviceClient: quotationClient,
                templateBytes,
                renderDocx: renderSdfQuotationDocxBytes,
              },
            );
          }
          if (input.action === "prepare_sdf_quotation_delivery") {
            return await executeSdfQuotationDeliveryPreparationAction(
              input as SdfQuotationDeliveryPreparationActionInput,
              clientFor(jwt),
            );
          }
          if (input.action === "send_sdf_quotation_delivery") {
            const from = Deno.env.get("FROM_EMAIL") || "";
            const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
            if (!from || !resendApiKey) {
              throw new Error("SERVER_CONFIGURATION_ERROR");
            }
            return await executeSdfQuotationDeliverySendAction(
              input as SdfQuotationDeliverySendActionInput,
              clientFor(jwt),
              serviceClient(),
              { from, resendApiKey },
            );
          }
          if (input.action === "get_my_assigned_dossiers") {
            return await executeCallerJwtOperatorPersonalQueueAction(jwt, {
              action: "get_my_assigned_dossiers",
              cursor: input.cursor,
              limit: input.limit,
            }, clientFor);
          }
          if (input.action === "get_dossier_document_manifest") {
            return await executeCallerJwtDossierDocumentManifestAction(
              jwt,
              input as Extract<
                DossierDocumentActionInput,
                { action: "get_dossier_document_manifest" }
              >,
              clientFor,
            );
          }
          if (input.action === "create_dossier_document_access") {
            return await executeServiceRoleDossierDocumentAction(
              actorAuthUserId,
              input as unknown as Extract<
                DossierDocumentActionInput,
                { action: "create_dossier_document_access" }
              >,
              serviceClient(),
            );
          }
          if (
            [
              "create_sdf_customer_request",
              "list_customer_requests_for_dossier",
              "get_customer_request",
              "transition_customer_request",
            ].includes(input.action)
          ) {
            return await executeCallerJwtCustomerRequestAction(
              jwt,
              input as CustomerRequestActionInput,
              clientFor,
            );
          }
          if (
            input.action === "create_customer_request_upload_link" ||
            input.action === "revoke_customer_request_upload_link"
          ) {
            return await executeCallerJwtCustomerRequestUploadAction(
              jwt,
              input as CustomerRequestUploadOperatorActionInput,
              clientFor,
            );
          }
          if (
            input.action ===
              "promote_customer_request_upload_to_document_inbox"
          ) {
            return await executeCustomerRequestUploadInboxPromotionAction(
              jwt,
              input as CustomerRequestUploadInboxPromotionActionInput,
              clientFor,
              serviceClient,
            );
          }
          if (
            input.action === "get_dossier_assignment" ||
            input.action === "assign_dossier"
          ) {
            return await executeCallerJwtDossierAssignmentAction(
              jwt,
              input as DossierAssignmentActionInput,
              clientFor,
            );
          }
          if (input.action === "start_website_concept") {
            return await executeCallerJwtWebsiteConceptStartAction(
              jwt,
              input as WebsiteConceptStartActionInput,
              clientFor,
            );
          }
          if (input.action === "promote_website_concept") {
            return await executeCallerJwtWebsiteConceptPromotionAction(
              jwt,
              input as WebsiteConceptPromotionActionInput,
              clientFor,
            );
          }
          if (input.action === "record_website_project_preview_ready") {
            return await executeCallerJwtWebsiteProjectPreviewReadyAction(
              jwt,
              input as WebsiteProjectPreviewReadyActionInput,
              clientFor,
            );
          }
          if (input.action === "provision_website_execution_workspace") {
            return await executeCallerJwtWebsiteExecutionWorkspaceProvisionAction(
              jwt,
              input as WebsiteExecutionWorkspaceProvisionActionInput,
              clientFor,
            );
          }
          if (input.action === "provision_website_repository") {
            return await executeCallerJwtWebsiteRepositoryProvisionAction(
              jwt,
              input as WebsiteRepositoryProvisionActionInput,
              clientFor,
            );
          }
          if (input.action === "recover_existing_website_repository") {
            return await executeCallerJwtWebsiteRepositoryRecoveryAction(
              jwt,
              actorAuthUserId,
              input as WebsiteRepositoryRecoveryActionInput,
              clientFor,
              serviceClient,
            );
          }
          if (input.action === "get_website_quotation_pricing_state") {
            return await executeWebsiteQuotationPricingStateAction(
              actorAuthUserId,
              input as WebsiteQuotationPricingStateActionInput,
              clientFor(jwt),
            );
          }
          if (input.action === "get_website_quotation_approval_status") {
            return await executeWebsiteQuotationApprovalStatusAction(
              input as WebsiteQuotationApprovalStatusActionInput,
              { callerClient: clientFor(jwt) },
            );
          }
          if (input.action === "evaluate_quotation_vat_readiness") {
            return await executeCallerJwtQuotationVatReadinessAction(
              jwt,
              input as VatReadinessActionInput,
              clientFor,
            );
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
          if (
            [
              "interrupt_intake",
              "resume_intake",
              "cancel_intake",
              "reactivate_intake",
            ].includes(input.action)
          ) {
            const { data, error } = await client.rpc(
              "execute_operator_intake_lifecycle_command_v1",
              {
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
          if (isDossierLifecycleAction(input)) {
            return await executeDossierLifecycleTransport(
              (args) =>
                serviceClient().rpc(
                  "issue_operator_dossier_lifecycle_edge_capability_v1",
                  args,
                ),
              (args) =>
                client.rpc(
                  "execute_operator_dossier_lifecycle_command_v1",
                  args,
                ),
              actorAuthUserId,
              input,
            );
          }
          if (
            ["bind_project_site", "rotate_project_site"].includes(input.action)
          ) {
            const { data, error } = await client.rpc(
              "execute_operator_project_site_command_v1",
              {
                p_project_id: input.project_id,
                p_operation: input.operation,
                p_expected_revision: input.expected_revision,
                p_idempotency_key: input.idempotency_key,
                p_canonical_domain: input.canonical_domain,
                p_evidence: input.evidence,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "create_internal_e2e_run") {
            const approvalToken = await createApprovalTokenForIdempotencyKey(
              input.idempotency_key,
            );
            const intakeToken =
              await createInternalE2EIntakeTokenForIdempotencyKey(
                input.idempotency_key,
              );
            const intakeTokenHash = await hashIntakeToken(intakeToken);
            const adminToken = await deriveAdminIntakeCapability(
              intakeTokenHash,
            );
            const requestFingerprint = await sha256(JSON.stringify({
              contract_version: 1,
              run_label: input.run_label,
              ttl_minutes: input.ttl_minutes,
            }));
            const { data, error } = await client.rpc(
              "create_internal_e2e_run_v1",
              {
                p_idempotency_key: input.idempotency_key,
                p_request_fingerprint: requestFingerprint,
                p_run_label: input.run_label,
                p_ttl_minutes: input.ttl_minutes,
                p_approval_token_hash: await hashApprovalToken(approvalToken),
                p_intake_access_token_hash: intakeTokenHash,
                p_admin_access_token_hash: await hashAdminIntakeToken(
                  adminToken,
                ),
              },
            );
            if (error) throw new Error(error.message);
            return {
              ...data,
              intake_token: intakeToken,
              admin_intake_token: adminToken,
            };
          }
          if (input.action === "create_customer_request_smoke_fixture") {
            return await executeCallerJwtCustomerRequestSmokeFixtureAction(
              jwt,
              input.idempotency_key,
              clientFor,
            );
          }
          if (input.action === "cleanup_internal_e2e_accepted_file") {
            return await executeCallerJwtInternalE2EAcceptedFileCleanupAction(
              jwt,
              input as InternalE2EAcceptedFileCleanupActionInput,
              clientFor,
              serviceClient,
            );
          }
          if (input.action === "finalize_internal_e2e_run") {
            const { data, error } = await client.rpc(
              "finalize_internal_e2e_run_v1",
              {
                p_run_id: input.run_id,
                p_terminal_status: input.terminal_status,
                p_expected_revision: input.expected_revision,
                p_idempotency_key: input.idempotency_key,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "get_project_workspace") {
            const [project, startGate] = await Promise.all([
              client.rpc("get_commercial_project_view_v2", {
                p_project_id: input.project_id,
              }),
              client.rpc("get_operator_project_start_gate_v1", {
                p_quote_request_id: input.quote_request_id,
                p_project_id: input.project_id,
              }),
            ]);
            if (project.error) throw new Error(project.error.message);
            if (startGate.error) throw new Error(startGate.error.message);
            return { project: project.data, start_gate: startGate.data };
          }
          if (input.action === "get_website_execution_workspace") {
            // V2 database contract remains: "get_website_execution_workspace_v2" with p_quote_request_id: input.quote_request_id.
            const data =
              await executeCallerJwtWebsiteExecutionWorkspaceReadAction(
                jwt,
                {
                  action: "get_website_execution_workspace",
                  quote_request_id: String(input.quote_request_id),
                },
                clientFor,
              );
            return data;
          }
          if (input.action === "get_project_requirements_board") {
            const { data, error } = await client.rpc(
              "get_project_requirements_board_v1",
              {
                p_quote_request_id: input.quote_request_id,
                p_project_id: input.project_id,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "create_project_requirements_board") {
            const { data, error } = await client.rpc(
              "create_project_requirements_board_v1",
              {
                p_quote_request_id: input.quote_request_id,
                p_project_id: input.project_id,
                p_idempotency_key: input.idempotency_key,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "create_project_requirement") {
            const { data, error } = await client.rpc(
              "create_project_requirement_v1",
              {
                p_quote_request_id: input.quote_request_id,
                p_project_id: input.project_id,
                p_requirements_board_id: input.requirements_board_id,
                p_expected_board_revision: input.expected_board_revision,
                p_item: input.item,
                p_idempotency_key: input.idempotency_key,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "finalize_project_requirements_board") {
            const { data, error } = await client.rpc(
              "finalize_project_requirements_board_v1",
              {
                p_quote_request_id: input.quote_request_id,
                p_project_id: input.project_id,
                p_requirements_board_id: input.requirements_board_id,
                p_expected_revision: input.expected_revision,
                p_idempotency_key: input.idempotency_key,
              },
            );
            if (error) throw new Error(error.message);
            return data;
          }
          if (
            input.action === "start_project_requirement" ||
            input.action === "block_project_requirement" ||
            input.action === "complete_project_requirement" ||
            input.action === "reopen_project_requirement"
          ) {
            const rpcName = `${input.action}_v1`;
            const parameters: Record<string, unknown> = {
              p_quote_request_id: input.quote_request_id,
              p_project_id: input.project_id,
              p_requirement_id: input.requirement_id,
              p_expected_revision: input.expected_revision,
              p_idempotency_key: input.idempotency_key,
            };
            if (input.action === "block_project_requirement") {
              parameters.p_blocked_reason = input.reason;
            }
            if (input.action === "complete_project_requirement") {
              parameters.p_evidence_reference = input.evidence_reference;
            }
            if (input.action === "reopen_project_requirement") {
              parameters.p_reopen_reason = input.reason;
            }
            const { data, error } = await client.rpc(rpcName, parameters);
            if (error) throw new Error(error.message);
            return data;
          }
          if (input.action === "start_project_work") {
            const { data, error } = await client.rpc("start_project_work_v1", {
              p_quote_request_id: input.quote_request_id,
              p_project_id: input.project_id,
              p_expected_state: input.expected_state,
              p_expected_revision: input.expected_revision,
              p_idempotency_key: input.idempotency_key,
            });
            if (error) throw new Error(error.message);
            return data;
          }
          const request = input.action === "list_applications"
            ? client.rpc("list_operator_applications_v1", {
              p_limit: input.limit,
              p_offset: input.offset,
            })
            : input.action === "get_project_dossier"
            ? client.rpc("get_commercial_project_view_v2", {
              p_project_id: input.project_id,
            })
            : input.action === "get_application_detail"
            ? executeApplicationDetailRead(
              client,
              input,
            )
            : client.rpc("promote_operator_application_v1", {
              p_idempotency_key: input.idempotency_key,
              p_quote_request_id: input.quote_request_id,
              p_application_reference: input.application_reference,
            });
          const { data, error } = await request;
          if (error) throw new Error(error.message);
          if (
            input.action === "get_application_detail" &&
            data?.request_kind === "website"
          ) {
            const service = serviceClient();
            const context = await loadSubmittedApplicationOutputForOperator(
              client,
              service,
              actorAuthUserId,
              data.quote_request_id,
            );
            return enrichOperatorApplicationDetailWithOutput(data, context);
          }
          return data;
        },
        executeCommand: async (
          jwt: string,
          input: ValidatedCommercialCommandInput,
        ) => {
          const { data, error } = await clientFor(jwt).rpc(
            "execute_commercial_command_v2",
            {
              p_project_id: input.project_id,
              p_command_type: input.command_type,
              p_expected_state: input.expected_state,
              p_expected_revision: input.expected_revision,
              p_idempotency_key: input.idempotency_key,
              p_payload: input.payload,
            },
          );
          if (error) throw new Error(error.message);
          return data;
        },
      });
    })
  );
}

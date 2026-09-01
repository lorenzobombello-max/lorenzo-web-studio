import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { deliverEmailJob, type EmailDeliveryResult } from "./email-delivery.ts";
import { buildQuotationEmail, type QuotationEmailTemplate } from "./email-templates.ts";
import {
  buildQuotationAcceptanceUrl,
  createQuotationAcceptanceCapabilityToken,
  hashQuotationAcceptanceCapabilityToken,
} from "./quotation-acceptance-capability.ts";
import { decryptQuotationDeliveryToken, encryptQuotationDeliveryToken } from "./security.ts";

type RpcRow = Record<string, unknown>;
type RpcClient = {
  rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface DeliveryInput {
  supabase: SupabaseClient;
  issuanceId: string;
  requestedExpiresAt: string | null;
  capabilityIdempotencyKey: string;
  deliveryIdempotencyKey: string;
  adminAccessTokenHash: string;
  createdBy: string;
  from: string;
  resendApiKey: string;
}

interface ConfirmationInput {
  supabase: SupabaseClient;
  acceptanceId: string;
  template: Exclude<QuotationEmailTemplate, "QUOTATION_DELIVERY_NL_BE_v1">;
  idempotencyKey: string;
  createdBy: string;
  internalRecipient?: string;
  from: string;
  resendApiKey: string;
}

interface SdfPreparedDeliveryAuthority {
  businessDraftId: string;
  approvalId: string;
  approvalVersion: number;
  approvalSha256: string;
  issuanceId: string;
  artifactId: string;
  artifactSha256: string;
  artifactBytes: number;
}

interface SdfPreparedDeliveryInput {
  authorityClient: RpcClient;
  transportClient: SupabaseClient;
  authority: SdfPreparedDeliveryAuthority;
  from: string;
  resendApiKey: string;
}

interface SdfPreparedDeliveryDependencies {
  decryptToken?: typeof decryptQuotationDeliveryToken;
  buildAcceptanceUrl?: typeof buildQuotationAcceptanceUrl;
  buildEmail?: typeof buildQuotationEmail;
  deliverEmailJob?: typeof deliverEmailJob;
}

function oneRow(data: unknown, error: unknown, code: string): RpcRow {
  const row = Array.isArray(data) && data.length === 1 ? data[0] : null;
  if (error || !row || typeof row !== "object") throw new Error(code);
  return row as RpcRow;
}

function requiredString(row: RpcRow, key: string): string {
  const value = row[key];
  if (typeof value !== "string" || !value) throw new Error("Quotation email state invalid");
  return value;
}

function requiredInteger(row: RpcRow, key: string): number {
  const value = Number(row[key]);
  if (!Number.isInteger(value)) throw new Error("Quotation email state invalid");
  return value;
}

export async function deliverIssuedQuotation(input: DeliveryInput): Promise<EmailDeliveryResult> {
  const token = createQuotationAcceptanceCapabilityToken();
  const tokenDigest = await hashQuotationAcceptanceCapabilityToken(token);
  const encryptedToken = await encryptQuotationDeliveryToken(token, tokenDigest);
  const { data, error } = await input.supabase.rpc("prepare_issued_quotation_delivery_with_capability_v1", {
    p_issuance_id: input.issuanceId,
    p_token_digest: tokenDigest,
    p_encrypted_token: encryptedToken,
    p_requested_expires_at: input.requestedExpiresAt,
    p_capability_idempotency_key: input.capabilityIdempotencyKey,
    p_delivery_idempotency_key: input.deliveryIdempotencyKey,
    p_admin_access_token_hash: input.adminAccessTokenHash,
    p_created_by: input.createdBy,
  });
  const row = oneRow(data, error, "Quotation delivery preparation failed");
  if (row.job_status === "sent") return { status: "sent", attempted: false, attemptCount: 0 };
  const storedTokenDigest = requiredString(row, "stored_token_digest");
  const storedToken = await decryptQuotationDeliveryToken(requiredString(row, "encrypted_token"), storedTokenDigest);
  const email = buildQuotationEmail("QUOTATION_DELIVERY_NL_BE_v1", {
    clientName: requiredString(row, "client_name"),
    quotationNumber: requiredString(row, "quotation_number"),
    quotationVersion: requiredInteger(row, "quotation_version"),
    projectTitle: requiredString(row, "project_title"),
    validUntil: requiredString(row, "valid_until"),
    acceptanceUrl: buildQuotationAcceptanceUrl(storedToken),
  });
  return await deliverEmailJob({
    supabase: input.supabase,
    jobId: requiredString(row, "email_job_id"),
    resendApiKey: input.resendApiKey,
    email: { from: input.from, to: requiredString(row, "recipient_email"), ...email },
  });
}

export async function sendPreparedSdfQuotationDelivery(
  input: SdfPreparedDeliveryInput,
  dependencies: SdfPreparedDeliveryDependencies = {},
): Promise<Readonly<Record<string, unknown>>> {
  const { authority } = input;
  const { data, error } = await input.authorityClient.rpc(
    "get_sdf_quotation_delivery_transport_context_v1",
    {
      p_business_draft_id: authority.businessDraftId,
      p_approval_id: authority.approvalId,
      p_expected_approval_version: authority.approvalVersion,
      p_expected_approval_sha256: authority.approvalSha256,
      p_issuance_id: authority.issuanceId,
      p_artifact_id: authority.artifactId,
      p_expected_artifact_sha256: authority.artifactSha256,
      p_expected_artifact_bytes: authority.artifactBytes,
    },
  );
  if (error) {
    const message = typeof error === "object" && error !== null &&
        "message" in error
      ? String(error.message)
      : "SDF_DELIVERY_TRANSPORT_CONTEXT_INVALID";
    throw new Error(message);
  }
  const row = oneRow(
    data,
    null,
    "SDF_DELIVERY_TRANSPORT_CONTEXT_INVALID",
  );
  const orchestrationId = String(row.orchestration_id || "");
  const emailJobId = String(row.email_job_id || "");
  const capabilityId = String(row.capability_id || "");
  const recipientEmail = String(row.recipient_email || "");
  const tokenDigest = String(row.stored_token_digest || "");
  const encryptedToken = String(row.encrypted_token || "");
  const artifactBytes = Number(row.artifact_bytes);
  const quotationVersion = Number(row.quotation_version);
  const attemptCount = Number(row.attempt_count || 0);
  const jobStatus = String(row.job_status || "");
  if (
    !UUID.test(orchestrationId) || !UUID.test(emailJobId) ||
    !UUID.test(capabilityId) || row.issuance_id !== authority.issuanceId ||
    row.artifact_id !== authority.artifactId ||
    row.artifact_sha256 !== authority.artifactSha256 ||
    artifactBytes !== authority.artifactBytes ||
    row.content_version !== "QUOTATION_DELIVERY_NL_BE_v1" ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipientEmail) ||
    !Number.isInteger(quotationVersion) || quotationVersion < 1 ||
    !Number.isInteger(attemptCount) || attemptCount < 0 ||
    !["pending", "processing", "retry_wait", "sent"].includes(jobStatus)
  ) {
    throw new Error("SDF_DELIVERY_TRANSPORT_CONTEXT_INVALID");
  }
  if (jobStatus === "sent") {
    return {
      delivery_status: "sent",
      email_job_id: emailJobId,
      attempt_count: attemptCount,
      delivery_attempted: false,
      ...(typeof row.sent_at === "string" ? { sent_at: row.sent_at } : {}),
    };
  }
  if (!/^[0-9a-f]{64}$/.test(tokenDigest) || !encryptedToken) {
    throw new Error("SDF_DELIVERY_PAYLOAD_UNAVAILABLE");
  }
  const decryptToken = dependencies.decryptToken ??
    decryptQuotationDeliveryToken;
  const buildAcceptanceUrl = dependencies.buildAcceptanceUrl ??
    buildQuotationAcceptanceUrl;
  const buildEmail = dependencies.buildEmail ?? buildQuotationEmail;
  const deliver = dependencies.deliverEmailJob ?? deliverEmailJob;
  const rawToken = await decryptToken(encryptedToken, tokenDigest);
  const email = buildEmail("QUOTATION_DELIVERY_NL_BE_v1", {
    clientName: requiredString(row, "client_name"),
    quotationNumber: requiredString(row, "quotation_number"),
    quotationVersion,
    projectTitle: requiredString(row, "project_title"),
    validUntil: requiredString(row, "valid_until"),
    acceptanceUrl: buildAcceptanceUrl(rawToken),
  });
  const delivery = await deliver({
    supabase: input.transportClient,
    jobId: emailJobId,
    resendApiKey: input.resendApiKey,
    email: { from: input.from, to: recipientEmail, ...email },
  });
  return {
    delivery_status: delivery.status,
    email_job_id: emailJobId,
    attempt_count: delivery.attemptCount,
    delivery_attempted: delivery.attempted,
    ...(delivery.errorCode ? { error_code: delivery.errorCode } : {}),
  };
}

export async function deliverAcceptanceConfirmation(input: ConfirmationInput): Promise<EmailDeliveryResult> {
  const emailType = input.template === "ACCEPTANCE_CONFIRMATION_CUSTOMER_NL_BE_v1"
    ? "ACCEPTANCE_CONFIRMATION_CUSTOMER"
    : "ACCEPTANCE_CONFIRMATION_INTERNAL";
  const { data, error } = await input.supabase.rpc("prepare_quotation_acceptance_confirmation_v1", {
    p_acceptance_id: input.acceptanceId,
    p_email_type: emailType,
    p_content_version: input.template,
    p_idempotency_key: input.idempotencyKey,
    p_created_by: input.createdBy,
    p_internal_recipient: input.internalRecipient ?? null,
  });
  const row = oneRow(data, error, "Acceptance confirmation preparation failed");
  const email = buildQuotationEmail(input.template, {
    clientName: requiredString(row, "client_name"),
    quotationNumber: requiredString(row, "quotation_number"),
    quotationVersion: requiredInteger(row, "quotation_version"),
    projectTitle: requiredString(row, "project_title"),
    acceptedAt: requiredString(row, "accepted_at"),
    acceptingName: requiredString(row, "accepting_name"),
  });
  return await deliverEmailJob({
    supabase: input.supabase,
    jobId: requiredString(row, "email_job_id"),
    resendApiKey: input.resendApiKey,
    email: { from: input.from, to: requiredString(row, "recipient_email"), ...email },
  });
}

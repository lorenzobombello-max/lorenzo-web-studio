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

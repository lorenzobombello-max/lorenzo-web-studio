import { createClient } from "npm:@supabase/supabase-js@2";
import { deliverEmailJob, type EmailDeliveryResult } from "../_shared/email-delivery.ts";
import {
  type ResendTransportInput,
  type ResendTransportResult,
  sendEmailViaResend,
} from "../_shared/resend-transport.ts";
import {
  buildApprovedConfirmationEmail, buildIntakeInvitationEmail,
  buildSdfQualificationInvitationEmail, buildSdfQualificationMoreInformationEmail, buildSdfRequestReceivedEmail,
} from "../_shared/email-templates.ts";
import { createRawIntakeToken, decryptIntakeInvitationToken, encryptIntakeInvitationToken, hashIntakeToken } from "../_shared/security.ts";
import { handleApplicationIntakeAutomation, hasCanonicalSdfConfirmationTemplate, sdfInvitationOutcome, type AutomationClaim, websiteIntakeOutcome, websiteTypeOrNull } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const workerSecret = Deno.env.get("APPLICATION_INTAKE_AUTOMATION_WORKER_SECRET") || "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
const fromEmail = Deno.env.get("FROM_EMAIL") || "";
const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";
const sdfInitialConfirmationAuthorityMode = Deno.env.get(
  "SDF_INITIAL_CONFIRMATION_AUTHORITY_MODE",
);
const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });

async function rpc(name: string, parameters: Record<string, unknown>) { return await supabase.rpc(name, parameters); }
function row(data: unknown): Record<string, unknown> | null { const value = Array.isArray(data) ? data[0] : data; return value && typeof value === "object" ? value as Record<string, unknown> : null; }

async function executeWebsite(claim: AutomationClaim): Promise<EmailDeliveryResult> {
  if (claim.phase === "APPROVAL") {
    const result = await rpc("execute_application_intake_automation_approval_v1", { p_work_id: claim.work_id, p_claim_token: claim.claim_token });
    const authority = row(result.data);
    if (result.error || !authority) throw new Error("WEBSITE_APPROVAL_AUTHORITY_FAILED");
    return await deliverEmailJob({ supabase, jobId: String(authority.confirmation_job_id), resendApiKey, email: {
      from: fromEmail, to: String(authority.request_email),
      ...buildApprovedConfirmationEmail({ clientName: String(authority.request_name), requestId: claim.quote_request_id, createdAt: String(authority.created_at), websiteType: websiteTypeOrNull(authority.website_type) || "Niet van toepassing" }),
    } });
  }
  const rawToken = createRawIntakeToken(); const digest = await hashIntakeToken(rawToken); const encrypted = await encryptIntakeInvitationToken(rawToken, digest);
  const result = await rpc("execute_application_intake_automation_intake_v1", { p_work_id: claim.work_id, p_claim_token: claim.claim_token, p_access_token_hash: digest, p_encrypted_token: encrypted });
  const authority = row(result.data); if (result.error || !authority) throw new Error("WEBSITE_INTAKE_AUTHORITY_FAILED");
  const outcome = websiteIntakeOutcome(authority);
  if (outcome === "stopped") return { status: "sent", attempted: false, attemptCount: 0 };
  if (outcome !== "deliver") throw new Error("WEBSITE_INTAKE_AUTHORITY_FAILED");
  const url = new URL("/pages/intake.html", siteUrl); url.searchParams.set("token", rawToken);
  return await deliverEmailJob({ supabase, jobId: String(authority.invitation_job_id), resendApiKey, email: { from: fromEmail, to: String(authority.request_email), ...buildIntakeInvitationEmail({ clientName: String(authority.request_name), company: authority.request_company as string | null, requestId: claim.quote_request_id, intakeUrl: url.toString() }) } });
}

interface SdfConfirmationRpcResult {
  data: unknown;
  error: { message: string } | null;
}

export interface SdfConfirmationExecutorDependencies {
  authorityMode: string | undefined;
  resendApiKey: string;
  fromEmail: string;
  rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): Promise<SdfConfirmationRpcResult>;
  deliverLegacy(input: {
    jobId: string;
    email: ResendTransportInput;
  }): Promise<EmailDeliveryResult>;
  sendTransport(input: ResendTransportInput): Promise<ResendTransportResult>;
}

function sdfFailure(
  errorCode: string,
  attempted = false,
  attemptCount = 0,
): EmailDeliveryResult {
  return { status: "failed", attempted, attemptCount, errorCode };
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function sdfRequestReference(
  authority: Record<string, unknown>,
): string | null {
  return isNonEmptyString(authority.support_reference)
    ? authority.support_reference
    : null;
}

function sdfEmail(
  authority: Record<string, unknown>,
  apiKey: string,
  from: string,
  idempotencyKey: string,
): ResendTransportInput | null {
  const requestReference = sdfRequestReference(authority);
  if (
    !isNonEmptyString(authority.request_name) ||
    !isNonEmptyString(authority.request_email) ||
    !requestReference
  ) return null;
  return {
    apiKey,
    from,
    to: authority.request_email,
    ...buildSdfRequestReceivedEmail({
      customerName: authority.request_name,
      supportReference: requestReference,
    }),
    idempotencyKey,
  };
}

async function resolveSdfSupportReference(
  rpc: SdfConfirmationExecutorDependencies["rpc"],
  identifiers: { p_quote_request_id: string | null; p_intake_id: string | null },
): Promise<string | null> {
  const result = await rpc("resolve_sdf_support_reference_v1", identifiers);
  const value = Array.isArray(result.data) ? result.data[0] : result.data;
  return result.error || !isNonEmptyString(value) ? null : value;
}

function completionStatus(value: unknown): EmailDeliveryResult["status"] | null {
  return value === "sent" || value === "retry_wait" || value === "failed"
    ? value
    : null;
}

export function createSdfConfirmationExecutor(
  dependencies: SdfConfirmationExecutorDependencies,
): (claim: AutomationClaim) => Promise<EmailDeliveryResult> {
  return async (claim) => {
    if (
      dependencies.authorityMode !== "legacy" &&
      dependencies.authorityMode !== "isolated"
    ) {
      throw new Error("SDF_INITIAL_CONFIRMATION_MODE_INVALID");
    }

    if (dependencies.authorityMode === "legacy") {
      const result = await dependencies.rpc(
        "execute_application_intake_automation_sdf_confirmation_v1",
        { p_work_id: claim.work_id, p_claim_token: claim.claim_token },
      );
      const authority = row(result.data);
      if (
        result.error || !authority ||
        authority.request_kind !== "slimme_documentenflow" ||
        !hasCanonicalSdfConfirmationTemplate(authority) ||
        !isNonEmptyString(authority.confirmation_job_id)
      ) throw new Error("SDF_CONFIRMATION_AUTHORITY_FAILED");
      const supportReference = await resolveSdfSupportReference(
        dependencies.rpc,
        { p_quote_request_id: claim.quote_request_id, p_intake_id: null },
      );
      const email = sdfEmail(
        { ...authority, support_reference: supportReference },
        dependencies.resendApiKey,
        dependencies.fromEmail,
        `quote-request-email/${authority.confirmation_job_id}`,
      );
      if (!email) throw new Error("SDF_CONFIRMATION_AUTHORITY_FAILED");
      return await dependencies.deliverLegacy({
        jobId: authority.confirmation_job_id,
        email,
      });
    }

    const preparedResult = await dependencies.rpc(
      "prepare_sdf_initial_confirmation_v2",
      { p_work_id: claim.work_id, p_work_claim_token: claim.claim_token },
    );
    const prepared = row(preparedResult.data);
    if (preparedResult.error || !prepared) {
      return sdfFailure("SDF_INITIAL_CONFIRMATION_PREPARE_FAILED");
    }
    if (
      prepared.outcome === "already_sent" &&
      prepared.authority_source == null && prepared.job_id == null
    ) {
      return { status: "sent", attempted: false, attemptCount: 0 };
    }
    if (prepared.authority_source === "legacy") {
      if (
        !isNonEmptyString(prepared.job_id) ||
        prepared.request_kind !== "slimme_documentenflow" ||
        prepared.template_version !== "v1"
      ) return sdfFailure("SDF_INITIAL_CONFIRMATION_LEGACY_INVALID");
      const supportReference = await resolveSdfSupportReference(
        dependencies.rpc,
        { p_quote_request_id: claim.quote_request_id, p_intake_id: null },
      );
      const email = sdfEmail(
        { ...prepared, support_reference: supportReference },
        dependencies.resendApiKey,
        dependencies.fromEmail,
        `quote-request-email/${prepared.job_id}`,
      );
      if (!email) return sdfFailure("SDF_INITIAL_CONFIRMATION_LEGACY_INVALID");
      return await dependencies.deliverLegacy({
        jobId: prepared.job_id,
        email,
      });
    }
    if (prepared.authority_source !== "sdf_initial") {
      return sdfFailure("SDF_INITIAL_CONFIRMATION_PREPARE_INVALID");
    }
    if (prepared.outcome === "retry_wait" || prepared.outcome === "processing") {
      return { status: "retry_wait", attempted: false, attemptCount: 0 };
    }
    if (prepared.outcome === "failed") {
      return sdfFailure("SDF_INITIAL_CONFIRMATION_FAILED");
    }
    if (prepared.outcome !== "due" || !isNonEmptyString(prepared.job_id)) {
      return sdfFailure("SDF_INITIAL_CONFIRMATION_PREPARE_INVALID");
    }

    const jobId = prepared.job_id;
    const idempotencyKey = `sdf-initial-confirmation/${jobId}`;
    const claimResult = await dependencies.rpc(
      "claim_sdf_initial_confirmation_email_job_v1",
      { p_job_id: jobId },
    );
    const claimed = row(claimResult.data);
    const attemptCount = Number(claimed?.attempt_count) || 0;
    if (
      claimResult.error || !claimed || claimed.job_id !== jobId ||
      claimed.template_version !== "SDF_REQUEST_RECEIVED_NL_BE_v1" ||
      claimed.provider_idempotency_key !== idempotencyKey ||
      !isNonEmptyString(claimed.delivery_lease_token)
    ) return sdfFailure("SDF_INITIAL_CONFIRMATION_CLAIM_FAILED", false, attemptCount);

    const transportInput = sdfEmail(
      {
        ...claimed,
        support_reference: await resolveSdfSupportReference(
          dependencies.rpc,
          { p_quote_request_id: claim.quote_request_id, p_intake_id: null },
        ),
      },
      dependencies.resendApiKey,
      dependencies.fromEmail,
      idempotencyKey,
    );
    if (!transportInput) {
      return sdfFailure("SDF_INITIAL_CONFIRMATION_PAYLOAD_INVALID", false, attemptCount);
    }
    const leaseToken = claimed.delivery_lease_token;
    const validation = await dependencies.rpc(
      "validate_sdf_initial_confirmation_email_delivery_v1",
      { p_job_id: jobId, p_delivery_lease_token: leaseToken },
    );
    if (validation.error || validation.data !== true) {
      return sdfFailure("SDF_INITIAL_CONFIRMATION_LEASE_INVALID", false, attemptCount);
    }

    const transport = await dependencies.sendTransport(transportInput);
    const completion = await dependencies.rpc(
      "complete_sdf_initial_confirmation_email_job_v1",
      {
        p_job_id: jobId,
        p_delivery_lease_token: leaseToken,
        p_succeeded: transport.ok,
        p_retryable: transport.ok ? false : transport.retryable,
        p_error_code: transport.ok ? null : transport.code,
        p_provider_message_id: transport.ok
          ? transport.providerMessageId
          : null,
      },
    );
    const completed = row(completion.data);
    const status = completionStatus(completed?.status);
    if (completion.error || !completed || !status) {
      return sdfFailure(
        "SDF_INITIAL_CONFIRMATION_COMPLETION_FAILED",
        true,
        attemptCount,
      );
    }
    return {
      status,
      attempted: true,
      attemptCount: Number(completed.attempt_count) || attemptCount,
    };
  };
}

const executeSdfConfirmation = createSdfConfirmationExecutor({
  authorityMode: sdfInitialConfirmationAuthorityMode,
  resendApiKey,
  fromEmail,
  rpc,
  deliverLegacy: async ({ jobId, email }) =>
    await deliverEmailJob({ supabase, jobId, resendApiKey, email }),
  sendTransport: sendEmailViaResend,
});

export interface SdfInvitationExecutorDependencies {
  siteUrl: string;
  resendApiKey: string;
  fromEmail: string;
  rpc: SdfConfirmationExecutorDependencies["rpc"];
  createCapabilityMaterial(): Promise<{ digest: string; encrypted: string }>;
  decryptCapability(encrypted: string, digest: string): Promise<string>;
  fetchProvider(input: string | URL | Request, init?: RequestInit): Promise<Response>;
}

export function createSdfInvitationExecutor(dependencies: SdfInvitationExecutorDependencies) {
  return async (claim: AutomationClaim): Promise<EmailDeliveryResult> => {
  const capability = await dependencies.createCapabilityMaterial();
  const result = await dependencies.rpc("execute_application_intake_automation_sdf_intake_v1", {
    p_work_id: claim.work_id,
    p_claim_token: claim.claim_token,
    p_customer_capability_digest: capability.digest,
    p_encrypted_capability: capability.encrypted,
  });
  const authority = row(result.data); if (result.error || !authority) throw new Error("SDF_INTAKE_AUTHORITY_FAILED");
  const outcome = sdfInvitationOutcome(authority);
  if (outcome === "already_sent") return { status: "sent", attempted: false, attemptCount: 0 };
  if (outcome !== "deliver") throw new Error("SDF_INTAKE_AUTHORITY_FAILED");
  const persistedRawToken = await dependencies.decryptCapability(String(authority.encrypted_capability), String(authority.customer_capability_digest));
  const url = new URL("/pages/sdf-qualification-intake.html", dependencies.siteUrl); url.hash = new URLSearchParams({ token: persistedRawToken }).toString();
  const claimResult = await dependencies.rpc("claim_sdf_qualification_email_job_v1", { p_job_id: authority.job_id });
  const claimedAuthority = row(claimResult.data);
  if (claimResult.error || !claimedAuthority) throw new Error("SDF_EMAIL_JOB_NOT_CLAIMED");
  const deliveryAuthority = await dependencies.rpc("validate_sdf_qualification_email_delivery_v1", { p_job_id: authority.job_id, p_delivery_lease_token: claimedAuthority.delivery_lease_token });
  if (deliveryAuthority.error || deliveryAuthority.data !== true) return { status: "failed", attempted: false, attemptCount: 0 };
  const supportReference = await resolveSdfSupportReference(dependencies.rpc, { p_quote_request_id: claim.quote_request_id, p_intake_id: null });
  if (!supportReference) throw new Error("SDF_SUPPORT_REFERENCE_AUTHORITY_FAILED");
  const email = buildSdfQualificationInvitationEmail({ customerName: String(authority.request_name), supportReference, intakeUrl: url.toString() });
  const response = await dependencies.fetchProvider("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${dependencies.resendApiKey}`, "Content-Type": "application/json", "Idempotency-Key": `sdf-qualification-email/${authority.job_id}` }, body: JSON.stringify({ from: dependencies.fromEmail, to: [authority.request_email], ...email }) });
  const provider = response.ok ? await response.json().catch(() => ({})) as Record<string, unknown> : {};
  const completion = await dependencies.rpc("complete_sdf_qualification_email_job_v1", { p_job_id: authority.job_id, p_delivery_lease_token: claimedAuthority.delivery_lease_token, p_succeeded: response.ok, p_retryable: response.status === 429 || response.status >= 500, p_error_code: response.ok ? null : `RESEND_HTTP_${response.status}`, p_provider_message_id: typeof provider.id === "string" ? provider.id : null });
  const completed = row(completion.data); return { status: String(completed?.status || "failed") as EmailDeliveryResult["status"], attempted: true, attemptCount: Number(completed?.attempt_count || 0) };
  };
}

const executeSdfInvitation = createSdfInvitationExecutor({
  siteUrl, resendApiKey, fromEmail, rpc,
  createCapabilityMaterial: async () => {
    const rawToken = createRawIntakeToken();
    const digest = await hashIntakeToken(rawToken);
    return { digest, encrypted: await encryptIntakeInvitationToken(rawToken, digest) };
  },
  decryptCapability: decryptIntakeInvitationToken,
  fetchProvider: fetch,
});

async function executeQueuedSdfEmail(): Promise<EmailDeliveryResult | null> {
  const claimed = await rpc("claim_next_sdf_qualification_email_job_v1", {});
  const authority = row(claimed.data);
  if (claimed.error) throw new Error("SDF_EMAIL_JOB_CLAIM_FAILED");
  if (!authority) return null;
  const expectedTemplate = authority.kind === "invitation" ? "SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1" : authority.kind === "more_information" ? "SDF_QUALIFICATION_MORE_INFORMATION_NL_BE_v1" : null;
  if (!expectedTemplate || authority.template_version !== expectedTemplate) throw new Error("SDF_EMAIL_TEMPLATE_AUTHORITY_FAILED");
  const deliveryAuthority = await rpc("validate_sdf_qualification_email_delivery_v1", { p_job_id: authority.job_id, p_delivery_lease_token: authority.delivery_lease_token });
  if (deliveryAuthority.error || deliveryAuthority.data !== true) return { status: "failed", attempted: false, attemptCount: Number(authority.attempt_count || 0) };
  const rawToken = await decryptIntakeInvitationToken(String(authority.encrypted_capability), String(authority.customer_capability_digest));
  const url = new URL("/pages/sdf-qualification-intake.html", siteUrl); url.hash = new URLSearchParams({ token: rawToken }).toString();
  const supportReference = await resolveSdfSupportReference(rpc, { p_quote_request_id: null, p_intake_id: String(authority.intake_id) });
  if (!supportReference) throw new Error("SDF_SUPPORT_REFERENCE_AUTHORITY_FAILED");
  const email = authority.kind === "invitation"
    ? buildSdfQualificationInvitationEmail({ customerName: String(authority.request_name), supportReference, intakeUrl: url.toString() })
    : buildSdfQualificationMoreInformationEmail({ customerName: String(authority.request_name), supportReference, moreInformationReason: String(authority.reason || ""), intakeUrl: url.toString() });
  const response = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json", "Idempotency-Key": `sdf-qualification-email/${authority.job_id}` }, body: JSON.stringify({ from: fromEmail, to: [authority.request_email], ...email }) });
  const provider = response.ok ? await response.json().catch(() => ({})) as Record<string, unknown> : {};
  const completion = await rpc("complete_sdf_qualification_email_job_v1", { p_job_id: authority.job_id, p_delivery_lease_token: authority.delivery_lease_token, p_succeeded: response.ok, p_retryable: response.status === 429 || response.status >= 500, p_error_code: response.ok ? null : `RESEND_HTTP_${response.status}`, p_provider_message_id: typeof provider.id === "string" ? provider.id : null });
  const completed = row(completion.data);
  return { status: String(completed?.status || "failed") as EmailDeliveryResult["status"], attempted: true, attemptCount: Number(completed?.attempt_count || 0) };
}

if (import.meta.main) Deno.serve((request) => handleApplicationIntakeAutomation(request, {
  configurationReady: Boolean(supabaseUrl && serviceRoleKey && workerSecret && resendApiKey && fromEmail), workerSecret,
  randomUUID: () => crypto.randomUUID(), digest: async (data) => await crypto.subtle.digest("SHA-256", Uint8Array.from(data)), rpc,
  executeWebsite, executeSdfConfirmation, executeSdfInvitation, executeQueuedSdfEmail,
}));
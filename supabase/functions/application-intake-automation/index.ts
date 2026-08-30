import { createClient } from "npm:@supabase/supabase-js@2";
import { deliverEmailJob, type EmailDeliveryResult } from "../_shared/email-delivery.ts";
import {
  buildApprovedConfirmationEmail, buildIntakeInvitationEmail,
  buildSdfQualificationInvitationEmail, buildSdfQualificationMoreInformationEmail, buildSdfRequestReceivedEmail,
} from "../_shared/email-templates.ts";
import { createRawIntakeToken, decryptIntakeInvitationToken, encryptIntakeInvitationToken, hashIntakeToken } from "../_shared/security.ts";
import { handleApplicationIntakeAutomation, hasCanonicalSdfConfirmationTemplate, type AutomationClaim, websiteIntakeOutcome, websiteTypeOrNull } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const workerSecret = Deno.env.get("APPLICATION_INTAKE_AUTOMATION_WORKER_SECRET") || "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
const fromEmail = Deno.env.get("FROM_EMAIL") || "";
const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";
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

async function executeSdfConfirmation(claim: AutomationClaim): Promise<EmailDeliveryResult> {
  const result = await rpc("execute_application_intake_automation_sdf_confirmation_v1", { p_work_id: claim.work_id, p_claim_token: claim.claim_token });
  const authority = row(result.data); if (result.error || !authority || authority.request_kind !== "slimme_documentenflow" || !hasCanonicalSdfConfirmationTemplate(authority)) throw new Error("SDF_CONFIRMATION_AUTHORITY_FAILED");
  return await deliverEmailJob({ supabase, jobId: String(authority.confirmation_job_id), resendApiKey, email: { from: fromEmail, to: String(authority.request_email), ...buildSdfRequestReceivedEmail({ customerName: String(authority.request_name), applicationReference: String(authority.application_reference || `#${claim.quote_request_id.slice(0,8).toUpperCase()}`) }) } });
}

async function executeSdfInvitation(claim: AutomationClaim): Promise<EmailDeliveryResult> {
  const result = await rpc("execute_application_intake_automation_sdf_intake_v1", { p_work_id: claim.work_id, p_claim_token: claim.claim_token });
  const authority = row(result.data); if (result.error || !authority) throw new Error("SDF_INTAKE_AUTHORITY_FAILED");
  const rawToken = await decryptIntakeInvitationToken(String(authority.encrypted_capability), String(authority.customer_capability_digest));
  const url = new URL("/pages/sdf-qualification-intake.html", siteUrl); url.hash = new URLSearchParams({ token: rawToken }).toString();
  const claimResult = await rpc("claim_sdf_qualification_email_job_v1", { p_job_id: authority.job_id });
  const claimedAuthority = row(claimResult.data);
  if (claimResult.error || !claimedAuthority) throw new Error("SDF_EMAIL_JOB_NOT_CLAIMED");
  const deliveryAuthority = await rpc("validate_sdf_qualification_email_delivery_v1", { p_job_id: authority.job_id, p_delivery_lease_token: claimedAuthority.delivery_lease_token });
  if (deliveryAuthority.error || deliveryAuthority.data !== true) return { status: "failed", attempted: false, attemptCount: 0 };
  const email = buildSdfQualificationInvitationEmail({ customerName: String(authority.request_name), intakeUrl: url.toString() });
  const response = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json", "Idempotency-Key": `sdf-qualification-email/${authority.job_id}` }, body: JSON.stringify({ from: fromEmail, to: [authority.request_email], ...email }) });
  const provider = response.ok ? await response.json().catch(() => ({})) as Record<string, unknown> : {};
  const completion = await rpc("complete_sdf_qualification_email_job_v1", { p_job_id: authority.job_id, p_delivery_lease_token: claimedAuthority.delivery_lease_token, p_succeeded: response.ok, p_retryable: response.status === 429 || response.status >= 500, p_error_code: response.ok ? null : `RESEND_HTTP_${response.status}`, p_provider_message_id: typeof provider.id === "string" ? provider.id : null });
  const completed = row(completion.data); return { status: String(completed?.status || "failed") as EmailDeliveryResult["status"], attempted: true, attemptCount: Number(completed?.attempt_count || 0) };
}

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
  const email = authority.kind === "invitation"
    ? buildSdfQualificationInvitationEmail({ customerName: String(authority.request_name), intakeUrl: url.toString() })
    : buildSdfQualificationMoreInformationEmail({ customerName: String(authority.request_name), moreInformationReason: String(authority.reason || ""), intakeUrl: url.toString() });
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
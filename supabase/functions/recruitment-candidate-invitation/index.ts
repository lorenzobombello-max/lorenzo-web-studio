import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { buildRecruitmentCandidateInvitationEmail } from "../_shared/email-templates.ts";
import { sendEmailViaResend } from "../_shared/resend-transport.ts";
import {
  createRawRecruitmentCandidateToken,
  decryptRecruitmentCandidateToken,
  encryptRecruitmentCandidateToken,
  hashRecruitmentCandidateToken,
} from "../_shared/security.ts";
import {
  getSupabaseServerSecretKey,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";

const PROFILES = new Set(["Webdesign", "Development", "Security", "SEO", "Content"]);
const EMAIL = /^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/;
const RECRUITMENT_PUBLIC_SITE_URL = "https://lorenzowebsolutions.be";

export function resolveRecruitmentCandidateInvitationServiceKey(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
): string | null {
  try {
    return getSupabaseServerSecretKey("default", environment);
  } catch {
    return null;
  }
}

function json(origin: string | null, status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(origin), "Content-Type": "application/json", "Cache-Control": "no-store" } });
}

function row(value: unknown): Record<string, unknown> | null {
  const candidate = Array.isArray(value) ? value[0] : value;
  return candidate && typeof candidate === "object" ? candidate as Record<string, unknown> : null;
}

function bearer(request: Request): string | null {
  return request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1] || null;
}

function localDeliveryFetch(): typeof fetch {
  const configured = Deno.env.get("RESEND_API_URL");
  if (!configured || configured === "https://api.resend.com/emails") return fetch;
  const target = new URL(configured);
  if (Deno.env.get("ALLOW_LOCAL_EMAIL_DELIVERY") !== "true" || !["127.0.0.1", "localhost", "host.docker.internal"].includes(target.hostname)) {
    throw new Error("RECRUITMENT_EMAIL_CONFIGURATION_INVALID");
  }
  return (_input, init)=>fetch(target, init);
}

export async function handleRecruitmentCandidateInvitation(request: Request): Promise<Response> {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  const originFailure = rejectIfOriginNotAllowed(request);
  if (originFailure) return originFailure;
  if (request.method !== "POST") return json(origin, 405, { ok: false, code: "METHOD_NOT_ALLOWED" });
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const serviceRoleKey = resolveRecruitmentCandidateInvitationServiceKey();
  const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
  const fromEmail = Deno.env.get("FROM_EMAIL") || "";
  const jwt = bearer(request);
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !jwt) return json(origin, 401, { ok: false, code: "RECRUITMENT_OWNER_REQUIRED" });

  const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !authData.user) return json(origin, 401, { ok: false, code: "RECRUITMENT_OWNER_REQUIRED" });
  let input: Record<string, unknown>;
  try { input = await request.json(); } catch { return json(origin, 400, { ok: false, code: "RECRUITMENT_INVITATION_INVALID" }); }
  const name = typeof input.name === "string" ? input.name.trim() : "";
  const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
  const testProfile = typeof input.test_profile === "string" ? input.test_profile.trim() : "";
  if (!name || name.length > 120 || !EMAIL.test(email) || email.length > 254 || !PROFILES.has(testProfile)) {
    return json(origin, 400, { ok: false, code: "RECRUITMENT_INVITATION_INVALID" });
  }

  const service = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  try {
    const rawToken = createRawRecruitmentCandidateToken();
    const digest = await hashRecruitmentCandidateToken(rawToken);
    const encryptedToken = await encryptRecruitmentCandidateToken(rawToken, digest);
    const preparedResult = await service.rpc("create_recruitment_candidate_invitation_v2", {
      p_owner_auth_user_id: authData.user.id,
      p_name: name,
      p_email: email,
      p_test_profile: testProfile,
      p_capability_digest: digest,
      p_encrypted_capability: encryptedToken,
    });
    const prepared = row(preparedResult.data);
    if (preparedResult.error || !prepared || typeof prepared.job_id !== "string") throw new Error("RECRUITMENT_INVITATION_PREPARE_FAILED");
    const claimResult = await service.rpc("claim_recruitment_candidate_invitation_email_v2", { p_job_id: prepared.job_id });
    const claim = row(claimResult.data);
    if (claimResult.error || !claim || claim.outcome !== "claimed" || typeof claim.delivery_lease_token !== "string") throw new Error("RECRUITMENT_INVITATION_CLAIM_FAILED");
    const claimedToken = await decryptRecruitmentCandidateToken(String(claim.encrypted_capability), String(claim.capability_digest));
    const testUrl = new URL("/recruitment/test/", RECRUITMENT_PUBLIC_SITE_URL);
    testUrl.hash = new URLSearchParams({ token: claimedToken }).toString();
    const content = buildRecruitmentCandidateInvitationEmail({
      candidateName: String(claim.candidate_name), testProfile: String(claim.test_profile),
      selectionCount: Number(claim.selection_count), testUrl: testUrl.toString(),
    });
    const delivery = await sendEmailViaResend({
      apiKey: resendApiKey, from: fromEmail, to: String(claim.candidate_email), ...content,
      idempotencyKey: `recruitment-candidate-invitation/${prepared.job_id}`,
    }, localDeliveryFetch());
    const completionResult = await service.rpc("complete_recruitment_candidate_invitation_email_v2", {
      p_job_id: prepared.job_id, p_delivery_lease_token: claim.delivery_lease_token,
      p_succeeded: delivery.ok, p_retryable: delivery.ok ? false : delivery.retryable,
      p_error_code: delivery.ok ? null : delivery.code,
      p_provider_message_id: delivery.ok ? delivery.providerMessageId : null,
    });
    const completed = row(completionResult.data);
    if (completionResult.error || !completed) throw new Error("RECRUITMENT_INVITATION_COMPLETION_FAILED");
    return json(origin, delivery.ok ? 201 : 502, {
      ok: delivery.ok, candidate_id: prepared.candidate_id, assignment_id: prepared.assignment_id,
      selection_count: prepared.selection_count, invitation_status: completed.status,
    });
  } catch {
    return json(origin, 500, { ok: false, code: "RECRUITMENT_INVITATION_FAILED" });
  }
}

if (import.meta.main) Deno.serve(handleRecruitmentCandidateInvitation);
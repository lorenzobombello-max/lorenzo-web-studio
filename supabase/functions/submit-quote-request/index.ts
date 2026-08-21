import { createClient } from "npm:@supabase/supabase-js@2";
import { buildAdminNotificationEmail } from "../_shared/email-templates.ts";
import { deliverEmailJob } from "../_shared/email-delivery.ts";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { computeTokenExpiry, createApprovalTokenForIdempotencyKey, extractClientIp, hashApprovalToken, hashClientIp } from "../_shared/security.ts";
import { isRateLimited } from "../_shared/rate-limit.ts";
import { InputValidationError, sanitizeAndValidateSubmitPayload } from "../_shared/validation.ts";
import { validateVatWithVies, type VatValidationResult } from "../_shared/vat-validation.ts";

const MAX_BODY_BYTES = 16 * 1024;
const IDEMPOTENCY_KEY_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

class RequestError extends Error {
  constructor(public readonly status: number, public readonly code: string) {
    super(code);
    this.name = "RequestError";
  }
}

function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function parseJsonBody(request: Request): Promise<unknown> {
  const contentType = request.headers.get("content-type") || "";
  if (contentType.split(";", 1)[0].trim().toLowerCase() !== "application/json") {
    throw new RequestError(415, "UNSUPPORTED_CONTENT_TYPE");
  }

  const declaredLength = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    throw new RequestError(413, "BODY_TOO_LARGE");
  }

  if (!request.body) throw new RequestError(400, "INVALID_JSON");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    totalBytes += value.byteLength;
    if (totalBytes > MAX_BODY_BYTES) {
      await reader.cancel();
      throw new RequestError(413, "BODY_TOO_LARGE");
    }
    chunks.push(value);
  }

  const bodyBytes = new Uint8Array(totalBytes);
  let offset = 0;
  chunks.forEach((chunk) => {
    bodyBytes.set(chunk, offset);
    offset += chunk.byteLength;
  });

  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes));
  } catch {
    throw new RequestError(400, "INVALID_JSON");
  }
}

async function fingerprintPayload(payload: Record<string, unknown>): Promise<string> {
  const canonical = JSON.stringify(payload);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return toHex(digest);
}

function jsonResponse(status: number, body: Record<string, unknown>, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(origin),
    });
  }

  const blocked = rejectIfOriginNotAllowed(request);
  if (blocked) return blocked;

  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, message: "Method not allowed." }, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
  const adminEmail = Deno.env.get("ADMIN_EMAIL") || "";
  const fromEmail = Deno.env.get("FROM_EMAIL") || "";
  const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(500, {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      message: "Server configuration is incomplete.",
    }, origin);
  }

  let rawPayload: unknown;
  try {
    rawPayload = await parseJsonBody(request);
  } catch (error) {
    if (error instanceof RequestError) {
      return jsonResponse(error.status, { ok: false, code: error.code, message: "Invalid request." }, origin);
    }
    return jsonResponse(400, { ok: false, code: "INVALID_REQUEST", message: "Invalid request." }, origin);
  }

  let sanitized;
  try {
    sanitized = sanitizeAndValidateSubmitPayload(rawPayload);
  } catch (error) {
    const code = error instanceof InputValidationError ? error.code : "INVALID_INPUT";
    const field = error instanceof InputValidationError ? error.field : undefined;
    return jsonResponse(400, {
      ok: false,
      code,
      ...(field ? { field } : {}),
      message: "Invalid input.",
    }, origin);
  }

  // Honeypot: return success-shaped response to avoid bot feedback loops.
  if (sanitized.honeypotValue) {
    return jsonResponse(200, {
      ok: true,
      code: "REQUEST_ACCEPTED",
      message: "Request received.",
    }, origin);
  }

  const requestedIdempotencyKey = (request.headers.get("idempotency-key") || "").trim();
  const idempotencyKey = requestedIdempotencyKey || crypto.randomUUID();
  if (!IDEMPOTENCY_KEY_REGEX.test(idempotencyKey)) {
    return jsonResponse(400, {
      ok: false,
      code: "INVALID_IDEMPOTENCY_KEY",
      message: "Invalid request.",
    }, origin);
  }

  const requestFingerprint = await fingerprintPayload({
    request_kind: sanitized.request_kind,
    ...(sanitized.request_kind === "slimme_documentenflow" ? { sdf_package: sanitized.sdf_package } : {}),
    name: sanitized.name,
    customer_type: sanitized.customer_type,
    company: sanitized.company,
    enterprise_number: sanitized.enterprise_number,
    vat_number: sanitized.vat_number,
    billing_address: sanitized.billing_address,
    billing_postal_code: sanitized.billing_postal_code,
    billing_city: sanitized.billing_city,
    billing_country: sanitized.billing_country,
    billing_email: sanitized.billing_email,
    email: sanitized.email,
    phone: sanitized.phone,
    website_type: sanitized.website_type,
    budget: sanitized.budget,
    timing: sanitized.timing,
    description: sanitized.description,
    privacy_consent: sanitized.privacy_consent,
  });

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let clientIpHash = "";
  try {
    clientIpHash = await hashClientIp(extractClientIp(request));
  } catch {
    return jsonResponse(500, {
      ok: false,
      message: "Could not process request.",
    }, origin);
  }

  const { data: existingRequest, error: existingRequestError } = await supabase
    .from("quote_requests")
    .select("id, request_fingerprint, vat_validation_status, vat_validated_at")
    .eq("idempotency_key", idempotencyKey)
    .maybeSingle();

  if (existingRequestError) {
    return jsonResponse(500, { ok: false, code: "IDEMPOTENCY_LOOKUP_FAILED", message: "Could not process request." }, origin);
  }
  if (existingRequest && existingRequest.request_fingerprint !== requestFingerprint) {
    return jsonResponse(409, { ok: false, code: "IDEMPOTENCY_CONFLICT", message: "Request key was already used." }, origin);
  }

  const rateLimitResult = existingRequest
    ? { limited: false, error: false }
    : await isRateLimited(supabase, clientIpHash);

  if (rateLimitResult.error) {
    console.error("rate_limit_internal_error", {
      category: "rate_limit",
      step: "quote_requests_count",
      code: rateLimitResult.errorCode ?? "UNKNOWN_RATE_LIMIT_ERROR",
      message: rateLimitResult.errorMessage ?? "Rate limit check failed",
    });

    return jsonResponse(503, {
      ok: false,
      code: "RATE_LIMIT_UNAVAILABLE",
      message: "Service temporarily unavailable.",
    }, origin);
  }

  if (rateLimitResult.limited) {
    return jsonResponse(429, {
      ok: false,
      code: "RATE_LIMITED",
      message: "Too many requests.",
    }, origin);
  }

  const vatValidation: VatValidationResult = existingRequest
    ? {
      status: existingRequest.vat_validation_status,
      validatedAt: existingRequest.vat_validated_at,
    }
    : sanitized.vat_number
    ? await validateVatWithVies(sanitized.vat_number)
    : { status: "not_checked", validatedAt: null };

  const approvalToken = await createApprovalTokenForIdempotencyKey(idempotencyKey);
  const approvalTokenHash = await hashApprovalToken(approvalToken);
  const approvalTokenExpiresAt = computeTokenExpiry();

  const userAgentRaw = request.headers.get("user-agent") || "";
  const userAgent = userAgentRaw.slice(0, 500);

  const { data: createData, error: createError } = await supabase.rpc("create_quote_request_idempotent", {
    p_idempotency_key: idempotencyKey,
    p_request_fingerprint: requestFingerprint,
    p_request_kind: sanitized.request_kind,
    p_sdf_package: sanitized.sdf_package,
    p_name: sanitized.name,
    p_customer_type: sanitized.customer_type,
    p_company: sanitized.company,
    p_enterprise_number: sanitized.enterprise_number,
    p_enterprise_validation_status: sanitized.enterprise_validation_status,
    p_vat_number: sanitized.vat_number,
    p_vat_validation_status: vatValidation.status,
    p_vat_validated_at: vatValidation.validatedAt,
    p_billing_address: sanitized.billing_address,
    p_billing_postal_code: sanitized.billing_postal_code,
    p_billing_city: sanitized.billing_city,
    p_billing_country: sanitized.billing_country,
    p_billing_email: sanitized.billing_email,
    p_email: sanitized.email,
    p_phone: sanitized.phone,
    p_website_type: sanitized.website_type,
    p_budget: sanitized.budget,
    p_timing: sanitized.timing,
    p_description: sanitized.description,
    p_privacy_consent: sanitized.privacy_consent,
    p_approval_token_hash: approvalTokenHash,
    p_approval_token_expires_at: approvalTokenExpiresAt,
    p_client_ip_hash: clientIpHash,
    p_user_agent: userAgent,
  });
  const created = Array.isArray(createData) ? createData[0] : createData;

  if (createError || !created) {
    const conflict = createError?.message?.includes("IDEMPOTENCY_CONFLICT");
    return jsonResponse(conflict ? 409 : 500, {
      ok: false,
      code: conflict ? "IDEMPOTENCY_CONFLICT" : "REQUEST_STORAGE_FAILED",
      message: conflict ? "Request key was already used." : "Could not save request.",
    }, origin);
  }

  if (!created.admin_job_id) {
    return jsonResponse(500, {
      ok: false,
      code: "EMAIL_JOB_CREATION_FAILED",
      message: "Could not queue notification.",
    }, origin);
  }

  if (!created.was_created && created.admin_job_status === "failed") {
    await supabase.rpc("requeue_quote_request_email_job", {
      p_job_id: created.admin_job_id,
      p_expected_kind: "admin_notification",
    });
  }

  const reviewUrl = `${siteUrl}/pages/review-request.html?token=${encodeURIComponent(approvalToken)}`;

  const adminEmailPayload = buildAdminNotificationEmail({
    requestId: created.request_id,
    createdAt: created.request_created_at,
    requestKind: sanitized.request_kind,
    name: sanitized.name,
    customerType: sanitized.customer_type,
    company: sanitized.company,
    enterpriseNumber: sanitized.enterprise_number,
    enterpriseValidationStatus: sanitized.enterprise_validation_status,
    vatNumber: sanitized.vat_number,
    vatValidationStatus: vatValidation.status,
    vatValidatedAt: vatValidation.validatedAt,
    billingAddress: sanitized.billing_address,
    billingPostalCode: sanitized.billing_postal_code,
    billingCity: sanitized.billing_city,
    billingCountry: sanitized.billing_country,
    billingEmail: sanitized.billing_email,
    email: sanitized.email,
    phone: sanitized.phone,
    websiteType: sanitized.website_type,
    budget: sanitized.budget,
    timing: sanitized.timing,
    description: sanitized.description,
    reviewUrl,
  });

  const delivery = await deliverEmailJob({
    supabase,
    jobId: created.admin_job_id,
    resendApiKey,
    email: {
      from: fromEmail,
      to: adminEmail,
      subject: adminEmailPayload.subject,
      html: adminEmailPayload.html,
      text: adminEmailPayload.text,
    },
  });

  const notificationSent = delivery.status === "sent";
  return jsonResponse(notificationSent ? 200 : 202, {
    ok: true,
    code: "REQUEST_ACCEPTED",
    message: "Request received.",
    notification_status: delivery.status,
    vat_validation_status: vatValidation.status,
    vat_validated_at: vatValidation.validatedAt,
  }, origin);
});

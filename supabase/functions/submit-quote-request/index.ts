import { createClient } from "npm:@supabase/supabase-js@2";
import { buildAdminNotificationEmail } from "../_shared/email-templates.ts";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { computeTokenExpiry, createRawApprovalToken, extractClientIp, hashApprovalToken, hashClientIp } from "../_shared/security.ts";
import { isRateLimited } from "../_shared/rate-limit.ts";
import { sanitizeAndValidateSubmitPayload } from "../_shared/validation.ts";
import type { SubmitQuotePayload } from "../_shared/types.ts";

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const sanitizeHeaderValue = (value: string) => value.replace(/[\r\n]+/g, "").trim();

function isValidEmail(value: string): boolean {
  return EMAIL_REGEX.test(value);
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
  const resendApiKeyRaw = Deno.env.get("RESEND_API_KEY") || "";
  const adminEmailRaw = Deno.env.get("ADMIN_EMAIL") || "";
  const fromEmailRaw = Deno.env.get("FROM_EMAIL") || "";
  const resendApiKey = sanitizeHeaderValue(resendApiKeyRaw);
  const adminEmail = sanitizeHeaderValue(adminEmailRaw);
  const fromEmail = sanitizeHeaderValue(fromEmailRaw);
  const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";

  if (!supabaseUrl || !serviceRoleKey || !resendApiKey || !adminEmail || !fromEmail) {
    return jsonResponse(500, {
      ok: false,
      message: "Server configuration is incomplete.",
    }, origin);
  }

  if (!isValidEmail(fromEmail) || !isValidEmail(adminEmail)) {
    console.error("resend_config_invalid", {
      step: "resend_request",
      errorType: "ValidationError",
      errorMessage: "Invalid FROM_EMAIL or ADMIN_EMAIL format",
    });

    return jsonResponse(500, {
      ok: false,
      message: "Server configuration is incomplete.",
    }, origin);
  }

  let payload: SubmitQuotePayload;

  try {
    payload = await request.json();
  } catch {
    return jsonResponse(400, {
      ok: false,
      message: "Invalid request payload.",
    }, origin);
  }

  let sanitized;
  try {
    sanitized = sanitizeAndValidateSubmitPayload(payload);
  } catch {
    return jsonResponse(400, {
      ok: false,
      message: "Invalid input.",
    }, origin);
  }

  // Honeypot: return success-shaped response to avoid bot feedback loops.
  if (sanitized.honeypotValue) {
    return jsonResponse(200, {
      ok: true,
      message: "Request received.",
    }, origin);
  }

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

  const rateLimitResult = await isRateLimited(supabase, clientIpHash);

  if (rateLimitResult.error) {
    console.error("rate_limit_internal_error", {
      category: "rate_limit",
      step: "quote_requests_count",
      code: rateLimitResult.errorCode ?? "UNKNOWN_RATE_LIMIT_ERROR",
      message: rateLimitResult.errorMessage ?? "Rate limit check failed",
    });

    return jsonResponse(503, {
      ok: false,
      message: "Service temporarily unavailable.",
    }, origin);
  }

  if (rateLimitResult.limited) {
    return jsonResponse(429, {
      ok: false,
      message: "Too many requests.",
    }, origin);
  }

  const approvalToken = createRawApprovalToken();
  const approvalTokenHash = await hashApprovalToken(approvalToken);
  const approvalTokenExpiresAt = computeTokenExpiry();

  const userAgentRaw = request.headers.get("user-agent") || "";
  const userAgent = userAgentRaw.slice(0, 500);

  const { data: inserted, error: insertError } = await supabase
    .from("quote_requests")
    .insert({
      name: sanitized.name,
      company: sanitized.company,
      email: sanitized.email,
      phone: sanitized.phone,
      website_type: sanitized.website_type,
      budget: sanitized.budget,
      timing: sanitized.timing,
      description: sanitized.description,
      privacy_consent: sanitized.privacy_consent,
      status: "pending",
      approval_token_hash: approvalTokenHash,
      approval_token_expires_at: approvalTokenExpiresAt,
      client_ip_hash: clientIpHash,
      user_agent: userAgent,
    })
    .select("id, created_at")
    .single();

  if (insertError || !inserted) {
    return jsonResponse(500, {
      ok: false,
      message: "Could not save request.",
    }, origin);
  }

  const reviewUrl = `${siteUrl}/pages/review-request.html?token=${encodeURIComponent(approvalToken)}`;

  const adminEmailPayload = buildAdminNotificationEmail({
    requestId: inserted.id,
    createdAt: inserted.created_at,
    name: sanitized.name,
    company: sanitized.company,
    email: sanitized.email,
    phone: sanitized.phone,
    websiteType: sanitized.website_type,
    budget: sanitized.budget,
    timing: sanitized.timing,
    description: sanitized.description,
    reviewUrl,
  });

  let resendResponse: Response;
  try {
    resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [adminEmail],
        subject: adminEmailPayload.subject,
        html: adminEmailPayload.html,
        text: adminEmailPayload.text,
      }),
    });
  } catch (error) {
    const err = error as Error;
    console.error("resend_request_error", {
      step: "resend_request",
      errorType: err.name || "Error",
      errorMessage: err.message || "Resend request failed",
      httpStatus: null,
    });

    return jsonResponse(500, {
      ok: false,
      message: "Could not complete notification step.",
    }, origin);
  }

  if (!resendResponse.ok) {
    console.error("resend_request_error", {
      step: "resend_request",
      errorType: "HttpError",
      errorMessage: "Resend returned non-success status",
      httpStatus: resendResponse.status,
    });

    return jsonResponse(500, {
      ok: false,
      message: "Could not complete notification step.",
    }, origin);
  }

  await supabase
    .from("quote_requests")
    .update({ notification_sent_at: new Date().toISOString() })
    .eq("id", inserted.id)
    .eq("status", "pending");

  return jsonResponse(200, {
    ok: true,
    message: "Request received.",
  }, origin);
});

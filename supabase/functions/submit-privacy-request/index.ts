import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { buildPrivacyRequestNotificationEmail } from "../_shared/privacy-email-template.ts";
import {
  PrivacyRequestValidationError,
  sanitizeAndValidatePrivacyRequest,
} from "../_shared/privacy-validation.ts";
import { extractClientIp, hashClientIp } from "../_shared/security.ts";
import { getSupabaseServerSecretKey } from "../_shared/supabase-key-bindings.ts";

const MAX_BODY_BYTES = 16 * 1024;
const IDEMPOTENCY_KEY_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RESEND_API_URL = "https://api.resend.com/emails";

class RequestError extends Error {
  constructor(public readonly status: number, public readonly code: string) {
    super(code);
    this.name = "RequestError";
  }
}

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
    },
  });
}

async function parseJsonBody(request: Request): Promise<unknown> {
  const contentType = request.headers.get("content-type") || "";
  if (
    contentType.split(";", 1)[0].trim().toLowerCase() !== "application/json"
  ) {
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
    return JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes),
    );
  } catch {
    throw new RequestError(400, "INVALID_JSON");
  }
}

async function fingerprintPayload(
  payload: Record<string, unknown>,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(payload)),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function sanitizeHeaderValue(value: string): string {
  return value.replace(/[\r\n]+/g, "").trim();
}

function resendUrl(): string {
  const configured = Deno.env.get("RESEND_API_URL");
  if (!configured || configured === RESEND_API_URL) return RESEND_API_URL;
  const url = new URL(configured);
  const localAllowed = Deno.env.get("ALLOW_LOCAL_EMAIL_DELIVERY") === "true";
  if (
    !localAllowed ||
    !["127.0.0.1", "localhost", "host.docker.internal"].includes(url.hostname)
  ) {
    throw new Error("Invalid local email delivery URL");
  }
  return url.toString();
}

export async function handleSubmitPrivacyRequest(
  request: Request,
): Promise<Response> {
  const origin = request.headers.get("origin");

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  const blocked = rejectIfOriginNotAllowed(request);
  if (blocked) return blocked;

  if (request.method !== "POST") {
    return jsonResponse(405, {
      ok: false,
      code: "METHOD_NOT_ALLOWED",
      message: "Method not allowed.",
    }, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  let serviceRoleKey;
  try {
    serviceRoleKey = getSupabaseServerSecretKey("default");
  } catch {
    return jsonResponse(500, {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      message: "Service unavailable.",
    }, origin);
  }
  if (!supabaseUrl) {
    return jsonResponse(500, {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      message: "Service unavailable.",
    }, origin);
  }

  let rawPayload: unknown;
  try {
    rawPayload = await parseJsonBody(request);
  } catch (error) {
    const requestError = error instanceof RequestError
      ? error
      : new RequestError(400, "INVALID_REQUEST");
    return jsonResponse(requestError.status, {
      ok: false,
      code: requestError.code,
      message: "Invalid request.",
    }, origin);
  }

  let payload;
  try {
    payload = sanitizeAndValidatePrivacyRequest(rawPayload);
  } catch (error) {
    const code = error instanceof PrivacyRequestValidationError
      ? error.code
      : "INVALID_INPUT";
    const field = error instanceof PrivacyRequestValidationError
      ? error.field
      : undefined;
    return jsonResponse(400, {
      ok: false,
      code,
      ...(field ? { field } : {}),
      message: "Invalid input.",
    }, origin);
  }

  const idempotencyKey = (request.headers.get("idempotency-key") || "").trim();
  if (!IDEMPOTENCY_KEY_REGEX.test(idempotencyKey)) {
    return jsonResponse(400, {
      ok: false,
      code: "INVALID_IDEMPOTENCY_KEY",
      message: "Invalid request.",
    }, origin);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const requestFingerprint = await fingerprintPayload(
    payload as unknown as Record<string, unknown>,
  );
  const { data: existingRequest, error: existingRequestError } = await supabase
    .from("privacy_requests")
    .select("id, request_fingerprint")
    .eq("idempotency_key", idempotencyKey)
    .maybeSingle();

  if (existingRequestError) {
    return jsonResponse(500, {
      ok: false,
      code: "IDEMPOTENCY_LOOKUP_FAILED",
      message: "Could not process request.",
    }, origin);
  }
  if (existingRequest) {
    if (existingRequest.request_fingerprint !== requestFingerprint) {
      return jsonResponse(409, {
        ok: false,
        code: "IDEMPOTENCY_CONFLICT",
        message: "Could not process request.",
      }, origin);
    }
    return jsonResponse(200, {
      ok: true,
      code: "REQUEST_RECEIVED",
      request_id: existingRequest.id,
    }, origin);
  }

  let clientIpHash: string;
  try {
    clientIpHash = await hashClientIp(extractClientIp(request));
  } catch {
    return jsonResponse(500, {
      ok: false,
      code: "REQUEST_SECURITY_ERROR",
      message: "Could not process request.",
    }, origin);
  }

  const configuredWindowSeconds = Number(
    Deno.env.get("PRIVACY_RATE_LIMIT_WINDOW_SECONDS") || "900",
  );
  const configuredMaxRequests = Number(
    Deno.env.get("PRIVACY_RATE_LIMIT_MAX_REQUESTS") || "3",
  );
  const windowSeconds =
    Number.isFinite(configuredWindowSeconds) && configuredWindowSeconds > 0
      ? configuredWindowSeconds
      : 900;
  const maxRequests =
    Number.isFinite(configuredMaxRequests) && configuredMaxRequests > 0
      ? configuredMaxRequests
      : 3;
  const since = new Date(Date.now() - windowSeconds * 1000).toISOString();
  const { count, error: rateLimitError } = await supabase
    .from("privacy_requests")
    .select("id", { count: "exact", head: true })
    .eq("client_ip_hash", clientIpHash)
    .gte("created_at", since);

  if (rateLimitError) {
    console.error("privacy_rate_limit_error", {
      code: rateLimitError.code ?? "UNKNOWN",
    });
    return jsonResponse(503, {
      ok: false,
      code: "RATE_LIMIT_UNAVAILABLE",
      message: "Service temporarily unavailable.",
    }, origin);
  }
  if ((count ?? 0) >= maxRequests) {
    return jsonResponse(429, {
      ok: false,
      code: "RATE_LIMITED",
      message: "Too many requests.",
    }, origin);
  }

  const userAgent = (request.headers.get("user-agent") || "").slice(0, 500);
  const { data, error: createError } = await supabase.rpc(
    "create_privacy_request_idempotent",
    {
      p_idempotency_key: idempotencyKey,
      p_request_fingerprint: requestFingerprint,
      p_name: payload.name,
      p_email: payload.email,
      p_phone: payload.phone,
      p_message: payload.message,
      p_client_ip_hash: clientIpHash,
      p_user_agent: userAgent,
    },
  );
  const created = Array.isArray(data) ? data[0] : data;

  if (createError || !created) {
    const conflict = createError?.message?.includes("IDEMPOTENCY_CONFLICT");
    return jsonResponse(conflict ? 409 : 500, {
      ok: false,
      code: conflict ? "IDEMPOTENCY_CONFLICT" : "REQUEST_STORAGE_FAILED",
      message: "Could not process request.",
    }, origin);
  }

  if (!created.was_created || created.request_notification_status === "sent") {
    return jsonResponse(200, {
      ok: true,
      code: "REQUEST_RECEIVED",
      request_id: created.request_id,
    }, origin);
  }

  const resendApiKey = sanitizeHeaderValue(
    Deno.env.get("RESEND_API_KEY") || "",
  );
  const adminEmail = sanitizeHeaderValue(Deno.env.get("ADMIN_EMAIL") || "");
  const fromEmail = sanitizeHeaderValue(Deno.env.get("FROM_EMAIL") || "");
  let notificationStatus = "failed";
  let notificationErrorCode = "EMAIL_CONFIGURATION_INVALID";
  let providerMessageId: string | null = null;

  if (resendApiKey && adminEmail && fromEmail) {
    const email = buildPrivacyRequestNotificationEmail({
      requestId: created.request_id,
      createdAt: created.request_created_at,
      name: payload.name,
      email: payload.email,
      phone: payload.phone,
      message: payload.message,
    });

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 10_000);
      const response = await fetch(resendUrl(), {
        method: "POST",
        signal: controller.signal,
        headers: {
          Authorization: `Bearer ${resendApiKey}`,
          "Content-Type": "application/json",
          "Idempotency-Key": `privacy-request/${created.request_id}`,
        },
        body: JSON.stringify({ from: fromEmail, to: [adminEmail], ...email }),
      }).finally(() => clearTimeout(timeout));

      if (response.ok) {
        notificationStatus = "sent";
        notificationErrorCode = "";
        try {
          const responseBody = await response.json();
          if (responseBody && typeof responseBody.id === "string") {
            providerMessageId = responseBody.id;
          }
        } catch {
          // A successful provider response without JSON remains successful.
        }
      } else {
        notificationErrorCode = `RESEND_HTTP_${response.status}`;
      }
    } catch (error) {
      notificationErrorCode =
        error instanceof Error && error.name === "AbortError"
          ? "EMAIL_TIMEOUT"
          : "EMAIL_DELIVERY_FAILED";
    }
  }

  const { error: notificationUpdateError } = await supabase
    .from("privacy_requests")
    .update({
      notification_status: notificationStatus,
      notification_attempted_at: new Date().toISOString(),
      notification_error_code: notificationErrorCode || null,
      provider_message_id: providerMessageId,
    })
    .eq("id", created.request_id);

  if (notificationUpdateError) {
    console.error("privacy_notification_status_update_error", {
      code: notificationUpdateError.code ?? "UNKNOWN",
    });
  }

  return jsonResponse(202, {
    ok: true,
    code: notificationStatus === "sent"
      ? "REQUEST_RECEIVED"
      : "REQUEST_STORED_NOTIFICATION_FAILED",
    request_id: created.request_id,
  }, origin);
}

if (import.meta.main) Deno.serve(handleSubmitPrivacyRequest);

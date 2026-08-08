import { createClient } from "npm:@supabase/supabase-js@2";
import { buildApprovedConfirmationEmail } from "../_shared/email-templates.ts";
import { deliverEmailJob } from "../_shared/email-delivery.ts";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { hashApprovalToken } from "../_shared/security.ts";
import { validateAction, validateToken } from "../_shared/validation.ts";
import type { ReviewAction } from "../_shared/types.ts";

type ReviewState = "pending" | "approved" | "rejected" | "expired" | "invalid";
type ReviewRequestDetails = {
  id: string;
  created_at: string;
  name: string;
  company: string | null;
  email: string;
  phone: string | null;
  website_type: string;
  budget: string;
  timing: string;
  description: string;
  reviewed_at?: string | null;
};
const MAX_REVIEW_BODY_BYTES = 4 * 1024;

class ReviewRequestError extends Error {
  constructor(public readonly status: number, public readonly code: string) {
    super(code);
    this.name = "ReviewRequestError";
  }
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

function readReviewToken(request: Request): string {
  const authorization = request.headers.get("authorization") || "";
  const bearerMatch = authorization.match(/^Bearer\s+(.+)$/i);
  if (bearerMatch) return bearerMatch[1];
  return new URL(request.url).searchParams.get("token") || "";
}

function serializeRequest(data: ReviewRequestDetails, reviewedAt = data.reviewed_at ?? null) {
  return {
    id: data.id,
    created_at: data.created_at,
    name: data.name,
    company: data.company,
    email: data.email,
    phone: data.phone,
    website_type: data.website_type,
    budget: data.budget,
    timing: data.timing,
    description: data.description,
    reviewed_at: reviewedAt,
  };
}

async function parseJsonBody(request: Request): Promise<Record<string, unknown>> {
  const contentType = request.headers.get("content-type") || "";
  if (contentType.split(";", 1)[0].trim().toLowerCase() !== "application/json") {
    throw new ReviewRequestError(415, "UNSUPPORTED_CONTENT_TYPE");
  }

  const declaredLength = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_REVIEW_BODY_BYTES) {
    throw new ReviewRequestError(413, "BODY_TOO_LARGE");
  }

  if (!request.body) throw new ReviewRequestError(400, "INVALID_JSON");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    totalBytes += value.byteLength;
    if (totalBytes > MAX_REVIEW_BODY_BYTES) {
      await reader.cancel();
      throw new ReviewRequestError(413, "BODY_TOO_LARGE");
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
    const parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid body");
    return parsed as Record<string, unknown>;
  } catch {
    throw new ReviewRequestError(400, "INVALID_JSON");
  }
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

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("FROM_EMAIL");

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(500, {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      message: "Server configuration is incomplete.",
    }, origin);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (request.method === "GET") {
    const tokenRaw = readReviewToken(request);
    let token: string;

    try {
      token = validateToken(tokenRaw);
    } catch {
      return jsonResponse(200, { ok: true, state: "invalid" satisfies ReviewState }, origin);
    }

    const tokenHash = await hashApprovalToken(token);

    const { data, error } = await supabase
      .from("quote_requests")
      .select("id, created_at, name, company, email, phone, website_type, budget, timing, description, status, approval_token_expires_at, reviewed_at")
      .eq("approval_token_hash", tokenHash)
      .maybeSingle();

    if (error || !data) {
      return jsonResponse(200, { ok: true, state: "invalid" satisfies ReviewState }, origin);
    }

    const now = Date.now();
    const expiresAt = data.approval_token_expires_at ? Date.parse(data.approval_token_expires_at) : 0;

    if (data.status === "pending" && expiresAt > 0 && expiresAt < now) {
      return jsonResponse(200, {
        ok: true,
        state: "expired" satisfies ReviewState,
        request: {
          id: data.id,
          created_at: data.created_at,
        },
      }, origin);
    }

    if (data.status === "approved" || data.status === "rejected") {
      let deliveryStatus: string | null = null;
      if (data.status === "approved") {
        const { data: deliveryJob } = await supabase
          .from("quote_request_email_jobs")
          .select("status")
          .eq("quote_request_id", data.id)
          .eq("kind", "customer_confirmation")
          .maybeSingle();
        deliveryStatus = deliveryJob?.status ?? null;
      }

      return jsonResponse(200, {
        ok: true,
        state: data.status as ReviewState,
        delivery_status: deliveryStatus,
        request: serializeRequest(data),
      }, origin);
    }

    return jsonResponse(200, {
      ok: true,
      state: "pending" satisfies ReviewState,
      request: serializeRequest(data),
    }, origin);
  }

  if (request.method === "POST") {
    let body: Record<string, unknown>;
    try {
      body = await parseJsonBody(request);
    } catch (error) {
      if (error instanceof ReviewRequestError) {
        return jsonResponse(error.status, { ok: false, code: error.code, message: "Invalid request." }, origin);
      }
      return jsonResponse(400, { ok: false, code: "INVALID_REQUEST", message: "Invalid request." }, origin);
    }

    let token: string;
    let action: ReviewAction;

    try {
      token = validateToken(body.token);
      action = validateAction(body.action);
    } catch {
      return jsonResponse(400, { ok: false, code: "INVALID_REVIEW_ACTION", message: "Invalid review action." }, origin);
    }

    const tokenHash = await hashApprovalToken(token);

    const { data: existing, error: fetchError } = await supabase
      .from("quote_requests")
      .select("id, created_at, name, company, email, phone, website_type, budget, timing, description, status, approval_token_expires_at, reviewed_at")
      .eq("approval_token_hash", tokenHash)
      .maybeSingle();

    if (fetchError || !existing) {
      return jsonResponse(200, { ok: true, state: "invalid" satisfies ReviewState }, origin);
    }

    const expiresAt = existing.approval_token_expires_at ? Date.parse(existing.approval_token_expires_at) : 0;

    if ((existing.status === "pending" || action === "retry_confirmation") && expiresAt > 0 && expiresAt < Date.now()) {
      return jsonResponse(200, { ok: true, state: "expired" satisfies ReviewState }, origin);
    }

    if (action === "retry_confirmation" && existing.status !== "approved") {
      return jsonResponse(409, {
        ok: false,
        code: "CONFIRMATION_NOT_RETRYABLE",
        state: existing.status as ReviewState,
        message: "Confirmation is not retryable for this request.",
      }, origin);
    }

    const databaseAction = action === "retry_confirmation" ? "approved" : action;
    const { data: transitionData, error: transitionError } = await supabase.rpc("transition_quote_request_review", {
      p_token_hash: tokenHash,
      p_action: databaseAction,
    });
    const transition = Array.isArray(transitionData) ? transitionData[0] : transitionData;

    if (transitionError) {
      return jsonResponse(500, {
        ok: false,
        code: "REVIEW_TRANSITION_FAILED",
        message: "Review action could not be completed.",
      }, origin);
    }
    if (!transition) {
      return jsonResponse(200, { ok: true, state: "expired" satisfies ReviewState }, origin);
    }

    if (transition.review_status === "approved") {
      if (!transition.confirmation_job_id) {
        return jsonResponse(200, {
          ok: true,
          code: "REQUEST_APPROVED_CONFIRMATION_PENDING",
          state: "approved" satisfies ReviewState,
          mail_sent: false,
          delivery_status: "failed",
          request: serializeRequest(existing, transition.reviewed_at),
        }, origin);
      }

      if (action === "retry_confirmation") {
        const { error: requeueError } = await supabase.rpc("requeue_quote_request_email_job", {
          p_job_id: transition.confirmation_job_id,
          p_expected_kind: "customer_confirmation",
        });
        if (requeueError) {
          return jsonResponse(500, {
            ok: false,
            code: "CONFIRMATION_REQUEUE_FAILED",
            state: "approved" satisfies ReviewState,
            message: "Confirmation retry could not be scheduled.",
          }, origin);
        }
      }

      const confirmationEmail = buildApprovedConfirmationEmail(transition.request_name);
      const delivery = await deliverEmailJob({
        supabase,
        jobId: transition.confirmation_job_id,
        resendApiKey: resendApiKey || "",
        email: {
          from: fromEmail || "",
          to: transition.request_email,
          subject: confirmationEmail.subject,
          html: confirmationEmail.html,
          text: confirmationEmail.text,
        },
      });

      return jsonResponse(200, {
        ok: true,
        state: "approved" satisfies ReviewState,
        mail_sent: delivery.status === "sent",
        delivery_status: delivery.status,
        request: serializeRequest(existing, transition.reviewed_at),
      }, origin);
    }

    return jsonResponse(200, {
      ok: true,
      state: "rejected" satisfies ReviewState,
      mail_sent: false,
      request: { id: transition.request_id, reviewed_at: transition.reviewed_at },
    }, origin);
  }

  return jsonResponse(405, { ok: false, message: "Method not allowed." }, origin);
});

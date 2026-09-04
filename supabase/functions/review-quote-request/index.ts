import { createClient } from "npm:@supabase/supabase-js@2";
import { buildApprovedConfirmationEmail, buildIntakeInvitationEmail } from "../_shared/email-templates.ts";
import { deliverEmailJob } from "../_shared/email-delivery.ts";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import {
  createRawIntakeToken,
  decryptIntakeInvitationToken,
  encryptIntakeInvitationToken,
  hashApprovalToken,
  hashIntakeToken,
} from "../_shared/security.ts";
import { validateAction, validateToken } from "../_shared/validation.ts";
import type { ReviewAction } from "../_shared/types.ts";
import { allowsWebsiteLifecycle } from "../_shared/request-kind.ts";
import {
  getSupabaseServerSecretKey,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";

type ReviewState = "pending" | "approved" | "rejected" | "expired" | "invalid";
type ReviewRequestDetails = {
  id: string;
  created_at: string;
  request_kind: "website" | "slimme_documentenflow";
  name: string;
  customer_type: string | null;
  company: string | null;
  enterprise_number: string | null;
  enterprise_validation_status: string;
  vat_number: string | null;
  vat_validation_status: string;
  vat_validated_at: string | null;
  billing_address: string | null;
  billing_postal_code: string | null;
  billing_city: string | null;
  billing_country: string | null;
  billing_email: string | null;
  email: string;
  phone: string | null;
  website_type: string | null;
  budget: string | null;
  timing: string | null;
  description: string;
  reviewed_at?: string | null;
};
const MAX_REVIEW_BODY_BYTES = 4 * 1024;

export function resolveReviewQuoteRequestConfiguration(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
): { url: string; serviceRoleKey: string } | null {
  const url = environment.get("SUPABASE_URL");
  if (!url) return null;
  try {
    return {
      url,
      serviceRoleKey: getSupabaseServerSecretKey("default", environment),
    };
  } catch {
    return null;
  }
}

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
    request_kind: data.request_kind,
    name: data.name,
    customer_type: data.customer_type,
    company: data.company,
    enterprise_number: data.enterprise_number,
    enterprise_validation_status: data.enterprise_validation_status,
    vat_number: data.vat_number,
    vat_validation_status: data.vat_validation_status,
    vat_validated_at: data.vat_validated_at,
    billing_address: data.billing_address,
    billing_postal_code: data.billing_postal_code,
    billing_city: data.billing_city,
    billing_country: data.billing_country,
    billing_email: data.billing_email,
    email: data.email,
    phone: data.phone,
    website_type: data.website_type,
    budget: data.budget,
    timing: data.timing,
    description: data.description,
    reviewed_at: reviewedAt,
  };
}

function buildIntakeUrl(rawToken: string): string {
  const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";
  const url = new URL("/pages/intake.html", siteUrl);
  url.searchParams.set("token", rawToken);
  return url.toString();
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

export async function handleReviewQuoteRequest(request: Request): Promise<Response> {
  const origin = request.headers.get("origin");

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(origin),
    });
  }

  const blocked = rejectIfOriginNotAllowed(request);
  if (blocked) return blocked;

  const configuration = resolveReviewQuoteRequestConfiguration();
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("FROM_EMAIL");

  if (!configuration) {
    return jsonResponse(500, {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      message: "Server configuration is incomplete.",
    }, origin);
  }

  const supabase = createClient(configuration.url, configuration.serviceRoleKey, {
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
      .select("id, created_at, request_kind, name, customer_type, company, enterprise_number, enterprise_validation_status, vat_number, vat_validation_status, vat_validated_at, billing_address, billing_postal_code, billing_city, billing_country, billing_email, email, phone, website_type, budget, timing, description, status, approval_token_expires_at, reviewed_at")
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
      let intakeExists = false;
      let intakeStatus: string | null = null;
      let intakeInvitationExists = false;
      let intakeInvitationDeliveryStatus: string | null = null;
      if (data.status === "approved") {
        const [confirmationResult, intakeResult, invitationResult] = await Promise.all([
          supabase
            .from("quote_request_email_jobs")
            .select("status")
            .eq("quote_request_id", data.id)
            .eq("kind", "customer_confirmation")
            .maybeSingle(),
          supabase
            .from("quote_request_intakes")
            .select("status")
            .eq("quote_request_id", data.id)
            .maybeSingle(),
          supabase
            .from("quote_request_email_jobs")
            .select("status")
            .eq("quote_request_id", data.id)
            .eq("kind", "intake_invitation")
            .maybeSingle(),
        ]);

        if (confirmationResult.error || intakeResult.error || invitationResult.error) {
          return jsonResponse(500, {
            ok: false,
            code: "REVIEW_STATE_LOOKUP_FAILED",
            message: "Review state could not be loaded.",
          }, origin);
        }

        const deliveryJob = confirmationResult.data;
        const intake = intakeResult.data;
        const invitationJob = invitationResult.data;
        deliveryStatus = deliveryJob?.status ?? null;
        intakeExists = intake !== null;
        intakeStatus = intake?.status ?? null;
        intakeInvitationExists = invitationJob !== null;
        intakeInvitationDeliveryStatus = invitationJob?.status ?? null;
      }

      return jsonResponse(200, {
        ok: true,
        state: data.status as ReviewState,
        delivery_status: deliveryStatus,
        intake_exists: intakeExists,
        intake_status: intakeStatus,
        intake_invitation_exists: intakeInvitationExists,
        intake_invitation_delivery_status: intakeInvitationDeliveryStatus,
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
      .select("id, created_at, request_kind, name, customer_type, company, enterprise_number, enterprise_validation_status, vat_number, vat_validation_status, vat_validated_at, billing_address, billing_postal_code, billing_city, billing_country, billing_email, email, phone, website_type, budget, timing, description, status, approval_token_expires_at, reviewed_at")
      .eq("approval_token_hash", tokenHash)
      .maybeSingle();

    if (fetchError || !existing) {
      return jsonResponse(200, { ok: true, state: "invalid" satisfies ReviewState }, origin);
    }

    if (!allowsWebsiteLifecycle(existing.request_kind)) {
      return jsonResponse(409, {
        ok: false,
        code: "REQUEST_KIND_ACTION_NOT_ALLOWED",
        state: existing.status as ReviewState,
        message: "Website review actions are not available for this request kind.",
        request: serializeRequest(existing),
      }, origin);
    }

    const expiresAt = existing.approval_token_expires_at ? Date.parse(existing.approval_token_expires_at) : 0;

    if (
      (existing.status === "pending" ||
        action === "retry_confirmation" ||
        action === "send_intake_invitation" ||
        action === "retry_intake_invitation") &&
      expiresAt > 0 && expiresAt < Date.now()
    ) {
      return jsonResponse(200, { ok: true, state: "expired" satisfies ReviewState }, origin);
    }

    if (action === "send_intake_invitation" || action === "retry_intake_invitation") {
      if (existing.status !== "approved") {
        return jsonResponse(409, {
          ok: false,
          code: "INTAKE_INVITATION_NOT_ALLOWED",
          state: existing.status as ReviewState,
          invitation_outcome: "not_allowed",
          message: "Intake invitation is not allowed for this request.",
        }, origin);
      }

      let invitation: Record<string, unknown> | null = null;
      let rawIntakeToken: string;

      if (action === "send_intake_invitation") {
        rawIntakeToken = createRawIntakeToken();
        const intakeTokenHash = await hashIntakeToken(rawIntakeToken);
        const encryptedToken = await encryptIntakeInvitationToken(rawIntakeToken, intakeTokenHash);
        const { data, error } = await supabase.rpc("create_quote_request_intake_invitation", {
          p_approval_token_hash: tokenHash,
          p_access_token_hash: intakeTokenHash,
          p_encrypted_token: encryptedToken,
        });
        invitation = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;

        if (error || !invitation) {
          return jsonResponse(500, {
            ok: false,
            code: "INTAKE_INVITATION_CREATE_FAILED",
            message: "Intake invitation could not be created.",
          }, origin);
        }
        if (invitation.outcome === "not_allowed") {
          return jsonResponse(409, {
            ok: false,
            code: "INTAKE_INVITATION_NOT_ALLOWED",
            state: "approved" satisfies ReviewState,
            invitation_outcome: "not_allowed",
            message: "Intake invitation is not allowed for this request.",
          }, origin);
        }
        if (invitation.outcome === "already_invited") {
          return jsonResponse(200, {
            ok: true,
            state: "approved" satisfies ReviewState,
            invitation_outcome: "already_invited",
            delivery_status: invitation.invitation_job_status ?? null,
            request: serializeRequest(existing),
          }, origin);
        }
        if (invitation.outcome !== "invitation_created") {
          return jsonResponse(409, {
            ok: false,
            code: "INTAKE_INVITATION_NOT_DELIVERABLE",
            state: "approved" satisfies ReviewState,
            invitation_outcome: invitation.outcome,
            message: "Existing intake cannot be invited again.",
          }, origin);
        }
      } else {
        const { data, error } = await supabase.rpc("get_quote_request_intake_invitation", {
          p_approval_token_hash: tokenHash,
        });
        invitation = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
        if (error || !invitation || invitation.outcome === "not_allowed") {
          return jsonResponse(409, {
            ok: false,
            code: "INTAKE_INVITATION_NOT_ALLOWED",
            state: "approved" satisfies ReviewState,
            invitation_outcome: "not_allowed",
            message: "Intake invitation retry is not allowed.",
          }, origin);
        }
        if (invitation.outcome === "already_invited") {
          return jsonResponse(200, {
            ok: true,
            state: "approved" satisfies ReviewState,
            invitation_outcome: "already_invited",
            delivery_status: invitation.invitation_job_status ?? null,
            request: serializeRequest(existing),
          }, origin);
        }
        if (
          invitation.outcome !== "retryable" ||
          typeof invitation.encrypted_token !== "string" ||
          typeof invitation.access_token_hash !== "string"
        ) {
          return jsonResponse(409, {
            ok: false,
            code: "INTAKE_INVITATION_NOT_DELIVERABLE",
            state: "approved" satisfies ReviewState,
            invitation_outcome: "not_deliverable",
            message: "Intake invitation cannot be retried.",
          }, origin);
        }
        try {
          rawIntakeToken = await decryptIntakeInvitationToken(
            invitation.encrypted_token,
            invitation.access_token_hash,
          );
        } catch {
          return jsonResponse(500, {
            ok: false,
            code: "INTAKE_INVITATION_DECRYPT_FAILED",
            message: "Intake invitation could not be prepared.",
          }, origin);
        }

        if (invitation.invitation_job_status === "failed" || invitation.invitation_job_status === "retry_wait") {
          const { data: requeued, error: requeueError } = await supabase.rpc("requeue_quote_request_email_job", {
            p_job_id: invitation.invitation_job_id,
            p_expected_kind: "intake_invitation",
          });
          if (requeueError || requeued !== true) {
            return jsonResponse(500, {
              ok: false,
              code: "INTAKE_INVITATION_REQUEUE_FAILED",
              message: "Intake invitation retry could not be scheduled.",
            }, origin);
          }
        }
      }

      if (
        typeof invitation.invitation_job_id !== "string" ||
        typeof invitation.request_name !== "string" ||
        typeof invitation.request_email !== "string"
      ) {
        return jsonResponse(500, {
          ok: false,
          code: "INTAKE_INVITATION_INVALID_STATE",
          message: "Intake invitation could not be prepared.",
        }, origin);
      }

      const intakeEmail = buildIntakeInvitationEmail({
        clientName: invitation.request_name,
        company: typeof invitation.request_company === "string" ? invitation.request_company : null,
        requestId: existing.id,
        intakeUrl: buildIntakeUrl(rawIntakeToken),
      });
      const delivery = await deliverEmailJob({
        supabase,
        jobId: invitation.invitation_job_id,
        resendApiKey: resendApiKey || "",
        email: {
          from: fromEmail || "",
          to: invitation.request_email,
          subject: intakeEmail.subject,
          html: intakeEmail.html,
          text: intakeEmail.text,
        },
      });

      return jsonResponse(200, {
        ok: true,
        state: "approved" satisfies ReviewState,
        invitation_outcome: action === "send_intake_invitation" ? "invitation_created" : "invitation_retried",
        mail_sent: delivery.status === "sent",
        delivery_status: delivery.status,
        request: serializeRequest(existing),
      }, origin);
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

      const confirmationEmail = buildApprovedConfirmationEmail({
        clientName: transition.request_name,
        requestId: existing.id,
        createdAt: existing.created_at,
        websiteType: existing.website_type || "Website",
      });
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
}

if (import.meta.main) Deno.serve(handleReviewQuoteRequest);

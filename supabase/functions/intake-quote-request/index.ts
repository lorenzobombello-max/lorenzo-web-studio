import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { buildAuthoritativeSubmitData } from "../_shared/authoritative-intake.ts";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { deliverEmailJob } from "../_shared/email-delivery.ts";
import { buildSubmittedIntakeAdminEmail } from "../_shared/email-templates.ts";
import {
  resolveBudgetEvidence,
  selectPricingSnapshotForSubmit,
  type PricingSnapshotV2,
} from "../_shared/pricing-engine.ts";
import { createPricingSnapshotIntegrity } from "../_shared/pricing-snapshot-integrity.ts";
import { dispatchPricingRead } from "../_shared/pricing-read-dispatch.ts";
import {
  buildAdminIntakeUrl,
  computeAdminIntakeTokenExpiry,
  createRawIntakeToken,
  deriveAdminIntakeCapability,
  hashAdminIntakeToken,
  hashApprovalToken,
  hashIntakeToken,
} from "../_shared/security.ts";
import type { EmailJobStatus, IntakeAction, IntakeStatus } from "../_shared/types.ts";
import {
  InputValidationError,
  partitionIntakeData,
  sanitizeAndValidateIntakeData,
  validateToken,
} from "../_shared/validation.ts";

const MAX_INTAKE_BODY_BYTES = 32 * 1024;

class IntakeRequestError extends Error {
  constructor(public readonly status: number, public readonly code: string) {
    super(code);
    this.name = "IntakeRequestError";
  }
}

function jsonResponse(status: number, body: Record<string, unknown>, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
}

async function parseJsonBody(request: Request): Promise<Record<string, unknown>> {
  const contentType = request.headers.get("content-type") || "";
  if (contentType.split(";", 1)[0].trim().toLowerCase() !== "application/json") {
    throw new IntakeRequestError(415, "UNSUPPORTED_CONTENT_TYPE");
  }

  const declaredLength = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_INTAKE_BODY_BYTES) {
    throw new IntakeRequestError(413, "BODY_TOO_LARGE");
  }

  if (!request.body) throw new IntakeRequestError(400, "INVALID_JSON");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    totalBytes += value.byteLength;
    if (totalBytes > MAX_INTAKE_BODY_BYTES) {
      await reader.cancel();
      throw new IntakeRequestError(413, "BODY_TOO_LARGE");
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
    throw new IntakeRequestError(400, "INVALID_JSON");
  }
}

function validateAction(value: unknown): IntakeAction {
  if (
    value === "create" ||
    value === "inspect" ||
    value === "save_draft" ||
    value === "submit" ||
    value === "inspect_submitted_intake_admin" ||
    value === "inspect_customer_pricing" ||
    value === "inspect_admin_pricing"
  ) return value;
  throw new IntakeRequestError(400, "INVALID_ACTION");
}

function isIntakeStatus(value: unknown): value is IntakeStatus {
  return value === "invited" || value === "in_progress" || value === "submitted" || value === "reviewed";
}

function isEmailJobStatus(value: unknown): value is EmailJobStatus {
  return value === "pending" || value === "processing" || value === "sent" || value === "retry_wait" || value === "failed";
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function invalidIntakeToken(origin: string | null): Response {
  return jsonResponse(401, {
    ok: false,
    code: "INVALID_INTAKE_TOKEN",
    message: "Intake link is invalid or unavailable.",
  }, origin);
}

interface SubmittedIntakeNotificationContext {
  requestId: string;
  clientName: string;
  company: string | null;
  submittedAt: string;
}

interface AuthoritativePricingContext {
  intakeId: string;
  intakeStatus: IntakeStatus;
  effectiveEvidence: Record<string, unknown>;
  budgetLabel: unknown;
  budgetScheme: unknown;
  budgetCode: unknown;
  existingSnapshot: Record<string, unknown> | null;
}

async function loadAuthoritativePricingContext(
  supabase: SupabaseClient,
  intakeTokenHash: string,
  submittedData: Record<string, unknown>,
): Promise<AuthoritativePricingContext | null> {
  const { data: inspectionData, error: inspectionError } = await supabase.rpc(
    "inspect_quote_request_intake_details_v3",
    { p_access_token_hash: intakeTokenHash },
  );
  const inspection = Array.isArray(inspectionData) ? inspectionData[0] : null;
  if (
    inspectionError || !inspection || !isIntakeStatus(inspection.intake_status)
  ) return null;

  const storedEvidence = inspection.intake_data &&
      typeof inspection.intake_data === "object" &&
      !Array.isArray(inspection.intake_data)
    ? inspection.intake_data as Record<string, unknown>
    : {};
  const effectiveEvidence = buildAuthoritativeSubmitData(
    storedEvidence,
    submittedData,
  );
  const existingSnapshot = inspection.pricing_snapshot &&
      typeof inspection.pricing_snapshot === "object" &&
      !Array.isArray(inspection.pricing_snapshot)
    ? inspection.pricing_snapshot as Record<string, unknown>
    : null;

  const { data: intake, error: intakeError } = await supabase
    .from("quote_request_intakes")
    .select("quote_request_id")
    .eq("id", inspection.intake_id)
    .eq("access_token_hash", intakeTokenHash)
    .maybeSingle();
  if (intakeError || !intake || !isUuid(intake.quote_request_id)) return null;

  const { data: quoteRequest, error: requestError } = await supabase
    .from("quote_requests")
    .select("budget, budget_category_scheme, budget_category_code")
    .eq("id", intake.quote_request_id)
    .maybeSingle();
  if (requestError || !quoteRequest) return null;

  const hasBudgetUpdate = typeof effectiveEvidence.budget_update_category ===
      "string" && effectiveEvidence.budget_update_category.length > 0;
  return {
    intakeId: inspection.intake_id,
    intakeStatus: inspection.intake_status,
    effectiveEvidence,
    budgetLabel: hasBudgetUpdate
      ? effectiveEvidence.budget_update_category
      : quoteRequest.budget,
    budgetScheme: hasBudgetUpdate
      ? effectiveEvidence.budget_update_category_scheme
      : quoteRequest.budget_category_scheme,
    budgetCode: hasBudgetUpdate
      ? effectiveEvidence.budget_update_category_code
      : quoteRequest.budget_category_code,
    existingSnapshot,
  };
}

async function loadSubmittedIntakeNotificationContext(
  supabase: SupabaseClient,
  intakeTokenHash: string,
): Promise<SubmittedIntakeNotificationContext | null> {
  const { data: intake, error: intakeError } = await supabase
    .from("quote_request_intakes")
    .select("quote_request_id, status, submitted_at")
    .eq("access_token_hash", intakeTokenHash)
    .maybeSingle();

  if (
    intakeError ||
    !intake ||
    intake.status !== "submitted" ||
    !isUuid(intake.quote_request_id) ||
    typeof intake.submitted_at !== "string"
  ) return null;

  const { data: quoteRequest, error: requestError } = await supabase
    .from("quote_requests")
    .select("id, name, company")
    .eq("id", intake.quote_request_id)
    .maybeSingle();

  if (
    requestError ||
    !quoteRequest ||
    quoteRequest.id !== intake.quote_request_id ||
    typeof quoteRequest.name !== "string" ||
    (quoteRequest.company !== null && typeof quoteRequest.company !== "string")
  ) return null;

  return {
    requestId: quoteRequest.id,
    clientName: quoteRequest.name,
    company: quoteRequest.company,
    submittedAt: intake.submitted_at,
  };
}

async function processSubmittedIntakeNotification(
  supabase: SupabaseClient,
  jobId: string,
  jobStatus: EmailJobStatus,
  intakeTokenHash: string,
  rawAdminCapability: string,
): Promise<EmailJobStatus> {
  if (jobStatus === "sent" || jobStatus === "failed") return jobStatus;

  const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
  const adminEmail = Deno.env.get("ADMIN_EMAIL") || "";
  const fromEmail = Deno.env.get("FROM_EMAIL") || "";
  if (!resendApiKey || !adminEmail || !fromEmail) return jobStatus;

  try {
    const context = await loadSubmittedIntakeNotificationContext(supabase, intakeTokenHash);
    if (!context) return jobStatus;

    const emailPayload = buildSubmittedIntakeAdminEmail({
      clientName: context.clientName,
      company: context.company,
      requestId: context.requestId,
      submittedAt: context.submittedAt,
      adminUrl: buildAdminIntakeUrl(rawAdminCapability),
    });
    const delivery = await deliverEmailJob({
      supabase,
      jobId,
      resendApiKey,
      email: {
        from: fromEmail,
        to: adminEmail,
        subject: emailPayload.subject,
        html: emailPayload.html,
        text: emailPayload.text,
      },
    });
    return delivery.status;
  } catch {
    return jobStatus;
  }
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  const blocked = rejectIfOriginNotAllowed(request);
  if (blocked) return blocked;

  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, code: "METHOD_NOT_ALLOWED", message: "Method not allowed." }, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey || !Deno.env.get("APPROVAL_TOKEN_SECRET")) {
    return jsonResponse(500, {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      message: "Server configuration is incomplete.",
    }, origin);
  }

  let body: Record<string, unknown>;
  let action: IntakeAction;
  try {
    body = await parseJsonBody(request);
    action = validateAction(body.action);
  } catch (error) {
    if (error instanceof IntakeRequestError) {
      return jsonResponse(error.status, { ok: false, code: error.code, message: "Invalid request." }, origin);
    }
    return jsonResponse(400, { ok: false, code: "INVALID_REQUEST", message: "Invalid request." }, origin);
  }

  if (
    (action === "submit" || action === "inspect_submitted_intake_admin" ||
      action === "inspect_admin_pricing") &&
    !Deno.env.get("ADMIN_INTAKE_TOKEN_SECRET")
  ) {
    return jsonResponse(500, {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      message: "Server configuration is incomplete.",
    }, origin);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (action === "inspect_admin_pricing") {
    return await dispatchPricingRead("admin", body.token, origin, supabase);
  }

  if (action === "inspect_customer_pricing") {
    return await dispatchPricingRead("customer", body.token, origin, supabase);
  }

  if (action === "inspect_submitted_intake_admin") {
    let adminToken: string;
    let adminTokenHash: string;
    try {
      adminToken = validateToken(body.token);
      adminTokenHash = await hashAdminIntakeToken(adminToken);
    } catch {
      return jsonResponse(401, {
        ok: false,
        code: "INVALID_ADMIN_CAPABILITY",
        message: "Admin briefing is unavailable.",
      }, origin);
    }

    const { data, error } = await supabase.rpc("inspect_submitted_intake_for_admin", {
      p_admin_access_token_hash: adminTokenHash,
    });
    const result = Array.isArray(data) ? data[0] : null;

    if (error) {
      return jsonResponse(500, {
        ok: false,
        code: "ADMIN_INTAKE_INSPECT_FAILED",
        message: "Admin briefing could not be inspected.",
      }, origin);
    }

    if (!result) {
      return jsonResponse(401, {
        ok: false,
        code: "INVALID_ADMIN_CAPABILITY",
        message: "Admin briefing is unavailable.",
      }, origin);
    }

    if (result.intake_status !== "submitted") {
      return jsonResponse(500, {
        ok: false,
        code: "INVALID_ADMIN_INTAKE_STATE",
        message: "Admin briefing could not be inspected.",
      }, origin);
    }

    const { data: businessDetails, error: businessDetailsError } = await supabase
      .from("quote_requests")
      .select("customer_type, company, enterprise_number, enterprise_validation_status, vat_number, vat_validation_status, vat_validated_at, billing_address, billing_postal_code, billing_city, billing_country, billing_email")
      .eq("id", result.quote_request_id)
      .maybeSingle();
    if (businessDetailsError || !businessDetails) {
      return jsonResponse(500, {
        ok: false,
        code: "ADMIN_BUSINESS_DETAILS_LOOKUP_FAILED",
        message: "Admin briefing could not be inspected.",
      }, origin);
    }

    return jsonResponse(200, {
      ok: true,
      intake: {
        id: result.intake_id,
        status: result.intake_status,
        started_at: result.started_at,
        submitted_at: result.submitted_at,
        reviewed_at: result.reviewed_at,
      },
      request: {
        id: result.quote_request_id,
        created_at: result.quote_request_created_at,
        name: result.name,
        customer_type: businessDetails.customer_type,
        company: businessDetails.company,
        enterprise_number: businessDetails.enterprise_number,
        enterprise_validation_status: businessDetails.enterprise_validation_status,
        vat_number: businessDetails.vat_number,
        vat_validation_status: businessDetails.vat_validation_status,
        vat_validated_at: businessDetails.vat_validated_at,
        billing_address: businessDetails.billing_address,
        billing_postal_code: businessDetails.billing_postal_code,
        billing_city: businessDetails.billing_city,
        billing_country: businessDetails.billing_country,
        billing_email: businessDetails.billing_email,
        email: result.email,
        phone: result.phone,
        website_type: result.website_type,
        budget: result.budget,
        timing: result.timing,
        description: result.description,
      },
      data: result.intake_data && typeof result.intake_data === "object" && !Array.isArray(result.intake_data)
        ? result.intake_data
        : {},
    }, origin);
  }

  if (action === "create") {
    let approvalToken: string;
    try {
      approvalToken = validateToken(body.approval_token);
    } catch {
      return jsonResponse(404, {
        ok: false,
        code: "INTAKE_NOT_AVAILABLE",
        message: "Intake cannot be created for this request.",
      }, origin);
    }

    const rawIntakeToken = createRawIntakeToken();
    const [approvalTokenHash, intakeTokenHash] = await Promise.all([
      hashApprovalToken(approvalToken),
      hashIntakeToken(rawIntakeToken),
    ]);
    const { data, error } = await supabase.rpc("create_quote_request_intake", {
      p_approval_token_hash: approvalTokenHash,
      p_access_token_hash: intakeTokenHash,
    });
    const result = Array.isArray(data) ? data[0] : null;

    if (error) {
      return jsonResponse(500, {
        ok: false,
        code: "INTAKE_CREATE_FAILED",
        message: "Intake could not be created.",
      }, origin);
    }

    if (result?.outcome === "already_exists") {
      return jsonResponse(409, {
        ok: false,
        code: "INTAKE_ALREADY_EXISTS",
        message: "Intake already exists.",
      }, origin);
    }

    if (result?.outcome !== "created") {
      return jsonResponse(404, {
        ok: false,
        code: "INTAKE_NOT_AVAILABLE",
        message: "Intake cannot be created for this request.",
      }, origin);
    }

    return jsonResponse(201, {
      ok: true,
      state: "created",
      intake: {
        id: result.intake_id,
        status: "invited" satisfies IntakeStatus,
        access_token: rawIntakeToken,
        access_token_expires_at: result.access_token_expires_at,
      },
    }, origin);
  }

  let intakeToken: string;
  try {
    intakeToken = validateToken(body.token);
  } catch {
    return invalidIntakeToken(origin);
  }

  const intakeTokenHash = await hashIntakeToken(intakeToken);
  if (action === "inspect") {
    const { data, error } = await supabase.rpc("inspect_quote_request_intake_details_v2", {
      p_access_token_hash: intakeTokenHash,
    });
    const result = Array.isArray(data) ? data[0] : null;

    if (error) {
      return jsonResponse(500, {
        ok: false,
        code: "INTAKE_INSPECT_FAILED",
        message: "Intake could not be inspected.",
      }, origin);
    }

    if (!result) return invalidIntakeToken(origin);
    if (!isIntakeStatus(result.intake_status)) {
      return jsonResponse(500, {
        ok: false,
        code: "INVALID_INTAKE_STATE",
        message: "Intake could not be inspected.",
      }, origin);
    }

    return jsonResponse(200, {
      ok: true,
      intake: {
        id: result.intake_id,
        status: result.intake_status,
        started_at: result.started_at,
        submitted_at: result.submitted_at,
        reviewed_at: result.reviewed_at,
      },
      request: {
        created_at: result.quote_request_created_at,
        name: result.name,
        company: result.company,
        email: result.email,
        phone: result.phone,
        website_type: result.website_type,
        budget: result.budget,
        timing: result.timing,
        description: result.description,
      },
      data: result.intake_data && typeof result.intake_data === "object" && !Array.isArray(result.intake_data)
        ? result.intake_data
        : {},
    }, origin);
  }

  let intakeData: Record<string, unknown>;
  try {
    intakeData = sanitizeAndValidateIntakeData(body.data, action === "submit" ? "submit" : "draft");
  } catch (error) {
    if (error instanceof InputValidationError) {
      return jsonResponse(400, {
        ok: false,
        code: "INVALID_INTAKE_DATA",
        field: error.field,
        message: "Intake data is invalid.",
      }, origin);
    }
    return jsonResponse(400, {
      ok: false,
      code: "INVALID_INTAKE_DATA",
      message: "Intake data is invalid.",
    }, origin);
  }

  const { legacyData, evidenceData } = partitionIntakeData(intakeData);
  const hasEvidence = Object.keys(evidenceData).length > 0;
  let mutationRpc: string;
  let mutationParameters: Record<string, unknown>;
  let rawAdminCapability: string | null = null;

  if (action === "submit") {
    const pricingContext = await loadAuthoritativePricingContext(
      supabase,
      intakeTokenHash,
      intakeData,
    );
    if (!pricingContext) return invalidIntakeToken(origin);

    let existingSnapshot: Record<string, unknown> | null = null;
    if (pricingContext.intakeStatus === "submitted") {
      if (!pricingContext.existingSnapshot) {
        return jsonResponse(500, {
          ok: false,
          code: "AUTHORITATIVE_SNAPSHOT_UNAVAILABLE",
          message: "Submitted intake pricing is unavailable.",
        }, origin);
      }
      existingSnapshot = pricingContext.existingSnapshot;
    }
    const budgetEvidence = resolveBudgetEvidence(
      pricingContext.budgetLabel,
      pricingContext.budgetScheme,
      pricingContext.budgetCode,
    );
    const pricingSnapshot: PricingSnapshotV2 | Record<string, unknown> =
      await selectPricingSnapshotForSubmit(
        pricingContext.effectiveEvidence,
        budgetEvidence,
        existingSnapshot,
      );

    try {
      const pricingSnapshotIntegrity = await createPricingSnapshotIntegrity(
        pricingSnapshot,
        pricingContext.intakeId,
      );
      rawAdminCapability = await deriveAdminIntakeCapability(intakeTokenHash);
      mutationParameters = {
        p_access_token_hash: intakeTokenHash,
        p_action: action,
        p_data: pricingContext.effectiveEvidence,
        p_admin_access_token_hash: await hashAdminIntakeToken(
          rawAdminCapability,
        ),
        p_admin_access_token_expires_at: computeAdminIntakeTokenExpiry(),
        p_budget_guard_snapshot: pricingSnapshot,
        p_pricing_snapshot_integrity: pricingSnapshotIntegrity,
      };
      mutationRpc = "update_quote_request_intake_v4";
    } catch {
      return jsonResponse(500, {
        ok: false,
        code: "SERVER_CONFIGURATION_ERROR",
        message: "Server configuration is incomplete.",
      }, origin);
    }
  } else {
    mutationParameters = hasEvidence ? {
      p_access_token_hash: intakeTokenHash,
      p_action: action,
      p_legacy_data: legacyData,
      p_evidence_data: evidenceData,
    } : {
      p_access_token_hash: intakeTokenHash,
      p_action: action,
      p_data: intakeData,
    };
    mutationRpc = hasEvidence
      ? "update_quote_request_intake_with_evidence"
      : "update_quote_request_intake";
  }

  const { data, error } = await supabase.rpc(mutationRpc, mutationParameters);
  const result = Array.isArray(data) ? data[0] : null;

  if (error || !result) {
    return jsonResponse(500, {
      ok: false,
      code: "INTAKE_UPDATE_FAILED",
      message: "Intake could not be updated.",
    }, origin);
  }

  if (result.outcome === "invalid_token") return invalidIntakeToken(origin);
  if (result.outcome === "not_editable") {
    return jsonResponse(409, {
      ok: false,
      code: "INTAKE_NOT_EDITABLE",
      message: "Intake can no longer be changed.",
    }, origin);
  }
  if (!isIntakeStatus(result.intake_status)) {
    return jsonResponse(500, {
      ok: false,
      code: "INVALID_INTAKE_STATE",
      message: "Intake could not be updated.",
    }, origin);
  }

  if (result.outcome === "already_submitted") {
    let notificationStatus = isEmailJobStatus(result.notification_job_status)
      ? result.notification_job_status
      : null;
    if (
      rawAdminCapability &&
      isUuid(result.notification_job_id) &&
      notificationStatus &&
      notificationStatus !== "sent" &&
      notificationStatus !== "failed"
    ) {
      notificationStatus = await processSubmittedIntakeNotification(
        supabase,
        result.notification_job_id,
        notificationStatus,
        intakeTokenHash,
        rawAdminCapability,
      );
    }

    return jsonResponse(200, {
      ok: true,
      state: "already_submitted",
      notification_status: notificationStatus,
      intake: {
        status: result.intake_status,
        submitted_at: result.submitted_at,
      },
    }, origin);
  }

  if (action === "save_draft" && result.outcome === "saved") {
    return jsonResponse(200, {
      ok: true,
      state: "saved",
      intake: {
        status: result.intake_status,
        updated_at: result.updated_at,
      },
    }, origin);
  }

  if (action === "submit" && result.outcome === "submitted") {
    if (!isUuid(result.notification_job_id) || !isEmailJobStatus(result.notification_job_status)) {
      return jsonResponse(500, {
        ok: false,
        code: "INTAKE_NOTIFICATION_JOB_UNAVAILABLE",
        message: "Intake was submitted, but its notification job is unavailable.",
      }, origin);
    }

    if (!rawAdminCapability) {
      return jsonResponse(500, {
        ok: false,
        code: "ADMIN_CAPABILITY_UNAVAILABLE",
        message: "Intake was submitted, but its notification could not be prepared.",
      }, origin);
    }

    const notificationStatus = await processSubmittedIntakeNotification(
      supabase,
      result.notification_job_id,
      result.notification_job_status,
      intakeTokenHash,
      rawAdminCapability,
    );

    return jsonResponse(200, {
      ok: true,
      state: "submitted",
      notification_status: notificationStatus,
      intake: {
        status: result.intake_status,
        submitted_at: result.submitted_at,
      },
    }, origin);
  }

  return jsonResponse(500, {
    ok: false,
    code: "INVALID_INTAKE_STATE",
    message: "Intake could not be updated.",
  }, origin);
});
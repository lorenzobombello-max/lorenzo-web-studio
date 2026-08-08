import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import {
  createRawIntakeToken,
  hashApprovalToken,
  hashIntakeToken,
} from "../_shared/security.ts";
import type { IntakeAction, IntakeStatus } from "../_shared/types.ts";
import {
  InputValidationError,
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
  if (value === "create" || value === "inspect" || value === "save_draft" || value === "submit") return value;
  throw new IntakeRequestError(400, "INVALID_ACTION");
}

function isIntakeStatus(value: unknown): value is IntakeStatus {
  return value === "invited" || value === "in_progress" || value === "submitted" || value === "reviewed";
}

function invalidIntakeToken(origin: string | null): Response {
  return jsonResponse(401, {
    ok: false,
    code: "INVALID_INTAKE_TOKEN",
    message: "Intake link is invalid or unavailable.",
  }, origin);
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

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

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
    const { data, error } = await supabase.rpc("inspect_quote_request_intake_details", {
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

  const { data, error } = await supabase.rpc("update_quote_request_intake", {
    p_access_token_hash: intakeTokenHash,
    p_action: action,
    p_data: intakeData,
  });
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
    return jsonResponse(200, {
      ok: true,
      state: "already_submitted",
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
    return jsonResponse(200, {
      ok: true,
      state: "submitted",
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
const MAX_BODY_BYTES = 16 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const COMMANDS = new Set([
  "prepare_milestone_1",
  "record_payment_evidence",
  "reconcile_payment",
  "confirm_payment",
  "release_project",
  "record_preview_ready",
  "activate_preview_access",
  "revoke_preview_access",
  "classify_feedback",
  "create_revision",
  "mark_revision_ready",
  "create_preview_version",
  "require_change_order",
  "authorize_final_transfer",
  "record_delivery",
  "archive_project"
]);
const APPLICATION_ACTIONS = new Set([
  "list_applications",
  "get_application_detail",
  "get_project_dossier",
  "promote_accepted_application"
]);
const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;
const FORBIDDEN_IDENTITY_FIELDS = new Set([
  "p_actor",
  "actor",
  "actor_id",
  "operator_id",
  "operator_role",
  "name",
  "email"
]);
class RequestError extends Error {
  status;
  code;
  constructor(status, code){
    super(code);
    this.status = status;
    this.code = code;
  }
}
function response(status, code, extra = {}) {
  return new Response(JSON.stringify({
    ok: status < 400,
    code,
    ...extra
  }), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer"
    }
  });
}
function bearer(request) {
  const match = (request.headers.get("authorization") || "").match(/^Bearer\s+([^\s]+)$/i);
  if (!match) throw new RequestError(401, "AUTHENTICATION_REQUIRED");
  return match[1];
}
function decodeClaims(jwt) {
  const parts = jwt.split(".");
  if (parts.length !== 3) throw new RequestError(401, "INVALID_JWT");
  try {
    const value = parts[1].replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(parts[1].length / 4) * 4, "=");
    return JSON.parse(atob(value));
  } catch  {
    throw new RequestError(401, "INVALID_JWT");
  }
}
async function body(request) {
  if ((request.headers.get("content-type") || "").split(";", 1)[0].trim().toLowerCase() !== "application/json") throw new RequestError(415, "UNSUPPORTED_CONTENT_TYPE");
  const declared = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) throw new RequestError(413, "BODY_TOO_LARGE");
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) throw new RequestError(413, "BODY_TOO_LARGE");
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw 0;
    return parsed;
  } catch  {
    throw new RequestError(400, "INVALID_JSON");
  }
}
function validate(value) {
  for (const key of FORBIDDEN_IDENTITY_FIELDS)if (key in value) throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
  if (!UUID.test(String(value.project_id || "")) || !UUID.test(String(value.idempotency_key || ""))) throw new RequestError(400, "INVALID_REQUEST");
  if (!COMMANDS.has(String(value.command_type || "")) || typeof value.expected_state !== "string" || !Number.isSafeInteger(value.expected_revision) || Number(value.expected_revision) < 0) throw new RequestError(400, "INVALID_REQUEST");
  if (!value.payload || typeof value.payload !== "object" || Array.isArray(value.payload)) throw new RequestError(400, "INVALID_REQUEST");
  for (const key of FORBIDDEN_IDENTITY_FIELDS)if (key in value.payload) throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
  return value;
}
function validateApplicationAction(value) {
  for (const key of FORBIDDEN_IDENTITY_FIELDS)if (key in value) throw new RequestError(400, "IDENTITY_FIELD_FORBIDDEN");
  const action = String(value.action || "");
  if (!APPLICATION_ACTIONS.has(action)) throw new RequestError(400, "INVALID_REQUEST");
  const allowed = action === "list_applications"
    ? new Set(["action", "limit", "offset"])
    : action === "get_project_dossier"
    ? new Set(["action", "project_id"])
    : action === "get_application_detail"
    ? new Set(["action", "quote_request_id", "application_reference"])
    : new Set(["action", "quote_request_id", "application_reference", "idempotency_key"]);
  if (Object.keys(value).some((key)=>!allowed.has(key))) throw new RequestError(400, "INVALID_REQUEST");
  if (action === "list_applications") {
    const limit = value.limit ?? 100, offset = value.offset ?? 0;
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 200 || !Number.isSafeInteger(offset) || offset < 0) throw new RequestError(400, "INVALID_REQUEST");
    return { action, limit, offset };
  }
  if (action === "get_project_dossier") {
    const projectId = String(value.project_id || "");
    if (!UUID.test(projectId)) throw new RequestError(400, "INVALID_REQUEST");
    return { action, project_id: projectId };
  }
  const quoteRequestId = value.quote_request_id == null ? null : String(value.quote_request_id);
  const applicationReference = value.application_reference == null ? null : String(value.application_reference);
  if ((quoteRequestId === null) === (applicationReference === null)) throw new RequestError(400, "INVALID_REQUEST");
  if (quoteRequestId !== null && !UUID.test(quoteRequestId)) throw new RequestError(400, "INVALID_REQUEST");
  if (applicationReference !== null && !APPLICATION_REFERENCE.test(applicationReference)) throw new RequestError(400, "INVALID_REQUEST");
  if (action === "promote_accepted_application" && !UUID.test(String(value.idempotency_key || ""))) throw new RequestError(400, "INVALID_REQUEST");
  return {
    action,
    quote_request_id: quoteRequestId,
    application_reference: applicationReference,
    ...(action === "promote_accepted_application" ? { idempotency_key: String(value.idempotency_key) } : {})
  };
}
function mapDatabaseError(error) {
  const code = error instanceof Error ? error.message : "INTERNAL";
  if ([
    "HUMAN_JWT_REQUIRED",
    "UNKNOWN_OPERATOR",
    "OPERATOR_DISABLED",
    "OPERATOR_REVOKED",
    "OPERATOR_INACTIVE",
    "APPLICATION_SCOPE_DENIED"
  ].includes(code)) return response(403, "OPERATOR_NOT_AUTHORIZED");
  if ([
    "PROJECT_SCOPE_DENIED",
    "COMMAND_PERMISSION_DENIED"
  ].includes(code)) return response(403, "INSUFFICIENT_PERMISSIONS");
  if (code === "IDEMPOTENCY_CONFLICT") return response(409, code);
  if (code === "CONCURRENT_MODIFICATION") return response(409, code);
  if (code === "APPLICATION_NOT_FOUND") return response(404, code);
  if (code === "PROJECT_NOT_FOUND") return response(404, code);
  if (code === "APPLICATION_NOT_ACCEPTED") return response(409, code);
  if ([
    "INVALID_APPLICATION_REFERENCE",
    "EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED",
    "INVALID_PAGINATION",
    "IDEMPOTENCY_KEY_REQUIRED"
  ].includes(code)) return response(400, "INVALID_REQUEST");
  if ([
    "INVALID_STATE",
    "PAYMENT_NOT_MATCHED",
    "ACCESS_DENIED"
  ].includes(code)) return response(409, "COMMAND_REJECTED");
  return response(500, "INTERNAL_ERROR");
}
export async function handleCommercialOperator(request, deps) {
  try {
    if (request.method !== "POST") throw new RequestError(405, "METHOD_NOT_ALLOWED");
    const jwt = bearer(request), claims = decodeClaims(jwt), sub = String(claims.sub || "");
    if (!UUID.test(sub) || typeof claims.exp !== "number" || claims.exp * 1000 <= deps.now()) throw new RequestError(401, "INVALID_JWT");
    if (claims.role === "service_role") throw new RequestError(401, "HUMAN_JWT_REQUIRED");
    const user = await deps.verifyUser(jwt);
    if (!user || user.id !== sub) throw new RequestError(401, "INVALID_JWT");
    const parsed = await body(request);
    if ("action" in parsed) {
      const input = validateApplicationAction(parsed);
      const result = await deps.executeApplicationAction(jwt, input);
      return response(200, "APPLICATION_ACTION_ACCEPTED", { result });
    }
    const input = validate(parsed);
    const limit = await deps.consumeRateLimit(jwt, input.project_id);
    if (!limit.allowed) return response(429, "RATE_LIMITED", {
      retry_after_seconds: limit.retry_after_seconds
    });
    const result = await deps.executeCommand(jwt, input);
    return response(200, "COMMAND_ACCEPTED", {
      result
    });
  } catch (error) {
    if (error instanceof RequestError) return response(error.status, error.code);
    return mapDatabaseError(error);
  }
}
export function createUnsignedTestJwt(payload) {
  const encode = (value)=>btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  return `${encode({
    alg: "RS256",
    typ: "JWT"
  })}.${encode(payload)}.signature`;
}
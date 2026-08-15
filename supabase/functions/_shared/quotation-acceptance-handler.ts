import { corsHeaders, rejectIfOriginNotAllowed } from "./cors.ts";
import { hashQuotationAcceptanceCapabilityToken, validateQuotationAcceptanceCapabilityToken } from "./quotation-acceptance-capability.ts";

type RpcResult = { data: unknown; error: unknown };
export type AcceptanceRpcClient = { rpc(name: string, parameters: Record<string, unknown>): PromiseLike<RpcResult> };
export type AcceptanceConfirmedHook = (acceptanceId: string) => Promise<void>;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function headers(origin: string | null): HeadersInit {
  return { ...corsHeaders(origin), "Content-Type": "application/json", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'", "Cache-Control": "no-store" };
}
function response(status: number, body: Record<string, unknown>, origin: string | null): Response {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) });
}
function bearer(request: Request): string {
  const match = (request.headers.get("authorization") || "").match(/^Bearer\s+([^\s]+)$/i);
  return validateQuotationAcceptanceCapabilityToken(match?.[1]);
}
async function body(request: Request): Promise<Record<string, unknown>> {
  if ((request.headers.get("content-type") || "").split(";", 1)[0].trim().toLowerCase() !== "application/json") throw new Error("VALIDATION_FAILED");
  const text = await request.text(); if (new TextEncoder().encode(text).byteLength > 4096) throw new Error("VALIDATION_FAILED");
  const parsed = JSON.parse(text); if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("VALIDATION_FAILED");
  return parsed;
}
function validSubmit(value: Record<string, unknown>): boolean {
  const keys = Object.keys(value).sort().join(",");
  return keys === "accepting_email,accepting_name,accepting_organization,accepting_role,authority_declaration,terms_id,terms_version"
    && typeof value.accepting_name === "string" && value.accepting_name.trim().length > 0 && value.accepting_name.length <= 200
    && typeof value.accepting_email === "string" && EMAIL.test(value.accepting_email) && value.accepting_email.length <= 320
    && (value.accepting_organization === null || typeof value.accepting_organization === "string")
    && (value.accepting_role === null || typeof value.accepting_role === "string")
    && value.authority_declaration === true
    && typeof value.terms_id === "string" && typeof value.terms_version === "string";
}

export async function handleQuotationAcceptance(request: Request, client: AcceptanceRpcClient, onAccepted?: AcceptanceConfirmedHook): Promise<Response> {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: headers(origin) });
  const blocked = rejectIfOriginNotAllowed(request); if (blocked) return blocked;
  if (!new Set(["GET", "POST"]).has(request.method)) return response(405, { ok: false, state: "VALIDATION_FAILED" }, origin);
  let digest: string;
  try { digest = await hashQuotationAcceptanceCapabilityToken(bearer(request)); } catch { return response(200, { ok: true, state: "INVALID_OR_EXPIRED_LINK" }, origin); }
  const limit = await client.rpc("consume_acceptance_capability_rate_limit_v1", { p_token_digest: digest, p_max_requests: 30 });
  if (limit.error || limit.data !== true) return response(429, { ok: false, state: "ACCEPTANCE_NOT_AVAILABLE" }, origin);
  if (request.method === "GET") {
    const result = await client.rpc("resolve_quotation_acceptance_capability_v1", { p_token_digest: digest });
    if (result.error || !result.data || typeof result.data !== "object") return response(200, { ok: true, state: "INVALID_OR_EXPIRED_LINK" }, origin);
    return response(200, { ok: true, ...(result.data as Record<string, unknown>) }, origin);
  }
  const idempotencyKey = request.headers.get("idempotency-key") || "";
  let input: Record<string, unknown>;
  try { input = await body(request); } catch { return response(400, { ok: false, state: "VALIDATION_FAILED" }, origin); }
  if (!UUID.test(idempotencyKey) || !validSubmit(input)) return response(400, { ok: false, state: "VALIDATION_FAILED" }, origin);
  const result = await client.rpc("submit_quotation_acceptance_capability_v1", {
    p_token_digest: digest, p_expected_terms_id: input.terms_id, p_expected_terms_version: input.terms_version,
    p_accepting_name: input.accepting_name, p_accepting_email: input.accepting_email,
    p_accepting_organization: input.accepting_organization, p_accepting_role: input.accepting_role,
    p_authority_declaration: true, p_idempotency_key: idempotencyKey,
  });
  if (result.error || !result.data || typeof result.data !== "object") return response(200, { ok: true, state: "VALIDATION_FAILED" }, origin);
  const resultBody = result.data as Record<string, unknown>;
  let confirmationStatus: "scheduled" | "failed" | undefined;
  if (resultBody.state === "ACCEPTED" && typeof resultBody.acceptance_id === "string" && onAccepted) {
    try { await onAccepted(resultBody.acceptance_id); confirmationStatus = "scheduled"; } catch { confirmationStatus = "failed"; }
  }
  return response(200, { ok: true, ...resultBody, ...(confirmationStatus ? { confirmation_status: confirmationStatus } : {}) }, origin);
}
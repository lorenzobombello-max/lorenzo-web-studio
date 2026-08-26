import { corsHeaders, rejectIfOriginNotAllowed } from "./cors.ts";
import { hashCustomerRequestUploadCapabilityToken, validateCustomerRequestUploadCapabilityToken } from "./customer-request-upload-capability.ts";

type RpcResult = { data: unknown; error: unknown };
export type CustomerRequestUploadRpcClient = { rpc(name: string, parameters: Record<string, unknown>): PromiseLike<RpcResult> };
export type CustomerRequestUploadStorage = {
  createSignedUploadUrl(bucket: string, path: string): PromiseLike<{ data: { signedUrl?: string } | null; error: unknown }>;
  download(bucket: string, path: string): PromiseLike<{ data: Blob | null; error: unknown }>;
  remove(bucket: string, paths: string[]): PromiseLike<{ error: unknown }>;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ALLOWED_TYPES = new Set(["application/pdf", "image/png", "image/jpeg"]);
const MAX_BODY_BYTES = 4096;

function response(status: number, body: Record<string, unknown>, origin: string | null): Response {
  return new Response(JSON.stringify(body), { status, headers: {
    ...corsHeaders(origin), "Content-Type": "application/json", "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY",
  } });
}

function bearer(request: Request): string {
  const match = (request.headers.get("authorization") || "").match(/^Bearer\s+([^\s]+)$/i);
  return validateCustomerRequestUploadCapabilityToken(match?.[1]);
}

async function body(request: Request): Promise<Record<string, unknown>> {
  if ((request.headers.get("content-type") || "").split(";", 1)[0].trim().toLowerCase() !== "application/json") throw new Error("VALIDATION_FAILED");
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) throw new Error("VALIDATION_FAILED");
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("VALIDATION_FAILED");
  return parsed;
}

function exactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).sort().join(",") === [...keys].sort().join(",");
}

function validPrepare(value: Record<string, unknown>): boolean {
  return exactKeys(value, ["action", "file_name", "content_type", "byte_count"])
    && value.action === "prepare" && typeof value.file_name === "string" && value.file_name.length > 0 && value.file_name.length <= 200
    && typeof value.content_type === "string" && ALLOWED_TYPES.has(value.content_type)
    && Number.isSafeInteger(value.byte_count) && Number(value.byte_count) > 0 && Number(value.byte_count) <= 8388608;
}

function signatureMatches(contentType: string, bytes: Uint8Array): boolean {
  if (contentType === "application/pdf") return bytes.length >= 5 && new TextDecoder().decode(bytes.slice(0, 5)) === "%PDF-";
  if (contentType === "image/png") return bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((value, index) => bytes[index] === value);
  if (contentType === "image/jpeg") return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  return false;
}

function hex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function objectResult(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

export async function handleCustomerRequestUpload(request: Request, client: CustomerRequestUploadRpcClient, storage: CustomerRequestUploadStorage): Promise<Response> {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  const blocked = rejectIfOriginNotAllowed(request); if (blocked) return blocked;
  if (!new Set(["GET", "POST"]).has(request.method)) return response(405, { ok: false, state: "VALIDATION_FAILED" }, origin);
  let digest: string;
  try { digest = await hashCustomerRequestUploadCapabilityToken(bearer(request)); }
  catch { return response(200, { ok: true, state: "INVALID_OR_EXPIRED_LINK" }, origin); }
  const limited = await client.rpc("consume_acceptance_capability_rate_limit_v1", { p_token_digest: digest, p_max_requests: 60 });
  if (limited.error || limited.data !== true) return response(429, { ok: false, state: "UPLOAD_NOT_AVAILABLE" }, origin);
  if (request.method === "GET") {
    const resolved = await client.rpc("resolve_customer_request_upload_capability_v1", { p_token_digest: digest });
    const result = objectResult(resolved.data);
    return response(200, { ok: true, ...(resolved.error || !result ? { state: "INVALID_OR_EXPIRED_LINK" } : result) }, origin);
  }
  const idempotencyKey = request.headers.get("idempotency-key") || "";
  let input: Record<string, unknown>;
  try { input = await body(request); } catch { return response(400, { ok: false, state: "VALIDATION_FAILED" }, origin); }
  if (!UUID.test(idempotencyKey)) return response(400, { ok: false, state: "VALIDATION_FAILED" }, origin);

  if (input.action === "prepare" && validPrepare(input)) {
    const prepared = await client.rpc("prepare_customer_request_upload_v1", {
      p_token_digest: digest, p_original_file_name: input.file_name,
      p_content_type: input.content_type, p_byte_count: input.byte_count, p_idempotency_key: idempotencyKey,
    });
    const result = objectResult(prepared.data);
    if (prepared.error || !result || result.state !== "PREPARED" || !UUID.test(String(result.file_id || ""))
        || result.storage_bucket_id !== "customer-request-quarantine" || typeof result.storage_object_path !== "string") {
      return response(200, { ok: true, state: result?.state || "VALIDATION_FAILED" }, origin);
    }
    const signed = await storage.createSignedUploadUrl("customer-request-quarantine", result.storage_object_path);
    if (signed.error || !signed.data?.signedUrl) return response(503, { ok: false, state: "UPLOAD_NOT_AVAILABLE" }, origin);
    return response(200, { ok: true, state: "PREPARED", file_id: result.file_id, signed_upload_url: signed.data.signedUrl }, origin);
  }

  if (input.action === "finalize" && exactKeys(input, ["action", "file_id"]) && UUID.test(String(input.file_id || ""))) {
    const parameters = { p_token_digest: digest, p_uploaded_file_id: input.file_id, p_idempotency_key: idempotencyKey };
    const prepared = await client.rpc("finalize_customer_request_uploaded_file_v1", {
      ...parameters, p_observed_content_type: null, p_observed_byte_count: null, p_sha256: null, p_signature_valid: null,
    });
    const reservation = objectResult(prepared.data);
    if (prepared.error || !reservation || reservation.state !== "PREPARED"
        || reservation.storage_bucket_id !== "customer-request-quarantine" || typeof reservation.storage_object_path !== "string"
        || typeof reservation.declared_content_type !== "string" || !ALLOWED_TYPES.has(reservation.declared_content_type)) {
      return response(200, { ok: true, state: "VALIDATION_FAILED" }, origin);
    }
    const downloaded = await storage.download("customer-request-quarantine", reservation.storage_object_path);
    if (downloaded.error || !downloaded.data) return response(200, { ok: true, state: "VALIDATION_FAILED" }, origin);
    const buffer = await downloaded.data.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    const observedType = downloaded.data.type || reservation.declared_content_type;
    const digestSha256 = hex(await crypto.subtle.digest("SHA-256", buffer));
    const finalized = await client.rpc("finalize_customer_request_uploaded_file_v1", {
      ...parameters, p_observed_content_type: observedType, p_observed_byte_count: bytes.byteLength,
      p_sha256: digestSha256, p_signature_valid: signatureMatches(reservation.declared_content_type, bytes),
    });
    const result = objectResult(finalized.data);
    if (finalized.error || !result) return response(200, { ok: true, state: "VALIDATION_FAILED" }, origin);
    if (result.state === "REJECTED") await storage.remove("customer-request-quarantine", [reservation.storage_object_path]);
    const safeResult = { ...result }; delete safeResult.storage_object_path; delete safeResult.delete_object;
    return response(200, { ok: true, ...safeResult }, origin);
  }

  if (input.action === "complete" && exactKeys(input, ["action"])) {
    const completed = await client.rpc("complete_customer_request_upload_request_v1", { p_token_digest: digest, p_idempotency_key: idempotencyKey });
    const result = objectResult(completed.data);
    return response(200, { ok: true, ...(completed.error || !result ? { state: "VALIDATION_FAILED" } : result) }, origin);
  }
  return response(400, { ok: false, state: "VALIDATION_FAILED" }, origin);
}
const encoder = new TextEncoder();
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const DOMAIN = "lws-quotation-acceptance-capability:v1:";

function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function secret(): string {
  const value = Deno.env.get("QUOTATION_ACCEPTANCE_CAPABILITY_SECRET");
  if (!value || encoder.encode(value).byteLength < 32) throw new Error("Missing quotation acceptance capability secret");
  return value;
}

export function createQuotationAcceptanceCapabilityToken(): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export async function hashQuotationAcceptanceCapabilityToken(rawToken: string): Promise<string> {
  if (!TOKEN_PATTERN.test(rawToken)) throw new TypeError("Invalid quotation acceptance capability");
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret()), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(`${DOMAIN}${rawToken}`)));
}

export function buildQuotationAcceptanceUrl(rawToken: string): string {
  if (!TOKEN_PATTERN.test(rawToken)) throw new TypeError("Invalid quotation acceptance capability");
  const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";
  const url = new URL("/pages/quotation-acceptance.html", siteUrl);
  url.hash = new URLSearchParams({ token: rawToken }).toString();
  return url.toString();
}

export function validateQuotationAcceptanceCapabilityToken(rawToken: unknown): string {
  if (typeof rawToken !== "string" || !TOKEN_PATTERN.test(rawToken)) throw new TypeError("Invalid quotation acceptance capability");
  return rawToken;
}

export async function createQuotationAcceptanceCapability(
  client: { rpc(name: string, parameters: Record<string, unknown>): Promise<{ data: unknown; error: unknown }> },
  input: { issuanceId: string; requestedExpiresAt: string | null; idempotencyKey: string; adminAccessTokenHash: string; createdBy: string },
): Promise<{ token: string; tokenDigest: string; capabilityId: string; expiresAt: string }> {
  const token = createQuotationAcceptanceCapabilityToken();
  const tokenDigest = await hashQuotationAcceptanceCapabilityToken(token);
  const { data, error } = await client.rpc("create_quotation_acceptance_capability_v1", {
    p_issuance_id: input.issuanceId, p_token_digest: tokenDigest,
    p_requested_expires_at: input.requestedExpiresAt, p_idempotency_key: input.idempotencyKey,
    p_admin_access_token_hash: input.adminAccessTokenHash, p_created_by: input.createdBy,
  });
  const row = Array.isArray(data) && data.length === 1 ? data[0] as Record<string, unknown> : null;
  if (error || !row || typeof row.capability_id !== "string" || typeof row.expires_at !== "string" || row.was_created !== true) {
    throw new Error("Capability creation failed");
  }
  return { token, tokenDigest, capabilityId: row.capability_id, expiresAt: row.expires_at };
}
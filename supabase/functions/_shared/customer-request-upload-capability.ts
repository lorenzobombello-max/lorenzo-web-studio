const encoder = new TextEncoder();
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const DOMAIN = "lws-customer-request-upload-capability:v1:";

function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function secret(): string {
  const value = Deno.env.get("CUSTOMER_REQUEST_UPLOAD_CAPABILITY_SECRET");
  if (!value || encoder.encode(value).byteLength < 32) throw new Error("Missing customer request upload capability secret");
  return value;
}

async function hmac(value: string): Promise<ArrayBuffer> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret()), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return await crypto.subtle.sign("HMAC", key, encoder.encode(value));
}

export function createCustomerRequestUploadCapabilityToken(): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export function validateCustomerRequestUploadCapabilityToken(rawToken: unknown): string {
  if (typeof rawToken !== "string" || !TOKEN_PATTERN.test(rawToken)) throw new TypeError("Invalid customer request upload capability");
  return rawToken;
}

export async function hashCustomerRequestUploadCapabilityToken(rawToken: string): Promise<string> {
  validateCustomerRequestUploadCapabilityToken(rawToken);
  return toHex(await hmac(`${DOMAIN}${rawToken}`));
}

export async function deriveCustomerRequestUploadCapabilityToken(requestId: string, idempotencyKey: string): Promise<string> {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuid.test(requestId) || !uuid.test(idempotencyKey)) throw new TypeError("Invalid customer request upload derivation input");
  return toBase64Url(new Uint8Array(await hmac(`${DOMAIN}operator-create:${requestId}:${idempotencyKey}`)));
}

export function buildCustomerRequestUploadUrl(rawToken: string): string {
  validateCustomerRequestUploadCapabilityToken(rawToken);
  const url = new URL("/pages/customer-request-upload.html", Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be");
  url.hash = new URLSearchParams({ token: rawToken }).toString();
  return url.toString();
}
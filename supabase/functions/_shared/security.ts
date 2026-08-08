const textEncoder = new TextEncoder();

function toHex(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function toBase64Url(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function intakeInvitationEncryptionKey(): Promise<CryptoKey> {
  const secret = Deno.env.get("APPROVAL_TOKEN_SECRET");
  if (!secret) throw new Error("Missing APPROVAL_TOKEN_SECRET");
  const keyMaterial = await crypto.subtle.digest(
    "SHA-256",
    textEncoder.encode(`intake-invitation-encryption:${secret}`),
  );
  return await crypto.subtle.importKey("raw", keyMaterial, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function intakeInvitationAdditionalData(accessTokenHash: string): Uint8Array {
  return textEncoder.encode(`intake-invitation:v1:${accessTokenHash}`);
}

async function hmacSha256(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    textEncoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign("HMAC", key, textEncoder.encode(value));
  return toHex(signature);
}

function createRawCapabilityToken(): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(32)).buffer);
}

export async function hashApprovalToken(rawToken: string): Promise<string> {
  const secret = Deno.env.get("APPROVAL_TOKEN_SECRET");
  if (!secret) throw new Error("Missing APPROVAL_TOKEN_SECRET");
  return await hmacSha256(secret, `approval:${rawToken}`);
}

export async function hashIntakeToken(rawToken: string): Promise<string> {
  const secret = Deno.env.get("APPROVAL_TOKEN_SECRET");
  if (!secret) throw new Error("Missing APPROVAL_TOKEN_SECRET");
  return await hmacSha256(secret, `intake:${rawToken}`);
}

export async function encryptIntakeInvitationToken(rawToken: string, accessTokenHash: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: intakeInvitationAdditionalData(accessTokenHash) },
    await intakeInvitationEncryptionKey(),
    textEncoder.encode(rawToken),
  );
  return `v1.${toBase64Url(iv.buffer)}.${toBase64Url(ciphertext)}`;
}

export async function decryptIntakeInvitationToken(encryptedToken: string, accessTokenHash: string): Promise<string> {
  const parts = encryptedToken.split(".");
  if (parts.length !== 3 || parts[0] !== "v1") throw new Error("Invalid encrypted intake token");
  const iv = fromBase64Url(parts[1]);
  if (iv.byteLength !== 12) throw new Error("Invalid encrypted intake token");
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv, additionalData: intakeInvitationAdditionalData(accessTokenHash) },
    await intakeInvitationEncryptionKey(),
    fromBase64Url(parts[2]),
  );
  const token = new TextDecoder("utf-8", { fatal: true }).decode(plaintext);
  if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new Error("Invalid encrypted intake token");
  return token;
}

export async function hashClientIp(ip: string): Promise<string> {
  const secret = Deno.env.get("APPROVAL_TOKEN_SECRET");
  if (!secret) throw new Error("Missing APPROVAL_TOKEN_SECRET");
  return await hmacSha256(secret, `ip:${ip}`);
}

export function createRawApprovalToken(): string {
  return createRawCapabilityToken();
}

export function createRawIntakeToken(): string {
  return createRawCapabilityToken();
}

export async function createApprovalTokenForIdempotencyKey(idempotencyKey: string): Promise<string> {
  const secret = Deno.env.get("APPROVAL_TOKEN_SECRET");
  if (!secret) throw new Error("Missing APPROVAL_TOKEN_SECRET");

  const key = await crypto.subtle.importKey(
    "raw",
    textEncoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    textEncoder.encode(`approval-raw:${idempotencyKey}`),
  );
  return toBase64Url(signature);
}

export function computeTokenExpiry(): string {
  const ttlMinutes = Number(Deno.env.get("TOKEN_TTL_MINUTES") || "1440");
  const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
  return expiresAt.toISOString();
}

export function extractClientIp(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();

  const realIp = request.headers.get("x-real-ip");
  if (realIp) return realIp.trim();

  const cfIp = request.headers.get("cf-connecting-ip");
  if (cfIp) return cfIp.trim();

  return "0.0.0.0";
}

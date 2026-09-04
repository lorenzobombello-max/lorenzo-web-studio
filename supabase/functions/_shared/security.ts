const textEncoder = new TextEncoder();
const ADMIN_INTAKE_RAW_DOMAIN = "admin-intake-raw:v1:";
const ADMIN_INTAKE_VERIFY_DOMAIN = "admin-intake-verify:v1:";

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

function fromBase64Url(value: string): Uint8Array<ArrayBuffer> {
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

async function quotationDeliveryEncryptionKey(): Promise<CryptoKey> {
  const secret = Deno.env.get("APPROVAL_TOKEN_SECRET");
  if (!secret) throw new Error("Missing APPROVAL_TOKEN_SECRET");
  const keyMaterial = await crypto.subtle.digest(
    "SHA-256",
    textEncoder.encode(`quotation-delivery-encryption:v1:${secret}`),
  );
  return await crypto.subtle.importKey("raw", keyMaterial, "AES-GCM", false, ["encrypt", "decrypt"]);
}

async function recruitmentInvitationEncryptionKey(): Promise<CryptoKey> {
  const secret = Deno.env.get("APPROVAL_TOKEN_SECRET");
  if (!secret) throw new Error("Missing APPROVAL_TOKEN_SECRET");
  const keyMaterial = await crypto.subtle.digest(
    "SHA-256",
    textEncoder.encode(`recruitment-invitation-encryption:v1:${secret}`),
  );
  return await crypto.subtle.importKey("raw", keyMaterial, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function intakeInvitationAdditionalData(accessTokenHash: string): Uint8Array<ArrayBuffer> {
  return textEncoder.encode(`intake-invitation:v1:${accessTokenHash}`);
}

async function hmacSha256Bytes(secret: string, value: string): Promise<ArrayBuffer> {
  const key = await crypto.subtle.importKey(
    "raw",
    textEncoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  return await crypto.subtle.sign("HMAC", key, textEncoder.encode(value));
}

async function hmacSha256(secret: string, value: string): Promise<string> {
  return toHex(await hmacSha256Bytes(secret, value));
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

function adminIntakeTokenSecret(): string {
  const secret = Deno.env.get("ADMIN_INTAKE_TOKEN_SECRET");
  if (!secret) throw new Error("Missing ADMIN_INTAKE_TOKEN_SECRET");
  return secret;
}

export async function deriveAdminIntakeCapability(accessTokenHash: string): Promise<string> {
  if (!/^[0-9a-f]{64}$/.test(accessTokenHash)) throw new Error("Invalid admin intake capability input");
  return toBase64Url(
    await hmacSha256Bytes(adminIntakeTokenSecret(), `${ADMIN_INTAKE_RAW_DOMAIN}${accessTokenHash}`),
  );
}

export async function hashAdminIntakeToken(rawToken: string): Promise<string> {
  if (!/^[A-Za-z0-9_-]{43}$/.test(rawToken)) throw new Error("Invalid admin intake capability");
  return await hmacSha256(adminIntakeTokenSecret(), `${ADMIN_INTAKE_VERIFY_DOMAIN}${rawToken}`);
}

export function computeAdminIntakeTokenExpiry(): string {
  const ttlMinutes = Number(Deno.env.get("ADMIN_INTAKE_TOKEN_TTL_MINUTES") || "43200");
  if (!Number.isFinite(ttlMinutes) || ttlMinutes <= 0) throw new Error("Invalid admin intake token TTL");
  return new Date(Date.now() + ttlMinutes * 60 * 1000).toISOString();
}

export function buildAdminIntakeUrl(rawToken: string): string {
  if (!/^[A-Za-z0-9_-]{43}$/.test(rawToken)) throw new Error("Invalid admin intake capability");
  const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";
  const url = new URL("/pages/admin-intake.html", siteUrl);
  url.hash = new URLSearchParams({ token: rawToken }).toString();
  return url.toString();
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

export async function encryptQuotationDeliveryToken(rawToken: string, tokenDigest: string): Promise<string> {
  if (!/^[A-Za-z0-9_-]{43}$/.test(rawToken) || !/^[0-9a-f]{64}$/.test(tokenDigest)) throw new Error("Invalid quotation delivery token");
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: textEncoder.encode(`quotation-delivery:v1:${tokenDigest}`) },
    await quotationDeliveryEncryptionKey(),
    textEncoder.encode(rawToken),
  );
  return `v1.${toBase64Url(iv.buffer)}.${toBase64Url(ciphertext)}`;
}

export async function decryptQuotationDeliveryToken(encryptedToken: string, tokenDigest: string): Promise<string> {
  if (!/^[0-9a-f]{64}$/.test(tokenDigest)) throw new Error("Invalid quotation delivery token");
  const parts = encryptedToken.split(".");
  if (parts.length !== 3 || parts[0] !== "v1") throw new Error("Invalid quotation delivery token");
  const iv = fromBase64Url(parts[1]);
  if (iv.byteLength !== 12) throw new Error("Invalid quotation delivery token");
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv, additionalData: textEncoder.encode(`quotation-delivery:v1:${tokenDigest}`) },
    await quotationDeliveryEncryptionKey(),
    fromBase64Url(parts[2]),
  );
  const token = new TextDecoder("utf-8", { fatal: true }).decode(plaintext);
  if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new Error("Invalid quotation delivery token");
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

export function createRawRecruitmentCandidateToken(): string {
  return toHex(crypto.getRandomValues(new Uint8Array(32)).buffer);
}

export async function hashRecruitmentCandidateToken(rawToken: string): Promise<string> {
  if (!/^[0-9a-f]{64}$/.test(rawToken)) throw new Error("Invalid recruitment candidate token");
  return toHex(await crypto.subtle.digest("SHA-256", textEncoder.encode(rawToken)));
}

export async function encryptRecruitmentCandidateToken(rawToken: string, tokenDigest: string): Promise<string> {
  if (!/^[0-9a-f]{64}$/.test(rawToken) || !/^[0-9a-f]{64}$/.test(tokenDigest)) throw new Error("Invalid recruitment candidate token");
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: textEncoder.encode(`recruitment-invitation:v1:${tokenDigest}`) },
    await recruitmentInvitationEncryptionKey(),
    textEncoder.encode(rawToken),
  );
  return `v1.${toBase64Url(iv.buffer)}.${toBase64Url(ciphertext)}`;
}

export async function decryptRecruitmentCandidateToken(encryptedToken: string, tokenDigest: string): Promise<string> {
  if (!/^[0-9a-f]{64}$/.test(tokenDigest)) throw new Error("Invalid recruitment candidate token");
  const parts = encryptedToken.split(".");
  if (parts.length !== 3 || parts[0] !== "v1") throw new Error("Invalid encrypted recruitment token");
  const iv = fromBase64Url(parts[1]);
  if (iv.byteLength !== 12) throw new Error("Invalid encrypted recruitment token");
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv, additionalData: textEncoder.encode(`recruitment-invitation:v1:${tokenDigest}`) },
    await recruitmentInvitationEncryptionKey(),
    fromBase64Url(parts[2]),
  );
  const token = new TextDecoder("utf-8", { fatal: true }).decode(plaintext);
  if (!/^[0-9a-f]{64}$/.test(token)) throw new Error("Invalid encrypted recruitment token");
  return token;
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

export async function createInternalE2EIntakeTokenForIdempotencyKey(idempotencyKey: string): Promise<string> {
  const secret = Deno.env.get("APPROVAL_TOKEN_SECRET");
  if (!secret) throw new Error("Missing APPROVAL_TOKEN_SECRET");
  return toBase64Url(await hmacSha256Bytes(secret, `internal-e2e-intake:v1:${idempotencyKey}`));
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

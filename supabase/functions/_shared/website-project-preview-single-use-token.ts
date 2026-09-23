// A generic, single-use, lease-bound token primitive - the building
// block underneath checkpoint §12/§16.1's "artifact-ontvangst-token" and
// §14.2's "handoff-token". Both use the same shape: mint a short-lived,
// HMAC-signed token bound to specific claims (e.g. a build id and a
// purpose), then verify + atomically consume it exactly once. The
// GitHub-Actions-OIDC-specific exchange that would issue the real
// artifact-receipt token in production is a separate, not-yet-built
// concern (checkpoint §16.6) - this module only provides the
// single-use-token mechanics themselves, fully testable locally without
// any GitHub Actions runtime.
const ENCODER = new TextEncoder();

export class WebsiteProjectPreviewTokenError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectPreviewTokenError";
  }
}

function fail(code: string): never {
  throw new WebsiteProjectPreviewTokenError(code);
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "raw",
    ENCODER.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function toHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let index = 0; index < a.length; index += 1) {
    mismatch |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }
  return mismatch === 0;
}

export type WebsiteProjectPreviewSingleUseToken = Readonly<{
  token: string;
  tokenHash: string;
  expiresAt: string;
}>;

// Mints an opaque, random, HMAC-bound single-use token for the given
// purpose+subject pair (e.g. purpose="artifact-receipt", subject=buildId)
// and TTL. Returns both the raw token (handed to the caller/runner - the
// only place it is ever transmitted) and its sha256 hash (the only form
// ever persisted, per checkpoint §14.2's "nooit het token zelf opslaan").
export async function mintWebsiteProjectPreviewSingleUseToken(
  input: Readonly<{ purpose: string; subject: string; ttlSeconds: number; secret: string }>,
): Promise<WebsiteProjectPreviewSingleUseToken> {
  if (!Number.isInteger(input.ttlSeconds) || input.ttlSeconds < 1) {
    fail("TOKEN_TTL_INVALID");
  }
  const nonce = toHex(crypto.getRandomValues(new Uint8Array(32)).buffer);
  // Epoch milliseconds, not an ISO string: the colon-delimited token
  // format below would otherwise be ambiguous, since an ISO-8601
  // timestamp itself contains colons (e.g. "...T04:15:00.000Z").
  const expiresAtMs = Date.now() + input.ttlSeconds * 1000;
  const payload = `${input.purpose}:${input.subject}:${nonce}:${expiresAtMs}`;
  const key = await hmacKey(input.secret);
  const signature = toHex(
    await crypto.subtle.sign("HMAC", key, ENCODER.encode(payload)),
  );
  const token = `${payload}:${signature}`;
  const tokenHash = toHex(await crypto.subtle.digest("SHA-256", ENCODER.encode(token)));
  return Object.freeze({ token, tokenHash, expiresAt: new Date(expiresAtMs).toISOString() });
}

// Verifies a token's HMAC signature, purpose/subject binding, and
// expiry - purely a structural/cryptographic check. Does NOT consult any
// consumption-state store; single-use enforcement is the caller's
// responsibility (typically backed by a database row keyed on
// `tokenHash`, exactly as checkpoint §14.2's session tables do) - this
// function only proves the token is authentic and not expired.
export async function verifyWebsiteProjectPreviewSingleUseToken(
  input: Readonly<{ token: string; purpose: string; subject: string; secret: string }>,
): Promise<Readonly<{ tokenHash: string }>> {
  const parts = input.token.split(":");
  if (parts.length !== 5) fail("TOKEN_MALFORMED");
  const [purpose, subject, nonce, expiresAtMsText, signature] = parts;
  if (purpose !== input.purpose || subject !== input.subject) {
    fail("TOKEN_BINDING_MISMATCH");
  }
  const expiryMs = Number(expiresAtMsText);
  if (!Number.isInteger(expiryMs) || expiryMs <= Date.now()) {
    fail("TOKEN_EXPIRED");
  }
  const payload = `${purpose}:${subject}:${nonce}:${expiresAtMsText}`;
  const key = await hmacKey(input.secret);
  const expectedSignature = toHex(
    await crypto.subtle.sign("HMAC", key, ENCODER.encode(payload)),
  );
  if (!timingSafeEqual(signature, expectedSignature)) {
    fail("TOKEN_SIGNATURE_INVALID");
  }
  const tokenHash = toHex(
    await crypto.subtle.digest("SHA-256", ENCODER.encode(input.token)),
  );
  return Object.freeze({ tokenHash });
}

// In-memory, single-use consumption tracker. A real deployment backs
// single-use enforcement with a database row (as the previewhost session
// tables already do); this in-process variant is for the artifact-
// receipt token specifically, whose lifetime is exactly one workflow
// run's "upload" job and therefore does not need cross-process/
// cross-restart durability the way a previewhost session does.
export function createInMemorySingleUseTokenLedger(): Readonly<{
  consumeOnce(tokenHash: string): boolean;
}> {
  const consumed = new Set<string>();
  return Object.freeze({
    consumeOnce(tokenHash: string): boolean {
      if (consumed.has(tokenHash)) return false;
      consumed.add(tokenHash);
      return true;
    },
  });
}

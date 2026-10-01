const GITHUB_ACTIONS_ISSUER = "https://token.actions.githubusercontent.com";
const DEFAULT_JWKS_URL = `${GITHUB_ACTIONS_ISSUER}/.well-known/jwks`;
const DIGITS = /^[1-9][0-9]*$/;

export class WebsiteDeliveryPdfOidcError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteDeliveryPdfOidcError";
  }
}

function fail(code: string): never {
  throw new WebsiteDeliveryPdfOidcError(code);
}

function decodeBase64Url(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) fail("OIDC_TOKEN_MALFORMED");
  const padded = value.replaceAll("-", "+").replaceAll("_", "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  try {
    return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
  } catch {
    return fail("OIDC_TOKEN_MALFORMED");
  }
}

function decodeJson(value: string): Record<string, unknown> {
  try {
    const decoded = new TextDecoder("utf-8", { fatal: true }).decode(decodeBase64Url(value));
    const parsed = JSON.parse(decoded);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return fail("OIDC_TOKEN_MALFORMED");
    return parsed;
  } catch (error) {
    if (error instanceof WebsiteDeliveryPdfOidcError) throw error;
    return fail("OIDC_TOKEN_MALFORMED");
  }
}

export type WebsiteDeliveryPdfOidcAuthority = Readonly<{
  audience: string;
  workflowRepository: string;
  workflowRepositoryId: string;
  workflowRef: string;
  workflowRefName: string;
  runId: string;
  runAttempt: string;
}>;

export async function verifyWebsiteDeliveryPdfOidcToken(
  token: string,
  expected: WebsiteDeliveryPdfOidcAuthority,
  dependencies: Readonly<{ fetch: typeof fetch; jwksUrl?: string; now?: () => number }>,
): Promise<WebsiteDeliveryPdfOidcAuthority> {
  if (!DIGITS.test(expected.workflowRepositoryId) || !DIGITS.test(expected.runId) || !DIGITS.test(expected.runAttempt)
    || !expected.audience || !expected.workflowRepository || !expected.workflowRef || !expected.workflowRefName) {
    fail("OIDC_AUTHORITY_INVALID");
  }
  const parts = String(token || "").split(".");
  if (parts.length !== 3) fail("OIDC_TOKEN_MALFORMED");
  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeJson(encodedHeader);
  const claims = decodeJson(encodedPayload);
  if (header.alg !== "RS256" || typeof header.kid !== "string") fail("OIDC_HEADER_INVALID");

  let response: Response;
  try {
    response = await dependencies.fetch(dependencies.jwksUrl ?? DEFAULT_JWKS_URL, {
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(5_000),
    });
  } catch {
    return fail("OIDC_JWKS_UNAVAILABLE");
  }
  if (!response.ok) fail("OIDC_JWKS_UNAVAILABLE");
  const jwks = await response.json() as { keys?: Array<JsonWebKey & { kid?: string; alg?: string }> };
  const jwk = jwks.keys?.find((candidate) => candidate.kid === header.kid
    && candidate.kty === "RSA" && (!candidate.alg || candidate.alg === "RS256"));
  if (!jwk) fail("OIDC_SIGNING_KEY_NOT_FOUND");
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
  } catch {
    return fail("OIDC_SIGNING_KEY_INVALID");
  }
  const validSignature = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    Uint8Array.from(decodeBase64Url(encodedSignature)).buffer,
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
  if (!validSignature) fail("OIDC_SIGNATURE_INVALID");

  const now = Math.floor((dependencies.now?.() ?? Date.now()) / 1000);
  if (claims.iss !== GITHUB_ACTIONS_ISSUER) fail("OIDC_ISSUER_INVALID");
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes(expected.audience)) fail("OIDC_AUDIENCE_INVALID");
  if (!Number.isInteger(claims.exp) || Number(claims.exp) <= now) fail("OIDC_TOKEN_EXPIRED");
  if (!Number.isInteger(claims.nbf) || Number(claims.nbf) > now + 30
    || !Number.isInteger(claims.iat) || Number(claims.iat) > now + 30) {
    fail("OIDC_TOKEN_TIME_INVALID");
  }
  if (claims.repository !== expected.workflowRepository
    || claims.repository_id !== expected.workflowRepositoryId) fail("OIDC_REPOSITORY_MISMATCH");
  if (claims.ref !== expected.workflowRefName) fail("OIDC_REF_MISMATCH");
  if (claims.workflow_ref !== expected.workflowRef) fail("OIDC_WORKFLOW_MISMATCH");
  if (claims.run_id !== expected.runId) fail("OIDC_RUN_MISMATCH");
  if (claims.run_attempt !== expected.runAttempt) fail("OIDC_RUN_ATTEMPT_MISMATCH");
  const subject = `repo:${expected.workflowRepository}:ref:${expected.workflowRefName}`;
  if (claims.sub !== subject) {
    fail("OIDC_SUBJECT_MISMATCH");
  }
  return Object.freeze({ ...expected });
}
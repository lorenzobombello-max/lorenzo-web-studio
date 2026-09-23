const GITHUB_ACTIONS_ISSUER = "https://token.actions.githubusercontent.com";
const DEFAULT_JWKS_URL = `${GITHUB_ACTIONS_ISSUER}/.well-known/jwks`;
const SHA = /^[0-9a-f]{40}$/;
const DIGITS = /^[1-9][0-9]*$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class WebsiteProjectPreviewOidcError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectPreviewOidcError";
  }
}

function fail(code: string): never {
  throw new WebsiteProjectPreviewOidcError(code);
}

function regexEscape(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return fail("OIDC_TOKEN_MALFORMED");
    }
    return parsed;
  } catch (error) {
    if (error instanceof WebsiteProjectPreviewOidcError) throw error;
    return fail("OIDC_TOKEN_MALFORMED");
  }
}

export type WebsiteProjectPreviewOidcAuthority = Readonly<{
  audience: string;
  workflowRepository: string;
  workflowRepositoryId: string;
  workflowRef: string;
  workflowRefName: string;
  customerRepository: string;
  customerRepositoryId: string;
  customerCommitSha: string;
  runId: string;
  leaseId: string;
  buildId: string;
}>;

export async function verifyGitHubActionsOidcToken(
  token: string,
  expected: WebsiteProjectPreviewOidcAuthority,
  dependencies: Readonly<{
    fetch: typeof fetch;
    jwksUrl?: string;
    now?: () => number;
  }>,
): Promise<WebsiteProjectPreviewOidcAuthority> {
  if (!UUID.test(expected.leaseId) || !UUID.test(expected.buildId)
    || !SHA.test(expected.customerCommitSha) || !DIGITS.test(expected.customerRepositoryId)
    || !DIGITS.test(expected.workflowRepositoryId) || !DIGITS.test(expected.runId)
    || !expected.workflowRepository || !expected.workflowRef || !expected.workflowRefName) {
    fail("OIDC_AUTHORITY_INVALID");
  }
  const parts = String(token || "").split(".");
  if (parts.length !== 3) fail("OIDC_TOKEN_MALFORMED");
  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeJson(encodedHeader);
  const claims = decodeJson(encodedPayload);
  if (header.alg !== "RS256" || typeof header.kid !== "string") {
    fail("OIDC_HEADER_INVALID");
  }
  let jwksResponse: Response;
  try {
    jwksResponse = await dependencies.fetch(dependencies.jwksUrl ?? DEFAULT_JWKS_URL, {
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(5_000),
    });
  } catch {
    return fail("OIDC_JWKS_UNAVAILABLE");
  }
  if (!jwksResponse.ok) fail("OIDC_JWKS_UNAVAILABLE");
  const jwks = await jwksResponse.json() as {
    keys?: Array<JsonWebKey & { kid?: string; alg?: string }>;
  };
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
  if (claims.repository !== expected.workflowRepository) fail("OIDC_REPOSITORY_MISMATCH");
  if (claims.repository_id !== expected.workflowRepositoryId) fail("OIDC_REPOSITORY_MISMATCH");
  if (claims.ref !== expected.workflowRefName) fail("OIDC_REF_MISMATCH");
  if (claims.workflow_ref !== expected.workflowRef) fail("OIDC_WORKFLOW_MISMATCH");
  if (claims.run_id !== expected.runId) fail("OIDC_RUN_MISMATCH");
  const [owner, repository] = expected.workflowRepository.split("/");
  const legacySubject = `repo:${expected.workflowRepository}:ref:${expected.workflowRefName}`;
  const immutableSubject = new RegExp(
    `^repo:${regexEscape(owner)}@[0-9]+/${regexEscape(repository)}@${regexEscape(expected.workflowRepositoryId)}:ref:${regexEscape(expected.workflowRefName)}$`,
  );
  if (claims.sub !== legacySubject && !immutableSubject.test(String(claims.sub || ""))) {
    fail("OIDC_SUBJECT_MISMATCH");
  }
  return Object.freeze({ ...expected });
}
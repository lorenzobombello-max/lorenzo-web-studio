type SourceTokenService = Readonly<{
  issue(input: Readonly<{
    oidcToken: string;
    leaseId: string;
    buildId: string;
    workflowRunId: string;
  }>): PromiseLike<Readonly<{ token: string; expiresAt: string }>>;
}>;

const BODY_KEYS = ["buildId", "leaseId", "workflowRunId"] as const;
const SAFE_CODES = new Set([
  "GITHUB_APP_SIGNING_FAILED",
  "GITHUB_TOKEN_AUTHORITY_INVALID",
  "GITHUB_TOKEN_EXCHANGE_FAILED",
  "GITHUB_TOKEN_FORBIDDEN",
  "GITHUB_TOKEN_RATE_LIMITED",
  "GITHUB_TOKEN_REDIRECT_DENIED",
  "GITHUB_TOKEN_RESPONSE_INVALID",
  "GITHUB_TOKEN_TIMEOUT",
  "OIDC_AUDIENCE_INVALID",
  "OIDC_AUTHORITY_INVALID",
  "OIDC_HEADER_INVALID",
  "OIDC_ISSUER_INVALID",
  "OIDC_JWKS_UNAVAILABLE",
  "OIDC_REF_MISMATCH",
  "OIDC_REPOSITORY_MISMATCH",
  "OIDC_RUN_MISMATCH",
  "OIDC_SIGNATURE_INVALID",
  "OIDC_SIGNING_KEY_INVALID",
  "OIDC_SIGNING_KEY_NOT_FOUND",
  "OIDC_SUBJECT_MISMATCH",
  "OIDC_TOKEN_EXPIRED",
  "OIDC_TOKEN_MALFORMED",
  "OIDC_TOKEN_TIME_INVALID",
  "OIDC_WORKFLOW_MISMATCH",
  "PROJECT_PREVIEW_ARTIFACT_AUTHORITY_INVALID",
  "PROJECT_PREVIEW_BUILD_AUTHORITY_INVALID",
  "PROJECT_PREVIEW_LEASE_INVALID",
]);

function json(status: number, body: unknown): Response {
  return Response.json(body, { status, headers: { "cache-control": "no-store" } });
}

function bearer(request: Request): string {
  return request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1] ?? "";
}

function hasExactBodyKeys(body: unknown): body is Record<(typeof BODY_KEYS)[number], unknown> {
  if (!body || typeof body !== "object" || Array.isArray(body)) return false;
  const keys = Object.keys(body as object).sort();
  return keys.length === BODY_KEYS.length && BODY_KEYS.every((key, index) => key === keys[index]);
}

export async function handleWebsiteProjectPreviewSourceToken(
  request: Request,
  service: SourceTokenService,
): Promise<Response> {
  if (request.method !== "POST") return json(405, { ok: false, code: "METHOD_NOT_ALLOWED" });
  const oidcToken = bearer(request);
  if (!oidcToken) return json(401, { ok: false, code: "SOURCE_TOKEN_OIDC_REQUIRED" });

  try {
    const body = await request.json();
    if (!hasExactBodyKeys(body)) {
      return json(400, { ok: false, code: "SOURCE_TOKEN_BODY_INVALID" });
    }
    const result = await service.issue({
      oidcToken,
      leaseId: String(body.leaseId ?? ""),
      buildId: String(body.buildId ?? ""),
      workflowRunId: String(body.workflowRunId ?? ""),
    });
    return json(200, { ok: true, token: result.token, expires_at: result.expiresAt });
  } catch (error) {
    const candidate = error instanceof Error ? error.message : "";
    const code = SAFE_CODES.has(candidate) ? candidate : "SOURCE_TOKEN_EXCHANGE_FAILED";
    const status = /INVALID|MISMATCH|EXPIRED|FORBIDDEN/.test(code) ? 403 : 503;
    return json(status, { ok: false, code });
  }
}

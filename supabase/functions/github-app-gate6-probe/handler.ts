const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 256;

type ProbeResult = Readonly<{
  app: Readonly<{ id: string; slug: string }>;
  repository: Readonly<{
    id: string;
    full_name: string;
    private: boolean;
    default_branch: string;
  }>;
  installation: Readonly<{
    repository_selection: "selected";
    permissions: Readonly<{ contents: "read"; metadata: "read" }>;
  }>;
}>;

export type GitHubAppGate6ProbeDependencies = Readonly<{
  now(): number;
  verifyUser(jwt: string): Promise<Readonly<{ id: string }> | null>;
  authorizeOwner(jwt: string): Promise<void>;
  executeProbe(): Promise<ProbeResult>;
}>;

class RequestError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

function response(
  status: number,
  code: string,
  extra: Record<string, unknown> = {},
): Response {
  return Response.json({ ok: status < 400, code, ...extra }, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
}

function bearer(request: Request): string {
  const match = (request.headers.get("authorization") || "").match(
    /^Bearer\s+([^\s]+)$/i,
  );
  if (!match) throw new RequestError(401, "AUTHENTICATION_REQUIRED");
  return match[1];
}

function decodeClaims(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) throw new RequestError(401, "INVALID_JWT");
  try {
    const encoded = parts[1].replaceAll("-", "+").replaceAll("_", "/")
      .padEnd(Math.ceil(parts[1].length / 4) * 4, "=");
    const value = JSON.parse(atob(encoded));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw 0;
    return value;
  } catch {
    throw new RequestError(401, "INVALID_JWT");
  }
}

async function validateBody(request: Request): Promise<void> {
  if (
    (request.headers.get("content-type") || "").split(";", 1)[0].trim()
      .toLowerCase() !== "application/json"
  ) throw new RequestError(415, "UNSUPPORTED_CONTENT_TYPE");
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new RequestError(413, "BODY_TOO_LARGE");
  }
  try {
    const value = JSON.parse(text) as Record<string, unknown>;
    if (
      !value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).length !== 1 || value.action !== "run_gate6_probe"
    ) throw 0;
  } catch {
    throw new RequestError(400, "INVALID_REQUEST");
  }
}

export async function handleGitHubAppGate6Probe(
  request: Request,
  dependencies: GitHubAppGate6ProbeDependencies,
): Promise<Response> {
  try {
    if (request.method !== "POST") {
      throw new RequestError(405, "METHOD_NOT_ALLOWED");
    }
    const token = bearer(request);
    const claims = decodeClaims(token);
    const subject = String(claims.sub || "");
    if (
      !UUID.test(subject) || typeof claims.exp !== "number" ||
      claims.exp * 1000 <= dependencies.now()
    ) throw new RequestError(401, "INVALID_JWT");
    if (claims.role === "service_role") {
      throw new RequestError(401, "HUMAN_JWT_REQUIRED");
    }
    if (claims.aal !== "aal2") throw new RequestError(403, "AAL2_REQUIRED");
    const user = await dependencies.verifyUser(token);
    if (!user || user.id !== subject) {
      throw new RequestError(401, "INVALID_JWT");
    }
    await validateBody(request);
    try {
      await dependencies.authorizeOwner(token);
    } catch {
      throw new RequestError(403, "OWNER_REQUIRED");
    }
    return response(200, "GITHUB_APP_GATE6_PROBE_PASSED", {
      result: await dependencies.executeProbe(),
    });
  } catch (error) {
    if (error instanceof RequestError) {
      return response(error.status, error.code);
    }
    return response(502, "GITHUB_APP_GATE6_PROBE_FAILED");
  }
}

export function createUnsignedTestJwt(
  claims: Record<string, unknown>,
): string {
  const encode = (value: Record<string, unknown>) =>
    btoa(JSON.stringify(value)).replaceAll("+", "-").replaceAll("/", "_")
      .replace(/=+$/, "");
  return `${encode({ alg: "none", typ: "JWT" })}.${encode(claims)}.`;
}

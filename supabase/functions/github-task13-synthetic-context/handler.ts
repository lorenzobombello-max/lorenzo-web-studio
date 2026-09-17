const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 512;

export type Task13SyntheticContextResult = Readonly<{
  website_work_context_id: string;
  workspace_id: string;
  record_classification: "internal_e2e";
  environment: "TEST";
}>;

export type Task13SyntheticContextDependencies = Readonly<{
  now(): number;
  verifyUser(jwt: string): Promise<Readonly<{ id: string }> | null>;
  authorizeOwner(jwt: string): Promise<void>;
  create(): Promise<Task13SyntheticContextResult>;
}>;

class RequestError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

function response(status: number, code: string, result?: unknown): Response {
  return Response.json({
    ok: status < 400,
    code,
    ...(result === undefined ? {} : { result }),
  }, {
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
  if (!match) throw new RequestError(401, "CALLER_VERIFICATION");
  return match[1];
}

function claims(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) throw new RequestError(403, "CALLER_VERIFICATION");
  try {
    const encoded = parts[1].replaceAll("-", "+").replaceAll("_", "/")
      .padEnd(Math.ceil(parts[1].length / 4) * 4, "=");
    const value = JSON.parse(atob(encoded));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw 0;
    return value;
  } catch {
    throw new RequestError(403, "CALLER_VERIFICATION");
  }
}

async function validateCommand(request: Request): Promise<void> {
  if (
    (request.headers.get("content-type") || "").split(";", 1)[0].trim()
      .toLowerCase() !== "application/json"
  ) throw new RequestError(415, "INVALID_REQUEST");
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    throw new RequestError(413, "INVALID_REQUEST");
  }
  try {
    const value = JSON.parse(text) as Record<string, unknown>;
    const keys = Object.keys(value).sort();
    const expected = ["action", "environment"].sort();
    if (
      keys.length !== expected.length ||
      !keys.every((key, index) => key === expected[index]) ||
      value.action !== "create_task13_synthetic_context" ||
      value.environment !== "TEST"
    ) throw 0;
  } catch {
    throw new RequestError(400, "INVALID_REQUEST");
  }
}

function projectResult(value: Task13SyntheticContextResult) {
  const keys = Object.keys(value).sort();
  const expected = [
    "environment",
    "record_classification",
    "website_work_context_id",
    "workspace_id",
  ];
  if (
    keys.length !== expected.length ||
    !keys.every((key, index) => key === expected[index]) ||
    !UUID.test(value.website_work_context_id) ||
    !UUID.test(value.workspace_id) ||
    value.record_classification !== "internal_e2e" ||
    value.environment !== "TEST"
  ) throw new Error("TASK13_SYNTHETIC_CONTEXT_RESULT_INVALID");
  return Object.freeze({ ...value });
}

export async function handleGitHubTask13SyntheticContext(
  request: Request,
  dependencies: Task13SyntheticContextDependencies,
): Promise<Response> {
  try {
    if (request.method !== "POST") {
      throw new RequestError(405, "INVALID_REQUEST");
    }
    await validateCommand(request);
    const token = bearer(request);
    const decoded = claims(token);
    const subject = String(decoded.sub || "");
    if (
      !UUID.test(subject) || typeof decoded.exp !== "number" ||
      decoded.exp * 1000 <= dependencies.now() ||
      decoded.role === "service_role"
    ) throw new RequestError(403, "CALLER_VERIFICATION");
    const user = await dependencies.verifyUser(token);
    if (!user || user.id !== subject) {
      throw new RequestError(403, "CALLER_VERIFICATION");
    }
    if (decoded.aal !== "aal2") {
      throw new RequestError(403, "AAL2_VERIFICATION");
    }
    try {
      await dependencies.authorizeOwner(token);
    } catch {
      throw new RequestError(403, "OWNER_AUTHORIZATION");
    }
    return response(
      201,
      "TASK13_SYNTHETIC_CONTEXT_CREATED",
      projectResult(await dependencies.create()),
    );
  } catch (error) {
    if (error instanceof RequestError) {
      return response(error.status, error.code);
    }
    return response(502, "TASK13_SYNTHETIC_CONTEXT_FAILED");
  }
}

export function createUnsignedTask13SyntheticJwt(
  value: Record<string, unknown>,
): string {
  const encode = (item: Record<string, unknown>) =>
    btoa(JSON.stringify(item)).replaceAll("+", "-").replaceAll("/", "_")
      .replace(/=+$/, "");
  return `${encode({ alg: "none", typ: "JWT" })}.${encode(value)}.`;
}

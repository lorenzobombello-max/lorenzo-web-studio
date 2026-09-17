import { GitHubAppGate6ProbeError } from "./probe.ts";
import {
  Gate6PreProbeError,
  type Gate6PreProbeFailedPhase,
} from "./preprobe.ts";

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
  diagnoseConfiguration(): Promise<
    Readonly<{ configuration_valid: boolean; failed_check: string | null }>
  >;
  executeProbe(): Promise<ProbeResult>;
  projectProbeResult(result: ProbeResult): ProbeResult;
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

function failureResponse(
  status: number,
  failedPhase: Gate6PreProbeFailedPhase,
): Response {
  return response(status, "GITHUB_APP_GATE6_PROBE_FAILED", {
    failed_phase: failedPhase,
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

async function validateBody(
  request: Request,
): Promise<"run_gate6_probe" | "diagnose_configuration"> {
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
    const action = value.action;
    if (
      Object.keys(value).length !== 1 ||
      !["run_gate6_probe", "diagnose_configuration"].includes(String(action))
    ) throw 0;
    return action as "run_gate6_probe" | "diagnose_configuration";
  } catch {
    throw new RequestError(400, "INVALID_REQUEST");
  }
}

export async function handleGitHubAppGate6Probe(
  request: Request,
  dependencies: GitHubAppGate6ProbeDependencies,
): Promise<Response> {
  try {
    let action: "run_gate6_probe" | "diagnose_configuration";
    try {
      if (request.method !== "POST") {
        throw new RequestError(405, "METHOD_NOT_ALLOWED");
      }
      action = await validateBody(request);
    } catch (error) {
      return failureResponse(
        error instanceof RequestError ? error.status : 400,
        "REQUEST_PARSE",
      );
    }

    const now = dependencies.now();
    let token: string;
    let claims: Record<string, unknown>;
    let subject: string;
    try {
      token = bearer(request);
      claims = decodeClaims(token);
      subject = String(claims.sub || "");
      if (
        !UUID.test(subject) || typeof claims.exp !== "number" ||
        claims.exp * 1000 <= now || claims.role === "service_role"
      ) throw new RequestError(401, "INVALID_JWT");
      const user = await dependencies.verifyUser(token);
      if (!user || user.id !== subject) {
        throw new RequestError(401, "INVALID_JWT");
      }
    } catch (error) {
      return failureResponse(
        error instanceof RequestError ? error.status : 502,
        "CALLER_VERIFICATION",
      );
    }

    if (claims.aal !== "aal2") {
      return failureResponse(403, "AAL2_VERIFICATION");
    }
    try {
      await dependencies.authorizeOwner(token);
    } catch {
      return failureResponse(403, "OWNER_AUTHORIZATION");
    }
    if (action === "diagnose_configuration") {
      return response(200, "GATE6_CONFIGURATION_DIAGNOSIS", {
        result: await dependencies.diagnoseConfiguration(),
      });
    }
    let result: ProbeResult;
    try {
      result = await dependencies.executeProbe();
    } catch (error) {
      if (
        error instanceof GitHubAppGate6ProbeError ||
        error instanceof Gate6PreProbeError
      ) throw error;
      throw new Gate6PreProbeError("PROBE_INVOCATION");
    }
    try {
      return response(200, "GITHUB_APP_GATE6_PROBE_PASSED", {
        result: dependencies.projectProbeResult(result),
      });
    } catch {
      throw new Gate6PreProbeError("RESPONSE_PROJECTION");
    }
  } catch (error) {
    if (error instanceof RequestError) {
      return response(error.status, error.code);
    }
    if (error instanceof GitHubAppGate6ProbeError) {
      return response(502, "GITHUB_APP_GATE6_PROBE_FAILED", {
        failed_phase: error.failedPhase,
        ...(error.httpStatusClass
          ? { http_status_class: error.httpStatusClass }
          : {}),
      });
    }
    if (error instanceof Gate6PreProbeError) {
      return failureResponse(502, error.failedPhase);
    }
    return response(502, "GITHUB_APP_GATE6_PROBE_FAILED", {
      failed_phase: "UNKNOWN_INTERNAL",
    });
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

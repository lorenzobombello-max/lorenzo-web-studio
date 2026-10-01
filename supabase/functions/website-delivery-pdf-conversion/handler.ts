const MAX_PDF_BYTES = 10 * 1024 * 1024;
const MAX_CLAIM_BYTES = 4096;

const PUBLIC_ERROR_STATUS = new Map<string, number>([
  ["ACTION_INVALID", 400],
  ["WEBSITE_DELIVERY_PDF_BODY_INVALID", 400],
  ["WEBSITE_DELIVERY_PDF_CONTENT_TYPE_INVALID", 400],
  ["WEBSITE_DELIVERY_PDF_REQUEST_INVALID", 400],
  ["WEBSITE_DELIVERY_PDF_CLAIM_TOO_LARGE", 413],
  ["WEBSITE_DELIVERY_PDF_TOO_LARGE", 413],
  ["OIDC_JWKS_UNAVAILABLE", 503],
  ["OIDC_SIGNING_KEY_NOT_FOUND", 503],
  ["OIDC_SIGNING_KEY_INVALID", 503],
]);

const PERMANENT_VALIDATOR_CODES = new Set([
  "WEBSITE_DELIVERY_PDF_VALIDATION_RESULT_INVALID",
  "WEBSITE_DELIVERY_GENERATION_PAYLOAD_INVALID",
  "WEBSITE_DELIVERY_PDF_SIGNATURE_INVALID",
  "WEBSITE_DELIVERY_PDF_PARSE_INVALID",
  "WEBSITE_DELIVERY_PDF_PAGE_COUNT_INVALID",
  "WEBSITE_DELIVERY_PDF_CONTENT_INVALID",
]);

const PUBLIC_FORBIDDEN_CODES = new Set([
  "OIDC_AUTHORITY_INVALID",
  "OIDC_TOKEN_MALFORMED",
  "OIDC_HEADER_INVALID",
  "OIDC_SIGNATURE_INVALID",
  "OIDC_ISSUER_INVALID",
  "OIDC_AUDIENCE_INVALID",
  "OIDC_TOKEN_EXPIRED",
  "OIDC_TOKEN_TIME_INVALID",
  "OIDC_REPOSITORY_MISMATCH",
  "OIDC_REF_MISMATCH",
  "OIDC_WORKFLOW_MISMATCH",
  "OIDC_RUN_MISMATCH",
  "OIDC_RUN_ATTEMPT_MISMATCH",
  "OIDC_SUBJECT_MISMATCH",
  "WEBSITE_DELIVERY_PDF_SESSION_INVALID",
  "WEBSITE_DELIVERY_PDF_SESSION_SIGNATURE_INVALID",
  "WEBSITE_DELIVERY_PDF_SESSION_BINDING_INVALID",
  "WEBSITE_DELIVERY_PDF_SESSION_EXPIRED",
  "WEBSITE_DELIVERY_PDF_EXECUTION_BINDING_INVALID",
  "WEBSITE_DELIVERY_PDF_CLAIM_INPUT_INVALID",
  "WEBSITE_DELIVERY_PDF_TASK_NOT_FOUND",
  "WEBSITE_DELIVERY_PDF_SOURCE_STALE",
  "WEBSITE_DELIVERY_STATE_INVALID",
  "WEBSITE_DELIVERY_ALREADY_ACCEPTED",
  "WEBSITE_DELIVERY_PDF_VIEW_ALREADY_REGISTERED",
  "WEBSITE_DELIVERY_PDF_SOURCE_OBJECT_INVALID",
  "WEBSITE_DELIVERY_PDF_CLAIM_CONFLICT",
  "WEBSITE_DELIVERY_PDF_EXECUTION_EXPIRED",
  "WEBSITE_DELIVERY_PDF_CLAIM_STALE",
  "WEBSITE_DELIVERY_PDF_COMPLETE_INPUT_INVALID",
  "WEBSITE_DELIVERY_PDF_COMPLETION_CONFLICT",
  "WEBSITE_DELIVERY_PDF_UPLOAD_CONFLICT",
  "WEBSITE_DELIVERY_PDF_READBACK_MISMATCH",
]);

type Service = Readonly<{
  claim(
    input: Readonly<{
      oidcToken: string;
      taskId: string;
      workflowRunId: string;
      workflowRunAttempt: string;
    }>,
  ): PromiseLike<unknown>;
  complete(
    input: Readonly<{
      oidcToken: string;
      sessionToken: string;
      taskId: string;
      executionId: string;
      workflowRunId: string;
      workflowRunAttempt: string;
      idempotencyKey: string;
      pdfBytes: Uint8Array;
    }>,
  ): PromiseLike<unknown>;
}>;

function json(status: number, body: unknown): Response {
  return Response.json(body, {
    status,
    headers: { "cache-control": "no-store" },
  });
}

function bearer(request: Request): string {
  return request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
}

function header(request: Request, name: string): string {
  return request.headers.get(name) ?? "";
}

async function boundedBody(request: Request): Promise<Uint8Array> {
  const declared = request.headers.get("content-length");
  const declaredLength = declared === null ? null : Number(declared);
  if (
    declaredLength !== null &&
    (!Number.isSafeInteger(declaredLength) || declaredLength < 1 ||
      declaredLength > MAX_PDF_BYTES)
  ) {
    throw new Error("WEBSITE_DELIVERY_PDF_TOO_LARGE");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new Error("WEBSITE_DELIVERY_PDF_BODY_INVALID");
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > MAX_PDF_BYTES) {
      await reader.cancel().catch(() => undefined);
      throw new Error("WEBSITE_DELIVERY_PDF_TOO_LARGE");
    }
    chunks.push(value);
  }
  if (!length || (declaredLength !== null && declaredLength !== length)) {
    throw new Error("WEBSITE_DELIVERY_PDF_BODY_INVALID");
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

async function boundedClaim(
  request: Request,
): Promise<Record<string, unknown>> {
  const declared = request.headers.get("content-length");
  const declaredLength = declared === null ? null : Number(declared);
  if (
    declaredLength !== null &&
    (!Number.isSafeInteger(declaredLength) || declaredLength < 1 ||
      declaredLength > MAX_CLAIM_BYTES)
  ) {
    throw new Error(
      declaredLength > MAX_CLAIM_BYTES
        ? "WEBSITE_DELIVERY_PDF_CLAIM_TOO_LARGE"
        : "WEBSITE_DELIVERY_PDF_REQUEST_INVALID",
    );
  }
  const reader = request.body?.getReader();
  if (!reader) throw new Error("WEBSITE_DELIVERY_PDF_REQUEST_INVALID");
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > MAX_CLAIM_BYTES) {
      await reader.cancel().catch(() => undefined);
      throw new Error("WEBSITE_DELIVERY_PDF_CLAIM_TOO_LARGE");
    }
    chunks.push(value);
  }
  if (!length || (declaredLength !== null && declaredLength !== length)) {
    throw new Error("WEBSITE_DELIVERY_PDF_REQUEST_INVALID");
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const value = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("WEBSITE_DELIVERY_PDF_REQUEST_INVALID");
    }
    return value as Record<string, unknown>;
  } catch (error) {
    if (
      error instanceof Error &&
      error.message === "WEBSITE_DELIVERY_PDF_REQUEST_INVALID"
    ) throw error;
    throw new Error("WEBSITE_DELIVERY_PDF_REQUEST_INVALID");
  }
}

function requireValues(values: readonly string[]): void {
  if (values.some((value) => !value)) {
    throw new Error("WEBSITE_DELIVERY_PDF_REQUEST_INVALID");
  }
}

export async function handleWebsiteDeliveryPdfConversion(
  request: Request,
  service: Service,
): Promise<Response> {
  if (request.method !== "POST") {
    return json(405, { ok: false, code: "METHOD_NOT_ALLOWED" });
  }
  try {
    if (new URL(request.url).searchParams.get("action") === "complete") {
      if (
        header(request, "content-type").split(";", 1)[0].toLowerCase() !==
          "application/pdf"
      ) {
        throw new Error("WEBSITE_DELIVERY_PDF_CONTENT_TYPE_INVALID");
      }
      const pdfBytes = await boundedBody(request);
      const input = {
        oidcToken: bearer(request),
        sessionToken: header(request, "x-lws-conversion-session"),
        taskId: header(request, "x-lws-task-id"),
        executionId: header(request, "x-lws-execution-id"),
        workflowRunId: header(request, "x-lws-workflow-run-id"),
        workflowRunAttempt: header(request, "x-lws-workflow-run-attempt"),
        idempotencyKey: header(request, "x-lws-idempotency-key"),
        pdfBytes,
      };
      requireValues([
        input.oidcToken,
        input.sessionToken,
        input.taskId,
        input.executionId,
        input.workflowRunId,
        input.workflowRunAttempt,
        input.idempotencyKey,
      ]);
      const result = await service.complete(input);
      return json(200, { ok: true, ...result as object });
    }
    if (
      header(request, "content-type").split(";", 1)[0].toLowerCase() !==
        "application/json"
    ) {
      throw new Error("WEBSITE_DELIVERY_PDF_CONTENT_TYPE_INVALID");
    }
    const body = await boundedClaim(request);
    if (body.action !== "claim") {
      return json(400, { ok: false, code: "ACTION_INVALID" });
    }
    const input = {
      oidcToken: bearer(request),
      taskId: String(body.taskId ?? ""),
      workflowRunId: String(body.workflowRunId ?? ""),
      workflowRunAttempt: String(body.workflowRunAttempt ?? ""),
    };
    requireValues([
      input.oidcToken,
      input.taskId,
      input.workflowRunId,
      input.workflowRunAttempt,
    ]);
    const result = await service.claim(input);
    return json(200, { ok: true, ...result as object });
  } catch (error) {
    const internalCode = error instanceof Error ? error.message : "";
    const validatorCode = internalCode.split(":", 1)[0];
    const isValidatorError = PERMANENT_VALIDATOR_CODES.has(validatorCode);
    const status = isValidatorError
      ? 422
      : PUBLIC_ERROR_STATUS.get(internalCode) ??
        (PUBLIC_FORBIDDEN_CODES.has(internalCode) ? 403 : 503);
    const code = isValidatorError
      ? validatorCode
      : PUBLIC_ERROR_STATUS.has(internalCode) ||
          PUBLIC_FORBIDDEN_CODES.has(internalCode)
      ? internalCode
      : "WEBSITE_DELIVERY_PDF_REQUEST_FAILED";
    return json(status, { ok: false, code });
  }
}

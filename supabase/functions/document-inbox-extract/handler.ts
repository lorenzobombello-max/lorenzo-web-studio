import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";

export const DOCUMENT_INBOX_BUCKET = "supplier-documents";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ERROR_CODE = /^[A-Z0-9_]{1,100}$/;
const SUPPORTED_MIME_TYPES = new Set([
  "application/pdf",
  "image/png",
  "image/jpeg",
]);
const CANDIDATE_NAMES = new Set([
  "supplier_name",
  "document_reference",
  "document_date",
  "document_type",
  "amount",
  "currency",
  "due_date",
  "vat_amount",
]);
const CANDIDATE_ALIASES: Readonly<Record<string, string>> = {
  invoice_number: "document_reference",
  invoice_date: "document_date",
};

export type ExtractionStatus = "SUCCEEDED" | "PARTIAL" | "ERROR";

export type ExtractionCandidate = Readonly<{
  value: string | number;
  confidence: number;
  evidence: string;
}>;

export type NormalizedExtractionResult = Readonly<{
  outcome: "success" | "partial" | "error";
  candidates: Readonly<Record<string, ExtractionCandidate>>;
  errorCode?: string | null;
}>;

export interface DocumentExtractionProvider {
  readonly name: string;
  readonly version: string;
  extract(
    input: Readonly<{
      bytes: Uint8Array;
      mimeType: string;
    }>,
  ): PromiseLike<NormalizedExtractionResult>;
}

export type DocumentInboxExtractionItem = Readonly<{
  id: string;
  revision: number;
  lifecycle_status: string;
  storage_bucket_id: string;
  storage_object_path: string;
  mime_type: string;
}>;

export type DocumentInboxExtractDependencies = Readonly<{
  verifyUser(jwt: string): PromiseLike<boolean>;
  authorizeOwner(jwt: string): PromiseLike<boolean>;
  getInboxItem(
    jwt: string,
    itemId: string,
  ): PromiseLike<DocumentInboxExtractionItem | null>;
  readBinary(
    input: Readonly<{
      bucket: typeof DOCUMENT_INBOX_BUCKET;
      objectPath: string;
    }>,
  ): PromiseLike<Uint8Array | null>;
  provider: DocumentExtractionProvider;
  recordExtraction(
    jwt: string,
    input: Readonly<{
      inboxItemId: string;
      expectedRevision: number;
      status: ExtractionStatus;
      provider: string | null;
      version: string | null;
      candidates: Readonly<Record<string, ExtractionCandidate>>;
      errorCode: string | null;
    }>,
  ): PromiseLike<Readonly<{ id: string; status: string; revision: number }>>;
}>;

export class DocumentInboxExtractError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

function response(
  status: number,
  code: string,
  origin: string | null,
  extra: Record<string, unknown> = {},
): Response {
  return new Response(JSON.stringify({ ok: status < 400, code, ...extra }), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    },
  });
}

function bearer(request: Request): string {
  const match = (request.headers.get("authorization") || "").match(
    /^Bearer\s+([^\s]+)$/i,
  );
  if (!match) {
    throw new DocumentInboxExtractError(401, "AUTHENTICATION_REQUIRED");
  }
  return match[1];
}

async function requestInput(
  request: Request,
): Promise<Readonly<{ itemId: string; expectedRevision: number }>> {
  if (
    (request.headers.get("content-type") || "").split(";", 1)[0].trim()
      .toLowerCase() !== "application/json"
  ) {
    throw new DocumentInboxExtractError(415, "UNSUPPORTED_CONTENT_TYPE");
  }
  let input: unknown;
  try {
    input = await request.json();
  } catch {
    throw new DocumentInboxExtractError(400, "INVALID_REQUEST_BODY");
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new DocumentInboxExtractError(400, "INVALID_REQUEST_BODY");
  }
  const value = input as Record<string, unknown>;
  const itemId = String(value.document_inbox_item_id || "");
  const expectedRevision = value.expected_revision;
  if (!UUID.test(itemId)) {
    throw new DocumentInboxExtractError(400, "INVALID_DOCUMENT_INBOX_ITEM_ID");
  }
  if (!Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 1) {
    throw new DocumentInboxExtractError(400, "INVALID_EXPECTED_REVISION");
  }
  return { itemId, expectedRevision: Number(expectedRevision) };
}

function boundedIdentity(value: string, code: string): string {
  const normalized = value.trim();
  if (!normalized || normalized.length > 100) {
    throw new DocumentInboxExtractError(502, code);
  }
  return normalized;
}

function normalizeCandidate(
  value: ExtractionCandidate,
): ExtractionCandidate {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new DocumentInboxExtractError(502, "INVALID_PROVIDER_CANDIDATE");
  }
  const candidateValue = value.value;
  const normalizedValue = typeof candidateValue === "string"
    ? candidateValue.trim()
    : candidateValue;
  const evidence = typeof value.evidence === "string"
    ? value.evidence.trim()
    : "";
  if (
    (typeof normalizedValue !== "string" &&
      typeof normalizedValue !== "number") ||
    normalizedValue === "" || !Number.isFinite(value.confidence) ||
    value.confidence < 0 || value.confidence > 1 || !evidence ||
    evidence.length > 1000
  ) {
    throw new DocumentInboxExtractError(502, "INVALID_PROVIDER_CANDIDATE");
  }
  return { value: normalizedValue, confidence: value.confidence, evidence };
}

export function normalizeExtractionResult(
  result: NormalizedExtractionResult,
): Readonly<{
  status: ExtractionStatus;
  candidates: Readonly<Record<string, ExtractionCandidate>>;
  errorCode: string | null;
}> {
  if (
    !result || typeof result !== "object" || Array.isArray(result) ||
    !["success", "partial", "error"].includes(result.outcome) ||
    !result.candidates || typeof result.candidates !== "object" ||
    Array.isArray(result.candidates)
  ) {
    throw new DocumentInboxExtractError(502, "INVALID_PROVIDER_RESULT");
  }
  const candidates: Record<string, ExtractionCandidate> = {};
  for (const [sourceName, candidate] of Object.entries(result.candidates)) {
    const name = CANDIDATE_ALIASES[sourceName] || sourceName;
    if (!CANDIDATE_NAMES.has(name) || candidates[name]) {
      throw new DocumentInboxExtractError(
        502,
        "INVALID_PROVIDER_CANDIDATE_NAME",
      );
    }
    candidates[name] = normalizeCandidate(candidate);
  }
  if (result.outcome === "error") {
    const errorCode = String(result.errorCode || "").trim().toUpperCase();
    if (!ERROR_CODE.test(errorCode)) {
      throw new DocumentInboxExtractError(502, "INVALID_PROVIDER_ERROR_CODE");
    }
    return { status: "ERROR", candidates, errorCode };
  }
  return {
    status: result.outcome === "success" && Object.keys(candidates).length > 0
      ? "SUCCEEDED"
      : "PARTIAL",
    candidates,
    errorCode: null,
  };
}

export async function handleDocumentInboxExtract(
  request: Request,
  dependencies: DocumentInboxExtractDependencies,
): Promise<Response> {
  const origin = request.headers.get("origin");
  const blocked = rejectIfOriginNotAllowed(request);
  if (blocked) return blocked;
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (request.method !== "POST") {
    return response(405, "METHOD_NOT_ALLOWED", origin);
  }

  try {
    const jwt = bearer(request);
    if (
      !await dependencies.verifyUser(jwt) ||
      !await dependencies.authorizeOwner(jwt)
    ) {
      throw new DocumentInboxExtractError(
        403,
        "DOCUMENT_INBOX_EXTRACT_OWNER_REQUIRED",
      );
    }
    const input = await requestInput(request);
    const item = await dependencies.getInboxItem(jwt, input.itemId);
    if (!item) {
      throw new DocumentInboxExtractError(404, "DOCUMENT_INBOX_ITEM_NOT_FOUND");
    }
    if (!["RECEIVED", "REVIEW_REQUIRED"].includes(item.lifecycle_status)) {
      throw new DocumentInboxExtractError(409, "DOCUMENT_INBOX_NOT_REVIEWABLE");
    }
    if (item.revision !== input.expectedRevision) {
      throw new DocumentInboxExtractError(
        409,
        "DOCUMENT_INBOX_REVISION_CONFLICT",
      );
    }
    if (
      item.storage_bucket_id !== DOCUMENT_INBOX_BUCKET ||
      !SUPPORTED_MIME_TYPES.has(item.mime_type)
    ) {
      throw new DocumentInboxExtractError(415, "UNSUPPORTED_DOCUMENT_BINARY");
    }

    let bytes: Uint8Array | null;
    try {
      bytes = await dependencies.readBinary({
        bucket: DOCUMENT_INBOX_BUCKET,
        objectPath: item.storage_object_path,
      });
    } catch {
      throw new DocumentInboxExtractError(503, "DOCUMENT_BINARY_READ_FAILED");
    }
    if (!bytes || bytes.byteLength === 0) {
      throw new DocumentInboxExtractError(404, "DOCUMENT_BINARY_NOT_FOUND");
    }

    let extraction;
    try {
      extraction = normalizeExtractionResult(
        await dependencies.provider.extract({
          bytes: new Uint8Array(bytes),
          mimeType: item.mime_type,
        }),
      );
    } catch (error) {
      if (error instanceof DocumentInboxExtractError) throw error;
      extraction = {
        status: "ERROR" as const,
        candidates: {},
        errorCode: "PROVIDER_EXECUTION_ERROR",
      };
    }
    const provider = extraction.status === "ERROR" &&
        extraction.errorCode === "PROVIDER_EXECUTION_ERROR"
      ? null
      : boundedIdentity(dependencies.provider.name, "INVALID_PROVIDER_NAME");
    const version = provider === null ? null : boundedIdentity(
      dependencies.provider.version,
      "INVALID_PROVIDER_VERSION",
    );
    const recorded = await dependencies.recordExtraction(jwt, {
      inboxItemId: item.id,
      expectedRevision: input.expectedRevision,
      status: extraction.status,
      provider,
      version,
      candidates: extraction.candidates,
      errorCode: extraction.errorCode,
    });
    return response(200, "DOCUMENT_INBOX_EXTRACTION_RECORDED", origin, {
      id: recorded.id,
      status: recorded.status,
      revision: recorded.revision,
      extraction_status: extraction.status,
      extraction_candidates: extraction.candidates,
    });
  } catch (error) {
    if (error instanceof DocumentInboxExtractError) {
      return response(error.status, error.code, origin);
    }
    return response(503, "DOCUMENT_INBOX_EXTRACTION_NOT_AVAILABLE", origin);
  }
}

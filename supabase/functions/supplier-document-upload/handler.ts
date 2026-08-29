import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";

export const SUPPLIER_DOCUMENT_BUCKET = "supplier-documents";
export const SUPPLIER_DOCUMENT_MAX_BYTES = 10 * 1024 * 1024;

export type SupplierDocumentMimeType =
  | "application/pdf"
  | "image/png"
  | "image/jpeg";
export type SupplierDocumentUploadResult = "stored" | "duplicate";

export type SupplierDocumentUploadDependencies = Readonly<{
  verifyUser(jwt: string): PromiseLike<boolean>;
  authorizeOwner(jwt: string): PromiseLike<boolean>;
  putObject(
    input: Readonly<{
      bucket: typeof SUPPLIER_DOCUMENT_BUCKET;
      objectPath: string;
      bytes: Uint8Array;
      mimeType: SupplierDocumentMimeType;
      upsert: false;
    }>,
  ): PromiseLike<SupplierDocumentUploadResult>;
  finalizeObjectMetadata(
    input: Readonly<{
      bucket: typeof SUPPLIER_DOCUMENT_BUCKET;
      objectPath: string;
      sha256: string;
      byteCount: number;
      mimeType: SupplierDocumentMimeType;
    }>,
  ): PromiseLike<void>;
}>;

class RequestError extends Error {
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
  if (!match) throw new RequestError(401, "AUTHENTICATION_REQUIRED");
  return match[1];
}

function declaredMimeType(request: Request): SupplierDocumentMimeType {
  const mimeType = (request.headers.get("content-type") || "").split(";", 1)[0]
    .trim().toLowerCase();
  if (
    mimeType !== "application/pdf" && mimeType !== "image/png" &&
    mimeType !== "image/jpeg"
  ) {
    throw new RequestError(415, "UNSUPPORTED_CONTENT_TYPE");
  }
  return mimeType;
}

function declaredLength(request: Request): number | null {
  const value = request.headers.get("content-length");
  if (value === null) return null;
  if (!/^[0-9]+$/.test(value)) {
    throw new RequestError(400, "INVALID_CONTENT_LENGTH");
  }
  const length = Number(value);
  if (!Number.isSafeInteger(length)) {
    throw new RequestError(400, "INVALID_CONTENT_LENGTH");
  }
  if (length > SUPPLIER_DOCUMENT_MAX_BYTES) {
    throw new RequestError(413, "FILE_TOO_LARGE");
  }
  return length;
}

async function readBinary(request: Request): Promise<Uint8Array> {
  if (!request.body) throw new RequestError(400, "INVALID_BINARY");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteCount += value.byteLength;
    if (byteCount > SUPPLIER_DOCUMENT_MAX_BYTES) {
      await reader.cancel();
      throw new RequestError(413, "FILE_TOO_LARGE");
    }
    chunks.push(value);
  }
  if (byteCount === 0) throw new RequestError(400, "INVALID_BINARY");
  const bytes = new Uint8Array(byteCount);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function detectMimeType(bytes: Uint8Array): SupplierDocumentMimeType | null {
  if (
    bytes.length >= 5 && new TextDecoder().decode(bytes.slice(0, 5)) === "%PDF-"
  ) return "application/pdf";
  if (
    bytes.length >= 8 &&
    [137, 80, 78, 71, 13, 10, 26, 10].every((value, index) =>
      bytes[index] === value
    )
  ) return "image/png";
  if (
    bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) return "image/jpeg";
  return null;
}

function extensionFor(
  mimeType: SupplierDocumentMimeType,
): "pdf" | "png" | "jpg" {
  if (mimeType === "application/pdf") return "pdf";
  if (mimeType === "image/png") return "png";
  return "jpg";
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const ownedBytes = new Uint8Array(bytes);
  const digest = await crypto.subtle.digest("SHA-256", ownedBytes.buffer);
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export async function handleSupplierDocumentUpload(
  request: Request,
  dependencies: SupplierDocumentUploadDependencies,
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
    const mimeType = declaredMimeType(request);
    const contentLength = declaredLength(request);
    const jwt = bearer(request);
    if (
      !await dependencies.verifyUser(jwt) ||
      !await dependencies.authorizeOwner(jwt)
    ) {
      return response(403, "SUPPLIER_DOCUMENT_UPLOAD_OWNER_REQUIRED", origin);
    }

    const bytes = await readBinary(request);
    if (contentLength !== null && contentLength !== bytes.byteLength) {
      throw new RequestError(400, "CONTENT_LENGTH_MISMATCH");
    }
    if (detectMimeType(bytes) !== mimeType) {
      throw new RequestError(415, "BINARY_MIME_MISMATCH");
    }

    const digest = await sha256(bytes);
    const objectPath = `documents/${digest}.${extensionFor(mimeType)}`;
    const uploadResult = await dependencies.putObject({
      bucket: SUPPLIER_DOCUMENT_BUCKET,
      objectPath,
      bytes,
      mimeType,
      upsert: false,
    });
    await dependencies.finalizeObjectMetadata({
      bucket: SUPPLIER_DOCUMENT_BUCKET,
      objectPath,
      sha256: digest,
      byteCount: bytes.byteLength,
      mimeType,
    });
    return response(
      200,
      uploadResult === "stored" ? "STORED" : "DUPLICATE",
      origin,
      {
        bucket: SUPPLIER_DOCUMENT_BUCKET,
        object_path: objectPath,
        sha256: digest,
        byte_count: bytes.byteLength,
        mime_type: mimeType,
      },
    );
  } catch (error) {
    if (error instanceof RequestError) {
      return response(error.status, error.code, origin);
    }
    return response(503, "UPLOAD_NOT_AVAILABLE", origin);
  }
}

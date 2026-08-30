import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";

export const RECRUITMENT_CV_BUCKET = "recruitment-cvs";
export const RECRUITMENT_CV_MAX_BYTES = 10 * 1024 * 1024;
const MAX_MULTIPART_BYTES = RECRUITMENT_CV_MAX_BYTES + 64 * 1024;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ALLOWED_FIELDS = new Set([
  "vacancy_id",
  "first_name",
  "last_name",
  "email",
  "phone",
  "motivation",
  "cv",
]);

export type RecruitmentCvMimeType =
  | "application/pdf"
  | "application/msword"
  | "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

type ApplicationInput = Readonly<{
  applicationId: string;
  vacancyId: string;
  firstName: string;
  lastName: string;
  email: string;
  phone: string | null;
  motivation: string;
  cvStoragePath: string;
  cvMimeType: RecruitmentCvMimeType;
  cvByteCount: number;
  cvSha256: string;
}>;

export type RecruitmentApplicationSubmitDependencies = Readonly<{
  createApplicationId(): string;
  putObject(
    input: Readonly<{
      bucket: typeof RECRUITMENT_CV_BUCKET;
      objectPath: string;
      bytes: Uint8Array;
      mimeType: RecruitmentCvMimeType;
      sha256: string;
      upsert: false;
    }>,
  ): PromiseLike<void>;
  finalizeApplication(input: ApplicationInput): PromiseLike<void>;
  removeObject(
    bucket: typeof RECRUITMENT_CV_BUCKET,
    objectPath: string,
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
): Response {
  return new Response(JSON.stringify({ ok: status < 400, code }), {
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

function declaredLength(request: Request): void {
  const raw = request.headers.get("content-length");
  if (raw === null) return;
  if (!/^[0-9]+$/.test(raw) || !Number.isSafeInteger(Number(raw))) {
    throw new RequestError(400, "INVALID_CONTENT_LENGTH");
  }
  if (Number(raw) > MAX_MULTIPART_BYTES) {
    throw new RequestError(413, "APPLICATION_TOO_LARGE");
  }
}

function textField(
  form: FormData,
  name: string,
  maxLength: number,
  required = true,
): string | null {
  const value = form.get(name);
  if (typeof value !== "string") {
    if (!required && value === null) return null;
    throw new RequestError(400, `INVALID_${name.toUpperCase()}`);
  }
  const normalized = value.trim();
  if ((required && normalized.length === 0) || normalized.length > maxLength) {
    throw new RequestError(400, `INVALID_${name.toUpperCase()}`);
  }
  return normalized || null;
}

function extensionFor(
  file: File,
  mimeType: RecruitmentCvMimeType,
): "pdf" | "doc" | "docx" {
  const match = file.name.toLowerCase().match(/\.([a-z0-9]+)$/);
  const extension = match?.[1];
  const expected = mimeType === "application/pdf"
    ? "pdf"
    : mimeType === "application/msword"
    ? "doc"
    : "docx";
  if (extension !== expected) {
    throw new RequestError(415, "CV_EXTENSION_MISMATCH");
  }
  return expected;
}

function cvMimeType(file: File): RecruitmentCvMimeType {
  const mimeType = file.type.trim().toLowerCase();
  if (
    mimeType !== "application/pdf" &&
    mimeType !== "application/msword" &&
    mimeType !==
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  ) throw new RequestError(415, "UNSUPPORTED_CV_TYPE");
  return mimeType;
}

function hasPrefix(bytes: Uint8Array, prefix: readonly number[]): boolean {
  return prefix.every((value, index) => bytes[index] === value);
}

function zipEntryNames(bytes: Uint8Array): Set<string> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const minimumOffset = Math.max(0, bytes.length - 65557);
  let endOffset = -1;
  for (let offset = bytes.length - 22; offset >= minimumOffset; offset--) {
    if (view.getUint32(offset, true) === 0x06054b50) {
      endOffset = offset;
      break;
    }
  }
  if (endOffset < 0) throw new Error("ZIP_END_NOT_FOUND");
  const entryCount = view.getUint16(endOffset + 10, true);
  const directorySize = view.getUint32(endOffset + 12, true);
  const directoryOffset = view.getUint32(endOffset + 16, true);
  if (directoryOffset + directorySize > endOffset) {
    throw new Error("ZIP_DIRECTORY_INVALID");
  }

  const names = new Set<string>();
  let offset = directoryOffset;
  for (let index = 0; index < entryCount; index++) {
    if (
      offset + 46 > endOffset || view.getUint32(offset, true) !== 0x02014b50
    ) {
      throw new Error("ZIP_ENTRY_INVALID");
    }
    const nameLength = view.getUint16(offset + 28, true);
    const extraLength = view.getUint16(offset + 30, true);
    const commentLength = view.getUint16(offset + 32, true);
    const nextOffset = offset + 46 + nameLength + extraLength + commentLength;
    if (nextOffset > endOffset) throw new Error("ZIP_ENTRY_BOUNDS_INVALID");
    names.add(
      new TextDecoder().decode(
        bytes.slice(offset + 46, offset + 46 + nameLength),
      ),
    );
    offset = nextOffset;
  }
  if (offset !== directoryOffset + directorySize) {
    throw new Error("ZIP_DIRECTORY_SIZE_MISMATCH");
  }
  return names;
}

function validateBinary(
  bytes: Uint8Array,
  mimeType: RecruitmentCvMimeType,
): void {
  let valid = false;
  if (mimeType === "application/pdf") {
    valid = bytes.length >= 5 &&
      new TextDecoder().decode(bytes.slice(0, 5)) === "%PDF-";
  } else if (mimeType === "application/msword") {
    valid = bytes.length >= 8 &&
      hasPrefix(bytes, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  } else if (bytes.length >= 4 && hasPrefix(bytes, [0x50, 0x4b, 0x03, 0x04])) {
    try {
      const archiveNames = zipEntryNames(bytes);
      valid = archiveNames.has("[Content_Types].xml") &&
        archiveNames.has("word/document.xml") &&
        !archiveNames.has("word/vbaProject.bin");
    } catch {
      valid = false;
    }
  }
  if (!valid) throw new RequestError(415, "CV_BINARY_MISMATCH");
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const ownedBytes = new Uint8Array(bytes);
  const digest = await crypto.subtle.digest("SHA-256", ownedBytes.buffer);
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export async function handleRecruitmentApplicationSubmit(
  request: Request,
  dependencies: RecruitmentApplicationSubmitDependencies,
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

  let uploadedPath: string | null = null;
  try {
    declaredLength(request);
    if (
      !(request.headers.get("content-type") || "").toLowerCase().startsWith(
        "multipart/form-data;",
      )
    ) {
      throw new RequestError(415, "MULTIPART_REQUIRED");
    }
    const form = await request.formData();
    for (const field of form.keys()) {
      if (!ALLOWED_FIELDS.has(field)) {
        throw new RequestError(400, "UNEXPECTED_APPLICATION_FIELD");
      }
    }

    const vacancyId = textField(form, "vacancy_id", 36) as string;
    if (!UUID_PATTERN.test(vacancyId)) {
      throw new RequestError(400, "INVALID_VACANCY_ID");
    }
    const firstName = textField(form, "first_name", 100) as string;
    const lastName = textField(form, "last_name", 100) as string;
    const email = (textField(form, "email", 254) as string).toLowerCase();
    if (!EMAIL_PATTERN.test(email)) {
      throw new RequestError(400, "INVALID_EMAIL");
    }
    const phone = textField(form, "phone", 40, false);
    const motivation = textField(form, "motivation", 5000) as string;
    const cv = form.get("cv");
    if (!(cv instanceof File) || cv.size === 0) {
      throw new RequestError(400, "CV_REQUIRED");
    }
    if (cv.size > RECRUITMENT_CV_MAX_BYTES) {
      throw new RequestError(413, "CV_TOO_LARGE");
    }

    const mimeType = cvMimeType(cv);
    const extension = extensionFor(cv, mimeType);
    const bytes = new Uint8Array(await cv.arrayBuffer());
    validateBinary(bytes, mimeType);
    const applicationId = dependencies.createApplicationId();
    if (!UUID_PATTERN.test(applicationId)) {
      throw new Error("INVALID_GENERATED_APPLICATION_ID");
    }
    const cvStoragePath = `applications/${applicationId}/cv.${extension}`;
    const cvSha256 = await sha256(bytes);

    await dependencies.putObject({
      bucket: RECRUITMENT_CV_BUCKET,
      objectPath: cvStoragePath,
      bytes,
      mimeType,
      sha256: cvSha256,
      upsert: false,
    });
    uploadedPath = cvStoragePath;
    await dependencies.finalizeApplication({
      applicationId,
      vacancyId,
      firstName,
      lastName,
      email,
      phone,
      motivation,
      cvStoragePath,
      cvMimeType: mimeType,
      cvByteCount: bytes.byteLength,
      cvSha256,
    });
    uploadedPath = null;
    return response(201, "SUBMITTED", origin);
  } catch (error) {
    if (uploadedPath !== null) {
      try {
        await dependencies.removeObject(RECRUITMENT_CV_BUCKET, uploadedPath);
      } catch {
        // Cleanup is best-effort; the application row is never finalized on this path.
      }
    }
    if (error instanceof RequestError) {
      return response(error.status, error.code, origin);
    }
    return response(503, "APPLICATION_NOT_AVAILABLE", origin);
  }
}

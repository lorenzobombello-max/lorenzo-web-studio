const MAX_PATH_BYTES = 1024;
const MAX_PATH_SEGMENTS = 64;
const MAX_SEGMENT_BYTES = 255;
const MAX_FILE_BYTES = 1_048_576;

const encoder = new TextEncoder();
const strictDecoder = new TextDecoder("utf-8", { fatal: true });

export type WebsiteProjectFilesPolicyErrorCode =
  | "INVALID_PROJECT_PATH"
  | "PROJECT_FILES_PROVIDER_RESPONSE_INVALID"
  | "PROJECT_PATH_KIND_MISMATCH"
  | "FILE_TOO_LARGE"
  | "BINARY_UNSUPPORTED"
  | "UNSUPPORTED_ENCODING"
  | "SENSITIVE_FILE_BLOCKED"
  | "SENSITIVE_CLASSIFICATION_UNAVAILABLE";

export class WebsiteProjectFilesPolicyError extends Error {
  readonly code: WebsiteProjectFilesPolicyErrorCode;

  constructor(code: WebsiteProjectFilesPolicyErrorCode) {
    super(code);
    this.name = "WebsiteProjectFilesPolicyError";
    this.code = code;
  }
}

export type WebsiteProjectPathClassification = "SAFE" | "BLOCKED_CREDENTIAL";

export type WebsiteProjectDirectoryEntry =
  | Readonly<{
    entry_type: "ENTRY";
    name: string;
    path: string;
    kind: "DIRECTORY" | "FILE" | "UNSUPPORTED";
    size_bytes: number | null;
    readability:
      | "DIRECTORY"
      | "READABLE_CANDIDATE"
      | "TOO_LARGE"
      | "SENSITIVE_BLOCKED"
      | "UNSUPPORTED";
    selectable: boolean;
  }>
  | Readonly<{
    entry_type: "BLOCKED_CREDENTIAL";
    name: "Geblokkeerd bestand";
    kind: "UNSUPPORTED";
    readability: "SENSITIVE_BLOCKED";
    selectable: false;
  }>;

export type SensitiveContentClassifier = Readonly<{
  classify(
    input: Readonly<{
      path: string;
      bytes: Uint8Array;
      text: string;
    }>,
  ): "SAFE" | "SENSITIVE" | "UNAVAILABLE";
}>;

export type WebsiteProjectFileInspection = Readonly<{
  readability: "TEXT";
  path: string;
  size_bytes: number;
  media_type: "text/plain";
  encoding: "utf-8";
  content: string;
}>;

export type WebsiteProjectDirectoryEntryInput = Readonly<{
  name: unknown;
  expectedPath: unknown;
  canonicalPath: unknown;
  mode: unknown;
  objectType: unknown;
  objectSha: unknown;
  size: unknown;
  redirected?: unknown;
  rootEscaped?: unknown;
}>;

export type WebsiteProjectFileInspectionInput = Readonly<{
  path: unknown;
  canonicalPath: unknown;
  mode: unknown;
  objectType: unknown;
  declaredSize: unknown;
  bytes: unknown;
  mediaType?: unknown;
  redirected?: unknown;
  rootEscaped?: unknown;
  classifier?: SensitiveContentClassifier;
}>;

function fail(code: WebsiteProjectFilesPolicyErrorCode): never {
  throw new WebsiteProjectFilesPolicyError(code);
}

function isValidUnicode(value: string): boolean {
  try {
    return strictDecoder.decode(encoder.encode(value)) === value;
  } catch {
    return false;
  }
}

function hasNfkcPathAmbiguity(value: string): boolean {
  return value.normalize("NFKC") !== value;
}

export function normalizeWebsiteProjectPath(
  raw: string,
  options: Readonly<{ allowRoot: boolean }>,
): string {
  if (typeof raw !== "string" || typeof options?.allowRoot !== "boolean") {
    return fail("INVALID_PROJECT_PATH");
  }
  if (raw === "") {
    if (options.allowRoot) return "";
    return fail("INVALID_PROJECT_PATH");
  }
  if (
    !isValidUnicode(raw) ||
    raw.normalize("NFC") !== raw ||
    hasNfkcPathAmbiguity(raw) ||
    /^[A-Za-z][A-Za-z0-9+.-]*:/.test(raw) ||
    raw.startsWith("/") ||
    raw.includes("\\") ||
    /[\u0000-\u001f\u007f-\u009f]/u.test(raw) ||
    /%(?:25)*(?:00|2e|2f|5c)/iu.test(raw)
  ) {
    return fail("INVALID_PROJECT_PATH");
  }

  const segments = raw.split("/");
  if (
    segments.length > MAX_PATH_SEGMENTS ||
    segments.some((segment) =>
      segment === "" ||
      segment === "." ||
      segment === ".." ||
      encoder.encode(segment).byteLength > MAX_SEGMENT_BYTES
    ) ||
    encoder.encode(raw).byteLength > MAX_PATH_BYTES
  ) {
    return fail("INVALID_PROJECT_PATH");
  }
  return raw;
}

const providerTokenBasename =
  /^\.?(?:github|gitlab|npm|provider)(?:[-_.]?token)(?:[-_.][a-z0-9][a-z0-9._-]*)?$/i;
const blockedExtensions = new Set(["pem", "key", "p12", "pfx"]);
const blockedBasenames = new Set([
  ".env",
  "id_rsa",
  "id_ed25519",
  "id_ecdsa",
  "id_dsa",
  ".git-credentials",
  ".netrc",
  ".npmrc",
  ".pypirc",
  "credentials.json",
  "service-account.json",
]);
const allowedEnvironmentTemplates = new Set([
  ".env.example",
  ".env.sample",
  ".env.template",
]);

export function classifyWebsiteProjectPath(
  path: string,
): WebsiteProjectPathClassification {
  const normalized = normalizeWebsiteProjectPath(path, { allowRoot: false });
  const segments = normalized.split("/");
  const lowerSegments = segments.map((segment) => segment.toLowerCase());
  const basename = lowerSegments.at(-1)!;
  const extension = basename.includes(".") ? basename.split(".").at(-1)! : "";

  if (
    lowerSegments.includes(".git") ||
    (lowerSegments.length === 2 && lowerSegments[0] === ".lws" &&
      basename === "project.json") ||
    blockedBasenames.has(basename) ||
    (basename.startsWith(".env.") &&
      !allowedEnvironmentTemplates.has(basename)) ||
    blockedExtensions.has(extension) ||
    providerTokenBasename.test(basename)
  ) {
    return "BLOCKED_CREDENTIAL";
  }
  return "SAFE";
}

function validObjectSha(value: unknown): value is string {
  return typeof value === "string" &&
    /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(value);
}

function validSize(value: unknown): value is number | null {
  return value === null ||
    (Number.isSafeInteger(value) && (value as number) >= 0);
}

function validateProviderPaths(
  expectedPath: unknown,
  canonicalPath: unknown,
  redirected: unknown,
  rootEscaped: unknown,
): Readonly<{ expectedPath: string; canonicalPath: string }> {
  if (
    (redirected !== undefined && typeof redirected !== "boolean") ||
    (rootEscaped !== undefined && typeof rootEscaped !== "boolean") ||
    redirected === true ||
    rootEscaped === true
  ) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  try {
    const expected = normalizeWebsiteProjectPath(String(expectedPath), {
      allowRoot: false,
    });
    const canonical = normalizeWebsiteProjectPath(String(canonicalPath), {
      allowRoot: false,
    });
    if (
      typeof expectedPath !== "string" ||
      typeof canonicalPath !== "string" ||
      expected !== canonical
    ) {
      return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
    }
    return { expectedPath: expected, canonicalPath: canonical };
  } catch {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
}

function classifyProviderObject(
  mode: unknown,
  objectType: unknown,
): "DIRECTORY" | "FILE" | "UNSUPPORTED" {
  if (mode === "040000" && objectType === "tree") return "DIRECTORY";
  if ((mode === "100644" || mode === "100755") && objectType === "blob") {
    return "FILE";
  }
  if (mode === "120000" && objectType === "blob") return "UNSUPPORTED";
  if (mode === "160000" && objectType === "commit") return "UNSUPPORTED";
  return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
}

export function classifyWebsiteProjectDirectoryEntry(
  input: WebsiteProjectDirectoryEntryInput,
): WebsiteProjectDirectoryEntry {
  if (!input || typeof input !== "object") {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  const paths = validateProviderPaths(
    input.expectedPath,
    input.canonicalPath,
    input.redirected,
    input.rootEscaped,
  );
  if (
    typeof input.name !== "string" ||
    input.name === "" ||
    input.name.includes("/") ||
    paths.canonicalPath.split("/").at(-1) !== input.name ||
    !validObjectSha(input.objectSha) ||
    !validSize(input.size)
  ) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }

  const kind = classifyProviderObject(input.mode, input.objectType);
  if (
    classifyWebsiteProjectPath(paths.canonicalPath) === "BLOCKED_CREDENTIAL"
  ) {
    return Object.freeze({
      entry_type: "BLOCKED_CREDENTIAL",
      name: "Geblokkeerd bestand",
      kind: "UNSUPPORTED",
      readability: "SENSITIVE_BLOCKED",
      selectable: false,
    });
  }
  if (kind === "DIRECTORY") {
    if (input.size !== null) {
      return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
    }
    return Object.freeze({
      entry_type: "ENTRY",
      name: input.name,
      path: paths.canonicalPath,
      kind,
      size_bytes: null,
      readability: "DIRECTORY",
      selectable: true,
    });
  }
  if (kind === "UNSUPPORTED") {
    return Object.freeze({
      entry_type: "ENTRY",
      name: input.name,
      path: paths.canonicalPath,
      kind,
      size_bytes: input.size,
      readability: "UNSUPPORTED",
      selectable: false,
    });
  }
  const tooLarge = input.size !== null && input.size > MAX_FILE_BYTES;
  return Object.freeze({
    entry_type: "ENTRY",
    name: input.name,
    path: paths.canonicalPath,
    kind,
    size_bytes: input.size,
    readability: tooLarge ? "TOO_LARGE" : "READABLE_CANDIDATE",
    selectable: !tooLarge,
  });
}

function hasBinaryBytes(bytes: Uint8Array): boolean {
  let forbiddenControls = 0;
  for (const byte of bytes) {
    if (byte === 0) return true;
    if (
      (byte < 0x20 && byte !== 0x09 && byte !== 0x0a && byte !== 0x0d) ||
      byte === 0x7f
    ) {
      forbiddenControls++;
    }
  }
  return bytes.length > 0 && forbiddenControls / bytes.length > 0.01;
}

function hasBinaryMediaType(mediaType: unknown): boolean {
  if (typeof mediaType !== "string" || mediaType === "") return false;
  const normalized = mediaType.toLowerCase().split(";", 1)[0].trim();
  return normalized === "application/octet-stream" ||
    normalized.startsWith("image/") ||
    normalized.startsWith("audio/") ||
    normalized.startsWith("video/") ||
    normalized.startsWith("font/");
}

function stripMatchingQuotes(value: string): string {
  if (value.length >= 2) {
    const first = value[0];
    const last = value.at(-1);
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return value.slice(1, -1).trim();
    }
  }
  return value;
}

function hasSensitiveAssignment(text: string): boolean {
  const sensitiveKeys = new Set([
    "password",
    "passwd",
    "secret",
    "token",
    "api_key",
    "apikey",
    "private_key",
    "client_secret",
  ]);
  const dummyValues = new Set([
    "example",
    "sample",
    "dummy",
    "changeme",
    "replace-me",
  ]);
  const pattern =
    /(?:^|[\n,{;])\s*(?:export\s+)?(?:const\s+|let\s+|var\s+)?["']?([A-Za-z][A-Za-z0-9_.-]*)["']?\s*[:=]\s*(?:"([^"\r\n]*)"|'([^'\r\n]*)'|(\$\{[^}\r\n]+\})|([^,;\r\n}]*))/gu;
  for (const match of text.matchAll(pattern)) {
    const key = match[1].toLowerCase().replace(/[.\s-]+/g, "_");
    if (!sensitiveKeys.has(key)) continue;
    const value = stripMatchingQuotes(
      (match[2] ?? match[3] ?? match[4] ?? match[5] ?? "").trim(),
    );
    if (
      value !== "" &&
      !dummyValues.has(value.toLowerCase()) &&
      !/^\$\{[^}]+\}$/u.test(value)
    ) {
      return true;
    }
  }
  return false;
}

function deterministicSensitiveClassification(
  text: string,
): "SAFE" | "SENSITIVE" {
  if (
    /-----BEGIN (?:ENCRYPTED |RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/u.test(
      text,
    )
  ) {
    return "SENSITIVE";
  }
  if (
    /(?:https?|ssh):\/\/[^\s/]+@/iu.test(text) ||
    /(?:^|\s)[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^\s]+/u.test(text)
  ) {
    return "SENSITIVE";
  }
  if (
    /(?<![A-Za-z0-9_])ghp_[A-Za-z0-9]{36}(?![A-Za-z0-9])/u.test(text) ||
    /(?<![A-Za-z0-9_])github_pat_[A-Za-z0-9_]{82}(?![A-Za-z0-9_])/u.test(
      text,
    ) ||
    /(?<![A-Za-z0-9_-])glpat-[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_-])/u.test(text) ||
    /(?<![A-Za-z0-9_])npm_[A-Za-z0-9]{36}(?![A-Za-z0-9])/u.test(text) ||
    hasSensitiveAssignment(text)
  ) {
    return "SENSITIVE";
  }
  return "SAFE";
}

function classifySensitiveContent(
  input: Readonly<{ path: string; bytes: Uint8Array; text: string }>,
  classifier?: SensitiveContentClassifier,
): "SAFE" | "SENSITIVE" | "UNAVAILABLE" {
  const deterministic = deterministicSensitiveClassification(input.text);
  if (deterministic === "SENSITIVE" || !classifier) return deterministic;
  try {
    const result = classifier.classify(input);
    if (
      result === "SAFE" || result === "SENSITIVE" || result === "UNAVAILABLE"
    ) return result;
    return "UNAVAILABLE";
  } catch {
    return "UNAVAILABLE";
  }
}

function hasUtf16Bom(bytes: Uint8Array): boolean {
  return bytes.length >= 2 &&
    ((bytes[0] === 0xff && bytes[1] === 0xfe) ||
      (bytes[0] === 0xfe && bytes[1] === 0xff));
}

function decodedUtf8(bytes: Uint8Array): string {
  if (hasUtf16Bom(bytes)) return fail("UNSUPPORTED_ENCODING");
  try {
    const text = strictDecoder.decode(bytes);
    return text.startsWith("\ufeff") ? text.slice(1) : text;
  } catch {
    return fail("UNSUPPORTED_ENCODING");
  }
}

export function inspectWebsiteProjectFile(
  input: WebsiteProjectFileInspectionInput,
): WebsiteProjectFileInspection {
  if (!input || typeof input !== "object") {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  const paths = validateProviderPaths(
    input.path,
    input.canonicalPath,
    input.redirected,
    input.rootEscaped,
  );
  if (input.mode === "120000" && input.objectType === "blob") {
    return fail("PROJECT_PATH_KIND_MISMATCH");
  }
  if (input.mode === "160000" && input.objectType === "commit") {
    return fail("PROJECT_PATH_KIND_MISMATCH");
  }
  if (
    !((input.mode === "100644" || input.mode === "100755") &&
      input.objectType === "blob")
  ) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  if (
    classifyWebsiteProjectPath(paths.canonicalPath) === "BLOCKED_CREDENTIAL"
  ) {
    return fail("SENSITIVE_FILE_BLOCKED");
  }
  if (!validSize(input.declaredSize)) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  const declaredSize = input.declaredSize;
  if (declaredSize !== null && declaredSize > MAX_FILE_BYTES) {
    return fail("FILE_TOO_LARGE");
  }
  if (!(input.bytes instanceof Uint8Array)) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  if (input.bytes.byteLength > MAX_FILE_BYTES) return fail("FILE_TOO_LARGE");
  if (
    declaredSize !== null &&
    input.bytes.byteLength !== declaredSize
  ) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  if (hasUtf16Bom(input.bytes)) return fail("UNSUPPORTED_ENCODING");
  if (hasBinaryMediaType(input.mediaType)) {
    return fail("BINARY_UNSUPPORTED");
  }

  const text = decodedUtf8(input.bytes);
  if (hasBinaryBytes(input.bytes)) return fail("BINARY_UNSUPPORTED");
  const classification = classifySensitiveContent(
    { path: paths.canonicalPath, bytes: input.bytes, text },
    input.classifier,
  );
  if (classification === "SENSITIVE") return fail("SENSITIVE_FILE_BLOCKED");
  if (classification === "UNAVAILABLE") {
    return fail("SENSITIVE_CLASSIFICATION_UNAVAILABLE");
  }

  return Object.freeze({
    readability: "TEXT",
    path: paths.canonicalPath,
    size_bytes: input.bytes.byteLength,
    media_type: "text/plain",
    encoding: "utf-8",
    content: text,
  });
}

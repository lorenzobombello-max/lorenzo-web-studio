const CURSOR_DOMAIN = "lws-website-project-files";
const CURSOR_VERSION = 1;
const CURSOR_KEY_ID = "V1";
const CURSOR_TTL_MILLISECONDS = 300_000;
const SECRET_ENVIRONMENT_VARIABLE =
  "LWS_WEBSITE_PROJECT_FILES_CURSOR_SIGNING_KEY_V1";
const SHA = /^[a-f0-9]{40}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const NUMERIC_ID = /^[1-9][0-9]{0,19}$/;
const BASE64URL = /^[A-Za-z0-9_-]+$/;

export type WebsiteProjectFilesCursorBinding = Readonly<{
  actorAuthUserId: string;
  websiteWorkContextId: string;
  repositoryExternalId: string;
  bindingRevision: number;
  commitSha: string;
  rootTreeSha: string;
  directory: string;
  directoryTreeSha: string;
  offset: number;
}>;

export type WebsiteProjectFilesCursorPayload =
  & WebsiteProjectFilesCursorBinding
  & Readonly<{
    domain: typeof CURSOR_DOMAIN;
    version: typeof CURSOR_VERSION;
    keyId: typeof CURSOR_KEY_ID;
    issuedAt: number;
    expiresAt: number;
  }>;

export type WebsiteProjectFilesCursorExpected = Readonly<
  & Pick<
    WebsiteProjectFilesCursorBinding,
    | "actorAuthUserId"
    | "websiteWorkContextId"
    | "repositoryExternalId"
    | "bindingRevision"
    | "directory"
  >
  & Partial<WebsiteProjectFilesCursorBinding>
>;

export class WebsiteProjectFilesCursorError extends Error {
  constructor(
    public readonly code:
      | "PROJECT_FILES_CURSOR_INVALID"
      | "PROJECT_FILES_CURSOR_CONFIGURATION_ERROR",
  ) {
    super(code);
    this.name = "WebsiteProjectFilesCursorError";
  }
}

type CursorDependencies = Readonly<{
  now?: number;
  secret?: string;
}>;

function invalid(): never {
  throw new WebsiteProjectFilesCursorError("PROJECT_FILES_CURSOR_INVALID");
}

function configurationError(): never {
  throw new WebsiteProjectFilesCursorError(
    "PROJECT_FILES_CURSOR_CONFIGURATION_ERROR",
  );
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_")
    .replace(/=+$/u, "");
}

function decodeBase64Url(value: string): Uint8Array {
  if (!value || !BASE64URL.test(value)) return invalid();
  try {
    const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const binary = atob(padded);
    const bytes = Uint8Array.from(
      binary,
      (character) => character.charCodeAt(0),
    );
    if (encodeBase64Url(bytes) !== value) return invalid();
    return bytes;
  } catch {
    return invalid();
  }
}

function decodeSecret(value: string | undefined): Uint8Array {
  if (!value || !BASE64URL.test(value)) return configurationError();
  try {
    const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const binary = atob(padded);
    const bytes = Uint8Array.from(
      binary,
      (character) => character.charCodeAt(0),
    );
    if (bytes.byteLength !== 32 || encodeBase64Url(bytes) !== value) {
      return configurationError();
    }
    return bytes;
  } catch {
    return configurationError();
  }
}

function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  return `{${
    Object.keys(record).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(record[key])}`
    ).join(",")
  }}`;
}

function validDirectory(value: string): boolean {
  return value === "" || value.length <= 1024 && !value.startsWith("/") &&
      !value.endsWith("/") && !value.includes("\\") &&
      value.split("/").every((segment) =>
        segment !== "" && segment !== "." && segment !== ".."
      );
}

function validBinding(value: WebsiteProjectFilesCursorBinding): boolean {
  return UUID.test(value.actorAuthUserId) &&
    UUID.test(value.websiteWorkContextId) &&
    NUMERIC_ID.test(value.repositoryExternalId) &&
    Number.isSafeInteger(value.bindingRevision) && value.bindingRevision > 0 &&
    SHA.test(value.commitSha) && SHA.test(value.rootTreeSha) &&
    validDirectory(value.directory) && SHA.test(value.directoryTreeSha) &&
    Number.isSafeInteger(value.offset) && value.offset >= 0;
}

function validExpected(value: WebsiteProjectFilesCursorExpected): boolean {
  return !!value && UUID.test(value.actorAuthUserId) &&
    UUID.test(value.websiteWorkContextId) &&
    NUMERIC_ID.test(value.repositoryExternalId) &&
    Number.isSafeInteger(value.bindingRevision) && value.bindingRevision > 0 &&
    validDirectory(value.directory) &&
    (value.commitSha === undefined || SHA.test(value.commitSha)) &&
    (value.rootTreeSha === undefined || SHA.test(value.rootTreeSha)) &&
    (value.directoryTreeSha === undefined ||
      SHA.test(value.directoryTreeSha)) &&
    (value.offset === undefined ||
      Number.isSafeInteger(value.offset) && value.offset >= 0);
}

function exactPayload(
  value: unknown,
): value is WebsiteProjectFilesCursorPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const record = value as Record<string, unknown>;
  const expectedKeys = [
    "actorAuthUserId",
    "bindingRevision",
    "commitSha",
    "directory",
    "directoryTreeSha",
    "domain",
    "expiresAt",
    "issuedAt",
    "keyId",
    "offset",
    "repositoryExternalId",
    "rootTreeSha",
    "version",
    "websiteWorkContextId",
  ];
  if (Object.keys(record).sort().join("\n") !== expectedKeys.join("\n")) {
    return false;
  }
  return record.domain === CURSOR_DOMAIN && record.version === CURSOR_VERSION &&
    record.keyId === CURSOR_KEY_ID && Number.isSafeInteger(record.issuedAt) &&
    Number.isSafeInteger(record.expiresAt) &&
    validBinding(record as WebsiteProjectFilesCursorPayload);
}

async function key(secret: Uint8Array): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(secret).buffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function now(dependencies: CursorDependencies): number {
  const value = dependencies.now ?? Date.now();
  if (!Number.isSafeInteger(value) || value < 0) return invalid();
  return value;
}

function secret(dependencies: CursorDependencies): Uint8Array {
  return decodeSecret(
    dependencies.secret ?? Deno.env.get(SECRET_ENVIRONMENT_VARIABLE),
  );
}

export async function signWebsiteProjectFilesCursor(
  binding: WebsiteProjectFilesCursorBinding,
  dependencies: CursorDependencies = {},
): Promise<string> {
  if (!validBinding(binding)) return invalid();
  const issuedAt = now(dependencies);
  const payload: WebsiteProjectFilesCursorPayload = Object.freeze({
    domain: CURSOR_DOMAIN,
    version: CURSOR_VERSION,
    keyId: CURSOR_KEY_ID,
    ...binding,
    issuedAt,
    expiresAt: issuedAt + CURSOR_TTL_MILLISECONDS,
  });
  const encodedPayload = encodeBase64Url(
    new TextEncoder().encode(canonicalJson(payload)),
  );
  const signingInput = `v1.${encodedPayload}`;
  const signature = await crypto.subtle.sign(
    "HMAC",
    await key(secret(dependencies)),
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${encodeBase64Url(new Uint8Array(signature))}`;
}

export async function verifyWebsiteProjectFilesCursor(
  cursor: string,
  expected: WebsiteProjectFilesCursorExpected,
  dependencies: CursorDependencies = {},
): Promise<WebsiteProjectFilesCursorPayload> {
  if (typeof cursor !== "string" || !validExpected(expected)) return invalid();
  const parts = cursor.split(".");
  if (parts.length !== 3 || parts[0] !== "v1") return invalid();
  const payloadBytes = decodeBase64Url(parts[1]);
  const signature = decodeBase64Url(parts[2]);
  if (signature.byteLength !== 32) return invalid();
  const verified = await crypto.subtle.verify(
    "HMAC",
    await key(secret(dependencies)),
    Uint8Array.from(signature).buffer,
    new TextEncoder().encode(`v1.${parts[1]}`),
  );
  if (!verified) return invalid();
  let payload: unknown;
  try {
    payload = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(payloadBytes),
    );
  } catch {
    return invalid();
  }
  if (!exactPayload(payload)) return invalid();
  if (
    encodeBase64Url(new TextEncoder().encode(canonicalJson(payload))) !==
      parts[1] ||
    payload.expiresAt - payload.issuedAt !== CURSOR_TTL_MILLISECONDS ||
    now(dependencies) < payload.issuedAt ||
    now(dependencies) >= payload.expiresAt
  ) return invalid();
  for (
    const field of Object.keys(
      expected,
    ) as (keyof WebsiteProjectFilesCursorBinding)[]
  ) {
    if (payload[field] !== expected[field]) return invalid();
  }
  return Object.freeze(payload);
}

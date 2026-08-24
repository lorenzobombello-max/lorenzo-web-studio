import { canonicalizePricingConfig } from "./pricing-config.ts";

export const OPERATOR_CURSOR_SECRET_NAME = "LWS_OPERATOR_CURSOR_SIGNING_KEY_V1";
export const OPERATOR_CURSOR_TTL_MS = 15 * 60 * 1000;

const DOMAIN = "lws-operator-pagination-cursor";
const VERSION = 1;
const KEY_ID = "V1";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const DOSSIER_DATE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;
const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;
const SUPPORT_REFERENCE = /^#[0-9A-F]{8}$/;
const BASE64URL = /^[A-Za-z0-9_-]+$/;
const encoder = new TextEncoder();

export type OperatorCursorRequest = Readonly<{
  zone: "ACTIVE" | "ARCHIVED" | "TRASHED" | "ACTIVE_ARCHIVED";
  operationalStatus: string | null;
  year: number | null;
  quarter: "Q1" | "Q2" | "Q3" | "Q4" | null;
  requestKind: "website" | "slimme_documentenflow" | null;
  search: string | null;
}>;

export type OperatorCursorPosition = Readonly<{
  dossierDate: string;
  quoteRequestId: string;
}>;

type CursorPayload = Readonly<{
  domain: typeof DOMAIN;
  version: typeof VERSION;
  keyId: typeof KEY_ID;
  dossierDate: string;
  quoteRequestId: string;
  filterFingerprint: string;
  issuedAt: number;
  expiresAt: number;
}>;

type CursorOptions = Readonly<{
  now?: number;
  secret?: string;
}>;

export class OperatorCursorError extends Error {
  constructor(code = "INVALID_OPERATOR_CURSOR") {
    super(code);
    this.name = "OperatorCursorError";
  }
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(value: string): Uint8Array {
  if (!value || !BASE64URL.test(value)) throw new OperatorCursorError();
  try {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
    return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
  } catch {
    throw new OperatorCursorError();
  }
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return new Uint8Array(bytes).buffer;
}

function signingSecret(explicit?: string): Uint8Array {
  const encoded = explicit ?? Deno.env.get(OPERATOR_CURSOR_SECRET_NAME);
  if (!encoded) throw new OperatorCursorError("OPERATOR_CURSOR_CONFIGURATION_ERROR");
  let secret: Uint8Array;
  try {
    secret = fromBase64Url(encoded);
  } catch {
    throw new OperatorCursorError("OPERATOR_CURSOR_CONFIGURATION_ERROR");
  }
  if (secret.byteLength !== 32) throw new OperatorCursorError("OPERATOR_CURSOR_CONFIGURATION_ERROR");
  return secret;
}

async function signingKey(secret?: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "raw",
    toArrayBuffer(signingSecret(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function identifierSearch(search: string): { mode: string; canonical: string } | null {
  if (UUID.test(search.toLowerCase())) return { mode: "UUID", canonical: search.toLowerCase() };
  const upper = search.toUpperCase();
  if (APPLICATION_REFERENCE.test(upper)) return { mode: "APPLICATION_REFERENCE", canonical: upper };
  const support = `#${upper.replace(/^#/, "")}`;
  if (SUPPORT_REFERENCE.test(support)) return { mode: "SUPPORT_REFERENCE", canonical: support };
  return null;
}

export function canonicalOperatorCursorContext(request: OperatorCursorRequest): Record<string, unknown> {
  const trimmedSearch = request.search?.trim() || null;
  const identifier = trimmedSearch ? identifierSearch(trimmedSearch) : null;
  if (identifier) {
    return {
      contractVersion: 2,
      zone: request.zone === "TRASHED" ? "TRASHED" : "ACTIVE_ARCHIVED",
      operationalStatus: null,
      year: null,
      quarter: null,
      requestKind: null,
      searchMode: identifier.mode,
      canonicalSearch: identifier.canonical,
    };
  }
  return {
    contractVersion: 2,
    zone: request.zone,
    operationalStatus: request.operationalStatus,
    year: request.year,
    quarter: request.quarter,
    requestKind: request.requestKind,
    searchMode: trimmedSearch === null ? "NONE" : "PREFIX",
    canonicalSearch: trimmedSearch?.toLowerCase() ?? null,
  };
}

export async function operatorCursorFilterFingerprint(request: OperatorCursorRequest): Promise<string> {
  const canonical = canonicalizePricingConfig(canonicalOperatorCursorContext(request));
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(canonical));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function assertPosition(position: OperatorCursorPosition): OperatorCursorPosition {
  if (!DOSSIER_DATE.test(position.dossierDate) || !UUID.test(position.quoteRequestId)) {
    throw new OperatorCursorError();
  }
  return position;
}

function assertPayload(value: unknown): CursorPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new OperatorCursorError();
  const payload = value as Record<string, unknown>;
  const keys = Object.keys(payload).sort();
  const expected = ["domain", "dossierDate", "expiresAt", "filterFingerprint", "issuedAt", "keyId", "quoteRequestId", "version"];
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index])) throw new OperatorCursorError();
  if (payload.domain !== DOMAIN || payload.version !== VERSION || payload.keyId !== KEY_ID) throw new OperatorCursorError();
  if (typeof payload.dossierDate !== "string" || !DOSSIER_DATE.test(payload.dossierDate)) throw new OperatorCursorError();
  if (typeof payload.quoteRequestId !== "string" || !UUID.test(payload.quoteRequestId)) throw new OperatorCursorError();
  if (typeof payload.filterFingerprint !== "string" || !SHA256.test(payload.filterFingerprint)) throw new OperatorCursorError();
  if (!Number.isSafeInteger(payload.issuedAt) || !Number.isSafeInteger(payload.expiresAt)) throw new OperatorCursorError();
  if ((payload.expiresAt as number) - (payload.issuedAt as number) !== OPERATOR_CURSOR_TTL_MS) throw new OperatorCursorError();
  return payload as CursorPayload;
}

export async function signOperatorCursor(
  position: OperatorCursorPosition,
  request: OperatorCursorRequest,
  options: CursorOptions = {},
): Promise<string> {
  const normalizedPosition = assertPosition(position);
  const issuedAt = options.now ?? Date.now();
  if (!Number.isSafeInteger(issuedAt)) throw new OperatorCursorError();
  const payload: CursorPayload = {
    domain: DOMAIN,
    version: VERSION,
    keyId: KEY_ID,
    dossierDate: normalizedPosition.dossierDate,
    quoteRequestId: normalizedPosition.quoteRequestId,
    filterFingerprint: await operatorCursorFilterFingerprint(request),
    issuedAt,
    expiresAt: issuedAt + OPERATOR_CURSOR_TTL_MS,
  };
  const canonicalPayload = canonicalizePricingConfig(payload);
  const payloadBytes = encoder.encode(canonicalPayload);
  const signature = await crypto.subtle.sign("HMAC", await signingKey(options.secret), payloadBytes);
  return `v1.${toBase64Url(payloadBytes)}.${toBase64Url(new Uint8Array(signature))}`;
}

export async function verifyOperatorCursor(
  cursor: string,
  request: OperatorCursorRequest,
  options: CursorOptions = {},
): Promise<OperatorCursorPosition> {
  try {
    const parts = cursor.split(".");
    if (parts.length !== 3 || parts[0] !== "v1") throw new OperatorCursorError();
    const payloadBytes = fromBase64Url(parts[1]);
    const signature = fromBase64Url(parts[2]);
    if (signature.byteLength !== 32) throw new OperatorCursorError();
    const payload = assertPayload(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(payloadBytes)));
    if (canonicalizePricingConfig(payload) !== new TextDecoder().decode(payloadBytes)) throw new OperatorCursorError();
    const valid = await crypto.subtle.verify(
      "HMAC",
      await signingKey(options.secret),
      toArrayBuffer(signature),
      toArrayBuffer(payloadBytes),
    );
    if (!valid) throw new OperatorCursorError();
    if (payload.filterFingerprint !== await operatorCursorFilterFingerprint(request)) throw new OperatorCursorError();
    const now = options.now ?? Date.now();
    if (!Number.isSafeInteger(now) || payload.issuedAt > now || payload.expiresAt <= now) throw new OperatorCursorError();
    return { dossierDate: payload.dossierDate, quoteRequestId: payload.quoteRequestId };
  } catch (error) {
    if (error instanceof OperatorCursorError && error.message === "OPERATOR_CURSOR_CONFIGURATION_ERROR") throw error;
    throw new OperatorCursorError();
  }
}

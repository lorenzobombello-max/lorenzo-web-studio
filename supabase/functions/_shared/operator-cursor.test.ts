import { assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import {
  canonicalOperatorCursorContext,
  OperatorCursorError,
  OPERATOR_CURSOR_TTL_MS,
  signOperatorCursor,
  verifyOperatorCursor,
} from "./operator-cursor.ts";

const secret = "ERERERERERERERERERERERERERERERERERERERERERE";
const now = 4_102_444_800_000;
const position = {
  dossierDate: "2099-01-02T10:20:30.123456+00:00",
  quoteRequestId: "a1000000-0000-4000-8000-000000000001",
};
const request = {
  zone: "ACTIVE_ARCHIVED" as const,
  operationalStatus: "SUBMITTED",
  year: 2099,
  quarter: "Q1" as const,
  requestKind: "website" as const,
  search: "  Example  ",
};

function decodePayload(cursor: string): Record<string, unknown> {
  const value = cursor.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(value.padEnd(Math.ceil(value.length / 4) * 4, "=")));
}

function encodePayload(payload: Record<string, unknown>, signature: string): string {
  const bytes = new TextEncoder().encode(JSON.stringify(payload));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return `v1.${btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")}.${signature}`;
}

Deno.test("operator cursor canonical context is deterministic and exact identifiers ignore navigation filters", () => {
  assertEquals(canonicalOperatorCursorContext(request), canonicalOperatorCursorContext({ ...request }));
  assertEquals(canonicalOperatorCursorContext({
    ...request,
    zone: "ACTIVE",
    search: " lws-aan-2099-0001 ",
  }), {
    contractVersion: 2,
    zone: "ACTIVE_ARCHIVED",
    operationalStatus: null,
    year: null,
    quarter: null,
    requestKind: null,
    searchMode: "APPLICATION_REFERENCE",
    canonicalSearch: "LWS-AAN-2099-0001",
  });
});

Deno.test("operator cursor signs and verifies one bounded position", async () => {
  const cursor = await signOperatorCursor(position, request, { now, secret });
  assertEquals(await verifyOperatorCursor(cursor, request, { now: now + 1, secret }), position);
  const payload = decodePayload(cursor);
  assertEquals(payload.expiresAt, now + OPERATOR_CURSOR_TTL_MS);
  assertEquals(payload.dossierDate, position.dossierDate);
  assertEquals(payload.quoteRequestId, position.quoteRequestId);
});

Deno.test("operator cursor deterministic payload has a fresh signature only when semantic input changes", async () => {
  const left = await signOperatorCursor(position, request, { now, secret });
  const right = await signOperatorCursor({ ...position }, { ...request }, { now, secret });
  assertEquals(left, right);
  assertNotEquals(left, await signOperatorCursor({ ...position, quoteRequestId: "a1000000-0000-4000-8000-000000000002" }, request, { now, secret }));
});

Deno.test("operator cursor rejects changed position, fingerprint, search, filter, expiry, and key id", async () => {
  const cursor = await signOperatorCursor(position, request, { now, secret });
  const signature = cursor.split(".")[2];
  for (const changed of [
    { dossierDate: "2099-01-03T10:20:30.123456+00:00" },
    { quoteRequestId: "a1000000-0000-4000-8000-000000000002" },
    { filterFingerprint: "0".repeat(64) },
    { keyId: "V2" },
  ]) {
    await assertRejects(
      () => verifyOperatorCursor(encodePayload({ ...decodePayload(cursor), ...changed }, signature), request, { now: now + 1, secret }),
      OperatorCursorError,
      "INVALID_OPERATOR_CURSOR",
    );
  }
  await assertRejects(() => verifyOperatorCursor(cursor, { ...request, search: "Changed" }, { now: now + 1, secret }), OperatorCursorError);
  await assertRejects(() => verifyOperatorCursor(cursor, { ...request, zone: "ACTIVE" }, { now: now + 1, secret }), OperatorCursorError);
  await assertRejects(() => verifyOperatorCursor(cursor, request, { now: now + OPERATOR_CURSOR_TTL_MS, secret }), OperatorCursorError);
});

Deno.test("operator cursor fails closed for malformed envelopes and missing or invalid secrets", async () => {
  for (const malformed of ["", "v1", "v2.a.b", "v1.@@@.@@@", "v1.e30.AA"] ) {
    await assertRejects(() => verifyOperatorCursor(malformed, request, { now, secret }), OperatorCursorError, "INVALID_OPERATOR_CURSOR");
  }
  await assertRejects(() => signOperatorCursor(position, request, { now, secret: "short" }), OperatorCursorError, "OPERATOR_CURSOR_CONFIGURATION_ERROR");
  const previous = Deno.env.get("LWS_OPERATOR_CURSOR_SIGNING_KEY_V1");
  Deno.env.delete("LWS_OPERATOR_CURSOR_SIGNING_KEY_V1");
  try {
    await assertRejects(() => signOperatorCursor(position, request, { now }), OperatorCursorError, "OPERATOR_CURSOR_CONFIGURATION_ERROR");
  } finally {
    if (previous === undefined) Deno.env.delete("LWS_OPERATOR_CURSOR_SIGNING_KEY_V1");
    else Deno.env.set("LWS_OPERATOR_CURSOR_SIGNING_KEY_V1", previous);
  }
});

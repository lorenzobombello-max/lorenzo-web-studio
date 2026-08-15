import { assert, assertEquals, assertNotEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { buildQuotationAcceptanceUrl, createQuotationAcceptanceCapability, createQuotationAcceptanceCapabilityToken, hashQuotationAcceptanceCapabilityToken, validateQuotationAcceptanceCapabilityToken } from "./quotation-acceptance-capability.ts";

const previous = Deno.env.get("QUOTATION_ACCEPTANCE_CAPABILITY_SECRET");
Deno.test({ name: "capability uses 256-bit opaque randomness", fn() {
  const first = createQuotationAcceptanceCapabilityToken();
  const second = createQuotationAcceptanceCapabilityToken();
  assertEquals(first.length, 43); assertEquals(second.length, 43); assertNotEquals(first, second);
  assert(/^[A-Za-z0-9_-]{43}$/.test(first));
} });
Deno.test({ name: "capability digest is deterministic and not plaintext", async fn() {
  Deno.env.set("QUOTATION_ACCEPTANCE_CAPABILITY_SECRET", "s".repeat(32));
  const token = "A".repeat(43); const first = await hashQuotationAcceptanceCapabilityToken(token);
  assertEquals(first, await hashQuotationAcceptanceCapabilityToken(token)); assertEquals(first.length, 64); assert(!first.includes(token));
} });
Deno.test({ name: "capability URL keeps secret in fragment", fn() {
  const token = "B".repeat(43); const url = new URL(buildQuotationAcceptanceUrl(token));
  assertEquals(url.search, ""); assertEquals(new URLSearchParams(url.hash.slice(1)).get("token"), token);
} });
Deno.test({ name: "capability rejects malformed tokens and weak secret", async fn() {
  assertThrows(() => validateQuotationAcceptanceCapabilityToken("bad"));
  Deno.env.set("QUOTATION_ACCEPTANCE_CAPABILITY_SECRET", "short");
  await assertRejects(() => hashQuotationAcceptanceCapabilityToken("C".repeat(43)));
} });
Deno.test({ name: "restore capability environment", fn() {
  if (previous === undefined) Deno.env.delete("QUOTATION_ACCEPTANCE_CAPABILITY_SECRET"); else Deno.env.set("QUOTATION_ACCEPTANCE_CAPABILITY_SECRET", previous);
} });
Deno.test({ name: "trusted creation sends digest only and returns plaintext once", async fn() {
  Deno.env.set("QUOTATION_ACCEPTANCE_CAPABILITY_SECRET", "s".repeat(32));
  let parameters: Record<string, unknown> = {};
  const created = await createQuotationAcceptanceCapability({ async rpc(_name, value) {
    parameters = value;
    return { data: [{ capability_id: "d3e99000-0000-4000-8000-000000000001", expires_at: "2099-01-01T00:00:00Z", was_created: true }], error: null };
  } }, { issuanceId: "d3e96000-0000-4000-8000-000000000001", requestedExpiresAt: null, idempotencyKey: "d3e99000-0000-4000-8000-000000000002", adminAccessTokenHash: "f".repeat(64), createdBy: "admin:test" });
  assertEquals(created.token.length, 43); assertEquals(parameters.p_token_digest, created.tokenDigest);
  assert(!JSON.stringify(parameters).includes(created.token));
} });
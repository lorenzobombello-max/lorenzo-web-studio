import { assert, assertEquals, assertNotEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { buildCustomerRequestUploadUrl, createCustomerRequestUploadCapabilityToken, deriveCustomerRequestUploadCapabilityToken, hashCustomerRequestUploadCapabilityToken, validateCustomerRequestUploadCapabilityToken } from "./customer-request-upload-capability.ts";

Deno.test("upload capability uses 256-bit opaque randomness", () => {
  const first = createCustomerRequestUploadCapabilityToken();
  const second = createCustomerRequestUploadCapabilityToken();
  assertEquals(first.length, 43);
  assertNotEquals(first, second);
});

Deno.test("upload capability digest is deterministic and domain-separated", async () => {
  Deno.env.set("CUSTOMER_REQUEST_UPLOAD_CAPABILITY_SECRET", "u".repeat(32));
  const token = "A".repeat(43);
  const digest = await hashCustomerRequestUploadCapabilityToken(token);
  assertEquals(digest, await hashCustomerRequestUploadCapabilityToken(token));
  assertEquals(digest.length, 64);
  assert(!digest.includes(token));
});

Deno.test("upload capability URL uses only the fragment", () => {
  const token = "B".repeat(43);
  const url = new URL(buildCustomerRequestUploadUrl(token));
  assertEquals(url.search, "");
  assertEquals(new URLSearchParams(url.hash.slice(1)).get("token"), token);
});

Deno.test("operator create derives the same opaque capability for an idempotent retry", async () => {
  Deno.env.set("CUSTOMER_REQUEST_UPLOAD_CAPABILITY_SECRET", "u".repeat(32));
  const requestId = "ca020000-0000-4000-8000-000000000001";
  const key = "ca100000-0000-4000-8000-000000000001";
  const first = await deriveCustomerRequestUploadCapabilityToken(requestId, key);
  assertEquals(first, await deriveCustomerRequestUploadCapabilityToken(requestId, key));
  assertEquals(first.length, 43);
});

Deno.test("upload capability rejects malformed token and weak secret", async () => {
  assertThrows(() => validateCustomerRequestUploadCapabilityToken("bad"));
  Deno.env.set("CUSTOMER_REQUEST_UPLOAD_CAPABILITY_SECRET", "short");
  await assertRejects(() => hashCustomerRequestUploadCapabilityToken("C".repeat(43)));
});
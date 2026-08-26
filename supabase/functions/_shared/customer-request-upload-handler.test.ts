import { assert, assertEquals } from "jsr:@std/assert@1";
import { handleCustomerRequestUpload, type CustomerRequestUploadRpcClient, type CustomerRequestUploadStorage } from "./customer-request-upload-handler.ts";

const token = "A".repeat(43);
function setup(states: Record<string, unknown>) {
  Deno.env.set("CUSTOMER_REQUEST_UPLOAD_CAPABILITY_SECRET", "u".repeat(32));
  const calls: Array<{ name: string; parameters: Record<string, unknown> }> = [];
  const client: CustomerRequestUploadRpcClient = { async rpc(name, parameters) {
    calls.push({ name, parameters });
    if (name === "consume_acceptance_capability_rate_limit_v1") return { data: true, error: null };
    return { data: states[name], error: null };
  } };
  const storageCalls: string[] = [];
  const storage: CustomerRequestUploadStorage = {
    async createSignedUploadUrl(_bucket, _path) { storageCalls.push("sign"); return { data: { signedUrl: "https://storage.test/signed" }, error: null }; },
    async download(_bucket, _path) { storageCalls.push("download"); return { data: new Blob([new TextEncoder().encode("%PDF-test")], { type: "application/pdf" }), error: null }; },
    async remove(_bucket, _paths) { storageCalls.push("remove"); return { error: null }; },
  };
  return { client, storage, calls, storageCalls };
}

Deno.test("resolve returns safe capability projection", async () => {
  const harness = setup({ resolve_customer_request_upload_capability_v1: { state: "ACTIVE", request_reference: "LWS-VRZ-2099-0001", files: [] } });
  const response = await handleCustomerRequestUpload(new Request("https://example.test", { headers: { Authorization: `Bearer ${token}` } }), harness.client, harness.storage);
  const body = await response.json();
  assertEquals(body.state, "ACTIVE");
  assertEquals(response.headers.get("cache-control"), "no-store");
  assert(!JSON.stringify(body).includes("token_digest"));
});

Deno.test("prepare signs only the server-returned quarantine path", async () => {
  const harness = setup({ prepare_customer_request_upload_v1: { state: "PREPARED", file_id: "ca070000-0000-4000-8000-000000000001", storage_bucket_id: "customer-request-quarantine", storage_object_path: "requests/server/uploads/server/files/file.pdf" } });
  const request = new Request("https://example.test", { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "Idempotency-Key": "ca100000-0000-4000-8000-000000000001" }, body: JSON.stringify({ action: "prepare", file_name: "bewijs.pdf", content_type: "application/pdf", byte_count: 42 }) });
  const body = await (await handleCustomerRequestUpload(request, harness.client, harness.storage)).json();
  assertEquals(body.signed_upload_url, "https://storage.test/signed");
  assertEquals(body.storage_object_path, undefined);
  assertEquals(harness.storageCalls, ["sign"]);
  assertEquals(Object.hasOwn(harness.calls.at(-1)?.parameters || {}, "customer_request_id"), false);
});

Deno.test("finalize downloads the bound object and sends trusted observations", async () => {
  const harness = setup({ finalize_customer_request_uploaded_file_v1: { state: "PREPARED", storage_bucket_id: "customer-request-quarantine", storage_object_path: "requests/server/file.pdf", declared_content_type: "application/pdf", declared_byte_count: 9 } });
  let finalCalls = 0;
  harness.client.rpc = async (name, parameters) => {
    harness.calls.push({ name, parameters });
    if (name === "consume_acceptance_capability_rate_limit_v1") return { data: true, error: null };
    if (name === "finalize_customer_request_uploaded_file_v1" && finalCalls++ === 0) return { data: { state: "PREPARED", storage_bucket_id: "customer-request-quarantine", storage_object_path: "requests/server/file.pdf", declared_content_type: "application/pdf", declared_byte_count: 9 }, error: null };
    return { data: { state: "ACTIVE", accepted_file_count: 1, files: [] }, error: null };
  };
  const request = new Request("https://example.test", { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "Idempotency-Key": "ca100000-0000-4000-8000-000000000002" }, body: JSON.stringify({ action: "finalize", file_id: "ca070000-0000-4000-8000-000000000001" }) });
  const body = await (await handleCustomerRequestUpload(request, harness.client, harness.storage)).json();
  assertEquals(body.state, "ACTIVE");
  assertEquals(harness.storageCalls, ["download"]);
  const final = harness.calls.at(-1)?.parameters || {};
  assertEquals(final.p_observed_byte_count, 9);
  assertEquals(final.p_signature_valid, true);
  assertEquals(typeof final.p_sha256, "string");
});

Deno.test("magic-byte rejection removes quarantine object and hides path", async () => {
  const harness = setup({});
  harness.storage.download = async () => ({ data: new Blob([new Uint8Array([1, 2, 3])], { type: "image/png" }), error: null });
  let finalCalls = 0;
  harness.client.rpc = async (name, _parameters) => {
    if (name === "consume_acceptance_capability_rate_limit_v1") return { data: true, error: null };
    if (finalCalls++ === 0) return { data: { state: "PREPARED", storage_bucket_id: "customer-request-quarantine", storage_object_path: "requests/server/file.png", declared_content_type: "image/png", declared_byte_count: 3 }, error: null };
    return { data: { state: "REJECTED", delete_object: true, storage_object_path: "requests/server/file.png" }, error: null };
  };
  const request = new Request("https://example.test", { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "Idempotency-Key": "ca100000-0000-4000-8000-000000000003" }, body: JSON.stringify({ action: "finalize", file_id: "ca070000-0000-4000-8000-000000000001" }) });
  const body = await (await handleCustomerRequestUpload(request, harness.client, harness.storage)).json();
  assertEquals(body.state, "REJECTED");
  assertEquals(body.storage_object_path, undefined);
  assertEquals(harness.storageCalls, ["remove"]);
});

Deno.test("invalid bearer and forged object path are denied", async () => {
  const harness = setup({});
  const invalid = await handleCustomerRequestUpload(new Request("https://example.test", { headers: { Authorization: "Bearer bad" } }), harness.client, harness.storage);
  assertEquals((await invalid.json()).state, "INVALID_OR_EXPIRED_LINK");
  const forged = new Request("https://example.test", { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "Idempotency-Key": "ca100000-0000-4000-8000-000000000004" }, body: JSON.stringify({ action: "finalize", file_id: "ca070000-0000-4000-8000-000000000001", storage_object_path: "forged" }) });
  assertEquals((await handleCustomerRequestUpload(forged, harness.client, harness.storage)).status, 400);
});
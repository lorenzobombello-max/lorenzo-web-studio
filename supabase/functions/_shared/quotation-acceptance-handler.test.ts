import { assert, assertEquals } from "jsr:@std/assert@1";
import { handleQuotationAcceptance, type AcceptanceRpcClient } from "./quotation-acceptance-handler.ts";

const token = "A".repeat(43);
function restoreSecret() {
  Deno.env.set("QUOTATION_ACCEPTANCE_CAPABILITY_SECRET", "s".repeat(32));
}
function client(states: Record<string, unknown>): AcceptanceRpcClient & { calls: string[] } {
  const calls: string[] = [];
  return { calls, async rpc(name) { calls.push(name); if (name === "consume_acceptance_capability_rate_limit_v1") return { data: true, error: null }; return { data: states[name], error: null }; } };
}
Deno.test("public resolve returns minimized safe projection and security headers", async () => {
  restoreSecret();
  const c = client({ resolve_quotation_acceptance_capability_v1: { state: "ACTIVE", quotation: { number: "LWS-OFF-2099-0001", customer: { legal_name: "Customer" } }, acceptance_terms: { terms_id: "terms", terms_version: "1" } } });
  const response = await handleQuotationAcceptance(new Request("https://example.test", { headers: { Authorization: `Bearer ${token}` } }), c);
  const body = await response.json(); assertEquals(body.state, "ACTIVE"); assertEquals(response.headers.get("referrer-policy"), "no-referrer"); assertEquals(response.headers.get("cache-control"), "no-store");
  const serialized = JSON.stringify(body); for (const key of ["token_digest", "template_sha256", "docx_sha256", "generation_payload_sha256", "approval_id"]) assert(!serialized.includes(key));
});
Deno.test("public submit requires explicit evidence and idempotency", async () => {
  restoreSecret();
  const c = client({ submit_quotation_acceptance_capability_v1: { state: "ACCEPTED", acceptance_id: "d3e80000-0000-4000-8000-000000000001" } });
  const response = await handleQuotationAcceptance(new Request("https://example.test", { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "Idempotency-Key": "d3e89000-0000-4000-8000-000000000001" }, body: JSON.stringify({ terms_id: "terms", terms_version: "1", accepting_name: "Name", accepting_email: "name@example.test", accepting_organization: null, accepting_role: null, authority_declaration: true }) }), c);
  assertEquals((await response.json()).state, "ACCEPTED"); assertEquals(c.calls.at(-1), "submit_quotation_acceptance_capability_v1");
});
Deno.test("invalid token and invalid origin fail without token echo", async () => {
  restoreSecret();
  const c = client({}); const invalid = await handleQuotationAcceptance(new Request("https://example.test", { headers: { Authorization: "Bearer bad" } }), c);
  assertEquals((await invalid.json()).state, "INVALID_OR_EXPIRED_LINK");
  const blocked = await handleQuotationAcceptance(new Request("https://example.test", { headers: { Authorization: `Bearer ${token}`, Origin: "https://evil.test" } }), c);
  assertEquals(blocked.status, 403); assert(!await blocked.text().then((text) => text.includes(token)));
});
Deno.test("resolve is read-only and rate limit fails closed", async () => {
  restoreSecret();
  const c: AcceptanceRpcClient = { async rpc(name) { return name === "consume_acceptance_capability_rate_limit_v1" ? { data: false, error: null } : { data: null, error: null }; } };
  const response = await handleQuotationAcceptance(new Request("https://example.test", { headers: { Authorization: `Bearer ${token}` } }), c); assertEquals(response.status, 429);
});
Deno.test("confirmation failure cannot roll back committed acceptance", async () => {
  restoreSecret();
  const c = client({ submit_quotation_acceptance_capability_v1: { state: "ACCEPTED", acceptance_id: "d3e80000-0000-4000-8000-000000000001" } });
  const response = await handleQuotationAcceptance(new Request("https://example.test", { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "Idempotency-Key": "d3e89000-0000-4000-8000-000000000001" }, body: JSON.stringify({ terms_id: "terms", terms_version: "1", accepting_name: "Name", accepting_email: "name@example.test", accepting_organization: null, accepting_role: null, authority_declaration: true }) }), c, async () => { throw new Error("mock provider failure"); });
  const body = await response.json();
  assertEquals(response.status, 200); assertEquals(body.state, "ACCEPTED"); assertEquals(body.confirmation_status, "failed");
});
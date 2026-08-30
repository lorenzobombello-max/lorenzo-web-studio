import { assertEquals } from "jsr:@std/assert@1";
import { handleApplicationIntakeAutomation, hasCanonicalSdfConfirmationTemplate, type AutomationClaim, websiteIntakeOutcome, websiteTypeOrNull } from "./handler.ts";

const secret = "x".repeat(32);
function request() { return new Request("https://example.test/worker", { method: "POST", headers: { "content-type": "application/json", "x-lws-automation-secret": secret }, body: '{"version":1}' }); }
function dependencies(claims: AutomationClaim[]) {
  const phases: string[] = [];
  return { phases, value: {
    configurationReady: true, workerSecret: secret,
    randomUUID: () => "11111111-1111-4111-8111-111111111111",
    digest: async (data: Uint8Array) => await crypto.subtle.digest("SHA-256", Uint8Array.from(data)),
    rpc: async (name: string) => ({ data: name.startsWith("claim_") ? claims : [{ outcome: "retry_scheduled" }], error: null }),
    executeWebsite: async (claim: AutomationClaim) => { phases.push(claim.phase); return { status: "sent" as const }; },
    executeSdfConfirmation: async (claim: AutomationClaim) => { phases.push(claim.phase); return { status: "sent" as const }; },
    executeSdfInvitation: async (claim: AutomationClaim) => { phases.push(claim.phase); return { status: "sent" as const }; },
    executeQueuedSdfEmail: async (): Promise<{ status: "sent" | "retry_wait" } | null> => null,
  } };
}

Deno.test("worker rejects invalid secret", async () => {
  const fixture = dependencies([]);
  const invalid = request(); invalid.headers.set("x-lws-automation-secret", "wrong");
  assertEquals((await handleApplicationIntakeAutomation(invalid, fixture.value)).status, 401);
});

Deno.test("worker dispatches Website and SDF phases without fallback", async () => {
  const fixture = dependencies([
    { work_id: 1, quote_request_id: "22222222-2222-4222-8222-222222222222", phase: "APPROVAL", claim_token: "33333333-3333-4333-8333-333333333333" },
    { work_id: 2, quote_request_id: "44444444-4444-4444-8444-444444444444", phase: "SDF_CONFIRMATION", claim_token: "55555555-5555-4555-8555-555555555555" },
    { work_id: 3, quote_request_id: "66666666-6666-4666-8666-666666666666", phase: "SDF_INTAKE", claim_token: "77777777-7777-4777-8777-777777777777" },
  ]);
  const response = await handleApplicationIntakeAutomation(request(), fixture.value);
  assertEquals(response.status, 200);
  assertEquals(fixture.phases, ["APPROVAL", "SDF_CONFIRMATION", "SDF_INTAKE"]);
  assertEquals(await response.json(), { ok: true, claimed: 3, completed: 3, retry_scheduled: 0, manual_review: 0 });
});

Deno.test("worker accounts for one independently queued SDF email", async () => {
  const fixture = dependencies([]);
  fixture.value.executeQueuedSdfEmail = async () => ({ status: "retry_wait" as const });
  const response = await handleApplicationIntakeAutomation(request(), fixture.value);
  assertEquals(await response.json(), { ok: true, claimed: 0, completed: 0, retry_scheduled: 1, manual_review: 0 });
});

Deno.test("Website authority helpers preserve exact normal stopped and nullable semantics", () => {
  assertEquals(websiteIntakeOutcome({
    outcome: "intake_completed",
    invitation_job_id: "88888888-8888-4888-8888-888888888888",
    intake_id: "99999999-9999-4999-8999-999999999999",
    request_name: "Website klant",
    request_email: "website@example.test",
    request_company: null,
    access_token_expires_at: "2099-01-01T00:00:00Z",
  }), "deliver");
  assertEquals(websiteIntakeOutcome({
    outcome: "stopped",
    invitation_job_id: null,
    intake_id: "99999999-9999-4999-8999-999999999999",
    access_token_expires_at: "2099-01-01T00:00:00Z",
  }), "stopped");
  assertEquals(websiteIntakeOutcome({ outcome: "unknown" }), "invalid");
  assertEquals(websiteTypeOrNull(null), null);
  assertEquals(websiteTypeOrNull("Website op maat"), "Website op maat");
});

Deno.test("Website stopped authority fails closed before delivery when malformed", () => {
  assertEquals(websiteIntakeOutcome({ outcome: "stopped" }), "invalid");
  assertEquals(websiteIntakeOutcome({ outcome: "stopped", invitation_job_id: "88888888-8888-4888-8888-888888888888", intake_id: "99999999-9999-4999-8999-999999999999", access_token_expires_at: "2099-01-01T00:00:00Z" }), "invalid");
  assertEquals(websiteIntakeOutcome({ outcome: "stopped", invitation_job_id: null, intake_id: "not-a-uuid", access_token_expires_at: "2099-01-01T00:00:00Z" }), "invalid");
  assertEquals(websiteIntakeOutcome({ outcome: "stopped", invitation_job_id: null, intake_id: "99999999-9999-4999-8999-999999999999", access_token_expires_at: "not-a-timestamp" }), "invalid");
});

Deno.test("SDF confirmation accepts only its persisted template authority", () => {
  assertEquals(hasCanonicalSdfConfirmationTemplate({ template_key: "SDF_REQUEST_RECEIVED_NL_BE_v1", template_version: "v1" }), true);
  assertEquals(hasCanonicalSdfConfirmationTemplate({ template_key: "SDF_REQUEST_RECEIVED_NL_BE_v1", template_version: "v2" }), false);
  assertEquals(hasCanonicalSdfConfirmationTemplate({ template_key: "WEBSITE_CONFIRMATION", template_version: "v1" }), false);
});
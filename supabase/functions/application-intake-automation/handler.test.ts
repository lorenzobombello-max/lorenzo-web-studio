import { assertEquals } from "jsr:@std/assert@1";
import type { EmailDeliveryResult } from "../_shared/email-delivery.ts";
import type {
  ResendTransportInput,
  ResendTransportResult,
} from "../_shared/resend-transport.ts";
import { sendEmailViaResend } from "../_shared/resend-transport.ts";
import { handleApplicationIntakeAutomation, hasCanonicalSdfConfirmationTemplate, sdfInvitationOutcome, type AutomationClaim, websiteIntakeOutcome, websiteTypeOrNull } from "./handler.ts";

const sdfClaim: AutomationClaim = {
  work_id: 2,
  quote_request_id: "44444444-4444-4444-8444-444444444444",
  phase: "SDF_CONFIRMATION",
  claim_token: "55555555-5555-4555-8555-555555555555",
};
const sdfJobId = "88888888-8888-4888-8888-888888888888";
const sdfLeaseToken = "99999999-9999-4999-8999-999999999999";

interface TestSdfDependencies {
  authorityMode: string | undefined;
  resendApiKey: string;
  fromEmail: string;
  rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
  deliverLegacy(input: {
    jobId: string;
    email: ResendTransportInput;
  }): Promise<EmailDeliveryResult>;
  sendTransport(input: ResendTransportInput): Promise<ResendTransportResult>;
}

async function sdfExecutorFactory() {
  Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");
  return (await import("./index.ts")).createSdfConfirmationExecutor;
}

async function sdfInvitationExecutorFactory() {
  Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");
  return (await import("./index.ts")).createSdfInvitationExecutor;
}

function isolatedDependencies(
  transportResult: ResendTransportResult = {
    ok: true,
    providerMessageId: "provider-message-1",
  },
) {
  const calls: Array<{ name: string; parameters: Record<string, unknown> }> = [];
  const transportInputs: ResendTransportInput[] = [];
  const value: TestSdfDependencies = {
    authorityMode: "isolated",
    resendApiKey: "resend-test-key",
    fromEmail: "Lorenzo Web Solutions <noreply@example.test>",
    rpc: async (name, parameters) => {
      calls.push({ name, parameters });
      if (name === "prepare_sdf_initial_confirmation_v2") {
        return {
          data: [{
            outcome: "due",
            authority_source: "sdf_initial",
            job_id: sdfJobId,
            request_kind: "slimme_documentenflow",
          }],
          error: null,
        };
      }
      if (name === "claim_sdf_initial_confirmation_email_job_v1") {
        return {
          data: [{
            job_id: sdfJobId,
            request_name: "SDF klant",
            request_email: "customer@example.test",
            application_reference: null,
            template_version: "SDF_REQUEST_RECEIVED_NL_BE_v1",
            attempt_count: 1,
            provider_idempotency_key:
              `sdf-initial-confirmation/${sdfJobId}`,
            delivery_lease_token: sdfLeaseToken,
          }],
          error: null,
        };
      }
      if (name === "resolve_sdf_support_reference_v1") {
        return { data: "#A1B2C3D4", error: null };
      }
      if (name === "validate_sdf_initial_confirmation_email_delivery_v1") {
        return { data: true, error: null };
      }
      if (name === "complete_sdf_initial_confirmation_email_job_v1") {
        return {
          data: {
            status: transportResult.ok
              ? "sent"
              : transportResult.retryable
              ? "retry_wait"
              : "failed",
            attempt_count: 1,
          },
          error: null,
        };
      }
      throw new Error(`unexpected RPC: ${name}`);
    },
    deliverLegacy: async () => ({
      status: "sent",
      attempted: true,
      attemptCount: 1,
    }),
    sendTransport: async (input) => {
      transportInputs.push(input);
      return transportResult;
    },
  };
  return { calls, transportInputs, value };
}

const secret = "x".repeat(32);
function request(body = '{"version":1}') { return new Request("https://example.test/worker", { method: "POST", headers: { "content-type": "application/json", "x-lws-automation-secret": secret }, body }); }
function dependencies(claims: AutomationClaim[]) {
  const phases: string[] = [];
  return { phases, value: {
    configurationReady: true, workerSecret: secret,
    randomUUID: () => "11111111-1111-4111-8111-111111111111",
    digest: async (data: Uint8Array) => await crypto.subtle.digest("SHA-256", Uint8Array.from(data)),
    rpc: async (name: string, _parameters: Record<string, unknown>) => ({ data: name.startsWith("claim_") ? claims : [{ outcome: "retry_scheduled" }], error: null }),
    executeWebsite: async (claim: AutomationClaim) => { phases.push(claim.phase); return { status: "sent" as const }; },
    executeSdfConfirmation: async (claim: AutomationClaim) => { phases.push(claim.phase); return { status: "sent" as const }; },
    executeSdfInvitation: async (claim: AutomationClaim) => { phases.push(claim.phase); return { status: "sent" as const }; },
    executeQueuedSdfEmail: async (): Promise<{ status: "sent" | "retry_wait" } | null> => null,
  } };
}

Deno.test("stateless transport sends without Supabase client or RPC dependency", async () => {
  const requests: Request[] = [];
  const result = await sendEmailViaResend({
    apiKey: "resend-test-key",
    from: "sender@example.test",
    to: "customer@example.test",
    subject: "Task 9 isolation",
    html: "<p>Task 9 isolation</p>",
    text: "Task 9 isolation",
    idempotencyKey:
      "sdf-initial-confirmation/88888888-8888-4888-8888-888888888888",
    timeoutMs: 100,
  }, (input, init) => {
    requests.push(new Request(input, init));
    return Promise.resolve(
      new Response('{"id":"task9-provider-message"}', { status: 200 }),
    );
  });

  assertEquals(result, {
    ok: true,
    providerMessageId: "task9-provider-message",
  });
  assertEquals(requests.length, 1);
});

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

Deno.test("targeted worker claims and executes only the requested work without queued tail", async () => {
  const fixture = dependencies([sdfClaim]);
  const rpcCalls: Array<{ name: string; parameters: Record<string, unknown> }> = [];
  let queuedCalls = 0;
  const originalRpc = fixture.value.rpc;
  fixture.value.rpc = async (name, parameters) => {
    rpcCalls.push({ name, parameters });
    return await originalRpc(name, parameters);
  };
  fixture.value.executeQueuedSdfEmail = async () => {
    queuedCalls += 1;
    return { status: "sent" as const };
  };

  const response = await handleApplicationIntakeAutomation(
    request('{"version":1,"work_id":2}'),
    fixture.value,
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    ok: true,
    claimed: 1,
    completed: 1,
    retry_scheduled: 0,
    manual_review: 0,
  });
  assertEquals(fixture.phases, ["SDF_CONFIRMATION"]);
  assertEquals(rpcCalls, [{
    name: "claim_application_intake_automation_work_by_id_v1",
    parameters: {
      p_worker_id: "11111111-1111-4111-8111-111111111111",
      p_work_id: 2,
    },
  }]);
  assertEquals(queuedCalls, 0);
});

Deno.test("targeted worker returns an empty success without global fallback", async () => {
  const fixture = dependencies([]);
  const rpcNames: string[] = [];
  let queuedCalls = 0;
  const originalRpc = fixture.value.rpc;
  fixture.value.rpc = async (name, parameters) => {
    rpcNames.push(name);
    return await originalRpc(name, parameters);
  };
  fixture.value.executeQueuedSdfEmail = async () => {
    queuedCalls += 1;
    return null;
  };

  const response = await handleApplicationIntakeAutomation(
    request('{"version":1,"work_id":404}'),
    fixture.value,
  );

  assertEquals(await response.json(), {
    ok: true,
    claimed: 0,
    completed: 0,
    retry_scheduled: 0,
    manual_review: 0,
  });
  assertEquals(rpcNames, ["claim_application_intake_automation_work_by_id_v1"]);
  assertEquals(fixture.phases, []);
  assertEquals(queuedCalls, 0);
});

Deno.test("targeted execution failure uses canonical failure authority without queued tail", async () => {
  const fixture = dependencies([sdfClaim]);
  const rpcCalls: Array<{ name: string; parameters: Record<string, unknown> }> = [];
  let queuedCalls = 0;
  const originalRpc = fixture.value.rpc;
  fixture.value.rpc = async (name, parameters) => {
    rpcCalls.push({ name, parameters });
    return await originalRpc(name, parameters);
  };
  fixture.value.executeSdfConfirmation = () => {
    throw new Error("interrupted");
  };
  fixture.value.executeQueuedSdfEmail = async () => {
    queuedCalls += 1;
    return null;
  };

  const response = await handleApplicationIntakeAutomation(
    request('{"version":1,"work_id":2}'),
    fixture.value,
  );

  assertEquals((await response.json()).retry_scheduled, 1);
  assertEquals(rpcCalls.map(({ name }) => name), [
    "claim_application_intake_automation_work_by_id_v1",
    "fail_application_intake_automation_work_v1",
  ]);
  assertEquals(rpcCalls[1].parameters, {
    p_work_id: 2,
    p_claim_token: "55555555-5555-4555-8555-555555555555",
    p_error_code: "WORKER_INTERRUPTED",
    p_retryable: true,
  });
  assertEquals(queuedCalls, 0);
});

Deno.test("targeted worker body fails closed for invalid work IDs and extra fields", async () => {
  for (const body of [
    '{"version":1,"work_id":0}',
    '{"version":1,"work_id":-1}',
    '{"version":1,"work_id":"2"}',
    '{"version":1,"work_id":2.5}',
    '{"version":1,"work_id":2,"extra":true}',
  ]) {
    const fixture = dependencies([sdfClaim]);
    let rpcCalls = 0;
    fixture.value.rpc = async () => {
      rpcCalls += 1;
      return { data: [], error: null };
    };

    const response = await handleApplicationIntakeAutomation(
      request(body),
      fixture.value,
    );

    assertEquals(response.status, 400);
    assertEquals(rpcCalls, 0);
  }
});

Deno.test("Website dispatch continues under every SDF authority mode", async () => {
  for (const mode of ["legacy", "isolated", undefined, "unknown"]) {
    const websiteClaim: AutomationClaim = {
      work_id: 1,
      quote_request_id: "22222222-2222-4222-8222-222222222222",
      phase: "APPROVAL",
      claim_token: "33333333-3333-4333-8333-333333333333",
    };
    const fixture = dependencies([
      websiteClaim,
      sdfClaim,
    ]);
    const websiteClaims: AutomationClaim[] = [];
    fixture.value.executeWebsite = async (claim) => {
      websiteClaims.push(claim);
      fixture.phases.push(claim.phase);
      return { status: "sent" as const };
    };
    fixture.value.executeSdfConfirmation = async () => {
      if (mode !== "legacy" && mode !== "isolated") {
        throw new Error("SDF_INITIAL_CONFIRMATION_MODE_INVALID");
      }
      return { status: "sent" as const };
    };

    const response = await handleApplicationIntakeAutomation(
      request(),
      fixture.value,
    );

    assertEquals(fixture.phases, ["APPROVAL"]);
    assertEquals(websiteClaims, [websiteClaim]);
    const counters = await response.json();
    assertEquals(counters, {
      ok: true,
      claimed: 2,
      completed: mode === "legacy" || mode === "isolated" ? 2 : 1,
      retry_scheduled: mode === "legacy" || mode === "isolated" ? 0 : 1,
      manual_review: 0,
    });
    assertEquals(counters.claimed, 2);
    assertEquals(counters.completed + counters.retry_scheduled, 2);
  }
});

Deno.test("legacy mode routes only through the existing SDF legacy authority", async () => {
  const createExecutor = await sdfExecutorFactory();
  const calls: string[] = [];
  const executor = createExecutor({
    authorityMode: "legacy",
    resendApiKey: "resend-test-key",
    fromEmail: "sender@example.test",
    rpc: async (name: string) => {
      calls.push(name);
      if (name === "resolve_sdf_support_reference_v1") {
        return { data: "#A1B2C3D4", error: null };
      }
      return {
        data: [{
          confirmation_job_id: sdfJobId,
          request_name: "SDF klant",
          request_email: "customer@example.test",
          application_reference: "SDF-2026-0001",
          request_kind: "slimme_documentenflow",
          template_key: "SDF_REQUEST_RECEIVED_NL_BE_v1",
          template_version: "v1",
        }],
        error: null,
      };
    },
    deliverLegacy: async () => {
      calls.push("deliver_legacy");
      return { status: "sent", attempted: true, attemptCount: 1 };
    },
    sendTransport: async () => {
      calls.push("send_transport");
      return { ok: true, providerMessageId: "unexpected" };
    },
  });

  assertEquals((await executor(sdfClaim)).status, "sent");
  assertEquals(calls, [
    "execute_application_intake_automation_sdf_confirmation_v1",
    "resolve_sdf_support_reference_v1",
    "deliver_legacy",
  ]);
});

Deno.test("missing or unknown SDF mode fails before every mail authority", async () => {
  const createExecutor = await sdfExecutorFactory();
  for (const authorityMode of [undefined, "", "unknown"]) {
    const calls: string[] = [];
    const executor = createExecutor({
      authorityMode,
      resendApiKey: "resend-test-key",
      fromEmail: "sender@example.test",
      rpc: async (name: string) => {
        calls.push(name);
        return { data: null, error: null };
      },
      deliverLegacy: async () => {
        calls.push("deliver_legacy");
        return { status: "sent", attempted: true, attemptCount: 1 };
      },
      sendTransport: async () => {
        calls.push("send_transport");
        return { ok: true, providerMessageId: "unexpected" };
      },
    });

    let errorCode = "";
    try {
      await executor(sdfClaim);
    } catch (error) {
      errorCode = error instanceof Error ? error.message : String(error);
    }
    assertEquals(errorCode, "SDF_INITIAL_CONFIRMATION_MODE_INVALID");
    assertEquals(calls, []);
  }
});

Deno.test("canonical non-deliverable prepare outcomes never call provider", async () => {
  const createExecutor = await sdfExecutorFactory();
  const cases = [
    { outcome: "already_sent", authoritySource: null, status: "sent" },
    { outcome: "retry_wait", authoritySource: "sdf_initial", status: "retry_wait" },
    { outcome: "processing", authoritySource: "sdf_initial", status: "retry_wait" },
    { outcome: "failed", authoritySource: "sdf_initial", status: "failed" },
    { outcome: "unknown", authoritySource: "sdf_initial", status: "failed" },
  ];
  for (const testCase of cases) {
    const fixture = isolatedDependencies();
    fixture.value.rpc = async (name, parameters) => {
      fixture.calls.push({ name, parameters });
      return {
        data: [{
          outcome: testCase.outcome,
          authority_source: testCase.authoritySource,
        }],
        error: null,
      };
    };

    const result = await createExecutor(fixture.value)(sdfClaim);

    assertEquals(result.status, testCase.status);
    assertEquals(result.attempted, false);
    assertEquals(fixture.calls.map(({ name }) => name), [
      "prepare_sdf_initial_confirmation_v2",
    ]);
    assertEquals(fixture.transportInputs, []);
  }
});

Deno.test("malformed already-sent prepare outcome fails closed", async () => {
  const createExecutor = await sdfExecutorFactory();
  const fixture = isolatedDependencies();
  fixture.value.rpc = async (name, parameters) => {
    fixture.calls.push({ name, parameters });
    if (name === "resolve_sdf_support_reference_v1") {
      return { data: "#A1B2C3D4", error: null };
    }
    return {
      data: [{
        outcome: "already_sent",
        authority_source: "sdf_initial",
        job_id: sdfJobId,
      }],
      error: null,
    };
  };

  assertEquals(await createExecutor(fixture.value)(sdfClaim), {
    status: "failed",
    attempted: false,
    attemptCount: 0,
    errorCode: "SDF_INITIAL_CONFIRMATION_PREPARE_INVALID",
  });
  assertEquals(fixture.transportInputs, []);
});

Deno.test("isolated legacy outcome uses only the returned legacy job", async () => {
  const createExecutor = await sdfExecutorFactory();
  const fixture = isolatedDependencies();
  const deliveredJobIds: string[] = [];
  fixture.value.rpc = async (name, parameters) => {
    fixture.calls.push({ name, parameters });
    if (name === "resolve_sdf_support_reference_v1") {
      return { data: "#A1B2C3D4", error: null };
    }
    return {
      data: [{
        outcome: "due",
        authority_source: "legacy",
        job_id: sdfJobId,
        request_name: "SDF klant",
        request_email: "customer@example.test",
        application_reference: "SDF-2026-0001",
        request_kind: "slimme_documentenflow",
        template_version: "v1",
      }],
      error: null,
    };
  };
  fixture.value.deliverLegacy = async ({ jobId }) => {
    deliveredJobIds.push(jobId);
    return { status: "sent", attempted: true, attemptCount: 1 };
  };

  assertEquals((await createExecutor(fixture.value)(sdfClaim)).status, "sent");
  assertEquals(deliveredJobIds, [sdfJobId]);
  assertEquals(fixture.transportInputs, []);
});

Deno.test("isolated due validates its lease immediately before stateless delivery", async () => {
  const createExecutor = await sdfExecutorFactory();
  const fixture = isolatedDependencies();

  const result = await createExecutor(fixture.value)(sdfClaim);

  assertEquals(result, { status: "sent", attempted: true, attemptCount: 1 });
  assertEquals(fixture.calls.map(({ name }) => name), [
    "prepare_sdf_initial_confirmation_v2",
    "claim_sdf_initial_confirmation_email_job_v1",
    "resolve_sdf_support_reference_v1",
    "validate_sdf_initial_confirmation_email_delivery_v1",
    "complete_sdf_initial_confirmation_email_job_v1",
  ]);
  assertEquals(fixture.transportInputs.length, 1);
  assertEquals(
    fixture.transportInputs[0].idempotencyKey,
    `sdf-initial-confirmation/${sdfJobId}`,
  );
  assertEquals(fixture.transportInputs[0].text.includes("Referentie: #A1B2C3D4"), true);
  assertEquals(fixture.transportInputs[0].text.includes("SDF-2026-0001"), false);
  assertEquals(fixture.calls[4].parameters, {
    p_job_id: sdfJobId,
    p_delivery_lease_token: sdfLeaseToken,
    p_succeeded: true,
    p_retryable: false,
    p_error_code: null,
    p_provider_message_id: "provider-message-1",
  });
});

Deno.test("SDF confirmation always uses the canonical support reference", async () => {
  const createExecutor = await sdfExecutorFactory();
  const fixture = isolatedDependencies();
  const originalRpc = fixture.value.rpc;
  fixture.value.rpc = async (name, parameters) => {
    const result = await originalRpc(name, parameters);
    if (name !== "claim_sdf_initial_confirmation_email_job_v1") return result;
    const claimed = (result.data as Array<Record<string, unknown>>)[0];
    return { data: [{ ...claimed, application_reference: "LWS-AAN-2026-0001" }], error: null };
  };

  assertEquals((await createExecutor(fixture.value)(sdfClaim)).status, "sent");
  assertEquals(fixture.transportInputs[0].text.includes("Referentie: #A1B2C3D4"), true);
  assertEquals(fixture.transportInputs[0].text.includes("Referentie: LWS-AAN-2026-0001"), false);
  assertEquals(fixture.transportInputs[0].text.includes("Referentie: #44444444"), false);
});

Deno.test("SDF confirmation fails closed without a canonical support reference", async () => {
  const createExecutor = await sdfExecutorFactory();
  const fixture = isolatedDependencies();
  const originalRpc = fixture.value.rpc;
  fixture.value.rpc = async (name, parameters) => {
    if (name === "resolve_sdf_support_reference_v1") {
      fixture.calls.push({ name, parameters });
      return { data: null, error: null };
    }
    return await originalRpc(name, parameters);
  };

  assertEquals(await createExecutor(fixture.value)(sdfClaim), {
    status: "failed",
    attempted: false,
    attemptCount: 1,
    errorCode: "SDF_INITIAL_CONFIRMATION_PAYLOAD_INVALID",
  });
  assertEquals(fixture.transportInputs, []);
  assertEquals(fixture.calls.some(({ name }) =>
    name === "validate_sdf_initial_confirmation_email_delivery_v1"
  ), false);
});

Deno.test("invalid or expired SDF lease fails before provider and completion", async () => {
  const createExecutor = await sdfExecutorFactory();
  for (const validation of [{ data: false, error: null }, {
    data: null,
    error: { message: "validation failed" },
  }]) {
    const fixture = isolatedDependencies();
    const originalRpc = fixture.value.rpc;
    fixture.value.rpc = async (name, parameters) => {
      if (name === "validate_sdf_initial_confirmation_email_delivery_v1") {
        fixture.calls.push({ name, parameters });
        return validation;
      }
      return await originalRpc(name, parameters);
    };

    assertEquals(await createExecutor(fixture.value)(sdfClaim), {
      status: "failed",
      attempted: false,
      attemptCount: 1,
      errorCode: "SDF_INITIAL_CONFIRMATION_LEASE_INVALID",
    });
    assertEquals(fixture.transportInputs, []);
    assertEquals(
      fixture.calls.some(({ name }) =>
        name === "complete_sdf_initial_confirmation_email_job_v1"
      ),
      false,
    );
  }
});

Deno.test("transport outcomes pass only technical data to SDF completion", async () => {
  const createExecutor = await sdfExecutorFactory();
  const outcomes: Array<Extract<ResendTransportResult, { ok: false }>> = [
    { ok: false, retryable: true, code: "RESEND_HTTP_RETRYABLE" },
    { ok: false, retryable: false, code: "RESEND_HTTP_PERMANENT" },
    { ok: false, retryable: true, code: "RESEND_TIMEOUT" },
    { ok: false, retryable: true, code: "RESEND_NETWORK_ERROR" },
    { ok: false, retryable: true, code: "PROVIDER_RESPONSE_INVALID" },
  ];
  for (const transportResult of outcomes) {
    const fixture = isolatedDependencies(transportResult);
    const result = await createExecutor(fixture.value)(sdfClaim);
    const completion = fixture.calls.find(({ name }) =>
      name === "complete_sdf_initial_confirmation_email_job_v1"
    );

    assertEquals(result.status, transportResult.retryable
      ? "retry_wait"
      : "failed");
    assertEquals(completion?.parameters, {
      p_job_id: sdfJobId,
      p_delivery_lease_token: sdfLeaseToken,
      p_succeeded: false,
      p_retryable: transportResult.retryable,
      p_error_code: transportResult.code,
      p_provider_message_id: null,
    });
    assertEquals("p_work_id" in (completion?.parameters || {}), false);
    assertEquals("p_claim_token" in (completion?.parameters || {}), false);
  }
});

Deno.test("isolated completion failure fails closed without fallback", async () => {
  const createExecutor = await sdfExecutorFactory();
  const fixture = isolatedDependencies();
  const originalRpc = fixture.value.rpc;
  fixture.value.rpc = async (name, parameters) => {
    if (name === "complete_sdf_initial_confirmation_email_job_v1") {
      fixture.calls.push({ name, parameters });
      return { data: null, error: { message: "completion failed" } };
    }
    return await originalRpc(name, parameters);
  };

  assertEquals(await createExecutor(fixture.value)(sdfClaim), {
    status: "failed",
    attempted: true,
    attemptCount: 1,
    errorCode: "SDF_INITIAL_CONFIRMATION_COMPLETION_FAILED",
  });
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

Deno.test("SDF invitation authority distinguishes delivery from already-sent reconciliation", () => {
  const base = {
    job_id: "88888888-8888-4888-8888-888888888888",
    intake_id: "99999999-9999-4999-8999-999999999999",
    request_id: "77777777-7777-4777-8777-777777777777",
  };
  assertEquals(sdfInvitationOutcome({ outcome: "already_sent", ...base }), "already_sent");
  assertEquals(sdfInvitationOutcome({
    outcome: "invitation_pending",
    ...base,
    request_name: "SDF klant",
    request_email: "customer@example.test",
    template_version: "SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1",
    encrypted_capability: "v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    customer_capability_digest: "a".repeat(64),
    expires_at: "2099-01-01T00:00:00Z",
  }), "deliver");
  assertEquals(sdfInvitationOutcome({ outcome: "already_sent", ...base, encrypted_capability: "secret" }), "already_sent");
  assertEquals(sdfInvitationOutcome({ outcome: "invitation_pending", ...base }), "invalid");
});

Deno.test("already-sent SDF invitation reconciliation never reaches provider delivery", async () => {
  const createExecutor = await sdfInvitationExecutorFactory();
  const rpcCalls: string[] = [];
  let decryptCalls = 0;
  let providerCalls = 0;
  const execute = createExecutor({
    siteUrl: "https://example.test",
    resendApiKey: "resend-test-key",
    fromEmail: "Lorenzo Web Solutions <noreply@example.test>",
    createCapabilityMaterial: async () => ({ digest: "a".repeat(64), encrypted: "v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" }),
    decryptCapability: async () => { decryptCalls += 1; return "raw-token"; },
    fetchProvider: async () => { providerCalls += 1; return new Response(null, { status: 200 }); },
    rpc: async (name) => {
      rpcCalls.push(name);
      return { data: { outcome: "already_sent", job_id: sdfJobId, intake_id: "77777777-7777-4777-8777-777777777777", request_id: sdfClaim.quote_request_id }, error: null };
    },
  });
  assertEquals(await execute({ ...sdfClaim, phase: "SDF_INTAKE" }), { status: "sent", attempted: false, attemptCount: 0 });
  assertEquals(rpcCalls, ["execute_application_intake_automation_sdf_intake_v1"]);
  assertEquals(decryptCalls, 0);
  assertEquals(providerCalls, 0);
});
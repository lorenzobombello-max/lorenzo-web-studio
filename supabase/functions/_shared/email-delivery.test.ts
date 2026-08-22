import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { deliverEmailJob } from "./email-delivery.ts";

function client(completionStatus: "sent" | "retry_wait" | "failed", classification = "production") {
  const calls: Array<{ name: string; parameters: Record<string, unknown> }> = [];
  return {
    calls,
    rpc(name: string, parameters: Record<string, unknown>) {
      calls.push({ name, parameters });
      if (name === "claim_quote_request_email_job") return Promise.resolve({ data: [{ job_id: parameters.p_job_id, attempt_count: 1 }], error: null });
      if (name === "get_quote_request_email_classification_v1") return Promise.resolve({ data: classification, error: null });
      return Promise.resolve({ data: [{ job_status: completionStatus, attempt_count: 1 }], error: null });
    },
    from() { throw new Error("unexpected state read"); },
  };
}

Deno.test("email transport sends html and text with stable provider idempotency", async () => {
  const supabase = client("sent");
  let request: Request | null = null;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (input, init) => {
    request = new Request(input, init);
    return Promise.resolve(new Response('{"id":"provider-1"}', { status: 200, headers: { "content-type": "application/json" } }));
  };
  try {
    const result = await deliverEmailJob({ supabase: supabase as never, jobId: "job-1", resendApiKey: "test-key", email: { from: "from@example.test", to: "to@example.test", subject: "Offerte", html: "<p>Offerte</p>", text: "Offerte" } });
    assertEquals(result.status, "sent");
    assertEquals(request!.headers.get("Idempotency-Key"), "quote-request-email/job-1");
    const body = await request!.text();
    assertStringIncludes(body, '"html":"<p>Offerte</p>"');
    assertStringIncludes(body, '"text":"Offerte"');
    assertStringIncludes(body, '"to":["to@example.test"]');
    assertEquals(supabase.calls.map((call) => call.name), [
      "claim_quote_request_email_job",
      "get_quote_request_email_classification_v1",
      "complete_quote_request_email_job",
    ]);
    assertEquals(supabase.calls[2].parameters.p_provider_message_id, "provider-1");
  } finally { globalThis.fetch = originalFetch; }
});

Deno.test("provider 500 schedules retry without claiming delivery", async () => {
  const supabase = client("retry_wait");
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () => Promise.resolve(new Response("failure", { status: 500 }));
  try {
    const result = await deliverEmailJob({ supabase: supabase as never, jobId: "job-2", resendApiKey: "test-key", email: { from: "from@example.test", to: "to@example.test", subject: "Offerte", html: "<p>Offerte</p>", text: "Offerte" } });
    assertEquals(result.status, "retry_wait");
    assertEquals(result.errorCode, "RESEND_HTTP_500");
    assertEquals(supabase.calls[2].parameters.p_succeeded, false);
    assertEquals(supabase.calls[2].parameters.p_retryable, true);
  } finally { globalThis.fetch = originalFetch; }
});

Deno.test("internal E2E mail is routed only to the server allowlisted mailbox", async () => {
  const supabase = client("sent", "internal_e2e");
  const previousMailbox = Deno.env.get("INTERNAL_E2E_MAILBOX");
  const originalFetch = globalThis.fetch;
  let request: Request | null = null;
  Deno.env.set("INTERNAL_E2E_MAILBOX", "production-e2e@lorenzowebsolutions.be");
  globalThis.fetch = (input, init) => {
    request = new Request(input, init);
    return Promise.resolve(new Response('{"id":"provider-e2e"}', { status: 200 }));
  };
  try {
    const result = await deliverEmailJob({ supabase: supabase as never, jobId: "job-e2e", resendApiKey: "test-key", email: { from: "from@example.test", to: "customer@example.com", subject: "Test", html: "<p>Test</p>", text: "Test" } });
    assertEquals(result.status, "sent");
    assertStringIncludes(await request!.text(), '"to":["production-e2e@lorenzowebsolutions.be"]');
  } finally {
    if (previousMailbox === undefined) Deno.env.delete("INTERNAL_E2E_MAILBOX");
    else Deno.env.set("INTERNAL_E2E_MAILBOX", previousMailbox);
    globalThis.fetch = originalFetch;
  }
});

Deno.test("internal E2E mail fails closed when the server mailbox is missing", async () => {
  const supabase = client("failed", "internal_e2e");
  const previousMailbox = Deno.env.get("INTERNAL_E2E_MAILBOX");
  let fetchCalls = 0;
  const originalFetch = globalThis.fetch;
  Deno.env.delete("INTERNAL_E2E_MAILBOX");
  globalThis.fetch = () => { fetchCalls += 1; return Promise.resolve(new Response(null, { status: 200 })); };
  try {
    const result = await deliverEmailJob({ supabase: supabase as never, jobId: "job-e2e", resendApiKey: "test-key", email: { from: "from@example.test", to: "customer@example.com", subject: "Test", html: "<p>Test</p>", text: "Test" } });
    assertEquals(result.errorCode, "INTERNAL_E2E_MAILBOX_REQUIRED");
    assertEquals(fetchCalls, 0);
  } finally {
    if (previousMailbox === undefined) Deno.env.delete("INTERNAL_E2E_MAILBOX");
    else Deno.env.set("INTERNAL_E2E_MAILBOX", previousMailbox);
    globalThis.fetch = originalFetch;
  }
});

Deno.test("replay of an already sent job does not deliver twice", async () => {
  let fetchCalls = 0;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () => {
    fetchCalls += 1;
    return Promise.resolve(new Response('{"id":"unexpected"}', { status: 200 }));
  };
  const supabase = {
    rpc(name: string) {
      assertEquals(name, "claim_quote_request_email_job");
      return Promise.resolve({ data: [], error: null });
    },
    from() {
      return {
        select() { return this; },
        eq() { return this; },
        maybeSingle() { return Promise.resolve({ data: { status: "sent", attempt_count: 1 }, error: null }); },
      };
    },
  };
  try {
    const result = await deliverEmailJob({ supabase: supabase as never, jobId: "job-sent", resendApiKey: "test-key", email: { from: "from@example.test", to: "to@example.test", subject: "Offerte", html: "<p>Offerte</p>", text: "Offerte" } });
    assertEquals(result.status, "sent");
    assertEquals(result.attempted, false);
    assertEquals(fetchCalls, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

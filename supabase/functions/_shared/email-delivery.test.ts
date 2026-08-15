import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { deliverEmailJob } from "./email-delivery.ts";

function client(completionStatus: "sent" | "retry_wait") {
  const calls: Array<{ name: string; parameters: Record<string, unknown> }> = [];
  return {
    calls,
    rpc(name: string, parameters: Record<string, unknown>) {
      calls.push({ name, parameters });
      if (name === "claim_quote_request_email_job") return Promise.resolve({ data: [{ job_id: parameters.p_job_id, attempt_count: 1 }], error: null });
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
    assertEquals(supabase.calls[1].parameters.p_provider_message_id, "provider-1");
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
    assertEquals(supabase.calls[1].parameters.p_succeeded, false);
    assertEquals(supabase.calls[1].parameters.p_retryable, true);
  } finally { globalThis.fetch = originalFetch; }
});

import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { handleRequest, type ReceiptRegistration } from "./index.ts";

const secret = `whsec_${btoa("local-resend-webhook-secret-material")}`;
const recipient = "sdf@lorenzowebsolutions.be";
const receiptId = "f1000000-0000-4000-8000-000000000001";

function event(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    type: "email.received",
    created_at: "2030-01-01T10:00:01.000Z",
    data: {
      email_id: "f2000000-0000-4000-8000-000000000001",
      message_id: "<message-1@example.test>",
      from: "Customer@Example.Test",
      to: ["SDF@LorenzoWebSolutions.be"],
      created_at: "2030-01-01T10:00:00.000Z",
      ...overrides,
    },
  };
}

async function signature(
  payload: string,
  id: string,
  timestamp: string,
): Promise<string> {
  const keyBytes = Uint8Array.from(
    atob(secret.slice("whsec_".length)),
    (character) => character.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${id}.${timestamp}.${payload}`),
  ));
  return `v1,${btoa(String.fromCharCode(...digest))}`;
}

async function signedRequest(
  body: string,
  options: { id?: string; signatureBody?: string } = {},
): Promise<Request> {
  const id = options.id ?? "msg_delivery_1";
  const timestamp = String(Math.floor(Date.now() / 1000));
  return new Request("https://example.test/functions/v1/sdf-inbound-email", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "svix-id": id,
      "svix-timestamp": timestamp,
      "svix-signature": await signature(
        options.signatureBody ?? body,
        id,
        timestamp,
      ),
    },
    body,
  });
}

async function withEnvironment(run: () => Promise<void>): Promise<void> {
  const previousSecret = Deno.env.get("RESEND_WEBHOOK_SECRET");
  const previousRecipient = Deno.env.get("SDF_INBOUND_RECIPIENT");
  Deno.env.set("RESEND_WEBHOOK_SECRET", secret);
  Deno.env.set("SDF_INBOUND_RECIPIENT", recipient);
  try {
    await run();
  } finally {
    if (previousSecret === undefined) Deno.env.delete("RESEND_WEBHOOK_SECRET");
    else Deno.env.set("RESEND_WEBHOOK_SECRET", previousSecret);
    if (previousRecipient === undefined) {
      Deno.env.delete("SDF_INBOUND_RECIPIENT");
    } else Deno.env.set("SDF_INBOUND_RECIPIENT", previousRecipient);
  }
}

function registrationHarness() {
  const calls: ReceiptRegistration[] = [];
  return {
    calls,
    register: async (input: ReceiptRegistration) => {
      calls.push(input);
      return { receipt_id: receiptId, replayed: false };
    },
  };
}

Deno.test("valid signed email.received is normalized and persisted", async () => {
  await withEnvironment(async () => {
    const harness = registrationHarness();
    const response = await handleRequest(
      await signedRequest(JSON.stringify(event())),
      { register: harness.register },
    );
    assertEquals(response.status, 200);
    assertEquals((await response.json()).state, "received");
    assertEquals(harness.calls.length, 1);
    assertEquals(harness.calls[0].senderEmail, "customer@example.test");
    assertEquals(harness.calls[0].matchedRecipient, recipient);
    assertMatch(String(harness.calls[0].canonicalFingerprint), /^[0-9a-f]{64}$/);
  });
});

Deno.test("missing Svix headers are rejected before persistence", async () => {
  await withEnvironment(async () => {
    const harness = registrationHarness();
    const response = await handleRequest(new Request("https://example.test", {
      method: "POST",
      body: JSON.stringify(event()),
    }), { register: harness.register });
    assertEquals(response.status, 401);
    assertEquals(harness.calls.length, 0);
  });
});

Deno.test("invalid and tampered signatures are rejected", async () => {
  await withEnvironment(async () => {
    const harness = registrationHarness();
    const body = JSON.stringify(event());
    const invalid = await signedRequest(body, { signatureBody: `${body}x` });
    const response = await handleRequest(invalid, { register: harness.register });
    assertEquals(response.status, 401);
    assertEquals(harness.calls.length, 0);
  });
});

Deno.test("signed invalid JSON fails closed without persistence", async () => {
  await withEnvironment(async () => {
    const harness = registrationHarness();
    const response = await handleRequest(
      await signedRequest("{invalid"),
      { register: harness.register },
    );
    assertEquals(response.status, 401);
    assertEquals(harness.calls.length, 0);
  });
});

Deno.test("wrong event type is ignored without persistence", async () => {
  await withEnvironment(async () => {
    const harness = registrationHarness();
    const body = JSON.stringify({ ...event(), type: "email.sent" });
    const response = await handleRequest(
      await signedRequest(body),
      { register: harness.register },
    );
    assertEquals(response.status, 202);
    assertEquals((await response.json()).state, "ignored");
    assertEquals(harness.calls.length, 0);
  });
});

Deno.test("recipient mismatch creates no receipt", async () => {
  await withEnvironment(async () => {
    const harness = registrationHarness();
    const body = JSON.stringify(event({ to: ["other@example.test"] }));
    const response = await handleRequest(
      await signedRequest(body),
      { register: harness.register },
    );
    assertEquals(response.status, 202);
    assertEquals((await response.json()).state, "recipient_not_routed");
    assertEquals(harness.calls.length, 0);
  });
});

for (const [name, data] of [
  ["invalid sender", { from: "not-an-email" }],
  ["missing email id", { email_id: "" }],
  ["invalid recipients", { to: ["not-an-email"] }],
] as const) {
  Deno.test(`${name} is rejected`, async () => {
    await withEnvironment(async () => {
      const harness = registrationHarness();
      const body = JSON.stringify(event(data));
      const response = await handleRequest(
        await signedRequest(body),
        { register: harness.register },
      );
      assertEquals(response.status, 400);
      assertEquals(harness.calls.length, 0);
    });
  });
}

Deno.test("database conflicts are returned without leaking details", async () => {
  await withEnvironment(async () => {
    const body = JSON.stringify(event());
    const response = await handleRequest(await signedRequest(body), {
      register: () => Promise.reject(new Error("INBOUND_RECEIPT_CONFLICT")),
    });
    assertEquals(response.status, 409);
    assertEquals((await response.json()).code, "INBOUND_RECEIPT_CONFLICT");
  });
});
import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { SUPABASE_KEY_BINDING_ERROR } from "../_shared/supabase-key-bindings.ts";
import {
  createReceiptRegistration,
  handleRequest,
  type ReceiptRegistration,
} from "./index.ts";

const secret = `whsec_${btoa("local-resend-webhook-secret-material")}`;
const recipient = "sdf@lorenzowebsolutions.be";
const receiptId = "f1000000-0000-4000-8000-000000000001";

function event(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
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
  const digest = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(`${id}.${timestamp}.${payload}`),
    ),
  );
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
    assertMatch(
      String(harness.calls[0].canonicalFingerprint),
      /^[0-9a-f]{64}$/,
    );
  });
});

Deno.test("missing Svix headers are rejected before persistence", async () => {
  await withEnvironment(async () => {
    const harness = registrationHarness();
    const response = await handleRequest(
      new Request("https://example.test", {
        method: "POST",
        body: JSON.stringify(event()),
      }),
      { register: harness.register },
    );
    assertEquals(response.status, 401);
    assertEquals(await response.json(), {
      ok: false,
      code: "WEBHOOK_SIGNATURE_REQUIRED",
    });
    assertEquals(harness.calls.length, 0);
  });
});

Deno.test("invalid and tampered signatures are rejected", async () => {
  await withEnvironment(async () => {
    const harness = registrationHarness();
    const body = JSON.stringify(event());
    const invalid = await signedRequest(body, { signatureBody: `${body}x` });
    const response = await handleRequest(invalid, {
      register: harness.register,
    });
    assertEquals(response.status, 401);
    assertEquals(await response.json(), {
      ok: false,
      code: "INVALID_WEBHOOK_SIGNATURE",
    });
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

for (
  const [name, data] of [
    ["invalid sender", { from: "not-an-email" }],
    ["missing email id", { email_id: "" }],
    ["invalid recipients", { to: ["not-an-email"] }],
  ] as const
) {
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

Deno.test("modern server binding preserves client config and exact receipt RPC", async () => {
  const registration: ReceiptRegistration = {
    providerEmailId: "provider-email-1",
    webhookDeliveryId: "delivery-1",
    rfcMessageId: "<message-1@example.test>",
    senderEmail: "customer@example.test",
    matchedRecipient: recipient,
    receivedAt: "2030-01-01T10:00:00.000Z",
    canonicalFingerprint: "c".repeat(64),
  };
  let clientInput: unknown;
  let rpcInput: unknown;
  const register = createReceiptRegistration(
    {
      get: (name) =>
        name === "SUPABASE_URL"
          ? "https://example.supabase.co"
          : name === "SUPABASE_SECRET_KEYS"
          ? JSON.stringify({ default: "sb_secret_inboundTest_123" })
          : undefined,
    },
    (url, key, options) => {
      clientInput = { url, key, options };
      return {
        rpc: async (name, parameters) => {
          rpcInput = { name, parameters };
          return {
            data: { receipt_id: receiptId, replayed: false },
            error: null,
          };
        },
      };
    },
  );

  assertEquals(await register(registration), {
    receipt_id: receiptId,
    replayed: false,
  });
  assertEquals(clientInput, {
    url: "https://example.supabase.co",
    key: "sb_secret_inboundTest_123",
    options: { auth: { persistSession: false, autoRefreshToken: false } },
  });
  assertEquals(rpcInput, {
    name: "register_resend_sdf_inbound_receipt_v1",
    parameters: {
      p_provider_email_id: registration.providerEmailId,
      p_webhook_delivery_id: registration.webhookDeliveryId,
      p_rfc_message_id: registration.rfcMessageId,
      p_sender_email: registration.senderEmail,
      p_matched_recipient: registration.matchedRecipient,
      p_received_at: registration.receivedAt,
      p_canonical_fingerprint: registration.canonicalFingerprint,
    },
  });
});

Deno.test("invalid modern bindings fail closed without client creation or leakage", async () => {
  const sensitiveValue = "sb_publishable_mustNeverAppear_789";
  const output: unknown[][] = [];
  const original = {
    log: console.log,
    warn: console.warn,
    error: console.error,
  };
  console.log = (...values) => output.push(values);
  console.warn = (...values) => output.push(values);
  console.error = (...values) => output.push(values);
  try {
    for (
      const binding of [
        undefined,
        "not-json",
        JSON.stringify({ default: sensitiveValue }),
      ]
    ) {
      let clientCreated = false;
      const register = createReceiptRegistration(
        {
          get: (name) =>
            name === "SUPABASE_URL"
              ? "https://example.supabase.co"
              : name === "SUPABASE_SECRET_KEYS"
              ? binding
              : undefined,
        },
        () => {
          clientCreated = true;
          throw new Error("CLIENT_MUST_NOT_BE_CREATED");
        },
      );
      let error: unknown;
      try {
        await register({} as ReceiptRegistration);
      } catch (caught) {
        error = caught;
      }
      assertEquals(
        error instanceof Error ? error.message : null,
        SUPABASE_KEY_BINDING_ERROR,
      );
      assertEquals(
        error instanceof Error ? error.stack?.includes(sensitiveValue) : false,
        false,
      );
      assertEquals(clientCreated, false);
    }
    assertEquals(output, []);
  } finally {
    console.log = original.log;
    console.warn = original.warn;
    console.error = original.error;
  }
});

Deno.test("valid webhook maps binding failures to the non-sensitive binding code", async () => {
  await withEnvironment(async () => {
    const body = JSON.stringify(event());
    const response = await handleRequest(await signedRequest(body), {
      register: () => Promise.reject(new Error(SUPABASE_KEY_BINDING_ERROR)),
    });
    assertEquals(response.status, 500);
    assertEquals(await response.json(), {
      ok: false,
      code: SUPABASE_KEY_BINDING_ERROR,
    });
  });
});

Deno.test("replayed registration preserves the existing idempotent response", async () => {
  await withEnvironment(async () => {
    const body = JSON.stringify(event());
    const response = await handleRequest(await signedRequest(body), {
      register: async () => ({ receipt_id: receiptId, replayed: true }),
    });
    assertEquals(response.status, 200);
    assertEquals(await response.json(), {
      ok: true,
      state: "replayed",
      receipt_id: receiptId,
    });
  });
});

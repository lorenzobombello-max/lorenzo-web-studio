import { assertEquals } from "jsr:@std/assert@1";
import { SUPABASE_KEY_BINDING_ERROR } from "../_shared/supabase-key-bindings.ts";
import { SDF_CONFIRMATION_VERSION } from "./handler.ts";
import { createSdfQualificationIntakeRuntime } from "./index.ts";

const token = "a".repeat(43);
const digest = "b".repeat(64);
const modernKey = "sb_secret_sdfQualificationTest_123";

function environment(secretBinding?: string) {
  return {
    get(name: string): string | undefined {
      if (name === "SUPABASE_URL") return "https://example.supabase.co";
      if (name === "SUPABASE_SECRET_KEYS") return secretBinding;
      return undefined;
    },
  };
}

function request(body: Record<string, unknown>): Request {
  return new Request("https://example.test/sdf-qualification-intake", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

Deno.test("SDF runtime selects the modern server key and preserves client configuration", async () => {
  let clientInput: unknown;
  const runtime = createSdfQualificationIntakeRuntime(
    environment(JSON.stringify({ default: modernKey })),
    (url, key, options) => {
      clientInput = { url, key, options };
      return {
        rpc: async (name) =>
          name === "consume_sdf_qualification_rate_limit_v1"
            ? { data: true, error: null }
            : { data: { status: "invited" }, error: null },
      };
    },
    async () => digest,
  );

  const response = await runtime(request({ action: "inspect" }));
  assertEquals(response.status, 200);
  assertEquals(clientInput, {
    url: "https://example.supabase.co",
    key: modernKey,
    options: { auth: { persistSession: false, autoRefreshToken: false } },
  });
});

Deno.test("SDF runtime fails closed for missing, malformed, and wrong-kind bindings without leaking", async () => {
  const sensitiveValue = "sb_publishable_mustNeverAppear_456";
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
      let created = false;
      const runtime = createSdfQualificationIntakeRuntime(
        environment(binding),
        () => {
          created = true;
          throw new Error("CLIENT_MUST_NOT_BE_CREATED");
        },
      );
      const response = await runtime(request({ action: "inspect" }));
      const text = await response.text();
      assertEquals(response.status, 500);
      assertEquals(JSON.parse(text), {
        ok: false,
        code: SUPABASE_KEY_BINDING_ERROR,
      });
      assertEquals(text.includes(sensitiveValue), false);
      assertEquals(created, false);
    }
    assertEquals(output, []);
  } finally {
    console.log = original.log;
    console.warn = original.warn;
    console.error = original.error;
  }
});

Deno.test("SDF runtime preserves every RPC name, parameter, rate-limit, and response contract", async () => {
  const cases = [
    {
      body: { action: "inspect" },
      operation: "inspect_save",
      rpc: "inspect_sdf_qualification_intake_v1",
      parameters: { p_customer_capability_digest: digest },
    },
    {
      body: { action: "evaluate_capacity_preview" },
      operation: "inspect_save",
      rpc: "evaluate_sdf_budget_guard_capacity_preview_v1",
      parameters: { p_customer_capability_digest: digest },
    },
    {
      body: {
        action: "save_draft",
        expected_revision: 2,
        answers: { version: 1 },
      },
      operation: "inspect_save",
      rpc: "save_sdf_qualification_intake_draft_v1",
      parameters: {
        p_customer_capability_digest: digest,
        p_expected_revision: 2,
        p_answers: { version: 1 },
      },
    },
    {
      body: {
        action: "submit",
        expected_revision: 2,
        idempotency_key: "11111111-1111-4111-8111-111111111111",
        confirmation_accepted: true,
        confirmation_version: SDF_CONFIRMATION_VERSION,
      },
      operation: "submit",
      rpc: "submit_sdf_qualification_intake_v1",
      parameters: {
        p_customer_capability_digest: digest,
        p_expected_revision: 2,
        p_confirmation_accepted: true,
        p_confirmation_version: SDF_CONFIRMATION_VERSION,
        p_confirmation_sha256:
          "6577a4f252b00ff64589a5b781f2928c648f0b0aedf184b822ac2908b8f927f3",
        p_idempotency_key: "11111111-1111-4111-8111-111111111111",
      },
    },
  ] as const;

  for (const testCase of cases) {
    const calls: Array<{ name: string; parameters: Record<string, unknown> }> =
      [];
    const runtime = createSdfQualificationIntakeRuntime(
      environment(JSON.stringify({ default: modernKey })),
      () => ({
        rpc: async (name, parameters) => {
          calls.push({ name, parameters });
          return name === "consume_sdf_qualification_rate_limit_v1"
            ? { data: true, error: null }
            : { data: { contract: "unchanged" }, error: null };
        },
      }),
      async () => digest,
    );

    const response = await runtime(request(testCase.body));
    assertEquals(response.status, 200);
    const output = await response.json();
    assertEquals(output.ok, true);
    assertEquals(output.result, { contract: "unchanged" });
    assertEquals(calls, [
      {
        name: "consume_sdf_qualification_rate_limit_v1",
        parameters: {
          p_pseudonymous_key: digest,
          p_operation: testCase.operation,
        },
      },
      { name: testCase.rpc, parameters: testCase.parameters },
    ]);
  }
});

Deno.test("SDF runtime preserves rate-limit and URL configuration failure contracts", async () => {
  for (
    const failure of [
      {
        result: { data: false, error: null },
        status: 429,
        code: "RATE_LIMITED",
      },
      {
        result: { data: null, error: { message: "unavailable" } },
        status: 503,
        code: "RATE_LIMIT_UNAVAILABLE",
      },
    ]
  ) {
    let calls = 0;
    const runtime = createSdfQualificationIntakeRuntime(
      environment(JSON.stringify({ default: modernKey })),
      () => ({
        rpc: async () => {
          calls += 1;
          return failure.result;
        },
      }),
      async () => digest,
    );
    const response = await runtime(request({ action: "inspect" }));
    assertEquals(response.status, failure.status);
    assertEquals(await response.json(), { ok: false, code: failure.code });
    assertEquals(calls, 1);
  }

  const missingUrlRuntime = createSdfQualificationIntakeRuntime(
    {
      get: (name) =>
        name === "SUPABASE_SECRET_KEYS"
          ? JSON.stringify({ default: modernKey })
          : undefined,
    },
  );
  const response = await missingUrlRuntime(request({ action: "inspect" }));
  assertEquals(response.status, 500);
  assertEquals(await response.json(), {
    ok: false,
    code: "SERVER_CONFIGURATION_ERROR",
  });
});

Deno.test("SDF runtime has one modern server-key callsite and no legacy key callsite", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertEquals(source.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
  assertEquals(source.match(/getSupabaseServerSecretKey\(/g)?.length, 1);
});

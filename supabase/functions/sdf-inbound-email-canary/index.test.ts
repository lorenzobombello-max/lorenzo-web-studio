import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { Resend } from "npm:resend@6.25.0";
import { handleRequest } from "./index.ts";

const secret = `whsec_${btoa("local-signed-canary-secret-material")}`;
const jwt = "header.payload.signature";
const url = "https://example.supabase.co";

function request(
  body = "{}",
  options: {
    method?: string;
    authorization?: string | null;
    origin?: string | null;
    requestedHeaders?: string;
  } = {},
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (options.origin !== null) {
    headers.set("origin", options.origin ?? "https://lorenzowebsolutions.be");
  }
  if (options.authorization !== null) {
    headers.set("authorization", options.authorization ?? `Bearer ${jwt}`);
  }
  if (options.method === "OPTIONS") {
    headers.set("access-control-request-method", "POST");
    headers.set(
      "access-control-request-headers",
      options.requestedHeaders ??
        "apikey,authorization,content-type,x-client-info",
    );
  }
  return new Request(`${url}/functions/v1/sdf-inbound-email-canary`, {
    method: options.method ?? "POST",
    headers,
    body: !options.method || options.method === "POST" ? body : undefined,
  });
}

function dependencies(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  let invocation = 0;
  return {
    authorize: () => Promise.resolve("allowed"),
    readEvidence: () =>
      Promise.resolve({
        authorized: true,
        receipt_count: 1,
        delivery_count: 1,
        classification: "internal_e2e",
      }),
    invoke: () => {
      invocation += 1;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            ok: true,
            state: invocation === 1 ? "received" : "replayed",
            receipt_id: "not-forwarded",
          }),
          { status: 200 },
        ),
      );
    },
    environment: {
      get: (name: string) =>
        name === "SUPABASE_URL"
          ? url
          : name === "RESEND_WEBHOOK_SECRET"
          ? secret
          : undefined,
    },
    now: () => Date.now(),
    callTimeoutMs: 100,
    totalTimeoutMs: 500,
    ...overrides,
  };
}

Deno.test("canary accepts only POST with an exact empty JSON object", async () => {
  for (
    const [candidate, expectedStatus] of [
      [request("{}", { method: "GET" }), 405],
      [request("[]"), 400],
      [request('{"actor":"OP-01"}'), 400],
      [request("invalid"), 400],
    ] as const
  ) {
    const response = await handleRequest(candidate, dependencies());
    assertEquals(response.status, expectedStatus);
  }
});

Deno.test("exact production origin receives the minimal preflight contract without authority calls", async () => {
  let authorizeCalls = 0;
  const response = await handleRequest(
    request("{}", { method: "OPTIONS" }),
    dependencies({
      authorize: () => {
        authorizeCalls += 1;
        return Promise.resolve("allowed");
      },
    }),
  );
  assertEquals(response.status, 204);
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    "https://lorenzowebsolutions.be",
  );
  assertEquals(
    response.headers.get("access-control-allow-methods"),
    "POST,OPTIONS",
  );
  assertEquals(
    response.headers.get("access-control-allow-headers"),
    "authorization,apikey,content-type,x-client-info",
  );
  assertEquals(response.headers.get("vary"), "Origin");
  assertEquals(
    [...response.headers.values()].some((value) => value.includes("*")),
    false,
  );
  assertEquals(authorizeCalls, 0);
});

for (
  const origin of [
    "https://attacker.test",
    "null",
    "https://lorenzowebsolutions.be.attacker.test",
    "http://lorenzowebsolutions.be",
  ]
) {
  Deno.test(`preflight denies origin ${origin} without permissive ACAO`, async () => {
    const response = await handleRequest(
      request("{}", { method: "OPTIONS", origin }),
      dependencies(),
    );
    assertEquals(response.status, 403);
    assertEquals(response.headers.get("access-control-allow-origin"), null);
  });
}

Deno.test("preflight denies unnecessary methods and request headers", async () => {
  const method = request("{}", { method: "OPTIONS" });
  method.headers.set("access-control-request-method", "GET");
  const methodResponse = await handleRequest(method, dependencies());
  assertEquals(methodResponse.status, 403);
  assertEquals(
    methodResponse.headers.get("access-control-allow-origin"),
    "https://lorenzowebsolutions.be",
  );

  const headersResponse = await handleRequest(
    request("{}", {
      method: "OPTIONS",
      requestedHeaders: "authorization,x-debug",
    }),
    dependencies(),
  );
  assertEquals(headersResponse.status, 403);
});

Deno.test("anonymous caller is denied", async () => {
  const response = await handleRequest(
    request("{}", { authorization: null }),
    dependencies(),
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "AUTHENTICATION_REQUIRED");
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    "https://lorenzowebsolutions.be",
  );
});

for (
  const caller of [
    "ordinary authenticated",
    "OP-02",
    "OP-03",
    "service-role",
    "OP-01 AAL1",
  ]
) {
  Deno.test(`${caller} is denied`, async () => {
    const response = await handleRequest(
      request(),
      dependencies({
        authorize: () => Promise.resolve("forbidden"),
      }),
    );
    assertEquals(response.status, 403);
    assertEquals(await response.json(), {
      ok: false,
      code: "AUTHORIZATION_DENIED",
    });
  });
}

Deno.test("unverifiable bearer token is denied as unauthenticated", async () => {
  const response = await handleRequest(
    request(),
    dependencies({
      authorize: () => Promise.resolve("unauthenticated"),
    }),
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "AUTHENTICATION_REQUIRED");
});

Deno.test("OP-01 AAL2 signs the exact payload and proves first plus replay", async () => {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const resend = new Resend("re_webhook_verification_only");
  let invocation = 0;
  const response = await handleRequest(
    request(),
    dependencies({
      invoke: async (target: string, init: RequestInit) => {
        calls.push({ url: target, init });
        const headers = new Headers(init.headers);
        const verified = await resend.webhooks.verify({
          payload: String(init.body),
          headers: {
            id: headers.get("svix-id")!,
            timestamp: headers.get("svix-timestamp")!,
            signature: headers.get("svix-signature")!,
          },
          webhookSecret: secret,
        });
        assertEquals(verified as unknown, {
          type: "email.received",
          created_at: "2000-01-01T00:00:00.000Z",
          marker: "SDF_INBOUND_SIGNED_CANARY_V1",
          data: {
            email_id: "internal_e2e_sdf_inbound_canary_v1",
            message_id: "<internal-e2e-sdf-inbound-canary-v1@invalid.local>",
            from: "sdf-inbound-canary@invalid.local",
            to: ["sdf-inbound-canary@invalid.local"],
            created_at: "2000-01-01T00:00:00.000Z",
          },
        });
        invocation += 1;
        return new Response(
          JSON.stringify({
            ok: true,
            state: invocation === 1 ? "received" : "replayed",
            receipt_id: "never-forward-this-id",
          }),
          { status: 200 },
        );
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    "https://lorenzowebsolutions.be",
  );
  assertEquals(await response.json(), {
    ok: true,
    canary: "SDF_INBOUND_SIGNED_CANARY_V1",
    first: "received",
    replay: "replayed",
    classification: "internal_e2e",
    receipt_count: 1,
    delivery_count: 1,
  });
  assertEquals(calls.length, 2);
  assertEquals(calls[0].url, `${url}/functions/v1/sdf-inbound-email`);
  assertEquals(calls[1].url, calls[0].url);
  assertEquals(calls[1].init.body, calls[0].init.body);
  assertEquals(calls[1].init.headers, calls[0].init.headers);
});

Deno.test("per-call timeout aborts and returns a fixed non-sensitive code", async () => {
  const response = await handleRequest(
    request(),
    dependencies({
      invoke: (_target: string, init: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init.signal?.addEventListener(
            "abort",
            () => reject(new DOMException("aborted", "AbortError")),
          );
        }),
      callTimeoutMs: 5,
      totalTimeoutMs: 20,
    }),
  );
  assertEquals(response.status, 504);
  assertEquals(await response.json(), { ok: false, code: "CANARY_TIMEOUT" });
});

Deno.test("secret signature JWT and upstream errors never reach logs or response", async () => {
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
    let signature = "";
    const response = await handleRequest(
      request(),
      dependencies({
        invoke: (_target: string, init: RequestInit) => {
          signature = new Headers(init.headers).get("svix-signature") || "";
          return Promise.reject(new Error(`${secret}:${signature}:${jwt}`));
        },
      }),
    );
    const body = await response.text();
    assertEquals(response.status, 500);
    assertEquals(JSON.parse(body), {
      ok: false,
      code: "CANARY_EXECUTION_FAILED",
    });
    assertEquals(
      response.headers.get("access-control-allow-origin"),
      "https://lorenzowebsolutions.be",
    );
    assertEquals(output, []);
    assertEquals(body.includes(secret), false);
    assertEquals(body.includes(signature), false);
    assertEquals(body.includes(jwt), false);
    const responseHeaders = JSON.stringify([...response.headers.entries()]);
    assertEquals(responseHeaders.includes(secret), false);
    assertEquals(responseHeaders.includes(signature), false);
    assertEquals(responseHeaders.includes(jwt), false);
    assertEquals(responseHeaders.includes("*"), false);
    assertMatch(signature, /^v1,[A-Za-z0-9+/=]+$/);
  } finally {
    console.log = original.log;
    console.warn = original.warn;
    console.error = original.error;
  }
});

Deno.test("unexpected first or replay state fails closed", async () => {
  const response = await handleRequest(
    request(),
    dependencies({
      invoke: () =>
        Promise.resolve(
          new Response(
            JSON.stringify({
              ok: true,
              state: "replayed",
            }),
            { status: 200 },
          ),
        ),
    }),
  );
  assertEquals(response.status, 502);
  assertEquals((await response.json()).code, "CANARY_RESULT_MISMATCH");
});

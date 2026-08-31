import { assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  type ResendTransportInput,
  sendEmailViaResend,
} from "./resend-transport.ts";

const RESEND_URL = "https://api.resend.com/emails";
const PROVIDER_KEY =
  "sdf-initial-confirmation/fa240000-0000-4000-8000-000000000001";

function validInput(
  overrides: Partial<ResendTransportInput> = {},
): ResendTransportInput {
  return {
    apiKey: "resend-test-key",
    from: "Lorenzo Web Solutions <noreply@example.test>",
    to: "customer@example.test",
    subject: "Aanvraag ontvangen",
    html: "<p>Uw aanvraag is ontvangen.</p>",
    text: "Uw aanvraag is ontvangen.",
    idempotencyKey: PROVIDER_KEY,
    timeoutMs: 100,
    ...overrides,
  };
}

function fetchStub(
  implementation: (
    input: string | URL | Request,
    init?: RequestInit,
  ) => Promise<Response>,
): typeof fetch {
  return implementation as typeof fetch;
}

Deno.test("valid transport sends one exact Resend request and normalizes success", async () => {
  const requests: Request[] = [];
  const result = await sendEmailViaResend(
    validInput(),
    fetchStub((input, init) => {
      requests.push(new Request(input, init));
      return Promise.resolve(
        new Response('{"id":"provider-message-1"}', { status: 200 }),
      );
    }),
  );

  assertEquals(requests.length, 1);
  assertEquals(requests[0].url, RESEND_URL);
  assertEquals(requests[0].method, "POST");
  assertEquals(
    requests[0].headers.get("Authorization"),
    "Bearer resend-test-key",
  );
  assertEquals(requests[0].headers.get("Content-Type"), "application/json");
  assertEquals(requests[0].headers.get("Idempotency-Key"), PROVIDER_KEY);
  assertEquals(await requests[0].json(), {
    from: "Lorenzo Web Solutions <noreply@example.test>",
    to: ["customer@example.test"],
    subject: "Aanvraag ontvangen",
    html: "<p>Uw aanvraag is ontvangen.</p>",
    text: "Uw aanvraag is ontvangen.",
  });
  assertEquals(result, { ok: true, providerMessageId: "provider-message-1" });
});

Deno.test("caller-owned provider key stays stable across repeated transport attempts", async () => {
  const keys: Array<string | null> = [];
  const fakeFetch = fetchStub((input, init) => {
    keys.push(new Request(input, init).headers.get("Idempotency-Key"));
    return Promise.resolve(
      new Response('{"id":"provider-message-2"}', { status: 202 }),
    );
  });

  await sendEmailViaResend(validInput(), fakeFetch);
  await sendEmailViaResend(validInput(), fakeFetch);

  assertEquals(keys, [PROVIDER_KEY, PROVIDER_KEY]);
});

Deno.test("retryable HTTP statuses normalize without provider response exposure", async () => {
  for (const status of [408, 425, 429, 500, 502, 503, 504, 599]) {
    const result = await sendEmailViaResend(
      validInput(),
      fetchStub(() =>
        Promise.resolve(new Response("provider-secret-body", { status }))
      ),
    );
    assertEquals(result, {
      ok: false,
      retryable: true,
      code: "RESEND_HTTP_RETRYABLE",
    });
  }
});

Deno.test("ordinary 4xx statuses normalize as permanent", async () => {
  for (const status of [400, 401, 403, 404, 422]) {
    const result = await sendEmailViaResend(
      validInput(),
      fetchStub(() => Promise.resolve(new Response("rejected", { status }))),
    );
    assertEquals(result, {
      ok: false,
      retryable: false,
      code: "RESEND_HTTP_PERMANENT",
    });
  }
});

Deno.test("malformed 2xx provider responses are retryable technical failures", async () => {
  const responses = [
    new Response("not-json", { status: 200 }),
    new Response("{}", { status: 200 }),
    new Response('{"id":null}', { status: 200 }),
    new Response('{"id":42}', { status: 200 }),
    new Response('{"id":""}', { status: 200 }),
    new Response('{"id":"   "}', { status: 200 }),
  ];

  for (const response of responses) {
    const result = await sendEmailViaResend(
      validInput(),
      fetchStub(() => Promise.resolve(response)),
    );
    assertEquals(result, {
      ok: false,
      retryable: true,
      code: "PROVIDER_RESPONSE_INVALID",
    });
  }
});

Deno.test("configured timeout is retryable and cleans up through abort", async () => {
  let timeoutAborted = false;
  const result = await sendEmailViaResend(
    validInput({ timeoutMs: 1 }),
    fetchStub((_input, init) => {
      const signal = init?.signal;
      return new Promise((_resolve, reject) => {
        signal?.addEventListener(
          "abort",
          () => {
            timeoutAborted = true;
            reject(new DOMException("request aborted", "AbortError"));
          },
          { once: true },
        );
      });
    }),
  );

  assertEquals(timeoutAborted, true);
  assertEquals(result, { ok: false, retryable: true, code: "RESEND_TIMEOUT" });
});

Deno.test("network exception is a retryable normalized failure", async () => {
  const result = await sendEmailViaResend(
    validInput(),
    fetchStub(() =>
      Promise.reject(
        new TypeError("network unavailable with provider-secret-body"),
      )
    ),
  );
  assertEquals(result, {
    ok: false,
    retryable: true,
    code: "RESEND_NETWORK_ERROR",
  });
  assertFalse(JSON.stringify(result).includes("provider-secret-body"));
});

Deno.test("missing or blank API key fails before provider I/O", async () => {
  for (const apiKey of [undefined, "", "   "]) {
    let fetchCalls = 0;
    const result = await sendEmailViaResend(
      validInput({ apiKey } as Partial<ResendTransportInput>),
      fetchStub(() => {
        fetchCalls += 1;
        return Promise.resolve(
          new Response('{"id":"unexpected"}', { status: 200 }),
        );
      }),
    );
    assertEquals(result, {
      ok: false,
      retryable: false,
      code: "EMAIL_CONFIGURATION_INVALID",
    });
    assertEquals(fetchCalls, 0);
  }
});

Deno.test("invalid recipient fails before provider I/O", async () => {
  for (
    const to of [
      "",
      "   ",
      "not-an-email",
      "customer@example.test\r\nBcc:other@example.test",
    ]
  ) {
    let fetchCalls = 0;
    const result = await sendEmailViaResend(
      validInput({ to }),
      fetchStub(() => {
        fetchCalls += 1;
        return Promise.resolve(
          new Response('{"id":"unexpected"}', { status: 200 }),
        );
      }),
    );
    const code = to.includes("\r") || to.includes("\n")
      ? "EMAIL_HEADER_INVALID"
      : "EMAIL_INPUT_INVALID";
    assertEquals(result, { ok: false, retryable: false, code });
    assertEquals(fetchCalls, 0);
  }
});

Deno.test("invalid sender fails before provider I/O", async () => {
  for (
    const from of [
      "",
      "   ",
      "not-an-email",
      "sender@example.test\r\nBcc:other@example.test",
    ]
  ) {
    let fetchCalls = 0;
    const result = await sendEmailViaResend(
      validInput({ from }),
      fetchStub(() => {
        fetchCalls += 1;
        return Promise.resolve(
          new Response('{"id":"unexpected"}', { status: 200 }),
        );
      }),
    );
    const code = from.includes("\r") || from.includes("\n")
      ? "EMAIL_HEADER_INVALID"
      : "EMAIL_INPUT_INVALID";
    assertEquals(result, { ok: false, retryable: false, code });
    assertEquals(fetchCalls, 0);
  }
});

Deno.test("empty or unsafe subject fails before provider I/O", async () => {
  for (const subject of ["", "   ", "Subject\r\nBcc:other@example.test"]) {
    let fetchCalls = 0;
    const result = await sendEmailViaResend(
      validInput({ subject }),
      fetchStub(() => {
        fetchCalls += 1;
        return Promise.resolve(
          new Response('{"id":"unexpected"}', { status: 200 }),
        );
      }),
    );
    const code = subject.includes("\r") || subject.includes("\n")
      ? "EMAIL_HEADER_INVALID"
      : "EMAIL_INPUT_INVALID";
    assertEquals(result, { ok: false, retryable: false, code });
    assertEquals(fetchCalls, 0);
  }
});

Deno.test("both HTML and text bodies are required before provider I/O", async () => {
  for (
    const overrides of [{ html: "" }, { html: "   " }, { text: "" }, {
      text: "   ",
    }]
  ) {
    let fetchCalls = 0;
    const result = await sendEmailViaResend(
      validInput(overrides),
      fetchStub(() => {
        fetchCalls += 1;
        return Promise.resolve(
          new Response('{"id":"unexpected"}', { status: 200 }),
        );
      }),
    );
    assertEquals(result, {
      ok: false,
      retryable: false,
      code: "EMAIL_INPUT_INVALID",
    });
    assertEquals(fetchCalls, 0);
  }
});

Deno.test("header injection is rejected for every header source", async () => {
  const cases: Array<Partial<ResendTransportInput>> = [
    { apiKey: "key\r\ninjected" },
    { from: "sender@example.test\r\ninjected" },
    { to: "customer@example.test\ninjected" },
    { subject: "Subject\rInjected" },
    { idempotencyKey: `${PROVIDER_KEY}\ninjected` },
  ];

  for (const overrides of cases) {
    let fetchCalls = 0;
    const result = await sendEmailViaResend(
      validInput(overrides),
      fetchStub(() => {
        fetchCalls += 1;
        return Promise.resolve(
          new Response('{"id":"unexpected"}', { status: 200 }),
        );
      }),
    );
    assertEquals(result, {
      ok: false,
      retryable: false,
      code: "EMAIL_HEADER_INVALID",
    });
    assertEquals(fetchCalls, 0);
  }
});

Deno.test("empty idempotency key fails without fallback or provider call", async () => {
  for (const idempotencyKey of ["", "   "]) {
    let fetchCalls = 0;
    const result = await sendEmailViaResend(
      validInput({ idempotencyKey }),
      fetchStub(() => {
        fetchCalls += 1;
        return Promise.resolve(
          new Response('{"id":"unexpected"}', { status: 200 }),
        );
      }),
    );
    assertEquals(result, {
      ok: false,
      retryable: false,
      code: "EMAIL_INPUT_INVALID",
    });
    assertEquals(fetchCalls, 0);
  }
});

Deno.test("normalized failures expose no secrets, headers, raw response or businessstate", async () => {
  const apiKey = "private-resend-api-key";
  const rawBody = "private-provider-response";
  const result = await sendEmailViaResend(
    validInput({ apiKey }),
    fetchStub(() => Promise.resolve(new Response(rawBody, { status: 503 }))),
  );
  const serialized = JSON.stringify(result);

  assertEquals(Object.keys(result).sort(), ["code", "ok", "retryable"]);
  assertFalse(serialized.includes(apiKey));
  assertFalse(serialized.includes("Authorization"));
  assertFalse(serialized.includes(rawBody));
  for (
    const businessField of [
      "status",
      "pending",
      "processing",
      "retry_wait",
      "sent",
      "failed",
      "attempt_count",
      "lease",
      "next_attempt_at",
      "MANUAL_REVIEW",
    ]
  ) {
    assertFalse(serialized.includes(businessField));
  }
});

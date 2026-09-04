import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1";
import { handleSubmitPrivacyRequest } from "./index.ts";

const endpointUrl = "https://functions.test/submit-privacy-request";
const supabaseUrl = "https://supabase.test";
const modernSecret = "sb_secret_submit_privacy_test";
const idempotencyKey = "8acb4fa8-1fd2-4d3b-9b15-7adabe7843d1";
const requestId = "c24ca940-0ee8-49be-bd73-ad147810b123";
const payload = {
  name: "Jan Peeters",
  email: "jan@example.com",
  phone: null,
  message: "Ik wil graag inzage in mijn persoonsgegevens.",
};

function request(body: Record<string, unknown>, key = idempotencyKey): Request {
  return new Request(endpointUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Idempotency-Key": key,
      "User-Agent": "privacy-endpoint-test",
      "X-Forwarded-For": "203.0.113.10",
    },
    body: JSON.stringify(body),
  });
}

function setEnvironment(
  values: Record<string, string | undefined>,
): () => void {
  const previous = new Map<string, string | undefined>();
  for (const [name, value] of Object.entries(values)) {
    previous.set(name, Deno.env.get(name));
    if (value === undefined) Deno.env.delete(name);
    else Deno.env.set(name, value);
  }
  return () => {
    for (const [name, value] of previous) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  };
}

async function fingerprint(value: Record<string, unknown>): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

Deno.test("modern binding initializes the privileged client without the legacy runtime key", async () => {
  const restoreEnvironment = setEnvironment({
    SUPABASE_URL: supabaseUrl,
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: modernSecret }),
    SUPABASE_SERVICE_ROLE_KEY: undefined,
    APPROVAL_TOKEN_SECRET: "privacy-ip-hash-test-secret",
    RESEND_API_KEY: undefined,
    ADMIN_EMAIL: undefined,
    FROM_EMAIL: undefined,
  });
  const originalFetch = globalThis.fetch;
  const calls: Array<
    {
      method: string;
      url: URL;
      body: unknown;
      authorization: string | null;
      apikey: string | null;
    }
  > = [];

  globalThis.fetch = (async (input, init) => {
    const fetchRequest = input instanceof Request
      ? input
      : new Request(input, init);
    const url = new URL(fetchRequest.url);
    const method = fetchRequest.method;
    const body = method === "GET" || method === "HEAD"
      ? null
      : JSON.parse(await fetchRequest.clone().text());
    calls.push({
      method,
      url,
      body,
      authorization: fetchRequest.headers.get("authorization"),
      apikey: fetchRequest.headers.get("apikey"),
    });

    if (url.pathname === "/rest/v1/privacy_requests" && method === "GET") {
      return Response.json([], { status: 200 });
    }
    if (url.pathname === "/rest/v1/privacy_requests" && method === "HEAD") {
      return new Response(null, {
        status: 200,
        headers: { "Content-Range": "*/0" },
      });
    }
    if (
      url.pathname === "/rest/v1/rpc/create_privacy_request_idempotent" &&
      method === "POST"
    ) {
      return Response.json([{
        request_id: requestId,
        request_created_at: "2026-09-04T10:00:00.000Z",
        was_created: true,
        request_notification_status: "pending",
      }], { status: 200 });
    }
    if (url.pathname === "/rest/v1/privacy_requests" && method === "PATCH") {
      return Response.json([], { status: 200 });
    }
    throw new Error(`Unexpected network call: ${method} ${url}`);
  }) as typeof fetch;

  try {
    const response = await handleSubmitPrivacyRequest(request(payload));
    const responseBody = await response.json();
    assertEquals(response.status, 202);
    assertEquals(responseBody, {
      ok: true,
      code: "REQUEST_STORED_NOTIFICATION_FAILED",
      request_id: requestId,
    });
    assertEquals(calls.length, 4);
    for (const call of calls) {
      assertEquals(call.authorization, `Bearer ${modernSecret}`);
      assertEquals(call.apikey, modernSecret);
      assertEquals(call.url.origin, supabaseUrl);
    }

    const idempotencyLookup = calls[0];
    assertEquals(idempotencyLookup.method, "GET");
    assertEquals(idempotencyLookup.url.pathname, "/rest/v1/privacy_requests");
    assertEquals(
      idempotencyLookup.url.searchParams.get("select"),
      "id,request_fingerprint",
    );
    assertEquals(
      idempotencyLookup.url.searchParams.get("idempotency_key"),
      `eq.${idempotencyKey}`,
    );

    const rateCount = calls[1];
    assertEquals(rateCount.method, "HEAD");
    assertEquals(rateCount.url.pathname, "/rest/v1/privacy_requests");
    assertEquals(rateCount.url.searchParams.get("select"), "id");
    assertMatch(
      rateCount.url.searchParams.get("client_ip_hash") || "",
      /^eq\.[0-9a-f]{64}$/,
    );
    assertMatch(
      rateCount.url.searchParams.get("created_at") || "",
      /^gte\..+Z$/,
    );

    const rpc = calls[2];
    assertEquals(rpc.method, "POST");
    assertEquals(
      rpc.url.pathname,
      "/rest/v1/rpc/create_privacy_request_idempotent",
    );
    assertEquals(rpc.body, {
      p_idempotency_key: idempotencyKey,
      p_request_fingerprint: await fingerprint(payload),
      p_name: payload.name,
      p_email: payload.email,
      p_phone: payload.phone,
      p_message: payload.message,
      p_client_ip_hash: (rateCount.url.searchParams.get("client_ip_hash") || "")
        .slice(3),
      p_user_agent: "privacy-endpoint-test",
    });

    const notificationUpdate = calls[3];
    assertEquals(notificationUpdate.method, "PATCH");
    assertEquals(notificationUpdate.url.pathname, "/rest/v1/privacy_requests");
    assertEquals(
      notificationUpdate.url.searchParams.get("id"),
      `eq.${requestId}`,
    );
    const updateBody = notificationUpdate.body as Record<string, unknown>;
    assertEquals(Object.keys(updateBody).sort(), [
      "notification_attempted_at",
      "notification_error_code",
      "notification_status",
      "provider_message_id",
    ]);
    assertEquals(updateBody.notification_status, "failed");
    assertEquals(
      updateBody.notification_error_code,
      "EMAIL_CONFIGURATION_INVALID",
    );
    assertEquals(updateBody.provider_message_id, null);
  } finally {
    globalThis.fetch = originalFetch;
    restoreEnvironment();
  }
});

Deno.test("missing and invalid modern bindings fail closed without secret leakage", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalls = 0;
  globalThis.fetch = (() => {
    fetchCalls += 1;
    throw new Error("Network must not be called for invalid configuration");
  }) as typeof fetch;

  try {
    for (
      const binding of [
        undefined,
        JSON.stringify({ default: "leak-marker-invalid-secret" }),
      ]
    ) {
      const restoreEnvironment = setEnvironment({
        SUPABASE_URL: supabaseUrl,
        SUPABASE_SECRET_KEYS: binding,
        SUPABASE_SERVICE_ROLE_KEY: "legacy-key-must-not-be-used",
      });
      try {
        const response = await handleSubmitPrivacyRequest(request(payload));
        const rawBody = await response.text();
        assertEquals(response.status, 500);
        assertEquals(JSON.parse(rawBody).code, "SERVER_CONFIGURATION_ERROR");
        assert(!rawBody.includes("leak-marker-invalid-secret"));
        assert(!rawBody.includes("legacy-key-must-not-be-used"));
      } finally {
        restoreEnvironment();
      }
    }
    assertEquals(fetchCalls, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("idempotent replay returns the stored request without RPC, update, or email", async () => {
  const restoreEnvironment = setEnvironment({
    SUPABASE_URL: supabaseUrl,
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: modernSecret }),
    SUPABASE_SERVICE_ROLE_KEY: undefined,
    RESEND_API_KEY: "resend-key-that-must-not-be-used",
    ADMIN_EMAIL: "admin@example.com",
    FROM_EMAIL: "privacy@example.com",
  });
  const originalFetch = globalThis.fetch;
  let fetchCalls = 0;

  globalThis.fetch = (async (input, init) => {
    fetchCalls += 1;
    const fetchRequest = input instanceof Request
      ? input
      : new Request(input, init);
    const url = new URL(fetchRequest.url);
    if (
      url.pathname !== "/rest/v1/privacy_requests" ||
      fetchRequest.method !== "GET"
    ) {
      throw new Error(
        `Unexpected replay network call: ${fetchRequest.method} ${url}`,
      );
    }
    return Response.json([{
      id: requestId,
      request_fingerprint: await fingerprint(payload),
    }]);
  }) as typeof fetch;

  try {
    const response = await handleSubmitPrivacyRequest(request(payload));
    assertEquals(response.status, 200);
    assertEquals(await response.json(), {
      ok: true,
      code: "REQUEST_RECEIVED",
      request_id: requestId,
    });
    assertEquals(fetchCalls, 1);
  } finally {
    globalThis.fetch = originalFetch;
    restoreEnvironment();
  }
});

Deno.test("honeypot and validation errors remain unchanged and stop before database access", async () => {
  const restoreEnvironment = setEnvironment({
    SUPABASE_URL: supabaseUrl,
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: modernSecret }),
  });
  const originalFetch = globalThis.fetch;
  let fetchCalls = 0;
  globalThis.fetch = (() => {
    fetchCalls += 1;
    throw new Error("Validation failures must not access the network");
  }) as typeof fetch;

  try {
    const honeypotResponse = await handleSubmitPrivacyRequest(
      request({ ...payload, website: "spam.example" }),
    );
    assertEquals(honeypotResponse.status, 400);
    assertEquals(await honeypotResponse.json(), {
      ok: false,
      code: "HONEYPOT_TRIGGERED",
      field: "website",
      message: "Invalid input.",
    });

    const validationResponse = await handleSubmitPrivacyRequest(request({
      name: payload.name,
      message: payload.message,
    }));
    assertEquals(validationResponse.status, 400);
    assertEquals(await validationResponse.json(), {
      ok: false,
      code: "CONTACT_REQUIRED",
      field: "email_or_phone",
      message: "Invalid input.",
    });
    assertEquals(fetchCalls, 0);
  } finally {
    globalThis.fetch = originalFetch;
    restoreEnvironment();
  }
});

Deno.test("endpoint source keeps the privacy authority surface constrained", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const tablePaths = [...source.matchAll(/\.from\(\s*["']([^"']+)["']\s*\)/g)]
    .map((
      match,
    ) => match[1]);
  assertEquals(tablePaths, [
    "privacy_requests",
    "privacy_requests",
    "privacy_requests",
  ]);
  assertEquals(
    [...source.matchAll(/\.rpc\(\s*["']([^"']+)["']/g)].map((match) =>
      match[1]
    ),
    [
      "create_privacy_request_idempotent",
    ],
  );
  assert(source.includes('getSupabaseServerSecretKey("default")'));
  assert(!source.includes("SUPABASE_SERVICE_ROLE_KEY"));
  assert(!source.includes(".storage"));
  assert(!source.includes("auth.admin"));
});

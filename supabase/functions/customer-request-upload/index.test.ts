import { assertEquals } from "jsr:@std/assert@1";
import { createCustomerRequestUploadRuntime } from "./index.ts";

const modernKey = "sb_secret_customerRequestUploadTest_123";

function environment(
  binding: string | undefined,
  url = "https://example.supabase.co",
) {
  return {
    get(name: string): string | undefined {
      if (name === "SUPABASE_URL") return url;
      if (name === "SUPABASE_SECRET_KEYS") return binding;
      if (name === "SUPABASE_SERVICE_ROLE_KEY") {
        return "legacy-key-must-not-be-used";
      }
      return undefined;
    },
  };
}

function client() {
  return {
    rpc: async () => ({ data: null, error: null }),
    storage: {
      from: () => ({
        createSignedUploadUrl: async () => ({ data: null, error: null }),
        download: async () => ({ data: null, error: null }),
        remove: async () => ({ error: null }),
      }),
    },
  };
}

Deno.test("customer upload runtime uses the modern server binding without the legacy key", async () => {
  let clientInput: unknown;
  const runtime = createCustomerRequestUploadRuntime(
    environment(JSON.stringify({ default: modernKey })),
    (url, key, options) => {
      clientInput = { url, key, options };
      return client();
    },
  );

  const response = await runtime(new Request("https://example.test", {
    headers: { Authorization: "Bearer invalid" },
  }));
  assertEquals(response.status, 200);
  assertEquals(clientInput, {
    url: "https://example.supabase.co",
    key: modernKey,
    options: { auth: { persistSession: false, autoRefreshToken: false } },
  });
});

Deno.test("customer upload runtime fails closed for missing or invalid configuration without leakage", async () => {
  const sensitiveValue = "sb_publishable_invalidBindingMarker_456";
  for (
    const values of [
      { binding: undefined, url: "https://example.supabase.co" },
      { binding: "not-json", url: "https://example.supabase.co" },
      {
        binding: JSON.stringify({ default: sensitiveValue }),
        url: "https://example.supabase.co",
      },
      { binding: JSON.stringify({ default: modernKey }), url: "" },
    ]
  ) {
    let clientCreated = false;
    const runtime = createCustomerRequestUploadRuntime(
      environment(values.binding, values.url),
      () => {
        clientCreated = true;
        return client();
      },
    );
    const response = await runtime(new Request("https://example.test"));
    const text = await response.text();
    assertEquals(response.status, 500);
    assertEquals(JSON.parse(text), {
      ok: false,
      state: "UPLOAD_NOT_AVAILABLE",
    });
    assertEquals(response.headers.get("cache-control"), "no-store");
    assertEquals(text.includes(sensitiveValue), false);
    assertEquals(text.includes("legacy-key-must-not-be-used"), false);
    assertEquals(clientCreated, false);
  }
});

Deno.test("customer upload runtime preserves RPC and Storage authority surfaces", async () => {
  const entrypoint = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const handler = await Deno.readTextFile(
    new URL("../_shared/customer-request-upload-handler.ts", import.meta.url),
  );
  const rpcNames = [...handler.matchAll(/client\.rpc\(\s*"([^"]+)"/g)]
    .map((match) => match[1]);
  assertEquals([...new Set(rpcNames)], [
    "consume_acceptance_capability_rate_limit_v1",
    "resolve_customer_request_upload_capability_v1",
    "prepare_customer_request_upload_v1",
    "finalize_customer_request_uploaded_file_v1",
    "complete_customer_request_upload_request_v1",
  ]);
  assertEquals(entrypoint.includes('getSupabaseServerSecretKey("default"'), true);
  assertEquals(entrypoint.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
  assertEquals(entrypoint.includes("SUPABASE_ANON_KEY"), false);
  assertEquals(entrypoint.includes("getSupabasePublishableKey"), false);
  assertEquals(entrypoint.includes("client.from("), false);
  assertEquals(entrypoint.includes("auth.admin"), false);
  assertEquals(
    [...entrypoint.matchAll(/client\.storage\.from\(bucket\)\.(createSignedUploadUrl|download|remove)/g)]
      .map((match) => match[1]),
    ["createSignedUploadUrl", "download", "remove"],
  );
  assertEquals(
    entrypoint.includes(
      "createSignedUploadUrl(path, { upsert: false })",
    ),
    true,
  );
  assertEquals(
    handler.includes(
      'if (result.state === "REJECTED") await storage.remove("customer-request-quarantine", [reservation.storage_object_path]);',
    ),
    true,
  );
});
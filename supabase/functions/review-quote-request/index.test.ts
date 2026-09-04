import { assertEquals } from "jsr:@std/assert@1";
import {
  handleReviewQuoteRequest,
  resolveReviewQuoteRequestConfiguration,
} from "./index.ts";

const serverKey = ["sb", "secret", "reviewQuoteRequest", "test"].join("_");

function environment(values: Record<string, string | undefined>) {
  return { get: (name: string) => values[name] };
}

async function withInvalidBindingResponse(
  serverBinding: string | undefined,
  legacyBinding: string | undefined = "must-not-be-read",
): Promise<Response> {
  const previousEnvironment = new Map<string, string | undefined>();
  for (
    const [name, value] of [
      ["SUPABASE_URL", "https://supabase.test"],
      ["SUPABASE_SERVICE_ROLE_KEY", legacyBinding],
      ["SUPABASE_SECRET_KEYS", serverBinding],
    ] as const
  ) {
    previousEnvironment.set(name, Deno.env.get(name));
    if (value === undefined) Deno.env.delete(name);
    else Deno.env.set(name, value);
  }

  try {
    return await handleReviewQuoteRequest(
      new Request("https://functions.test/review-quote-request"),
    );
  } finally {
    for (const [name, value] of previousEnvironment) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

Deno.test("review configuration uses only the modern server binding and preserves its failure contract", async () => {
  assertEquals(
    resolveReviewQuoteRequestConfiguration(environment({
      SUPABASE_URL: "https://supabase.test",
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
    })),
    { url: "https://supabase.test", serviceRoleKey: serverKey },
  );

  for (
    const [serverBinding, legacyBinding] of [
      [undefined, undefined],
      ["not-json", "must-not-be-read"],
      [
        JSON.stringify({ default: "legacy-service-role-key" }),
        "must-not-be-read",
      ],
      [undefined, "legacy-only-binding"],
    ] as const
  ) {
    assertEquals(
      resolveReviewQuoteRequestConfiguration(environment({
        SUPABASE_URL: "https://supabase.test",
        SUPABASE_SERVICE_ROLE_KEY: legacyBinding,
        SUPABASE_SECRET_KEYS: serverBinding,
      })),
      null,
    );

    const response = await withInvalidBindingResponse(
      serverBinding,
      legacyBinding,
    );
    assertEquals(response.status, 500);
    assertEquals(await response.json(), {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
      message: "Server configuration is incomplete.",
    });
  }

  assertEquals(
    resolveReviewQuoteRequestConfiguration(environment({
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
    })),
    null,
  );

  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertEquals(source.includes('getSupabaseServerSecretKey("default"'), true);
  assertEquals(source.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
  assertEquals(source.match(/createClient\(/g)?.length, 1);
  assertEquals(source.match(/\.from\(/g)?.length, 5);
  assertEquals(source.match(/\.rpc\(/g)?.length, 5);
  for (
    const expectedRpc of [
      "create_quote_request_intake_invitation",
      "get_quote_request_intake_invitation",
      "requeue_quote_request_email_job",
      "transition_quote_request_review",
    ]
  ) assertEquals(source.includes(expectedRpc), true);
  for (
    const forbidden of [
      "SUPABASE_ANON_KEY",
      "getSupabasePublishableKey",
      "auth.getUser",
      "auth.admin",
      ".storage.",
    ]
  ) assertEquals(source.includes(forbidden), false);
});

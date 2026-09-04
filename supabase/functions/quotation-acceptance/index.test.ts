import { assertEquals } from "jsr:@std/assert@1";
import { resolveQuotationAcceptanceConfiguration } from "./index.ts";

function environment(values: Record<string, string | undefined>) {
  return { get: (name: string) => values[name] };
}

Deno.test("runtime adapter uses only the modern server binding and fails closed", async () => {
  const serverKey = ["sb", "secret", "quotationAcceptance", "test"].join("_");
  assertEquals(
    resolveQuotationAcceptanceConfiguration(environment({
      SUPABASE_URL: "https://project.supabase.co",
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
    })),
    { url: "https://project.supabase.co", key: serverKey },
  );

  for (const serverBinding of [
    undefined,
    "not-json",
    JSON.stringify({ default: "legacy-service-role-key" }),
  ]) {
    assertEquals(
      resolveQuotationAcceptanceConfiguration(environment({
        SUPABASE_URL: "https://project.supabase.co",
        SUPABASE_SERVICE_ROLE_KEY: "must-not-be-read",
        SUPABASE_SECRET_KEYS: serverBinding,
      })),
      null,
    );
  }
  assertEquals(
    resolveQuotationAcceptanceConfiguration(environment({
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
    })),
    null,
  );

  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(source.includes('getSupabaseServerSecretKey("default"'), true);
  assertEquals(source.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
  assertEquals(source.includes("ACCEPTANCE_NOT_AVAILABLE"), true);
  for (const forbidden of [
    "SUPABASE_ANON_KEY",
    "getSupabasePublishableKey",
    "auth.getUser",
    "auth.admin",
    ".from(",
    ".storage.",
  ]) assertEquals(source.includes(forbidden), false);
});

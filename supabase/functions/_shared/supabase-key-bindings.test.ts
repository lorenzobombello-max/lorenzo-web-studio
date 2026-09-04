import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  getSupabasePublishableKey,
  getSupabaseServerSecretKey,
  SUPABASE_KEY_BINDING_ERROR,
  type SupabaseKeyBindingEnvironment,
  SupabaseKeyBindingError,
} from "./supabase-key-bindings.ts";

const serverKey = "sb_secret_localServerKey_123";
const publishableKey = "sb_publishable_localPublishableKey_456";

function environment(
  values: Record<string, string | undefined>,
): SupabaseKeyBindingEnvironment {
  return { get: (name) => values[name] };
}

function assertBindingError(action: () => unknown): SupabaseKeyBindingError {
  return assertThrows(
    action,
    SupabaseKeyBindingError,
    SUPABASE_KEY_BINDING_ERROR,
  );
}

Deno.test("selects a valid server secret key", () => {
  assertEquals(
    getSupabaseServerSecretKey(
      "default",
      environment({
        SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
      }),
    ),
    serverKey,
  );
});

Deno.test("selects a valid publishable key", () => {
  assertEquals(
    getSupabasePublishableKey(
      "default",
      environment({
        SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: publishableKey }),
      }),
    ),
    publishableKey,
  );
});

Deno.test("selects an explicit entry from multiple entries", () => {
  const keys = JSON.stringify({
    default: "sb_secret_default_1",
    rotation: "sb_secret_rotation_2",
  });
  assertEquals(
    getSupabaseServerSecretKey(
      "rotation",
      environment({ SUPABASE_SECRET_KEYS: keys }),
    ),
    "sb_secret_rotation_2",
  );
});

Deno.test("fails closed for missing, empty, malformed, and structurally invalid bindings", () => {
  for (
    const value of [
      undefined,
      "",
      "not-json",
      "null",
      "[]",
      JSON.stringify({ default: "" }),
      JSON.stringify({ default: serverKey, invalid: 1 }),
    ]
  ) {
    assertBindingError(() =>
      getSupabaseServerSecretKey(
        "default",
        environment({ SUPABASE_SECRET_KEYS: value }),
      )
    );
  }
});

Deno.test("fails closed when the requested entry is absent", () => {
  assertBindingError(() =>
    getSupabaseServerSecretKey(
      "rotation",
      environment({
        SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
      }),
    )
  );
});

Deno.test("fails closed for the wrong or malformed key kind", () => {
  for (
    const value of [
      publishableKey,
      "sb_secret_",
      "sb_secret_invalid.value",
      "legacy-jwt",
    ]
  ) {
    assertBindingError(() =>
      getSupabaseServerSecretKey(
        "default",
        environment({
          SUPABASE_SECRET_KEYS: JSON.stringify({ default: value }),
        }),
      )
    );
  }
  assertBindingError(() =>
    getSupabasePublishableKey(
      "default",
      environment({
        SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: serverKey }),
      }),
    )
  );
});

Deno.test("errors and console output never contain binding values", () => {
  const sensitiveValue = "sb_secret_mustNeverAppear_789";
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
    const error = assertBindingError(() =>
      getSupabasePublishableKey(
        "default",
        environment({
          SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
            default: sensitiveValue,
          }),
        }),
      )
    );
    assertEquals(error.message.includes(sensitiveValue), false);
    assertEquals(error.stack?.includes(sensitiveValue) ?? false, false);
    assertEquals(output, []);
  } finally {
    console.log = original.log;
    console.warn = original.warn;
    console.error = original.error;
  }
});

Deno.test("selection is deterministic and does not mutate the binding", () => {
  const binding = JSON.stringify({ default: serverKey });
  const source = environment({ SUPABASE_SECRET_KEYS: binding });
  assertEquals(
    getSupabaseServerSecretKey("default", source),
    getSupabaseServerSecretKey("default", source),
  );
  assertEquals(source.get("SUPABASE_SECRET_KEYS"), binding);
});

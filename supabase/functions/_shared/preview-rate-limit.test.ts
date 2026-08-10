import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  capabilityPreviewRateLimitKey,
  consumePreviewRateLimit,
  globalPreviewRateLimitKey,
  previewRateLimitConfig,
  type PreviewRateLimitRpcClient,
} from "./preview-rate-limit.ts";

const originalSecret = Deno.env.get("PREVIEW_RATE_LIMIT_SECRET");
const configNames = [
  "PREVIEW_GLOBAL_WINDOW_SECONDS",
  "PREVIEW_GLOBAL_MAX_REQUESTS",
  "PREVIEW_CAPABILITY_WINDOW_SECONDS",
  "PREVIEW_CAPABILITY_MAX_REQUESTS",
  "PREVIEW_RATE_LIMIT_CLEANUP_BATCH",
];

function restoreEnvironment() {
  if (originalSecret === undefined) Deno.env.delete("PREVIEW_RATE_LIMIT_SECRET");
  else Deno.env.set("PREVIEW_RATE_LIMIT_SECRET", originalSecret);
  configNames.forEach((name) => Deno.env.delete(name));
}

Deno.test({
  name: "preview limiter uses bounded tunable operational defaults",
  fn() {
    try {
      configNames.forEach((name) => Deno.env.delete(name));
      assertEquals(previewRateLimitConfig(), {
        global: { windowSeconds: 60, maxRequests: 300 },
        capability: { windowSeconds: 60, maxRequests: 30 },
        cleanupBatch: 25,
      });
      Deno.env.set("PREVIEW_CAPABILITY_MAX_REQUESTS", "31");
      assertEquals(previewRateLimitConfig().capability.maxRequests, 31);
      Deno.env.set("PREVIEW_GLOBAL_WINDOW_SECONDS", "0");
      assertThrows(() => previewRateLimitConfig(), Error, "Invalid PREVIEW_GLOBAL_WINDOW_SECONDS");
    } finally {
      restoreEnvironment();
    }
  },
});

Deno.test({
  name: "preview limiter keys are domain-separated HMAC values",
  async fn() {
    try {
      Deno.env.set("PREVIEW_RATE_LIMIT_SECRET", "s".repeat(32));
      const capabilityHash = "a".repeat(64);
      const globalKey = await globalPreviewRateLimitKey();
      const capabilityKey = await capabilityPreviewRateLimitKey(capabilityHash);
      assertEquals(/^[0-9a-f]{64}$/.test(globalKey), true);
      assertEquals(/^[0-9a-f]{64}$/.test(capabilityKey), true);
      assertEquals(globalKey === capabilityKey, false);
      assertEquals(capabilityKey.includes(capabilityHash), false);
      assertThrows(() => capabilityPreviewRateLimitKey("raw-token"), TypeError);
    } finally {
      restoreEnvironment();
    }
  },
});

Deno.test("preview limiter passes central config and accepts an authoritative decision", async () => {
  let call: { functionName: string; parameters: Record<string, unknown> } | null = null;
  const client: PreviewRateLimitRpcClient = {
    rpc(functionName, parameters) {
      call = { functionName, parameters };
      return Promise.resolve({
        data: [{ allowed: false, remaining: 0, reset_at: "2026-08-10T12:01:00Z", retry_after_seconds: 42 }],
        error: null,
      });
    },
  };
  const decision = await consumePreviewRateLimit(client, "preview_capability", "b".repeat(64), {
    global: { windowSeconds: 60, maxRequests: 300 },
    capability: { windowSeconds: 60, maxRequests: 30 },
    cleanupBatch: 25,
  });
  assertEquals(call, {
    functionName: "consume_preview_rate_limit_v1",
    parameters: {
      p_namespace: "preview_capability",
      p_key_hash: "b".repeat(64),
      p_window_seconds: 60,
      p_max_requests: 30,
      p_cleanup_batch: 25,
    },
  });
  assertEquals(decision.retryAfterSeconds, 42);
  assertEquals(decision.allowed, false);
});

Deno.test("preview limiter fails closed on RPC errors and malformed state", async () => {
  const errorClient: PreviewRateLimitRpcClient = {
    rpc: () => Promise.resolve({ data: null, error: { message: "unavailable" } }),
  };
  await assertRejects(
    () => consumePreviewRateLimit(errorClient, "preview_global", "a".repeat(64)),
    Error,
    "Preview rate-limit RPC failed",
  );

  for (const data of [
    null,
    [],
    [{ allowed: true, remaining: -1, reset_at: "invalid", retry_after_seconds: 0 }],
    [{ allowed: false, remaining: 0, reset_at: "2026-08-10T12:01:00Z", retry_after_seconds: 0 }],
  ]) {
    const malformedClient: PreviewRateLimitRpcClient = {
      rpc: () => Promise.resolve({ data, error: null }),
    };
    await assertRejects(
      () => consumePreviewRateLimit(malformedClient, "preview_global", "a".repeat(64)),
      TypeError,
      "Malformed preview rate-limit result",
    );
  }
});

export type PreviewRateLimitNamespace =
  | "preview_global"
  | "preview_capability";

export interface PreviewRateLimitDecision {
  allowed: boolean;
  remaining: number;
  resetAt: string;
  retryAfterSeconds: number;
}

export interface PreviewRateLimitRpcClient {
  rpc(
    functionName: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
}

export interface PreviewRateLimitConfig {
  global: { windowSeconds: number; maxRequests: number };
  capability: { windowSeconds: number; maxRequests: number };
  cleanupBatch: number;
}

const DEFAULT_CONFIG: PreviewRateLimitConfig = {
  global: { windowSeconds: 60, maxRequests: 300 },
  capability: { windowSeconds: 60, maxRequests: 30 },
  cleanupBatch: 25,
};

function boundedInteger(
  name: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const raw = Deno.env.get(name);
  if (raw === undefined || raw === "") return fallback;
  if (!/^\d+$/.test(raw)) throw new Error(`Invalid ${name}`);
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`Invalid ${name}`);
  }
  return value;
}

export function previewRateLimitConfig(): PreviewRateLimitConfig {
  return {
    global: {
      windowSeconds: boundedInteger("PREVIEW_GLOBAL_WINDOW_SECONDS", DEFAULT_CONFIG.global.windowSeconds, 1, 3600),
      maxRequests: boundedInteger("PREVIEW_GLOBAL_MAX_REQUESTS", DEFAULT_CONFIG.global.maxRequests, 1, 10000),
    },
    capability: {
      windowSeconds: boundedInteger(
        "PREVIEW_CAPABILITY_WINDOW_SECONDS",
        DEFAULT_CONFIG.capability.windowSeconds,
        1,
        3600,
      ),
      maxRequests: boundedInteger(
        "PREVIEW_CAPABILITY_MAX_REQUESTS",
        DEFAULT_CONFIG.capability.maxRequests,
        1,
        10000,
      ),
    },
    cleanupBatch: boundedInteger("PREVIEW_RATE_LIMIT_CLEANUP_BATCH", DEFAULT_CONFIG.cleanupBatch, 0, 100),
  };
}

function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function rateLimitHash(domain: string, identity: string): Promise<string> {
  const secret = Deno.env.get("PREVIEW_RATE_LIMIT_SECRET");
  if (!secret || secret.length < 32) throw new Error("Missing PREVIEW_RATE_LIMIT_SECRET");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`lws-preview-rate-limit-v1:${domain}:${identity}`),
  ));
}

export function globalPreviewRateLimitKey(): Promise<string> {
  return rateLimitHash("global", "all-preview-requests");
}

export function capabilityPreviewRateLimitKey(
  intakeTokenHash: string,
): Promise<string> {
  if (!/^[0-9a-f]{64}$/.test(intakeTokenHash)) {
    throw new TypeError("Invalid intake capability hash");
  }
  return rateLimitHash("capability", intakeTokenHash);
}

function parseDecision(value: unknown): PreviewRateLimitDecision {
  const row = Array.isArray(value) && value.length === 1 ? value[0] : null;
  if (!row || typeof row !== "object" || Array.isArray(row)) {
    throw new TypeError("Malformed preview rate-limit result");
  }
  const source = row as Record<string, unknown>;
  const resetAt = typeof source.reset_at === "string" ? source.reset_at : "";
  const parsedResetAt = Date.parse(resetAt);
  if (
    typeof source.allowed !== "boolean" ||
    !Number.isSafeInteger(source.remaining) || Number(source.remaining) < 0 ||
    !Number.isSafeInteger(source.retry_after_seconds) ||
    Number(source.retry_after_seconds) < 0 || Number(source.retry_after_seconds) > 3600 ||
    !Number.isFinite(parsedResetAt) ||
    (source.allowed === true && source.retry_after_seconds !== 0) ||
    (source.allowed === false && Number(source.retry_after_seconds) < 1)
  ) throw new TypeError("Malformed preview rate-limit result");
  return {
    allowed: source.allowed,
    remaining: Number(source.remaining),
    resetAt,
    retryAfterSeconds: Number(source.retry_after_seconds),
  };
}

export async function consumePreviewRateLimit(
  client: PreviewRateLimitRpcClient,
  namespace: PreviewRateLimitNamespace,
  keyHash: string,
  config: PreviewRateLimitConfig = previewRateLimitConfig(),
): Promise<PreviewRateLimitDecision> {
  if (!/^[0-9a-f]{64}$/.test(keyHash)) throw new TypeError("Invalid rate-limit key");
  const limit = namespace === "preview_global" ? config.global : config.capability;
  const { data, error } = await client.rpc("consume_preview_rate_limit_v1", {
    p_namespace: namespace,
    p_key_hash: keyHash,
    p_window_seconds: limit.windowSeconds,
    p_max_requests: limit.maxRequests,
    p_cleanup_batch: config.cleanupBatch,
  });
  if (error) throw new Error("Preview rate-limit RPC failed");
  return parseDecision(data);
}

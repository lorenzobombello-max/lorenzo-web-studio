import { assertEquals } from "jsr:@std/assert@1";
import { calculateBudgetGuard } from "./pricing-engine.ts";
import type { RawPricingScope } from "./pricing-normalization.ts";
import { handlePricingPreview } from "./pricing-preview-handler.ts";
import type { PreviewRateLimitRpcClient } from "./preview-rate-limit.ts";

const token = "A".repeat(43);
const origin = "https://lorenzowebsolutions.be";
const body = {
  action: "preview_budget_guard",
  token,
  scopeRevision: 12,
  data: {
    requested_pages: ["home", "contact"],
    requested_features: ["contact_form"],
  },
};

function allowedDecision() {
  return {
    data: [{
      allowed: true,
      remaining: 20,
      reset_at: "2026-08-10T12:01:00Z",
      retry_after_seconds: 0,
    }],
    error: null,
  };
}

function context(status = "in_progress") {
  return {
    data: [{
      intake_status: status,
      budget_label: "EUR 3.200 t/m EUR 6.000",
      budget_category_scheme: "budget_guard_v1",
      budget_category_code: "3200_to_6000_inclusive",
    }],
    error: null,
  };
}

function dependencies(onCalculate: () => void = () => {}) {
  return {
    validateCapability(value: unknown) {
      if (value !== token) throw new Error("invalid token");
      return token;
    },
    hashCapability: () => Promise.resolve("a".repeat(64)),
    globalLimitKey: () => Promise.resolve("b".repeat(64)),
    capabilityLimitKey: () => Promise.resolve("c".repeat(64)),
    calculate(input: RawPricingScope) {
      onCalculate();
      return calculateBudgetGuard(input);
    },
  };
}

Deno.test("preview success uses global, context and capability RPCs without mutation RPCs", async () => {
  const calls: Array<{ name: string; parameters: Record<string, unknown> }> = [];
  const client: PreviewRateLimitRpcClient = {
    rpc(name, parameters) {
      calls.push({ name, parameters });
      if (name === "inspect_preview_budget_guard_context_v1") return Promise.resolve(context());
      return Promise.resolve(allowedDecision());
    },
  };
  const response = await handlePricingPreview(body, origin, client, dependencies());
  const payload = await response.json();

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(payload.preview.scopeRevision, 12);
  assertEquals(payload.preview.nonBinding, true);
  assertEquals(calls.map((call) => call.name), [
    "consume_preview_rate_limit_v1",
    "inspect_preview_budget_guard_context_v1",
    "consume_preview_rate_limit_v1",
  ]);
  assertEquals(JSON.stringify(calls).includes("update_quote_request_intake"), false);
  assertEquals(JSON.stringify(payload).includes("pricingSnapshot"), false);
  assertEquals(JSON.stringify(payload).includes("proof"), false);
});

Deno.test("global denial returns authoritative 429 before token validation or pricing", async () => {
  let calculated = false;
  const client: PreviewRateLimitRpcClient = {
    rpc() {
      return Promise.resolve({
        data: [{
          allowed: false,
          remaining: 0,
          reset_at: "2026-08-10T12:01:00Z",
          retry_after_seconds: 19,
        }],
        error: null,
      });
    },
  };
  const response = await handlePricingPreview(
    { ...body, token: "invalid" },
    origin,
    client,
    dependencies(() => calculated = true),
  );
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("retry-after"), "19");
  assertEquals((await response.json()).code, "PREVIEW_RATE_LIMITED");
  assertEquals(calculated, false);
});

Deno.test("invalid token and unavailable lifecycle create no per-capability bucket", async () => {
  for (const variant of ["invalid", "submitted"] as const) {
    const calls: string[] = [];
    const client: PreviewRateLimitRpcClient = {
      rpc(name) {
        calls.push(name);
        if (name === "inspect_preview_budget_guard_context_v1") {
          return Promise.resolve(context("submitted"));
        }
        return Promise.resolve(allowedDecision());
      },
    };
    const response = await handlePricingPreview(
      variant === "invalid" ? { ...body, token: "invalid" } : body,
      origin,
      client,
      dependencies(),
    );
    assertEquals(response.status, variant === "invalid" ? 401 : 409);
    assertEquals(calls.filter((name) => name === "consume_preview_rate_limit_v1").length, 1);
  }
});

Deno.test("capability denial returns 429 and performs no pricing calculation", async () => {
  let limitCalls = 0;
  let calculated = false;
  const client: PreviewRateLimitRpcClient = {
    rpc(name) {
      if (name === "inspect_preview_budget_guard_context_v1") return Promise.resolve(context());
      limitCalls += 1;
      return Promise.resolve(limitCalls === 1 ? allowedDecision() : {
        data: [{
          allowed: false,
          remaining: 0,
          reset_at: "2026-08-10T12:01:00Z",
          retry_after_seconds: 7,
        }],
        error: null,
      });
    },
  };
  const response = await handlePricingPreview(body, origin, client, dependencies(() => calculated = true));
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("retry-after"), "7");
  assertEquals(calculated, false);
});

Deno.test("limiter RPC failure and malformed result fail closed with 503", async () => {
  for (const result of [
    { data: null, error: { message: "database unavailable" } },
    { data: [{ allowed: "yes" }], error: null },
  ]) {
    let calculated = false;
    const client: PreviewRateLimitRpcClient = { rpc: () => Promise.resolve(result) };
    const response = await handlePricingPreview(body, origin, client, dependencies(() => calculated = true));
    assertEquals(response.status, 503);
    assertEquals((await response.json()).code, "PREVIEW_RATE_LIMIT_UNAVAILABLE");
    assertEquals(calculated, false);
  }
});

Deno.test("closed request schema rejects injections only after both valid limits", async () => {
  const calls: string[] = [];
  const client: PreviewRateLimitRpcClient = {
    rpc(name) {
      calls.push(name);
      if (name === "inspect_preview_budget_guard_context_v1") return Promise.resolve(context("invited"));
      return Promise.resolve(allowedDecision());
    },
  };
  const response = await handlePricingPreview({
    ...body,
    data: { ...body.data, selectedPackage: "professional" },
  }, origin, client, dependencies());
  assertEquals(response.status, 400);
  assertEquals((await response.json()).code, "INVALID_PREVIEW_REQUEST");
  assertEquals(calls.filter((name) => name === "consume_preview_rate_limit_v1").length, 2);
});

Deno.test("manual success keeps compatible budget independent and suppresses amounts", async () => {
  const client: PreviewRateLimitRpcClient = {
    rpc(name) {
      if (name === "inspect_preview_budget_guard_context_v1") return Promise.resolve(context());
      return Promise.resolve(allowedDecision());
    },
  };
  const response = await handlePricingPreview({
    ...body,
    data: {
      requested_pages: ["home", "about", "services", "portfolio", "team", "pricing"],
      requested_features: ["customer_login"],
    },
  }, origin, client, dependencies());
  const payload = await response.json();
  assertEquals(response.status, 200);
  assertEquals(payload.preview.budget.comparisonStatus, "WITHIN_KNOWN_BUDGET");
  assertEquals(payload.preview.budget.knownMinimumExceedsBudget, false);
  assertEquals(payload.preview.summary.manualReviewRequired, true);
  assertEquals(JSON.stringify(payload.preview).includes("amountMinor"), false);
  assertEquals("knownMinimumMinor" in payload.preview.summary, false);
});

import { corsHeaders } from "./cors.ts";
import {
  calculateBudgetGuard,
  evaluateBudget,
  resolveBudgetEvidence,
} from "./pricing-engine.ts";
import { buildCustomerPricingPreview } from "./pricing-preview-dto.ts";
import {
  capabilityPreviewRateLimitKey,
  consumePreviewRateLimit,
  globalPreviewRateLimitKey,
  type PreviewRateLimitRpcClient,
} from "./preview-rate-limit.ts";
import { hashIntakeToken } from "./security.ts";
import {
  InputValidationError,
  sanitizeAndValidatePricingPreviewInput,
  validateToken,
} from "./validation.ts";

type PreviewRpcClient = PreviewRateLimitRpcClient;

interface PreviewDependencies {
  validateCapability(value: unknown): string;
  hashCapability(value: string): Promise<string>;
  globalLimitKey(): Promise<string>;
  capabilityLimitKey(value: string): Promise<string>;
  calculate: typeof calculateBudgetGuard;
}

const defaultDependencies: PreviewDependencies = {
  validateCapability: validateToken,
  hashCapability: hashIntakeToken,
  globalLimitKey: globalPreviewRateLimitKey,
  capabilityLimitKey: capabilityPreviewRateLimitKey,
  calculate: calculateBudgetGuard,
};

function response(
  status: number,
  body: Record<string, unknown>,
  origin: string | null,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      ...headers,
    },
  });
}

function limiterUnavailable(origin: string | null): Response {
  return response(503, {
    ok: false,
    code: "PREVIEW_RATE_LIMIT_UNAVAILABLE",
    message: "Pricing preview is temporarily unavailable.",
  }, origin);
}

async function applyLimit(
  client: PreviewRpcClient,
  namespace: "preview_global" | "preview_capability",
  keyHash: string,
  origin: string | null,
): Promise<Response | null> {
  try {
    const decision = await consumePreviewRateLimit(client, namespace, keyHash);
    if (decision.allowed) return null;
    return response(429, {
      ok: false,
      code: "PREVIEW_RATE_LIMITED",
      message: "Too many pricing preview requests.",
    }, origin, { "Retry-After": String(decision.retryAfterSeconds) });
  } catch {
    return limiterUnavailable(origin);
  }
}

function validTopLevelRequest(body: Record<string, unknown>): boolean {
  const keys = Object.keys(body);
  return keys.length === 4 &&
    keys.every((key) => ["action", "token", "scopeRevision", "data"].includes(key)) &&
    body.action === "preview_budget_guard" &&
    Number.isSafeInteger(body.scopeRevision) && Number(body.scopeRevision) >= 0;
}

export async function handlePricingPreview(
  body: Record<string, unknown>,
  origin: string | null,
  client: PreviewRpcClient,
  dependencies: PreviewDependencies = defaultDependencies,
): Promise<Response> {
  let globalKey: string;
  try {
    globalKey = await dependencies.globalLimitKey();
  } catch {
    return limiterUnavailable(origin);
  }
  const globalLimitResponse = await applyLimit(client, "preview_global", globalKey, origin);
  if (globalLimitResponse) return globalLimitResponse;

  if (!validTopLevelRequest(body)) {
    return response(400, {
      ok: false,
      code: "INVALID_PREVIEW_REQUEST",
      message: "Pricing preview request is invalid.",
    }, origin);
  }

  let intakeTokenHash: string;
  try {
    const rawToken = dependencies.validateCapability(body.token);
    intakeTokenHash = await dependencies.hashCapability(rawToken);
  } catch {
    return response(401, {
      ok: false,
      code: "INVALID_INTAKE_TOKEN",
      message: "The intake link is invalid or expired.",
    }, origin);
  }

  const { data: contextData, error: contextError } = await client.rpc(
    "inspect_preview_budget_guard_context_v1",
    { p_access_token_hash: intakeTokenHash },
  );
  if (contextError) {
    return response(500, {
      ok: false,
      code: "PRICING_PREVIEW_UNAVAILABLE",
      message: "Pricing preview is unavailable.",
    }, origin);
  }
  const context = Array.isArray(contextData) && contextData.length === 1 &&
      contextData[0] && typeof contextData[0] === "object" && !Array.isArray(contextData[0])
    ? contextData[0] as Record<string, unknown>
    : null;
  if (!context) {
    return response(401, {
      ok: false,
      code: "INVALID_INTAKE_TOKEN",
      message: "The intake link is invalid or expired.",
    }, origin);
  }
  if (context.intake_status !== "invited" && context.intake_status !== "in_progress") {
    return response(409, {
      ok: false,
      code: "PREVIEW_NOT_AVAILABLE",
      message: "Pricing preview is not available for this intake.",
    }, origin);
  }

  let capabilityKey: string;
  try {
    capabilityKey = await dependencies.capabilityLimitKey(intakeTokenHash);
  } catch {
    return limiterUnavailable(origin);
  }
  const capabilityLimitResponse = await applyLimit(
    client,
    "preview_capability",
    capabilityKey,
    origin,
  );
  if (capabilityLimitResponse) return capabilityLimitResponse;

  let input: Record<string, unknown>;
  try {
    input = sanitizeAndValidatePricingPreviewInput(body.data);
  } catch (error) {
    if (error instanceof InputValidationError) {
      return response(400, {
        ok: false,
        code: "INVALID_PREVIEW_REQUEST",
        message: "Pricing preview request is invalid.",
      }, origin);
    }
    return response(500, {
      ok: false,
      code: "PRICING_PREVIEW_UNAVAILABLE",
      message: "Pricing preview is unavailable.",
    }, origin);
  }

  try {
    const hasPreviewBudget = "budget_update_category" in input;
    const budgetEvidence = resolveBudgetEvidence(
      hasPreviewBudget ? input.budget_update_category : context.budget_label,
      hasPreviewBudget ? input.budget_update_category_scheme : context.budget_category_scheme,
      hasPreviewBudget ? input.budget_update_category_code : context.budget_category_code,
    );
    const pricing = dependencies.calculate(input);
    const preview = buildCustomerPricingPreview(
      Number(body.scopeRevision),
      pricing,
      evaluateBudget(pricing.calculation, budgetEvidence),
    );
    return response(200, { ok: true, preview }, origin);
  } catch {
    return response(500, {
      ok: false,
      code: "PRICING_PREVIEW_UNAVAILABLE",
      message: "Pricing preview is unavailable.",
    }, origin);
  }
}

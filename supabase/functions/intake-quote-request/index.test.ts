import { assertEquals } from "jsr:@std/assert@1";
import { handleIntakeQuoteRequest } from "./index.ts";

const token = "A".repeat(43);

async function withLifecycleResponse(
  effectiveAccess: string | null,
  action: "inspect" | "preview_budget_guard" | "inspect_customer_pricing" =
    "inspect",
): Promise<Response> {
  const originalFetch = globalThis.fetch;
  const previousEnvironment = new Map<string, string | undefined>();
  for (
    const [name, value] of [
      ["SUPABASE_URL", "https://supabase.test"],
      ["SUPABASE_SERVICE_ROLE_KEY", "service-role-test-key"],
      [
        "APPROVAL_TOKEN_SECRET",
        "approval-token-secret-with-sufficient-test-entropy",
      ],
    ]
  ) {
    previousEnvironment.set(name, Deno.env.get(name));
    Deno.env.set(name, value);
  }

  globalThis.fetch = (async (input) => {
    const url = input instanceof Request ? input.url : String(input);
    if (
      !url.includes(
        "/rest/v1/rpc/inspect_quote_request_intake_customer_access_v1",
      )
    ) {
      throw new Error(`Unexpected fetch after lifecycle denial: ${url}`);
    }
    return Response.json(
      effectiveAccess === null ? [] : [{ effective_access: effectiveAccess }],
      { status: 200 },
    );
  }) as typeof fetch;

  try {
    return await handleIntakeQuoteRequest(
      new Request("https://functions.test/intake-quote-request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action,
          token,
          ...(action === "preview_budget_guard"
            ? { scopeRevision: 0, clientPreviewVersion: 3, data: {} }
            : {}),
        }),
      }),
    );
  } finally {
    globalThis.fetch = originalFetch;
    for (const [name, value] of previousEnvironment) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

Deno.test("customer lifecycle states map to machine-readable Edge errors", async () => {
  for (
    const [state, status, code] of [
      ["INTERRUPTED", 403, "INTAKE_ACCESS_INTERRUPTED"],
      ["EXPIRED", 410, "INTAKE_ACCESS_EXPIRED"],
      ["CANCELLED", 410, "INTAKE_ACCESS_CANCELLED"],
    ] as const
  ) {
    const response = await withLifecycleResponse(state);
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, code);
  }
});

Deno.test("preview and customer pricing use the same lifecycle preflight", async () => {
  for (
    const action of [
      "preview_budget_guard",
      "inspect_customer_pricing",
    ] as const
  ) {
    const response = await withLifecycleResponse("INTERRUPTED", action);
    assertEquals(response.status, 403);
    assertEquals((await response.json()).code, "INTAKE_ACCESS_INTERRUPTED");
  }
});

Deno.test("unknown or revoked customer capability remains invalid token", async () => {
  const response = await withLifecycleResponse(null);
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "INVALID_INTAKE_TOKEN");
});

async function withDatabaseErrorAfterActivePreflight(
  action:
    | "inspect"
    | "reset_draft"
    | "save_draft"
    | "preview_budget_guard"
    | "inspect_customer_pricing",
  databaseCode: string,
  databaseMessage: string,
): Promise<Response> {
  const originalFetch = globalThis.fetch;
  const previousEnvironment = new Map<string, string | undefined>();
  for (
    const [name, value] of [
      ["SUPABASE_URL", "https://supabase.test"],
      ["SUPABASE_SERVICE_ROLE_KEY", "service-role-test-key"],
      [
        "APPROVAL_TOKEN_SECRET",
        "approval-token-secret-with-sufficient-test-entropy",
      ],
      [
        "PREVIEW_RATE_LIMIT_SECRET",
        "preview-rate-limit-secret-with-sufficient-test-entropy",
      ],
    ]
  ) {
    previousEnvironment.set(name, Deno.env.get(name));
    Deno.env.set(name, value);
  }

  globalThis.fetch = (async (input) => {
    const url = input instanceof Request ? input.url : String(input);
    if (
      url.includes(
        "/rpc/inspect_quote_request_intake_customer_access_v1",
      )
    ) {
      return Response.json([{ effective_access: "ACTIVE" }]);
    }
    if (url.includes("/rpc/consume_preview_rate_limit_v1")) {
      return Response.json([{
        allowed: true,
        remaining: 1,
        reset_at: new Date(Date.now() + 60_000).toISOString(),
        retry_after_seconds: 0,
      }]);
    }
    return Response.json({
      code: databaseCode,
      details: null,
      hint: null,
      message: databaseMessage,
    }, { status: 400 });
  }) as typeof fetch;

  try {
    return await handleIntakeQuoteRequest(
      new Request("https://functions.test/intake-quote-request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action,
          token,
          ...(action === "reset_draft" ? { expected_revision: 0 } : {}),
          ...(action === "save_draft" ? { data: {} } : {}),
          ...(action === "preview_budget_guard"
            ? { scopeRevision: 0, clientPreviewVersion: 3, data: {} }
            : {}),
        }),
      }),
    );
  } finally {
    globalThis.fetch = originalFetch;
    for (const [name, value] of previousEnvironment) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

Deno.test("protected database calls preserve lifecycle denial codes", async () => {
  for (
    const [state, status] of [
      ["INTERRUPTED", 403],
      ["EXPIRED", 410],
      ["CANCELLED", 410],
    ] as const
  ) {
    for (
      const action of [
        "inspect",
        "reset_draft",
        "save_draft",
        "preview_budget_guard",
        "inspect_customer_pricing",
      ] as const
    ) {
      const code = `INTAKE_ACCESS_${state}`;
      const response = await withDatabaseErrorAfterActivePreflight(
        action,
        "P0001",
        code,
      );
      assertEquals(response.status, status, `${action} ${state} status`);
      assertEquals(
        (await response.json()).code,
        code,
        `${action} ${state} code`,
      );
    }
  }
});

Deno.test("non-lifecycle database errors keep generic branch contracts", async () => {
  for (
    const [action, code] of [
      ["inspect", "INTAKE_INSPECT_FAILED"],
      ["reset_draft", "INTAKE_RESET_FAILED"],
      ["save_draft", "INTAKE_UPDATE_FAILED"],
      ["preview_budget_guard", "PRICING_PREVIEW_UNAVAILABLE"],
      ["inspect_customer_pricing", "CUSTOMER_PRICING_READ_FAILED"],
    ] as const
  ) {
    const response = await withDatabaseErrorAfterActivePreflight(
      action,
      "XX000",
      "database failure",
    );
    assertEquals(response.status, 500);
    assertEquals((await response.json()).code, code);
  }
});

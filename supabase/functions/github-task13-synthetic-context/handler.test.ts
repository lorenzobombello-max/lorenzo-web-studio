import { assertEquals } from "jsr:@std/assert@1";
import {
  createUnsignedTask13SyntheticJwt,
  handleGitHubTask13SyntheticContext,
} from "./handler.ts";

const SUBJECT = "e2100000-0000-4000-8000-000000000001";
const CONTEXT_A = "e2120000-0000-4000-8000-000000000001";
const CONTEXT_B = "e2120000-0000-4000-8000-000000000002";
const WORKSPACE_A = "e2130000-0000-4000-8000-000000000001";
const WORKSPACE_B = "e2130000-0000-4000-8000-000000000002";
const NOW = Date.parse("2026-09-13T12:00:00.000Z");

function request(
  claims?: Record<string, unknown>,
  body: unknown = {
    action: "create_task13_synthetic_context",
    environment: "TEST",
  },
) {
  return new Request("https://example.test/github-task13-synthetic-context", {
    method: "POST",
    headers: {
      ...(claims
        ? {
          authorization: `Bearer ${createUnsignedTask13SyntheticJwt(claims)}`,
        }
        : {}),
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function dependencies(overrides: Record<string, unknown> = {}) {
  const calls: string[] = [];
  let sequence = 0;
  return {
    calls,
    value: {
      now: () => NOW,
      verifyUser: () => {
        calls.push("VERIFY_USER");
        return Promise.resolve({ id: SUBJECT });
      },
      authorizeOwner: () => {
        calls.push("AUTHORIZE_OWNER");
        return Promise.resolve();
      },
      create: () => {
        calls.push("CREATE");
        sequence++;
        return Promise.resolve({
          website_work_context_id: sequence === 1 ? CONTEXT_A : CONTEXT_B,
          workspace_id: sequence === 1 ? WORKSPACE_A : WORKSPACE_B,
          record_classification: "internal_e2e" as const,
          environment: "TEST" as const,
        });
      },
      ...overrides,
    },
  };
}

const ownerClaims = {
  sub: SUBJECT,
  exp: NOW / 1000 + 60,
  aal: "aal2",
};

Deno.test("synthetic context denies unauthenticated callers", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13SyntheticContext(
    request(),
    test.value,
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "CALLER_VERIFICATION");
  assertEquals(test.calls, []);
});

Deno.test("synthetic context denies AAL1", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13SyntheticContext(
    request({ ...ownerClaims, aal: "aal1" }),
    test.value,
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "AAL2_VERIFICATION");
  assertEquals(test.calls.includes("CREATE"), false);
});

Deno.test("synthetic context denies non-OWNER", async () => {
  const test = dependencies({
    authorizeOwner: () => Promise.reject(new Error("not owner")),
  });
  const response = await handleGitHubTask13SyntheticContext(
    request(ownerClaims),
    test.value,
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "OWNER_AUTHORIZATION");
  assertEquals(test.calls.includes("CREATE"), false);
});

Deno.test("synthetic context denies client classification", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13SyntheticContext(
    request(ownerClaims, {
      action: "create_task13_synthetic_context",
      environment: "TEST",
      record_classification: "production",
    }),
    test.value,
  );
  assertEquals(response.status, 400);
  assertEquals(test.calls, []);
});

Deno.test("synthetic context is TEST-only", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13SyntheticContext(
    request(ownerClaims, {
      action: "create_task13_synthetic_context",
      environment: "PRODUCTION",
    }),
    test.value,
  );
  assertEquals(response.status, 400);
  assertEquals(test.calls, []);
});

Deno.test("synthetic context denies client context identity", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13SyntheticContext(
    request(ownerClaims, {
      action: "create_task13_synthetic_context",
      environment: "TEST",
      website_work_context_id: CONTEXT_A,
    }),
    test.value,
  );
  assertEquals(response.status, 400);
  assertEquals(test.calls, []);
});

Deno.test("synthetic context denies customer and dossier identity", async () => {
  for (
    const override of [
      { customer_id: crypto.randomUUID() },
      { quote_request_id: crypto.randomUUID() },
      { dossier_id: crypto.randomUUID() },
    ]
  ) {
    const test = dependencies();
    const response = await handleGitHubTask13SyntheticContext(
      request(ownerClaims, {
        action: "create_task13_synthetic_context",
        environment: "TEST",
        ...override,
      }),
      test.value,
    );
    assertEquals(response.status, 400);
    assertEquals(test.calls, []);
  }
});

Deno.test("synthetic context denies GitHub target authority", async () => {
  for (
    const override of [
      { organization: "lorenzo-web-solutions-lab" },
      { repository: "attacker" },
      { installation_id: "161461160" },
    ]
  ) {
    const test = dependencies();
    const response = await handleGitHubTask13SyntheticContext(
      request(ownerClaims, {
        action: "create_task13_synthetic_context",
        environment: "TEST",
        ...override,
      }),
      test.value,
    );
    assertEquals(response.status, 400);
    assertEquals(test.calls, []);
  }
});

Deno.test("valid OWNER AAL2 request creates exactly one synthetic context", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13SyntheticContext(
    request(ownerClaims),
    test.value,
  );
  assertEquals(response.status, 201);
  assertEquals(await response.json(), {
    ok: true,
    code: "TASK13_SYNTHETIC_CONTEXT_CREATED",
    result: {
      website_work_context_id: CONTEXT_A,
      workspace_id: WORKSPACE_A,
      record_classification: "internal_e2e",
      environment: "TEST",
    },
  });
  assertEquals(test.calls, ["VERIFY_USER", "AUTHORIZE_OWNER", "CREATE"]);
});

Deno.test("two valid requests create two distinct context islands", async () => {
  const test = dependencies();
  const first = await handleGitHubTask13SyntheticContext(
    request(ownerClaims),
    test.value,
  );
  const second = await handleGitHubTask13SyntheticContext(
    request(ownerClaims),
    test.value,
  );
  const firstResult = (await first.json()).result;
  const secondResult = (await second.json()).result;
  assertEquals(firstResult.website_work_context_id, CONTEXT_A);
  assertEquals(secondResult.website_work_context_id, CONTEXT_B);
  assertEquals(firstResult.workspace_id, WORKSPACE_A);
  assertEquals(secondResult.workspace_id, WORKSPACE_B);
  assertEquals(test.calls.filter((call) => call === "CREATE").length, 2);
});

Deno.test("synthetic response contains no customer binding", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13SyntheticContext(
    request(ownerClaims),
    test.value,
  );
  const result = (await response.json()).result;
  assertEquals(Object.keys(result).sort(), [
    "environment",
    "record_classification",
    "website_work_context_id",
    "workspace_id",
  ]);
});

Deno.test("synthetic response rejects a cross-island or enriched result", async () => {
  const test = dependencies({
    create: () =>
      Promise.resolve({
        website_work_context_id: CONTEXT_A,
        workspace_id: WORKSPACE_A,
        record_classification: "internal_e2e",
        environment: "TEST",
        customer_id: crypto.randomUUID(),
      }),
  });
  const response = await handleGitHubTask13SyntheticContext(
    request(ownerClaims),
    test.value,
  );
  assertEquals(response.status, 502);
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_SYNTHETIC_CONTEXT_FAILED",
  });
});

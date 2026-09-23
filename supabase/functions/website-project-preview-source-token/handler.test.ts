import { assertEquals } from "jsr:@std/assert@1";
import { handleWebsiteProjectPreviewSourceToken } from "./handler.ts";
import { createWebsiteProjectPreviewSourceTokenService } from "./service.ts";

const AUTHORITY = Object.freeze({
  audience: "lws-preview",
  workflowRepository: "lorenzo-web-solutions/platform",
  workflowRepositoryId: "123456",
  workflowRef: "lorenzo-web-solutions/platform/.github/workflows/build-website-project-preview.yml@refs/heads/main",
  workflowRefName: "refs/heads/main",
  customerRepository: "lorenzo-web-solutions/lws-web-a88b1e8792714ad199ccb385b7982a8b",
  customerRepositoryId: "1378797607",
  customerCommitSha: "1f19bf01c61c6da79fa4c7374333a91b70f9bf48",
  runId: "42",
  leaseId: "11111111-1111-4111-8111-111111111111",
  buildId: "22222222-2222-4222-8222-222222222222",
});

function request(body: Record<string, unknown>, authorization = "Bearer oidc.jwt"): Request {
  return new Request("http://local/", {
    method: "POST",
    headers: { authorization, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("source-token endpoint forwards only workflow OIDC and server authority keys", async () => {
  let received: unknown;
  const response = await handleWebsiteProjectPreviewSourceToken(
    request({ leaseId: "lease", buildId: "build", workflowRunId: "42" }),
    {
      issue: async (input) => {
        received = input;
        return { token: "ghs_scoped", expiresAt: "2026-09-23T12:00:00.000Z" };
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(received, {
    oidcToken: "oidc.jwt",
    leaseId: "lease",
    buildId: "build",
    workflowRunId: "42",
  });
  assertEquals(await response.json(), {
    ok: true,
    token: "ghs_scoped",
    expires_at: "2026-09-23T12:00:00.000Z",
  });
});

Deno.test("source-token endpoint rejects caller-selected repository or permissions", async () => {
  let called = false;
  const response = await handleWebsiteProjectPreviewSourceToken(
    request({
      leaseId: "lease",
      buildId: "build",
      workflowRunId: "42",
      repositoryId: "999",
      permissions: { contents: "write" },
    }),
    { issue: async () => { called = true; return { token: "unused", expiresAt: "unused" }; } },
  );

  assertEquals(response.status, 400);
  assertEquals(called, false);
  assertEquals(await response.json(), { ok: false, code: "SOURCE_TOKEN_BODY_INVALID" });
});

Deno.test("source-token endpoint requires a bearer token and POST", async () => {
  const service = { issue: async () => ({ token: "unused", expiresAt: "unused" }) };
  const missingBearer = await handleWebsiteProjectPreviewSourceToken(
    request({ leaseId: "lease", buildId: "build", workflowRunId: "42" }, ""),
    service,
  );
  const wrongMethod = await handleWebsiteProjectPreviewSourceToken(
    new Request("http://local/", { method: "GET" }),
    service,
  );

  assertEquals(missingBearer.status, 401);
  assertEquals(await missingBearer.json(), { ok: false, code: "SOURCE_TOKEN_OIDC_REQUIRED" });
  assertEquals(wrongMethod.status, 405);
});

Deno.test("source-token endpoint returns only safe broker errors", async () => {
  const response = await handleWebsiteProjectPreviewSourceToken(
    request({ leaseId: "lease", buildId: "build", workflowRunId: "42" }),
    { issue: async () => { throw new Error("private-key=secret provider detail"); } },
  );

  assertEquals(response.status, 503);
  assertEquals(await response.json(), { ok: false, code: "SOURCE_TOKEN_EXCHANGE_FAILED" });
});

Deno.test("source-token service resolves and verifies authority before one exact read-only exchange", async () => {
  const calls: string[] = [];
  let exchangeInput: unknown;
  const service = createWebsiteProjectPreviewSourceTokenService({
    resolveAuthority: async (input) => {
      calls.push(`resolve:${input.leaseId}:${input.buildId}:${input.workflowRunId}`);
      return AUTHORITY;
    },
    verifyOidc: async (token, authority) => {
      calls.push(`verify:${token}`);
      assertEquals(authority, AUTHORITY);
      return authority;
    },
    issueInstallationToken: async (input) => {
      calls.push("exchange");
      exchangeInput = input;
      return { token: "ghs_scoped", expiresAt: "2026-09-23T12:00:00.000Z" };
    },
  });

  const result = await service.issue({
    oidcToken: "oidc.jwt",
    leaseId: AUTHORITY.leaseId,
    buildId: AUTHORITY.buildId,
    workflowRunId: AUTHORITY.runId,
  });

  assertEquals(calls, [
    `resolve:${AUTHORITY.leaseId}:${AUTHORITY.buildId}:${AUTHORITY.runId}`,
    "verify:oidc.jwt",
    "exchange",
  ]);
  assertEquals(exchangeInput, {
    leaseId: AUTHORITY.leaseId,
    repository: AUTHORITY.customerRepository,
    repositoryIds: [AUTHORITY.customerRepositoryId],
    permissions: { contents: "read" },
  });
  assertEquals(result, { token: "ghs_scoped", expiresAt: "2026-09-23T12:00:00.000Z" });
});

Deno.test("source-token service never exchanges after authority or OIDC failure", async () => {
  let exchanges = 0;
  const failingResolve = createWebsiteProjectPreviewSourceTokenService({
    resolveAuthority: async () => { throw new Error("PROJECT_PREVIEW_LEASE_INVALID"); },
    verifyOidc: async (_token, authority) => authority,
    issueInstallationToken: async () => { exchanges += 1; return { token: "unused", expiresAt: "unused" }; },
  });
  const failingOidc = createWebsiteProjectPreviewSourceTokenService({
    resolveAuthority: async () => AUTHORITY,
    verifyOidc: async () => { throw new Error("OIDC_REPOSITORY_MISMATCH"); },
    issueInstallationToken: async () => { exchanges += 1; return { token: "unused", expiresAt: "unused" }; },
  });
  const input = {
    oidcToken: "oidc.jwt",
    leaseId: AUTHORITY.leaseId,
    buildId: AUTHORITY.buildId,
    workflowRunId: AUTHORITY.runId,
  };

  for (const service of [failingResolve, failingOidc]) {
    try {
      await service.issue(input);
      throw new Error("EXPECTED_FAILURE");
    } catch (error) {
      if (error instanceof Error && error.message === "EXPECTED_FAILURE") throw error;
    }
  }
  assertEquals(exchanges, 0);
});

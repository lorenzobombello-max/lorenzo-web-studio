import assert from "node:assert/strict";
import { createWebsiteProjectPreviewSourceTokenService } from "./service.ts";

Deno.test("source token is never issued when durable run claim is denied", async () => {
  let issued = false;
  const authority = {
    audience: "test", workflowRepository: "owner/platform", workflowRepositoryId: "123",
    workflowRef: "owner/platform/.github/workflows/test.yml@refs/heads/main",
    workflowRefName: "refs/heads/main", workflowSha: "a".repeat(40),
    customerRepository: "customer/site", customerRepositoryId: "456", customerCommitSha: "b".repeat(40),
    runId: "123", leaseId: "11111111-1111-4111-8111-111111111111",
    buildId: "22222222-2222-4222-8222-222222222222",
  };
  const dependencies = {
    resolveAuthority: async () => authority,
    verifyOidc: async () => authority,
    claimRun: async () => { throw new Error("PROJECT_PREVIEW_RUN_ALREADY_CLAIMED"); },
    issueInstallationToken: async () => { issued = true; return { token: "test", expiresAt: "" }; },
  };
  const service = createWebsiteProjectPreviewSourceTokenService(dependencies);
  await assert.rejects(() => service.issue({ oidcToken: "test", leaseId: authority.leaseId,
    buildId: authority.buildId, workflowRunId: "123" }), /ALREADY_CLAIMED/);
  assert.equal(issued, false);
});

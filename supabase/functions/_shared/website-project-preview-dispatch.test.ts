import assert from "node:assert/strict";
import { assertPreviewWorkflowConfiguration, createWebsiteProjectPreviewDispatch } from "./website-project-preview-dispatch.ts";

const lease = "11111111-1111-4111-8111-111111111111";
const build = "22222222-2222-4222-8222-222222222222";
const sha = "a".repeat(40);
const workflowSha = "b".repeat(40);
Deno.test("source and artifact OIDC configuration cannot select a fork or another workflow", () => {
  const repository = "lorenzobombello-max/lorenzo-web-studio";
  const ref = `${repository}/.github/workflows/build-website-project-preview.yml@refs/heads/main`;
  assertPreviewWorkflowConfiguration(repository, "1320223175", ref, "refs/heads/main");
  assert.throws(() => assertPreviewWorkflowConfiguration("fork/platform", "1320223175", ref, "refs/heads/main"));
  assert.throws(() => assertPreviewWorkflowConfiguration(repository, "123", ref, "refs/heads/main"));
  assert.throws(() => assertPreviewWorkflowConfiguration(repository, "1320223175", ref, "refs/heads/other"));
});
function fixture(status = 204, ambiguous = false) {
  let claimed = false;
  const calls: string[] = [];
  const requests: Request[] = [];
  const service = createWebsiteProjectPreviewDispatch({
    workflowSha,
    client: { rpc(name, args) {
      calls.push(name);
      if (name.startsWith("claim_")) {
        const dispatchAllowed = !claimed;
        claimed = true;
        return Promise.resolve({ error: null, data: { leaseId: lease, buildId: build,
          commitSha: sha, workflowSha, repositoryOwner: "acme", repositoryName: "website",
          repositoryId: "123", dispatchAllowed, state: "ATTEMPTED" } });
      }
      return Promise.resolve({ error: null, data: {
        state: args.p_outcome === "REJECTED" ? "FAILED" : args.p_outcome,
      } });
    } },
    acquireToken: async () => ({ token: "test-token", expiresAt: new Date(Date.now() + 60000).toISOString() }),
    fetch: async (request) => {
      requests.push(request);
      if (ambiguous) throw new TypeError("private transport detail");
      return new Response(null, { status });
    },
  });
  return { service, calls, requests };
}
Deno.test("one durable claim permits one dispatch across duplicate calls", async () => {
  const f = fixture();
  assert.equal((await f.service.dispatch(lease, build, sha)).status, "BUILD_QUEUED");
  await f.service.dispatch(lease, build, sha);
  assert.equal(f.requests.length, 1);
  assert.equal(f.requests[0].redirect, "error");
  const body = await f.requests[0].json();
  assert.equal(body.inputs.commit_sha, sha);
  assert.equal(body.inputs.build_id, build);
  assert.equal(body.inputs.repository_id, "123");
});
Deno.test("ambiguous response records UNKNOWN with no retry or leaked detail", async () => {
  const f = fixture(204, true);
  const result = await f.service.dispatch(lease, build, sha);
  assert.equal(result.status, "DISPATCH_UNKNOWN");
  assert.equal(f.requests.length, 1);
  assert.equal(JSON.stringify(result).includes("private"), false);
  assert.equal(f.calls.at(-1), "record_website_project_preview_dispatch_v1");
});
for (const status of [200, 201, 408, 429, 500, 503]) {
  Deno.test(`HTTP ${status} is UNKNOWN, not permission to retry`, async () => {
    const f = fixture(status);
    assert.equal((await f.service.dispatch(lease, build, sha)).status, "DISPATCH_UNKNOWN");
    assert.equal(f.requests.length, 1);
  });
}
Deno.test("concurrent callers sharing the claim cannot produce two POSTs", async () => {
  const f = fixture();
  await Promise.all([f.service.dispatch(lease, build, sha), f.service.dispatch(lease, build, sha)]);
  assert.equal(f.requests.length, 1);
});
Deno.test("definite rejection is finalized as FAILED", async () => {
  const f = fixture(403);
  assert.equal((await f.service.dispatch(lease, build, sha)).status, "FAILED");
});
Deno.test("mismatched pinned commit never reaches GitHub", async () => {
  const f = fixture();
  await assert.rejects(() => f.service.dispatch(lease, build, "c".repeat(40)), /AUTHORITY_INVALID/);
  assert.equal(f.requests.length, 0);
});

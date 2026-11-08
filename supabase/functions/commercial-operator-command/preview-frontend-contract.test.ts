import assert from "node:assert/strict";
import { executeCallerJwtWebsiteProjectPreviewControlAction } from "./index.ts";
import { createWebsiteProjectPreviewDispatch, previewRecord } from "../_shared/website-project-preview-dispatch.ts";

const assets = new URL("../../../assets/js/", import.meta.url);
const registry = await Deno.readTextFile(new URL("operator-module-registry.mjs", assets));
const childImport = registry.match(/import\("(\.\/operator-website-execution-child\.mjs\?v=[^"]+)"\)/)?.[1];
assert.ok(childImport);
const childUrl = new URL(childImport, assets);
const child = await Deno.readTextFile(new URL(childUrl.pathname, childUrl));
const statusImport = child.match(/from "(\.\/operator-website-preview-build\.mjs\?v=[^"]+)"/)?.[1];
assert.ok(statusImport);
const statusUrl = new URL(statusImport, assets);
const { createPreviewBuildController } = await import(statusUrl.href);

Deno.test("release invalidates both previously cached child and status module URLs", () => {
  assert.equal(childUrl.searchParams.get("v"), "20261108-preview-status-r1");
  assert.equal(statusUrl.searchParams.get("v"), "20261108-preview-status-r1");
});

for (const httpStatus of [204, 503]) {
  Deno.test(`backend HTTP ${httpStatus} is shown accurately by the release-selected frontend without redispatch`, async () => {
    const leaseId = "11111111-1111-4111-8111-111111111111";
    const buildId = "22222222-2222-4222-8222-222222222222";
    const commit = "a".repeat(40);
    const workflowSha = "b".repeat(40);
    const states: Record<string, unknown>[] = [];
    let posts = 0;
    let acquisitions = 0;
    let polls = 0;
    const expectedStatus = httpStatus === 204 ? "BUILD_QUEUED" : "DISPATCH_UNKNOWN";
    const dispatcher = createWebsiteProjectPreviewDispatch({
      workflowSha,
      acquireToken: async () => ({ token: "synthetic-token", expiresAt: new Date(Date.now() + 60000).toISOString() }),
      client: { rpc: async (name, args) => ({
        error: null,
        data: name === "claim_website_project_preview_dispatch_v1"
          ? { leaseId, buildId, commitSha: commit, workflowSha, repositoryOwner: "fixture",
            repositoryName: "website", repositoryId: "123", dispatchAllowed: true, state: "ATTEMPTED" }
          : { state: args.p_outcome },
      }) },
      fetch: async () => { posts++; return new Response(null, { status: httpStatus }); },
    });
    const dependencies = {
      dispatch: dispatcher,
      clientFor: () => ({ rpc: async (name: string) => {
        if (name === "acquire_website_project_preview_build_v1") {
          acquisitions++;
          return { error: null, data: { leaseId, buildId } };
        }
        polls++;
        return { error: null, data: {
          buildStatus: polls === 1 ? expectedStatus : "PASS",
          previewBuildId: polls === 1 ? null : buildId,
        } };
      } }),
    };
    const controller = createPreviewBuildController({
      startBuild: async () => {
        const result = previewRecord(await executeCallerJwtWebsiteProjectPreviewControlAction("synthetic-jwt", {
          action: "request_website_project_preview_build", quote_request_id: leaseId,
          expected_commit_sha: commit, idempotency_key: buildId,
        }, dependencies));
        return { leaseId: result.lease_id, status: result.status, reason: result.reason };
      },
      getBuildStatus: async () => previewRecord(await executeCallerJwtWebsiteProjectPreviewControlAction("synthetic-jwt", {
        action: "get_website_project_preview_build_status", lease_id: leaseId,
      }, dependencies)),
      onStateChange: (state: Record<string, unknown>) => states.push(state),
      wait: async () => {},
    });
    const result = await controller.start({});
    const expectedLabel = httpStatus === 204 ? "Preview staat in de wachtrij\u2026"
      : "Ontvangst van previewaanvraag onzeker \u2013 geen nieuwe aanvraag starten";
    assert.equal(states[1].status, expectedStatus);
    assert.equal(states[1].label, expectedLabel);
    assert.equal(states[1].tone, httpStatus === 204 ? "progress" : "warning");
    assert.equal(states[2].label, expectedLabel);
    assert.equal(states.some(state => state.label === "Status onbekend"), false);
    assert.equal(result.status, "PASS");
    assert.equal(posts, 1);
    assert.equal(acquisitions, 1);
    assert.equal(polls, 2);
  });
}

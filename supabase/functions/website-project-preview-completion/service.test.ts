import assert from "node:assert/strict";
import { createPreviewCompletionService } from "./service.ts";

const leaseId = "11111111-1111-4111-8111-111111111111";
const buildId = "22222222-2222-4222-8222-222222222222";
const workflowSha = "a".repeat(40);
const input = { leaseId, buildId, workflowRunId: "123", monitorRunId: "456", oidcToken: "test" };
function harness(overrides: Record<string, unknown> = {}, terminal = "FAILED", failedJob = "build") {
  const calls: string[] = [];
  const service = createPreviewCompletionService({
    resolve: async () => ({ leaseId, buildId, workflowSha, runId: "123" }),
    verifyMonitor: async () => { calls.push("oidc"); },
    getRun: async () => ({ id: 123, run_attempt: 1, event: "workflow_dispatch", status: "completed",
      conclusion: "failure", head_sha: workflowSha, head_branch: "main",
      repository: { id: 1320223175, full_name: "lorenzobombello-max/lorenzo-web-studio" },
      head_repository: { id: 1320223175, full_name: "lorenzobombello-max/lorenzo-web-studio" },
      path: ".github/workflows/build-website-project-preview.yml",
      display_title: `LWS preview lease=${leaseId} build=${buildId}`, ...overrides }),
    getJobs: async () => ({ total_count: 3, jobs: ["fetch", "build", "upload"].map((name, index, stages) => ({
      run_id: 123, run_attempt: 1, name,
      conclusion: name === failedJob ? "failure" : index < stages.indexOf(failedJob) ? "success" : "skipped",
    })) }),
    finish: async (_input, reason) => { calls.push(reason); return { state: terminal }; },
    cleanup: async () => { calls.push("cleanup"); },
  });
  return { service, calls };
}
for (const [conclusion, reason] of [["failure", "BUILD_FAILED"], ["cancelled", "CANCELLED"],
  ["timed_out", "TIMED_OUT"], ["success", "FINALIZATION_MISSING"]]) {
  Deno.test(`verified completion ${conclusion} finalizes ${reason}`, async () => {
    const { service, calls } = harness({ conclusion });
    assert.equal((await service.complete(input)).state, "FAILED");
    assert.deepEqual(calls, ["oidc", reason, "cleanup"]);
  });
}
for (const stage of ["fetch", "upload"]) {
  Deno.test(`verified ${stage} failure has its own terminal category`, async () => {
    const { service, calls } = harness({}, "FAILED", stage);
    await service.complete(input);
    assert.deepEqual(calls, ["oidc", `${stage.toUpperCase()}_FAILED`, "cleanup"]);
  });
}
Deno.test("forged, rerun and unreviewed runs never finalize", async () => {
  for (const override of [{ run_attempt: 2 }, { head_sha: "b".repeat(40) }, { event: "push" },
    { display_title: "other lease" }, { id: 999 }, { path: "other.yml" },
    { repository: { id: 123 } }, { status: "in_progress" }]) {
    const { service, calls } = harness(override);
    await assert.rejects(() => service.complete(input));
    assert.deepEqual(calls, ["oidc"]);
  }
});
Deno.test("a committed success wins over late failure callbacks without storage removal", async () => {
  const { service, calls } = harness({}, "PASS");
  assert.equal((await service.complete(input)).state, "PASS");
  assert.deepEqual(calls, ["oidc", "BUILD_FAILED"]);
});

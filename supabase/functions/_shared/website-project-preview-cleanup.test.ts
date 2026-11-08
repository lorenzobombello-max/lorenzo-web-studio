import assert from "node:assert/strict";
import { cleanupFailedPreviewArtifacts, sweepPreviewDeadlines } from "./website-project-preview-cleanup.ts";
const buildId = "22222222-2222-4222-8222-222222222222";
Deno.test("cleanup uses only failed-build paths from authority, never caller-selected paths", async () => {
  const removed: string[][] = [];
  const storage = { remove: async (paths: string[]) => { removed.push(paths); return { error: null }; } };
  await cleanupFailedPreviewArtifacts({
    rpc: async () => ({ data: [`${buildId}/index.html`], error: null }),
  }, storage, buildId);
  assert.deepEqual(removed, [[`${buildId}/index.html`]]);
  for (const path of ["other/index.html", `${buildId}/../index.html`]) {
    await assert.rejects(() => cleanupFailedPreviewArtifacts({
      rpc: async () => ({ data: [path], error: null }),
    }, storage, buildId));
  }
  assert.equal(removed.length, 1);
});
Deno.test("deadline sweep expires once and reports storage removal errors", async () => {
  const calls: string[] = [];
  await assert.rejects(() => sweepPreviewDeadlines({
    rpc: async (name: string) => {
      calls.push(name);
      return { data: name === "expire_website_project_preview_dispatches_v1" ? 1
        : name === "get_website_project_preview_cleanup_candidates_v1" ? [buildId]
        : [`${buildId}/index.html`], error: null };
    },
  }, { remove: async () => ({ error: { message: "private" } }) }), /PROJECT_PREVIEW_CLEANUP_FAILED/);
  assert.equal(calls.filter((name) => name.startsWith("expire_")).length, 1);
  assert.equal(calls.some((name) => name.startsWith("record_")), false);
});

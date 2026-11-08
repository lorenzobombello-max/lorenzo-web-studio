import assert from "node:assert/strict";
import { handlePreviewCompletion } from "./handler.ts";

Deno.test("completion accepts only bounded identity fields and never echoes provider errors", async () => {
  const input = { leaseId: "lease", buildId: "build", workflowRunId: "123", monitorRunId: "456" };
  const request = (body: unknown) => new Request("http://local", {
    method: "POST", headers: { authorization: "Bearer test", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  let called = 0;
  const service = { complete: async () => { called++; throw new Error("private provider detail"); } };
  const rejected = await handlePreviewCompletion(request({ ...input, reason: "BUILD_FAILED" }), service);
  assert.equal(rejected.status, 400);
  assert.equal(called, 0);
  const failed = await handlePreviewCompletion(request(input), service);
  assert.equal(failed.status, 503);
  assert.equal((await failed.text()).includes("private provider detail"), false);
  const oversized = await handlePreviewCompletion(request({ ...input, leaseId: "x".repeat(4097) }), service);
  assert.equal(oversized.status, 400);
});

import assert from "node:assert/strict";
import { executeCallerJwtWebsiteProjectPreviewControlAction } from "./index.ts";
const leaseId = "11111111-1111-4111-8111-111111111111";
const buildId = "22222222-2222-4222-8222-222222222222";
const input = { action: "request_website_project_preview_build" as const,
  quote_request_id: leaseId, expected_commit_sha: "a".repeat(40), idempotency_key: "test-key" };

Deno.test("preview control acquires once then dispatches only server-authorized identifiers", async () => {
  const calls: string[] = [];
  const result = await executeCallerJwtWebsiteProjectPreviewControlAction("actor-jwt", input, {
    clientFor: (jwt) => {
      assert.equal(jwt, "actor-jwt");
      return { rpc: async (name) => {
        calls.push(name); return { data: { leaseId, buildId }, error: null };
      } };
    },
    dispatch: { dispatch: async (...args) => {
      assert.deepEqual(args, [leaseId, buildId, input.expected_commit_sha]);
      calls.push("dispatch"); return { lease_id: leaseId, status: "DISPATCH_UNKNOWN" };
    } },
  });
  assert.deepEqual(calls, ["acquire_website_project_preview_build_v1", "dispatch"]);
  assert.deepEqual(result, { lease_id: leaseId, status: "DISPATCH_UNKNOWN" });
});
Deno.test("missing dispatch configuration creates no lease", async () => {
  let acquired = false;
  await assert.rejects(() => executeCallerJwtWebsiteProjectPreviewControlAction("jwt", input, {
    clientFor: () => ({ rpc: async () => { acquired = true; return { data: {}, error: null }; } }),
  }), /WORKFLOW_NOT_CONFIGURED/);
  assert.equal(acquired, false);
});
Deno.test("006 preview reconciles first and pins verified commit in acquisition and dispatch", async () => {
  const calls: string[] = [];
  await executeCallerJwtWebsiteProjectPreviewControlAction("jwt", {
    ...input, quote_request_id: "7458c346-dfc9-40f3-ad0e-cb94a16636bf",
  }, {
    reconcileHead: async (quote, expected) => {
      assert.equal(quote, "7458c346-dfc9-40f3-ad0e-cb94a16636bf");
      assert.equal(expected, input.expected_commit_sha);
      calls.push("reconcile");
      return "b".repeat(40);
    },
    clientFor: () => ({ rpc: async (_name, args) => {
      assert.equal(args.p_expected_commit_sha, "b".repeat(40));
      calls.push("acquire"); return { data: { leaseId, buildId }, error: null };
    } }),
    dispatch: { dispatch: async (_lease, _build, commit) => {
      assert.equal(commit, "b".repeat(40)); calls.push("dispatch");
    } },
  });
  assert.deepEqual(calls, ["reconcile", "acquire", "dispatch"]);
});
Deno.test("006 reconciliation failure cannot acquire or dispatch", async () => {
  await assert.rejects(() => executeCallerJwtWebsiteProjectPreviewControlAction("jwt", {
    ...input, quote_request_id: "7458c346-dfc9-40f3-ad0e-cb94a16636bf",
  }, {
    reconcileHead: async () => { throw new Error("PROJECT_FILES_STALE_REVISION"); },
    clientFor: () => ({ rpc: () => { throw new Error("UNEXPECTED_ACQUIRE"); } }),
    dispatch: { dispatch: () => { throw new Error("UNEXPECTED_DISPATCH"); } },
  }), /PROJECT_FILES_STALE_REVISION/);
});

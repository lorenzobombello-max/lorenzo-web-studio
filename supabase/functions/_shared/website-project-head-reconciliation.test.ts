import { assertEquals, assertRejects } from "jsr:@std/assert";
import { reconcileWebsiteProjectHead } from "./website-project-head-reconciliation.ts";

Deno.test("reconciliation forwards only server verified head and real read lease", async () => {
  const calls: unknown[] = [];
  const result = await reconcileWebsiteProjectHead(
    "7458c346-dfc9-40f3-ad0e-cb94a16636bf",
    "a".repeat(40),
    {
      caller: {
        rpc: async (name, args) => {
          calls.push([name, args]);
          return { data: { leaseId: "read-lease" }, error: null };
        },
      },
      provider: {
        resolveSnapshot: async () => ({
          commitSha: "b".repeat(40),
          rootTreeSha: "c".repeat(40),
          repositoryDisplayName: "verified",
        }),
      },
      finalizer: {
        rpc: async (name, args) => {
          calls.push([name, args]);
          return { data: { commitSha: "b".repeat(40) }, error: null };
        },
      },
    },
  );
  assertEquals(result, "b".repeat(40));
  assertEquals(calls[1], ["reconcile_website_project_repository_head_v1", {
    p_lease_id: "read-lease",
    p_expected_commit_sha: "a".repeat(40),
    p_verified_commit_sha: "b".repeat(40),
  }]);
});

for (const failure of ["response", "release"]) {
  Deno.test(`reconciliation refuses a successful result after ${failure} failure`, async () => {
    await assertRejects(() => reconcileWebsiteProjectHead(
      "7458c346-dfc9-40f3-ad0e-cb94a16636bf", "a".repeat(40), {
        caller: { rpc: async (name) => ({
          data: { leaseId: "read-lease" },
          error: failure === "release" && name === "release_website_project_files_read_v1"
            ? { message: "release failed" } : null,
        }) },
        provider: { resolveSnapshot: async () => ({
          commitSha: "b".repeat(40), rootTreeSha: "c".repeat(40),
          repositoryDisplayName: "verified",
        }) },
        finalizer: { rpc: async () => ({
          data: failure === "response" ? null : { commitSha: "b".repeat(40) },
          error: null,
        }) },
      },
    ), Error, failure === "response"
      ? "PROJECT_HEAD_RESPONSE_INVALID" : "PROJECT_FILES_LEASE_RELEASE_FAILED");
  });
}

Deno.test("provider verification failure never finalizes and releases read authority", async () => {
  let released = false;
  await assertRejects(
    () =>
      reconcileWebsiteProjectHead(
        "7458c346-dfc9-40f3-ad0e-cb94a16636bf",
        "a".repeat(40),
        {
          caller: {
            rpc: async (name) => {
              released ||= name === "release_website_project_files_read_v1";
              return { data: { leaseId: "read-lease" }, error: null };
            },
          },
          provider: {
            resolveSnapshot: async () => {
              throw new Error("MARKER_MISMATCH");
            },
          },
          finalizer: {
            rpc: async () => {
              throw new Error("UNEXPECTED_FINALIZER");
            },
          },
        },
      ),
    Error,
    "MARKER_MISMATCH",
  );
  assertEquals(released, true);
});

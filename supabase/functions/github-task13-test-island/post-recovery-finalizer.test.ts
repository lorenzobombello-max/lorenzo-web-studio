import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { VerifiedRepositoryBindingV2 } from "../_shared/repository-provisioning.ts";
import { createTask13PostRecoveryFinalizer } from "./post-recovery-finalizer.ts";

const OPERATION_ID = "e646ae44-ec5d-46b6-96e3-b1023b9e1b68";
const CONTEXT_ID = "33a61b58-1d55-4624-bdb7-3c724d35ebcc";
const WORKSPACE_ID = "4dfe44a5-60d0-4728-b62b-ef87aa838976";
const REPOSITORY_ID = "1371224564";
const OWNER = "lorenzo-web-solutions-lab";
const REPOSITORY = "lws-web-33a61b581d554624bdb73c724d35ebcc";
const input = Object.freeze({
  operationId: OPERATION_ID,
  websiteWorkContextId: CONTEXT_ID,
  websiteWorkspaceId: WORKSPACE_ID,
});
const config = Object.freeze({
  actorAuthUserId: "d2100000-0000-4000-8000-000000000001",
  actorAal: "aal2" as const,
  starterSource: "lorenzo-web-solutions/lws-website-starter",
  starterVersion: "1.0.0",
  starterCommitSha: "a".repeat(40),
  starterTreeSha256: "c".repeat(64),
  markerContent: "exact marker",
});

function authority(state: "TERMINAL_FAILED" | "BOUND" = "TERMINAL_FAILED") {
  return {
    operation_found: true,
    operation_id: OPERATION_ID,
    website_work_context_id: CONTEXT_ID,
    website_workspace_id: WORKSPACE_ID,
    operation_state: state,
    failure_code: state === "TERMINAL_FAILED"
      ? "REPOSITORY_PROVIDER_FAILED"
      : null,
    external_created_at_present: true,
    repository_external_id: REPOSITORY_ID,
    target_owner: OWNER,
    target_repository_name: REPOSITORY,
    bound_at_present: state === "BOUND",
    quarantine_present: false,
    customer_binding_present: false,
    dossier_binding_present: false,
    repository_binding_present: state === "BOUND",
  };
}

function dependencies(state: "TERMINAL_FAILED" | "BOUND" = "TERMINAL_FAILED") {
  const calls: unknown[] = [];
  return {
    calls,
    value: {
      readAuthority: (value: unknown) => {
        calls.push(["READ_AUTHORITY", value]);
        return Promise.resolve(authority(state));
      },
      inspectCompletion: (value: unknown) => {
        calls.push(["INSPECT_COMPLETION", value]);
        return Promise.resolve({
          state: "ALREADY_COMPLETE" as const,
          proof: {
            providerRepositoryId: REPOSITORY_ID,
            providerNodeId: "R_task13_existing_repository",
            owner: OWNER,
            name: REPOSITORY,
            visibility: "PRIVATE" as const,
            defaultBranch: "main" as const,
            repositoryMarkerCommitSha: "b".repeat(40),
          },
        });
      },
      finalize: (
        operationId: string,
        expected: unknown,
        binding: VerifiedRepositoryBindingV2,
        actor: unknown,
      ) => {
        calls.push(["FINALIZE", operationId, expected, binding, actor]);
        return Promise.resolve(binding);
      },
    },
  };
}

Deno.test("post-recovery finalizer uses fresh server proof then the dedicated transition", async () => {
  const test = dependencies();
  const finalize = createTask13PostRecoveryFinalizer(config, test.value);
  const result = await finalize(input);
  assertEquals(result.replayed, false);
  assertEquals(result.providerRepositoryId, REPOSITORY_ID);
  assertEquals(test.calls.map((call) => (call as unknown[])[0]), [
    "READ_AUTHORITY",
    "INSPECT_COMPLETION",
    "FINALIZE",
  ]);
  assertEquals((test.calls[2] as unknown[])[4], {
    authUserId: config.actorAuthUserId,
    aal: "aal2",
  });
});

Deno.test("post-recovery finalizer supports exact bound replay", async () => {
  const test = dependencies("BOUND");
  const result = await createTask13PostRecoveryFinalizer(config, test.value)(
    input,
  );
  assertEquals(result.replayed, true);
  assertEquals(test.calls.map((call) => (call as unknown[])[0]), [
    "READ_AUTHORITY",
    "INSPECT_COMPLETION",
    "FINALIZE",
  ]);
});

Deno.test("post-recovery finalizer never writes without ALREADY_COMPLETE proof", async () => {
  const test = dependencies();
  const finalize = createTask13PostRecoveryFinalizer(config, {
    ...test.value,
    inspectCompletion: () => Promise.resolve({ state: "CONFLICT" }),
  } as never);
  await assertRejects(() => finalize(input));
  assertEquals(
    test.calls.some((call) => (call as unknown[])[0] === "FINALIZE"),
    false,
  );
});

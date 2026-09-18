import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type {
  RepositoryProvisioningAuthorityV2,
  VerifiedRepositoryBindingV2,
} from "./repository-provisioning.ts";
import {
  createRepositoryProvisioningStoreV2,
  RepositoryProvisioningClaimDiagnosticError,
} from "./repository-provisioning-store-v2.ts";

const WORKSPACE_ID = "d2110000-0000-4000-8000-000000000001";
const CONTEXT_ID = "d2120000-0000-4000-8000-000000000001";
const IDEMPOTENCY_KEY = "d2130000-0000-4000-8000-000000000001";
const OPERATION_ID = "d2140000-0000-4000-8000-000000000001";
const REPOSITORY_ID = "1369000001";
const NODE_ID = "R_task13_repository";
const MARKER_COMMIT = "b".repeat(40);

const authority: RepositoryProvisioningAuthorityV2 = Object.freeze({
  contractVersion: 2,
  websiteWorkspaceId: WORKSPACE_ID,
  websiteWorkContextId: CONTEXT_ID,
  idempotencyKey: IDEMPOTENCY_KEY,
  repositoryName: "lws-web-d2120000000040008000000000000001",
  starter: Object.freeze({
    source: "lorenzo-web-solutions/lws-website-starter",
    version: "1.0.0",
    commitSha: "a".repeat(40),
    templateRepositoryId: "1368684860",
  }),
});

const binding: VerifiedRepositoryBindingV2 = Object.freeze({
  provider: "GITHUB",
  providerRepositoryId: REPOSITORY_ID,
  providerNodeId: NODE_ID,
  owner: "lorenzo-web-solutions-lab",
  name: authority.repositoryName,
  visibility: "PRIVATE",
  defaultBranch: "main",
  starterSource: authority.starter.source,
  starterVersion: authority.starter.version,
  starterCommitSha: authority.starter.commitSha,
  repositoryMarkerCommitSha: MARKER_COMMIT,
});

function operation(overrides: Record<string, unknown> = {}) {
  return {
    result: "CLAIMED",
    operation_id: OPERATION_ID,
    website_workspace_id: WORKSPACE_ID,
    website_work_context_id: CONTEXT_ID,
    state: "CREATING",
    repository_provider: "GITHUB",
    repository_owner: "lorenzo-web-solutions-lab",
    repository_name: authority.repositoryName,
    starter_source: authority.starter.source,
    starter_version: authority.starter.version,
    starter_commit_sha: authority.starter.commitSha,
    repository_external_id: null,
    repository_node_id: null,
    repository_visibility: null,
    default_branch: null,
    repository_marker_commit_sha: null,
    attempt_count: 1,
    failure_code: null,
    retry_action: "RECONCILE",
    quarantine_evidence_sha256: null,
    ...overrides,
  };
}

Deno.test("StoreV2 maps claim, durable identity capture and bind to the existing authority RPCs", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const responses = [
    operation(),
    operation({
      result: "EXTERNAL_CREATED",
      state: "VERIFYING",
      repository_external_id: REPOSITORY_ID,
      repository_node_id: NODE_ID,
    }),
    operation({
      result: "BOUND",
      state: "BOUND",
      repository_external_id: REPOSITORY_ID,
      repository_node_id: NODE_ID,
      repository_visibility: "private",
      default_branch: "main",
      repository_marker_commit_sha: MARKER_COMMIT,
    }),
  ];
  const store = createRepositoryProvisioningStoreV2({
    rpc(name, args) {
      calls.push({ name, args });
      return Promise.resolve({ data: responses.shift(), error: null });
    },
  });

  assertEquals(await store.claim(authority), {
    state: "CLAIMED",
    operationId: OPERATION_ID,
  });
  await store.captureLabIdentity({
    operationId: OPERATION_ID,
    websiteWorkContextId: CONTEXT_ID,
    repositoryId: REPOSITORY_ID,
    nodeId: NODE_ID,
  });
  assertEquals(
    await store.bind(
      OPERATION_ID,
      { websiteWorkspaceId: WORKSPACE_ID, websiteWorkContextId: CONTEXT_ID },
      binding,
    ),
    binding,
  );
  assertEquals(calls.map((call) => call.name), [
    "claim_website_repository_provisioning_v1",
    "record_website_repository_external_identity_v1",
    "bind_website_repository_v1",
  ]);
  assertEquals(calls[0].args, {
    p_website_workspace_id: WORKSPACE_ID,
    p_website_work_context_id: CONTEXT_ID,
    p_idempotency_key: IDEMPOTENCY_KEY,
    p_starter_source: authority.starter.source,
    p_starter_version: authority.starter.version,
    p_starter_commit_sha: authority.starter.commitSha,
  });
  assertEquals(calls[1].args, {
    p_operation_id: OPERATION_ID,
    p_repository_external_id: REPOSITORY_ID,
    p_repository_node_id: NODE_ID,
  });
});

Deno.test("StoreV2 finalizes a recovered repository through only the dedicated RPC", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const store = createRepositoryProvisioningStoreV2({
    rpc(name, args) {
      calls.push({ name, args });
      return Promise.resolve({
        data: operation({
          result: "BOUND",
          state: "BOUND",
          repository_external_id: REPOSITORY_ID,
          repository_node_id: NODE_ID,
          repository_visibility: "private",
          default_branch: "main",
          repository_marker_commit_sha: MARKER_COMMIT,
        }),
        error: null,
      });
    },
  });

  assertEquals(
    await store.finalizeRecoveredRepository(
      OPERATION_ID,
      { websiteWorkspaceId: WORKSPACE_ID, websiteWorkContextId: CONTEXT_ID },
      binding,
      { authUserId: "d2100000-0000-4000-8000-000000000001", aal: "aal2" },
    ),
    binding,
  );
  assertEquals(calls, [{
    name: "finalize_recovered_website_repository_v1",
    args: {
      p_operation_id: OPERATION_ID,
      p_verification: {
        operation_id: OPERATION_ID,
        website_workspace_id: WORKSPACE_ID,
        website_work_context_id: CONTEXT_ID,
        repository_external_id: REPOSITORY_ID,
        repository_node_id: NODE_ID,
        repository_owner: binding.owner,
        repository_name: binding.name,
        repository_visibility: "private",
        default_branch: "main",
        starter_source: binding.starterSource,
        starter_version: binding.starterVersion,
        starter_commit_sha: binding.starterCommitSha,
        repository_marker_commit_sha: MARKER_COMMIT,
      },
      p_actor_auth_user_id: "d2100000-0000-4000-8000-000000000001",
      p_actor_aal: "aal2",
    },
  }]);
});

Deno.test("StoreV2 concurrent replay cannot grant a second create authority", async () => {
  const store = createRepositoryProvisioningStoreV2({
    rpc: () =>
      Promise.resolve({
        data: operation({ result: "REPLAY", state: "CREATING" }),
        error: null,
      }),
  });
  assertEquals(await store.claim(authority), { state: "IN_PROGRESS" });
});

Deno.test("StoreV2 exposes only redacted failure, reconciliation and quarantine state", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const secret = "ghs_synthetic_secret_token_value";
  const store = createRepositoryProvisioningStoreV2({
    rpc(name, args) {
      calls.push({ name, args });
      if (name === "fail_website_repository_provisioning_v1") {
        return Promise.resolve({
          data: operation({
            result: "QUARANTINED",
            state: "QUARANTINED",
            failure_code: "REPOSITORY_IDENTITY_MISMATCH",
            quarantine_evidence_sha256: "c".repeat(64),
          }),
          error: null,
        });
      }
      return Promise.resolve({
        data: operation({ result: "READ", state: "QUARANTINED" }),
        error: null,
      });
    },
  });

  const quarantined = await store.quarantine(
    OPERATION_ID,
    "REPOSITORY_IDENTITY_MISMATCH",
  );
  assertEquals(quarantined.state, "QUARANTINED");
  assertEquals((await store.readStatus(OPERATION_ID)).state, "QUARANTINED");
  assertEquals(JSON.stringify({ calls, quarantined }).includes(secret), false);

  const failing = createRepositoryProvisioningStoreV2({
    rpc: () => Promise.resolve({ data: null, error: { message: secret } }),
  });
  const error = await assertRejects(
    () => failing.claim(authority),
    RepositoryProvisioningClaimDiagnosticError,
    "REPOSITORY_PROVISIONING_CLAIM_FAILED",
  );
  assertEquals(error.phase, "CLAIM_RPC_HTTP_OR_POSTGREST");
  assertEquals(`${error.message}\n${error.stack}`.includes(secret), false);
});

Deno.test("StoreV2 classifies claim failures without exposing raw errors", async () => {
  const secret = "database-secret-message";
  const scenarios = [
    {
      name: "transport exception",
      rpc: () => Promise.reject(new TypeError(secret)),
      phase: "CLAIM_RPC_INVOCATION",
      sqlstateClass: undefined,
    },
    {
      name: "PostgREST error",
      rpc: () =>
        Promise.resolve({
          data: null,
          error: { code: "PGRST202", message: secret },
        }),
      phase: "CLAIM_RPC_HTTP_OR_POSTGREST",
      sqlstateClass: undefined,
    },
    {
      name: "authority error",
      rpc: () =>
        Promise.resolve({
          data: null,
          error: { code: "42501", message: secret },
        }),
      phase: "CLAIM_RPC_AUTHORITY",
      sqlstateClass: "42",
    },
    {
      name: "database exception",
      rpc: () =>
        Promise.resolve({
          data: null,
          error: { code: "23514", message: secret },
        }),
      phase: "CLAIM_RPC_DATABASE_EXCEPTION",
      sqlstateClass: "23",
    },
    {
      name: "null response",
      rpc: () => Promise.resolve({ data: null, error: null }),
      phase: "CLAIM_RPC_RESPONSE_VALIDATION",
      sqlstateClass: undefined,
    },
    {
      name: "malformed JSONB",
      rpc: () => Promise.resolve({ data: { result: "CLAIMED" }, error: null }),
      phase: "CLAIM_RPC_RESPONSE_VALIDATION",
      sqlstateClass: undefined,
    },
    {
      name: "unexpected exception",
      rpc: () => Promise.reject(new Error(secret)),
      phase: "UNKNOWN_CLAIM_ERROR",
      sqlstateClass: undefined,
    },
  ] as const;

  for (const scenario of scenarios) {
    const store = createRepositoryProvisioningStoreV2({ rpc: scenario.rpc });
    const error = await assertRejects(
      () => store.claim(authority),
      RepositoryProvisioningClaimDiagnosticError,
    );
    assertEquals(error.phase, scenario.phase, scenario.name);
    assertEquals(error.sqlstateClass, scenario.sqlstateClass, scenario.name);
    assertEquals(JSON.stringify(error).includes(secret), false, scenario.name);
    assertEquals(`${error.message}\n${error.stack}`.includes(secret), false);
  }
});

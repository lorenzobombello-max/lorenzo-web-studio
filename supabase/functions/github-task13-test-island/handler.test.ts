import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  createUnsignedTask13TestJwt,
  handleGitHubTask13TestIsland,
} from "./handler.ts";
import { RepositoryProvisioningClaimDiagnosticError } from "../_shared/repository-provisioning-store-v2.ts";
import { GitHubRepositoryProviderError } from "../_shared/github-repository-provider.ts";
import {
  GITHUB_LAB_POST_CREATE_SUBPHASES,
  GitHubLabPostCreateDiagnosticError,
  GitHubTokenAcquireDiagnosticError,
  RepositoryProvisioningProviderDiagnosticError,
  RepositoryProvisioningRuntimeDiagnosticError,
} from "../_shared/repository-provisioning-diagnostics.ts";
import { RepositoryPreclaimDiagnosticError } from "./runtime.ts";
import { Task13LabReadonlyError } from "./readonly-reconciliation.ts";
import { createGitHubRefReadDiagnostic } from "../_shared/github-ref-read-diagnostic.ts";
import { createGitHubHttpClient } from "../_shared/github-http.ts";
import { createGitHubRepositoryStateInspectionCapability } from "../_shared/github-repository-state-inspector.ts";
import { createTask13RecoveryPrerequisiteInspection } from "./recovery-prerequisite-inspection.ts";

const SUBJECT = "d2100000-0000-4000-8000-000000000001";
const WORKSPACE_ID = "d2110000-0000-4000-8000-000000000001";
const CONTEXT_ID = "d2120000-0000-4000-8000-000000000001";
const IDEMPOTENCY_KEY = "d2130000-0000-4000-8000-000000000001";
const SYNTHETIC_WORKSPACE_ID = "4dfe44a5-60d0-4728-b62b-ef87aa838976";
const SYNTHETIC_CONTEXT_ID = "33a61b58-1d55-4624-bdb7-3c724d35ebcc";
const OPERATION_ID = "e646ae44-ec5d-46b6-96e3-b1023b9e1b68";
const NOW = Date.parse("2026-09-13T12:00:00.000Z");

const recoveryBody = Object.freeze({
  action: "inspect_recovery_prerequisites",
  operation_id: OPERATION_ID,
  website_workspace_id: SYNTHETIC_WORKSPACE_ID,
  website_work_context_id: SYNTHETIC_CONTEXT_ID,
});
const recoveryWriteBody = Object.freeze({
  action: "recover_post_create_existing_repository",
  operation_id: OPERATION_ID,
  website_workspace_id: SYNTHETIC_WORKSPACE_ID,
  website_work_context_id: SYNTHETIC_CONTEXT_ID,
});
const finalizationBody = Object.freeze({
  action: "finalize_post_recovery_repository",
  operation_id: OPERATION_ID,
  website_workspace_id: SYNTHETIC_WORKSPACE_ID,
  website_work_context_id: SYNTHETIC_CONTEXT_ID,
});

function request(claims: Record<string, unknown>, body: unknown = {
  action: "execute_task13_test_island",
  website_workspace_id: WORKSPACE_ID,
  website_work_context_id: CONTEXT_ID,
  idempotency_key: IDEMPOTENCY_KEY,
}) {
  return new Request("https://example.test/github-task13-test-island", {
    method: "POST",
    headers: {
      "authorization": `Bearer ${createUnsignedTask13TestJwt(claims)}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function dependencies(overrides: Record<string, unknown> = {}) {
  const calls: string[] = [];
  let executedCommand: unknown;
  let verifiedActor: unknown;
  return {
    calls,
    executedCommand: () => executedCommand,
    verifiedActor: () => verifiedActor,
    value: {
      now: () => NOW,
      verifyUser: () => {
        calls.push("VERIFY_USER");
        return Promise.resolve({ id: SUBJECT });
      },
      authorizeOwner: () => {
        calls.push("AUTHORIZE_OWNER");
        return Promise.resolve();
      },
      verifySyntheticAuthority: () => {
        calls.push("VERIFY_SYNTHETIC_AUTHORITY");
        return Promise.resolve(true);
      },
      execute: (command: unknown) => {
        calls.push("EXECUTE");
        executedCommand = command;
        return Promise.resolve({
          provider: "GITHUB" as const,
          providerRepositoryId: "1369000001",
          providerNodeId: "R_task13_repository",
          owner: "lorenzo-web-solutions-lab",
          name: "lws-web-d2120000000040008000000000000001",
          visibility: "PRIVATE" as const,
          defaultBranch: "main" as const,
          starterSource: "lorenzo-web-solutions/lws-website-starter",
          starterVersion: "1.0.0",
          starterCommitSha: "a".repeat(40),
          repositoryMarkerCommitSha: "b".repeat(40),
          replayed: false,
        });
      },
      reconcileReadonly: () =>
        Promise.reject(new Error("READONLY_RECONCILIATION_NOT_EXPECTED")),
      inspectRecoveryPrerequisites: () => {
        calls.push("INSPECT_RECOVERY_PREREQUISITES");
        return Promise.resolve({
          authority_valid: true as const,
          repository_identity_valid: true as const,
          state_classification: "ALREADY_COMPLETE" as const,
        });
      },
      recoverPostCreateExistingRepository: (input: unknown) => {
        calls.push("RECOVER_POST_CREATE_EXISTING_REPOSITORY");
        executedCommand = input;
        return Promise.resolve(
          Object.freeze({ status: "ALREADY_COMPLETE" as const }),
        );
      },
      finalizePostRecoveryRepository: (input: unknown, actor: unknown) => {
        calls.push("FINALIZE_POST_RECOVERY_REPOSITORY");
        executedCommand = input;
        verifiedActor = actor;
        return Promise.resolve({
          provider: "GITHUB" as const,
          providerRepositoryId: "1371224564",
          providerNodeId: "R_task13_existing_repository",
          owner: "lorenzo-web-solutions-lab",
          name: "lws-web-33a61b581d554624bdb73c724d35ebcc",
          visibility: "PRIVATE" as const,
          defaultBranch: "main" as const,
          starterSource: "lorenzo-web-solutions/lws-website-starter",
          starterVersion: "1.0.0",
          starterCommitSha: "a".repeat(40),
          repositoryMarkerCommitSha: "b".repeat(40),
          replayed: false,
        });
      },
      ...overrides,
    },
  };
}

Deno.test("Task 13 finalization action reaches only its narrow dependency", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      finalizationBody,
    ),
    test.value,
  );
  assertEquals(response.status, 200);
  assertEquals(test.calls, [
    "VERIFY_USER",
    "AUTHORIZE_OWNER",
    "VERIFY_SYNTHETIC_AUTHORITY",
    "FINALIZE_POST_RECOVERY_REPOSITORY",
  ]);
  assertEquals(test.executedCommand(), {
    operationId: OPERATION_ID,
    websiteWorkContextId: SYNTHETIC_CONTEXT_ID,
    websiteWorkspaceId: SYNTHETIC_WORKSPACE_ID,
  });
  assertEquals(test.verifiedActor(), { authUserId: SUBJECT, aal: "aal2" });
  assertEquals(await response.json(), {
    ok: true,
    code: "TASK13_POST_RECOVERY_REPOSITORY_FINALIZED",
    result: {
      status: "REPOSITORY_READY",
      replayed: false,
    },
  });
});

Deno.test("Task 13 finalization action fails closed before its dependency", async () => {
  const scenarios = [
    {
      body: finalizationBody,
      claims: { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal1" },
      overrides: {},
      status: 403,
      code: "AAL2_VERIFICATION",
    },
    {
      body: finalizationBody,
      claims: { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      overrides: { verifySyntheticAuthority: () => Promise.resolve(false) },
      status: 403,
      code: "TASK13_SYNTHETIC_AUTHORITY_INVALID",
    },
    {
      body: { ...finalizationBody, repository_external_id: "1371224564" },
      claims: { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      overrides: {},
      status: 400,
      code: "INVALID_REQUEST",
    },
  ];
  for (const scenario of scenarios) {
    const test = dependencies(scenario.overrides);
    const response = await handleGitHubTask13TestIsland(
      request(scenario.claims, scenario.body),
      test.value,
    );
    assertEquals(response.status, scenario.status);
    assertEquals((await response.json()).code, scenario.code);
    assertEquals(
      test.calls.includes("FINALIZE_POST_RECOVERY_REPOSITORY"),
      false,
    );
  }

  const test = dependencies({
    finalizePostRecoveryRepository: () =>
      Promise.reject(new Error("raw finalizer detail")),
  });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      finalizationBody,
    ),
    test.value,
  );
  const text = await response.text();
  assertEquals(response.status, 502);
  assertEquals(
    JSON.parse(text).code,
    "TASK13_POST_RECOVERY_FINALIZATION_FAILED",
  );
  assertEquals(text.includes("raw finalizer detail"), false);
});

Deno.test("Task 13 recovery writer action reaches only its narrow dependency", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryWriteBody,
    ),
    test.value,
  );
  assertEquals(response.status, 200);
  assertEquals(test.calls, [
    "VERIFY_USER",
    "AUTHORIZE_OWNER",
    "VERIFY_SYNTHETIC_AUTHORITY",
    "RECOVER_POST_CREATE_EXISTING_REPOSITORY",
  ]);
  assertEquals(test.executedCommand(), {
    operationId: OPERATION_ID,
    websiteWorkContextId: SYNTHETIC_CONTEXT_ID,
    websiteWorkspaceId: SYNTHETIC_WORKSPACE_ID,
  });
  const body = await response.json();
  assertEquals(body, {
    ok: true,
    code: "TASK13_POST_CREATE_RECOVERY_RESULT",
    result: { status: "ALREADY_COMPLETE" },
  });
});

Deno.test("Task 13 recovery writer action keeps the human AAL2 OWNER boundary", async () => {
  const scenarios = [
    {
      request: new Request("https://example.test/github-task13-test-island", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(recoveryWriteBody),
      }),
      overrides: {},
      status: 401,
      code: "CALLER_VERIFICATION",
    },
    {
      request: request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal1" },
        recoveryWriteBody,
      ),
      overrides: {},
      status: 403,
      code: "AAL2_VERIFICATION",
    },
    {
      request: request(
        { sub: SUBJECT, exp: NOW / 1000 - 1, aal: "aal2" },
        recoveryWriteBody,
      ),
      overrides: {},
      status: 403,
      code: "CALLER_VERIFICATION",
    },
    {
      request: request(
        {
          sub: SUBJECT,
          exp: NOW / 1000 + 60,
          aal: "aal2",
          role: "service_role",
        },
        recoveryWriteBody,
      ),
      overrides: {},
      status: 403,
      code: "CALLER_VERIFICATION",
    },
    {
      request: request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryWriteBody,
      ),
      overrides: { verifyUser: () => Promise.resolve(null) },
      status: 403,
      code: "CALLER_VERIFICATION",
    },
    {
      request: request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryWriteBody,
      ),
      overrides: {
        authorizeOwner: () => Promise.reject(new Error("not owner")),
      },
      status: 403,
      code: "OWNER_AUTHORIZATION",
    },
  ];
  for (const scenario of scenarios) {
    const test = dependencies(scenario.overrides);
    const response = await handleGitHubTask13TestIsland(
      scenario.request,
      test.value,
    );
    assertEquals(response.status, scenario.status);
    assertEquals((await response.json()).code, scenario.code);
    assertEquals(
      test.calls.includes("RECOVER_POST_CREATE_EXISTING_REPOSITORY"),
      false,
    );
  }
});

Deno.test("Task 13 recovery writer action requires exact synthetic authority", async () => {
  const test = dependencies({
    verifySyntheticAuthority: () => Promise.resolve(false),
  });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryWriteBody,
    ),
    test.value,
  );
  assertEquals(response.status, 403);
  assertEquals(
    (await response.json()).code,
    "TASK13_SYNTHETIC_AUTHORITY_INVALID",
  );
  assertEquals(
    test.calls.includes("RECOVER_POST_CREATE_EXISTING_REPOSITORY"),
    false,
  );
});

Deno.test("Task 13 recovery writer action rejects every caller authority override", async () => {
  for (
    const extra of [
      { extra: true },
      { repository_external_id: "1371224564" },
      { owner: "lorenzo-web-solutions-lab" },
      { idempotency_key: IDEMPOTENCY_KEY },
    ]
  ) {
    const test = dependencies();
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        { ...recoveryWriteBody, ...extra },
      ),
      test.value,
    );
    assertEquals(response.status, 400);
    assertEquals((await response.json()).code, "INVALID_REQUEST");
    assertEquals(test.calls, []);
  }
});

Deno.test("Task 13 recovery writer action projects every closed status", async () => {
  for (
    const status of [
      "ALREADY_COMPLETE",
      "RECOVERED_FROM_EMPTY",
      "RECOVERED_MARKER_ONLY",
    ] as const
  ) {
    const test = dependencies({
      recoverPostCreateExistingRepository: () =>
        Promise.resolve(Object.freeze({ status })),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryWriteBody,
      ),
      test.value,
    );
    assertEquals(response.status, 200);
    assertEquals((await response.json()).result, { status });
  }
});

Deno.test("Task 13 recovery writer action rejects forged or mutable results", async () => {
  const valid = { status: "ALREADY_COMPLETE" };
  const hidden = { ...valid };
  Object.defineProperty(hidden, "raw", { value: "secret", enumerable: false });
  const accessor = Object.defineProperty({}, "status", {
    get: () => "ALREADY_COMPLETE",
    enumerable: true,
  });
  const symbol = Object.assign({ ...valid }, { [Symbol("raw")]: "secret" });
  const mutable = { ...valid };
  for (
    const unsafe of [
      { ...valid, raw: "secret" },
      hidden,
      accessor,
      Object.freeze(symbol),
      Object.assign(Object.create({ forged: true }), valid),
      { status: "UNKNOWN" },
      mutable,
    ]
  ) {
    const test = dependencies({
      recoverPostCreateExistingRepository: () => Promise.resolve(unsafe),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryWriteBody,
      ),
      test.value as never,
    );
    const text = await response.text();
    assertEquals(response.status, 502);
    assertEquals(JSON.parse(text).code, "TASK13_POST_CREATE_RECOVERY_FAILED");
    assertEquals(text.includes("secret"), false);
  }
});

Deno.test("Task 13 recovery prerequisite inspection keeps the human AAL2 OWNER boundary", async () => {
  const scenarios = [
    {
      request: new Request("https://example.test/github-task13-test-island", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(recoveryBody),
      }),
      overrides: {},
      status: 401,
      code: "CALLER_VERIFICATION",
    },
    {
      request: request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal1" },
        recoveryBody,
      ),
      overrides: {},
      status: 403,
      code: "AAL2_VERIFICATION",
    },
    {
      request: request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryBody,
      ),
      overrides: {
        authorizeOwner: () => Promise.reject(new Error("not owner")),
      },
      status: 403,
      code: "OWNER_AUTHORIZATION",
    },
  ];
  for (const scenario of scenarios) {
    const test = dependencies(scenario.overrides);
    const response = await handleGitHubTask13TestIsland(
      scenario.request,
      test.value,
    );
    assertEquals(response.status, scenario.status);
    assertEquals((await response.json()).code, scenario.code);
    assertEquals(test.calls.includes("INSPECT_RECOVERY_PREREQUISITES"), false);
  }
});

Deno.test("Task 13 recovery prerequisite inspection rejects excess caller authority", async () => {
  for (
    const extra of [
      { repository_external_id: "1371224564" },
      { owner: "lorenzo-web-solutions-lab" },
      { repository: "lws-web-33a61b581d554624bdb73c724d35ebcc" },
      { installation_id: "161461160" },
      { idempotency_key: IDEMPOTENCY_KEY },
      { permissions: { contents: "read" } },
      { ref: "heads/main" },
    ]
  ) {
    const test = dependencies();
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        { ...recoveryBody, ...extra },
      ),
      test.value,
    );
    assertEquals(response.status, 400);
    assertEquals((await response.json()).code, "INVALID_REQUEST");
    assertEquals(test.calls, []);
  }
});

Deno.test("Task 13 recovery prerequisite inspection requires exact synthetic authority", async () => {
  const test = dependencies({
    verifySyntheticAuthority: () => Promise.resolve(false),
  });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    test.value,
  );
  assertEquals(response.status, 403);
  assertEquals(
    (await response.json()).code,
    "TASK13_SYNTHETIC_AUTHORITY_INVALID",
  );
  assertEquals(test.calls.includes("INSPECT_RECOVERY_PREREQUISITES"), false);
});

Deno.test("Task 13 recovery prerequisite inspection returns one closed classification", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    test.value,
  );
  assertEquals(response.status, 200);
  assertEquals(test.calls, [
    "VERIFY_USER",
    "AUTHORIZE_OWNER",
    "VERIFY_SYNTHETIC_AUTHORITY",
    "INSPECT_RECOVERY_PREREQUISITES",
  ]);
  assertEquals(await response.json(), {
    ok: true,
    code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION",
    result: {
      authority_valid: true,
      repository_identity_valid: true,
      state_classification: "ALREADY_COMPLETE",
    },
  });
});

Deno.test("Task 13 recovery prerequisite inspection preserves all four success contracts", async () => {
  for (
    const stateClassification of [
      "EMPTY_OR_UNINITIALIZED",
      "ALREADY_COMPLETE",
      "MARKER_MISSING",
      "CONFLICT",
    ] as const
  ) {
    const test = dependencies({
      inspectRecoveryPrerequisites: () =>
        Promise.resolve({
          authority_valid: true as const,
          repository_identity_valid: true as const,
          state_classification: stateClassification,
        }),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryBody,
      ),
      test.value,
    );
    assertEquals(response.status, 200);
    assertEquals(await response.json(), {
      ok: true,
      code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION",
      result: {
        authority_valid: true,
        repository_identity_valid: true,
        state_classification: stateClassification,
      },
    });
  }
});

Deno.test("Task 13 recovery prerequisite inspection projects every trusted read phase", async () => {
  for (
    const failedInspectionPhase of [
      "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
      "LAB_POST_CREATE_METADATA_READ",
      "LAB_POST_CREATE_SNAPSHOT_READBACK",
      "LAB_POST_CREATE_MARKER_READBACK",
      "LAB_POST_CREATE_PROVENANCE_VALIDATE",
    ] as const
  ) {
    const error = new GitHubLabPostCreateDiagnosticError(
      failedInspectionPhase,
    );
    const test = dependencies({
      inspectRecoveryPrerequisites: () => Promise.reject(error),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryBody,
      ),
      test.value,
    );
    assertEquals(response.status, 502);
    assertEquals(await response.json(), {
      ok: false,
      code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
      failed_inspection_phase: failedInspectionPhase,
      ...(failedInspectionPhase === "LAB_POST_CREATE_SNAPSHOT_READBACK"
        ? { failed_snapshot_readback_check: "UNKNOWN" }
        : {}),
    });
  }
});

Deno.test("Task 13 snapshot failure projects one closed nested check", async () => {
  const Diagnostic = GitHubLabPostCreateDiagnosticError as unknown as new (
    subphase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
    snapshotReadbackCheck: string,
  ) => GitHubLabPostCreateDiagnosticError;
  for (
    const snapshotReadbackCheck of [
      "REF_READ",
      "COMMIT_READ",
      "TREE_READ",
      "BLOB_READ",
    ]
  ) {
    const test = dependencies({
      inspectRecoveryPrerequisites: () =>
        Promise.reject(
          new Diagnostic(
            "LAB_POST_CREATE_SNAPSHOT_READBACK",
            snapshotReadbackCheck,
          ),
        ),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryBody,
      ),
      test.value,
    );
    assertEquals(response.status, 502);
    assertEquals(await response.json(), {
      ok: false,
      code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
      failed_inspection_phase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
      failed_snapshot_readback_check: snapshotReadbackCheck,
      ...(snapshotReadbackCheck === "REF_READ"
        ? {
          failed_ref_read_diagnostic: {
            boundary: "UNKNOWN",
            code: "UNKNOWN",
          },
        }
        : {}),
    });
  }
});

Deno.test("Task 13 REF_READ failure projects only one closed trusted diagnostic", async () => {
  const Diagnostic = GitHubLabPostCreateDiagnosticError as unknown as new (
    subphase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
    snapshotReadbackCheck: "REF_READ",
    refReadDiagnostic: Readonly<{ boundary: string; code: string }>,
  ) => GitHubLabPostCreateDiagnosticError;
  const test = dependencies({
    inspectRecoveryPrerequisites: () =>
      Promise.reject(
        new Diagnostic(
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "REF_READ",
          createGitHubRefReadDiagnostic(
            "HTTP_STATUS",
            "GITHUB_HTTP_FORBIDDEN",
          ),
        ),
      ),
  });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    test.value,
  );
  assertEquals(response.status, 502);
  const body = await response.json();
  assertEquals(body, {
    ok: false,
    code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
    failed_inspection_phase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
    failed_snapshot_readback_check: "REF_READ",
    failed_ref_read_diagnostic: {
      boundary: "HTTP_STATUS",
      code: "GITHUB_HTTP_FORBIDDEN",
    },
  });
  assertEquals(Object.keys(body.failed_ref_read_diagnostic).sort(), [
    "boundary",
    "code",
  ]);
});

Deno.test("Task 13 preserves a real HTTP REF_READ diagnostic through every layer", async () => {
  const expected = Object.freeze({
    websiteWorkContextId: SYNTHETIC_CONTEXT_ID,
    repositoryId: "1371224564",
    owner: "lorenzo-web-solutions-lab",
    repository: "lws-web-33a61b581d554624bdb73c724d35ebcc",
    private: true as const,
    defaultBranch: "main" as const,
    snapshotTreeSha256: "b".repeat(64),
    markerContent: "synthetic marker",
  });
  const config = {
    production: {
      target: "PRODUCTION",
      templateOwner: "lorenzo-web-solutions",
      templateName: "lws-website-starter",
    },
    lab: {
      target: "TEST",
      organization: expected.owner,
      installationId: "161461160",
      starterVersion: "1.0.0",
      starterCommitSha: "a".repeat(40),
      starterTreeSha256: expected.snapshotTreeSha256,
    },
  } as const;
  const operations: string[] = [];
  const http = createGitHubHttpClient({
    fetch: (input) => {
      const url = String(input);
      const isRef = url.includes("/git/ref/");
      operations.push(isRef ? "READ_REF" : "REPOSITORY_METADATA");
      return Promise.resolve(
        isRef
          ? new Response("{}", {
            status: 403,
            headers: { "content-type": "application/json" },
          })
          : new Response(
            JSON.stringify({
              id: Number(expected.repositoryId),
              node_id: "R_task13_existing_repository",
              owner: { login: expected.owner },
              name: expected.repository,
              full_name: `${expected.owner}/${expected.repository}`,
              private: true,
              default_branch: "main",
              description: null,
              created_at: "2026-09-13T12:00:00.000Z",
            }),
            { headers: { "content-type": "application/json" } },
          ),
      );
    },
  });
  const inspectRepository = createGitHubRepositoryStateInspectionCapability(
    config.lab as never,
    expected,
    {
      tokenBroker: {
        issue: () => Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
      },
      http,
    } as never,
  );
  const inspect = createTask13RecoveryPrerequisiteInspection(
    config as never,
    {
      rpc: () =>
        Promise.resolve({
          error: null,
          data: {
            operation_found: true,
            operation_id: OPERATION_ID,
            website_work_context_id: SYNTHETIC_CONTEXT_ID,
            website_workspace_id: SYNTHETIC_WORKSPACE_ID,
            operation_state: "TERMINAL_FAILED",
            failure_code: "REPOSITORY_PROVIDER_FAILED",
            external_created_at_present: true,
            repository_external_id: expected.repositoryId,
            target_owner: expected.owner,
            target_repository_name: expected.repository,
            bound_at_present: false,
            quarantine_present: false,
            customer_binding_present: false,
            dossier_binding_present: false,
            repository_binding_present: false,
          },
        }),
      inspectRepository,
    },
  );
  const test = dependencies({ inspectRecoveryPrerequisites: inspect });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    test.value,
  );
  assertEquals(response.status, 502);
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
    failed_inspection_phase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
    failed_snapshot_readback_check: "REF_READ",
    failed_ref_read_diagnostic: {
      boundary: "HTTP_STATUS",
      code: "GITHUB_HTTP_FORBIDDEN",
    },
  });
  assertEquals(operations, ["REPOSITORY_METADATA", "READ_REF"]);
});

Deno.test("Task 13 omits REF_READ metadata from success and other failures", async () => {
  const success = dependencies();
  const successResponse = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    success.value,
  );
  assertEquals(
    "failed_ref_read_diagnostic" in await successResponse.json(),
    false,
  );

  const failure = dependencies({
    inspectRecoveryPrerequisites: () =>
      Promise.reject(
        new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "TREE_READ",
        ),
      ),
  });
  const failureResponse = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    failure.value,
  );
  assertEquals(
    "failed_ref_read_diagnostic" in await failureResponse.json(),
    false,
  );
});

Deno.test("Task 13 snapshot failure defaults missing nested evidence to UNKNOWN", async () => {
  const error = new GitHubLabPostCreateDiagnosticError(
    "LAB_POST_CREATE_SNAPSHOT_READBACK",
  );
  const test = dependencies({
    inspectRecoveryPrerequisites: () => Promise.reject(error),
  });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
    failed_inspection_phase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
    failed_snapshot_readback_check: "UNKNOWN",
  });
});

Deno.test("Task 13 recovery prerequisite inspection identifies authority infrastructure", async () => {
  const { createTask13RecoveryPrerequisiteInspection } = await import(
    "./recovery-prerequisite-inspection.ts"
  );
  const inspect = createTask13RecoveryPrerequisiteInspection(
    {
      production: {
        templateOwner: "lorenzo-web-solutions",
        templateName: "lws-website-starter",
      },
      lab: {
        target: "TEST",
        organization: "lorenzo-web-solutions-lab",
        installationId: "161461160",
        starterVersion: "1.0.0",
        starterCommitSha: "a".repeat(40),
        starterTreeSha256: "b".repeat(64),
      },
    } as never,
    {
      rpc: () => Promise.reject(new Error("raw RPC transport detail")),
      inspectRepository: () =>
        Promise.reject(new Error("inspector must not run")),
    },
  );
  const test = dependencies({ inspectRecoveryPrerequisites: inspect });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    test.value,
  );
  assertEquals(response.status, 502);
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
    failed_inspection_phase: "RECOVERY_AUTHORITY",
  });
});

Deno.test("Task 13 recovery prerequisite inspection keeps authority precondition rejection unknown", async () => {
  const { createTask13RecoveryPrerequisiteInspection } = await import(
    "./recovery-prerequisite-inspection.ts"
  );
  const inspect = createTask13RecoveryPrerequisiteInspection(
    {
      production: {
        templateOwner: "lorenzo-web-solutions",
        templateName: "lws-website-starter",
      },
      lab: {
        target: "TEST",
        organization: "lorenzo-web-solutions-lab",
        installationId: "161461160",
        starterVersion: "1.0.0",
        starterCommitSha: "a".repeat(40),
        starterTreeSha256: "b".repeat(64),
      },
    } as never,
    {
      rpc: () =>
        Promise.resolve({
          data: {
            operation_found: true,
            operation_id: OPERATION_ID,
            website_work_context_id: SYNTHETIC_CONTEXT_ID,
            website_workspace_id: SYNTHETIC_WORKSPACE_ID,
            operation_state: "TERMINAL_FAILED",
            failure_code: "REPOSITORY_PROVIDER_FAILED",
            external_created_at_present: true,
            repository_external_id: "1371224564",
            target_owner: "lorenzo-web-solutions-lab",
            target_repository_name: "lws-web-33a61b581d554624bdb73c724d35ebcc",
            bound_at_present: true,
            quarantine_present: false,
            customer_binding_present: false,
            dossier_binding_present: false,
            repository_binding_present: false,
          },
          error: null,
        }),
      inspectRepository: () =>
        Promise.reject(new Error("inspector must not run")),
    },
  );
  const test = dependencies({ inspectRecoveryPrerequisites: inspect });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
    failed_inspection_phase: "UNKNOWN",
  });
});

Deno.test("Task 13 recovery prerequisite inspection rejects trusted write phases", async () => {
  for (
    const writePhase of [
      "LAB_POST_CREATE_WRITE_TOKEN_ACQUIRE",
      "LAB_POST_CREATE_SNAPSHOT_PREPARE",
      "LAB_POST_CREATE_BLOB_WRITE",
      "LAB_POST_CREATE_TREE_WRITE",
      "LAB_POST_CREATE_COMMIT_WRITE",
      "LAB_POST_CREATE_REF_WRITE",
      "LAB_POST_CREATE_MARKER_WRITE",
      "LAB_POST_CREATE_WRITE_RESULT_VALIDATE",
    ] as const
  ) {
    const test = dependencies({
      inspectRecoveryPrerequisites: () =>
        Promise.reject(new GitHubLabPostCreateDiagnosticError(writePhase)),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryBody,
      ),
      test.value,
    );
    assertEquals(await response.json(), {
      ok: false,
      code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
      failed_inspection_phase: "UNKNOWN",
    });
  }
});

Deno.test("Task 13 recovery prerequisite inspection maps unknown and forged failures closed", async () => {
  const secret = "token Authorization private_key repository SQL URL stack";
  const forged = Object.assign(
    Object.create(GitHubLabPostCreateDiagnosticError.prototype),
    { subphase: "LAB_POST_CREATE_METADATA_READ", raw: secret },
  );
  for (
    const error of [
      Object.assign(new Error(secret), {
        failed_inspection_phase: "LAB_POST_CREATE_METADATA_READ",
        token: secret,
        authorization: secret,
        private_key: secret,
        repository_content: secret,
        github_body: secret,
        sql_message: secret,
        url: secret,
        arbitrary: secret,
      }),
      forged,
    ]
  ) {
    Object.defineProperty(error, "hidden", {
      value: secret,
      enumerable: false,
    });
    Object.defineProperty(error, Symbol("secret"), { value: secret });
    Object.defineProperty(error, "throwing", {
      get: () => {
        throw new Error(secret);
      },
      enumerable: true,
    });
    const test = dependencies({
      inspectRecoveryPrerequisites: () => Promise.reject(error),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryBody,
      ),
      test.value,
    );
    const text = await response.text();
    assertEquals(response.status, 502);
    assertEquals(JSON.parse(text), {
      ok: false,
      code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
      failed_inspection_phase: "UNKNOWN",
    });
    assertEquals(Reflect.ownKeys(JSON.parse(text)).sort(), [
      "code",
      "failed_inspection_phase",
      "ok",
    ]);
    assertEquals(text.includes(secret), false);
  }
});

Deno.test("Task 13 recovery prerequisite inspection leaks no hostile trusted-error properties", async () => {
  const secret = "raw-message-stack-token-private-key-body-content";
  const error = new GitHubLabPostCreateDiagnosticError(
    "LAB_POST_CREATE_METADATA_READ",
  );
  Object.assign(error, {
    raw_error: secret,
    stack: secret,
    cause: secret,
    token: secret,
    authorization: secret,
    private_key: secret,
    repository_content: secret,
    provider_response: secret,
  });
  Object.defineProperty(error, "hidden", { value: secret });
  Object.defineProperty(error, Symbol("secret"), { value: secret });
  Object.defineProperty(error, "throwing", {
    get: () => {
      throw new Error(secret);
    },
    enumerable: true,
  });
  const test = dependencies({
    inspectRecoveryPrerequisites: () => Promise.reject(error),
  });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      recoveryBody,
    ),
    test.value,
  );
  const text = await response.text();
  assertEquals(JSON.parse(text), {
    ok: false,
    code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
    failed_inspection_phase: "LAB_POST_CREATE_METADATA_READ",
  });
  assertEquals(text.includes(secret), false);
});

Deno.test("Task 13 recovery prerequisite inspection rejects unsafe result projection", async () => {
  const secret = "raw recovery authority or GitHub response";
  let getterCalls = 0;
  const valid = {
    authority_valid: true,
    repository_identity_valid: true,
    state_classification: "ALREADY_COMPLETE",
  };
  const hidden = { ...valid };
  Object.defineProperty(hidden, "raw", { value: secret });
  const symbol = Object.assign({ ...valid }, { [Symbol("raw")]: secret });
  const accessor = { ...valid } as Record<string, unknown>;
  Object.defineProperty(accessor, "state_classification", {
    get: () => {
      getterCalls++;
      return "ALREADY_COMPLETE";
    },
    enumerable: true,
  });
  for (
    const unsafe of [
      {
        ...valid,
        raw: secret,
      },
      Object.assign(Object.create({ raw: secret }), {
        ...valid,
      }),
      hidden,
      symbol,
      accessor,
    ]
  ) {
    const test = dependencies({
      inspectRecoveryPrerequisites: () => Promise.resolve(unsafe),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        recoveryBody,
      ),
      test.value as never,
    );
    const text = await response.text();
    assertEquals(response.status, 502);
    assertEquals(
      JSON.parse(text).code,
      "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
    );
    assertEquals(text.includes(secret), false);
  }
  assertEquals(getterCalls, 0);
});

Deno.test("Task 13 route requires human AAL2 OWNER before execution", async () => {
  for (
    const scenario of [
      {
        claims: { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal1" },
        expected: "AAL2_VERIFICATION",
      },
      {
        claims: {
          sub: SUBJECT,
          exp: NOW / 1000 + 60,
          aal: "aal2",
          role: "service_role",
        },
        expected: "CALLER_VERIFICATION",
      },
    ]
  ) {
    const test = dependencies();
    const response = await handleGitHubTask13TestIsland(
      request(scenario.claims),
      test.value,
    );
    assertEquals(response.status, 403);
    assertEquals((await response.json()).code, scenario.expected);
    assertEquals(test.calls.includes("EXECUTE"), false);
  }

  const denied = dependencies({
    authorizeOwner: () => Promise.reject(new Error("not owner")),
  });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    denied.value,
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "OWNER_AUTHORIZATION");
});

Deno.test("Task 13 route passes only the closed command to server-side execution", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.ok, true);
  assertEquals(test.calls, ["VERIFY_USER", "AUTHORIZE_OWNER", "EXECUTE"]);
  assertEquals(test.executedCommand(), {
    contractVersion: 2,
    websiteWorkspaceId: WORKSPACE_ID,
    websiteWorkContextId: CONTEXT_ID,
    idempotencyKey: IDEMPOTENCY_KEY,
  });
});

Deno.test("Task 13 route exposes one closed OWNER AAL2 LAB reconciliation read", async () => {
  const test = dependencies({
    reconcileReadonly: () => {
      test.calls.push("RECONCILE_READONLY");
      return Promise.resolve({
        principal_type: "GITHUB_APP_INSTALLATION",
        installation_id_match: true,
        private_lab_visibility_proven: true,
        found: false,
      });
    },
  });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      {
        action: "reconcile_task13_lab_repository_readonly",
        website_workspace_id: SYNTHETIC_WORKSPACE_ID,
        website_work_context_id: SYNTHETIC_CONTEXT_ID,
      },
    ),
    test.value,
  );

  assertEquals(response.status, 200);
  assertEquals(test.calls, [
    "VERIFY_USER",
    "AUTHORIZE_OWNER",
    "VERIFY_SYNTHETIC_AUTHORITY",
    "RECONCILE_READONLY",
  ]);
  assertEquals(await response.json(), {
    ok: true,
    code: "TASK13_LAB_RECONCILIATION_READONLY_RESULT",
    result: {
      principal_type: "GITHUB_APP_INSTALLATION",
      installation_id_match: true,
      private_lab_visibility_proven: true,
      found: false,
    },
  });
});

Deno.test("Task 13 readonly authenticates before rejecting wrong synthetic authority", async () => {
  const test = dependencies();
  const response = await handleGitHubTask13TestIsland(
    new Request("https://example.test/github-task13-test-island", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "reconcile_task13_lab_repository_readonly",
        website_work_context_id: "11111111-1111-4111-8111-111111111111",
        website_workspace_id: "22222222-2222-4222-8222-222222222222",
      }),
    }),
    test.value,
  );

  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "CALLER_VERIFICATION");
  assertEquals(test.calls, []);
});

Deno.test("Task 13 readonly reconciliation keeps the human OWNER AAL2 boundary", async () => {
  const body = {
    action: "reconcile_task13_lab_repository_readonly",
    website_workspace_id: SYNTHETIC_WORKSPACE_ID,
    website_work_context_id: SYNTHETIC_CONTEXT_ID,
  };
  const unauthenticated = new Request(
    "https://example.test/github-task13-test-island",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  const noAuth = dependencies();
  let response = await handleGitHubTask13TestIsland(
    unauthenticated,
    noAuth.value,
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "CALLER_VERIFICATION");
  assertEquals(noAuth.calls, []);

  const aal1 = dependencies();
  response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal1" }, body),
    aal1.value,
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "AAL2_VERIFICATION");
  assertEquals(aal1.calls, ["VERIFY_USER"]);

  const nonOwner = dependencies({
    authorizeOwner: () => Promise.reject(new Error("not owner")),
  });
  response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }, body),
    nonOwner.value,
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "OWNER_AUTHORIZATION");
  assertEquals(nonOwner.calls.includes("VERIFY_SYNTHETIC_AUTHORITY"), false);
  assertEquals(nonOwner.calls.includes("RECONCILE_READONLY"), false);
});

Deno.test("Task 13 readonly wrong authority remains hidden from AAL1 and non-OWNER callers", async () => {
  const body = {
    action: "reconcile_task13_lab_repository_readonly",
    website_work_context_id: "11111111-1111-4111-8111-111111111111",
    website_workspace_id: "22222222-2222-4222-8222-222222222222",
  };
  const aal1 = dependencies();
  let response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal1" }, body),
    aal1.value,
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "AAL2_VERIFICATION");
  assertEquals(aal1.calls, ["VERIFY_USER"]);

  const nonOwner = dependencies({
    authorizeOwner: () => {
      nonOwner.calls.push("AUTHORIZE_OWNER");
      return Promise.reject(new Error("not owner"));
    },
  });
  response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }, body),
    nonOwner.value,
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "OWNER_AUTHORIZATION");
  assertEquals(nonOwner.calls, ["VERIFY_USER", "AUTHORIZE_OWNER"]);
});

Deno.test("Task 13 readonly reconciliation accepts only the exact synthetic authority", async () => {
  for (
    const body of [
      {
        action: "reconcile_task13_lab_repository_readonly",
        website_workspace_id: WORKSPACE_ID,
        website_work_context_id: SYNTHETIC_CONTEXT_ID,
      },
      {
        action: "reconcile_task13_lab_repository_readonly",
        website_workspace_id: SYNTHETIC_WORKSPACE_ID,
        website_work_context_id: CONTEXT_ID,
      },
      {
        action: "reconcile_task13_lab_repository_readonly",
        website_workspace_id: WORKSPACE_ID,
        website_work_context_id: CONTEXT_ID,
      },
    ]
  ) {
    const test = dependencies();
    const response = await handleGitHubTask13TestIsland(
      request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }, body),
      test.value,
    );
    assertEquals(response.status, 403);
    assertEquals(
      (await response.json()).code,
      "TASK13_SYNTHETIC_AUTHORITY_INVALID",
    );
    assertEquals(test.calls, ["VERIFY_USER", "AUTHORIZE_OWNER"]);
    assertEquals(test.calls.includes("RECONCILE_READONLY"), false);
  }
});

Deno.test("Task 13 readonly keeps structural validation before authentication", async () => {
  const cases = [
    {
      body: {
        action: "reconcile_task13_lab_repository_readonly",
        website_work_context_id: SYNTHETIC_CONTEXT_ID,
      },
      status: 403,
      code: "TASK13_SYNTHETIC_AUTHORITY_INVALID",
    },
    {
      body: {
        action: "reconcile_task13_lab_repository_readonly",
        website_work_context_id: SYNTHETIC_CONTEXT_ID,
        website_workspace_id: SYNTHETIC_WORKSPACE_ID,
        extra: true,
      },
      status: 403,
      code: "TASK13_SYNTHETIC_AUTHORITY_INVALID",
    },
    {
      body: {
        action: "reconcile_task13_lab_repository_readonly",
        website_work_context_id: "invalid",
        website_workspace_id: SYNTHETIC_WORKSPACE_ID,
      },
      status: 403,
      code: "TASK13_SYNTHETIC_AUTHORITY_INVALID",
    },
    {
      body: {
        action: "unknown",
        website_work_context_id: SYNTHETIC_CONTEXT_ID,
        website_workspace_id: SYNTHETIC_WORKSPACE_ID,
      },
      status: 400,
      code: "INVALID_REQUEST",
    },
  ];
  for (const scenario of cases) {
    const test = dependencies();
    const response = await handleGitHubTask13TestIsland(
      new Request("https://example.test/github-task13-test-island", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(scenario.body),
      }),
      test.value,
    );
    assertEquals(response.status, scenario.status);
    assertEquals((await response.json()).code, scenario.code);
    assertEquals(test.calls, []);
  }
});

Deno.test("Task 13 readonly reconciliation fails before execution when synthetic authority is unproven", async () => {
  const test = dependencies({
    verifySyntheticAuthority: () => Promise.resolve(false),
  });
  const response = await handleGitHubTask13TestIsland(
    request(
      { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
      {
        action: "reconcile_task13_lab_repository_readonly",
        website_workspace_id: SYNTHETIC_WORKSPACE_ID,
        website_work_context_id: SYNTHETIC_CONTEXT_ID,
      },
    ),
    test.value,
  );
  assertEquals(response.status, 403);
  assertEquals(
    (await response.json()).code,
    "TASK13_SYNTHETIC_AUTHORITY_INVALID",
  );
  assertEquals(test.calls.includes("EXECUTE"), false);
});

Deno.test("Task 13 readonly reconciliation rejects every caller authority override", async () => {
  for (
    const extra of [
      { organization: "lorenzo-web-solutions-lab" },
      { repository_name: "lws-web-attacker" },
      { installation_id: "161461160" },
      { repository_ids: ["1"] },
      { permissions: { metadata: "read" } },
      { idempotency_key: IDEMPOTENCY_KEY },
      { token: "synthetic-secret" },
      { operation_id: IDEMPOTENCY_KEY },
    ]
  ) {
    const test = dependencies();
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        {
          action: "reconcile_task13_lab_repository_readonly",
          website_workspace_id: SYNTHETIC_WORKSPACE_ID,
          website_work_context_id: SYNTHETIC_CONTEXT_ID,
          ...extra,
        },
      ),
      test.value,
    );
    assertEquals(response.status, 403);
    assertEquals(
      (await response.json()).code,
      "TASK13_SYNTHETIC_AUTHORITY_INVALID",
    );
    assertEquals(test.calls, []);
  }
});

Deno.test("Task 13 readonly reconciliation exposes only closed failures", async () => {
  const secret =
    "raw token JWT privateKey Authorization stack cause details hint";
  for (
    const error of [
      new Task13LabReadonlyError("TASK13_LAB_PRIVATE_VISIBILITY_UNPROVEN"),
      new Task13LabReadonlyError("TASK13_LAB_RECONCILIATION_TOKEN_FAILED"),
      new Task13LabReadonlyError("TASK13_LAB_RECONCILIATION_READ_FAILED"),
      new Task13LabReadonlyError("TASK13_LAB_RECONCILIATION_RESPONSE_INVALID"),
    ]
  ) {
    Object.assign(error, { raw: secret, cause: secret, details: secret });
    const test = dependencies({
      reconcileReadonly: () => Promise.reject(error),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        {
          action: "reconcile_task13_lab_repository_readonly",
          website_workspace_id: SYNTHETIC_WORKSPACE_ID,
          website_work_context_id: SYNTHETIC_CONTEXT_ID,
        },
      ),
      test.value,
    );
    const text = await response.text();
    assertEquals(response.status, 502);
    assertEquals(JSON.parse(text).code, error.code);
    assertEquals(text.includes(secret), false);
  }
});

Deno.test("Task 13 readonly reconciliation rejects unsafe result projection", async () => {
  const secret = "raw repository response with credential";
  const valid = {
    principal_type: "GITHUB_APP_INSTALLATION",
    installation_id_match: true,
    private_lab_visibility_proven: true,
    found: false,
  } as const;
  for (
    const unsafe of [
      { ...valid, raw: secret },
      { ...valid, diagnostics: { raw: secret } },
      Object.create({ ...valid, raw: secret }),
    ]
  ) {
    const test = dependencies({
      reconcileReadonly: () => Promise.resolve(unsafe as never),
    });
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        {
          action: "reconcile_task13_lab_repository_readonly",
          website_workspace_id: SYNTHETIC_WORKSPACE_ID,
          website_work_context_id: SYNTHETIC_CONTEXT_ID,
        },
      ),
      test.value,
    );
    const text = await response.text();
    assertEquals(response.status, 502);
    assertEquals(
      JSON.parse(text).code,
      "TASK13_LAB_RECONCILIATION_READ_FAILED",
    );
    assertEquals(text.includes(secret), false);
  }
});

Deno.test("Task 13 route rejects caller-controlled provider authority", async () => {
  for (
    const extra of [
      { starter: { source: "attacker/repository" } },
      { repository_name: "attacker" },
      { organization: "lorenzo-web-solutions" },
      { installation_id: "161436785" },
      { token: "synthetic-secret" },
    ]
  ) {
    const test = dependencies();
    const response = await handleGitHubTask13TestIsland(
      request(
        { sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" },
        {
          action: "execute_task13_test_island",
          website_workspace_id: WORKSPACE_ID,
          website_work_context_id: CONTEXT_ID,
          idempotency_key: IDEMPOTENCY_KEY,
          ...extra,
        },
      ),
      test.value,
    );
    assertEquals(response.status, 400);
    assertEquals(test.calls.includes("EXECUTE"), false);
  }
});

Deno.test("Task 13 route rejects and redacts an unexpected execution result", async () => {
  const secret = "ghs_synthetic_secret_token_value";
  const test = dependencies({
    execute: () =>
      Promise.resolve({
        provider: "GITHUB",
        providerRepositoryId: "1369000001",
        providerNodeId: "R_task13_repository",
        owner: "lorenzo-web-solutions-lab",
        name: "lws-web-d2120000000040008000000000000001",
        visibility: "PRIVATE",
        defaultBranch: "main",
        starterSource: "lorenzo-web-solutions/lws-website-starter",
        starterVersion: "1.0.0",
        starterCommitSha: "a".repeat(40),
        repositoryMarkerCommitSha: "b".repeat(40),
        replayed: false,
        token: secret,
      }),
  });

  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  const body = await response.text();

  assertEquals(response.status, 502);
  assertEquals(JSON.parse(body), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
  });
  assertEquals(body.includes(secret), false);
});

Deno.test("Task 13 route exposes only the closed claim diagnostic", async () => {
  const secret = "raw database detail with token and query";
  const test = dependencies({
    execute: () =>
      Promise.reject(
        new RepositoryProvisioningClaimDiagnosticError(
          "CLAIM_RPC_DATABASE_EXCEPTION",
          "23",
        ),
      ),
  });

  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  const text = await response.text();

  assertEquals(response.status, 502);
  assertEquals(JSON.parse(text), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "STORE_CLAIM",
    failed_claim_phase: "CLAIM_RPC_DATABASE_EXCEPTION",
    sqlstate_class: "23",
  });
  assertEquals(text.includes(secret), false);

  const unsafe = dependencies({
    execute: () =>
      Promise.reject(
        new RepositoryProvisioningClaimDiagnosticError(
          "CLAIM_RPC_DATABASE_EXCEPTION",
          "23514" as "23",
        ),
      ),
  });
  const unsafeBody = await (await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    unsafe.value,
  )).json();
  assertEquals("sqlstate_class" in unsafeBody, false);
});

function tokenDiagnostic(
  tokenAcquireSubphase: string,
): GitHubRepositoryProviderError & { tokenAcquireSubphase?: string } {
  const Constructor = GitHubRepositoryProviderError as unknown as new (
    code: "GITHUB_STARTER_SNAPSHOT_INVALID",
    subphase: "STARTER_TOKEN_ACQUIRE",
    tokenSubphase: string,
  ) => GitHubRepositoryProviderError & { tokenAcquireSubphase?: string };
  return new Constructor(
    "GITHUB_STARTER_SNAPSHOT_INVALID",
    "STARTER_TOKEN_ACQUIRE",
    tokenAcquireSubphase,
  );
}

function leaseDiagnostic(
  tokenLeaseCheck: string,
): GitHubRepositoryProviderError & { tokenLeaseCheck?: string } {
  const Constructor = GitHubRepositoryProviderError as unknown as new (
    code: "GITHUB_STARTER_SNAPSHOT_INVALID",
    subphase: "STARTER_TOKEN_ACQUIRE",
    tokenSubphase: "TOKEN_LEASE_VALIDATE",
    leaseCheck: string,
  ) => GitHubRepositoryProviderError & { tokenLeaseCheck?: string };
  return new Constructor(
    "GITHUB_STARTER_SNAPSHOT_INVALID",
    "STARTER_TOKEN_ACQUIRE",
    "TOKEN_LEASE_VALIDATE",
    tokenLeaseCheck,
  );
}

function labTokenDiagnostic(
  tokenAcquireSubphase: string,
  tokenLeaseCheck?: string,
): GitHubRepositoryProviderError {
  const Constructor = GitHubRepositoryProviderError as unknown as new (
    code: "GITHUB_LAB_CREATE_FAILED",
    subphase: "LAB_TOKEN_ACQUIRE",
    tokenSubphase: string,
    leaseCheck?: string,
  ) => GitHubRepositoryProviderError;
  return new Constructor(
    "GITHUB_LAB_CREATE_FAILED",
    "LAB_TOKEN_ACQUIRE",
    tokenAcquireSubphase,
    tokenLeaseCheck,
  );
}

function responseDiagnostic(
  phase: "GITHUB_STARTER_SNAPSHOT_INVALID" | "GITHUB_LAB_CREATE_FAILED",
): GitHubRepositoryProviderError {
  const Constructor = GitHubRepositoryProviderError as unknown as new (
    code: typeof phase,
    subphase: "STARTER_TOKEN_ACQUIRE" | "LAB_TOKEN_ACQUIRE",
    tokenSubphase: "TOKEN_RESPONSE_SCHEMA",
    leaseCheck: undefined,
    responseCheck: "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  ) => GitHubRepositoryProviderError;
  return new Constructor(
    phase,
    phase === "GITHUB_STARTER_SNAPSHOT_INVALID"
      ? "STARTER_TOKEN_ACQUIRE"
      : "LAB_TOKEN_ACQUIRE",
    "TOKEN_RESPONSE_SCHEMA",
    undefined,
    "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  );
}

Deno.test("Task 13 route preserves closed provider and runtime diagnostics", async () => {
  const scenarios = [
    {
      error: new GitHubRepositoryProviderError(
        "GITHUB_STARTER_SNAPSHOT_INVALID",
        "STARTER_TOKEN_ACQUIRE",
      ),
      expected: {
        ok: false,
        code: "TASK13_TEST_ISLAND_FAILED",
        failed_stage: "PROVIDER",
        failed_provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
        failed_provider_subphase: "STARTER_TOKEN_ACQUIRE",
      },
    },
    {
      error: new RepositoryProvisioningRuntimeDiagnosticError(
        "REPOSITORY_BINDING_FAILED",
      ),
      expected: {
        ok: false,
        code: "TASK13_TEST_ISLAND_FAILED",
        failed_stage: "RUNTIME_PROVISION",
        failed_runtime_phase: "REPOSITORY_BINDING_FAILED",
      },
    },
    {
      error: new GitHubRepositoryProviderError(
        "GITHUB_LAB_CREATE_FAILED",
        "LAB_CREATE_HTTP_STATUS",
      ),
      expected: {
        ok: false,
        code: "TASK13_TEST_ISLAND_FAILED",
        failed_stage: "PROVIDER",
        failed_provider_phase: "GITHUB_LAB_CREATE_FAILED",
        failed_provider_subphase: "LAB_CREATE_HTTP_STATUS",
      },
    },
  ] as const;

  for (const scenario of scenarios) {
    const test = dependencies({
      execute: () => Promise.reject(scenario.error),
    });
    const response = await handleGitHubTask13TestIsland(
      request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
      test.value,
    );
    assertEquals(response.status, 502);
    assertEquals(await response.json(), scenario.expected);
  }
});

Deno.test("Task 13 route projects every trusted post-create subphase", async () => {
  for (const subphase of GITHUB_LAB_POST_CREATE_SUBPHASES) {
    const test = dependencies({
      execute: () =>
        Promise.reject(
          new GitHubRepositoryProviderError(
            "GITHUB_LAB_POST_CREATE_FAILED",
            subphase,
          ),
        ),
    });
    const response = await handleGitHubTask13TestIsland(
      request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
      test.value,
    );
    assertEquals(await response.json(), {
      ok: false,
      code: "TASK13_TEST_ISLAND_FAILED",
      failed_stage: "PROVIDER",
      failed_provider_phase: "GITHUB_LAB_POST_CREATE_FAILED",
      failed_provider_subphase: subphase,
    });
  }
});

Deno.test("Task 13 route keeps binding invalid separate from post-create diagnostics", async () => {
  const test = dependencies({
    execute: () =>
      Promise.reject(
        new GitHubRepositoryProviderError("GITHUB_LAB_BINDING_INVALID"),
      ),
  });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_LAB_BINDING_INVALID",
  });
});

Deno.test("Task 13 route denies forged post-create subphases", async () => {
  const forgedValues = [
    Object.assign(
      Object.create(RepositoryProvisioningProviderDiagnosticError.prototype),
      {
        phase: "GITHUB_LAB_POST_CREATE_FAILED",
        subphase: "LAB_POST_CREATE_BLOB_WRITE",
      },
    ),
    {
      phase: "GITHUB_LAB_POST_CREATE_FAILED",
      subphase: "LAB_POST_CREATE_BLOB_WRITE",
    },
  ];
  for (const forged of forgedValues) {
    const test = dependencies({ execute: () => Promise.reject(forged) });
    const body = await (await handleGitHubTask13TestIsland(
      request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
      test.value,
    )).json();
    assertEquals("failed_provider_subphase" in body, false);
  }
});

Deno.test("Task 13 post-create subphase is immutable and exposes no raw fields", async () => {
  const canaries = [
    "raw-error-message-canary",
    "raw-stack-canary",
    "raw-cause-canary",
    "raw-github-response-canary",
    "raw-token-canary",
    "raw-jwt-canary",
    "raw-private-key-canary",
    "raw-authorization-canary",
    "raw-repository-content-canary",
  ];
  const error = new GitHubRepositoryProviderError(
    "GITHUB_LAB_POST_CREATE_FAILED",
    "LAB_POST_CREATE_BLOB_WRITE",
  );
  assertThrows(
    () => Object.assign(error, { subphase: "LAB_POST_CREATE_TREE_WRITE" }),
    TypeError,
  );
  Object.assign(error, {
    rawMessage: canaries[0],
    rawStack: canaries[1],
    cause: canaries[2],
    rawResponse: canaries[3],
    token: canaries[4],
    appJwt: canaries[5],
    privateKey: canaries[6],
    authorization: canaries[7],
    blobData: canaries[8],
  });
  const test = dependencies({ execute: () => Promise.reject(error) });
  const text = await (await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  )).text();
  assertEquals(JSON.parse(text), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_LAB_POST_CREATE_FAILED",
    failed_provider_subphase: "LAB_POST_CREATE_BLOB_WRITE",
  });
  assertEquals(canaries.filter((canary) => text.includes(canary)).length, 0);
});

Deno.test("Task 13 route never projects LAB create detail across provider phases", async () => {
  const error = new GitHubRepositoryProviderError(
    "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
    "LAB_CREATE_HTTP_REQUEST",
  );
  const test = dependencies({ execute: () => Promise.reject(error) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
  });
});

Deno.test("Task 13 route projects one closed token acquire subphase", async () => {
  const test = dependencies({
    execute: () => Promise.reject(tokenDiagnostic("TOKEN_LEASE_VALIDATE")),
  });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
    failed_provider_subphase: "STARTER_TOKEN_ACQUIRE",
    failed_token_acquire_subphase: "TOKEN_LEASE_VALIDATE",
  });
});

Deno.test("Task 13 route projects trusted LAB token and lease diagnostics", async () => {
  const error = labTokenDiagnostic(
    "TOKEN_LEASE_VALIDATE",
    "LEASE_TOKEN_FORMAT_VALIDATE",
  );
  const test = dependencies({ execute: () => Promise.reject(error) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_LAB_CREATE_FAILED",
    failed_provider_subphase: "LAB_TOKEN_ACQUIRE",
    failed_token_acquire_subphase: "TOKEN_LEASE_VALIDATE",
    failed_token_lease_check: "LEASE_TOKEN_FORMAT_VALIDATE",
  });
});

Deno.test("Task 13 route projects trusted LAB non-lease token detail without a lease check", async () => {
  const error = labTokenDiagnostic("TOKEN_HTTP_STATUS");
  const test = dependencies({ execute: () => Promise.reject(error) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_LAB_CREATE_FAILED",
    failed_provider_subphase: "LAB_TOKEN_ACQUIRE",
    failed_token_acquire_subphase: "TOKEN_HTTP_STATUS",
  });
});

Deno.test("Task 13 route projects a trusted response check only for closed token pairings", async () => {
  for (
    const phase of [
      "GITHUB_STARTER_SNAPSHOT_INVALID",
      "GITHUB_LAB_CREATE_FAILED",
    ] as const
  ) {
    const test = dependencies({
      execute: () => Promise.reject(responseDiagnostic(phase)),
    });
    const response = await handleGitHubTask13TestIsland(
      request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
      test.value,
    );
    const body = await response.json();
    assertEquals(body.failed_token_acquire_subphase, "TOKEN_RESPONSE_SCHEMA");
    assertEquals(
      body.failed_token_response_check,
      "TOKEN_SCHEMA_REPOSITORY_SELECTION",
    );
    assertEquals("failed_token_lease_check" in body, false);
  }
});

Deno.test("Task 13 token response checks enforce closed pairing and mutual exclusion", () => {
  const Constructor = GitHubTokenAcquireDiagnosticError as unknown as new (
    message: string,
    tokenAcquireSubphase?: string,
    tokenLeaseCheck?: string,
    tokenResponseCheck?: string,
  ) => GitHubTokenAcquireDiagnosticError;
  for (
    const [subphase, leaseCheck, responseCheck] of [
      ["TOKEN_RESPONSE_SCHEMA", undefined, "FORGED_RESPONSE_CHECK"],
      ["TOKEN_HTTP_STATUS", undefined, "TOKEN_SCHEMA_TOKEN"],
      ["TOKEN_LEASE_VALIDATE", undefined, "TOKEN_SCHEMA_TOKEN"],
      [undefined, undefined, "TOKEN_SCHEMA_TOKEN"],
      [
        "TOKEN_RESPONSE_SCHEMA",
        "LEASE_TOKEN_FORMAT_VALIDATE",
        "TOKEN_SCHEMA_TOKEN",
      ],
    ] as const
  ) {
    assertThrows(
      () => new Constructor("SYNTHETIC", subphase, leaseCheck, responseCheck),
      Error,
    );
  }
});

Deno.test("Task 13 token response checks are immutable", () => {
  const error = responseDiagnostic("GITHUB_LAB_CREATE_FAILED") as unknown as {
    tokenResponseCheck: string;
  };
  assertThrows(
    () => Object.assign(error, { tokenResponseCheck: "TOKEN_SCHEMA_TOKEN" }),
    TypeError,
  );
  assertEquals(
    error.tokenResponseCheck,
    "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  );
});

Deno.test("Task 13 route denies prototype-forged allowlisted response checks", async () => {
  const forged = Object.assign(
    Object.create(RepositoryProvisioningProviderDiagnosticError.prototype),
    {
      phase: "GITHUB_LAB_CREATE_FAILED",
      subphase: "LAB_TOKEN_ACQUIRE",
      tokenAcquireSubphase: "TOKEN_RESPONSE_SCHEMA",
      tokenResponseCheck: "TOKEN_SCHEMA_REPOSITORY_SELECTION",
    },
  );
  const test = dependencies({ execute: () => Promise.reject(forged) });
  const body = await (await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  )).json();
  assertEquals("failed_token_response_check" in body, false);
  assertEquals("failed_token_acquire_subphase" in body, false);
});

Deno.test("Task 13 route never projects response checks across provider phases", async () => {
  const forged = Object.assign(
    Object.create(RepositoryProvisioningProviderDiagnosticError.prototype),
    {
      phase: "GITHUB_LAB_POST_CREATE_FAILED",
      subphase: "LAB_TOKEN_ACQUIRE",
      tokenAcquireSubphase: "TOKEN_RESPONSE_SCHEMA",
      tokenResponseCheck: "TOKEN_SCHEMA_REPOSITORY_SELECTION",
    },
  );
  const test = dependencies({ execute: () => Promise.reject(forged) });
  const body = await (await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  )).json();
  assertEquals("failed_token_response_check" in body, false);
  assertEquals("failed_token_acquire_subphase" in body, false);
});

Deno.test("Task 13 response-check projection exposes no raw token response values", async () => {
  const canaries = [
    "synthetic-token-canary",
    "synthetic-prefix-length-charset-canary",
    "synthetic-expiry-canary",
    "synthetic-permissions-canary",
    "synthetic-repository-selection-canary",
    "synthetic-raw-response-canary",
    "synthetic-message-stack-cause-details-hint-canary",
    "synthetic-authorization-jwt-private-key-canary",
  ];
  const error = responseDiagnostic("GITHUB_LAB_CREATE_FAILED");
  Object.assign(error, {
    token: canaries[0],
    tokenMetadata: canaries[1],
    expiry: canaries[2],
    permissions: canaries[3],
    repositorySelection: canaries[4],
    rawResponse: canaries[5],
    cause: {
      message: canaries[6],
      stack: canaries[6],
      details: canaries[6],
      hint: canaries[6],
    },
    authorization: canaries[7],
    appJwt: canaries[7],
    privateKey: canaries[7],
  });
  const test = dependencies({ execute: () => Promise.reject(error) });
  const text = await (await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  )).text();
  assertEquals(
    canaries.filter((canary) => text.includes(canary)).length,
    0,
  );
  assertEquals(
    JSON.parse(text).failed_token_response_check,
    "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  );
});

Deno.test("Task 13 route projects each closed token lease check", async () => {
  for (
    const tokenLeaseCheck of [
      "LEASE_TOKEN_FORMAT_VALIDATE",
      "LEASE_EXPIRY_LOWER_BOUND",
      "LEASE_EXPIRY_UPPER_BOUND",
    ]
  ) {
    const test = dependencies({
      execute: () => Promise.reject(leaseDiagnostic(tokenLeaseCheck)),
    });
    const response = await handleGitHubTask13TestIsland(
      request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
      test.value,
    );
    assertEquals(await response.json(), {
      ok: false,
      code: "TASK13_TEST_ISLAND_FAILED",
      failed_stage: "PROVIDER",
      failed_provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
      failed_provider_subphase: "STARTER_TOKEN_ACQUIRE",
      failed_token_acquire_subphase: "TOKEN_LEASE_VALIDATE",
      failed_token_lease_check: tokenLeaseCheck,
    });
  }
});

Deno.test("Task 13 token lease check is immutable", () => {
  const error = leaseDiagnostic("LEASE_TOKEN_FORMAT_VALIDATE");
  assertThrows(
    () => Object.assign(error, { tokenLeaseCheck: "LEASE_EXPIRY_LOWER_BOUND" }),
    TypeError,
  );
  assertEquals(error.tokenLeaseCheck, "LEASE_TOKEN_FORMAT_VALIDATE");
});

Deno.test("Task 13 rejects an unknown token lease check", () => {
  assertThrows(
    () => leaseDiagnostic("FORGED_LEASE_CHECK"),
    Error,
    "GITHUB_TOKEN_LEASE_DIAGNOSTIC_INVALID",
  );
});

Deno.test("Task 13 route omits a prototype-forged token lease check", async () => {
  const forged = Object.assign(
    Object.create(RepositoryProvisioningProviderDiagnosticError.prototype),
    {
      phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
      subphase: "STARTER_TOKEN_ACQUIRE",
      tokenAcquireSubphase: "TOKEN_LEASE_VALIDATE",
      tokenLeaseCheck: "FORGED_LEASE_CHECK",
    },
  );
  const test = dependencies({ execute: () => Promise.reject(forged) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
    failed_provider_subphase: "STARTER_TOKEN_ACQUIRE",
  });
});

Deno.test("Task 13 route denies a prototype-forged allowlisted token lease check", async () => {
  const forged = Object.assign(
    Object.create(RepositoryProvisioningProviderDiagnosticError.prototype),
    {
      phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
      subphase: "STARTER_TOKEN_ACQUIRE",
      tokenAcquireSubphase: "TOKEN_LEASE_VALIDATE",
      tokenLeaseCheck: "LEASE_TOKEN_FORMAT_VALIDATE",
    },
  );
  const test = dependencies({ execute: () => Promise.reject(forged) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
    failed_provider_subphase: "STARTER_TOKEN_ACQUIRE",
  });
});

Deno.test("Task 13 token acquire subphase is immutable", () => {
  const error = tokenDiagnostic("TOKEN_LEASE_VALIDATE");
  assertThrows(
    () => Object.assign(error, { tokenAcquireSubphase: "TOKEN_JSON_PARSE" }),
    TypeError,
  );
  assertEquals(error.tokenAcquireSubphase, "TOKEN_LEASE_VALIDATE");
});

Deno.test("Task 13 rejects an unknown token acquire subphase", () => {
  assertThrows(
    () => tokenDiagnostic("FORGED_TOKEN_STAGE"),
    Error,
    "GITHUB_TOKEN_ACQUIRE_DIAGNOSTIC_INVALID",
  );
});

Deno.test("Task 13 route omits a prototype-forged token acquire subphase", async () => {
  const forged = Object.assign(
    Object.create(RepositoryProvisioningProviderDiagnosticError.prototype),
    {
      phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
      subphase: "STARTER_TOKEN_ACQUIRE",
      tokenAcquireSubphase: "FORGED_TOKEN_STAGE",
    },
  );
  const test = dependencies({ execute: () => Promise.reject(forged) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
    failed_provider_subphase: "STARTER_TOKEN_ACQUIRE",
  });
});

Deno.test("Task 13 route omits a prototype-forged LAB create subphase", async () => {
  const forged = Object.assign(
    Object.create(RepositoryProvisioningProviderDiagnosticError.prototype),
    {
      phase: "GITHUB_LAB_CREATE_FAILED",
      subphase: "LAB_CREATE_HTTP_STATUS",
    },
  );
  const test = dependencies({ execute: () => Promise.reject(forged) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_LAB_CREATE_FAILED",
  });
});

Deno.test("Task 13 route omits prototype-forged LAB token diagnostics", async () => {
  const forged = Object.assign(
    Object.create(RepositoryProvisioningProviderDiagnosticError.prototype),
    {
      phase: "GITHUB_LAB_CREATE_FAILED",
      subphase: "LAB_TOKEN_ACQUIRE",
      tokenAcquireSubphase: "TOKEN_LEASE_VALIDATE",
      tokenLeaseCheck: "LEASE_TOKEN_FORMAT_VALIDATE",
    },
  );
  const test = dependencies({ execute: () => Promise.reject(forged) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  assertEquals(await response.json(), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_LAB_CREATE_FAILED",
  });
});

Deno.test("Task 13 LAB token diagnostics are immutable and redact raw fields", async () => {
  const secret =
    "raw LAB token JWT privateKey Authorization stack cause details hint";
  const error = labTokenDiagnostic(
    "TOKEN_LEASE_VALIDATE",
    "LEASE_TOKEN_FORMAT_VALIDATE",
  );
  assertThrows(
    () => Object.assign(error, { tokenAcquireSubphase: "TOKEN_HTTP_STATUS" }),
    TypeError,
  );
  assertThrows(
    () => Object.assign(error, { tokenLeaseCheck: "LEASE_EXPIRY_UPPER_BOUND" }),
    TypeError,
  );
  Object.assign(error, {
    rawMessage: secret,
    details: secret,
    hint: secret,
    cause: secret,
    token: secret,
    authorization: secret,
    privateKey: secret,
  });
  const test = dependencies({ execute: () => Promise.reject(error) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  const text = await response.text();
  assertEquals(JSON.parse(text), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_LAB_CREATE_FAILED",
    failed_provider_subphase: "LAB_TOKEN_ACQUIRE",
    failed_token_acquire_subphase: "TOKEN_LEASE_VALIDATE",
    failed_token_lease_check: "LEASE_TOKEN_FORMAT_VALIDATE",
  });
  assertEquals(text.includes(secret), false);
});

Deno.test("Task 13 route projects no raw provider diagnostic fields", async () => {
  const secret =
    "raw message stack details hint cause JWT private key Authorization";
  const error = new GitHubRepositoryProviderError(
    "GITHUB_STARTER_SNAPSHOT_INVALID",
    "STARTER_BLOB_VALIDATE",
  );
  Object.assign(error, {
    rawMessage: secret,
    details: secret,
    hint: secret,
    cause: secret,
    token: secret,
    authorization: secret,
    privateKey: secret,
  });
  const test = dependencies({ execute: () => Promise.reject(error) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  const text = await response.text();
  assertEquals(JSON.parse(text), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
    failed_provider_subphase: "STARTER_BLOB_VALIDATE",
  });
  assertEquals(text.includes(secret), false);
});

Deno.test("Task 13 route denies a provider subphase forged after construction", async () => {
  const secret = "forged raw provider subphase";
  const error = new GitHubRepositoryProviderError(
    "GITHUB_STARTER_SNAPSHOT_INVALID",
    "STARTER_TREE_READ",
  );
  assertThrows(() => Object.assign(error, { subphase: secret }), TypeError);
  const test = dependencies({ execute: () => Promise.reject(error) });
  const response = await handleGitHubTask13TestIsland(
    request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
    test.value,
  );
  const text = await response.text();
  assertEquals(JSON.parse(text), {
    ok: false,
    code: "TASK13_TEST_ISLAND_FAILED",
    failed_stage: "PROVIDER",
    failed_provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
    failed_provider_subphase: "STARTER_TREE_READ",
  });
  assertEquals(text.includes(secret), false);
});

Deno.test("Task 13 provider diagnostic denies mutation to another closed subphase", async () => {
  const error = new GitHubRepositoryProviderError(
    "GITHUB_STARTER_SNAPSHOT_INVALID",
    "STARTER_TREE_READ",
  );
  assertThrows(
    () => Object.assign(error, { subphase: "STARTER_TOKEN_ACQUIRE" }),
    TypeError,
  );
  assertEquals(error.subphase, "STARTER_TREE_READ");
});

Deno.test("Task 13 route rejects forged diagnostic phases without disclosure", async () => {
  const secret = "raw diagnostic detail with credential";
  const factories = [
    () =>
      new RepositoryProvisioningClaimDiagnosticError(
        secret as "CLAIM_RPC_INVOCATION",
      ),
    () =>
      new GitHubRepositoryProviderError(
        secret as "GITHUB_STARTER_SNAPSHOT_INVALID",
      ),
    () =>
      new GitHubRepositoryProviderError(
        "GITHUB_STARTER_SNAPSHOT_INVALID",
        secret as never,
      ),
    () =>
      new RepositoryProvisioningRuntimeDiagnosticError(
        secret as "REPOSITORY_BINDING_FAILED",
      ),
    () =>
      new RepositoryPreclaimDiagnosticError(
        secret as "RUNTIME_PROVISION_INVOCATION",
      ),
  ];

  for (const factory of factories) {
    const test = dependencies({
      execute: () => Promise.reject(factory()),
    });
    const response = await handleGitHubTask13TestIsland(
      request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
      test.value,
    );
    const text = await response.text();
    assertEquals(response.status, 502);
    assertEquals(JSON.parse(text), {
      ok: false,
      code: "TASK13_TEST_ISLAND_FAILED",
      failed_stage: "PRE_CLAIM",
      failed_preclaim_phase: "UNKNOWN_PRECLAIM_ERROR",
    });
    assertEquals(text.includes(secret), false);
  }
});

Deno.test("Task 13 route exposes only closed pre-claim diagnostics", async () => {
  const secret = "private key and raw stack";
  for (
    const phase of [
      "RUNTIME_CONFIG_LOAD",
      "STARTER_PROVENANCE_LOAD",
      "GITHUB_APP_SIGNER_INIT",
      "PRODUCTION_TOKEN_BROKER_INIT",
      "LAB_TOKEN_BROKER_INIT",
      "STORE_ADAPTER_INIT",
      "PROVIDER_INIT",
      "RUNTIME_ASSEMBLY",
      "COMMAND_VALIDATION",
      "RUNTIME_PROVISION_INVOCATION",
      "UNKNOWN_PRECLAIM_ERROR",
    ] as const
  ) {
    const test = dependencies({
      execute: () =>
        Promise.reject(new RepositoryPreclaimDiagnosticError(phase)),
    });
    const response = await handleGitHubTask13TestIsland(
      request({ sub: SUBJECT, exp: NOW / 1000 + 60, aal: "aal2" }),
      test.value,
    );
    const text = await response.text();
    assertEquals(response.status, 502);
    assertEquals(JSON.parse(text), {
      ok: false,
      code: "TASK13_TEST_ISLAND_FAILED",
      failed_stage: "PRE_CLAIM",
      failed_preclaim_phase: phase,
    });
    assertEquals(text.includes(secret), false);
  }
});

import {
  assert,
  assertEquals,
  assertMatch,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";
import { GitHubHttpError } from "./github-http.ts";
import { GitHubTokenBrokerError, type GitHubTokenBrokerCode, type GitHubTokenExchangeHttpClass } from "./github-app-token.ts";
import type { GitHubTokenAcquireSubphase } from "./repository-provisioning-diagnostics.ts";
import { computeGitHubSnapshotDigest } from "./github-snapshot-digest.ts";
import {
  createProductionRepositoryRecovery,
  productionRepositoryRecoveryDiagnosticCode,
  productionRepositoryRecoveryFailureLog,
  ProductionRepositoryRecoveryStageError,
  withProductionRepositoryRecoveryFailureLogging,
} from "./production-repository-recovery.ts";

const source = await Deno.readTextFile(
  new URL("./production-repository-recovery.ts", import.meta.url),
);

Deno.test("production recovery graph has zero repository creation calls", () => {
  assertEquals(source.match(/CREATE_REPOSITORY/g)?.length ?? 0, 0);
  assert(!source.includes("github-repository-runtime.ts"));
  assert(!source.includes("github-repository-provider.ts"));
  assertMatch(source, /"PRODUCTION_REPOSITORY_WRITE"/);
  assert(!source.includes('"LAB_REPOSITORY_WRITE"'));
});

Deno.test("production recovery authority accepts no browser operation or retry identity", () => {
  const authorityCall = source.match(
    /"get_production_website_repository_recovery_authority_v1"[\s\S]*?\}\),/,
  )?.[0] ?? "";
  assertMatch(authorityCall, /p_quote_request_id/);
  assertMatch(authorityCall, /p_website_work_context_id/);
  assertMatch(authorityCall, /p_website_workspace_id/);
  assert(!authorityCall.includes("p_operation_id"));
  assert(!authorityCall.includes("idempotency"));
});

Deno.test("production empty-repository recovery runtime makes zero create-repository calls", async () => {
  const operations: string[] = [];
  const tokenRequests: unknown[] = [];
  const contextId = "e1300000-0000-4000-8000-000000000002";
  const repository = `lws-web-${contextId.replaceAll("-", "")}`;
  const recovery = createProductionRepositoryRecovery({
    config: Object.freeze({
      enabled: true as const,
      target: "PRODUCTION" as const,
      appId: "1",
      installationId: "161436785",
      organization: "lorenzo-web-solutions",
      templateOwner: "lorenzo-web-solutions",
      templateName: "lws-website-starter",
      templateRepositoryId: "1369007000",
      starterVersion: "1.0.0",
      starterCommitSha: "1".repeat(40),
      starterTreeSha256: "2".repeat(64),
      privateKey: "test-only",
    }),
    actor: Object.freeze({
      authUserId: "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0",
      aal: "aal2" as const,
    }),
    callerRpc: () => Promise.resolve({
      data: {
        operation_id: "e1500000-0000-4000-8000-000000000002",
        website_work_context_id: contextId,
        website_workspace_id: "e1400000-0000-4000-8000-000000000002",
        repository_external_id: "1369007102",
        repository_node_id: "R_production_recovery_guard",
        repository_owner: "lorenzo-web-solutions",
        repository_name: repository,
        starter_source: "lorenzo-web-solutions/lws-website-starter",
        starter_version: "1.0.0",
        starter_commit_sha: "1".repeat(40),
      },
      error: null,
    }),
    serviceRpc: () => Promise.reject(new Error("must not finalize")),
    tokenBroker: {
      issue: (_config, request) => {
        tokenRequests.push(request);
        return Promise.resolve({
        token: `ghs_${"a".repeat(36)}`,
        expiresAt: "2099-01-01T00:00:00.000Z",
        permissions: Object.freeze({}),
        });
      },
    },
    http: {
      execute: (operation) => {
        operations.push(operation.kind);
        if (operation.kind === "READ_REF") {
          return Promise.reject(new GitHubHttpError("GITHUB_HTTP_NOT_FOUND"));
        }
        if (operation.kind === "REPOSITORY_METADATA") {
          if (operation.repository === "lws-website-starter") {
            return Promise.reject(new Error("stop before snapshot write"));
          }
          return Promise.resolve({
            repositoryId: "1369007102",
            nodeId: "R_production_recovery_guard",
            owner: "lorenzo-web-solutions",
            name: repository,
            fullName: `lorenzo-web-solutions/${repository}`,
            private: true,
            defaultBranch: "main",
            description: null,
            createdAt: "2026-09-20T00:00:00.000Z",
          });
        }
        return Promise.reject(new Error("unexpected operation"));
      },
    },
  });

  await assertRejects(() => recovery.recover({
    quoteRequestId: "e1100000-0000-4000-8000-000000000002",
    websiteWorkContextId: contextId,
    websiteWorkspaceId: "e1400000-0000-4000-8000-000000000002",
  }));
  assert(operations.includes("READ_REF"));
  assert(operations.includes("REPOSITORY_METADATA"));
  assertEquals(operations.filter((kind) => kind === "CREATE_REPOSITORY").length, 0);
  assertEquals(tokenRequests[0], {
    websiteWorkContextId: contextId,
    target: "PRODUCTION",
    organization: "lorenzo-web-solutions",
    operation: "PRODUCTION_REPOSITORY_READ",
    repositoryIds: ["1369007102"],
  });
});

const QUOTE_ID = "e1110000-0000-4000-8000-000000000002";
const CONTEXT_ID = "e1300000-0000-4000-8000-000000000002";
const WORKSPACE_ID = "e1400000-0000-4000-8000-000000000002";
const OPERATION_ID = "e1500000-0000-4000-8000-000000000002";
const REPOSITORY_ID = "1369007102";
const REPOSITORY_NODE_ID = "R_production_recovery_guard";
const OWNER = "lorenzo-web-solutions";
const REPOSITORY = `lws-web-${CONTEXT_ID.replaceAll("-", "")}`;
const STARTER_COMMIT = "1".repeat(40);
const TARGET_COMMIT = "3".repeat(40);
const TREE_SHA = "4".repeat(40);
const BLOB_SHA = "5".repeat(40);
const TOKEN = `ghs_${"a".repeat(36)}`;
const STARTER_CONTENT = new TextEncoder().encode("approved starter\n");

type RecoveryState =
  | "EMPTY_OR_UNINITIALIZED"
  | "MARKER_MISSING"
  | "ALREADY_COMPLETE"
  | "CONFLICT";

type HarnessOptions = Readonly<{
  authorityOverrides?: Readonly<Record<string, unknown>>;
  callerError?: unknown;
  callerRpcThrows?: boolean;
  networkReadFailure?: boolean;
  writeFailure?: boolean;
  readbackFailure?: boolean;
  replay?: boolean;
  tokenIssueFailsFor?: "STARTER_SNAPSHOT_READ" | "PRODUCTION_REPOSITORY_WRITE" | "PRODUCTION_REPOSITORY_READ";
  tokenIssueFailsWith?: GitHubTokenBrokerCode;
  tokenIssueFailsWithSubphase?: GitHubTokenAcquireSubphase;
  tokenIssueFailsWithHttpClass?: GitHubTokenExchangeHttpClass;
  starterMetadataMismatch?: boolean;
  createTreeFailure?: boolean;
  finalizeError?: unknown;
}>;

function expectedMarker(treeDigest: string): string {
  return `${JSON.stringify({
    schema_version: 1,
    environment: "PRODUCTION",
    organization: OWNER,
    website_work_context_id: CONTEXT_ID,
    repository_provisioning_operation_id: OPERATION_ID,
    starter_source: `${OWNER}/lws-website-starter`,
    starter_version: "v1.0.0",
    starter_commit_sha: STARTER_COMMIT,
    starter_tree_sha256: treeDigest,
  }, null, 2)}\n`;
}

function encoded(content: Uint8Array): string {
  let binary = "";
  for (const byte of content) binary += String.fromCharCode(byte);
  return btoa(binary);
}

async function recoveryHarness(
  initialState: RecoveryState,
  options: HarnessOptions = {},
) {
  const starterTreeSha256 = await computeGitHubSnapshotDigest([{
    path: "README.md",
    mode: "100644",
    type: "blob",
    content: STARTER_CONTENT,
  }]);
  const marker = expectedMarker(starterTreeSha256);
  const operations: string[] = [];
  const tokenRequests: unknown[] = [];
  const serviceCalls: unknown[] = [];
  let initialized = initialState !== "EMPTY_OR_UNINITIALIZED";
  let markerPresent = initialState === "ALREADY_COMPLETE";
  let readRefCalls = 0;

  const authority = {
    operation_id: OPERATION_ID,
    website_work_context_id: CONTEXT_ID,
    website_workspace_id: WORKSPACE_ID,
    repository_external_id: REPOSITORY_ID,
    repository_node_id: REPOSITORY_NODE_ID,
    repository_owner: OWNER,
    repository_name: REPOSITORY,
    starter_source: `${OWNER}/lws-website-starter`,
    starter_version: "1.0.0",
    starter_commit_sha: STARTER_COMMIT,
    ...options.authorityOverrides,
  };
  const recovery = createProductionRepositoryRecovery({
    config: Object.freeze({
      enabled: true as const,
      target: "PRODUCTION" as const,
      appId: "1",
      installationId: "161436785",
      organization: OWNER,
      templateOwner: OWNER,
      templateName: "lws-website-starter",
      templateRepositoryId: "1369007000",
      starterVersion: "1.0.0",
      starterCommitSha: STARTER_COMMIT,
      starterTreeSha256,
      privateKey: "test-only",
    }),
    actor: Object.freeze({
      authUserId: "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0",
      aal: "aal2" as const,
    }),
    callerRpc: () => {
      if (options.callerRpcThrows) {
        return Promise.reject(new Error("authority rpc network failure with sensitive detail"));
      }
      return Promise.resolve({
        data: authority,
        error: options.callerError ?? null,
      });
    },
    serviceRpc: (name, parameters) => {
      serviceCalls.push({ name, parameters });
      if (options.finalizeError !== undefined) {
        return Promise.resolve({ data: null, error: options.finalizeError });
      }
      return Promise.resolve({
        data: { replayed: options.replay === true },
        error: null,
      });
    },
    tokenBroker: {
      issue: (_config, request) => {
        tokenRequests.push(request);
        if (options.tokenIssueFailsFor === request.operation) {
          return Promise.reject(
            options.tokenIssueFailsWith !== undefined
              ? new GitHubTokenBrokerError(
                options.tokenIssueFailsWith,
                options.tokenIssueFailsWithSubphase,
                undefined,
                undefined,
                options.tokenIssueFailsWithHttpClass,
              )
              : new Error("token exchange failed with sensitive installation detail"),
          );
        }
        return Promise.resolve({
          token: TOKEN,
          expiresAt: "2099-01-01T00:00:00.000Z",
          permissions: Object.freeze({}),
        });
      },
    },
    http: {
      execute: async (operation) => {
        operations.push(operation.kind);
        if (operation.kind === "REPOSITORY_METADATA") {
          if (options.networkReadFailure && operation.repository === REPOSITORY) {
            throw new Error("network unavailable");
          }
          if (operation.repository === "lws-website-starter") {
            if (options.starterMetadataMismatch) {
              return {
                repositoryId: "9999999999",
                nodeId: "R_wrong_starter_repository",
                owner: OWNER,
                name: "lws-website-starter",
                fullName: `${OWNER}/lws-website-starter`,
                private: true,
                defaultBranch: "main",
                description: null,
                createdAt: "2026-09-20T00:00:00.000Z",
              };
            }
            return {
              repositoryId: "1369007000",
              nodeId: "R_starter_repository",
              owner: OWNER,
              name: "lws-website-starter",
              fullName: `${OWNER}/lws-website-starter`,
              private: true,
              defaultBranch: "main",
              description: null,
              createdAt: "2026-09-20T00:00:00.000Z",
            };
          }
          return {
            repositoryId: REPOSITORY_ID,
            nodeId: REPOSITORY_NODE_ID,
            owner: OWNER,
            name: REPOSITORY,
            fullName: `${OWNER}/${REPOSITORY}`,
            private: true,
            defaultBranch: "main",
            description: null,
            createdAt: "2026-09-20T00:00:00.000Z",
          };
        }
        if (operation.kind === "READ_REF") {
          readRefCalls++;
          if (options.readbackFailure && readRefCalls > 1) {
            throw new Error("readback unavailable");
          }
          if (!initialized) {
            throw new GitHubHttpError(
              "GITHUB_HTTP_NOT_FOUND",
              null,
              null,
              undefined,
              "HTTP_STATUS",
              undefined,
              404,
            );
          }
          return { ref: "refs/heads/main", commitSha: TARGET_COMMIT };
        }
        if (operation.kind === "COMMIT_METADATA") {
          return { sha: TARGET_COMMIT, treeSha: TREE_SHA };
        }
        if (operation.kind === "REPOSITORY_TREE") {
          return {
            sha: operation.repository === "lws-website-starter"
              ? STARTER_COMMIT
              : TREE_SHA,
            truncated: false,
            entries: [{
              path: "README.md",
              mode: "100644",
              type: "blob",
              sha: BLOB_SHA,
            }],
          };
        }
        if (operation.kind === "READ_BLOB") {
          const content = initialState === "CONFLICT" &&
              operation.repository === REPOSITORY
            ? new TextEncoder().encode("unexpected content\n")
            : STARTER_CONTENT;
          return {
            sha: BLOB_SHA,
            encoding: "base64",
            contentBase64: encoded(content),
            size: content.byteLength,
          };
        }
        if (operation.kind === "READ_PROJECT_MARKER") {
          if (!markerPresent) {
            throw new GitHubHttpError(
              "GITHUB_HTTP_NOT_FOUND",
              null,
              null,
              undefined,
              "HTTP_STATUS",
              undefined,
              404,
            );
          }
          const content = new TextEncoder().encode(marker);
          return {
            path: ".lws/project.json",
            sha: "6".repeat(40),
            encoding: "base64",
            contentBase64: encoded(content),
            size: content.byteLength,
          };
        }
        if (operation.kind === "WRITE_PROJECT_MARKER") {
          if (options.writeFailure) throw new Error("write unavailable");
          markerPresent = true;
          return { contentSha: "6".repeat(40), commitSha: TARGET_COMMIT };
        }
        if (operation.kind === "CREATE_BOOTSTRAP_FILE") {
          return {
            path: ".lws/bootstrap.json",
            contentSha: "7".repeat(40),
            commitSha: "8".repeat(40),
            parentCount: 0,
          };
        }
        if (operation.kind === "CREATE_BLOB") return { sha: BLOB_SHA };
        if (operation.kind === "CREATE_TREE") {
          if (options.createTreeFailure) {
            throw new Error("create tree failure with sensitive provider detail");
          }
          return { sha: TREE_SHA };
        }
        if (operation.kind === "CREATE_COMMIT") return { sha: TARGET_COMMIT };
        if (operation.kind === "UPDATE_REF") {
          initialized = true;
          return { ref: "refs/heads/main", commitSha: TARGET_COMMIT };
        }
        throw new Error(`unexpected ${operation.kind}`);
      },
    },
  });
  return {
    recovery,
    operations,
    tokenRequests,
    serviceCalls,
    input: {
      quoteRequestId: QUOTE_ID,
      websiteWorkContextId: CONTEXT_ID,
      websiteWorkspaceId: WORKSPACE_ID,
    },
  };
}

function assertZeroCreate(operations: readonly string[]): void {
  assertEquals(
    operations.filter((operation) => operation === "CREATE_REPOSITORY").length,
    0,
  );
}

for (const [state, status] of [
  ["EMPTY_OR_UNINITIALIZED", "RECOVERED_FROM_EMPTY"],
  ["MARKER_MISSING", "RECOVERED_MARKER_ONLY"],
  ["ALREADY_COMPLETE", "ALREADY_COMPLETE"],
] as const) {
  Deno.test(`production recovery handles ${state} with zero repository creates`, async () => {
    const test = await recoveryHarness(state);
    assertEquals((await test.recovery.recover(test.input)).status, status);
    assertEquals(test.serviceCalls.length, 1);
    assertZeroCreate(test.operations);
  });
}

Deno.test("production recovery rejects CONFLICT with zero repository creates", async () => {
  const test = await recoveryHarness("CONFLICT");
  await assertRejects(() => test.recovery.recover(test.input));
  assertEquals(test.serviceCalls.length, 0);
  assertZeroCreate(test.operations);
});

Deno.test("production recovery finalization replay uses zero repository creates", async () => {
  const test = await recoveryHarness("ALREADY_COMPLETE", { replay: true });
  const result = await test.recovery.recover(test.input);
  assertEquals(result.binding, { replayed: true });
  assertZeroCreate(test.operations);
});

for (const [name, options, inputOverrides] of [
  ["malformed authority", { authorityOverrides: { operation_id: "invalid" } }, {}],
  ["wrong dossier", { callerError: { code: "DOSSIER_MISMATCH" } }, {}],
  ["OWNER denial", { callerError: { code: "OWNER_REQUIRED" } }, {}],
  ["AAL2 denial", { callerError: { code: "AAL2_REQUIRED" } }, {}],
  ["wrong work context", { authorityOverrides: { website_work_context_id: "e1300000-0000-4000-8000-000000000099" } }, {}],
  ["wrong workspace", { authorityOverrides: { website_workspace_id: "e1400000-0000-4000-8000-000000000099" } }, {}],
  ["wrong external repository identity", { authorityOverrides: { repository_external_id: "1369007999" } }, {}],
] as const) {
  Deno.test(`production recovery rejects ${name} with zero repository creates`, async () => {
    const test = await recoveryHarness("ALREADY_COMPLETE", options);
    await assertRejects(() => test.recovery.recover({ ...test.input, ...inputOverrides }));
    assertZeroCreate(test.operations);
  });
}

Deno.test("production recovery rejects malformed composition with zero repository creates", () => {
  assertThrows(() => createProductionRepositoryRecovery({} as never));
});

Deno.test("production recovery rejects non-AAL2 composition with zero repository creates", async () => {
  const test = await recoveryHarness("ALREADY_COMPLETE");
  const dependencies = {
    config: { target: "PRODUCTION", organization: OWNER },
    actor: {
      authUserId: "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0",
      aal: "aal1",
    },
  };
  assertThrows(() => createProductionRepositoryRecovery(dependencies as never));
  assertZeroCreate(test.operations);
});

const STAGE_FAILURE_SCENARIOS = [
  ["network read failure", { networkReadFailure: true }, "REPOSITORY_INSPECT"],
  ["write failure", { writeFailure: true }, "MARKER_WRITE"],
  ["readback failure", { readbackFailure: true }, "COMPLETION_PROOF"],
] as const;

for (const [name, options, expectedStage] of STAGE_FAILURE_SCENARIOS) {
  Deno.test(`production recovery ${name} retains zero repository creates`, async () => {
    const state = name === "network read failure"
      ? "ALREADY_COMPLETE"
      : "MARKER_MISSING";
    const test = await recoveryHarness(state, options);
    const error = await assertRejects(() => test.recovery.recover(test.input));
    assertZeroCreate(test.operations);
    assert(error instanceof ProductionRepositoryRecoveryStageError);
    assertEquals(error.stage, expectedStage);
  });
}

// ==========================================================================
// Recovery stage diagnostic classification (backend observability fix)
// ==========================================================================
//
// Every distinct recovery failure point must classify to exactly one
// pre-approved, sanitized diagnostic code. The underlying raw exception
// (which may carry network/provider detail) must never be observable in the
// resulting error, in server logs, or in the code returned to the caller.

const STAGE_DIAGNOSTIC_SCENARIOS: ReadonlyArray<
  readonly [string, "EMPTY_OR_UNINITIALIZED" | "MARKER_MISSING" | "ALREADY_COMPLETE", HarnessOptions, string, string]
> = [
  [
    "authority RPC transport failure",
    "ALREADY_COMPLETE",
    { callerRpcThrows: true },
    "AUTHORITY_RPC",
    "PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_FAILED",
  ],
  [
    "authority RPC application error",
    "ALREADY_COMPLETE",
    { callerError: { code: "SOME_DATABASE_ERROR" } },
    "AUTHORITY_RPC",
    "PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_FAILED",
  ],
  [
    "authority shape invalid",
    "ALREADY_COMPLETE",
    { authorityOverrides: { operation_id: "not-a-uuid" } },
    "AUTHORITY_VALIDATE",
    "PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_INVALID",
  ],
  [
    "target write token acquisition failure",
    "EMPTY_OR_UNINITIALIZED",
    { tokenIssueFailsFor: "PRODUCTION_REPOSITORY_WRITE" },
    "TARGET_TOKEN_ACQUIRE",
    "PRODUCTION_REPOSITORY_RECOVERY_TARGET_TOKEN_FAILED",
  ],
  [
    "starter template token acquisition failure",
    "EMPTY_OR_UNINITIALIZED",
    { tokenIssueFailsFor: "STARTER_SNAPSHOT_READ" },
    "STARTER_TOKEN_ACQUIRE",
    "PRODUCTION_REPOSITORY_RECOVERY_STARTER_TOKEN_FAILED",
  ],
  [
    "starter snapshot identity mismatch",
    "EMPTY_OR_UNINITIALIZED",
    { starterMetadataMismatch: true },
    "STARTER_SNAPSHOT_READ",
    "PRODUCTION_REPOSITORY_RECOVERY_SNAPSHOT_FAILED",
  ],
  [
    "empty repository initialize failure",
    "EMPTY_OR_UNINITIALIZED",
    { createTreeFailure: true },
    "EMPTY_REPOSITORY_INITIALIZE",
    "PRODUCTION_REPOSITORY_RECOVERY_INITIALIZE_FAILED",
  ],
  [
    "finalize RPC application error",
    "ALREADY_COMPLETE",
    { finalizeError: { code: "SOME_DATABASE_ERROR" } },
    "FINALIZE_RPC",
    "PRODUCTION_REPOSITORY_RECOVERY_FINALIZE_FAILED",
  ],
];

for (const [name, state, options, expectedStage, expectedCode] of STAGE_DIAGNOSTIC_SCENARIOS) {
  Deno.test(`production recovery ${name} classifies to ${expectedStage}`, async () => {
    const test = await recoveryHarness(state, options);
    const error = await assertRejects(() => test.recovery.recover(test.input));
    assertZeroCreate(test.operations);
    assert(error instanceof ProductionRepositoryRecoveryStageError);
    assertEquals(error.stage, expectedStage);
    assertEquals(error.message, expectedCode);
  });
}

Deno.test("production recovery CONFLICT state classifies to REPOSITORY_INSPECT", async () => {
  const test = await recoveryHarness("CONFLICT");
  const error = await assertRejects(() => test.recovery.recover(test.input));
  assert(error instanceof ProductionRepositoryRecoveryStageError);
  assertEquals(error.stage, "REPOSITORY_INSPECT");
  assertEquals(error.message, "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_FAILED");
});

// ==========================================================================
// REPOSITORY_INSPECT substep classification (observability hardening)
// ==========================================================================
//
// REPOSITORY_INSPECT wraps several distinct GitHub read substeps behind one
// guard() boundary. Without substep classification, every one of these
// failures collapsed into the same generic
// PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_FAILED code, making the exact
// failing read unprovable without raw log access. These tests prove the
// substep code is both correct and still fully sanitized.

Deno.test("production recovery repository metadata read failure classifies to REPOSITORY_INSPECT metadata substep", async () => {
  const test = await recoveryHarness("ALREADY_COMPLETE", { networkReadFailure: true });
  const error = await assertRejects(() => test.recovery.recover(test.input));
  assertZeroCreate(test.operations);
  assert(error instanceof ProductionRepositoryRecoveryStageError);
  assertEquals(error.stage, "REPOSITORY_INSPECT");
  assertEquals(error.message, "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_METADATA_FAILED");
  assert(!error.message.includes("network unavailable"));
  const log = productionRepositoryRecoveryFailureLog(error);
  assertEquals(log.diagnostic_code, "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_METADATA_FAILED");
  assert(!JSON.stringify(log).includes("network unavailable"));
});

Deno.test("production recovery unrecognized REPOSITORY_INSPECT failure falls back to the generic sanitized code", async () => {
  const test = await recoveryHarness("CONFLICT");
  const error = await assertRejects(() => test.recovery.recover(test.input));
  assert(error instanceof ProductionRepositoryRecoveryStageError);
  assertEquals(error.message, "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_FAILED");
});

// Distinguishes the safe GitHubTokenBrokerError code the inspector's own
// token acquisition previously discarded (LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE
// collapsed every broker failure into one generic code). Each broker code is
// itself already pre-approved/safe (see GITHUB_TOKEN_BROKER_CODES); this only
// narrows which known broker failure occurred.
const TOKEN_SUBSTEP_SCENARIOS: ReadonlyArray<
  readonly [GitHubTokenBrokerCode, string]
> = [
  ["GITHUB_TOKEN_AUTHORITY_INVALID", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_AUTHORITY_FAILED"],
  ["GITHUB_APP_SIGNING_FAILED", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_SIGNING_FAILED"],
  ["GITHUB_TOKEN_EXCHANGE_FAILED", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_FAILED"],
  ["GITHUB_TOKEN_TIMEOUT", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_FAILED"],
  ["GITHUB_TOKEN_RATE_LIMITED", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_FAILED"],
  ["GITHUB_TOKEN_REDIRECT_DENIED", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_FAILED"],
  ["GITHUB_TOKEN_FORBIDDEN", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_FORBIDDEN"],
  ["GITHUB_TOKEN_RESPONSE_INVALID", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_RESPONSE_INVALID"],
];

for (const [brokerCode, expectedDiagnosticCode] of TOKEN_SUBSTEP_SCENARIOS) {
  Deno.test(`production recovery PRODUCTION_REPOSITORY_READ token failure (${brokerCode}) classifies to ${expectedDiagnosticCode}`, async () => {
    const test = await recoveryHarness("ALREADY_COMPLETE", {
      tokenIssueFailsFor: "PRODUCTION_REPOSITORY_READ",
      tokenIssueFailsWith: brokerCode,
    });
    const error = await assertRejects(() => test.recovery.recover(test.input));
    assertZeroCreate(test.operations);
    assert(error instanceof ProductionRepositoryRecoveryStageError);
    assertEquals(error.stage, "REPOSITORY_INSPECT");
    assertEquals(error.message, expectedDiagnosticCode);
    assert(!error.message.includes(brokerCode.toLowerCase()));
    const log = productionRepositoryRecoveryFailureLog(error);
    assertEquals(log.diagnostic_code, expectedDiagnosticCode);
  });
}

Deno.test("production recovery PRODUCTION_REPOSITORY_READ token failure with an unrecognized broker error falls back to the generic token code", async () => {
  const test = await recoveryHarness("ALREADY_COMPLETE", { tokenIssueFailsFor: "PRODUCTION_REPOSITORY_READ" });
  const error = await assertRejects(() => test.recovery.recover(test.input));
  assertZeroCreate(test.operations);
  assert(error instanceof ProductionRepositoryRecoveryStageError);
  assertEquals(error.message, "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_FAILED");
  assert(!error.message.includes("sensitive installation detail"));
  const log = productionRepositoryRecoveryFailureLog(error);
  assert(!JSON.stringify(log).includes("sensitive installation detail"));
});

// Narrows GITHUB_TOKEN_EXCHANGE_FAILED (and its TIMEOUT/RATE_LIMITED/
// REDIRECT_DENIED siblings, which all share the exchange bucket) one level
// further using the already-safe GitHubTokenAcquireSubphase the broker
// preserves on GitHubHttpError-derived failures. This is the exact HTTP
// exchange boundary (request prepare / HTTP transport / HTTP status /
// content-type / body read / JSON parse / response schema / adapter
// projection) -- still a pre-approved, whitelisted, safe code, never raw
// provider text.
const TOKEN_EXCHANGE_SUBPHASE_SCENARIOS: ReadonlyArray<
  readonly [GitHubTokenAcquireSubphase, string]
> = [
  ["TOKEN_REQUEST_PREPARE", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_REQUEST_PREPARE_FAILED"],
  ["TOKEN_HTTP_REQUEST", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_HTTP_REQUEST_FAILED"],
  ["TOKEN_HTTP_STATUS", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_HTTP_STATUS_FAILED"],
  ["TOKEN_CONTENT_TYPE_VALIDATE", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_CONTENT_TYPE_FAILED"],
  ["TOKEN_RESPONSE_BODY_READ", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_BODY_READ_FAILED"],
  ["TOKEN_JSON_PARSE", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_JSON_PARSE_FAILED"],
  ["TOKEN_RESPONSE_SCHEMA", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_RESPONSE_SCHEMA_FAILED"],
  ["TOKEN_ADAPTER_PROJECT", "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_ADAPTER_FAILED"],
];

for (const [subphase, expectedDiagnosticCode] of TOKEN_EXCHANGE_SUBPHASE_SCENARIOS) {
  Deno.test(`production recovery PRODUCTION_REPOSITORY_READ token exchange failure (${subphase}) classifies to ${expectedDiagnosticCode}`, async () => {
    const test = await recoveryHarness("ALREADY_COMPLETE", {
      tokenIssueFailsFor: "PRODUCTION_REPOSITORY_READ",
      tokenIssueFailsWith: "GITHUB_TOKEN_EXCHANGE_FAILED",
      tokenIssueFailsWithSubphase: subphase,
    });
    const error = await assertRejects(() => test.recovery.recover(test.input));
    assertZeroCreate(test.operations);
    assert(error instanceof ProductionRepositoryRecoveryStageError);
    assertEquals(error.stage, "REPOSITORY_INSPECT");
    assertEquals(error.message, expectedDiagnosticCode);
    const log = productionRepositoryRecoveryFailureLog(error);
    assertEquals(log.diagnostic_code, expectedDiagnosticCode);
  });
}

Deno.test("production recovery PRODUCTION_REPOSITORY_READ token exchange failure with an unrecognized subphase falls back to the generic exchange code", async () => {
  const test = await recoveryHarness("ALREADY_COMPLETE", {
    tokenIssueFailsFor: "PRODUCTION_REPOSITORY_READ",
    tokenIssueFailsWith: "GITHUB_TOKEN_EXCHANGE_FAILED",
    tokenIssueFailsWithSubphase: "TOKEN_LEASE_VALIDATE",
  });
  const error = await assertRejects(() => test.recovery.recover(test.input));
  assertZeroCreate(test.operations);
  assert(error instanceof ProductionRepositoryRecoveryStageError);
  assertEquals(error.message, "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_FAILED");
});

Deno.test("production recovery PRODUCTION_REPOSITORY_READ token exchange HTTP status failure never leaks the underlying safe HTTP class in the public diagnostic code", async () => {
  const test = await recoveryHarness("ALREADY_COMPLETE", {
    tokenIssueFailsFor: "PRODUCTION_REPOSITORY_READ",
    tokenIssueFailsWith: "GITHUB_TOKEN_EXCHANGE_FAILED",
    tokenIssueFailsWithSubphase: "TOKEN_HTTP_STATUS",
    tokenIssueFailsWithHttpClass: "GITHUB_HTTP_NOT_FOUND",
  });
  const error = await assertRejects(() => test.recovery.recover(test.input));
  assertZeroCreate(test.operations);
  assert(error instanceof ProductionRepositoryRecoveryStageError);
  assertEquals(error.message, "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_HTTP_STATUS_FAILED");
  // The public/client-facing diagnostic code itself must stay generic --
  // only the server-side-only log record below may carry the safe HTTP class.
  assert(!error.message.includes("NOT_FOUND"));
  const log = productionRepositoryRecoveryFailureLog(error);
  assertEquals(log.token_exchange_http_class, "GITHUB_HTTP_NOT_FOUND");
});

Deno.test("productionRepositoryRecoveryFailureLog includes the safe token-exchange HTTP class only for the TOKEN_HTTP_STATUS substep", async () => {
  for (const httpClass of ["GITHUB_HTTP_UNAUTHORIZED", "GITHUB_HTTP_FORBIDDEN", "GITHUB_HTTP_SERVER_ERROR", "GITHUB_HTTP_CONFLICT"] as const) {
    const test = await recoveryHarness("ALREADY_COMPLETE", {
      tokenIssueFailsFor: "PRODUCTION_REPOSITORY_READ",
      tokenIssueFailsWith: "GITHUB_TOKEN_EXCHANGE_FAILED",
      tokenIssueFailsWithSubphase: "TOKEN_HTTP_STATUS",
      tokenIssueFailsWithHttpClass: httpClass,
    });
    const error = await assertRejects(() => test.recovery.recover(test.input));
    const log = productionRepositoryRecoveryFailureLog(error);
    assertEquals(log.token_exchange_http_class, httpClass);
    assertEquals(log.stage, "REPOSITORY_INSPECT");
    assertEquals(log.diagnostic_code, "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_HTTP_STATUS_FAILED");
  }
});

Deno.test("productionRepositoryRecoveryFailureLog omits the token-exchange HTTP class for every other substep/stage", async () => {
  // A non-HTTP-status token-exchange substep (e.g. a JSON parse failure) has
  // no meaningful HTTP status class -- the log must not fabricate one.
  const jsonParseFailure = await recoveryHarness("ALREADY_COMPLETE", {
    tokenIssueFailsFor: "PRODUCTION_REPOSITORY_READ",
    tokenIssueFailsWith: "GITHUB_TOKEN_EXCHANGE_FAILED",
    tokenIssueFailsWithSubphase: "TOKEN_JSON_PARSE",
  });
  const jsonParseError = await assertRejects(() => jsonParseFailure.recovery.recover(jsonParseFailure.input));
  const jsonParseLog = productionRepositoryRecoveryFailureLog(jsonParseError);
  assert(!Object.hasOwn(jsonParseLog, "token_exchange_http_class"));

  // A completely unrelated stage (e.g. metadata read) must not carry the
  // field either.
  const metadataFailure = await recoveryHarness("ALREADY_COMPLETE", { networkReadFailure: true });
  const metadataError = await assertRejects(() => metadataFailure.recovery.recover(metadataFailure.input));
  const metadataLog = productionRepositoryRecoveryFailureLog(metadataError);
  assert(!Object.hasOwn(metadataLog, "token_exchange_http_class"));

  // The unclassified/UNKNOWN fallback branch must not carry the field.
  const unclassifiedLog = productionRepositoryRecoveryFailureLog(new Error("unrelated"));
  assert(!Object.hasOwn(unclassifiedLog, "token_exchange_http_class"));
});

Deno.test("ProductionRepositoryRecoveryStageError rejects a token-exchange HTTP class attached to the wrong substep", () => {
  assertThrows(() =>
    new ProductionRepositoryRecoveryStageError(
      "REPOSITORY_INSPECT",
      "TOKEN_EXCHANGE_JSON_PARSE_FAILED",
      "GITHUB_HTTP_NOT_FOUND",
    )
  );
  assertThrows(() =>
    new ProductionRepositoryRecoveryStageError(
      "REPOSITORY_INSPECT",
      undefined,
      "GITHUB_HTTP_NOT_FOUND",
    )
  );
});

Deno.test("REPOSITORY_INSPECT substep diagnostic codes are all pre-approved and machine-readable", () => {
  const codes: string[] = source.match(/PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_[A-Z_]+/g) ?? [];
  assert(codes.length > 0);
  for (const code of codes) {
    assertMatch(code, /^PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_[A-Z_]+$/);
  }
  assert(codes.includes("PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_METADATA_FAILED"));
  assert(codes.includes("PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_REF_READ_FAILED"));
  assert(codes.includes("PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_FAILED"));
  assert(codes.includes("PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_AUTHORITY_FAILED"));
  assert(codes.includes("PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_SIGNING_FAILED"));
  assert(codes.includes("PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_FAILED"));
  assert(codes.includes("PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_FORBIDDEN"));
  assert(codes.includes("PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_RESPONSE_INVALID"));
});

Deno.test("production recovery stage errors never leak the underlying raw exception text", async () => {
  for (const [, , options] of STAGE_DIAGNOSTIC_SCENARIOS) {
    const test = await recoveryHarness(
      Object.keys(options).includes("callerRpcThrows") ||
        Object.keys(options).includes("callerError") ||
        Object.keys(options).includes("finalizeError")
        ? "ALREADY_COMPLETE"
        : "EMPTY_OR_UNINITIALIZED",
      options,
    );
    const error = await assertRejects(() => test.recovery.recover(test.input));
    const message = String((error as Error).message);
    assert(!message.includes("sensitive"));
    assert(!message.includes("network"));
    assert(!message.includes("provider"));
    assertMatch(message, /^PRODUCTION_REPOSITORY_RECOVERY_[A-Z_]+$/);
  }
});

Deno.test("productionRepositoryRecoveryDiagnosticCode returns null for unrelated errors", () => {
  assertEquals(productionRepositoryRecoveryDiagnosticCode(new Error("unrelated database failure")), null);
  assertEquals(productionRepositoryRecoveryDiagnosticCode("not an error"), null);
  assertEquals(productionRepositoryRecoveryDiagnosticCode(null), null);
});

Deno.test("productionRepositoryRecoveryDiagnosticCode returns the exact sanitized code for stage errors", () => {
  const error = new ProductionRepositoryRecoveryStageError("FINALIZE_RPC");
  assertEquals(
    productionRepositoryRecoveryDiagnosticCode(error),
    "PRODUCTION_REPOSITORY_RECOVERY_FINALIZE_FAILED",
  );
});

Deno.test("productionRepositoryRecoveryFailureLog contains only safe fields for stage errors", () => {
  const log = productionRepositoryRecoveryFailureLog(
    new ProductionRepositoryRecoveryStageError("MARKER_WRITE"),
  );
  assertEquals(log, {
    event: "LWS_GIT001_RECOVERY_FAILURE",
    action: "recover_existing_website_repository",
    stage: "MARKER_WRITE",
    diagnostic_code: "PRODUCTION_REPOSITORY_RECOVERY_MARKER_FAILED",
  });
});

Deno.test("productionRepositoryRecoveryFailureLog fails closed for unclassified errors", () => {
  const log = productionRepositoryRecoveryFailureLog(
    new Error("some raw sensitive provider payload"),
  );
  assertEquals(log, {
    event: "LWS_GIT001_RECOVERY_FAILURE",
    action: "recover_existing_website_repository",
    stage: "UNKNOWN",
    diagnostic_code: "UNCLASSIFIED",
  });
  assert(!JSON.stringify(log).includes("sensitive"));
});

Deno.test("withProductionRepositoryRecoveryFailureLogging logs sanitized entry and rethrows the original error unchanged", async () => {
  const logs: string[] = [];
  const original = new ProductionRepositoryRecoveryStageError("AUTHORITY_RPC");
  await assertRejects(
    () =>
      withProductionRepositoryRecoveryFailureLogging(
        () => Promise.reject(original),
        (entry) => logs.push(entry),
      ),
    ProductionRepositoryRecoveryStageError,
  );
  assertEquals(logs.length, 1);
  const parsed = JSON.parse(logs[0]);
  assertEquals(parsed.stage, "AUTHORITY_RPC");
  assertEquals(parsed.diagnostic_code, "PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_FAILED");
});

Deno.test("withProductionRepositoryRecoveryFailureLogging does not log on success", async () => {
  const logs: string[] = [];
  const result = await withProductionRepositoryRecoveryFailureLogging(
    () => Promise.resolve("ok"),
    (entry) => logs.push(entry),
  );
  assertEquals(result, "ok");
  assertEquals(logs.length, 0);
});
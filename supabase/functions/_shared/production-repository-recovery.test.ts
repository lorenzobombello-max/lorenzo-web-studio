import {
  assert,
  assertEquals,
  assertMatch,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";
import { GitHubHttpError } from "./github-http.ts";
import { computeGitHubSnapshotDigest } from "./github-snapshot-digest.ts";
import { createProductionRepositoryRecovery } from "./production-repository-recovery.ts";

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
  networkReadFailure?: boolean;
  writeFailure?: boolean;
  readbackFailure?: boolean;
  replay?: boolean;
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
    callerRpc: () => Promise.resolve({
      data: authority,
      error: options.callerError ?? null,
    }),
    serviceRpc: (name, parameters) => {
      serviceCalls.push({ name, parameters });
      return Promise.resolve({
        data: { replayed: options.replay === true },
        error: null,
      });
    },
    tokenBroker: {
      issue: (_config, request) => {
        tokenRequests.push(request);
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
        if (operation.kind === "CREATE_TREE") return { sha: TREE_SHA };
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

for (const [name, options] of [
  ["network read failure", { networkReadFailure: true }],
  ["write failure", { writeFailure: true }],
  ["readback failure", { readbackFailure: true }],
] as const) {
  Deno.test(`production recovery ${name} retains zero repository creates`, async () => {
    const state = name === "network read failure"
      ? "ALREADY_COMPLETE"
      : "MARKER_MISSING";
    const test = await recoveryHarness(state, options);
    await assertRejects(() => test.recovery.recover(test.input));
    assertZeroCreate(test.operations);
  });
}
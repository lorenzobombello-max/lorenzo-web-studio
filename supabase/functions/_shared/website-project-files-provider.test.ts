import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { GitHubAppConfig } from "./github-app-config.ts";
import {
  createWebsiteProjectFilesProvider,
  type WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProviderError,
} from "./website-project-files-provider.ts";

const TOKEN = "gh" + `s_${"a".repeat(36)}`;
const COMMIT = "a".repeat(40);
const ROOT_TREE = "b".repeat(40);
const SRC_TREE = "c".repeat(40);
const BLOB = "d".repeat(40);
const CONTEXT_A = "10000000-0000-4000-8000-000000000001";
const CONTEXT_B = "20000000-0000-4000-8000-000000000001";
const OPERATION_A = "10000000-0000-4000-8000-000000000002";
const OPERATION_B = "20000000-0000-4000-8000-000000000002";

const config = Object.freeze({
  enabled: true,
  target: "TEST",
  appId: "123456",
  installationId: "654321",
  organization: "lws-phase-a-fixtures",
  templateOwner: "lws-phase-a-fixtures",
  templateName: "starter",
  templateRepositoryId: "7000000000",
  starterVersion: "1.0.0",
  starterCommitSha: COMMIT,
  starterTreeSha256: "e".repeat(64),
  privateKey: "hidden",
}) as unknown as GitHubAppConfig;

function authority(overrides: Partial<WebsiteProjectFilesAuthority> = {}) {
  return Object.freeze({
    leaseId: "10000000-0000-4000-8000-000000000010",
    actorAuthUserId: "10000000-0000-4000-8000-000000000011",
    quoteRequestId: "10000000-0000-4000-8000-000000000012",
    websiteWorkContextId: CONTEXT_A,
    websiteWorkspaceId: "10000000-0000-4000-8000-000000000013",
    bindingRevision: 7,
    repositoryProvider: "GITHUB" as const,
    repositoryOwner: "lws-phase-a-fixtures",
    repositoryName: "project-a",
    repositoryExternalId: "7100000001",
    repositoryNodeId: "R_context_a",
    defaultBranch: "main",
    repositoryRef: "heads/main",
    refLabel: "main",
    markerOperationId: OPERATION_A,
    expiresAt: "2099-01-01T00:00:00.000Z",
    ...overrides,
  });
}

function marker(context = CONTEXT_A, operation = OPERATION_A) {
  return btoa(JSON.stringify({
    schema_version: 1,
    environment: "TEST",
    organization: "lws-phase-a-fixtures",
    website_work_context_id: context,
    repository_provisioning_operation_id: operation,
    starter_source: "lws-phase-a-fixtures/starter",
    starter_version: "v1.0.0",
    starter_commit_sha: COMMIT,
    starter_tree_sha256: "e".repeat(64),
  }));
}

function harness(overrides: {
  metadata?: Record<string, unknown>;
  markerContext?: string;
  markerOperation?: string;
  failCode?: string;
  treeEntries?: readonly Record<string, unknown>[];
  truncated?: boolean;
} = {}) {
  const calls: Array<
    { operation: Record<string, unknown>; signal?: AbortSignal }
  > = [];
  const signal = new AbortController().signal;
  const tokenCalls: unknown[] = [];
  const provider = createWebsiteProjectFilesProvider({
    config,
    signal,
    tokenBroker: {
      issue(
        _config: GitHubAppConfig,
        request: unknown,
        tokenAuthority: unknown,
        passedSignal?: AbortSignal,
      ) {
        tokenCalls.push({ request, tokenAuthority, passedSignal });
        return Promise.resolve({
          token: TOKEN,
          expiresAt: "2099-01-01T00:00:00Z",
        });
      },
    },
    httpClient: {
      execute(operation: Record<string, unknown>, passedSignal?: AbortSignal) {
        calls.push({
          operation: operation as unknown as Record<string, unknown>,
          signal: passedSignal,
        });
        if (overrides.failCode) {
          return Promise.reject(new Error(overrides.failCode));
        }
        const kind = (operation as { kind: string }).kind;
        if (kind === "WEBSITE_PROJECT_FILES_REPOSITORY_METADATA") {
          return Promise.resolve({
            repositoryId: "7100000001",
            nodeId: "R_context_a",
            owner: "lws-phase-a-fixtures",
            name: "project-a",
            fullName: "lws-phase-a-fixtures/project-a",
            private: true,
            defaultBranch: "main",
            description: null,
            createdAt: "2026-09-19T00:00:00Z",
            ...overrides.metadata,
          });
        }
        if (kind === "WEBSITE_PROJECT_FILES_READ_REF") {
          return Promise.resolve({ ref: "refs/heads/main", commitSha: COMMIT });
        }
        if (kind === "WEBSITE_PROJECT_FILES_READ_COMMIT") {
          return Promise.resolve({ sha: COMMIT, treeSha: ROOT_TREE });
        }
        if (kind === "WEBSITE_PROJECT_FILES_READ_MARKER") {
          return Promise.resolve({
            path: ".lws/project.json",
            sha: BLOB,
            encoding: "base64",
            contentBase64: marker(
              overrides.markerContext,
              overrides.markerOperation,
            ),
            size: 200,
          });
        }
        if (kind === "WEBSITE_PROJECT_FILES_READ_TREE") {
          return Promise.resolve({
            sha: (operation as { treeRef: string }).treeRef,
            truncated: overrides.truncated ?? false,
            entries: overrides.treeEntries ?? [{
              path: "src",
              mode: "040000",
              type: "tree",
              sha: SRC_TREE,
            }],
          });
        }
        throw new Error("UNEXPECTED_OPERATION");
      },
    },
  });
  return { provider, calls, tokenCalls, signal };
}

Deno.test("directory listing resolves ref to immutable commit", async () => {
  const test = harness();
  const snapshot = await test.provider.resolveSnapshot(authority());
  assertEquals(snapshot, {
    commitSha: COMMIT,
    rootTreeSha: ROOT_TREE,
    repositoryDisplayName: "lws-phase-a-fixtures/project-a",
  });
  assertEquals(test.tokenCalls.length, 1);
  assertEquals(test.calls.map(({ operation }) => operation.kind), [
    "WEBSITE_PROJECT_FILES_REPOSITORY_METADATA",
    "WEBSITE_PROJECT_FILES_READ_REF",
    "WEBSITE_PROJECT_FILES_READ_COMMIT",
    "WEBSITE_PROJECT_FILES_READ_MARKER",
  ]);
  assert(test.calls.every((call) => call.signal === test.signal));
});

Deno.test("directory traversal uses commit tree only", async () => {
  const test = harness();
  const result = await test.provider.listDirectory({
    authority: authority(),
    commitSha: COMMIT,
    rootTreeSha: ROOT_TREE,
    directoryTreeSha: null,
    path: "",
  });
  assertEquals(result.directoryTreeSha, ROOT_TREE);
  assertEquals(result.entries[0].canonicalPath, "src");
  assertEquals(test.calls.map(({ operation }) => operation.kind), [
    "WEBSITE_PROJECT_FILES_READ_TREE",
  ]);
});

Deno.test("marker and external repository identity are mandatory", async () => {
  for (
    const test of [
      harness({ metadata: { repositoryId: "7100000002" } }),
      harness({ metadata: { nodeId: "R_context_b" } }),
      harness({ markerContext: CONTEXT_B }),
      harness({ markerOperation: OPERATION_B }),
    ]
  ) {
    await assertRejects(
      () => test.provider.resolveSnapshot(authority()),
      WebsiteProjectFilesProviderError,
      "REPOSITORY_BINDING_STALE",
    );
  }
});

Deno.test("tree entries reject canonical path and object type mismatch", async () => {
  const malformed = [
    [{ path: "../escape", mode: "100644", type: "blob", sha: BLOB, size: 1 }],
    [{ path: "safe.txt", mode: "040000", type: "blob", sha: BLOB, size: 1 }],
    [{ path: "safe.txt", mode: "100644", type: "unknown", sha: BLOB, size: 1 }],
  ];
  for (const treeEntries of malformed) {
    const test = harness({ treeEntries });
    await assertRejects(
      () =>
        test.provider.listDirectory({
          authority: authority(),
          commitSha: COMMIT,
          rootTreeSha: ROOT_TREE,
          directoryTreeSha: null,
          path: "",
        }),
      WebsiteProjectFilesProviderError,
      "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    );
  }
  await assertRejects(
    () =>
      harness({ truncated: true }).provider.listDirectory({
        authority: authority(),
        commitSha: COMMIT,
        rootTreeSha: ROOT_TREE,
        directoryTreeSha: null,
        path: "",
      }),
    WebsiteProjectFilesProviderError,
    "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
  );
});

Deno.test("provider timeout throttle malformed and snapshot unavailable normalize", async () => {
  const cases = [
    ["GITHUB_HTTP_TIMEOUT", "PROJECT_FILES_PROVIDER_TIMEOUT"],
    ["GITHUB_HTTP_RATE_LIMITED", "PROJECT_FILES_PROVIDER_THROTTLED"],
    ["GITHUB_HTTP_NOT_FOUND", "PROJECT_FILES_SNAPSHOT_UNAVAILABLE"],
    ["raw network body token url", "PROJECT_FILES_PROVIDER_UNAVAILABLE"],
  ] as const;
  for (const [injected, expected] of cases) {
    const test = harness({ failCode: injected });
    const error = await assertRejects(
      () => test.provider.resolveSnapshot(authority()),
      WebsiteProjectFilesProviderError,
      expected,
    );
    assertEquals(JSON.stringify(error).includes(injected), false);
    assertEquals(test.calls.length, 1);
  }
});

Deno.test("provider rejects CONTEXT_B authority substitution before any result", async () => {
  const substitutions = [
    { websiteWorkContextId: CONTEXT_B },
    { repositoryExternalId: "7100000002" },
    { repositoryNodeId: "R_context_b" },
    { markerOperationId: OPERATION_B },
    { repositoryOwner: "other-owner" },
    { repositoryName: "project-b" },
  ];
  for (const substitution of substitutions) {
    const test = harness();
    await assertRejects(
      () => test.provider.resolveSnapshot(authority(substitution)),
      WebsiteProjectFilesProviderError,
    );
  }
});

Deno.test("provider exposes no write method", () => {
  const provider = harness().provider;
  assertEquals(Object.keys(provider).sort(), [
    "listDirectory",
    "resolveSnapshot",
  ]);
  assertEquals("readFile" in provider, false);
});

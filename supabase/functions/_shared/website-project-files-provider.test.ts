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
const NEXT_COMMIT = "e".repeat(40);
const NEXT_ROOT_TREE = "f".repeat(40);
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

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

type ReadFileResult = Readonly<{
  path: string;
  canonicalPath: string;
  mode: string;
  objectType: "blob";
  declaredSize: number | null;
  bytes: Uint8Array;
}>;

type ReadCapableProvider = Readonly<{
  readFile(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      commitSha: string;
      rootTreeSha: string;
      path: string;
    }>,
  ): Promise<ReadFileResult>;
}>;

function readCapable(value: unknown): ReadCapableProvider {
  return value as ReadCapableProvider;
}

function harness(overrides: {
  metadata?: Record<string, unknown>;
  markerContext?: string;
  markerOperation?: string;
  failCode?: string;
  treeEntries?: readonly Record<string, unknown>[];
  trees?: Readonly<Record<string, readonly Record<string, unknown>[]>>;
  truncated?: boolean;
  refCommits?: readonly string[];
  commitTrees?: Readonly<Record<string, string>>;
  blobBytes?: Uint8Array;
  blobDeclaredSize?: number;
  blobSha?: string;
  failKind?: string;
} = {}) {
  const calls: Array<
    { operation: Record<string, unknown>; signal?: AbortSignal }
  > = [];
  const signal = new AbortController().signal;
  const tokenCalls: unknown[] = [];
  let refIndex = 0;
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
        if (
          overrides.failCode &&
          (!overrides.failKind ||
            overrides.failKind === (operation as { kind: string }).kind)
        ) {
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
          const commitSha = overrides.refCommits?.[
            Math.min(refIndex++, overrides.refCommits.length - 1)
          ] ?? COMMIT;
          return Promise.resolve({ ref: "refs/heads/main", commitSha });
        }
        if (kind === "WEBSITE_PROJECT_FILES_READ_COMMIT") {
          const commitSha = String(operation.commitSha);
          return Promise.resolve({
            sha: commitSha,
            treeSha: overrides.commitTrees?.[commitSha] ?? ROOT_TREE,
          });
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
          const treeRef = String(operation.treeRef);
          return Promise.resolve({
            sha: treeRef,
            truncated: overrides.truncated ?? false,
            entries: overrides.trees?.[treeRef] ?? overrides.treeEntries ?? [{
              path: "src",
              mode: "040000",
              type: "tree",
              sha: SRC_TREE,
            }],
          });
        }
        if (kind === "READ_BLOB") {
          const bytes = overrides.blobBytes ?? new TextEncoder().encode("safe");
          return Promise.resolve({
            sha: overrides.blobSha ?? BLOB,
            encoding: "base64",
            contentBase64: base64(bytes),
            size: overrides.blobDeclaredSize ?? bytes.byteLength,
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
    "readFile",
    "resolveSnapshot",
  ]);
});

Deno.test("direct read re-resolves current canonical commit", async () => {
  const test = harness({
    trees: {
      [ROOT_TREE]: [{
        path: "safe.txt",
        mode: "100644",
        type: "blob",
        sha: BLOB,
        size: 4,
      }],
    },
  });
  const snapshot = await test.provider.resolveSnapshot(authority());
  await readCapable(test.provider).readFile({
    authority: authority(),
    commitSha: snapshot.commitSha,
    rootTreeSha: snapshot.rootTreeSha,
    path: "safe.txt",
  });
  assertEquals(
    test.calls.filter(({ operation }) =>
      operation.kind === "WEBSITE_PROJECT_FILES_READ_REF"
    ).length,
    1,
  );
  assertEquals(
    test.calls.slice(4).map(({ operation }) => operation.kind),
    ["WEBSITE_PROJECT_FILES_READ_TREE", "READ_BLOB"],
  );
});

Deno.test("direct read cannot select historical commit", async () => {
  const test = harness();
  await assertRejects(
    () =>
      readCapable(test.provider).readFile({
        authority: authority(),
        commitSha: COMMIT,
        rootTreeSha: ROOT_TREE,
        path: "safe.txt",
        ref: "heads/historical",
      } as never),
    WebsiteProjectFilesProviderError,
    "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
  );
  assertEquals(test.calls.length, 0);
});

Deno.test("parent tree traversal validates exact blob path", async () => {
  const test = harness({
    trees: {
      [ROOT_TREE]: [{
        path: "src",
        mode: "040000",
        type: "tree",
        sha: SRC_TREE,
      }],
      [SRC_TREE]: [{
        path: "safe.txt",
        mode: "100644",
        type: "blob",
        sha: BLOB,
        size: 4,
      }],
    },
  });
  const result = await readCapable(test.provider).readFile({
    authority: authority(),
    commitSha: COMMIT,
    rootTreeSha: ROOT_TREE,
    path: "src/safe.txt",
  });
  assertEquals(result.canonicalPath, "src/safe.txt");
  assertEquals(test.calls.map(({ operation }) => operation.kind), [
    "WEBSITE_PROJECT_FILES_READ_TREE",
    "WEBSITE_PROJECT_FILES_READ_TREE",
    "READ_BLOB",
  ]);
  assert(test.calls.every((call) => call.signal === test.signal));
});

Deno.test("changed branch yields new snapshot SHA", async () => {
  const test = harness({
    refCommits: [COMMIT, NEXT_COMMIT],
    commitTrees: {
      [COMMIT]: ROOT_TREE,
      [NEXT_COMMIT]: NEXT_ROOT_TREE,
    },
  });
  const first = await test.provider.resolveSnapshot(authority());
  const second = await test.provider.resolveSnapshot(authority());
  assertEquals(first.commitSha, COMMIT);
  assertEquals(second.commitSha, NEXT_COMMIT);
  assertEquals(second.rootTreeSha, NEXT_ROOT_TREE);
});

Deno.test("provider rejects declared oversize before blob fetch", async () => {
  const test = harness({
    trees: {
      [ROOT_TREE]: [{
        path: "large.txt",
        mode: "100644",
        type: "blob",
        sha: BLOB,
        size: 1_048_577,
      }],
    },
  });
  await assertRejects(
    () =>
      readCapable(test.provider).readFile({
        authority: authority(),
        commitSha: COMMIT,
        rootTreeSha: ROOT_TREE,
        path: "large.txt",
      }),
    WebsiteProjectFilesProviderError,
    "FILE_TOO_LARGE",
  );
  assertEquals(
    test.calls.filter(({ operation }) => operation.kind === "READ_BLOB").length,
    0,
  );
});

Deno.test("provider rejects decoded oversize without truncation", async () => {
  const bytes = new Uint8Array(1_048_577).fill(0x61);
  const test = harness({
    blobBytes: bytes,
    blobDeclaredSize: 1_048_576,
    trees: {
      [ROOT_TREE]: [{
        path: "unknown.txt",
        mode: "100644",
        type: "blob",
        sha: BLOB,
      }],
    },
  });
  await assertRejects(
    () =>
      readCapable(test.provider).readFile({
        authority: authority(),
        commitSha: COMMIT,
        rootTreeSha: ROOT_TREE,
        path: "unknown.txt",
      }),
    WebsiteProjectFilesProviderError,
    "FILE_TOO_LARGE",
  );
});

Deno.test("provider file read rejects missing, wrong-kind, symlink, submodule, and malformed objects", async () => {
  const cases = [
    [[], "PROJECT_FILE_NOT_FOUND"],
    [
      [{ path: "safe.txt", mode: "040000", type: "tree", sha: SRC_TREE }],
      "PROJECT_PATH_KIND_MISMATCH",
    ],
    [
      [{ path: "safe.txt", mode: "120000", type: "blob", sha: BLOB, size: 4 }],
      "PROJECT_PATH_KIND_MISMATCH",
    ],
    [
      [{ path: "safe.txt", mode: "160000", type: "commit", sha: BLOB }],
      "PROJECT_PATH_KIND_MISMATCH",
    ],
    [
      [{ path: "safe.txt", mode: "100644", type: "blob", sha: "bad", size: 4 }],
      "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    ],
  ] as const;
  for (const [entries, code] of cases) {
    const test = harness({ trees: { [ROOT_TREE]: entries } });
    await assertRejects(
      () =>
        readCapable(test.provider).readFile({
          authority: authority(),
          commitSha: COMMIT,
          rootTreeSha: ROOT_TREE,
          path: "safe.txt",
        }),
      WebsiteProjectFilesProviderError,
      code,
    );
  }
});

Deno.test("provider validates exact blob SHA and decoded transport shape", async () => {
  for (
    const overrides of [
      { blobSha: NEXT_COMMIT },
      { blobDeclaredSize: 5 },
    ]
  ) {
    const test = harness({
      ...overrides,
      trees: {
        [ROOT_TREE]: [{
          path: "safe.txt",
          mode: "100644",
          type: "blob",
          sha: BLOB,
          size: 4,
        }],
      },
    });
    await assertRejects(
      () =>
        readCapable(test.provider).readFile({
          authority: authority(),
          commitSha: COMMIT,
          rootTreeSha: ROOT_TREE,
          path: "safe.txt",
        }),
      WebsiteProjectFilesProviderError,
      "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    );
  }
});

Deno.test("wrong canonical file path returns not found without blob fetch", async () => {
  const test = harness({
    trees: {
      [ROOT_TREE]: [{
        path: "other.txt",
        mode: "100644",
        type: "blob",
        sha: BLOB,
        size: 4,
      }],
    },
  });
  await assertRejects(
    () =>
      readCapable(test.provider).readFile({
        authority: authority(),
        commitSha: COMMIT,
        rootTreeSha: ROOT_TREE,
        path: "safe.txt",
      }),
    WebsiteProjectFilesProviderError,
    "PROJECT_FILE_NOT_FOUND",
  );
  assertEquals(
    test.calls.filter(({ operation }) => operation.kind === "READ_BLOB").length,
    0,
  );
});

Deno.test("missing commit tree and blob normalize at their exact one-attempt boundaries", async () => {
  const scenarios = [
    {
      kind: "WEBSITE_PROJECT_FILES_READ_COMMIT",
      action: (test: ReturnType<typeof harness>) =>
        test.provider.resolveSnapshot(authority()),
    },
    {
      kind: "WEBSITE_PROJECT_FILES_READ_TREE",
      action: (test: ReturnType<typeof harness>) =>
        readCapable(test.provider).readFile({
          authority: authority(),
          commitSha: COMMIT,
          rootTreeSha: ROOT_TREE,
          path: "safe.txt",
        }),
    },
    {
      kind: "READ_BLOB",
      action: (test: ReturnType<typeof harness>) =>
        readCapable(test.provider).readFile({
          authority: authority(),
          commitSha: COMMIT,
          rootTreeSha: ROOT_TREE,
          path: "safe.txt",
        }),
      trees: {
        [ROOT_TREE]: [{
          path: "safe.txt",
          mode: "100644",
          type: "blob",
          sha: BLOB,
          size: 4,
        }],
      },
    },
  ] as const;
  for (const scenario of scenarios) {
    const test = harness({
      failCode: "GITHUB_HTTP_NOT_FOUND",
      failKind: scenario.kind,
      trees: "trees" in scenario ? scenario.trees : undefined,
    });
    await assertRejects(
      () => scenario.action(test),
      WebsiteProjectFilesProviderError,
      "PROJECT_FILES_SNAPSHOT_UNAVAILABLE",
    );
    assertEquals(
      test.calls.filter(({ operation }) => operation.kind === scenario.kind)
        .length,
      1,
    );
  }
});

Deno.test("provider file failures normalize once with no retry", async () => {
  const cases = [
    ["GITHUB_HTTP_TIMEOUT", "PROJECT_FILES_PROVIDER_TIMEOUT"],
    ["GITHUB_HTTP_RATE_LIMITED", "PROJECT_FILES_PROVIDER_THROTTLED"],
    ["GITHUB_HTTP_NOT_FOUND", "PROJECT_FILES_SNAPSHOT_UNAVAILABLE"],
    ["raw network body token url", "PROJECT_FILES_PROVIDER_UNAVAILABLE"],
  ] as const;
  for (const [injected, expected] of cases) {
    const test = harness({
      failCode: injected,
      failKind: "WEBSITE_PROJECT_FILES_READ_TREE",
    });
    const error = await assertRejects(
      () =>
        readCapable(test.provider).readFile({
          authority: authority(),
          commitSha: COMMIT,
          rootTreeSha: ROOT_TREE,
          path: "safe.txt",
        }),
      WebsiteProjectFilesProviderError,
      expected,
    );
    assertEquals(test.calls.length, 1);
    assertEquals(JSON.stringify(error).includes(injected), false);
  }
});

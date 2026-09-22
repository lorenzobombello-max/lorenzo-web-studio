import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { GitHubAppConfig } from "./github-app-config.ts";
import {
  buildProjectFilesFailureLog,
  createWebsiteProjectFilesProvider,
  type WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProviderError,
} from "./website-project-files-provider.ts";
import { GitHubTokenBrokerError } from "./github-app-token.ts";
import { GitHubHttpError } from "./github-http.ts";

const source = await Deno.readTextFile(
  new URL("./website-project-files-provider.ts", import.meta.url),
);

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
  tokenIssueFailsWith?: unknown;
  httpExecuteFailsWith?: unknown;
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
        if (overrides.tokenIssueFailsWith !== undefined) {
          return Promise.reject(overrides.tokenIssueFailsWith);
        }
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
        if (
          overrides.httpExecuteFailsWith !== undefined &&
          (!overrides.failKind ||
            overrides.failKind === (operation as { kind: string }).kind)
        ) {
          return Promise.reject(overrides.httpExecuteFailsWith);
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
        if (kind === "CREATE_BLOB") {
          return Promise.resolve({ sha: BLOB });
        }
        if (kind === "CREATE_TREE") {
          return Promise.resolve({ sha: NEXT_ROOT_TREE });
        }
        if (kind === "CREATE_COMMIT") {
          return Promise.resolve({ sha: NEXT_COMMIT });
        }
        if (kind === "UPDATE_REF") {
          return Promise.resolve({
            ref: "refs/heads/main",
            commitSha: NEXT_COMMIT,
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

Deno.test("provider saves through parented non-force CAS operations", async () => {
  const test = harness({
    trees: {
      [ROOT_TREE]: [{
        path: "index.html",
        mode: "100644",
        type: "blob",
        sha: BLOB,
        size: 4,
      }],
    },
  });
  assert(test.provider.writeFile);
  const result = await test.provider.writeFile({
    authority: authority(),
    parentCommitSha: COMMIT,
    rootTreeSha: ROOT_TREE,
    path: "index.html",
    bytes: new TextEncoder().encode("next"),
  });

  assertEquals(result, { commitSha: NEXT_COMMIT, created: false });
  assertEquals(test.calls.map(({ operation }) => operation.kind), [
    "WEBSITE_PROJECT_FILES_READ_REF",
    "WEBSITE_PROJECT_FILES_READ_TREE",
    "CREATE_BLOB",
    "CREATE_TREE",
    "CREATE_COMMIT",
    "UPDATE_REF",
  ]);
  assertEquals(test.calls[3].operation.baseTreeSha, ROOT_TREE);
  assertEquals(test.calls[4].operation.parentSha, COMMIT);
  assertEquals(test.calls[5].operation.force, false);
  assertEquals(
    (test.tokenCalls[0] as { request: { operation: string } }).request.operation,
    "WEBSITE_PROJECT_FILES_WRITE",
  );
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

// ==========================================================================
// LWS_GIT001_PROJECT_FILES_FAILURE stage observability
// ==========================================================================
//
// resolveSnapshot()'s single-attempt read pipeline (token acquire, metadata,
// ref, commit, marker) previously collapsed every failure into the same
// generic public code with zero server-side stage detail. These prove the
// exact safe stage/diagnostic/field record buildProjectFilesFailureLog()
// produces, both as a pure function and end-to-end through the real
// provider, without ever changing the public/client-facing error.

function withCapturedConsoleError(run: () => Promise<void>) {
  const original = console.error;
  const calls: string[] = [];
  console.error = (...args: unknown[]) => {
    calls.push(args.map(String).join(" "));
  };
  return run().finally(() => {
    console.error = original;
  }).then(() => calls);
}

Deno.test("buildProjectFilesFailureLog reports the exact safe stage/diagnostic for a trusted GitHubTokenBrokerError", () => {
  const error = new GitHubTokenBrokerError(
    "GITHUB_TOKEN_EXCHANGE_FAILED",
    "TOKEN_HTTP_STATUS",
    undefined,
    undefined,
    "GITHUB_HTTP_CONFLICT",
    409,
  );
  const log = buildProjectFilesFailureLog(
    "WEBSITE_PROJECT_FILES_READ",
    "TOKEN_ACQUIRE",
    error,
  );
  assertEquals(log.event, "LWS_GIT001_PROJECT_FILES_FAILURE");
  assertEquals(log.action, "WEBSITE_PROJECT_FILES_READ");
  assertEquals(log.stage, "TOKEN_ACQUIRE");
  assertEquals(log.diagnostic_code, "PROJECT_FILES_PROVIDER_UNAVAILABLE");
  assertEquals(log.token_acquire_subphase, "TOKEN_HTTP_STATUS");
  assertEquals(log.token_exchange_http_class, "GITHUB_HTTP_CONFLICT");
  assertEquals(log.token_exchange_http_status, "409");
  assert(!Object.hasOwn(log, "github_http_class"));
});

Deno.test("buildProjectFilesFailureLog reports the exact safe stage/diagnostic for a trusted GitHubHttpError", () => {
  const error = new GitHubHttpError(
    "GITHUB_HTTP_NOT_FOUND",
    null,
    null,
    undefined,
    "HTTP_STATUS",
  );
  const log = buildProjectFilesFailureLog(
    "WEBSITE_PROJECT_FILES_READ_REF",
    "REF_READ",
    error,
  );
  assertEquals(log.stage, "REF_READ");
  assertEquals(log.diagnostic_code, "PROJECT_FILES_SNAPSHOT_UNAVAILABLE");
  assertEquals(log.github_http_class, "GITHUB_HTTP_NOT_FOUND");
  assertEquals(log.github_http_boundary, "HTTP_STATUS");
  assert(!Object.hasOwn(log, "token_acquire_subphase"));
  assert(!Object.hasOwn(log, "github_http_status"));
});

Deno.test("buildProjectFilesFailureLog omits every optional field for an untrusted/unrelated error", () => {
  const log = buildProjectFilesFailureLog(
    "WEBSITE_PROJECT_FILES_REPOSITORY_METADATA",
    "REPOSITORY_METADATA",
    new Error("raw network body token url"),
  );
  assertEquals(log.diagnostic_code, "PROJECT_FILES_PROVIDER_UNAVAILABLE");
  assertEquals(Object.keys(log).sort(), [
    "action",
    "diagnostic_code",
    "event",
    "stage",
  ]);
  assert(!JSON.stringify(log).includes("raw network body token url"));
});

Deno.test("buildProjectFilesFailureLog never includes secrets, tokens, JWTs, headers, or raw provider payloads", () => {
  const secret = "raw provider body with a token and Authorization: Bearer x";
  const forged = Object.assign(
    new GitHubHttpError("GITHUB_HTTP_SERVER_ERROR", null, null, undefined, "HTTP_STATUS"),
    { rawBody: secret, headers: { authorization: secret }, cause: secret },
  );
  const log = buildProjectFilesFailureLog("WEBSITE_PROJECT_FILES_READ_COMMIT", "COMMIT_READ", forged);
  const serialized = JSON.stringify(log);
  assert(!serialized.includes(secret));
  assert(!/authorization|bearer|jwt|private.?key/i.test(serialized));
});

Deno.test("resolveSnapshot token acquisition failure reports stage TOKEN_ACQUIRE end-to-end", async () => {
  const test = harness({
    tokenIssueFailsWith: new GitHubTokenBrokerError(
      "GITHUB_TOKEN_EXCHANGE_FAILED",
      "TOKEN_HTTP_STATUS",
      undefined,
      undefined,
      "GITHUB_HTTP_SERVER_ERROR",
    ),
  });
  const logs = await withCapturedConsoleError(async () => {
    await assertRejects(
      () => test.provider.resolveSnapshot(authority()),
      WebsiteProjectFilesProviderError,
    );
  });
  assertEquals(logs.length, 1);
  const record = JSON.parse(logs[0]);
  assertEquals(record.event, "LWS_GIT001_PROJECT_FILES_FAILURE");
  assertEquals(record.stage, "TOKEN_ACQUIRE");
  assertEquals(record.token_exchange_http_class, "GITHUB_HTTP_SERVER_ERROR");
});

Deno.test("resolveSnapshot stage-by-stage failures each report their exact safe stage end-to-end", async () => {
  const scenarios = [
    ["WEBSITE_PROJECT_FILES_REPOSITORY_METADATA", "REPOSITORY_METADATA"],
    ["WEBSITE_PROJECT_FILES_READ_REF", "REF_READ"],
    ["WEBSITE_PROJECT_FILES_READ_COMMIT", "COMMIT_READ"],
    ["WEBSITE_PROJECT_FILES_READ_MARKER", "MARKER_READ"],
  ] as const;
  for (const [kind, stage] of scenarios) {
    const test = harness({
      failKind: kind,
      httpExecuteFailsWith: new GitHubHttpError(
        "GITHUB_HTTP_NOT_FOUND",
        null,
        null,
        undefined,
        "HTTP_STATUS",
      ),
    });
    const logs = await withCapturedConsoleError(async () => {
      await assertRejects(() => test.provider.resolveSnapshot(authority()));
    });
    assertEquals(logs.length, 1, `stage ${stage}`);
    const record = JSON.parse(logs[0]);
    assertEquals(record.action, kind);
    assertEquals(record.stage, stage);
    assertEquals(record.github_http_class, "GITHUB_HTTP_NOT_FOUND");
  }
});

Deno.test("root directory tree-read failure reports stage TREE_READ end-to-end", async () => {
  const test = harness({
    failKind: "WEBSITE_PROJECT_FILES_READ_TREE",
    httpExecuteFailsWith: new GitHubHttpError(
      "GITHUB_HTTP_SERVER_ERROR",
      null,
      null,
      undefined,
      "HTTP_STATUS",
    ),
  });
  const logs = await withCapturedConsoleError(async () => {
    await assertRejects(() =>
      readCapable(test.provider).readFile({
        authority: authority(),
        commitSha: COMMIT,
        rootTreeSha: ROOT_TREE,
        path: "safe.txt",
      })
    );
  });
  assertEquals(logs.length, 1);
  const record = JSON.parse(logs[0]);
  assertEquals(record.stage, "TREE_READ");
  assertEquals(record.github_http_class, "GITHUB_HTTP_SERVER_ERROR");
});

Deno.test("the public/client-facing thrown error is completely unaffected by the new observability", async () => {
  const test = harness({
    failKind: "WEBSITE_PROJECT_FILES_READ_REF",
    httpExecuteFailsWith: new GitHubHttpError(
      "GITHUB_HTTP_NOT_FOUND",
      null,
      null,
      undefined,
      "HTTP_STATUS",
    ),
  });
  await withCapturedConsoleError(async () => {
    const error = await assertRejects(
      () => test.provider.resolveSnapshot(authority()),
      WebsiteProjectFilesProviderError,
      "PROJECT_FILES_SNAPSHOT_UNAVAILABLE",
    );
    // Exactly the same closed shape as every other provider error -- only
    // `code`/`name`, nothing from the new safe log fields leaks onto it.
    assertEquals(Object.keys(error).sort(), ["code", "name"]);
  });
});

Deno.test("a fully successful resolveSnapshot produces no failure log at all", async () => {
  const test = harness();
  const logs = await withCapturedConsoleError(async () => {
    await test.provider.resolveSnapshot(authority());
  });
  assertEquals(logs, []);
});

Deno.test("Project Files provider observability introduces no repository-create dependency", () => {
  // This provider module has no repository-creation capability at all --
  // the new logging is purely additive around the existing read/write
  // operations and must never gain one.
  assert(!source.includes("CREATE_REPOSITORY"));
  assert(!source.includes("github-repository-runtime.ts"));
  assert(!source.includes("github-repository-provider.ts"));
});

Deno.test("lease/authority validation is unaffected by the new observability", async () => {
  // A stale/invalid authority must still fail closed on REPOSITORY_BINDING_STALE
  // before any token acquisition or HTTP call -- and must never log a failure
  // record, since it never reaches access()/execute() at all.
  const test = harness();
  const logs = await withCapturedConsoleError(async () => {
    await assertRejects(
      () =>
        test.provider.resolveSnapshot(authority({
          bindingRevision: -1,
        }) as unknown as WebsiteProjectFilesAuthority),
      WebsiteProjectFilesProviderError,
      "REPOSITORY_BINDING_STALE",
    );
  });
  assertEquals(logs, []);
  assertEquals(test.tokenCalls.length, 0);
  assertEquals(test.calls.length, 0);
});

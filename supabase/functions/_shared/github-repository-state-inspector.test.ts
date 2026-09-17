import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";
import type {
  GitHubHttpOperation,
  GitHubRepositoryMetadata,
} from "./github-http.ts";
import { createGitHubHttpClient, GitHubHttpError } from "./github-http.ts";
import { createGitHubRefReadDiagnostic } from "./github-ref-read-diagnostic.ts";
import {
  computeGitHubSnapshotDigest,
  GitHubSnapshotDigestError,
} from "./github-snapshot-digest.ts";

const SHA = "a".repeat(40);
const EXPECTED = Object.freeze({
  websiteWorkContextId: "33a61b58-1d55-4624-bdb7-3c724d35ebcc",
  repositoryId: "1371224564",
  owner: "lorenzo-web-solutions-lab",
  repository: "lws-web-33a61b581d554624bdb73c724d35ebcc",
  private: true as const,
  defaultBranch: "main" as const,
  snapshotTreeSha256: "b".repeat(64),
  markerContent: JSON.stringify({
    schema_version: 1,
    starter_source: "lorenzo-web-solutions/lws-website-starter",
    starter_version: "v1.0.0",
    starter_commit_sha: "c".repeat(40),
    starter_tree_sha256: "b".repeat(64),
  }),
});

Deno.test("snapshot digest rejects manifest delimiters in paths", async () => {
  for (
    const path of ["folder\tname.txt", "folder\nname.txt", "folder\rname.txt"]
  ) {
    await assertRejects(
      () =>
        computeGitHubSnapshotDigest([{
          path,
          mode: "100644",
          type: "blob",
          content: new Uint8Array([1]),
        }]),
      GitHubSnapshotDigestError,
      "SNAPSHOT_INVALID",
    );
  }
});

type InspectorDependencies = Readonly<{
  readMetadata(input: Readonly<Record<string, unknown>>): Promise<unknown>;
  readRef(input: Readonly<Record<string, unknown>>): Promise<unknown>;
  readSnapshot(input: Readonly<Record<string, unknown>>): Promise<unknown>;
  readMarker(input: Readonly<Record<string, unknown>>): Promise<unknown>;
}>;

type InspectorModule = Readonly<{
  GITHUB_SNAPSHOT_READBACK_CHECKS?: readonly string[];
  createGitHubRepositoryStateInspector?: (
    expected: typeof EXPECTED,
    dependencies: InspectorDependencies,
  ) => () => Promise<Readonly<{ state: string }>>;
  GitHubRepositoryStateInspectionError?: new (
    code: "REPOSITORY_IDENTITY_MISMATCH" | "REPOSITORY_STATE_UNCERTAIN",
    postCreateSubphase?: string,
    snapshotReadbackCheck?: string,
    refReadDiagnostic?: Readonly<{ boundary: string; code: string }>,
  ) => Error;
  hasValidatedGitHubRepositoryStateInspectionSubphase?: (
    value: unknown,
  ) => boolean;
  getValidatedGitHubRepositoryRefReadDiagnostic?: (
    value: unknown,
  ) => Readonly<{ boundary: string; code: string }>;
  createGitHubRepositoryStateInspectionCapability?: (
    config: unknown,
    expected: unknown,
    dependencies: unknown,
  ) => () => Promise<Readonly<{ state: string }>>;
  inspectGitHubRepositoryCompletionProof?: (
    expected: typeof EXPECTED,
    dependencies: InspectorDependencies,
  ) => () => Promise<
    Readonly<{
      state: "ALREADY_COMPLETE";
      proof: Readonly<{
        providerRepositoryId: string;
        providerNodeId: string;
        owner: string;
        name: string;
        visibility: "PRIVATE";
        defaultBranch: "main";
        repositoryMarkerCommitSha: string;
      }>;
    }>
  >;
}>;

async function module(): Promise<InspectorModule> {
  try {
    return await import(
      "./github-repository-state-inspector.ts"
    ) as unknown as InspectorModule;
  } catch {
    return {};
  }
}

type SnapshotReadbackCheck =
  | "REF_READ"
  | "COMMIT_READ"
  | "TREE_READ"
  | "BLOB_READ";

type SnapshotFailureVariant =
  | "HTTP"
  | "NOT_RECORD"
  | "CONTRACT"
  | "ENTRY_NOT_RECORD"
  | "BASE64"
  | "SIZE";

async function assertSnapshotReadbackCheck(
  check: SnapshotReadbackCheck,
  variant: SnapshotFailureVariant,
) {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspectionCapability ===
      "function",
  );
  const content = new TextEncoder().encode("canonical snapshot\n");
  const inspect = implementation
    .createGitHubRepositoryStateInspectionCapability(
      { target: "TEST", organization: EXPECTED.owner },
      EXPECTED,
      {
        tokenBroker: {
          issue: () => Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
        },
        http: {
          execute: (operation: GitHubHttpOperation) => {
            const selected = operation.kind === {
              REF_READ: "READ_REF",
              COMMIT_READ: "COMMIT_METADATA",
              TREE_READ: "REPOSITORY_TREE",
              BLOB_READ: "READ_BLOB",
            }[check];
            if (selected && variant === "HTTP") {
              return Promise.reject(new Error("raw snapshot failure"));
            }
            switch (operation.kind) {
              case "REPOSITORY_METADATA":
                return Promise.resolve(metadata());
              case "READ_REF":
                return Promise.resolve(
                  selected && variant === "NOT_RECORD"
                    ? null
                    : selected && variant === "CONTRACT"
                    ? {}
                    : {
                      ref: "refs/heads/main",
                      commitSha: SHA,
                    },
                );
              case "COMMIT_METADATA":
                return Promise.resolve(
                  selected && variant === "NOT_RECORD"
                    ? null
                    : selected && variant === "CONTRACT"
                    ? {}
                    : {
                      sha: SHA,
                      treeSha: "d".repeat(40),
                    },
                );
              case "REPOSITORY_TREE":
                return Promise.resolve(
                  selected && variant === "NOT_RECORD"
                    ? null
                    : selected && variant === "CONTRACT"
                    ? {}
                    : {
                      sha: "d".repeat(40),
                      truncated: false,
                      entries: selected && variant === "ENTRY_NOT_RECORD"
                        ? [null]
                        : [{
                          path: "index.html",
                          mode: "100644",
                          type: "blob",
                          sha: "e".repeat(40),
                          size: content.length,
                        }],
                    },
                );
              case "READ_BLOB":
                return Promise.resolve(
                  selected && variant === "NOT_RECORD"
                    ? null
                    : selected && variant === "CONTRACT"
                    ? {}
                    : {
                      sha: "e".repeat(40),
                      encoding: "base64",
                      contentBase64: selected && variant === "BASE64"
                        ? "%%%invalid%%%"
                        : btoa(String.fromCharCode(...content)),
                      size: selected && variant === "SIZE"
                        ? content.length + 1
                        : content.length,
                    },
                );
              default:
                return Promise.reject(new Error("unexpected operation"));
            }
          },
        },
      },
    );
  const error = await assertRejects(() => inspect()) as Error & {
    postCreateSubphase?: string;
    snapshotReadbackCheck?: string;
  };
  assertEquals(
    error.postCreateSubphase,
    "LAB_POST_CREATE_SNAPSHOT_READBACK",
  );
  assertEquals(error.snapshotReadbackCheck, check);
}

function metadata(
  overrides: Partial<GitHubRepositoryMetadata> = {},
): GitHubRepositoryMetadata {
  return {
    repositoryId: EXPECTED.repositoryId,
    nodeId: "R_task13_existing_repository",
    owner: EXPECTED.owner,
    name: EXPECTED.repository,
    fullName: `${EXPECTED.owner}/${EXPECTED.repository}`,
    private: true,
    defaultBranch: "main",
    description: null,
    createdAt: "2026-09-15T09:45:30.111Z",
    ...overrides,
  };
}

function dependencies(overrides: Record<string, unknown> = {}) {
  const calls: Readonly<Record<string, unknown>>[] = [];
  const record = (kind: string, input: Readonly<Record<string, unknown>>) => {
    calls.push({ kind, ...input });
  };
  return {
    calls,
    value: {
      readMetadata: (input: Readonly<Record<string, unknown>>) => {
        record("READ_METADATA", input);
        return Promise.resolve(metadata());
      },
      readRef: (input: Readonly<Record<string, unknown>>) => {
        record("READ_REF", input);
        return Promise.resolve({ state: "PRESENT" as const, commitSha: SHA });
      },
      readSnapshot: (input: Readonly<Record<string, unknown>>) => {
        record("READ_SNAPSHOT", input);
        return Promise.resolve({
          treeSha256: EXPECTED.snapshotTreeSha256,
          unexpectedContent: false,
        });
      },
      readMarker: (input: Readonly<Record<string, unknown>>) => {
        record("READ_MARKER", input);
        return Promise.resolve({
          state: "PRESENT" as const,
          content: EXPECTED.markerContent,
        });
      },
      ...overrides,
    },
  };
}

async function inspect(overrides: Record<string, unknown> = {}) {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspector === "function",
    "read-only repository state inspector capability is missing",
  );
  const test = dependencies(overrides);
  return {
    result: await implementation.createGitHubRepositoryStateInspector(
      EXPECTED,
      test.value,
    )(),
    calls: test.calls,
  };
}

Deno.test("state inspector classifies an absent main ref as EMPTY_OR_UNINITIALIZED", async () => {
  const test = await inspect({
    readRef: () => Promise.resolve({ state: "ABSENT" as const }),
  });
  assertEquals(test.result, { state: "EMPTY_OR_UNINITIALIZED" });
});

Deno.test("state inspector classifies exact snapshot marker and provenance as ALREADY_COMPLETE", async () => {
  assertEquals((await inspect()).result, { state: "ALREADY_COMPLETE" });
});

Deno.test("completion proof inspector projects only server-read binding evidence", async () => {
  const implementation = await module();
  assert(
    typeof implementation.inspectGitHubRepositoryCompletionProof ===
      "function",
    "read-only repository completion proof capability is missing",
  );
  const test = dependencies();
  assertEquals(
    await implementation.inspectGitHubRepositoryCompletionProof(
      EXPECTED,
      test.value,
    )(),
    {
      state: "ALREADY_COMPLETE",
      proof: {
        providerRepositoryId: EXPECTED.repositoryId,
        providerNodeId: "R_task13_existing_repository",
        owner: EXPECTED.owner,
        name: EXPECTED.repository,
        visibility: "PRIVATE",
        defaultBranch: "main",
        repositoryMarkerCommitSha: SHA,
      },
    },
  );
});

Deno.test("completion proof inspector rejects every non-complete classification", async () => {
  const implementation = await module();
  assert(
    typeof implementation.inspectGitHubRepositoryCompletionProof ===
      "function",
  );
  const InspectionError = implementation.GitHubRepositoryStateInspectionError;
  assert(typeof InspectionError === "function");
  for (
    const overrides of [
      { readRef: () => Promise.resolve({ state: "ABSENT" as const }) },
      {
        readSnapshot: () =>
          Promise.resolve({
            treeSha256: "d".repeat(64),
            unexpectedContent: false,
          }),
      },
      { readMarker: () => Promise.resolve({ state: "ABSENT" as const }) },
    ]
  ) {
    const test = dependencies(overrides);
    await assertRejects(
      implementation.inspectGitHubRepositoryCompletionProof(
        EXPECTED,
        test.value,
      ),
      InspectionError,
      "REPOSITORY_STATE_UNCERTAIN",
    );
  }
});

Deno.test("state inspector classifies exact snapshot with marker 404 as MARKER_MISSING", async () => {
  const test = await inspect({
    readMarker: () => Promise.resolve({ state: "ABSENT" as const }),
  });
  assertEquals(test.result, { state: "MARKER_MISSING" });
});

Deno.test("state inspector classifies snapshot conflict as CONFLICT", async () => {
  const test = await inspect({
    readSnapshot: () =>
      Promise.resolve({ treeSha256: "d".repeat(64), unexpectedContent: false }),
  });
  assertEquals(test.result, { state: "CONFLICT" });
});

Deno.test("state inspector classifies marker provenance conflict as CONFLICT", async () => {
  const test = await inspect({
    readMarker: () =>
      Promise.resolve({ state: "PRESENT" as const, content: "{}" }),
  });
  assertEquals(test.result, { state: "CONFLICT" });
});

for (
  const [name, override] of [
    ["repository external ID", { repositoryId: "1371224565" }],
    ["owner", { owner: "other-owner" }],
    ["repository name", { name: "other-repository" }],
  ] as const
) {
  Deno.test(`state inspector fails closed on ${name} mismatch`, async () => {
    const implementation = await module();
    assert(
      typeof implementation.createGitHubRepositoryStateInspector === "function",
    );
    assert(
      typeof implementation.GitHubRepositoryStateInspectionError === "function",
    );
    const test = dependencies({
      readMetadata: () => Promise.resolve(metadata(override)),
    });
    await assertRejects(
      implementation.createGitHubRepositoryStateInspector(EXPECTED, test.value),
      implementation.GitHubRepositoryStateInspectionError,
      "REPOSITORY_IDENTITY_MISMATCH",
    );
    assertEquals(test.calls.some((call) => call.kind === "READ_REF"), false);
  });
}

Deno.test("snapshot observability maps all REF_READ predicates", async () => {
  for (const variant of ["HTTP", "NOT_RECORD", "CONTRACT"] as const) {
    await assertSnapshotReadbackCheck("REF_READ", variant);
  }
});

Deno.test("snapshot observability maps all COMMIT_READ predicates", async () => {
  for (const variant of ["HTTP", "NOT_RECORD", "CONTRACT"] as const) {
    await assertSnapshotReadbackCheck("COMMIT_READ", variant);
  }
});

Deno.test("snapshot observability maps all TREE_READ predicates", async () => {
  for (
    const variant of [
      "HTTP",
      "NOT_RECORD",
      "CONTRACT",
      "ENTRY_NOT_RECORD",
    ] as const
  ) {
    await assertSnapshotReadbackCheck("TREE_READ", variant);
  }
});

Deno.test("snapshot observability maps all BLOB_READ predicates", async () => {
  for (
    const variant of [
      "HTTP",
      "NOT_RECORD",
      "CONTRACT",
      "BASE64",
      "SIZE",
    ] as const
  ) {
    await assertSnapshotReadbackCheck("BLOB_READ", variant);
  }
});

Deno.test("snapshot observability is frozen, branded, immutable and cross-phase closed", async () => {
  const implementation = await module();
  assertEquals(implementation.GITHUB_SNAPSHOT_READBACK_CHECKS, [
    "REF_READ",
    "COMMIT_READ",
    "TREE_READ",
    "BLOB_READ",
    "UNKNOWN",
  ]);
  assertEquals(
    Object.isFrozen(implementation.GITHUB_SNAPSHOT_READBACK_CHECKS),
    true,
  );
  assert(
    typeof implementation.GitHubRepositoryStateInspectionError === "function",
  );
  const trusted = new implementation.GitHubRepositoryStateInspectionError(
    "REPOSITORY_STATE_UNCERTAIN",
    "LAB_POST_CREATE_SNAPSHOT_READBACK",
    "REF_READ",
  ) as Error & { snapshotReadbackCheck?: string };
  assertEquals(
    implementation.hasValidatedGitHubRepositoryStateInspectionSubphase?.(
      trusted,
    ),
    true,
  );
  assertThrows(
    () => Object.assign(trusted, { snapshotReadbackCheck: "BLOB_READ" }),
    TypeError,
  );
  const forged = Object.assign(
    Object.create(
      implementation.GitHubRepositoryStateInspectionError.prototype,
    ),
    {
      postCreateSubphase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
      snapshotReadbackCheck: "REF_READ",
    },
  );
  assertEquals(
    implementation.hasValidatedGitHubRepositoryStateInspectionSubphase?.(
      forged,
    ),
    false,
  );
  assertThrows(() =>
    new implementation.GitHubRepositoryStateInspectionError!(
      "REPOSITORY_STATE_UNCERTAIN",
      "LAB_POST_CREATE_MARKER_READBACK",
      "REF_READ",
    )
  );
  assertThrows(() =>
    new implementation.GitHubRepositoryStateInspectionError!(
      "REPOSITORY_STATE_UNCERTAIN",
      "LAB_POST_CREATE_SNAPSHOT_READBACK",
      "NOT_CLOSED",
    )
  );
});

for (
  const [name, boundary] of [
    ["metadata", "readMetadata"],
    ["ref", "readRef"],
    ["snapshot", "readSnapshot"],
    ["marker", "readMarker"],
  ] as const
) {
  Deno.test(`state inspector fails closed on ${name} transport uncertainty`, async () => {
    const implementation = await module();
    assert(
      typeof implementation.createGitHubRepositoryStateInspector === "function",
    );
    assert(
      typeof implementation.GitHubRepositoryStateInspectionError === "function",
    );
    const test = dependencies({
      [boundary]: () => Promise.reject(new Error("raw transport detail")),
    });
    const error = await assertRejects(
      implementation.createGitHubRepositoryStateInspector(EXPECTED, test.value),
      implementation.GitHubRepositoryStateInspectionError,
      "REPOSITORY_STATE_UNCERTAIN",
    );
    assertEquals(JSON.stringify(error).includes("raw transport detail"), false);
  });
}

Deno.test("state inspector treats unexpected reachable content as CONFLICT", async () => {
  const test = await inspect({
    readSnapshot: () =>
      Promise.resolve({
        treeSha256: EXPECTED.snapshotTreeSha256,
        unexpectedContent: true,
      }),
  });
  assertEquals(test.result, { state: "CONFLICT" });
});

Deno.test("state inspector source has no mutation or create dependency", async () => {
  const source = await Deno.readTextFile(
    new URL("./github-repository-state-inspector.ts", import.meta.url),
  ).catch(() => "");
  assert(
    source.length > 0,
    "read-only repository state inspector capability is missing",
  );
  for (
    const forbidden of [
      "CREATE_REPOSITORY",
      "createRepository",
      "createLab",
      "provider.provision",
      ".claim(",
      ".resume(",
      ".bind(",
      ".quarantine(",
      "DELETE",
      "PATCH",
      "PUT",
      "force",
    ]
  ) assertEquals(source.includes(forbidden), false, forbidden);
});

Deno.test("state inspector dependency interface exposes read capabilities only", async () => {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspector === "function",
  );
  const test = dependencies();
  assertEquals(Object.keys(test.value).sort(), [
    "readMarker",
    "readMetadata",
    "readRef",
    "readSnapshot",
  ]);
});

Deno.test("state inspector uses only exact expected LAB identity and scope", async () => {
  const test = await inspect();
  assertEquals(test.calls.map((call) => call.kind), [
    "READ_METADATA",
    "READ_REF",
    "READ_SNAPSHOT",
    "READ_MARKER",
  ]);
  for (const call of test.calls) {
    assertEquals(call.websiteWorkContextId, EXPECTED.websiteWorkContextId);
    assertEquals(call.repositoryId, EXPECTED.repositoryId);
    assertEquals(call.owner, EXPECTED.owner);
    assertEquals(call.repository, EXPECTED.repository);
  }
});

Deno.test("state inspection capability uses one read-only LAB token and GET primitives only", async () => {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspectionCapability ===
      "function",
  );
  const content = new TextEncoder().encode("canonical snapshot\n");
  const expected = {
    ...EXPECTED,
    snapshotTreeSha256: await computeGitHubSnapshotDigest([{
      path: "index.html",
      mode: "100644",
      type: "blob" as const,
      content,
    }]),
  };
  const tokenRequests: unknown[] = [];
  const httpOperations: GitHubHttpOperation[] = [];
  const inspect = implementation
    .createGitHubRepositoryStateInspectionCapability(
      {
        target: "TEST",
        organization: EXPECTED.owner,
        installationId: "161461160",
      },
      expected,
      {
        tokenBroker: {
          issue: (_config: unknown, request: unknown, authority: unknown) => {
            tokenRequests.push({ request, authority });
            return Promise.resolve({ token: `ghs_${"a".repeat(36)}` });
          },
        },
        http: {
          execute: (operation: GitHubHttpOperation) => {
            httpOperations.push(operation);
            switch (operation.kind) {
              case "REPOSITORY_METADATA":
                return Promise.resolve(metadata());
              case "READ_REF":
                return Promise.resolve({
                  ref: "refs/heads/main",
                  commitSha: SHA,
                });
              case "COMMIT_METADATA":
                return Promise.resolve({ sha: SHA, treeSha: "d".repeat(40) });
              case "REPOSITORY_TREE":
                return Promise.resolve({
                  sha: "d".repeat(40),
                  truncated: false,
                  entries: [
                    {
                      path: "index.html",
                      mode: "100644",
                      type: "blob",
                      sha: "e".repeat(40),
                      size: content.length,
                    },
                    {
                      path: ".lws/project.json",
                      mode: "100644",
                      type: "blob",
                      sha: "f".repeat(40),
                      size: EXPECTED.markerContent.length,
                    },
                  ],
                });
              case "READ_BLOB":
                return Promise.resolve({
                  sha: "e".repeat(40),
                  encoding: "base64",
                  contentBase64: btoa(String.fromCharCode(...content)),
                  size: content.length,
                });
              case "READ_PROJECT_MARKER":
                return Promise.resolve({
                  path: ".lws/project.json",
                  sha: "f".repeat(40),
                  encoding: "base64",
                  contentBase64: btoa(EXPECTED.markerContent),
                  size: EXPECTED.markerContent.length,
                });
              default:
                return Promise.reject(new Error("mutation operation reached"));
            }
          },
        },
      },
    );

  assertEquals(await inspect(), { state: "ALREADY_COMPLETE" });
  assertEquals(tokenRequests, [{
    request: {
      websiteWorkContextId: EXPECTED.websiteWorkContextId,
      target: "TEST",
      organization: EXPECTED.owner,
      operation: "LAB_REPOSITORY_READ",
      repositoryIds: [EXPECTED.repositoryId],
    },
    authority: {
      websiteWorkContextId: EXPECTED.websiteWorkContextId,
      target: "TEST",
      organization: EXPECTED.owner,
      repositoryIds: [EXPECTED.repositoryId],
    },
  }]);
  assertEquals(httpOperations.map((operation) => operation.kind), [
    "REPOSITORY_METADATA",
    "READ_REF",
    "COMMIT_METADATA",
    "REPOSITORY_TREE",
    "READ_BLOB",
    "READ_PROJECT_MARKER",
  ]);
});

Deno.test("state inspection capability accepts READ_REF metadata and uses the projected commit SHA downstream", async () => {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspectionCapability ===
      "function",
  );
  const content = new TextEncoder().encode("canonical snapshot\n");
  const expected = {
    ...EXPECTED,
    snapshotTreeSha256: await computeGitHubSnapshotDigest([{
      path: "index.html",
      mode: "100644",
      type: "blob" as const,
      content,
    }]),
  };
  const requestedTargets: string[] = [];
  const http = createGitHubHttpClient({
    fetch: (input, init) => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      const path = url.pathname;
      requestedTargets.push(`${path}${url.search}`);
      let body: unknown;
      if (path.endsWith("/git/ref/heads/main")) {
        body = {
          ref: "refs/heads/main",
          node_id: "REF_kwDOSyntheticMain",
          url:
            "https://api.github.com/repos/example/example/git/refs/heads/main",
          object: {
            type: "commit",
            sha: SHA,
            url:
              "https://api.github.com/repos/example/example/git/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          },
        };
      } else if (path.endsWith(`/commits/${SHA}`)) {
        body = { sha: SHA, commit: { tree: { sha: "d".repeat(40) } } };
      } else if (path.endsWith(`/git/trees/${"d".repeat(40)}`)) {
        body = {
          sha: "d".repeat(40),
          truncated: false,
          tree: [
            {
              path: "index.html",
              mode: "100644",
              type: "blob",
              sha: "e".repeat(40),
              size: content.length,
            },
            {
              path: ".lws/project.json",
              mode: "100644",
              type: "blob",
              sha: "f".repeat(40),
              size: EXPECTED.markerContent.length,
            },
          ],
        };
      } else if (path.endsWith(`/git/blobs/${"e".repeat(40)}`)) {
        body = {
          sha: "e".repeat(40),
          encoding: "base64",
          content: btoa(String.fromCharCode(...content)),
          size: content.length,
        };
      } else if (path.endsWith("/contents/.lws/project.json")) {
        body = {
          path: ".lws/project.json",
          sha: "f".repeat(40),
          encoding: "base64",
          content: btoa(EXPECTED.markerContent),
          size: EXPECTED.markerContent.length,
        };
      } else {
        body = {
          id: Number(EXPECTED.repositoryId),
          node_id: "R_kgDOSynthetic",
          owner: { login: EXPECTED.owner },
          name: EXPECTED.repository,
          full_name: `${EXPECTED.owner}/${EXPECTED.repository}`,
          private: true,
          default_branch: "main",
          description: null,
          created_at: "2026-09-13T12:00:00.000Z",
        };
      }
      return Promise.resolve(
        new Response(JSON.stringify(body), {
          status: 200,
          headers: { "content-type": "application/vnd.github+json" },
        }),
      );
    },
  });
  const inspect = implementation
    .createGitHubRepositoryStateInspectionCapability(
      { target: "TEST", organization: EXPECTED.owner },
      expected,
      {
        tokenBroker: {
          issue: () => Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
        },
        http,
      },
    );

  assertEquals(await inspect(), { state: "ALREADY_COMPLETE" });
  assertEquals(requestedTargets, [
    `/repos/${EXPECTED.owner}/${EXPECTED.repository}`,
    `/repos/${EXPECTED.owner}/${EXPECTED.repository}/git/ref/heads/main`,
    `/repos/${EXPECTED.owner}/${EXPECTED.repository}/commits/${SHA}`,
    `/repos/${EXPECTED.owner}/${EXPECTED.repository}/git/trees/${
      "d".repeat(40)
    }?recursive=1`,
    `/repos/${EXPECTED.owner}/${EXPECTED.repository}/git/blobs/${
      "e".repeat(40)
    }`,
    `/repos/${EXPECTED.owner}/${EXPECTED.repository}/contents/.lws/project.json?ref=${SHA}`,
  ]);
});

Deno.test("state inspection capability preserves REF_READ for malformed projected ref data", async () => {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspectionCapability ===
      "function",
  );
  assert(
    typeof implementation.GitHubRepositoryStateInspectionError === "function",
  );
  const InspectionError = implementation.GitHubRepositoryStateInspectionError;
  const http = createGitHubHttpClient({
    fetch: (input, init) => {
      const request = new Request(input, init);
      const isRef = request.url.endsWith("/git/ref/heads/main");
      const body = isRef
        ? {
          ref: "refs/heads/main",
          object: { type: "commit", sha: "not-a-sha" },
        }
        : {
          id: Number(EXPECTED.repositoryId),
          node_id: "R_kgDOSynthetic",
          owner: { login: EXPECTED.owner },
          name: EXPECTED.repository,
          full_name: `${EXPECTED.owner}/${EXPECTED.repository}`,
          private: true,
          default_branch: "main",
          description: null,
          created_at: "2026-09-13T12:00:00.000Z",
        };
      return Promise.resolve(
        new Response(JSON.stringify(body), {
          status: 200,
          headers: { "content-type": "application/vnd.github+json" },
        }),
      );
    },
  });
  const inspect = implementation
    .createGitHubRepositoryStateInspectionCapability(
      { target: "TEST", organization: EXPECTED.owner },
      EXPECTED,
      {
        tokenBroker: {
          issue: () => Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
        },
        http,
      },
    );
  const error = await assertRejects(
    () => inspect(),
    InspectionError,
  ) as Error & {
    postCreateSubphase?: string;
    snapshotReadbackCheck?: string;
  };
  assertEquals(error.postCreateSubphase, "LAB_POST_CREATE_SNAPSHOT_READBACK");
  assertEquals(error.snapshotReadbackCheck, "REF_READ");
});

Deno.test("state inspection preserves the trusted first-causal REF_READ pair", async () => {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspectionCapability ===
      "function",
  );
  assert(
    typeof implementation.getValidatedGitHubRepositoryRefReadDiagnostic ===
      "function",
    "trusted inspector REF_READ diagnostic accessor is missing",
  );
  assert(
    typeof implementation.GitHubRepositoryStateInspectionError === "function",
  );
  const InspectionError = implementation.GitHubRepositoryStateInspectionError;
  const operations: string[] = [];
  const http = createGitHubHttpClient({
    fetch: (input) => {
      const url = String(input);
      operations.push(url.includes("/git/ref/") ? "READ_REF" : "METADATA");
      return Promise.resolve(
        url.includes("/git/ref/")
          ? new Response("{}", {
            status: 403,
            headers: { "content-type": "application/json" },
          })
          : new Response(
            JSON.stringify({
              id: Number(EXPECTED.repositoryId),
              node_id: "R_task13_existing_repository",
              owner: { login: EXPECTED.owner },
              name: EXPECTED.repository,
              full_name: `${EXPECTED.owner}/${EXPECTED.repository}`,
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
  const inspect = implementation
    .createGitHubRepositoryStateInspectionCapability(
      { target: "TEST", organization: EXPECTED.owner },
      EXPECTED,
      {
        tokenBroker: {
          issue: () => Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
        },
        http,
      },
    );
  const error = await assertRejects(
    () => inspect(),
    InspectionError,
  );
  assertEquals(
    implementation.getValidatedGitHubRepositoryRefReadDiagnostic(error),
    { boundary: "HTTP_STATUS", code: "GITHUB_HTTP_FORBIDDEN" },
  );
  assertEquals(operations, ["METADATA", "READ_REF"]);

  const unknown = new InspectionError(
    "REPOSITORY_STATE_UNCERTAIN",
    "LAB_POST_CREATE_SNAPSHOT_READBACK",
    "REF_READ",
  );
  assertEquals(
    implementation.getValidatedGitHubRepositoryRefReadDiagnostic(unknown),
    { boundary: "UNKNOWN", code: "UNKNOWN" },
  );

  const trusted = new InspectionError(
    "REPOSITORY_STATE_UNCERTAIN",
    "LAB_POST_CREATE_SNAPSHOT_READBACK",
    "REF_READ",
    createGitHubRefReadDiagnostic(
      "HTTP_STATUS",
      "GITHUB_HTTP_FORBIDDEN",
    ),
  );
  assertEquals(
    implementation.getValidatedGitHubRepositoryRefReadDiagnostic(trusted),
    { boundary: "HTTP_STATUS", code: "GITHUB_HTTP_FORBIDDEN" },
  );
  let trapCalls = 0;
  const hostile = new Proxy({}, {
    get() {
      trapCalls++;
      throw new Error("raw proxy detail");
    },
  });
  assertEquals(
    implementation.getValidatedGitHubRepositoryRefReadDiagnostic(hostile),
    { boundary: "UNKNOWN", code: "UNKNOWN" },
  );
  assertEquals(trapCalls, 0);

  let prototypeTrapCalls = 0;
  const hostileThrowable = new Proxy({}, {
    getPrototypeOf() {
      prototypeTrapCalls++;
      throw new Error("raw prototype trap");
    },
  });
  const hostileInspect = implementation
    .createGitHubRepositoryStateInspectionCapability(
      { target: "TEST", organization: EXPECTED.owner },
      EXPECTED,
      {
        tokenBroker: {
          issue: () => Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
        },
        http: {
          execute: (operation: GitHubHttpOperation) =>
            operation.kind === "REPOSITORY_METADATA"
              ? Promise.resolve(metadata())
              : Promise.reject(hostileThrowable),
        },
      },
    );
  const closed = await assertRejects(hostileInspect, InspectionError);
  assertEquals(
    implementation.getValidatedGitHubRepositoryRefReadDiagnostic(closed),
    { boundary: "UNKNOWN", code: "UNKNOWN" },
  );
  assertEquals(prototypeTrapCalls, 0);
});

Deno.test("state inspection capability identifies all five recovery readback boundaries", async () => {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspectionCapability ===
      "function",
  );
  assert(
    typeof implementation.GitHubRepositoryStateInspectionError === "function",
  );
  const content = new TextEncoder().encode("canonical snapshot\n");
  const expected = {
    ...EXPECTED,
    snapshotTreeSha256: await computeGitHubSnapshotDigest([{
      path: "index.html",
      mode: "100644",
      type: "blob" as const,
      content,
    }]),
  };
  const scenarios = [
    ["TOKEN", "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE"],
    ["TOKEN_MALFORMED", "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE"],
    ["REPOSITORY_METADATA", "LAB_POST_CREATE_METADATA_READ"],
    ["READ_REF", "LAB_POST_CREATE_SNAPSHOT_READBACK"],
    ["REF_MALFORMED", "LAB_POST_CREATE_SNAPSHOT_READBACK"],
    ["COMMIT_MALFORMED", "LAB_POST_CREATE_SNAPSHOT_READBACK"],
    ["TREE_MALFORMED", "LAB_POST_CREATE_SNAPSHOT_READBACK"],
    ["BLOB_MALFORMED", "LAB_POST_CREATE_SNAPSHOT_READBACK"],
    ["READ_PROJECT_MARKER", "LAB_POST_CREATE_MARKER_READBACK"],
    ["MARKER_MALFORMED", "LAB_POST_CREATE_MARKER_READBACK"],
    ["MARKER_DECODE", "LAB_POST_CREATE_PROVENANCE_VALIDATE"],
  ] as const;
  for (const [failure, subphase] of scenarios) {
    const inspect = implementation
      .createGitHubRepositoryStateInspectionCapability(
        { target: "TEST", organization: EXPECTED.owner },
        expected,
        {
          tokenBroker: {
            issue: () =>
              failure === "TOKEN"
                ? Promise.reject(new Error("raw token"))
                : failure === "TOKEN_MALFORMED"
                ? Promise.resolve({} as never)
                : Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
          },
          http: {
            execute: (operation: GitHubHttpOperation) => {
              if (operation.kind === failure) {
                return Promise.reject(new Error("raw HTTP"));
              }
              switch (operation.kind) {
                case "REPOSITORY_METADATA":
                  return Promise.resolve(metadata());
                case "READ_REF":
                  return Promise.resolve(
                    failure === "REF_MALFORMED" ? {} : {
                      ref: "refs/heads/main",
                      commitSha: SHA,
                    },
                  );
                case "COMMIT_METADATA":
                  return Promise.resolve(
                    failure === "COMMIT_MALFORMED"
                      ? {}
                      : { sha: SHA, treeSha: "d".repeat(40) },
                  );
                case "REPOSITORY_TREE":
                  return Promise.resolve(
                    failure === "TREE_MALFORMED" ? {} : {
                      sha: "d".repeat(40),
                      truncated: false,
                      entries: [
                        {
                          path: "index.html",
                          mode: "100644",
                          type: "blob",
                          sha: "e".repeat(40),
                          size: content.length,
                        },
                        {
                          path: ".lws/project.json",
                          mode: "100644",
                          type: "blob",
                          sha: "f".repeat(40),
                          size: EXPECTED.markerContent.length,
                        },
                      ],
                    },
                  );
                case "READ_BLOB":
                  return Promise.resolve(
                    failure === "BLOB_MALFORMED" ? {} : {
                      sha: "e".repeat(40),
                      encoding: "base64",
                      contentBase64: btoa(String.fromCharCode(...content)),
                      size: content.length,
                    },
                  );
                case "READ_PROJECT_MARKER":
                  if (failure === "MARKER_MALFORMED") {
                    return Promise.resolve({});
                  }
                  return Promise.resolve({
                    path: ".lws/project.json",
                    sha: "f".repeat(40),
                    encoding: "base64",
                    contentBase64: failure === "MARKER_DECODE"
                      ? "%%%invalid%%%"
                      : btoa(EXPECTED.markerContent),
                    size: EXPECTED.markerContent.length,
                  });
                default:
                  return Promise.reject(new Error("unexpected operation"));
              }
            },
          },
        },
      );
    const error = await assertRejects(
      () => inspect(),
      implementation.GitHubRepositoryStateInspectionError,
    ) as Error & { postCreateSubphase?: string };
    assertEquals(error.postCreateSubphase, subphase, failure);
  }
});

Deno.test("state inspector rejects accessor-backed expected authority before reads", async () => {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspector === "function",
  );
  const accessorExpected = { ...EXPECTED } as Record<string, unknown>;
  Object.defineProperty(accessorExpected, "repositoryId", {
    get: () => EXPECTED.repositoryId,
    enumerable: true,
  });
  const test = dependencies();
  await assertRejects(async () => {
    implementation.createGitHubRepositoryStateInspector!(
      accessorExpected as typeof EXPECTED,
      test.value,
    );
  });
  assertEquals(test.calls, []);
});

for (
  const [missingKind, expectedState] of [
    ["READ_REF", "EMPTY_OR_UNINITIALIZED"],
    ["READ_PROJECT_MARKER", "MARKER_MISSING"],
  ] as const
) {
  Deno.test(`state inspection capability treats only ${missingKind} 404 as ${expectedState}`, async () => {
    const implementation = await module();
    assert(
      typeof implementation.createGitHubRepositoryStateInspectionCapability ===
        "function",
    );
    const content = new TextEncoder().encode("canonical snapshot\n");
    const expected = {
      ...EXPECTED,
      snapshotTreeSha256: await computeGitHubSnapshotDigest([{
        path: "index.html",
        mode: "100644",
        type: "blob" as const,
        content,
      }]),
    };
    const httpOperations: GitHubHttpOperation[] = [];
    const inspect = implementation
      .createGitHubRepositoryStateInspectionCapability(
        { target: "TEST", organization: EXPECTED.owner },
        expected,
        {
          tokenBroker: {
            issue: () => Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
          },
          http: {
            execute: (operation: GitHubHttpOperation) => {
              httpOperations.push(operation);
              if (operation.kind === missingKind) {
                return Promise.reject(
                  new GitHubHttpError(
                    "GITHUB_HTTP_NOT_FOUND",
                    null,
                    null,
                    undefined,
                    "HTTP_STATUS",
                  ),
                );
              }
              switch (operation.kind) {
                case "REPOSITORY_METADATA":
                  return Promise.resolve(metadata());
                case "READ_REF":
                  return Promise.resolve({
                    ref: "refs/heads/main",
                    commitSha: SHA,
                  });
                case "COMMIT_METADATA":
                  return Promise.resolve({ sha: SHA, treeSha: "d".repeat(40) });
                case "REPOSITORY_TREE":
                  return Promise.resolve({
                    sha: "d".repeat(40),
                    truncated: false,
                    entries: [{
                      path: "index.html",
                      mode: "100644",
                      type: "blob",
                      sha: "e".repeat(40),
                      size: content.length,
                    }],
                  });
                case "READ_BLOB":
                  return Promise.resolve({
                    sha: "e".repeat(40),
                    encoding: "base64",
                    contentBase64: btoa(String.fromCharCode(...content)),
                    size: content.length,
                  });
                default:
                  return Promise.reject(new Error("unexpected operation"));
              }
            },
          },
        },
      );
    assertEquals(await inspect(), { state: expectedState });
    assertEquals(
      httpOperations.map((operation) => operation.kind),
      missingKind === "READ_REF"
        ? ["REPOSITORY_METADATA", "READ_REF", "REPOSITORY_METADATA"]
        : [
          "REPOSITORY_METADATA",
          "READ_REF",
          "COMMIT_METADATA",
          "REPOSITORY_TREE",
          "READ_BLOB",
          "READ_PROJECT_MARKER",
          "REPOSITORY_METADATA",
          "COMMIT_METADATA",
        ],
    );
  });
}

function graphQlEmptyProofResponse(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    data: {
      repository: {
        databaseId: Number(EXPECTED.repositoryId),
        nameWithOwner: `${EXPECTED.owner}/${EXPECTED.repository}`,
        isEmpty: true,
        defaultBranchRef: null,
        ...overrides,
      },
    },
  };
}

async function conflictProofInspector(
  refStatus: 409 | 422,
  graphQlResponse: Response,
) {
  const implementation = await module();
  assert(
    typeof implementation.createGitHubRepositoryStateInspectionCapability ===
      "function",
  );
  const operations: string[] = [];
  const http = createGitHubHttpClient({
    fetch(input) {
      const url = String(input);
      if (url === "https://api.github.com/graphql") {
        operations.push("REPOSITORY_EMPTY_PROOF");
        return Promise.resolve(graphQlResponse);
      }
      if (url.includes("/git/ref/")) {
        operations.push("READ_REF");
        return Promise.resolve(
          new Response("{}", {
            status: refStatus,
            headers: { "content-type": "application/json" },
          }),
        );
      }
      operations.push("REPOSITORY_METADATA");
      return Promise.resolve(
        new Response(
          JSON.stringify({
            id: Number(EXPECTED.repositoryId),
            node_id: "R_task13_existing_repository",
            owner: { login: EXPECTED.owner },
            name: EXPECTED.repository,
            full_name: `${EXPECTED.owner}/${EXPECTED.repository}`,
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
  const inspect = implementation
    .createGitHubRepositoryStateInspectionCapability(
      { target: "TEST", organization: EXPECTED.owner },
      EXPECTED,
      {
        tokenBroker: {
          issue: () => Promise.resolve({ token: `ghs_${"a".repeat(36)}` }),
        },
        http,
      },
    );
  return { inspect, operations };
}

Deno.test("READ_REF 409 classifies empty only after exact trusted GraphQL proof", async () => {
  const test = await conflictProofInspector(
    409,
    new Response(JSON.stringify(graphQlEmptyProofResponse()), {
      headers: { "content-type": "application/json" },
    }),
  );
  assertEquals(await test.inspect(), { state: "EMPTY_OR_UNINITIALIZED" });
  assertEquals(test.operations, [
    "REPOSITORY_METADATA",
    "READ_REF",
    "REPOSITORY_EMPTY_PROOF",
  ]);
});

Deno.test("READ_REF 409 remains closed for nonempty mismatched errored unauthorized or malformed proof", async () => {
  const cases = [
    new Response(
      JSON.stringify(graphQlEmptyProofResponse({ isEmpty: false })),
      {
        headers: { "content-type": "application/json" },
      },
    ),
    new Response(
      JSON.stringify(graphQlEmptyProofResponse({ databaseId: 1 })),
      { headers: { "content-type": "application/json" } },
    ),
    new Response(
      JSON.stringify({
        ...graphQlEmptyProofResponse(),
        errors: [{ type: "FORBIDDEN" }],
      }),
      { headers: { "content-type": "application/json" } },
    ),
    new Response("{}", {
      status: 401,
      headers: { "content-type": "application/json" },
    }),
    new Response(JSON.stringify({ data: { repository: {} } }), {
      headers: { "content-type": "application/json" },
    }),
  ];
  for (const response of cases) {
    const test = await conflictProofInspector(409, response);
    await assertRejects(() => test.inspect());
    assertEquals(test.operations, [
      "REPOSITORY_METADATA",
      "READ_REF",
      "REPOSITORY_EMPTY_PROOF",
    ]);
  }
});

Deno.test("READ_REF 422 never enters the empty-proof route", async () => {
  const test = await conflictProofInspector(
    422,
    new Response(JSON.stringify(graphQlEmptyProofResponse()), {
      headers: { "content-type": "application/json" },
    }),
  );
  await assertRejects(() => test.inspect());
  assertEquals(test.operations, ["REPOSITORY_METADATA", "READ_REF"]);
});

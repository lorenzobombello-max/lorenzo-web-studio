import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { GitHubHttpOperation } from "../_shared/github-http.ts";
import { GitHubHttpError } from "../_shared/github-http.ts";
import { computeGitHubSnapshotDigest } from "../_shared/github-snapshot-digest.ts";
import type { GitHubTokenRequest } from "../_shared/github-app-token.ts";
import { GitHubLabPostCreateDiagnosticError } from "../_shared/repository-provisioning-diagnostics.ts";

const CONTEXT_ID = "33a61b58-1d55-4624-bdb7-3c724d35ebcc";
const WORKSPACE_ID = "4dfe44a5-60d0-4728-b62b-ef87aa838976";
const OPERATION_ID = "e646ae44-ec5d-46b6-96e3-b1023b9e1b68";
const REPOSITORY_ID = "1371224564";
const REPOSITORY = "lws-web-33a61b581d554624bdb73c724d35ebcc";
const CONTENT = new TextEncoder().encode("canonical starter\n");
const SOURCE_COMMIT = "a".repeat(40);
const BOOTSTRAP_COMMIT = "8".repeat(40);

function bootstrapContent(): string {
  return `${
    JSON.stringify(
      {
        schema_version: 1,
        purpose: "TASK13_EMPTY_REPOSITORY_RECOVERY",
        environment: "TEST",
        organization: "lorenzo-web-solutions-lab",
        repository: REPOSITORY,
        repository_id: REPOSITORY_ID,
        website_work_context_id: CONTEXT_ID,
        website_workspace_id: WORKSPACE_ID,
        repository_provisioning_operation_id: OPERATION_ID,
      },
      null,
      2,
    )
  }\n`;
}

type Module = Readonly<{
  createTask13PostCreateRecoveryWriteCapability?: (
    config: unknown,
    dependencies: unknown,
  ) => Readonly<{
    writeCanonicalSnapshotToEmptyRepository(
      authority: unknown,
    ): Promise<unknown>;
    writeMissingMarker(authority: unknown): Promise<unknown>;
  }>;
}>;

async function implementation(): Promise<Module> {
  try {
    return await import("./post-create-recovery-write-capability.ts") as Module;
  } catch {
    return {};
  }
}

Deno.test("recovery write adapter source has no repository-create capability", async () => {
  const source = await Deno.readTextFile(
    new URL("./post-create-recovery-write-capability.ts", import.meta.url),
  );
  assertEquals(source.includes("GitHubHttpClient"), false);
  assertEquals(source.includes("CREATE_REPOSITORY"), false);
});

async function fixture(
  failure?: string,
  malformed?: string,
) {
  const treeDigest = await computeGitHubSnapshotDigest([{
    path: "README.md",
    mode: "100644",
    type: "blob",
    content: CONTENT,
  }]);
  const config = {
    production: {
      target: "PRODUCTION",
      appId: "4932372",
      installationId: "161436785",
      organization: "lorenzo-web-solutions",
      templateOwner: "lorenzo-web-solutions",
      templateName: "lws-website-starter",
      templateRepositoryId: "1368684860",
      starterVersion: "1.0.0",
      starterCommitSha: SOURCE_COMMIT,
      starterTreeSha256: treeDigest,
    },
    lab: {
      target: "TEST",
      appId: "4932372",
      installationId: "161461160",
      organization: "lorenzo-web-solutions-lab",
      templateOwner: "lorenzo-web-solutions",
      templateName: "lws-website-starter",
      templateRepositoryId: "1368684860",
      starterVersion: "1.0.0",
      starterCommitSha: SOURCE_COMMIT,
      starterTreeSha256: treeDigest,
    },
  };
  const markerContent = '{"canonical":true}\n';
  const authority = Object.freeze({
    operationId: OPERATION_ID,
    websiteWorkContextId: CONTEXT_ID,
    websiteWorkspaceId: WORKSPACE_ID,
    repositoryId: REPOSITORY_ID,
    owner: "lorenzo-web-solutions-lab",
    repository: REPOSITORY,
    installationId: "161461160",
    starterSource: "lorenzo-web-solutions/lws-website-starter",
    starterVersion: "1.0.0",
    starterCommitSha: SOURCE_COMMIT,
    starterTreeSha256: treeDigest,
    markerContent,
  });
  const tokenRequests: GitHubTokenRequest[] = [];
  const httpOperations: GitHubHttpOperation[] = [];
  const module = await implementation();
  assert(
    typeof module.createTask13PostCreateRecoveryWriteCapability === "function",
    "post-create recovery write capability is missing",
  );
  const capability = module.createTask13PostCreateRecoveryWriteCapability(
    config,
    {
      tokenBroker: {
        issue(_config: unknown, request: GitHubTokenRequest) {
          tokenRequests.push(request);
          if (failure === `TOKEN_${request.operation}`) {
            return Promise.reject(new Error("raw token secret"));
          }
          return Promise.resolve({ token: `ghs_${"a".repeat(36)}` });
        },
      },
      http: {
        execute(operation: GitHubHttpOperation) {
          httpOperations.push(operation);
          if (
            (failure === "CREATE_BOOTSTRAP_FILE" ||
              failure === "CREATE_BOOTSTRAP_FILE_READBACK") &&
            operation.kind === "CREATE_BOOTSTRAP_FILE"
          ) {
            return Promise.reject(
              new GitHubHttpError("GITHUB_HTTP_NETWORK_ERROR"),
            );
          }
          if (
            failure === "CREATE_BOOTSTRAP_FILE_READBACK" &&
            operation.kind === "READ_BOOTSTRAP_FILE"
          ) return Promise.reject(new Error("raw readback secret"));
          if (failure === operation.kind) {
            return Promise.reject(new Error("raw HTTP secret"));
          }
          if (failure === `${operation.kind}_CONFLICT`) {
            return Promise.reject(new GitHubHttpError("GITHUB_HTTP_CONFLICT"));
          }
          switch (operation.kind) {
            case "REPOSITORY_METADATA":
              if (operation.repository === REPOSITORY) {
                return Promise.resolve({
                  repositoryId: REPOSITORY_ID,
                  nodeId: "R_target_repository",
                  owner: "lorenzo-web-solutions-lab",
                  name: REPOSITORY,
                  fullName: `lorenzo-web-solutions-lab/${REPOSITORY}`,
                  private: true,
                  defaultBranch: "main",
                  description: null,
                  createdAt: "2026-09-15T00:00:00Z",
                });
              }
              return Promise.resolve({
                repositoryId: "1368684860",
                nodeId: "R_source_repository",
                owner: "lorenzo-web-solutions",
                name: "lws-website-starter",
                fullName: "lorenzo-web-solutions/lws-website-starter",
                private: true,
                defaultBranch: "main",
                description: null,
                createdAt: "2026-09-15T00:00:00Z",
              });
            case "REPOSITORY_TREE":
              if (operation.repository === REPOSITORY) {
                return Promise.resolve({
                  sha: "6".repeat(40),
                  truncated: false,
                  entries: [{
                    path: ".lws",
                    mode: "040000",
                    type: "tree",
                    sha: "5".repeat(40),
                  }, {
                    path: ".lws/bootstrap.json",
                    mode: "100644",
                    type: "blob",
                    sha: "7".repeat(40),
                    size: bootstrapContent().length,
                  }],
                });
              }
              return Promise.resolve({
                sha: SOURCE_COMMIT,
                truncated: false,
                entries: [{
                  path: "README.md",
                  mode: "100644",
                  type: "blob",
                  sha: "b".repeat(40),
                  size: CONTENT.length,
                }],
              });
            case "READ_BLOB":
              return Promise.resolve({
                sha: "b".repeat(40),
                encoding: "base64",
                contentBase64: btoa(String.fromCharCode(...CONTENT)),
                size: CONTENT.length,
              });
            case "CREATE_BOOTSTRAP_FILE":
              return Promise.resolve({
                path: ".lws/bootstrap.json",
                contentSha: "7".repeat(40),
                commitSha: BOOTSTRAP_COMMIT,
                parentCount: malformed === "BOOTSTRAP_PARENT" ? 1 : 0,
              });
            case "READ_BOOTSTRAP_FILE": {
              const content = malformed === "FOREIGN_BOOTSTRAP"
                ? "foreign\n"
                : bootstrapContent();
              return Promise.resolve({
                path: ".lws/bootstrap.json",
                sha: "7".repeat(40),
                encoding: "base64",
                contentBase64: btoa(content),
                size: content.length,
              });
            }
            case "READ_BOOTSTRAP_COMMIT":
              return Promise.resolve({
                sha: malformed === "DESCENDANT_HEAD"
                  ? "9".repeat(40)
                  : BOOTSTRAP_COMMIT,
                treeSha: "6".repeat(40),
                parentCount: malformed === "DESCENDANT_HEAD" ? 1 : 0,
              });
            case "READ_REF":
              return Promise.resolve({
                ref: "refs/heads/main",
                commitSha: malformed === "DESCENDANT_HEAD"
                  ? "9".repeat(40)
                  : BOOTSTRAP_COMMIT,
              });
            case "CREATE_BLOB":
              return Promise.resolve({ sha: "c".repeat(40) });
            case "CREATE_TREE":
              return Promise.resolve({ sha: "d".repeat(40) });
            case "CREATE_COMMIT":
              return Promise.resolve({ sha: "e".repeat(40) });
            case "UPDATE_REF":
              return Promise.resolve({
                ref: "refs/heads/main",
                commitSha: malformed === "UPDATE_REF"
                  ? "wrong"
                  : "e".repeat(40),
              });
            case "WRITE_PROJECT_MARKER":
              return Promise.resolve({
                contentSha: "f".repeat(40),
                commitSha: malformed === "WRITE_PROJECT_MARKER"
                  ? "wrong"
                  : "1".repeat(40),
              });
            default:
              return Promise.reject(new Error("unexpected operation"));
          }
        },
      },
    },
  );
  return {
    authority,
    capability,
    tokenRequests,
    httpOperations,
    markerContent,
  };
}

Deno.test("empty recovery capability uses exact approved canonical initial-write sequence", async () => {
  const test = await fixture();
  assertEquals(
    await test.capability.writeCanonicalSnapshotToEmptyRepository(
      test.authority,
    ),
    { outcome: "WRITTEN" },
  );
  assertEquals(test.tokenRequests.map((request) => request.operation), [
    "LAB_REPOSITORY_WRITE",
    "STARTER_SNAPSHOT_READ",
  ]);
  assertEquals(test.httpOperations.map((operation) => operation.kind), [
    "REPOSITORY_METADATA",
    "REPOSITORY_TREE",
    "READ_BLOB",
    "REPOSITORY_METADATA",
    "CREATE_BOOTSTRAP_FILE",
    "READ_REF",
    "CREATE_BLOB",
    "CREATE_TREE",
    "CREATE_COMMIT",
    "UPDATE_REF",
    "WRITE_PROJECT_MARKER",
  ]);
  assertEquals(
    test.httpOperations.some((operation) =>
      operation.kind === "CREATE_REPOSITORY" || operation.kind === "CREATE_REF"
    ),
    false,
  );
  const bootstrap = test.httpOperations.find((operation) =>
    operation.kind === "CREATE_BOOTSTRAP_FILE"
  ) as Extract<GitHubHttpOperation, { kind: "CREATE_BOOTSTRAP_FILE" }>;
  assertEquals(atob(bootstrap.contentBase64), bootstrapContent());
  assertEquals("sha" in bootstrap, false);
  const tree = test.httpOperations.find((operation) =>
    operation.kind === "CREATE_TREE"
  ) as Extract<GitHubHttpOperation, { kind: "CREATE_TREE" }>;
  assertEquals(
    tree.entries.some((entry) => entry.path === ".lws/bootstrap.json"),
    false,
  );
  const commit = test.httpOperations.find((operation) =>
    operation.kind === "CREATE_COMMIT"
  ) as Extract<GitHubHttpOperation, { kind: "CREATE_COMMIT" }>;
  assertEquals(commit.parentSha, BOOTSTRAP_COMMIT);
  const update = test.httpOperations.find((operation) =>
    operation.kind === "UPDATE_REF"
  ) as Extract<GitHubHttpOperation, { kind: "UPDATE_REF" }>;
  assertEquals(update.force, false);
});

Deno.test("marker recovery capability writes only the create-once marker", async () => {
  const test = await fixture();
  assertEquals(await test.capability.writeMissingMarker(test.authority), {
    outcome: "WRITTEN",
  });
  assertEquals(test.tokenRequests.map((request) => request.operation), [
    "LAB_REPOSITORY_WRITE",
  ]);
  assertEquals(test.httpOperations.map((operation) => operation.kind), [
    "WRITE_PROJECT_MARKER",
  ]);
  const marker = test.httpOperations[0] as Extract<GitHubHttpOperation, {
    kind: "WRITE_PROJECT_MARKER";
  }>;
  assertEquals(atob(marker.contentBase64), test.markerContent);
  assertEquals("sha" in marker, false);
});

Deno.test("response loss resumes only after exact bootstrap readback and never retries PUT", async () => {
  const test = await fixture("CREATE_BOOTSTRAP_FILE");
  assertEquals(
    await test.capability.writeCanonicalSnapshotToEmptyRepository(
      test.authority,
    ),
    { outcome: "WRITTEN" },
  );
  assertEquals(
    test.httpOperations.filter((operation) =>
      operation.kind === "CREATE_BOOTSTRAP_FILE"
    ).length,
    1,
  );
  assertEquals(
    test.httpOperations.filter((operation) =>
      operation.kind === "READ_BOOTSTRAP_FILE"
    ).length,
    1,
  );
  const resumeOperations = test.httpOperations.filter((operation) =>
    [
      "READ_REF",
      "READ_BOOTSTRAP_FILE",
      "READ_BOOTSTRAP_COMMIT",
      "REPOSITORY_TREE",
    ].includes(operation.kind) && "repository" in operation &&
    operation.repository === REPOSITORY
  );
  assertEquals(resumeOperations.map((operation) => operation.kind), [
    "READ_REF",
    "READ_BOOTSTRAP_FILE",
    "READ_BOOTSTRAP_COMMIT",
    "REPOSITORY_TREE",
  ]);
  const bootstrapRead = resumeOperations[1] as Extract<GitHubHttpOperation, {
    kind: "READ_BOOTSTRAP_FILE";
  }>;
  assertEquals(bootstrapRead.ref, BOOTSTRAP_COMMIT);
});

Deno.test("response loss with exact bootstrap on a foreign descendant HEAD stops closed", async () => {
  const test = await fixture("CREATE_BOOTSTRAP_FILE", "DESCENDANT_HEAD");
  await assertRejects(() =>
    test.capability.writeCanonicalSnapshotToEmptyRepository(test.authority)
  );
  assertEquals(
    test.httpOperations.filter((operation) =>
      operation.kind === "CREATE_BOOTSTRAP_FILE"
    ).length,
    1,
  );
  assertEquals(
    test.httpOperations.some((operation) =>
      operation.kind === "CREATE_BLOB" || operation.kind === "UPDATE_REF"
    ),
    false,
  );
});

Deno.test("foreign bootstrap readback and externally parented 201 stop before canonical writes", async () => {
  for (
    const scenario of [
      ["CREATE_BOOTSTRAP_FILE", "FOREIGN_BOOTSTRAP"],
      ["CREATE_BOOTSTRAP_FILE_CONFLICT", "FOREIGN_BOOTSTRAP"],
      [undefined, "BOOTSTRAP_PARENT"],
    ] as const
  ) {
    const test = await fixture(...scenario);
    await assertRejects(() =>
      test.capability.writeCanonicalSnapshotToEmptyRepository(test.authority)
    );
    assertEquals(
      test.httpOperations.filter((operation) =>
        operation.kind === "CREATE_BOOTSTRAP_FILE"
      ).length,
      1,
    );
    assertEquals(
      test.httpOperations.some((operation) =>
        operation.kind === "CREATE_BLOB" || operation.kind === "UPDATE_REF"
      ),
      false,
    );
  }
});

Deno.test("non-fast-forward publication stops without force or overwrite retry", async () => {
  const test = await fixture("UPDATE_REF_CONFLICT");
  await assertRejects(() =>
    test.capability.writeCanonicalSnapshotToEmptyRepository(test.authority)
  );
  const updates = test.httpOperations.filter((operation) =>
    operation.kind === "UPDATE_REF"
  ) as Array<Extract<GitHubHttpOperation, { kind: "UPDATE_REF" }>>;
  assertEquals(updates.length, 1);
  assertEquals(updates[0].force, false);
  assertEquals(
    test.httpOperations.some((operation) =>
      operation.kind === "WRITE_PROJECT_MARKER"
    ),
    false,
  );
});

Deno.test("marker already-exists conflict remains a non-destructive race outcome", async () => {
  const marker = await fixture("WRITE_PROJECT_MARKER_CONFLICT");
  assertEquals(
    await marker.capability.writeCanonicalSnapshotToEmptyRepository(
      marker.authority,
    ),
    {
      outcome: "RACE",
    },
  );
  assertEquals(
    marker.httpOperations.filter((operation) =>
      operation.kind === "WRITE_PROJECT_MARKER"
    ).length,
    1,
  );
});

Deno.test("write capability maps first causal failures to existing subphases", async () => {
  const scenarios = [
    ["TOKEN_LAB_REPOSITORY_WRITE", "LAB_POST_CREATE_WRITE_TOKEN_ACQUIRE"],
    ["TOKEN_STARTER_SNAPSHOT_READ", "LAB_POST_CREATE_SNAPSHOT_PREPARE"],
    ["REPOSITORY_METADATA", "LAB_POST_CREATE_SNAPSHOT_PREPARE"],
    ["REPOSITORY_TREE", "LAB_POST_CREATE_SNAPSHOT_PREPARE"],
    ["READ_BLOB", "LAB_POST_CREATE_SNAPSHOT_PREPARE"],
    ["CREATE_BOOTSTRAP_FILE_READBACK", "LAB_POST_CREATE_REF_WRITE"],
    ["CREATE_BLOB", "LAB_POST_CREATE_BLOB_WRITE"],
    ["CREATE_TREE", "LAB_POST_CREATE_TREE_WRITE"],
    ["CREATE_COMMIT", "LAB_POST_CREATE_COMMIT_WRITE"],
    ["UPDATE_REF", "LAB_POST_CREATE_REF_WRITE"],
    ["WRITE_PROJECT_MARKER", "LAB_POST_CREATE_MARKER_WRITE"],
  ] as const;
  for (const [failure, subphase] of scenarios) {
    const test = await fixture(failure);
    const error = await assertRejects(
      () =>
        test.capability.writeCanonicalSnapshotToEmptyRepository(test.authority),
      GitHubLabPostCreateDiagnosticError,
    );
    assertEquals(error.subphase, subphase, failure);
    assertEquals(JSON.stringify(error).includes("secret"), false);
  }
});

Deno.test("write result validation is closed and never retries a mutation", async () => {
  for (const malformed of ["UPDATE_REF", "WRITE_PROJECT_MARKER"] as const) {
    const test = await fixture(undefined, malformed);
    const error = await assertRejects(
      () =>
        test.capability.writeCanonicalSnapshotToEmptyRepository(test.authority),
      GitHubLabPostCreateDiagnosticError,
    );
    assertEquals(error.subphase, "LAB_POST_CREATE_WRITE_RESULT_VALIDATE");
    const kind = malformed as GitHubHttpOperation["kind"];
    assertEquals(
      test.httpOperations.filter((operation) => operation.kind === kind).length,
      1,
    );
  }
});

Deno.test("write capability rejects forged authority before tokens or HTTP", async () => {
  const test = await fixture();
  for (
    const invalid of [
      { ...test.authority, repositoryId: "invalid" },
      { ...test.authority, owner: "other-owner" },
      { ...test.authority, repository: "other-repository" },
      { ...test.authority, markerContent: "" },
      Object.assign(Object.create({ forged: true }), test.authority),
    ]
  ) {
    await assertRejects(() =>
      test.capability.writeCanonicalSnapshotToEmptyRepository(invalid)
    );
  }
  assertEquals(test.tokenRequests, []);
  assertEquals(test.httpOperations, []);
});

Deno.test("write capability rejects accessor-backed authority before side effects", async () => {
  const test = await fixture();
  const accessorAuthority = { ...test.authority } as Record<string, unknown>;
  Object.defineProperty(accessorAuthority, "repositoryId", {
    get: () => REPOSITORY_ID,
    enumerable: true,
  });
  await assertRejects(() =>
    test.capability.writeCanonicalSnapshotToEmptyRepository(accessorAuthority)
  );
  assertEquals(test.tokenRequests, []);
  assertEquals(test.httpOperations, []);
});

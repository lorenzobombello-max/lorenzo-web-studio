import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  type GitHubTokenAuthority,
  GitHubTokenBrokerError,
  type GitHubTokenRequest,
} from "./github-app-token.ts";
import { GitHubHttpError, type GitHubHttpOperation } from "./github-http.ts";
import {
  computeSnapshotDigest,
  GitHubRepositoryProviderError,
} from "./github-repository-provider.ts";
import {
  createGitHubLabRepositoryMetadataReader,
  createGitHubRepositoryRuntime,
  GitHubLabPrivateVisibilityUnprovenError,
} from "./github-repository-runtime.ts";
import type {
  RepositoryProvisioningAuthorityV2,
  RepositoryProvisioningCommandV2,
} from "./repository-provisioning.ts";
import { GitHubTokenAcquireDiagnosticError } from "./repository-provisioning-diagnostics.ts";
import type { RepositoryProvisioningRuntimeStoreV2 } from "./repository-provisioning-store-v2.ts";

const WORKSPACE_ID = "d2110000-0000-4000-8000-000000000001";
const CONTEXT_ID = "d2120000-0000-4000-8000-000000000001";
const IDEMPOTENCY_KEY = "d2130000-0000-4000-8000-000000000001";
const OPERATION_ID = "d2140000-0000-4000-8000-000000000001";
const REPOSITORY = "lws-web-d2120000000040008000000000000001";
const SOURCE_INSTALLATION = "161436785";
const LAB_INSTALLATION = "161461160";
const SOURCE_REPOSITORY_ID = "1368684860";
const LAB_REPOSITORY_ID = "1369000001";
const SOURCE_COMMIT = "a".repeat(40);
const SOURCE_BLOB = "b".repeat(40);
const CREATED_BLOB = "c".repeat(40);
const CREATED_TREE = "d".repeat(40);
const SNAPSHOT_COMMIT = "e".repeat(40);
const MARKER_COMMIT = "f".repeat(40);
const CONTENT = new TextEncoder().encode("starter\n");
const CONTENT_BASE64 = btoa(String.fromCharCode(...CONTENT));

type PostCreateFailure =
  | "WRITE_TOKEN"
  | "CREATE_BLOB"
  | "CREATE_TREE"
  | "CREATE_COMMIT"
  | "CREATE_REF"
  | "WRITE_PROJECT_MARKER"
  | "READBACK_TOKEN"
  | "REPOSITORY_METADATA"
  | "SNAPSHOT_TREE"
  | "SNAPSHOT_BLOB"
  | "READ_PROJECT_MARKER"
  | "PROVENANCE";

function appConfig(
  target: "PRODUCTION" | "TEST",
  starterTreeSha256: string,
) {
  const value = {
    enabled: true as const,
    target,
    appId: "4932372",
    installationId: target === "PRODUCTION"
      ? SOURCE_INSTALLATION
      : LAB_INSTALLATION,
    organization: target === "PRODUCTION"
      ? "lorenzo-web-solutions"
      : "lorenzo-web-solutions-lab",
    templateOwner: "lorenzo-web-solutions",
    templateName: "lws-website-starter",
    templateRepositoryId: SOURCE_REPOSITORY_ID,
    starterVersion: "1.0.0",
    starterCommitSha: SOURCE_COMMIT,
    starterTreeSha256,
  };
  Object.defineProperty(value, "privateKey", {
    value: "synthetic-private-key-not-a-credential",
    enumerable: false,
  });
  return value as typeof value & { privateKey: string };
}

Deno.test("positive exact repository-installation proof occurs before LAB token issuance", async () => {
  const treeSha256 = await computeSnapshotDigest([{
    path: "README.md",
    mode: "100644",
    type: "blob",
    content: CONTENT,
  }]);
  const calls: string[] = [];
  const reader = createGitHubLabRepositoryMetadataReader(
    {
      production: appConfig("PRODUCTION", treeSha256),
      lab: appConfig("TEST", treeSha256),
    },
    {
      tokenBroker: {
        issue() {
          calls.push("LAB_TOKEN_ISSUE");
          return Promise.resolve({
            token: `ghs_${"a".repeat(36)}`,
            expiresAt: "2026-09-13T12:55:00Z",
          });
        },
      },
      http: {
        execute() {
          calls.push("REPOSITORY_METADATA");
          return Promise.resolve({
            repositoryId: LAB_REPOSITORY_ID,
            nodeId: "R_task13_repository",
            owner: "lorenzo-web-solutions-lab",
            name: REPOSITORY,
            fullName: `lorenzo-web-solutions-lab/${REPOSITORY}`,
            private: true,
            defaultBranch: "main",
            createdAt: "2026-09-13T12:00:00Z",
            description: null,
          });
        },
      },
    },
    () => {
      calls.push("REPOSITORY_INSTALLATION_PROOF");
      return true;
    },
  );

  await reader({
    websiteWorkContextId: CONTEXT_ID,
    organization: "lorenzo-web-solutions-lab",
    repository: REPOSITORY,
  });

  assertEquals(calls, [
    "REPOSITORY_INSTALLATION_PROOF",
    "LAB_TOKEN_ISSUE",
    "REPOSITORY_METADATA",
  ]);
});

Deno.test("shared LAB metadata reader proves visibility before its only GET", async () => {
  const treeSha256 = await computeSnapshotDigest([{
    path: "README.md",
    mode: "100644",
    type: "blob",
    content: CONTENT,
  }]);
  const tokenCalls: unknown[] = [];
  const httpCalls: GitHubHttpOperation[] = [];
  const reader = createGitHubLabRepositoryMetadataReader(
    {
      production: appConfig("PRODUCTION", treeSha256),
      lab: appConfig("TEST", treeSha256),
    },
    {
      tokenBroker: {
        issue(config, request, authority) {
          tokenCalls.push({ config, request, authority });
          return Promise.resolve({
            token: `ghs_${"a".repeat(36)}`,
            expiresAt: "2026-09-13T12:55:00Z",
          });
        },
      },
      http: {
        execute(operation) {
          httpCalls.push(operation);
          throw new Error("HTTP must remain unreachable");
        },
      },
    },
    () => false,
  );
  await assertRejects(
    () =>
      reader({
        websiteWorkContextId: CONTEXT_ID,
        organization: "lorenzo-web-solutions-lab",
        repository: REPOSITORY,
      }),
    GitHubLabPrivateVisibilityUnprovenError,
  );
  assertEquals(tokenCalls, []);
  assertEquals(httpCalls, []);
});

async function harness(
  createFailure: GitHubHttpError | null = null,
  reconciliationExact = true,
  claim?: RepositoryProvisioningRuntimeStoreV2["claim"],
  starterFailure?: Readonly<{
    kind: "REPOSITORY_METADATA" | "REPOSITORY_TREE" | "READ_BLOB";
    value: unknown;
    reject?: boolean;
  }>,
  starterTokenFailure?: unknown,
  labTokenFailure?: unknown,
  createMetadata?: unknown,
  postCreateFailure?: PostCreateFailure,
) {
  const treeSha256 = await computeSnapshotDigest([{
    path: "README.md",
    mode: "100644",
    type: "blob",
    content: CONTENT,
  }]);
  const production = appConfig("PRODUCTION", treeSha256);
  const lab = appConfig("TEST", treeSha256);
  const tokenRequests: GitHubTokenRequest[] = [];
  const tokenAuthorities: GitHubTokenAuthority[] = [];
  const httpOperations: GitHubHttpOperation[] = [];
  const storeCalls: string[] = [];
  let markerContentBase64 = "";
  let createCalls = 0;
  let labWriteTokenCalls = 0;
  const repository = {
    repositoryId: LAB_REPOSITORY_ID,
    nodeId: "R_task13_repository",
    owner: "lorenzo-web-solutions-lab",
    name: REPOSITORY,
    fullName: `lorenzo-web-solutions-lab/${REPOSITORY}`,
    private: true,
    defaultBranch: "main",
    createdAt: "2026-09-13T12:00:00Z",
    description: reconciliationExact
      ? `LWS Task 13 operation ${OPERATION_ID}`
      : "unrelated repository",
  };
  const store: RepositoryProvisioningRuntimeStoreV2 = {
    claim: (authority: RepositoryProvisioningAuthorityV2) => {
      storeCalls.push("CLAIM");
      assertEquals(authority.repositoryName, REPOSITORY);
      return claim
        ? claim(authority)
        : Promise.resolve({ state: "CLAIMED", operationId: OPERATION_ID });
    },
    captureLabIdentity: (identity) => {
      storeCalls.push("CAPTURE");
      assertEquals(identity.repositoryId, LAB_REPOSITORY_ID);
      return Promise.resolve();
    },
    finalizeRecoveredRepository: () => Promise.reject(new Error("unused")),
    bind: (_operationId, _expected, binding) => {
      storeCalls.push("BIND");
      return Promise.resolve(binding);
    },
    fail: () => {
      storeCalls.push("FAIL");
      return Promise.resolve();
    },
    quarantine: () => {
      storeCalls.push("QUARANTINE");
      return Promise.resolve({
        operationId: OPERATION_ID,
        websiteWorkspaceId: WORKSPACE_ID,
        websiteWorkContextId: CONTEXT_ID,
        state: "QUARANTINED",
        repositoryOwner: repository.owner,
        repositoryName: repository.name,
        repositoryId: null,
        repositoryNodeId: null,
        retryAction: null,
        quarantineEvidenceSha256: "9".repeat(64),
      });
    },
    readStatus: () => Promise.reject(new Error("unused")),
    resume: () => Promise.reject(new Error("unused")),
  };
  const runtime = createGitHubRepositoryRuntime(
    { production, lab },
    {
      store,
      tokenBroker: {
        issue(_config, request, authority) {
          tokenRequests.push(request);
          tokenAuthorities.push(authority);
          if (
            request.target === "PRODUCTION" &&
            request.operation === "STARTER_SNAPSHOT_READ" &&
            starterTokenFailure !== undefined
          ) return Promise.reject(starterTokenFailure);
          if (
            request.target === "TEST" &&
            request.operation === "LAB_REPOSITORY_CREATE" &&
            labTokenFailure !== undefined
          ) return Promise.reject(labTokenFailure);
          if (request.operation === "LAB_REPOSITORY_WRITE") {
            labWriteTokenCalls++;
            if (
              postCreateFailure === "WRITE_TOKEN" &&
                labWriteTokenCalls === 1 ||
              postCreateFailure === "READBACK_TOKEN" &&
                labWriteTokenCalls === 2
            ) return Promise.reject(new Error("synthetic post-create token"));
          }
          return Promise.resolve({
            token: `synthetic_${request.operation}_token_value`,
            expiresAt: "2026-09-13T23:00:00.000Z",
          });
        },
      },
      http: {
        execute(operation) {
          httpOperations.push(operation);
          if (operation.kind === starterFailure?.kind) {
            return starterFailure.reject
              ? Promise.reject(starterFailure.value)
              : Promise.resolve(starterFailure.value as never);
          }
          if (
            "owner" in operation &&
            operation.owner === "lorenzo-web-solutions-lab" &&
            (postCreateFailure === operation.kind ||
              postCreateFailure === "SNAPSHOT_TREE" &&
                operation.kind === "REPOSITORY_TREE" ||
              postCreateFailure === "SNAPSHOT_BLOB" &&
                operation.kind === "READ_BLOB" ||
              postCreateFailure === "PROVENANCE" &&
                operation.kind === "READ_PROJECT_MARKER")
          ) {
            if (
              postCreateFailure === "PROVENANCE" &&
              operation.kind === "READ_PROJECT_MARKER"
            ) {
              return Promise.resolve({
                path: ".lws/project.json",
                sha: "1".repeat(40),
                encoding: "base64",
                contentBase64: "%%%invalid%%%",
                size: 1,
              });
            }
            return Promise.reject(new Error("synthetic post-create HTTP"));
          }
          switch (operation.kind) {
            case "REPOSITORY_METADATA":
              return Promise.resolve(
                operation.owner === "lorenzo-web-solutions"
                  ? {
                    repositoryId: SOURCE_REPOSITORY_ID,
                    nodeId: "R_source_repository",
                    owner: "lorenzo-web-solutions",
                    name: "lws-website-starter",
                    fullName: "lorenzo-web-solutions/lws-website-starter",
                    private: true,
                    defaultBranch: "main",
                    createdAt: "2026-09-13T12:00:00Z",
                    description: null,
                  }
                  : repository,
              );
            case "REPOSITORY_TREE":
              return Promise.resolve({
                sha: CREATED_TREE,
                truncated: false,
                entries: [{
                  path: "README.md",
                  mode: "100644",
                  type: "blob",
                  sha: operation.owner === "lorenzo-web-solutions"
                    ? SOURCE_BLOB
                    : CREATED_BLOB,
                  size: CONTENT.length,
                }],
              });
            case "READ_BLOB":
              return Promise.resolve({
                sha: operation.blobSha,
                encoding: "base64",
                contentBase64: CONTENT_BASE64,
                size: CONTENT.length,
              });
            case "CREATE_REPOSITORY":
              createCalls++;
              return createFailure
                ? Promise.reject(createFailure)
                : Promise.resolve((createMetadata ?? repository) as never);
            case "CREATE_BLOB":
              return Promise.resolve({ sha: CREATED_BLOB });
            case "CREATE_TREE":
              return Promise.resolve({ sha: CREATED_TREE });
            case "CREATE_COMMIT":
              return Promise.resolve({ sha: SNAPSHOT_COMMIT });
            case "CREATE_REF":
              return Promise.resolve({
                ref: "refs/heads/main",
                commitSha: SNAPSHOT_COMMIT,
              });
            case "WRITE_PROJECT_MARKER":
              markerContentBase64 = operation.contentBase64;
              return Promise.resolve({
                contentSha: "1".repeat(40),
                commitSha: MARKER_COMMIT,
              });
            case "READ_PROJECT_MARKER":
              return Promise.resolve({
                path: ".lws/project.json",
                sha: "1".repeat(40),
                encoding: "base64",
                contentBase64: markerContentBase64,
                size: atob(markerContentBase64).length,
              });
            default:
              return Promise.reject(new Error("unexpected operation"));
          }
        },
      },
    },
  );
  const command: RepositoryProvisioningCommandV2 = {
    contractVersion: 2,
    websiteWorkspaceId: WORKSPACE_ID,
    websiteWorkContextId: CONTEXT_ID,
    idempotencyKey: IDEMPOTENCY_KEY,
    starter: {
      source: "lorenzo-web-solutions/lws-website-starter",
      version: "1.0.0",
      commitSha: SOURCE_COMMIT,
      templateRepositoryId: SOURCE_REPOSITORY_ID,
    },
  };
  return {
    runtime,
    command,
    storeCalls,
    tokenRequests,
    tokenAuthorities,
    httpOperations,
    createCalls: () => createCalls,
  };
}

async function assertPostCreateBoundary(
  failure: PostCreateFailure,
  expectedSubphase: string,
) {
  const test = await harness(
    null,
    true,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    failure,
  );
  const error = await assertRejects(
    () => test.runtime.provision(test.command),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_POST_CREATE_FAILED",
  );
  assertEquals(String(error.subphase), expectedSubphase);
  assertEquals(test.createCalls(), 1);
}

Deno.test("post-create write token failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary(
    "WRITE_TOKEN",
    "LAB_POST_CREATE_WRITE_TOKEN_ACQUIRE",
  );
});

Deno.test("post-create blob failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary("CREATE_BLOB", "LAB_POST_CREATE_BLOB_WRITE");
});

Deno.test("post-create tree failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary("CREATE_TREE", "LAB_POST_CREATE_TREE_WRITE");
});

Deno.test("post-create commit failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary(
    "CREATE_COMMIT",
    "LAB_POST_CREATE_COMMIT_WRITE",
  );
});

Deno.test("post-create ref failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary("CREATE_REF", "LAB_POST_CREATE_REF_WRITE");
});

Deno.test("post-create marker write failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary(
    "WRITE_PROJECT_MARKER",
    "LAB_POST_CREATE_MARKER_WRITE",
  );
});

Deno.test("post-create readback token failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary(
    "READBACK_TOKEN",
    "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
  );
});

Deno.test("post-create metadata failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary(
    "REPOSITORY_METADATA",
    "LAB_POST_CREATE_METADATA_READ",
  );
});

Deno.test("post-create snapshot tree and blob failures retain the readback boundary", async () => {
  for (const failure of ["SNAPSHOT_TREE", "SNAPSHOT_BLOB"] as const) {
    await assertPostCreateBoundary(
      failure,
      "LAB_POST_CREATE_SNAPSHOT_READBACK",
    );
  }
});

Deno.test("post-create marker readback failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary(
    "READ_PROJECT_MARKER",
    "LAB_POST_CREATE_MARKER_READBACK",
  );
});

Deno.test("post-create provenance failure retains its first causal boundary", async () => {
  await assertPostCreateBoundary(
    "PROVENANCE",
    "LAB_POST_CREATE_PROVENANCE_VALIDATE",
  );
});

Deno.test("runtime sends a separate closed authority DTO to the token broker", async () => {
  const test = await harness();
  await test.runtime.provision(test.command);

  assertEquals(
    test.tokenAuthorities,
    test.tokenRequests.map((request) => ({
      websiteWorkContextId: request.websiteWorkContextId,
      target: request.target,
      organization: request.organization,
      repositoryIds: request.repositoryIds,
    })),
  );
});

Deno.test("runtime enforces claim, production read, one LAB create, durable capture, write, readback and bind", async () => {
  const test = await harness();
  const result = await test.runtime.provision(test.command);

  assertEquals(result.replayed, false);
  assertEquals(test.storeCalls, ["CLAIM", "CAPTURE", "BIND"]);
  assertEquals(test.createCalls(), 1);
  assertEquals(
    test.tokenRequests.map((request) => [
      request.target,
      request.operation,
      request.repositoryIds,
    ]),
    [
      ["PRODUCTION", "STARTER_SNAPSHOT_READ", [SOURCE_REPOSITORY_ID]],
      ["TEST", "LAB_REPOSITORY_CREATE", []],
      ["TEST", "LAB_REPOSITORY_WRITE", [LAB_REPOSITORY_ID]],
      ["TEST", "LAB_REPOSITORY_WRITE", [LAB_REPOSITORY_ID]],
    ],
  );
  const createIndex = test.httpOperations.findIndex((item) =>
    item.kind === "CREATE_REPOSITORY"
  );
  const firstWriteIndex = test.httpOperations.findIndex((item) =>
    item.kind === "CREATE_BLOB"
  );
  assertEquals(createIndex > 0 && firstWriteIndex > createIndex, true);
});

Deno.test("runtime classifies starter read boundaries without exposing upstream errors", async () => {
  const secret = "raw upstream message token Authorization private key";
  const failure = new Error(secret, {
    cause: { stack: secret, details: secret, hint: secret },
  });
  const scenarios = [
    {
      kind: "REPOSITORY_METADATA",
      value: failure,
      reject: true,
      subphase: "STARTER_METADATA_READ",
    },
    {
      kind: "REPOSITORY_TREE",
      value: failure,
      reject: true,
      subphase: "STARTER_TREE_READ",
    },
    {
      kind: "REPOSITORY_TREE",
      value: { truncated: true, entries: [] },
      subphase: "STARTER_TREE_VALIDATE",
    },
    {
      kind: "REPOSITORY_TREE",
      value: { truncated: false, entries: [null] },
      subphase: "STARTER_TREE_VALIDATE",
    },
    {
      kind: "READ_BLOB",
      value: failure,
      reject: true,
      subphase: "STARTER_BLOB_READ",
    },
    {
      kind: "READ_BLOB",
      value: {
        sha: SOURCE_BLOB,
        encoding: "base64",
        contentBase64: "%%%invalid%%%",
        size: CONTENT.length,
      },
      subphase: "STARTER_BLOB_VALIDATE",
    },
  ] as const;

  for (const scenario of scenarios) {
    const test = await harness(null, true, undefined, scenario);
    const error = await assertRejects(
      () => test.runtime.provision(test.command),
      GitHubRepositoryProviderError,
      "GITHUB_STARTER_SNAPSHOT_INVALID",
    );
    assertEquals(error.subphase, scenario.subphase, scenario.kind);
    assertEquals(test.createCalls(), 0);
    assertEquals(
      `${error.message}\n${error.stack}\n${JSON.stringify(error)}`.includes(
        secret,
      ),
      false,
    );
  }
});

Deno.test("runtime classifies canonical repository identity mismatch", async () => {
  const test = await harness(null, true, undefined, {
    kind: "REPOSITORY_METADATA",
    value: {
      repositoryId: "999999999",
      nodeId: "R_source_repository",
      owner: "lorenzo-web-solutions",
      name: "lws-website-starter",
      fullName: "lorenzo-web-solutions/lws-website-starter",
      private: true,
      defaultBranch: "main",
      createdAt: "2026-09-13T12:00:00Z",
      description: null,
    },
  });
  const error = await assertRejects(
    () => test.runtime.provision(test.command),
    GitHubRepositoryProviderError,
    "GITHUB_STARTER_SNAPSHOT_INVALID",
  );
  assertEquals(error.subphase, "STARTER_IDENTITY_VALIDATE");
  assertEquals(test.createCalls(), 0);
});

Deno.test("runtime requires a distinct closed subphase for production starter token acquisition", async () => {
  const secret = "raw production token acquisition failure";
  const tokenFailure = new GitHubTokenBrokerError(
    "GITHUB_TOKEN_RESPONSE_INVALID",
    "TOKEN_LEASE_VALIDATE",
    "LEASE_TOKEN_FORMAT_VALIDATE",
  );
  Object.assign(tokenFailure, {
    cause: { stack: secret, details: secret, hint: secret },
    rawMessage: secret,
    details: secret,
    hint: secret,
    token: secret,
    authorization: secret,
    privateKey: secret,
  });
  const test = await harness(
    null,
    true,
    undefined,
    undefined,
    tokenFailure,
  );
  const error = await assertRejects(
    () => test.runtime.provision(test.command),
    GitHubRepositoryProviderError,
    "GITHUB_STARTER_SNAPSHOT_INVALID",
  );

  assertEquals(test.createCalls(), 0);
  assertEquals(test.httpOperations, []);
  assertEquals(
    `${error.message}\n${error.stack}\n${JSON.stringify(error)}`.includes(
      secret,
    ),
    false,
  );
  assertEquals(Object.keys(error).sort(), [
    "code",
    "name",
    "phase",
    "subphase",
    "tokenAcquireSubphase",
    "tokenLeaseCheck",
  ]);
  assertEquals(error.subphase, "STARTER_TOKEN_ACQUIRE");
  assertEquals(
    (error as { tokenAcquireSubphase?: string }).tokenAcquireSubphase,
    "TOKEN_LEASE_VALIDATE",
  );
  assertEquals(
    (error as { tokenLeaseCheck?: string }).tokenLeaseCheck,
    "LEASE_TOKEN_FORMAT_VALIDATE",
  );
});

Deno.test("runtime does not rebrand prototype-forged starter token diagnostics", async () => {
  const forged = Object.assign(
    Object.create(GitHubTokenAcquireDiagnosticError.prototype),
    {
      tokenAcquireSubphase: "TOKEN_LEASE_VALIDATE",
      tokenLeaseCheck: "LEASE_TOKEN_FORMAT_VALIDATE",
    },
  );
  const test = await harness(
    null,
    true,
    undefined,
    undefined,
    forged,
  );
  const error = await assertRejects(
    () => test.runtime.provision(test.command),
    GitHubRepositoryProviderError,
    "GITHUB_STARTER_SNAPSHOT_INVALID",
  );

  assertEquals(error.subphase, "STARTER_TOKEN_ACQUIRE");
  assertEquals(error.tokenAcquireSubphase, undefined);
  assertEquals(error.tokenLeaseCheck, undefined);
  assertEquals(test.httpOperations, []);
  assertEquals(test.createCalls(), 0);
});

Deno.test("runtime reconciles an unknown create result and never creates twice", async () => {
  const test = await harness(new GitHubHttpError("GITHUB_HTTP_TIMEOUT"));
  await test.runtime.provision(test.command);

  assertEquals(test.createCalls(), 1);
  assertEquals(test.storeCalls, ["CLAIM", "CAPTURE", "BIND"]);
  assertEquals(
    test.httpOperations.filter((item) => item.kind === "CREATE_REPOSITORY")
      .length,
    1,
  );
});

Deno.test("runtime preserves closed LAB create causal boundaries", async () => {
  const scenarios = [
    {
      subphase: "LAB_TOKEN_ACQUIRE",
      createFailure: null,
      labTokenFailure: new GitHubTokenBrokerError(
        "GITHUB_TOKEN_FORBIDDEN",
        "TOKEN_HTTP_STATUS",
      ),
    },
    {
      subphase: "LAB_CREATE_REQUEST_PREPARE",
      createFailure: new GitHubHttpError(
        "GITHUB_HTTP_OPERATION_INVALID",
        null,
        null,
        undefined,
        "REQUEST_PREPARE",
      ),
    },
    {
      subphase: "LAB_CREATE_HTTP_STATUS",
      createFailure: new GitHubHttpError(
        "GITHUB_HTTP_FORBIDDEN",
        null,
        null,
        undefined,
        "HTTP_STATUS",
      ),
    },
  ] as const;

  for (const scenario of scenarios) {
    const test = await harness(
      scenario.createFailure,
      true,
      undefined,
      undefined,
      undefined,
      "labTokenFailure" in scenario ? scenario.labTokenFailure : undefined,
    );
    const error = await assertRejects(
      () => test.runtime.provision(test.command),
      GitHubRepositoryProviderError,
      "GITHUB_LAB_CREATE_FAILED",
    );
    assertEquals(error.subphase, scenario.subphase);
  }
});

Deno.test("runtime preserves closed LAB token acquisition detail before create dispatch", async () => {
  const secret = "raw LAB token acquisition failure";
  const tokenFailure = new GitHubTokenBrokerError(
    "GITHUB_TOKEN_RESPONSE_INVALID",
    "TOKEN_LEASE_VALIDATE",
    "LEASE_TOKEN_FORMAT_VALIDATE",
  );
  Object.assign(tokenFailure, {
    cause: { stack: secret, details: secret, hint: secret },
    rawMessage: secret,
    details: secret,
    hint: secret,
    token: secret,
    authorization: secret,
    privateKey: secret,
  });
  const test = await harness(
    null,
    true,
    undefined,
    undefined,
    undefined,
    tokenFailure,
  );
  const error = await assertRejects(
    () => test.runtime.provision(test.command),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_CREATE_FAILED",
  );

  assertEquals(test.createCalls(), 0);
  assertEquals(
    test.httpOperations.filter((operation) =>
      operation.kind === "CREATE_REPOSITORY"
    ),
    [],
  );
  assertEquals(
    `${error.message}\n${error.stack}\n${JSON.stringify(error)}`.includes(
      secret,
    ),
    false,
  );
  assertEquals(Object.keys(error).sort(), [
    "code",
    "name",
    "phase",
    "subphase",
    "tokenAcquireSubphase",
    "tokenLeaseCheck",
  ]);
  assertEquals(error.subphase, "LAB_TOKEN_ACQUIRE");
  assertEquals(
    (error as { tokenAcquireSubphase?: string }).tokenAcquireSubphase,
    "TOKEN_LEASE_VALIDATE",
  );
  assertEquals(
    (error as { tokenLeaseCheck?: string }).tokenLeaseCheck,
    "LEASE_TOKEN_FORMAT_VALIDATE",
  );
});

Deno.test("runtime preserves trusted starter and LAB token response checks", async () => {
  const Constructor = GitHubTokenBrokerError as unknown as new (
    code: string,
    tokenAcquireSubphase: "TOKEN_RESPONSE_SCHEMA",
    tokenLeaseCheck: undefined,
    tokenResponseCheck: "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  ) => GitHubTokenBrokerError & { tokenResponseCheck?: string };
  const tokenFailure = new Constructor(
    "GITHUB_TOKEN_EXCHANGE_FAILED",
    "TOKEN_RESPONSE_SCHEMA",
    undefined,
    "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  );
  const starter = await harness(
    null,
    true,
    undefined,
    undefined,
    tokenFailure,
  );
  const starterError = await assertRejects(
    () => starter.runtime.provision(starter.command),
    GitHubRepositoryProviderError,
    "GITHUB_STARTER_SNAPSHOT_INVALID",
  );
  assertEquals(
    (starterError as { tokenResponseCheck?: string }).tokenResponseCheck,
    "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  );

  const lab = await harness(
    null,
    true,
    undefined,
    undefined,
    undefined,
    tokenFailure,
  );
  const labError = await assertRejects(
    () => lab.runtime.provision(lab.command),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_CREATE_FAILED",
  );
  assertEquals(
    (labError as { tokenResponseCheck?: string }).tokenResponseCheck,
    "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  );
  assertEquals(lab.createCalls(), 0);
  assertEquals(
    lab.httpOperations.filter((operation) =>
      operation.kind === "CREATE_REPOSITORY"
    ).length,
    0,
  );
});

Deno.test("runtime preserves only genuine immutable LAB token acquisition detail", async () => {
  const genuine = new GitHubTokenBrokerError(
    "GITHUB_TOKEN_FORBIDDEN",
    "TOKEN_HTTP_STATUS",
  );
  assertThrows(
    () => Object.assign(genuine, { tokenAcquireSubphase: "TOKEN_JSON_PARSE" }),
    TypeError,
  );
  const genuineTest = await harness(
    null,
    true,
    undefined,
    undefined,
    undefined,
    genuine,
  );
  const genuineError = await assertRejects(
    () => genuineTest.runtime.provision(genuineTest.command),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_CREATE_FAILED",
  );
  assertEquals(genuineError.subphase, "LAB_TOKEN_ACQUIRE");
  assertEquals(genuineError.tokenAcquireSubphase, "TOKEN_HTTP_STATUS");
  assertEquals(genuineError.tokenLeaseCheck, undefined);
  assertEquals(genuineTest.createCalls(), 0);

  const forged = Object.assign(
    Object.create(GitHubTokenAcquireDiagnosticError.prototype),
    {
      tokenAcquireSubphase: "TOKEN_LEASE_VALIDATE",
      tokenLeaseCheck: "LEASE_TOKEN_FORMAT_VALIDATE",
    },
  );
  const forgedTest = await harness(
    null,
    true,
    undefined,
    undefined,
    undefined,
    forged,
  );
  const forgedError = await assertRejects(
    () => forgedTest.runtime.provision(forgedTest.command),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_CREATE_FAILED",
  );
  assertEquals(forgedError.subphase, "LAB_TOKEN_ACQUIRE");
  assertEquals(forgedError.tokenAcquireSubphase, undefined);
  assertEquals(forgedError.tokenLeaseCheck, undefined);
  assertEquals(forgedTest.createCalls(), 0);
});

Deno.test("runtime preserves the first boundary through ambiguous create reconciliation", async () => {
  const scenarios = [
    ["GITHUB_HTTP_NETWORK_ERROR", "HTTP_REQUEST", "LAB_CREATE_HTTP_REQUEST"],
    ["GITHUB_HTTP_RESPONSE_INVALID", "CONTENT_TYPE", "LAB_CREATE_CONTENT_TYPE"],
    ["GITHUB_HTTP_RESPONSE_INVALID", "JSON_PARSE", "LAB_CREATE_JSON_PARSE"],
    [
      "GITHUB_HTTP_RESPONSE_TOO_LARGE",
      "BODY_READ",
      "LAB_CREATE_BODY_READ",
    ],
    [
      "GITHUB_HTTP_RESPONSE_INVALID",
      "RESPONSE_SCHEMA",
      "LAB_CREATE_RESPONSE_SCHEMA",
    ],
  ] as const;
  for (const [code, boundary, subphase] of scenarios) {
    const test = await harness(
      new GitHubHttpError(code, null, null, undefined, boundary),
      false,
    );
    const error = await assertRejects(
      () => test.runtime.provision(test.command),
      GitHubRepositoryProviderError,
      "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
    );
    assertEquals(error.subphase, subphase);
    assertEquals(test.createCalls(), 1);
  }
});

Deno.test("runtime reconciles LAB create adapter projection without creating twice", async () => {
  const test = await harness(
    null,
    false,
    undefined,
    undefined,
    undefined,
    undefined,
    {
      repositoryId: LAB_REPOSITORY_ID,
      nodeId: "R_task13_repository",
      owner: "wrong-owner",
      name: REPOSITORY,
      fullName: `wrong-owner/${REPOSITORY}`,
      private: true,
      defaultBranch: "main",
      createdAt: "2026-09-13T12:00:00Z",
      description: null,
    },
  );
  const error = await assertRejects(
    () => test.runtime.provision(test.command),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
  );
  assertEquals(error.subphase, "LAB_CREATE_ADAPTER_PROJECT");
  assertEquals(test.createCalls(), 1);
  assertEquals(test.storeCalls.includes("QUARANTINE"), true);
});

Deno.test("runtime never fabricates a boundary for legacy boundaryless errors", async () => {
  const test = await harness(
    new GitHubHttpError("GITHUB_HTTP_RESPONSE_INVALID"),
    false,
  );
  const error = await assertRejects(
    () => test.runtime.provision(test.command),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
  );
  assertEquals(error.subphase, undefined);
});

Deno.test("runtime quarantines ambiguous reconciliation without repository writes", async () => {
  const test = await harness(
    new GitHubHttpError("GITHUB_HTTP_TIMEOUT"),
    false,
  );

  await assertRejects(
    () => test.runtime.provision(test.command),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
  );
  assertEquals(test.createCalls(), 1);
  assertEquals(test.storeCalls.includes("QUARANTINE"), true);
  assertEquals(
    test.httpOperations.some((item) => item.kind === "CREATE_BLOB"),
    false,
  );
});

Deno.test("concurrent duplicate runtime invocation grants create authority once", async () => {
  let claimed = false;
  const test = await harness(null, true, () => {
    if (claimed) return Promise.resolve({ state: "IN_PROGRESS" });
    claimed = true;
    return Promise.resolve({ state: "CLAIMED", operationId: OPERATION_ID });
  });

  const outcomes = await Promise.allSettled([
    test.runtime.provision(test.command),
    test.runtime.provision(test.command),
  ]);

  assertEquals(outcomes[0].status, "fulfilled");
  assertEquals(outcomes[1].status, "rejected");
  if (outcomes[1].status === "rejected") {
    assertEquals(
      outcomes[1].reason?.message,
      "REPOSITORY_PROVISIONING_IN_PROGRESS",
    );
  }
  assertEquals(test.createCalls(), 1);
  assertEquals(
    test.httpOperations.filter((item) => item.kind === "CREATE_REPOSITORY")
      .length,
    1,
  );
});

import type { GitHubTask13RuntimeConfig } from "../_shared/github-app-config.ts";
import type {
  GitHubInstallationTokenLease,
  GitHubTokenAuthority,
  GitHubTokenRequest,
} from "../_shared/github-app-token.ts";
import {
  GitHubHttpError,
  type GitHubHttpOperation,
  type GitHubHttpResult,
  type GitHubRepositoryMetadata,
  type GitHubTreeEntry,
} from "../_shared/github-http.ts";
import { computeGitHubSnapshotDigest } from "../_shared/github-snapshot-digest.ts";
import {
  GitHubLabPostCreateDiagnosticError,
  type GitHubLabPostCreateSubphase,
} from "../_shared/repository-provisioning-diagnostics.ts";
import type { Task13PostCreateRecoveryAuthority } from "./post-create-recovery-writer.ts";

const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SHA256 = /^[0-9a-f]{64}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const AUTHORITY_KEYS = [
  "operationId",
  "websiteWorkContextId",
  "websiteWorkspaceId",
  "repositoryId",
  "owner",
  "repository",
  "installationId",
  "starterSource",
  "starterVersion",
  "starterCommitSha",
  "starterTreeSha256",
  "markerContent",
] as const;

type TokenBroker = Readonly<{
  issue(
    config: GitHubTask13RuntimeConfig["lab"],
    request: GitHubTokenRequest,
    authority: GitHubTokenAuthority,
  ): Promise<GitHubInstallationTokenLease>;
}>;

type Dependencies = Readonly<{
  tokenBroker: TokenBroker;
  http: Readonly<{
    execute(operation: RecoveryHttpOperation): Promise<GitHubHttpResult>;
  }>;
}>;

type RecoveryHttpOperation = Extract<GitHubHttpOperation, {
  kind:
    | "REPOSITORY_METADATA"
    | "REPOSITORY_TREE"
    | "READ_BLOB"
    | "CREATE_BLOB"
    | "CREATE_TREE"
    | "CREATE_COMMIT"
    | "CREATE_BOOTSTRAP_FILE"
    | "READ_BOOTSTRAP_FILE"
    | "READ_BOOTSTRAP_COMMIT"
    | "READ_REF"
    | "UPDATE_REF"
    | "WRITE_PROJECT_MARKER";
}>;

type SnapshotEntry = Readonly<{
  path: string;
  mode: string;
  type: "blob";
  content: Uint8Array;
}>;

function phase(
  subphase: GitHubLabPostCreateSubphase,
  action: () => never,
): never;
function phase<T>(
  subphase: GitHubLabPostCreateSubphase,
  action: () => Promise<T>,
): Promise<T>;
function phase<T>(
  subphase: GitHubLabPostCreateSubphase,
  action: () => T | Promise<T>,
): T | Promise<T> {
  try {
    const result = action();
    if (result instanceof Promise) {
      return result.catch(() => {
        throw new GitHubLabPostCreateDiagnosticError(subphase);
      });
    }
    return result;
  } catch {
    throw new GitHubLabPostCreateDiagnosticError(subphase);
  }
}

function exactRecord(
  value: unknown,
  keys: readonly string[],
): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  return (prototype === Object.prototype || prototype === null) &&
    actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]) &&
    keys.every((key) =>
      descriptors[key]?.enumerable === true &&
      Object.hasOwn(descriptors[key], "value")
    );
}

function validConfig(config: GitHubTask13RuntimeConfig): boolean {
  return !!config && config.production?.target === "PRODUCTION" &&
    config.lab?.target === "TEST" &&
    config.production.installationId === "161436785" &&
    config.lab.installationId === "161461160" &&
    config.production.organization === "lorenzo-web-solutions" &&
    config.lab.organization === "lorenzo-web-solutions-lab" &&
    config.production.templateOwner === "lorenzo-web-solutions" &&
    config.production.templateName === "lws-website-starter" &&
    config.production.templateRepositoryId ===
      config.lab.templateRepositoryId &&
    config.production.starterVersion === config.lab.starterVersion &&
    config.production.starterCommitSha === config.lab.starterCommitSha &&
    config.production.starterTreeSha256 === config.lab.starterTreeSha256;
}

function projectAuthority(
  value: unknown,
  config: GitHubTask13RuntimeConfig,
): Task13PostCreateRecoveryAuthority {
  if (
    !exactRecord(value, AUTHORITY_KEYS) ||
    typeof value.operationId !== "string" || !UUID.test(value.operationId) ||
    typeof value.websiteWorkContextId !== "string" ||
    !UUID.test(value.websiteWorkContextId) ||
    typeof value.websiteWorkspaceId !== "string" ||
    !UUID.test(value.websiteWorkspaceId) ||
    typeof value.repositoryId !== "string" ||
    !NUMERIC_ID.test(value.repositoryId) ||
    value.owner !== config.lab.organization ||
    value.repository !==
      `lws-web-${
        value.websiteWorkContextId.toLowerCase().replaceAll("-", "")
      }` ||
    value.installationId !== config.lab.installationId ||
    value.starterSource !==
      `${config.production.templateOwner}/${config.production.templateName}` ||
    value.starterVersion !== config.production.starterVersion ||
    value.starterCommitSha !== config.production.starterCommitSha ||
    typeof value.starterCommitSha !== "string" ||
    !SHA.test(value.starterCommitSha) ||
    value.starterTreeSha256 !== config.production.starterTreeSha256 ||
    typeof value.starterTreeSha256 !== "string" ||
    !SHA256.test(value.starterTreeSha256) ||
    typeof value.markerContent !== "string" ||
    value.markerContent.length === 0 || value.markerContent.length > 64 * 1024
  ) {
    throw new Error("GITHUB_LAB_POST_CREATE_FAILED");
  }
  return Object.freeze({
    operationId: String(value.operationId),
    websiteWorkContextId: String(value.websiteWorkContextId),
    websiteWorkspaceId: String(value.websiteWorkspaceId),
    repositoryId: String(value.repositoryId),
    owner: String(value.owner),
    repository: String(value.repository),
    installationId: String(value.installationId),
    starterSource: String(value.starterSource),
    starterVersion: String(value.starterVersion),
    starterCommitSha: String(value.starterCommitSha),
    starterTreeSha256: String(value.starterTreeSha256),
    markerContent: value.markerContent,
  });
}

function base64(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function bytes(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

function sha(value: unknown): string {
  if (!exactRecord(value, ["sha"]) || !SHA.test(String(value.sha))) {
    throw new Error("INVALID_SHA");
  }
  return String(value.sha);
}

function conflict(error: unknown): boolean {
  return error instanceof GitHubHttpError &&
    error.code === "GITHUB_HTTP_CONFLICT";
}

function uncertainBootstrapWrite(error: unknown): boolean {
  return error instanceof GitHubHttpError && [
    "GITHUB_HTTP_TIMEOUT",
    "GITHUB_HTTP_NETWORK_ERROR",
    "GITHUB_HTTP_RESPONSE_INVALID",
    "GITHUB_HTTP_RESPONSE_TOO_LARGE",
    "GITHUB_HTTP_SERVER_ERROR",
    "GITHUB_HTTP_FAILED",
  ].includes(error.code);
}

function bootstrapContent(
  authority: Task13PostCreateRecoveryAuthority,
): string {
  return `${
    JSON.stringify(
      {
        schema_version: 1,
        purpose: "TASK13_EMPTY_REPOSITORY_RECOVERY",
        environment: "TEST",
        organization: authority.owner,
        repository: authority.repository,
        repository_id: authority.repositoryId,
        website_work_context_id: authority.websiteWorkContextId,
        website_workspace_id: authority.websiteWorkspaceId,
        repository_provisioning_operation_id: authority.operationId,
      },
      null,
      2,
    )
  }\n`;
}

export function createTask13PostCreateRecoveryWriteCapability(
  config: GitHubTask13RuntimeConfig,
  dependencies: Dependencies,
) {
  if (
    !validConfig(config) || !dependencies ||
    typeof dependencies.tokenBroker?.issue !== "function" ||
    typeof dependencies.http?.execute !== "function"
  ) throw new Error("GITHUB_LAB_POST_CREATE_FAILED");

  const issue = async (
    appConfig: GitHubTask13RuntimeConfig["lab"],
    authority: Task13PostCreateRecoveryAuthority,
    operation: "STARTER_SNAPSHOT_READ" | "LAB_REPOSITORY_WRITE",
    repositoryId: string,
  ) => {
    const request = Object.freeze({
      websiteWorkContextId: authority.websiteWorkContextId,
      target: appConfig.target,
      organization: appConfig.organization,
      operation,
      repositoryIds: Object.freeze([repositoryId]),
    });
    const tokenAuthority = Object.freeze({
      websiteWorkContextId: request.websiteWorkContextId,
      target: request.target,
      organization: request.organization,
      repositoryIds: request.repositoryIds,
    });
    const lease = await dependencies.tokenBroker.issue(
      appConfig,
      request,
      tokenAuthority,
    );
    if (!lease || typeof lease.token !== "string") throw new Error("TOKEN");
    return lease.token;
  };

  const prepareSnapshot = async (
    authority: Task13PostCreateRecoveryAuthority,
  ): Promise<readonly SnapshotEntry[]> => {
    const token = await issue(
      config.production,
      authority,
      "STARTER_SNAPSHOT_READ",
      config.production.templateRepositoryId,
    );
    const metadata = await dependencies.http.execute({
      kind: "REPOSITORY_METADATA",
      owner: config.production.templateOwner,
      repository: config.production.templateName,
      token,
    }) as GitHubRepositoryMetadata;
    if (
      metadata.repositoryId !== config.production.templateRepositoryId ||
      metadata.owner !== config.production.templateOwner ||
      metadata.name !== config.production.templateName
    ) throw new Error("STARTER_IDENTITY");
    const tree = await dependencies.http.execute({
      kind: "REPOSITORY_TREE",
      owner: config.production.templateOwner,
      repository: config.production.templateName,
      treeRef: authority.starterCommitSha,
      token,
    }) as Readonly<{
      sha: string;
      truncated: false;
      entries: readonly GitHubTreeEntry[];
    }>;
    if (!tree || tree.truncated !== false || !Array.isArray(tree.entries)) {
      throw new Error("STARTER_TREE");
    }
    const entries: SnapshotEntry[] = [];
    for (const entry of tree.entries) {
      if (entry.type === "tree") continue;
      if (entry.type !== "blob") throw new Error("STARTER_TREE");
      const blob = await dependencies.http.execute({
        kind: "READ_BLOB",
        owner: config.production.templateOwner,
        repository: config.production.templateName,
        blobSha: entry.sha,
        token,
      }) as Readonly<{
        sha: string;
        encoding: "base64";
        contentBase64: string;
        size: number;
      }>;
      const content = bytes(blob.contentBase64);
      if (
        blob.sha !== entry.sha || blob.encoding !== "base64" ||
        content.byteLength !== blob.size
      ) throw new Error("STARTER_BLOB");
      entries.push(Object.freeze({
        path: entry.path,
        mode: entry.mode,
        type: "blob" as const,
        content,
      }));
    }
    if (
      await computeGitHubSnapshotDigest(entries) !==
        authority.starterTreeSha256
    ) throw new Error("STARTER_DIGEST");
    return Object.freeze(entries);
  };

  const confirmTargetIdentity = async (
    authority: Task13PostCreateRecoveryAuthority,
    token: string,
  ) => {
    const metadata = await dependencies.http.execute({
      kind: "REPOSITORY_METADATA",
      owner: authority.owner,
      repository: authority.repository,
      token,
    }) as GitHubRepositoryMetadata;
    if (
      metadata.repositoryId !== authority.repositoryId ||
      metadata.owner !== authority.owner ||
      metadata.name !== authority.repository ||
      metadata.fullName !== `${authority.owner}/${authority.repository}` ||
      metadata.private !== true || metadata.defaultBranch !== "main"
    ) throw new Error("TARGET_IDENTITY");
  };

  const readBootstrapHead = async (
    authority: Task13PostCreateRecoveryAuthority,
    token: string,
    expectedContentBase64: string,
  ): Promise<string> => {
    const ref: unknown = await dependencies.http.execute({
      kind: "READ_REF",
      owner: authority.owner,
      repository: authority.repository,
      ref: "heads/main",
      token,
    });
    if (
      !exactRecord(ref, ["ref", "commitSha"]) ||
      ref.ref !== "refs/heads/main" || !SHA.test(String(ref.commitSha))
    ) throw new Error("BOOTSTRAP_REF");
    const commitSha = String(ref.commitSha);
    const readback: unknown = await dependencies.http.execute({
      kind: "READ_BOOTSTRAP_FILE",
      owner: authority.owner,
      repository: authority.repository,
      ref: commitSha,
      token,
    });
    if (
      !exactRecord(readback, [
        "path",
        "sha",
        "encoding",
        "contentBase64",
        "size",
      ]) || readback.path !== ".lws/bootstrap.json" ||
      readback.encoding !== "base64" ||
      readback.contentBase64 !== expectedContentBase64 ||
      !SHA.test(String(readback.sha)) ||
      readback.size !== bytes(expectedContentBase64).byteLength
    ) throw new Error("BOOTSTRAP_READBACK");
    await confirmTargetIdentity(authority, token);
    const commit: unknown = await dependencies.http.execute({
      kind: "READ_BOOTSTRAP_COMMIT",
      owner: authority.owner,
      repository: authority.repository,
      commitSha,
      token,
    });
    if (
      !exactRecord(commit, ["sha", "treeSha", "parentCount"]) ||
      commit.sha !== commitSha || !SHA.test(String(commit.treeSha)) ||
      commit.parentCount !== 0
    ) throw new Error("BOOTSTRAP_COMMIT");
    const tree: unknown = await dependencies.http.execute({
      kind: "REPOSITORY_TREE",
      owner: authority.owner,
      repository: authority.repository,
      treeRef: String(commit.treeSha),
      token,
    });
    if (
      !exactRecord(tree, ["sha", "truncated", "entries"]) ||
      tree.sha !== commit.treeSha || tree.truncated !== false ||
      !Array.isArray(tree.entries) || tree.entries.length !== 2
    ) throw new Error("BOOTSTRAP_TREE");
    const directory = tree.entries.find((entry: unknown) =>
      exactRecord(entry, ["path", "mode", "type", "sha"]) &&
      entry.path === ".lws" && entry.mode === "040000" &&
      entry.type === "tree" && SHA.test(String(entry.sha))
    );
    const file = tree.entries.find((entry: unknown) =>
      exactRecord(entry, ["path", "mode", "type", "sha", "size"]) &&
      entry.path === ".lws/bootstrap.json" && entry.mode === "100644" &&
      entry.type === "blob" && entry.sha === readback.sha &&
      entry.size === readback.size
    );
    if (!directory || !file) throw new Error("BOOTSTRAP_TREE");
    return commitSha;
  };

  const createOrResumeBootstrap = async (
    authority: Task13PostCreateRecoveryAuthority,
    token: string,
  ): Promise<string> => {
    const contentBase64 = base64(
      new TextEncoder().encode(bootstrapContent(authority)),
    );
    let write: unknown;
    try {
      write = await dependencies.http.execute({
        kind: "CREATE_BOOTSTRAP_FILE",
        owner: authority.owner,
        repository: authority.repository,
        contentBase64,
        branch: "main",
        token,
      });
    } catch (error) {
      if (!conflict(error) && !uncertainBootstrapWrite(error)) throw error;
      return await readBootstrapHead(authority, token, contentBase64);
    }
    if (
      !exactRecord(write, [
        "path",
        "contentSha",
        "commitSha",
        "parentCount",
      ]) || write.path !== ".lws/bootstrap.json" ||
      !SHA.test(String(write.contentSha)) ||
      !SHA.test(String(write.commitSha)) || write.parentCount !== 0
    ) throw new Error("BOOTSTRAP_WRITE");
    const ref: unknown = await dependencies.http.execute({
      kind: "READ_REF",
      owner: authority.owner,
      repository: authority.repository,
      ref: "heads/main",
      token,
    });
    if (
      !exactRecord(ref, ["ref", "commitSha"]) ||
      ref.ref !== "refs/heads/main" || ref.commitSha !== write.commitSha
    ) throw new Error("BOOTSTRAP_REF");
    return String(write.commitSha);
  };

  const markerWrite = async (
    authority: Task13PostCreateRecoveryAuthority,
    token: string,
  ): Promise<"WRITTEN" | "RACE"> => {
    let result: unknown;
    try {
      result = await dependencies.http.execute({
        kind: "WRITE_PROJECT_MARKER",
        owner: authority.owner,
        repository: authority.repository,
        message: "chore: bind project context",
        contentBase64: base64(
          new TextEncoder().encode(authority.markerContent),
        ),
        token,
      });
    } catch (error) {
      if (conflict(error)) return "RACE";
      throw new GitHubLabPostCreateDiagnosticError(
        "LAB_POST_CREATE_MARKER_WRITE",
      );
    }
    if (
      !exactRecord(result, ["contentSha", "commitSha"]) ||
      !SHA.test(String(result.contentSha)) ||
      !SHA.test(String(result.commitSha))
    ) {
      throw new GitHubLabPostCreateDiagnosticError(
        "LAB_POST_CREATE_WRITE_RESULT_VALIDATE",
      );
    }
    return "WRITTEN";
  };

  return Object.freeze({
    async writeCanonicalSnapshotToEmptyRepository(
      authority: Task13PostCreateRecoveryAuthority,
    ) {
      const safeAuthority = projectAuthority(authority, config);
      const token = await phase(
        "LAB_POST_CREATE_WRITE_TOKEN_ACQUIRE",
        () =>
          issue(
            config.lab,
            safeAuthority,
            "LAB_REPOSITORY_WRITE",
            safeAuthority.repositoryId,
          ),
      );
      const entries = await phase(
        "LAB_POST_CREATE_SNAPSHOT_PREPARE",
        () => prepareSnapshot(safeAuthority),
      );
      const bootstrapHead = await phase(
        "LAB_POST_CREATE_REF_WRITE",
        async () => {
          await confirmTargetIdentity(safeAuthority, token);
          return await createOrResumeBootstrap(safeAuthority, token);
        },
      );
      const treeEntries: Array<
        Readonly<{
          path: string;
          mode: string;
          type: "blob";
          sha: string;
        }>
      > = [];
      for (const entry of entries) {
        const blobSha = await phase(
          "LAB_POST_CREATE_BLOB_WRITE",
          async () =>
            sha(
              await dependencies.http.execute({
                kind: "CREATE_BLOB",
                owner: safeAuthority.owner,
                repository: safeAuthority.repository,
                contentBase64: base64(entry.content),
                token,
              }),
            ),
        );
        treeEntries.push(Object.freeze({
          path: entry.path,
          mode: entry.mode,
          type: "blob" as const,
          sha: blobSha,
        }));
      }
      const treeSha = await phase(
        "LAB_POST_CREATE_TREE_WRITE",
        async () =>
          sha(
            await dependencies.http.execute({
              kind: "CREATE_TREE",
              owner: safeAuthority.owner,
              repository: safeAuthority.repository,
              entries: Object.freeze(treeEntries),
              token,
            }),
          ),
      );
      const commitSha = await phase(
        "LAB_POST_CREATE_COMMIT_WRITE",
        async () =>
          sha(
            await dependencies.http.execute({
              kind: "CREATE_COMMIT",
              owner: safeAuthority.owner,
              repository: safeAuthority.repository,
              message: "chore: initialize approved starter snapshot",
              treeSha,
              parentSha: bootstrapHead,
              token,
            }),
          ),
      );
      let ref: unknown;
      try {
        ref = await dependencies.http.execute({
          kind: "UPDATE_REF",
          owner: safeAuthority.owner,
          repository: safeAuthority.repository,
          commitSha,
          force: false,
          token,
        });
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_REF_WRITE",
        );
      }
      if (
        !exactRecord(ref, ["ref", "commitSha"]) ||
        ref.ref !== "refs/heads/main" || ref.commitSha !== commitSha
      ) {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_WRITE_RESULT_VALIDATE",
        );
      }
      const marker = await markerWrite(safeAuthority, token);
      return Object.freeze({
        outcome: marker === "RACE" ? "RACE" as const : "WRITTEN" as const,
      });
    },

    async writeMissingMarker(authority: Task13PostCreateRecoveryAuthority) {
      const safeAuthority = projectAuthority(authority, config);
      const token = await phase(
        "LAB_POST_CREATE_WRITE_TOKEN_ACQUIRE",
        () =>
          issue(
            config.lab,
            safeAuthority,
            "LAB_REPOSITORY_WRITE",
            safeAuthority.repositoryId,
          ),
      );
      return Object.freeze({
        outcome: await markerWrite(safeAuthority, token),
      });
    },
  });
}

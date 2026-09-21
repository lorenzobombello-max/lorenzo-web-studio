import type { GitHubAppConfig } from "./github-app-config.ts";
import {
  GITHUB_TOKEN_BROKER_CODES,
  GITHUB_TOKEN_EXCHANGE_HTTP_CLASSES,
  GitHubTokenBrokerError,
  type GitHubInstallationTokenLease,
  type GitHubTokenAuthority,
  type GitHubTokenBrokerCode,
  type GitHubTokenExchangeHttpClass,
  type GitHubTokenRequest,
} from "./github-app-token.ts";
import {
  getValidatedGitHubHttpRefReadDiagnostic,
  getValidatedGitHubHttpStatus,
  type GitHubHttpOperation,
  type GitHubHttpResult,
  type GitHubRepositoryMetadata,
  type GitHubTreeEntry,
} from "./github-http.ts";
import {
  type GitHubRefReadDiagnostic,
  validateGitHubRefReadDiagnostic,
} from "./github-ref-read-diagnostic.ts";
import {
  computeGitHubSnapshotDigest,
  type GitHubSnapshotDigestEntry,
} from "./github-snapshot-digest.ts";
import {
  GITHUB_SNAPSHOT_READBACK_CHECKS,
  GITHUB_TOKEN_ACQUIRE_SUBPHASES,
  type GitHubLabPostCreateSubphase,
  type GitHubSnapshotReadbackCheck,
  type GitHubTokenAcquireSubphase,
} from "./repository-provisioning-diagnostics.ts";

export { GITHUB_SNAPSHOT_READBACK_CHECKS };

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const REPOSITORY = /^[A-Za-z0-9._-]{1,100}$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SHA256 = /^[0-9a-f]{64}$/;

export type GitHubRepositoryStateClassification =
  | "EMPTY_OR_UNINITIALIZED"
  | "ALREADY_COMPLETE"
  | "MARKER_MISSING"
  | "CONFLICT";

export type GitHubRepositoryStateInspectionAuthority = Readonly<{
  websiteWorkContextId: string;
  repositoryId: string;
  owner: string;
  repository: string;
  private: true;
  defaultBranch: "main";
  snapshotTreeSha256: string;
  markerContent: string;
}>;

export type GitHubRepositoryCompletionProof = Readonly<{
  providerRepositoryId: string;
  providerNodeId: string;
  owner: string;
  name: string;
  visibility: "PRIVATE";
  defaultBranch: "main";
  repositoryMarkerCommitSha: string;
}>;

type ReadInput = Readonly<{
  websiteWorkContextId: string;
  repositoryId: string;
  owner: string;
  repository: string;
}>;

type CommitReadInput = ReadInput & Readonly<{ commitSha: string }>;

export type GitHubRepositoryStateInspectionDependencies = Readonly<{
  readMetadata(input: ReadInput): Promise<unknown>;
  readRef(input: ReadInput & Readonly<{ ref: "heads/main" }>): Promise<unknown>;
  readSnapshot(input: CommitReadInput): Promise<unknown>;
  readMarker(input: CommitReadInput): Promise<unknown>;
}>;

type TokenBroker = Readonly<{
  issue(
    config: GitHubAppConfig,
    request:
      & GitHubTokenRequest
      & Readonly<{
        operation: "LAB_REPOSITORY_READ" | "PRODUCTION_REPOSITORY_READ";
      }>,
    authority: GitHubTokenAuthority,
  ): Promise<GitHubInstallationTokenLease>;
}>;

type InspectionHttpOperation = Extract<GitHubHttpOperation, {
  kind:
    | "REPOSITORY_METADATA"
    | "READ_REF"
    | "REPOSITORY_EMPTY_PROOF"
    | "COMMIT_METADATA"
    | "REPOSITORY_TREE"
    | "READ_BLOB"
    | "READ_PROJECT_MARKER";
}>;

export type GitHubRepositoryStateInspectionRuntimeDependencies = Readonly<{
  tokenBroker: TokenBroker;
  http: Readonly<{
    execute(operation: InspectionHttpOperation): Promise<GitHubHttpResult>;
  }>;
}>;

export class GitHubRepositoryStateInspectionError extends Error {
  declare readonly snapshotReadbackCheck?: GitHubSnapshotReadbackCheck;
  declare readonly tokenBrokerCode?: GitHubTokenBrokerCode;
  declare readonly tokenAcquireSubphase?: GitHubTokenAcquireSubphase;
  declare readonly tokenExchangeHttpClass?: GitHubTokenExchangeHttpClass;

  constructor(
    readonly code:
      | "REPOSITORY_IDENTITY_MISMATCH"
      | "REPOSITORY_STATE_UNCERTAIN",
    readonly postCreateSubphase?: Extract<
      GitHubLabPostCreateSubphase,
      | "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE"
      | "LAB_POST_CREATE_METADATA_READ"
      | "LAB_POST_CREATE_SNAPSHOT_READBACK"
      | "LAB_POST_CREATE_MARKER_READBACK"
      | "LAB_POST_CREATE_PROVENANCE_VALIDATE"
    >,
    snapshotReadbackCheck?: GitHubSnapshotReadbackCheck,
    refReadDiagnostic?: GitHubRefReadDiagnostic,
    tokenBrokerCode?: GitHubTokenBrokerCode,
    tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
    tokenExchangeHttpClass?: GitHubTokenExchangeHttpClass,
  ) {
    if (
      postCreateSubphase !== undefined &&
        ![
          "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
          "LAB_POST_CREATE_METADATA_READ",
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "LAB_POST_CREATE_MARKER_READBACK",
          "LAB_POST_CREATE_PROVENANCE_VALIDATE",
        ].includes(postCreateSubphase) ||
      snapshotReadbackCheck !== undefined &&
        (postCreateSubphase !== "LAB_POST_CREATE_SNAPSHOT_READBACK" ||
          !GITHUB_SNAPSHOT_READBACK_CHECKS.includes(snapshotReadbackCheck)) ||
      tokenBrokerCode !== undefined &&
        (postCreateSubphase !== "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE" ||
          !GITHUB_TOKEN_BROKER_CODES.includes(tokenBrokerCode)) ||
      tokenAcquireSubphase !== undefined &&
        (postCreateSubphase !== "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE" ||
          !GITHUB_TOKEN_ACQUIRE_SUBPHASES.includes(tokenAcquireSubphase)) ||
      tokenExchangeHttpClass !== undefined &&
        (tokenAcquireSubphase !== "TOKEN_HTTP_STATUS" ||
          !GITHUB_TOKEN_EXCHANGE_HTTP_CLASSES.includes(tokenExchangeHttpClass))
    ) throw new Error("REPOSITORY_STATE_INSPECTION_DIAGNOSTIC_INVALID");
    super(code);
    this.name = "GitHubRepositoryStateInspectionError";
    Object.defineProperty(this, "postCreateSubphase", {
      value: postCreateSubphase,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    Object.defineProperty(this, "snapshotReadbackCheck", {
      value: snapshotReadbackCheck,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    Object.defineProperty(this, "tokenBrokerCode", {
      value: tokenBrokerCode,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    Object.defineProperty(this, "tokenAcquireSubphase", {
      value: tokenAcquireSubphase,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    Object.defineProperty(this, "tokenExchangeHttpClass", {
      value: tokenExchangeHttpClass,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    repositoryStateInspectionErrors.add(this);
    if (
      postCreateSubphase === "LAB_POST_CREATE_SNAPSHOT_READBACK" &&
      snapshotReadbackCheck === "REF_READ"
    ) {
      repositoryRefReadDiagnostics.set(
        this,
        validateGitHubRefReadDiagnostic(refReadDiagnostic),
      );
    }
  }
}

const repositoryStateInspectionErrors = new WeakSet<object>();
const repositoryRefReadDiagnostics = new WeakMap<
  object,
  GitHubRefReadDiagnostic
>();

function isTrustedRepositoryStateInspectionError(
  value: unknown,
): value is GitHubRepositoryStateInspectionError {
  return typeof value === "object" && value !== null &&
    repositoryStateInspectionErrors.has(value);
}

export function hasValidatedGitHubRepositoryStateInspectionSubphase(
  value: unknown,
): value is GitHubRepositoryStateInspectionError & {
  readonly postCreateSubphase: GitHubLabPostCreateSubphase;
} {
  return isTrustedRepositoryStateInspectionError(value) &&
    value.postCreateSubphase !== undefined;
}

export function getValidatedGitHubRepositoryRefReadDiagnostic(
  value: unknown,
): GitHubRefReadDiagnostic {
  return validateGitHubRefReadDiagnostic(
    typeof value === "object" && value !== null
      ? repositoryRefReadDiagnostics.get(value)
      : undefined,
  );
}

function uncertain(
  subphase?: GitHubRepositoryStateInspectionError["postCreateSubphase"],
  snapshotReadbackCheck?: GitHubSnapshotReadbackCheck,
  refReadDiagnostic?: GitHubRefReadDiagnostic,
  tokenBrokerCode?: GitHubTokenBrokerCode,
  tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
  tokenExchangeHttpClass?: GitHubTokenExchangeHttpClass,
): never {
  throw new GitHubRepositoryStateInspectionError(
    "REPOSITORY_STATE_UNCERTAIN",
    subphase,
    snapshotReadbackCheck,
    refReadDiagnostic,
    tokenBrokerCode,
    tokenAcquireSubphase,
    tokenExchangeHttpClass,
  );
}

function record(
  value: unknown,
  subphase?: GitHubRepositoryStateInspectionError["postCreateSubphase"],
  snapshotReadbackCheck?: GitHubSnapshotReadbackCheck,
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    uncertain(subphase, snapshotReadbackCheck);
  }
  return value as Record<string, unknown>;
}

function projectAuthority(
  value: GitHubRepositoryStateInspectionAuthority,
): GitHubRepositoryStateInspectionAuthority {
  if (!value || typeof value !== "object" || Array.isArray(value)) uncertain();
  const keys = Object.keys(value).sort();
  const expectedKeys = [
    "websiteWorkContextId",
    "repositoryId",
    "owner",
    "repository",
    "private",
    "defaultBranch",
    "snapshotTreeSha256",
    "markerContent",
  ].sort();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (
    (Object.getPrototypeOf(value) !== Object.prototype &&
      Object.getPrototypeOf(value) !== null) ||
    keys.length !== expectedKeys.length ||
    !keys.every((key, index) => key === expectedKeys[index]) ||
    !expectedKeys.every((key) =>
      descriptors[key]?.enumerable === true &&
      Object.hasOwn(descriptors[key], "value")
    ) ||
    !UUID.test(value.websiteWorkContextId) ||
    !NUMERIC_ID.test(value.repositoryId) || !OWNER.test(value.owner) ||
    !REPOSITORY.test(value.repository) || value.private !== true ||
    value.defaultBranch !== "main" ||
    !SHA256.test(value.snapshotTreeSha256) ||
    typeof value.markerContent !== "string" ||
    value.markerContent.length === 0 || value.markerContent.length > 64 * 1024
  ) uncertain();
  return Object.freeze({
    websiteWorkContextId: value.websiteWorkContextId,
    repositoryId: value.repositoryId,
    owner: value.owner,
    repository: value.repository,
    private: true,
    defaultBranch: "main",
    snapshotTreeSha256: value.snapshotTreeSha256,
    markerContent: value.markerContent,
  });
}

function metadata(value: unknown): GitHubRepositoryMetadata {
  const candidate = record(value);
  if (
    typeof candidate.repositoryId !== "string" ||
    typeof candidate.owner !== "string" || typeof candidate.name !== "string" ||
    typeof candidate.fullName !== "string" ||
    typeof candidate.private !== "boolean" ||
    typeof candidate.defaultBranch !== "string"
  ) uncertain();
  return candidate as GitHubRepositoryMetadata;
}

function expectedMetadata(
  value: unknown,
  expected: GitHubRepositoryStateInspectionAuthority,
): GitHubRepositoryMetadata {
  const repository = metadata(value);
  if (
    repository.repositoryId !== expected.repositoryId ||
    repository.owner !== expected.owner ||
    repository.name !== expected.repository ||
    repository.fullName !== `${expected.owner}/${expected.repository}` ||
    repository.private !== expected.private ||
    repository.defaultBranch !== expected.defaultBranch
  ) {
    throw new GitHubRepositoryStateInspectionError(
      "REPOSITORY_IDENTITY_MISMATCH",
    );
  }
  return repository;
}

function commonInput(
  expected: GitHubRepositoryStateInspectionAuthority,
): ReadInput {
  return Object.freeze({
    websiteWorkContextId: expected.websiteWorkContextId,
    repositoryId: expected.repositoryId,
    owner: expected.owner,
    repository: expected.repository,
  });
}

function sameInput(
  value: ReadInput,
  expected: GitHubRepositoryStateInspectionAuthority,
): boolean {
  return value.websiteWorkContextId === expected.websiteWorkContextId &&
    value.repositoryId === expected.repositoryId &&
    value.owner === expected.owner &&
    value.repository === expected.repository;
}

function bytesFromBase64(
  value: string,
  subphase?: GitHubRepositoryStateInspectionError["postCreateSubphase"],
  snapshotReadbackCheck?: GitHubSnapshotReadbackCheck,
): Uint8Array {
  try {
    return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
  } catch {
    return uncertain(subphase, snapshotReadbackCheck);
  }
}

export function createGitHubRepositoryStateInspector(
  expected: GitHubRepositoryStateInspectionAuthority,
  dependencies: GitHubRepositoryStateInspectionDependencies,
): () => Promise<Readonly<{ state: GitHubRepositoryStateClassification }>> {
  const safeExpected = projectAuthority(expected);
  if (
    !dependencies ||
    typeof dependencies.readMetadata !== "function" ||
    typeof dependencies.readRef !== "function" ||
    typeof dependencies.readSnapshot !== "function" ||
    typeof dependencies.readMarker !== "function"
  ) uncertain();
  const input = commonInput(safeExpected);

  return async () => {
    try {
      expectedMetadata(await dependencies.readMetadata(input), safeExpected);
    } catch (error) {
      if (isTrustedRepositoryStateInspectionError(error)) throw error;
      return uncertain();
    }

    let ref: Record<string, unknown>;
    try {
      ref = record(await dependencies.readRef({ ...input, ref: "heads/main" }));
    } catch (error) {
      if (isTrustedRepositoryStateInspectionError(error)) throw error;
      return uncertain();
    }
    if (ref.state === "ABSENT" && Object.keys(ref).length === 1) {
      return Object.freeze({ state: "EMPTY_OR_UNINITIALIZED" as const });
    }
    if (
      ref.state !== "PRESENT" || Object.keys(ref).length !== 2 ||
      typeof ref.commitSha !== "string" || !SHA.test(ref.commitSha)
    ) uncertain();
    const commitInput = Object.freeze({ ...input, commitSha: ref.commitSha });

    let snapshot: Record<string, unknown>;
    try {
      snapshot = record(await dependencies.readSnapshot(commitInput));
    } catch (error) {
      if (isTrustedRepositoryStateInspectionError(error)) throw error;
      return uncertain();
    }
    if (
      Object.keys(snapshot).length !== 2 ||
      typeof snapshot.treeSha256 !== "string" ||
      !SHA256.test(snapshot.treeSha256) ||
      typeof snapshot.unexpectedContent !== "boolean"
    ) uncertain();
    if (
      snapshot.treeSha256 !== safeExpected.snapshotTreeSha256 ||
      snapshot.unexpectedContent
    ) return Object.freeze({ state: "CONFLICT" as const });

    let marker: Record<string, unknown>;
    try {
      marker = record(await dependencies.readMarker(commitInput));
    } catch (error) {
      if (isTrustedRepositoryStateInspectionError(error)) throw error;
      return uncertain();
    }
    if (marker.state === "ABSENT" && Object.keys(marker).length === 1) {
      return Object.freeze({ state: "MARKER_MISSING" as const });
    }
    if (
      marker.state !== "PRESENT" || Object.keys(marker).length !== 2 ||
      typeof marker.content !== "string"
    ) uncertain();
    return Object.freeze({
      state: marker.content === safeExpected.markerContent
        ? "ALREADY_COMPLETE" as const
        : "CONFLICT" as const,
    });
  };
}

export function inspectGitHubRepositoryCompletionProof(
  expected: GitHubRepositoryStateInspectionAuthority,
  dependencies: GitHubRepositoryStateInspectionDependencies,
): () => Promise<
  Readonly<{
    state: "ALREADY_COMPLETE";
    proof: GitHubRepositoryCompletionProof;
  }>
> {
  let metadataResult: unknown;
  let refResult: unknown;
  const inspect = createGitHubRepositoryStateInspector(expected, {
    async readMetadata(input) {
      metadataResult = await dependencies.readMetadata(input);
      return metadataResult;
    },
    async readRef(input) {
      refResult = await dependencies.readRef(input);
      return refResult;
    },
    readSnapshot: dependencies.readSnapshot,
    readMarker: dependencies.readMarker,
  });
  return async () => {
    const result = await inspect();
    if (result.state !== "ALREADY_COMPLETE") uncertain();
    const safeExpected = projectAuthority(expected);
    const repository = expectedMetadata(metadataResult, safeExpected);
    const ref = record(refResult);
    if (
      typeof repository.nodeId !== "string" || repository.nodeId.length === 0 ||
      repository.nodeId.length > 255 || typeof ref.commitSha !== "string" ||
      !SHA.test(ref.commitSha)
    ) uncertain();
    return Object.freeze({
      state: "ALREADY_COMPLETE" as const,
      proof: Object.freeze({
        providerRepositoryId: repository.repositoryId,
        providerNodeId: repository.nodeId,
        owner: repository.owner,
        name: repository.name,
        visibility: "PRIVATE" as const,
        defaultBranch: "main" as const,
        repositoryMarkerCommitSha: ref.commitSha,
      }),
    });
  };
}

function repositoryStateInspectionCapability(
  config: GitHubAppConfig,
  expected: GitHubRepositoryStateInspectionAuthority,
  dependencies: GitHubRepositoryStateInspectionRuntimeDependencies,
  completionProof: boolean,
  readAuthority: Readonly<{
    target: "TEST" | "PRODUCTION";
    operation: "LAB_REPOSITORY_READ" | "PRODUCTION_REPOSITORY_READ";
  }>,
): () => Promise<
  | Readonly<{ state: GitHubRepositoryStateClassification }>
  | Readonly<{
    state: "ALREADY_COMPLETE";
    proof: GitHubRepositoryCompletionProof;
  }>
> {
  const safeExpected = projectAuthority(expected);
  if (
    !config || config.target !== readAuthority.target ||
    config.organization !== safeExpected.owner || !dependencies ||
    typeof dependencies.tokenBroker?.issue !== "function" ||
    typeof dependencies.http?.execute !== "function"
  ) uncertain();

  const request = Object.freeze({
    websiteWorkContextId: safeExpected.websiteWorkContextId,
    target: readAuthority.target,
    organization: safeExpected.owner,
    operation: readAuthority.operation,
    repositoryIds: Object.freeze([safeExpected.repositoryId]),
  });
  const authority = Object.freeze({
    websiteWorkContextId: expected.websiteWorkContextId,
    target: readAuthority.target,
    organization: expected.owner,
    repositoryIds: request.repositoryIds,
  });
  let tokenLease: Promise<GitHubInstallationTokenLease> | undefined;
  const token = async () => {
    let lease: GitHubInstallationTokenLease;
    try {
      tokenLease ??= dependencies.tokenBroker.issue(config, request, authority);
      lease = await tokenLease;
    } catch (error) {
      return uncertain(
        "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
        undefined,
        undefined,
        error instanceof GitHubTokenBrokerError ? error.code : undefined,
        error instanceof GitHubTokenBrokerError
          ? error.tokenAcquireSubphase
          : undefined,
        error instanceof GitHubTokenBrokerError
          ? error.tokenExchangeHttpClass
          : undefined,
      );
    }
    if (!lease || typeof lease.token !== "string") {
      uncertain("LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE");
    }
    return lease.token;
  };
  const coordinates = async (input: ReadInput) => {
    if (!sameInput(input, safeExpected)) uncertain();
    return Object.freeze({
      owner: safeExpected.owner,
      repository: safeExpected.repository,
      token: await token(),
    });
  };
  const confirmRepositoryIdentity = async (input: ReadInput) => {
    let result: GitHubHttpResult;
    try {
      result = await dependencies.http.execute({
        kind: "REPOSITORY_METADATA",
        ...await coordinates(input),
      });
    } catch (error) {
      if (isTrustedRepositoryStateInspectionError(error)) throw error;
      return uncertain("LAB_POST_CREATE_METADATA_READ");
    }
    try {
      return expectedMetadata(result, safeExpected);
    } catch (error) {
      if (
        isTrustedRepositoryStateInspectionError(error) &&
        error.code === "REPOSITORY_IDENTITY_MISMATCH"
      ) throw error;
      return uncertain("LAB_POST_CREATE_METADATA_READ");
    }
  };
  const confirmCommit = async (input: CommitReadInput) => {
    let result: GitHubHttpResult;
    try {
      result = await dependencies.http.execute({
        kind: "COMMIT_METADATA",
        ...await coordinates(input),
        commitSha: input.commitSha,
      });
    } catch (error) {
      if (isTrustedRepositoryStateInspectionError(error)) throw error;
      return uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "COMMIT_READ");
    }
    const commit = record(
      result,
      "LAB_POST_CREATE_SNAPSHOT_READBACK",
      "COMMIT_READ",
    );
    if (
      commit.sha !== input.commitSha || typeof commit.treeSha !== "string" ||
      !SHA.test(commit.treeSha)
    ) uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "COMMIT_READ");
    return Object.freeze({ sha: input.commitSha, treeSha: commit.treeSha });
  };

  const inspectionDependencies: GitHubRepositoryStateInspectionDependencies = {
    async readMetadata(input) {
      return await confirmRepositoryIdentity(input);
    },
    async readRef(input) {
      try {
        const ref = record(
          await dependencies.http.execute({
            kind: "READ_REF",
            ...await coordinates(input),
            ref: "heads/main",
          }),
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "REF_READ",
        );
        if (
          ref.ref !== "refs/heads/main" ||
          typeof ref.commitSha !== "string" || !SHA.test(ref.commitSha)
        ) uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "REF_READ");
        return Object.freeze({
          state: "PRESENT" as const,
          commitSha: ref.commitSha,
        });
      } catch (error) {
        if (
          getValidatedGitHubHttpRefReadDiagnostic(error).code ===
            "GITHUB_HTTP_NOT_FOUND"
        ) {
          await confirmRepositoryIdentity(input);
          return Object.freeze({ state: "ABSENT" as const });
        }
        if (getValidatedGitHubHttpStatus(error) === 409) {
          try {
            const proof = record(
              await dependencies.http.execute({
                kind: "REPOSITORY_EMPTY_PROOF",
                ...await coordinates(input),
                expectedRepositoryId: safeExpected.repositoryId,
              }),
              "LAB_POST_CREATE_SNAPSHOT_READBACK",
              "REF_READ",
            );
            if (proof.empty === true && Object.keys(proof).length === 1) {
              return Object.freeze({ state: "ABSENT" as const });
            }
          } catch {
            // The original READ_REF conflict remains the causal diagnostic.
          }
        }
        if (isTrustedRepositoryStateInspectionError(error)) throw error;
        return uncertain(
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "REF_READ",
          getValidatedGitHubHttpRefReadDiagnostic(error),
        );
      }
    },
    async readSnapshot(input) {
      if (!SHA.test(input.commitSha)) uncertain();
      const repository = await coordinates(input);
      const commit = await confirmCommit(input);
      let treeResult: GitHubHttpResult;
      try {
        treeResult = await dependencies.http.execute({
          kind: "REPOSITORY_TREE",
          ...repository,
          treeRef: commit.treeSha,
        });
      } catch (error) {
        if (isTrustedRepositoryStateInspectionError(error)) throw error;
        return uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "TREE_READ");
      }
      const tree = record(
        treeResult,
        "LAB_POST_CREATE_SNAPSHOT_READBACK",
        "TREE_READ",
      );
      if (
        tree.sha !== commit.treeSha || tree.truncated !== false ||
        !Array.isArray(tree.entries)
      ) uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "TREE_READ");
      const entries: GitHubSnapshotDigestEntry[] = [];
      let unexpectedContent = false;
      for (const rawEntry of tree.entries as GitHubTreeEntry[]) {
        if (!rawEntry || typeof rawEntry !== "object") {
          uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "TREE_READ");
        }
        if (rawEntry.path === ".lws/project.json") {
          if (rawEntry.type !== "blob") unexpectedContent = true;
          continue;
        }
        if (rawEntry.type === "tree") continue;
        if (rawEntry.type !== "blob") {
          unexpectedContent = true;
          continue;
        }
        let blobResult: GitHubHttpResult;
        try {
          blobResult = await dependencies.http.execute({
            kind: "READ_BLOB",
            ...repository,
            blobSha: rawEntry.sha,
          });
        } catch (error) {
          if (isTrustedRepositoryStateInspectionError(error)) {
            throw error;
          }
          return uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "BLOB_READ");
        }
        const blob = record(
          blobResult,
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "BLOB_READ",
        );
        if (
          blob.sha !== rawEntry.sha || blob.encoding !== "base64" ||
          typeof blob.contentBase64 !== "string" ||
          typeof blob.size !== "number"
        ) uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "BLOB_READ");
        const content = bytesFromBase64(
          blob.contentBase64,
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "BLOB_READ",
        );
        if (content.byteLength !== blob.size) {
          uncertain("LAB_POST_CREATE_SNAPSHOT_READBACK", "BLOB_READ");
        }
        entries.push(Object.freeze({
          path: rawEntry.path,
          mode: rawEntry.mode,
          type: "blob" as const,
          content,
        }));
      }
      if (entries.length === 0) {
        return Object.freeze({
          treeSha256: "0".repeat(64),
          unexpectedContent: true,
        });
      }
      try {
        return Object.freeze({
          treeSha256: await computeGitHubSnapshotDigest(entries),
          unexpectedContent,
        });
      } catch {
        return uncertain("LAB_POST_CREATE_PROVENANCE_VALIDATE");
      }
    },
    async readMarker(input) {
      if (!SHA.test(input.commitSha)) uncertain();
      try {
        const marker = record(
          await dependencies.http.execute({
            kind: "READ_PROJECT_MARKER",
            ...await coordinates(input),
            ref: input.commitSha,
          }),
          "LAB_POST_CREATE_MARKER_READBACK",
        );
        if (
          marker.path !== ".lws/project.json" ||
          marker.encoding !== "base64" ||
          typeof marker.contentBase64 !== "string" ||
          typeof marker.size !== "number"
        ) uncertain("LAB_POST_CREATE_MARKER_READBACK");
        const content = bytesFromBase64(
          marker.contentBase64,
          "LAB_POST_CREATE_PROVENANCE_VALIDATE",
        );
        if (content.byteLength !== marker.size) {
          uncertain("LAB_POST_CREATE_PROVENANCE_VALIDATE");
        }
        try {
          return Object.freeze({
            state: "PRESENT" as const,
            content: new TextDecoder("utf-8", { fatal: true }).decode(content),
          });
        } catch {
          return uncertain("LAB_POST_CREATE_PROVENANCE_VALIDATE");
        }
      } catch (error) {
        if (
          getValidatedGitHubHttpRefReadDiagnostic(error).code ===
            "GITHUB_HTTP_NOT_FOUND"
        ) {
          await confirmRepositoryIdentity(input);
          await confirmCommit(input);
          return Object.freeze({ state: "ABSENT" as const });
        }
        if (isTrustedRepositoryStateInspectionError(error)) throw error;
        return uncertain("LAB_POST_CREATE_MARKER_READBACK");
      }
    },
  };
  return completionProof
    ? inspectGitHubRepositoryCompletionProof(
      safeExpected,
      inspectionDependencies,
    )
    : createGitHubRepositoryStateInspector(
      safeExpected,
      inspectionDependencies,
    );
}

export function createGitHubRepositoryStateInspectionCapability(
  config: GitHubAppConfig,
  expected: GitHubRepositoryStateInspectionAuthority,
  dependencies: GitHubRepositoryStateInspectionRuntimeDependencies,
): () => Promise<Readonly<{ state: GitHubRepositoryStateClassification }>> {
  return repositoryStateInspectionCapability(
    config,
    expected,
    dependencies,
    false,
    Object.freeze({ target: "TEST", operation: "LAB_REPOSITORY_READ" }),
  ) as () => Promise<
    Readonly<{
      state: GitHubRepositoryStateClassification;
    }>
  >;
}

export function createGitHubRepositoryCompletionProofCapability(
  config: GitHubAppConfig,
  expected: GitHubRepositoryStateInspectionAuthority,
  dependencies: GitHubRepositoryStateInspectionRuntimeDependencies,
): () => Promise<
  Readonly<{
    state: "ALREADY_COMPLETE";
    proof: GitHubRepositoryCompletionProof;
  }>
> {
  return repositoryStateInspectionCapability(
    config,
    expected,
    dependencies,
    true,
    Object.freeze({ target: "TEST", operation: "LAB_REPOSITORY_READ" }),
  ) as () => Promise<
    Readonly<{
      state: "ALREADY_COMPLETE";
      proof: GitHubRepositoryCompletionProof;
    }>
  >;
}

export function createProductionRepositoryStateInspectionCapability(
  config: GitHubAppConfig,
  expected: GitHubRepositoryStateInspectionAuthority,
  dependencies: GitHubRepositoryStateInspectionRuntimeDependencies,
): () => Promise<Readonly<{ state: GitHubRepositoryStateClassification }>> {
  return repositoryStateInspectionCapability(
    config,
    expected,
    dependencies,
    false,
    Object.freeze({
      target: "PRODUCTION",
      operation: "PRODUCTION_REPOSITORY_READ",
    }),
  ) as () => Promise<Readonly<{ state: GitHubRepositoryStateClassification }>>;
}

export function createProductionRepositoryCompletionProofCapability(
  config: GitHubAppConfig,
  expected: GitHubRepositoryStateInspectionAuthority,
  dependencies: GitHubRepositoryStateInspectionRuntimeDependencies,
): () => Promise<
  Readonly<{
    state: "ALREADY_COMPLETE";
    proof: GitHubRepositoryCompletionProof;
  }>
> {
  return repositoryStateInspectionCapability(
    config,
    expected,
    dependencies,
    true,
    Object.freeze({
      target: "PRODUCTION",
      operation: "PRODUCTION_REPOSITORY_READ",
    }),
  ) as () => Promise<
    Readonly<{
      state: "ALREADY_COMPLETE";
      proof: GitHubRepositoryCompletionProof;
    }>
  >;
}

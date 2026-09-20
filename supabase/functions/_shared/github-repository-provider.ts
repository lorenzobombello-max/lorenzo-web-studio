import type {
  RepositoryProvisioningProviderV2,
  RepositoryProvisioningRequestV2,
  VerifiedRepositoryBindingV2,
} from "./repository-provisioning.ts";
import type { GitHubProviderTarget } from "./github-app-config.ts";
import {
  computeGitHubSnapshotDigest,
  GitHubSnapshotDigestError,
} from "./github-snapshot-digest.ts";
import {
  GITHUB_LAB_CREATE_SUBPHASES,
  type GitHubLabCreateSubphase,
  GitHubLabPostCreateDiagnosticError,
  GitHubTokenAcquireDiagnosticError,
  type GitHubTokenAcquireSubphase,
  type GitHubTokenLeaseCheck,
  type GitHubTokenResponseCheck,
  hasValidatedGitHubLabPostCreateDiagnosticError,
  hasValidatedGitHubTokenAcquireDiagnostic,
  hasValidatedGitHubTokenLeaseCheck,
  hasValidatedGitHubTokenResponseCheck,
  REPOSITORY_STARTER_READ_SUBPHASES,
  type RepositoryProviderSubphase,
  RepositoryProvisioningProviderDiagnosticError,
  type RepositoryProvisioningProviderFailurePhase,
  type RepositoryStarterReadSubphase,
} from "./repository-provisioning-diagnostics.ts";

export { GitHubLabPostCreateDiagnosticError } from "./repository-provisioning-diagnostics.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const REPOSITORY = /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,98}[A-Za-z0-9])?$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SHA256 = /^[0-9a-f]{64}$/;
const VERSION = /^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$/;
const NODE_ID = /^[A-Za-z0-9_-]{6,128}$/;

export type GitHubSnapshotEntry = Readonly<{
  path: string;
  mode: string;
  type: "blob";
  content: Uint8Array;
}>;

export type GitHubStarterSnapshot = Readonly<{
  installationId: string;
  repositoryId: string;
  owner: string;
  repository: string;
  commitSha: string;
  entries: readonly GitHubSnapshotEntry[];
}>;

export type GitHubLabRepositoryIdentity = Readonly<{
  installationId: string;
  repositoryId: string;
  nodeId: string;
  owner: string;
  name: string;
  private: true;
  defaultBranch: "main";
}>;

export type GitHubLabBindingReadback =
  & GitHubLabRepositoryIdentity
  & Readonly<{
    sourceTreeSha256: string;
    markerContent: string;
    markerCommitSha: string;
  }>;

export type GitHubLabReconciliation =
  | Readonly<{ state: "MATCH"; identity: GitHubLabRepositoryIdentity }>
  | Readonly<{ state: "AMBIGUOUS" }>;

export type GitHubRepositoryIdentity = GitHubLabRepositoryIdentity;
export type GitHubRepositoryBindingReadback = GitHubLabBindingReadback;
export type GitHubRepositoryReconciliation = GitHubLabReconciliation;

export type GitHubTargetRepositoryProviderConfig = Readonly<{
  source: GitHubRepositoryProviderConfig["source"];
  target: Readonly<{
    providerTarget: GitHubProviderTarget;
    installationId: string;
    organization: string;
  }>;
}>;

export type GitHubRepositoryProviderConfig = Readonly<{
  source: Readonly<{
    installationId: string;
    owner: string;
    repository: string;
    repositoryId: string;
    version: string;
    commitSha: string;
    treeSha256: string;
  }>;
  lab: Readonly<{
    installationId: string;
    organization: string;
  }>;
}>;

export type GitHubRepositoryProviderDependencies = Readonly<{
  readStarter(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      installationId: string;
      owner: string;
      repository: string;
      repositoryId: string;
      commitSha: string;
    }>,
  ): Promise<GitHubStarterSnapshot>;
  createLab(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      installationId: string;
      organization: string;
      repository: string;
      private: true;
    }>,
  ): Promise<GitHubLabRepositoryIdentity>;
  reconcileLab(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      installationId: string;
      organization: string;
      repository: string;
    }>,
  ): Promise<GitHubLabReconciliation>;
  quarantineLab(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      reason: "REPOSITORY_IDENTITY_MISMATCH";
    }>,
  ): Promise<void>;
  captureLabIdentity(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      identity: GitHubLabRepositoryIdentity;
    }>,
  ): Promise<void>;
  writeLabSnapshot(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      installationId: string;
      identity: GitHubLabRepositoryIdentity;
      entries: readonly GitHubSnapshotEntry[];
      markerContent: string;
    }>,
  ): Promise<
    Readonly<{
      snapshotCommitSha: string;
      markerCommitSha: string;
    }>
  >;
  readLabBinding(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      installationId: string;
      identity: GitHubLabRepositoryIdentity;
      snapshotCommitSha: string;
      markerCommitSha: string;
    }>,
  ): Promise<GitHubLabBindingReadback>;
}>;

export type GitHubTargetRepositoryProviderDependencies = Readonly<{
  readStarter: GitHubRepositoryProviderDependencies["readStarter"];
  createTarget: GitHubRepositoryProviderDependencies["createLab"];
  reconcileTarget: GitHubRepositoryProviderDependencies["reconcileLab"];
  quarantineTarget: GitHubRepositoryProviderDependencies["quarantineLab"];
  captureTargetIdentity: GitHubRepositoryProviderDependencies["captureLabIdentity"];
  writeTargetSnapshot: GitHubRepositoryProviderDependencies["writeLabSnapshot"];
  readTargetBinding: GitHubRepositoryProviderDependencies["readLabBinding"];
}>;

export class GitHubRepositoryProviderError
  extends RepositoryProvisioningProviderDiagnosticError {
  constructor(
    readonly code: RepositoryProvisioningProviderFailurePhase,
    subphase?: RepositoryProviderSubphase,
    tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
    tokenLeaseCheck?: GitHubTokenLeaseCheck,
    tokenResponseCheck?: GitHubTokenResponseCheck,
  ) {
    super(
      code,
      subphase,
      tokenAcquireSubphase,
      tokenLeaseCheck,
      tokenResponseCheck,
    );
    this.name = "GitHubRepositoryProviderError";
    Object.defineProperty(this, "code", {
      value: code,
      enumerable: true,
      writable: false,
      configurable: false,
    });
  }
}

export class GitHubStarterReadDiagnosticError
  extends GitHubTokenAcquireDiagnosticError {
  constructor(
    readonly subphase: RepositoryStarterReadSubphase,
    tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
    tokenLeaseCheck?: GitHubTokenLeaseCheck,
    tokenResponseCheck?: GitHubTokenResponseCheck,
  ) {
    if (!REPOSITORY_STARTER_READ_SUBPHASES.includes(subphase)) {
      throw new Error("GITHUB_STARTER_READ_DIAGNOSTIC_INVALID");
    }
    if (
      tokenAcquireSubphase !== undefined &&
      subphase !== "STARTER_TOKEN_ACQUIRE"
    ) throw new Error("GITHUB_STARTER_READ_DIAGNOSTIC_INVALID");
    super(
      "GITHUB_STARTER_READ_FAILED",
      tokenAcquireSubphase,
      tokenLeaseCheck,
      tokenResponseCheck,
    );
    this.name = "GitHubStarterReadDiagnosticError";
    Object.defineProperty(this, "subphase", {
      value: subphase,
      enumerable: true,
      writable: false,
      configurable: false,
    });
  }
}

const githubLabCreateUnknownOutcomes = new WeakSet<object>();
const githubLabCreateDiagnostics = new WeakSet<object>();

export class GitHubLabCreateOutcomeUnknownError extends Error {
  constructor(readonly subphase?: GitHubLabCreateSubphase) {
    if (
      subphase !== undefined && !GITHUB_LAB_CREATE_SUBPHASES.includes(subphase)
    ) {
      throw new Error("GITHUB_LAB_CREATE_DIAGNOSTIC_INVALID");
    }
    super("GITHUB_LAB_CREATE_OUTCOME_UNKNOWN");
    this.name = "GitHubLabCreateOutcomeUnknownError";
    Object.defineProperty(this, "subphase", {
      value: subphase,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    githubLabCreateUnknownOutcomes.add(this);
  }
}

export class GitHubLabCreateDiagnosticError
  extends GitHubTokenAcquireDiagnosticError {
  constructor(
    readonly subphase: GitHubLabCreateSubphase,
    tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
    tokenLeaseCheck?: GitHubTokenLeaseCheck,
    tokenResponseCheck?: GitHubTokenResponseCheck,
  ) {
    if (!GITHUB_LAB_CREATE_SUBPHASES.includes(subphase)) {
      throw new Error("GITHUB_LAB_CREATE_DIAGNOSTIC_INVALID");
    }
    if (
      tokenAcquireSubphase !== undefined && subphase !== "LAB_TOKEN_ACQUIRE"
    ) throw new Error("GITHUB_LAB_CREATE_DIAGNOSTIC_INVALID");
    super(
      "GITHUB_LAB_CREATE_FAILED",
      tokenAcquireSubphase,
      tokenLeaseCheck,
      tokenResponseCheck,
    );
    this.name = "GitHubLabCreateDiagnosticError";
    Object.defineProperty(this, "subphase", {
      value: subphase,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    githubLabCreateDiagnostics.add(this);
  }
}

function isValidatedGitHubLabCreateOutcomeUnknownError(
  value: unknown,
): value is GitHubLabCreateOutcomeUnknownError {
  return typeof value === "object" && value !== null &&
    githubLabCreateUnknownOutcomes.has(value);
}

function isValidatedGitHubLabCreateDiagnosticError(
  value: unknown,
): value is GitHubLabCreateDiagnosticError {
  return typeof value === "object" && value !== null &&
    githubLabCreateDiagnostics.has(value);
}

function fail(
  code: RepositoryProvisioningProviderFailurePhase,
  subphase?: RepositoryProviderSubphase,
  tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
  tokenLeaseCheck?: GitHubTokenLeaseCheck,
  tokenResponseCheck?: GitHubTokenResponseCheck,
): never {
  throw new GitHubRepositoryProviderError(
    code,
    subphase,
    tokenAcquireSubphase,
    tokenLeaseCheck,
    tokenResponseCheck,
  );
}

function exactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}

export async function computeSnapshotDigest(
  entries: readonly GitHubSnapshotEntry[],
): Promise<string> {
  try {
    return await computeGitHubSnapshotDigest(entries);
  } catch (error) {
    if (
      error instanceof GitHubSnapshotDigestError &&
      error.code === "DIGEST_CALCULATE"
    ) {
      return fail(
        "GITHUB_STARTER_SNAPSHOT_INVALID",
        "STARTER_DIGEST_CALCULATE",
      );
    }
    return fail(
      "GITHUB_STARTER_SNAPSHOT_INVALID",
      "STARTER_SNAPSHOT_VALIDATE",
    );
  }
}

function validTargetConfig(config: GitHubTargetRepositoryProviderConfig): boolean {
  return exactKeys(config, ["source", "target"]) &&
    exactKeys(config.source, [
      "installationId",
      "owner",
      "repository",
      "repositoryId",
      "version",
      "commitSha",
      "treeSha256",
    ]) && exactKeys(config.target, [
      "providerTarget",
      "installationId",
      "organization",
    ]) &&
    NUMERIC_ID.test(config.source.installationId) &&
    NUMERIC_ID.test(config.target.installationId) &&
    ["TEST", "PRODUCTION"].includes(config.target.providerTarget) &&
    OWNER.test(config.source.owner) && OWNER.test(config.target.organization) &&
    (config.target.providerTarget === "PRODUCTION"
      ? config.source.owner.toLowerCase() === config.target.organization.toLowerCase()
      : config.source.installationId !== config.target.installationId &&
        config.source.owner.toLowerCase() !== config.target.organization.toLowerCase()) &&
    REPOSITORY.test(config.source.repository) &&
    NUMERIC_ID.test(config.source.repositoryId) &&
    VERSION.test(config.source.version) && SHA.test(config.source.commitSha) &&
    SHA256.test(config.source.treeSha256);
}

function validRequest(
  request: RepositoryProvisioningRequestV2,
  config: GitHubTargetRepositoryProviderConfig,
): boolean {
  return exactKeys(request, [
    "contractVersion",
    "operationId",
    "websiteWorkContextId",
    "repositoryName",
    "visibility",
    "defaultBranch",
    "bootstrap",
    "starter",
  ]) && exactKeys(request.starter, [
    "source",
    "version",
    "commitSha",
    "templateRepositoryId",
  ]) && request.contractVersion === 2 && UUID.test(request.operationId) &&
    UUID.test(request.websiteWorkContextId) &&
    request.repositoryName ===
      `lws-web-${
        request.websiteWorkContextId.toLowerCase().replaceAll("-", "")
      }` &&
    request.visibility === "PRIVATE" && request.defaultBranch === "main" &&
    request.bootstrap === "GITHUB_SNAPSHOT" &&
    request.starter.source ===
      `${config.source.owner}/${config.source.repository}` &&
    request.starter.version === config.source.version &&
    request.starter.commitSha === config.source.commitSha &&
    request.starter.templateRepositoryId === config.source.repositoryId;
}

function validIdentityFields(
  identity: GitHubLabRepositoryIdentity,
  config: GitHubTargetRepositoryProviderConfig,
  repositoryName: string,
): boolean {
  return identity.installationId === config.target.installationId &&
    NUMERIC_ID.test(identity.repositoryId) && NODE_ID.test(identity.nodeId) &&
    identity.owner === config.target.organization &&
    identity.name === repositoryName &&
    identity.private === true && identity.defaultBranch === "main";
}

function validIdentity(
  identity: GitHubLabRepositoryIdentity,
  config: GitHubTargetRepositoryProviderConfig,
  repositoryName: string,
): boolean {
  return exactKeys(identity, [
    "installationId",
    "repositoryId",
    "nodeId",
    "owner",
    "name",
    "private",
    "defaultBranch",
  ]) && validIdentityFields(identity, config, repositoryName);
}

function markerFor(
  request: RepositoryProvisioningRequestV2,
  config: GitHubTargetRepositoryProviderConfig,
): string {
  return `${
    JSON.stringify(
      {
        schema_version: 1,
        environment: config.target.providerTarget,
        organization: config.target.organization,
        website_work_context_id: request.websiteWorkContextId,
        repository_provisioning_operation_id: request.operationId,
        starter_source: request.starter.source,
        starter_version: `v${request.starter.version}`,
        starter_commit_sha: request.starter.commitSha,
        starter_tree_sha256: config.source.treeSha256,
      },
      null,
      2,
    )
  }\n`;
}

function copyEntries(
  entries: readonly GitHubSnapshotEntry[],
): readonly GitHubSnapshotEntry[] {
  return Object.freeze(entries.map((entry) =>
    Object.freeze({
      ...entry,
      content: entry.content.slice(),
    })
  ));
}

export function createGitHubTargetRepositoryProvider(
  config: GitHubTargetRepositoryProviderConfig,
  dependencies: GitHubTargetRepositoryProviderDependencies,
): RepositoryProvisioningProviderV2 {
  if (
    !validTargetConfig(config) || !dependencies || typeof dependencies !== "object"
  ) {
    fail("GITHUB_REPOSITORY_PROVIDER_CONFIG_INVALID");
  }
  for (
    const method of [
      dependencies.readStarter,
      dependencies.createTarget,
      dependencies.reconcileTarget,
      dependencies.quarantineTarget,
      dependencies.captureTargetIdentity,
      dependencies.writeTargetSnapshot,
      dependencies.readTargetBinding,
    ]
  ) {
    if (typeof method !== "function") {
      fail("GITHUB_REPOSITORY_PROVIDER_CONFIG_INVALID");
    }
  }

  return Object.freeze({
    async provision(
      request: RepositoryProvisioningRequestV2,
    ): Promise<VerifiedRepositoryBindingV2> {
      if (!validRequest(request, config)) {
        fail("GITHUB_REPOSITORY_PROVIDER_REQUEST_INVALID");
      }

      let snapshot: GitHubStarterSnapshot;
      try {
        snapshot = await dependencies.readStarter(Object.freeze({
          operationId: request.operationId,
          websiteWorkContextId: request.websiteWorkContextId,
          installationId: config.source.installationId,
          owner: config.source.owner,
          repository: config.source.repository,
          repositoryId: config.source.repositoryId,
          commitSha: config.source.commitSha,
        }));
        const digest = await computeSnapshotDigest(snapshot.entries);
        if (
          snapshot.installationId !== config.source.installationId ||
          snapshot.repositoryId !== config.source.repositoryId ||
          snapshot.owner !== config.source.owner ||
          snapshot.repository !== config.source.repository ||
          snapshot.commitSha !== config.source.commitSha
        ) {
          fail(
            "GITHUB_STARTER_SNAPSHOT_INVALID",
            "STARTER_IDENTITY_VALIDATE",
          );
        }
        if (digest !== config.source.treeSha256) {
          fail(
            "GITHUB_STARTER_SNAPSHOT_INVALID",
            "STARTER_DIGEST_COMPARE",
          );
        }
      } catch (error) {
        if (error instanceof GitHubStarterReadDiagnosticError) {
          throw new GitHubRepositoryProviderError(
            "GITHUB_STARTER_SNAPSHOT_INVALID",
            error.subphase,
            error.tokenAcquireSubphase,
            error.tokenLeaseCheck,
            hasValidatedGitHubTokenResponseCheck(error)
              ? error.tokenResponseCheck
              : undefined,
          );
        }
        if (
          error instanceof GitHubRepositoryProviderError &&
          error.code === "GITHUB_STARTER_SNAPSHOT_INVALID"
        ) throw error;
        fail("GITHUB_STARTER_SNAPSHOT_INVALID");
      }

      let identity: GitHubLabRepositoryIdentity;
      try {
        identity = await dependencies.createTarget(Object.freeze({
          operationId: request.operationId,
          websiteWorkContextId: request.websiteWorkContextId,
          installationId: config.target.installationId,
          organization: config.target.organization,
          repository: request.repositoryName,
          private: true,
        }));
      } catch (error) {
        if (isValidatedGitHubLabCreateDiagnosticError(error)) {
          throw new GitHubRepositoryProviderError(
            "GITHUB_LAB_CREATE_FAILED",
            error.subphase,
            error.tokenAcquireSubphase,
            hasValidatedGitHubTokenLeaseCheck(error)
              ? error.tokenLeaseCheck
              : undefined,
            hasValidatedGitHubTokenResponseCheck(error)
              ? error.tokenResponseCheck
              : undefined,
          );
        }
        if (!isValidatedGitHubLabCreateOutcomeUnknownError(error)) {
          fail("GITHUB_LAB_CREATE_FAILED");
        }
        let reconciliation: GitHubLabReconciliation;
        try {
          reconciliation = await dependencies.reconcileTarget(Object.freeze({
            operationId: request.operationId,
            websiteWorkContextId: request.websiteWorkContextId,
            installationId: config.target.installationId,
            organization: config.target.organization,
            repository: request.repositoryName,
          }));
        } catch {
          reconciliation = Object.freeze({ state: "AMBIGUOUS" });
        }
        if (reconciliation.state !== "MATCH") {
          try {
            await dependencies.quarantineTarget(Object.freeze({
              operationId: request.operationId,
              websiteWorkContextId: request.websiteWorkContextId,
              reason: "REPOSITORY_IDENTITY_MISMATCH",
            }));
          } catch {
            fail("GITHUB_LAB_QUARANTINE_FAILED");
          }
          fail("GITHUB_LAB_RECONCILIATION_AMBIGUOUS", error.subphase);
        }
        identity = reconciliation.identity;
      }
      if (!validIdentity(identity, config, request.repositoryName)) {
        fail("GITHUB_LAB_POST_CREATE_FAILED");
      }

      const markerContent = markerFor(request, config);
      try {
        await dependencies.captureTargetIdentity(Object.freeze({
          operationId: request.operationId,
          websiteWorkContextId: request.websiteWorkContextId,
          identity,
        }));
      } catch {
        try {
          await dependencies.quarantineTarget(Object.freeze({
            operationId: request.operationId,
            websiteWorkContextId: request.websiteWorkContextId,
            reason: "REPOSITORY_IDENTITY_MISMATCH",
          }));
        } catch {
          fail("GITHUB_LAB_QUARANTINE_FAILED");
        }
        fail("GITHUB_LAB_POST_CREATE_FAILED");
      }
      try {
        let preparedEntries: readonly GitHubSnapshotEntry[];
        try {
          preparedEntries = copyEntries(snapshot.entries);
        } catch {
          throw new GitHubLabPostCreateDiagnosticError(
            "LAB_POST_CREATE_SNAPSHOT_PREPARE",
          );
        }
        const written = await dependencies.writeTargetSnapshot(Object.freeze({
          operationId: request.operationId,
          websiteWorkContextId: request.websiteWorkContextId,
          installationId: config.target.installationId,
          identity,
          entries: preparedEntries,
          markerContent,
        }));
        if (
          !exactKeys(written, ["snapshotCommitSha", "markerCommitSha"]) ||
          !SHA.test(written.snapshotCommitSha) ||
          !SHA.test(written.markerCommitSha)
        ) {
          throw new GitHubLabPostCreateDiagnosticError(
            "LAB_POST_CREATE_WRITE_RESULT_VALIDATE",
          );
        }
        const readback = await dependencies.readTargetBinding(Object.freeze({
          operationId: request.operationId,
          websiteWorkContextId: request.websiteWorkContextId,
          installationId: config.target.installationId,
          identity,
          snapshotCommitSha: written.snapshotCommitSha,
          markerCommitSha: written.markerCommitSha,
        }));
        if (
          !exactKeys(readback, [
            "installationId",
            "repositoryId",
            "nodeId",
            "owner",
            "name",
            "private",
            "defaultBranch",
            "sourceTreeSha256",
            "markerContent",
            "markerCommitSha",
          ]) ||
          !validIdentityFields(readback, config, request.repositoryName) ||
          readback.repositoryId !== identity.repositoryId ||
          readback.nodeId !== identity.nodeId ||
          readback.sourceTreeSha256 !== config.source.treeSha256 ||
          readback.markerContent !== markerContent ||
          readback.markerCommitSha !== written.markerCommitSha
        ) fail("GITHUB_LAB_BINDING_INVALID");
        return Object.freeze({
          provider: "GITHUB" as const,
          providerRepositoryId: identity.repositoryId,
          providerNodeId: identity.nodeId,
          owner: identity.owner,
          name: identity.name,
          visibility: "PRIVATE" as const,
          defaultBranch: "main" as const,
          starterSource: request.starter.source,
          starterVersion: request.starter.version,
          starterCommitSha: request.starter.commitSha,
          repositoryMarkerCommitSha: written.markerCommitSha,
        });
      } catch (error) {
        if (hasValidatedGitHubLabPostCreateDiagnosticError(error)) {
          fail(
            "GITHUB_LAB_POST_CREATE_FAILED",
            error.subphase,
            hasValidatedGitHubTokenAcquireDiagnostic(error)
              ? error.tokenAcquireSubphase
              : undefined,
            hasValidatedGitHubTokenAcquireDiagnostic(error) &&
                hasValidatedGitHubTokenLeaseCheck(error)
              ? error.tokenLeaseCheck
              : undefined,
            hasValidatedGitHubTokenAcquireDiagnostic(error) &&
                hasValidatedGitHubTokenResponseCheck(error)
              ? error.tokenResponseCheck
              : undefined,
          );
        }
        if (
          error instanceof GitHubRepositoryProviderError &&
          error.code === "GITHUB_LAB_BINDING_INVALID"
        ) throw error;
        fail("GITHUB_LAB_POST_CREATE_FAILED");
      }
    },
  });
}

export function createGitHubRepositoryProvider(
  config: GitHubRepositoryProviderConfig,
  dependencies: GitHubRepositoryProviderDependencies,
): RepositoryProvisioningProviderV2 {
  return createGitHubTargetRepositoryProvider(Object.freeze({
    source: config.source,
    target: Object.freeze({
      providerTarget: "TEST" as const,
      installationId: config.lab.installationId,
      organization: config.lab.organization,
    }),
  }), Object.freeze({
    readStarter: dependencies.readStarter,
    createTarget: dependencies.createLab,
    reconcileTarget: dependencies.reconcileLab,
    quarantineTarget: dependencies.quarantineLab,
    captureTargetIdentity: dependencies.captureLabIdentity,
    writeTargetSnapshot: dependencies.writeLabSnapshot,
    readTargetBinding: dependencies.readLabBinding,
  }));
}

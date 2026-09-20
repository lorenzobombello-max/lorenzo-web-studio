import type { GitHubAppConfig } from "./github-app-config.ts";
import type {
  GitHubInstallationTokenLease,
  GitHubTokenAuthority,
  GitHubTokenRequest,
} from "./github-app-token.ts";
import {
  type GitHubHttpClient,
  GitHubHttpError,
  type GitHubHttpFailureBoundary,
  type GitHubHttpResult,
  type GitHubRepositoryMetadata,
  type GitHubTreeEntry,
  hasValidatedGitHubHttpBoundary,
} from "./github-http.ts";
import {
  computeSnapshotDigest,
  createGitHubRepositoryProvider,
  createGitHubTargetRepositoryProvider,
  GitHubLabCreateDiagnosticError,
  GitHubLabCreateOutcomeUnknownError,
  GitHubLabPostCreateDiagnosticError,
  type GitHubLabRepositoryIdentity,
  type GitHubSnapshotEntry,
  GitHubStarterReadDiagnosticError,
} from "./github-repository-provider.ts";
import {
  type GitHubLabCreateSubphase,
  type GitHubTokenAcquireSubphase,
  type GitHubTokenLeaseCheck,
  type GitHubTokenResponseCheck,
  hasValidatedGitHubTokenAcquireDiagnostic,
  hasValidatedGitHubTokenLeaseCheck,
  hasValidatedGitHubTokenResponseCheck,
  type RepositoryStarterReadSubphase,
} from "./repository-provisioning-diagnostics.ts";
import {
  type RepositoryProvisioningCommandV2,
  type RepositoryProvisioningProviderV2,
  type RepositoryProvisioningResultV2,
  RepositoryProvisioningServiceV2,
} from "./repository-provisioning.ts";
import type { RepositoryProvisioningRuntimeStoreV2 } from "./repository-provisioning-store-v2.ts";

const LAB_CREATE_DESCRIPTION_PREFIX = "LWS Task 13 operation ";
const PRODUCTION_CREATE_DESCRIPTION_PREFIX = "LWS website operation ";

const LAB_CREATE_HTTP_SUBPHASES = Object.freeze(
  {
    REQUEST_PREPARE: "LAB_CREATE_REQUEST_PREPARE",
    HTTP_REQUEST: "LAB_CREATE_HTTP_REQUEST",
    HTTP_STATUS: "LAB_CREATE_HTTP_STATUS",
    CONTENT_TYPE: "LAB_CREATE_CONTENT_TYPE",
    BODY_READ: "LAB_CREATE_BODY_READ",
    JSON_PARSE: "LAB_CREATE_JSON_PARSE",
    RESPONSE_SCHEMA: "LAB_CREATE_RESPONSE_SCHEMA",
  } satisfies Record<GitHubHttpFailureBoundary, GitHubLabCreateSubphase>,
);

type TokenBroker = Readonly<{
  issue(
    config: GitHubAppConfig,
    request: GitHubTokenRequest,
    authority: GitHubTokenAuthority,
  ): Promise<GitHubInstallationTokenLease>;
}>;

export class GitHubLabPrivateVisibilityUnprovenError extends Error {
  constructor() {
    super("GITHUB_LAB_PRIVATE_VISIBILITY_UNPROVEN");
    this.name = "GitHubLabPrivateVisibilityUnprovenError";
  }
}

export class GitHubLabRepositoryTokenError extends Error {
  constructor() {
    super("GITHUB_LAB_REPOSITORY_TOKEN_FAILED");
    this.name = "GitHubLabRepositoryTokenError";
  }
}

export function createGitHubLabRepositoryMetadataReader(
  config: GitHubRepositoryRuntimeConfig,
  dependencies: Pick<
    GitHubRepositoryRuntimeDependencies,
    "tokenBroker" | "http"
  >,
  provePrivateLabVisibility: (
    input: Readonly<{
      config: GitHubAppConfig;
      organization: string;
      repository: string;
    }>,
  ) => boolean | Promise<boolean> = () => true,
) {
  return async (
    input: Readonly<{
      websiteWorkContextId: string;
      organization: string;
      repository: string;
    }>,
  ): Promise<GitHubRepositoryMetadata> => {
    const request = Object.freeze({
      websiteWorkContextId: input.websiteWorkContextId,
      target: config.lab.target,
      organization: config.lab.organization,
      operation: "LAB_REPOSITORY_CREATE" as const,
      repositoryIds: Object.freeze([]),
    });
    const authority = Object.freeze({
      websiteWorkContextId: request.websiteWorkContextId,
      target: request.target,
      organization: request.organization,
      repositoryIds: request.repositoryIds,
    });
    if (
      !await provePrivateLabVisibility({
        config: config.lab,
        organization: input.organization,
        repository: input.repository,
      })
    ) {
      throw new GitHubLabPrivateVisibilityUnprovenError();
    }
    let lease: GitHubInstallationTokenLease;
    try {
      lease = await dependencies.tokenBroker.issue(
        config.lab,
        request,
        authority,
      );
    } catch {
      throw new GitHubLabRepositoryTokenError();
    }
    return repository(
      await dependencies.http.execute({
        kind: "REPOSITORY_METADATA",
        owner: input.organization,
        repository: input.repository,
        token: lease.token,
      }),
    );
  };
}

export type GitHubRepositoryRuntimeConfig = Readonly<{
  production: GitHubAppConfig;
  lab: GitHubAppConfig;
}>;

export type GitHubRepositoryRuntimeDependencies = Readonly<{
  store: RepositoryProvisioningRuntimeStoreV2;
  tokenBroker: TokenBroker;
  http: GitHubHttpClient;
}>;

export class GitHubRepositoryRuntimeError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "GitHubRepositoryRuntimeError";
  }
}

function fail(code: string): never {
  throw new GitHubRepositoryRuntimeError(code);
}

function starterFail(
  subphase: RepositoryStarterReadSubphase,
  tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
  tokenLeaseCheck?: GitHubTokenLeaseCheck,
  tokenResponseCheck?: GitHubTokenResponseCheck,
): never {
  throw new GitHubStarterReadDiagnosticError(
    subphase,
    tokenAcquireSubphase,
    tokenLeaseCheck,
    tokenResponseCheck,
  );
}

function validConfig(config: GitHubRepositoryRuntimeConfig): boolean {
  return config.production.target === "PRODUCTION" &&
    config.lab.target === "TEST" &&
    config.production.installationId === "161436785" &&
    config.lab.installationId === "161461160" &&
    config.production.organization === "lorenzo-web-solutions" &&
    config.lab.organization === "lorenzo-web-solutions-lab" &&
    config.production.appId === config.lab.appId &&
    config.production.templateOwner === "lorenzo-web-solutions" &&
    config.lab.templateOwner === config.production.templateOwner &&
    config.production.templateName === config.lab.templateName &&
    config.production.templateRepositoryId ===
      config.lab.templateRepositoryId &&
    config.production.starterVersion === config.lab.starterVersion &&
    config.production.starterCommitSha === config.lab.starterCommitSha &&
    config.production.starterTreeSha256 === config.lab.starterTreeSha256 &&
    config.production.privateKey === config.lab.privateKey;
}

function bytesFromBase64(value: string): Uint8Array {
  try {
    return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
  } catch {
    return fail("GITHUB_RUNTIME_RESPONSE_INVALID");
  }
}

function base64FromBytes(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function repository(value: unknown): GitHubRepositoryMetadata {
  if (
    !value || typeof value !== "object" ||
    !("repositoryId" in value) || !("nodeId" in value) ||
    !("owner" in value) || !("name" in value) || !("private" in value) ||
    !("defaultBranch" in value) || !("description" in value)
  ) return fail("GITHUB_RUNTIME_RESPONSE_INVALID");
  return value as GitHubRepositoryMetadata;
}

function sha(value: unknown): string {
  if (
    !value || typeof value !== "object" || !("sha" in value) ||
    typeof value.sha !== "string"
  ) return fail("GITHUB_RUNTIME_RESPONSE_INVALID");
  return value.sha;
}

function identity(
  metadata: GitHubRepositoryMetadata,
  installationId: string,
  expectedOwner = "lorenzo-web-solutions-lab",
): GitHubLabRepositoryIdentity {
  if (
    metadata.owner !== expectedOwner ||
    metadata.private !== true || metadata.defaultBranch !== "main"
  ) return fail("GITHUB_LAB_IDENTITY_INVALID");
  return Object.freeze({
    installationId,
    repositoryId: metadata.repositoryId,
    nodeId: metadata.nodeId,
    owner: metadata.owner,
    name: metadata.name,
    private: true as const,
    defaultBranch: "main" as const,
  });
}

function unknownCreateOutcome(error: unknown): boolean {
  return error instanceof GitHubHttpError && [
    "GITHUB_HTTP_TIMEOUT",
    "GITHUB_HTTP_NETWORK_ERROR",
    "GITHUB_HTTP_RESPONSE_INVALID",
    "GITHUB_HTTP_RESPONSE_TOO_LARGE",
    "GITHUB_HTTP_SERVER_ERROR",
    "GITHUB_HTTP_FAILED",
  ].includes(error.code);
}

export function createGitHubRepositoryProviderForRuntime(
  config: GitHubRepositoryRuntimeConfig,
  dependencies: GitHubRepositoryRuntimeDependencies,
): RepositoryProvisioningProviderV2 {
  if (
    !config || !validConfig(config) || !dependencies ||
    typeof dependencies.store !== "object" ||
    typeof dependencies.tokenBroker?.issue !== "function" ||
    typeof dependencies.http?.execute !== "function"
  ) return fail("GITHUB_RUNTIME_CONFIG_INVALID");

  return createGitHubTargetRepositoryProviderForRuntime(
    config.production,
    config.lab,
    dependencies,
  );
}

export function createGitHubTargetRepositoryProviderForRuntime(
  sourceConfig: GitHubAppConfig,
  targetConfig: GitHubAppConfig,
  dependencies: GitHubRepositoryRuntimeDependencies,
): RepositoryProvisioningProviderV2 {
  if (
    !sourceConfig || sourceConfig.target !== "PRODUCTION" ||
    !targetConfig || !dependencies ||
    sourceConfig.templateOwner !== sourceConfig.organization ||
    sourceConfig.templateName !== targetConfig.templateName ||
    sourceConfig.templateRepositoryId !== targetConfig.templateRepositoryId ||
    sourceConfig.starterVersion !== targetConfig.starterVersion ||
    sourceConfig.starterCommitSha !== targetConfig.starterCommitSha ||
    sourceConfig.starterTreeSha256 !== targetConfig.starterTreeSha256
  ) return fail("GITHUB_RUNTIME_CONFIG_INVALID");

  const createOperation = targetConfig.target === "PRODUCTION"
    ? "PRODUCTION_REPOSITORY_CREATE" as const
    : "LAB_REPOSITORY_CREATE" as const;
  const writeOperation = targetConfig.target === "PRODUCTION"
    ? "PRODUCTION_REPOSITORY_WRITE" as const
    : "LAB_REPOSITORY_WRITE" as const;
  const createDescriptionPrefix = targetConfig.target === "PRODUCTION"
    ? PRODUCTION_CREATE_DESCRIPTION_PREFIX
    : LAB_CREATE_DESCRIPTION_PREFIX;

  async function issue(
    appConfig: GitHubAppConfig,
    websiteWorkContextId: string,
    operation: GitHubTokenRequest["operation"],
    repositoryIds: readonly string[],
  ): Promise<string> {
    const request = Object.freeze({
      websiteWorkContextId,
      target: appConfig.target,
      organization: appConfig.organization,
      operation,
      repositoryIds: Object.freeze([...repositoryIds]),
    });
    const authority = Object.freeze({
      websiteWorkContextId,
      target: appConfig.target,
      organization: appConfig.organization,
      repositoryIds: request.repositoryIds,
    });
    return (await dependencies.tokenBroker.issue(
      appConfig,
      request,
      authority,
    )).token;
  }

  async function readEntries(
    owner: string,
    repositoryName: string,
    treeRef: string,
    token: string,
  ): Promise<readonly GitHubSnapshotEntry[]> {
    let tree: Readonly<{
      truncated: false;
      entries: readonly GitHubTreeEntry[];
    }>;
    try {
      tree = await dependencies.http.execute({
        kind: "REPOSITORY_TREE",
        owner,
        repository: repositoryName,
        treeRef,
        token,
      }) as typeof tree;
    } catch {
      return starterFail("STARTER_TREE_READ");
    }
    if (
      !tree || tree.truncated !== false || !Array.isArray(tree.entries) ||
      tree.entries.some((entry) =>
        !entry || typeof entry !== "object" ||
        !["blob", "tree"].includes(String(entry.type))
      )
    ) return starterFail("STARTER_TREE_VALIDATE");
    const entries: GitHubSnapshotEntry[] = [];
    for (const blob of tree.entries.filter((entry) => entry.type === "blob")) {
      let value: Readonly<{
        sha: string;
        encoding: "base64";
        contentBase64: string;
        size: number;
      }>;
      try {
        value = await dependencies.http.execute({
          kind: "READ_BLOB",
          owner,
          repository: repositoryName,
          blobSha: blob.sha,
          token,
        }) as typeof value;
      } catch {
        return starterFail("STARTER_BLOB_READ");
      }
      let content: Uint8Array;
      try {
        content = bytesFromBase64(value.contentBase64);
      } catch {
        return starterFail("STARTER_BLOB_VALIDATE");
      }
      if (value.encoding !== "base64" || value.sha !== blob.sha ||
        content.byteLength !== value.size) return starterFail("STARTER_BLOB_VALIDATE");
      entries.push(Object.freeze({
        path: blob.path,
        mode: blob.mode,
        type: "blob" as const,
        content,
      }));
    }
    return Object.freeze(entries);
  }

  async function readTargetRepository(input: Readonly<{
    websiteWorkContextId: string;
    organization: string;
    repository: string;
  }>): Promise<GitHubRepositoryMetadata> {
    const token = await issue(
      targetConfig,
      input.websiteWorkContextId,
      createOperation,
      [],
    );
    return repository(await dependencies.http.execute({
      kind: "REPOSITORY_METADATA",
      owner: input.organization,
      repository: input.repository,
      token,
    }));
  }

  const provider = createGitHubTargetRepositoryProvider({
    source: {
      installationId: sourceConfig.installationId,
      owner: sourceConfig.templateOwner,
      repository: sourceConfig.templateName,
      repositoryId: sourceConfig.templateRepositoryId,
      version: sourceConfig.starterVersion,
      commitSha: sourceConfig.starterCommitSha,
      treeSha256: sourceConfig.starterTreeSha256,
    },
    target: {
      providerTarget: targetConfig.target,
      installationId: targetConfig.installationId,
      organization: targetConfig.organization,
    },
  }, {
    async readStarter(input) {
      let token: string;
      try {
        token = await issue(
          sourceConfig,
          input.websiteWorkContextId,
          "STARTER_SNAPSHOT_READ",
          [input.repositoryId],
        );
      } catch (error) {
        return starterFail(
          "STARTER_TOKEN_ACQUIRE",
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
      let metadata: GitHubRepositoryMetadata;
      try {
        metadata = repository(
          await dependencies.http.execute({
            kind: "REPOSITORY_METADATA",
            owner: input.owner,
            repository: input.repository,
            token,
          }),
        );
      } catch {
        return starterFail("STARTER_METADATA_READ");
      }
      if (
        metadata.repositoryId !== input.repositoryId ||
        metadata.owner !== input.owner || metadata.name !== input.repository
      ) return starterFail("STARTER_IDENTITY_VALIDATE");
      return Object.freeze({
        installationId: input.installationId,
        repositoryId: metadata.repositoryId,
        owner: metadata.owner,
        repository: metadata.name,
        commitSha: input.commitSha,
        entries: await readEntries(
          input.owner,
          input.repository,
          input.commitSha,
          token,
        ),
      });
    },

    async createTarget(input) {
      let token: string;
      try {
        token = await issue(
          targetConfig,
          input.websiteWorkContextId,
          createOperation,
          [],
        );
      } catch (error) {
        throw new GitHubLabCreateDiagnosticError(
          "LAB_TOKEN_ACQUIRE",
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
      let result: GitHubHttpResult;
      try {
        result = await dependencies.http.execute({
          kind: "CREATE_REPOSITORY",
          owner: input.organization,
          repository: input.repository,
          description: `${createDescriptionPrefix}${input.operationId}`,
          token,
        });
      } catch (error) {
        if (error instanceof GitHubHttpError) {
          const subphase = hasValidatedGitHubHttpBoundary(error)
            ? LAB_CREATE_HTTP_SUBPHASES[error.boundary]
            : undefined;
          if (unknownCreateOutcome(error)) {
            throw new GitHubLabCreateOutcomeUnknownError(subphase);
          }
          if (subphase) throw new GitHubLabCreateDiagnosticError(subphase);
        }
        throw error;
      }
      try {
        return identity(
          repository(result),
          input.installationId,
          targetConfig.organization,
        );
      } catch {
        throw new GitHubLabCreateOutcomeUnknownError(
          "LAB_CREATE_ADAPTER_PROJECT",
        );
      }
    },

    async reconcileTarget(input) {
      try {
        const metadata = await readTargetRepository(input);
        if (
          metadata.name !== input.repository ||
          metadata.description !==
            `${createDescriptionPrefix}${input.operationId}`
        ) return Object.freeze({ state: "AMBIGUOUS" as const });
        return Object.freeze({
          state: "MATCH" as const,
          identity: identity(
            metadata,
            input.installationId,
            targetConfig.organization,
          ),
        });
      } catch {
        return Object.freeze({ state: "AMBIGUOUS" as const });
      }
    },

    quarantineTarget(input) {
      return dependencies.store.quarantine(input.operationId, input.reason)
        .then(() => undefined);
    },

    captureTargetIdentity(input) {
      return dependencies.store.captureLabIdentity({
        operationId: input.operationId,
        websiteWorkContextId: input.websiteWorkContextId,
        repositoryId: input.identity.repositoryId,
        nodeId: input.identity.nodeId,
      });
    },

    async writeTargetSnapshot(input) {
      let token: string;
      try {
        token = await issue(
          targetConfig,
          input.websiteWorkContextId,
          writeOperation,
          [input.identity.repositoryId],
        );
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_WRITE_TOKEN_ACQUIRE",
        );
      }
      const treeEntries: Array<
        Readonly<{
          path: string;
          mode: string;
          type: "blob";
          sha: string;
        }>
      > = [];
      for (const entry of input.entries) {
        let blobSha: string;
        try {
          blobSha = sha(
            await dependencies.http.execute({
              kind: "CREATE_BLOB",
              owner: input.identity.owner,
              repository: input.identity.name,
              contentBase64: base64FromBytes(entry.content),
              token,
            }),
          );
        } catch {
          throw new GitHubLabPostCreateDiagnosticError(
            "LAB_POST_CREATE_BLOB_WRITE",
          );
        }
        treeEntries.push(Object.freeze({
          path: entry.path,
          mode: entry.mode,
          type: "blob" as const,
          sha: blobSha,
        }));
      }
      let treeSha: string;
      try {
        treeSha = sha(
          await dependencies.http.execute({
            kind: "CREATE_TREE",
            owner: input.identity.owner,
            repository: input.identity.name,
            entries: Object.freeze(treeEntries),
            token,
          }),
        );
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_TREE_WRITE",
        );
      }
      let snapshotCommitSha: string;
      try {
        snapshotCommitSha = sha(
          await dependencies.http.execute({
            kind: "CREATE_COMMIT",
            owner: input.identity.owner,
            repository: input.identity.name,
            message: "chore: initialize approved starter snapshot",
            treeSha,
            token,
          }),
        );
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_COMMIT_WRITE",
        );
      }
      try {
        await dependencies.http.execute({
          kind: "CREATE_REF",
          owner: input.identity.owner,
          repository: input.identity.name,
          commitSha: snapshotCommitSha,
          token,
        });
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_REF_WRITE",
        );
      }
      let marker: Readonly<{ commitSha: string }>;
      try {
        marker = await dependencies.http.execute({
          kind: "WRITE_PROJECT_MARKER",
          owner: input.identity.owner,
          repository: input.identity.name,
          message: "chore: bind project context",
          contentBase64: base64FromBytes(
            new TextEncoder().encode(input.markerContent),
          ),
          token,
        }) as Readonly<{ commitSha: string }>;
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_MARKER_WRITE",
        );
      }
      return Object.freeze({
        snapshotCommitSha,
        markerCommitSha: marker.commitSha,
      });
    },

    async readTargetBinding(input) {
      let token: string;
      try {
        token = await issue(
          targetConfig,
          input.websiteWorkContextId,
          writeOperation,
          [input.identity.repositoryId],
        );
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
        );
      }
      let metadata: GitHubRepositoryMetadata;
      try {
        metadata = repository(
          await dependencies.http.execute({
            kind: "REPOSITORY_METADATA",
            owner: input.identity.owner,
            repository: input.identity.name,
            token,
          }),
        );
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_METADATA_READ",
        );
      }
      let entries: readonly GitHubSnapshotEntry[];
      try {
        entries = await readEntries(
          input.identity.owner,
          input.identity.name,
          input.snapshotCommitSha,
          token,
        );
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
        );
      }
      let marker: Readonly<{ contentBase64: string }>;
      try {
        marker = await dependencies.http.execute({
          kind: "READ_PROJECT_MARKER",
          owner: input.identity.owner,
          repository: input.identity.name,
          ref: input.markerCommitSha,
          token,
        }) as Readonly<{ contentBase64: string }>;
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_MARKER_READBACK",
        );
      }
      let sourceTreeSha256: string;
      let markerContent: string;
      try {
        sourceTreeSha256 = await computeSnapshotDigest(entries);
        markerContent = new TextDecoder().decode(
          bytesFromBase64(marker.contentBase64),
        );
      } catch {
        throw new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_PROVENANCE_VALIDATE",
        );
      }
      return Object.freeze({
        ...identity(metadata, input.installationId, targetConfig.organization),
        sourceTreeSha256,
        markerContent,
        markerCommitSha: input.markerCommitSha,
      });
    },
  });

  return provider;
}

export function createGitHubRepositoryRuntimeFromProvider(
  provider: RepositoryProvisioningProviderV2,
  store: RepositoryProvisioningRuntimeStoreV2,
): Readonly<{
  provision(
    command: RepositoryProvisioningCommandV2,
  ): Promise<RepositoryProvisioningResultV2>;
}> {
  if (!provider || typeof provider.provision !== "function" || !store) {
    return fail("GITHUB_RUNTIME_CONFIG_INVALID");
  }
  const service = new RepositoryProvisioningServiceV2(provider, store);
  return Object.freeze({
    provision: (command: RepositoryProvisioningCommandV2) =>
      service.provision(command),
  });
}

export function createGitHubRepositoryRuntime(
  config: GitHubRepositoryRuntimeConfig,
  dependencies: GitHubRepositoryRuntimeDependencies,
) {
  return createGitHubRepositoryRuntimeFromProvider(
    createGitHubRepositoryProviderForRuntime(config, dependencies),
    dependencies.store,
  );
}

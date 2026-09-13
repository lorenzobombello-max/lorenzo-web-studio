const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UUID_V2 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const GITHUB_SEGMENT = /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,98}[A-Za-z0-9])?$/;
const PROVIDER_REPOSITORY_ID = /^[1-9][0-9]{0,29}$/;
const PROVIDER_NODE_ID = /^[A-Za-z0-9_-]{6,128}$/;
const GIT_OBJECT_ID = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SEMANTIC_VERSION =
  /^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

export type RepositoryProvisioningCommand = Readonly<{
  websiteWorkspaceId: string;
  websiteWorkContextId: string;
  idempotencyKey: string;
  repositoryName: string;
}>;

export type RepositoryProvisioningRequest = Readonly<{
  idempotencyKey: string;
  repositoryName: string;
  visibility: "PRIVATE";
  defaultBranch: "main";
  bootstrap: "NONE";
}>;

export type RepositoryBinding = Readonly<{
  provider: "GITHUB";
  providerRepositoryId: string;
  owner: string;
  name: string;
  visibility: "PRIVATE";
  defaultBranch: "main";
}>;

export type RepositoryProvisioningClaim =
  | Readonly<{ state: "CLAIMED"; operationId: string }>
  | Readonly<{ state: "REPLAY"; binding: RepositoryBinding }>
  | Readonly<{ state: "IN_PROGRESS" }>;

export interface RepositoryProvisioningProvider {
  provision(request: RepositoryProvisioningRequest): Promise<RepositoryBinding>;
}

export interface RepositoryProvisioningStore {
  claim(
    command: RepositoryProvisioningCommand,
  ): Promise<RepositoryProvisioningClaim>;
  bind(
    operationId: string,
    expected: Readonly<{
      websiteWorkspaceId: string;
      websiteWorkContextId: string;
    }>,
    binding: RepositoryBinding,
  ): Promise<RepositoryBinding>;
  fail(operationId: string, code: string): Promise<void>;
}

export type RepositoryProvisioningResult =
  & RepositoryBinding
  & Readonly<{ replayed: boolean }>;

export type RepositoryStarterProvenance = Readonly<{
  source: string;
  version: string;
  commitSha: string;
  templateRepositoryId: string;
}>;

export type RepositoryProvisioningCommandV2 = Readonly<{
  contractVersion: 2;
  websiteWorkspaceId: string;
  websiteWorkContextId: string;
  idempotencyKey: string;
  starter: RepositoryStarterProvenance;
}>;

export type RepositoryProvisioningAuthorityV2 =
  & RepositoryProvisioningCommandV2
  & Readonly<{ repositoryName: string }>;

export type RepositoryProvisioningRequestV2 = Readonly<{
  contractVersion: 2;
  operationId: string;
  websiteWorkContextId: string;
  repositoryName: string;
  visibility: "PRIVATE";
  defaultBranch: "main";
  bootstrap: "GITHUB_TEMPLATE";
  starter: RepositoryStarterProvenance;
}>;

export type VerifiedRepositoryBindingV2 = Readonly<{
  provider: "GITHUB";
  providerRepositoryId: string;
  providerNodeId: string;
  owner: string;
  name: string;
  visibility: "PRIVATE";
  defaultBranch: "main";
  starterSource: string;
  starterVersion: string;
  starterCommitSha: string;
  repositoryMarkerCommitSha: string;
}>;

export type RepositoryProvisioningClaimV2 =
  | Readonly<{ state: "CLAIMED"; operationId: string }>
  | Readonly<{ state: "REPLAY"; binding: VerifiedRepositoryBindingV2 }>
  | Readonly<{ state: "IN_PROGRESS" }>;

export interface RepositoryProvisioningProviderV2 {
  provision(
    request: RepositoryProvisioningRequestV2,
  ): Promise<VerifiedRepositoryBindingV2>;
}

export interface RepositoryProvisioningStoreV2 {
  claim(
    authority: RepositoryProvisioningAuthorityV2,
  ): Promise<RepositoryProvisioningClaimV2>;
  bind(
    operationId: string,
    expected: Readonly<{
      websiteWorkspaceId: string;
      websiteWorkContextId: string;
    }>,
    binding: VerifiedRepositoryBindingV2,
  ): Promise<VerifiedRepositoryBindingV2>;
  fail(operationId: string, code: string): Promise<void>;
}

export type RepositoryProvisioningResultV2 =
  & VerifiedRepositoryBindingV2
  & Readonly<{ replayed: boolean }>;

function hasExactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => key in value);
}

export function repositoryNameForContext(websiteWorkContextId: string): string {
  if (!UUID_V2.test(websiteWorkContextId)) {
    throw new Error("INVALID_WEBSITE_WORK_CONTEXT_ID");
  }
  return `lws-web-${websiteWorkContextId.toLowerCase().replaceAll("-", "")}`;
}

function validStarter(
  value: unknown,
): value is RepositoryStarterProvenance {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const starter = value as Record<string, unknown>;
  const source = String(starter.source || "");
  const [owner, repository, ...extra] = source.split("/");
  return hasExactKeys(starter, [
    "source",
    "version",
    "commitSha",
    "templateRepositoryId",
  ]) && extra.length === 0 && GITHUB_SEGMENT.test(owner || "") &&
    GITHUB_SEGMENT.test(repository || "") &&
    SEMANTIC_VERSION.test(String(starter.version || "")) &&
    GIT_OBJECT_ID.test(String(starter.commitSha || "")) &&
    PROVIDER_REPOSITORY_ID.test(String(starter.templateRepositoryId || ""));
}

function validCommandV2(
  value: unknown,
): value is RepositoryProvisioningCommandV2 {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const command = value as Record<string, unknown>;
  return hasExactKeys(command, [
    "contractVersion",
    "websiteWorkspaceId",
    "websiteWorkContextId",
    "idempotencyKey",
    "starter",
  ]) && command.contractVersion === 2 &&
    UUID_V2.test(String(command.websiteWorkspaceId || "")) &&
    UUID_V2.test(String(command.websiteWorkContextId || "")) &&
    UUID_V2.test(String(command.idempotencyKey || "")) &&
    validStarter(command.starter);
}

function validBindingV2(
  value: unknown,
  expectedName: string,
  expectedStarter: RepositoryStarterProvenance,
): value is VerifiedRepositoryBindingV2 {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const binding = value as Record<string, unknown>;
  return hasExactKeys(binding, [
    "provider",
    "providerRepositoryId",
    "providerNodeId",
    "owner",
    "name",
    "visibility",
    "defaultBranch",
    "starterSource",
    "starterVersion",
    "starterCommitSha",
    "repositoryMarkerCommitSha",
  ]) && binding.provider === "GITHUB" &&
    PROVIDER_REPOSITORY_ID.test(String(binding.providerRepositoryId || "")) &&
    PROVIDER_NODE_ID.test(String(binding.providerNodeId || "")) &&
    GITHUB_SEGMENT.test(String(binding.owner || "")) &&
    binding.name === expectedName && binding.visibility === "PRIVATE" &&
    binding.defaultBranch === "main" &&
    binding.starterSource === expectedStarter.source &&
    binding.starterVersion === expectedStarter.version &&
    binding.starterCommitSha === expectedStarter.commitSha &&
    GIT_OBJECT_ID.test(String(binding.repositoryMarkerCommitSha || ""));
}

function sameBindingV2(
  left: VerifiedRepositoryBindingV2,
  right: VerifiedRepositoryBindingV2,
): boolean {
  return Object.keys(left).every((key) =>
    left[key as keyof VerifiedRepositoryBindingV2] ===
      right[key as keyof VerifiedRepositoryBindingV2]
  );
}

function validCommand(value: unknown): value is RepositoryProvisioningCommand {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const command = value as Record<string, unknown>;
  return hasExactKeys(command, [
    "websiteWorkspaceId",
    "websiteWorkContextId",
    "idempotencyKey",
    "repositoryName",
  ]) && UUID.test(String(command.websiteWorkspaceId || "")) &&
    UUID.test(String(command.websiteWorkContextId || "")) &&
    UUID.test(String(command.idempotencyKey || "")) &&
    GITHUB_SEGMENT.test(String(command.repositoryName || ""));
}

function validBinding(
  value: unknown,
  expectedName: string,
): value is RepositoryBinding {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const binding = value as Record<string, unknown>;
  return hasExactKeys(binding, [
    "provider",
    "providerRepositoryId",
    "owner",
    "name",
    "visibility",
    "defaultBranch",
  ]) && binding.provider === "GITHUB" &&
    PROVIDER_REPOSITORY_ID.test(String(binding.providerRepositoryId || "")) &&
    GITHUB_SEGMENT.test(String(binding.owner || "")) &&
    binding.name === expectedName &&
    binding.visibility === "PRIVATE" && binding.defaultBranch === "main";
}

function sameBinding(
  left: RepositoryBinding,
  right: RepositoryBinding,
): boolean {
  return left.provider === right.provider &&
    left.providerRepositoryId === right.providerRepositoryId &&
    left.owner === right.owner && left.name === right.name &&
    left.visibility === right.visibility &&
    left.defaultBranch === right.defaultBranch;
}

async function recordFailure(
  store: RepositoryProvisioningStore,
  operationId: string,
  code: string,
): Promise<void> {
  try {
    await store.fail(operationId, code);
  } catch {
  }
}

export class RepositoryProvisioningService {
  constructor(
    private readonly provider: RepositoryProvisioningProvider,
    private readonly store: RepositoryProvisioningStore,
  ) {}

  async provision(
    command: RepositoryProvisioningCommand,
  ): Promise<RepositoryProvisioningResult> {
    if (!validCommand(command)) {
      throw new Error("INVALID_REPOSITORY_PROVISIONING_COMMAND");
    }

    let claim: RepositoryProvisioningClaim;
    try {
      claim = await this.store.claim(command);
    } catch {
      throw new Error("REPOSITORY_PROVISIONING_CLAIM_FAILED");
    }
    if (
      !claim || typeof claim !== "object" || Array.isArray(claim) ||
      !Object.hasOwn(claim, "state")
    ) {
      throw new Error("INVALID_REPOSITORY_PROVISIONING_CLAIM");
    }
    if (claim.state === "IN_PROGRESS") {
      if (!hasExactKeys(claim, ["state"])) {
        throw new Error("INVALID_REPOSITORY_PROVISIONING_CLAIM");
      }
      throw new Error("REPOSITORY_PROVISIONING_IN_PROGRESS");
    }
    if (claim.state === "REPLAY") {
      if (
        !hasExactKeys(claim, ["state", "binding"]) ||
        !validBinding(claim.binding, command.repositoryName)
      ) {
        throw new Error("INVALID_REPOSITORY_BINDING");
      }
      return Object.freeze({ ...claim.binding, replayed: true });
    }
    if (
      claim.state !== "CLAIMED" ||
      !hasExactKeys(claim, ["state", "operationId"]) ||
      !UUID.test(claim.operationId)
    ) {
      throw new Error("INVALID_REPOSITORY_PROVISIONING_CLAIM");
    }

    let provisioned: RepositoryBinding;
    try {
      provisioned = await this.provider.provision(Object.freeze({
        idempotencyKey: command.idempotencyKey,
        repositoryName: command.repositoryName,
        visibility: "PRIVATE",
        defaultBranch: "main",
        bootstrap: "NONE",
      }));
    } catch {
      await recordFailure(
        this.store,
        claim.operationId,
        "REPOSITORY_PROVIDER_FAILED",
      );
      throw new Error("REPOSITORY_PROVIDER_FAILED");
    }

    if (!validBinding(provisioned, command.repositoryName)) {
      await recordFailure(
        this.store,
        claim.operationId,
        "INVALID_REPOSITORY_PROVIDER_RESULT",
      );
      throw new Error("INVALID_REPOSITORY_PROVIDER_RESULT");
    }

    let bound: RepositoryBinding;
    try {
      bound = await this.store.bind(
        claim.operationId,
        Object.freeze({
          websiteWorkspaceId: command.websiteWorkspaceId,
          websiteWorkContextId: command.websiteWorkContextId,
        }),
        provisioned,
      );
    } catch {
      await recordFailure(
        this.store,
        claim.operationId,
        "REPOSITORY_BINDING_FAILED",
      );
      throw new Error("REPOSITORY_BINDING_FAILED");
    }
    if (
      !validBinding(bound, command.repositoryName) ||
      !sameBinding(bound, provisioned)
    ) {
      await recordFailure(
        this.store,
        claim.operationId,
        "INVALID_REPOSITORY_BINDING",
      );
      throw new Error("INVALID_REPOSITORY_BINDING");
    }

    return Object.freeze({ ...bound, replayed: false });
  }
}

export class RepositoryProvisioningServiceV2 {
  constructor(
    private readonly provider: RepositoryProvisioningProviderV2,
    private readonly store: RepositoryProvisioningStoreV2,
  ) {}

  async provision(
    command: RepositoryProvisioningCommandV2,
  ): Promise<RepositoryProvisioningResultV2> {
    if (!validCommandV2(command)) {
      throw new Error("INVALID_REPOSITORY_PROVISIONING_COMMAND_V2");
    }
    const repositoryName = repositoryNameForContext(
      command.websiteWorkContextId,
    );
    const authority = Object.freeze({ ...command, repositoryName });

    let claim: RepositoryProvisioningClaimV2;
    try {
      claim = await this.store.claim(authority);
    } catch {
      throw new Error("REPOSITORY_PROVISIONING_CLAIM_FAILED");
    }
    if (!claim || typeof claim !== "object" || Array.isArray(claim)) {
      throw new Error("INVALID_REPOSITORY_PROVISIONING_CLAIM");
    }
    if (claim.state === "IN_PROGRESS") {
      if (!hasExactKeys(claim, ["state"])) {
        throw new Error("INVALID_REPOSITORY_PROVISIONING_CLAIM");
      }
      throw new Error("REPOSITORY_PROVISIONING_IN_PROGRESS");
    }
    if (claim.state === "REPLAY") {
      if (
        !hasExactKeys(claim, ["state", "binding"]) ||
        !validBindingV2(claim.binding, repositoryName, command.starter)
      ) {
        throw new Error("INVALID_REPOSITORY_BINDING_V2");
      }
      return Object.freeze({ ...claim.binding, replayed: true });
    }
    if (
      claim.state !== "CLAIMED" ||
      !hasExactKeys(claim, ["state", "operationId"]) ||
      !UUID_V2.test(claim.operationId)
    ) {
      throw new Error("INVALID_REPOSITORY_PROVISIONING_CLAIM");
    }

    let provisioned: VerifiedRepositoryBindingV2;
    try {
      provisioned = await this.provider.provision(Object.freeze({
        contractVersion: 2,
        operationId: claim.operationId,
        websiteWorkContextId: command.websiteWorkContextId,
        repositoryName,
        visibility: "PRIVATE",
        defaultBranch: "main",
        bootstrap: "GITHUB_TEMPLATE",
        starter: command.starter,
      }));
    } catch {
      await recordFailure(
        this.store,
        claim.operationId,
        "REPOSITORY_PROVIDER_FAILED",
      );
      throw new Error("REPOSITORY_PROVIDER_FAILED");
    }
    if (!validBindingV2(provisioned, repositoryName, command.starter)) {
      await recordFailure(
        this.store,
        claim.operationId,
        "INVALID_REPOSITORY_PROVIDER_RESULT_V2",
      );
      throw new Error("INVALID_REPOSITORY_PROVIDER_RESULT_V2");
    }

    let bound: VerifiedRepositoryBindingV2;
    try {
      bound = await this.store.bind(
        claim.operationId,
        Object.freeze({
          websiteWorkspaceId: command.websiteWorkspaceId,
          websiteWorkContextId: command.websiteWorkContextId,
        }),
        provisioned,
      );
    } catch {
      await recordFailure(
        this.store,
        claim.operationId,
        "REPOSITORY_BINDING_FAILED",
      );
      throw new Error("REPOSITORY_BINDING_FAILED");
    }
    if (
      !validBindingV2(bound, repositoryName, command.starter) ||
      !sameBindingV2(bound, provisioned)
    ) {
      await recordFailure(
        this.store,
        claim.operationId,
        "INVALID_REPOSITORY_BINDING_V2",
      );
      throw new Error("INVALID_REPOSITORY_BINDING_V2");
    }
    return Object.freeze({ ...bound, replayed: false });
  }
}

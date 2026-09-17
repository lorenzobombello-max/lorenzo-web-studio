import type {
  GitHubRepositoryCompletionProof,
  GitHubRepositoryStateInspectionAuthority,
} from "../_shared/github-repository-state-inspector.ts";
import type {
  RepositoryProvisioningResultV2,
  VerifiedRepositoryBindingV2,
} from "../_shared/repository-provisioning.ts";
import { TASK13_SYNTHETIC_AUTHORITY } from "./readonly-reconciliation.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const NODE_ID = /^[A-Za-z0-9_-]{6,255}$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SHA256 = /^[0-9a-f]{64}$/;
const AUTHORITY_KEYS = [
  "operation_found",
  "operation_id",
  "website_work_context_id",
  "website_workspace_id",
  "operation_state",
  "failure_code",
  "external_created_at_present",
  "repository_external_id",
  "target_owner",
  "target_repository_name",
  "bound_at_present",
  "quarantine_present",
  "customer_binding_present",
  "dossier_binding_present",
  "repository_binding_present",
] as const;

export type Task13PostRecoveryFinalizationInput = Readonly<{
  operationId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
}>;

type Config = Readonly<{
  actorAuthUserId: string;
  actorAal: "aal2";
  starterSource: string;
  starterVersion: string;
  starterCommitSha: string;
  starterTreeSha256: string;
  markerContent: string;
}>;

type Completion = Readonly<{
  state: "ALREADY_COMPLETE";
  proof: GitHubRepositoryCompletionProof;
}>;

type Dependencies = Readonly<{
  readAuthority(input: Task13PostRecoveryFinalizationInput): Promise<unknown>;
  inspectCompletion(
    authority: GitHubRepositoryStateInspectionAuthority,
  ): Promise<Completion>;
  finalize(
    operationId: string,
    expected: Readonly<{
      websiteWorkspaceId: string;
      websiteWorkContextId: string;
    }>,
    binding: VerifiedRepositoryBindingV2,
    actor: Readonly<{ authUserId: string; aal: "aal2" }>,
  ): Promise<VerifiedRepositoryBindingV2>;
}>;

function fail(): never {
  throw new Error("TASK13_POST_RECOVERY_FINALIZATION_FAILED");
}

function exactRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail();
  const prototype = Object.getPrototypeOf(value);
  const keys = Reflect.ownKeys(value).sort();
  const expected = [...AUTHORITY_KEYS].sort();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (
    prototype !== Object.prototype && prototype !== null ||
    keys.length !== expected.length ||
    !keys.every((key, index) => key === expected[index]) ||
    !AUTHORITY_KEYS.every((key) =>
      descriptors[key]?.enumerable === true &&
      Object.hasOwn(descriptors[key], "value")
    )
  ) fail();
  return Object.fromEntries(
    AUTHORITY_KEYS.map((key) => [key, descriptors[key].value]),
  );
}

export function createTask13PostRecoveryFinalizer(
  config: Config,
  dependencies: Dependencies,
) {
  if (
    !config || !UUID.test(config.actorAuthUserId) ||
    config.actorAal !== "aal2" || !SHA.test(config.starterCommitSha) ||
    !SHA256.test(config.starterTreeSha256) ||
    typeof config.markerContent !== "string" || !config.markerContent ||
    !dependencies || typeof dependencies.readAuthority !== "function" ||
    typeof dependencies.inspectCompletion !== "function" ||
    typeof dependencies.finalize !== "function"
  ) fail();

  return async (
    input: Task13PostRecoveryFinalizationInput,
  ): Promise<RepositoryProvisioningResultV2> => {
    if (
      !input || !UUID.test(input.operationId) ||
      input.websiteWorkContextId !==
        TASK13_SYNTHETIC_AUTHORITY.websiteWorkContextId ||
      input.websiteWorkspaceId !==
        TASK13_SYNTHETIC_AUTHORITY.websiteWorkspaceId
    ) fail();
    const authority = exactRecord(await dependencies.readAuthority(input));
    const replayed = authority.operation_state === "BOUND";
    if (
      authority.operation_found !== true ||
      authority.operation_id !== input.operationId ||
      authority.website_work_context_id !== input.websiteWorkContextId ||
      authority.website_workspace_id !== input.websiteWorkspaceId ||
      authority.external_created_at_present !== true ||
      typeof authority.repository_external_id !== "string" ||
      !NUMERIC_ID.test(authority.repository_external_id) ||
      authority.target_owner !== TASK13_SYNTHETIC_AUTHORITY.organization ||
      authority.target_repository_name !==
        TASK13_SYNTHETIC_AUTHORITY.repository ||
      authority.quarantine_present !== false ||
      authority.customer_binding_present !== false ||
      authority.dossier_binding_present !== false ||
      (!replayed && (
        authority.operation_state !== "TERMINAL_FAILED" ||
        authority.failure_code !== "REPOSITORY_PROVIDER_FAILED" ||
        authority.bound_at_present !== false ||
        authority.repository_binding_present !== false
      )) ||
      (replayed && (
        authority.failure_code !== null ||
        authority.bound_at_present !== true ||
        authority.repository_binding_present !== true
      ))
    ) fail();

    const inspected = await dependencies.inspectCompletion(Object.freeze({
      websiteWorkContextId: input.websiteWorkContextId,
      repositoryId: authority.repository_external_id,
      owner: TASK13_SYNTHETIC_AUTHORITY.organization,
      repository: TASK13_SYNTHETIC_AUTHORITY.repository,
      private: true,
      defaultBranch: "main",
      snapshotTreeSha256: config.starterTreeSha256,
      markerContent: config.markerContent,
    }));
    if (
      !inspected || inspected.state !== "ALREADY_COMPLETE" ||
      !inspected.proof ||
      inspected.proof.providerRepositoryId !==
        authority.repository_external_id ||
      !NODE_ID.test(inspected.proof.providerNodeId) ||
      inspected.proof.owner !== TASK13_SYNTHETIC_AUTHORITY.organization ||
      inspected.proof.name !== TASK13_SYNTHETIC_AUTHORITY.repository ||
      inspected.proof.visibility !== "PRIVATE" ||
      inspected.proof.defaultBranch !== "main" ||
      !SHA.test(inspected.proof.repositoryMarkerCommitSha)
    ) fail();
    const binding = Object.freeze({
      provider: "GITHUB" as const,
      ...inspected.proof,
      starterSource: config.starterSource,
      starterVersion: config.starterVersion,
      starterCommitSha: config.starterCommitSha,
    });
    const finalized = await dependencies.finalize(
      input.operationId,
      Object.freeze({
        websiteWorkspaceId: input.websiteWorkspaceId,
        websiteWorkContextId: input.websiteWorkContextId,
      }),
      binding,
      Object.freeze({
        authUserId: config.actorAuthUserId,
        aal: config.actorAal,
      }),
    );
    return Object.freeze({ ...finalized, replayed });
  };
}

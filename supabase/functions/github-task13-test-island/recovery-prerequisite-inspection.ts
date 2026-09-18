import type { GitHubTask13RuntimeConfig } from "../_shared/github-app-config.ts";
import type {
  GitHubRepositoryStateClassification,
  GitHubRepositoryStateInspectionAuthority,
} from "../_shared/github-repository-state-inspector.ts";
import {
  getValidatedGitHubRepositoryRefReadDiagnostic,
  hasValidatedGitHubRepositoryStateInspectionSubphase,
} from "../_shared/github-repository-state-inspector.ts";
import {
  getValidatedGitHubLabPostCreateRefReadDiagnostic,
  GitHubLabPostCreateDiagnosticError,
  hasValidatedGitHubLabPostCreateDiagnosticError,
} from "../_shared/repository-provisioning-diagnostics.ts";
import type { GitHubRefReadDiagnostic } from "../_shared/github-ref-read-diagnostic.ts";
import { TASK13_SYNTHETIC_AUTHORITY } from "./readonly-reconciliation.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const CLASSIFICATIONS: readonly GitHubRepositoryStateClassification[] = [
  "EMPTY_OR_UNINITIALIZED",
  "ALREADY_COMPLETE",
  "MARKER_MISSING",
  "CONFLICT",
];
export const TASK13_RECOVERY_INSPECTION_FAILURE_PHASES = Object.freeze(
  [
    "RECOVERY_AUTHORITY",
    "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
    "LAB_POST_CREATE_METADATA_READ",
    "LAB_POST_CREATE_SNAPSHOT_READBACK",
    "LAB_POST_CREATE_MARKER_READBACK",
    "LAB_POST_CREATE_PROVENANCE_VALIDATE",
    "UNKNOWN",
  ] as const,
);

export type Task13RecoveryInspectionFailurePhase =
  (typeof TASK13_RECOVERY_INSPECTION_FAILURE_PHASES)[number];
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

type Input = Readonly<{
  operationId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
}>;

type RpcClient = Readonly<{
  rpc(
    name: "get_task13_repository_recovery_authority_v1",
    parameters: Readonly<{
      p_operation_id: string;
      p_website_work_context_id: string;
      p_website_workspace_id: string;
    }>,
  ): PromiseLike<Readonly<{ data: unknown; error: unknown }>>;
}>;

export type Task13RecoveryPrerequisiteInspectionResult = Readonly<{
  authority_valid: true;
  repository_identity_valid: true;
  state_classification: GitHubRepositoryStateClassification;
}>;

export type Task13RecoveryAuthorityInspectionResult = Readonly<{
  state: GitHubRepositoryStateClassification;
  authority: Readonly<{
    operationId: string;
    websiteWorkContextId: string;
    websiteWorkspaceId: string;
    repositoryId: string;
    owner: string;
    repository: string;
    installationId: string;
    starterSource: string;
    starterVersion: string;
    starterCommitSha: string;
    starterTreeSha256: string;
    markerContent: string;
  }>;
}>;

export class Task13RecoveryPrerequisiteInspectionError extends Error {
  readonly code = "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED";

  constructor() {
    super("TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED");
    this.name = "Task13RecoveryPrerequisiteInspectionError";
  }
}

export function getValidatedTask13RefReadDiagnostic(
  value: unknown,
): GitHubRefReadDiagnostic {
  return getValidatedGitHubLabPostCreateRefReadDiagnostic(value);
}

const recoveryAuthorityDiagnostics = new WeakSet<object>();

export class Task13RecoveryAuthorityDiagnosticError extends Error {
  readonly failedInspectionPhase = "RECOVERY_AUTHORITY" as const;

  constructor() {
    super("TASK13_RECOVERY_AUTHORITY_FAILED");
    this.name = "Task13RecoveryAuthorityDiagnosticError";
    Object.defineProperty(this, "failedInspectionPhase", {
      value: "RECOVERY_AUTHORITY",
      enumerable: true,
      writable: false,
      configurable: false,
    });
    recoveryAuthorityDiagnostics.add(this);
  }
}

export function hasValidatedTask13RecoveryAuthorityDiagnostic(
  value: unknown,
): value is Task13RecoveryAuthorityDiagnosticError {
  return typeof value === "object" && value !== null &&
    recoveryAuthorityDiagnostics.has(value);
}

type Dependencies = Readonly<{
  rpc: RpcClient["rpc"];
  inspectRepository(
    authority: GitHubRepositoryStateInspectionAuthority,
  ): Promise<Readonly<{ state: GitHubRepositoryStateClassification }>>;
}>;

function fail(): never {
  throw new Task13RecoveryPrerequisiteInspectionError();
}

function authorityFail(): never {
  throw new Task13RecoveryAuthorityDiagnosticError();
}

function exactRecord(
  value: unknown,
  expectedKeys: readonly string[] = AUTHORITY_KEYS,
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail();
  const prototype = Object.getPrototypeOf(value);
  const keys = Reflect.ownKeys(value).sort();
  const expected = [...expectedKeys].sort();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (
    prototype !== Object.prototype && prototype !== null ||
    keys.length !== expected.length ||
    !keys.every((key, index) => key === expected[index]) ||
    !expectedKeys.every((key) =>
      descriptors[key]?.enumerable === true &&
      Object.hasOwn(descriptors[key], "value")
    )
  ) fail();
  return Object.fromEntries(
    expectedKeys.map((key) => [key, descriptors[key].value]),
  );
}

function markerContent(
  config: GitHubTask13RuntimeConfig,
  input: Input,
): string {
  return `${
    JSON.stringify(
      {
        schema_version: 1,
        environment: "TEST",
        organization: config.lab.organization,
        website_work_context_id: input.websiteWorkContextId,
        repository_provisioning_operation_id: input.operationId,
        starter_source:
          `${config.production.templateOwner}/${config.production.templateName}`,
        starter_version: `v${config.lab.starterVersion}`,
        starter_commit_sha: config.lab.starterCommitSha,
        starter_tree_sha256: config.lab.starterTreeSha256,
      },
      null,
      2,
    )
  }\n`;
}

export function createTask13RecoveryAuthorityInspection(
  config: GitHubTask13RuntimeConfig,
  dependencies: Dependencies,
) {
  if (
    !config || config.lab.target !== "TEST" ||
    config.lab.organization !== TASK13_SYNTHETIC_AUTHORITY.organization ||
    config.lab.installationId !== TASK13_SYNTHETIC_AUTHORITY.installationId ||
    config.production?.templateOwner !== "lorenzo-web-solutions" ||
    config.production.templateName !== "lws-website-starter" ||
    !dependencies || typeof dependencies.rpc !== "function" ||
    typeof dependencies.inspectRepository !== "function"
  ) fail();

  return async (
    input: Input,
  ): Promise<Task13RecoveryAuthorityInspectionResult> => {
    if (
      !input || !UUID.test(input.operationId) ||
      input.websiteWorkContextId !==
        TASK13_SYNTHETIC_AUTHORITY.websiteWorkContextId ||
      input.websiteWorkspaceId !== TASK13_SYNTHETIC_AUTHORITY.websiteWorkspaceId
    ) fail();
    let authority: Record<string, unknown>;
    try {
      const rpcResult = await dependencies.rpc(
        "get_task13_repository_recovery_authority_v1",
        Object.freeze({
          p_operation_id: input.operationId,
          p_website_work_context_id: input.websiteWorkContextId,
          p_website_workspace_id: input.websiteWorkspaceId,
        }),
      );
      if (!rpcResult || rpcResult.error) authorityFail();
      authority = exactRecord(rpcResult.data);
    } catch {
      return authorityFail();
    }
    if (
      authority.operation_found !== true ||
      authority.operation_id !== input.operationId ||
      authority.website_work_context_id !== input.websiteWorkContextId ||
      authority.website_workspace_id !== input.websiteWorkspaceId ||
      authority.operation_state !== "TERMINAL_FAILED" ||
      authority.failure_code !== "REPOSITORY_PROVIDER_FAILED" ||
      authority.external_created_at_present !== true ||
      typeof authority.repository_external_id !== "string" ||
      !NUMERIC_ID.test(authority.repository_external_id) ||
      authority.target_owner !== TASK13_SYNTHETIC_AUTHORITY.organization ||
      authority.target_repository_name !==
        TASK13_SYNTHETIC_AUTHORITY.repository ||
      authority.bound_at_present !== false ||
      authority.quarantine_present !== false ||
      authority.customer_binding_present !== false ||
      authority.dossier_binding_present !== false ||
      authority.repository_binding_present !== false
    ) fail();

    const recoveryAuthority = Object.freeze({
      operationId: input.operationId,
      websiteWorkContextId: input.websiteWorkContextId,
      websiteWorkspaceId: input.websiteWorkspaceId,
      repositoryId: authority.repository_external_id,
      owner: TASK13_SYNTHETIC_AUTHORITY.organization,
      repository: TASK13_SYNTHETIC_AUTHORITY.repository,
      installationId: config.lab.installationId,
      starterSource:
        `${config.production.templateOwner}/${config.production.templateName}`,
      starterVersion: config.lab.starterVersion,
      starterCommitSha: config.lab.starterCommitSha,
      starterTreeSha256: config.lab.starterTreeSha256,
      markerContent: markerContent(config, input),
    });
    const repositoryAuthority = Object.freeze({
      websiteWorkContextId: input.websiteWorkContextId,
      repositoryId: recoveryAuthority.repositoryId,
      owner: TASK13_SYNTHETIC_AUTHORITY.organization,
      repository: TASK13_SYNTHETIC_AUTHORITY.repository,
      private: true as const,
      defaultBranch: "main" as const,
      snapshotTreeSha256: config.lab.starterTreeSha256,
      markerContent: recoveryAuthority.markerContent,
    });
    let inspected: Readonly<{ state: GitHubRepositoryStateClassification }>;
    try {
      inspected = await dependencies.inspectRepository(repositoryAuthority);
    } catch (error) {
      if (hasValidatedGitHubLabPostCreateDiagnosticError(error)) throw error;
      if (hasValidatedGitHubRepositoryStateInspectionSubphase(error)) {
        throw new GitHubLabPostCreateDiagnosticError(
          error.postCreateSubphase,
          error.snapshotReadbackCheck,
          getValidatedGitHubRepositoryRefReadDiagnostic(error),
        );
      }
      return fail();
    }
    const inspectedRecord = exactRecord(inspected, ["state"]);
    const state = inspectedRecord.state;
    if (
      !CLASSIFICATIONS.includes(
        state as GitHubRepositoryStateClassification,
      )
    ) fail();
    return Object.freeze({
      state: state as GitHubRepositoryStateClassification,
      authority: recoveryAuthority,
    });
  };
}

export function createTask13RecoveryPrerequisiteInspection(
  config: GitHubTask13RuntimeConfig,
  dependencies: Dependencies,
) {
  const inspect = createTask13RecoveryAuthorityInspection(
    config,
    dependencies,
  );
  return async (
    input: Input,
  ): Promise<Task13RecoveryPrerequisiteInspectionResult> => {
    const result = await inspect(input);
    return Object.freeze({
      authority_valid: true,
      repository_identity_valid: true,
      state_classification: result.state,
    });
  };
}

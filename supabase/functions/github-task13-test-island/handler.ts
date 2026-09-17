import type {
  RepositoryProvisioningCommandV2,
  RepositoryProvisioningResultV2,
} from "../_shared/repository-provisioning.ts";
import {
  GITHUB_LAB_CREATE_SUBPHASES,
  GITHUB_LAB_POST_CREATE_SUBPHASES,
  GITHUB_SNAPSHOT_READBACK_CHECKS,
  GITHUB_TOKEN_ACQUIRE_SUBPHASES,
  GITHUB_TOKEN_LEASE_CHECKS,
  GITHUB_TOKEN_RESPONSE_CHECKS,
  type GitHubLabCreateSubphase,
  type GitHubLabPostCreateSubphase,
  hasValidatedGitHubLabCreateSubphase,
  hasValidatedGitHubLabPostCreateDiagnosticError,
  hasValidatedGitHubLabPostCreateSubphase,
  hasValidatedGitHubTokenAcquireDiagnostic,
  hasValidatedGitHubTokenLeaseCheck,
  hasValidatedGitHubTokenResponseCheck,
  REPOSITORY_PROVIDER_FAILURE_PHASES,
  REPOSITORY_STARTER_READ_SUBPHASES,
  RepositoryProvisioningClaimDiagnosticError,
  RepositoryProvisioningProviderDiagnosticError,
  RepositoryProvisioningRuntimeDiagnosticError,
  type RepositoryStarterReadSubphase,
} from "../_shared/repository-provisioning-diagnostics.ts";
import { RepositoryPreclaimDiagnosticError } from "./runtime.ts";
import {
  TASK13_SYNTHETIC_AUTHORITY,
  Task13LabReadonlyError,
  type Task13LabReadonlyResult,
} from "./readonly-reconciliation.ts";
import type { Task13PostCreateRecoveryResult } from "./post-create-recovery-writer.ts";
import {
  getValidatedTask13RefReadDiagnostic,
  hasValidatedTask13RecoveryAuthorityDiagnostic,
  TASK13_RECOVERY_INSPECTION_FAILURE_PHASES,
  type Task13RecoveryInspectionFailurePhase,
  type Task13RecoveryPrerequisiteInspectionResult,
} from "./recovery-prerequisite-inspection.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 512;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const NODE_ID = /^[A-Za-z0-9_-]{6,128}$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;

export type GitHubTask13TestIslandDependencies = Readonly<{
  now(): number;
  verifyUser(jwt: string): Promise<Readonly<{ id: string }> | null>;
  authorizeOwner(jwt: string): Promise<void>;
  verifySyntheticAuthority(
    input: Readonly<{
      websiteWorkContextId: string;
      websiteWorkspaceId: string;
    }>,
  ): Promise<boolean>;
  execute(
    command: Omit<RepositoryProvisioningCommandV2, "starter">,
  ): Promise<RepositoryProvisioningResultV2>;
  reconcileReadonly(): Promise<Task13LabReadonlyResult>;
  inspectRecoveryPrerequisites(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      websiteWorkspaceId: string;
    }>,
  ): Promise<Task13RecoveryPrerequisiteInspectionResult>;
  recoverPostCreateExistingRepository(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      websiteWorkspaceId: string;
    }>,
  ): Promise<Task13PostCreateRecoveryResult>;
  finalizePostRecoveryRepository(
    input: Readonly<{
      operationId: string;
      websiteWorkContextId: string;
      websiteWorkspaceId: string;
    }>,
    actor: Readonly<{ authUserId: string; aal: "aal2" }>,
  ): Promise<RepositoryProvisioningResultV2>;
}>;

type ParsedCommand =
  | Readonly<{
    action: "execute_task13_test_island";
    input: Omit<RepositoryProvisioningCommandV2, "starter">;
  }>
  | Readonly<{
    action: "reconcile_task13_lab_repository_readonly";
    websiteWorkContextId: string;
    websiteWorkspaceId: string;
  }>
  | Readonly<{
    action: "inspect_recovery_prerequisites";
    operationId: string;
    websiteWorkContextId: string;
    websiteWorkspaceId: string;
  }>
  | Readonly<{
    action: "recover_post_create_existing_repository";
    operationId: string;
    websiteWorkContextId: string;
    websiteWorkspaceId: string;
  }>
  | Readonly<{
    action: "finalize_post_recovery_repository";
    operationId: string;
    websiteWorkContextId: string;
    websiteWorkspaceId: string;
  }>;

class RequestError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

function response(status: number, code: string, result?: unknown): Response {
  return Response.json({
    ok: status < 400,
    code,
    ...(result === undefined ? {} : { result }),
  }, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
}

function recoveryInspectionFailureResponse(error: unknown): Response {
  let failedInspectionPhase: Task13RecoveryInspectionFailurePhase = "UNKNOWN";
  let failedSnapshotReadbackCheck:
    | (typeof GITHUB_SNAPSHOT_READBACK_CHECKS)[number]
    | undefined;
  let failedRefReadDiagnostic:
    | ReturnType<typeof getValidatedTask13RefReadDiagnostic>
    | undefined;
  if (hasValidatedTask13RecoveryAuthorityDiagnostic(error)) {
    failedInspectionPhase = error.failedInspectionPhase;
  } else if (
    hasValidatedGitHubLabPostCreateDiagnosticError(error) &&
    TASK13_RECOVERY_INSPECTION_FAILURE_PHASES.includes(
      error.subphase as Task13RecoveryInspectionFailurePhase,
    )
  ) {
    failedInspectionPhase = error
      .subphase as Task13RecoveryInspectionFailurePhase;
    if (failedInspectionPhase === "LAB_POST_CREATE_SNAPSHOT_READBACK") {
      failedSnapshotReadbackCheck = GITHUB_SNAPSHOT_READBACK_CHECKS.includes(
          error
            .snapshotReadbackCheck as (typeof GITHUB_SNAPSHOT_READBACK_CHECKS)[
              number
            ],
        )
        ? error.snapshotReadbackCheck
        : "UNKNOWN";
      if (failedSnapshotReadbackCheck === "REF_READ") {
        failedRefReadDiagnostic = getValidatedTask13RefReadDiagnostic(error);
      }
    }
  }
  return Response.json({
    ok: false,
    code: "TASK13_RECOVERY_PREREQUISITES_INSPECTION_FAILED",
    failed_inspection_phase: failedInspectionPhase,
    ...(failedSnapshotReadbackCheck === undefined ? {} : {
      failed_snapshot_readback_check: failedSnapshotReadbackCheck,
    }),
    ...(failedRefReadDiagnostic === undefined ? {} : {
      failed_ref_read_diagnostic: failedRefReadDiagnostic,
    }),
  }, {
    status: 502,
    headers: {
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
}

function projectResult(value: RepositoryProvisioningResultV2) {
  const keys = Object.keys(value).sort();
  const expected = [
    "defaultBranch",
    "name",
    "owner",
    "provider",
    "providerNodeId",
    "providerRepositoryId",
    "replayed",
    "repositoryMarkerCommitSha",
    "starterCommitSha",
    "starterSource",
    "starterVersion",
    "visibility",
  ].sort();
  if (
    keys.length !== expected.length ||
    !keys.every((key, index) => key === expected[index]) ||
    value.provider !== "GITHUB" ||
    !NUMERIC_ID.test(value.providerRepositoryId) ||
    !NODE_ID.test(value.providerNodeId) ||
    value.owner !== "lorenzo-web-solutions-lab" ||
    !/^lws-web-[0-9a-f]{32}$/.test(value.name) ||
    value.visibility !== "PRIVATE" || value.defaultBranch !== "main" ||
    value.starterSource !== "lorenzo-web-solutions/lws-website-starter" ||
    value.starterVersion !== "1.0.0" ||
    !SHA.test(value.starterCommitSha) ||
    !SHA.test(value.repositoryMarkerCommitSha) ||
    typeof value.replayed !== "boolean"
  ) throw new Error("TASK13_RESULT_INVALID");
  return Object.freeze({ ...value });
}

function projectReadonlyResult(value: Task13LabReadonlyResult) {
  const common = [
    "found",
    "installation_id_match",
    "principal_type",
    "private_lab_visibility_proven",
  ];
  const found = [
    ...common,
    "created_at_present",
    "default_branch_present",
    "name",
    "node_id_present",
    "owner",
    "private",
    "repository_id",
    "visibility",
  ].sort();
  const keys = Object.keys(value).sort();
  const expected = value.found === true ? found : common.sort();
  if (
    keys.length !== expected.length ||
    !keys.every((key, index) => key === expected[index]) ||
    value.principal_type !== "GITHUB_APP_INSTALLATION" ||
    value.installation_id_match !== true ||
    value.private_lab_visibility_proven !== true ||
    typeof value.found !== "boolean" ||
    value.found && (
        !NUMERIC_ID.test(String(value.repository_id || "")) ||
        value.node_id_present !== true ||
        value.owner !== TASK13_SYNTHETIC_AUTHORITY.organization ||
        value.name !== TASK13_SYNTHETIC_AUTHORITY.repository ||
        value.private !== true || value.visibility !== "PRIVATE" ||
        typeof value.default_branch_present !== "boolean" ||
        value.created_at_present !== true
      )
  ) throw new Error("TASK13_LAB_RECONCILIATION_RESULT_INVALID");
  return Object.freeze({ ...value });
}

function projectRecoveryPrerequisiteResult(
  value: Task13RecoveryPrerequisiteInspectionResult,
): Task13RecoveryPrerequisiteInspectionResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("TASK13_RECOVERY_PREREQUISITES_RESULT_INVALID");
  }
  const prototype = Object.getPrototypeOf(value);
  const keys = Reflect.ownKeys(value).sort();
  const expected = [
    "authority_valid",
    "repository_identity_valid",
    "state_classification",
  ].sort();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (
    prototype !== Object.prototype && prototype !== null ||
    keys.length !== expected.length ||
    !keys.every((key, index) => key === expected[index]) ||
    !expected.every((key) =>
      descriptors[key]?.enumerable === true &&
      Object.hasOwn(descriptors[key], "value")
    ) ||
    descriptors.authority_valid.value !== true ||
    descriptors.repository_identity_valid.value !== true ||
    typeof descriptors.state_classification.value !== "string" ||
    ![
      "EMPTY_OR_UNINITIALIZED",
      "ALREADY_COMPLETE",
      "MARKER_MISSING",
      "CONFLICT",
    ].includes(descriptors.state_classification.value)
  ) throw new Error("TASK13_RECOVERY_PREREQUISITES_RESULT_INVALID");
  return Object.freeze({
    authority_valid: true,
    repository_identity_valid: true,
    state_classification: descriptors.state_classification
      .value as Task13RecoveryPrerequisiteInspectionResult[
        "state_classification"
      ],
  });
}

function projectPostCreateRecoveryResult(
  value: Task13PostCreateRecoveryResult,
): Task13PostCreateRecoveryResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("TASK13_POST_CREATE_RECOVERY_RESULT_INVALID");
  }
  const prototype = Object.getPrototypeOf(value);
  const ownKeys = Reflect.ownKeys(value);
  const descriptor = Object.getOwnPropertyDescriptor(value, "status");
  if (
    prototype !== Object.prototype && prototype !== null ||
    ownKeys.length !== 1 || ownKeys[0] !== "status" ||
    descriptor?.enumerable !== true || !Object.hasOwn(descriptor, "value") ||
    !Object.isFrozen(value) ||
    ![
      "ALREADY_COMPLETE",
      "RECOVERED_FROM_EMPTY",
      "RECOVERED_MARKER_ONLY",
    ].includes(descriptor.value)
  ) throw new Error("TASK13_POST_CREATE_RECOVERY_RESULT_INVALID");
  return Object.freeze({
    status: descriptor.value as Task13PostCreateRecoveryResult["status"],
  });
}

function projectPostRecoveryFinalizationResult(
  value: RepositoryProvisioningResultV2,
) {
  const result = projectResult(value);
  return Object.freeze({
    status: "REPOSITORY_READY" as const,
    replayed: result.replayed,
  });
}

function bearer(request: Request): string {
  const match = (request.headers.get("authorization") || "").match(
    /^Bearer\s+([^\s]+)$/i,
  );
  if (!match) throw new RequestError(401, "CALLER_VERIFICATION");
  return match[1];
}

function claims(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) throw new RequestError(403, "CALLER_VERIFICATION");
  try {
    const encoded = parts[1].replaceAll("-", "+").replaceAll("_", "/")
      .padEnd(Math.ceil(parts[1].length / 4) * 4, "=");
    const value = JSON.parse(atob(encoded));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw 0;
    return value;
  } catch {
    throw new RequestError(403, "CALLER_VERIFICATION");
  }
}

async function command(
  request: Request,
): Promise<ParsedCommand> {
  if (
    (request.headers.get("content-type") || "").split(";", 1)[0].trim()
      .toLowerCase() !== "application/json"
  ) throw new RequestError(415, "INVALID_REQUEST");
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    throw new RequestError(413, "INVALID_REQUEST");
  }
  try {
    const value = JSON.parse(text) as Record<string, unknown>;
    const keys = Object.keys(value).sort();
    if (
      value.action === "inspect_recovery_prerequisites" ||
      value.action === "recover_post_create_existing_repository" ||
      value.action === "finalize_post_recovery_repository"
    ) {
      const expected = [
        "action",
        "operation_id",
        "website_work_context_id",
        "website_workspace_id",
      ].sort();
      if (
        keys.length !== expected.length ||
        !keys.every((key, index) => key === expected[index]) ||
        !UUID.test(String(value.operation_id || "")) ||
        !UUID.test(String(value.website_work_context_id || "")) ||
        !UUID.test(String(value.website_workspace_id || ""))
      ) throw new RequestError(400, "INVALID_REQUEST");
      return Object.freeze({
        action: value.action,
        operationId: String(value.operation_id),
        websiteWorkContextId: String(value.website_work_context_id),
        websiteWorkspaceId: String(value.website_workspace_id),
      });
    }
    if (value.action === "reconcile_task13_lab_repository_readonly") {
      const expected = [
        "action",
        "website_work_context_id",
        "website_workspace_id",
      ].sort();
      if (
        keys.length !== expected.length ||
        !keys.every((key, index) => key === expected[index]) ||
        !UUID.test(String(value.website_work_context_id || "")) ||
        !UUID.test(String(value.website_workspace_id || ""))
      ) throw new RequestError(403, "TASK13_SYNTHETIC_AUTHORITY_INVALID");
      return Object.freeze({
        action: value.action,
        websiteWorkContextId: String(value.website_work_context_id),
        websiteWorkspaceId: String(value.website_workspace_id),
      });
    }
    const expected = [
      "action",
      "idempotency_key",
      "website_work_context_id",
      "website_workspace_id",
    ].sort();
    if (
      keys.length !== expected.length ||
      !keys.every((key, index) => key === expected[index]) ||
      value.action !== "execute_task13_test_island" ||
      !UUID.test(String(value.website_workspace_id || "")) ||
      !UUID.test(String(value.website_work_context_id || "")) ||
      !UUID.test(String(value.idempotency_key || ""))
    ) throw 0;
    return Object.freeze({
      action: value.action,
      input: Object.freeze({
        contractVersion: 2 as const,
        websiteWorkspaceId: String(value.website_workspace_id),
        websiteWorkContextId: String(value.website_work_context_id),
        idempotencyKey: String(value.idempotency_key),
      }),
    });
  } catch (error) {
    if (error instanceof RequestError) throw error;
    throw new RequestError(400, "INVALID_REQUEST");
  }
}

export async function handleGitHubTask13TestIsland(
  request: Request,
  dependencies: GitHubTask13TestIslandDependencies,
): Promise<Response> {
  try {
    if (request.method !== "POST") {
      throw new RequestError(405, "INVALID_REQUEST");
    }
    const parsedCommand = await command(request);
    const token = bearer(request);
    const decoded = claims(token);
    const subject = String(decoded.sub || "");
    if (
      !UUID.test(subject) || typeof decoded.exp !== "number" ||
      decoded.exp * 1000 <= dependencies.now() ||
      decoded.role === "service_role"
    ) throw new RequestError(403, "CALLER_VERIFICATION");
    const user = await dependencies.verifyUser(token);
    if (!user || user.id !== subject) {
      throw new RequestError(403, "CALLER_VERIFICATION");
    }
    if (decoded.aal !== "aal2") {
      throw new RequestError(403, "AAL2_VERIFICATION");
    }
    try {
      await dependencies.authorizeOwner(token);
    } catch {
      throw new RequestError(403, "OWNER_AUTHORIZATION");
    }
    if (
      parsedCommand.action === "inspect_recovery_prerequisites" ||
      parsedCommand.action === "recover_post_create_existing_repository" ||
      parsedCommand.action === "finalize_post_recovery_repository"
    ) {
      if (
        parsedCommand.websiteWorkContextId !==
          TASK13_SYNTHETIC_AUTHORITY.websiteWorkContextId ||
        parsedCommand.websiteWorkspaceId !==
          TASK13_SYNTHETIC_AUTHORITY.websiteWorkspaceId
      ) return response(403, "TASK13_SYNTHETIC_AUTHORITY_INVALID");
      const validAuthority = await dependencies.verifySyntheticAuthority(
        Object.freeze({
          websiteWorkContextId: parsedCommand.websiteWorkContextId,
          websiteWorkspaceId: parsedCommand.websiteWorkspaceId,
        }),
      );
      if (!validAuthority) {
        return response(403, "TASK13_SYNTHETIC_AUTHORITY_INVALID");
      }
      const input = Object.freeze({
        operationId: parsedCommand.operationId,
        websiteWorkContextId: parsedCommand.websiteWorkContextId,
        websiteWorkspaceId: parsedCommand.websiteWorkspaceId,
      });
      if (parsedCommand.action === "finalize_post_recovery_repository") {
        try {
          const result = projectPostRecoveryFinalizationResult(
            await dependencies.finalizePostRecoveryRepository(
              input,
              Object.freeze({ authUserId: user.id, aal: "aal2" }),
            ),
          );
          return response(
            200,
            "TASK13_POST_RECOVERY_REPOSITORY_FINALIZED",
            result,
          );
        } catch {
          return response(502, "TASK13_POST_RECOVERY_FINALIZATION_FAILED");
        }
      }
      if (parsedCommand.action === "recover_post_create_existing_repository") {
        try {
          const result = projectPostCreateRecoveryResult(
            await dependencies.recoverPostCreateExistingRepository(input),
          );
          return response(200, "TASK13_POST_CREATE_RECOVERY_RESULT", result);
        } catch {
          return response(502, "TASK13_POST_CREATE_RECOVERY_FAILED");
        }
      }
      try {
        const result = projectRecoveryPrerequisiteResult(
          await dependencies.inspectRecoveryPrerequisites(input),
        );
        return response(
          200,
          "TASK13_RECOVERY_PREREQUISITES_INSPECTION",
          result,
        );
      } catch (error) {
        return recoveryInspectionFailureResponse(error);
      }
    }
    if (parsedCommand.action === "reconcile_task13_lab_repository_readonly") {
      try {
        if (
          parsedCommand.websiteWorkContextId !==
            TASK13_SYNTHETIC_AUTHORITY.websiteWorkContextId ||
          parsedCommand.websiteWorkspaceId !==
            TASK13_SYNTHETIC_AUTHORITY.websiteWorkspaceId
        ) return response(403, "TASK13_SYNTHETIC_AUTHORITY_INVALID");
        const validAuthority = await dependencies.verifySyntheticAuthority(
          Object.freeze({
            websiteWorkContextId: parsedCommand.websiteWorkContextId,
            websiteWorkspaceId: parsedCommand.websiteWorkspaceId,
          }),
        );
        if (!validAuthority) {
          return response(403, "TASK13_SYNTHETIC_AUTHORITY_INVALID");
        }
        const result = projectReadonlyResult(
          await dependencies.reconcileReadonly(),
        );
        return response(
          200,
          "TASK13_LAB_RECONCILIATION_READONLY_RESULT",
          result,
        );
      } catch (error) {
        if (error instanceof Task13LabReadonlyError) {
          return response(502, error.code);
        }
        return response(502, "TASK13_LAB_RECONCILIATION_READ_FAILED");
      }
    }
    let executed: RepositoryProvisioningResultV2;
    try {
      executed = await dependencies.execute(parsedCommand.input);
    } catch (error) {
      if (
        error instanceof RepositoryProvisioningClaimDiagnosticError ||
        error instanceof RepositoryProvisioningProviderDiagnosticError ||
        error instanceof RepositoryProvisioningRuntimeDiagnosticError ||
        error instanceof RepositoryPreclaimDiagnosticError
      ) throw error;
      throw new RepositoryPreclaimDiagnosticError("UNKNOWN_PRECLAIM_ERROR");
    }
    const result = projectResult(executed);
    return response(200, "TASK13_TEST_ISLAND_EXECUTED", result);
  } catch (error) {
    if (error instanceof RequestError) {
      return response(error.status, error.code);
    }
    if (error instanceof RepositoryProvisioningClaimDiagnosticError) {
      const sqlstateClass = error.sqlstateClass &&
          /^[0-9A-Z]{2}$/.test(error.sqlstateClass)
        ? error.sqlstateClass
        : undefined;
      return Response.json({
        ok: false,
        code: "TASK13_TEST_ISLAND_FAILED",
        failed_stage: "STORE_CLAIM",
        failed_claim_phase: error.phase,
        ...(sqlstateClass ? { sqlstate_class: sqlstateClass } : {}),
      }, {
        status: 502,
        headers: {
          "Cache-Control": "no-store",
          "Referrer-Policy": "no-referrer",
        },
      });
    }
    if (error instanceof RepositoryProvisioningProviderDiagnosticError) {
      if (!REPOSITORY_PROVIDER_FAILURE_PHASES.includes(error.phase)) {
        return response(502, "TASK13_TEST_ISLAND_FAILED");
      }
      const starterSubphase =
        error.phase === "GITHUB_STARTER_SNAPSHOT_INVALID" &&
          error.subphase !== undefined &&
          REPOSITORY_STARTER_READ_SUBPHASES.includes(
            error.subphase as RepositoryStarterReadSubphase,
          )
          ? error.subphase as RepositoryStarterReadSubphase
          : undefined;
      const createSubphase = error.phase === "GITHUB_LAB_CREATE_FAILED" &&
          error.subphase !== undefined &&
          hasValidatedGitHubLabCreateSubphase(error) &&
          GITHUB_LAB_CREATE_SUBPHASES.includes(
            error.subphase as GitHubLabCreateSubphase,
          )
        ? error.subphase as GitHubLabCreateSubphase
        : undefined;
      const postCreateSubphase =
        error.phase === "GITHUB_LAB_POST_CREATE_FAILED" &&
          error.subphase !== undefined &&
          hasValidatedGitHubLabPostCreateSubphase(error) &&
          GITHUB_LAB_POST_CREATE_SUBPHASES.includes(
            error.subphase as GitHubLabPostCreateSubphase,
          )
          ? error.subphase as GitHubLabPostCreateSubphase
          : undefined;
      const subphase = starterSubphase ?? createSubphase ??
        postCreateSubphase;
      const tokenAcquirePair = starterSubphase === "STARTER_TOKEN_ACQUIRE" ||
        createSubphase === "LAB_TOKEN_ACQUIRE";
      const tokenAcquireSubphase =
        tokenAcquirePair && hasValidatedGitHubTokenAcquireDiagnostic(error) &&
          error.tokenAcquireSubphase !== undefined &&
          GITHUB_TOKEN_ACQUIRE_SUBPHASES.includes(error.tokenAcquireSubphase)
          ? error.tokenAcquireSubphase
          : undefined;
      const tokenLeaseCheck = tokenAcquireSubphase === "TOKEN_LEASE_VALIDATE" &&
          hasValidatedGitHubTokenLeaseCheck(error) &&
          GITHUB_TOKEN_LEASE_CHECKS.includes(error.tokenLeaseCheck)
        ? error.tokenLeaseCheck
        : undefined;
      const tokenResponseCheck =
        tokenAcquireSubphase === "TOKEN_RESPONSE_SCHEMA" &&
          hasValidatedGitHubTokenResponseCheck(error) &&
          GITHUB_TOKEN_RESPONSE_CHECKS.includes(error.tokenResponseCheck)
          ? error.tokenResponseCheck
          : undefined;
      return Response.json({
        ok: false,
        code: "TASK13_TEST_ISLAND_FAILED",
        failed_stage: "PROVIDER",
        failed_provider_phase: error.phase,
        ...(subphase ? { failed_provider_subphase: subphase } : {}),
        ...(tokenAcquireSubphase
          ? { failed_token_acquire_subphase: tokenAcquireSubphase }
          : {}),
        ...(tokenLeaseCheck
          ? { failed_token_lease_check: tokenLeaseCheck }
          : {}),
        ...(tokenResponseCheck
          ? { failed_token_response_check: tokenResponseCheck }
          : {}),
      }, {
        status: 502,
        headers: {
          "Cache-Control": "no-store",
          "Referrer-Policy": "no-referrer",
        },
      });
    }
    if (error instanceof RepositoryProvisioningRuntimeDiagnosticError) {
      return Response.json({
        ok: false,
        code: "TASK13_TEST_ISLAND_FAILED",
        failed_stage: "RUNTIME_PROVISION",
        failed_runtime_phase: error.phase,
      }, {
        status: 502,
        headers: {
          "Cache-Control": "no-store",
          "Referrer-Policy": "no-referrer",
        },
      });
    }
    if (error instanceof RepositoryPreclaimDiagnosticError) {
      return Response.json({
        ok: false,
        code: "TASK13_TEST_ISLAND_FAILED",
        failed_stage: "PRE_CLAIM",
        failed_preclaim_phase: error.phase,
      }, {
        status: 502,
        headers: {
          "Cache-Control": "no-store",
          "Referrer-Policy": "no-referrer",
        },
      });
    }
    return response(502, "TASK13_TEST_ISLAND_FAILED");
  }
}

export function createUnsignedTask13TestJwt(
  value: Record<string, unknown>,
): string {
  const encode = (item: Record<string, unknown>) =>
    btoa(JSON.stringify(item)).replaceAll("+", "-").replaceAll("/", "_")
      .replace(/=+$/, "");
  return `${encode({ alg: "none", typ: "JWT" })}.${encode(value)}.`;
}

import type {
  RepositoryProvisioningAuthorityV2,
  RepositoryProvisioningClaimV2,
  RepositoryProvisioningStoreV2,
  VerifiedRepositoryBindingV2,
} from "./repository-provisioning.ts";
import {
  RepositoryProvisioningClaimDiagnosticError,
  type RepositoryProvisioningClaimFailurePhase,
} from "./repository-provisioning-diagnostics.ts";

export { RepositoryProvisioningClaimDiagnosticError } from "./repository-provisioning-diagnostics.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,15}$/;
const NODE_ID = /^[A-Za-z0-9_-]{6,255}$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SHA256 = /^[0-9a-f]{64}$/;
const FAILURE_CODE = /^[A-Z][A-Z0-9_]{0,127}$/;

export type RepositoryProvisioningRpcClient = Readonly<{
  rpc(
    name: string,
    arguments_: Readonly<Record<string, unknown>>,
  ): Promise<Readonly<{ data: unknown; error: unknown }>>;
}>;

export type RepositoryProvisioningStoreV2Options = Readonly<{
  claimRpcName?: "claim_website_repository_provisioning_v1" |
    "claim_production_website_repository_provisioning_v1";
  bindRpcName?: "bind_website_repository_v1" |
    "bind_production_website_repository_v1";
  quoteRequestId?: string;
}>;

export type RepositoryProvisioningOperationStatusV2 = Readonly<{
  operationId: string;
  websiteWorkspaceId: string;
  websiteWorkContextId: string;
  state: string;
  repositoryOwner: string;
  repositoryName: string;
  repositoryId: string | null;
  repositoryNodeId: string | null;
  retryAction: "CREATE" | "RECONCILE" | null;
  quarantineEvidenceSha256: string | null;
}>;

type CapturedLabIdentity = Readonly<{
  operationId: string;
  websiteWorkContextId: string;
  repositoryId: string;
  nodeId: string;
}>;

type QuarantineCode =
  | "EXTERNAL_OUTCOME_UNKNOWN"
  | "REPOSITORY_IDENTITY_MISMATCH"
  | "MARKER_MISMATCH"
  | "STARTER_PROVENANCE_MISMATCH"
  | "CROSS_CONTEXT_BIND_DENIED";

export interface RepositoryProvisioningRuntimeStoreV2
  extends RepositoryProvisioningStoreV2 {
  captureLabIdentity(input: CapturedLabIdentity): Promise<void>;
  finalizeRecoveredRepository(
    operationId: string,
    expected: Readonly<{
      websiteWorkspaceId: string;
      websiteWorkContextId: string;
    }>,
    binding: VerifiedRepositoryBindingV2,
    actor: Readonly<{ authUserId: string; aal: "aal2" }>,
  ): Promise<VerifiedRepositoryBindingV2>;
  quarantine(
    operationId: string,
    code: QuarantineCode,
    githubRequestId?: string | null,
  ): Promise<RepositoryProvisioningOperationStatusV2>;
  readStatus(
    operationId: string,
  ): Promise<RepositoryProvisioningOperationStatusV2>;
  resume(
    operationId: string,
    idempotencyKey: string,
  ): Promise<RepositoryProvisioningOperationStatusV2>;
}

export class RepositoryProvisioningStoreV2Error extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "RepositoryProvisioningStoreV2Error";
  }
}

function fail(code: string): never {
  throw new RepositoryProvisioningStoreV2Error(code);
}

function failClaim(
  phase: RepositoryProvisioningClaimFailurePhase,
  sqlstateClass?: string,
): never {
  throw new RepositoryProvisioningClaimDiagnosticError(phase, sqlstateClass);
}

function errorCode(value: unknown): string | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const code = (value as Record<string, unknown>).code;
  return typeof code === "string" ? code : null;
}

function classifyClaimRpcError(value: unknown): never {
  const code = errorCode(value);
  if (code?.startsWith("PGRST")) {
    return failClaim("CLAIM_RPC_HTTP_OR_POSTGREST");
  }
  if (code === "42501" || code?.startsWith("28")) {
    return failClaim("CLAIM_RPC_AUTHORITY", code.slice(0, 2));
  }
  if (code && /^[0-9A-Z]{5}$/.test(code)) {
    return failClaim("CLAIM_RPC_DATABASE_EXCEPTION", code.slice(0, 2));
  }
  return failClaim("CLAIM_RPC_HTTP_OR_POSTGREST");
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return fail("REPOSITORY_PROVISIONING_STORE_RESPONSE_INVALID");
  }
  return value as Record<string, unknown>;
}

function string(value: unknown, pattern?: RegExp): string {
  if (typeof value !== "string" || !value || pattern && !pattern.test(value)) {
    return fail("REPOSITORY_PROVISIONING_STORE_RESPONSE_INVALID");
  }
  return value;
}

function optionalString(value: unknown, pattern?: RegExp): string | null {
  return value === null ? null : string(value, pattern);
}

function operationStatus(
  value: unknown,
): RepositoryProvisioningOperationStatusV2 {
  const result = record(value);
  const retryAction = result.retry_action;
  if (
    retryAction !== null && retryAction !== "CREATE" &&
    retryAction !== "RECONCILE"
  ) return fail("REPOSITORY_PROVISIONING_STORE_RESPONSE_INVALID");
  return Object.freeze({
    operationId: string(result.operation_id, UUID),
    websiteWorkspaceId: string(result.website_workspace_id, UUID),
    websiteWorkContextId: string(result.website_work_context_id, UUID),
    state: string(result.state, /^[A-Z][A-Z_]{1,63}$/),
    repositoryOwner: string(result.repository_owner),
    repositoryName: string(result.repository_name),
    repositoryId: optionalString(result.repository_external_id, NUMERIC_ID),
    repositoryNodeId: optionalString(result.repository_node_id, NODE_ID),
    retryAction,
    quarantineEvidenceSha256: optionalString(
      result.quarantine_evidence_sha256,
      SHA256,
    ),
  });
}

function sameOperation(
  status: RepositoryProvisioningOperationStatusV2,
  expected: Readonly<{
    operationId?: string;
    websiteWorkspaceId?: string;
    websiteWorkContextId?: string;
    repositoryName?: string;
  }>,
): boolean {
  return (!expected.operationId ||
    status.operationId === expected.operationId) &&
    (!expected.websiteWorkspaceId ||
      status.websiteWorkspaceId === expected.websiteWorkspaceId) &&
    (!expected.websiteWorkContextId ||
      status.websiteWorkContextId === expected.websiteWorkContextId) &&
    (!expected.repositoryName ||
      status.repositoryName === expected.repositoryName);
}

function bindingFrom(value: unknown): VerifiedRepositoryBindingV2 {
  const result = record(value);
  if (
    result.state !== "BOUND" || result.repository_visibility !== "private" ||
    result.default_branch !== "main"
  ) return fail("REPOSITORY_PROVISIONING_STORE_RESPONSE_INVALID");
  return Object.freeze({
    provider: "GITHUB" as const,
    providerRepositoryId: string(result.repository_external_id, NUMERIC_ID),
    providerNodeId: string(result.repository_node_id, NODE_ID),
    owner: string(result.repository_owner),
    name: string(result.repository_name),
    visibility: "PRIVATE" as const,
    defaultBranch: "main" as const,
    starterSource: string(result.starter_source),
    starterVersion: string(result.starter_version),
    starterCommitSha: string(result.starter_commit_sha, SHA),
    repositoryMarkerCommitSha: string(
      result.repository_marker_commit_sha,
      SHA,
    ),
  });
}

function sameBinding(
  left: VerifiedRepositoryBindingV2,
  right: VerifiedRepositoryBindingV2,
): boolean {
  return Object.keys(left).every((key) =>
    left[key as keyof VerifiedRepositoryBindingV2] ===
      right[key as keyof VerifiedRepositoryBindingV2]
  );
}

export function createRepositoryProvisioningStoreV2(
  client: RepositoryProvisioningRpcClient,
  options: RepositoryProvisioningStoreV2Options = {},
): RepositoryProvisioningRuntimeStoreV2 {
  if (!client || typeof client.rpc !== "function") {
    return fail("REPOSITORY_PROVISIONING_STORE_CONFIG_INVALID");
  }
  const claimRpcName = options.claimRpcName ||
    "claim_website_repository_provisioning_v1";
  const bindRpcName = options.bindRpcName || "bind_website_repository_v1";
  const productionAuthority =
    claimRpcName === "claim_production_website_repository_provisioning_v1" ||
    bindRpcName === "bind_production_website_repository_v1";
  if (
    productionAuthority &&
    (!UUID.test(String(options.quoteRequestId || "")) ||
      claimRpcName !== "claim_production_website_repository_provisioning_v1" ||
      bindRpcName !== "bind_production_website_repository_v1")
  ) return fail("REPOSITORY_PROVISIONING_STORE_CONFIG_INVALID");

  async function rpc(
    name: string,
    arguments_: Readonly<Record<string, unknown>>,
  ): Promise<unknown> {
    let response: Readonly<{ data: unknown; error: unknown }>;
    try {
      response = await client.rpc(name, arguments_);
    } catch {
      return fail("REPOSITORY_PROVISIONING_STORE_RPC_FAILED");
    }
    if (!response || response.error || response.data === null) {
      return fail("REPOSITORY_PROVISIONING_STORE_RPC_FAILED");
    }
    return response.data;
  }

  async function claimRpc(
    arguments_: Readonly<Record<string, unknown>>,
  ): Promise<unknown> {
    let response: Readonly<{ data: unknown; error: unknown }>;
    try {
      response = await client.rpc(
        claimRpcName,
        arguments_,
      );
    } catch (error) {
      if (error instanceof TypeError) {
        return failClaim("CLAIM_RPC_INVOCATION");
      }
      return failClaim("UNKNOWN_CLAIM_ERROR");
    }
    if (!response || typeof response !== "object" || Array.isArray(response)) {
      return failClaim("CLAIM_RPC_RESPONSE_VALIDATION");
    }
    if (response.error) classifyClaimRpcError(response.error);
    if (response.data === null) {
      return failClaim("CLAIM_RPC_RESPONSE_VALIDATION");
    }
    return response.data;
  }

  return Object.freeze({
    async claim(
      authority: RepositoryProvisioningAuthorityV2,
    ): Promise<RepositoryProvisioningClaimV2> {
      try {
        const value = record(
          await claimRpc(Object.freeze({
            ...(productionAuthority
              ? { p_quote_request_id: options.quoteRequestId }
              : {}),
            p_website_workspace_id: authority.websiteWorkspaceId,
            p_website_work_context_id: authority.websiteWorkContextId,
            p_idempotency_key: authority.idempotencyKey,
            p_starter_source: authority.starter.source,
            p_starter_version: authority.starter.version,
            p_starter_commit_sha: authority.starter.commitSha,
          })),
        );
        const status = operationStatus(value);
        if (
          !sameOperation(status, {
            websiteWorkspaceId: authority.websiteWorkspaceId,
            websiteWorkContextId: authority.websiteWorkContextId,
            repositoryName: authority.repositoryName,
          }) || value.starter_source !== authority.starter.source ||
          value.starter_version !== authority.starter.version ||
          value.starter_commit_sha !== authority.starter.commitSha
        ) return fail("REPOSITORY_PROVISIONING_STORE_BINDING_MISMATCH");
        if (value.result === "CLAIMED" && status.state === "CREATING") {
          return Object.freeze({
            state: "CLAIMED",
            operationId: status.operationId,
          });
        }
        if (value.result === "REPLAY" && status.state === "BOUND") {
          return Object.freeze({
            state: "REPLAY",
            binding: bindingFrom(value),
          });
        }
        if (
          value.result === "IN_PROGRESS" ||
          value.result === "REPLAY" && status.state !== "BOUND"
        ) return Object.freeze({ state: "IN_PROGRESS" });
        return fail("REPOSITORY_PROVISIONING_STORE_RESPONSE_INVALID");
      } catch (error) {
        if (error instanceof RepositoryProvisioningClaimDiagnosticError) {
          throw error;
        }
        return failClaim("CLAIM_RPC_RESPONSE_VALIDATION");
      }
    },

    async captureLabIdentity(input: CapturedLabIdentity): Promise<void> {
      const value = await rpc(
        "record_website_repository_external_identity_v1",
        Object.freeze({
          p_operation_id: input.operationId,
          p_repository_external_id: input.repositoryId,
          p_repository_node_id: input.nodeId,
        }),
      );
      const status = operationStatus(value);
      if (
        !sameOperation(status, input) || status.state !== "VERIFYING" ||
        status.repositoryId !== input.repositoryId ||
        status.repositoryNodeId !== input.nodeId
      ) return fail("REPOSITORY_PROVISIONING_STORE_BINDING_MISMATCH");
    },

    async bind(
      operationId: string,
      expected: Readonly<{
        websiteWorkspaceId: string;
        websiteWorkContextId: string;
      }>,
      binding: VerifiedRepositoryBindingV2,
    ) {
      const value = await rpc(
        bindRpcName,
        Object.freeze({
          ...(productionAuthority
            ? { p_quote_request_id: options.quoteRequestId }
            : {}),
          p_operation_id: operationId,
          p_verification: Object.freeze({
            operation_id: operationId,
            website_workspace_id: expected.websiteWorkspaceId,
            website_work_context_id: expected.websiteWorkContextId,
            repository_external_id: binding.providerRepositoryId,
            repository_node_id: binding.providerNodeId,
            repository_owner: binding.owner,
            repository_name: binding.name,
            repository_visibility: "private",
            default_branch: binding.defaultBranch,
            starter_source: binding.starterSource,
            starter_version: binding.starterVersion,
            starter_commit_sha: binding.starterCommitSha,
            repository_marker_commit_sha: binding.repositoryMarkerCommitSha,
          }),
        }),
      );
      const projected = bindingFrom(value);
      const status = operationStatus(value);
      if (
        !sameOperation(status, { operationId, ...expected }) ||
        !sameBinding(projected, binding)
      ) return fail("REPOSITORY_PROVISIONING_STORE_BINDING_MISMATCH");
      return projected;
    },

    async finalizeRecoveredRepository(
      operationId: string,
      expected: Readonly<{
        websiteWorkspaceId: string;
        websiteWorkContextId: string;
      }>,
      binding: VerifiedRepositoryBindingV2,
      actor: Readonly<{ authUserId: string; aal: "aal2" }>,
    ) {
      if (!UUID.test(actor?.authUserId) || actor.aal !== "aal2") {
        return fail("REPOSITORY_PROVISIONING_STORE_REQUEST_INVALID");
      }
      const value = await rpc(
        "finalize_recovered_website_repository_v1",
        Object.freeze({
          p_operation_id: operationId,
          p_verification: Object.freeze({
            operation_id: operationId,
            website_workspace_id: expected.websiteWorkspaceId,
            website_work_context_id: expected.websiteWorkContextId,
            repository_external_id: binding.providerRepositoryId,
            repository_node_id: binding.providerNodeId,
            repository_owner: binding.owner,
            repository_name: binding.name,
            repository_visibility: "private",
            default_branch: binding.defaultBranch,
            starter_source: binding.starterSource,
            starter_version: binding.starterVersion,
            starter_commit_sha: binding.starterCommitSha,
            repository_marker_commit_sha: binding.repositoryMarkerCommitSha,
          }),
          p_actor_auth_user_id: actor.authUserId,
          p_actor_aal: actor.aal,
        }),
      );
      const projected = bindingFrom(value);
      const status = operationStatus(value);
      if (
        !sameOperation(status, { operationId, ...expected }) ||
        !sameBinding(projected, binding)
      ) return fail("REPOSITORY_PROVISIONING_STORE_BINDING_MISMATCH");
      return projected;
    },

    async fail(operationId: string, code: string): Promise<void> {
      if (!UUID.test(operationId) || !FAILURE_CODE.test(code)) {
        return fail("REPOSITORY_PROVISIONING_STORE_REQUEST_INVALID");
      }
      await rpc(
        "fail_website_repository_provisioning_v1",
        Object.freeze({
          p_operation_id: operationId,
          p_failure_code: code,
          p_github_request_id: null,
          p_provider_retry_at: null,
        }),
      );
    },

    async quarantine(
      operationId: string,
      code: QuarantineCode,
      githubRequestId: string | null = null,
    ) {
      if (!UUID.test(operationId) || !FAILURE_CODE.test(code)) {
        return fail("REPOSITORY_PROVISIONING_STORE_REQUEST_INVALID");
      }
      const value = await rpc(
        "fail_website_repository_provisioning_v1",
        Object.freeze({
          p_operation_id: operationId,
          p_failure_code: code,
          p_github_request_id: githubRequestId,
          p_provider_retry_at: null,
        }),
      );
      const status = operationStatus(value);
      if (
        !sameOperation(status, { operationId }) ||
        status.state !== "QUARANTINED"
      ) {
        return fail("REPOSITORY_PROVISIONING_STORE_RESPONSE_INVALID");
      }
      return status;
    },

    async readStatus(operationId: string) {
      if (!UUID.test(operationId)) {
        return fail("REPOSITORY_PROVISIONING_STORE_REQUEST_INVALID");
      }
      const status = operationStatus(
        await rpc(
          "get_website_repository_operation_v1",
          Object.freeze({ p_operation_id: operationId }),
        ),
      );
      if (!sameOperation(status, { operationId })) {
        return fail("REPOSITORY_PROVISIONING_STORE_BINDING_MISMATCH");
      }
      return status;
    },

    async resume(operationId: string, idempotencyKey: string) {
      if (!UUID.test(operationId) || !UUID.test(idempotencyKey)) {
        return fail("REPOSITORY_PROVISIONING_STORE_REQUEST_INVALID");
      }
      const status = operationStatus(
        await rpc(
          "resume_website_repository_provisioning_v1",
          Object.freeze({
            p_operation_id: operationId,
            p_idempotency_key: idempotencyKey,
          }),
        ),
      );
      if (!sameOperation(status, { operationId })) {
        return fail("REPOSITORY_PROVISIONING_STORE_BINDING_MISMATCH");
      }
      return status;
    },
  });
}

import { createClient } from "npm:@supabase/supabase-js@2";
import { createWebsiteProjectPreviewArtifactReceiptService } from "../_shared/website-project-preview-artifact-receipt.ts";
import { verifyGitHubActionsOidcToken } from "../_shared/website-project-preview-oidc-broker.ts";
import {
  getSupabaseServerSecretKey,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";
import { handleWebsiteProjectPreviewArtifact } from "./handler.ts";

const BUCKET = "website-project-previews";

export function createWebsiteProjectPreviewArtifactRuntime(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
  oidcFetch: typeof fetch = fetch,
) {
  const url = environment.get("SUPABASE_URL") ?? "";
  const key = getSupabaseServerSecretKey("default", environment);
  const audience = environment.get("LWS_PREVIEW_OIDC_AUDIENCE") ?? "";
  const workflowRepository = environment.get("LWS_PREVIEW_WORKFLOW_REPOSITORY") ?? "";
  const workflowRepositoryId = environment.get("LWS_PREVIEW_WORKFLOW_REPOSITORY_ID") ?? "";
  const workflowRef = environment.get("LWS_PREVIEW_WORKFLOW_REF") ?? "";
  const workflowRefName = environment.get("LWS_PREVIEW_WORKFLOW_REF_NAME") ?? "";
  if (!url || !audience || !workflowRepository || !workflowRepositoryId || !workflowRef || !workflowRefName) {
    throw new Error("SERVER_CONFIGURATION_ERROR");
  }
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const storage = client.storage.from(BUCKET);
  const rpc = async <T>(name: string, args: Record<string, unknown>): Promise<T> => {
    const { data, error } = await client.rpc(name, args);
    if (error || !data) throw new Error(error?.message || "RPC_FAILED");
    return data as T;
  };
  return createWebsiteProjectPreviewArtifactReceiptService({
    resolveAuthority: async (input) => {
      const resolved = await rpc<Record<string, unknown>>("resolve_website_project_preview_artifact_authority_v1", {
        p_lease_id: input.leaseId,
        p_build_id: input.buildId,
        p_workflow_run_id: Number(input.workflowRunId),
      });
      return {
        audience,
        workflowRepository,
        workflowRepositoryId,
        workflowRef,
        workflowRefName,
        customerRepository: String(resolved.repository ?? ""),
        customerRepositoryId: String(resolved.repositoryId ?? ""),
        customerCommitSha: String(resolved.commitSha ?? ""),
        runId: String(resolved.runId ?? ""),
        leaseId: String(resolved.leaseId ?? ""),
        buildId: String(resolved.buildId ?? ""),
      };
    },
    verifyOidc: (token, expected) => verifyGitHubActionsOidcToken(token, expected, { fetch: oidcFetch }),
    issueToken: (input) => rpc("issue_website_project_preview_artifact_token_v1", {
      p_token_hash: input.tokenHash,
      p_lease_id: input.authority.leaseId,
      p_build_id: input.authority.buildId,
      p_repository_external_id: Number(input.authority.customerRepositoryId),
      p_commit_sha: input.authority.customerCommitSha,
      p_workflow_run_id: Number(input.authority.runId),
      p_ttl_seconds: input.ttlSeconds,
    }),
    openSession: (input) => rpc("open_website_project_preview_upload_session_v1", {
      p_receipt_token_hash: input.receiptTokenHash,
      p_session_token_hash: input.sessionTokenHash,
      p_lease_id: input.binding.leaseId,
      p_build_id: input.binding.buildId,
      p_repository_external_id: Number(input.binding.repositoryId),
      p_commit_sha: input.binding.commitSha,
      p_workflow_run_id: Number(input.binding.workflowRunId),
      p_primary_relative_path: input.primaryRelativePath,
      p_build_status: input.buildStatus,
      p_manifest: input.manifest.map((entry) => ({
        relative_path: entry.relativePath,
        content_type: entry.contentType,
        sha256: entry.sha256,
        bytes: entry.bytes,
      })),
      p_ttl_seconds: input.ttlSeconds,
    }),
    claimFile: async (input) => {
      await rpc("claim_website_project_preview_upload_file_v1", {
        p_session_token_hash: input.sessionTokenHash,
        p_lease_id: input.binding.leaseId,
        p_build_id: input.binding.buildId,
        p_repository_external_id: Number(input.binding.repositoryId),
        p_commit_sha: input.binding.commitSha,
        p_workflow_run_id: Number(input.binding.workflowRunId),
        p_relative_path: input.file.relativePath,
        p_content_type: input.file.contentType,
        p_sha256: input.file.sha256,
        p_bytes: input.file.bytes,
      });
    },
    completeFile: async (input) => {
      await rpc("complete_website_project_preview_upload_file_v1", {
        p_session_token_hash: input.sessionTokenHash,
        p_lease_id: input.binding.leaseId,
        p_build_id: input.binding.buildId,
        p_repository_external_id: Number(input.binding.repositoryId),
        p_commit_sha: input.binding.commitSha,
        p_workflow_run_id: Number(input.binding.workflowRunId),
        p_relative_path: input.relativePath,
      });
    },
    finalizeSession: (input) => rpc("finalize_website_project_preview_upload_session_v1", {
      p_session_token_hash: input.sessionTokenHash,
      p_lease_id: input.binding.leaseId,
      p_build_id: input.binding.buildId,
      p_repository_external_id: Number(input.binding.repositoryId),
      p_commit_sha: input.binding.commitSha,
      p_workflow_run_id: Number(input.binding.workflowRunId),
    }),
    abortSession: (input) => rpc("abort_website_project_preview_upload_session_v1", {
      p_session_token_hash: input.sessionTokenHash,
      p_lease_id: input.binding.leaseId,
      p_build_id: input.binding.buildId,
      p_repository_external_id: Number(input.binding.repositoryId),
      p_commit_sha: input.binding.commitSha,
      p_workflow_run_id: Number(input.binding.workflowRunId),
    }),
    upload: async (input) => {
      const contentType = input.contentType.split(";", 1)[0];
      const { error } = await storage.upload(
        `${input.buildId}/${input.relativePath}`,
        Uint8Array.from(input.bytes).buffer,
        { contentType, upsert: false },
      );
      if (error) throw new Error(error.message || "ARTIFACT_STORAGE_FAILED");
    },
    remove: async (paths, buildId) => {
      const { error } = await storage.remove(paths.map((path) => `${buildId}/${path}`));
      if (error) throw new Error(error.message || "ARTIFACT_STORAGE_CLEANUP_FAILED");
    },
    randomBytes: () => crypto.getRandomValues(new Uint8Array(32)),
  });
}

if (import.meta.main) {
  const service = createWebsiteProjectPreviewArtifactRuntime();
  Deno.serve((request) => handleWebsiteProjectPreviewArtifact(request, service));
}
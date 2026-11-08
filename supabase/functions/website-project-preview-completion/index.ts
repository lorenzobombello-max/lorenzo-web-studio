import { createClient } from "npm:@supabase/supabase-js@2";
import { getSupabaseServerSecretKey } from "../_shared/supabase-key-bindings.ts";
import { createPreviewPlatformTokenProvider } from "../_shared/website-project-preview-dispatch-runtime.ts";
import { PREVIEW_MONITOR_PATH, PREVIEW_WORKFLOW_REPOSITORY, PREVIEW_WORKFLOW_REPOSITORY_ID, previewRpc } from "../_shared/website-project-preview-dispatch.ts";
import { verifyGitHubActionsOidcToken } from "../_shared/website-project-preview-oidc-broker.ts";
import { createPreviewCompletionService } from "./service.ts";
import { handlePreviewCompletion } from "./handler.ts";
import { cleanupFailedPreviewArtifacts } from "../_shared/website-project-preview-cleanup.ts";
import { handlePreviewDeadline } from "./deadline-handler.ts";
import { runPreviewDeadlineSweep } from "./deadline.ts";

export function createPreviewCompletionRuntime() {
  const audience = Deno.env.get("LWS_PREVIEW_COMPLETION_OIDC_AUDIENCE") ?? "";
  const monitorSha = Deno.env.get("LWS_PREVIEW_COMPLETION_WORKFLOW_SHA") ?? "";
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  if (!audience || !url || !/^[0-9a-f]{40}$/.test(monitorSha)) throw new Error("SERVER_CONFIGURATION_ERROR");
  const client = createClient(url, getSupabaseServerSecretKey("default"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const acquireToken = createPreviewPlatformTokenProvider("WEBSITE_PROJECT_PREVIEW_MONITOR");
  let tokenLease: ReturnType<typeof acquireToken> | undefined;
  const readGitHub = async (path: string, leaseId: string) => {
    tokenLease ??= acquireToken(leaseId);
    const lease = await tokenLease;
    const response = await fetch(`https://api.github.com/repos/${PREVIEW_WORKFLOW_REPOSITORY}/${path}`, {
      redirect: "error", signal: AbortSignal.timeout(10000),
      headers: { authorization: `Bearer ${lease.token}`, accept: "application/vnd.github+json",
        "x-github-api-version": "2022-11-28" },
    });
    if (!response.ok) { await response.body?.cancel(); throw new Error("COMPLETION_PROVIDER_UNAVAILABLE"); }
    return await response.json();
  };
  return createPreviewCompletionService({
    resolve: (input) => previewRpc(client, "get_website_project_preview_dispatch_completion_v1", {
      p_lease_id: input.leaseId, p_build_id: input.buildId,
    }),
    verifyMonitor: (input, authority) => verifyGitHubActionsOidcToken(input.oidcToken, {
      audience, workflowRepository: PREVIEW_WORKFLOW_REPOSITORY, workflowRepositoryId: PREVIEW_WORKFLOW_REPOSITORY_ID,
      workflowRef: `${PREVIEW_WORKFLOW_REPOSITORY}/${PREVIEW_MONITOR_PATH}@refs/heads/main`,
      workflowRefName: "refs/heads/main", workflowSha: monitorSha, workflowEvent: "workflow_run",
      runId: input.monitorRunId, leaseId: input.leaseId, buildId: input.buildId,
      customerRepository: String(authority.repository), customerRepositoryId: String(authority.repositoryId),
      customerCommitSha: String(authority.commitSha),
    }, { fetch }),
    getRun: (id, leaseId) => readGitHub(`actions/runs/${id}`, leaseId),
    getJobs: (id, leaseId) => readGitHub(`actions/runs/${id}/jobs?filter=latest&per_page=100`, leaseId),
    finish: (input, reason) => previewRpc(client, "finish_website_project_preview_failure_v1", {
      p_lease_id: input.leaseId, p_build_id: input.buildId, p_workflow_run_id: Number(input.workflowRunId),
      p_reason: reason, p_workflow_sha: input.workflowSha,
    }),
    cleanup: (buildId) => cleanupFailedPreviewArtifacts(client, client.storage.from("website-project-previews"), buildId),
  });
}

if (import.meta.main) {
  Deno.serve(async (request) => {
    if (new URL(request.url).pathname.endsWith("/website-project-preview-completion/deadline")) {
      return await handlePreviewDeadline(
        request, Deno.env.get("LWS_PREVIEW_DEADLINE_AUTOMATION_SECRET") ?? "", runPreviewDeadlineSweep,
      );
    }
    try { return await handlePreviewCompletion(request, createPreviewCompletionRuntime()); }
    catch { return Response.json({ ok: false, code: "COMPLETION_CONFIGURATION_INVALID" }, { status: 503 }); }
  });
}

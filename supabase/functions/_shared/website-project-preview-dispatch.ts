const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA = /^[0-9a-f]{40}$/;
const REPO = /^[A-Za-z0-9_.-]+$/;
export const PREVIEW_WORKFLOW_REPOSITORY = "lorenzobombello-max/lorenzo-web-studio";
export const PREVIEW_WORKFLOW_REPOSITORY_ID = "1320223175";
export const PREVIEW_WORKFLOW_PATH = ".github/workflows/build-website-project-preview.yml";
export const PREVIEW_MONITOR_PATH = ".github/workflows/complete-website-project-preview.yml";

export function assertPreviewWorkflowConfiguration(repository: string, repositoryId: string, workflowRef: string, refName: string) {
  if (repository !== PREVIEW_WORKFLOW_REPOSITORY || repositoryId !== PREVIEW_WORKFLOW_REPOSITORY_ID
    || workflowRef !== `${PREVIEW_WORKFLOW_REPOSITORY}/${PREVIEW_WORKFLOW_PATH}@refs/heads/main`
    || refName !== "refs/heads/main") {
    throw new Error("PROJECT_PREVIEW_WORKFLOW_CONFIGURATION_INVALID");
  }
}

export type PreviewDispatchRpc = Readonly<{
  rpc(name: string, args: Record<string, unknown>): PromiseLike<{
    data: unknown;
    error: { message?: string } | null;
  }>;
}>;
export function previewRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("PROJECT_PREVIEW_RESPONSE_INVALID");
  }
  return value as Record<string, unknown>;
}
export async function previewRpc(client: PreviewDispatchRpc, name: string, args: Record<string, unknown>) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error("PROJECT_PREVIEW_STATE_OPERATION_FAILED");
  return previewRecord(data);
}
export function previewDispatchStatus(state: unknown): string {
  switch (state) {
    case "ATTEMPTED":
    case "UNKNOWN": return "DISPATCH_UNKNOWN";
    case "ACCEPTED": return "BUILD_QUEUED";
    case "RUNNING": return "BUILD_IN_PROGRESS";
    case "PASS":
    case "PASS_WITH_WARNINGS":
    case "FAILED": return state;
    default: throw new Error("PROJECT_PREVIEW_STATE_INVALID");
  }
}
export function createWebsiteProjectPreviewDispatch(dependencies: Readonly<{
  workflowSha: string;
  client: PreviewDispatchRpc;
  acquireToken(leaseId: string): PromiseLike<{ token: string; expiresAt: string }>;
  fetch(request: Request): Promise<Response>;
}>) {
  if (!SHA.test(dependencies.workflowSha)) throw new Error("PROJECT_PREVIEW_WORKFLOW_NOT_CONFIGURED");
  return {
    async dispatch(leaseId: string, buildId: string, expectedCommitSha: string) {
      if (!UUID.test(leaseId) || !UUID.test(buildId) || !SHA.test(expectedCommitSha)) {
        throw new Error("PROJECT_PREVIEW_AUTHORITY_INVALID");
      }
      const authority = await previewRpc(dependencies.client, "claim_website_project_preview_dispatch_v1", {
        p_lease_id: leaseId, p_workflow_sha: dependencies.workflowSha,
      });
      if (authority.leaseId !== leaseId || authority.buildId !== buildId ||
        authority.commitSha !== expectedCommitSha || authority.workflowSha !== dependencies.workflowSha ||
        typeof authority.dispatchAllowed !== "boolean" ||
        typeof authority.repositoryOwner !== "string" || !REPO.test(authority.repositoryOwner) ||
        typeof authority.repositoryName !== "string" || !REPO.test(authority.repositoryName) ||
        typeof authority.repositoryId !== "string" || !/^[1-9][0-9]*$/.test(authority.repositoryId)) {
        throw new Error("PROJECT_PREVIEW_AUTHORITY_INVALID");
      }
      if (!authority.dispatchAllowed) {
        return { lease_id: leaseId, build_id: buildId, status: previewDispatchStatus(authority.state) };
      }
      let outcome: "ACCEPTED" | "UNKNOWN" | "REJECTED" = "REJECTED";
      let token: { token: string; expiresAt: string };
      try {
        token = await dependencies.acquireToken(leaseId);
        if (!token.token || Date.parse(token.expiresAt) <= Date.now() || !Number.isFinite(Date.parse(token.expiresAt))) {
          throw new Error("PROJECT_PREVIEW_DISPATCH_TOKEN_INVALID");
        }
      } catch {
        await previewRpc(dependencies.client, "record_website_project_preview_dispatch_v1", {
          p_lease_id: leaseId, p_outcome: outcome,
        });
        throw new Error("PROJECT_PREVIEW_DISPATCH_TOKEN_UNAVAILABLE");
      }
      try {
        const response = await dependencies.fetch(new Request(
          `https://api.github.com/repos/${PREVIEW_WORKFLOW_REPOSITORY}/actions/workflows/build-website-project-preview.yml/dispatches`,
          {
            method: "POST", redirect: "error", signal: AbortSignal.timeout(10000),
            headers: { authorization: `Bearer ${token.token}`, accept: "application/vnd.github+json",
              "content-type": "application/json", "x-github-api-version": "2022-11-28" },
            body: JSON.stringify({ ref: "main", inputs: {
              repository_owner: authority.repositoryOwner, repository_name: authority.repositoryName,
              repository_id: authority.repositoryId, commit_sha: expectedCommitSha,
              lease_id: leaseId, build_id: buildId,
            } }),
          },
        ));
        outcome = response.status === 204 ? "ACCEPTED"
          : [400, 401, 403, 404, 422].includes(response.status) ? "REJECTED" : "UNKNOWN";
        await response.body?.cancel();
      } catch {
        outcome = "UNKNOWN";
      }
      const recorded = await previewRpc(dependencies.client, "record_website_project_preview_dispatch_v1", {
        p_lease_id: leaseId, p_outcome: outcome,
      });
      return { lease_id: leaseId, build_id: buildId, status: previewDispatchStatus(recorded.state) };
    },
  };
}

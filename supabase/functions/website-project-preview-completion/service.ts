import { PREVIEW_WORKFLOW_PATH, PREVIEW_WORKFLOW_REPOSITORY, PREVIEW_WORKFLOW_REPOSITORY_ID, previewRecord } from "../_shared/website-project-preview-dispatch.ts";

export type CompletionInput = Readonly<{
  leaseId: string; buildId: string; workflowRunId: string; monitorRunId: string; oidcToken: string;
}>;
type CompletionAuthority = Record<string, unknown> & { workflowSha: string };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const runIdValid = (id: string) => /^[1-9][0-9]*$/.test(id) && Number.isSafeInteger(Number(id));

export function createPreviewCompletionService(dependencies: {
  resolve(input: CompletionInput): Promise<Record<string, unknown>>;
  verifyMonitor(input: CompletionInput, authority: CompletionAuthority): Promise<unknown>;
  getRun(runId: string, leaseId: string): Promise<unknown>;
  getJobs(runId: string, leaseId: string): Promise<unknown>;
  finish(input: CompletionInput & { workflowSha: string }, reason: string): Promise<Record<string, unknown>>;
  cleanup(buildId: string): Promise<void>;
}) {
  return {
    async complete(input: CompletionInput): Promise<Record<string, unknown>> {
      if (!UUID.test(input.leaseId) || !UUID.test(input.buildId)
        || !runIdValid(input.workflowRunId) || !runIdValid(input.monitorRunId)) {
        throw new Error("PROJECT_PREVIEW_COMPLETION_INVALID");
      }
      const authority = await dependencies.resolve(input);
      if (authority.leaseId !== input.leaseId || authority.buildId !== input.buildId
        || typeof authority.workflowSha !== "string" || !/^[0-9a-f]{40}$/.test(authority.workflowSha)
        || (authority.runId !== null && authority.runId !== input.workflowRunId)) {
        throw new Error("PROJECT_PREVIEW_COMPLETION_BINDING_INVALID");
      }
      const workflowSha = authority.workflowSha;
      await dependencies.verifyMonitor(input, { ...authority, workflowSha });
      const run = previewRecord(await dependencies.getRun(input.workflowRunId, input.leaseId));
      for (const repository of [run.repository, run.head_repository]) {
        const repo = previewRecord(repository);
        if (String(repo.id) !== PREVIEW_WORKFLOW_REPOSITORY_ID || repo.full_name !== PREVIEW_WORKFLOW_REPOSITORY) {
          throw new Error("PROJECT_PREVIEW_COMPLETION_RUN_INVALID");
        }
      }
      if (String(run.id) !== input.workflowRunId || run.run_attempt !== 1 || run.event !== "workflow_dispatch"
        || run.status !== "completed" || run.head_sha !== workflowSha || run.head_branch !== "main"
        || run.path !== PREVIEW_WORKFLOW_PATH
        || run.display_title !== `LWS preview lease=${input.leaseId} build=${input.buildId}`) {
        throw new Error("PROJECT_PREVIEW_COMPLETION_RUN_INVALID");
      }
      let reason: string;
      if (run.conclusion === "cancelled") reason = "CANCELLED";
      else if (run.conclusion === "timed_out") reason = "TIMED_OUT";
      else if (run.conclusion === "success") reason = "FINALIZATION_MISSING";
      else if (["failure", "startup_failure", "action_required", "stale", "neutral", "skipped"].includes(String(run.conclusion))) {
        reason = "WORKFLOW_FAILED";
        const data = previewRecord(await dependencies.getJobs(input.workflowRunId, input.leaseId));
        if (!Array.isArray(data.jobs) || data.total_count !== data.jobs.length || data.jobs.length > 100) {
          throw new Error("PROJECT_PREVIEW_COMPLETION_JOBS_INVALID");
        }
        for (const value of data.jobs) {
          const job = previewRecord(value);
          if (String(job.run_id) !== input.workflowRunId || job.run_attempt !== 1) {
            throw new Error("PROJECT_PREVIEW_COMPLETION_JOBS_INVALID");
          }
          if (job.conclusion === "timed_out") { reason = "TIMED_OUT"; break; }
          if (job.conclusion === "failure") {
            reason = job.name === "fetch" ? "FETCH_FAILED" : job.name === "build" ? "BUILD_FAILED"
              : job.name === "upload" ? "UPLOAD_FAILED" : "WORKFLOW_FAILED";
            break;
          }
        }
      } else throw new Error("PROJECT_PREVIEW_COMPLETION_CONCLUSION_INVALID");
      const result = await dependencies.finish({ ...input, workflowSha }, reason);
      if (!["FAILED", "PASS", "PASS_WITH_WARNINGS"].includes(String(result.state))) {
        throw new Error("PROJECT_PREVIEW_COMPLETION_STATE_INVALID");
      }
      if (result.state === "FAILED") await dependencies.cleanup(input.buildId);
      return result;
    },
  };
}

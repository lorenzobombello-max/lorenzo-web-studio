import type {
  WebsiteDeliveryPdfDispatchResult,
  WebsiteDeliveryPdfRerunResult,
  WebsiteDeliveryPdfRunEvidence,
} from "./website-delivery-pdf-workflow-dispatch.ts";

type Status = Readonly<
  Record<string, unknown> & {
    task_id: string;
    status: string;
  }
>;

type Dependencies = Readonly<{
  claim(
    taskId: string,
  ): Promise<
    Status & { dispatch_attempt_id?: string; should_dispatch: boolean }
  >;
  record(
    taskId: string,
    attemptId: string,
    result: WebsiteDeliveryPdfDispatchResult,
  ): Promise<Status>;
  status(taskId: string): Promise<Status>;
  reconcile(
    taskId: string,
    evidence: WebsiteDeliveryPdfRunEvidence,
  ): Promise<Status>;
  reconcileRerun(
    taskId: string,
    recoveryId: string,
    evidence: WebsiteDeliveryPdfRunEvidence,
  ): Promise<Status>;
  claimRerun(
    taskId: string,
    expectedDispatchAttemptId: string,
    evidence: WebsiteDeliveryPdfRunEvidence,
    approvalId: string,
  ): Promise<Status & { should_rerun: boolean }>;
  recordRerun(
    taskId: string,
    approvalId: string,
    result: WebsiteDeliveryPdfRerunResult,
  ): Promise<Status>;
  dispatch(taskId: string): Promise<WebsiteDeliveryPdfDispatchResult>;
  rerun(
    taskId: string,
    providerRunId: string,
  ): Promise<WebsiteDeliveryPdfRerunResult>;
  findRun(
    taskId: string,
    dispatchStartedAt: string,
  ): Promise<WebsiteDeliveryPdfRunEvidence>;
}>;

const RETRYABLE_CONCLUSIONS = new Set([
  "action_required",
  "cancelled",
  "failure",
  "stale",
  "startup_failure",
  "timed_out",
]);

function isDurableProviderEvidence(
  evidence: WebsiteDeliveryPdfRunEvidence,
): boolean {
  return evidence.providerRunStatus === "queued" ||
    evidence.providerRunStatus === "in_progress" ||
    (evidence.providerRunStatus === "completed" &&
      evidence.providerRunConclusion !== null);
}

function dispatchBinding(status: Status): Readonly<{
  attemptId: string;
  startedAt: string;
}> {
  if (
    typeof status.dispatch_attempt_id !== "string" ||
    typeof status.dispatch_started_at !== "string"
  ) {
    throw new Error("WEBSITE_DELIVERY_PDF_DISPATCH_RESPONSE_INVALID");
  }
  return {
    attemptId: status.dispatch_attempt_id,
    startedAt: status.dispatch_started_at,
  };
}

export function createWebsiteDeliveryPdfWorkflowStarter(
  dependencies: Dependencies,
) {
  return Object.freeze({
    async start(taskId: string): Promise<Status> {
      const claim = await dependencies.claim(taskId);
      if (!claim.should_dispatch) return claim;
      if (typeof claim.dispatch_attempt_id !== "string") {
        throw new Error("WEBSITE_DELIVERY_PDF_DISPATCH_RESPONSE_INVALID");
      }
      const result = await dependencies.dispatch(taskId);
      return await dependencies.record(
        taskId,
        claim.dispatch_attempt_id,
        result,
      );
    },

    async read(taskId: string): Promise<Status> {
      return await dependencies.status(taskId);
    },

    async inspect(taskId: string): Promise<Status> {
      const current = await dependencies.status(taskId);
      const binding = dispatchBinding(current);
      const evidence = await dependencies.findRun(taskId, binding.startedAt);
      if (evidence.outcome === "UNKNOWN") {
        return Object.freeze({
          ...current,
          provider_inspection_status: "UNKNOWN",
          result_code: evidence.code,
          provider_checked_at: evidence.checkedAt,
          allowed_action: "INSPECT_PROVIDER",
        });
      }
      if (current.recovery_status === "RERUN_FAILED") {
        return Object.freeze({
          ...current,
          provider_inspection_status: "FOUND",
          provider_checked_at: evidence.checkedAt,
          allowed_action: "NONE",
        });
      }
      if (["RERUN_UNKNOWN", "RERUN_ACCEPTED", "RUNNING"].includes(
        String(current.recovery_status || ""),
      )) {
        if (
          typeof current.recovery_id !== "string" ||
          typeof current.approved_run_attempt !== "number" ||
          evidence.providerRunId !== current.provider_run_id
        ) throw new Error("WEBSITE_DELIVERY_PDF_RECOVERY_RESPONSE_INVALID");
        if (!isDurableProviderEvidence(evidence)) {
          return Object.freeze({
            ...current,
            provider_inspection_status: "FOUND",
            provider_run_status: evidence.providerRunStatus,
            provider_run_conclusion: evidence.providerRunConclusion,
            provider_checked_at: evidence.checkedAt,
            allowed_action: "INSPECT_PROVIDER",
          });
        }
        if (
          evidence.providerRunAttempt !== null &&
          evidence.providerRunAttempt > current.approved_run_attempt
        ) {
          const reconciled = await dependencies.reconcileRerun(
            taskId,
            current.recovery_id,
            evidence,
          );
          return Object.freeze({
            ...current,
            ...reconciled,
            recovery_result_code: reconciled.result_code,
            provider_inspection_status: "FOUND",
            provider_checked_at: evidence.checkedAt,
            allowed_action: evidence.providerRunStatus === "completed"
              ? "NONE"
              : "WAIT_FOR_RERUN",
          });
        }
        return Object.freeze({
          ...current,
          provider_inspection_status: "FOUND",
          provider_checked_at: evidence.checkedAt,
          allowed_action: "INSPECT_PROVIDER",
        });
      }
      if (!isDurableProviderEvidence(evidence)) {
        return Object.freeze({
          ...current,
          provider_inspection_status: "FOUND",
          provider_run_status: evidence.providerRunStatus,
          provider_run_conclusion: evidence.providerRunConclusion,
          provider_checked_at: evidence.checkedAt,
          allowed_action: "INSPECT_PROVIDER",
        });
      }
      const mayRerun = evidence.providerRunStatus === "completed" &&
        evidence.providerRunConclusion !== null &&
        RETRYABLE_CONCLUSIONS.has(evidence.providerRunConclusion);
      if (!["DISPATCH_UNKNOWN", "DISPATCH_ACCEPTED"].includes(current.status)) {
        return Object.freeze({
          ...current,
          provider_inspection_status: "FOUND",
          provider_run_status: evidence.providerRunStatus,
          provider_run_conclusion: evidence.providerRunConclusion,
          provider_checked_at: evidence.checkedAt,
          allowed_action: current.status === "RUNNING" && mayRerun
            ? "APPROVE_RERUN"
            : "NONE",
        });
      }
      const reconciled = await dependencies.reconcile(taskId, evidence);
      return Object.freeze({
        ...reconciled,
        provider_inspection_status: "FOUND",
        provider_run_status: evidence.providerRunStatus,
        provider_run_conclusion: evidence.providerRunConclusion,
        provider_checked_at: evidence.checkedAt,
        result_code: evidence.code,
        allowed_action: mayRerun
          ? "APPROVE_RERUN"
          : evidence.providerRunStatus === "completed"
          ? "NONE"
          : "INSPECT_PROVIDER",
      });
    },

    async recover(
      taskId: string,
      expectedDispatchAttemptId: string,
      approvalId: string,
    ): Promise<Status> {
      const current = await dependencies.status(taskId);
      const binding = dispatchBinding(current);
      if (binding.attemptId !== expectedDispatchAttemptId) {
        throw new Error("WEBSITE_DELIVERY_PDF_RECOVERY_STALE");
      }
      const evidence = await dependencies.findRun(taskId, binding.startedAt);
      if (
        evidence.outcome !== "FOUND" || evidence.providerRunId === null ||
        evidence.providerRunAttempt === null ||
        evidence.providerRunStatus !== "completed" ||
        evidence.providerRunConclusion === null
      ) {
        throw new Error("WEBSITE_DELIVERY_PDF_RECOVERY_NOT_ALLOWED");
      }
      const claim = await dependencies.claimRerun(
        taskId,
        expectedDispatchAttemptId,
        evidence,
        approvalId,
      );
      if (!claim.should_rerun) return claim;
      const result = await dependencies.rerun(taskId, evidence.providerRunId);
      return await dependencies.recordRerun(taskId, approvalId, result);
    },
  });
}

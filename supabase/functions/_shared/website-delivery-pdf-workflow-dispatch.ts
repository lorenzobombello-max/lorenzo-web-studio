const TASK_ID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RUN_ID = /^[1-9][0-9]*$/;
const API = "https://api.github.com";
const OWNER = "lorenzobombello-max";
const REPOSITORY = "lorenzo-web-studio";
const REPOSITORY_ID = "1320223175";
const WORKFLOW = "convert-website-delivery-pdf.yml";
const WORKFLOW_PATH = `.github/workflows/${WORKFLOW}`;
const MAX_READBACK_BYTES = 256 * 1024;
const MAX_READBACK_PAGES = 3;
const READBACK_PAGE_SIZE = 100;
const RUN_CLOCK_SKEW_MS = 2 * 60 * 1000;

export type WebsiteDeliveryPdfDispatchResult = Readonly<{
  status: "DISPATCH_ACCEPTED" | "DISPATCH_FAILED" | "DISPATCH_UNKNOWN";
  code: string;
}>;

export type WebsiteDeliveryPdfRerunResult = Readonly<{
  status: "RERUN_ACCEPTED" | "RERUN_FAILED" | "RERUN_UNKNOWN";
  code: string;
}>;

export type WebsiteDeliveryPdfRunEvidence = Readonly<{
  outcome: "FOUND" | "UNKNOWN";
  code:
    | "DISPATCH_RUN_FOUND"
    | "DISPATCH_RUN_NOT_OBSERVED"
    | "DISPATCH_READBACK_INCOMPLETE"
    | "DISPATCH_PROVIDER_READBACK_FAILED";
  providerRunId: string | null;
  providerRunAttempt: number | null;
  providerRunStatus: string | null;
  providerRunConclusion: string | null;
  checkedAt: string;
  searchComplete: boolean;
}>;

type TokenRequest = Readonly<{
  taskId: string;
  repositoryIds: readonly ["1320223175"];
  permissions: Readonly<{ metadata: "read"; actions: "write" }>;
}>;

type Dependencies = Readonly<{
  apiUrl?: string;
  acquireToken(
    input: TokenRequest,
  ): Promise<Readonly<{ token: string; expiresAt: string }>>;
  fetch(request: Request): Promise<Response>;
  now(): number;
}>;

export class WebsiteDeliveryPdfDispatchError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "WebsiteDeliveryPdfDispatchError";
  }
}

function checkedTaskId(taskId: string): string {
  if (!TASK_ID.test(taskId)) {
    throw new WebsiteDeliveryPdfDispatchError(
      "WEBSITE_DELIVERY_PDF_DISPATCH_INPUT_INVALID",
    );
  }
  return taskId;
}

async function token(dependencies: Dependencies, taskId: string) {
  return await dependencies.acquireToken({
    taskId,
    repositoryIds: [REPOSITORY_ID],
    permissions: { metadata: "read", actions: "write" },
  });
}

function headers(accessToken: string): Headers {
  return new Headers({
    accept: "application/vnd.github+json",
    authorization: `Bearer ${accessToken}`,
    "content-type": "application/json",
    "x-github-api-version": "2022-11-28",
  });
}

function unknownEvidence(
  checkedAt: string,
  code: WebsiteDeliveryPdfRunEvidence["code"],
  searchComplete: boolean,
): WebsiteDeliveryPdfRunEvidence {
  return Object.freeze({
    outcome: "UNKNOWN",
    code,
    providerRunId: null,
    providerRunAttempt: null,
    providerRunStatus: null,
    providerRunConclusion: null,
    checkedAt,
    searchComplete,
  });
}

async function boundedText(response: Response): Promise<string> {
  const declaredLength = Number(response.headers.get("content-length") || 0);
  if (Number.isFinite(declaredLength) && declaredLength > MAX_READBACK_BYTES) {
    throw new WebsiteDeliveryPdfDispatchError(
      "WEBSITE_DELIVERY_PDF_PROVIDER_READBACK_FAILED",
    );
  }
  if (!response.body) return "";

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let bytesRead = 0;
  let text = "";
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytesRead += chunk.value.byteLength;
      if (bytesRead > MAX_READBACK_BYTES) {
        await reader.cancel();
        throw new WebsiteDeliveryPdfDispatchError(
          "WEBSITE_DELIVERY_PDF_PROVIDER_READBACK_FAILED",
        );
      }
      text += decoder.decode(chunk.value, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    reader.releaseLock();
  }
}

function matchingRun(
  candidate: unknown,
  taskId: string,
  earliestCreatedAt: number,
  latestCreatedAt: number,
): Record<string, unknown> | null {
  if (!candidate || typeof candidate !== "object") return null;
  const item = candidate as Record<string, unknown>;
  const createdAt = Date.parse(String(item.created_at || ""));
  if (
    item.event !== "workflow_dispatch" || item.head_branch !== "main" ||
    item.path !== WORKFLOW_PATH || item.display_title !== `PDF ${taskId}` ||
    !RUN_ID.test(String(item.id || "")) ||
    !Number.isSafeInteger(item.run_attempt) || Number(item.run_attempt) <= 0 ||
    !Number.isFinite(createdAt) || createdAt < earliestCreatedAt ||
    createdAt > latestCreatedAt || typeof item.status !== "string" ||
    (item.conclusion !== null && typeof item.conclusion !== "string")
  ) return null;
  return item;
}

export function createWebsiteDeliveryPdfWorkflowDispatch(
  dependencies: Dependencies,
) {
  const apiUrl = dependencies.apiUrl ?? API;
  if (dependencies.apiUrl) {
    const hostname = new URL(apiUrl).hostname;
    if (
      hostname !== "127.0.0.1" && hostname !== "localhost" &&
      hostname !== "::1"
    ) {
      throw new WebsiteDeliveryPdfDispatchError(
        "WEBSITE_DELIVERY_PDF_DISPATCH_INPUT_INVALID",
      );
    }
  }
  return Object.freeze({
    async dispatch(
      rawTaskId: string,
    ): Promise<WebsiteDeliveryPdfDispatchResult> {
      const taskId = checkedTaskId(rawTaskId);
      const lease = await token(dependencies, taskId);
      const request = new Request(
        `${apiUrl}/repos/${OWNER}/${REPOSITORY}/actions/workflows/${WORKFLOW}/dispatches`,
        {
          method: "POST",
          redirect: "manual",
          headers: headers(lease.token),
          body: JSON.stringify({ ref: "main", inputs: { task_id: taskId } }),
          signal: AbortSignal.timeout(10_000),
        },
      );
      try {
        const response = await dependencies.fetch(request);
        if (response.status === 204) {
          return { status: "DISPATCH_ACCEPTED", code: "DISPATCH_ACCEPTED" };
        }
        if (response.status >= 300 && response.status < 400) {
          return {
            status: "DISPATCH_FAILED",
            code: "DISPATCH_REDIRECT_DENIED",
          };
        }
        if (response.status === 429 || response.status >= 500) {
          return {
            status: "DISPATCH_UNKNOWN",
            code: "DISPATCH_PROVIDER_UNAVAILABLE",
          };
        }
        return { status: "DISPATCH_FAILED", code: "DISPATCH_REJECTED" };
      } catch (error) {
        return {
          status: "DISPATCH_UNKNOWN",
          code: error instanceof DOMException && error.name === "AbortError"
            ? "DISPATCH_TIMEOUT"
            : "DISPATCH_NETWORK_UNKNOWN",
        };
      }
    },

    async rerun(
      rawTaskId: string,
      rawProviderRunId: string,
    ): Promise<WebsiteDeliveryPdfRerunResult> {
      const taskId = checkedTaskId(rawTaskId);
      if (!RUN_ID.test(rawProviderRunId)) {
        throw new WebsiteDeliveryPdfDispatchError(
          "WEBSITE_DELIVERY_PDF_DISPATCH_INPUT_INVALID",
        );
      }
      const lease = await token(dependencies, taskId);
      const request = new Request(
        `${apiUrl}/repos/${OWNER}/${REPOSITORY}/actions/runs/${rawProviderRunId}/rerun`,
        {
          method: "POST",
          redirect: "manual",
          headers: headers(lease.token),
          signal: AbortSignal.timeout(10_000),
        },
      );
      try {
        const response = await dependencies.fetch(request);
        if (response.status === 201) {
          return { status: "RERUN_ACCEPTED", code: "RERUN_ACCEPTED" };
        }
        if (response.status >= 300 && response.status < 400) {
          return { status: "RERUN_FAILED", code: "RERUN_REDIRECT_DENIED" };
        }
        if (response.status === 429 || response.status >= 500) {
          return {
            status: "RERUN_UNKNOWN",
            code: "RERUN_PROVIDER_UNAVAILABLE",
          };
        }
        return { status: "RERUN_FAILED", code: "RERUN_REJECTED" };
      } catch (error) {
        return {
          status: "RERUN_UNKNOWN",
          code: error instanceof DOMException && error.name === "AbortError"
            ? "RERUN_TIMEOUT"
            : "RERUN_NETWORK_UNKNOWN",
        };
      }
    },

    async findRun(
      rawTaskId: string,
      dispatchStartedAt: string,
    ): Promise<WebsiteDeliveryPdfRunEvidence> {
      const taskId = checkedTaskId(rawTaskId);
      const dispatchStartedAtMs = Date.parse(dispatchStartedAt);
      const checkedAtMs = dependencies.now();
      if (
        !Number.isFinite(dispatchStartedAtMs) ||
        dispatchStartedAtMs > checkedAtMs + RUN_CLOCK_SKEW_MS
      ) {
        throw new WebsiteDeliveryPdfDispatchError(
          "WEBSITE_DELIVERY_PDF_DISPATCH_INPUT_INVALID",
        );
      }
      const checkedAt = new Date(checkedAtMs).toISOString();
      const lease = await token(dependencies, taskId);
      const url = new URL(
        `${apiUrl}/repos/${OWNER}/${REPOSITORY}/actions/workflows/${WORKFLOW}/runs`,
      );
      url.searchParams.set("event", "workflow_dispatch");
      url.searchParams.set("branch", "main");
      url.searchParams.set("per_page", String(READBACK_PAGE_SIZE));
      let observed = 0;
      for (let page = 1; page <= MAX_READBACK_PAGES; page += 1) {
        url.searchParams.set("page", String(page));
        let response: Response;
        try {
          response = await dependencies.fetch(
            new Request(url, {
              method: "GET",
              redirect: "manual",
              headers: headers(lease.token),
              signal: AbortSignal.timeout(10_000),
            }),
          );
        } catch {
          return unknownEvidence(
            checkedAt,
            "DISPATCH_PROVIDER_READBACK_FAILED",
            false,
          );
        }
        if (response.status !== 200) {
          throw new WebsiteDeliveryPdfDispatchError(
            "WEBSITE_DELIVERY_PDF_PROVIDER_READBACK_FAILED",
          );
        }
        let value: unknown;
        try {
          value = JSON.parse(await boundedText(response));
        } catch {
          return unknownEvidence(
            checkedAt,
            "DISPATCH_PROVIDER_READBACK_FAILED",
            false,
          );
        }
        const record = value && typeof value === "object"
          ? value as Record<string, unknown>
          : null;
        const runs = record && Array.isArray(record.workflow_runs)
          ? record.workflow_runs
          : null;
        if (!record || !runs) {
          return unknownEvidence(
            checkedAt,
            "DISPATCH_PROVIDER_READBACK_FAILED",
            false,
          );
        }
        const run = runs.map((candidate) =>
          matchingRun(
            candidate,
            taskId,
            dispatchStartedAtMs - RUN_CLOCK_SKEW_MS,
            checkedAtMs + RUN_CLOCK_SKEW_MS,
          )
        ).find((candidate) => candidate !== null);
        if (run) {
          return Object.freeze({
            outcome: "FOUND",
            code: "DISPATCH_RUN_FOUND",
            providerRunId: String(run.id),
            providerRunAttempt: Number(run.run_attempt),
            providerRunStatus: String(run.status),
            providerRunConclusion: run.conclusion === null
              ? null
              : String(run.conclusion),
            checkedAt,
            searchComplete: true,
          });
        }
        if (!Number.isSafeInteger(record.total_count) ||
          Number(record.total_count) < 0) {
          return unknownEvidence(
            checkedAt,
            "DISPATCH_READBACK_INCOMPLETE",
            false,
          );
        }
        observed += runs.length;
        if (observed >= Number(record.total_count) ||
          runs.length < READBACK_PAGE_SIZE) {
          return unknownEvidence(
            checkedAt,
            "DISPATCH_RUN_NOT_OBSERVED",
            true,
          );
        }
      }
      return unknownEvidence(
        checkedAt,
        "DISPATCH_READBACK_INCOMPLETE",
        false,
      );
    },
  });
}

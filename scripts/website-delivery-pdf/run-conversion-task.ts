import { runWebsiteDeliveryPdfConversionOverHttp } from "./conversion-task-http-runner.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DIGITS = /^[1-9][0-9]*$/;
const AUDIENCE = "lws-website-delivery-pdf-conversion";

function required(name: string): string {
  const value = Deno.env.get(name)?.trim() ?? "";
  if (!value) throw new Error("WEBSITE_DELIVERY_PDF_WORKFLOW_INPUT_INVALID");
  return value;
}

export async function runConversionTaskFromEnvironment(
  fetcher: typeof fetch = fetch,
): Promise<unknown> {
  const taskId = required("LWS_DELIVERY_PDF_TASK_ID");
  const workflowRunId = required("GITHUB_RUN_ID");
  const workflowRunAttempt = required("GITHUB_RUN_ATTEMPT");
  const endpoint = required("LWS_DELIVERY_PDF_CONVERSION_ENDPOINT");
  if (
    !UUID.test(taskId) || !DIGITS.test(workflowRunId) ||
    !DIGITS.test(workflowRunAttempt)
  ) {
    throw new Error("WEBSITE_DELIVERY_PDF_WORKFLOW_INPUT_INVALID");
  }
  const endpointUrl = new URL(endpoint);
  if (endpointUrl.protocol !== "https:") {
    throw new Error("WEBSITE_DELIVERY_PDF_WORKFLOW_INPUT_INVALID");
  }
  const oidcUrl = new URL(required("ACTIONS_ID_TOKEN_REQUEST_URL"));
  oidcUrl.searchParams.set("audience", AUDIENCE);
  const oidcResponse = await fetcher(oidcUrl, {
    headers: {
      authorization: `Bearer ${required("ACTIONS_ID_TOKEN_REQUEST_TOKEN")}`,
    },
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  const oidcBody = await oidcResponse.json().catch(() => null) as
    | { value?: unknown }
    | null;
  if (
    !oidcResponse.ok || typeof oidcBody?.value !== "string" ||
    !oidcBody.value
  ) {
    throw new Error("WEBSITE_DELIVERY_PDF_OIDC_ACQUISITION_FAILED");
  }
  return await runWebsiteDeliveryPdfConversionOverHttp({
    endpoint: endpointUrl.toString(),
    taskId,
    workflowRunId,
    workflowRunAttempt,
    oidcToken: oidcBody.value,
    idempotencyKey: taskId,
  }, { fetch: fetcher });
}

if (import.meta.main) {
  await runConversionTaskFromEnvironment();
}

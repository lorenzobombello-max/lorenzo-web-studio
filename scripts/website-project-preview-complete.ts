function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("COMPLETION_ENVIRONMENT_INCOMPLETE");
  return value;
}

export async function completePreviewWorkflow() {
  const event = JSON.parse(await Deno.readTextFile(required("GITHUB_EVENT_PATH")));
  const run = event.workflow_run;
  const binding = String(run?.display_title ?? "").match(/^LWS preview lease=([0-9a-f-]{36}) build=([0-9a-f-]{36})$/);
  if (!binding || !Number.isSafeInteger(run.id) || run.id <= 0) throw new Error("COMPLETION_EVENT_INVALID");
  const oidcUrl = new URL(required("ACTIONS_ID_TOKEN_REQUEST_URL"));
  oidcUrl.searchParams.set("audience", required("LWS_PREVIEW_COMPLETION_OIDC_AUDIENCE"));
  const oidcResponse = await fetch(oidcUrl, {
    redirect: "error", signal: AbortSignal.timeout(10000),
    headers: { authorization: `Bearer ${required("ACTIONS_ID_TOKEN_REQUEST_TOKEN")}` },
  });
  if (!oidcResponse.ok) throw new Error("COMPLETION_OIDC_UNAVAILABLE");
  const oidc = await oidcResponse.json();
  if (typeof oidc.value !== "string" || !oidc.value) throw new Error("COMPLETION_OIDC_UNAVAILABLE");
  const response = await fetch(required("LWS_PREVIEW_COMPLETION_ENDPOINT"), {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(60000),
    headers: { authorization: `Bearer ${oidc.value}`, "content-type": "application/json" },
    body: JSON.stringify({ leaseId: binding[1], buildId: binding[2],
      workflowRunId: String(run.id), monitorRunId: required("GITHUB_RUN_ID") }),
  });
  if (!response.ok) { await response.body?.cancel(); throw new Error("COMPLETION_NOT_CONFIRMED"); }
  const result = await response.json();
  if (result.ok !== true || !["PASS", "PASS_WITH_WARNINGS", "FAILED"].includes(result.state)) {
    throw new Error("COMPLETION_NOT_CONFIRMED");
  }
  console.log(JSON.stringify({ state: result.state }));
}
if (import.meta.main) await completePreviewWorkflow();

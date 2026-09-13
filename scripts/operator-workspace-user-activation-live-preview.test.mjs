import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import test from "node:test";
import { chromium } from "@playwright/test";

const root = new URL("../", import.meta.url);
const rootPath = decodeURIComponent(root.pathname).replace(/^\/(?:([A-Za-z]:))/, "$1");
const workspaceId = "a1900000-0000-4000-8000-000000000001";
const renewalToken = "a1900000-0000-4000-8000-000000000002";
const quoteRequestId = "a1900000-0000-4000-8000-000000000003";
const conceptId = "a1900000-0000-4000-8000-000000000004";
const contextId = "a1900000-0000-4000-8000-000000000005";

const masterHarness = `<!doctype html><html><body><button id="open-website">Open website</button><script type="module">
const workspaceId = "${workspaceId}";
window.metrics = { received: false, receivedActivation: null, opens: [] };
const nativeOpen = window.open.bind(window);
window.open = (...args) => {
  const slot = new URL(args[0], location.href).hash.match(/(?:^|&)slot=([^&]+)/)?.[1] || "";
  const reference = nativeOpen(...args);
  window.metrics.opens.push({ slot: decodeURIComponent(slot), isActive: navigator.userActivation.isActive, hasBeenActive: navigator.userActivation.hasBeenActive, returnedReference: Boolean(reference) });
  return reference;
};
const client = { async rpc(name) { if (name === "acquire_operator_workspace_v1") return { data: { acquired: true, workspace_id: workspaceId, epoch: 1, renewal_token: "${renewalToken}", lease_expires_at: new Date(Date.now() + 60_000).toISOString() }, error: null }; return { data: { valid: true, lease_expires_at: new Date(Date.now() + 60_000).toISOString() }, error: null }; } };
const { workspaceChannelName } = await import('/assets/js/operator-workspace-protocol.mjs');
const observer = new BroadcastChannel(workspaceChannelName(workspaceId, 1));
observer.addEventListener("message", (event) => { if (event.data?.type === "OPEN_REQUEST") { window.metrics.received = true; window.metrics.receivedActivation = { isActive: navigator.userActivation.isActive, hasBeenActive: navigator.userActivation.hasBeenActive }; } });
const { createOperatorWorkspaceMaster } = await import('/assets/js/operator-workspace-master.mjs');
window.master = await createOperatorWorkspaceMaster({ client, setIntervalFn: () => 1, clearIntervalFn() {} });
window.master.bindModuleButton(document.querySelector('#open-website'), 'dossiers', 'website-${quoteRequestId}');
</script></body></html>`;

const childHarness = `<!doctype html><html><head><link rel="stylesheet" href="/assets/css/operator-dashboard.css"></head><body><main data-dossiers-workspace></main><script type="module">
window.opener = null;
const NativeBroadcastChannel = window.BroadcastChannel;
window.BroadcastChannel = class extends NativeBroadcastChannel {
  postMessage(value) {
    if (value?.type === "OPEN_REQUEST") {
      setTimeout(() => NativeBroadcastChannel.prototype.postMessage.call(this, value), 6_000);
      return;
    }
    NativeBroadcastChannel.prototype.postMessage.call(this, value);
  }
};
const quoteRequestId = "${quoteRequestId}";
const detail = { quote_request_id: quoteRequestId, request_kind: "website", application_reference: "LWS-AAN-2099-0001", project: null, website_work: { state: "PRE_PROJECT", quote_request_id: quoteRequestId, concept_id: "${conceptId}", project_id: null, website_work_context_id: "${contextId}", mode: "PRE_PROJECT", briefing_status: "COMPLETE", commercially_released: false, revision: 1, permitted_actions: ["OPEN_WEBSITE"] } };
const projection = { contract_version: 2, mode: "PRE_PROJECT", quote_request_id: quoteRequestId, concept_id: "${conceptId}", project_id: null, website_work_context_id: "${contextId}", context_revision: 1, briefing_status: "COMPLETE", commercially_released: false, project: null, start_gate: null, workspace: null, requirements: { state: "NOT_AVAILABLE", message: "Requirements volgen na intake-sync." } };
const gateway = { functions: { async invoke(_name, { body }) { let result; if (body.action === "get_application_detail") result = detail; else if (body.action === "get_dossier_substance") result = { customer: { name: "Preview customer" } }; else if (body.action === "get_website_execution_workspace") result = projection; else if (body.action === "get_dossier_assignment") result = { assignee_display_name: "Operator A" }; return { data: { ok: true, result }, error: null }; } }, async rpc() { return { data: { valid: true, lease_expires_at: new Date(Date.now() + 60_000).toISOString() }, error: null }; } };
const { parseChildBootstrap } = await import('/assets/js/operator-workspace-protocol.mjs');
const { createOperatorWorkspaceChild } = await import('/assets/js/operator-workspace-child.mjs');
const bootstrap = parseChildBootstrap(location.href, location.origin);
const workspaceChild = createOperatorWorkspaceChild({ client: gateway, bootstrap, joinedWorkspace: { lease_expires_at: new Date(Date.now() + 60_000).toISOString() }, setIntervalFn: () => 1, clearIntervalFn() {} });
window.metrics = { clickActivation: null, openRequestSent: false, registered: false };
if (bootstrap.slotKey.startsWith('website-')) {
  const { initializeOperatorWebsiteExecution } = await import('/assets/js/operator-website-execution-child.mjs');
  window.controller = initializeOperatorWebsiteExecution(document, gateway, { role: "owner", status: "ACTIVE" }, { slotKey: bootstrap.slotKey, requestOpen(moduleKey, slotKey) { window.metrics.openRequestSent = true; return workspaceChild.requestOpen(moduleKey, slotKey); }, onAuthorizationFailure() {} });
  document.addEventListener('click', (event) => { if (event.target.closest?.('[data-website-action="requirements"]')) window.metrics.clickActivation = { isActive: navigator.userActivation.isActive, hasBeenActive: navigator.userActivation.hasBeenActive }; }, true);
} else if (bootstrap.slotKey.startsWith('req-')) {
  const { initializeOperatorProjectRequirements } = await import('/assets/js/operator-project-requirements-child.mjs');
  window.controller = initializeOperatorProjectRequirements(document, gateway, { role: "owner", status: "ACTIVE" }, { slotKey: bootstrap.slotKey, requestOpen: workspaceChild.requestOpen, onAuthorizationFailure() {} });
  window.metrics.registered = true;
}
</script></body></html>`;

function serve() {
  const server = createServer(async (request, response) => {
    if (request.url === "/__master-harness") {
      response.setHeader("content-type", "text/html; charset=utf-8");
      response.end(masterHarness);
      return;
    }
    if (request.url?.startsWith("/operator/window/")) {
      response.setHeader("content-type", "text/html; charset=utf-8");
      response.end(childHarness);
      return;
    }
    const relative = normalize(decodeURIComponent(request.url.split("?")[0])).replace(/^[/\\]+/, "");
    if (relative.includes("..")) { response.writeHead(403).end(); return; }
    try {
      const body = await readFile(join(rootPath, relative));
      response.setHeader("content-type", extname(relative) === ".mjs" ? "text/javascript" : "text/css");
      response.end(body);
    } catch { response.writeHead(404).end(); }
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

test("real browser hands a user-gesture reservation to the managed sibling owner", async () => {
  const server = await serve();
  const browser = await chromium.launch({ headless: false, ignoreDefaultArgs: ["--disable-popup-blocking"] });
  const context = await browser.newContext();
  const master = await context.newPage();
  try {
    const address = server.address();
    await master.goto(`http://127.0.0.1:${address.port}/__master-harness`);
    const websitePromise = master.waitForEvent("popup");
    await master.getByRole("button", { name: "Open website" }).click();
    const website = await websitePromise;
    await website.getByRole("button", { name: "Takenbord openen" }).waitFor();
    await website.evaluate(({ workspaceId, quoteRequestId }) => {
      window.__legacyOpenChannel = new BroadcastChannel(`lws-operator-workspace-v1:${workspaceId}:1`);
      window.__legacyOpenChannel.postMessage({
        type: "OPEN_REQUEST",
        workspaceId,
        epoch: 1,
        senderWindowId: "a1900000-0000-4000-8000-000000000006",
        sequence: 100,
        timestamp: Date.now(),
        moduleKey: "dossiers",
        slotKey: `req-${quoteRequestId}`,
      });
    }, { workspaceId, quoteRequestId });
    await master.waitForFunction(() => window.metrics.opens.some((entry) => entry.slot.startsWith("req-")), null, { timeout: 8_000 });
    const legacyMetrics = await master.evaluate(() => window.metrics);
    const legacyBlocked = legacyMetrics.opens.some((entry) => entry.slot.startsWith("req-") && !entry.returnedReference);
    console.log(`REAL_BROWSER_ASYNC_OPEN_REQUEST_BLOCKED_BEFORE_FIX=${legacyBlocked ? "PASS_AS_EXPECTED" : "FAIL"}`);
    assert.equal(legacyBlocked, true);
    const reservationPromise = context.waitForEvent("page", { timeout: 2_000 }).catch(() => null);
    await website.getByRole("button", { name: "Takenbord openen" }).click();
    const requirements = await reservationPromise;
    let requirementsRegistered = false;
    try {
      await requirements?.waitForURL(/slot=req-/, { timeout: 8_000 });
      requirementsRegistered = true;
    } catch {}
    const websiteMetrics = await website.evaluate(() => window.metrics);
    const masterMetrics = await master.evaluate(() => window.metrics);
    console.log(`USER_ACTIVATION_AT_CLICK=${JSON.stringify(websiteMetrics.clickActivation)}`);
    console.log(`OPEN_REQUEST_SENT=${websiteMetrics.openRequestSent}`);
    console.log(`MASTER_RECEIVED=${masterMetrics.received}`);
    console.log(`USER_ACTIVATION_AT_MASTER_OPEN=${JSON.stringify(masterMetrics.receivedActivation)}`);
    console.log(`WINDOW_OPEN_ATTEMPTED=${masterMetrics.opens.some((entry) => entry.slot.startsWith("req-"))}`);
    console.log(`WINDOW_OPEN_RETURNED_REFERENCE=${masterMetrics.opens.some((entry) => entry.slot.startsWith("req-") && entry.returnedReference)}`);
    console.log(`POPUP_BLOCKED=${!masterMetrics.opens.some((entry) => entry.slot.startsWith("req-") && entry.returnedReference)}`);
    console.log(`REQUIREMENTS_CHILD_REGISTERED=${requirementsRegistered}`);
    console.log(`USER_GESTURE_HANDOFF_VALID=${requirementsRegistered ? "PASS" : "FAIL"}`);
    console.log(`MASTER_OWNS_CHILD_REFERENCE=${masterMetrics.opens.some((entry) => entry.slot.startsWith("req-") && entry.returnedReference) ? "PASS" : "FAIL"}`);
    assert.ok(requirementsRegistered, "REQUIREMENTS_POPUP_BLOCKED_AFTER_ASYNC_OPEN_REQUEST");
  } finally {
    await context.close();
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});
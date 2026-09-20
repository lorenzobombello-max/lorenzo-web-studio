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

const masterHarness = `<!doctype html><html><body><section data-dossiers-workspace data-zone="ACTIVE"><h1>Actief dossier</h1><button data-dossiers-website-open data-operator-window-module="dossiers" data-operator-window-slot="website-${quoteRequestId}">WEBSITE OPENEN</button></section><script type="module">
const workspaceId = "${workspaceId}";
window.metrics = { received: false, receivedActivation: null, opens: [], rpc: [] };
const nativeOpen = window.open.bind(window);
window.open = (...args) => {
  const reference = nativeOpen(...args);
  window.metrics.opens.push({ url: args[0], name: args[1], isActive: navigator.userActivation.isActive, hasBeenActive: navigator.userActivation.hasBeenActive, returnedReference: Boolean(reference) });
  return reference;
};
const client = { async rpc(name) { window.metrics.rpc.push(name); if (name === "acquire_operator_workspace_v1") return { data: { acquired: true, workspace_id: workspaceId, epoch: 1, renewal_token: "${renewalToken}", lease_expires_at: new Date(Date.now() + 60_000).toISOString() }, error: null }; return { data: { valid: true, lease_expires_at: new Date(Date.now() + 60_000).toISOString() }, error: null }; } };
const { workspaceChannelName } = await import('/assets/js/operator-workspace-protocol.mjs');
const observer = new BroadcastChannel(workspaceChannelName(workspaceId, 1));
observer.addEventListener("message", (event) => { if (event.data?.type === "OPEN_REQUEST") { window.metrics.received = true; window.metrics.receivedActivation = { isActive: navigator.userActivation.isActive, hasBeenActive: navigator.userActivation.hasBeenActive }; } });
const { createOperatorWorkspaceMaster } = await import('/assets/js/operator-workspace-master.mjs');
window.master = await createOperatorWorkspaceMaster({ client, setIntervalFn: () => 1, clearIntervalFn() {} });
const websiteLauncher = document.querySelector('[data-dossiers-website-open]');
window.master.bindModuleButton(websiteLauncher, websiteLauncher.dataset.operatorWindowModule, websiteLauncher.dataset.operatorWindowSlot);
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
const projection = { contract_version: 3, mode: "PRE_PROJECT", quote_request_id: quoteRequestId, concept_id: "${conceptId}", project_id: null, website_work_context_id: "${contextId}", context_revision: 1, briefing_status: "COMPLETE", commercially_released: false, project: null, start_gate: null, workspace: null, requirements: { state: "NOT_AVAILABLE", message: "Requirements volgen na intake-sync." } };
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

test("active Dossiers Website launcher reserves synchronously and navigates only after server renewal", async () => {
  const server = await serve();
  const browser = await chromium.launch({ headless: false, ignoreDefaultArgs: ["--disable-popup-blocking"] });
  const context = await browser.newContext();
  const childErrors = [];
  context.on("page", (page) => page.on("pageerror", (error) => childErrors.push(error.message)));
  const master = await context.newPage();
  try {
    const address = server.address();
    await master.goto(`http://127.0.0.1:${address.port}/__master-harness`);
    const websitePromise = master.waitForEvent("popup");
    await master.getByRole("button", { name: "WEBSITE OPENEN" }).click();
    const website = await websitePromise;
    await website.waitForURL(/module=dossiers.*slot=website-/, { timeout: 8_000 });
    await website.getByRole("button", { name: "Requirements openen" }).waitFor({ timeout: 8_000 }).catch(async () => {
      throw new Error(`WEBSITE_CHILD_NOT_MOUNTED url=${website.url()} errors=${childErrors.join(" | ") || "none"} body=${(await website.locator("body").innerText()).slice(0, 500)}`);
    });
    const websiteUrl = new URL(website.url());
    const masterLaunchMetrics = await master.evaluate(() => window.metrics);
    assert.equal(masterLaunchMetrics.opens.length, 1);
    assert.equal(masterLaunchMetrics.opens[0].url, "about:blank");
    assert.equal(masterLaunchMetrics.opens[0].returnedReference, true);
    assert.deepEqual(masterLaunchMetrics.rpc.slice(0, 2), ["acquire_operator_workspace_v1", "renew_operator_workspace_lease_v1"]);
    assert.equal(websiteUrl.searchParams.get("module"), "dossiers");
    assert.equal(new URLSearchParams(websiteUrl.hash.slice(1)).get("slot"), `website-${quoteRequestId}`);
    const reservationPromise = context.waitForEvent("page", { timeout: 2_000 }).catch(() => null);
    await website.getByRole("button", { name: "Requirements openen" }).click();
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
    console.log(`REQUIREMENTS_CHILD_REGISTERED=${requirementsRegistered}`);
    console.log(`USER_GESTURE_HANDOFF_VALID=${requirementsRegistered ? "PASS" : "FAIL"}`);
    assert.ok(requirementsRegistered, "REQUIREMENTS_POPUP_BLOCKED_AFTER_ASYNC_OPEN_REQUEST");
  } finally {
    await context.close();
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});
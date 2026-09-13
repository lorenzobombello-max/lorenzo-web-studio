import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import test from "node:test";
import { chromium } from "@playwright/test";

const root = new URL("../", import.meta.url);
const rootPath = decodeURIComponent(root.pathname).replace(/^\/(?:([A-Za-z]:))/, "$1");
const quoteRequestId = "a1800000-0000-4000-8000-000000000001";
const conceptId = "a1800000-0000-4000-8000-000000000004";
const contextId = "a1800000-0000-4000-8000-000000000005";

const shared = `
const quoteRequestId = "${quoteRequestId}";
const detail = { quote_request_id: quoteRequestId, request_kind: "website", application_reference: "LWS-AAN-2099-0001", project: null, website_work: { state: "PRE_PROJECT", quote_request_id: quoteRequestId, concept_id: "${conceptId}", project_id: null, website_work_context_id: "${contextId}", mode: "PRE_PROJECT", briefing_status: "COMPLETE", commercially_released: false, revision: 1, permitted_actions: ["OPEN_WEBSITE"] } };
const projection = { contract_version: 2, mode: "PRE_PROJECT", quote_request_id: quoteRequestId, concept_id: "${conceptId}", project_id: null, website_work_context_id: "${contextId}", context_revision: 1, briefing_status: "COMPLETE", commercially_released: false, project: null, start_gate: null, workspace: null, requirements: { state: "NOT_AVAILABLE", message: "Requirements volgen na intake-sync." } };
window.gatewayActions = [];
const client = { functions: { async invoke(_name, { body }) { window.gatewayActions.push(body.action); let result; if (body.action === "get_application_detail") result = detail; else if (body.action === "get_dossier_substance") result = { customer: { name: "Preview customer" } }; else if (body.action === "get_website_execution_workspace") result = projection; else if (body.action === "get_dossier_assignment") result = { assignee_display_name: "Operator A" }; return { data: { ok: true, result }, error: null }; } } };
`;

const websiteHarness = `<!doctype html><html><head><link rel="stylesheet" href="/assets/css/operator-dashboard.css"></head><body><main data-dossiers-workspace></main><script type="module">
window.setInterval = () => 1; window.clearInterval = () => {};
${shared}
let requirementsChild = null;
window.metrics = { created: 0, focused: 0, projectFiles: 0, requests: [] };
const requestOpen = (moduleKey, slotKey) => { window.metrics.requests.push({ moduleKey, slotKey }); if (slotKey === 'main') { window.metrics.projectFiles += 1; return true; } if (requirementsChild && !requirementsChild.closed) { requirementsChild.focus(); window.metrics.focused += 1; return true; } requirementsChild = window.open('/__requirements-harness', 'lws-test-requirements', 'popup'); window.metrics.created += 1; requirementsChild?.focus(); return Boolean(requirementsChild); };
const { initializeOperatorWebsiteExecution } = await import('/assets/js/operator-website-execution-child.mjs');
window.controller = initializeOperatorWebsiteExecution(document, client, { role: "owner", status: "ACTIVE" }, { slotKey: "website-${quoteRequestId}", requestOpen, onAuthorizationFailure() {} });
window.snapshot = () => ({ visible: !document.querySelector('[data-website-content]')?.hidden, buttonVisible: !document.querySelector('[data-website-action="requirements"]')?.hidden, mode: document.querySelector('[data-website-mode]')?.textContent, dossier: document.querySelector('[data-website-context="dossier"]')?.textContent });
window.invalidFrames = 0; new MutationObserver(() => { const value = window.snapshot(); if (!value.visible || value.mode !== 'Voorlopig concept' || value.dossier !== 'LWS-AAN-2099-0001') window.invalidFrames += 1; }).observe(document.body, { childList: true, subtree: true, attributes: true, characterData: true });
</script></body></html>`;

const requirementsHarness = `<!doctype html><html><head><link rel="stylesheet" href="/assets/css/operator-dashboard.css"></head><body><main data-dossiers-workspace></main><script type="module">
window.setInterval = () => 1; window.clearInterval = () => {};
${shared}
const { initializeOperatorProjectRequirements } = await import('/assets/js/operator-project-requirements-child.mjs');
window.controller = initializeOperatorProjectRequirements(document, client, { role: "owner", status: "ACTIVE" }, { slotKey: "req-${quoteRequestId}", onAuthorizationFailure() {} });
window.snapshot = () => ({ message: document.querySelector('[data-requirements-empty]')?.textContent, dossier: document.querySelector('[data-requirements-context="dossier"]')?.textContent, project: document.querySelector('[data-requirements-context="project"]')?.textContent, contentVisible: !document.querySelector('[data-requirements-content]')?.hidden });
window.contextDrift = 0; new MutationObserver(() => { const value = window.snapshot(); if (value.contentVisible && (value.dossier !== 'LWS-AAN-2099-0001' || value.project !== 'Niet van toepassing')) window.contextDrift += 1; }).observe(document.body, { childList: true, subtree: true, attributes: true, characterData: true });
</script></body></html>`;

function serve() {
  const server = createServer(async (request, response) => {
    if (request.url === "/__website-harness") {
      response.setHeader("content-type", "text/html; charset=utf-8");
      response.end(websiteHarness);
      return;
    }
    if (request.url === "/__requirements-harness") {
      response.setHeader("content-type", "text/html; charset=utf-8");
      response.end(requirementsHarness);
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

test("Website Execution opens and focuses one PRE_PROJECT Requirements managed sibling", async () => {
  const server = await serve();
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  try {
    const address = server.address();
    await page.goto(`http://127.0.0.1:${address.port}/__website-harness`);
    await page.waitForFunction(() => window.snapshot?.().mode === "Voorlopig concept");
    const button = page.getByRole("button", { name: "Takenbord openen" });
    assert.equal(await button.isVisible(), true);
    const popupPromise = page.waitForEvent("popup");
    await button.click();
    const requirements = await popupPromise;
    await requirements.waitForFunction(() => window.snapshot?.().contentVisible === true);
    assert.deepEqual(await requirements.evaluate(() => window.snapshot()), {
      message: "Requirements volgen na intake-sync.",
      dossier: "LWS-AAN-2099-0001",
      project: "Niet van toepassing",
      contentVisible: true,
    });
    const requirementsActions = await requirements.evaluate(() => window.gatewayActions);
    assert.equal(requirementsActions.includes("get_website_execution_workspace"), true);
    assert.equal(requirementsActions.includes("get_project_requirements_board"), false);
    await button.click();
    await page.getByRole("button", { name: "Projectbestanden" }).click();
    assert.deepEqual(await page.evaluate(() => window.metrics), {
      created: 1,
      focused: 1,
      projectFiles: 1,
      requests: [
        { moduleKey: "dossiers", slotKey: `req-${quoteRequestId}` },
        { moduleKey: "dossiers", slotKey: `req-${quoteRequestId}` },
        { moduleKey: "dossiers", slotKey: "main" },
      ],
    });
    for (let cycle = 0; cycle < 3; cycle += 1) {
      await page.waitForTimeout(8_000);
      await Promise.all([
        page.evaluate(() => window.controller.refresh({ background: true })),
        requirements.evaluate(() => window.controller.refresh({ background: true })),
      ]);
    }
    assert.equal(await page.evaluate(() => window.invalidFrames), 0);
    assert.equal(await requirements.evaluate(() => window.contextDrift), 0);
    assert.deepEqual(errors, []);
    console.log("WEBSITE_EXECUTION_REQUIREMENTS_BUTTON_WIRED=PASS");
    console.log("PRE_PROJECT_REQUIREMENTS_CONTEXT_MATCH=PASS");
    console.log("REQUIREMENTS_MANAGED_SIBLING_OPEN=PASS");
    console.log("REQUIREMENTS_EXISTING_CHILD_FOCUSED=PASS");
    console.log("REQUIREMENTS_DUPLICATE_CHILD_COUNT=0");
    console.log("WEBSITE_EXECUTION_INVALID_FRAMES=0");
    console.log("REQUIREMENTS_CONTEXT_DRIFT=0");
    console.log("PROJECTBESTANDEN_REGRESSION=PASS");
    console.log("PROJECT_ID_REQUIRED=NEE");
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});
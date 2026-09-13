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

const harness = `<!doctype html><html><body><main data-dossiers-workspace></main><script type="module">
window.setInterval = () => 1;
window.clearInterval = () => {};
const quoteRequestId = "${quoteRequestId}";
const conceptId = "${conceptId}";
const contextId = "${contextId}";
const detail = { quote_request_id: quoteRequestId, request_kind: "website", name: "Preview customer", application_reference: "LWS-AAN-2099-0001", website_work: { state: "PRE_PROJECT", quote_request_id: quoteRequestId, concept_id: conceptId, project_id: null, website_work_context_id: contextId, mode: "PRE_PROJECT", briefing_status: "COMPLETE", commercially_released: false, revision: 1, permitted_actions: ["OPEN_WEBSITE"] } };
const projection = { contract_version: 2, mode: "PRE_PROJECT", quote_request_id: quoteRequestId, concept_id: conceptId, project_id: null, website_work_context_id: contextId, context_revision: 1, briefing_status: "COMPLETE", commercially_released: false, project: null, start_gate: null, workspace: null, requirements: { state: "NOT_AVAILABLE", message: "Requirements volgen na intake-sync." } };
let phase = 0;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const client = { functions: { async invoke(_name, { body }) {
  if (phase === 1) await pause(55);
  if (phase === 2) throw new Error("NETWORK_FAILURE");
  if (phase === 4) return { data: { ok: false, code: "OPERATOR_NOT_AUTHORIZED" }, error: null };
  let result;
  if (body.action === "get_application_detail") result = detail;
  else if (body.action === "get_dossier_substance") result = { customer: { name: "Preview customer" } };
  else if (body.action === "get_website_execution_workspace") result = phase === 3 ? { ...projection, unknown: true } : projection;
  else if (body.action === "get_dossier_assignment") result = { assignee_display_name: "Operator A" };
  return { data: { ok: true, result }, error: null };
} } };
const { initializeOperatorWebsiteExecution } = await import("/assets/js/operator-website-execution-child.mjs");
window.controller = initializeOperatorWebsiteExecution(document, client, { role: "owner", status: "ACTIVE" }, { slotKey: "website-${quoteRequestId}", onAuthorizationFailure() {} });
window.runPhase = async (next) => { phase = next; window.phaseDone = false; const result = await window.controller.refresh({ background: true }); window.phaseDone = true; return result; };
window.snapshot = () => ({
  contentHidden: document.querySelector("[data-website-content]")?.hidden,
  mode: document.querySelector("[data-website-mode]")?.textContent,
  briefing: document.querySelector("[data-website-briefing]")?.textContent,
  release: document.querySelector("[data-website-release]")?.textContent,
  repository: document.querySelector('[data-website-field="repository"]')?.textContent,
  requirements: document.querySelector("[data-website-requirements-empty]")?.textContent,
  overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
});
window.mutations = [];
new MutationObserver(() => window.mutations.push(window.snapshot())).observe(document.body, { childList: true, subtree: true, attributes: true, characterData: true });
</script></body></html>`;

function serve() {
  const server = createServer(async (request, response) => {
    if (request.url === "/__website-concept-harness") {
      response.setHeader("content-type", "text/html; charset=utf-8");
      response.end(harness);
      return;
    }
    const relative = normalize(decodeURIComponent(request.url.split("?")[0])).replace(/^[/\\]+/, "");
    if (relative.includes("..")) { response.writeHead(403).end(); return; }
    try {
      const body = await readFile(join(rootPath, relative));
      response.setHeader("content-type", extname(relative) === ".mjs" ? "text/javascript" : "application/octet-stream");
      response.end(body);
    } catch { response.writeHead(404).end(); }
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

async function samplePhase(page, phase) {
  await page.evaluate((value) => { void window.runPhase(value); }, phase);
  const samples = [];
  for (let index = 0; index < 8; index += 1) {
    await page.waitForTimeout(16);
    samples.push(await page.evaluate(() => window.snapshot()));
  }
  await page.waitForFunction(() => window.phaseDone === true);
  samples.push(await page.evaluate(() => window.snapshot()));
  return samples;
}

for (const viewport of [{ width: 1280, height: 800 }, { width: 390, height: 844 }]) {
  test(`PRE_PROJECT frames remain stable at ${viewport.width}px`, async () => {
    const server = await serve();
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport });
    const errors = [];
    page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
    page.on("pageerror", (error) => errors.push(error.message));
    try {
      const address = server.address();
      await page.goto(`http://127.0.0.1:${address.port}/__website-concept-harness`);
      await page.waitForFunction(() => window.snapshot?.().mode === "Voorlopig concept");
      for (const phase of [1, 2, 3]) {
        const samples = await samplePhase(page, phase);
        for (const snapshot of samples) {
          assert.equal(snapshot.contentHidden, false);
          assert.equal(snapshot.mode, "Voorlopig concept");
          assert.equal(snapshot.briefing, "COMPLETE");
          assert.equal(snapshot.release, "Niet commercieel vrijgegeven");
          assert.equal(snapshot.repository, "Repository niet gekoppeld");
          assert.equal(snapshot.requirements, "Requirements volgen na intake-sync.");
          assert.equal(snapshot.overflow, false);
        }
      }
      await page.evaluate(() => { void window.runPhase(4); });
      await page.waitForFunction(() => document.querySelector("[data-website-content]")?.hidden === true);
      assert.deepEqual(errors, []);
    } finally {
      await browser.close();
      await new Promise((resolve) => server.close(resolve));
    }
  });
}

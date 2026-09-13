import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import test from "node:test";
import { chromium } from "@playwright/test";

const root = new URL("../", import.meta.url);
const rootPath = decodeURIComponent(root.pathname).replace(/^\/(?:([A-Za-z]:))/, "$1");
const quoteRequestId = "a1800000-0000-4000-8000-000000000001";

const harness = `<!doctype html><html><body>
<section data-pricing><strong data-minimum></strong><span data-final></span></section>
<section data-project>Project actief</section><section data-website-work>PRE_PROJECT / CONCEPT</section>
<script type="module">
const { retainWebsiteQuotationAuthorities, websiteQuotationPricingPresentation } = await import("/assets/js/operator-dossiers.mjs");
const quoteRequestId = "${quoteRequestId}";
const detail = { quote_request_id: quoteRequestId, request_kind: "website", quotation: null, acceptance: null };
const vatReadiness = { quote_request_id: quoteRequestId, vat_readiness: "READY" };
const pricing = (revision, amount) => ({ quote_request_id: quoteRequestId, intake_id: "a1800000-0000-4000-8000-000000000002", pricing_snapshot_id: "a1800000-0000-4000-8000-000000000003", pricing_snapshot_sha256: "a".repeat(64), currency: "EUR", known_minimum_minor: amount, contains_from_pricing: true, decision_required: true, can_decide: true, resolved: false, quotation_draft_available: false, billing_context_complete: false, billing_context: {}, revision });
let state = { detail, pricing: pricing(1, 350000), vatReadiness };
const panel = document.querySelector("[data-pricing]");
const render = () => {
  const presentation = websiteQuotationPricingPresentation(state.detail, state.pricing, { role: "owner", status: "ACTIVE" });
  panel.hidden = !presentation && !state.vatReadiness;
  panel.querySelector("[data-minimum]").textContent = presentation?.minimum || "-";
  panel.querySelector("[data-final]").textContent = presentation?.finalAmount || "Nog niet bepaald";
};
render();
window.metrics = { refreshStarts: [], pricingInvalid: 0, pricingHidden: 0, pricingPlaceholder: 0, pricingLoading: 0, pricingUnmount: 0, projectInvalid: 0, websiteWorkInvalid: 0 };
const initialPanel = panel;
const sample = () => {
  const current = document.querySelector("[data-pricing]");
  const minimum = current?.querySelector("[data-minimum]")?.textContent || "";
  const finalAmount = current?.querySelector("[data-final]")?.textContent || "";
  const hidden = !current || current.hidden;
  const placeholder = minimum === "-" || !minimum || !finalAmount;
  const loading = /laden/i.test(current?.textContent || "");
  window.metrics.pricingHidden += Number(hidden);
  window.metrics.pricingPlaceholder += Number(placeholder);
  window.metrics.pricingLoading += Number(loading);
  window.metrics.pricingUnmount += Number(current !== initialPanel);
  window.metrics.pricingInvalid += Number(hidden || placeholder || loading || current !== initialPanel);
  window.metrics.projectInvalid += Number(document.querySelector("[data-project]")?.textContent !== "Project actief");
  window.metrics.websiteWorkInvalid += Number(document.querySelector("[data-website-work]")?.textContent !== "PRE_PROJECT / CONCEPT");
};
window.sampleTimer = setInterval(sample, 20);
let cycle = 0;
window.refreshTimer = setInterval(() => {
  cycle += 1;
  window.metrics.refreshStarts.push(performance.now());
  state = retainWebsiteQuotationAuthorities(state.detail, state.pricing, state.vatReadiness, quoteRequestId);
  render();
  setTimeout(() => {
    if (cycle !== 2) state = { detail, pricing: pricing(cycle + 1, 350000 + cycle * 10000), vatReadiness };
    render();
    if (cycle === 3) window.complete = true;
  }, 600);
}, 8000);
</script></body></html>`;

function serve() {
  const server = createServer(async (request, response) => {
    if (request.url === "/__pricing-stability-harness") {
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

test("pricing, project, and Website work stay mounted across three genuine 8-second cycles", { timeout: 35_000 }, async () => {
  const server = await serve();
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  try {
    await page.goto(`http://127.0.0.1:${server.address().port}/__pricing-stability-harness`);
    await page.waitForFunction(() => window.complete === true, null, { timeout: 30_000 });
    const metrics = await page.evaluate(() => { clearInterval(window.sampleTimer); clearInterval(window.refreshTimer); return window.metrics; });
    assert.equal(metrics.refreshStarts.length, 3);
    assert.ok(metrics.refreshStarts[1] - metrics.refreshStarts[0] >= 7_900);
    assert.ok(metrics.refreshStarts[2] - metrics.refreshStarts[1] >= 7_900);
    assert.deepEqual(metrics, {
      refreshStarts: metrics.refreshStarts,
      pricingInvalid: 0,
      pricingHidden: 0,
      pricingPlaceholder: 0,
      pricingLoading: 0,
      pricingUnmount: 0,
      projectInvalid: 0,
      websiteWorkInvalid: 0,
    });
    console.log(`PRICING_STABILITY_METRICS=${JSON.stringify(metrics)}`);
  } finally {
    await page.close();
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});
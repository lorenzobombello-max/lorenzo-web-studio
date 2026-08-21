import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { applicationLocatorFromUrl, applicationReferenceFromUrl, applicationsForFilter, applyDetailVisibility, canPromoteApplication, customerCorePresentation, emptyStateForFilter, nextWorkflowStage, selectionFallsOutsideFilter } from "../assets/js/operator-dashboard.js";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("operator shell links to the canonical dashboard route", async () => {
  const source = await read("operator/index.html");
  assert.match(source, /href="\/operator\/dashboard\/"/);
});

test("dashboard remains hidden until the authorization guard succeeds", async () => {
  const source = await read("operator/dashboard/index.html");
  assert.match(source, /id="operatorDashboard" hidden/);
  assert.match(source, /operator-dashboard-guard\.mjs/);
});

test("dashboard preserves the locked Lorenzo Web Solutions branding", async () => {
  const source = await read("operator/dashboard/index.html");
  assert.match(source, /lorenzo-web-solution-logo-transparent\.png/);
  assert.match(source, /class="identity__mark"/);
  assert.match(source, /<strong>Lorenzo Web Solutions<\/strong>/);
  assert.doesNotMatch(source, />LW<\/|lw-badge/i);
});

test("dashboard guard requires database-backed operator authorization", async () => {
  const source = await read("assets/js/operator-dashboard-guard.mjs");
  assert.match(source, /requireAuthorizedOperator/);
  assert.match(source, /access\.status === "unauthenticated"/);
  assert.match(source, /access\.status === "unauthorized"/);
  assert.match(source, /startOperatorDashboard/);
  assert.match(source, /functionsBaseUrl/);
  assert.doesNotMatch(source, /operator-dashboard-contract\.js/);
  assert.match(source, /dashboard\.hidden = false/);
});

test("session shell uses the same database-backed authorization", async () => {
  const source = await read("assets/js/operator-shell.mjs");
  assert.match(source, /requireAuthorizedOperator/);
  assert.doesNotMatch(source, /requireOperatorSession/);
});

test("production dashboard uses real application data and no synthetic state", async () => {
  const [html, contract, script, css] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard-contract.js"),
    read("assets/js/operator-dashboard.js"),
    read("assets/css/operator-dashboard.css"),
  ]);
  assert.match(html, /id="applicationList"/);
  assert.match(html, /id="applicationDetail"/);
  assert.match(html, /id="promoteApplication"/);
  assert.match(html, /id="pricingDossier"/);
  assert.match(html, /id="documentsDossier"/);
  assert.match(html, /id="paymentDossier"/);
  assert.match(html, /id="auditTimeline"/);
  assert.doesNotMatch(html, /href=[^>]*(download|document)/i);
  assert.doesNotMatch(html, /Synthetic Project|TEST-LWS-OFF/);
  assert.match(contract, /LWS_DASHBOARD_CONTRACT/);
  assert.match(contract, /createScenario/);
  assert.match(script, /list_applications/);
  assert.match(script, /get_application_detail/);
  assert.match(script, /promote_accepted_application/);
  assert.match(script, /get_project_dossier/);
  assert.match(script, /requestId !== detailRequestId/);
  assert.match(script, /gereconcilieerd.*laatste:/);
  assert.doesNotMatch(script, /localStorage|lws-phase5d-synthetic-state-v1|LWS_DASHBOARD_CONTRACT/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
  assert.match(css, /\.dashboard-grid/);
  assert.match(css, /\.application-list/);
});

test("application reference query is the only accepted human locator", () => {
  assert.equal(applicationReferenceFromUrl("https://example.test/operator/dashboard/?application=LWS-AAN-2099-0001"), "LWS-AAN-2099-0001");
  assert.equal(applicationReferenceFromUrl("https://example.test/operator/dashboard/?application=bad"), null);
});

test("promotion is visible only for accepted applications without a project", () => {
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: { acceptance_id: "accepted" }, project: null }), true);
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: null, project: null }), false);
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: { acceptance_id: "accepted" }, project: { project_id: "project" } }), false);
  assert.equal(canPromoteApplication({ request_kind: "slimme_documentenflow", acceptance: { acceptance_id: "unexpected" }, project: null }), false);
});

test("product filters use only authoritative request_kind and fail closed", () => {
  const website = { quote_request_id: "website", request_kind: "website", website_type: "business" };
  const sdf = { quote_request_id: "sdf", request_kind: "slimme_documentenflow" };
  const unknown = { quote_request_id: "unknown", request_kind: "unknown", website_type: "business" };
  const missing = { quote_request_id: "missing", website_type: "business" };
  assert.deepEqual(applicationsForFilter([website, sdf, unknown, missing], "all"), [website, sdf]);
  assert.deepEqual(applicationsForFilter([website, sdf, unknown, missing], "website"), [website]);
  assert.deepEqual(applicationsForFilter([website, sdf, unknown, missing], "slimme_documentenflow"), [sdf]);
  assert.deepEqual(applicationsForFilter([website, sdf], "invalid"), []);
});

test("product filter empty states are specific and neutral", () => {
  assert.equal(emptyStateForFilter("all"), "Geen ingediende aanvragen.");
  assert.equal(emptyStateForFilter("website"), "Geen Website-aanvragen.");
  assert.equal(emptyStateForFilter("slimme_documentenflow"), "Geen Slimme Documentenflow-aanvragen.");
});

test("filter changes invalidate stale or unsupported detail state", () => {
  assert.equal(selectionFallsOutsideFilter({ request_kind: "website" }, "website"), false);
  assert.equal(selectionFallsOutsideFilter({ request_kind: "website" }, "slimme_documentenflow"), true);
  assert.equal(selectionFallsOutsideFilter({ request_kind: "slimme_documentenflow" }, "website"), true);
  assert.equal(selectionFallsOutsideFilter({ request_kind: null }, "all"), true);
});

function detailVisibilityHarness() {
  const customer = { hidden: false };
  const websiteSections = Array.from({ length: 7 }, () => ({ hidden: false }));
  return {
    customer,
    websiteSections,
    nodes: {
      detail: { hidden: false },
      detailEmpty: { hidden: true },
      promote: { hidden: false, disabled: true },
      dossierSections: [customer, ...websiteSections],
      websiteDossierSections: websiteSections,
      websiteDetailRows: Array.from({ length: 3 }, () => ({ hidden: false })),
      sdfDetailNotice: { hidden: false },
    },
  };
}

test("product switch fully clears Website and SDF dossier presentation", () => {
  for (const selectedKind of ["website", "slimme_documentenflow"]) {
    const harness = detailVisibilityHarness();
    applyDetailVisibility(selectedKind, harness.nodes);
    applyDetailVisibility(null, harness.nodes);
    assert.equal(harness.nodes.detail.hidden, true);
    assert.equal(harness.nodes.detailEmpty.hidden, false);
    assert.equal(harness.nodes.promote.hidden, true);
    assert.equal(harness.nodes.promote.disabled, false);
    assert.equal(harness.nodes.dossierSections.every((section) => section.hidden), true);
    assert.equal(harness.nodes.websiteDetailRows.every((row) => row.hidden), true);
    assert.equal(harness.nodes.sdfDetailNotice.hidden, true);
  }
});

test("Website detail is restored only after Website reselection", () => {
  const harness = detailVisibilityHarness();
  applyDetailVisibility(null, harness.nodes);
  applyDetailVisibility("website", harness.nodes);
  assert.equal(harness.nodes.detail.hidden, false);
  assert.equal(harness.nodes.detailEmpty.hidden, true);
  assert.equal(harness.customer.hidden, false);
  assert.equal(harness.websiteSections.every((section) => !section.hidden), true);
  assert.equal(harness.nodes.websiteDetailRows.every((row) => !row.hidden), true);
  assert.equal(harness.nodes.sdfDetailNotice.hidden, true);
});

test("SDF detail restores shared data without Website-only presentation", () => {
  const harness = detailVisibilityHarness();
  applyDetailVisibility(null, harness.nodes);
  applyDetailVisibility("slimme_documentenflow", harness.nodes);
  assert.equal(harness.nodes.detail.hidden, false);
  assert.equal(harness.nodes.detailEmpty.hidden, true);
  assert.equal(harness.customer.hidden, false);
  assert.equal(harness.websiteSections.every((section) => section.hidden), true);
  assert.equal(harness.nodes.websiteDetailRows.every((row) => row.hidden), true);
  assert.equal(harness.nodes.sdfDetailNotice.hidden, false);
});

test("SDF detail hides every Website-only field and dossier section", async () => {
  const [html, script] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard.js"),
  ]);
  assert.match(html, /data-website-detail/);
  assert.match(html, /id="sdfDetailNotice"[^>]* hidden/);
  assert.match(script, /WEBSITE_DOSSIER_IDS/);
  assert.match(script, /section\.hidden = !isWebsite/);
  assert.match(script, /row\.hidden = !isWebsite/);
  assert.match(script, /if \(!isWebsite\) return/);
  assert.match(script, /application\.request_kind === "website" && application\.project/);
});

test("Website and SDF use the same persisted Customer Core presentation", () => {
  const customer = {
    customer_type: "business", name: "Test Klant", company: "Test BV", email: "klant@example.test", phone: "+32 470 00 00 00",
    enterprise_number: "0123456789", enterprise_validation_status: "format_valid_not_externally_verified",
    vat_number: "BE0123456789", vat_validation_status: "valid", vat_validated_at: "2026-08-21T10:00:00Z",
    billing_address: "Teststraat 1", billing_postal_code: "9000", billing_city: "Gent", billing_country: "BE", billing_email: "billing@example.test",
  };
  const website = customerCorePresentation({ ...customer, request_kind: "website" });
  const sdf = customerCorePresentation({ ...customer, request_kind: "slimme_documentenflow" });
  assert.deepEqual(sdf, website);
  assert.equal(website.detailEnterpriseNumber, "0123456789");
  assert.equal(website.detailBillingEmail, "billing@example.test");
});

test("missing optional Customer Core values clear stale dossier content", () => {
  const previous = customerCorePresentation({ company: "Vorige BV", vat_number: "BE0123456789", billing_city: "Gent" });
  const next = customerCorePresentation({ name: "Nieuwe klant", email: "nieuw@example.test" });
  assert.equal(previous.detailCompany, "Vorige BV");
  assert.equal(next.detailCompany, "-");
  assert.equal(next.detailVatNumber, "-");
  assert.equal(next.detailBillingCity, "-");
});

test("Customer Core presentation preserves untrusted text for textContent rendering", async () => {
  const payload = '<img src=x onerror="alert(1)">';
  assert.equal(customerCorePresentation({ company: payload }).detailCompany, payload);
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});

test("filter navigation reuses loaded data and preserves out-of-order protection", async () => {
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /activeFilter = nextFilter;[\s\S]{0,250}clearDetail\(\);[\s\S]{0,150}renderList/);
  assert.match(script, /renderList\(applicationsForFilter\(applications, activeFilter\)\)/);
  assert.match(script, /requestId !== detailRequestId/);
  assert.match(script, /detailRequestId \+= 1/);
  assert.equal(script.match(/action: "list_applications"/g)?.length, 1);
});

test("legacy applications use the internal UUID locator without fabricating a reference", () => {
  assert.deepEqual(applicationLocatorFromUrl("https://example.test/operator/dashboard/?request=a1100000-0000-4000-8000-000000000003"), { quote_request_id: "a1100000-0000-4000-8000-000000000003" });
  assert.equal(applicationLocatorFromUrl("https://example.test/operator/dashboard/?request=bad"), null);
});

test("workflow display distinguishes available, locked, completed, and unimplemented states", () => {
  assert.equal(nextWorkflowStage("QUOTE_ACCEPTED").availability, "AVAILABLE NOW");
  assert.equal(nextWorkflowStage("M1_PAYMENT_PENDING").availability, "LOCKED");
  assert.equal(nextWorkflowStage("ARCHIVED").availability, "COMPLETED");
  assert.equal(nextWorkflowStage("UNKNOWN").availability, "NOT YET IMPLEMENTED");
});
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { applicationIdentityPresentation, applicationLocatorFromUrl, applicationReferenceFromUrl, applicationsForFilter, applyDetailVisibility, buildIntakeLifecycleCommand, canPromoteApplication, customerCorePresentation, emptyStateForFilter, focusIntakeLifecycle, intakeLifecycleError, intakeLifecyclePresentation, nextWorkflowStage, sdfPackageLabel, sdfPricingPresentation, sdfProjectPresentation, sdfQuotationPresentation, selectionFallsOutsideFilter } from "../assets/js/operator-dashboard.js";

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

test("application identity presents the human reference and routes with the existing reference contract", () => {
  const application = {
    application_reference: "LWS-AAN-2099-0401",
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
  };
  assert.deepEqual(applicationIdentityPresentation(application), {
    visibleReference: "LWS-AAN-2099-0401",
    locator: { application_reference: "LWS-AAN-2099-0401" },
  });
  assert.equal(application.quote_request_id, "a1100000-0000-4000-8000-000000000003");
});

test("application identity preserves the technical UUID fallback for legacy records", () => {
  const quoteRequestId = "a1100000-0000-4000-8000-000000000003";
  assert.deepEqual(applicationIdentityPresentation({ application_reference: null, quote_request_id: quoteRequestId }), {
    visibleReference: `Oudere aanvraag · ${quoteRequestId}`,
    locator: { quote_request_id: quoteRequestId },
  });
  assert.deepEqual(applicationIdentityPresentation({ application_reference: "invalid", quote_request_id: quoteRequestId }).locator, { quote_request_id: quoteRequestId });
});

test("application list and detail use the same human-readable identity presentation", async () => {
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /setText\("detailReference", applicationIdentityPresentation\(application\)\.visibleReference\)/);
  assert.match(script, /reference\.textContent = `\$\{applicationPresentation\.visibleReference\}/);
  assert.match(script, /const locator = applicationPresentation\.locator/);
});

test("promotion is visible only for accepted applications without a project", () => {
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: { acceptance_id: "accepted" }, project: null }), true);
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: null, project: null }), false);
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: { acceptance_id: "accepted" }, project: { project_id: "project" } }), false);
  assert.equal(canPromoteApplication({ request_kind: "slimme_documentenflow", acceptance: { acceptance_id: "unexpected" }, project: null }), false);
});

function intakeLifecycle(effectiveAccess, overrides = {}) {
  return {
    intake_id: "a1800000-0000-4000-8000-000000000030",
    access_state: effectiveAccess === "EXPIRED" ? "ACTIVE" : effectiveAccess,
    effective_access: effectiveAccess,
    access_token_expires_at: "2099-08-30T12:00:00Z",
    lifecycle_revision: 2,
    ...overrides,
  };
}

test("lifecycle actions follow only the authoritative effective state", () => {
  assert.deepEqual(intakeLifecyclePresentation(intakeLifecycle("ACTIVE")).actions, ["interrupt_intake", "cancel_intake"]);
  assert.deepEqual(intakeLifecyclePresentation(intakeLifecycle("INTERRUPTED")).actions, ["resume_intake", "cancel_intake"]);
  assert.deepEqual(intakeLifecyclePresentation(intakeLifecycle("EXPIRED")).actions, ["reactivate_intake"]);
  assert.deepEqual(intakeLifecyclePresentation(intakeLifecycle("CANCELLED")).actions, []);
  assert.equal(intakeLifecyclePresentation(intakeLifecycle("UNKNOWN")), null);
  assert.equal(intakeLifecyclePresentation(null), null);
});

test("lifecycle command sends revision and idempotency without token or expiry authority", () => {
  const command = buildIntakeLifecycleCommand(
    "interrupt_intake",
    intakeLifecycle("ACTIVE"),
    "  Klant vroeg om een tijdelijke pauze.  ",
    "a1800000-0000-4000-8000-000000000031",
  );
  assert.deepEqual(command, {
    action: "interrupt_intake",
    intake_id: "a1800000-0000-4000-8000-000000000030",
    expected_revision: 2,
    idempotency_key: "a1800000-0000-4000-8000-000000000031",
    reason: "Klant vroeg om een tijdelijke pauze.",
  });
  assert.equal(Object.hasOwn(command, "access_token"), false);
  assert.equal(Object.hasOwn(command, "expires_at"), false);
});

test("lifecycle command fails closed for blank reason and forbidden transitions", () => {
  assert.throws(()=>buildIntakeLifecycleCommand("interrupt_intake", intakeLifecycle("ACTIVE"), "   ", "a1800000-0000-4000-8000-000000000031"), /INVALID_LIFECYCLE_COMMAND/);
  assert.throws(()=>buildIntakeLifecycleCommand("resume_intake", intakeLifecycle("ACTIVE"), "Reden", "a1800000-0000-4000-8000-000000000031"), /INVALID_LIFECYCLE_COMMAND/);
  assert.throws(()=>buildIntakeLifecycleCommand("reactivate_intake", intakeLifecycle("CANCELLED"), "Reden", "a1800000-0000-4000-8000-000000000031"), /INVALID_LIFECYCLE_COMMAND/);
});

test("lifecycle errors request authoritative refresh without exposing internals", () => {
  assert.equal(intakeLifecycleError("CONCURRENT_MODIFICATION").refresh, true);
  assert.equal(intakeLifecycleError("COMMAND_REJECTED").refresh, true);
  assert.equal(intakeLifecycleError("IDEMPOTENCY_CONFLICT").refresh, true);
  assert.equal(intakeLifecycleError("INTAKE_NOT_FOUND").refresh, true);
  assert.equal(intakeLifecycleError("OPERATOR_NOT_AUTHORIZED").refresh, false);
  assert.doesNotMatch(intakeLifecycleError("internal SQL detail").message, /SQL|postgres|internal/i);
});

test("lifecycle UI uses one accessible dialog, busy guard, and authoritative reload", async () => {
  const [html, script] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard.js"),
  ]);
  assert.match(html, /id="lifecycleDossier"/);
  assert.match(html, /id="lifecycleDialog"[^>]*aria-labelledby="lifecycleDialogTitle"[^>]*aria-describedby="lifecycleDialogDescription"/);
  assert.match(html, /id="lifecycleReason"[^>]*maxlength="500"[^>]*required/);
  assert.doesNotMatch(html, /customer token|access token|access_token/i);
  assert.match(script, /if \(lifecycleBusy \|\|/);
  assert.match(script, /button\.disabled = lifecycleBusy/);
  assert.match(script, /crypto\.randomUUID\(\)/);
  assert.match(script, /await invoke\(input\);[\s\S]{0,80}await loadDetail\(command\.locator\)/);
  assert.match(script, /if \(outcome\.refresh\) await loadDetail\(command\.locator\)/);
});

test("successful interrupt focuses the visible resume action instead of the hidden trigger", () => {
  const focused = [];
  const buttons = [
    { dataset: { lifecycleAction: "interrupt_intake" }, hidden: true, disabled: false, focus: ()=>focused.push("interrupt_intake") },
    { dataset: { lifecycleAction: "resume_intake" }, hidden: false, disabled: false, focus: ()=>focused.push("resume_intake") },
    { dataset: { lifecycleAction: "cancel_intake" }, hidden: false, disabled: false, focus: ()=>focused.push("cancel_intake") },
  ];
  const body = { focus: ()=>focused.push("body") };

  assert.equal(focusIntakeLifecycle(intakeLifecycle("INTERRUPTED"), buttons, body), buttons[1]);
  assert.deepEqual(focused, ["resume_intake"]);
});

test("successful cancellation focuses the visible lifecycle heading fallback", () => {
  const focused = [];
  const hiddenTrigger = { dataset: { lifecycleAction: "cancel_intake" }, hidden: true, disabled: false, focus: ()=>focused.push("cancel_intake") };
  const heading = { focus: ()=>focused.push("heading") };

  assert.equal(focusIntakeLifecycle(intakeLifecycle("CANCELLED"), [hiddenTrigger], heading), heading);
  assert.deepEqual(focused, ["heading"]);
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
  const sdfSections = Array.from({ length: 2 }, () => ({ hidden: false }));
  return {
    customer,
    websiteSections,
    sdfSections,
    nodes: {
      detail: { hidden: false },
      detailEmpty: { hidden: true },
      promote: { hidden: false, disabled: true },
      dossierSections: [customer, ...websiteSections, ...sdfSections],
      websiteDossierSections: websiteSections,
      sdfDossierSections: sdfSections,
      websiteDetailRows: Array.from({ length: 3 }, () => ({ hidden: false })),
      sdfDetailRows: Array.from({ length: 1 }, () => ({ hidden: false })),
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
    assert.equal(harness.nodes.sdfDetailRows.every((row) => row.hidden), true);
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
  assert.equal(harness.sdfSections.every((section) => section.hidden), true);
  assert.equal(harness.nodes.websiteDetailRows.every((row) => !row.hidden), true);
  assert.equal(harness.nodes.sdfDetailRows.every((row) => row.hidden), true);
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
  assert.equal(harness.sdfSections.every((section) => !section.hidden), true);
  assert.equal(harness.nodes.websiteDetailRows.every((row) => row.hidden), true);
  assert.equal(harness.nodes.sdfDetailRows.every((row) => !row.hidden), true);
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

test("SDF package rendering uses canonical labels and a neutral legacy state", async () => {
  assert.equal(sdfPackageLabel("start"), "START");
  assert.equal(sdfPackageLabel("groei"), "GROEI");
  assert.equal(sdfPackageLabel("maatwerk"), "MAATWERK");
  assert.equal(sdfPackageLabel(null), "Niet geregistreerd");
  assert.equal(sdfPackageLabel('<img src=x onerror="alert(1)">'), "Niet geregistreerd");
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
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

function sdfPricing(packageName, implementationMinor, recurringMinor, priceMode = "fixed") {
  return {
    authority_version: 1,
    package: packageName,
    currency: "EUR",
    vat_basis: "exclusive",
    implementation: { amount_minor: implementationMinor, price_mode: priceMode },
    recurring: {
      amount_minor: recurringMinor,
      price_mode: priceMode,
      billing_period: "month",
      commercial_package_price: true,
      active_recurring_obligation: false,
    },
  };
}

test("SDF pricing renders exact START and GROEI commercial package prices", () => {
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "start", sdf_pricing: sdfPricing("start", 285000, 17500) }), {
    package: "START", implementation: "€ 2.850 excl. btw", recurring: "€ 175 excl. btw / maand",
  });
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "groei", sdf_pricing: sdfPricing("groei", 570000, 29900) }), {
    package: "GROEI", implementation: "€ 5.700 excl. btw", recurring: "€ 299 excl. btw / maand",
  });
});

test("SDF MAATWERK pricing preserves starting-at semantics", () => {
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "maatwerk", sdf_pricing: sdfPricing("maatwerk", 750000, 44900, "starting_at") }), {
    package: "MAATWERK", implementation: "vanaf € 7.500 excl. btw", recurring: "vanaf € 449 excl. btw / maand",
  });
});

test("SDF pricing fails closed for legacy, mismatched, and non-commercial contexts", () => {
  const unavailable = { package: "GROEI", implementation: "Niet beschikbaar", recurring: "Niet beschikbaar" };
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: null, sdf_pricing: null }), {
    package: "Niet geregistreerd", implementation: "Niet beschikbaar", recurring: "Niet beschikbaar",
  });
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "groei", sdf_pricing: sdfPricing("start", 285000, 17500) }), unavailable);
  const obligation = sdfPricing("groei", 570000, 29900);
  obligation.recurring.active_recurring_obligation = true;
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "groei", sdf_pricing: obligation }), unavailable);
  assert.equal(sdfPricingPresentation({ request_kind: "website", sdf_package: "start", sdf_pricing: sdfPricing("start", 285000, 17500) }), null);
});

test("SDF pricing clears stale values and remains textContent-only", async () => {
  const previous = sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "start", sdf_pricing: sdfPricing("start", 285000, 17500) });
  const next = sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: null, sdf_pricing: null });
  assert.equal(previous.implementation, "€ 2.850 excl. btw");
  assert.equal(next.implementation, "Niet beschikbaar");
  assert.equal(next.recurring, "Niet beschikbaar");
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="sdfPricingDossier"[^>]* hidden/);
  assert.match(html, /commerciële pakketprijs en geen actieve terugkerende dienst of financiële verplichting/);
  assert.match(script, /setText\("detailSdfImplementationPrice", sdfPricing\?\.implementation \|\| "Niet beschikbaar"\)/);
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});

function sdfQuotation(overrides = {}) {
  return {
    quotation_id: "a1a00000-0000-4000-8000-000000000001",
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
    application_reference: null,
    created_at: "2099-01-03T10:00:00Z",
    document: null,
    acceptance: null,
    ...overrides,
  };
}

test("SDF quotation presenter renders exact identity without inventing status", () => {
  const presentation = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation() });
  assert.equal(presentation.quotationId, "a1a00000-0000-4000-8000-000000000001");
  assert.equal(presentation.application, "a1100000-0000-4000-8000-000000000003");
  assert.notEqual(presentation.createdAt, "Niet beschikbaar");
  assert.equal(presentation.documentState, "Niet geregistreerd");
  assert.equal(presentation.acceptanceState, "Niet geregistreerd");
});

test("SDF quotation presenter renders document evidence without acceptance", () => {
  const document = {
    quotation_date: "2099-01-03",
    valid_until: "2099-02-02",
    prepared_at: "2099-01-03T11:00:00Z",
    document_reference_present: true,
    document_sha256_present: true,
  };
  const presentation = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation({ document }) });
  assert.equal(presentation.documentState, "Geregistreerd");
  assert.notEqual(presentation.quotationDate, "Niet beschikbaar");
  assert.notEqual(presentation.validUntil, "Niet beschikbaar");
  assert.equal(presentation.documentReference, "Aanwezig");
  assert.equal(presentation.documentHash, "Aanwezig");
  assert.equal(presentation.acceptanceState, "Niet geregistreerd");
});

test("SDF quotation presenter renders active acceptance evidence", () => {
  const document = { quotation_date: "2099-01-03", valid_until: "2099-02-02", prepared_at: "2099-01-03T11:00:00Z", document_reference_present: true, document_sha256_present: true };
  const acceptance = { accepted_at: "2099-01-04T12:00:00Z", accepted_document_reference_present: true, accepted_document_sha256_present: true };
  const presentation = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation({ document, acceptance }) });
  assert.equal(presentation.acceptanceState, "Geaccepteerd");
  assert.notEqual(presentation.acceptedAt, "Niet beschikbaar");
  assert.equal(presentation.acceptedDocument, "Aanwezig");
  assert.equal(presentation.acceptedHash, "Aanwezig");
});

test("SDF quotation presenter handles absent, mismatched, Website, and legacy identities", () => {
  assert.deepEqual(sdfQuotationPresentation(sdfApplication()), {
    quotationId: "Nog geen offerte",
    application: "a1100000-0000-4000-8000-000000000003",
    createdAt: "Niet beschikbaar",
    documentState: "Niet geregistreerd",
    quotationDate: "Niet beschikbaar",
    validUntil: "Niet beschikbaar",
    preparedAt: "Niet beschikbaar",
    documentReference: "Niet beschikbaar",
    documentHash: "Niet beschikbaar",
    acceptanceState: "Niet geregistreerd",
    acceptedAt: "Niet beschikbaar",
    acceptedDocument: "Niet beschikbaar",
    acceptedHash: "Niet beschikbaar",
  });
  assert.equal(sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation({ quote_request_id: "b1100000-0000-4000-8000-000000000003" }) }).quotationId, "Nog geen offerte");
  assert.equal(sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation({ status: "DRAFT" }) }).quotationId, "Nog geen offerte");
  assert.equal(sdfQuotationPresentation({ request_kind: "website", sdf_quotation: sdfQuotation() }), null);
  assert.equal(sdfQuotationPresentation({ quote_request_id: "legacy", request_kind: "slimme_documentenflow", sdf_quotation: null }).application, "legacy");
});

test("SDF quotation presenter fails closed on malformed or mismatched evidence", () => {
  const validDocument = { quotation_date: "2099-01-03", valid_until: "2099-02-02", prepared_at: "2099-01-03T11:00:00Z", document_reference_present: true, document_sha256_present: true };
  const invalidCases = [
    sdfQuotation({ document: { ...validDocument, valid_until: "2099-01-02" } }),
    sdfQuotation({ document: { ...validDocument, document_sha256: "a".repeat(64) } }),
    sdfQuotation({ document: null, acceptance: { accepted_at: "2099-01-04T12:00:00Z", accepted_document_reference_present: true, accepted_document_sha256_present: true } }),
    sdfQuotation({ document: validDocument, acceptance: { accepted_at: "invalid", accepted_document_reference_present: true, accepted_document_sha256_present: true } }),
  ];
  for (const quotation of invalidCases) {
    const presentation = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: quotation });
    assert.equal(presentation.quotationId, "Nog geen offerte");
    assert.equal(presentation.documentState, "Niet geregistreerd");
    assert.equal(presentation.acceptanceState, "Niet geregistreerd");
  }
});

test("SDF quotation values clear on dossier switch and remain textContent-only", async () => {
  const previous = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation() });
  const next = sdfQuotationPresentation(sdfApplication());
  assert.notEqual(previous.quotationId, "Nog geen offerte");
  assert.equal(next.quotationId, "Nog geen offerte");
  assert.equal(next.createdAt, "Niet beschikbaar");
  assert.equal(next.documentReference, "Niet beschikbaar");
  assert.equal(next.acceptedDocument, "Niet beschikbaar");
  const payload = '<img src=x onerror="alert(1)">';
  assert.equal(sdfQuotationPresentation({ ...sdfApplication(), application_reference: payload }).application, payload);
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="sdfQuotationDossier"[^>]* hidden/);
  assert.match(html, /id="detailSdfQuotationAcceptanceState"><\/dd>/);
  assert.doesNotMatch(html, /detailSdfQuotationStatus/);
  assert.match(script, /setText\("detailSdfQuotationId", sdfQuotation\?\.quotationId \|\| "Nog geen offerte"\)/);
  assert.doesNotMatch(script, /detailSdfQuotationStatus/);
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});

function sdfApplication(project = null) {
  return {
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
    application_reference: null,
    request_kind: "slimme_documentenflow",
    sdf_package: "groei",
    name: "Documentenflow Application",
    project,
  };
}

function sdfProject(overrides = {}) {
  return {
    project_id: "a1900000-0000-4000-8000-000000000001",
    request_kind: "slimme_documentenflow",
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
    application_reference: null,
    customer_name: "Documentenflow Application",
    sdf_package: "groei",
    current_state: null,
    operational_status: null,
    created_at: "2099-01-02T10:00:00Z",
    ...overrides,
  };
}

test("SDF application without project authority shows no fabricated project", () => {
  assert.deepEqual(sdfProjectPresentation(sdfApplication()), {
    projectId: "Nog geen project",
    product: "Slimme Documentenflow",
    application: "a1100000-0000-4000-8000-000000000003",
    customer: "Documentenflow Application",
    package: "GROEI",
    status: "Niet beschikbaar",
    operationalStatus: "Niet beschikbaar",
    createdAt: "Niet beschikbaar",
  });
});

test("SDF project authority renders exact linkage without inventing status", () => {
  const presentation = sdfProjectPresentation(sdfApplication(sdfProject()));
  assert.equal(presentation.projectId, "a1900000-0000-4000-8000-000000000001");
  assert.equal(presentation.product, "Slimme Documentenflow");
  assert.equal(presentation.application, "a1100000-0000-4000-8000-000000000003");
  assert.equal(presentation.customer, "Documentenflow Application");
  assert.equal(presentation.package, "GROEI");
  assert.equal(presentation.status, "Niet beschikbaar");
  assert.equal(presentation.operationalStatus, "Niet beschikbaar");
  assert.notEqual(presentation.createdAt, "Niet beschikbaar");
});

test("SDF project presentation fails closed for cross-product, mismatched, and legacy contexts", () => {
  assert.equal(sdfProjectPresentation({ request_kind: "website", project: sdfProject() }), null);
  assert.equal(sdfProjectPresentation(sdfApplication(sdfProject({ quote_request_id: "b1100000-0000-4000-8000-000000000003" }))).projectId, "Nog geen project");
  assert.equal(sdfProjectPresentation(sdfApplication(sdfProject({ current_state: "PROJECT_IN_PROGRESS" }))).projectId, "Nog geen project");
  const legacy = sdfProjectPresentation({ quote_request_id: "legacy", request_kind: "slimme_documentenflow", sdf_package: null, name: "Legacy", project: null });
  assert.equal(legacy.projectId, "Nog geen project");
  assert.equal(legacy.package, "Niet geregistreerd");
});

test("SDF project values clear on dossier switch and remain textContent-only", async () => {
  const previous = sdfProjectPresentation(sdfApplication(sdfProject()));
  const next = sdfProjectPresentation(sdfApplication());
  assert.notEqual(previous.projectId, "Nog geen project");
  assert.equal(next.projectId, "Nog geen project");
  assert.equal(next.createdAt, "Niet beschikbaar");
  const payload = '<img src=x onerror="alert(1)">';
  assert.equal(sdfProjectPresentation({ ...sdfApplication(), name: payload }).customer, payload);
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="sdfProjectDossier"[^>]* hidden/);
  assert.match(script, /setText\("detailSdfProjectId", sdfProject\?\.projectId \|\| "Nog geen project"\)/);
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});
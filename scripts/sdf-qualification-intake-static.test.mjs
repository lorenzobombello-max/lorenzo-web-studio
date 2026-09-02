import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { applySdfQualificationView, sdfQualificationInitialView } from "../assets/js/sdf-qualification-state.mjs";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("draft restore does not show submitted success state", () => {
  for (const status of ["invited", "in_progress", "changes_requested"]) {
    const nodes = {
      loading: { hidden: true }, unavailable: { hidden: true },
      workspace: { hidden: true }, success: { hidden: false },
    };
    const view = sdfQualificationInitialView(status);
    applySdfQualificationView(view, nodes);
    assert.equal(view, "workspace");
    assert.equal(nodes.workspace.hidden, false);
    assert.equal(nodes.success.hidden, true);
  }
});

test("only canonical submitted lifecycle statuses show success", () => {
  for (const status of ["submitted", "under_review", "qualification_complete", "closed"]) {
    assert.equal(sdfQualificationInitialView(status), "success");
  }
  assert.equal(sdfQualificationInitialView("unexpected"), "unavailable");
});

test("SDF qualification intake preserves its three-step form contract", async () => {
  const html = await read("pages/sdf-qualification-intake.html");

  assert.equal(html.match(/<fieldset[^>]*data-step="\d"[^>]*>/g)?.length, 3);
  assert.match(html, /<legend>Welke documenten gebruikt u\?<\/legend>/);
  assert.match(html, /<legend>Welke werkstappen zijn nodig\?<\/legend>/);
  assert.match(html, /<legend>Beschrijf uw huidige en gewenste flow\.<\/legend>/);

  for (const id of [
    "qualificationForm",
    "documentCategories",
    "workflowCapabilities",
    "currentWorkflow",
    "desiredWorkflow",
    "volumeBand",
    "frequency",
    "relevantDocumentTypes",
    "rolesUsers",
    "sampleAvailable",
    "sampleRequestedByLws",
    "sampleUploadRequiredLater",
    "confirmation",
    "sdfDossierReference",
    "sdfSuccessReference",
    "saveButton",
    "submitButton",
  ]) {
    assert.match(html, new RegExp(`id="${id}"`), `Missing required #${id}`);
  }

  for (const value of [
    "quotation",
    "invoice",
    "order_confirmation",
    "work_order",
    "delivery_note",
    "contract",
    "customer_document",
    "supplier_document",
    "internal_administrative_document",
    "multiple_document_types",
    "other_custom",
    "unknown_qualification_required",
    "receive",
    "generate",
    "review",
    "approve",
    "send",
    "archive",
    "retrieve",
  ]) {
    assert.match(html, new RegExp(`value="${value}"`), `Missing option value ${value}`);
  }
});

test("SDF progress presentation mirrors the active three-step structure", async () => {
  const [html, script] = await Promise.all([
    read("pages/sdf-qualification-intake.html"),
    read("assets/js/sdf-qualification-intake.js"),
  ]);

  assert.match(html, /id="sdfStepLabel">Documenten/);
  assert.match(html, /id="sdfCompletionValue">Fase 1 van 3/);
  assert.match(html, /id="sdfProgressBar"/);
  assert.match(script, /stepLabels=\["Documenten","Werkstappen","Uw flow"\]/);
  assert.match(script, /completionValue\.textContent=`Fase \$\{currentStep\+1\} van 3`/);
  assert.match(script, /progressBar\.style\.width=/);
});

test("SDF qualification intake preserves capability and API contracts", async () => {
  const [html, script] = await Promise.all([
    read("pages/sdf-qualification-intake.html"),
    read("assets/js/sdf-qualification-intake.js"),
  ]);

  assert.match(html, /sdf-qualification-intake\.js\?v=20260902-1/);
  assert.match(script, /new URLSearchParams\(location\.hash\.slice\(1\)\)/);
  assert.match(script, /history\.replaceState\(null,"",location\.pathname\)/);
  assert.doesNotMatch(script, /location\.search/);
  assert.match(script, /sdfQualificationInitialView\(intake\.status\)/);
  assert.match(script, /reference:intake\.support_reference/);
  assert.match(html, /id="sdfDossierReference"/);
  assert.doesNotMatch(script, /intake\.application_reference/);
  assert.match(script, /applySdfQualificationView\("workspace",stateViews\)/);

  for (const key of [
    "documentPurpose",
    "workflowCapabilities",
    "businessRequirements",
    "sampleDocumentMetadata",
  ]) {
    assert.match(script, new RegExp(`${key}:`), `Missing payload key ${key}`);
  }

  for (const action of ["inspect", "save_draft", "evaluate_capacity_preview", "submit"]) {
    assert.match(script, new RegExp(`action:"${action}"`), `Missing API action ${action}`);
  }
});

test("SDF capacity preview is preliminary, server-derived, and keyboard-safe", async () => {
  const [html, script, presenter, publishScript] = await Promise.all([
    read("pages/sdf-qualification-intake.html"),
    read("assets/js/sdf-qualification-intake.js"),
    read("assets/js/sdf-budget-guard-capacity-preview.mjs"),
    read("scripts/prepare-pages-dist.ps1"),
  ]);

  for (const id of ["capacityPreview", "capacityPreviewHeading", "capacityPreviewBadge", "capacityPreviewMessage", "capacityPreviewDetail", "capacityPreviewReasons"]) {
    assert.match(html, new RegExp(`id="${id}"`), `Missing preview region #${id}`);
  }
  assert.match(html, /role="status" aria-live="polite" aria-atomic="true"/);
  assert.match(html, /Budget Guard — voorlopige capaciteitscheck/);
  assert.match(script, /buildSdfCapacityPreviewPresentation/);
  assert.match(script, /input\.disabled=packageState\.disabled/);
  assert.match(script, /action:"evaluate_capacity_preview"/);
  assert.match(script, /await saveDraft\(true\)/);
  assert.match(presenter, /finalDecisionPending: true/);
  assert.doesNotMatch(presenter, /max_flows|max_document_types|max_pages_per_month|max_users|setup_price|monthly_price/);
  assert.match(publishScript, /assets\/js\/sdf-budget-guard-capacity-preview\.mjs/);
});

test("SDF qualification intake personalizes only the capability-bound customer dossier", async () => {
  const [html, script, customerModule] = await Promise.all([
    read("pages/sdf-qualification-intake.html"),
    read("assets/js/sdf-qualification-intake.js"),
    read("assets/js/sdf-qualification-customer.mjs"),
  ]);

  for (const id of ["sdfCustomerGreeting", "sdfCustomerDossier"]) {
    assert.match(html, new RegExp(`id="${id}"`), `Missing customer personalization #${id}`);
  }
  assert.match(script, /renderSdfQualificationCustomer\(.*intake/);
  for (const field of ["name", "company", "email", "phone", "support_reference"]) {
    assert.match(customerModule, new RegExp(`\\b${field}\\b`), `Missing safe customer field ${field}`);
  }
  assert.match(customerModule, /Slimme Documentenflow/);
  assert.doesNotMatch(customerModule, /quote_request_id|application_id|application_reference|automation|provider|token|capability/i);
});

test("SDF commercial qualification V3 captures capacities without pricing authority", async () => {
  const [html, script] = await Promise.all([
    read("pages/sdf-qualification-intake.html"),
    read("assets/js/sdf-qualification-intake.js"),
  ]);

  for (const value of ["start", "groei", "pro", "maatwerk", "advice_requested"]) {
    assert.match(html, new RegExp(`name="packageDirection" value="${value}"`));
  }

  for (const id of [
    "customComplexity",
    "documentVolumeSection",
    "documentVolumes",
    "flowCount",
    "userCount",
    "qualificationSummary",
  ]) {
    assert.match(html, new RegExp(`id="${id}"`), `Missing V2 control #${id}`);
  }

  assert.match(script, /commercialQualification:\{packageDirection:/);
  assert.match(script, /flowCount:flowCount===""\?null:Number\(flowCount\)/);
  assert.match(script, /userCount:userCount===""\?null:Number\(userCount\)/);
  assert.match(script, /documentType:category,documentCount:/);
  assert.match(script, /averagePagesPerDocument:/);
  assert.match(script, /min="1" max="1000000"/);
  assert.match(script, /min="1" max="1000"/);
  assert.match(script, /periodLabels=\{weekly:/);
  assert.match(html, /uiteindelijke scope en prijs worden bevestigd in uw offerte/i);
  assert.match(html, /€2\.850 implementatie · €175\/maand/);
  assert.match(html, /€5\.700 implementatie · €299\/maand/);
  assert.match(html, /€7\.500 implementatie · €449\/maand/);
  assert.match(html, /Prijs na beoordeling en offerte/);
  assert.doesNotMatch(script, /priceMinor|estimatedPagesPerPeriod|totalDocuments|totalPages/);
  assert.doesNotMatch(html, /name="(?:price|amount|budget)/i);
});

test("SDF stepper is fail-closed, keyboard-safe, and deterministically revalidated", async () => {
  const [html, script, publishScript] = await Promise.all([
    read("pages/sdf-qualification-intake.html"),
    read("assets/js/sdf-qualification-intake.js"),
    read("scripts/prepare-pages-dist.ps1"),
  ]);

  assert.match(html, /data-step-target="1" disabled aria-disabled="true"/);
  assert.match(html, /data-step-target="2" disabled aria-disabled="true"/);
  assert.match(script, /deriveSdfStepState\(answers\(\),document\.getElementById\("confirmation"\)\.checked\)/);
  assert.match(script, /canActivateSdfStep\(updateStepperState\(\),target\)/);
  assert.match(script, /form\.addEventListener\("input",refreshDerivedPresentation\)/);
  assert.match(script, /form\.addEventListener\("change",refreshDerivedPresentation\)/);
  assert.match(script, /querySelector\("input, textarea, select"\)\?\.focus\(\)/);
  assert.match(publishScript, /assets\/js\/sdf-qualification-stepper\.mjs/);
});

test("SDF completed and locked presentation reuses the Website intake pattern on every viewport", async () => {
  const [websiteCss, sdfCss] = await Promise.all([
    read("assets/css/intake.css"),
    read("assets/css/sdf-qualification-intake.css"),
  ]);
  const completedColors = /button\.is-complete > span:first-child \{ color: (#\w+); border-color: (#\w+); background: (#\w+); \}/;
  assert.deepEqual(sdfCss.match(completedColors)?.slice(1), websiteCss.match(completedColors)?.slice(1));
  assert.match(sdfCss, /\.sdf-progress button:disabled \{ cursor: default; opacity: 0\.48; \}/);
  assert.doesNotMatch(sdfCss, /@media[^}]+is-complete/s);
});

test("SDF pre-submit print follows the Website iframe pattern and publishes an A4-safe stylesheet", async () => {
  const [html, script, reviewModule, printCss, publishScript] = await Promise.all([
    read("pages/sdf-qualification-intake.html"),
    read("assets/js/sdf-qualification-intake.js"),
    read("assets/js/sdf-qualification-review.mjs"),
    read("assets/css/sdf-qualification-print.css"),
    read("scripts/prepare-pages-dist.ps1"),
  ]);
  assert.match(html, /id="printReviewButton"[^>]*>Afdrukken \/ Opslaan als PDF/);
  assert.match(script, /printSdfQualificationReview\(answers\(\),reviewContext\)/);
  assert.match(reviewModule, /frame\.contentWindow\?\.print\(\)/);
  assert.match(reviewModule, /meta name="referrer" content="no-referrer"/);
  assert.doesNotMatch(reviewModule, /location\.hash|token|capability|authorization|Bearer/);
  assert.match(printCss, /@page \{ size: A4 portrait;/);
  assert.match(printCss, /@media print/);
  assert.match(printCss, /break-inside: avoid/);
  assert.match(printCss, /overflow-wrap: anywhere/);
  assert.doesNotMatch(printCss, /overflow:\s*hidden/);
  assert.match(publishScript, /assets\/css\/sdf-qualification-print\.css/);
  assert.match(publishScript, /assets\/js\/sdf-qualification-review\.mjs/);
});

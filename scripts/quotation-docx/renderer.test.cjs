const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const PizZip = require("pizzip");
const {
  buildRenderModel,
  formatMinor,
  renderQuotationDocx,
} = require("./renderer.cjs");

const templatePath = path.resolve(__dirname, "../../assets/docs/quotation/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx");
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "lws-d3e6-"));

function fixture(overrides = {}) {
  const payload = {
    contract_version: 1,
    mode: "PREVIEW",
    template: { template_id: "LWS_QUOTATION_NL_BE", template_version: "1.0.0-technical", template_sha256: "a".repeat(64), authority_status: "CANDIDATE" },
    quotation: { approval_id: "d3ea5000-0000-4000-8000-000000000001", issuance_id: null, quotation_number: null, quotation_version: null, quotation_status: "NON_AUTHORITATIVE", visible_marker: "CONCEPT — NIET GELDIG ALS OFFERTE" },
    seller: { legal_name: "Lorenzo Web Solutions", address_line_1: "Teststraat 1", address_line_2: null, postal_code: "9000", city: "Gent", country_code: "BE", enterprise_number: "0123456789", vat_number: "BE0123456789", email: "seller@example.test", website: "https://example.test", contact_name: null },
    customer: { customer_id: null, legal_name: "Voorbeeld Klant", contact_name: null, email: "customer@example.test", address_line_1: "Klantstraat 2", address_line_2: null, postal_code: "2000", city: "Antwerpen", country_code: "BE", enterprise_number: null, vat_number: null },
    project: { project_id: null, project_title: "Zakelijke website", project_type: "website", scope_summary: "Ontwerp en ontwikkeling van een professionele website.", requested_languages: ["nl"], included_page_count: 5, features: ["Contactformulier"], copywriting: null, seo: null, hosting: null, maintenance: null, exclusions: [], assumptions: [], indicative_timing: null },
    lines: [{ line_id: "website", sequence: 1, product_or_service_code: "WEBSITE", description: "Websiteontwikkeling", quantity: 1, unit: "project", unit_price_minor: 100000, discount_minor: 0, vat_treatment: "STANDARD", vat_rate: 21, line_net_amount_minor: 100000, cost_type: "ONE_TIME" }],
    totals: { subtotal_net_minor: 100000, one_time_subtotal_minor: 100000, recurring_subtotal_minor: 0, discount_total_minor: 0, vat_base_minor: 100000, vat_amount_minor: 21000, total_gross_minor: 121000 },
    vat: { vat_treatment: "STANDARD", vat_rate: 21, vat_decision_source: "accountant" },
    payment_schedule: { schedule_id: "schedule-1", milestones: [{ sequence: 1, label: "Volledige betaling", percentage: 100, amount_minor: null, trigger: "factuur", due_terms_days: 30, recurring_cycle: null }] },
    validity: { valid_from: "2026-08-15", valid_until: "2026-09-14", validity_days: 30 },
    legal_references: { terms_reference: "Algemene voorwaarden", terms_version: "1.0.0", agreement_reference: null, agreement_version: null },
    acceptance_instruction: "Bevestig uw akkoord volgens de instructies bij deze offerte.",
    pricing_references: { approval_payload_sha256: "c".repeat(64), pricing_snapshot_id: "d3ea2000-0000-4000-8000-000000000001", pricing_snapshot_contract_version: 2 },
    locale: { document_language: "nl", document_locale: "nl-BE", currency: "EUR" },
  };
  Object.assign(payload, overrides);
  return {
    preview_contract_version: 1,
    preview_id: "d3e65000-0000-5000-8000-000000000001",
    created_at: "2026-08-15T12:00:00.000000Z",
    mode: payload.mode,
    is_authoritative: payload.mode === "ISSUE",
    source_identity: { source_type: "IMMUTABLE_APPROVAL", approval_id: payload.quotation.approval_id },
    template: payload.template,
    generation_payload: payload,
    generation_payload_sha256: "d".repeat(64),
    display_markers: payload.mode === "PREVIEW" ? { primary: "CONCEPT — NIET GELDIG ALS OFFERTE", secondary: "Geen officieel offertenummer toegekend." } : null,
    locale: payload.locale,
    requested_output: "DOCX",
  };
}

function extractText(buffer) {
  const zip = new PizZip(buffer);
  return Object.keys(zip.files)
    .filter((name) => /^word\/(document|header\d*|footer\d*)\.xml$/.test(name))
    .map((name) => zip.file(name).asText().replace(/<w:tab\/>/g, "\t").replace(/<w:br\/>/g, "\n").replace(/<[^>]+>/g, " "))
    .join(" ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ");
}

function validatePackage(buffer) {
  const zip = new PizZip(buffer);
  for (const part of ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/_rels/document.xml.rels"]) {
    assert.ok(zip.file(part), `missing required DOCX part ${part}`);
  }
  const relationships = zip.file("word/_rels/document.xml.rels").asText();
  for (const match of relationships.matchAll(/Target="([^"#]+)"/g)) {
    const target = match[1];
    if (/^[a-z]+:/i.test(target)) continue;
    const resolved = path.posix.normalize(path.posix.join("word", target));
    assert.ok(resolved.startsWith("word/"), `relationship escapes word namespace: ${target}`);
    assert.ok(zip.file(resolved), `broken relationship ${target}`);
  }
}

const scenarios = [
  ["minimal preview", fixture()],
  ["normal website quotation", fixture({ project: { ...fixture().generation_payload.project, features: ["Contactformulier", "Nieuwssectie", "SEO-basis"] } })],
  ["multiple lines", fixture({ lines: [fixture().generation_payload.lines[0], { ...fixture().generation_payload.lines[0], line_id: "seo", sequence: 2, description: "SEO-optimalisatie", unit_price_minor: 25000, line_net_amount_minor: 25000 }], totals: { ...fixture().generation_payload.totals, subtotal_net_minor: 125000, one_time_subtotal_minor: 125000, vat_base_minor: 125000, vat_amount_minor: 26250, total_gross_minor: 151250 } })],
  ["mixed one-time recurring", fixture({ lines: [fixture().generation_payload.lines[0], { ...fixture().generation_payload.lines[0], line_id: "hosting", sequence: 2, description: "Hosting per jaar", unit_price_minor: 12000, line_net_amount_minor: 12000, cost_type: "RECURRING" }], totals: { ...fixture().generation_payload.totals, subtotal_net_minor: 112000, recurring_subtotal_minor: 12000 } })],
  ["optional fields absent", fixture()],
  ["discount present", fixture({ lines: [{ ...fixture().generation_payload.lines[0], unit_price_minor: 110000, discount_minor: 10000 }] , totals: { ...fixture().generation_payload.totals, discount_total_minor: 10000 } })],
  ["multiple milestones", fixture({ payment_schedule: { schedule_id: "schedule-2", milestones: [{ sequence: 1, label: "Voorschot", percentage: 50, amount_minor: null, trigger: "start", due_terms_days: 14, recurring_cycle: null }, { sequence: 2, label: "Oplevering", percentage: 50, amount_minor: null, trigger: "oplevering", due_terms_days: 30, recurring_cycle: null }] } })],
  ["exclusions assumptions", fixture({ project: { ...fixture().generation_payload.project, exclusions: ["Fotografie"], assumptions: ["Inhoud tijdig aangeleverd"] } })],
  ["long pagination stress", fixture({ project: { ...fixture().generation_payload.project, project_title: "Uitgebreid digitaal platform voor internationale dienstverlening en langdurige contentpublicatie", scope_summary: "Lange technische beschrijving. ".repeat(80), features: Array.from({ length: 24 }, (_, index) => `Uitgebreide functie ${index + 1}: ${"inhoud ".repeat(12)}`), exclusions: Array.from({ length: 12 }, (_, index) => `Uitsluiting ${index + 1}`), assumptions: Array.from({ length: 12 }, (_, index) => `Aanname ${index + 1}`) }, lines: Array.from({ length: 16 }, (_, index) => ({ ...fixture().generation_payload.lines[0], line_id: `line-${index + 1}`, sequence: index + 1, description: `Lange offertelijn ${index + 1}: ${"detail ".repeat(15)}` })), totals: { ...fixture().generation_payload.totals, subtotal_net_minor: 1600000, one_time_subtotal_minor: 1600000, vat_base_minor: 1600000, vat_amount_minor: 336000, total_gross_minor: 1936000 } })],
  ["TEST_ONLY synthetic issue readiness", fixture({ mode: "ISSUE", quotation: { ...fixture().generation_payload.quotation, issuance_id: "d3e66000-0000-4000-8000-000000000001", quotation_number: "LWS-OFF-2099-0001", quotation_version: 1, quotation_status: "PREPARED", visible_marker: null } })],
];

test("presentation adapter uses integer minor units", () => {
  assert.equal(formatMinor(123456), "€ 1.234,56");
  assert.throws(() => formatMinor(1.5), /INVALID_MINOR_AMOUNT/);
});

test("renderer rejects unsupported contract and locale", () => {
  assert.throws(() => buildRenderModel(fixture({ contract_version: 2 })), /UNSUPPORTED_RENDER_CONTRACT/);
  assert.throws(() => buildRenderModel(fixture({ locale: { document_language: "nl", document_locale: "nl-BE", currency: "USD" } })), /UNSUPPORTED_RENDER_LOCALE/);
});

test("renderer output is byte-deterministic", () => {
  const rendererPackage = fixture();
  const first = renderQuotationDocx({ templatePath, outputPath: path.join(tempRoot, "deterministic-1.docx"), rendererPackage });
  const second = renderQuotationDocx({ templatePath, outputPath: path.join(tempRoot, "deterministic-2.docx"), rendererPackage });
  assert.equal(first.sha256, second.sha256);
  assert.deepEqual(first.buffer, second.buffer);
});

test("canonical ISSUE identity validation is strict and side-effect free", () => {
  const base = fixture().generation_payload.quotation;
  const issue = (quotationNumber, issuanceId = "d3e66000-0000-4000-8000-000000000001") => fixture({
    mode: "ISSUE",
    quotation: { ...base, issuance_id: issuanceId, quotation_number: quotationNumber, quotation_version: 1, quotation_status: "PREPARED", visible_marker: null },
  });
  assert.equal(buildRenderModel(issue("LWS-OFF-2026-0001")).issue_identity[0].quotation_number, "LWS-OFF-2026-0001");
  assert.equal(buildRenderModel(issue("LWS-OFF-2099-0001")).issue_identity[0].quotation_number, "LWS-OFF-2099-0001");
  for (const invalid of ["TEST-LWS-OFF-2026-0001", "LWS-QUOTE-2026-0001", "LWS-OFF-26-0001", "LWS-OFF-2026-001", null]) {
    assert.throws(() => buildRenderModel(issue(invalid)), /INVALID_CANONICAL_ISSUE_IDENTITY/);
  }
  assert.throws(() => buildRenderModel(issue("LWS-OFF-2026-0001", null)), /INVALID_CANONICAL_ISSUE_IDENTITY/);
});

for (const [name, rendererPackage] of scenarios) {
  test(`renders valid DOCX: ${name}`, () => {
    const outputPath = path.join(tempRoot, `${name.replace(/\W+/g, "-")}.docx`);
    const { buffer } = renderQuotationDocx({ templatePath, outputPath, rendererPackage });
    validatePackage(buffer);
    const rendered = extractText(buffer);
    assert.doesNotMatch(rendered, /\{[#/]?[^}]+\}/, "template syntax leaked");
    assert.doesNotMatch(rendered, /\b(null|undefined)\b/i);
    assert.doesNotMatch(rendered, /(capability|integrity_mac|hmac|service_role|[a-f0-9]{64})/i);
    assert.match(rendered, /CANDIDATE \| FINAL_DOCUMENT_PRESENTATION_PHASE DEFERRED/);
    assert.match(rendered, /Lorenzo Web Solutions/);
    assert.match(rendered, /Voorbeeld Klant/);
    assert.ok(rendered.includes(rendererPackage.generation_payload.project.project_title));
    assert.ok(rendered.includes(rendererPackage.generation_payload.lines[0].description));
    assert.match(rendered, /€ 1\.000,00/);
    assert.match(rendered, /21%/);
    assert.match(rendered, /Volledige betaling|Voorschot/);
    assert.match(rendered, /15\/08\/2026/);
    assert.match(rendered, /Algemene voorwaarden/);
    if (rendererPackage.mode === "PREVIEW") {
      assert.match(rendered, /CONCEPT — NIET GELDIG ALS OFFERTE/);
      assert.match(rendered, /Geen officieel offertenummer toegekend/);
      assert.doesNotMatch(rendered, /LWS-OFF-\d{4}-\d{4}/);
    } else {
      assert.match(rendered, /LWS-OFF-2099-0001/);
      assert.doesNotMatch(rendered, /TEST-LWS-OFF/);
      assert.doesNotMatch(rendered, /NIET GELDIG ALS OFFERTE/);
    }
  });
}

test("forbidden backend evidence is rejected before rendering", () => {
  const rendererPackage = fixture();
  rendererPackage.capability_token = "secret";
  assert.throws(() => buildRenderModel(rendererPackage), /FORBIDDEN_RENDER_DATA/);
});

test.after(() => {
  if (process.env.LWS_D3E6_KEEP_OUTPUT !== "1") {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  } else {
    process.stdout.write(`D3E6_OUTPUT=${tempRoot}\n`);
  }
});
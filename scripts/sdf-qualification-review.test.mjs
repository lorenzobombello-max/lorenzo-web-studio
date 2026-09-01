import assert from "node:assert/strict";
import test from "node:test";
import { buildSdfQualificationPresentation, sdfQualificationPrintHtml } from "../assets/js/sdf-qualification-review.mjs";

const fixture = (direction = "pro") => ({
  documentPurpose: { categories: ["invoice", "quotation"] },
  workflowCapabilities: ["receive", "review", "approve"],
  businessRequirements: {
    currentWorkflow: "Inkomende documenten worden handmatig verdeeld.",
    desiredWorkflow: "Documenten automatisch herkennen en laten goedkeuren.",
    volumeBand: "50_to_249",
    frequency: "monthly",
    relevantDocumentTypes: ["Facturen", "Offertes"],
    rolesUsers: ["Boekhouding", "Zaakvoerder"],
  },
  sampleDocumentMetadata: { available: true, requestedByLws: false, uploadRequiredLater: true },
  commercialQualification: {
    packageDirection: direction,
    customComplexity: direction === "maatwerk" ? "Koppeling met twee ERP-systemen" : "",
    flowCount: 6,
    userCount: 25,
    documentVolumes: [
      { documentType: "invoice", documentCount: 120, period: "monthly", averagePagesPerDocument: 2 },
      { documentType: "quotation", documentCount: 30, period: "quarterly", averagePagesPerDocument: 5 },
    ],
  },
});

const values = (presentation) => presentation.sections.flatMap((section) => section.rows.flatMap((row) => [row.label, row.value])).join("\n");

test("PRO review contains all canonical customer-facing qualification data and derived pages", () => {
  const review = buildSdfQualificationPresentation(fixture(), { preparedAt: "2026-08-31T10:00:00Z", status: "Concept — nog niet ingediend" });
  const output = values(review);
  for (const expected of [
    "PRO", "€7.500 implementatie · €449/maand · excl. btw", "Factuur", "120 documenten per maand",
    "Gemiddeld 2 pagina's per document", "Geschat volume: 240 pagina's per maand", "Offerte",
    "30 documenten per kwartaal", "Geschat volume: 150 pagina's per kwartaal", "Ontvangen, Controleren, Goedkeuren",
    "Afzonderlijke document- of businessflows", "6", "Gebruikersaccounts of personen", "25",
    "Inkomende documenten worden handmatig verdeeld.", "Documenten automatisch herkennen en laten goedkeuren.",
    "1 tot 9".replace("1 tot 9", "50 tot 249"), "Maandelijks", "Facturen, Offertes", "Boekhouding, Zaakvoerder",
  ]) assert.match(output, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.doesNotMatch(output, /\binvoice\b|\bquotation\b|\breceive\b|\breview\b|50_to_249/);
});

test("maatwerk context is conditional and package directions remain distinct", () => {
  const custom = values(buildSdfQualificationPresentation(fixture("maatwerk")));
  const standard = values(buildSdfQualificationPresentation(fixture("groei")));
  assert.match(custom, /Koppeling met twee ERP-systemen/);
  assert.doesNotMatch(standard, /Maatwerkcontext|Koppeling met twee ERP-systemen/);
  for (const [key, label] of [["start", "START"], ["groei", "GROEI"], ["pro", "PRO"], ["maatwerk", "MAATWERK"], ["advice_requested", "ADVIES GEWENST"]]) {
    assert.match(values(buildSdfQualificationPresentation(fixture(key))), new RegExp(label));
  }
});

test("print document uses A4 stylesheet, includes complete review, and excludes capability material", () => {
  const html = sdfQualificationPrintHtml(buildSdfQualificationPresentation(fixture(), { reference: "LWS-AAN-2026-0001", preparedAt: "2026-08-31T10:00:00Z", status: "Concept" }));
  for (const expected of ["Lorenzo Web Solutions", "Slimme Documentenflow — Intake", "LWS-AAN-2026-0001", "PRO", "Factuur", "240 pagina&#39;s per maand", "Ontvangen, Controleren, Goedkeuren", "De uiteindelijke scope en prijs worden bevestigd in uw offerte.", "sdf-qualification-print.css"]) assert.match(html, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.doesNotMatch(html, /token=|capability|Bearer|aaaaaaaaaaaaaaaa/);
  assert.doesNotMatch(html, /<input|<button|data-step-target/);
});

test("operator print context adds only explicit dossier metadata", () => {
  const presentation = buildSdfQualificationPresentation(fixture(), {
    reference: "LWS-AAN-2026-0001",
    intakeReference: "8c20163c-3c52-45ea-b3e2-11c2e49bc231",
    customerName: "Ada Lovelace",
    organization: "Analytical Engines BV",
    email: "ada@example.test",
    status: "Ingediend",
    taxonomyVersion: "sdf_qualification_intake/2.0.0",
    preparedAt: "2026-08-31T09:30:00.000Z",
  });
  const html = sdfQualificationPrintHtml(presentation);
  for (const expected of ["Ada Lovelace", "Analytical Engines BV", "ada@example.test", "Ingediend", "sdf_qualification_intake/2.0.0"]) assert.match(html, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.doesNotMatch(html, /capability|authorization|bearer|token/i);
});

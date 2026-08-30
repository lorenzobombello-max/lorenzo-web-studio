import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  sdfQualificationDetailPresentation,
  sdfQualificationDetailRequest,
  sdfQualificationStatusPresentation,
} from "../assets/js/operator-dashboard.js";
import { buildSdfQualificationPresentation, sdfQualificationPrintHtml } from "../assets/js/sdf-qualification-review.mjs";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");
const quoteRequestId = "bd200000-0000-4000-8000-000000000001";
const intakeId = "bd300000-0000-4000-8000-000000000001";
const application = {
  quote_request_id: quoteRequestId,
  request_kind: "slimme_documentenflow",
  application_reference: "LWS-AAN-2026-0001",
  support_reference: "A1B2C3D4",
  name: "Ada Lovelace",
  company: "Analytical Engines BV",
  email: "ada@example.test",
};
const answers = (direction = "pro") => ({
  documentPurpose: { categories: ["invoice", "contract"] },
  workflowCapabilities: ["receive", "review", "approve"],
  businessRequirements: {
    currentWorkflow: "Documenten komen per e-mail binnen.",
    desiredWorkflow: "Centraal ontvangen, controleren en goedkeuren.",
    volumeBand: "50_to_249",
    frequency: "monthly",
    relevantDocumentTypes: ["Facturen", "Contracten"],
    rolesUsers: ["Boekhouding", "Zaakvoerder"],
  },
  sampleDocumentMetadata: { available: true, requestedByLws: false, uploadRequiredLater: true },
  commercialQualification: {
    packageDirection: direction,
    customComplexity: direction === "maatwerk" ? "Koppeling met twee ERP-systemen" : "",
    documentVolumes: [
      { documentType: "invoice", documentCount: 120, period: "monthly", averagePagesPerDocument: 2 },
      { documentType: "contract", documentCount: 12, period: "quarterly", averagePagesPerDocument: 8 },
    ],
  },
});
const readModel = (status = "submitted", direction = "pro") => ({
  quote_request_id: quoteRequestId,
  name: application.name,
  company: application.company,
  email: application.email,
  sdf_package: "groei",
  intake_id: intakeId,
  status,
  taxonomy_version: "sdf_qualification_intake/2.0.0",
  draft_revision: 4,
  latest_submission_sequence: 1,
  latest_submission: answers(direction),
  latest_submission_sha256: "a".repeat(64),
});
const text = (presentation) => presentation.sections.flatMap((section) => section.rows.flatMap((row) => [row.label, row.value])).join("\n");

test("operator detail requests only the existing SDF inspect action", () => {
  assert.deepEqual(sdfQualificationDetailRequest(application), { action: "inspect_sdf_qualification_intake", quote_request_id: quoteRequestId });
  assert.throws(() => sdfQualificationDetailRequest({ ...application, request_kind: "website" }), /INVALID_SDF_QUALIFICATION_DETAIL_REQUEST/);
  assert.throws(() => sdfQualificationDetailRequest({ ...application, quote_request_id: "invalid" }), /INVALID_SDF_QUALIFICATION_DETAIL_REQUEST/);
});

test("submitted PRO detail reuses the complete canonical customer presentation", () => {
  const output = sdfQualificationDetailPresentation(readModel(), application, "2026-08-31T10:00:00.000Z");
  assert.equal(output.meta.intakeReference, intakeId);
  assert.equal(output.context.intakeReference, "#BD300000");
  const presentation = buildSdfQualificationPresentation(output.answers, output.context);
  const rendered = text(presentation);
  for (const expected of [
    "LWS-AAN-2026-0001", "#BD300000", "Ada Lovelace", "Analytical Engines BV", "ada@example.test",
    "Ingediend", "sdf_qualification_intake/2.0.0", "PRO", "Factuur", "Contract",
    "120 documenten per maand", "Gemiddeld 2 pagina's per document", "Geschat volume: 240 pagina's per maand",
    "12 documenten per kwartaal", "Geschat volume: 96 pagina's per kwartaal", "Ontvangen, Controleren, Goedkeuren",
    "Documenten komen per e-mail binnen.", "Centraal ontvangen, controleren en goedkeuren.",
    "50 tot 249", "Maandelijks", "Facturen, Contracten", "Boekhouding, Zaakvoerder", "Beschikbaar", "Ja",
  ]) assert.match(rendered, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  const printHtml = sdfQualificationPrintHtml(presentation);
  assert.match(printHtml, /Afdrukweergave|Slimme Documentenflow|PRO/);
  assert.doesNotMatch(printHtml, /capability|authorization|bearer|token|latest_submission_sha256/i);
});

test("all authority statuses remain human-readable without changing active-work semantics", () => {
  const expected = {
    invited: ["Uitgenodigd", false, ""], in_progress: ["In uitvoering", false, "amber"], submitted: ["Ingediend", true, "amber"],
    under_review: ["In beoordeling", true, "amber"], changes_requested: ["Aanvulling gevraagd", false, "amber"],
    qualification_complete: ["Kwalificatie voltooid", false, "green"], closed: ["Gesloten", false, ""],
  };
  for (const [status, [label, activeWork, tone]] of Object.entries(expected)) assert.deepEqual(sdfQualificationStatusPresentation(status), { value: status, label, activeWork, tone });
  assert.throws(() => sdfQualificationStatusPresentation("invented"), /INVALID_SDF_QUALIFICATION_STATUS/);
});

test("package labels are shared and maatwerk context remains conditional", () => {
  for (const [direction, label] of [["start", "START"], ["groei", "GROEI"], ["pro", "PRO"], ["maatwerk", "MAATWERK"], ["advice_requested", "ADVIES GEWENST"]]) {
    const output = sdfQualificationDetailPresentation(readModel("submitted", direction), application);
    const rendered = text(buildSdfQualificationPresentation(output.answers, output.context));
    assert.match(rendered, new RegExp(label));
    if (direction === "maatwerk") assert.match(rendered, /Koppeling met twee ERP-systemen/);
    else assert.doesNotMatch(rendered, /Maatwerkcontext|Koppeling met twee ERP-systemen/);
  }
});

test("pending intake presents status but never fabricates submitted answers", () => {
  const pending = { ...readModel("invited"), latest_submission_sequence: 0, latest_submission: null, latest_submission_sha256: null };
  const output = sdfQualificationDetailPresentation(pending, application);
  assert.equal(output.status.label, "Uitgenodigd");
  assert.equal(output.status.activeWork, false);
  assert.equal(output.answers, null);
  assert.equal(output.meta.submissionSequence, "Nog niet ingediend");
  assert.throws(() => sdfQualificationDetailPresentation({ ...pending, status: "submitted" }, application), /INVALID_SDF_QUALIFICATION_DETAIL/);
});

test("dashboard wiring stays owner-authorized, caller-JWT based, responsive, and print-safe", async () => {
  const [html, dashboard, migration, edgeIndex, css, printCss] = await Promise.all([
    read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js"),
    read("supabase/migrations/20260831110000_add_sdf_qualification_automation_bridge_v1.sql"),
    read("supabase/functions/commercial-operator-command/index.ts"), read("assets/css/operator-dashboard.css"),
    read("assets/css/sdf-qualification-print.css"),
  ]);
  assert.match(html, /id="sdfQualificationDossier"/);
  assert.match(html, /id="sdfQualificationPrint"[^>]*>Afdrukken \/ Opslaan als PDF/);
  assert.match(dashboard, /renderSdfQualificationReview\(sdfQualificationReview, output\.answers, output\.context\)/);
  assert.match(dashboard, /printSdfQualificationReview\(output\.answers, output\.context\)/);
  assert.match(dashboard, /loadSdfQualification\(application, requestId\)/);
  assert.match(migration, /create function public\.inspect_sdf_qualification_intake_for_operator_v1/);
  assert.match(migration, /v_operator:=lws_internal\.assert_sdf_owner_v1\(\)/);
  const inspectDispatch = edgeIndex.match(/if \(input\.action === "inspect_sdf_qualification_intake"\)[\s\S]*?return data;\s*}/)?.[0] || "";
  assert.match(inspectDispatch, /clientFor\(jwt\)\.rpc\("inspect_sdf_qualification_intake_for_operator_v1"/);
  assert.doesNotMatch(inspectDispatch, /serviceClient/);
  assert.match(css, /@media \(max-width:700px\) \{ \.sdf-operator-review dl div \{ grid-template-columns:1fr;/);
  assert.match(printCss, /@page \{ size: A4 portrait; margin: 15mm 12mm 12mm; \}/);
  const panel = html.match(/<section id="sdfQualificationDossier"[\s\S]*?<\/section>/)?.[0] || "";
  assert.doesNotMatch(panel, /capability|authorization|bearer|service_role|token/i);
});

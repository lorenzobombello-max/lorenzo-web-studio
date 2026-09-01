import { assertEquals, assertRejects, assertStringIncludes, assertThrows } from "jsr:@std/assert@1";
import PizZip from "npm:pizzip@3.2.0";
import {
  renderSdfQuotationDocumentXml,
  renderSdfQuotationDocxBytes,
} from "./sdf-quotation-renderer-edge.ts";
import {
  createSdfSyntheticRendererPackage as rendererPackage,
  SDF_SYNTHETIC_EXECUTION_TERM_WEEKS as executionTerms,
  SDF_SYNTHETIC_PACKAGE_AMOUNTS as packageAmounts,
} from "../../../scripts/quotation-docx/sdf-synthetic-fixture.ts";

const OFFICIAL_TEMPLATE = new URL(
  "../../../assets/docs/quotation/LWS_SDF_QUOTATION_NL_BE_OFFICIAL_v1.docx",
  import.meta.url,
);

function mutablePackage(packageKey: keyof typeof packageAmounts): Record<string, any> {
  return structuredClone(rendererPackage(packageKey));
}

Deno.test("SDF renderer binds each authoritative package to the official template", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  for (const packageKey of Object.keys(packageAmounts) as Array<keyof typeof packageAmounts>) {
    const first = await renderSdfQuotationDocxBytes({
      templateBytes,
      rendererPackage: rendererPackage(packageKey),
    });
    const second = await renderSdfQuotationDocxBytes({
      templateBytes,
      rendererPackage: rendererPackage(packageKey),
    });
    assertEquals(first.sha256, second.sha256);
    assertEquals(first.buffer, second.buffer);
    const xml = new PizZip(first.buffer).file("word/document.xml")?.asText() || "";
    assertStringIncludes(xml, "TEST-SDF-2026-0001");
    assertStringIncludes(xml, "Voorbeeldbedrijf BV");
    assertStringIncludes(xml, "Factuur, Creditnota");
    assertStringIncludes(xml, "Gecontroleerde verwerking van inkomende facturen.");
    assertStringIncludes(xml, "Facturen zijn betaalbaar binnen 14 dagen na factuurdatum");
    assertStringIncludes(xml, `uitvoeringstermijn tot functionele oplevering/testfase bedraagt ${executionTerms[packageKey]} weken`);
    assertStringIncludes(xml, "☒");
  }
});

Deno.test("SDF renderer rejects Website payloads before rendering", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const input = rendererPackage("start");
  input.generation_payload.product_family = "website";
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: input }),
    Error,
    "SDF_RENDER_PRODUCT_INVALID",
  );
});

Deno.test("SDF renderer rejects non-authority template bytes", async () => {
  await assertRejects(
    () => renderSdfQuotationDocxBytes({
      templateBytes: new Uint8Array([1, 2, 3]),
      rendererPackage: rendererPackage("start"),
    }),
    Error,
    "SDF_TEMPLATE_HASH_MISMATCH",
  );
});

Deno.test("SDF renderer fails closed when a structural anchor drifts", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const documentXml = new PizZip(templateBytes).file("word/document.xml")?.asText() || "";
  const driftedXml = documentXml.replace("Offertenummer", "Offertenummer gewijzigd");
  await assertRejects(
    async () => renderSdfQuotationDocumentXml(driftedXml, rendererPackage("start")),
    Error,
    "SDF_RENDER_TEMPLATE_STRUCTURE_DRIFT",
  );
});

Deno.test("SDF renderer rejects missing or invalid package authority", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const missingScope = mutablePackage("start");
  delete missingScope.generation_payload.sdf_scope;
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: missingScope }),
    Error,
    "SDF_RENDER_SCOPE_REQUIRED",
  );

  const invalidPackage = mutablePackage("start");
  invalidPackage.generation_payload.sdf_scope.package_key = "website";
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: invalidPackage }),
    Error,
    "SDF_RENDER_PACKAGE_INVALID",
  );
});

Deno.test("SDF renderer rejects unapproved or mismatched template identity", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const unapproved = mutablePackage("start");
  unapproved.generation_payload.template.authority_status = "CANDIDATE";
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: unapproved }),
    Error,
    "SDF_RENDER_TEMPLATE_IDENTITY_INVALID",
  );

  const wrongHash = mutablePackage("start");
  wrongHash.generation_payload.template.template_sha256 = "a".repeat(64);
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: wrongHash }),
    Error,
    "SDF_RENDER_TEMPLATE_IDENTITY_INVALID",
  );
});

Deno.test("SDF renderer rejects manipulated prices and MAATWERK amounts", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const manipulated = mutablePackage("start");
  manipulated.generation_payload.sdf_scope.implementation_amount_minor = 1;
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: manipulated }),
    Error,
    "SDF_RENDER_AUTHORITY_MISMATCH",
  );

  const maatwerkGap = mutablePackage("maatwerk");
  maatwerkGap.generation_payload.sdf_scope.implementation_amount_minor = 900000;
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: maatwerkGap }),
    Error,
    "SDF_RENDER_MAATWERK_AUTHORITY_INVALID",
  );
});

Deno.test("SDF renderer rejects malformed document XML", () => {
  assertThrows(
    () => renderSdfQuotationDocumentXml("<w:document", rendererPackage("start")),
    Error,
    "SDF_RENDER_DOCX_MALFORMED",
  );
});

Deno.test("SDF renderer rejects forbidden raw authority data", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const input = mutablePackage("start");
  input.generation_payload.sdf_scope.raw_intake = { answer: "secret" };
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: input }),
    Error,
    "FORBIDDEN_RENDER_DATA:raw_intake",
  );
});

Deno.test("SDF renderer requires the approved project scope summary without title fallback", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const input = mutablePackage("start");
  input.generation_payload.project.project_title = "Niet gebruiken als beschrijving";
  delete input.generation_payload.project.scope_summary;
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: input }),
    Error,
    "SDF_RENDER_PROJECT_DESCRIPTION_REQUIRED",
  );
});

Deno.test("SDF renderer requires one unambiguous approved milestone payment term", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const missing = mutablePackage("start");
  delete missing.generation_payload.payment_schedule.milestones[0].due_terms_days;
  missing.generation_payload.sdf_scope.payment_milestones = missing.generation_payload.payment_schedule.milestones;
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: missing }),
    Error,
    "SDF_RENDER_PAYMENT_TERM_INVALID",
  );

  const ambiguous = mutablePackage("start");
  ambiguous.generation_payload.payment_schedule.milestones[2].due_terms_days = 30;
  ambiguous.generation_payload.sdf_scope.payment_milestones = ambiguous.generation_payload.payment_schedule.milestones;
  await assertRejects(
    () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: ambiguous }),
    Error,
    "SDF_RENDER_PAYMENT_TERM_AMBIGUOUS",
  );
});

Deno.test("SDF renderer requires a positive whole-week approved execution term", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  for (const value of [undefined, null, 0, -1, 3.5]) {
    const input = mutablePackage("start");
    input.generation_payload.project.indicative_timing = value;
    await assertRejects(
      () => renderSdfQuotationDocxBytes({ templateBytes, rendererPackage: input }),
      Error,
      "SDF_RENDER_EXECUTION_TERM_INVALID",
    );
  }
});

Deno.test("SDF execution term comes from the approved snapshot, not the package", async () => {
  const templateBytes = await Deno.readFile(OFFICIAL_TEMPLATE);
  const first = mutablePackage("start");
  const second = mutablePackage("start");
  first.generation_payload.project.indicative_timing = 3;
  second.generation_payload.project.indicative_timing = 11;
  const firstXml = new PizZip((await renderSdfQuotationDocxBytes({
    templateBytes,
    rendererPackage: first,
  })).buffer).file("word/document.xml")?.asText() || "";
  const secondXml = new PizZip((await renderSdfQuotationDocxBytes({
    templateBytes,
    rendererPackage: second,
  })).buffer).file("word/document.xml")?.asText() || "";
  assertStringIncludes(firstXml, "bedraagt 3 weken");
  assertStringIncludes(secondXml, "bedraagt 11 weken");
});
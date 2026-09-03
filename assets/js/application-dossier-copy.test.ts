import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildApplicationDossierPresentation,
  createApplicationDossierPdf,
  measureApplicationDossierPdfText,
  printApplicationDossier,
} from "./application-dossier-copy.js";
import type { ApplicationOutput } from "../../supabase/functions/_shared/application-output.ts";

const application: ApplicationOutput = {
  applicationReference: "LWS-AAN-2026-0042",
  submittedAt: "2026-08-28T13:14:51.504Z",
  customer: { name: "Test Klant", company: "Test BV", email: "test@example.test", phone: "+32 470 00 00 00" },
  commercial: {
    packageId: "professional_v2",
    packageLabel: "Professional",
    budgetLabel: "EUR 5.000 - EUR 7.500",
    knownMinimumMinor: 350000,
    currency: "EUR",
    vatBasis: "exclusive",
    budgetStatus: "within",
    recurringServices: [{ productId: "care_plus", label: "LWS Care+", amountMinor: 9900, unit: "month" }],
  },
  project: {
    websiteType: "Bedrijfswebsite", businessDescription: null, targetAudience: null,
    hasExistingWebsite: false, currentWebsite: null, elementsToKeep: null,
    improvementAreas: null, domain: null, hostingStatus: null, goals: [],
    primaryConversionGoal: null,
  },
  website: {
    pages: ["Home", "Over ons"], webshop: true, booking: false,
    primaryLanguage: "nl", additionalLanguages: ["fr"],
    otherPages: null, features: [], webshopDetails: null, bookingDetails: null,
    pageScopeDetails: null, quoteFormDetails: null, multilingualDetails: null,
    downloadDetails: null, newsletterDetails: null, integrations: [],
    socialChannels: [], seoPriority: null, seoDetails: null,
  },
  brandingContent: {
    brandStatus: "Bestaand", logoStatus: "Bestaand",
    contentStatus: "Wordt aangeleverd", imageStatus: "Hulp gewenst",
    brandColors: [], designStyles: [], inspirationSites: [], dislikedStyles: null,
    imageSupport: [], contentMediaDetails: null,
  },
  servicePlanning: {
    deadline: "2026-11-01", timing: "Binnen 3 maanden", domainStatus: null,
    maintenanceInterest: null, hostingSupport: null, hostingMaintenanceDetails: null,
    deadlineReason: null, deadlineDetails: null, priorities: [], budgetNotes: null,
    notes: null,
  },
};

const pending = {
  kind: "pending_intake",
  reference: "#77EE2F45",
  requestKind: "website",
  status: "invited",
  statusLabel: "Uitgenodigd",
  websiteType: "Website op maat",
  customer: { name: "Pending Klant", company: null, email: "pending@example.test", phone: null },
  request: {
    requestedAt: "2026-09-03T01:25:00Z",
    requestedService: "Website",
    originalText: "Volledige oorspronkelijke aanvraagtekst.",
  },
  intake: {
    invitedAt: "2026-09-03T01:31:00Z",
    startedAt: null,
    submittedAt: null,
    structuredAnswers: {
      shop_required: false,
      website_goals: ["Meer aanvragen"],
      budget_notes: null,
      shop_details: { online_payments: false, categories: [] },
    },
  },
  documents: { customerRequestCount: 2, uploadedDocumentCount: 1 },
} as const;

Deno.test("dossier presentation is one stable customer and operator truth", () => {
  const dossier = buildApplicationDossierPresentation(application);
  assertEquals(dossier.reference, "LWS-AAN-2026-0042");
  assertEquals(dossier.title, "Kopie van ingediende aanvraag");
  assertStringIncludes(dossier.disclaimer, "geen definitieve offerte of overeenkomst");
  assertStringIncludes(dossier.disclaimer, "indicatief en niet-bindend");
  assertEquals(dossier.sections.flatMap((section) => section.rows).find((row) => row.label === "Webshop")?.value, "Ja");
  assertEquals(dossier.sections.flatMap((section) => section.rows).find((row) => row.label === "Boeking/reservatie")?.value, "Nee");
  assertStringIncludes(dossier.sections[0].rows[1].value, "15:14");
});

Deno.test("invited and in-progress authority payloads normalize to the canonical dossier presentation", () => {
  for (const [status, statusLabel] of [["invited", "Uitgenodigd"], ["in_progress", "Intake bezig"]] as const) {
    const dossier = buildApplicationDossierPresentation({ ...pending, status, statusLabel });
    const rows = dossier.sections.flatMap((group) => group.rows);
    assertEquals(dossier.title, "Dossierkopie");
    assertEquals(dossier.reference, "#77EE2F45");
    assertEquals(rows.find((row) => row.label === "Status")?.value, statusLabel);
    assertEquals(rows.find((row) => row.label === "Volledige aanvraagtekst")?.value, pending.request.originalText);
    assertEquals(rows.find((row) => row.label === "shop required")?.value, "Nee");
    assertEquals(rows.find((row) => row.label === "website goals")?.value, "Meer aanvragen");
    assertEquals(rows.find((row) => row.label === "budget notes")?.value, "Niet beschikbaar");
    assertEquals(rows.find((row) => row.label === "shop details")?.value, "categories: Niet beschikbaar; online payments: Nee");
    assertEquals(rows.find((row) => row.label === "Klantverzoeken")?.value, "2");
  }
});

Deno.test("pending dossier PDF uses the same engine and remains deterministic with partial fields", () => {
  const first = createApplicationDossierPdf(pending);
  const second = createApplicationDossierPdf({
    ...pending,
    customer: { ...pending.customer, company: undefined },
    documents: { customerRequestCount: undefined, uploadedDocumentCount: undefined },
    intake: { ...pending.intake, structuredAnswers: {} },
  });
  assertEquals(first.type, "application/pdf");
  assertEquals(first.fileName, "aanvraag-#77EE2F45.pdf");
  assertEquals(new TextDecoder().decode(first.bytes.slice(0, 8)), "%PDF-1.4");
  const partialSource = new TextDecoder("windows-1252").decode(second.bytes);
  assertStringIncludes(partialSource, "Niet beschikbaar");
  assertStringIncludes(partialSource, "Beschikbare antwoorden");
});

Deno.test("pending dossier print uses the canonical presentation and triggers the print flow", () => {
  const globalScope = globalThis as typeof globalThis & { document?: unknown };
  const originalDocument = globalScope.document;
  let loadListener = () => {};
  let printCalls = 0;
  let appended = false;
  const frame = {
    hidden: false,
    title: "",
    srcdoc: "",
    contentWindow: { focus() {}, print() { printCalls += 1; } },
    addEventListener(_type: string, listener: () => void) { loadListener = listener; },
    remove() {},
  };
  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: {
      createElement: () => frame,
      body: { append(node: unknown) { appended = node === frame; } },
    },
  });
  try {
    printApplicationDossier(pending);
    assertEquals(appended, true);
    assertStringIncludes(frame.srcdoc, "#77EE2F45");
    assertStringIncludes(frame.srcdoc, "Volledige oorspronkelijke aanvraagtekst.");
    loadListener();
    assertEquals(printCalls, 1);
  } finally {
    Object.defineProperty(globalThis, "document", { configurable: true, value: originalDocument });
  }
});

Deno.test("download preserves euro and common Dutch and French characters", () => {
  const pdf = createApplicationDossierPdf({
    ...application,
    customer: { ...application.customer, name: "Renée Noël", company: "Dëmo € BV" },
    servicePlanning: { ...application.servicePlanning, notes: "Crème brûlée, België" },
  });
  assertEquals(pdf.type, "application/pdf");
  assertEquals(pdf.fileName, "aanvraag-LWS-AAN-2026-0042.pdf");
  assertEquals(new TextDecoder().decode(pdf.bytes.slice(0, 8)), "%PDF-1.4");
  const source = new TextDecoder("windows-1252").decode(pdf.bytes);
  assertStringIncludes(source, "Kopie van ingediende aanvraag");
  assertStringIncludes(source, "geen definitieve offerte of overeenkomst");
  assertStringIncludes(source, "Dëmo € BV");
  assertStringIncludes(source, "Renée Noël");
  assertStringIncludes(source, "Crème brûlée, België");
  assertEquals(source.includes("?"), false);
  assertStringIncludes(source, "/MediaBox [0 0 842 595]");
  assertEquals(source.match(/\/Type \/Page\b/g)?.length, 1);
});

Deno.test("PDF preserves Greek mu through the built-in Symbol font", () => {
  const pdf = createApplicationDossierPdf({
    ...pending,
    request: { ...pending.request, originalText: "Maatvoering: 5.25 μm" },
  });
  const source = new TextDecoder("windows-1252").decode(pdf.bytes);
  assertEquals(new TextDecoder().decode(pdf.bytes.slice(0, 8)), "%PDF-1.4");
  assertStringIncludes(source, "/BaseFont /Symbol");
  assertStringIncludes(source, "/F2 8.5 Tf\n(m) Tj");
});

Deno.test("PDF generation fails explicitly for characters outside WinAnsi", () => {
  let message = "";
  try {
    createApplicationDossierPdf({
      ...application,
      servicePlanning: { ...application.servicePlanning, notes: "Niet-WinAnsi: 漢" },
    });
  } catch (error) {
    message = error instanceof Error ? error.message : String(error);
  }
  assertEquals(message, "UNSUPPORTED_PDF_CHARACTER_U+6F22");
});

Deno.test("long URL tokens wrap losslessly within every PDF column", () => {
  const longUrl = `https://example.test/${"a".repeat(180)}`;
  const pdf = createApplicationDossierPdf({
    ...application,
    brandingContent: { ...application.brandingContent, inspirationSites: [longUrl] },
  });
  const source = new TextDecoder("windows-1252").decode(pdf.bytes);
  const writtenLines = [...source.matchAll(/^\((.*)\) Tj$/gm)].map((match) => match[1]);
  const urlLines = writtenLines.filter((line) => line.includes("https://") || /^a+$/.test(line));

  assertEquals(writtenLines.every((line) => measureApplicationDossierPdfText(line) <= 373), true);
  assertEquals(urlLines.length > 1, true);
  assertEquals(urlLines.join(""), longUrl);
});

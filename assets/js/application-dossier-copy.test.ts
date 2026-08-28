import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  buildApplicationDossierPresentation,
  createApplicationDossierPdf,
  measureApplicationDossierPdfText,
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

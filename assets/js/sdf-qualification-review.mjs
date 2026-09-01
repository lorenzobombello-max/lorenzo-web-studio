export const SDF_QUALIFICATION_DISCLAIMER = "De uiteindelijke scope en prijs worden bevestigd in uw offerte.";

const PACKAGE_PRESENTATION = Object.freeze({
  start: { label: "START", reference: "€2.850 implementatie · €175/maand · excl. btw", scope: "Max. 1 documentflow · 2 documenttypes/templates · 500 pagina's/maand · Tot 3 gebruikersaccounts" },
  groei: { label: "GROEI", reference: "€5.700 implementatie · €299/maand · excl. btw", scope: "Max. 3 documentflows · 5 documenttypes/templates · 2.500 pagina's/maand · Tot 10 gebruikersaccounts" },
  pro: { label: "PRO", reference: "€7.500 implementatie · €449/maand · excl. btw", scope: "Max. 6 documentflows · 10 documenttypes/templates · 7.500 pagina's/maand · Tot 25 gebruikersaccounts" },
  maatwerk: { label: "MAATWERK", reference: "Prijs na beoordeling en offerte", scope: "Boven PRO-grenzen of uitzonderlijke complexiteit" },
  advice_requested: { label: "ADVIES GEWENST", reference: "Persoonlijke beoordeling", scope: "Lorenzo Web Solutions bepaalt samen met u de passende richting" },
});

const DOCUMENT_LABELS = Object.freeze({
  quotation: "Offerte", invoice: "Factuur", order_confirmation: "Bestelbevestiging", work_order: "Werkbon",
  delivery_note: "Leveringsbon", contract: "Contract", customer_document: "Klantendocument",
  supplier_document: "Leveranciersdocument", internal_administrative_document: "Intern administratief document",
  multiple_document_types: "Meerdere documenttypes", other_custom: "Ander documenttype",
  unknown_qualification_required: "Nog te bepalen",
});
const WORKFLOW_LABELS = Object.freeze({ receive: "Ontvangen", generate: "Genereren", review: "Controleren", approve: "Goedkeuren", send: "Verzenden", archive: "Archiveren", retrieve: "Terugvinden" });
const PERIOD_LABELS = Object.freeze({ weekly: "per week", monthly: "per maand", quarterly: "per kwartaal", yearly: "per jaar" });
const VOLUME_LABELS = Object.freeze({ "1_to_9": "1 tot 9", "10_to_49": "10 tot 49", "50_to_249": "50 tot 249", "250_plus": "250 of meer", unknown: "Nog niet bekend" });
const FREQUENCY_LABELS = Object.freeze({ daily: "Dagelijks", weekly: "Wekelijks", monthly: "Maandelijks", ad_hoc: "Wanneer nodig", unknown: "Nog niet bekend" });

const text = (value, fallback = "Niet opgegeven") => typeof value === "string" && value.trim() ? value.trim() : fallback;
const list = (values, labels = {}) => Array.isArray(values) && values.length ? values.map((value) => labels[value] || value).join(", ") : "Niet opgegeven";
const yesNo = (value) => value === true ? "Ja" : "Nee";
const section = (title, rows) => ({ title, rows: rows.filter(Boolean).map(([label, value]) => ({ label, value })) });
const formatDate = (value) => new Intl.DateTimeFormat("nl-BE", { dateStyle: "long", timeStyle: "short", timeZone: "Europe/Brussels" }).format(new Date(value));

export function buildSdfQualificationPresentation(data, context = {}) {
  if (!data || typeof data !== "object") throw new TypeError("INVALID_SDF_QUALIFICATION_REVIEW");
  const purpose = data.documentPurpose || {};
  const commercial = data.commercialQualification || {};
  const requirements = data.businessRequirements || {};
  const samples = data.sampleDocumentMetadata || {};
  const packageInfo = PACKAGE_PRESENTATION[commercial.packageDirection] || { label: "Niet gekozen", reference: "Niet beschikbaar", scope: "Niet beschikbaar" };
  const volumes = Array.isArray(commercial.documentVolumes) ? commercial.documentVolumes : [];
  const volumeByType = new Map(volumes.map((volume) => [volume.documentType, volume]));
  const documentRows = (purpose.categories || []).map((documentType) => {
    const volume = volumeByType.get(documentType) || {};
    const label = documentType === "other_custom" ? text(purpose.otherDescription, DOCUMENT_LABELS.other_custom) : DOCUMENT_LABELS[documentType] || documentType;
    const period = PERIOD_LABELS[volume.period] || "periode niet opgegeven";
    const estimatedPages = Number.isInteger(volume.documentCount) && Number.isInteger(volume.averagePagesPerDocument)
      ? volume.documentCount * volume.averagePagesPerDocument : null;
    return [label, `${volume.documentCount ?? "Niet opgegeven"} documenten ${period}\nGemiddeld ${volume.averagePagesPerDocument ?? "Niet opgegeven"} pagina's per document\nGeschat volume: ${estimatedPages ?? "Niet opgegeven"} pagina's ${period}`];
  });
  const preparedAt = context.preparedAt || new Date().toISOString();
  const overviewRows = [
    context.reference ? ["Aanvraagreferentie", text(context.reference)] : null,
    context.intakeReference ? ["Qualificationreferentie", text(context.intakeReference)] : null,
    context.customerName ? ["Klant", text(context.customerName)] : null,
    context.organization ? ["Organisatie", text(context.organization)] : null,
    context.email ? ["E-mail", text(context.email)] : null,
    ["Datum", formatDate(preparedAt)],
    ["Status", text(context.status, "Concept — nog niet ingediend")],
    context.taxonomyVersion ? ["Schema", text(context.taxonomyVersion)] : null,
  ];
  const packageRows = [
    ["Richting", packageInfo.label], ["Commerciële referentie", packageInfo.reference], ["Inbegrepen maximum", packageInfo.scope],
    ["Afzonderlijke document- of businessflows", commercial.flowCount ?? "Niet opgegeven"],
    ["Gebruikersaccounts of personen", commercial.userCount ?? "Niet opgegeven"],
    commercial.packageDirection === "maatwerk" ? ["Maatwerkcontext", text(commercial.customComplexity)] : null,
  ];
  return {
    brand: "Lorenzo Web Solutions",
    title: "Slimme Documentenflow — Intake",
    reference: context.reference || "Concept",
    disclaimer: SDF_QUALIFICATION_DISCLAIMER,
    sections: [
      section("Overzicht", overviewRows),
      section("Commerciële richting", packageRows),
      section("Documenttypes en volumes", documentRows),
      section("Werkstappen", [["Geselecteerd", list(data.workflowCapabilities, WORKFLOW_LABELS)]]),
      section("Uw documentenflow", [
        ["Huidige flow", text(requirements.currentWorkflow)], ["Gewenste flow", text(requirements.desiredWorkflow)],
        ["Algemene volume-indicatie", VOLUME_LABELS[requirements.volumeBand] || text(requirements.volumeBand)],
        ["Frequentie", FREQUENCY_LABELS[requirements.frequency] || text(requirements.frequency)],
        ["Relevante documenttypes", list(requirements.relevantDocumentTypes)], ["Betrokken rollen of gebruikers", list(requirements.rolesUsers)],
      ]),
      section("Voorbeelddocumenten", [
        ["Beschikbaar", yesNo(samples.available)], ["Door Lorenzo Web Solutions gevraagd", yesNo(samples.requestedByLws)],
        ["Later aanleveren vereist", yesNo(samples.uploadRequiredLater)],
      ]),
    ],
  };
}

export function renderSdfQualificationReview(container, data, context) {
  const presentation = buildSdfQualificationPresentation(data, context);
  const fragment = document.createDocumentFragment();
  for (const group of presentation.sections.slice(1)) {
    const sectionNode = document.createElement("section");
    const heading = document.createElement("h3");
    const rows = document.createElement("dl");
    heading.textContent = group.title;
    for (const row of group.rows) {
      const item = document.createElement("div");
      const label = document.createElement("dt");
      const value = document.createElement("dd");
      label.textContent = row.label;
      value.textContent = row.value;
      item.append(label, value);
      rows.append(item);
    }
    sectionNode.append(heading, rows);
    fragment.append(sectionNode);
  }
  container.replaceChildren(fragment);
  return presentation;
}

const htmlEscape = (value) => String(value).replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);

export function sdfQualificationPrintHtml(presentation) {
  const sections = presentation.sections.map((group) => `<section><h2>${htmlEscape(group.title)}</h2><dl>${group.rows.map((row) => `<div><dt>${htmlEscape(row.label)}</dt><dd>${htmlEscape(row.value)}</dd></div>`).join("")}</dl></section>`).join("");
  return `<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="referrer" content="no-referrer"><title>${htmlEscape(presentation.title)}</title><link rel="stylesheet" href="/assets/css/sdf-qualification-print.css?v=20260831-1"></head><body><header><p class="brand">${htmlEscape(presentation.brand)}</p><h1>${htmlEscape(presentation.title)}</h1><p class="reference">${htmlEscape(presentation.reference)}</p><p class="notice">${htmlEscape(presentation.disclaimer)}</p></header><main>${sections}</main></body></html>`;
}

export function printSdfQualificationReview(data, context) {
  const presentation = buildSdfQualificationPresentation(data, context);
  const frame = document.createElement("iframe");
  frame.hidden = true;
  frame.title = "Afdrukweergave Slimme Documentenflow intake";
  frame.srcdoc = sdfQualificationPrintHtml(presentation);
  frame.addEventListener("load", () => {
    frame.contentWindow?.focus();
    frame.contentWindow?.print();
    setTimeout(() => frame.remove(), 1000);
  }, { once: true });
  document.body.append(frame);
}

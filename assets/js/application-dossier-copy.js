const DISCLAIMER = "Dit document is een kopie van de ingediende aanvraag. Prijzen en bedragen zijn indicatief en niet-bindend. Dit is geen definitieve offerte of overeenkomst.";
const PENDING_DISCLAIMER = "Dit document is een momentopname van het dossier op basis van de gegevens die op dit moment door de server zijn uitgegeven. Ontbrekende gegevens zijn nog niet beschikbaar.";

/**
 * @typedef {object} PendingDossierCopy
 * @property {"pending_intake"} kind
 * @property {string} reference
 * @property {"website"} requestKind
 * @property {"invited" | "in_progress"} status
 * @property {string} statusLabel
 * @property {string | null | undefined} websiteType
 * @property {{name?: string | null, company?: string | null, email?: string | null, phone?: string | null}} customer
 * @property {{requestedAt?: string | null, requestedService?: string | null, originalText?: string | null}} request
 * @property {{invitedAt?: string | null, startedAt?: string | null, submittedAt?: string | null, structuredAnswers: Record<string, unknown>}} intake
 * @property {{customerRequestCount?: number, uploadedDocumentCount?: number}} documents
 */

function text(value, fallback = "Niet opgegeven") {
  if (typeof value === "string" && value.trim()) return value.trim();
  return fallback;
}

function list(value) {
  return Array.isArray(value) && value.length ? value.join(", ") : "Niet opgegeven";
}

function yesNo(value) {
  return value === true ? "Ja" : "Nee";
}

function money(minor, currency = "EUR") {
  if (!Number.isSafeInteger(minor)) return "Niet opgegeven";
  return new Intl.NumberFormat("nl-BE", { style: "currency", currency }).format(minor / 100);
}

function detail(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return "Niet opgegeven";
  const entries = Object.entries(value).filter(([, item]) => item !== null && item !== "" && item !== false);
  return entries.length ? entries.map(([key, item]) => `${key}: ${Array.isArray(item) ? item.join(", ") : String(item)}`).join("; ") : "Niet opgegeven";
}

function date(value) {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) return "Niet beschikbaar";
  return new Intl.DateTimeFormat("nl-BE", { dateStyle: "long", timeStyle: "short", timeZone: "Europe/Brussels" }).format(new Date(value));
}

function structuredValue(value) {
  if (value === null || value === undefined || value === "" || (Array.isArray(value) && value.length === 0)) return "Niet beschikbaar";
  if (value === true) return "Ja";
  if (value === false) return "Nee";
  if (Array.isArray(value)) return value.map((item) => String(item)).join(", ");
  if (typeof value === "object") {
    const entries = Object.entries(value).sort(([left], [right]) => left.localeCompare(right, "en"));
    return entries.length
      ? entries.map(([key, item]) => `${key.replaceAll("_", " ")}: ${structuredValue(item)}`).join("; ")
      : "Niet beschikbaar";
  }
  return String(value);
}

/** @param {string} title @param {Array<[string, string]>} rows */
function section(title, rows) {
  return { title, rows: rows.map(([label, value]) => ({ label, value })) };
}

function pendingDossierPresentation(source) {
  if (source?.kind !== "pending_intake" || source.requestKind !== "website"
    || !/^#[0-9A-F]{8}$/.test(String(source.reference || ""))
    || !["invited", "in_progress"].includes(source.status)
    || !source.customer || !source.request || !source.intake || !source.documents
    || !source.intake.structuredAnswers || typeof source.intake.structuredAnswers !== "object"
    || Array.isArray(source.intake.structuredAnswers)) throw new TypeError("INVALID_PENDING_DOSSIER_COPY");
  const answers = Object.entries(source.intake.structuredAnswers)
    .sort(([left], [right]) => left.localeCompare(right, "en"))
    .map(([key, value]) => [key.replaceAll("_", " "), structuredValue(value)]);
  return {
    title: "Dossierkopie",
    reference: source.reference,
    submittedAt: source.intake.submittedAt || null,
    disclaimer: PENDING_DISCLAIMER,
    sections: [
      section("Dossier", [
        ["Dossierreferentie", source.reference], ["Status", text(source.statusLabel)],
        ["Product", "Website"], ["Commerciële richting", text(source.websiteType, "Niet beschikbaar")],
        ["Aangevraagd op", date(source.request.requestedAt)], ["Uitgenodigd op", date(source.intake.invitedAt)],
        ["Gestart op", date(source.intake.startedAt)], ["Ingediend op", date(source.intake.submittedAt)],
      ]),
      section("Klant", [
        ["Naam", text(source.customer.name)], ["Bedrijf", text(source.customer.company)],
        ["E-mail", text(source.customer.email)], ["Telefoon", text(source.customer.phone)],
      ]),
      section("Oorspronkelijke aanvraag", [
        ["Aangevraagde dienst", text(source.request.requestedService)],
        ["Volledige aanvraagtekst", text(source.request.originalText)],
      ]),
      section("Documenten", [
        ["Klantverzoeken", Number.isSafeInteger(source.documents.customerRequestCount) ? String(source.documents.customerRequestCount) : "Niet beschikbaar"],
        ["Ontvangen documenten", Number.isSafeInteger(source.documents.uploadedDocumentCount) ? String(source.documents.uploadedDocumentCount) : "Niet beschikbaar"],
      ]),
      section("Intakegegevens", answers.length ? answers : [["Beschikbare antwoorden", "Niet beschikbaar"]]),
    ],
  };
}

/**
 * Builds the sole print/PDF presentation from the server-issued ApplicationOutput.
 * @param {import("../../supabase/functions/_shared/application-output.ts").ApplicationOutput | PendingDossierCopy} application
 */
export function buildApplicationDossierPresentation(application) {
  if (!application || typeof application !== "object") throw new TypeError("INVALID_APPLICATION_DOSSIER");
  if (application.kind === "pending_intake") return pendingDossierPresentation(application);
  const recurring = application.commercial.recurringServices.length
    ? application.commercial.recurringServices.map((service) => `${service.label}: ${money(service.amountMinor, application.commercial.currency)} per maand`).join(", ")
    : "Geen";

  return {
    title: "Kopie van ingediende aanvraag",
    reference: application.applicationReference || "Historische aanvraag",
    submittedAt: application.submittedAt,
    disclaimer: DISCLAIMER,
    sections: [
      section("Aanvraag", [
        ["Aanvraagnummer", application.applicationReference || "Niet beschikbaar"],
        ["Ingediend op", new Intl.DateTimeFormat("nl-BE", { dateStyle: "long", timeStyle: "short", timeZone: "Europe/Brussels" }).format(new Date(application.submittedAt))],
      ]),
      section("Klant", [
        ["Naam", text(application.customer.name)], ["Bedrijf", text(application.customer.company)],
        ["E-mail", text(application.customer.email)], ["Telefoon", text(application.customer.phone)],
      ]),
      section("Commerciele indicatie", [
        ["Pakket", text(application.commercial.packageLabel)], ["Opgegeven budget", text(application.commercial.budgetLabel)],
        ["Indicatief projectminimum", `${money(application.commercial.knownMinimumMinor, application.commercial.currency)} excl. btw`],
        ["Terugkerende diensten", recurring],
      ]),
      section("Project", [
        ["Type website", text(application.project.websiteType)], ["Bedrijfsomschrijving", text(application.project.businessDescription)],
        ["Doelgroep", text(application.project.targetAudience)], ["Bestaande website", yesNo(application.project.hasExistingWebsite)],
        ["Huidige website", text(application.project.currentWebsite)], ["Te behouden elementen", text(application.project.elementsToKeep)],
        ["Verbeterpunten", text(application.project.improvementAreas)], ["Domein", text(application.project.domain)],
        ["Hostingstatus", text(application.project.hostingStatus)], ["Doelen", list(application.project.goals)],
        ["Primair conversiedoel", text(application.project.primaryConversionGoal)],
      ]),
      section("Website en functies", [
        ["Pagina's", list(application.website.pages)], ["Andere pagina's", text(application.website.otherPages)],
        ["Functies", list(application.website.features)], ["Webshop", yesNo(application.website.webshop)],
        ["Webshopdetails", detail(application.website.webshopDetails)], ["Boeking/reservatie", yesNo(application.website.booking)],
        ["Boekingsdetails", detail(application.website.bookingDetails)], ["Pagina-omvang", detail(application.website.pageScopeDetails)],
        ["Offerteformulier", detail(application.website.quoteFormDetails)], ["Hoofdtaal", text(application.website.primaryLanguage)],
        ["Extra talen", list(application.website.additionalLanguages)], ["Meertaligheid", detail(application.website.multilingualDetails)],
        ["Downloads", detail(application.website.downloadDetails)], ["Nieuwsbrief", detail(application.website.newsletterDetails)],
        ["Koppelingen", list(application.website.integrations)], ["Sociale kanalen", list(application.website.socialChannels)],
        ["SEO-prioriteit", text(application.website.seoPriority)], ["SEO-details", detail(application.website.seoDetails)],
      ]),
      section("Merk en content", [
        ["Merkstatus", text(application.brandingContent.brandStatus)], ["Logostatus", text(application.brandingContent.logoStatus)],
        ["Merkkleuren", list(application.brandingContent.brandColors)], ["Ontwerpstijlen", list(application.brandingContent.designStyles)],
        ["Inspiratiesites", list(application.brandingContent.inspirationSites)], ["Ongewenste stijlen", text(application.brandingContent.dislikedStyles)],
        ["Contentstatus", text(application.brandingContent.contentStatus)], ["Beeldstatus", text(application.brandingContent.imageStatus)],
        ["Beeldondersteuning", list(application.brandingContent.imageSupport)], ["Content- en mediadetails", detail(application.brandingContent.contentMediaDetails)],
      ]),
      section("Service en planning", [
        ["Domeinstatus", text(application.servicePlanning.domainStatus)], ["Onderhoud", text(application.servicePlanning.maintenanceInterest)],
        ["Hostingondersteuning", text(application.servicePlanning.hostingSupport)], ["Hosting- en onderhoudsdetails", detail(application.servicePlanning.hostingMaintenanceDetails)],
        ["Gewenste deadline", text(application.servicePlanning.deadline)], ["Reden deadline", text(application.servicePlanning.deadlineReason)],
        ["Deadlinedetails", detail(application.servicePlanning.deadlineDetails)], ["Timing", text(application.servicePlanning.timing)],
        ["Prioriteiten", list(application.servicePlanning.priorities)], ["Budgetnotities", text(application.servicePlanning.budgetNotes)],
        ["Aanvullende opmerkingen", text(application.servicePlanning.notes)],
      ]),
    ],
  };
}

export function renderApplicationDossier(container, application) {
  const dossier = buildApplicationDossierPresentation(application);
  const fragment = document.createDocumentFragment();
  const notice = document.createElement("p");
  notice.className = "application-dossier-copy__notice";
  notice.textContent = dossier.disclaimer;
  fragment.append(notice);
  for (const group of dossier.sections) {
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
  return dossier;
}

function htmlEscape(value) {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

export function printApplicationDossier(application) {
  const dossier = buildApplicationDossierPresentation(application);
  const sections = dossier.sections.map((group) => `<section><h2>${htmlEscape(group.title)}</h2><dl>${group.rows.map((row) =>
    `<div><dt>${htmlEscape(row.label)}</dt><dd>${htmlEscape(row.value)}</dd></div>`
  ).join("")}</dl></section>`).join("");
  const frame = document.createElement("iframe");
  frame.hidden = true;
  frame.title = "Afdrukweergave aanvraag";
  frame.srcdoc = `<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>${htmlEscape(dossier.reference)}</title><link rel="stylesheet" href="/assets/css/application-dossier-print.css?v=20260828-dossier-ux"></head><body><header><div><h1>${htmlEscape(dossier.title)}</h1><p class="reference">${htmlEscape(dossier.reference)}</p></div><p class="notice">${htmlEscape(dossier.disclaimer)}</p></header><main>${sections}</main></body></html>`;
  frame.addEventListener("load", () => {
    frame.contentWindow?.focus();
    frame.contentWindow?.print();
    setTimeout(() => frame.remove(), 1000);
  }, { once: true });
  document.body.append(frame);
}

const WIN_ANSI_BYTES = new Map([
  [0x20ac, 0x80], [0x201a, 0x82], [0x0192, 0x83], [0x201e, 0x84],
  [0x2026, 0x85], [0x2020, 0x86], [0x2021, 0x87], [0x02c6, 0x88],
  [0x2030, 0x89], [0x0160, 0x8a], [0x2039, 0x8b], [0x0152, 0x8c],
  [0x017d, 0x8e], [0x2018, 0x91], [0x2019, 0x92], [0x201c, 0x93],
  [0x201d, 0x94], [0x2022, 0x95], [0x2013, 0x96], [0x2014, 0x97],
  [0x02dc, 0x98], [0x2122, 0x99], [0x0161, 0x9a], [0x203a, 0x9b],
  [0x0153, 0x9c], [0x017e, 0x9e], [0x0178, 0x9f],
]);
const PDF_SYMBOL_GLYPHS = new Map([[0x03bc, { byte: 0x6d, width: 576 }]]);

function winAnsi(value) {
  let encoded = "";
  for (const character of value) {
    const codePoint = character.codePointAt(0);
    const byte = codePoint <= 0x7f || (codePoint >= 0xa0 && codePoint <= 0xff)
      ? codePoint
      : WIN_ANSI_BYTES.get(codePoint);
    if (byte === undefined) {
      throw new TypeError(`UNSUPPORTED_PDF_CHARACTER_U+${codePoint.toString(16).toUpperCase().padStart(4, "0")}`);
    }
    encoded += String.fromCharCode(byte);
  }
  return encoded;
}

function pdfEscape(value) {
  return winAnsi(value).replace(/([\\()])/g, "\\$1");
}

const PDF_FONT_SIZE = 8.5;
const PDF_COLUMN_WIDTH = 373;
const HELVETICA_ASCII_WIDTHS = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
  556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
  1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
  667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
  333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
  556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
];

export function measureApplicationDossierPdfText(value) {
  const units = [...value].reduce((total, character) => {
    const codePoint = character.codePointAt(0);
    const symbol = PDF_SYMBOL_GLYPHS.get(codePoint);
    if (symbol) return total + symbol.width;
    winAnsi(character);
    if (codePoint >= 0x20 && codePoint <= 0x7e) return total + HELVETICA_ASCII_WIDTHS[codePoint - 0x20];
    const base = character.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    if (base.length === 1) {
      const baseCodePoint = base.codePointAt(0);
      if (baseCodePoint >= 0x20 && baseCodePoint <= 0x7e) return total + HELVETICA_ASCII_WIDTHS[baseCodePoint - 0x20];
    }
    return total + 1000;
  }, 0);
  return units * PDF_FONT_SIZE / 1000;
}

function pdfTextCommands(value) {
  const commands = [];
  let font = null;
  let segment = "";
  const flush = () => {
    if (!segment) return;
    commands.push(`/${font} ${PDF_FONT_SIZE} Tf`, `(${font === "F1" ? pdfEscape(segment) : segment}) Tj`);
    segment = "";
  };
  for (const character of value) {
    const symbol = PDF_SYMBOL_GLYPHS.get(character.codePointAt(0));
    const nextFont = symbol ? "F2" : "F1";
    if (font !== nextFont) {
      flush();
      font = nextFont;
    }
    segment += symbol ? String.fromCharCode(symbol.byte) : character;
  }
  flush();
  return commands;
}

function splitPdfToken(token, width = PDF_COLUMN_WIDTH) {
  const chunks = [];
  let chunk = "";
  for (const character of token) {
    if (chunk && measureApplicationDossierPdfText(chunk + character) > width) {
      chunks.push(chunk);
      chunk = character;
    } else chunk += character;
  }
  if (chunk) chunks.push(chunk);
  return chunks;
}

function wrap(value, width = PDF_COLUMN_WIDTH) {
  const words = value.split(/\s+/);
  const lines = [];
  let line = "";
  for (const word of words) {
    if (line && measureApplicationDossierPdfText(`${line} ${word}`) <= width) {
      line = `${line} ${word}`;
      continue;
    }
    if (line) lines.push(line);
    const chunks = splitPdfToken(word, width);
    lines.push(...chunks.slice(0, -1));
    line = chunks.at(-1) || "";
  }
  if (line) lines.push(line);
  return lines;
}

/** @param {import("../../supabase/functions/_shared/application-output.ts").ApplicationOutput | PendingDossierCopy} application */
export function createApplicationDossierPdf(application) {
  const dossier = buildApplicationDossierPresentation(application);
  const lines = [
    ...wrap(dossier.title),
    ...wrap(dossier.reference),
    "",
    ...wrap(dossier.disclaimer),
    "",
  ];
  for (const group of dossier.sections) {
    lines.push(group.title.toUpperCase());
    for (const row of group.rows) lines.push(...wrap(`${row.label}: ${row.value}`));
    lines.push("");
  }

  const linesPerColumn = 48;
  const columnsPerPage = 2;
  const linesPerPage = linesPerColumn * columnsPerPage;
  const pages = [];
  for (let offset = 0; offset < lines.length; offset += linesPerPage) pages.push(lines.slice(offset, offset + linesPerPage));
  const pageIds = pages.map((_, index) => 5 + index * 2);
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    `<< /Type /Pages /Kids [${pageIds.map((id) => `${id} 0 R`).join(" ")}] /Count ${pages.length} >>`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Symbol >>",
  ];
  pages.forEach((page, index) => {
    const pageId = pageIds[index];
    const contentId = pageId + 1;
    const commands = [];
    for (let column = 0; column < columnsPerPage; column += 1) {
      const columnLines = page.slice(column * linesPerColumn, (column + 1) * linesPerColumn);
      if (!columnLines.length) continue;
      commands.push("BT", `${32 + column * 405} 559 Td`, "10.5 TL");
      columnLines.forEach((line, lineIndex) => {
        if (lineIndex) commands.push("T*");
        commands.push(...pdfTextCommands(line));
      });
      commands.push("ET");
    }
    const stream = commands.join("\n");
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${contentId} 0 R >>`);
    objects.push(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
  });

  let source = "%PDF-1.4\n";
  const offsets = [0];
  objects.forEach((object, index) => { offsets.push(source.length); source += `${index + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = source.length;
  source += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  source += offsets.slice(1).map((offset) => `${String(offset).padStart(10, "0")} 00000 n \n`).join("");
  source += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return {
    bytes: Uint8Array.from(source, (character) => character.charCodeAt(0)),
    type: "application/pdf",
    fileName: `aanvraag-${dossier.reference || "historisch"}.pdf`,
  };
}

export function downloadApplicationDossierPdf(application) {
  const pdf = createApplicationDossierPdf(application);
  const url = URL.createObjectURL(new Blob([pdf.bytes], { type: pdf.type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = pdf.fileName;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

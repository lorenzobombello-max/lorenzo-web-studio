import pdfParse from "npm:pdf-parse@1.1.1";

const MAX_PDF_BYTES = 10 * 1024 * 1024;
const SECTION_4 = "De Opdrachtgever verklaart de hierboven beschreven website te hebben gecontroleerd en, onder voorbehoud van de eventuele opmerkingen vermeld in punt 3, te aanvaarden conform artikel 6 van de Websiteontwikkelingsovereenkomst (functionele test van 10 werkdagen, gevolgd door een finale controle van 5 werkdagen; formele, actieve acceptatie is vereist — er geldt geen stilzwijgende aanvaarding). Dit document vormt de formele bevestiging van die aanvaarding.";
const CONTRACTOR = {
  legalName: "Lorenzo Web Solutions",
  legalForm: "Eenmanszaak (natuurlijke persoon)",
  enterpriseNumber: "0742.361.487",
  vatNumber: "BE 0742.361.487",
  address: "Grote Baan 164 bus 102, 9920 Lievegem, België",
  representative: "Lorenzo Bombello",
  role: "Zelfstandige (eigenaar)",
  email: "bombello.lorenzo1972@gmail.com",
} as const;
const CHECKLIST = [
  ["pages", "Alle overeengekomen pagina’s zijn aanwezig en werken correct"],
  ["desktop_browsers", "De website is getest op de belangrijkste browsers (Chrome, Safari, Firefox, Edge)"],
  ["mobile_tablet", "De website is getest op mobiele en tablet-weergave"],
  ["forms", "Alle formulieren zijn getest en versturen correct"],
  ["links", "Alle links zijn gecontroleerd op werking"],
  ["technical_seo", "Basis technische SEO-instellingen zijn toegepast (titels, meta-omschrijvingen)"],
  ["ssl", "SSL-certificaat is actief (indien van toepassing)"],
  ["hosting", "Website is gekoppeld aan de definitieve hostingomgeving"],
  ["domain", "Domeinnaam wijst correct naar de website"],
  ["access_transfer", "Toegangsgegevens (beheeromgeving, hosting, domein) zijn overgedragen aan de Opdrachtgever"],
  ["backup", "Een back-up van de opgeleverde website is bezorgd of beschikbaar gesteld"],
] as const;

type Anchor = string | Readonly<{ cells: readonly string[]; label?: string }>;

export class WebsiteDeliveryPdfValidationError extends Error {
  constructor(public readonly code: string, detail?: string) {
    super(detail ? `${code}:${detail}` : code);
    this.name = "WebsiteDeliveryPdfValidationError";
  }
}

function fail(code: string, detail?: string): never {
  throw new WebsiteDeliveryPdfValidationError(code, detail);
}

function objectAt(value: unknown, key: string): Record<string, unknown> {
  const nested = (value as Record<string, unknown> | null)?.[key];
  if (!nested || typeof nested !== "object" || Array.isArray(nested)) fail("WEBSITE_DELIVERY_GENERATION_PAYLOAD_INVALID", key);
  return nested as Record<string, unknown>;
}

function stringAt(value: Record<string, unknown>, key: string): string {
  const result = value[key];
  if (typeof result !== "string" || !result.trim()) fail("WEBSITE_DELIVERY_GENERATION_PAYLOAD_INVALID", key);
  return result;
}

function normalized(value: string): string {
  return value.normalize("NFC").replace(/\s+/g, " ").trim();
}

function includesAnchor(text: string, anchor: Anchor): boolean {
  const flat = normalized(text);
  if (typeof anchor === "string") return flat.includes(normalized(anchor));
  const escaped = anchor.cells.map((cell) => normalized(cell).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  return new RegExp(escaped.join(" ?"), "u").test(flat);
}

function anchorLabel(anchor: Anchor): string {
  return typeof anchor === "string" ? anchor : anchor.label ?? anchor.cells.join(" | ");
}

function buildAnchors(payload: unknown): Anchor[] {
  const authority = objectAt(payload, "authority");
  if (stringAt(authority, "statement_version") !== "OPL-W-01") fail("WEBSITE_DELIVERY_GENERATION_PAYLOAD_INVALID", "statement_version");
  const customer = objectAt(payload, "customer");
  const project = objectAt(payload, "project");
  const checklist = objectAt(payload, "checklist");
  const remarks = objectAt(payload, "remarks");
  const signatures = objectAt(payload, "signatures");
  const customerName = stringAt(customer, "legal_name");
  const customerRepresentative = stringAt(customer, "representative_name");
  const customerRole = stringAt(customer, "representative_role");
  const deliveryDate = stringAt(project, "delivery_date");
  const anchors: Anchor[] = [
    { label: "PARTIJ 1 – OPDRACHTNEMER", cells: ["PARTIJ 1 – OPDRACHTNEMER", "Naam onderneming", CONTRACTOR.legalName, "Rechtsvorm", CONTRACTOR.legalForm, "Ondernemingsnummer (KBO)", CONTRACTOR.enterpriseNumber, "BTW-nummer", CONTRACTOR.vatNumber, "Maatschappelijke zetel", CONTRACTOR.address, "Vertegenwoordigd door", CONTRACTOR.representative, "Functie vertegenwoordiger", CONTRACTOR.role, "E-mailadres", CONTRACTOR.email] },
    { label: "PARTIJ 2 – OPDRACHTGEVER", cells: ["PARTIJ 2 – OPDRACHTGEVER", "Naam onderneming / natuurlijke persoon", customerName, "Rechtsvorm (indien van toepassing)", stringAt(customer, "legal_form"), "Ondernemingsnummer (KBO, indien van toepassing)", stringAt(customer, "enterprise_number"), "BTW-nummer (indien van toepassing)", stringAt(customer, "vat_number"), "Adres / maatschappelijke zetel", stringAt(customer, "address"), "Vertegenwoordigd door", customerRepresentative, "Functie vertegenwoordiger", customerRole, "E-mailadres", stringAt(customer, "email")] },
    "1. Projectgegevens",
    `Projectnaam / referentie: ${stringAt(project, "reference")} — ${stringAt(project, "title")}`,
    `URL van de opgeleverde website: ${stringAt(project, "canonical_url")}`,
    `Datum van oplevering: ${deliveryDate}`,
    "2. Opleverchecklist",
  ];
  for (const [key, label] of CHECKLIST) {
    const status = stringAt(checklist, key);
    if (status !== "COMPLETED" && status !== "NOT_APPLICABLE") fail("WEBSITE_DELIVERY_GENERATION_PAYLOAD_INVALID", key);
    anchors.push({ cells: [status === "COMPLETED" ? "☒" : "N.v.t.", label] });
  }
  const remarksState = stringAt(remarks, "state");
  const remarksText = remarksState === "NONE_CONFIRMED"
    ? "Geen opmerkingen of openstaande punten."
    : remarksState === "RECORDED" ? stringAt(remarks, "text") : fail("WEBSITE_DELIVERY_GENERATION_PAYLOAD_INVALID", "remarks.state");
  anchors.push(
    "3. Opmerkingen of openstaande punten",
    remarksText,
    "4. Aanvaarding",
    SECTION_4,
    "Ondertekening",
    { cells: [`Naam: ${CONTRACTOR.representative}`, `Naam: ${customerRepresentative}`] },
    { cells: [`Functie: ${CONTRACTOR.role}`, `Functie: ${customerRole}`] },
  );
  const contractorDate = stringAt(signatures, "contractor_date");
  const contractorPlace = stringAt(signatures, "contractor_place");
  if (signatures.customer_date !== undefined || signatures.customer_place !== undefined) {
    if (typeof signatures.customer_date !== "string" || typeof signatures.customer_place !== "string") {
      fail("WEBSITE_DELIVERY_GENERATION_PAYLOAD_INVALID", "customer_signature");
    }
    anchors.push({ cells: [`Datum: ${contractorDate}`, `Datum: ${signatures.customer_date}`, `Plaats: ${contractorPlace}`, `Plaats: ${signatures.customer_place}`, "Handtekening"] });
  } else {
    anchors.push({ cells: [`Datum: ${contractorDate}`, "Datum:", `Plaats: ${contractorPlace}`, "Plaats:", "Handtekening"] });
  }
  return anchors;
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes).buffer);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function validateWebsiteDeliveryPdf(bytes: Uint8Array, generationPayload: unknown) {
  if (bytes.length > MAX_PDF_BYTES) fail("WEBSITE_DELIVERY_PDF_TOO_LARGE");
  if (bytes.length < 6 || new TextDecoder().decode(bytes.subarray(0, 5)) !== "%PDF-") {
    fail("WEBSITE_DELIVERY_PDF_SIGNATURE_INVALID");
  }
  let parsed: { numpages: number; text: string };
  try {
    parsed = await pdfParse(bytes);
  } catch {
    return fail("WEBSITE_DELIVERY_PDF_PARSE_INVALID");
  }
  if (parsed.numpages !== 3) fail("WEBSITE_DELIVERY_PDF_PAGE_COUNT_INVALID");
  const missing = buildAnchors(generationPayload).find((anchor) => !includesAnchor(parsed.text, anchor));
  if (missing) fail("WEBSITE_DELIVERY_PDF_CONTENT_INVALID", anchorLabel(missing));
  return Object.freeze({ pageCount: parsed.numpages, byteLength: bytes.length, sha256: await sha256(bytes) });
}
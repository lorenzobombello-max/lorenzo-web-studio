import PizZip from "npm:pizzip@3.2.0";
import {
  type Document,
  DOMParser,
  type Element,
  type Node,
  XMLSerializer,
} from "npm:@xmldom/xmldom@0.9.12";

const WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
const SOURCE_SHA256 = "57a39bab36303b133c6acb41f857aeb4cad6de25811e127e7444f590fda4697b";
const SOURCE_DRIVE_ID = "1dx4vXk6VNbykqY2S2cKmK9TeQBMBfDKP";
// Layout-only derivative of the official source; provenance in LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v2.provenance.json.
const RUNTIME_TEMPLATE_SHA256 = "84f16839f584e6949c9fc6389d72894160e65fbf67746eb3bc0effb0d546706d";
const SECTION_4 = "De Opdrachtgever verklaart de hierboven beschreven website te hebben gecontroleerd en, onder voorbehoud van de eventuele opmerkingen vermeld in punt 3, te aanvaarden conform artikel 6 van de Websiteontwikkelingsovereenkomst (functionele test van 10 werkdagen, gevolgd door een finale controle van 5 werkdagen; formele, actieve acceptatie is vereist — er geldt geen stilzwijgende aanvaarding). Dit document vormt de formele bevestiging van die aanvaarding.";
const CHECKLIST_KEYS = [
  "pages", "desktop_browsers", "mobile_tablet", "forms", "links", "technical_seo",
  "ssl", "hosting", "domain", "access_transfer", "backup",
] as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const DATE = /^\d{2}\/\d{2}\/\d{4}$/;

async function sha256(bytes: Uint8Array): Promise<string> {
  const copied = new Uint8Array(bytes.byteLength);
  copied.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", copied.buffer);
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("WEBSITE_DELIVERY_PAYLOAD_INVALID");
  }
  return value as Record<string, unknown>;
}

function text(value: unknown, code = "WEBSITE_DELIVERY_PAYLOAD_INVALID"): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(code);
  return value.trim();
}

function validate(payloadValue: Record<string, unknown>) {
  const authority = record(payloadValue.authority);
  const lineage = record(payloadValue.lineage);
  const customer = record(payloadValue.customer);
  const project = record(payloadValue.project);
  const checklist = record(payloadValue.checklist);
  const remarks = record(payloadValue.remarks);
  const signatures = record(payloadValue.signatures);
  if (
    authority.source_drive_file_id !== SOURCE_DRIVE_ID || authority.source_sha256 !== SOURCE_SHA256 ||
    authority.statement_version !== "OPL-W-01" || !UUID.test(String(lineage.project_id || "")) ||
    !UUID.test(String(lineage.customer_id || "")) || !UUID.test(String(lineage.preview_version_id || "")) ||
    !Number.isSafeInteger(lineage.preview_version) || Number(lineage.preview_version) < 1 ||
    !SHA256.test(String(lineage.preview_content_sha256 || ""))
  ) throw new Error("WEBSITE_DELIVERY_PAYLOAD_INVALID");
  text(lineage.preview_content_reference);
  for (const key of [
    "legal_name", "legal_form", "enterprise_number", "vat_number", "address",
    "representative_name", "representative_role", "email",
  ]) text(customer[key]);
  for (const key of ["reference", "title", "canonical_url", "delivery_date"]) text(project[key]);
  try {
    if (new URL(String(project.canonical_url)).protocol !== "https:") throw new Error();
  } catch {
    throw new Error("WEBSITE_DELIVERY_PAYLOAD_INVALID");
  }
  if (!DATE.test(String(project.delivery_date))) throw new Error("WEBSITE_DELIVERY_PAYLOAD_INVALID");
  if (Object.keys(checklist).sort().join("|") !== [...CHECKLIST_KEYS].sort().join("|")) {
    throw new Error("WEBSITE_DELIVERY_CHECKLIST_INVALID");
  }
  for (const key of CHECKLIST_KEYS) {
    if (!["COMPLETED", "NOT_APPLICABLE"].includes(String(checklist[key]))) {
      throw new Error("WEBSITE_DELIVERY_CHECKLIST_INVALID");
    }
  }
  if (remarks.state === "NONE_CONFIRMED") {
    if (remarks.text != null && remarks.text !== "") throw new Error("WEBSITE_DELIVERY_REMARKS_INVALID");
  } else if (remarks.state === "RECORDED") {
    text(remarks.text, "WEBSITE_DELIVERY_REMARKS_INVALID");
  } else throw new Error("WEBSITE_DELIVERY_REMARKS_INVALID");
  for (const key of ["contractor_date", "contractor_place", "customer_name", "customer_role"]) {
    text(signatures[key]);
  }
  // Before acceptance the customer's date and place stay empty; they are filled only as a pair.
  const customerSigned = signatures.customer_date != null || signatures.customer_place != null;
  if (customerSigned) {
    text(signatures.customer_date);
    text(signatures.customer_place);
  }
  if (
    !DATE.test(String(signatures.contractor_date)) ||
    (customerSigned && !DATE.test(String(signatures.customer_date)))
  ) {
    throw new Error("WEBSITE_DELIVERY_PAYLOAD_INVALID");
  }
  return { customer, project, checklist, remarks, signatures };
}

function children(node: Node, localName: string): Element[] {
  return Array.from(node.childNodes).filter((child) => child.localName === localName) as Element[];
}

function content(node: Element): string {
  return Array.from(node.getElementsByTagNameNS(WORD_NS, "t")).map((item) => item.textContent).join("");
}

function setParagraph(document: Document, paragraph: Element, value: string) {
  const firstRun = children(paragraph, "r")[0];
  const runProperties = firstRun && children(firstRun, "rPr")[0];
  for (const child of Array.from(paragraph.childNodes)) {
    if (child.localName !== "pPr") paragraph.removeChild(child);
  }
  const run = document.createElementNS(WORD_NS, "w:r");
  if (runProperties) run.appendChild(runProperties.cloneNode(true));
  const textNode = document.createElementNS(WORD_NS, "w:t");
  textNode.setAttribute("xml:space", "preserve");
  textNode.appendChild(document.createTextNode(value));
  run.appendChild(textNode);
  paragraph.appendChild(run);
}

function setCell(document: Document, table: Element, row: number, cell: number, value: string) {
  const target = children(children(table, "tr")[row], "tc")[cell];
  const paragraph = target && children(target, "p")[0];
  if (!paragraph) throw new Error("WEBSITE_DELIVERY_TEMPLATE_STRUCTURE_MISMATCH");
  setParagraph(document, paragraph, value);
}

function setPrefix(document: Document, paragraphs: Element[], prefix: string, value: string) {
  const matches = paragraphs.filter((paragraph) => content(paragraph).startsWith(prefix));
  if (matches.length !== 1) throw new Error("WEBSITE_DELIVERY_TEMPLATE_STRUCTURE_MISMATCH");
  setParagraph(document, matches[0], `${prefix}${value}`);
}

function fill(xml: string, payloadValue: Record<string, unknown>): string {
  const payload = validate(payloadValue);
  const document = new DOMParser({ onError: () => undefined }).parseFromString(xml, "application/xml");
  const tables = Array.from(document.getElementsByTagNameNS(WORD_NS, "tbl"));
  const paragraphs = Array.from(document.getElementsByTagNameNS(WORD_NS, "p"));
  if (tables.length !== 3 || !paragraphs.some((paragraph) => content(paragraph) === SECTION_4)) {
    throw new Error("WEBSITE_DELIVERY_TEMPLATE_STRUCTURE_MISMATCH");
  }
  [
    "legal_name", "legal_form", "enterprise_number", "vat_number", "address",
    "representative_name", "representative_role", "email",
  ].forEach((key, index) => setCell(document, tables[0], 10 + index, 1, String(payload.customer[key])));
  setPrefix(document, paragraphs, "Projectnaam / referentie: ", `${payload.project.reference} — ${payload.project.title}`);
  setPrefix(document, paragraphs, "URL van de opgeleverde website: ", String(payload.project.canonical_url));
  setPrefix(document, paragraphs, "Datum van oplevering: ", String(payload.project.delivery_date));
  CHECKLIST_KEYS.forEach((key, index) => {
    setCell(document, tables[1], index + 1, 0, payload.checklist[key] === "COMPLETED" ? "☒" : "N.v.t.");
  });
  const start = paragraphs.findIndex((paragraph) => content(paragraph) === "3. Opmerkingen of openstaande punten");
  const end = paragraphs.findIndex((paragraph) => content(paragraph) === "4. Aanvaarding");
  const target = paragraphs.slice(start + 1, end).find((paragraph) => !content(paragraph).trim());
  if (start < 0 || end < 0 || !target) throw new Error("WEBSITE_DELIVERY_TEMPLATE_STRUCTURE_MISMATCH");
  setParagraph(document, target, payload.remarks.state === "NONE_CONFIRMED"
    ? "Geen opmerkingen of openstaande punten."
    : text(payload.remarks.text, "WEBSITE_DELIVERY_REMARKS_INVALID"));
  setCell(document, tables[2], 1, 1, `Naam: ${payload.signatures.customer_name}`);
  setCell(document, tables[2], 2, 1, `Functie: ${payload.signatures.customer_role}`);
  setCell(document, tables[2], 3, 0, `Datum: ${payload.signatures.contractor_date}`);
  setCell(document, tables[2], 4, 0, `Plaats: ${payload.signatures.contractor_place}`);
  if (payload.signatures.customer_date != null) {
    setCell(document, tables[2], 3, 1, `Datum: ${payload.signatures.customer_date}`);
    setCell(document, tables[2], 4, 1, `Plaats: ${payload.signatures.customer_place}`);
  }
  return new XMLSerializer().serializeToString(document);
}

export async function renderWebsiteDeliveryDocumentDocxBytes(input: Readonly<{
  templateBytes: Uint8Array;
  payload: Record<string, unknown>;
}>): Promise<Readonly<{ buffer: Uint8Array; sha256: string; templateSha256: string }>> {
  if (await sha256(input.templateBytes) !== RUNTIME_TEMPLATE_SHA256) {
    throw new Error("WEBSITE_DELIVERY_TEMPLATE_AUTHORITY_MISMATCH");
  }
  const zip = new PizZip(input.templateBytes);
  const part = zip.file("word/document.xml");
  if (!part) throw new Error("WEBSITE_DELIVERY_TEMPLATE_MALFORMED");
  zip.file("word/document.xml", fill(part.asText(), input.payload));
  const fixedDate = new Date("2000-01-01T00:00:00.000Z");
  Object.values(zip.files).forEach((entry) => entry.date = fixedDate);
  const buffer = zip.generate({ type: "uint8array", compression: "DEFLATE" });
  return { buffer, sha256: await sha256(buffer), templateSha256: RUNTIME_TEMPLATE_SHA256 };
}
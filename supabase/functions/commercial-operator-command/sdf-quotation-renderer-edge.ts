import {
  DOMParser,
  type Document,
  type Element,
  XMLSerializer,
} from "npm:@xmldom/xmldom@0.9.12";
import PizZip from "npm:pizzip@3.2.0";

const WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
const TEMPLATE_ID = "LWS_SDF_QUOTATION_NL_BE";
const TEMPLATE_VERSION = "1.0.0-official";
const TEMPLATE_SHA256 = "33da6dbbeef02876d0624d28fb17a16787cb1e7d0bde8ee74026664ba7739c1d";
const PACKAGES = ["start", "groei", "pro", "maatwerk"] as const;
const PROJECT_DESCRIPTION_PLACEHOLDER = "___________________________";
const PAYMENT_TERM_PLACEHOLDER = "Facturen zijn betaalbaar binnen ___ dagen na factuurdatum (conform Algemene Voorwaarden art. 3, tenzij hierboven anders vermeld).";
const EXECUTION_TERM_PLACEHOLDER = "De geschatte uitvoeringstermijn tot functionele oplevering/testfase bedraagt ___ weken, te rekenen vanaf ontvangst van de eerste betaling (mijlpaal 1) en ontvangst van alle benodigde input van de klant — niet vanaf ondertekening van deze offerte. Deze termijn is indicatief.";
const FORBIDDEN_KEYS = new Set([
  "admin_access_token_hash",
  "capability_token",
  "integrity_mac",
  "integrity_key_id",
  "hmac",
  "raw_approval",
  "raw_intake",
  "raw_pricing_snapshot",
]);
const TABLE_SCHEMA = [
  { columns: 2, labels: ["Offertenummer", "Datum", "Geldig tot", "Contactpersoon Lorenzo Web Solutions"] },
  { columns: 2, labels: ["", "Naam onderneming / persoon", "Ondernemingsnummer (indien van toepassing)", "BTW-nummer (indien van toepassing)", "Adres", "Land", "Contactpersoon", "E-mailadres"] },
  { columns: 4, labels: ["Pakket", "START", "GROEI", "PRO", "MAATWERK"] },
  { columns: 5, labels: ["Pakket", "START", "GROEI", "PRO", "MAATWERK"] },
  { columns: 2, labels: ["Onderdeel", "Documentflows", "Geschat verwerkingsvolume (pagina's/maand)", "Documenttypes", "Gebruikers", "Overige scope-afspraken"] },
  { columns: 2, labels: ["Categorie", "Extra standaard documenttype/template", "Complex documenttype/template", "Losse standaardmodule", "Complexe losse module", "Documentmigratie — eenvoudig", "Documentmigratie — normaal", "Documentmigratie — complex/groot volume", "Externe integratie — eenvoudig", "Externe integratie — standaard zakelijk", "Externe integratie — complex", "Extra opleiding", "Opleidingsblok 3 uur"] },
  { columns: 4, labels: ["Pakket", "START (€ 2.850)", "GROEI (€ 5.700)", "PRO (€ 7.500)", "MAATWERK"] },
  { columns: 2, labels: ["Pakket", "START", "GROEI", "PRO", "MAATWERK"] },
  { columns: 2, labels: ["Voor akkoord – Lorenzo Web Solutions", "Naam: Lorenzo Bombello", "Datum:", "Handtekening", ""] },
] as const;

type JsonRecord = Record<string, unknown>;
type PackageKey = typeof PACKAGES[number];

function assertNoForbiddenData(value: unknown): void {
  if (Array.isArray(value)) {
    value.forEach(assertNoForbiddenData);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_KEYS.has(key)) throw new Error(`FORBIDDEN_RENDER_DATA:${key}`);
    assertNoForbiddenData(child);
  }
}

function record(value: unknown, code: string): JsonRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(code);
  return value as JsonRecord;
}

function requiredString(value: unknown, code: string): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(code);
  return value.trim();
}

function requiredInteger(value: unknown, code: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) throw new Error(code);
  return Number(value);
}

function nullableInteger(value: unknown, code: string): number | null {
  return value === null ? null : requiredInteger(value, code);
}

function formatMinor(value: number): string {
  const minor = BigInt(requiredInteger(value, "SDF_RENDER_AMOUNT_INVALID"));
  const whole = (minor / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `€ ${whole},${(minor % 100n).toString().padStart(2, "0")}`;
}

function formatDate(value: unknown): string {
  const date = requiredString(value, "SDF_RENDER_DATE_INVALID");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("SDF_RENDER_DATE_INVALID");
  const [year, month, day] = date.split("-");
  return `${day}/${month}/${year}`;
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes).buffer);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function directChildren(element: Element, localName: string): Element[] {
  const children: Element[] = [];
  for (let index = 0; index < element.childNodes.length; index += 1) {
    const child = element.childNodes[index];
    if (child.nodeType === 1 && child.localName === localName) children.push(child as Element);
  }
  return children;
}

function elementText(element: Element): string {
  return Array.from(element.getElementsByTagNameNS(WORD_NS, "t"))
    .map((node) => node.textContent || "")
    .join("")
    .replace(/\s+/g, " ")
    .trim();
}

function tableRows(table: Element): Element[] {
  return directChildren(table, "tr");
}

function rowCells(row: Element): Element[] {
  return directChildren(row, "tc");
}

function tableSignature(table: Element): string {
  const firstRow = tableRows(table)[0];
  if (!firstRow) return "";
  return rowCells(firstRow).map(elementText).join(" | ");
}

function validateTemplateStructure(document: Document): void {
  const tables = Array.from(document.getElementsByTagNameNS(WORD_NS, "tbl"));
  if (tables.length !== TABLE_SCHEMA.length) throw new Error("SDF_RENDER_TEMPLATE_STRUCTURE_DRIFT");
  tables.forEach((table, tableIndex) => {
    const rows = tableRows(table);
    const schema = TABLE_SCHEMA[tableIndex];
    if (rows.length !== schema.labels.length) throw new Error("SDF_RENDER_TEMPLATE_STRUCTURE_DRIFT");
    rows.forEach((row, rowIndex) => {
      const cells = rowCells(row);
      if (cells.length !== schema.columns || elementText(cells[0]) !== schema.labels[rowIndex]) {
        throw new Error("SDF_RENDER_TEMPLATE_STRUCTURE_DRIFT");
      }
    });
  });
}

function findUniqueTable(document: Document, signature: string): Element {
  const matches = Array.from(document.getElementsByTagNameNS(WORD_NS, "tbl"))
    .filter((table) => tableSignature(table) === signature);
  if (matches.length !== 1) {
    throw new Error(`SDF_RENDER_MAPPING_AMBIGUOUS:${signature}:${matches.length}`);
  }
  return matches[0];
}

function findUniqueRow(table: Element, label: string): Element {
  const matches = tableRows(table).filter((row) => elementText(rowCells(row)[0]) === label);
  if (matches.length !== 1) throw new Error("SDF_RENDER_MAPPING_ANCHOR_MISSING");
  return matches[0];
}

function setCellText(document: Document, row: Element, cellIndex: number, value: string): void {
  const cell = rowCells(row)[cellIndex];
  if (!cell) throw new Error("SDF_RENDER_MAPPING_ANCHOR_MISSING");
  const textNodes = Array.from(cell.getElementsByTagNameNS(WORD_NS, "t"));
  if (textNodes.length) {
    setElementText(cell, value);
    return;
  }
  const paragraph = document.createElementNS(WORD_NS, "w:p");
  const run = document.createElementNS(WORD_NS, "w:r");
  const text = document.createElementNS(WORD_NS, "w:t");
  text.textContent = value;
  run.appendChild(text);
  paragraph.appendChild(run);
  cell.appendChild(paragraph);
}

function setElementText(element: Element, value: string): void {
  const textNodes = Array.from(element.getElementsByTagNameNS(WORD_NS, "t"));
  if (textNodes.length) {
    textNodes[0].textContent = value;
    for (const node of textNodes.slice(1)) node.textContent = "";
    return;
  }
  throw new Error("SDF_RENDER_MAPPING_ANCHOR_MISSING");
}

function bodyParagraphs(document: Document): Element[] {
  const bodies = Array.from(document.getElementsByTagNameNS(WORD_NS, "body"));
  if (bodies.length !== 1) throw new Error("SDF_RENDER_MAPPING_AMBIGUOUS:body");
  return directChildren(bodies[0], "p");
}

function paragraphStyle(paragraph: Element): string {
  const properties = directChildren(paragraph, "pPr")[0];
  const style = properties && directChildren(properties, "pStyle")[0];
  return style?.getAttributeNS(WORD_NS, "val") || "";
}

function findUniqueBodyParagraph(document: Document, text: string): Element {
  const matches = bodyParagraphs(document).filter((paragraph) => elementText(paragraph) === text);
  if (matches.length !== 1) throw new Error(`SDF_RENDER_MAPPING_AMBIGUOUS:paragraph:${matches.length}`);
  return matches[0];
}

function findUniqueSectionParagraph(document: Document, heading: string, text: string): Element {
  const paragraphs = bodyParagraphs(document);
  const headings = paragraphs
    .map((paragraph, index) => ({ paragraph, index }))
    .filter(({ paragraph }) => paragraphStyle(paragraph) === "Kop2" && elementText(paragraph) === heading);
  if (headings.length !== 1) throw new Error(`SDF_RENDER_MAPPING_AMBIGUOUS:section:${heading}`);
  const matches: Element[] = [];
  for (let index = headings[0].index + 1; index < paragraphs.length; index += 1) {
    if (paragraphStyle(paragraphs[index]) === "Kop2") break;
    if (elementText(paragraphs[index]) === text) matches.push(paragraphs[index]);
  }
  if (matches.length !== 1) throw new Error(`SDF_RENDER_MAPPING_AMBIGUOUS:section-target:${heading}`);
  return matches[0];
}

function stringArray(value: unknown, code: string): string[] {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string" || !item.trim())) {
    throw new Error(code);
  }
  return value.map((item) => String(item).trim());
}

function formatExtraWork(value: unknown): string {
  if (!Array.isArray(value)) throw new Error("SDF_RENDER_EXTRA_WORK_INVALID");
  if (!value.length) return "Geen specifiek meerwerk opgenomen.";
  return value.map((item) => {
    const line = record(item, "SDF_RENDER_EXTRA_WORK_INVALID");
    const description = requiredString(line.description, "SDF_RENDER_EXTRA_WORK_INVALID");
    const amount = nullableInteger(line.amount_minor, "SDF_RENDER_EXTRA_WORK_INVALID");
    const unit = line.unit === null || line.unit === undefined
      ? ""
      : ` / ${requiredString(line.unit, "SDF_RENDER_EXTRA_WORK_INVALID")}`;
    return amount === null ? `${description}: prijs volgens offerte` : `${description}: ${formatMinor(amount)}${unit}`;
  }).join("; ");
}

function validateInput(rendererPackage: JsonRecord): Readonly<{
  payload: JsonRecord;
  scope: JsonRecord;
  packageKey: PackageKey;
  milestones: JsonRecord[];
  paymentTermDays: number;
  executionTermWeeks: number;
  testOnly: boolean;
}> {
  assertNoForbiddenData(rendererPackage);
  const payload = record(rendererPackage.generation_payload, "SDF_RENDER_PAYLOAD_INVALID");
  if (payload.product_family !== "slimme_documentenflow") throw new Error("SDF_RENDER_PRODUCT_INVALID");
  if (payload.contract_version !== 1 || payload.mode !== "ISSUE") throw new Error("SDF_RENDER_PAYLOAD_INVALID");
  const template = record(payload.template, "SDF_RENDER_TEMPLATE_IDENTITY_INVALID");
  if (template.template_id !== TEMPLATE_ID || template.template_version !== TEMPLATE_VERSION
    || String(template.template_sha256 || "").toLowerCase() !== TEMPLATE_SHA256
    || template.authority_status !== "APPROVED") {
    throw new Error("SDF_RENDER_TEMPLATE_IDENTITY_INVALID");
  }
  const scope = record(payload.sdf_scope, "SDF_RENDER_SCOPE_REQUIRED");
  const packageKey = requiredString(scope.package_key, "SDF_RENDER_PACKAGE_REQUIRED") as PackageKey;
  const requiredPackageKey = requiredString(scope.required_package_key, "SDF_RENDER_REQUIRED_PACKAGE_REQUIRED");
  if (!PACKAGES.includes(packageKey) || requiredPackageKey !== packageKey) {
    throw new Error("SDF_RENDER_PACKAGE_INVALID");
  }
  if (scope.snapshot_contract_version !== 1
    || scope.source_taxonomy_version !== "sdf_qualification_intake/3.0.0"
    || scope.budget_guard_authority_version !== 1
    || scope.pricing_authority_version !== 2) {
    throw new Error("SDF_RENDER_SCOPE_VERSION_INVALID");
  }
  requiredInteger(scope.document_flow_count, "SDF_RENDER_SCOPE_INVALID");
  requiredInteger(scope.document_type_count, "SDF_RENDER_SCOPE_INVALID");
  requiredInteger(scope.normalized_monthly_pages, "SDF_RENDER_SCOPE_INVALID");
  requiredInteger(scope.user_count, "SDF_RENDER_SCOPE_INVALID");
  const selectedTypes = stringArray(scope.selected_document_types, "SDF_RENDER_SCOPE_INVALID");
  if (selectedTypes.length !== scope.document_type_count) throw new Error("SDF_RENDER_SCOPE_INVALID");
  const workflow = record(scope.workflow_complexity, "SDF_RENDER_SCOPE_INVALID");
  stringArray(workflow.workflow_capabilities, "SDF_RENDER_SCOPE_INVALID");
  record(scope.budget_guard_result, "SDF_RENDER_SCOPE_INVALID");
  formatExtraWork(scope.extra_work_line_items);

  const schedule = record(payload.payment_schedule, "SDF_RENDER_MILESTONES_INVALID");
  if (!Array.isArray(schedule.milestones) || schedule.milestones.length !== 3) {
    throw new Error("SDF_RENDER_MILESTONES_INVALID");
  }
  const milestones = schedule.milestones.map((item) => record(item, "SDF_RENDER_MILESTONES_INVALID"));
  if (milestones.map((item) => item.percentage).join(",") !== "40,40,20"
    || JSON.stringify(scope.payment_milestones) !== JSON.stringify(schedule.milestones)) {
    throw new Error("SDF_RENDER_MILESTONES_INVALID");
  }
  const paymentTerms = milestones.map((milestone) =>
    requiredInteger(milestone.due_terms_days, "SDF_RENDER_PAYMENT_TERM_INVALID")
  );
  if (new Set(paymentTerms).size !== 1) throw new Error("SDF_RENDER_PAYMENT_TERM_AMBIGUOUS");
  const project = record(payload.project, "SDF_RENDER_PROJECT_INVALID");
  const executionTermWeeks = requiredInteger(
    project.indicative_timing,
    "SDF_RENDER_EXECUTION_TERM_INVALID",
  );
  if (executionTermWeeks < 1) throw new Error("SDF_RENDER_EXECUTION_TERM_INVALID");
  const implementation = nullableInteger(scope.implementation_amount_minor, "SDF_RENDER_AMOUNT_INVALID");
  const recurring = nullableInteger(scope.recurring_amount_minor, "SDF_RENDER_AMOUNT_INVALID");
  if (packageKey === "maatwerk") {
    if (implementation !== null || recurring !== null
      || milestones.some((item) => item.amount_minor !== null)) {
      throw new Error("SDF_RENDER_MAATWERK_AUTHORITY_INVALID");
    }
  } else {
    if (implementation === null || recurring === null) throw new Error("SDF_RENDER_AMOUNT_REQUIRED");
    const totals = record(payload.totals, "SDF_RENDER_TOTALS_INVALID");
    if (totals.one_time_subtotal_minor !== implementation || totals.recurring_subtotal_minor !== recurring
      || milestones.some((item) => !Number.isSafeInteger(item.amount_minor))) {
      throw new Error("SDF_RENDER_AUTHORITY_MISMATCH");
    }
  }
  return {
    payload,
    scope,
    packageKey,
    milestones,
    paymentTermDays: paymentTerms[0],
    executionTermWeeks,
    testOnly: rendererPackage.test_only === true,
  };
}

function applyMapping(document: Document, input: ReturnType<typeof validateInput>): void {
  const { payload, scope, packageKey, milestones, paymentTermDays, executionTermWeeks } = input;
  const quotation = record(payload.quotation, "SDF_RENDER_QUOTATION_INVALID");
  const quotationNumber = requiredString(quotation.quotation_number, "SDF_RENDER_QUOTATION_INVALID");
  const testOnly = input.testOnly;
  if (!(testOnly ? /^TEST-SDF-\d{4}-\d{4}$/.test(quotationNumber) : /^LWS-OFF-\d{4}-\d{4}$/.test(quotationNumber))) {
    throw new Error("SDF_RENDER_QUOTATION_INVALID");
  }
  const validity = record(payload.validity, "SDF_RENDER_DATE_INVALID");
  const customer = record(payload.customer, "SDF_RENDER_CUSTOMER_INVALID");
  const project = record(payload.project, "SDF_RENDER_PROJECT_INVALID");
  const projectDescription = requiredString(project.scope_summary, "SDF_RENDER_PROJECT_DESCRIPTION_REQUIRED");
  const workflow = record(scope.workflow_complexity, "SDF_RENDER_SCOPE_INVALID");
  const capabilities = stringArray(workflow.workflow_capabilities, "SDF_RENDER_SCOPE_INVALID");
  const customComplexity = workflow.custom_complexity === null || workflow.custom_complexity === ""
    ? "geen bijkomende complexiteit"
    : requiredString(workflow.custom_complexity, "SDF_RENDER_SCOPE_INVALID");

  const identityTable = findUniqueTable(document, "Offertenummer | ___________________________");
  setCellText(document, findUniqueRow(identityTable, "Offertenummer"), 1, quotationNumber);
  setCellText(document, findUniqueRow(identityTable, "Datum"), 1, formatDate(validity.valid_from));
  setCellText(document, findUniqueRow(identityTable, "Geldig tot"), 1, formatDate(validity.valid_until));

  const customerTable = findUniqueTable(document, " | KLANTGEGEVENS");
  setCellText(document, findUniqueRow(customerTable, "Naam onderneming / persoon"), 1,
    requiredString(customer.legal_name, "SDF_RENDER_CUSTOMER_INVALID"));
  setCellText(document, findUniqueRow(customerTable, "Ondernemingsnummer (indien van toepassing)"), 1,
    customer.enterprise_number ? String(customer.enterprise_number) : "Niet opgegeven");
  setCellText(document, findUniqueRow(customerTable, "BTW-nummer (indien van toepassing)"), 1,
    customer.vat_number ? String(customer.vat_number) : "Niet opgegeven");
  const address = [customer.address_line_1, customer.address_line_2, customer.postal_code, customer.city]
    .filter((value) => typeof value === "string" && value.trim()).join(", ");
  setCellText(document, findUniqueRow(customerTable, "Adres"), 1,
    requiredString(address, "SDF_RENDER_CUSTOMER_INVALID"));
  setCellText(document, findUniqueRow(customerTable, "Land"), 1,
    requiredString(customer.country_code, "SDF_RENDER_CUSTOMER_INVALID"));
  setCellText(document, findUniqueRow(customerTable, "Contactpersoon"), 1,
    customer.contact_name ? String(customer.contact_name) : "Niet opgegeven");
  setCellText(document, findUniqueRow(customerTable, "E-mailadres"), 1,
    requiredString(customer.email, "SDF_RENDER_CUSTOMER_INVALID"));

  setElementText(
    findUniqueSectionParagraph(document, "Projectomschrijving", PROJECT_DESCRIPTION_PLACEHOLDER),
    projectDescription,
  );

  const packageTable = findUniqueTable(document,
    "Pakket | Eenmalige implementatie (excl. btw) | Recurrente dienstverlening (excl. btw) | Aangeduid");
  for (const key of PACKAGES) setCellText(document, findUniqueRow(packageTable, key.toUpperCase()), 3,
    key === packageKey ? "☒" : "☐");
  if (packageKey !== "maatwerk") {
    const selected = findUniqueRow(packageTable, packageKey.toUpperCase());
    setCellText(document, selected, 1, formatMinor(Number(scope.implementation_amount_minor)));
    setCellText(document, selected, 2, `${formatMinor(Number(scope.recurring_amount_minor))} / maand`);
  }

  const scopeTable = findUniqueTable(document, "Onderdeel | Omschrijving voor deze offerte");
  setCellText(document, findUniqueRow(scopeTable, "Documentflows"), 1, String(scope.document_flow_count));
  setCellText(document, findUniqueRow(scopeTable, "Geschat verwerkingsvolume (pagina's/maand)"), 1,
    String(scope.normalized_monthly_pages));
  setCellText(document, findUniqueRow(scopeTable, "Documenttypes"), 1,
    stringArray(scope.selected_document_types, "SDF_RENDER_SCOPE_INVALID").join(", "));
  setCellText(document, findUniqueRow(scopeTable, "Gebruikers"), 1, String(scope.user_count));
  setCellText(document, findUniqueRow(scopeTable, "Overige scope-afspraken"), 1,
    `${requiredString(project.scope_summary, "SDF_RENDER_PROJECT_INVALID")} Workflow: ${capabilities.join(", ")}; ${customComplexity}. Meerwerk: ${formatExtraWork(scope.extra_work_line_items)}`);

  const milestoneTable = findUniqueTable(document,
    "Pakket | 40% — opdrachtbevestiging (factureerbaar na aanvaarding offerte) | 40% — functionele oplevering/testfase | 20% — definitieve oplevering/acceptatie");
  if (packageKey !== "maatwerk") {
    const selected = findUniqueRow(milestoneTable, `${packageKey.toUpperCase()} (${formatMinor(Number(scope.implementation_amount_minor)).replace(",00", "")})`);
    milestones.forEach((milestone, index) => setCellText(document, selected, index + 1,
      formatMinor(requiredInteger(milestone.amount_minor, "SDF_RENDER_MILESTONES_INVALID"))));
  }

  setElementText(
    findUniqueBodyParagraph(document, PAYMENT_TERM_PLACEHOLDER),
    PAYMENT_TERM_PLACEHOLDER.replace("___", String(paymentTermDays)),
  );
  setElementText(
    findUniqueBodyParagraph(document, EXECUTION_TERM_PLACEHOLDER),
    EXECUTION_TERM_PLACEHOLDER.replace("___", String(executionTermWeeks)),
  );

  const acceptanceTable = findUniqueTable(document, "Voor akkoord – Lorenzo Web Solutions | Voor akkoord – Klant");
  setCellText(document, findUniqueRow(acceptanceTable, "Naam: Lorenzo Bombello"), 1,
    `Naam: ${requiredString(customer.legal_name, "SDF_RENDER_CUSTOMER_INVALID")}`);
}

export async function renderSdfQuotationDocxBytes(input: Readonly<{
  templateBytes: Uint8Array;
  rendererPackage: JsonRecord;
}>): Promise<Readonly<{ buffer: Uint8Array; sha256: string }>> {
  if (await sha256(input.templateBytes) !== TEMPLATE_SHA256) throw new Error("SDF_TEMPLATE_HASH_MISMATCH");
  const validated = validateInput(input.rendererPackage);
  let zip: PizZip;
  try {
    zip = new PizZip(input.templateBytes);
  } catch {
    throw new Error("SDF_RENDER_DOCX_MALFORMED");
  }
  const documentPart = zip.file("word/document.xml");
  if (!documentPart) throw new Error("SDF_RENDER_DOCX_MALFORMED");
  const renderedDocumentXml = renderSdfQuotationDocumentXml(
    documentPart.asText(),
    input.rendererPackage,
  );
  zip.file("word/document.xml", renderedDocumentXml);
  const fixedDate = new Date("2000-01-01T00:00:00.000Z");
  for (const entry of Object.values(zip.files)) entry.date = fixedDate;
  const buffer = zip.generate({ type: "uint8array", compression: "DEFLATE" }) as Uint8Array;
  return { buffer, sha256: await sha256(buffer) };
}

export function renderSdfQuotationDocumentXml(
  documentXml: string,
  rendererPackage: JsonRecord,
): string {
  let document: Document;
  try {
    document = new DOMParser({ onError: () => undefined }).parseFromString(
      documentXml,
      "application/xml",
    );
  } catch {
    throw new Error("SDF_RENDER_DOCX_MALFORMED");
  }
  if (!document || document.getElementsByTagName("parsererror").length) {
    throw new Error("SDF_RENDER_DOCX_MALFORMED");
  }
  validateTemplateStructure(document);
  applyMapping(document, validateInput(rendererPackage));
  return new XMLSerializer().serializeToString(document);
}

export const SDF_QUOTATION_TEMPLATE_AUTHORITY = Object.freeze({
  templateId: TEMPLATE_ID,
  templateVersion: TEMPLATE_VERSION,
  templateSha256: TEMPLATE_SHA256,
});
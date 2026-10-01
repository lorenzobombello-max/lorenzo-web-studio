import {
  DOMParser,
  type Document,
  XMLSerializer,
} from "npm:@xmldom/xmldom@0.9.12";
import PizZip from "npm:pizzip@3.2.0";

const WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
const TEMPLATE_ID = "LWS_QUOTATION_NL_BE";
const TEMPLATE_VERSION = "2.0.0-official";
const TEMPLATE_SHA256 = "b8b958ae9567fd8526195b4f614ecdccab7e1bb2acab21121bee0342630da059";
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

type JsonRecord = Record<string, unknown>;

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes).buffer);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function assertNoForbiddenData(value: unknown): void {
  if (Array.isArray(value)) return value.forEach(assertNoForbiddenData);
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

function optionalString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function requiredInteger(value: unknown, code: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) throw new Error(code);
  return Number(value);
}

function formatMinor(value: unknown): string {
  const minor = BigInt(requiredInteger(value, "WEBSITE_RENDER_AMOUNT_INVALID"));
  const whole = (minor / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `€ ${whole},${(minor % 100n).toString().padStart(2, "0")}`;
}

function formatDate(value: unknown): string {
  const date = requiredString(value, "WEBSITE_RENDER_DATE_INVALID");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("WEBSITE_RENDER_DATE_INVALID");
  const [year, month, day] = date.split("-");
  return `${day}/${month}/${year}`;
}

function formatQuantity(value: unknown): string {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new Error("WEBSITE_RENDER_LINE_INVALID");
  }
  return String(value).replace(".", ",");
}

function timingValue(value: unknown): string {
  if (value === null || value === undefined || value === "") return "";
  const normalized = typeof value === "number" ? String(value) : String(value).trim();
  if (!/^\d+$/.test(normalized) || Number(normalized) < 1) throw new Error("WEBSITE_RENDER_TIMING_INVALID");
  return normalized;
}

function paymentTerm(schedule: JsonRecord): string {
  if (!Array.isArray(schedule.milestones) || schedule.milestones.length !== 3) {
    throw new Error("WEBSITE_RENDER_MILESTONES_INVALID");
  }
  const milestones = schedule.milestones.map((item) => record(item, "WEBSITE_RENDER_MILESTONES_INVALID"));
  if (milestones.map((item) => item.percentage).join(",") !== "40,40,20") {
    throw new Error("WEBSITE_RENDER_MILESTONES_INVALID");
  }
  const terms = milestones.map((item) => item.due_terms_days);
  if (terms.every((value) => value === null)) return "";
  if (terms.some((value) => !Number.isSafeInteger(value) || Number(value) < 0)
    || new Set(terms).size !== 1) {
    throw new Error("WEBSITE_RENDER_PAYMENT_TERM_AMBIGUOUS");
  }
  return String(terms[0]);
}

function validateInput(rendererPackage: JsonRecord): Readonly<{
  mapping: Record<string, string>;
  commercialLines: Array<Record<string, string | number>>;
}> {
  assertNoForbiddenData(rendererPackage);
  const payload = record(rendererPackage.generation_payload, "WEBSITE_RENDER_PAYLOAD_INVALID");
  if (payload.contract_version !== 1 || payload.mode !== "ISSUE") throw new Error("WEBSITE_RENDER_PAYLOAD_INVALID");
  const locale = record(payload.locale, "WEBSITE_RENDER_LOCALE_INVALID");
  if (locale.document_locale !== "nl-BE" || locale.currency !== "EUR") {
    throw new Error("WEBSITE_RENDER_LOCALE_INVALID");
  }
  const template = record(payload.template, "WEBSITE_RENDER_TEMPLATE_IDENTITY_INVALID");
  if (template.template_id !== TEMPLATE_ID || template.template_version !== TEMPLATE_VERSION
    || String(template.template_sha256 || "").toLowerCase() !== TEMPLATE_SHA256
    || template.authority_status !== "APPROVED") {
    throw new Error("WEBSITE_RENDER_TEMPLATE_IDENTITY_INVALID");
  }
  const quotation = record(payload.quotation, "WEBSITE_RENDER_QUOTATION_INVALID");
  const quotationNumber = requiredString(quotation.quotation_number, "WEBSITE_RENDER_QUOTATION_INVALID");
  const numberPattern = rendererPackage.test_only === true
    ? /^TEST-WEB-\d{4}-\d{4}$/
    : /^LWS-OFF-\d{4}-\d{4}$/;
  if (!numberPattern.test(quotationNumber)) throw new Error("WEBSITE_RENDER_QUOTATION_INVALID");

  const customer = record(payload.customer, "WEBSITE_RENDER_CUSTOMER_INVALID");
  const project = record(payload.project, "WEBSITE_RENDER_PROJECT_INVALID");
  const totals = record(payload.totals, "WEBSITE_RENDER_TOTALS_INVALID");
  const vat = record(payload.vat, "WEBSITE_RENDER_VAT_INVALID");
  const validity = record(payload.validity, "WEBSITE_RENDER_DATE_INVALID");
  const subtotal = requiredInteger(totals.subtotal_net_minor, "WEBSITE_RENDER_TOTALS_INVALID");
  const vatAmount = requiredInteger(totals.vat_amount_minor, "WEBSITE_RENDER_TOTALS_INVALID");
  const gross = requiredInteger(totals.total_gross_minor, "WEBSITE_RENDER_TOTALS_INVALID");
  if (subtotal + vatAmount !== gross) throw new Error("WEBSITE_RENDER_TOTALS_INVALID");
  if (typeof vat.vat_rate !== "number" || !Number.isFinite(vat.vat_rate) || vat.vat_rate < 0) {
    throw new Error("WEBSITE_RENDER_VAT_INVALID");
  }
  const address = [customer.address_line_1, customer.address_line_2, customer.postal_code, customer.city]
    .map(optionalString)
    .filter(Boolean)
    .join(", ");
  requiredString(address, "WEBSITE_RENDER_CUSTOMER_INVALID");
  if (!Array.isArray(payload.lines) || !payload.lines.length) throw new Error("WEBSITE_RENDER_LINES_INVALID");
  const commercialLines = payload.lines.map((value) => {
    const line = record(value, "WEBSITE_RENDER_LINE_INVALID");
    return {
      COMMERCIAL_DESCRIPTION: requiredString(line.description, "WEBSITE_RENDER_LINE_INVALID"),
      COMMERCIAL_QUANTITY: formatQuantity(line.quantity),
      COMMERCIAL_UNIT_PRICE: formatMinor(line.unit_price_minor),
      COMMERCIAL_LINE_TOTAL: formatMinor(line.line_net_amount_minor),
      lineNetAmountMinor: requiredInteger(line.line_net_amount_minor, "WEBSITE_RENDER_LINE_INVALID"),
    };
  });
  if (commercialLines.reduce((sum, line) => sum + Number(line.lineNetAmountMinor), 0) !== subtotal) {
    throw new Error("WEBSITE_RENDER_LINES_TOTAL_MISMATCH");
  }

  return {
    mapping: {
      QUOTATION_NUMBER: quotationNumber,
      VALID_FROM: formatDate(validity.valid_from),
      VALID_UNTIL: formatDate(validity.valid_until),
      CUSTOMER_LEGAL_NAME: requiredString(customer.legal_name, "WEBSITE_RENDER_CUSTOMER_INVALID"),
      CUSTOMER_ENTERPRISE_NUMBER: optionalString(customer.enterprise_number),
      CUSTOMER_VAT_NUMBER: optionalString(customer.vat_number),
      CUSTOMER_ADDRESS: address,
      CUSTOMER_COUNTRY: requiredString(customer.country_code, "WEBSITE_RENDER_CUSTOMER_INVALID"),
      CUSTOMER_CONTACT_NAME: optionalString(customer.contact_name),
      CUSTOMER_EMAIL: requiredString(customer.email, "WEBSITE_RENDER_CUSTOMER_INVALID"),
      PROJECT_SCOPE_SUMMARY: requiredString(project.scope_summary, "WEBSITE_RENDER_PROJECT_INVALID"),
      PROJECT_PAGE_COUNT: String(requiredInteger(project.included_page_count, "WEBSITE_RENDER_PROJECT_INVALID")),
      PROJECT_TIMING_WEEKS: timingValue(project.indicative_timing),
      PAYMENT_TERM_DAYS: paymentTerm(record(payload.payment_schedule, "WEBSITE_RENDER_MILESTONES_INVALID")),
      TOTAL_EXCL_VAT: formatMinor(subtotal),
      VAT_RATE_PERCENT: String(vat.vat_rate).replace(".", ","),
      TOTAL_VAT: formatMinor(vatAmount),
      TOTAL_INCL_VAT: formatMinor(gross),
    },
    commercialLines,
  };
}

function replaceTag(document: Document, tag: string, value: string): void {
  const token = `{{${tag}}}`;
  const matches = Array.from(document.getElementsByTagNameNS(WORD_NS, "t"))
    .filter((node) => (node.textContent || "").includes(token));
  if (matches.length !== 1) throw new Error(`WEBSITE_RENDER_MAPPING_AMBIGUOUS:${tag}:${matches.length}`);
  if ((matches[0].textContent?.match(new RegExp(`\\{\\{${tag}\\}\\}`, "g")) || []).length !== 1) {
    throw new Error(`WEBSITE_RENDER_MAPPING_AMBIGUOUS:${tag}:multiple`);
  }
  matches[0].textContent = (matches[0].textContent || "").replace(token, value);
}

function renderCommercialRows(document: Document, lines: Array<Record<string, string | number>>): void {
  const token = "{{COMMERCIAL_DESCRIPTION}}";
  const rows = Array.from(document.getElementsByTagNameNS(WORD_NS, "tr"));
  const matches = rows.filter((row) => Array.from(row.getElementsByTagNameNS(WORD_NS, "t"))
    .some((node) => (node.textContent || "").includes(token)));
  if (matches.length !== 1) throw new Error(`WEBSITE_RENDER_COMMERCIAL_ROW_AMBIGUOUS:${matches.length}`);
  const prototype = matches[0];
  const parent = prototype.parentNode;
  if (!parent) throw new Error("WEBSITE_RENDER_COMMERCIAL_ROW_AMBIGUOUS:0");
  for (const line of lines) {
    const row = prototype.cloneNode(true) as Document;
    for (const [tag, value] of Object.entries(line)) {
      if (tag !== "lineNetAmountMinor") replaceTag(row, tag, String(value));
    }
    parent.insertBefore(row, prototype);
  }
  parent.removeChild(prototype);
}

export async function renderWebsiteQuotationDocxBytes(input: Readonly<{
  templateBytes: Uint8Array;
  rendererPackage: JsonRecord;
}>): Promise<Readonly<{ buffer: Uint8Array; sha256: string }>> {
  if (await sha256(input.templateBytes) !== TEMPLATE_SHA256) throw new Error("WEBSITE_TEMPLATE_HASH_MISMATCH");
  const values = validateInput(input.rendererPackage);
  let zip: PizZip;
  try {
    zip = new PizZip(input.templateBytes);
  } catch {
    throw new Error("WEBSITE_RENDER_DOCX_MALFORMED");
  }
  const documentPart = zip.file("word/document.xml");
  if (!documentPart) throw new Error("WEBSITE_RENDER_DOCX_MALFORMED");
  const document = new DOMParser({ onError: () => undefined }).parseFromString(
    documentPart.asText(),
    "application/xml",
  );
  if (!document || document.getElementsByTagName("parsererror").length) {
    throw new Error("WEBSITE_RENDER_DOCX_MALFORMED");
  }
  renderCommercialRows(document, values.commercialLines);
  Object.entries(values.mapping).forEach(([tag, value]) => replaceTag(document, tag, value));
  zip.file("word/document.xml", new XMLSerializer().serializeToString(document));
  const fixedDate = new Date("2000-01-01T00:00:00.000Z");
  for (const entry of Object.values(zip.files)) entry.date = fixedDate;
  const buffer = zip.generate({ type: "uint8array", compression: "DEFLATE" }) as Uint8Array;
  return { buffer, sha256: await sha256(buffer) };
}

export const WEBSITE_QUOTATION_TEMPLATE_AUTHORITY = Object.freeze({
  templateId: TEMPLATE_ID,
  templateVersion: TEMPLATE_VERSION,
  templateSha256: TEMPLATE_SHA256,
});
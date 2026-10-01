import {
  type Document,
  DOMParser,
  XMLSerializer,
} from "npm:@xmldom/xmldom@0.9.12";
import PizZip from "npm:pizzip@3.2.0";

const WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TEMPLATE_AUTHORITIES = Object.freeze({
  AGREEMENT: Object.freeze({
    derivativeReference:
      "assets/docs/website-commercial/LWS_WEBSITE_AGREEMENT_NL_BE_CONCEPT_v1.docx",
    derivativeSha256:
      "10804398000fc16c1cedd95fa4391971a9c9133ba530c4eea07088c6bddd6ccd",
    milestone: null,
  }),
  INVOICE_M1: Object.freeze({
    derivativeReference:
      "assets/docs/website-commercial/LWS_WEBSITE_INVOICE_M1_40_NONPRODUCTION_v1.docx",
    derivativeSha256:
      "53c8e7b8223a6c2d62b471ecabc8982663b7ce5a98a73b15b45b66b59ac12e9a",
    milestone: 1,
  }),
  INVOICE_M2: Object.freeze({
    derivativeReference:
      "assets/docs/website-commercial/LWS_WEBSITE_INVOICE_M2_40_NONPRODUCTION_v1.docx",
    derivativeSha256:
      "b25615b7890789d08df0a4017ae149a47a2e655169a2497848c0817e8fffdf82",
    milestone: 2,
  }),
  INVOICE_FINAL: Object.freeze({
    derivativeReference:
      "assets/docs/website-commercial/LWS_WEBSITE_INVOICE_FINAL_REMAINDER_NONPRODUCTION_v1.docx",
    derivativeSha256:
      "fe567d0f02a998f59ca73189287d565d669ff2d4adb9a5d4167f548081ca0d94",
    milestone: 3,
  }),
});

type WebsiteCommercialDocumentKind = keyof typeof TEMPLATE_AUTHORITIES;

type JsonRecord = Record<string, unknown>;

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array(bytes).buffer,
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function record(value: unknown, code: string): JsonRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(code);
  }
  return value as JsonRecord;
}

function requireText(value: unknown, code: string): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(code);
  return value.trim();
}

function optionalText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function requireInteger(value: unknown, code: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) throw new Error(code);
  return Number(value);
}

function validateLineage(payload: JsonRecord): JsonRecord {
  const lineage = record(payload.lineage, "WEBSITE_COMMERCIAL_LINEAGE_INVALID");
  for (
    const field of [
      "quote_request_id",
      "quotation_issuance_id",
      "acceptance_id",
      "customer_id",
      "project_id",
    ]
  ) {
    if (!UUID_PATTERN.test(String(lineage[field] || ""))) {
      throw new Error(`WEBSITE_COMMERCIAL_LINEAGE_INVALID:${field}`);
    }
  }
  if (
    payload.document_kind !== "AGREEMENT" &&
    !UUID_PATTERN.test(String(lineage.obligation_id || ""))
  ) {
    throw new Error("WEBSITE_COMMERCIAL_LINEAGE_INVALID:obligation_id");
  }
  requireText(
    lineage.quotation_number,
    "WEBSITE_COMMERCIAL_LINEAGE_INVALID:quotation_number",
  );
  return lineage;
}

function formatMoney(value: unknown, currency: unknown): string {
  const minor = requireInteger(value, "WEBSITE_COMMERCIAL_AMOUNT_INVALID");
  if (currency !== "EUR") {
    throw new Error("WEBSITE_COMMERCIAL_CURRENCY_INVALID");
  }
  const units = Math.floor(minor / 100).toLocaleString("nl-BE");
  return `EUR ${units},${String(minor % 100).padStart(2, "0")}`;
}

function validateVatAuthority(payload: JsonRecord, project: JsonRecord): void {
  const vat = record(payload.vat, "WEBSITE_COMMERCIAL_VAT_AUTHORITY_INVALID");
  if (
    !UUID_PATTERN.test(String(vat.vat_decision_authority_id || "")) ||
    !/^[0-9a-f]{64}$/.test(String(vat.authority_sha256 || "")) ||
    vat.authority_family !== "LWS_OUTGOING_VAT" ||
    vat.decision_code !== "BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION" ||
    vat.vat_treatment !== "EXEMPT" ||
    vat.rate_semantics !== "NOT_APPLICABLE" ||
    vat.vat_rate !== 0 ||
    vat.invoice_literal !== "Bijzondere vrijstellingsregeling van belasting"
  ) {
    throw new Error("WEBSITE_COMMERCIAL_VAT_AUTHORITY_INVALID");
  }
  const acceptedTotal = requireInteger(
    project.accepted_total_minor,
    "WEBSITE_COMMERCIAL_VAT_AMOUNT_MISMATCH",
  );
  if (
    requireInteger(
        vat.vat_base_minor,
        "WEBSITE_COMMERCIAL_VAT_AMOUNT_MISMATCH",
      ) !== acceptedTotal ||
    requireInteger(
        vat.vat_amount_minor,
        "WEBSITE_COMMERCIAL_VAT_AMOUNT_MISMATCH",
      ) !== 0 ||
    requireInteger(
        vat.customer_total_minor,
        "WEBSITE_COMMERCIAL_VAT_AMOUNT_MISMATCH",
      ) !== acceptedTotal ||
    project.project_price_excl_vat_minor !== acceptedTotal
  ) {
    throw new Error("WEBSITE_COMMERCIAL_VAT_AMOUNT_MISMATCH");
  }
}

function invoiceAmounts(
  project: JsonRecord,
  documentKind: WebsiteCommercialDocumentKind,
): number[] {
  const total = requireInteger(
    project.accepted_total_minor,
    "WEBSITE_COMMERCIAL_AMOUNT_INVALID",
  );
  const m1 = requireInteger(
    project.m1_minor,
    "WEBSITE_COMMERCIAL_AMOUNT_INVALID",
  );
  const m2 = requireInteger(
    project.m2_minor,
    "WEBSITE_COMMERCIAL_AMOUNT_INVALID",
  );
  const m3 = requireInteger(
    project.m3_minor,
    "WEBSITE_COMMERCIAL_AMOUNT_INVALID",
  );
  if (m3 !== total - m1 - m2) throw new Error("WEBSITE_COMMERCIAL_M3_MISMATCH");
  if (documentKind === "INVOICE_M1") return [total, 0, m1, total - m1];
  if (documentKind === "INVOICE_M2") return [total, m1, m2, total - m1 - m2];
  return [total, m1 + m2, m3, 0];
}

function validateInvoiceFiscal(
  payload: JsonRecord,
  lineage: JsonRecord,
  documentKind: WebsiteCommercialDocumentKind,
  currentMilestoneAmount: number,
): JsonRecord {
  const invoiceFiscal = record(
    payload.invoice_fiscal,
    "WEBSITE_COMMERCIAL_INVOICE_FISCAL_BINDING_INVALID",
  );
  const expectedMilestone = TEMPLATE_AUTHORITIES[documentKind].milestone;
  if (
    !UUID_PATTERN.test(String(invoiceFiscal.obligation_id || "")) ||
    invoiceFiscal.obligation_id !== lineage.obligation_id ||
    invoiceFiscal.milestone !== expectedMilestone
  ) {
    throw new Error("WEBSITE_COMMERCIAL_INVOICE_FISCAL_BINDING_INVALID");
  }
  const vatBase = requireInteger(
    invoiceFiscal.vat_base_minor,
    "WEBSITE_COMMERCIAL_INVOICE_FISCAL_AMOUNT_MISMATCH",
  );
  const vatAmount = requireInteger(
    invoiceFiscal.vat_amount_minor,
    "WEBSITE_COMMERCIAL_INVOICE_FISCAL_AMOUNT_MISMATCH",
  );
  const customerTotal = requireInteger(
    invoiceFiscal.customer_total_minor,
    "WEBSITE_COMMERCIAL_INVOICE_FISCAL_AMOUNT_MISMATCH",
  );
  if (
    vatBase !== currentMilestoneAmount || vatAmount !== 0 ||
    customerTotal !== vatBase
  ) {
    throw new Error("WEBSITE_COMMERCIAL_INVOICE_FISCAL_AMOUNT_MISMATCH");
  }
  return invoiceFiscal;
}

function replacementsFor(
  payload: JsonRecord,
  documentKind: WebsiteCommercialDocumentKind,
): Record<string, string> {
  const lineage = validateLineage(payload);
  const customer = record(
    payload.customer,
    "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
  );
  const project = record(payload.project, "WEBSITE_COMMERCIAL_PAYLOAD_INVALID");
  validateVatAuthority(payload, project);
  const paymentTermDays = requireInteger(
    project.payment_term_days,
    "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
  );
  if (paymentTermDays < 1) {
    throw new Error("WEBSITE_COMMERCIAL_PAYLOAD_INVALID");
  }
  const address = [
    customer.address_line_1,
    customer.address_line_2,
    [customer.postal_code, customer.city].filter(Boolean).join(" "),
    customer.country_code,
  ].filter((value) => typeof value === "string" && value.trim()).join(", ");

  const common = {
    QUOTATION_NUMBER: requireText(
      lineage.quotation_number,
      "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
    ),
    CUSTOMER_LEGAL_NAME: requireText(
      customer.legal_name,
      "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
    ),
    CUSTOMER_ADDRESS: requireText(
      address,
      "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
    ),
  };
  if (documentKind !== "AGREEMENT") {
    const [total, alreadyInvoiced, current, remaining] = invoiceAmounts(
      project,
      documentKind,
    );
    const invoiceFiscal = validateInvoiceFiscal(
      payload,
      lineage,
      documentKind,
      current,
    );
    const vat = record(payload.vat, "WEBSITE_COMMERCIAL_VAT_AUTHORITY_INVALID");
    const businessIdentity = optionalText(customer.vat_number) ||
      optionalText(customer.enterprise_number);
    return {
      ...common,
      PROJECT_TITLE: requireText(
        project.title,
        "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
      ),
      CUSTOMER_TYPE: businessIdentity ? "B2B" : "B2C",
      CUSTOMER_ENTERPRISE_OR_VAT_IDENTITY: businessIdentity ||
        "Niet van toepassing",
      PAYMENT_TERM_DAYS: String(paymentTermDays),
      ACCEPTED_TOTAL: formatMoney(total, project.currency),
      ALREADY_INVOICED: formatMoney(alreadyInvoiced, project.currency),
      CURRENT_MILESTONE_AMOUNT: formatMoney(current, project.currency),
      REMAINING_BALANCE: formatMoney(remaining, project.currency),
      VAT_INVOICE_LITERAL: requireText(
        vat.invoice_literal,
        "WEBSITE_COMMERCIAL_VAT_AUTHORITY_INVALID",
      ),
      VAT_BREAKDOWN: [
        formatMoney(invoiceFiscal.vat_base_minor, project.currency),
        String(vat.vat_treatment),
        String(vat.rate_semantics),
        formatMoney(invoiceFiscal.vat_amount_minor, project.currency),
      ].join(" | "),
    };
  }
  const agreement = record(
    payload.agreement,
    "WEBSITE_COMMERCIAL_AGREEMENT_STATUS_INVALID",
  );
  if (agreement.status !== "UNSIGNED_CONCEPT") {
    throw new Error("WEBSITE_COMMERCIAL_AGREEMENT_STATUS_INVALID");
  }
  if (payload.invoice_fiscal !== null) {
    throw new Error("WEBSITE_COMMERCIAL_INVOICE_FISCAL_BINDING_INVALID");
  }
  const timingWeeks = requireInteger(
    project.timing_weeks,
    "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
  );
  if (timingWeeks < 1) throw new Error("WEBSITE_COMMERCIAL_PAYLOAD_INVALID");
  return {
    ...common,
    CUSTOMER_LEGAL_FORM: optionalText(customer.legal_form),
    CUSTOMER_ENTERPRISE_NUMBER: optionalText(customer.enterprise_number),
    CUSTOMER_VAT_NUMBER: optionalText(customer.vat_number),
    CUSTOMER_REPRESENTATIVE: requireText(
      customer.representative_name,
      "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
    ),
    CUSTOMER_REPRESENTATIVE_ROLE: requireText(
      customer.representative_role,
      "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
    ),
    CUSTOMER_EMAIL: requireText(
      customer.email,
      "WEBSITE_COMMERCIAL_PAYLOAD_INVALID",
    ),
    PROJECT_PRICE_EXCL_VAT: formatMoney(
      project.project_price_excl_vat_minor,
      project.currency,
    ),
    PAYMENT_TERM_DAYS: String(paymentTermDays),
    PROJECT_TIMING_WEEKS: String(timingWeeks),
  };
}

function renderTags(
  templateBytes: Uint8Array,
  replacements: Record<string, string>,
): Uint8Array {
  let zip: PizZip;
  try {
    zip = new PizZip(templateBytes);
  } catch {
    throw new Error("WEBSITE_COMMERCIAL_TEMPLATE_MALFORMED");
  }
  const documentPart = zip.file("word/document.xml");
  if (!documentPart) throw new Error("WEBSITE_COMMERCIAL_TEMPLATE_MALFORMED");
  const document = new DOMParser({ onError: () => undefined }).parseFromString(
    documentPart.asText(),
    "application/xml",
  );
  if (!document || document.getElementsByTagName("parsererror").length) {
    throw new Error("WEBSITE_COMMERCIAL_TEMPLATE_MALFORMED");
  }
  const replaced = new Set<string>();
  for (
    const node of Array.from(document.getElementsByTagNameNS(WORD_NS, "t"))
  ) {
    let value = node.textContent || "";
    for (const [key, replacement] of Object.entries(replacements)) {
      const tag = `{{${key}}}`;
      if (value.includes(tag)) {
        value = value.split(tag).join(replacement);
        replaced.add(key);
      }
    }
    node.textContent = value;
  }
  if (
    JSON.stringify([...replaced].sort()) !==
      JSON.stringify(Object.keys(replacements).sort())
  ) {
    throw new Error("WEBSITE_COMMERCIAL_TEMPLATE_TAG_MISMATCH");
  }
  const serialized = new XMLSerializer().serializeToString(
    document as Document,
  );
  if (/\{\{[A-Z0-9_]+\}\}/.test(serialized)) {
    throw new Error("WEBSITE_COMMERCIAL_TEMPLATE_TAG_UNRESOLVED");
  }
  zip.file("word/document.xml", serialized);
  const fixedDate = new Date("2000-01-01T00:00:00.000Z");
  for (const entry of Object.values(zip.files)) entry.date = fixedDate;
  return zip.generate({
    type: "uint8array",
    compression: "DEFLATE",
  }) as Uint8Array;
}

export async function renderWebsiteAgreementConceptDocxBytes(
  input: Readonly<{
    templateBytes: Uint8Array;
    payload: JsonRecord;
  }>,
): Promise<
  Readonly<{
    buffer: Uint8Array;
    sha256: string;
    templateSha256: string;
    agreementStatus: "UNSIGNED_CONCEPT";
    issuanceStatus: "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED";
  }>
> {
  if (input.payload?.document_kind !== "AGREEMENT") {
    throw new Error("WEBSITE_COMMERCIAL_DOCUMENT_KIND_INVALID");
  }
  const rendered = await renderWebsiteCommercialConceptDocxBytes(input);
  if (
    rendered.documentKind !== "AGREEMENT" ||
    rendered.agreementStatus !== "UNSIGNED_CONCEPT"
  ) {
    throw new Error("WEBSITE_COMMERCIAL_DOCUMENT_KIND_INVALID");
  }
  return {
    buffer: rendered.buffer,
    sha256: rendered.sha256,
    templateSha256: rendered.templateSha256,
    agreementStatus: rendered.agreementStatus,
    issuanceStatus: rendered.issuanceStatus,
  };
}

export async function renderWebsiteCommercialConceptDocxBytes(
  input: Readonly<{
    templateBytes: Uint8Array;
    payload: JsonRecord;
  }>,
): Promise<
  Readonly<{
    buffer: Uint8Array;
    sha256: string;
    documentKind: WebsiteCommercialDocumentKind;
    templateSha256: string;
    lineage: JsonRecord;
    agreementStatus: "UNSIGNED_CONCEPT" | null;
    issuanceStatus: "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED";
  }>
> {
  const payload = record(input.payload, "WEBSITE_COMMERCIAL_PAYLOAD_INVALID");
  if (payload.test_only !== true) {
    throw new Error("WEBSITE_COMMERCIAL_CONCEPT_ONLY");
  }
  if (payload.product_family !== "WEBSITE") {
    throw new Error("WEBSITE_COMMERCIAL_PRODUCT_FAMILY_INVALID");
  }
  if (
    typeof payload.document_kind !== "string" ||
    !(payload.document_kind in TEMPLATE_AUTHORITIES)
  ) {
    throw new Error("WEBSITE_COMMERCIAL_DOCUMENT_KIND_INVALID");
  }
  const documentKind = payload.document_kind as WebsiteCommercialDocumentKind;
  const authority = TEMPLATE_AUTHORITIES[documentKind];
  const template = record(
    payload.template,
    "WEBSITE_COMMERCIAL_TEMPLATE_IDENTITY_INVALID",
  );
  const templateSha256 = await sha256(input.templateBytes);
  if (
    template.document_kind !== documentKind ||
    template.derivative_reference !== authority.derivativeReference ||
    template.derivative_sha256 !== authority.derivativeSha256 ||
    templateSha256 !== authority.derivativeSha256
  ) {
    throw new Error("WEBSITE_COMMERCIAL_TEMPLATE_IDENTITY_INVALID");
  }
  const lineage = validateLineage(payload);
  const buffer = renderTags(
    input.templateBytes,
    replacementsFor(payload, documentKind),
  );
  return {
    buffer,
    sha256: await sha256(buffer),
    documentKind,
    templateSha256,
    lineage: { ...lineage },
    agreementStatus: documentKind === "AGREEMENT" ? "UNSIGNED_CONCEPT" : null,
    issuanceStatus: "BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED",
  };
}

export const WEBSITE_AGREEMENT_TEMPLATE_AUTHORITY = Object.freeze({
  documentKind: "AGREEMENT",
  ...TEMPLATE_AUTHORITIES.AGREEMENT,
});

export const WEBSITE_COMMERCIAL_TEMPLATE_AUTHORITIES = TEMPLATE_AUTHORITIES;

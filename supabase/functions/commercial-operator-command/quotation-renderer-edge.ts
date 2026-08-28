import Docxtemplater from "npm:docxtemplater@3.69.3";
import PizZip from "npm:pizzip@3.2.0";

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

function formatMinor(value: number, currency = "EUR"): string {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("INVALID_MINOR_AMOUNT");
  if (currency !== "EUR") throw new Error("UNSUPPORTED_RENDER_CURRENCY");
  const minor = BigInt(value);
  const whole = minor / 100n;
  const cents = (minor % 100n).toString().padStart(2, "0");
  const grouped = whole.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `€ ${grouped},${cents}`;
}

function formatDate(value: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("INVALID_RENDER_DATE");
  const [year, month, day] = value.split("-");
  return `${day}/${month}/${year}`;
}

function optional(value: unknown): Array<{ value: string }> {
  return value === null || value === undefined || value === "" ? [] : [{ value: String(value) }];
}

function listSection(items: unknown): Array<{ items: Array<{ value: string }> }> {
  return Array.isArray(items) && items.length
    ? [{ items: items.map((value) => ({ value: String(value) })) }]
    : [];
}

function formatVat(vat: Record<string, unknown>): string {
  if (vat.vat_treatment === "EXEMPT"
    && vat.rate_semantics === "NOT_APPLICABLE"
    && vat.vat_rate === 0
    && vat.invoice_literal === "Bijzondere vrijstellingsregeling van belasting") {
    return String(vat.invoice_literal);
  }
  if (vat.vat_treatment !== "EXEMPT"
    && vat.rate_semantics === "PERCENT"
    && vat.invoice_literal === null) {
    return `${vat.vat_rate}%`;
  }
  throw new Error("INVALID_RENDER_VAT_SEMANTICS");
}

function record(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(code);
  return value as Record<string, unknown>;
}

function buildRenderModel(rendererPackage: Record<string, unknown>): Record<string, unknown> {
  assertNoForbiddenData(rendererPackage);
  const payload = record(rendererPackage.generation_payload, "INVALID_RENDER_PAYLOAD");
  if (!['PREVIEW', 'ISSUE'].includes(String(payload.mode))) throw new Error("INVALID_RENDER_PAYLOAD");
  if (payload.contract_version !== 1) throw new Error("UNSUPPORTED_RENDER_CONTRACT");
  const locale = record(payload.locale, "UNSUPPORTED_RENDER_LOCALE");
  if (locale.document_language !== "nl" || locale.document_locale !== "nl-BE" || locale.currency !== "EUR") {
    throw new Error("UNSUPPORTED_RENDER_LOCALE");
  }
  const quotation = record(payload.quotation, "INVALID_RENDER_PAYLOAD");
  if (payload.mode === "PREVIEW") {
    if (quotation.quotation_number !== null || quotation.issuance_id !== null) {
      throw new Error("PREVIEW_AUTHORITY_INJECTION");
    }
  } else if (!/^LWS-OFF-[0-9]{4}-[0-9]{4}$/.test(String(quotation.quotation_number || ""))
    || typeof quotation.issuance_id !== "string" || !quotation.issuance_id) {
    throw new Error("INVALID_CANONICAL_ISSUE_IDENTITY");
  }

  const vat = record(payload.vat, "INVALID_RENDER_PAYLOAD");
  const vatDisplay = formatVat(vat);
  const lines = (payload.lines as Array<Record<string, unknown>>).map((line) => ({
    ...line,
    unit_price: formatMinor(Number(line.unit_price_minor)),
    discount: formatMinor(Number(line.discount_minor)),
    vat: vat.vat_treatment === "EXEMPT" ? vatDisplay : `${line.vat_rate}%`,
    line_net_amount: formatMinor(Number(line.line_net_amount_minor)),
  }));
  const paymentSchedule = record(payload.payment_schedule, "INVALID_RENDER_PAYLOAD");
  const milestones = (paymentSchedule.milestones as Array<Record<string, unknown>>).map((milestone) => ({
    ...milestone,
    allocation: milestone.percentage !== null
      ? `${milestone.percentage}%`
      : formatMinor(Number(milestone.amount_minor)),
    due_terms: milestone.due_terms_days === null ? "" : `${milestone.due_terms_days} dagen`,
  }));
  const seller = record(payload.seller, "INVALID_RENDER_PAYLOAD");
  const customer = record(payload.customer, "INVALID_RENDER_PAYLOAD");
  const project = record(payload.project, "INVALID_RENDER_PAYLOAD");
  const totals = record(payload.totals, "INVALID_RENDER_PAYLOAD");
  const validity = record(payload.validity, "INVALID_RENDER_PAYLOAD");
  const legal = record(payload.legal_references, "INVALID_RENDER_PAYLOAD");
  const displayMarkers = payload.mode === "PREVIEW"
    ? record(rendererPackage.display_markers, "INVALID_RENDER_PAYLOAD")
    : null;

  return {
    preview_markers: displayMarkers ? [{ primary: displayMarkers.primary, secondary: displayMarkers.secondary }] : [],
    issue_identity: payload.mode === "ISSUE" ? [{
      quotation_number: quotation.quotation_number,
      quotation_version: quotation.quotation_version,
      status: quotation.quotation_status,
    }] : [],
    seller: {
      ...seller,
      address_line_2_block: optional(seller.address_line_2),
      contact_name_block: optional(seller.contact_name),
    },
    customer: {
      ...customer,
      address_line_2_block: optional(customer.address_line_2),
      contact_name_block: optional(customer.contact_name),
      enterprise_number_block: optional(customer.enterprise_number),
      vat_number_block: optional(customer.vat_number),
    },
    project: {
      ...project,
      requested_languages_text: (project.requested_languages as unknown[]).join(", "),
      indicative_timing_block: optional(project.indicative_timing),
    },
    features_section: listSection(project.features),
    exclusions_section: listSection(project.exclusions),
    assumptions_section: listSection(project.assumptions),
    lines,
    recurring_section: (payload.lines as Array<Record<string, unknown>>)
      .some((line) => line.cost_type === "RECURRING") ? [{}] : [],
    totals: {
      one_time_subtotal: formatMinor(Number(totals.one_time_subtotal_minor)),
      recurring_subtotal: formatMinor(Number(totals.recurring_subtotal_minor)),
      discount_total: formatMinor(Number(totals.discount_total_minor)),
      vat_base: formatMinor(Number(totals.vat_base_minor)),
      vat_amount: formatMinor(Number(totals.vat_amount_minor)),
      total_gross: formatMinor(Number(totals.total_gross_minor)),
    },
    vat: { rate_display: vatDisplay },
    payment_milestones: milestones,
    validity: {
      valid_from: formatDate(String(validity.valid_from)),
      valid_until: formatDate(String(validity.valid_until)),
      validity_days: validity.validity_days,
    },
    legal: {
      terms_reference: legal.terms_reference,
      terms_version: legal.terms_version,
      agreement_block: legal.agreement_reference === null ? [] : [{
        reference: legal.agreement_reference,
        version: legal.agreement_version,
      }],
    },
    acceptance_instruction: payload.acceptance_instruction,
  };
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes).buffer));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function renderQuotationDocxBytes(input: Readonly<{
  templateBytes: Uint8Array;
  rendererPackage: Record<string, unknown>;
}>): Promise<Readonly<{ buffer: Uint8Array; sha256: string }>> {
  const zip = new PizZip(input.templateBytes);
  const doc = new Docxtemplater(zip, {
    paragraphLoop: true,
    linebreaks: true,
    nullGetter: () => "",
    parser: (tag: string) => ({
      get: (scope: unknown) => tag.split(".").reduce<unknown>(
        (value, key) => value === null || value === undefined
          ? undefined
          : (value as Record<string, unknown>)[key],
        scope,
      ),
    }),
  });
  doc.render(buildRenderModel(input.rendererPackage));
  const renderedZip = doc.getZip();
  const fixedDate = new Date("2000-01-01T00:00:00.000Z");
  for (const entry of Object.values(renderedZip.files)) entry.date = fixedDate;
  const buffer = renderedZip.generate({ type: "uint8array", compression: "DEFLATE" }) as Uint8Array;
  return { buffer, sha256: await sha256(buffer) };
}
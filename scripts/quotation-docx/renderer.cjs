const fs = require("node:fs");
const crypto = require("node:crypto");
const PizZip = require("pizzip");
const Docxtemplater = require("docxtemplater");

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

function assertNoForbiddenData(value) {
  if (Array.isArray(value)) return value.forEach(assertNoForbiddenData);
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_KEYS.has(key)) throw new Error(`FORBIDDEN_RENDER_DATA:${key}`);
    assertNoForbiddenData(child);
  }
}

function formatMinor(value, currency = "EUR") {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("INVALID_MINOR_AMOUNT");
  if (currency !== "EUR") throw new Error("UNSUPPORTED_RENDER_CURRENCY");
  const minor = BigInt(value);
  const whole = minor / 100n;
  const cents = (minor % 100n).toString().padStart(2, "0");
  const grouped = whole.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `${currency === "EUR" ? "€" : currency} ${grouped},${cents}`;
}

function formatDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("INVALID_RENDER_DATE");
  const [year, month, day] = value.split("-");
  return `${day}/${month}/${year}`;
}

function optional(value) {
  return value === null || value === undefined || value === "" ? [] : [{ value: String(value) }];
}

function listSection(items) {
  return Array.isArray(items) && items.length
    ? [{ items: items.map((value) => ({ value: String(value) })) }]
    : [];
}

function buildRenderModel(rendererPackage) {
  assertNoForbiddenData(rendererPackage);
  const payload = rendererPackage.generation_payload;
  if (!payload || !["PREVIEW", "ISSUE"].includes(payload.mode)) throw new Error("INVALID_RENDER_PAYLOAD");
  if (payload.contract_version !== 1) throw new Error("UNSUPPORTED_RENDER_CONTRACT");
  if (!payload.locale
    || payload.locale.document_language !== "nl"
    || payload.locale.document_locale !== "nl-BE"
    || payload.locale.currency !== "EUR") {
    throw new Error("UNSUPPORTED_RENDER_LOCALE");
  }
  if (payload.mode === "PREVIEW") {
    if (payload.quotation.quotation_number !== null || payload.quotation.issuance_id !== null) {
      throw new Error("PREVIEW_AUTHORITY_INJECTION");
    }
  } else if (!/^LWS-OFF-[0-9]{4}-[0-9]{4}$/.test(payload.quotation.quotation_number || "")
    || typeof payload.quotation.issuance_id !== "string"
    || payload.quotation.issuance_id.length === 0) {
    throw new Error("INVALID_CANONICAL_ISSUE_IDENTITY");
  }

  const currency = payload.locale.currency;
  const lines = payload.lines.map((line) => ({
    ...line,
    unit_price: formatMinor(line.unit_price_minor, currency),
    discount: formatMinor(line.discount_minor, currency),
    vat: `${line.vat_rate}%`,
    line_net_amount: formatMinor(line.line_net_amount_minor, currency),
  }));
  const milestones = payload.payment_schedule.milestones.map((milestone) => ({
    ...milestone,
    allocation: milestone.percentage !== null
      ? `${milestone.percentage}%`
      : formatMinor(milestone.amount_minor, currency),
    due_terms: milestone.due_terms_days === null ? "" : `${milestone.due_terms_days} dagen`,
  }));
  const previewMarkers = payload.mode === "PREVIEW"
    ? [{
      primary: rendererPackage.display_markers.primary,
      secondary: rendererPackage.display_markers.secondary,
    }]
    : [];

  return {
    preview_markers: previewMarkers,
    issue_identity: payload.mode === "ISSUE" ? [{
      quotation_number: payload.quotation.quotation_number,
      quotation_version: payload.quotation.quotation_version,
      status: payload.quotation.quotation_status,
    }] : [],
    seller: {
      ...payload.seller,
      address_line_2_block: optional(payload.seller.address_line_2),
      contact_name_block: optional(payload.seller.contact_name),
    },
    customer: {
      ...payload.customer,
      address_line_2_block: optional(payload.customer.address_line_2),
      contact_name_block: optional(payload.customer.contact_name),
      enterprise_number_block: optional(payload.customer.enterprise_number),
      vat_number_block: optional(payload.customer.vat_number),
    },
    project: {
      ...payload.project,
      requested_languages_text: payload.project.requested_languages.join(", "),
      indicative_timing_block: optional(payload.project.indicative_timing),
    },
    features_section: listSection(payload.project.features),
    exclusions_section: listSection(payload.project.exclusions),
    assumptions_section: listSection(payload.project.assumptions),
    lines,
    recurring_section: lines.some((line) => line.cost_type === "RECURRING") ? [{}] : [],
    totals: {
      one_time_subtotal: formatMinor(payload.totals.one_time_subtotal_minor, currency),
      recurring_subtotal: formatMinor(payload.totals.recurring_subtotal_minor, currency),
      discount_total: formatMinor(payload.totals.discount_total_minor, currency),
      vat_base: formatMinor(payload.totals.vat_base_minor, currency),
      vat_amount: formatMinor(payload.totals.vat_amount_minor, currency),
      total_gross: formatMinor(payload.totals.total_gross_minor, currency),
    },
    vat: { rate_display: `${payload.vat.vat_rate}%` },
    payment_milestones: milestones,
    validity: {
      valid_from: formatDate(payload.validity.valid_from),
      valid_until: formatDate(payload.validity.valid_until),
      validity_days: payload.validity.validity_days,
    },
    legal: {
      terms_reference: payload.legal_references.terms_reference,
      terms_version: payload.legal_references.terms_version,
      agreement_block: payload.legal_references.agreement_reference === null ? [] : [{
        reference: payload.legal_references.agreement_reference,
        version: payload.legal_references.agreement_version,
      }],
    },
    acceptance_instruction: payload.acceptance_instruction,
  };
}

function renderQuotationDocx({ templatePath, outputPath, rendererPackage }) {
  const template = fs.readFileSync(templatePath);
  const zip = new PizZip(template);
  const doc = new Docxtemplater(zip, {
    paragraphLoop: true,
    linebreaks: true,
    nullGetter: () => "",
    parser: (tag) => ({
      get: (scope) => tag.split(".").reduce(
        (value, key) => value === null || value === undefined ? undefined : value[key],
        scope,
      ),
    }),
  });
  doc.render(buildRenderModel(rendererPackage));
  const renderedZip = doc.getZip();
  const fixedDate = new Date("2000-01-01T00:00:00.000Z");
  for (const entry of Object.values(renderedZip.files)) entry.date = fixedDate;
  const buffer = renderedZip.generate({ type: "nodebuffer", compression: "DEFLATE" });
  fs.writeFileSync(outputPath, buffer);
  return { buffer, sha256: crypto.createHash("sha256").update(buffer).digest("hex") };
}

module.exports = { assertNoForbiddenData, buildRenderModel, formatDate, formatMinor, renderQuotationDocx };
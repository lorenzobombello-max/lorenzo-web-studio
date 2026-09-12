const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const RESPONSE_KEYS = Object.freeze([
  "quote_request_id",
  "intake_id",
  "vat_readiness",
  "classification_status",
  "turnover_status",
  "blocking_reason",
  "policy_version",
  "context_sha256",
  "resolved_at",
  "can_request_review",
  "can_request_turnover_refresh",
]);
const READINESS_PRESENTATION = Object.freeze({
  READY: Object.freeze({ label: "Gereed", tone: "ready" }),
  PENDING_EVIDENCE: Object.freeze({ label: "Bewijs ontbreekt", tone: "missing" }),
  REVIEW_REQUIRED: Object.freeze({ label: "Beoordeling vereist", tone: "review" }),
  UNSUPPORTED: Object.freeze({ label: "Niet ondersteund", tone: "unsupported" }),
  STALE: Object.freeze({ label: "Verouderd", tone: "stale" }),
  ERROR: Object.freeze({ label: "Tijdelijk niet beschikbaar", tone: "error" }),
});
const COMPONENT_PRESENTATION = Object.freeze({
  READY: Object.freeze({ label: "Gereed", tone: "ready" }),
  MISSING: Object.freeze({ label: "Ontbreekt", tone: "missing" }),
  REVIEW_REQUIRED: Object.freeze({ label: "Beoordeling vereist", tone: "review" }),
  UNSUPPORTED: Object.freeze({ label: "Niet ondersteund", tone: "unsupported" }),
  STALE: Object.freeze({ label: "Verouderd", tone: "stale" }),
});
const BLOCKING_REASONS = new Set([
  "VAT_BILLING_CONTEXT_REQUIRED",
  "VAT_INDIVIDUAL_POLICY_REVIEW_REQUIRED",
  "VAT_CLASSIFICATION_REVIEW_REQUIRED",
  "VAT_CLASSIFICATION_EVIDENCE_REQUIRED",
  "VAT_POLICY_UNSUPPORTED",
  "VAT_TURNOVER_POLICY_REQUIRED",
  "VAT_TURNOVER_EVIDENCE_REQUIRED",
  "VAT_TURNOVER_STALE",
  "VAT_TURNOVER_SOURCE_INVALID",
  "VAT_CONTEXT_STALE",
  "VAT_EVIDENCE_READY",
  "VAT_READINESS_ERROR",
]);

function invalidReadiness() {
  throw new Error("INVALID_VAT_READINESS");
}

function exactKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).length === keys.length &&
    keys.every((key) => Object.hasOwn(value, key));
}

function validInstant(value) {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function validCalendarDate(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
  })[character]);
}

export function normalizeVatReadiness(value) {
  if (
    !exactKeys(value, RESPONSE_KEYS) ||
    !UUID.test(String(value.quote_request_id || "")) ||
    !UUID.test(String(value.intake_id || "")) ||
    !Object.hasOwn(READINESS_PRESENTATION, value.vat_readiness) ||
    !Object.hasOwn(COMPONENT_PRESENTATION, value.classification_status) ||
    !["READY", "MISSING", "STALE"].includes(value.turnover_status) ||
    !BLOCKING_REASONS.has(value.blocking_reason) ||
    (value.policy_version !== null && typeof value.policy_version !== "string") ||
    (value.context_sha256 !== null && !SHA256.test(String(value.context_sha256))) ||
    (value.resolved_at !== null && !validInstant(value.resolved_at)) ||
    typeof value.can_request_review !== "boolean" ||
    typeof value.can_request_turnover_refresh !== "boolean"
  ) invalidReadiness();
  return Object.freeze(Object.fromEntries(
    RESPONSE_KEYS.map((key) => [key, value[key]]),
  ));
}

function billingPresentation(viewModel) {
  return viewModel.blocking_reason === "VAT_BILLING_CONTEXT_REQUIRED"
    ? COMPONENT_PRESENTATION.MISSING
    : COMPONENT_PRESENTATION.READY;
}

function remediation(viewModel) {
  if (viewModel.vat_readiness === "READY") {
    return "De BTW-context is actueel en server-side gecontroleerd.";
  }
  if (viewModel.vat_readiness === "REVIEW_REQUIRED") {
    return viewModel.can_request_review
      ? "Vraag beoordeling aan. De offerte blijft geblokkeerd tot de server nieuw bewijs bevestigt."
      : "De beoordeling is aangevraagd. Vernieuw de status zodra deze is verwerkt.";
  }
  if (viewModel.vat_readiness === "UNSUPPORTED") {
    return "Deze context valt niet onder het huidige beleid. Er is geen handmatige override beschikbaar.";
  }
  if (viewModel.vat_readiness === "STALE") {
    return "De BTW-context is gewijzigd of verouderd. Evalueer de serverstatus opnieuw.";
  }
  if (viewModel.vat_readiness === "ERROR") {
    return "De BTW-status is tijdelijk niet beschikbaar. Probeer de evaluatie later opnieuw.";
  }
  return viewModel.can_request_turnover_refresh
    ? "Vraag omzetbewijs op en vernieuw daarna de serverstatus."
    : "Vernieuw de status zodra het ontbrekende bewijs beschikbaar is.";
}

function row(label, presentation) {
  return `<div class="operator-vat-readiness__row" data-state="${presentation.tone}"><dt>${label}</dt><dd>${presentation.label}</dd></div>`;
}

export function renderVatReadinessPanel(viewModel) {
  const normalized = normalizeVatReadiness(viewModel);
  const readiness = READINESS_PRESENTATION[normalized.vat_readiness];
  const classification = COMPONENT_PRESENTATION[normalized.classification_status];
  const turnover = COMPONENT_PRESENTATION[normalized.turnover_status];
  const actions = [];
  if (normalized.can_request_review) {
    actions.push('<button type="button" class="secondary-action operator-vat-readiness__action" data-vat-action="request_quotation_vat_review" title="Vraag beoordeling aan" aria-label="Vraag beoordeling aan"><span aria-hidden="true">?</span><span>Vraag beoordeling aan</span></button>');
  }
  if (normalized.can_request_turnover_refresh) {
    actions.push('<button type="button" class="secondary-action operator-vat-readiness__action" data-vat-action="request_vat_turnover_refresh" title="Vraag omzetbewijs op" aria-label="Vraag omzetbewijs op"><span aria-hidden="true">&#8635;</span><span>Vraag omzetbewijs op</span></button>');
  }
  const policy = normalized.policy_version === null
    ? ""
    : `<p class="operator-vat-readiness__policy">Beleidsversie: ${escapeHtml(normalized.policy_version)}</p>`;
  return `<section class="operator-vat-readiness" aria-labelledby="operator-vat-readiness-title" data-vat-readiness="${readiness.tone}"><h4 id="operator-vat-readiness-title">BTW-context</h4><dl>${row("Facturatiegegevens", billingPresentation(normalized))}${row("Transactieclassificatie", classification)}${row("Omzetbewijs", turnover)}${row("Offerte", readiness)}</dl><p class="operator-vat-readiness__remediation">${escapeHtml(remediation(normalized))}</p>${policy}${actions.length ? `<div class="lifecycle-actions operator-vat-readiness__actions">${actions.join("")}</div>` : ""}</section>`;
}

export function canComposeQuotationFromVatReadiness(viewModel) {
  return normalizeVatReadiness(viewModel).vat_readiness === "READY";
}

function requiredUuid(value) {
  const result = String(value || "");
  if (!UUID.test(result)) throw new Error("INVALID_VAT_READINESS_ACTION");
  return result;
}

export function buildVatReadinessAction(action, state, reason) {
  if (!state || typeof state !== "object" || Array.isArray(state)) {
    throw new Error("INVALID_VAT_READINESS_ACTION");
  }
  if (action === "evaluate_quotation_vat_readiness") {
    return Object.freeze({
      action,
      quote_request_id: requiredUuid(state.quote_request_id),
    });
  }
  if (action === "request_quotation_vat_review") {
    const normalizedReason = typeof reason === "string" ? reason.trim() : "";
    if (normalizedReason.length < 1 || normalizedReason.length > 2000) {
      throw new Error("INVALID_VAT_READINESS_ACTION");
    }
    return Object.freeze({
      action,
      quote_request_id: requiredUuid(state.quote_request_id),
      intake_id: requiredUuid(state.intake_id),
      reason: normalizedReason,
      idempotency_key: requiredUuid(state.idempotency_key),
    });
  }
  if (action === "request_vat_turnover_refresh") {
    if (!validCalendarDate(state.measurement_date)) {
      throw new Error("INVALID_VAT_READINESS_ACTION");
    }
    return Object.freeze({
      action,
      measurement_date: state.measurement_date,
      idempotency_key: requiredUuid(state.idempotency_key),
    });
  }
  throw new Error("INVALID_VAT_READINESS_ACTION");
}
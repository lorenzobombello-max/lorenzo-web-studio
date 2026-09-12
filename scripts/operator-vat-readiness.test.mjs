import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  buildVatReadinessAction,
  canComposeQuotationFromVatReadiness,
  normalizeVatReadiness,
  renderVatReadinessPanel,
} from "../assets/js/operator-vat-readiness.mjs";

const REQUEST_ID = "be410000-0000-4000-8000-000000000001";
const INTAKE_ID = "be420000-0000-4000-8000-000000000001";
const IDEMPOTENCY_KEY = "be430000-0000-4000-8000-000000000001";
const RESPONSE_KEYS = [
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
];

const readyResponse = {
  quote_request_id: REQUEST_ID,
  intake_id: INTAKE_ID,
  vat_readiness: "READY",
  classification_status: "READY",
  turnover_status: "READY",
  blocking_reason: "VAT_EVIDENCE_READY",
  policy_version: "classification-v1",
  context_sha256: "a".repeat(64),
  resolved_at: "2026-09-11T12:00:00.000Z",
  can_request_review: false,
  can_request_turnover_refresh: false,
};

test("normalizes only the exact browser-safe readiness response", () => {
  const result = normalizeVatReadiness(readyResponse);
  assert.deepEqual(result, readyResponse);
  assert.deepEqual(Object.keys(result), RESPONSE_KEYS);
  assert.equal(Object.isFrozen(result), true);
  assert.throws(
    () => normalizeVatReadiness({ ...readyResponse, source_sha256: "b".repeat(64) }),
    /INVALID_VAT_READINESS/,
  );
  assert.throws(
    () => normalizeVatReadiness({ ...readyResponse, vat_readiness: "POLICY_REQUIRED" }),
    /INVALID_VAT_READINESS/,
  );
});

test("READY alone permits quotation composition", () => {
  assert.equal(canComposeQuotationFromVatReadiness(
    normalizeVatReadiness(readyResponse)), true);
  for (const vat_readiness of [
    "PENDING_EVIDENCE", "REVIEW_REQUIRED", "UNSUPPORTED", "STALE", "ERROR",
  ]) {
    assert.equal(canComposeQuotationFromVatReadiness(
      normalizeVatReadiness({
        ...readyResponse,
        vat_readiness,
        blocking_reason: vat_readiness === "UNSUPPORTED"
          ? "VAT_POLICY_UNSUPPORTED"
          : vat_readiness === "STALE"
          ? "VAT_CONTEXT_STALE"
          : vat_readiness === "ERROR"
          ? "VAT_READINESS_ERROR"
          : vat_readiness === "REVIEW_REQUIRED"
          ? "VAT_CLASSIFICATION_REVIEW_REQUIRED"
          : "VAT_TURNOVER_EVIDENCE_REQUIRED",
        resolved_at: null,
      })), false);
  }
});

test("browser and DOM overrides cannot promote blocked readiness", () => {
  const blocked = {
    ...readyResponse,
    vat_readiness: "REVIEW_REQUIRED",
    classification_status: "REVIEW_REQUIRED",
    blocking_reason: "VAT_INDIVIDUAL_POLICY_REVIEW_REQUIRED",
    resolved_at: null,
    can_request_review: true,
  };
  assert.equal(canComposeQuotationFromVatReadiness(blocked), false);
  assert.throws(
    () => canComposeQuotationFromVatReadiness({
      ...blocked,
      vat_readiness: "READY",
      can_compose_quotation: true,
    }),
    /INVALID_VAT_READINESS/,
  );
  const html = renderVatReadinessPanel(blocked);
  assert.doesNotMatch(
    html,
    /data-dossiers-website-pricing-compose|data-dossiers-website-quotation-form|type="submit"/,
  );
});

test("quotation compose and submit both require server READY and authoritative refetch", async () => {
  const source = await readFile(
    new URL("../assets/js/operator-dossiers.mjs", import.meta.url),
    "utf8",
  );
  assert.match(
    source,
    /event\.target\.matches\("\[data-dossiers-website-quotation-form\]"\)[\s\S]*websiteQuotationCanCompose\(presentation, state\.vatReadiness\)/,
  );
  assert.match(
    source,
    /target\.hasAttribute\("data-dossiers-website-pricing-compose"\)[\s\S]*websiteQuotationCanCompose\(presentation, state\.vatReadiness\)/,
  );
  assert.match(
    source,
    /async function refreshWebsiteQuotationAuthorities[\s\S]*state\.vatReadiness = null[\s\S]*Promise\.all\([\s\S]*authority\.gateway\(pricingRequest\)[\s\S]*authority\.gateway\(vatRequest\)/,
  );
  assert.match(
    source,
    /await authority\.gateway\(request\)[\s\S]*await refreshWebsiteQuotationAuthorities\(selection\)/,
  );
});

test("renders the four compact Dutch readiness rows for all six states", () => {
  const labels = new Map([
    ["READY", "Gereed"],
    ["PENDING_EVIDENCE", "Bewijs ontbreekt"],
    ["REVIEW_REQUIRED", "Beoordeling vereist"],
    ["UNSUPPORTED", "Niet ondersteund"],
    ["STALE", "Verouderd"],
    ["ERROR", "Tijdelijk niet beschikbaar"],
  ]);
  for (const [vat_readiness, label] of labels) {
    const html = renderVatReadinessPanel(normalizeVatReadiness({
      ...readyResponse,
      vat_readiness,
      blocking_reason: vat_readiness === "READY"
        ? "VAT_EVIDENCE_READY"
        : "VAT_READINESS_ERROR",
      resolved_at: vat_readiness === "READY" ? readyResponse.resolved_at : null,
    }));
    assert.match(html, /BTW-context/);
    assert.match(html, /Facturatiegegevens/);
    assert.match(html, /Transactieclassificatie/);
    assert.match(html, /Omzetbewijs/);
    assert.match(html, /Offerte/);
    assert.match(html, new RegExp(label));
    assert.doesNotMatch(html, /<article|class="[^\"]*card/);
  }
});

test("renders state-specific remediation and only server-authorized intents", () => {
  const reviewHtml = renderVatReadinessPanel(normalizeVatReadiness({
    ...readyResponse,
    vat_readiness: "REVIEW_REQUIRED",
    classification_status: "REVIEW_REQUIRED",
    turnover_status: "MISSING",
    blocking_reason: "VAT_INDIVIDUAL_POLICY_REVIEW_REQUIRED",
    resolved_at: null,
    can_request_review: true,
  }));
  assert.match(reviewHtml, /Vraag beoordeling aan/);
  assert.match(reviewHtml, /data-vat-action="request_quotation_vat_review"/);
  assert.doesNotMatch(reviewHtml, /approve_quotation_vat_review|Goedkeuren/);

  const pendingHtml = renderVatReadinessPanel(normalizeVatReadiness({
    ...readyResponse,
    vat_readiness: "PENDING_EVIDENCE",
    turnover_status: "MISSING",
    blocking_reason: "VAT_TURNOVER_EVIDENCE_REQUIRED",
    resolved_at: null,
    can_request_turnover_refresh: true,
  }));
  assert.match(pendingHtml, /Vraag omzetbewijs op/);
  assert.match(pendingHtml, /data-vat-action="request_vat_turnover_refresh"/);

  const unsupportedHtml = renderVatReadinessPanel(normalizeVatReadiness({
    ...readyResponse,
    vat_readiness: "UNSUPPORTED",
    classification_status: "UNSUPPORTED",
    blocking_reason: "VAT_POLICY_UNSUPPORTED",
    resolved_at: null,
  }));
  assert.match(unsupportedHtml, /huidige beleid/);
  assert.doesNotMatch(unsupportedHtml, /data-vat-action=/);
});

test("renderer escapes all server-projected text and omits sensitive values", () => {
  const html = renderVatReadinessPanel(normalizeVatReadiness({
    ...readyResponse,
    policy_version: "<img src=x onerror=alert(1)>",
  }));
  assert.doesNotMatch(html, /<img/);
  assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
  for (const sensitive of [
    "classification_code", "governed_turnover_minor", "vat_rate",
    "vat_treatment", "source_sha256", "source_projection_id", "adapter_id",
    "ledger_source_details", "service_role_key", "approve_quotation_vat_review",
  ]) assert.doesNotMatch(html, new RegExp(sensitive));
  assert.doesNotMatch(html, /<input|<select|<textarea/);
});

test("turnover refresh carries no authority values", () => {
  assert.deepEqual(buildVatReadinessAction("request_vat_turnover_refresh", {
    measurement_date: "2026-09-11",
    idempotency_key: IDEMPOTENCY_KEY,
    governed_turnover_minor: 1,
    source_sha256: "b".repeat(64),
  }), {
    action: "request_vat_turnover_refresh",
    measurement_date: "2026-09-11",
    idempotency_key: IDEMPOTENCY_KEY,
  });
});

test("readiness and review builders emit only exact command keys", () => {
  assert.deepEqual(buildVatReadinessAction("evaluate_quotation_vat_readiness", {
    quote_request_id: REQUEST_ID,
    classification_code: "FORGED",
  }), {
    action: "evaluate_quotation_vat_readiness",
    quote_request_id: REQUEST_ID,
  });
  assert.deepEqual(buildVatReadinessAction("request_quotation_vat_review", {
    quote_request_id: REQUEST_ID,
    intake_id: INTAKE_ID,
    idempotency_key: IDEMPOTENCY_KEY,
  }, "  Beoordeling vereist  "), {
    action: "request_quotation_vat_review",
    quote_request_id: REQUEST_ID,
    intake_id: INTAKE_ID,
    reason: "Beoordeling vereist",
    idempotency_key: IDEMPOTENCY_KEY,
  });
  assert.throws(
    () => buildVatReadinessAction("approve_quotation_vat_review", readyResponse),
    /INVALID_VAT_READINESS_ACTION/,
  );
});
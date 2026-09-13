const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const READINESS_STATES = new Set([
  "READY", "PENDING_EVIDENCE", "REVIEW_REQUIRED", "UNSUPPORTED", "STALE", "ERROR",
]);
const CLASSIFICATION_STATES = new Set([
  "READY", "MISSING", "REVIEW_REQUIRED", "UNSUPPORTED", "STALE",
]);
const TURNOVER_STATES = new Set(["READY", "MISSING", "STALE"]);
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

export type VatReadinessActionInput = Readonly<{
  action: "evaluate_quotation_vat_readiness";
  quote_request_id: string;
}>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).length === keys.length &&
    keys.every((key) => Object.hasOwn(value, key));
}

export function validateVatReadinessAction(
  value: unknown,
): VatReadinessActionInput {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["action", "quote_request_id"]) ||
    value.action !== "evaluate_quotation_vat_readiness" ||
    !UUID.test(String(value.quote_request_id || ""))
  ) throw new Error("INVALID_REQUEST");
  return {
    action: value.action,
    quote_request_id: String(value.quote_request_id),
  };
}

export function normalizeVatReadinessResponse(
  value: unknown,
): Readonly<Record<string, unknown>> {
  const keys = [
    "quote_request_id", "intake_id", "vat_readiness", "classification_status",
    "turnover_status", "blocking_reason", "policy_version", "context_sha256",
    "resolved_at", "can_request_review", "can_request_turnover_refresh",
  ];
  if (
    !isRecord(value) || !hasExactKeys(value, keys) ||
    !UUID.test(String(value.quote_request_id || "")) ||
    !UUID.test(String(value.intake_id || "")) ||
    !READINESS_STATES.has(String(value.vat_readiness || "")) ||
    !CLASSIFICATION_STATES.has(String(value.classification_status || "")) ||
    !TURNOVER_STATES.has(String(value.turnover_status || "")) ||
    !BLOCKING_REASONS.has(String(value.blocking_reason || "")) ||
    (value.policy_version !== null && typeof value.policy_version !== "string") ||
    (value.context_sha256 !== null && !SHA256.test(String(value.context_sha256))) ||
    (value.resolved_at !== null &&
      (typeof value.resolved_at !== "string" ||
        !Number.isFinite(Date.parse(value.resolved_at)))) ||
    typeof value.can_request_review !== "boolean" ||
    typeof value.can_request_turnover_refresh !== "boolean"
  ) throw new Error("INVALID_VAT_READINESS_RESPONSE");
  return value;
}
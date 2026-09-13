import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  normalizeVatReadinessResponse,
  validateVatReadinessAction,
} from "./vat-readiness.ts";

const quoteRequestId = "7d120000-0000-4000-8000-000000000001";
const intakeId = "7d130000-0000-4000-8000-000000000001";

Deno.test("VAT action validation accepts only server-minimal exact inputs", () => {
  const request = {
    action: "evaluate_quotation_vat_readiness",
    quote_request_id: quoteRequestId,
  };
  assertEquals(validateVatReadinessAction(request), request);
  for (const invalid of [
    { action: request.action },
    { ...request, quote_request_id: "bad" },
    { ...request, extra: true },
  ]) {
    assertThrows(() => validateVatReadinessAction(invalid), "INVALID_REQUEST");
  }
});

Deno.test("VAT readiness response validation is exact", () => {
  const response = {
    quote_request_id: quoteRequestId,
    intake_id: intakeId,
    vat_readiness: "READY",
    classification_status: "READY",
    turnover_status: "READY",
    blocking_reason: "VAT_EVIDENCE_READY",
    policy_version: "v1",
    context_sha256: "a".repeat(64),
    resolved_at: "2099-01-01T00:00:00Z",
    can_request_review: false,
    can_request_turnover_refresh: false,
  };
  assertEquals(normalizeVatReadinessResponse(response), response);
  assertThrows(
    () => normalizeVatReadinessResponse({ ...response, extra: true }),
    "INVALID_VAT_READINESS_RESPONSE",
  );
});
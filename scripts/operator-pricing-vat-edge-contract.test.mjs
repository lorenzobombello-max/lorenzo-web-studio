import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  websiteQuotationPricingStateRequest,
  websiteQuotationVatReadinessRequest,
} from "../assets/js/operator-dossiers.mjs";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8").catch(() => "");
const [handler, handlerTests, index, vatReadiness, vatReadinessTests] = await Promise.all([
  read("supabase/functions/commercial-operator-command/handler.ts"),
  read("supabase/functions/commercial-operator-command/handler.test.ts"),
  read("supabase/functions/commercial-operator-command/index.ts"),
  read("supabase/functions/commercial-operator-command/vat-readiness.ts"),
  read("supabase/functions/commercial-operator-command/vat-readiness.test.ts"),
]);

const detail = Object.freeze({
  quote_request_id: "7d120000-0000-4000-8000-000000000001",
  request_kind: "website",
  intake_lifecycle: Object.freeze({
    intake_id: "7d130000-0000-4000-8000-000000000001",
  }),
  quotation: null,
  acceptance: null,
});

test("FRONTEND_PRICING_REQUEST_MATCHES_EDGE", () => {
  assert.deepEqual(websiteQuotationPricingStateRequest(detail), {
    action: "get_website_quotation_pricing_state",
    quote_request_id: detail.quote_request_id,
    intake_id: detail.intake_lifecycle.intake_id,
  });
  assert.match(handler, /"get_website_quotation_pricing_state"/);
  assert.match(handler, /action === "get_website_quotation_pricing_state"[\s\S]*?new Set\(\["action", "quote_request_id", "intake_id"\]\)/);
  assert.match(handlerTests, /pricing read accepts only the canonical frontend contract/);
  assert.match(handlerTests, /pricingStateRequest[\s\S]*?extra: true/);
  assert.match(index, /executeWebsiteQuotationPricingStateAction[\s\S]*?get_operator_website_quotation_pricing_state_v1/);
  assert.match(index, /INVALID_WEBSITE_PRICING_STATE_RESPONSE/);
  console.log("FRONTEND_PRICING_REQUEST_MATCHES_EDGE=PASS");
  console.log("PRICING_REQUEST_CONTRACT_GATE=PASS");
});

test("FRONTEND_VAT_REQUEST_MATCHES_EDGE", () => {
  assert.deepEqual(websiteQuotationVatReadinessRequest(detail), {
    action: "evaluate_quotation_vat_readiness",
    quote_request_id: detail.quote_request_id,
  });
  assert.match(handler, /"evaluate_quotation_vat_readiness"/);
  assert.match(handler, /action === "evaluate_quotation_vat_readiness"[\s\S]*?new Set\(\["action", "quote_request_id"\]\)/);
  assert.match(vatReadiness, /hasExactKeys\(value, \["action", "quote_request_id"\]\)/);
  assert.match(vatReadinessTests, /VAT action validation accepts only server-minimal exact inputs/);
  assert.match(vatReadinessTests, /quote_request_id: "bad"/);
  assert.match(index, /executeCallerJwtQuotationVatReadinessAction[\s\S]*?get_quotation_vat_readiness_v1/);
  assert.match(index, /normalizeVatReadinessResponse/);
  console.log("FRONTEND_VAT_REQUEST_MATCHES_EDGE=PASS");
  console.log("VAT_REQUEST_CONTRACT_GATE=PASS");
});
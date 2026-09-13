import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  retainProjectWorkspace,
  retainWebsiteQuotationAuthorities,
} from "../assets/js/operator-dossiers.mjs";

const quoteRequestA = "a1800000-0000-4000-8000-000000000001";
const quoteRequestB = "a1800000-0000-4000-8000-000000000002";
const oldDetail = Object.freeze({ quote_request_id: quoteRequestA });
const oldPricing = Object.freeze({ quote_request_id: quoteRequestA, revision: 1 });
const oldVatReadiness = Object.freeze({ quote_request_id: quoteRequestA, vat_readiness: "READY" });
const oldProjectWorkspace = Object.freeze({ state: "empty", message: "Geen project gekoppeld." });

const source = await readFile(
  new URL("../assets/js/operator-dossiers.mjs", import.meta.url),
  "utf8",
);

test("background pricing refresh retains the last valid same-dossier presentation", () => {
  const retained = retainWebsiteQuotationAuthorities(
    oldDetail,
    oldPricing,
    oldVatReadiness,
    quoteRequestA,
  );
  assert.equal(retained.detail, oldDetail);
  assert.equal(retained.pricing, oldPricing);
  assert.equal(retained.vatReadiness, oldVatReadiness);
});

test("successful pricing refresh can atomically replace the retained presentation", () => {
  const retained = retainWebsiteQuotationAuthorities(
    { quote_request_id: quoteRequestA },
    oldPricing,
    oldVatReadiness,
    quoteRequestA,
  );
  const nextPricing = Object.freeze({ quote_request_id: quoteRequestA, revision: 2 });
  const nextVatReadiness = Object.freeze({ quote_request_id: quoteRequestA, vat_readiness: "PENDING_EVIDENCE" });
  const state = { websitePricing: retained.pricing, vatReadiness: retained.vatReadiness };
  [state.websitePricing, state.vatReadiness] = [nextPricing, nextVatReadiness];
  assert.equal(state.websitePricing, nextPricing);
  assert.equal(state.vatReadiness, nextVatReadiness);
});

test("pricing refresh failure leaves the retained same-dossier presentation intact", () => {
  const state = retainWebsiteQuotationAuthorities(
    { quote_request_id: quoteRequestA },
    oldPricing,
    oldVatReadiness,
    quoteRequestA,
  );
  assert.equal(state.pricing, oldPricing);
  assert.equal(state.vatReadiness, oldVatReadiness);
});

test("dossier selection changes never retain pricing from the previous dossier", () => {
  const retained = retainWebsiteQuotationAuthorities(
    oldDetail,
    oldPricing,
    oldVatReadiness,
    quoteRequestB,
  );
  assert.deepEqual(retained, { detail: null, pricing: null, vatReadiness: null });
});

test("SAME_DOSSIER_PRICING_NEVER_EMPTY while other dossier data is pending", () => {
  const retained = retainWebsiteQuotationAuthorities(
    oldDetail,
    oldPricing,
    oldVatReadiness,
    quoteRequestA,
  );
  const frames = [
    retained,
    retained,
    {
      detail: Object.freeze({ quote_request_id: quoteRequestA }),
      pricing: Object.freeze({ quote_request_id: quoteRequestA, revision: 2 }),
      vatReadiness: Object.freeze({ quote_request_id: quoteRequestA, vat_readiness: "READY" }),
    },
  ];
  assert.ok(frames.every((frame)=>frame.detail && frame.pricing && frame.vatReadiness));
  assert.match(
    source,
    /state\.detail = retainedWebsiteAuthorities\.detail \|\| retainedWebsiteWorkSnapshot\?\.detail \|\| null;/,
  );
});

test("SAME_DOSSIER_PRICING_NEVER_HIDDEN and never replaced by loading presentation", () => {
  assert.doesNotMatch(source, /if \(background\)[\s\S]{0,240}state\.websitePricing = null/);
  assert.doesNotMatch(source, /if \(background\)[\s\S]{0,240}pricingPanel\.hidden = true/);
});

test("FAILED_REFRESH_RETAINS_LAST_VALID and CROSS_DOSSIER_CLEARS_OLD_PRICING", () => {
  const failedRefresh = retainWebsiteQuotationAuthorities(
    oldDetail,
    oldPricing,
    oldVatReadiness,
    quoteRequestA,
  );
  const switched = retainWebsiteQuotationAuthorities(
    oldDetail,
    oldPricing,
    oldVatReadiness,
    quoteRequestB,
  );
  assert.equal(failedRefresh.pricing, oldPricing);
  assert.equal(failedRefresh.vatReadiness, oldVatReadiness);
  assert.deepEqual(switched, { detail: null, pricing: null, vatReadiness: null });
});

test("background refresh retains the same dossier project presentation", () => {
  assert.equal(
    retainProjectWorkspace(oldDetail, oldProjectWorkspace, quoteRequestA),
    oldProjectWorkspace,
  );
});

test("dossier selection changes never retain the previous project presentation", () => {
  assert.equal(
    retainProjectWorkspace(oldDetail, oldProjectWorkspace, quoteRequestB),
    null,
  );
});

test("Dossiers refresh retains by identity and replaces paired authorities after both fetches", () => {
  assert.match(
    source,
    /retainWebsiteWorkSnapshot\([\s\S]*summary\.raw\?\.quote_request_id,[\s\S]*retainWebsiteQuotationAuthorities\([\s\S]*state\.detail = retainedWebsiteAuthorities\.detail \|\| retainedWebsiteWorkSnapshot\?\.detail \|\| null;[\s\S]*state\.websitePricing = retainedWebsiteAuthorities\.pricing;[\s\S]*state\.vatReadiness = retainedWebsiteAuthorities\.vatReadiness;/,
  );
  const refreshBody = source.match(
    /async function refreshWebsiteQuotationAuthorities\(selection\) \{([\s\S]*?)\n  \}/,
  )?.[1] || "";
  assert.doesNotMatch(refreshBody, /state\.vatReadiness = null/);
  assert.match(refreshBody, /await Promise\.all/);
  assert.match(
    refreshBody,
    /state\.websitePricing = pricing;\s+state\.vatReadiness = normalizeVatReadiness\(vatReadiness\);/,
  );
  assert.match(
    source,
    /const retainedProjectWorkspace = retainProjectWorkspace\([\s\S]*state\.projectWorkspace = retainedProjectWorkspace;[\s\S]*if \(state\.projectWorkspace\) renderProjectWorkspace\(workspace, state\.projectWorkspace\);/,
  );
});
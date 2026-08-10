import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  mapAdminPricingReadRow,
  mapCustomerPricingReadRow,
} from "./pricing-read-dto.ts";

function customerRow(overrides: Record<string, unknown> = {}) {
  return {
    intake_status: "submitted",
    snapshot_present: true,
    snapshot_contract_version: 2,
    calculation_basis: "starter_floor",
    currency: "EUR",
    vat_basis: "exclusive",
    known_minimum_minor: 220_000,
    contains_from_pricing: true,
    manual_review_required: false,
    manual_reason_count: 0,
    budget_contract_version: 2,
    evidence_provenance: "budget_guard_v1",
    budget_status: "possibly_compatible_with_category",
    outside_budget_wishes: false,
    futureInternalSecret: "must-never-leak",
    ...overrides,
  };
}

function calculation(manualReviewRequired = false) {
  return {
    basis: "starter_floor",
    currency: "EUR",
    vatBasis: "exclusive",
    knownMinimumMinor: 220_000,
    containsFromPricing: true,
    manualReviewRequired,
    manualReasons: manualReviewRequired ? ["shop_manual"] : [],
    appliedRules: [
      {
        ruleId: "starter_floor",
        mode: "from",
        amountMinor: 180_000,
        quantity: 1,
        knownMinimumContributionMinor: 180_000,
      },
    ],
    futureInternalSecret: "must-never-leak",
  };
}

function budgetEvaluation(
  evidenceProvenance = "budget_guard_v1",
  outsideBudgetWishes: boolean | null = false,
) {
  const status = outsideBudgetWishes === true
    ? "known_minimum_exceeds_category_upper_bound"
    : outsideBudgetWishes === false
    ? "possibly_compatible_with_category"
    : evidenceProvenance === "legacy_label"
    ? "legacy_category_not_safely_comparable"
    : "manual_review_required";
  return {
    contractVersion: 2,
    evidenceProvenance,
    categoryScheme: evidenceProvenance === "budget_guard_v1"
      ? "budget_guard_v1"
      : null,
    categoryCode: evidenceProvenance === "budget_guard_v1"
      ? "3200_to_6000_inclusive"
      : null,
    originalLabel: evidenceProvenance === "missing"
      ? null
      : evidenceProvenance === "budget_guard_v1"
      ? "EUR 3.200 t/m EUR 6.000"
      : "EUR 3.000 - EUR 6.000",
    status,
    outsideBudgetWishes,
  };
}

function normalizedScope() {
  return {
    standardPages: ["home"],
    standardPageCount: 1,
    primaryLanguage: "nl",
    additionalLanguages: [],
    unknownLanguages: [],
    modules: [],
    manualComponents: [],
    futureInternalSecret: "must-never-leak",
  };
}

function adminRow(overrides: Record<string, unknown> = {}) {
  return {
    intake_status: "submitted",
    snapshot_present: true,
    snapshot_contract_version: 2,
    snapshot_created_at: "2026-08-10T12:00:00.000Z",
    config_version: "1.0.0",
    config_hash: "a".repeat(64),
    calculation: calculation(),
    package_advice: {
      status: "consider_professional",
      reasons: ["standard_page_count_above_starter_scope"],
      advisoryOnly: true,
      selectedPackage: null,
    },
    budget_evaluation: budgetEvaluation(),
    normalized_scope: normalizedScope(),
    futureInternalSecret: "must-never-leak",
    ...overrides,
  };
}

function allKeys(value: unknown): string[] {
  if (!value || typeof value !== "object") return [];
  if (Array.isArray(value)) return value.flatMap(allKeys);
  return Object.entries(value).flatMap(([key, child]) => [key, ...allKeys(child)]);
}

Deno.test("customer automatic v2 exposes only historical indicative starting price", () => {
  const dto = mapCustomerPricingReadRow(customerRow());
  assertEquals(dto.indicativeStartingPrice?.amountMinor, 220_000);
  assertEquals(dto.indicativeStartingPrice?.vatLabel, "excl_btw");
  assertEquals(dto.pricingState, "indicative_starting_price_available");
  assertEquals(dto.budgetIndicator, "no_known_minimum_conflict_detected");
});

Deno.test("customer manual review omits amount property entirely", () => {
  const dto = mapCustomerPricingReadRow(customerRow({
    manual_review_required: true,
    manual_reason_count: 1,
    budget_status: "manual_review_required",
    outside_budget_wishes: null,
  }));
  assertEquals(dto.pricingState, "personal_review_required");
  assertEquals("indicativeStartingPrice" in dto, false);
});

Deno.test("customer v1 and missing snapshots never expose an amount", () => {
  for (
    const row of [
      customerRow({ snapshot_contract_version: null }),
      customerRow({ snapshot_present: false, snapshot_contract_version: null }),
    ]
  ) {
    const dto = mapCustomerPricingReadRow(row);
    assertEquals(dto.pricingState, "pricing_result_unavailable");
    assertEquals("indicativeStartingPrice" in dto, false);
  }
});

Deno.test("customer tri-state mapping preserves true false and null semantics", () => {
  const outside = mapCustomerPricingReadRow(customerRow({
    budget_status: "known_minimum_exceeds_category_upper_bound",
    outside_budget_wishes: true,
  }));
  const noConflict = mapCustomerPricingReadRow(customerRow());
  const indeterminate = mapCustomerPricingReadRow(customerRow({
    budget_status: "unbounded_category_indeterminate",
    outside_budget_wishes: null,
  }));
  assertEquals(outside.budgetIndicator, "known_minimum_exceeds_selected_budget");
  assertEquals(noConflict.budgetIndicator, "no_known_minimum_conflict_detected");
  assertEquals(indeterminate.budgetIndicator, "not_reliably_comparable");
});

Deno.test("customer legacy missing and ambiguous provenance stays non-comparable", () => {
  for (const evidence_provenance of ["legacy_label", "missing", "ambiguous"]) {
    const dto = mapCustomerPricingReadRow(customerRow({
      evidence_provenance,
      budget_status: evidence_provenance === "legacy_label"
        ? "legacy_category_not_safely_comparable"
        : "manual_review_required",
      outside_budget_wishes: null,
    }));
    assertEquals(dto.budgetIndicator, "not_reliably_comparable");
    assertEquals(dto.indicativeStartingPrice?.amountMinor, 220_000);
  }
});

Deno.test("customer denylist excludes snapshot internals and unknown future fields", () => {
  const keys = new Set(allKeys(mapCustomerPricingReadRow(customerRow())));
  for (
    const forbidden of [
      "normalizedEvidence",
      "normalizedScope",
      "rawEvidence",
      "appliedRules",
      "manualReasons",
      "evidenceProvenance",
      "configVersion",
      "configHash",
      "snapshotContractVersion",
      "futureInternalSecret",
      "pricingSnapshot",
      "serviceRole",
    ]
  ) assert(!keys.has(forbidden), `customer DTO leaked ${forbidden}`);
});

Deno.test("admin v2 preserves approved operational and audit fields", () => {
  const dto = mapAdminPricingReadRow(adminRow());
  assertEquals(dto.availability, "available");
  assertEquals(dto.calculation?.knownMinimumMinor, 220_000);
  assertEquals(dto.calculation?.appliedRules[0].ruleId, "starter_floor");
  assertEquals(dto.packageAdvice?.status, "consider_professional");
  assertEquals(dto.budget?.outsideBudgetWishes, false);
  assertEquals(dto.budget?.evidenceProvenance, "budget_guard_v1");
  assertEquals(dto.normalizedScope?.standardPages, ["home"]);
  assertEquals(dto.audit?.pricingConfigHash, "a".repeat(64));
});

Deno.test("admin manual reasons and exact provenance remain available", () => {
  const dto = mapAdminPricingReadRow(adminRow({
    calculation: calculation(true),
    budget_evaluation: budgetEvaluation("ambiguous", null),
  }));
  assertEquals(dto.calculation?.manualReviewRequired, true);
  assertEquals(dto.calculation?.manualReasons[0].code, "shop_manual");
  assertEquals(dto.budget?.outsideBudgetWishes, null);
  assertEquals(dto.budget?.evidenceProvenance, "ambiguous");
});

Deno.test("admin v1 is limited and does not invent provenance", () => {
  const dto = mapAdminPricingReadRow(adminRow({ snapshot_contract_version: null }));
  assertEquals(dto.availability, "historical_limited");
  assertEquals(dto.calculation?.knownMinimumMinor, 220_000);
  assertEquals("budget" in dto, false);
});

Deno.test("admin allowlist excludes secrets and unknown future snapshot fields", () => {
  const keys = new Set(allKeys(mapAdminPricingReadRow(adminRow())));
  for (
    const forbidden of [
      "futureInternalSecret",
      "pricingSnapshot",
      "serviceRole",
      "accessTokenHash",
      "adminAccessTokenHash",
      "snapshotContractVersion",
    ]
  ) assert(!keys.has(forbidden), `admin DTO leaked ${forbidden}`);
});
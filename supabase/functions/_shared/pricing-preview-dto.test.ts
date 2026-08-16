import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  calculateBudgetGuard,
  evaluateBudget,
  resolveBudgetEvidence,
  type BudgetGuardResult,
} from "./pricing-engine.ts";
import { PRICING_CONFIG, type BudgetCategoryCode } from "./pricing-config.ts";
import { buildCustomerPricingPreview } from "./pricing-preview-dto.ts";

const budgetEvidence = (categoryCode: BudgetCategoryCode) => resolveBudgetEvidence(
  PRICING_CONFIG.budgetEvaluation.categories[categoryCode].originalLabel,
  PRICING_CONFIG.budgetEvaluation.schemeId,
  categoryCode,
);

const boundedBudget = () => budgetEvidence("3500_to_6000_inclusive");

function preview(
  input: Record<string, unknown>,
  revision = 1,
  categoryCode: BudgetCategoryCode = "3500_to_6000_inclusive",
) {
  const pricing = calculateBudgetGuard(input);
  return buildCustomerPricingPreview(
    revision,
    pricing,
    evaluateBudget(pricing.calculation, budgetEvidence(categoryCode)),
  );
}

function assertBudgetResult(
  result: ReturnType<typeof preview>,
  expected: {
    categoryCode: BudgetCategoryCode | null;
    comparisonStatus: string;
    knownMinimumExceedsBudget?: boolean;
    knownMinimumMinor?: number;
    containsFromPricing: boolean;
  },
) {
  assertEquals(result.budget.selectedBudgetCategoryCode, expected.categoryCode);
  assertEquals(result.budget.comparisonStatus, expected.comparisonStatus);
  assertEquals(result.budget.knownMinimumExceedsBudget, expected.knownMinimumExceedsBudget);
  assertEquals(result.summary.knownMinimumMinor, expected.knownMinimumMinor);
  assertEquals(result.summary.containsFromPricing, expected.containsFromPricing);
}

Deno.test("preview maps included, fixed and from items without starter as an extra", () => {
  const result = preview({
    requested_pages: ["home", "about", "services", "portfolio", "team", "pricing", "contact", "quote_request"],
    requested_features: ["quote_form"],
    quote_form_details: { structure_scope: "basic_single_section" },
    primary_language: "nl",
    additional_languages: ["fr"],
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      extensive_seo: false,
      language_specific_integrations: false,
      complex_scope: false,
    },
  }, 7);

  assertEquals(result.scopeRevision, 7);
  assertEquals(result.nonBinding, true);
  assertEquals(result.pricingConfigVersion, "2026-08-16-v3");
  assertEquals(result.items.some((item) => item.presentationKey === "EXTRA_STANDARD_PAGE"), true);
  assertEquals(result.items.some((item) => item.presentationKey === "SIMPLE_QUOTE_FORM"), true);
  assertEquals(result.items.some((item) => item.presentationKey === "EXTRA_LANGUAGE"), true);
  assertEquals(result.items.some((item) => item.labelKey.includes("starter_floor")), false);
  assertEquals(result.items.find((item) => item.presentationKey === "SIMPLE_QUOTE_FORM")?.amountMinor, 25_000);
});

Deno.test("included scope has no supplement and duplicate evidence is charged once", () => {
  const result = preview({
    requested_pages: ["home", "contact", "quote_request"],
    requested_features: ["contact_form", "quote_form", "quote_form"],
    website_goals: ["quote_requests", "contact_requests"],
    quote_form_details: { structure_scope: "basic_single_section" },
    content_status: "complete",
    image_status: "sufficient",
    seo_priority: "basic",
  });
  assertEquals(result.summary.knownMinimumMinor, 205_000);
  assertEquals(result.items.filter((item) => item.presentationKey === "SIMPLE_QUOTE_FORM").length, 1);
  assertEquals(result.items.filter((item) => item.state === "INCLUDED").every((item) => !("amountMinor" in item)), true);
});

Deno.test("manual preview keeps review and compatible budget dimensions independent", () => {
  const result = preview({
    requested_pages: ["home", "about", "services", "portfolio", "team", "pricing"],
    requested_features: ["customer_login"],
  });
  assertBudgetResult(result, {
    categoryCode: "3500_to_6000_inclusive",
    comparisonStatus: "WITHIN_KNOWN_BUDGET",
    knownMinimumExceedsBudget: false,
    knownMinimumMinor: 202_500,
    containsFromPricing: true,
  });
  assertEquals(result.summary.manualReviewRequired, true);
  assertEquals(result.summary.knownMinimumMinor, 202_500);
  assertEquals(result.items.some((item) => item.state === "MANUAL_REVIEW"), true);
  assertEquals(result.items.some((item) => item.state === "FROM_EXTRA"), false);
  assertEquals(
    result.items.filter((item) => item.state === "FIXED_EXTRA").some((item) => item.amountMinor === 22_500),
    true,
  );
  assertEquals(JSON.stringify(result).includes("manualReasons"), false);
});

Deno.test("preview contract v3 marks requested manual scope essential beside known minimum", () => {
  const pricing = calculateBudgetGuard({
    selected_package_definition_id: "starter_v1",
    requested_features: ["customer_login"],
  });
  const result = buildCustomerPricingPreview(
    1,
    pricing,
    evaluateBudget(pricing.calculation, boundedBudget()),
    3,
  );

  assertEquals(result.previewContractVersion, 3);
  assertEquals(result.summary.knownMinimumMinor, 180_000);
  assertEquals(result.summary.manualReviewRequired, true);
  assertEquals(result.summary.manualScope, "ESSENTIAL");
});

Deno.test("preview preserves fixed and multiple from amounts beside manual review", () => {
  const result = preview({
    requested_pages: ["home", "quote_request"],
    requested_features: ["quote_form", "customer_login"],
    quote_form_details: { structure_scope: "basic_single_section" },
    primary_language: "nl",
    additional_languages: ["fr", "en"],
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      extensive_seo: false,
      language_specific_integrations: false,
      complex_scope: false,
    },
  });

  assertEquals(result.summary.knownMinimumMinor, 315_000);
  assertEquals(result.summary.containsFromPricing, true);
  assertEquals(result.summary.manualReviewRequired, true);
  assertEquals(result.items.find((item) => item.presentationKey === "SIMPLE_QUOTE_FORM")?.amountMinor, 25_000);
  assertEquals(result.items.find((item) => item.presentationKey === "EXTRA_LANGUAGE")?.amountMinor, 110_000);
  assertEquals(result.items.find((item) => item.presentationKey === "EXTRA_LANGUAGE")?.quantity, undefined);
  assertEquals(result.items.find((item) => item.state === "MANUAL_REVIEW")?.amountMinor, undefined);
});

Deno.test("preview consolidates multilingual SEO quantities to their total minimum", () => {
  const result = preview({
    selected_package_definition_id: "professional_v2",
    primary_language: "nl",
    additional_languages: ["fr", "en"],
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      translation_required: false,
      seo_per_language: true,
      advanced_seo_research: true,
      language_specific_integrations: false,
      complex_scope: false,
    },
    seo_details: {
      scope: "included",
      extra_language_seo: true,
      advanced_language_seo: true,
    },
  });

  assertEquals(result.summary.knownMinimumMinor, 630_000);
  const seo = result.items.find((item) => item.presentationKey === "EXTENSIVE_SEO");
  assertEquals(seo?.amountMinor, 170_000);
  assertEquals(seo?.quantity, undefined);
});

Deno.test("substantial copywriting supersedes generic content support in customer presentation", () => {
  const pricing = calculateBudgetGuard({
    content_status: "needs_help",
    content_media_details: {
      copywriting_scope: "substantial",
      image_work_scope: "unknown",
      paid_stock_handling: false,
    },
  });
  assertEquals(pricing.calculation.appliedRules.some((rule) => rule.ruleId === "content_support"), false);
  assertEquals(pricing.calculation.appliedRules.some((rule) => rule.ruleId === "substantial_copywriting"), false);
  assertEquals(pricing.calculation.appliedRules.some((rule) => rule.ruleId === "substantial_rewrite"), true);

  const result = buildCustomerPricingPreview(
    1,
    pricing,
    evaluateBudget(pricing.calculation, boundedBudget()),
  );
  const copywritingItems = result.items.filter((item) => item.presentationKey === "COPYWRITING");
  assertEquals(copywritingItems.length, 1);
  assertEquals(copywritingItems[0].state, "FROM_EXTRA");
  assertEquals("amountMinor" in copywritingItems[0], true);
  assertEquals(result.summary.manualReviewRequired, false);
});

Deno.test("uncertain normal and feature scopes have explicit customer presentation keys", () => {
  const result = preview({
    requested_features: ["unsure"],
    image_support: ["unsure"],
  });

  assertEquals(
    result.items.find((item) => item.presentationKey === "INDETERMINATE_SCOPE")?.state,
    "MANUAL_REVIEW",
  );
  assertEquals(
    result.items.find((item) => item.presentationKey === "UNKNOWN_FEATURE_SCOPE")?.state,
    "MANUAL_REVIEW",
  );
});

Deno.test("manual preview retains a proven package-floor budget mismatch", () => {
  const result = preview({
    selected_package_definition_id: "starter_v1",
    requested_pages: ["home"],
    requested_features: ["customer_login"],
  }, 1, "below_1800");

  assertBudgetResult(result, {
    categoryCode: "below_1800",
    comparisonStatus: "KNOWN_MINIMUM_ABOVE_BUDGET",
    knownMinimumExceedsBudget: true,
    knownMinimumMinor: 180_000,
    containsFromPricing: true,
  });
  assertEquals(result.summary.manualReviewRequired, true);
  assertEquals(result.items.some((item) => item.state === "MANUAL_REVIEW"), true);
  assertEquals(result.items.every((item) => !("amountMinor" in item)), true);
});

Deno.test("legacy preview contract keeps manual mismatch usable without combined fields", () => {
  const pricing = calculateBudgetGuard({
    selected_package_definition_id: "professional_v2",
    requested_pages: ["home"],
    requested_features: ["customer_login"],
  });
  const result = buildCustomerPricingPreview(
    9,
    pricing,
    evaluateBudget(pricing.calculation, budgetEvidence("below_1800")),
    1,
  );

  assertEquals(result.previewContractVersion, 1);
  assertEquals(result.budget.comparisonStatus, "MANUAL_REVIEW");
  assertEquals("knownMinimumExceedsBudget" in result.budget, false);
  assertEquals(result.summary.manualReviewRequired, true);
  assertEquals("knownMinimumMinor" in result.summary, false);
  assertEquals(result.items.every((item) => !("amountMinor" in item)), true);
});

Deno.test("current preview contract preserves combined manual mismatch semantics", () => {
  const pricing = calculateBudgetGuard({
    selected_package_definition_id: "professional_v2",
    requested_pages: ["home"],
    requested_features: ["customer_login"],
  });
  const result = buildCustomerPricingPreview(
    9,
    pricing,
    evaluateBudget(pricing.calculation, budgetEvidence("below_1800")),
    2,
  );

  assertEquals(result.previewContractVersion, 2);
  assertEquals(result.budget.comparisonStatus, "KNOWN_MINIMUM_ABOVE_BUDGET");
  assertEquals(result.budget.knownMinimumExceedsBudget, true);
  assertEquals(result.summary.manualReviewRequired, true);
  assertEquals(result.summary.knownMinimumMinor, 350_000);
  assertEquals(result.items.every((item) => !("amountMinor" in item)), true);
});

Deno.test("D43 D53 Phase D preview separates recurring services and presents catalog selections", () => {
  const pricing = calculateBudgetGuard({
    selected_package_definition_id: "starter_v1",
    requested_pages: ["portfolio"],
    page_scope_details: { portfolio: "dynamic", search: "advanced" },
    content_media_details: { image_work_scope: "stock", branding_tier: "extended" },
    hosting_maintenance_details: { maintenance_plan: "care_plus" },
  });
  const result = buildCustomerPricingPreview(
    12,
    pricing,
    evaluateBudget(pricing.calculation, boundedBudget()),
  );

  assertEquals(result.summary.knownMinimumMinor, 450_000);
  assertEquals(result.recurringServices, [{
    presentationKey: "CARE_PLUS",
    amountMinor: 9_900,
    unit: "MONTH",
  }]);
  assertEquals(result.items.map((item) => item.presentationKey), [
    "DYNAMIC_PORTFOLIO",
    "SEARCH",
    "STOCK_SELECTION",
    "EXTENDED_BRANDING",
  ]);
});

Deno.test("manual preview keeps unreliable budget evidence indeterminate", () => {
  const pricing = calculateBudgetGuard({
    selected_package_definition_id: "starter_v1",
    requested_pages: ["home"],
    requested_features: ["customer_login"],
  });
  const evidence = resolveBudgetEvidence(null, null, null);
  const result = buildCustomerPricingPreview(
    1,
    pricing,
    evaluateBudget(pricing.calculation, evidence),
  );

  assertEquals(result.budget.comparisonStatus, "INDETERMINATE");
  assertEquals(result.summary.manualReviewRequired, true);
  assertEquals(result.summary.knownMinimumMinor, 180_000);
  assertEquals(result.items.every((item) => !("amountMinor" in item)), true);
});

Deno.test("preview compares package known minimum safely for approved budget matrix A-E", () => {
  const cases = [
    ["starter_v1", "below_1800", 180_000, "KNOWN_MINIMUM_ABOVE_BUDGET", true],
    ["professional_v2", "below_1800", 350_000, "KNOWN_MINIMUM_ABOVE_BUDGET", true],
    ["professional_v2", "1800_to_below_3500", 350_000, "KNOWN_MINIMUM_ABOVE_BUDGET", true],
    ["professional_v2", "3500_to_6000_inclusive", 350_000, "WITHIN_KNOWN_BUDGET", false],
    ["professional_v2", "above_6000", 350_000, "WITHIN_KNOWN_BUDGET", false],
  ] as const;
  for (const [packageId, categoryCode, knownMinimumMinor, comparisonStatus, exceeds] of cases) {
    const result = preview({
      selected_package_definition_id: packageId,
      requested_pages: ["home"],
    }, 1, categoryCode);
    assertBudgetResult(result, {
      categoryCode,
      comparisonStatus,
      knownMinimumExceedsBudget: exceeds,
      knownMinimumMinor,
      containsFromPricing: true,
    });
  }
});

Deno.test("from pricing remains indeterminate above a bounded category lower bound", () => {
  const base = calculateBudgetGuard({
    selected_package_definition_id: "professional_v2",
    requested_pages: ["home"],
  });
  const pricing: BudgetGuardResult = {
    ...base,
    calculation: { ...base.calculation, knownMinimumMinor: 400_000 },
  };
  const result = buildCustomerPricingPreview(
    1,
    pricing,
    evaluateBudget(pricing.calculation, boundedBudget()),
  );
  assertBudgetResult(result, {
    categoryCode: "3500_to_6000_inclusive",
    comparisonStatus: "INDETERMINATE",
    knownMinimumMinor: 400_000,
    containsFromPricing: true,
  });
});

Deno.test("open category remains indeterminate above its lower bound", () => {
  const base = calculateBudgetGuard({
    selected_package_definition_id: "professional_v2",
    requested_pages: ["home"],
  });
  const pricing: BudgetGuardResult = {
    ...base,
    calculation: { ...base.calculation, knownMinimumMinor: 700_000 },
  };
  const evidence = budgetEvidence("above_6000");
  const result = buildCustomerPricingPreview(
    1,
    pricing,
    evaluateBudget(pricing.calculation, evidence),
  );
  assertBudgetResult(result, {
    categoryCode: "above_6000",
    comparisonStatus: "INDETERMINATE",
    knownMinimumMinor: 700_000,
    containsFromPricing: true,
  });
});

Deno.test("legacy and missing budget evidence remain indeterminate", () => {
  const pricing = calculateBudgetGuard({ requested_pages: ["home"] });
  for (const evidence of [
    resolveBudgetEvidence("EUR 3.000 - EUR 6.000", null, null),
    resolveBudgetEvidence(null, null, null),
  ]) {
    const result = buildCustomerPricingPreview(
      1,
      pricing,
      evaluateBudget(pricing.calculation, evidence),
    );
    assertBudgetResult(result, {
      categoryCode: null,
      comparisonStatus: "INDETERMINATE",
      knownMinimumMinor: 180_000,
      containsFromPricing: true,
    });
  }
});

Deno.test("preview supports within-known-budget when a coherent calculation has no from or manual scope", () => {
  const base = calculateBudgetGuard({ requested_pages: ["home"] });
  const pricing: BudgetGuardResult = {
    ...base,
    calculation: {
      ...base.calculation,
      knownMinimumMinor: 400_000,
      containsFromPricing: false,
    },
  };
  const evaluation = evaluateBudget(pricing.calculation, boundedBudget());
  assertBudgetResult(buildCustomerPricingPreview(1, pricing, evaluation), {
    categoryCode: "3500_to_6000_inclusive",
    comparisonStatus: "WITHIN_KNOWN_BUDGET",
    knownMinimumExceedsBudget: false,
    knownMinimumMinor: 400_000,
    containsFromPricing: false,
  });
});

Deno.test("preview package advice remains advisory and has no selected package or raw evidence", () => {
  const result = preview({ requested_pages: ["home", "about", "services", "portfolio", "team", "pricing"] });
  assertEquals(result.packageAdvice.state, "CONSIDER_PROFESSIONAL");
  const serialized = JSON.stringify(result);
  for (const forbidden of ["selectedPackage", "normalizedScope", "appliedRules", "pricingConfigHash", "proof", "integrity"]) {
    assertEquals(serialized.includes(forbidden), false);
  }
});

Deno.test("package preview v2 exposes only server-derived customer-safe package state", () => {
  const starter = preview({ selected_package_definition_id: "starter_v1", requested_pages: ["home"] }, 7);
  const professional = preview({ selected_package_definition_id: "professional_v2", requested_pages: ["home"] }, 7);
  if (starter.previewVersion !== 2 || professional.previewVersion !== 2) throw new Error("expected preview v2");

  assertEquals(starter.selectedPackage.selectedPackageDefinitionId, "starter_v1");
  assertEquals(starter.selectedPackage.label, "Starter");
  assertEquals(starter.selectedPackage.floorMinor, 180_000);
  assertEquals(starter.selectedPackage.standardPageCount, 1);
  assertEquals(starter.selectedPackage.standardPageLimit, 5);
  assertEquals(starter.selectedPackage.includedCorrectionRounds, 1);
  assertEquals(professional.selectedPackage.selectedPackageDefinitionId, "professional_v2");
  assertEquals(professional.selectedPackage.label, "Professional");
  assertEquals(professional.selectedPackage.floorMinor, 350_000);
  assertEquals(professional.selectedPackage.standardPageCount, 1);
  assertEquals(professional.selectedPackage.standardPageLimit, 10);
  assertEquals(professional.selectedPackage.includedCorrectionRounds, 2);
  assertEquals(
    professional.selectedPackage.includedPresentation.length,
    starter.selectedPackage.includedPresentation.length + 1,
  );
  assertEquals(
    professional.selectedPackage.includedPresentation.some((item) =>
      item.entitlement === "blog_news"
    ),
    true,
  );
  assertEquals(starter.selectedPackage.includedPresentation.length, 15);
  assertEquals(starter.selectedPackage.includedPresentation.find((item) =>
    item.entitlement === "technical_seo_base"
  ), {
    entitlement: "technical_seo_base",
    label: "Technische SEO-basis",
    group: "PACKAGE_QUALITY",
    scope: "BASE",
  });
  assertEquals(starter.items.some((item) => item.labelKey.includes("floor")), false);
  assertEquals("entitlements" in starter.selectedPackage, false);
});

Deno.test("package preview rejects entitlements outside the closed presentation contract", () => {
  const pricing = calculateBudgetGuard({ selected_package_definition_id: "starter_v1", requested_pages: ["home"] });
  if (!pricing.selectedPackageDefinition) throw new Error("expected selected package");
  const injected = {
    ...pricing,
    selectedPackageDefinition: {
      ...pricing.selectedPackageDefinition,
      entitlements: [...pricing.selectedPackageDefinition.entitlements, "unexpected_entitlement"],
    },
  } as BudgetGuardResult;
  assertThrows(
    () => buildCustomerPricingPreview(1, injected, evaluateBudget(injected.calculation, boundedBudget())),
    TypeError,
    "UNKNOWN_PACKAGE_ENTITLEMENT",
  );
});

Deno.test("preview fails closed for invalid revision and unknown rule", () => {
  const pricing = calculateBudgetGuard({ requested_pages: ["home"] });
  const evaluation = evaluateBudget(pricing.calculation, boundedBudget());
  assertThrows(() => buildCustomerPricingPreview(-1, pricing, evaluation), TypeError, "INVALID_SCOPE_REVISION");
  const injected: BudgetGuardResult = {
    ...pricing,
    calculation: {
      ...pricing.calculation,
      appliedRules: [...pricing.calculation.appliedRules, {
        ruleId: "injected_rule",
        mode: "manual",
        quantity: 1,
        knownMinimumContributionMinor: 0,
      }],
      manualReviewRequired: true,
      manualReasons: ["injected_rule"],
    },
  };
  assertThrows(
    () => buildCustomerPricingPreview(1, injected, evaluateBudget(injected.calculation, boundedBudget())),
    TypeError,
    "UNKNOWN_PRICING_RULE",
  );
});

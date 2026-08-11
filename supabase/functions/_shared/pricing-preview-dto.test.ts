import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  calculateBudgetGuard,
  evaluateBudget,
  resolveBudgetEvidence,
  type BudgetGuardResult,
} from "./pricing-engine.ts";
import { buildCustomerPricingPreview } from "./pricing-preview-dto.ts";

const boundedBudget = () => resolveBudgetEvidence(
  "EUR 3.200 t/m EUR 6.000",
  "budget_guard_v1",
  "3200_to_6000_inclusive",
);

function preview(input: Record<string, unknown>, revision = 1) {
  const pricing = calculateBudgetGuard(input);
  return buildCustomerPricingPreview(
    revision,
    pricing,
    evaluateBudget(pricing.calculation, boundedBudget()),
  );
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
  assertEquals(result.pricingConfigVersion, "2.0.0");
  assertEquals(result.items.some((item) => item.presentationKey === "EXTRA_STANDARD_PAGE"), true);
  assertEquals(result.items.some((item) => item.presentationKey === "SIMPLE_QUOTE_FORM"), true);
  assertEquals(result.items.some((item) => item.presentationKey === "EXTRA_LANGUAGE"), true);
  assertEquals(result.items.some((item) => item.labelKey.includes("starter_floor")), false);
  assertEquals(result.items.find((item) => item.presentationKey === "SIMPLE_QUOTE_FORM")?.amountMinor, 20_000);
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
  assertEquals(result.summary.knownMinimumMinor, 200_000);
  assertEquals(result.items.filter((item) => item.presentationKey === "SIMPLE_QUOTE_FORM").length, 1);
  assertEquals(result.items.filter((item) => item.state === "INCLUDED").every((item) => !("amountMinor" in item)), true);
});

Deno.test("manual preview suppresses every monetary amount while retaining presentation states", () => {
  const result = preview({
    requested_pages: ["home", "about", "services", "portfolio", "team", "pricing"],
    requested_features: ["customer_login"],
  });
  assertEquals(result.budget.comparisonStatus, "MANUAL_REVIEW");
  assertEquals(result.summary.manualReviewRequired, true);
  assertEquals("knownMinimumMinor" in result.summary, false);
  assertEquals(result.items.some((item) => item.state === "MANUAL_REVIEW"), true);
  assertEquals(result.items.some((item) => item.state === "FROM_EXTRA"), true);
  assertEquals(result.items.every((item) => !("amountMinor" in item)), true);
  assertEquals(JSON.stringify(result).includes("manualReasons"), false);
});

Deno.test("preview budget precedence handles legacy, missing, above, open and from states", () => {
  const pricing = calculateBudgetGuard({ requested_pages: ["home"] });
  const cases = [
    [resolveBudgetEvidence("EUR 3.000 - EUR 6.000", null, null), "INDETERMINATE"],
    [resolveBudgetEvidence(null, null, null), "INDETERMINATE"],
    [resolveBudgetEvidence("Minder dan EUR 1.800", "budget_guard_v1", "below_1800"), "KNOWN_MINIMUM_ABOVE_BUDGET"],
    [resolveBudgetEvidence("Meer dan EUR 6.000", "budget_guard_v1", "above_6000"), "INDETERMINATE"],
    [boundedBudget(), "INDETERMINATE"],
  ] as const;
  for (const [evidence, expected] of cases) {
    const result = buildCustomerPricingPreview(1, pricing, evaluateBudget(pricing.calculation, evidence));
    assertEquals(result.budget.comparisonStatus, expected);
  }
});

Deno.test("preview supports within-known-budget when a coherent calculation has no from or manual scope", () => {
  const base = calculateBudgetGuard({ requested_pages: ["home"] });
  const pricing: BudgetGuardResult = {
    ...base,
    calculation: { ...base.calculation, containsFromPricing: false },
  };
  const evaluation = evaluateBudget(pricing.calculation, boundedBudget());
  assertEquals(buildCustomerPricingPreview(1, pricing, evaluation).budget, {
    selectedBudgetCategoryCode: "3200_to_6000_inclusive",
    comparisonStatus: "WITHIN_KNOWN_BUDGET",
    knownMinimumExceedsBudget: false,
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
  const professional = preview({ selected_package_definition_id: "professional_v1", requested_pages: ["home"] }, 7);
  if (starter.previewVersion !== 2 || professional.previewVersion !== 2) throw new Error("expected preview v2");

  assertEquals(starter.selectedPackage.selectedPackageDefinitionId, "starter_v1");
  assertEquals(starter.selectedPackage.label, "Starter");
  assertEquals(starter.selectedPackage.floorMinor, 180_000);
  assertEquals(starter.selectedPackage.standardPageCount, 1);
  assertEquals(starter.selectedPackage.standardPageLimit, 5);
  assertEquals(starter.selectedPackage.includedCorrectionRounds, 1);
  assertEquals(professional.selectedPackage.selectedPackageDefinitionId, "professional_v1");
  assertEquals(professional.selectedPackage.label, "Professional");
  assertEquals(professional.selectedPackage.floorMinor, 320_000);
  assertEquals(professional.selectedPackage.standardPageCount, 1);
  assertEquals(professional.selectedPackage.standardPageLimit, 12);
  assertEquals(professional.selectedPackage.includedCorrectionRounds, 2);
  assertEquals(professional.selectedPackage.includedPresentation, starter.selectedPackage.includedPresentation);
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

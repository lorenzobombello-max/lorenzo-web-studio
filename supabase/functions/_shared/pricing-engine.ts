import {
  type BudgetCategoryCode,
  computePricingConfigHash,
  type PriceMode,
  PRICING_CONFIG,
  type PricingRuleId,
} from "./pricing-config.ts";
import {
  type NormalizedPricingScope,
  normalizePricingScope,
  type RawPricingScope,
} from "./pricing-normalization.ts";

export type PackageAdviceStatus =
  | "none"
  | "consider_professional"
  | "manual_scope_review";

interface AppliedRuleBase {
  ruleId: string;
  mode: PriceMode;
  quantity: number;
  knownMinimumContributionMinor: number;
}

export type AppliedPricingRule = AppliedRuleBase & { amountMinor?: number };

export interface BudgetGuardResult {
  pricingConfigVersion: string;
  normalizedScope: NormalizedPricingScope;
  calculation: {
    basis: "starter_floor";
    currency: "EUR";
    vatBasis: "exclusive";
    knownMinimumMinor: number;
    containsFromPricing: boolean;
    manualReviewRequired: boolean;
    manualReasons: string[];
    appliedRules: AppliedPricingRule[];
  };
  packageAdvice: {
    status: PackageAdviceStatus;
    reasons: string[];
    advisoryOnly: true;
    selectedPackage: null;
  };
  nonBinding: true;
}

export type BudgetEvidence =
  | {
    evidenceProvenance: "budget_guard_v1";
    categoryScheme: "budget_guard_v1";
    categoryCode: BudgetCategoryCode;
    originalLabel: string;
  }
  | {
    evidenceProvenance: "legacy_label";
    categoryScheme: null;
    categoryCode: null;
    originalLabel: string;
  }
  | {
    evidenceProvenance: "missing";
    categoryScheme: null;
    categoryCode: null;
    originalLabel: null;
  }
  | {
    evidenceProvenance: "ambiguous";
    categoryScheme: null;
    categoryCode: null;
    originalLabel: string;
  };

export type BudgetEvaluationStatus =
  | "below_starter_starting_price"
  | "known_minimum_exceeds_category_upper_bound"
  | "possibly_compatible_with_category"
  | "unbounded_category_indeterminate"
  | "legacy_category_not_safely_comparable"
  | "manual_review_required";

export type BudgetEvaluationV2 = BudgetEvidence & {
  contractVersion: 2;
  status: BudgetEvaluationStatus;
  outsideBudgetWishes: boolean | null;
};

export interface PricingSnapshotV2 {
  snapshotContractVersion: 2;
  pricingConfigVersion: string;
  pricingConfigHash: string;
  normalizedScope: NormalizedPricingScope;
  calculation: BudgetGuardResult["calculation"];
  packageAdvice: BudgetGuardResult["packageAdvice"];
  budgetEvaluation: BudgetEvaluationV2;
}

function configuredRule(
  ruleId: PricingRuleId,
  quantity = 1,
): AppliedPricingRule {
  const rule = PRICING_CONFIG.rules[ruleId];
  if ("amountMinor" in rule) {
    return {
      ruleId,
      mode: rule.mode,
      amountMinor: rule.amountMinor,
      quantity,
      knownMinimumContributionMinor: rule.amountMinor * quantity,
    };
  }
  return {
    ruleId,
    mode: rule.mode,
    quantity,
    knownMinimumContributionMinor: 0,
  };
}

function packageAdvice(
  standardPageCount: number,
): BudgetGuardResult["packageAdvice"] {
  if (
    standardPageCount > PRICING_CONFIG.packages.professional.standardPageLimit
  ) {
    return {
      status: "manual_scope_review",
      reasons: ["standard_page_count_above_professional_scope"],
      advisoryOnly: true,
      selectedPackage: null,
    };
  }
  if (standardPageCount > PRICING_CONFIG.packages.starter.standardPageLimit) {
    return {
      status: "consider_professional",
      reasons: ["standard_page_count_above_starter_scope"],
      advisoryOnly: true,
      selectedPackage: null,
    };
  }
  return {
    status: "none",
    reasons: [],
    advisoryOnly: true,
    selectedPackage: null,
  };
}

const MANUAL_COMPONENT_RULES: Record<string, PricingRuleId> = {
  customer_login: "customer_login",
  external_integration: "external_integration",
  secured_downloads: "secured_downloads",
  professional_photography: "professional_photography",
  unresolved_search: "unresolved_search",
  rush_review: "rush_review",
  substantial_copywriting: "substantial_copywriting",
  exceptional_image_work: "exceptional_image_work",
  paid_stock_handling: "paid_stock_handling",
  complex_gallery_scope: "complex_gallery_scope",
  complex_reviews_scope: "complex_reviews_scope",
  complex_blog_scope: "complex_blog_scope",
  complex_jobs_scope: "complex_jobs_scope",
  other_page_scope: "other_page_scope",
  unknown_page_scope: "unknown_page_scope",
  newsletter_manual: "newsletter_manual",
  extensive_seo: "extensive_seo",
};

export function calculateBudgetGuard(
  input: RawPricingScope,
): BudgetGuardResult {
  const normalizedScope = normalizePricingScope(input);
  const appliedRules: AppliedPricingRule[] = [{
    ruleId: "starter_floor",
    mode: PRICING_CONFIG.packages.starter.priceMode,
    amountMinor: PRICING_CONFIG.packages.starter.startingPriceMinor,
    quantity: 1,
    knownMinimumContributionMinor:
      PRICING_CONFIG.packages.starter.startingPriceMinor,
  }];

  const extraPageCount = Math.max(
    0,
    normalizedScope.standardPageCount -
      PRICING_CONFIG.packages.starter.standardPageLimit,
  );
  if (extraPageCount) {
    appliedRules.push(configuredRule("extra_standard_page", extraPageCount));
  }

  for (const module of normalizedScope.modules) {
    if (module.id === "shop") appliedRules.push(configuredRule("shop_manual"));
    else if (module.id === "booking") {
      appliedRules.push(configuredRule("booking_manual"));
    } else if (module.id === "forms") {
      if (module.classification === "contact") {
        appliedRules.push(configuredRule("contact_form"));
      } else if (module.classification === "simple") {
        appliedRules.push(configuredRule("simple_quote_form"));
      } else if (module.classification === "extended") {
        appliedRules.push(configuredRule("extended_quote_form"));
      } else appliedRules.push(configuredRule("complex_form_manual"));
    } else if (module.id === "multilingual") {
      if (module.classification === "normal") {
        appliedRules.push(
          configuredRule(
            "extra_language",
            normalizedScope.additionalLanguages.length,
          ),
        );
      } else appliedRules.push(configuredRule("multilingual_manual"));
    } else if (
      module.id === "content_media" && module.classification === "included"
    ) {
      appliedRules.push(configuredRule("content_media_included"));
    } else if (module.id === "hosting_maintenance") {
      appliedRules.push(configuredRule("hosting_maintenance_manual"));
    } else if (module.id === "seo" && module.classification === "included") {
      appliedRules.push(configuredRule("seo_included"));
    }
  }

  const appliedManualComponents = new Set<string>();
  for (const component of normalizedScope.manualComponents) {
    const ruleId = MANUAL_COMPONENT_RULES[component];
    if (ruleId && !appliedManualComponents.has(ruleId)) {
      appliedRules.push(configuredRule(ruleId));
      appliedManualComponents.add(ruleId);
    }
  }

  const manualRules = appliedRules.filter((rule) => rule.mode === "manual");
  const knownMinimumMinor = appliedRules.reduce(
    (sum, rule) => sum + rule.knownMinimumContributionMinor,
    0,
  );
  const advice = packageAdvice(normalizedScope.standardPageCount);
  const manualReasons = [...new Set(manualRules.map((rule) => rule.ruleId))];
  if (advice.status === "manual_scope_review") {
    manualReasons.push(
      ...advice.reasons.filter((reason) => !manualReasons.includes(reason)),
    );
  }

  return {
    pricingConfigVersion: PRICING_CONFIG.version,
    normalizedScope,
    calculation: {
      basis: "starter_floor",
      currency: PRICING_CONFIG.currency,
      vatBasis: PRICING_CONFIG.vatBasis,
      knownMinimumMinor,
      containsFromPricing: appliedRules.some((rule) => rule.mode === "from"),
      manualReviewRequired: manualReasons.length > 0,
      manualReasons,
      appliedRules,
    },
    packageAdvice: advice,
    nonBinding: true,
  };
}

export function resolveBudgetEvidence(
  originalLabel: unknown,
  categoryScheme: unknown,
  categoryCode: unknown,
): BudgetEvidence {
  const label = typeof originalLabel === "string" && originalLabel.trim()
    ? originalLabel
    : null;
  const categories = PRICING_CONFIG.budgetEvaluation.categories;
  if (
    categoryScheme === PRICING_CONFIG.budgetEvaluation.schemeId &&
    typeof categoryCode === "string" &&
    categoryCode in categories
  ) {
    const code = categoryCode as BudgetCategoryCode;
    if (label === categories[code].originalLabel) {
      return {
        evidenceProvenance: "budget_guard_v1",
        categoryScheme: "budget_guard_v1",
        categoryCode: code,
        originalLabel: label,
      };
    }
  }
  if (
    categoryScheme == null && categoryCode == null && label !== null &&
    PRICING_CONFIG.budgetEvaluation.legacyLabels.includes(
      label as typeof PRICING_CONFIG.budgetEvaluation.legacyLabels[number],
    )
  ) {
    return {
      evidenceProvenance: "legacy_label",
      categoryScheme: null,
      categoryCode: null,
      originalLabel: label,
    };
  }
  if (label === null && categoryScheme == null && categoryCode == null) {
    return {
      evidenceProvenance: "missing",
      categoryScheme: null,
      categoryCode: null,
      originalLabel: null,
    };
  }
  return {
    evidenceProvenance: "ambiguous",
    categoryScheme: null,
    categoryCode: null,
    originalLabel: label ?? String(originalLabel),
  };
}

export function evaluateBudget(
  calculation: BudgetGuardResult["calculation"],
  evidence: BudgetEvidence,
): BudgetEvaluationV2 {
  const policy = PRICING_CONFIG.budgetEvaluation;
  const result = (
    status: BudgetEvaluationStatus,
    outsideBudgetWishes: boolean | null,
  ): BudgetEvaluationV2 => ({
    contractVersion: policy.contractVersion,
    ...evidence,
    status,
    outsideBudgetWishes,
  });

  if (
    calculation.manualReviewRequired ||
    evidence.evidenceProvenance === "missing" ||
    evidence.evidenceProvenance === "ambiguous"
  ) {
    return result(policy.statusMapping.manual, null);
  }
  if (evidence.evidenceProvenance === "legacy_label") {
    return result(policy.statusMapping.legacy, null);
  }
  if (evidence.categoryCode === "below_1800") {
    return result(policy.statusMapping.belowStarter, true);
  }

  const upperBound = policy.categories[evidence.categoryCode]
    .upperInclusiveMinor;
  if (upperBound === null) return result(policy.statusMapping.openUpper, null);
  if (calculation.knownMinimumMinor > upperBound) {
    return result(policy.statusMapping.exceedsBoundedUpper, true);
  }
  return result(policy.statusMapping.withinBoundedUpper, false);
}

export async function buildPricingSnapshotV2(
  input: RawPricingScope,
  budgetEvidence: BudgetEvidence,
): Promise<PricingSnapshotV2> {
  const pricing = calculateBudgetGuard(input);
  return {
    snapshotContractVersion: 2,
    pricingConfigVersion: pricing.pricingConfigVersion,
    pricingConfigHash: await computePricingConfigHash(),
    normalizedScope: pricing.normalizedScope,
    calculation: pricing.calculation,
    packageAdvice: pricing.packageAdvice,
    budgetEvaluation: evaluateBudget(pricing.calculation, budgetEvidence),
  };
}

export async function selectPricingSnapshotForSubmit(
  input: RawPricingScope,
  budgetEvidence: BudgetEvidence,
  existingSnapshot: Record<string, unknown> | null,
  buildSnapshot: (
    input: RawPricingScope,
    budgetEvidence: BudgetEvidence,
  ) => Promise<PricingSnapshotV2> = buildPricingSnapshotV2,
): Promise<PricingSnapshotV2 | Record<string, unknown>> {
  if (existingSnapshot) return existingSnapshot;
  return await buildSnapshot(input, budgetEvidence);
}

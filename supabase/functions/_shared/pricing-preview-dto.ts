import type {
  AppliedPricingRule,
  BudgetEvaluationV2,
  BudgetGuardResult,
} from "./pricing-engine.ts";
import {
  PRICING_CONFIG,
  type PackageEntitlementId,
} from "./pricing-config.ts";

export type PricingPreviewBudgetState =
  | "WITHIN_KNOWN_BUDGET"
  | "KNOWN_MINIMUM_ABOVE_BUDGET"
  | "INDETERMINATE"
  | "MANUAL_REVIEW";

export type PricingPreviewItemState =
  | "INCLUDED"
  | "FIXED_EXTRA"
  | "FROM_EXTRA"
  | "MANUAL_REVIEW";

export type PricingPreviewPresentationKey =
  | "EXTRA_STANDARD_PAGE"
  | "EXTRA_LANGUAGE"
  | "CONTACT_FORM"
  | "SIMPLE_QUOTE_FORM"
  | "EXTENDED_QUOTE_FORM"
  | "COMPLEX_FORM"
  | "SHOP"
  | "BOOKING"
  | "MULTILINGUAL_SCOPE"
  | "CONTENT_MEDIA"
  | "HOSTING_MAINTENANCE"
  | "SEO_BASE"
  | "EXTENSIVE_SEO"
  | "CUSTOMER_LOGIN"
  | "EXTERNAL_INTEGRATION"
  | "SECURED_DOWNLOADS"
  | "PROFESSIONAL_PHOTOGRAPHY"
  | "SEARCH"
  | "RUSH_SCOPE"
  | "COPYWRITING"
  | "IMAGE_WORK"
  | "PAID_STOCK"
  | "GALLERY_SCOPE"
  | "REVIEWS_SCOPE"
  | "BLOG_SCOPE"
  | "JOBS_SCOPE"
  | "OTHER_PAGE_SCOPE"
  | "UNKNOWN_PAGE_SCOPE"
  | "NEWSLETTER_SCOPE"
  | "PACKAGE_SCOPE";

export type PricingPreviewLabelKey = `pricing_preview.${Lowercase<PricingPreviewPresentationKey>}`;

export type PackageInclusionPresentation = {
  entitlement: PackageEntitlementId;
  label: string;
  group: "PACKAGE_QUALITY" | "WHEN_REQUESTED";
  scope: "FULL" | "BASE";
};

export interface CustomerPricingPreviewDTOv1 {
  previewVersion: 1;
  scopeRevision: number;
  pricingConfigVersion: string;
  currency: "EUR";
  vatBasis: "exclusive";
  nonBinding: true;
  budget: {
    selectedBudgetCategoryCode: BudgetEvaluationV2["categoryCode"];
    comparisonStatus: PricingPreviewBudgetState;
    knownMinimumExceedsBudget?: boolean;
  };
  summary: {
    knownMinimumMinor?: number;
    containsFromPricing: boolean;
    manualReviewRequired: boolean;
  };
  items: Array<{
    presentationKey: PricingPreviewPresentationKey;
    labelKey: PricingPreviewLabelKey;
    state: PricingPreviewItemState;
    quantity?: number;
    amountMinor?: number;
  }>;
  packageAdvice: {
    state:
      | "NO_PACKAGE_ADVICE"
      | "CONSIDER_PROFESSIONAL"
      | "PERSONAL_REVIEW_RECOMMENDED";
  };
}

export interface CustomerPricingPreviewDTOv2
  extends Omit<CustomerPricingPreviewDTOv1, "previewVersion"> {
  previewVersion: 2;
  selectedPackage: {
    selectedPackageDefinitionId: "starter_v1" | "professional_v1";
    label: "Starter" | "Professional";
    floorMinor: number;
    standardPageCount: number;
    standardPageLimit: number;
    includedCorrectionRounds: number;
    includedPresentation: PackageInclusionPresentation[];
  };
}

const PACKAGE_INCLUSION_PRESENTATION = {
  responsive_design: { label: "Responsive ontwerp", group: "PACKAGE_QUALITY", scope: "FULL" },
  technical_foundation: { label: "Technische basis", group: "PACKAGE_QUALITY", scope: "FULL" },
  navigation: { label: "Navigatie", group: "PACKAGE_QUALITY", scope: "FULL" },
  browser_compatibility: { label: "Browsercompatibiliteit", group: "PACKAGE_QUALITY", scope: "FULL" },
  technical_seo_base: { label: "Technische SEO-basis", group: "PACKAGE_QUALITY", scope: "BASE" },
  testing_and_delivery: { label: "Testing en oplevering", group: "PACKAGE_QUALITY", scope: "FULL" },
  standard_contact_form: { label: "Standaard contactformulier", group: "WHEN_REQUESTED", scope: "FULL" },
  social_links: { label: "Social links", group: "WHEN_REQUESTED", scope: "FULL" },
  google_maps: { label: "Google Maps", group: "WHEN_REQUESTED", scope: "FULL" },
  whatsapp: { label: "WhatsApp", group: "WHEN_REQUESTED", scope: "FULL" },
  normal_gallery_reviews: { label: "Galerijen en reviews binnen normale scope", group: "WHEN_REQUESTED", scope: "BASE" },
  public_downloads: { label: "Publieke downloads", group: "WHEN_REQUESTED", scope: "BASE" },
  supplied_content_media_processing: {
    label: "Verwerking van aangeleverde content en media",
    group: "WHEN_REQUESTED",
    scope: "BASE",
  },
  normal_ai_image_support: { label: "AI-beeldondersteuning binnen normale scope", group: "WHEN_REQUESTED", scope: "BASE" },
  primary_language: { label: "Eén hoofdtaal", group: "WHEN_REQUESTED", scope: "FULL" },
} as const satisfies Record<PackageEntitlementId, Omit<PackageInclusionPresentation, "entitlement">>;

function packageInclusionPresentation(
  entitlements: readonly PackageEntitlementId[],
): PackageInclusionPresentation[] {
  return entitlements.map((entitlement) => {
    const presentation = PACKAGE_INCLUSION_PRESENTATION[entitlement];
    if (!presentation) throw new TypeError("UNKNOWN_PACKAGE_ENTITLEMENT");
    return { entitlement, ...presentation };
  });
}

const PRESENTATION_KEYS = {
  extra_standard_page: "EXTRA_STANDARD_PAGE",
  extra_custom_page: "EXTRA_STANDARD_PAGE",
  extra_correction_round: "PACKAGE_SCOPE",
  extra_language: "EXTRA_LANGUAGE",
  contact_form: "CONTACT_FORM",
  simple_quote_form: "SIMPLE_QUOTE_FORM",
  extended_quote_form: "EXTENDED_QUOTE_FORM",
  other_extended_form: "EXTENDED_QUOTE_FORM",
  complex_form_manual: "COMPLEX_FORM",
  shop_manual: "SHOP",
  booking_manual: "BOOKING",
  simple_booking: "BOOKING",
  multilingual_manual: "MULTILINGUAL_SCOPE",
  content_media_included: "CONTENT_MEDIA",
  hosting_maintenance_manual: "HOSTING_MAINTENANCE",
  seo_included: "SEO_BASE",
  extensive_seo: "EXTENSIVE_SEO",
  basic_branding: "CONTENT_MEDIA",
  basic_logo: "CONTENT_MEDIA",
  content_support: "COPYWRITING",
  extended_ai_imagery: "IMAGE_WORK",
  customer_login: "CUSTOMER_LOGIN",
  external_integration: "EXTERNAL_INTEGRATION",
  secured_downloads: "SECURED_DOWNLOADS",
  professional_photography: "PROFESSIONAL_PHOTOGRAPHY",
  unresolved_search: "SEARCH",
  rush_review: "RUSH_SCOPE",
  substantial_copywriting: "COPYWRITING",
  exceptional_image_work: "IMAGE_WORK",
  paid_stock_handling: "PAID_STOCK",
  complex_gallery_scope: "GALLERY_SCOPE",
  complex_reviews_scope: "REVIEWS_SCOPE",
  complex_blog_scope: "BLOG_SCOPE",
  complex_jobs_scope: "JOBS_SCOPE",
  other_page_scope: "OTHER_PAGE_SCOPE",
  unknown_page_scope: "UNKNOWN_PAGE_SCOPE",
  newsletter_manual: "NEWSLETTER_SCOPE",
  standard_page_count_above_professional_scope: "PACKAGE_SCOPE",
} as const satisfies Record<string, PricingPreviewPresentationKey>;

function itemState(rule: AppliedPricingRule): PricingPreviewItemState {
  if (rule.mode === "included") return "INCLUDED";
  if (rule.mode === "fixed") return "FIXED_EXTRA";
  if (rule.mode === "from") return "FROM_EXTRA";
  if (rule.mode === "manual") return "MANUAL_REVIEW";
  throw new TypeError("UNKNOWN_PRICING_MODE");
}

function budgetState(
  pricing: BudgetGuardResult,
  budget: BudgetEvaluationV2,
): PricingPreviewBudgetState {
  if (budget.evidenceProvenance !== "budget_guard_v1") return "INDETERMINATE";
  if (budget.outsideBudgetWishes === true) return "KNOWN_MINIMUM_ABOVE_BUDGET";
  const lowerInclusiveMinor = PRICING_CONFIG.budgetEvaluation.categories[budget.categoryCode]
    .lowerInclusiveMinor;
  if (
    lowerInclusiveMinor !== null &&
    pricing.calculation.knownMinimumMinor <= lowerInclusiveMinor
  ) return "WITHIN_KNOWN_BUDGET";
  if (budget.categoryCode === "above_6000") return "INDETERMINATE";
  if (pricing.calculation.containsFromPricing) return "INDETERMINATE";
  if (budget.outsideBudgetWishes === false) return "WITHIN_KNOWN_BUDGET";
  throw new TypeError("INCOHERENT_PREVIEW_BUDGET_STATE");
}

function packageAdviceState(
  status: BudgetGuardResult["packageAdvice"]["status"],
): CustomerPricingPreviewDTOv1["packageAdvice"]["state"] {
  if (status === "none") return "NO_PACKAGE_ADVICE";
  if (status === "consider_professional") return "CONSIDER_PROFESSIONAL";
  if (status === "manual_scope_review") return "PERSONAL_REVIEW_RECOMMENDED";
  throw new TypeError("UNKNOWN_PACKAGE_ADVICE");
}

export function buildCustomerPricingPreview(
  scopeRevision: number,
  pricing: BudgetGuardResult,
  budgetEvaluation: BudgetEvaluationV2,
): CustomerPricingPreviewDTOv1 | CustomerPricingPreviewDTOv2 {
  if (!Number.isSafeInteger(scopeRevision) || scopeRevision < 0) {
    throw new TypeError("INVALID_SCOPE_REVISION");
  }
  if (
    pricing.nonBinding !== true || pricing.calculation.currency !== "EUR" ||
    pricing.calculation.vatBasis !== "exclusive" ||
    pricing.calculation.manualReviewRequired !== (pricing.calculation.manualReasons.length > 0)
  ) throw new TypeError("INCOHERENT_PRICING_PREVIEW");

  const comparisonStatus = budgetState(pricing, budgetEvaluation);
  const suppressItemAmounts = pricing.calculation.manualReviewRequired;
  const items = pricing.calculation.appliedRules
    .filter((rule) => !rule.ruleId.endsWith("_floor"))
    .map((rule) => {
      const presentationKey = PRESENTATION_KEYS[rule.ruleId as keyof typeof PRESENTATION_KEYS];
      if (!presentationKey) throw new TypeError("UNKNOWN_PRICING_RULE");
      const state = itemState(rule);
      if (
        !Number.isSafeInteger(rule.quantity) || rule.quantity < 1 ||
        ((state === "INCLUDED" || state === "MANUAL_REVIEW") && "amountMinor" in rule) ||
        ((state === "FIXED_EXTRA" || state === "FROM_EXTRA") &&
          (!Number.isSafeInteger(rule.amountMinor) || Number(rule.amountMinor) < 1))
      ) throw new TypeError("INCOHERENT_PRICING_RULE");
      return {
        presentationKey,
        labelKey: `pricing_preview.${presentationKey.toLowerCase()}` as PricingPreviewLabelKey,
        state,
        ...(rule.quantity === 1 ? {} : { quantity: rule.quantity }),
        ...(!suppressItemAmounts && (state === "FIXED_EXTRA" || state === "FROM_EXTRA")
          ? { amountMinor: rule.amountMinor }
          : {}),
      };
    });

  const base: Omit<CustomerPricingPreviewDTOv1, "previewVersion"> = {
    scopeRevision,
    pricingConfigVersion: pricing.pricingConfigVersion,
    currency: "EUR",
    vatBasis: "exclusive",
    nonBinding: true,
    budget: {
      selectedBudgetCategoryCode: budgetEvaluation.categoryCode,
      comparisonStatus,
      ...(comparisonStatus === "KNOWN_MINIMUM_ABOVE_BUDGET"
        ? { knownMinimumExceedsBudget: true }
        : comparisonStatus === "WITHIN_KNOWN_BUDGET"
        ? { knownMinimumExceedsBudget: false }
        : {}),
    },
    summary: {
      ...(!pricing.calculation.manualReviewRequired ||
          comparisonStatus === "KNOWN_MINIMUM_ABOVE_BUDGET"
        ? { knownMinimumMinor: pricing.calculation.knownMinimumMinor }
        : {}),
      containsFromPricing: pricing.calculation.containsFromPricing,
      manualReviewRequired: pricing.calculation.manualReviewRequired,
    },
    items,
    packageAdvice: { state: packageAdviceState(pricing.packageAdvice.status) },
  };
  const selectedPackage = pricing.selectedPackageDefinition;
  if (!selectedPackage) return { previewVersion: 1, ...base };
  return {
    previewVersion: 2,
    ...base,
    selectedPackage: {
      selectedPackageDefinitionId: selectedPackage.id,
      label: selectedPackage.label,
      floorMinor: selectedPackage.floorMinor,
      standardPageCount: pricing.normalizedScope.standardPageCount,
      standardPageLimit: selectedPackage.standardPageLimit,
      includedCorrectionRounds: selectedPackage.includedCorrectionRounds,
      includedPresentation: packageInclusionPresentation(selectedPackage.entitlements),
    },
  };
}

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  catalogAmountMinor,
  catalogKnownMinimumContributionMinor,
  MASTER_PRICING_CATALOG,
} from "./pricing-catalog.ts";
import {
  HISTORICAL_PACKAGE_DEFINITION_REGISTRY,
  PRICING_CONFIG,
} from "./pricing-config.ts";
import {
  calculateBudgetGuard,
  evaluateBudget,
  resolveBudgetEvidence,
} from "./pricing-engine.ts";
import { buildCustomerPricingPreview } from "./pricing-preview-dto.ts";

const manifest = JSON.parse(await Deno.readTextFile(new URL(
  "../../../docs/BUDGET-GUARD-V2-PROTECTED-CONTRACT.json",
  import.meta.url,
)));
const protectedContract = manifest.protected;
const products = MASTER_PRICING_CATALOG.products;

function preview(input: Record<string, unknown>) {
  const pricing = calculateBudgetGuard(input);
  const category = PRICING_CONFIG.budgetEvaluation.categories.above_6000;
  const evidence = resolveBudgetEvidence(
    category.originalLabel,
    PRICING_CONFIG.budgetEvaluation.schemeId,
    "above_6000",
  );
  return buildCustomerPricingPreview(
    1,
    pricing,
    evaluateBudget(pricing.calculation, evidence),
  );
}

Deno.test("freeze manifest identifies production authority and change-control stop rule", () => {
  assertEquals(manifest.status, "FROZEN");
  assertEquals(
    manifest.productionBaseline.mainSha,
    "3867b6b6dde73528d92d1b7457c8309c87d5098e",
  );
  assertEquals(
    manifest.changeControl.onUnexpectedDiff,
    "STOP — BUDGET GUARD V2 PROTECTED CONTRACT CHANGE DETECTED",
  );
  assertEquals(manifest.changeControl.autoFix, false);
});

Deno.test("protected package, budget and legacy contracts equal runtime authority", () => {
  assertEquals(PRICING_CONFIG.version, manifest.productionBaseline.pricingConfigVersion);
  assertEquals(MASTER_PRICING_CATALOG.catalogVersion, manifest.productionBaseline.catalogVersion);
  assertEquals(PRICING_CONFIG.currency, manifest.productionBaseline.currency);
  assertEquals(PRICING_CONFIG.vatBasis, manifest.productionBaseline.vatBasis);

  assertEquals(PRICING_CONFIG.packages.starter.floorMinor, protectedContract.packages.starter.floorMinor);
  assertEquals(PRICING_CONFIG.packages.starter.standardPageLimit, protectedContract.packages.starter.standardPageLimit);
  assertEquals(
    PRICING_CONFIG.packages.starter.includedCorrectionRounds,
    protectedContract.packages.starter.includedCorrectionRounds,
  );
  assertEquals(PRICING_CONFIG.packages.professional.floorMinor, protectedContract.packages.professional.floorMinor);
  assertEquals(
    PRICING_CONFIG.packages.professional.standardPageLimit,
    protectedContract.packages.professional.standardPageLimit,
  );
  assertEquals(
    PRICING_CONFIG.packages.professional.includedCorrectionRounds,
    protectedContract.packages.professional.includedCorrectionRounds,
  );

  const categories = PRICING_CONFIG.budgetEvaluation.categories;
  for (const [code, expectedBounds] of Object.entries(protectedContract.budgetV2.categories)) {
    const category = categories[code as keyof typeof categories];
    assertEquals(
      [category.lowerInclusiveMinor, category.upperInclusiveMinor],
      expectedBounds,
    );
  }
  assertEquals(
    HISTORICAL_PACKAGE_DEFINITION_REGISTRY.professional_v1.floorMinor,
    protectedContract.legacyCompatibility.professionalV1FloorMinor,
  );
  assertEquals(PRICING_CONFIG.historicalBudgetEvaluation.schemeId, "budget_guard_v1");
});

Deno.test("protected catalog values and webshop minimum charge equal business authority", () => {
  assertEquals(catalogAmountMinor("first_extra_language"), protectedContract.multilingual.firstExtraLanguageMinor);
  assertEquals(catalogAmountMinor("second_extra_language"), protectedContract.multilingual.secondAndSubsequentExtraLanguageMinor);
  assertEquals(catalogAmountMinor("subsequent_extra_language"), protectedContract.multilingual.secondAndSubsequentExtraLanguageMinor);
  assertEquals(catalogAmountMinor("webshop_base"), protectedContract.webshop.baseMinor);
  assertEquals(
    MASTER_PRICING_CATALOG.bundles.webshop_base.includedProductQuantities.simple_product,
    protectedContract.webshop.includedSimpleProducts,
  );
  assertEquals(
    products.extra_simple_products.pricing,
    {
      mode: "FIXED",
      amountMinor: protectedContract.webshop.extraSimpleProductMinor,
      unit: "product",
      minimumChargeMinor: protectedContract.webshop.extraSimpleProductsMinimumChargeMinor,
    },
  );
  assertEquals(catalogAmountMinor("stock_selection"), protectedContract.paidStock.minimumMinor);
  assertStringIncludes(products.stock_selection.externalCost ?? "", "license cost");
  assertEquals(catalogAmountMinor("advanced_newsletter"), protectedContract.newsletter.minimumMinor);
  assertEquals(catalogAmountMinor("seo_extra_language"), protectedContract.seo.extraLanguageMinor);
  assertEquals(catalogAmountMinor("advanced_seo_language"), protectedContract.seo.advancedExtraLanguageMinor);

  const bundle = ["webshop_base"] as const;
  assertEquals(
    catalogKnownMinimumContributionMinor("extra_simple_products", {
      bundleProductIds: bundle,
      quantity: 16,
    }),
    protectedContract.webshop.extraSimpleProductsMinimumChargeMinor,
  );
});

Deno.test("protected production scenarios preserve backend and customer-visible amounts", () => {
  const languages = calculateBudgetGuard({
    selected_package_definition_id: "professional_v2",
    primary_language: "nl",
    additional_languages: ["fr", "en"],
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      translation_required: false,
      seo_per_language: false,
      advanced_seo_research: false,
      language_specific_integrations: false,
      complex_scope: false,
    },
  });
  assertEquals(
    languages.calculation.knownMinimumMinor - protectedContract.packages.professional.floorMinor,
    protectedContract.multilingual.nlFrEnSupplementMinor,
  );

  for (const [productCount, expectedShopMinor] of Object.entries(protectedContract.webshop.scenarios)) {
    const result = preview({
      selected_package_definition_id: "professional_v2",
      shop_required: true,
      shop_details: {
        approx_product_count: Number(productCount),
        complex_product_count: 0,
        payment_provider_count: 1,
        shipping_scope: "standard",
        customer_accounts: false,
        catalog_import: false,
        erp_api: false,
        pickup_scope: "none",
      },
    });
    assertEquals(
      result.items.find((item) => item.presentationKey === "SHOP")?.amountMinor,
      expectedShopMinor,
    );
  }

  const paidStock = preview({
    selected_package_definition_id: "professional_v2",
    content_media_details: {
      copywriting_scope: "supplied",
      image_work_scope: "standard",
      paid_stock_handling: true,
      branding_tier: "existing",
    },
  });
  const paidStockItem = paidStock.items.find((item) => item.presentationKey === protectedContract.paidStock.presentationKey);
  assertEquals(paidStockItem?.amountMinor, protectedContract.paidStock.minimumMinor);
  assertEquals(paidStockItem?.externalCost, true);
});

Deno.test("recognized newsletter and SEO contracts preserve pricing and review semantics", () => {
  for (const scope of protectedContract.newsletter.recognizedPaidScopes) {
    const newsletter = calculateBudgetGuard({
      selected_package_definition_id: "professional_v2",
      requested_features: ["newsletter"],
      newsletter_details: {
        scope,
        analytics: "standard",
        custom_integration: false,
      },
    });
    const newsletterRule = newsletter.calculation.appliedRules.find((rule) =>
      rule.ruleId === "advanced_newsletter"
    );
    assertEquals(newsletterRule?.knownMinimumContributionMinor, protectedContract.newsletter.minimumMinor);
    assertEquals(newsletter.calculation.manualReviewRequired, false);
  }

  const seo = calculateBudgetGuard({
    selected_package_definition_id: "professional_v2",
    primary_language: "nl",
    additional_languages: ["fr"],
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      translation_required: false,
      seo_per_language: true,
      advanced_seo_research: true,
      language_specific_integrations: false,
      complex_scope: false,
    },
  });
  const seoRules = Object.fromEntries(
    seo.calculation.appliedRules.map((rule) => [rule.ruleId, rule]),
  );
  assertEquals(seoRules.seo_extra_language?.knownMinimumContributionMinor, protectedContract.seo.extraLanguageMinor);
  assertEquals(seoRules.advanced_seo_language?.knownMinimumContributionMinor, protectedContract.seo.advancedExtraLanguageMinor);
  assertEquals(seo.calculation.manualReviewRequired, true);
});

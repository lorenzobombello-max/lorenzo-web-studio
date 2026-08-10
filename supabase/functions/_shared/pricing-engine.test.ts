import { assert, assertEquals } from "jsr:@std/assert@1";
import { PRICING_CONFIG } from "./pricing-config.ts";
import { normalizePricingScope } from "./pricing-normalization.ts";
import { calculateBudgetGuard } from "./pricing-engine.ts";

const NORMAL_PAGE_SCOPES = {
  reviews: "normal",
  blog: "normal",
  jobs: "normal",
  gallery: "normal",
} as const;

function rule(result: ReturnType<typeof calculateBudgetGuard>, id: string) {
  return result.calculation.appliedRules.find((entry) => entry.ruleId === id);
}

Deno.test("pricing config contains only approved amounts and amount-safe modes", () => {
  assertEquals(PRICING_CONFIG.version, "1.0.0");
  assertEquals(PRICING_CONFIG.currency, "EUR");
  assertEquals(PRICING_CONFIG.vatBasis, "exclusive");
  assertEquals(PRICING_CONFIG.packages.starter.startingPriceMinor, 180_000);
  assertEquals(
    PRICING_CONFIG.packages.professional.startingPriceMinor,
    320_000,
  );

  const pricedRules = Object.values(PRICING_CONFIG.rules)
    .filter((entry) => "amountMinor" in entry)
    .map((entry) => entry.amountMinor)
    .sort((left, right) => left - right);
  assertEquals(pricedRules, [20_000, 20_000, 30_000, 40_000]);

  Object.values(PRICING_CONFIG.rules).forEach((entry) => {
    if (entry.mode === "manual" || entry.mode === "included") {
      assert(!("amountMinor" in entry));
    }
  });
});

Deno.test("Starter floor and included contact form produce a non-binding known minimum", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home", "contact"],
    requested_features: ["contact_form"],
  });

  assertEquals(result.calculation.knownMinimumMinor, 180_000);
  assertEquals(rule(result, "starter_floor")?.mode, "from");
  assertEquals(rule(result, "contact_form")?.mode, "included");
  assertEquals(result.calculation.manualReviewRequired, false);
  assertEquals(result.nonBinding, true);
  assertEquals("total" in result.calculation, false);
});

Deno.test("package-included functionality is not charged again beside one paid quote form", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home", "contact", "quote_request"],
    requested_features: ["contact_form", "quote_form"],
    quote_form_details: { structure_scope: "basic_single_section" },
    content_status: "complete",
    image_status: "sufficient",
    seo_priority: "basic",
  });

  assertEquals(
    result.normalizedScope.modules.filter((entry) => entry.id === "forms")
      .length,
    1,
  );
  assertEquals(rule(result, "contact_form"), undefined);
  assertEquals(rule(result, "simple_quote_form")?.knownMinimumContributionMinor, 20_000);
  assertEquals(rule(result, "content_media_included")?.knownMinimumContributionMinor, 0);
  assertEquals(rule(result, "seo_included")?.knownMinimumContributionMinor, 0);
  assertEquals(result.calculation.knownMinimumMinor, 200_000);
});

Deno.test("extra standard pages are unique and add fixed EUR 200 each above five", () => {
  const input = {
    requested_pages: [
      "home",
      "about",
      "services",
      "portfolio",
      "team",
      "pricing",
      "faq",
      "faq",
    ],
  };
  const result = calculateBudgetGuard(input);

  assertEquals(result.normalizedScope.standardPageCount, 7);
  assertEquals(rule(result, "extra_standard_page")?.quantity, 2);
  assertEquals(
    rule(result, "extra_standard_page")?.knownMinimumContributionMinor,
    40_000,
  );
  assertEquals(result.calculation.knownMinimumMinor, 220_000);
});

Deno.test("normal extra languages are deduplicated and add a from lower bound", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home"],
    primary_language: "nl",
    additional_languages: ["EN", "en", "fr", "nl"],
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      extensive_seo: false,
      language_specific_integrations: false,
      complex_scope: false,
    },
  });

  assertEquals(result.normalizedScope.additionalLanguages, ["en", "fr"]);
  assertEquals(rule(result, "extra_language")?.mode, "from");
  assertEquals(rule(result, "extra_language")?.quantity, 2);
  assertEquals(
    rule(result, "extra_language")?.knownMinimumContributionMinor,
    60_000,
  );
  assertEquals(result.calculation.knownMinimumMinor, 240_000);
});

Deno.test("language aliases, casing and locales normalize to commercial base languages", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home"],
    primary_language: "Nederlands",
    additional_languages: [
      "NL",
      "Dutch",
      "nl-BE",
      "Frans",
      "Français",
      "French",
      "fr-BE",
      "Engels",
      "English",
      "en-GB",
      "en-US",
      "Duits",
      "Deutsch",
      "German",
      "de-DE",
      "Italiaans",
      "Italiano",
      "Italian",
      "it-IT",
      "Spaans",
      "Español",
      "Spanish",
      "es_ES",
    ],
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      extensive_seo: false,
      language_specific_integrations: false,
      complex_scope: false,
    },
  });

  assertEquals(result.normalizedScope.primaryLanguage, "nl");
  assertEquals(result.normalizedScope.additionalLanguages, [
    "fr",
    "en",
    "de",
    "it",
    "es",
  ]);
  assertEquals(result.normalizedScope.unknownLanguages, []);
  assertEquals(rule(result, "extra_language")?.quantity, 5);
  assertEquals(result.calculation.knownMinimumMinor, 330_000);
  assertEquals(result.calculation.manualReviewRequired, false);
});

Deno.test("unknown languages remain evidence, are not priced and require manual review", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home"],
    primary_language: "nl_BE",
    additional_languages: ["French", "Português", "pt-BR"],
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      extensive_seo: false,
      language_specific_integrations: false,
      complex_scope: false,
    },
  });

  assertEquals(result.normalizedScope.primaryLanguage, "nl");
  assertEquals(result.normalizedScope.additionalLanguages, ["fr"]);
  assertEquals(result.normalizedScope.unknownLanguages, ["português", "pt-br"]);
  assertEquals(rule(result, "extra_language"), undefined);
  assertEquals(rule(result, "multilingual_manual")?.mode, "manual");
  assertEquals(result.calculation.knownMinimumMinor, 180_000);
  assertEquals(result.calculation.manualReviewRequired, true);
});

Deno.test("unsafe multilingual scope is manual and adds no amount", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home"],
    primary_language: "nl",
    additional_languages: ["fr"],
    multilingual_details: { final_translations_supplied: false },
  });

  assertEquals(rule(result, "multilingual_manual")?.mode, "manual");
  assertEquals(
    rule(result, "multilingual_manual")?.knownMinimumContributionMinor,
    0,
  );
  assertEquals(result.calculation.knownMinimumMinor, 180_000);
  assertEquals(result.calculation.manualReviewRequired, true);
});

Deno.test("shop evidence deduplicates and shop page is not a standard page", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home", "shop"],
    requested_features: ["shop", "online_payment"],
    website_goals: ["sell_products"],
    shop_required: true,
    shop_details: { online_payments: true },
  });

  assertEquals(result.normalizedScope.standardPages, ["home"]);
  assertEquals(
    result.normalizedScope.modules.filter((entry) => entry.id === "shop")
      .length,
    1,
  );
  assertEquals(
    result.calculation.appliedRules.filter((entry) =>
      entry.ruleId === "shop_manual"
    ).length,
    1,
  );
  assertEquals(result.calculation.knownMinimumMinor, 180_000);
});

Deno.test("booking evidence deduplicates and reservation page is not a standard page", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home", "reservations"],
    requested_features: ["appointments", "reservations"],
    website_goals: ["appointments"],
    booking_required: true,
    booking_details: { calendar_integration: true },
  });

  assertEquals(result.normalizedScope.standardPageCount, 1);
  assertEquals(
    result.normalizedScope.modules.filter((entry) => entry.id === "booking")
      .length,
    1,
  );
  assertEquals(
    result.calculation.appliedRules.filter((entry) =>
      entry.ruleId === "booking_manual"
    ).length,
    1,
  );
});

Deno.test("raw structure classifies simple and extended quote forms authoritatively", () => {
  const simple = calculateBudgetGuard({
    requested_pages: ["home", "quote_request"],
    requested_features: ["quote_form"],
    website_goals: ["quote_requests"],
    quote_form_details: {
      classification: "extended",
      structure_scope: "basic_single_section",
    },
  });
  assertEquals(simple.normalizedScope.standardPageCount, 1);
  assertEquals(
    simple.normalizedScope.modules.filter((entry) => entry.id === "forms")
      .length,
    1,
  );
  assertEquals(
    simple.calculation.appliedRules.filter((entry) =>
      entry.ruleId === "simple_quote_form"
    ).length,
    1,
  );
  assertEquals(simple.calculation.knownMinimumMinor, 200_000);

  const extended = calculateBudgetGuard({
    requested_pages: ["home", "quote_request"],
    requested_features: ["quote_form"],
    quote_form_details: {
      classification: "simple",
      structure_scope: "extended_standard_structure",
    },
  });
  assertEquals(rule(extended, "extended_quote_form")?.mode, "from");
  assertEquals(extended.calculation.knownMinimumMinor, 220_000);
});

Deno.test("unsure or missing raw form structure is manual and contributes zero", () => {
  for (const structure_scope of [undefined, "unsure_or_other"] as const) {
    const result = calculateBudgetGuard({
      requested_pages: ["home", "quote_request"],
      requested_features: ["quote_form"],
      quote_form_details: structure_scope ? { structure_scope } : undefined,
    });
    assertEquals(rule(result, "complex_form_manual")?.mode, "manual");
    assertEquals(
      rule(result, "complex_form_manual")?.knownMinimumContributionMinor,
      0,
    );
    assertEquals(result.calculation.knownMinimumMinor, 180_000);
  }
});

Deno.test("every complex workflow signal overrides raw standard structure", () => {
  for (
    const quote_form_details of [
      { structure_scope: "basic_single_section", file_uploads: true },
      { structure_scope: "basic_single_section", form_count: 2 },
      { structure_scope: "extended_standard_structure", database_workflow: true },
      { structure_scope: "extended_standard_structure", automated_processing: true },
      { structure_scope: "extended_standard_structure", review_approval: true },
      { structure_scope: "extended_standard_structure", custom_logic: true },
    ]
  ) {
    const result = calculateBudgetGuard({
      requested_pages: ["home", "quote_request"],
      requested_features: ["quote_form"],
      quote_form_details,
    });
    assertEquals(rule(result, "complex_form_manual")?.mode, "manual");
    assertEquals(rule(result, "simple_quote_form"), undefined);
    assertEquals(result.calculation.knownMinimumMinor, 180_000);
    assertEquals(result.calculation.manualReviewRequired, true);
  }
});

Deno.test("legacy classification alone neither creates nor prices a quote form", () => {
  const noQuoteIntent = calculateBudgetGuard({
    requested_pages: ["home"],
    quote_form_details: { classification: "simple" },
  });
  assertEquals(
    noQuoteIntent.normalizedScope.modules.some((entry) => entry.id === "forms"),
    false,
  );

  const quoteIntent = calculateBudgetGuard({
    requested_pages: ["home", "quote_request"],
    quote_form_details: { classification: "simple" },
  });
  assertEquals(rule(quoteIntent, "simple_quote_form"), undefined);
  assertEquals(rule(quoteIntent, "complex_form_manual")?.mode, "manual");
});

Deno.test("conditional and unknown pages are conservative and never double-counted", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home", "gallery", "other", "mystery", "gallery"],
    page_scope_details: { gallery: "complex" },
  });

  assertEquals(result.normalizedScope.standardPages, ["home"]);
  assert(
    result.normalizedScope.manualComponents.includes("complex_gallery_scope"),
  );
  assert(result.normalizedScope.manualComponents.includes("other_page_scope"));
  assert(
    result.normalizedScope.manualComponents.includes("unknown_page_scope"),
  );
  assertEquals(result.calculation.manualReviewRequired, true);
});

Deno.test("known manual components normalize once and never add money", () => {
  const result = calculateBudgetGuard({
    requested_pages: ["home"],
    requested_features: ["customer_login", "downloads", "search", "search"],
    integrations: ["CRM", "CRM"],
    image_support: ["professional_photography", "professional_photography"],
    download_details: { access: "secured" },
    deadline_details: { commercially_critical: true },
  });

  assertEquals(result.normalizedScope.manualComponents.sort(), [
    "customer_login",
    "external_integration",
    "professional_photography",
    "rush_review",
    "secured_downloads",
    "unresolved_search",
  ]);
  assertEquals(result.calculation.knownMinimumMinor, 180_000);
  assertEquals(result.calculation.manualReviewRequired, true);
  assert(
    result.calculation.appliedRules
      .filter((entry) => entry.mode === "manual")
      .every((entry) =>
        entry.knownMinimumContributionMinor === 0 && !("amountMinor" in entry)
      ),
  );
});

Deno.test("content, hosting and SEO normalize to one canonical module each", () => {
  const scope = normalizePricingScope({
    requested_pages: ["home", "gallery"],
    requested_features: ["gallery", "reviews"],
    page_scope_details: { gallery: "normal" },
    content_status: "complete",
    image_status: "sufficient",
    hosting_status: "no_hosting",
    hosting_support: "advice",
    maintenance_interest: "info_requested",
    seo_priority: "basic",
  });

  assertEquals(
    scope.modules.filter((entry) => entry.id === "content_media").length,
    1,
  );
  assertEquals(
    scope.modules.filter((entry) => entry.id === "hosting_maintenance").length,
    1,
  );
  assertEquals(scope.modules.filter((entry) => entry.id === "seo").length, 1);

  const result = calculateBudgetGuard({
    requested_pages: ["home", "gallery"],
    requested_features: ["gallery", "reviews"],
    page_scope_details: { gallery: "normal" },
    content_status: "complete",
    image_status: "sufficient",
    hosting_status: "no_hosting",
    hosting_support: "advice",
    maintenance_interest: "info_requested",
    seo_priority: "basic",
  });
  assertEquals(rule(result, "content_media_included")?.mode, "included");
  assertEquals(rule(result, "seo_included")?.mode, "included");
  assertEquals(rule(result, "hosting_maintenance_manual")?.mode, "manual");
  assertEquals(result.calculation.knownMinimumMinor, 180_000);
});

Deno.test("package advice follows page thresholds and never changes calculation basis", () => {
  const five = calculateBudgetGuard({
    requested_pages: ["home", "about", "services", "portfolio", "contact"],
  });
  const twelve = calculateBudgetGuard({
    requested_pages: [
      "home",
      "about",
      "services",
      "products",
      "portfolio",
      "team",
      "pricing",
      "faq",
      "reviews",
      "blog",
      "contact",
      "jobs",
    ],
    page_scope_details: NORMAL_PAGE_SCOPES,
  });
  const thirteen = calculateBudgetGuard({
    requested_pages: [
      "home",
      "about",
      "services",
      "products",
      "portfolio",
      "team",
      "pricing",
      "faq",
      "reviews",
      "blog",
      "contact",
      "jobs",
      "gallery",
    ],
    page_scope_details: NORMAL_PAGE_SCOPES,
  });

  assertEquals(five.packageAdvice.status, "none");
  assertEquals(twelve.packageAdvice.status, "consider_professional");
  assertEquals(thirteen.packageAdvice.status, "manual_scope_review");
  assertEquals(twelve.calculation.manualReviewRequired, false);
  assertEquals(thirteen.calculation.manualReviewRequired, true);
  assertEquals(thirteen.calculation.manualReasons, [
    "standard_page_count_above_professional_scope",
  ]);
  assertEquals(twelve.packageAdvice.advisoryOnly, true);
  assertEquals(thirteen.packageAdvice.advisoryOnly, true);
  assertEquals(twelve.packageAdvice.selectedPackage, null);
  assertEquals(thirteen.packageAdvice.selectedPackage, null);
  assertEquals(rule(twelve, "starter_floor")?.amountMinor, 180_000);
  assertEquals(twelve.calculation.knownMinimumMinor, 320_000);
  assertEquals(thirteen.calculation.knownMinimumMinor, 340_000);
  assertEquals(
    thirteen.calculation.appliedRules.some((entry) =>
      entry.ruleId === "standard_page_count_above_professional_scope"
    ),
    false,
  );
  assertEquals(rule(twelve, "professional_reference"), undefined);
});

Deno.test("13+ pages and another manual component remain deduplicated and amount-safe", () => {
  const result = calculateBudgetGuard({
    requested_pages: [
      "home",
      "about",
      "services",
      "products",
      "portfolio",
      "team",
      "pricing",
      "faq",
      "reviews",
      "blog",
      "contact",
      "jobs",
      "gallery",
    ],
    page_scope_details: NORMAL_PAGE_SCOPES,
    requested_features: ["customer_login"],
  });

  assertEquals(result.packageAdvice.status, "manual_scope_review");
  assertEquals(result.packageAdvice.advisoryOnly, true);
  assertEquals(result.packageAdvice.selectedPackage, null);
  assertEquals(result.calculation.manualReviewRequired, true);
  assertEquals(result.calculation.manualReasons, [
    "customer_login",
    "standard_page_count_above_professional_scope",
  ]);
  assertEquals(result.calculation.knownMinimumMinor, 340_000);
  assertEquals(
    rule(result, "customer_login")?.knownMinimumContributionMinor,
    0,
  );
});

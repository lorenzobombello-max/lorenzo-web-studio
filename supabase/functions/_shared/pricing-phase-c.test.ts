import { assertEquals } from "jsr:@std/assert@1";
import { catalogAmountMinor } from "./pricing-catalog.ts";
import {
  ACTIVE_PACKAGE_DEFINITION_IDS,
  HISTORICAL_PACKAGE_DEFINITION_REGISTRY,
  PRICING_CONFIG,
  resolvePackageDefinition,
} from "./pricing-config.ts";
import { calculateBudgetGuard } from "./pricing-engine.ts";

const standardPages = [
  "home",
  "about",
  "services",
  "portfolio",
  "team",
  "pricing",
  "faq",
  "contact",
  "reviews",
  "blog",
  "jobs",
  "gallery",
] as const;

const normalPageScopeEvidence = {
  page_scope_details: {
    reviews: "normal",
    blog: "normal",
    jobs: "normal",
    gallery: "normal",
  },
};

function price(input: Record<string, unknown>) {
  return calculateBudgetGuard(input);
}

Deno.test("C01-C10 active packages use catalog v1 and preserve professional_v1 history", () => {
  assertEquals(ACTIVE_PACKAGE_DEFINITION_IDS, [
    "starter_v1",
    "professional_v2",
  ]);

  const starter = resolvePackageDefinition("starter_v1");
  assertEquals(starter.floorMinor, 180_000);
  assertEquals(starter.standardPageLimit, 5);
  assertEquals(starter.includedCorrectionRounds, 1);

  const professional = resolvePackageDefinition("professional_v2");
  assertEquals(professional.id, "professional_v2");
  assertEquals(professional.floorMinor, 350_000);
  assertEquals(professional.standardPageLimit, 10);
  assertEquals(professional.includedCorrectionRounds, 2);
  assertEquals(professional.entitlements.includes("blog_news"), true);

  assertEquals(HISTORICAL_PACKAGE_DEFINITION_REGISTRY.professional_v1, {
    id: "professional_v1",
    version: 1,
    label: "Professional",
    priceMode: "from",
    floorMinor: 320_000,
    standardPageLimit: 12,
    includedCorrectionRounds: 2,
    inheritsFrom: "starter_v1",
    entitlements: [],
  });

  assertEquals(PRICING_CONFIG.packages.professional.id, "professional_v2");
});

Deno.test("C09-C13 blog and page allowances do not double charge", () => {
  const starterBlog = price({
    selected_package_definition_id: "starter_v1",
    requested_pages: ["home", "blog"],
    ...normalPageScopeEvidence,
  });
  assertEquals(starterBlog.calculation.knownMinimumMinor, 225_000);

  const professionalBlog = price({
    selected_package_definition_id: "professional_v2",
    requested_pages: ["home", "blog"],
    ...normalPageScopeEvidence,
  });
  assertEquals(professionalBlog.calculation.knownMinimumMinor, 350_000);

  const starterSeven = price({
    selected_package_definition_id: "starter_v1",
    requested_pages: standardPages.slice(0, 7),
    ...normalPageScopeEvidence,
  });
  assertEquals(starterSeven.calculation.knownMinimumMinor, 225_000);

  const professionalTwelve = price({
    selected_package_definition_id: "professional_v2",
    requested_pages: standardPages,
    ...normalPageScopeEvidence,
  });
  assertEquals(professionalTwelve.calculation.knownMinimumMinor, 395_000);
});

Deno.test("C14-C20 language ladder and manual pricing remain additive", () => {
  for (
    const [count, expected] of [[1, 245_000], [2, 290_000], [
      3,
      335_000,
    ]] as const
  ) {
    const result = price({
      selected_package_definition_id: "starter_v1",
      primary_language: "nl",
      additional_languages: ["fr", "en", "de"].slice(0, count),
      multilingual_details: {
        final_translations_supplied: true,
        same_structure: true,
        extensive_seo: false,
        language_specific_integrations: false,
        complex_scope: false,
      },
    });
    assertEquals(result.calculation.knownMinimumMinor, expected);
  }

  const additive = price({
    selected_package_definition_id: "professional_v2",
    seo_details: { extensive_services: true },
    integrations: ["custom"],
  });
  assertEquals(additive.calculation.knownMinimumMinor, 415_000);
  assertEquals(additive.calculation.containsFromPricing, true);
  assertEquals(additive.calculation.manualReviewRequired, true);
});

Deno.test("C23-C25 existing add-on evidence uses catalog values without tier stacking", () => {
  const cases = [
    [
      {
        requested_pages: ["quote_request"],
        quote_form_details: { structure_scope: "basic_single_section" },
      },
      "simple_quote_form",
      "basic_quote_form",
    ],
    [
      {
        requested_pages: ["quote_request"],
        quote_form_details: { structure_scope: "extended_standard_structure" },
      },
      "extended_quote_form",
      "extended_quote_form",
    ],
    [
      {
        requested_pages: ["quote_request"],
        quote_form_details: {
          structure_scope: "basic_single_section",
          file_uploads: true,
        },
      },
      "other_extended_form",
      "upload_form",
    ],
    [
      {
        requested_pages: ["gallery"],
        page_scope_details: { gallery: "complex" },
      },
      "complex_gallery_scope",
      "advanced_gallery",
    ],
    [
      {
        requested_pages: ["reviews"],
        page_scope_details: { reviews: "complex" },
      },
      "complex_reviews_scope",
      "live_reviews",
    ],
    [
      { download_details: { access: "secured" } },
      "secured_downloads",
      "secure_download",
    ],
  ] as const;

  for (const [input, ruleId, productId] of cases) {
    const result = price({
      selected_package_definition_id: "starter_v1",
      ...input,
    });
    const matching = result.calculation.appliedRules.filter((entry) =>
      entry.ruleId === ruleId
    );
    assertEquals(matching.length, 1);
    assertEquals(
      matching[0].knownMinimumContributionMinor,
      catalogAmountMinor(productId),
    );
  }

  const combo = price({
    selected_package_definition_id: "starter_v1",
    brand_status: "none",
    logo_status: "needed",
  });
  assertEquals(combo.calculation.knownMinimumMinor, 295_000);
  assertEquals(
    combo.calculation.appliedRules.filter((entry) =>
      ["basic_branding", "basic_logo", "logo_identity_combo"].includes(
        entry.ruleId,
      )
    ).map((entry) => entry.ruleId),
    ["logo_identity_combo"],
  );
});

Deno.test("C20 C25 C30 known webshop and newsletter minima preserve their catalog states", () => {
  const webshop = price({
    selected_package_definition_id: "professional_v2",
    shop_required: true,
  });
  assertEquals(webshop.calculation.knownMinimumMinor, 525_000);
  assertEquals(webshop.calculation.manualReviewRequired, true);

  const newsletter = price({
    selected_package_definition_id: "starter_v1",
    newsletter_details: { scope: "automation_or_segmentation" },
  });
  assertEquals(newsletter.calculation.knownMinimumMinor, 205_000);
  assertEquals(newsletter.calculation.manualReviewRequired, false);
});

Deno.test("C26 unsupported catalog products remain outside active runtime config", () => {
  for (
    const productId of [
      "dns_configuration",
      "domain_transfer",
      "extra_payment_provider",
      "advanced_search",
    ]
  ) {
    assertEquals(productId in PRICING_CONFIG.rules, false);
  }
});

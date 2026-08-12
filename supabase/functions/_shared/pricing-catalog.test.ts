import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  CATALOG_VERSION,
  catalogKnownMinimumContributionMinor,
  MASTER_PRICING_CATALOG,
} from "./pricing-catalog.ts";
import {
  PACKAGE_DEFINITION_REGISTRY,
  PRICING_CONFIG,
} from "./pricing-config.ts";

const product = (id: keyof typeof MASTER_PRICING_CATALOG.products) =>
  MASTER_PRICING_CATALOG.products[id];

const amount = (id: keyof typeof MASTER_PRICING_CATALOG.products) => {
  const pricing = product(id).pricing;
  assert("amountMinor" in pricing, `${id} must have an amount`);
  return pricing.amountMinor;
};

Deno.test("B01-B05 package catalog matches Master Catalog v1", () => {
  assertEquals(amount("starter"), 180_000);
  assertEquals(amount("professional"), 350_000);
  assertEquals(MASTER_PRICING_CATALOG.packages.starter_v1.standardPageLimit, 5);
  assertEquals(
    MASTER_PRICING_CATALOG.packages.professional_v2.standardPageLimit,
    10,
  );
  assertEquals(
    MASTER_PRICING_CATALOG.packages.starter_v1.includedCorrectionRounds,
    1,
  );
  assertEquals(
    MASTER_PRICING_CATALOG.packages.professional_v2.includedCorrectionRounds,
    2,
  );
  assert(
    MASTER_PRICING_CATALOG.packages.professional_v2.includedProductIds.includes(
      "blog_news",
    ),
  );
});

Deno.test("B06-B11 page, webshop, language and SEO prices are authoritative", () => {
  assertEquals(product("extra_standard_page").pricing.mode, "FIXED");
  assertEquals(amount("extra_standard_page"), 22_500);
  assertEquals(product("complex_page").pricing.mode, "FROM");
  assertEquals(amount("complex_page"), 45_000);
  assertEquals(product("webshop_base").pricing.mode, "FROM");
  assertEquals(amount("webshop_base"), 175_000);
  assertEquals([
    amount("first_extra_language"),
    amount("second_extra_language"),
    amount("subsequent_extra_language"),
  ], [65_000, 45_000, 45_000]);
  assertEquals(product("seo_launch").pricing.mode, "FROM");
  assertEquals(amount("seo_launch"), 65_000);
});

Deno.test("B09 webshop base records every included base component", () => {
  assertEquals(
    MASTER_PRICING_CATALOG.bundles.webshop_base.includedProductQuantities,
    {
      simple_product: 15,
      standard_payment_provider: 1,
      standard_shipping: 1,
      normal_categories: 1,
    },
  );
});

Deno.test("B12 branding prices and alternatives are explicit", () => {
  assertEquals([
    amount("professional_logo"),
    amount("visual_identity"),
    amount("logo_identity_combo"),
    amount("extended_branding"),
  ], [65_000, 75_000, 115_000, 150_000]);
  const brandingIds = [
    "professional_logo",
    "visual_identity",
    "logo_identity_combo",
    "extended_branding",
  ] as const;
  assertEquals(
    brandingIds.map((id) => product(id).alternativeGroup),
    brandingIds.map(() => "branding_tier"),
  );
});

Deno.test("B13-B17 maintenance, revision and rush prices preserve units", () => {
  assertEquals([amount("care"), product("care").pricing.unit], [
    4_900,
    "month",
  ]);
  assertEquals([amount("care_plus"), product("care_plus").pricing.unit], [
    9_900,
    "month",
  ]);
  assertEquals([amount("adhoc_work"), product("adhoc_work").pricing.unit], [
    8_500,
    "hour",
  ]);
  assertEquals(amount("extra_revision"), 15_000);
  assertEquals(product("rush").pricing, {
    mode: "FROM",
    minimumPercentage: 20,
    unit: "percentage",
  });
});

Deno.test("B18 package inclusion prevents a Professional blog double-charge", () => {
  assertEquals(catalogKnownMinimumContributionMinor("blog_news"), 45_000);
  assertEquals(
    catalogKnownMinimumContributionMinor("blog_news", {
      packageId: "professional_v2",
    }),
    0,
  );
  assertEquals(
    catalogKnownMinimumContributionMinor("standard_contact_form", {
      packageId: "professional_v2",
    }),
    0,
  );
});

Deno.test("B19 webshop allowances prevent base component double-charges", () => {
  const context = { bundleProductIds: ["webshop_base"] as const };
  assertEquals(
    catalogKnownMinimumContributionMinor("simple_product", {
      ...context,
      quantity: 15,
    }),
    0,
  );
  assertEquals(
    catalogKnownMinimumContributionMinor("standard_payment_provider", context),
    0,
  );
  assertEquals(
    catalogKnownMinimumContributionMinor("standard_shipping", context),
    0,
  );
  assertEquals(
    catalogKnownMinimumContributionMinor("normal_categories", context),
    0,
  );
  assertEquals(
    catalogKnownMinimumContributionMinor("extra_simple_products", {
      ...context,
      quantity: 16,
    }),
    10_000,
  );
});

Deno.test("B20 every tier family is mutually exclusive", () => {
  for (
    const group of [
      "reviews_tier",
      "gallery_tier",
      "branding_tier",
      "form_tier",
      "booking_tier",
      "search_tier",
      "secure_tier",
    ]
  ) {
    assert(
      Object.values(MASTER_PRICING_CATALOG.products)
        .filter((entry) => entry.alternativeGroup === group).length >= 2,
      `${group} must contain alternatives`,
    );
  }
});

Deno.test("B21 recurring products do not inflate a one-time project minimum", () => {
  assertEquals(
    catalogKnownMinimumContributionMinor("care", { billingContext: "PROJECT" }),
    0,
  );
  assertEquals(
    catalogKnownMinimumContributionMinor("care", {
      billingContext: "RECURRING",
    }),
    4_900,
  );
  assertEquals(
    catalogKnownMinimumContributionMinor("five_hour_bundle"),
    40_000,
  );
});

Deno.test("B22 manual-only products never fabricate an amount", () => {
  const manualProducts = Object.values(MASTER_PRICING_CATALOG.products)
    .filter((entry) => entry.pricing.mode === "MANUAL");
  assert(manualProducts.length > 0);
  assert(manualProducts.every((entry) => !("amountMinor" in entry.pricing)));
  assert(manualProducts.every((entry) => entry.manualReview !== undefined));
});

Deno.test("B23 catalog version and source identity are explicit", () => {
  assertEquals(CATALOG_VERSION, "2026-08-12-v1");
  assertEquals(MASTER_PRICING_CATALOG.catalogVersion, CATALOG_VERSION);
  assertEquals(MASTER_PRICING_CATALOG.packages.professional_v2.version, 2);
  assertEquals(
    MASTER_PRICING_CATALOG.legacyPackageBindings.professional_v1,
    "professional_v2",
  );
  assertEquals(
    MASTER_PRICING_CATALOG.source.sha256,
    "d95ad2392ea18c518ae21e8965379cdd377a68027cc6ca0f3f8e5e54a907e7c3",
  );
  assertEquals(
    MASTER_PRICING_CATALOG.dependencies.publicPricingPage,
    "https://lorenzowebsolutions.be/pages/pricing.html",
  );
});

Deno.test("B24 historical Professional v1 remains isolated from catalog Professional v2", () => {
  assertEquals(PACKAGE_DEFINITION_REGISTRY.professional_v1.floorMinor, 320_000);
  assertEquals(
    PACKAGE_DEFINITION_REGISTRY.professional_v1.standardPageLimit,
    12,
  );
  assertEquals(
    MASTER_PRICING_CATALOG.packages.professional_v2.catalogProductId,
    "professional",
  );
  assertEquals(amount("professional"), 350_000);
  assertEquals(
    MASTER_PRICING_CATALOG.packages.professional_v2.standardPageLimit,
    10,
  );
});

Deno.test("every legacy runtime rule has a closed catalog migration binding", () => {
  assertEquals(
    Object.keys(MASTER_PRICING_CATALOG.legacyRuleBindings).sort(),
    Object.keys(PRICING_CONFIG.rules).sort(),
  );
  const productIds = new Set(Object.keys(MASTER_PRICING_CATALOG.products));
  for (
    const bindings of Object.values(MASTER_PRICING_CATALOG.legacyRuleBindings)
  ) {
    assert(bindings.length > 0);
    for (const productId of bindings) assert(productIds.has(productId));
  }
});

Deno.test("catalog references are closed and stable", () => {
  const ids = new Set(Object.keys(MASTER_PRICING_CATALOG.products));
  assert(
    ids.size >= 70,
    "full Master Catalog v1 must contain at least 70 products",
  );
  for (const [id, entry] of Object.entries(MASTER_PRICING_CATALOG.products)) {
    assertEquals(entry.id, id);
    assert(entry.label.length > 0);
    for (const dependency of entry.dependencies) {
      assert(ids.has(dependency), `${id} dependency ${dependency}`);
    }
    for (const alternative of entry.requiresOneOf ?? []) {
      assert(
        ids.has(alternative),
        `${id} alternative dependency ${alternative}`,
      );
    }
    if (entry.consumesAllowanceFor) {
      assert(ids.has(entry.consumesAllowanceFor), `${id} allowance reference`);
    }
  }
  for (
    const packageDefinition of Object.values(MASTER_PRICING_CATALOG.packages)
  ) {
    assert(ids.has(packageDefinition.catalogProductId));
    for (const included of packageDefinition.includedProductIds) {
      assert(ids.has(included));
    }
  }
  for (const bundle of Object.values(MASTER_PRICING_CATALOG.bundles)) {
    assert(ids.has(bundle.catalogProductId));
    for (const included of Object.keys(bundle.includedProductQuantities)) {
      assert(ids.has(included));
    }
  }
});

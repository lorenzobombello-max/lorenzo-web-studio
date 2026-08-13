import { assertEquals } from "jsr:@std/assert@1";
import { catalogAmountMinor } from "./pricing-catalog.ts";
import { calculateBudgetGuard } from "./pricing-engine.ts";

function price(input: Record<string, unknown>) {
  return calculateBudgetGuard({
    selected_package_definition_id: "starter_v1",
    ...input,
  });
}

function contribution(
  result: ReturnType<typeof price>,
  ruleId: string,
): number {
  return result.calculation.appliedRules
    .filter((rule) => rule.ruleId === ruleId)
    .reduce((sum, rule) => sum + rule.knownMinimumContributionMinor, 0);
}

Deno.test("D01-D02 dynamic portfolio, advanced gallery and live reviews use catalog products", () => {
  const result = price({
    requested_pages: ["portfolio", "gallery", "reviews"],
    page_scope_details: {
      portfolio: "dynamic",
      gallery: "advanced",
      reviews: "live",
    },
  });
  assertEquals(
    contribution(result, "dynamic_portfolio"),
    catalogAmountMinor("dynamic_portfolio"),
  );
  assertEquals(
    contribution(result, "advanced_gallery"),
    catalogAmountMinor("advanced_gallery"),
  );
  assertEquals(
    contribution(result, "live_reviews"),
    catalogAmountMinor("live_reviews"),
  );
});

Deno.test("D03-D05 booking tiers are exclusive and custom remains manual", () => {
  for (
    const [tier, productId] of [["widget", "booking_widget"], [
      "advanced",
      "advanced_booking",
    ]] as const
  ) {
    const result = price({ booking_required: true, booking_details: { tier } });
    assertEquals(
      contribution(result, productId),
      catalogAmountMinor(productId),
    );
    assertEquals(
      result.calculation.appliedRules.filter((rule) =>
        ["booking_widget", "advanced_booking", "custom_booking"].includes(
          rule.ruleId,
        )
      ).length,
      1,
    );
  }
  const custom = price({
    booking_required: true,
    booking_details: { tier: "custom" },
  });
  assertEquals(custom.calculation.manualReviewRequired, true);
  assertEquals(contribution(custom, "custom_booking"), 0);
});

Deno.test("D06-D10 search and secure tiers preserve known minima beside review", () => {
  const basic = price({
    requested_features: ["search"],
    page_scope_details: { search: "basic" },
  });
  assertEquals(
    contribution(basic, "site_search"),
    catalogAmountMinor("site_search"),
  );
  const advanced = price({
    requested_features: ["search"],
    page_scope_details: { search: "advanced" },
  });
  assertEquals(
    contribution(advanced, "advanced_search"),
    catalogAmountMinor("advanced_search"),
  );
  assertEquals(advanced.calculation.manualReviewRequired, true);

  const secure = price({
    requested_features: ["downloads"],
    download_details: { access: "download" },
  });
  assertEquals(
    contribution(secure, "secure_download"),
    catalogAmountMinor("secure_download"),
  );
  const documents = price({
    requested_features: ["downloads"],
    download_details: { access: "document_flow" },
  });
  assertEquals(
    contribution(documents, "professional_document_flow"),
    catalogAmountMinor("professional_document_flow"),
  );
  const portal = price({
    requested_features: ["downloads"],
    download_details: { access: "portal" },
  });
  assertEquals(portal.calculation.manualReviewRequired, true);
  assertEquals(contribution(portal, "customer_portal"), 0);
});

Deno.test("D11-D18 webshop allowances and extras do not double charge", () => {
  const base = {
    shop_required: true,
    shop_details: {
      approx_product_count: 15,
      complex_product_count: 0,
      payment_provider_count: 1,
      shipping_scope: "standard",
      customer_accounts: false,
      catalog_import: false,
      erp_api: false,
    },
  };
  assertEquals(contribution(price(base), "extra_simple_products"), 0);
  assertEquals(
    contribution(
      price({
        ...base,
        shop_details: { ...base.shop_details, approx_product_count: 16 },
      }),
      "extra_simple_products",
    ),
    10_000,
  );
  assertEquals(
    contribution(
      price({
        ...base,
        shop_details: { ...base.shop_details, approx_product_count: 20 },
      }),
      "extra_simple_products",
    ),
    10_000,
  );

  const extras = price({
    ...base,
    shop_details: {
      ...base.shop_details,
      payment_provider_count: 2,
      shipping_scope: "complex",
      customer_accounts: true,
      catalog_import: true,
      erp_api: true,
    },
  });
  assertEquals(
    contribution(extras, "extra_payment_provider"),
    catalogAmountMinor("extra_payment_provider"),
  );
  assertEquals(
    contribution(extras, "complex_shipping"),
    catalogAmountMinor("complex_shipping"),
  );
  assertEquals(
    contribution(extras, "webshop_accounts"),
    catalogAmountMinor("webshop_accounts"),
  );
  assertEquals(
    extras.calculation.manualReasons.includes("catalog_import"),
    true,
  );
  assertEquals(
    extras.calculation.manualReasons.includes("erp_inventory_api"),
    true,
  );
});

Deno.test("D62 complex webshop products use the approved 50/30 staircase", () => {
  for (
    const [complex_product_count, expected] of [
      [5, 25_000],
      [10, 50_000],
      [11, 53_000],
      [15, 65_000],
      [20, 80_000],
    ] as const
  ) {
    const result = price({
      shop_required: true,
      shop_details: {
        approx_product_count: 15,
        complex_product_count,
        payment_provider_count: 1,
        shipping_scope: "standard",
        customer_accounts: false,
        catalog_import: false,
        erp_api: false,
      },
    });
    assertEquals(contribution(result, "complex_product"), expected);
  }
});

Deno.test("D63-D65 pickup reuses included, booking and manual catalog semantics", () => {
  const base = {
    shop_required: true,
    shop_details: {
      approx_product_count: 15,
      complex_product_count: 0,
      payment_provider_count: 1,
      shipping_scope: "standard",
      customer_accounts: false,
      catalog_import: false,
      erp_api: false,
    },
  };

  const simple = price({
    ...base,
    shop_details: { ...base.shop_details, pickup_scope: "simple" },
  });
  assertEquals(simple.calculation.manualReviewRequired, false);
  assertEquals(contribution(simple, "booking_widget"), 0);

  const scheduled = price({
    ...base,
    shop_details: { ...base.shop_details, pickup_scope: "scheduled" },
  });
  assertEquals(
    contribution(scheduled, "booking_widget"),
    catalogAmountMinor("booking_widget"),
  );

  const complex = price({
    ...base,
    shop_details: { ...base.shop_details, pickup_scope: "complex" },
  });
  assertEquals(complex.calculation.manualReviewRequired, true);
  assertEquals(
    complex.calculation.manualReasons.includes("custom_booking"),
    true,
  );
});

Deno.test("D66-D70 vacancies reuse page, form, upload and integration rules", () => {
  const normal = price({
    requested_pages: ["home", "jobs"],
    page_scope_details: { jobs: "normal", jobs_application: "none" },
  });
  assertEquals(normal.normalizedScope.standardPages.includes("jobs"), true);

  const dynamic = price({
    requested_pages: ["home", "jobs"],
    page_scope_details: { jobs: "dynamic", jobs_application: "none" },
  });
  assertEquals(
    contribution(dynamic, "complex_page"),
    catalogAmountMinor("complex_page"),
  );

  for (
    const [jobs_application, productId] of [
      ["basic", "basic_quote_form"],
      ["upload", "upload_form"],
      ["complex", "complex_form_workflow"],
    ] as const
  ) {
    const result = price({
      requested_pages: ["home", "jobs"],
      page_scope_details: { jobs: "normal", jobs_application },
    });
    assertEquals(contribution(result, productId), catalogAmountMinor(productId));
  }

  const ats = price({
    requested_pages: ["home", "jobs"],
    page_scope_details: { jobs: "normal", jobs_application: "ats" },
  });
  assertEquals(ats.calculation.manualReviewRequired, true);
  assertEquals(
    ats.calculation.manualReasons.includes("crm_api_erp_automation"),
    true,
  );
});

Deno.test("D19-D21 exact extra-language ladder remains catalog backed", () => {
  for (
    const [count, expected] of [[1, 65_000], [2, 110_000], [
      3,
      155_000,
    ]] as const
  ) {
    const result = price({
      primary_language: "nl",
      additional_languages: ["fr", "en", "de"].slice(0, count),
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
    assertEquals(result.calculation.knownMinimumMinor, 180_000 + expected);
  }
});

Deno.test("D22-D29 copy and media tiers use quantities and external-cost metadata", () => {
  assertEquals(
    price({ content_media_details: { copywriting_scope: "supplied" } })
      .calculation.knownMinimumMinor,
    180_000,
  );
  assertEquals(
    contribution(
      price({ content_media_details: { copywriting_scope: "light" } }),
      "light_copy_optimization",
    ),
    30_000,
  );
  assertEquals(
    contribution(
      price({
        content_media_details: {
          copywriting_scope: "substantial",
          copy_page_count: 3,
        },
      }),
      "substantial_rewrite",
    ),
    52_500,
  );
  assertEquals(
    contribution(
      price({
        content_media_details: { copywriting_scope: "new", copy_page_count: 3 },
      }),
      "new_copy",
    ),
    90_000,
  );
  assertEquals(
    price({ content_media_details: { copywriting_scope: "specialist" } })
      .calculation.manualReviewRequired,
    true,
  );
  assertEquals(
    contribution(
      price({ content_media_details: { image_work_scope: "advanced" } }),
      "advanced_image_editing",
    ),
    15_000,
  );
  assertEquals(
    contribution(
      price({ content_media_details: { image_work_scope: "ai_set" } }),
      "ai_image_set",
    ),
    25_000,
  );
  const stock = price({ content_media_details: { image_work_scope: "stock" } });
  assertEquals(contribution(stock, "stock_selection"), 10_000);
});

Deno.test("D30-D34 branding is one exclusive catalog tier", () => {
  for (
    const [tier, productId] of [
      ["logo", "professional_logo"],
      ["identity", "visual_identity"],
      ["logo_identity", "logo_identity_combo"],
      ["extended", "extended_branding"],
    ] as const
  ) {
    const result = price({ content_media_details: { branding_tier: tier } });
    assertEquals(
      contribution(result, productId),
      catalogAmountMinor(productId),
    );
    assertEquals(
      result.calculation.appliedRules.filter((rule) =>
        [
          "professional_logo",
          "visual_identity",
          "logo_identity_combo",
          "extended_branding",
        ].includes(rule.ruleId)
      ).length,
      1,
    );
    if (tier === "extended") {
      assertEquals(result.calculation.manualReviewRequired, true);
    }
  }
});

Deno.test("D35-D40 SEO, domain and migration products stay additive", () => {
  const seo = price({
    additional_languages: ["fr"],
    seo_details: {
      scope: "launch",
      extra_language_seo: true,
      advanced_language_seo: true,
    },
  });
  assertEquals(contribution(seo, "seo_launch"), 65_000);
  assertEquals(contribution(seo, "seo_extra_language"), 35_000);
  assertEquals(contribution(seo, "advanced_seo_language"), 50_000);
  assertEquals(seo.calculation.manualReviewRequired, true);

  for (
    const [service, productId] of [["dns", "dns_configuration"], [
      "transfer",
      "domain_transfer",
    ], ["migration", "simple_hosting_migration"]] as const
  ) {
    assertEquals(
      contribution(
        price({ hosting_maintenance_details: { domain_service: service } }),
        productId,
      ),
      catalogAmountMinor(productId),
    );
  }
});

Deno.test("D41-D43 recurring Care services never inflate one-time minimum", () => {
  for (
    const [plan, productId, amountMinor] of [["care", "care", 4_900], [
      "care_plus",
      "care_plus",
      9_900,
    ]] as const
  ) {
    const result = price({
      hosting_maintenance_details: { maintenance_plan: plan },
    });
    assertEquals(result.calculation.knownMinimumMinor, 180_000);
    assertEquals(result.recurringServices, [{
      productId,
      amountMinor,
      unit: "month",
    }]);
  }
});

Deno.test("D59 recognized hosting and maintenance evidence remains catalog scope", () => {
  const result = price({
    hosting_status: "no_hosting",
    hosting_support: "advice",
    maintenance_interest: "info_requested",
    hosting_maintenance_details: {
      hosting_support: "advice",
      maintenance_interest: "info_requested",
      domain_service: "new",
      maintenance_plan: "none",
    },
  });

  assertEquals(result.calculation.manualReviewRequired, false);
  assertEquals(
    result.normalizedScope.modules.find((module) =>
      module.id === "hosting_maintenance"
    )?.classification,
    "catalog",
  );
});

Deno.test("D60 unsupported or incoherent hosting evidence remains manual", () => {
  for (
    const input of [
      { hosting_support: "unsupported" },
      { hosting_status: "unknown" },
      {
        hosting_maintenance_details: {
          domain_service: "unsupported",
          maintenance_plan: "none",
        },
      },
      {
        hosting_maintenance_details: {
          domain_service: "existing",
          maintenance_plan: "enterprise",
        },
      },
      {
        maintenance_interest: "no",
        hosting_maintenance_details: {
          domain_service: "existing",
          maintenance_plan: "care",
        },
      },
      {
        hosting_support: "yes",
        hosting_maintenance_details: {
          hosting_support: "no",
          domain_service: "existing",
          maintenance_plan: "none",
        },
      },
    ]
  ) {
    const result = price(input);
    assertEquals(result.calculation.manualReviewRequired, true);
    assertEquals(
      result.normalizedScope.modules.find((module) =>
        module.id === "hosting_maintenance"
      )?.classification,
      "manual",
    );
  }
});

Deno.test("D61 recognized complex migration keeps its catalog manual review", () => {
  const result = price({
    hosting_maintenance_details: {
      domain_service: "complex_migration",
      maintenance_plan: "none",
    },
  });

  assertEquals(
    result.normalizedScope.modules.find((module) =>
      module.id === "hosting_maintenance"
    )?.classification,
    "catalog",
  );
  assertEquals(result.calculation.manualReviewRequired, true);
  assertEquals(
    result.calculation.manualReasons.includes("complex_migration"),
    true,
  );
});

Deno.test("D44-D46 integrations distinguish known from manual scope", () => {
  const result = price({
    newsletter_details: {
      scope: "automation_or_segmentation",
      analytics: "advanced",
      custom_integration: true,
    },
  });
  assertEquals(contribution(result, "advanced_newsletter"), 25_000);
  assertEquals(contribution(result, "advanced_analytics"), 35_000);
  assertEquals(result.calculation.manualReviewRequired, true);
  assertEquals(result.calculation.knownMinimumMinor, 240_000);
});

Deno.test("D51-D52 manual review retains fixed and from known minimums", () => {
  const result = price({
    requested_features: ["search"],
    page_scope_details: { search: "advanced" },
    download_details: { access: "download" },
    newsletter_details: { custom_integration: true },
  });
  assertEquals(result.calculation.knownMinimumMinor, 270_000);
  assertEquals(result.calculation.manualReviewRequired, true);
  assertEquals(result.calculation.containsFromPricing, true);
});

Deno.test("D54-D58 package and bundle double-charge regressions", () => {
  const professional = calculateBudgetGuard({
    selected_package_definition_id: "professional_v2",
    requested_pages: ["blog", "gallery", "reviews"],
    page_scope_details: {
      blog: "normal",
      gallery: "advanced",
      reviews: "live",
    },
  });
  assertEquals(contribution(professional, "blog_news"), 0);
  assertEquals(contribution(professional, "advanced_gallery"), 35_000);
  assertEquals(contribution(professional, "live_reviews"), 15_000);

  const form = price({
    requested_features: ["quote_form"],
    quote_form_details: {
      structure_scope: "basic_single_section",
      file_uploads: true,
    },
  });
  assertEquals(
    form.calculation.appliedRules.filter((rule) =>
      [
        "simple_quote_form",
        "extended_quote_form",
        "other_extended_form",
        "complex_form_workflow",
      ].includes(rule.ruleId)
    ).length,
    1,
  );
});

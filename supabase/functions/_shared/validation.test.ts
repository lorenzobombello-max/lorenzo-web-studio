import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  InputValidationError,
  partitionIntakeData,
  sanitizeAndValidateIntakeData,
  sanitizeAndValidatePricingPreviewInput,
  sanitizeAndValidateSubmitPayload,
} from "./validation.ts";

const basePayload = {
  request_kind: "website" as const,
  name: "Lorenzo Bombello",
  email: "hello@example.com",
  phone: "",
  website_type: "Bedrijfswebsite",
  budget: "EUR 1.500 - EUR 3.000",
  timing: "Binnen 2 tot 3 maanden",
  description: "Een veilige testaanvraag voor een nieuwe website.",
  privacy_consent: true,
  website: "",
};

Deno.test("individual quote strips no hidden business values", () => {
  const result = sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "individual" });
  assertEquals(result.customer_type, "individual");
  assertEquals(result.company, null);
  assertEquals(result.vat_number, null);
  assertEquals(result.billing_email, null);
});

Deno.test("business quote keeps required billing data and optional VAT", () => {
  const result = sanitizeAndValidateSubmitPayload({
    ...basePayload,
    customer_type: "business",
    company: "Voorbeeld BV",
    enterprise_number: "0123.456.749",
    vat_number: "",
    billing_address: "Voorbeeldstraat 10",
    billing_postal_code: "9000",
    billing_city: "Gent",
    billing_country: "Belgie",
    billing_email: "billing@example.com",
  });
  assertEquals(result.enterprise_number, "0123456749");
  assertEquals(result.enterprise_validation_status, "format_valid_not_externally_verified");
  assertEquals(result.vat_number, null);
  assertEquals(result.billing_email, "billing@example.com");
});

Deno.test("legacy quote payload remains compatible", () => {
  const { request_kind: _requestKind, ...legacyPayload } = basePayload;
  const result = sanitizeAndValidateSubmitPayload({ ...legacyPayload, company: "Legacy BV" });
  assertEquals(result.request_kind, "website");
  assertEquals(result.customer_type, null);
  assertEquals(result.company, "Legacy BV");
});

Deno.test("documentenflow request accepts each canonical package without website fields", () => {
  const { website_type: _websiteType, budget: _budget, timing: _timing, ...common } = basePayload;
  for (const sdfPackage of ["start", "groei", "maatwerk"] as const) {
    const result = sanitizeAndValidateSubmitPayload({
      ...common,
      request_kind: "slimme_documentenflow",
      sdf_package: sdfPackage,
      description: "Een veilige testaanvraag voor een slimme documentenflow.",
    });
    assertEquals(result.request_kind, "slimme_documentenflow");
    assertEquals(result.sdf_package, sdfPackage);
    assertEquals(result.website_type, null);
    assertEquals(result.budget, null);
    assertEquals(result.timing, null);
  }
});

Deno.test("documentenflow request rejects fabricated website fields", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, request_kind: "slimme_documentenflow", sdf_package: "start" }),
    InputValidationError,
    "INVALID_CONDITION",
  );
});

Deno.test("documentenflow package identity fails closed", () => {
  const { website_type: _websiteType, budget: _budget, timing: _timing, ...common } = basePayload;
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...common, request_kind: "slimme_documentenflow", sdf_package: "onbekend" as never }),
    InputValidationError,
    "INVALID_OPTION",
  );
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...common, request_kind: "slimme_documentenflow" }),
    InputValidationError,
    "REQUIRED_FIELD",
  );
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, sdf_package: "start" }),
    InputValidationError,
    "INVALID_CONDITION",
  );
});

Deno.test("request kind rejects unknown and malformed values", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, request_kind: "unknown" as never }),
    InputValidationError,
    "INVALID_OPTION",
  );
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, request_kind: 42 as never }),
    InputValidationError,
    "INVALID_TYPE",
  );
});

Deno.test("rejects invalid customer type", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "other" }),
    InputValidationError,
    "INVALID_OPTION",
  );
});

Deno.test("rejects missing required business data", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "business", company: "Voorbeeld BV" }),
    InputValidationError,
    "REQUIRED_FIELD",
  );
});

Deno.test("rejects invalid billing email", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({
      ...basePayload,
      customer_type: "business",
      company: "Voorbeeld BV",
      enterprise_number: "0123.456.749",
      billing_address: "Voorbeeldstraat 10",
      billing_postal_code: "9000",
      billing_city: "Gent",
      billing_country: "Belgie",
      billing_email: "geen-email",
    }),
    InputValidationError,
    "INVALID_FORMAT",
  );
});

Deno.test("rejects script markup and overlong business values", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "business", company: "<script>alert(1)</script>" }),
    InputValidationError,
    "INVALID_FORMAT",
  );
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, company: "x".repeat(141) }),
    InputValidationError,
    "INVALID_LENGTH",
  );
});

Deno.test("rejects non-string identifiers and new fields without customer type", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "business", enterprise_number: 123 } as never),
    InputValidationError,
    "INVALID_TYPE",
  );
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, billing_city: "Gent" }),
    InputValidationError,
    "INVALID_CONDITION",
  );
});

Deno.test("normalizes EU VAT and rejects malformed VAT before external validation", () => {
  const result = sanitizeAndValidateSubmitPayload({
    ...basePayload,
    customer_type: "business",
    company: "Voorbeeld BV",
    enterprise_number: "0123.456.749",
    vat_number: "be 0123.456.749",
    billing_address: "Voorbeeldstraat 10",
    billing_postal_code: "9000",
    billing_city: "Gent",
    billing_country: "Belgie",
  });
  assertEquals(result.vat_number, "BE0123456749");
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...result, vat_number: "geen btw nummer", privacy_consent: true }),
    InputValidationError,
    "INVALID_FORMAT",
  );
});

Deno.test("rejects a Belgian enterprise number with an invalid check digit", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({
      ...basePayload,
      customer_type: "business",
      company: "Voorbeeld BV",
      enterprise_number: "0123.456.789",
      billing_address: "Voorbeeldstraat 10",
      billing_postal_code: "9000",
      billing_city: "Gent",
      billing_country: "Belgie",
    }),
    InputValidationError,
    "INVALID_FORMAT",
  );
});

Deno.test("intake validator accepts and partitions closed raw evidence", () => {
  const result = sanitizeAndValidateIntakeData({
    business_description: "Legacy data",
    primary_language: "nl",
    additional_languages: ["fr", "en"],
    page_scope_details: { blog: "normal", gallery: "complex" },
    quote_form_details: { classification: "extended", file_uploads: false, form_count: 1 },
    multilingual_details: {
      final_translations_supplied: true,
      same_structure: true,
      extensive_seo: false,
      language_specific_integrations: false,
      complex_scope: false,
    },
    download_details: { access: "public" },
    content_media_details: { copywriting_scope: "light", image_work_scope: "standard", paid_stock_handling: false },
    newsletter_details: { scope: "simple_existing_service" },
    hosting_maintenance_details: { hosting_support: "advice", maintenance_interest: "maybe" },
    deadline_details: { commercially_critical: false, hard_deadline: true },
    seo_details: { extensive_services: false },
    budget_update_category: "EUR 3.200 t/m EUR 6.000",
    budget_update_category_scheme: "budget_guard_v1",
    budget_update_category_code: "3200_to_6000_inclusive",
  }, "draft");
  const partitioned = partitionIntakeData(result);
  assertEquals(partitioned.legacyData.business_description, "Legacy data");
  assertEquals(partitioned.legacyData.budget_update_category, "EUR 3.200 t/m EUR 6.000");
  assertEquals(partitioned.evidenceData.primary_language, "nl");
  assertEquals(partitioned.evidenceData.budget_update_category, "EUR 3.200 t/m EUR 6.000");
  assertEquals(partitioned.evidenceData.budget_update_category_code, "3200_to_6000_inclusive");
});

Deno.test("pricing preview validator accepts only closed pricing scope", () => {
  const result = sanitizeAndValidatePricingPreviewInput({
    requested_pages: ["home", "quote_request"],
    requested_features: ["quote_form"],
    quote_form_details: { structure_scope: "basic_single_section" },
    primary_language: "nl",
    additional_languages: ["fr"],
    budget_update_category: "EUR 3.200 t/m EUR 6.000",
    budget_update_category_scheme: "budget_guard_v1",
    budget_update_category_code: "3200_to_6000_inclusive",
  });
  assertEquals(result.requested_pages, ["home", "quote_request"]);
  assertEquals(result.quote_form_details, { structure_scope: "basic_single_section" });
});

Deno.test("package evidence accepts only immutable IDs and partitions as evidence", () => {
  for (const selected_package_definition_id of [
    "starter_v1",
    "professional_v2",
    null,
  ]) {
    const result = sanitizeAndValidatePricingPreviewInput({
      selected_package_definition_id,
    });
    assertEquals(
      result.selected_package_definition_id,
      selected_package_definition_id,
    );
    assertEquals(
      partitionIntakeData(result).evidenceData.selected_package_definition_id,
      selected_package_definition_id,
    );
  }
  for (const selected_package_definition_id of [
    "starter",
    "professional",
    "custom",
    "auto",
    "suggested",
    "professional_v1",
    3200,
    {},
  ]) {
    assertThrows(
      () => sanitizeAndValidatePricingPreviewInput({ selected_package_definition_id }),
      InputValidationError,
    );
  }
});

Deno.test("pricing preview validator rejects pricing output, PII and unknown nested fields", () => {
  for (const field of [
    "calculatedPrice", "knownMinimum", "knownMinimumMinor", "selectedPackage",
    "selectedPackageDefinitionId", "packagePrice", "packageFloor", "packageLimits",
    "includedEntitlements", "packageDiscount",
    "pricingMode", "appliedRuleAmount", "isIncluded", "budgetStatus", "appliedRules",
    "manualReasons", "snapshot", "proof", "integrityMac", "configHash",
  ]) {
    assertThrows(
      () => sanitizeAndValidatePricingPreviewInput({ [field]: "injected" }),
      InputValidationError,
      "PRICING_OUTPUT_NOT_ALLOWED",
    );
  }
  assertThrows(
    () => sanitizeAndValidatePricingPreviewInput({ email: "person@example.test" }),
    InputValidationError,
    "UNKNOWN_FIELD",
  );
  assertThrows(
    () => sanitizeAndValidatePricingPreviewInput({ page_scope_details: { internal: "normal" } }),
    InputValidationError,
    "INVALID_SCHEMA",
  );
});

Deno.test("pricing preview validator rejects partial or incoherent budget evidence", () => {
  assertThrows(
    () => sanitizeAndValidatePricingPreviewInput({ budget_update_category_scheme: "budget_guard_v1" }),
    InputValidationError,
    "INCOHERENT_BUDGET_EVIDENCE",
  );
  assertThrows(
    () => sanitizeAndValidatePricingPreviewInput({
      budget_update_category: "EUR 3.200 t/m EUR 6.000",
      budget_update_category_scheme: "budget_guard_v1",
      budget_update_category_code: "below_1800",
    }),
    InputValidationError,
    "INCOHERENT_BUDGET_EVIDENCE",
  );
});

Deno.test("legacy quote form classification remains coherent with complex signals", () => {
  const cases: Array<[string, Record<string, unknown>]> = [
    ["simple", { classification: "simple", file_uploads: false, form_count: 1 }],
    ["file upload", { classification: "complex", file_uploads: true, form_count: 1 }],
    ["multiple forms", { classification: "complex", file_uploads: false, form_count: 2 }],
    ["database workflow", { classification: "complex", database_workflow: true, form_count: 1 }],
    ["automated processing", { classification: "complex", automated_processing: true, form_count: 1 }],
    ["review approval", { classification: "complex", review_approval: true, form_count: 1 }],
    ["custom logic", { classification: "complex", custom_logic: true, form_count: 1 }],
  ];
  for (const [name, quoteFormDetails] of cases) {
    const result = sanitizeAndValidateIntakeData({ quote_form_details: quoteFormDetails }, "draft");
    assertEquals(result.quote_form_details, quoteFormDetails, name);
  }
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      quote_form_details: { classification: "extended", file_uploads: true, form_count: 1 },
    }, "draft"),
    InputValidationError,
    "INCOHERENT_QUOTE_FORM_EVIDENCE",
  );
});

Deno.test("quote form structure scope accepts only closed raw evidence", () => {
  for (const structureScope of [
    "basic_single_section",
    "extended_standard_structure",
    "unsure_or_other",
  ]) {
    const result = sanitizeAndValidateIntakeData({
      quote_form_details: { structure_scope: structureScope },
    }, "draft");
    assertEquals(result.quote_form_details, { structure_scope: structureScope });
  }

  for (const structureScope of ["unknown", 1, true, [], {}]) {
    assertThrows(
      () => sanitizeAndValidateIntakeData({
        quote_form_details: { structure_scope: structureScope },
      }, "draft"),
      InputValidationError,
    );
  }
});

Deno.test("quote form raw structure and complexity facts remain independent", () => {
  for (const quoteFormDetails of [
    { structure_scope: "basic_single_section", file_uploads: true, form_count: 1 },
    { structure_scope: "basic_single_section", file_uploads: false, form_count: 2 },
    { structure_scope: "extended_standard_structure", custom_logic: true, form_count: 1 },
  ]) {
    const result = sanitizeAndValidateIntakeData({ quote_form_details: quoteFormDetails }, "draft");
    assertEquals(result.quote_form_details, quoteFormDetails);
  }
});

Deno.test("legacy quote form evidence does not synthesize structure scope", () => {
  for (const quoteFormDetails of [{ form_count: 1 }, { classification: "simple", form_count: 1 }]) {
    const result = sanitizeAndValidateIntakeData({ quote_form_details: quoteFormDetails }, "draft");
    assertEquals(result.quote_form_details, quoteFormDetails);
    assertEquals("structure_scope" in (result.quote_form_details as Record<string, unknown>), false);
  }
});

Deno.test("intake validator rejects unknown and malformed evidence", () => {
  assertThrows(
    () => sanitizeAndValidateIntakeData({ unexpected: true }, "draft"),
    InputValidationError,
    "UNKNOWN_FIELD",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({ page_scope_details: { blog: "normal", internal: true } }, "draft"),
    InputValidationError,
    "INVALID_SCHEMA",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({ multilingual_details: { same_structure: "yes" } }, "draft"),
    InputValidationError,
    "INVALID_TYPE",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({ additional_languages: Array(9).fill("nl") }, "draft"),
    InputValidationError,
    "TOO_MANY_ITEMS",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({ primary_language: "x".repeat(36) }, "draft"),
    InputValidationError,
    "INVALID_LENGTH",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({ download_details: { access: null } }, "draft"),
    InputValidationError,
    "INVALID_OPTION",
  );
});

Deno.test("intake validator rejects every authoritative pricing output field", () => {
  for (const field of [
    "knownMinimumMinor", "appliedRules", "manualReviewRequired", "manualReasons",
    "packageAdvice", "budgetEvaluation", "pricingConfigVersion", "pricingConfigHash", "pricingSnapshot",
  ]) {
    assertThrows(
      () => sanitizeAndValidateIntakeData({ [field]: field === "knownMinimumMinor" ? 1 : {} }, "draft"),
      InputValidationError,
      "PRICING_OUTPUT_NOT_ALLOWED",
    );
  }
  for (const field of [
    "snapshotContractVersion", "snapshot_contract_version",
    "evidenceProvenance", "outsideBudgetWishes",
  ]) {
    assertThrows(
      () => sanitizeAndValidateIntakeData({ [field]: {} }, "draft"),
      InputValidationError,
      "UNKNOWN_FIELD",
    );
  }
});

Deno.test("intake validator preserves all historical Budget Guard v1 category triples", () => {
  for (const [code, label] of [
    ["below_1800", "Minder dan EUR 1.800"],
    ["1800_to_below_3200", "EUR 1.800 tot minder dan EUR 3.200"],
    ["3200_to_6000_inclusive", "EUR 3.200 t/m EUR 6.000"],
    ["above_6000", "Meer dan EUR 6.000"],
  ]) {
    const result = sanitizeAndValidateIntakeData({
      budget_update_category: label,
      budget_update_category_scheme: "budget_guard_v1",
      budget_update_category_code: code,
    }, "draft");
    assertEquals(result.budget_update_category_code, code);
  }
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      budget_update_category: "Meer dan EUR 6.000",
      budget_update_category_scheme: "budget_guard_v1",
      budget_update_category_code: "3200_to_6000_inclusive",
    }, "draft"),
    InputValidationError,
    "INCOHERENT_BUDGET_EVIDENCE",
  );
  for (const mode of ["draft", "submit"] as const) {
    assertThrows(
      () => sanitizeAndValidateIntakeData({
        budget_update_category: "Meer dan EUR 6.000",
        budget_update_category_scheme: null,
        budget_update_category_code: null,
      }, mode),
      InputValidationError,
      "INCOHERENT_BUDGET_EVIDENCE",
    );
  }
});

Deno.test("legacy intake payload remains valid without evidence conversion", () => {
  const result = sanitizeAndValidateIntakeData({
    budget_update_category: "EUR 1.500 - EUR 3.000",
    languages: ["nl"],
  }, "draft");
  assertEquals(result.budget_update_category, "EUR 1.500 - EUR 3.000");
  assertEquals(partitionIntakeData(result).evidenceData, {});
});

Deno.test("shared above-6000 label remains legacy without restored scheme and code", () => {
  const result = sanitizeAndValidateIntakeData({
    budget_update_category: "Meer dan EUR 6.000",
    languages: ["nl"],
  }, "draft");
  const partitioned = partitionIntakeData(result);
  assertEquals(partitioned.legacyData.budget_update_category, "Meer dan EUR 6.000");
  assertEquals(partitioned.evidenceData, {});
});

Deno.test("D47-D48 Phase D evidence validates and partitions through existing detail objects", () => {
  const evidence = {
    shop_required: true,
    shop_details: {
      approx_product_count: 20,
      categories: true,
      online_payments: true,
      shipping: true,
      pickup: false,
      existing_catalog: true,
      complex_product_count: 2,
      payment_provider_count: 2,
      shipping_scope: "complex",
      customer_accounts: true,
      catalog_import: true,
      erp_api: true,
    },
    booking_required: true,
    booking_details: {
      type: "appointments",
      existing_system: false,
      existing_system_name: null,
      calendar_integration: false,
      tier: "advanced",
    },
    page_scope_details: {
      portfolio: "dynamic",
      gallery: "advanced",
      reviews: "live",
      search: "advanced",
    },
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
    download_details: { access: "document_flow" },
    content_media_details: {
      copywriting_scope: "new",
      copy_page_count: 4,
      image_work_scope: "stock",
      branding_tier: "logo_identity",
    },
    hosting_maintenance_details: {
      hosting_support: "yes",
      maintenance_interest: "yes",
      domain_service: "transfer",
      maintenance_plan: "care_plus",
    },
    seo_details: {
      scope: "launch",
      extra_language_seo: true,
      advanced_language_seo: true,
    },
    newsletter_details: {
      scope: "automation_or_segmentation",
      analytics: "advanced",
      custom_integration: true,
    },
  };
  const result = sanitizeAndValidateIntakeData(evidence, "draft");
  assertEquals(result, evidence);
  const { evidenceData } = partitionIntakeData(result);
  for (const field of [
    "page_scope_details", "multilingual_details", "download_details",
    "content_media_details", "hosting_maintenance_details", "seo_details",
    "newsletter_details",
  ]) assertEquals(evidenceData[field], evidence[field as keyof typeof evidence]);
});

Deno.test("D49 Phase D enums and counts fail closed", () => {
  const invalidCases: Array<[string, unknown]> = [
    ["booking_details", {
      type: "appointments", existing_system: false, existing_system_name: null,
      calendar_integration: false, tier: "premium",
    }],
    ["page_scope_details", { search: "enterprise" }],
    ["download_details", { access: "private" }],
    ["content_media_details", { copywriting_scope: "generated" }],
    ["content_media_details", { copywriting_scope: "new", copy_page_count: 0 }],
    ["content_media_details", { branding_tier: "logo_and_more" }],
    ["hosting_maintenance_details", { maintenance_plan: "seo_care" }],
    ["shop_details", {
      approx_product_count: 10, categories: true, online_payments: true,
      shipping: true, pickup: false, existing_catalog: false,
      complex_product_count: -1, payment_provider_count: 1,
      shipping_scope: "standard", customer_accounts: false,
      catalog_import: false, erp_api: false,
    }],
  ];
  for (const [field, value] of invalidCases) {
    assertThrows(
      () => sanitizeAndValidateIntakeData({ [field]: value }, "draft"),
      InputValidationError,
    );
  }
});

Deno.test("D50 Phase D evidence dependencies reject incompatible states", () => {
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      booking_required: false,
      booking_details: {
        type: "appointments", existing_system: false, existing_system_name: null,
        calendar_integration: false, tier: "widget",
      },
    }, "draft"),
    InputValidationError,
    "INVALID_CONDITION",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      multilingual_details: {
        final_translations_supplied: true, same_structure: true,
        translation_required: false, seo_per_language: true,
        advanced_seo_research: true, language_specific_integrations: false,
        complex_scope: false,
      },
      additional_languages: [],
    }, "draft"),
    InputValidationError,
    "INVALID_CONDITION",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      seo_details: {
        scope: "included", extra_language_seo: false,
        advanced_language_seo: true,
      },
    }, "draft"),
    InputValidationError,
    "INVALID_CONDITION",
  );
});

Deno.test("pickup scope is closed and coherent with legacy pickup evidence", () => {
  const shopDetails = {
    approx_product_count: 15,
    categories: true,
    online_payments: true,
    shipping: true,
    pickup: true,
    existing_catalog: false,
    complex_product_count: 0,
    payment_provider_count: 1,
    shipping_scope: "standard",
    customer_accounts: false,
    catalog_import: false,
    erp_api: false,
  };
  for (const pickup_scope of ["simple", "scheduled", "complex"]) {
    const result = sanitizeAndValidateIntakeData({
      shop_required: true,
      shop_details: { ...shopDetails, pickup_scope },
    }, "draft");
    assertEquals(
      (result.shop_details as Record<string, unknown>).pickup_scope,
      pickup_scope,
    );
  }
  const none = sanitizeAndValidateIntakeData({
    shop_required: true,
    shop_details: { ...shopDetails, pickup: false, pickup_scope: "none" },
  }, "draft");
  assertEquals(
    (none.shop_details as Record<string, unknown>).pickup_scope,
    "none",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      shop_required: true,
      shop_details: { ...shopDetails, pickup_scope: "unsupported" },
    }, "draft"),
    InputValidationError,
    "INVALID_OPTION",
  );
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      shop_required: true,
      shop_details: { ...shopDetails, pickup: false, pickup_scope: "simple" },
    }, "draft"),
    InputValidationError,
    "INVALID_CONDITION",
  );
});

Deno.test("vacancy page and application evidence use closed existing scopes", () => {
  for (
    const jobs_application of ["none", "basic", "upload", "complex", "ats"]
  ) {
    const result = sanitizeAndValidateIntakeData({
      page_scope_details: { jobs: "dynamic", jobs_application },
    }, "draft");
    assertEquals(
      (result.page_scope_details as Record<string, unknown>).jobs_application,
      jobs_application,
    );
  }
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      page_scope_details: { jobs: "dynamic", jobs_application: "invented" },
    }, "draft"),
    InputValidationError,
    "INVALID_OPTION",
  );
});

Deno.test("intake validator enforces current Budget Guard v2 and rejects mixed schemes", () => {
  for (const [code, label] of [
    ["below_1800", "Minder dan EUR 1.800"],
    ["1800_to_below_3500", "EUR 1.800 tot minder dan EUR 3.500"],
    ["3500_to_6000_inclusive", "EUR 3.500 t/m EUR 6.000"],
    ["above_6000", "Meer dan EUR 6.000"],
  ]) {
    const result = sanitizeAndValidateIntakeData({
      budget_update_category: label,
      budget_update_category_scheme: "budget_guard_v2",
      budget_update_category_code: code,
    }, "draft");
    assertEquals(result.budget_update_category_code, code);
  }
  assertThrows(
    () => sanitizeAndValidateIntakeData({
      budget_update_category: "EUR 1.800 tot minder dan EUR 3.200",
      budget_update_category_scheme: "budget_guard_v2",
      budget_update_category_code: "1800_to_below_3200",
    }, "draft"),
    InputValidationError,
    "INCOHERENT_BUDGET_EVIDENCE",
  );
});

Deno.test("pricing preview rejects contradictory translation evidence", () => {
  assertThrows(
    () => sanitizeAndValidatePricingPreviewInput({
      primary_language: "nl",
      additional_languages: ["fr"],
      multilingual_details: {
        final_translations_supplied: true,
        same_structure: true,
        translation_required: true,
        seo_per_language: false,
        advanced_seo_research: false,
        language_specific_integrations: false,
        complex_scope: false,
      },
    }),
    InputValidationError,
    "INVALID_CONDITION",
  );
});

Deno.test("pricing preview rejects cross-step shop and booking contradictions", () => {
  for (const input of [
    { requested_features: ["shop"], shop_required: false },
    { website_goals: ["sell_products"], shop_required: false },
    { requested_features: ["appointments"], booking_required: false },
    { requested_pages: ["reservations"], booking_required: false },
  ]) {
    assertThrows(
      () => sanitizeAndValidatePricingPreviewInput(input),
      InputValidationError,
      "INVALID_CONDITION",
    );
  }
});
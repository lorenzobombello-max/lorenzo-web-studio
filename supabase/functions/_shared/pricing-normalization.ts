export type CanonicalModuleId =
  | "shop"
  | "booking"
  | "forms"
  | "multilingual"
  | "content_media"
  | "hosting_maintenance"
  | "seo";

export interface RawPricingScope {
  selected_package_definition_id?: unknown;
  requested_pages?: unknown;
  requested_features?: unknown;
  website_goals?: unknown;
  shop_required?: unknown;
  shop_details?: unknown;
  booking_required?: unknown;
  booking_details?: unknown;
  page_scope_details?: unknown;
  quote_form_details?: unknown;
  primary_language?: unknown;
  additional_languages?: unknown;
  languages?: unknown;
  multilingual_details?: unknown;
  content_status?: unknown;
  image_status?: unknown;
  image_support?: unknown;
  content_media_details?: unknown;
  download_details?: unknown;
  newsletter_details?: unknown;
  domain_status?: unknown;
  hosting_status?: unknown;
  hosting_support?: unknown;
  maintenance_interest?: unknown;
  hosting_maintenance_details?: unknown;
  seo_priority?: unknown;
  seo_details?: unknown;
  brand_status?: unknown;
  logo_status?: unknown;
  integrations?: unknown;
  deadline_details?: unknown;
}

export interface NormalizedCatalogSelection {
  productId: string;
  quantity: number;
}

export interface NormalizedRecurringService {
  productId: "care" | "care_plus";
}

export interface NormalizedModule {
  id: CanonicalModuleId;
  classification: string;
  evidence: string[];
}

export interface NormalizedPricingScope {
  standardPages: string[];
  standardPageCount: number;
  primaryLanguage: string | null;
  additionalLanguages: string[];
  unknownLanguages: string[];
  modules: NormalizedModule[];
  manualComponents: string[];
  catalogSelections?: NormalizedCatalogSelection[];
  recurringServices?: NormalizedRecurringService[];
}

const UNCONDITIONAL_STANDARD_PAGES = new Set([
  "home",
  "about",
  "services",
  "portfolio",
  "team",
  "pricing",
  "faq",
  "contact",
]);
const CONDITIONAL_STANDARD_PAGES = new Set([
  "reviews",
  "blog",
  "jobs",
  "gallery",
]);
const KNOWN_PAGE_IDS = new Set([
  ...UNCONDITIONAL_STANDARD_PAGES,
  ...CONDITIONAL_STANDARD_PAGES,
  "products",
  "quote_request",
  "reservations",
  "shop",
  "other",
]);
const COMMERCIAL_LANGUAGE_ALIASES: Readonly<Record<string, string>> = {
  nl: "nl",
  nederlands: "nl",
  dutch: "nl",
  fr: "fr",
  frans: "fr",
  francais: "fr",
  french: "fr",
  en: "en",
  engels: "en",
  english: "en",
  de: "de",
  duits: "de",
  deutsch: "de",
  german: "de",
  it: "it",
  italiaans: "it",
  italiano: "it",
  italian: "it",
  es: "es",
  spaans: "es",
  espanol: "es",
  spanish: "es",
};

interface NormalizedLanguageValue {
  canonical: string | null;
  normalizedInput: string;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value.filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean),
    ),
  ];
}

function normalizedLanguage(value: unknown): NormalizedLanguageValue | null {
  if (typeof value !== "string") return null;
  const normalizedInput = value.normalize("NFKC").trim().toLowerCase()
    .replace(/_/g, "-");
  if (!normalizedInput) return null;
  const comparable = normalizedInput.normalize("NFKD").replace(/\p{M}/gu, "");
  const baseLanguage = comparable.split("-", 1)[0];
  return {
    canonical: COMMERCIAL_LANGUAGE_ALIASES[baseLanguage] ?? null,
    normalizedInput,
  };
}

function normalizedLanguages(value: unknown): NormalizedLanguageValue[] {
  return stringArray(value).map(normalizedLanguage)
    .filter((language): language is NormalizedLanguageValue =>
      language !== null
    );
}

function objectValue(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function hasObjectData(value: unknown): boolean {
  return Object.keys(objectValue(value)).length > 0;
}

function addEvidence(
  evidence: Set<string>,
  condition: boolean,
  value: string,
): void {
  if (condition) evidence.add(value);
}

export function normalizePricingScope(
  input: RawPricingScope,
): NormalizedPricingScope {
  const pages = stringArray(input.requested_pages);
  const features = new Set(stringArray(input.requested_features));
  const goals = new Set(stringArray(input.website_goals));
  const manualComponents = new Set<string>();
  const modules: NormalizedModule[] = [];
  const catalogSelections = new Map<string, number>();
  const recurringServices: NormalizedRecurringService[] = [];
  let pickupScope: unknown;
  const selectCatalogProduct = (productId: string, quantity = 1) => {
    if (quantity > 0) catalogSelections.set(productId, quantity);
  };

  const shopEvidence = new Set<string>();
  addEvidence(shopEvidence, pages.includes("shop"), "requested_pages.shop");
  addEvidence(shopEvidence, features.has("shop"), "requested_features.shop");
  addEvidence(
    shopEvidence,
    features.has("online_payment"),
    "requested_features.online_payment",
  );
  addEvidence(
    shopEvidence,
    goals.has("sell_products"),
    "website_goals.sell_products",
  );
  addEvidence(shopEvidence, input.shop_required === true, "shop_required");
  addEvidence(shopEvidence, hasObjectData(input.shop_details), "shop_details");
  if (shopEvidence.size) {
    const shopDetails = objectValue(input.shop_details);
    pickupScope = shopDetails.pickup_scope;
    const simpleProductCount = typeof shopDetails.approx_product_count === "number"
      ? shopDetails.approx_product_count
      : 0;
    const extraSimpleProducts = Math.max(0, simpleProductCount - 15);
    if (extraSimpleProducts) {
      selectCatalogProduct("extra_simple_products", extraSimpleProducts);
    }
    if (typeof shopDetails.complex_product_count === "number") {
      selectCatalogProduct("complex_product", shopDetails.complex_product_count);
    }
    if (typeof shopDetails.payment_provider_count === "number") {
      selectCatalogProduct(
        "extra_payment_provider",
        Math.max(0, shopDetails.payment_provider_count - 1),
      );
    }
    if (shopDetails.shipping_scope === "complex") {
      selectCatalogProduct("complex_shipping");
    }
    if (shopDetails.customer_accounts === true) {
      selectCatalogProduct("webshop_accounts");
    }
    if (shopDetails.catalog_import === true) selectCatalogProduct("catalog_import");
    if (shopDetails.erp_api === true) selectCatalogProduct("erp_inventory_api");
    modules.push({
      id: "shop",
      classification: [
          "complex_product_count", "payment_provider_count", "shipping_scope",
          "customer_accounts", "catalog_import", "erp_api",
        ].some((key) => key in shopDetails)
        ? "catalog"
        : "manual",
      evidence: [...shopEvidence],
    });
  }

  const bookingEvidence = new Set<string>();
  addEvidence(
    bookingEvidence,
    pages.includes("reservations"),
    "requested_pages.reservations",
  );
  for (const value of ["appointments", "reservations"]) {
    addEvidence(
      bookingEvidence,
      features.has(value),
      `requested_features.${value}`,
    );
    addEvidence(bookingEvidence, goals.has(value), `website_goals.${value}`);
  }
  addEvidence(
    bookingEvidence,
    input.booking_required === true,
    "booking_required",
  );
  addEvidence(
    bookingEvidence,
    hasObjectData(input.booking_details),
    "booking_details",
  );
  if (bookingEvidence.size) {
    const bookingDetails = objectValue(input.booking_details);
    const bookingTier = bookingDetails.tier;
    if (bookingTier === "widget") selectCatalogProduct("booking_widget");
    else if (bookingTier === "advanced") selectCatalogProduct("advanced_booking");
    else if (bookingTier === "custom") selectCatalogProduct("custom_booking");
    const simple = bookingDetails.existing_system === false &&
      bookingDetails.calendar_integration === false;
    modules.push({
      id: "booking",
      classification: typeof bookingTier === "string"
        ? `catalog:${bookingTier}`
        : simple
        ? "simple"
        : "manual",
      evidence: [...bookingEvidence],
    });
  }
  if (pickupScope === "scheduled" && bookingEvidence.size === 0) {
    selectCatalogProduct("booking_widget");
  } else if (pickupScope === "complex") {
    selectCatalogProduct("custom_booking");
  }

  const standardPages: string[] = [];
  const pageScopes = objectValue(input.page_scope_details);
  if (pageScopes.portfolio === "dynamic") {
    selectCatalogProduct("dynamic_portfolio");
  }
  const searchTier = pageScopes.search;
  if (searchTier === "basic") selectCatalogProduct("site_search");
  else if (searchTier === "advanced") selectCatalogProduct("advanced_search");
  for (const page of pages) {
    if (UNCONDITIONAL_STANDARD_PAGES.has(page)) {
      standardPages.push(page);
    } else if (page === "products") {
      if (!shopEvidence.size) standardPages.push(page);
    } else if (CONDITIONAL_STANDARD_PAGES.has(page)) {
      if (pageScopes[page] === "normal") standardPages.push(page);
      else if (
        page === "jobs" &&
        (pageScopes[page] === "dynamic" || pageScopes[page] === "complex")
      ) {
        selectCatalogProduct("complex_page");
      }
      else if (page === "gallery" && pageScopes[page] === "advanced") {
        standardPages.push(page);
        selectCatalogProduct("advanced_gallery");
      } else if (page === "reviews" && pageScopes[page] === "live") {
        standardPages.push(page);
        selectCatalogProduct("live_reviews");
      }
      else manualComponents.add(`complex_${page}_scope`);
    } else if (page === "other") {
      manualComponents.add("other_page_scope");
    } else if (!KNOWN_PAGE_IDS.has(page)) {
      manualComponents.add("unknown_page_scope");
    }
  }
  if (pages.includes("jobs")) {
    const jobsApplication = pageScopes.jobs_application;
    if (jobsApplication === "basic") {
      selectCatalogProduct("basic_quote_form");
    } else if (jobsApplication === "upload") {
      selectCatalogProduct("upload_form");
    } else if (jobsApplication === "complex") {
      selectCatalogProduct("complex_form_workflow");
    } else if (jobsApplication === "ats") {
      selectCatalogProduct("crm_api_erp_automation");
    } else if (jobsApplication != null && jobsApplication !== "none") {
      manualComponents.add("complex_jobs_scope");
    }
  }

  const formDetails = objectValue(input.quote_form_details);
  const hasComplexFormSignals = formDetails.database_workflow === true ||
    formDetails.automated_processing === true ||
    formDetails.review_approval === true ||
    formDetails.custom_logic === true ||
    (typeof formDetails.form_count === "number" && formDetails.form_count > 1);
  const quoteEvidence = pages.includes("quote_request") ||
    features.has("quote_form") || goals.has("quote_requests");
  const contactEvidence = features.has("contact_form") ||
    goals.has("contact_requests") || goals.has("generate_leads");
  if (quoteEvidence || contactEvidence) {
    const evidence = new Set<string>();
    addEvidence(
      evidence,
      pages.includes("quote_request"),
      "requested_pages.quote_request",
    );
    addEvidence(
      evidence,
      features.has("quote_form"),
      "requested_features.quote_form",
    );
    addEvidence(
      evidence,
      goals.has("quote_requests"),
      "website_goals.quote_requests",
    );
    addEvidence(evidence, contactEvidence, "contact_form_intent");
    const classification = quoteEvidence
      ? hasComplexFormSignals
      ? "complex"
      : formDetails.file_uploads === true
      ? "upload"
        : formDetails.structure_scope === "basic_single_section"
        ? "simple"
        : formDetails.structure_scope === "extended_standard_structure"
        ? "extended"
        : "manual"
      : "contact";
    modules.push({ id: "forms", classification, evidence: [...evidence] });
  }

  const legacyLanguages = normalizedLanguages(input.languages);
  const explicitPrimary = normalizedLanguage(input.primary_language);
  const primaryLanguage = explicitPrimary?.canonical ??
    legacyLanguages[0]?.canonical ?? null;
  const additionalLanguageValues = [
    ...normalizedLanguages(input.additional_languages),
    ...(explicitPrimary ? legacyLanguages : legacyLanguages.slice(1)),
  ];
  const additionalLanguages = [
    ...new Set(
      additionalLanguageValues
        .map((language) => language.canonical)
        .filter((language): language is string =>
          language !== null && language !== primaryLanguage
        ),
    ),
  ];
  const unknownLanguages = [
    ...new Set(
      [
        explicitPrimary,
        ...normalizedLanguages(input.additional_languages),
        ...legacyLanguages,
      ]
        .filter((language): language is NormalizedLanguageValue =>
          language !== null && language.canonical === null
        )
        .map((language) => language.normalizedInput),
    ),
  ];
  if (additionalLanguages.length || unknownLanguages.length) {
    const details = objectValue(input.multilingual_details);
    const hasPhaseDLanguageEvidence =
      typeof details.translation_required === "boolean" ||
      typeof details.seo_per_language === "boolean" ||
      typeof details.advanced_seo_research === "boolean";
    const normal = primaryLanguage !== null && unknownLanguages.length === 0 &&
      details.final_translations_supplied === true &&
      details.same_structure === true &&
      (hasPhaseDLanguageEvidence || details.extensive_seo === false) &&
      details.language_specific_integrations === false &&
      details.complex_scope === false;
    if (hasPhaseDLanguageEvidence && normal) {
      selectCatalogProduct("first_extra_language");
      if (additionalLanguages.length > 1) {
        selectCatalogProduct("second_extra_language");
      }
      if (additionalLanguages.length > 2) {
        selectCatalogProduct(
          "subsequent_extra_language",
          additionalLanguages.length - 2,
        );
      }
    }
    if (details.translation_required === true) selectCatalogProduct("translation");
    if (details.same_structure === false) {
      selectCatalogProduct("alternative_language_structure");
    }
    modules.push({
      id: "multilingual",
      classification: hasPhaseDLanguageEvidence && normal
        ? "catalog"
        : normal
        ? "normal"
        : "manual",
      evidence: [
        ...(additionalLanguages.length ? ["additional_languages"] : []),
        ...(unknownLanguages.length ? ["unknown_languages"] : []),
        "multilingual_details",
      ],
    });
  }

  const imageSupport = new Set(stringArray(input.image_support));
  const contentDetails = objectValue(input.content_media_details);
  const downloadDetails = objectValue(input.download_details);
  const newsletterDetails = objectValue(input.newsletter_details);
  if (imageSupport.has("professional_photography")) {
    manualComponents.add("professional_photography");
  }
  if (features.has("search") && searchTier == null) {
    manualComponents.add("unresolved_search");
  }
  if (
    downloadDetails.access === "secured" || downloadDetails.access === "both"
  ) manualComponents.add("secured_downloads");
  if (downloadDetails.access === "download") selectCatalogProduct("secure_download");
  else if (downloadDetails.access === "document_flow") {
    selectCatalogProduct("professional_document_flow");
  } else if (downloadDetails.access === "portal") {
    selectCatalogProduct("customer_portal");
  }
  const copyPageCount = typeof contentDetails.copy_page_count === "number"
    ? contentDetails.copy_page_count
    : 1;
  if (contentDetails.copywriting_scope === "light") {
    selectCatalogProduct("light_copy_optimization");
  } else if (contentDetails.copywriting_scope === "substantial") {
    selectCatalogProduct("substantial_rewrite", copyPageCount);
  } else if (contentDetails.copywriting_scope === "new") {
    selectCatalogProduct("new_copy", copyPageCount);
  } else if (contentDetails.copywriting_scope === "specialist") {
    selectCatalogProduct("specialist_copy");
  }
  if (contentDetails.image_work_scope === "advanced") {
    selectCatalogProduct("advanced_image_editing");
  } else if (contentDetails.image_work_scope === "ai_set") {
    selectCatalogProduct("ai_image_set");
  } else if (contentDetails.image_work_scope === "stock") {
    selectCatalogProduct("stock_selection");
  } else if (contentDetails.image_work_scope === "photography") {
    selectCatalogProduct("photography");
  }
  const brandingTier = contentDetails.branding_tier;
  const brandingProducts: Record<string, string> = {
    logo: "professional_logo",
    identity: "visual_identity",
    logo_identity: "logo_identity_combo",
    extended: "extended_branding",
  };
  if (typeof brandingTier === "string" && brandingProducts[brandingTier]) {
    selectCatalogProduct(brandingProducts[brandingTier]);
  }
  if (
    newsletterDetails.scope &&
    newsletterDetails.scope !== "simple_existing_service"
  ) manualComponents.add("newsletter_manual");
  const contentEvidence =
    ["gallery", "reviews", "downloads", "newsletter"].some((value) =>
      features.has(value)
    ) ||
    imageSupport.size > 0 || input.content_status != null ||
    input.image_status != null ||
    hasObjectData(input.content_media_details) ||
    hasObjectData(input.download_details) ||
    hasObjectData(input.newsletter_details);
  if (contentEvidence) {
    const contentManual = [...manualComponents].some((component) =>
      [
        "professional_photography",
        "secured_downloads",
        "substantial_copywriting",
        "exceptional_image_work",
        "paid_stock_handling",
        "newsletter_manual",
        "complex_gallery_scope",
        "complex_reviews_scope",
        "complex_blog_scope",
      ].includes(component)
    );
    const hasCatalogContentEvidence = [
      "supplied", "light", "substantial", "new", "specialist",
    ].includes(String(contentDetails.copywriting_scope)) ||
      ["advanced", "ai_set", "stock", "photography"].includes(
        String(contentDetails.image_work_scope),
      ) || typeof brandingTier === "string";
    modules.push({
      id: "content_media",
      classification: hasCatalogContentEvidence
        ? "catalog"
        : contentManual
        ? "manual"
        : "included",
      evidence: ["content_media"],
    });
  }
  if (features.has("other") || features.has("unsure")) {
    manualComponents.add("unknown_feature_scope");
  }
  if (
    input.content_status === "unknown" || input.image_status === "unknown" ||
    imageSupport.has("unsure")
  ) manualComponents.add("indeterminate_normal_scope");

  const hostingDetails = objectValue(input.hosting_maintenance_details);
  const domainDetails = hostingDetails;
  const domainProducts: Record<string, string> = {
    dns: "dns_configuration",
    transfer: "domain_transfer",
    migration: "simple_hosting_migration",
    complex_dns_mail: "complex_dns_mail_migration",
    complex_migration: "complex_migration",
  };
  if (
    typeof domainDetails.domain_service === "string" &&
    domainProducts[domainDetails.domain_service]
  ) {
    selectCatalogProduct(domainProducts[domainDetails.domain_service]);
  }
  if (hostingDetails.maintenance_plan === "care") {
    recurringServices.push({ productId: "care" });
  } else if (hostingDetails.maintenance_plan === "care_plus") {
    recurringServices.push({ productId: "care_plus" });
  }
  const hostingEvidence = input.hosting_status != null ||
    input.hosting_support != null ||
    input.maintenance_interest != null ||
    hasObjectData(hostingDetails);
  if (hostingEvidence) {
    const recognizedValues: Record<string, Set<unknown>> = {
      hosting_status: new Set([undefined, null, "has_hosting", "no_hosting"]),
      hosting_support: new Set([undefined, null, "yes", "no", "advice"]),
      maintenance_interest: new Set([
        undefined,
        null,
        "yes",
        "no",
        "maybe",
        "info_requested",
      ]),
      domain_service: new Set([
        undefined,
        null,
        "existing",
        "new",
        ...Object.keys(domainProducts),
      ]),
      maintenance_plan: new Set([undefined, null, "none", "care", "care_plus"]),
    };
    const unsupportedEvidence =
      !recognizedValues.hosting_status.has(input.hosting_status) ||
      !recognizedValues.hosting_support.has(input.hosting_support) ||
      !recognizedValues.maintenance_interest.has(input.maintenance_interest) ||
      !recognizedValues.hosting_support.has(hostingDetails.hosting_support) ||
      !recognizedValues.maintenance_interest.has(
        hostingDetails.maintenance_interest,
      ) ||
      !recognizedValues.domain_service.has(hostingDetails.domain_service) ||
      !recognizedValues.maintenance_plan.has(hostingDetails.maintenance_plan);
    const maintenanceInterest = hostingDetails.maintenance_interest ??
      input.maintenance_interest;
    const incoherentEvidence =
      (maintenanceInterest === "no" &&
        (hostingDetails.maintenance_plan === "care" ||
          hostingDetails.maintenance_plan === "care_plus")) ||
      (input.hosting_support != null &&
        hostingDetails.hosting_support != null &&
        input.hosting_support !== hostingDetails.hosting_support) ||
      (input.maintenance_interest != null &&
        hostingDetails.maintenance_interest != null &&
        input.maintenance_interest !== hostingDetails.maintenance_interest);
    modules.push({
      id: "hosting_maintenance",
      classification: unsupportedEvidence || incoherentEvidence
        ? "manual"
        : "catalog",
      evidence: ["hosting_maintenance"],
    });
  }

  const seoDetails = objectValue(input.seo_details);
  if (input.seo_priority != null || hasObjectData(seoDetails)) {
    const extensive = seoDetails.extensive_services === true ||
      seoDetails.scope === "launch";
    if (seoDetails.scope === "launch") selectCatalogProduct("seo_launch");
    else if (seoDetails.scope === "complex") selectCatalogProduct("complex_seo");
    if (seoDetails.extra_language_seo === true) {
      selectCatalogProduct("seo_extra_language");
    }
    if (seoDetails.advanced_language_seo === true) {
      selectCatalogProduct("advanced_seo_language");
    }
    modules.push({
      id: "seo",
      classification: seoDetails.scope != null
        ? "catalog"
        : extensive
        ? "additional"
        : "included",
      evidence: ["seo"],
    });
  }

  if (features.has("customer_login")) manualComponents.add("customer_login");
  if (stringArray(input.integrations).length) {
    manualComponents.add("external_integration");
  }
  const integrationDetails = newsletterDetails;
  if (integrationDetails.analytics === "advanced") {
    selectCatalogProduct("advanced_analytics");
  }
  if (integrationDetails.custom_integration === true) {
    selectCatalogProduct("crm_api_erp_automation");
  }
  const normalized: NormalizedPricingScope = {
    standardPages: [...new Set(standardPages)],
    standardPageCount: new Set(standardPages).size,
    primaryLanguage,
    additionalLanguages,
    unknownLanguages,
    modules,
    manualComponents: [...manualComponents],
  };
  if (catalogSelections.size) {
    normalized.catalogSelections = [...catalogSelections].map(
      ([productId, quantity]) => ({ productId, quantity }),
    );
  }
  if (recurringServices.length) normalized.recurringServices = recurringServices;
  return normalized;
}

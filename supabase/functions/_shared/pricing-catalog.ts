export const CATALOG_VERSION = "2026-08-12-v1" as const;

export type CatalogPricingMode = "INCLUDED" | "FIXED" | "FROM" | "MANUAL";
export type CatalogUnit =
  | "item"
  | "page"
  | "language"
  | "month"
  | "hour"
  | "percentage"
  | "batch"
  | "product"
  | "project";
export type CatalogBilling = "ONE_TIME" | "RECURRING" | "EXTERNAL";
export type CatalogVisibility = "CUSTOMER" | "INTERNAL";
export type CatalogManualCategory =
  | "SCOPE"
  | "TECHNICAL"
  | "CONTENT"
  | "EXTERNAL_PARTNER"
  | "INTEGRATION";

export type CatalogPricing =
  | { mode: "INCLUDED"; unit?: CatalogUnit }
  | {
    mode: "FIXED";
    amountMinor: number;
    unit: CatalogUnit;
    minimumChargeMinor?: number;
  }
  | {
    mode: "FROM";
    amountMinor: number;
    unit: CatalogUnit;
    minimumChargeMinor?: number;
  }
  | { mode: "FROM"; minimumPercentage: number; unit: "percentage" }
  | { mode: "MANUAL"; unit?: CatalogUnit };

export interface CatalogProduct {
  id: string;
  label: string;
  category: string;
  pricing: CatalogPricing;
  billing: CatalogBilling;
  visibility: CatalogVisibility;
  dependencies: readonly string[];
  requiresOneOf?: readonly string[];
  alternativeGroup?: string;
  consumesAllowanceFor?: string;
  manualReview?: {
    category: CatalogManualCategory;
    reason: string;
  };
  externalCost?: string;
  validityMonths?: number;
}

type ProductOptions = Partial<
  Omit<CatalogProduct, "id" | "label" | "category" | "pricing">
>;

function baseProduct(
  id: string,
  label: string,
  category: string,
  pricing: CatalogPricing,
  options: ProductOptions = {},
): CatalogProduct {
  return {
    id,
    label,
    category,
    pricing,
    billing: options.billing ?? "ONE_TIME",
    visibility: options.visibility ?? "CUSTOMER",
    dependencies: options.dependencies ?? [],
    ...(options.requiresOneOf ? { requiresOneOf: options.requiresOneOf } : {}),
    ...(options.alternativeGroup
      ? { alternativeGroup: options.alternativeGroup }
      : {}),
    ...(options.consumesAllowanceFor
      ? { consumesAllowanceFor: options.consumesAllowanceFor }
      : {}),
    ...(options.manualReview ? { manualReview: options.manualReview } : {}),
    ...(options.externalCost ? { externalCost: options.externalCost } : {}),
    ...(options.validityMonths
      ? { validityMonths: options.validityMonths }
      : {}),
  };
}

const included = (
  id: string,
  label: string,
  category: string,
  unit: CatalogUnit = "item",
  options: ProductOptions = {},
) => baseProduct(id, label, category, { mode: "INCLUDED", unit }, options);

const fixed = (
  id: string,
  label: string,
  category: string,
  amountMinor: number,
  unit: CatalogUnit = "item",
  options: ProductOptions = {},
) =>
  baseProduct(
    id,
    label,
    category,
    { mode: "FIXED", amountMinor, unit },
    options,
  );

const from = (
  id: string,
  label: string,
  category: string,
  amountMinor: number,
  unit: CatalogUnit = "item",
  options: ProductOptions = {},
) =>
  baseProduct(
    id,
    label,
    category,
    { mode: "FROM", amountMinor, unit },
    options,
  );

const manual = (
  id: string,
  label: string,
  category: string,
  manualCategory: CatalogManualCategory,
  reason: string,
  options: ProductOptions = {},
) =>
  baseProduct(id, label, category, { mode: "MANUAL", unit: "item" }, {
    ...options,
    manualReview: { category: manualCategory, reason },
  });

const products = {
  starter: from(
    "starter",
    "Starter website package",
    "PACKAGES",
    180_000,
    "project",
  ),
  professional: from(
    "professional",
    "Professional website package",
    "PACKAGES",
    350_000,
    "project",
  ),

  standard_page: included(
    "standard_page",
    "Standard page",
    "PACKAGE_FOUNDATION",
    "page",
  ),
  correction_round: included(
    "correction_round",
    "Correction round",
    "PACKAGE_FOUNDATION",
  ),
  responsive_design: included(
    "responsive_design",
    "Responsive design",
    "PACKAGE_FOUNDATION",
  ),
  technical_foundation: included(
    "technical_foundation",
    "Technical website foundation",
    "PACKAGE_FOUNDATION",
  ),
  navigation: included(
    "navigation",
    "Navigation and base information structure",
    "PACKAGE_FOUNDATION",
  ),
  technical_seo: included("technical_seo", "Technical SEO foundation", "SEO"),
  standard_contact_form: included(
    "standard_contact_form",
    "Standard contact form",
    "FORMS",
    "item",
    {
      alternativeGroup: "form_tier",
    },
  ),
  analytics_search_console: included(
    "analytics_search_console",
    "Analytics and Search Console foundation",
    "INTEGRATIONS",
  ),
  content_integration: included(
    "content_integration",
    "Integration of supplied final content",
    "COPY",
  ),
  normal_image_optimization: included(
    "normal_image_optimization",
    "Normal web image optimization",
    "MEDIA",
  ),
  technical_qa_delivery: included(
    "technical_qa_delivery",
    "Technical QA and delivery",
    "PACKAGE_FOUNDATION",
  ),
  social_links: included("social_links", "Social links", "INTEGRATIONS"),
  maps_embed: included("maps_embed", "Simple maps embed", "INTEGRATIONS"),
  simple_newsletter_embed: included(
    "simple_newsletter_embed",
    "Simple newsletter embed",
    "INTEGRATIONS",
  ),
  extended_information_architecture: included(
    "extended_information_architecture",
    "Extended information architecture",
    "PACKAGE_FOUNDATION",
  ),
  professional_component_structure: included(
    "professional_component_structure",
    "Extended professional component structure",
    "PACKAGE_FOUNDATION",
  ),
  performance_finish: included(
    "performance_finish",
    "Extended technical and performance finish",
    "PACKAGE_FOUNDATION",
  ),

  extra_standard_page: fixed(
    "extra_standard_page",
    "Extra standard page",
    "PAGES",
    22_500,
    "page",
  ),
  complex_page: from("complex_page", "Complex page", "PAGES", 45_000, "page"),
  simple_portfolio: included(
    "simple_portfolio",
    "Simple portfolio or project page",
    "PAGES",
    "page",
  ),
  dynamic_portfolio: from(
    "dynamic_portfolio",
    "Dynamic portfolio or project system",
    "PAGES",
    45_000,
  ),
  static_gallery: included(
    "static_gallery",
    "Static gallery",
    "PAGES",
    "item",
    {
      alternativeGroup: "gallery_tier",
    },
  ),
  advanced_gallery: from(
    "advanced_gallery",
    "Advanced gallery",
    "PAGES",
    35_000,
    "item",
    {
      alternativeGroup: "gallery_tier",
    },
  ),
  static_reviews: included(
    "static_reviews",
    "Static reviews or testimonials",
    "PAGES",
    "item",
    {
      alternativeGroup: "reviews_tier",
    },
  ),
  live_reviews: from(
    "live_reviews",
    "Live reviews integration",
    "PAGES",
    15_000,
    "item",
    {
      alternativeGroup: "reviews_tier",
    },
  ),
  blog_news: fixed("blog_news", "Blog or news module", "PAGES", 45_000),
  custom_page: manual(
    "custom_page",
    "Custom page",
    "PAGES",
    "SCOPE",
    "Custom page scope requires review",
  ),

  basic_quote_form: fixed(
    "basic_quote_form",
    "Basic quote form",
    "FORMS",
    25_000,
    "item",
    {
      alternativeGroup: "form_tier",
    },
  ),
  extended_quote_form: from(
    "extended_quote_form",
    "Extended quote form",
    "FORMS",
    45_000,
    "item",
    {
      alternativeGroup: "form_tier",
    },
  ),
  upload_form: from(
    "upload_form",
    "File upload form",
    "FORMS",
    35_000,
    "item",
    {
      alternativeGroup: "form_tier",
    },
  ),
  complex_form_workflow: from(
    "complex_form_workflow",
    "Complex form workflow",
    "FORMS",
    65_000,
    "item",
    {
      alternativeGroup: "form_tier",
      manualReview: {
        category: "TECHNICAL",
        reason: "Conditional logic and workflow impact require review",
      },
    },
  ),

  booking_widget: from(
    "booking_widget",
    "External booking widget integration",
    "BOOKING",
    25_000,
    "item",
    {
      alternativeGroup: "booking_tier",
    },
  ),
  advanced_booking: from(
    "advanced_booking",
    "Advanced booking integration",
    "BOOKING",
    50_000,
    "item",
    {
      alternativeGroup: "booking_tier",
    },
  ),
  custom_booking: manual(
    "custom_booking",
    "Custom booking system",
    "BOOKING",
    "TECHNICAL",
    "Custom reservation logic requires review",
    {
      alternativeGroup: "booking_tier",
    },
  ),

  site_search: fixed("site_search", "Site search", "SEARCH", 35_000, "item", {
    alternativeGroup: "search_tier",
  }),
  advanced_search: from(
    "advanced_search",
    "Advanced search and filtering",
    "SEARCH",
    65_000,
    "item",
    {
      alternativeGroup: "search_tier",
      manualReview: {
        category: "TECHNICAL",
        reason: "Advanced filtering complexity requires review",
      },
    },
  ),

  secure_download: fixed(
    "secure_download",
    "Secure download",
    "SECURE",
    25_000,
    "item",
    {
      alternativeGroup: "secure_tier",
    },
  ),
  professional_document_flow: from(
    "professional_document_flow",
    "Professional secure document flow",
    "SECURE",
    75_000,
    "item",
    {
      alternativeGroup: "secure_tier",
    },
  ),
  customer_portal: manual(
    "customer_portal",
    "Customer portal",
    "SECURE",
    "TECHNICAL",
    "Portal access and workflow require review",
    {
      alternativeGroup: "secure_tier",
    },
  ),

  webshop_base: from(
    "webshop_base",
    "Webshop base add-on",
    "WEBSHOP",
    175_000,
    "project",
    {
      requiresOneOf: ["starter", "professional"],
    },
  ),
  simple_product: included(
    "simple_product",
    "Simple webshop product",
    "WEBSHOP",
    "product",
    {
      dependencies: ["webshop_base"],
    },
  ),
  standard_payment_provider: included(
    "standard_payment_provider",
    "Standard payment provider",
    "WEBSHOP",
    "item",
    {
      dependencies: ["webshop_base"],
    },
  ),
  standard_shipping: included(
    "standard_shipping",
    "Standard shipping configuration",
    "WEBSHOP",
    "item",
    {
      dependencies: ["webshop_base"],
    },
  ),
  normal_categories: included(
    "normal_categories",
    "Normal webshop categories",
    "WEBSHOP",
    "item",
    {
      dependencies: ["webshop_base"],
    },
  ),
  extra_simple_products: baseProduct(
    "extra_simple_products",
    "Extra simple webshop products",
    "WEBSHOP",
    {
      mode: "FIXED",
      amountMinor: 2_000,
      unit: "product",
      minimumChargeMinor: 10_000,
    },
    { dependencies: ["webshop_base"], consumesAllowanceFor: "simple_product" },
  ),
  complex_product: from(
    "complex_product",
    "Product with variants or complexity",
    "WEBSHOP",
    3_000,
    "product",
    {
      dependencies: ["webshop_base"],
      manualReview: {
        category: "SCOPE",
        reason: "Complexity beyond the base range requires review",
      },
    },
  ),
  extra_payment_provider: from(
    "extra_payment_provider",
    "Extra payment provider",
    "WEBSHOP",
    20_000,
    "item",
    {
      dependencies: ["webshop_base"],
    },
  ),
  complex_shipping: from(
    "complex_shipping",
    "Complex shipping configuration",
    "WEBSHOP",
    30_000,
    "item",
    {
      dependencies: ["webshop_base"],
    },
  ),
  webshop_accounts: from(
    "webshop_accounts",
    "Webshop customer accounts",
    "WEBSHOP",
    40_000,
    "item",
    {
      dependencies: ["webshop_base"],
    },
  ),
  catalog_import: manual(
    "catalog_import",
    "Catalog import",
    "WEBSHOP",
    "SCOPE",
    "Catalog quality and migration scope require review",
    {
      dependencies: ["webshop_base"],
    },
  ),
  erp_inventory_api: manual(
    "erp_inventory_api",
    "ERP inventory or API integration",
    "WEBSHOP",
    "INTEGRATION",
    "External system integration requires review",
    {
      dependencies: ["webshop_base"],
    },
  ),
  custom_portal: manual(
    "custom_portal",
    "Custom webshop portal",
    "WEBSHOP",
    "TECHNICAL",
    "Custom portal scope requires review",
    {
      dependencies: ["webshop_base"],
    },
  ),

  primary_language: included(
    "primary_language",
    "Primary language",
    "LANGUAGES",
    "language",
  ),
  first_extra_language: fixed(
    "first_extra_language",
    "First extra language",
    "LANGUAGES",
    65_000,
    "language",
  ),
  second_extra_language: fixed(
    "second_extra_language",
    "Second extra language",
    "LANGUAGES",
    45_000,
    "language",
  ),
  subsequent_extra_language: fixed(
    "subsequent_extra_language",
    "Subsequent extra language",
    "LANGUAGES",
    45_000,
    "language",
  ),
  translation: manual(
    "translation",
    "Translation",
    "LANGUAGES",
    "CONTENT",
    "Translation depends on copy scope",
  ),
  alternative_language_structure: manual(
    "alternative_language_structure",
    "Alternative site structure by language",
    "LANGUAGES",
    "SCOPE",
    "Different site structures require review",
  ),

  light_copy_optimization: from(
    "light_copy_optimization",
    "Light copy optimization",
    "COPY",
    30_000,
    "project",
  ),
  substantial_rewrite: from(
    "substantial_rewrite",
    "Substantial copy rewrite",
    "COPY",
    17_500,
    "page",
  ),
  new_copy: from("new_copy", "New web copy", "COPY", 30_000, "page"),
  specialist_copy: manual(
    "specialist_copy",
    "Specialist copy",
    "COPY",
    "CONTENT",
    "Legal or technical specialist copy requires review",
  ),

  client_image_integration: included(
    "client_image_integration",
    "Integration of usable client images",
    "MEDIA",
  ),
  advanced_image_editing: from(
    "advanced_image_editing",
    "Advanced image editing",
    "MEDIA",
    15_000,
    "batch",
  ),
  ai_image_set: from("ai_image_set", "AI image set", "MEDIA", 25_000, "batch"),
  stock_selection: from(
    "stock_selection",
    "Stock selection and processing",
    "MEDIA",
    10_000,
    "batch",
    {
      externalCost: "Actual stock license cost is additional",
    },
  ),
  photography: manual(
    "photography",
    "Professional photography",
    "MEDIA",
    "EXTERNAL_PARTNER",
    "Photography is quoted by scope or external partner",
    {
      billing: "EXTERNAL",
    },
  ),

  professional_logo: from(
    "professional_logo",
    "Professional logo",
    "BRANDING",
    65_000,
    "project",
    {
      alternativeGroup: "branding_tier",
    },
  ),
  visual_identity: from(
    "visual_identity",
    "Visual identity",
    "BRANDING",
    75_000,
    "project",
    {
      alternativeGroup: "branding_tier",
    },
  ),
  logo_identity_combo: from(
    "logo_identity_combo",
    "Logo and visual identity combination",
    "BRANDING",
    115_000,
    "project",
    {
      alternativeGroup: "branding_tier",
    },
  ),
  extended_branding: from(
    "extended_branding",
    "Extended branding",
    "BRANDING",
    150_000,
    "project",
    {
      alternativeGroup: "branding_tier",
      manualReview: {
        category: "SCOPE",
        reason: "Extended branding scope requires review",
      },
    },
  ),

  seo_launch: from("seo_launch", "SEO Launch", "SEO", 65_000, "project"),
  seo_extra_language: from(
    "seo_extra_language",
    "SEO extra language",
    "SEO",
    35_000,
    "language",
  ),
  advanced_seo_language: from(
    "advanced_seo_language",
    "Advanced SEO research for an extra language",
    "SEO",
    50_000,
    "language",
    {
      manualReview: {
        category: "SCOPE",
        reason: "Advanced multilingual SEO research requires review",
      },
    },
  ),
  seo_care: from("seo_care", "SEO Care", "SEO", 25_000, "month", {
    billing: "RECURRING",
  }),
  seo_growth: from("seo_growth", "SEO Growth", "SEO", 45_000, "month", {
    billing: "RECURRING",
  }),
  complex_seo: manual(
    "complex_seo",
    "Complex SEO engagement",
    "SEO",
    "SCOPE",
    "Complex SEO scope requires a quotation",
  ),

  project_domain_configuration: included(
    "project_domain_configuration",
    "Project domain configuration",
    "DOMAIN_HOSTING",
    "item",
    {
      externalCost: "Actual domain registration cost is additional",
    },
  ),
  existing_domain_link: included(
    "existing_domain_link",
    "Link existing domain",
    "DOMAIN_HOSTING",
  ),
  dns_configuration: from(
    "dns_configuration",
    "Standalone DNS configuration",
    "DOMAIN_HOSTING",
    10_000,
  ),
  domain_transfer: from(
    "domain_transfer",
    "Domain transfer and configuration",
    "DOMAIN_HOSTING",
    15_000,
  ),
  standard_hosting_setup: included(
    "standard_hosting_setup",
    "Standard LWS hosting setup",
    "DOMAIN_HOSTING",
  ),
  simple_hosting_migration: from(
    "simple_hosting_migration",
    "Simple hosting migration",
    "DOMAIN_HOSTING",
    20_000,
  ),
  complex_dns_mail_migration: manual(
    "complex_dns_mail_migration",
    "Complex DNS or mail migration",
    "DOMAIN_HOSTING",
    "TECHNICAL",
    "DNS and mail migration risk requires review",
  ),
  complex_migration: manual(
    "complex_migration",
    "Complex CMS database or mail migration",
    "DOMAIN_HOSTING",
    "TECHNICAL",
    "Complex migration requires review",
  ),

  care: fixed("care", "LWS Care", "MAINTENANCE", 4_900, "month", {
    billing: "RECURRING",
  }),
  care_plus: fixed(
    "care_plus",
    "LWS Care Plus",
    "MAINTENANCE",
    9_900,
    "month",
    { billing: "RECURRING" },
  ),
  adhoc_work: fixed(
    "adhoc_work",
    "Ad-hoc web or technical work",
    "MAINTENANCE",
    8_500,
    "hour",
  ),
  complex_technical_work: from(
    "complex_technical_work",
    "Complex technical work",
    "MAINTENANCE",
    9_500,
    "hour",
    {
      manualReview: {
        category: "TECHNICAL",
        reason: "Complex work may require a separate quotation",
      },
    },
  ),
  five_hour_bundle: fixed(
    "five_hour_bundle",
    "Five hour support bundle",
    "MAINTENANCE",
    40_000,
    "item",
    {
      validityMonths: 6,
    },
  ),

  advanced_newsletter: from(
    "advanced_newsletter",
    "Advanced newsletter integration",
    "INTEGRATIONS",
    25_000,
  ),
  advanced_analytics: from(
    "advanced_analytics",
    "Advanced analytics and tracking",
    "INTEGRATIONS",
    35_000,
  ),
  crm_api_erp_automation: manual(
    "crm_api_erp_automation",
    "CRM API ERP or automation integration",
    "INTEGRATIONS",
    "INTEGRATION",
    "External integration scope requires review",
  ),

  extra_revision: fixed(
    "extra_revision",
    "Extra bounded revision round",
    "OTHER",
    15_000,
  ),
  rush: baseProduct(
    "rush",
    "Rush planning surcharge",
    "OTHER",
    { mode: "FROM", minimumPercentage: 20, unit: "percentage" },
    {
      manualReview: {
        category: "SCOPE",
        reason: "Extreme urgency may require review or refusal",
      },
    },
  ),
  scope_review: manual(
    "scope_review",
    "Unresolved scope review",
    "INTERNAL",
    "SCOPE",
    "Unresolved or unsupported evidence requires review",
    {
      visibility: "INTERNAL",
    },
  ),
} satisfies Record<string, CatalogProduct>;

export type CatalogProductId = keyof typeof products;
export type CatalogPackageId = "starter_v1" | "professional_v2";

interface CatalogPackageDefinition {
  id: CatalogPackageId;
  version: 1 | 2;
  catalogProductId: CatalogProductId;
  inheritsFrom: CatalogPackageId | null;
  standardPageLimit: number;
  includedCorrectionRounds: number;
  includedProductIds: readonly CatalogProductId[];
}

const packages = {
  starter_v1: {
    id: "starter_v1",
    version: 1,
    catalogProductId: "starter",
    inheritsFrom: null,
    standardPageLimit: 5,
    includedCorrectionRounds: 1,
    includedProductIds: [
      "standard_page",
      "correction_round",
      "responsive_design",
      "technical_foundation",
      "navigation",
      "technical_seo",
      "standard_contact_form",
      "analytics_search_console",
      "content_integration",
      "normal_image_optimization",
      "technical_qa_delivery",
      "social_links",
      "maps_embed",
      "simple_newsletter_embed",
      "primary_language",
      "simple_portfolio",
      "static_gallery",
      "static_reviews",
      "project_domain_configuration",
      "existing_domain_link",
      "standard_hosting_setup",
    ],
  },
  professional_v2: {
    id: "professional_v2",
    version: 2,
    catalogProductId: "professional",
    inheritsFrom: "starter_v1",
    standardPageLimit: 10,
    includedCorrectionRounds: 2,
    includedProductIds: [
      "blog_news",
      "extended_information_architecture",
      "professional_component_structure",
      "performance_finish",
    ],
  },
} as const satisfies Record<CatalogPackageId, CatalogPackageDefinition>;

const bundles = {
  webshop_base: {
    catalogProductId: "webshop_base",
    includedProductQuantities: {
      simple_product: 15,
      standard_payment_provider: 1,
      standard_shipping: 1,
      normal_categories: 1,
    },
  },
} as const;

export const MASTER_PRICING_CATALOG = {
  catalogVersion: CATALOG_VERSION,
  currency: "EUR",
  vatBasis: "exclusive",
  source: {
    document: "LWS_Master_Product_Price_Catalog_v1_2026-08-12.md",
    date: "2026-08-12",
    sha256: "d95ad2392ea18c518ae21e8965379cdd377a68027cc6ca0f3f8e5e54a907e7c3",
  },
  dependencies: {
    publicPricingPage: "https://lorenzowebsolutions.be/pages/pricing.html",
    publicPricingPageMigrationPhase: "PHASE_C",
  },
  products,
  packages,
  bundles,
  legacyPackageBindings: {
    starter_v1: "starter_v1",
    professional_v1: "professional_v2",
  } as const,
  activeRuleBindings: {
    blog_news: ["blog_news"],
    first_extra_language: ["first_extra_language"],
    subsequent_extra_language: [
      "second_extra_language",
      "subsequent_extra_language",
    ],
    complex_form_workflow: ["complex_form_workflow"],
    webshop_base: ["webshop_base"],
    logo_identity_combo: ["logo_identity_combo"],
    advanced_newsletter: ["advanced_newsletter"],
  } satisfies Record<string, readonly CatalogProductId[]>,
  legacyRuleBindings: {
    extra_standard_page: ["extra_standard_page"],
    extra_custom_page: ["complex_page"],
    extra_correction_round: ["extra_revision"],
    extra_language: [
      "first_extra_language",
      "second_extra_language",
      "subsequent_extra_language",
    ],
    contact_form: ["standard_contact_form"],
    simple_quote_form: ["basic_quote_form"],
    extended_quote_form: ["extended_quote_form"],
    other_extended_form: ["upload_form"],
    complex_form_manual: ["complex_form_workflow"],
    shop_manual: ["webshop_base"],
    booking_manual: ["custom_booking"],
    simple_booking: ["booking_widget", "advanced_booking"],
    multilingual_manual: ["alternative_language_structure"],
    content_media_included: [
      "content_integration",
      "normal_image_optimization",
    ],
    hosting_maintenance_manual: ["complex_migration", "care", "care_plus"],
    seo_included: ["technical_seo"],
    extensive_seo: ["seo_launch"],
    basic_branding: ["visual_identity"],
    basic_logo: ["professional_logo"],
    content_support: [
      "light_copy_optimization",
      "substantial_rewrite",
      "new_copy",
    ],
    extended_ai_imagery: ["ai_image_set"],
    customer_login: ["customer_portal"],
    external_integration: ["crm_api_erp_automation"],
    secured_downloads: ["secure_download", "professional_document_flow"],
    professional_photography: ["photography"],
    unresolved_search: ["site_search", "advanced_search"],
    rush_review: ["rush"],
    substantial_copywriting: ["substantial_rewrite", "new_copy"],
    exceptional_image_work: ["advanced_image_editing"],
    paid_stock_handling: ["stock_selection"],
    complex_gallery_scope: ["advanced_gallery"],
    complex_reviews_scope: ["live_reviews"],
    complex_blog_scope: ["blog_news", "custom_page"],
    complex_jobs_scope: ["complex_page", "custom_page"],
    other_page_scope: ["custom_page"],
    unknown_page_scope: ["scope_review"],
    newsletter_manual: ["advanced_newsletter"],
    indeterminate_normal_scope: ["scope_review"],
    unknown_feature_scope: ["scope_review"],
  } satisfies Record<string, readonly CatalogProductId[]>,
} as const;

function resolvedPackageProductIds(
  packageId: CatalogPackageId,
): Set<CatalogProductId> {
  const definition = packages[packageId];
  const inherited = definition.inheritsFrom
    ? resolvedPackageProductIds(definition.inheritsFrom)
    : new Set<CatalogProductId>();
  for (const productId of definition.includedProductIds) {
    inherited.add(productId);
  }
  return inherited;
}

export interface CatalogContributionContext {
  packageId?: CatalogPackageId;
  bundleProductIds?: readonly (keyof typeof bundles)[];
  quantity?: number;
  billingContext?: "PROJECT" | "RECURRING";
  percentageBaseMinor?: number;
}

export function catalogAmountMinor(productId: CatalogProductId): number {
  const pricing = products[productId].pricing;
  if (!("amountMinor" in pricing)) {
    throw new TypeError("CATALOG_PRODUCT_HAS_NO_AMOUNT");
  }
  return pricing.amountMinor;
}

export function catalogKnownMinimumContributionMinor(
  productId: CatalogProductId,
  context: CatalogContributionContext = {},
): number {
  const product = products[productId];
  const quantity = context.quantity ?? 1;
  if (!Number.isSafeInteger(quantity) || quantity < 0) {
    throw new TypeError("INVALID_CATALOG_QUANTITY");
  }
  if (
    context.packageId &&
    resolvedPackageProductIds(context.packageId).has(productId)
  ) return 0;
  if (
    product.billing === "RECURRING" && context.billingContext !== "RECURRING"
  ) {
    return 0;
  }

  const allowanceProductId =
    (product.consumesAllowanceFor ?? productId) as CatalogProductId;
  const allowance = (context.bundleProductIds ?? []).reduce(
    (total, bundleId) => {
      const included = bundles[bundleId].includedProductQuantities as Partial<
        Record<CatalogProductId, number>
      >;
      return total + (included[allowanceProductId] ?? 0);
    },
    0,
  );
  const chargeableQuantity = Math.max(0, quantity - allowance);
  if (chargeableQuantity === 0) return 0;

  const pricing = product.pricing;
  if (pricing.mode === "INCLUDED" || pricing.mode === "MANUAL") return 0;
  if ("minimumPercentage" in pricing) {
    const baseMinor = context.percentageBaseMinor ?? 0;
    if (!Number.isSafeInteger(baseMinor) || baseMinor < 0) {
      throw new TypeError("INVALID_CATALOG_PERCENTAGE_BASE");
    }
    return Math.ceil(baseMinor * pricing.minimumPercentage / 100);
  }
  const contribution = pricing.amountMinor * chargeableQuantity;
  return Math.max(contribution, pricing.minimumChargeMinor ?? 0);
}

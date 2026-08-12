import {
  catalogAmountMinor,
  CATALOG_VERSION,
  MASTER_PRICING_CATALOG,
} from "./pricing-catalog.ts";

export type PriceMode = "included" | "fixed" | "from" | "manual";

interface RuleBase {
  id: string;
  label: string;
}

export type PricingRule =
  | (RuleBase & { mode: "included" | "manual" })
  | (RuleBase & { mode: "fixed" | "from"; amountMinor: number })
  | (RuleBase & {
    mode: "from";
    minimumPercentage: number;
    maximumPercentage: number;
  });

export type PackageDefinitionId = "starter_v1" | "professional_v2";
export type HistoricalPackageDefinitionId = "professional_v1";
type ReadablePackageDefinitionId =
  | PackageDefinitionId
  | HistoricalPackageDefinitionId;

export const ACTIVE_PACKAGE_DEFINITION_IDS = [
  "starter_v1",
  "professional_v2",
] as const satisfies readonly PackageDefinitionId[];

export type PackageEntitlementId =
  | "responsive_design"
  | "technical_foundation"
  | "navigation"
  | "browser_compatibility"
  | "technical_seo_base"
  | "testing_and_delivery"
  | "standard_contact_form"
  | "social_links"
  | "google_maps"
  | "whatsapp"
  | "normal_gallery_reviews"
  | "public_downloads"
  | "supplied_content_media_processing"
  | "normal_ai_image_support"
  | "primary_language"
  | "blog_news";

interface PackageDefinitionSource {
  id: ReadablePackageDefinitionId;
  version: 1 | 2;
  label: "Starter" | "Professional";
  priceMode: "from";
  floorMinor: number;
  standardPageLimit: number;
  includedCorrectionRounds: number;
  inheritsFrom: PackageDefinitionId | null;
  entitlements: readonly PackageEntitlementId[];
}

const STARTER_ENTITLEMENTS = [
  "responsive_design",
  "technical_foundation",
  "navigation",
  "browser_compatibility",
  "technical_seo_base",
  "testing_and_delivery",
  "standard_contact_form",
  "social_links",
  "google_maps",
  "whatsapp",
  "normal_gallery_reviews",
  "public_downloads",
  "supplied_content_media_processing",
  "normal_ai_image_support",
  "primary_language",
] as const satisfies readonly PackageEntitlementId[];

export const PACKAGE_DEFINITION_REGISTRY = {
  starter_v1: {
    id: "starter_v1",
    version: 1,
    label: "Starter",
    priceMode: "from",
    floorMinor: catalogAmountMinor("starter"),
    standardPageLimit:
      MASTER_PRICING_CATALOG.packages.starter_v1.standardPageLimit,
    includedCorrectionRounds:
      MASTER_PRICING_CATALOG.packages.starter_v1.includedCorrectionRounds,
    inheritsFrom: null,
    entitlements: STARTER_ENTITLEMENTS,
  },
  professional_v2: {
    id: "professional_v2",
    version: 2,
    label: "Professional",
    priceMode: "from",
    floorMinor: catalogAmountMinor("professional"),
    standardPageLimit:
      MASTER_PRICING_CATALOG.packages.professional_v2.standardPageLimit,
    includedCorrectionRounds:
      MASTER_PRICING_CATALOG.packages.professional_v2
        .includedCorrectionRounds,
    inheritsFrom: "starter_v1",
    entitlements: ["blog_news"],
  },
} as const satisfies Record<PackageDefinitionId, PackageDefinitionSource>;

export const HISTORICAL_PACKAGE_DEFINITION_REGISTRY = {
  professional_v1: {
    id: "professional_v1",
    version: 1,
    label: "Professional",
    priceMode: "from",
    floorMinor: 320_000,
    standardPageLimit: 12,
    includedCorrectionRounds: 2,
    inheritsFrom: "starter_v1",
    entitlements: [],
  },
} as const satisfies Record<
  HistoricalPackageDefinitionId,
  PackageDefinitionSource
>;

export interface ResolvedPackageDefinition {
  id: ReadablePackageDefinitionId;
  version: 1 | 2;
  label: "Starter" | "Professional";
  priceMode: "from";
  floorMinor: number;
  standardPageLimit: number;
  includedCorrectionRounds: number;
  entitlementSetId: "normal_web_v1";
  entitlements: readonly PackageEntitlementId[];
}

export function resolvePackageDefinition(
  id: ReadablePackageDefinitionId,
): ResolvedPackageDefinition {
  const source: PackageDefinitionSource = id === "professional_v1"
    ? HISTORICAL_PACKAGE_DEFINITION_REGISTRY.professional_v1
    : PACKAGE_DEFINITION_REGISTRY[id];
  const inherited = source.inheritsFrom === null
    ? []
    : resolvePackageDefinition(source.inheritsFrom).entitlements;
  return {
    id: source.id,
    version: source.version,
    label: source.label,
    priceMode: source.priceMode,
    floorMinor: source.floorMinor,
    standardPageLimit: source.standardPageLimit,
    includedCorrectionRounds: source.includedCorrectionRounds,
    entitlementSetId: "normal_web_v1",
    entitlements: [...new Set([...inherited, ...source.entitlements])],
  };
}

const rules = {
  extra_standard_page: {
    id: "extra_standard_page",
    label: "Extra standaardpagina boven geselecteerde package-scope",
    mode: "fixed",
    amountMinor: catalogAmountMinor("extra_standard_page"),
  },
  extra_custom_page: {
    id: "extra_custom_page",
    label: "Extra maatwerkpagina",
    mode: "from",
    amountMinor: catalogAmountMinor("complex_page"),
  },
  extra_correction_round: {
    id: "extra_correction_round",
    label: "Extra correctieronde",
    mode: "from",
    amountMinor: catalogAmountMinor("extra_revision"),
  },
  first_extra_language: {
    id: "first_extra_language",
    label: "Eerste extra taal binnen normale scope",
    mode: "fixed",
    amountMinor: catalogAmountMinor("first_extra_language"),
  },
  subsequent_extra_language: {
    id: "subsequent_extra_language",
    label: "Tweede en volgende extra taal binnen normale scope",
    mode: "fixed",
    amountMinor: catalogAmountMinor("subsequent_extra_language"),
  },
  blog_news: {
    id: "blog_news",
    label: "Blog/Nieuwsmodule",
    mode: "fixed",
    amountMinor: catalogAmountMinor("blog_news"),
  },
  contact_form: {
    id: "contact_form",
    label: "Normaal contactformulier",
    mode: "included",
  },
  simple_quote_form: {
    id: "simple_quote_form",
    label: "Eenvoudig offerteformulier",
    mode: "fixed",
    amountMinor: catalogAmountMinor("basic_quote_form"),
  },
  extended_quote_form: {
    id: "extended_quote_form",
    label: "Uitgebreid offerteformulier",
    mode: "from",
    amountMinor: catalogAmountMinor("extended_quote_form"),
  },
  other_extended_form: {
    id: "other_extended_form",
    label: "Overig uitgebreid formulier",
    mode: "from",
    amountMinor: catalogAmountMinor("upload_form"),
  },
  complex_form_workflow: {
    id: "complex_form_workflow",
    label: "Complex formulier of workflow",
    mode: "from",
    amountMinor: catalogAmountMinor("complex_form_workflow"),
  },
  complex_form_manual: {
    id: "complex_form_manual",
    label: "Complex formulier of workflow",
    mode: "manual",
  },
  shop_manual: {
    id: "shop_manual",
    label: "Webshop of e-commerce",
    mode: "manual",
  },
  webshop_base: {
    id: "webshop_base",
    label: "Webshop Basis",
    mode: "from",
    amountMinor: catalogAmountMinor("webshop_base"),
  },
  booking_manual: {
    id: "booking_manual",
    label: "Booking of reservatie-integratie",
    mode: "manual",
  },
  simple_booking: {
    id: "simple_booking",
    label: "Eenvoudige reservatie- of afspraakflow",
    mode: "manual",
  },
  multilingual_manual: {
    id: "multilingual_manual",
    label: "Complexe meertaligheid",
    mode: "manual",
  },
  content_media_included: {
    id: "content_media_included",
    label: "Normale content- en mediascope",
    mode: "included",
  },
  hosting_maintenance_manual: {
    id: "hosting_maintenance_manual",
    label: "Hosting, migratie of onderhoud",
    mode: "manual",
  },
  seo_included: {
    id: "seo_included",
    label: "Technische SEO-basis",
    mode: "included",
  },
  extensive_seo: {
    id: "extensive_seo",
    label: "Aanvullende SEO",
    mode: "from",
    amountMinor: catalogAmountMinor("seo_launch"),
  },
  basic_branding: {
    id: "basic_branding",
    label: "Basis branding en visuele richting",
    mode: "from",
    amountMinor: catalogAmountMinor("visual_identity"),
  },
  basic_logo: {
    id: "basic_logo",
    label: "Basis logo-ontwikkeling",
    mode: "from",
    amountMinor: catalogAmountMinor("professional_logo"),
  },
  logo_identity_combo: {
    id: "logo_identity_combo",
    label: "Logo en visuele identiteit",
    mode: "from",
    amountMinor: catalogAmountMinor("logo_identity_combo"),
  },
  content_support: {
    id: "content_support",
    label: "Contentondersteuning buiten normale scope",
    mode: "from",
    amountMinor: 30_000,
  },
  extended_ai_imagery: {
    id: "extended_ai_imagery",
    label: "Uitgebreide AI-beeldondersteuning",
    mode: "from",
    amountMinor: catalogAmountMinor("ai_image_set"),
  },
  customer_login: { id: "customer_login", label: "Klantlogin", mode: "manual" },
  external_integration: {
    id: "external_integration",
    label: "Externe integratie",
    mode: "manual",
  },
  secured_downloads: {
    id: "secured_downloads",
    label: "Beveiligde downloads",
    mode: "fixed",
    amountMinor: catalogAmountMinor("secure_download"),
  },
  professional_photography: {
    id: "professional_photography",
    label: "Professionele fotografie",
    mode: "manual",
  },
  unresolved_search: {
    id: "unresolved_search",
    label: "Zoekfunctionaliteit zonder standaardscope",
    mode: "manual",
  },
  rush_review: {
    id: "rush_review",
    label: "Harde of commercieel kritieke deadline",
    mode: "from",
    minimumPercentage: 20,
    maximumPercentage: 30,
  },
  substantial_copywriting: {
    id: "substantial_copywriting",
    label: "Substantiële copywriting",
    mode: "manual",
  },
  exceptional_image_work: {
    id: "exceptional_image_work",
    label: "Uitzonderlijke beeldproductie of editing",
    mode: "manual",
  },
  paid_stock_handling: {
    id: "paid_stock_handling",
    label: "Betaalde stock buiten externe licentiekost",
    mode: "manual",
  },
  complex_gallery_scope: {
    id: "complex_gallery_scope",
    label: "Complexe galerijscope",
    mode: "from",
    amountMinor: catalogAmountMinor("advanced_gallery"),
  },
  complex_reviews_scope: {
    id: "complex_reviews_scope",
    label: "Complexe reviewsscope",
    mode: "from",
    amountMinor: catalogAmountMinor("live_reviews"),
  },
  complex_blog_scope: {
    id: "complex_blog_scope",
    label: "Complexe blogscope",
    mode: "manual",
  },
  complex_jobs_scope: {
    id: "complex_jobs_scope",
    label: "Complexe vacature- of jobsscope",
    mode: "manual",
  },
  other_page_scope: {
    id: "other_page_scope",
    label: "Andere pagina in vrije tekst",
    mode: "manual",
  },
  unknown_page_scope: {
    id: "unknown_page_scope",
    label: "Onbekende paginascope",
    mode: "manual",
  },
  newsletter_manual: {
    id: "newsletter_manual",
    label: "Nieuwsbrief buiten eenvoudige standaardscope",
    mode: "manual",
  },
  advanced_newsletter: {
    id: "advanced_newsletter",
    label: "Geavanceerde nieuwsbriefintegratie",
    mode: "from",
    amountMinor: catalogAmountMinor("advanced_newsletter"),
  },
  indeterminate_normal_scope: {
    id: "indeterminate_normal_scope",
    label: "Niet objectief afgebakende normale scope",
    mode: "manual",
  },
  unknown_feature_scope: {
    id: "unknown_feature_scope",
    label: "Onbekende of onzekere functionaliteit",
    mode: "manual",
  },
} as const satisfies Record<string, PricingRule>;

export const PRICING_CONFIG = {
  version: CATALOG_VERSION,
  currency: "EUR",
  vatBasis: "exclusive",
  packages: {
    starter: {
      ...PACKAGE_DEFINITION_REGISTRY.starter_v1,
      startingPriceMinor: PACKAGE_DEFINITION_REGISTRY.starter_v1.floorMinor,
    },
    professional: {
      ...PACKAGE_DEFINITION_REGISTRY.professional_v2,
      startingPriceMinor: PACKAGE_DEFINITION_REGISTRY.professional_v2.floorMinor,
    },
    custom: { id: "custom", priceMode: "manual" },
  },
  packageDefinitions: PACKAGE_DEFINITION_REGISTRY,
  rules,
  budgetEvaluation: {
    contractVersion: 2,
    schemeId: "budget_guard_v1",
    starterStartingPriceMinor: 180_000,
    categories: {
      below_1800: {
        originalLabel: "Minder dan EUR 1.800",
        lowerInclusiveMinor: null,
        upperInclusiveMinor: 179_999,
      },
      "1800_to_below_3200": {
        originalLabel: "EUR 1.800 tot minder dan EUR 3.200",
        lowerInclusiveMinor: 180_000,
        upperInclusiveMinor: 319_999,
      },
      "3200_to_6000_inclusive": {
        originalLabel: "EUR 3.200 t/m EUR 6.000",
        lowerInclusiveMinor: 320_000,
        upperInclusiveMinor: 600_000,
      },
      above_6000: {
        originalLabel: "Meer dan EUR 6.000",
        lowerInclusiveMinor: 600_001,
        upperInclusiveMinor: null,
      },
    },
    legacyLabels: [
      "Tot EUR 1.500",
      "EUR 1.500 - EUR 3.000",
      "EUR 3.000 - EUR 6.000",
      "Meer dan EUR 6.000",
    ],
    statusPrecedence: [
      "manual_or_insufficient_evidence",
      "legacy_provenance",
      "below_starter",
      "bounded_comparison",
      "open_upper_category",
    ],
    statusMapping: {
      manual: "manual_review_required",
      legacy: "legacy_category_not_safely_comparable",
      belowStarter: "below_starter_starting_price",
      exceedsBoundedUpper: "known_minimum_exceeds_category_upper_bound",
      withinBoundedUpper: "possibly_compatible_with_category",
      openUpper: "unbounded_category_indeterminate",
    },
    outsideBudgetWishes: {
      provenExceedance: true,
      provenNoExceedance: false,
      indeterminate: null,
    },
  },
} as const;

export type PricingRuleId = keyof typeof PRICING_CONFIG.rules;
export type BudgetCategoryCode = keyof typeof PRICING_CONFIG.budgetEvaluation.categories;

function canonicalDataProperty(
  value: object,
  key: string,
  enumerable: boolean,
): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(value, key);
  if (
    !descriptor || descriptor.enumerable !== enumerable ||
    !("value" in descriptor)
  ) {
    throw new TypeError("PRICING_CONFIG_NON_DATA_PROPERTY");
  }
  return descriptor.value;
}

function assertCanonicalKey(key: string): void {
  if ([...key].some((character) => character.charCodeAt(0) > 0x7f)) {
    throw new TypeError("PRICING_CONFIG_NON_ASCII_KEY");
  }
}

function canonicalJsonValue(
  value: unknown,
  ancestors: Set<object>,
): unknown {
  if (value === null || typeof value === "string" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || Object.is(value, -0)) {
      throw new TypeError("PRICING_CONFIG_NON_CANONICAL_NUMBER");
    }
    return value;
  }
  if (typeof value !== "object") {
    throw new TypeError("PRICING_CONFIG_NON_JSON_VALUE");
  }
  if (ancestors.has(value)) throw new TypeError("PRICING_CONFIG_CYCLE");

  ancestors.add(value);
  try {
    if (Array.isArray(value)) {
      for (const key of Reflect.ownKeys(value)) {
        if (typeof key !== "string") {
          throw new TypeError("PRICING_CONFIG_SYMBOL_KEY");
        }
        assertCanonicalKey(key);
        if (key === "length") {
          canonicalDataProperty(value, key, false);
        } else if (
          !/^(0|[1-9]\d*)$/.test(key) || Number(key) >= value.length
        ) {
          throw new TypeError("PRICING_CONFIG_NON_JSON_ARRAY_PROPERTY");
        } else {
          canonicalDataProperty(value, key, true);
        }
      }
      const normalized: unknown[] = [];
      for (let index = 0; index < value.length; index += 1) {
        if (!(index in value)) throw new TypeError("PRICING_CONFIG_SPARSE_ARRAY");
        normalized.push(canonicalJsonValue(
          canonicalDataProperty(value, String(index), true),
          ancestors,
        ));
      }
      return normalized;
    }

    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) {
      throw new TypeError("PRICING_CONFIG_NON_PLAIN_OBJECT");
    }
    const normalized: Record<string, unknown> = {};
    const keys = Reflect.ownKeys(value).map((key) => {
      if (typeof key !== "string") {
        throw new TypeError("PRICING_CONFIG_SYMBOL_KEY");
      }
      assertCanonicalKey(key);
      canonicalDataProperty(value, key, true);
      return key;
    }).sort();
    for (const key of keys) {
      normalized[key] = canonicalJsonValue(
        canonicalDataProperty(value, key, true),
        ancestors,
      );
    }
    return normalized;
  } finally {
    ancestors.delete(value);
  }
}

export function canonicalizePricingConfig(value: unknown): string {
  return JSON.stringify(canonicalJsonValue(value, new Set()));
}

export async function computePricingConfigHash(
  value: unknown = PRICING_CONFIG,
): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalizePricingConfig(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

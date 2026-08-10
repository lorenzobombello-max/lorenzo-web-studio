export type PriceMode = "included" | "fixed" | "from" | "manual";

interface RuleBase {
  id: string;
  label: string;
}

export type PricingRule =
  | (RuleBase & { mode: "included" | "manual" })
  | (RuleBase & { mode: "fixed" | "from"; amountMinor: number });

const rules = {
  extra_standard_page: {
    id: "extra_standard_page",
    label: "Extra standaardpagina boven Starter-scope",
    mode: "fixed",
    amountMinor: 20_000,
  },
  extra_language: {
    id: "extra_language",
    label: "Extra taal binnen normale scope",
    mode: "from",
    amountMinor: 30_000,
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
    amountMinor: 20_000,
  },
  extended_quote_form: {
    id: "extended_quote_form",
    label: "Uitgebreid offerteformulier",
    mode: "from",
    amountMinor: 40_000,
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
  booking_manual: {
    id: "booking_manual",
    label: "Booking of reservatie-integratie",
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
    label: "Uitgebreide SEO",
    mode: "manual",
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
    mode: "manual",
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
    mode: "manual",
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
    mode: "manual",
  },
  complex_reviews_scope: {
    id: "complex_reviews_scope",
    label: "Complexe reviewsscope",
    mode: "manual",
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
} as const satisfies Record<string, PricingRule>;

export const PRICING_CONFIG = {
  version: "1.0.0",
  currency: "EUR",
  vatBasis: "exclusive",
  packages: {
    starter: {
      id: "starter",
      priceMode: "from",
      startingPriceMinor: 180_000,
      standardPageLimit: 5,
    },
    professional: {
      id: "professional",
      priceMode: "from",
      startingPriceMinor: 320_000,
      standardPageLimit: 12,
    },
    custom: { id: "custom", priceMode: "manual" },
  },
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

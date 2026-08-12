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
    modules.push({
      id: "shop",
      classification: "manual",
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
    const simple = bookingDetails.existing_system === false &&
      bookingDetails.calendar_integration === false;
    modules.push({
      id: "booking",
      classification: simple ? "simple" : "manual",
      evidence: [...bookingEvidence],
    });
  }

  const standardPages: string[] = [];
  const pageScopes = objectValue(input.page_scope_details);
  for (const page of pages) {
    if (UNCONDITIONAL_STANDARD_PAGES.has(page)) {
      standardPages.push(page);
    } else if (page === "products") {
      if (!shopEvidence.size) standardPages.push(page);
    } else if (CONDITIONAL_STANDARD_PAGES.has(page)) {
      if (pageScopes[page] === "normal") standardPages.push(page);
      else manualComponents.add(`complex_${page}_scope`);
    } else if (page === "other") {
      manualComponents.add("other_page_scope");
    } else if (!KNOWN_PAGE_IDS.has(page)) {
      manualComponents.add("unknown_page_scope");
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
    const normal = primaryLanguage !== null && unknownLanguages.length === 0 &&
      details.final_translations_supplied === true &&
      details.same_structure === true &&
      details.extensive_seo === false &&
      details.language_specific_integrations === false &&
      details.complex_scope === false;
    modules.push({
      id: "multilingual",
      classification: normal ? "normal" : "manual",
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
  if (features.has("search")) manualComponents.add("unresolved_search");
  if (
    downloadDetails.access === "secured" || downloadDetails.access === "both"
  ) manualComponents.add("secured_downloads");
  if (contentDetails.copywriting_scope === "substantial") {
    manualComponents.add("substantial_copywriting");
  }
  if (contentDetails.image_work_scope === "exceptional") {
    manualComponents.add("exceptional_image_work");
  }
  if (contentDetails.paid_stock_handling === true) {
    manualComponents.add("paid_stock_handling");
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
    modules.push({
      id: "content_media",
      classification: contentManual ? "manual" : "included",
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
  const hostingEvidence = input.hosting_support === "yes" ||
    input.hosting_support === "advice" ||
    input.hosting_status === "no_hosting" ||
    input.maintenance_interest === "yes" ||
    input.maintenance_interest === "maybe" ||
    input.maintenance_interest === "info_requested" ||
    hasObjectData(hostingDetails);
  if (hostingEvidence) {
    modules.push({
      id: "hosting_maintenance",
      classification: "manual",
      evidence: ["hosting_maintenance"],
    });
  }

  const seoDetails = objectValue(input.seo_details);
  if (input.seo_priority != null || hasObjectData(seoDetails)) {
    const extensive = seoDetails.extensive_services === true;
    modules.push({
      id: "seo",
      classification: extensive ? "additional" : "included",
      evidence: ["seo"],
    });
  }

  if (features.has("customer_login")) manualComponents.add("customer_login");
  if (stringArray(input.integrations).length) {
    manualComponents.add("external_integration");
  }
  const deadlineDetails = objectValue(input.deadline_details);
  if (
    deadlineDetails.commercially_critical === true ||
    deadlineDetails.hard_deadline === true
  ) manualComponents.add("rush_review");

  return {
    standardPages: [...new Set(standardPages)],
    standardPageCount: new Set(standardPages).size,
    primaryLanguage,
    additionalLanguages,
    unknownLanguages,
    modules,
    manualComponents: [...manualComponents],
  };
}

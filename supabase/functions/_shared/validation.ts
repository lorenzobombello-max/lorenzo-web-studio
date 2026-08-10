import type { CustomerType, EnterpriseValidationStatus, ReviewAction, SanitizedQuotePayload, SubmitQuotePayload } from "./types.ts";

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_CHARACTERS_REGEX = /^[+0-9().\s-]+$/;
const BUSINESS_IDENTIFIER_REGEX = /^[\p{L}\p{N} .\-_/]+$/u;
const SAFE_BUSINESS_TEXT_REGEX = /^[^<>]*$/u;
const CUSTOMER_TYPES = new Set(["individual", "business"]);
const VIES_COUNTRY_CODES = new Set([
  "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "EL", "ES", "FI", "FR", "HR", "HU", "IE", "IT",
  "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK", "XI",
]);
const WEBSITE_TYPES = new Set([
  "Bedrijfswebsite",
  "Portfolio-website",
  "Website voor lokale onderneming",
  "Demo of showcase concept",
  "Automotive website",
  "Technische dienstensite",
  "Personal portfolio",
  "Technische profielsite",
  "Consultancy website",
  "Restaurantwebsite",
  "Horeca website",
  "Andere",
]);
const BUDGETS = new Set([
  "Tot EUR 1.500",
  "EUR 1.500 - EUR 3.000",
  "EUR 3.000 - EUR 6.000",
  "Meer dan EUR 6.000",
  "Minder dan EUR 1.800",
  "EUR 1.800 tot minder dan EUR 3.200",
  "EUR 3.200 t/m EUR 6.000",
]);
const BUDGET_GUARD_CATEGORIES = new Map([
  ["below_1800", "Minder dan EUR 1.800"],
  ["1800_to_below_3200", "EUR 1.800 tot minder dan EUR 3.200"],
  ["3200_to_6000_inclusive", "EUR 3.200 t/m EUR 6.000"],
  ["above_6000", "Meer dan EUR 6.000"],
]);
const TIMINGS = new Set([
  "Binnen 1 maand",
  "Binnen 2 tot 3 maanden",
  "Flexibel / nog te bepalen",
]);
const INTAKE_FIELDS = new Set([
  "business_description", "target_audience", "has_existing_website", "existing_website_url",
  "elements_to_keep", "improvement_areas", "website_goals", "primary_conversion_goal",
  "requested_pages", "other_pages", "requested_features", "shop_required", "shop_details",
  "booking_required", "booking_details", "languages", "design_styles", "brand_status",
  "logo_status", "brand_colors", "inspiration_sites", "disliked_styles", "content_status",
  "image_status", "image_support", "domain_status", "domain_name", "hosting_status",
  "hosting_support", "maintenance_interest", "seo_priority", "seo_keywords", "social_channels",
  "integrations", "deadline_date", "deadline_reason", "budget_confirmed",
  "budget_update_category", "budget_notes", "priorities", "additional_notes", "confirmation",
  "primary_language", "additional_languages", "page_scope_details", "quote_form_details",
  "multilingual_details", "download_details", "content_media_details", "newsletter_details",
  "hosting_maintenance_details", "deadline_details", "seo_details",
  "budget_update_category_scheme", "budget_update_category_code",
]);
export const INTAKE_EVIDENCE_FIELDS = new Set([
  "primary_language", "additional_languages", "page_scope_details", "quote_form_details",
  "multilingual_details", "download_details", "content_media_details", "newsletter_details",
  "hosting_maintenance_details", "deadline_details", "seo_details",
  "budget_update_category_scheme", "budget_update_category_code",
]);
const FORBIDDEN_PRICING_FIELDS = new Set([
  "calculatedPrice", "knownMinimum", "knownMinimumMinor", "selectedPackage",
  "pricingMode", "appliedRuleAmount", "isIncluded", "budgetStatus", "appliedRules",
  "manualReviewRequired", "manualReasons", "packageAdvice", "budgetEvaluation",
  "pricingConfigVersion", "pricingConfigHash", "configHash", "pricingSnapshot",
  "snapshot", "proof",
]);
const PRICING_PREVIEW_FIELDS = new Set([
  "requested_pages", "requested_features", "website_goals",
  "shop_required", "shop_details", "booking_required", "booking_details",
  "page_scope_details", "quote_form_details", "primary_language",
  "additional_languages", "languages", "multilingual_details",
  "content_status", "image_status", "image_support", "content_media_details",
  "download_details", "newsletter_details", "hosting_status", "hosting_support",
  "maintenance_interest", "hosting_maintenance_details", "seo_priority",
  "seo_details", "integrations", "deadline_details", "budget_update_category",
  "budget_update_category_scheme", "budget_update_category_code",
]);
const WEBSITE_GOALS = new Set([
  "professional_presence", "generate_leads", "quote_requests", "contact_requests", "appointments",
  "reservations", "sell_products", "sell_services", "portfolio", "information", "recruitment", "other",
]);
const REQUESTED_PAGES = new Set([
  "home", "about", "services", "products", "portfolio", "team", "pricing", "faq", "reviews", "blog",
  "contact", "quote_request", "reservations", "shop", "jobs", "gallery", "other",
]);
const REQUESTED_FEATURES = new Set([
  "contact_form", "quote_form", "google_maps", "social_links", "reviews", "gallery", "newsletter",
  "whatsapp", "appointments", "reservations", "shop", "online_payment", "customer_login", "downloads",
  "search", "multilingual", "other", "unsure",
]);
const DESIGN_STYLES = new Set([
  "modern", "business", "minimal", "elegant", "luxury", "warm", "playful", "creative", "technical",
  "industrial", "calm", "unsure", "other",
]);
const IMAGE_SUPPORT = new Set([
  "optimize_existing", "ai_images", "stock_images", "professional_photography", "none", "unsure",
]);
const PRIORITIES = new Set([
  "professional_appearance", "usability", "more_requests", "more_sales", "mobile_experience", "performance",
  "seo", "easy_management", "fast_delivery", "stay_within_budget", "differentiate", "other",
]);
const BRAND_STATUSES = new Set(["complete", "partial", "none", "unknown"]);
const LOGO_STATUSES = new Set(["available", "needs_update", "needed", "unknown"]);
const CONTENT_STATUSES = new Set(["complete", "partial", "none", "needs_help"]);
const IMAGE_STATUSES = new Set(["sufficient", "partial", "none"]);
const DOMAIN_STATUSES = new Set(["has_domain", "no_domain", "unknown"]);
const HOSTING_STATUSES = new Set(["has_hosting", "no_hosting", "unknown"]);
const HOSTING_SUPPORT = new Set(["yes", "no", "advice"]);
const MAINTENANCE_INTEREST = new Set(["yes", "no", "maybe", "info_requested"]);
const SEO_PRIORITIES = new Set(["high", "basic", "low", "unsure"]);
const BOOKING_TYPES = new Set(["appointments", "reservations", "classes", "consultations", "other"]);

export class InputValidationError extends Error {
  readonly code: string;
  readonly field?: string;

  constructor(code: string, field?: string) {
    super(code);
    this.name = "InputValidationError";
    this.code = code;
    this.field = field;
  }
}

function normalizeText(value: unknown): string {
  if (typeof value !== "string") return "";
  return value
    .normalize("NFKC")
    .replace(/\r\n?/g, "\n")
    .split("")
    .filter((character) => {
      const codeUnit = character.charCodeAt(0);
      return !(
        codeUnit <= 0x08 ||
        codeUnit === 0x0b ||
        codeUnit === 0x0c ||
        (codeUnit >= 0x0e && codeUnit <= 0x1f) ||
        codeUnit === 0x7f
      );
    })
    .join("")
    .trim();
}

function assertLength(field: string, value: string, min: number, max: number): void {
  if (value.length < min || value.length > max) {
    throw new InputValidationError("INVALID_LENGTH", field);
  }
}

function assertAllowed(field: string, value: string, allowed: Set<string>): void {
  if (!allowed.has(value)) throw new InputValidationError("INVALID_OPTION", field);
}

function normalizeNullableText(field: string, value: unknown, max: number): string | null {
  if (value === null) return null;
  if (typeof value !== "string") throw new InputValidationError("INVALID_TYPE", field);
  const normalized = normalizeText(value);
  if (!normalized) return null;
  assertLength(field, normalized, 1, max);
  return normalized;
}

function normalizeBoolean(field: string, value: unknown): boolean {
  if (typeof value !== "boolean") throw new InputValidationError("INVALID_TYPE", field);
  return value;
}

function normalizeOption(field: string, value: unknown, allowed: Set<string>): string | null {
  const normalized = normalizeNullableText(field, value, 80);
  if (normalized !== null) assertAllowed(field, normalized, allowed);
  return normalized;
}

function normalizeRequiredOption(field: string, value: unknown, allowed: Set<string>): string {
  const normalized = normalizeOption(field, value, allowed);
  if (normalized === null) throw new InputValidationError("INVALID_OPTION", field);
  return normalized;
}

function normalizeArray(
  field: string,
  value: unknown,
  maxItems: number,
  itemMax: number,
  allowed?: Set<string>,
): string[] {
  if (!Array.isArray(value)) throw new InputValidationError("INVALID_TYPE", field);
  if (value.length > maxItems) throw new InputValidationError("TOO_MANY_ITEMS", field);

  const normalized = value.map((item) => {
    const text = normalizeNullableText(field, item, itemMax);
    if (text === null) throw new InputValidationError("INVALID_LENGTH", field);
    if (allowed) assertAllowed(field, text, allowed);
    return text;
  });
  return [...new Set(normalized)];
}

function normalizeUrl(field: string, value: unknown): string | null {
  const normalized = normalizeNullableText(field, value, 2048);
  if (normalized === null) return null;
  try {
    const url = new URL(normalized);
    if ((url.protocol !== "http:" && url.protocol !== "https:") || url.username || url.password) {
      throw new Error("invalid URL");
    }
    return url.toString();
  } catch {
    throw new InputValidationError("INVALID_FORMAT", field);
  }
}

function normalizeUrlArray(field: string, value: unknown, maxItems: number): string[] {
  if (!Array.isArray(value)) throw new InputValidationError("INVALID_TYPE", field);
  if (value.length > maxItems) throw new InputValidationError("TOO_MANY_ITEMS", field);
  const normalized = value.map((item) => {
    const url = normalizeUrl(field, item);
    if (!url) throw new InputValidationError("INVALID_FORMAT", field);
    return url;
  });
  return [...new Set(normalized)];
}

function normalizeDate(field: string, value: unknown): string | null {
  const normalized = normalizeNullableText(field, value, 10);
  if (normalized === null) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(normalized);
  if (!match) throw new InputValidationError("INVALID_FORMAT", field);
  const year = Number(match[1]);
  const date = new Date(`${normalized}T00:00:00.000Z`);
  if (year < 2000 || year > 2100 || Number.isNaN(date.valueOf()) || date.toISOString().slice(0, 10) !== normalized) {
    throw new InputValidationError("INVALID_FORMAT", field);
  }
  return normalized;
}

function normalizeShopDetails(value: unknown): Record<string, unknown> | null {
  if (value === null) return null;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputValidationError("INVALID_TYPE", "shop_details");
  }
  const input = value as Record<string, unknown>;
  const keys = ["approx_product_count", "categories", "online_payments", "shipping", "pickup", "existing_catalog"];
  if (Object.keys(input).some((key) => !keys.includes(key)) || keys.some((key) => !(key in input))) {
    throw new InputValidationError("INVALID_SCHEMA", "shop_details");
  }
  if (!Number.isInteger(input.approx_product_count) || Number(input.approx_product_count) < 1 || Number(input.approx_product_count) > 100000) {
    throw new InputValidationError("INVALID_RANGE", "shop_details.approx_product_count");
  }
  for (const key of keys.slice(1)) normalizeBoolean(`shop_details.${key}`, input[key]);
  return Object.fromEntries(keys.map((key) => [key, input[key]]));
}

function normalizeBookingDetails(value: unknown): Record<string, unknown> | null {
  if (value === null) return null;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputValidationError("INVALID_TYPE", "booking_details");
  }
  const input = value as Record<string, unknown>;
  const keys = ["type", "existing_system", "existing_system_name", "calendar_integration"];
  if (Object.keys(input).some((key) => !keys.includes(key)) || keys.some((key) => !(key in input))) {
    throw new InputValidationError("INVALID_SCHEMA", "booking_details");
  }
  const type = normalizeOption("booking_details.type", input.type, BOOKING_TYPES);
  if (!type) throw new InputValidationError("REQUIRED_FIELD", "booking_details.type");
  const existingSystem = normalizeBoolean("booking_details.existing_system", input.existing_system);
  const existingSystemName = normalizeNullableText("booking_details.existing_system_name", input.existing_system_name, 160);
  if (existingSystem && !existingSystemName) {
    throw new InputValidationError("REQUIRED_FIELD", "booking_details.existing_system_name");
  }
  if (!existingSystem && existingSystemName) {
    throw new InputValidationError("INVALID_CONDITION", "booking_details.existing_system_name");
  }
  return {
    type,
    existing_system: existingSystem,
    existing_system_name: existingSystemName,
    calendar_integration: normalizeBoolean("booking_details.calendar_integration", input.calendar_integration),
  };
}

function normalizeEvidenceObject(
  field: string,
  value: unknown,
  allowedKeys: readonly string[],
): Record<string, unknown> | null {
  if (value === null) return null;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputValidationError("INVALID_TYPE", field);
  }
  const input = value as Record<string, unknown>;
  const unknownKey = Object.keys(input).find((key) => !allowedKeys.includes(key));
  if (unknownKey) throw new InputValidationError("INVALID_SCHEMA", `${field}.${unknownKey}`);
  return input;
}

function normalizeEvidenceBooleanObject(field: string, value: unknown, keys: readonly string[]): Record<string, unknown> | null {
  const input = normalizeEvidenceObject(field, value, keys);
  if (input === null) return null;
  return Object.fromEntries(Object.entries(input).map(([key, entry]) => [key, normalizeBoolean(`${field}.${key}`, entry)]));
}

function normalizePageScopeDetails(value: unknown): Record<string, unknown> | null {
  const field = "page_scope_details";
  const input = normalizeEvidenceObject(field, value, ["reviews", "blog", "jobs", "gallery"]);
  if (input === null) return null;
  const allowed = new Set(["normal", "complex", "unknown"]);
  return Object.fromEntries(Object.entries(input).map(([key, entry]) => [key, normalizeRequiredOption(`${field}.${key}`, entry, allowed)]));
}

function normalizeQuoteFormDetails(value: unknown): Record<string, unknown> | null {
  const field = "quote_form_details";
  const booleanKeys = ["file_uploads", "database_workflow", "automated_processing", "review_approval", "custom_logic"];
  const input = normalizeEvidenceObject(field, value, ["classification", ...booleanKeys, "form_count", "structure_scope"]);
  if (input === null) return null;
  const output: Record<string, unknown> = {};
  if ("classification" in input) {
    output.classification = normalizeRequiredOption(`${field}.classification`, input.classification, new Set(["simple", "extended", "complex", "unknown"]));
  }
  if ("structure_scope" in input) {
    output.structure_scope = normalizeRequiredOption(`${field}.structure_scope`, input.structure_scope, new Set([
      "basic_single_section", "extended_standard_structure", "unsure_or_other",
    ]));
  }
  for (const key of booleanKeys) {
    if (key in input) output[key] = normalizeBoolean(`${field}.${key}`, input[key]);
  }
  if ("form_count" in input) {
    if (!Number.isInteger(input.form_count) || Number(input.form_count) < 1 || Number(input.form_count) > 20) {
      throw new InputValidationError("INVALID_RANGE", `${field}.form_count`);
    }
    output.form_count = input.form_count;
  }
  if ("classification" in output) {
    // Legacy compatibility only; authoritative pricing must derive from raw structure and complexity facts.
    const hasComplexSignals = booleanKeys.some((key) => output[key] === true) || Number(output.form_count) > 1;
    if ((hasComplexSignals && output.classification !== "complex") || (!hasComplexSignals && output.classification === "complex")) {
      throw new InputValidationError("INCOHERENT_QUOTE_FORM_EVIDENCE", `${field}.classification`);
    }
  }
  return output;
}

function normalizeSingleOptionEvidence(
  field: string,
  value: unknown,
  key: string,
  allowed: Set<string>,
): Record<string, unknown> | null {
  const input = normalizeEvidenceObject(field, value, [key]);
  if (input === null) return null;
  return key in input ? { [key]: normalizeRequiredOption(`${field}.${key}`, input[key], allowed) } : {};
}

function normalizeContentMediaDetails(value: unknown): Record<string, unknown> | null {
  const field = "content_media_details";
  const input = normalizeEvidenceObject(field, value, ["copywriting_scope", "image_work_scope", "paid_stock_handling"]);
  if (input === null) return null;
  const output: Record<string, unknown> = {};
  if ("copywriting_scope" in input) {
    output.copywriting_scope = normalizeRequiredOption(`${field}.copywriting_scope`, input.copywriting_scope, new Set(["none", "light", "substantial", "unknown"]));
  }
  if ("image_work_scope" in input) {
    output.image_work_scope = normalizeRequiredOption(`${field}.image_work_scope`, input.image_work_scope, new Set(["none", "standard", "exceptional", "unknown"]));
  }
  if ("paid_stock_handling" in input) {
    output.paid_stock_handling = normalizeBoolean(`${field}.paid_stock_handling`, input.paid_stock_handling);
  }
  return output;
}

function normalizeHostingMaintenanceDetails(value: unknown): Record<string, unknown> | null {
  const field = "hosting_maintenance_details";
  const input = normalizeEvidenceObject(field, value, ["hosting_support", "maintenance_interest"]);
  if (input === null) return null;
  const output: Record<string, unknown> = {};
  if ("hosting_support" in input) output.hosting_support = normalizeRequiredOption(`${field}.hosting_support`, input.hosting_support, HOSTING_SUPPORT);
  if ("maintenance_interest" in input) output.maintenance_interest = normalizeRequiredOption(`${field}.maintenance_interest`, input.maintenance_interest, MAINTENANCE_INTEREST);
  return output;
}

const TEXT_LIMITS: Record<string, number> = {
  business_description: 3000,
  target_audience: 2000,
  elements_to_keep: 2000,
  improvement_areas: 2000,
  primary_conversion_goal: 500,
  other_pages: 1000,
  disliked_styles: 1500,
  domain_name: 253,
  deadline_reason: 1000,
  budget_notes: 1000,
  additional_notes: 3000,
};
const OPTION_FIELDS: Record<string, Set<string>> = {
  brand_status: BRAND_STATUSES,
  logo_status: LOGO_STATUSES,
  content_status: CONTENT_STATUSES,
  image_status: IMAGE_STATUSES,
  domain_status: DOMAIN_STATUSES,
  hosting_status: HOSTING_STATUSES,
  hosting_support: HOSTING_SUPPORT,
  maintenance_interest: MAINTENANCE_INTEREST,
  seo_priority: SEO_PRIORITIES,
  budget_update_category: BUDGETS,
};
const ARRAY_FIELDS: Record<string, [number, number, Set<string>?]> = {
  website_goals: [12, 40, WEBSITE_GOALS],
  requested_pages: [17, 40, REQUESTED_PAGES],
  requested_features: [18, 40, REQUESTED_FEATURES],
  languages: [8, 40],
  design_styles: [13, 40, DESIGN_STYLES],
  brand_colors: [12, 80],
  image_support: [6, 40, IMAGE_SUPPORT],
  seo_keywords: [20, 120],
  social_channels: [12, 120],
  integrations: [20, 120],
  priorities: [3, 40, PRIORITIES],
};

export function sanitizeAndValidateIntakeData(payload: unknown, mode: "draft" | "submit"): Record<string, unknown> {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new InputValidationError("INVALID_PAYLOAD");
  }
  const input = payload as Record<string, unknown>;
  const forbiddenField = Object.keys(input).find((field) => FORBIDDEN_PRICING_FIELDS.has(field));
  if (forbiddenField) throw new InputValidationError("PRICING_OUTPUT_NOT_ALLOWED", forbiddenField);
  const unknownField = Object.keys(input).find((field) => !INTAKE_FIELDS.has(field));
  if (unknownField) throw new InputValidationError("UNKNOWN_FIELD", unknownField);

  const output: Record<string, unknown> = {};
  for (const [field, value] of Object.entries(input)) {
    if (field in TEXT_LIMITS) output[field] = normalizeNullableText(field, value, TEXT_LIMITS[field]);
    else if (field in OPTION_FIELDS) output[field] = normalizeOption(field, value, OPTION_FIELDS[field]);
    else if (field in ARRAY_FIELDS) {
      const [maxItems, itemMax, allowed] = ARRAY_FIELDS[field];
      output[field] = normalizeArray(field, value, maxItems, itemMax, allowed);
    } else if (field === "existing_website_url") output[field] = normalizeUrl(field, value);
    else if (field === "inspiration_sites") output[field] = normalizeUrlArray(field, value, 10);
    else if (field === "deadline_date") output[field] = normalizeDate(field, value);
    else if (field === "shop_details") output[field] = normalizeShopDetails(value);
    else if (field === "booking_details") output[field] = normalizeBookingDetails(value);
    else if (field === "primary_language") output[field] = normalizeNullableText(field, value, 35);
    else if (field === "additional_languages") output[field] = value === null ? null : normalizeArray(field, value, 8, 35);
    else if (field === "page_scope_details") output[field] = normalizePageScopeDetails(value);
    else if (field === "quote_form_details") output[field] = normalizeQuoteFormDetails(value);
    else if (field === "multilingual_details") {
      output[field] = normalizeEvidenceBooleanObject(field, value, [
        "final_translations_supplied", "same_structure", "extensive_seo",
        "language_specific_integrations", "complex_scope",
      ]);
    } else if (field === "download_details") {
      output[field] = normalizeSingleOptionEvidence(field, value, "access", new Set(["public", "secured", "both", "unknown"]));
    } else if (field === "content_media_details") output[field] = normalizeContentMediaDetails(value);
    else if (field === "newsletter_details") {
      output[field] = normalizeSingleOptionEvidence(field, value, "scope", new Set([
        "simple_existing_service", "new_service_setup", "automation_or_segmentation", "unknown",
      ]));
    } else if (field === "hosting_maintenance_details") output[field] = normalizeHostingMaintenanceDetails(value);
    else if (field === "deadline_details") {
      output[field] = normalizeEvidenceBooleanObject(field, value, ["commercially_critical", "hard_deadline"]);
    } else if (field === "seo_details") {
      output[field] = normalizeEvidenceBooleanObject(field, value, ["extensive_services"]);
    } else if (field === "budget_update_category_scheme") {
      output[field] = normalizeOption(field, value, new Set(["budget_guard_v1"]));
    } else if (field === "budget_update_category_code") {
      output[field] = normalizeOption(field, value, new Set(BUDGET_GUARD_CATEGORIES.keys()));
    }
    else output[field] = normalizeBoolean(field, value);
  }

  const hasBudgetScheme = "budget_update_category_scheme" in output;
  const hasBudgetCode = "budget_update_category_code" in output;
  if (hasBudgetScheme || hasBudgetCode) {
    if (
      !hasBudgetScheme || !hasBudgetCode ||
      typeof output.budget_update_category_scheme !== "string" ||
      typeof output.budget_update_category_code !== "string" ||
      typeof output.budget_update_category !== "string"
    ) {
      throw new InputValidationError("INCOHERENT_BUDGET_EVIDENCE", "budget_update_category");
    }
    if (BUDGET_GUARD_CATEGORIES.get(String(output.budget_update_category_code)) !== output.budget_update_category) {
      throw new InputValidationError("INCOHERENT_BUDGET_EVIDENCE", "budget_update_category");
    }
  }

  if (output.has_existing_website === false) {
    if (output.existing_website_url || output.elements_to_keep) {
      throw new InputValidationError("INVALID_CONDITION", "existing_website_url");
    }
    output.existing_website_url = null;
    output.elements_to_keep = null;
  }
  if ((output.existing_website_url || output.elements_to_keep) && output.has_existing_website !== true) {
    throw new InputValidationError("INVALID_CONDITION", "has_existing_website");
  }
  if (output.shop_required === false) {
    if (output.shop_details) throw new InputValidationError("INVALID_CONDITION", "shop_details");
    output.shop_details = null;
  }
  if (output.shop_details && output.shop_required !== true) {
    throw new InputValidationError("INVALID_CONDITION", "shop_required");
  }
  if (output.booking_required === false) {
    if (output.booking_details) throw new InputValidationError("INVALID_CONDITION", "booking_details");
    output.booking_details = null;
  }
  if (output.booking_details && output.booking_required !== true) {
    throw new InputValidationError("INVALID_CONDITION", "booking_required");
  }

  if (mode === "submit") {
    const requiredText = ["business_description", "target_audience", "primary_conversion_goal"];
    const requiredOptions = [
      "brand_status", "logo_status", "content_status", "image_status", "domain_status", "hosting_status",
      "maintenance_interest", "seo_priority",
    ];
    const requiredArrays = ["website_goals", "requested_pages", "design_styles", "priorities"];
    for (const field of [...requiredText, ...requiredOptions]) {
      if (typeof output[field] !== "string" || !output[field]) throw new InputValidationError("REQUIRED_FIELD", field);
    }
    for (const field of requiredArrays) {
      if (!Array.isArray(output[field]) || output[field].length === 0) throw new InputValidationError("REQUIRED_FIELD", field);
    }
    if (!Array.isArray(output.requested_features)) throw new InputValidationError("REQUIRED_FIELD", "requested_features");
    if (output.confirmation !== true) throw new InputValidationError("CONFIRMATION_REQUIRED", "confirmation");
    if (output.has_existing_website === true && !output.existing_website_url) {
      throw new InputValidationError("REQUIRED_FIELD", "existing_website_url");
    }
    if (output.shop_required === true && !output.shop_details) throw new InputValidationError("REQUIRED_FIELD", "shop_details");
    if (output.booking_required === true && !output.booking_details) throw new InputValidationError("REQUIRED_FIELD", "booking_details");
    if (output.domain_status === "has_domain" && !output.domain_name) throw new InputValidationError("REQUIRED_FIELD", "domain_name");
  }

  return output;
}

export function sanitizeAndValidatePricingPreviewInput(
  payload: unknown,
): Record<string, unknown> {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new InputValidationError("INVALID_PAYLOAD");
  }
  const input = payload as Record<string, unknown>;
  const forbiddenField = Object.keys(input).find((field) =>
    FORBIDDEN_PRICING_FIELDS.has(field) || field.toLowerCase().startsWith("integrity")
  );
  if (forbiddenField) {
    throw new InputValidationError("PRICING_OUTPUT_NOT_ALLOWED", forbiddenField);
  }
  const unknownField = Object.keys(input).find((field) => !PRICING_PREVIEW_FIELDS.has(field));
  if (unknownField) throw new InputValidationError("UNKNOWN_FIELD", unknownField);

  return sanitizeAndValidateIntakeData(input, "draft");
}

export function partitionIntakeData(input: Record<string, unknown>): {
  legacyData: Record<string, unknown>;
  evidenceData: Record<string, unknown>;
} {
  const legacyData: Record<string, unknown> = {};
  const evidenceData: Record<string, unknown> = {};
  for (const [field, value] of Object.entries(input)) {
    if (INTAKE_EVIDENCE_FIELDS.has(field)) evidenceData[field] = value;
    else legacyData[field] = value;
  }
  if (
    "budget_update_category_scheme" in evidenceData &&
    "budget_update_category_code" in evidenceData &&
    "budget_update_category" in legacyData
  ) {
    evidenceData.budget_update_category = legacyData.budget_update_category;
  }
  return { legacyData, evidenceData };
}

export function sanitizeAndValidateSubmitPayload(payload: unknown): SanitizedQuotePayload {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new InputValidationError("INVALID_PAYLOAD");
  }

  const input = payload as Partial<SubmitQuotePayload>;
  if (typeof input.email === "string" && /[\r\n]/.test(input.email)) {
    throw new InputValidationError("INVALID_FORMAT", "email");
  }

  const name = normalizeText(input.name);
  const customerTypeInput = input.customer_type === undefined
    ? null
    : normalizeText(input.customer_type);
  if (customerTypeInput !== null) assertAllowed("customer_type", customerTypeInput, CUSTOMER_TYPES);
  const customerType = customerTypeInput as CustomerType | null;
  const company = normalizeText(input.company ?? "");
  let enterpriseNumber = normalizeNullableText("enterprise_number", input.enterprise_number ?? null, 40) || "";
  let vatNumber = normalizeNullableText("vat_number", input.vat_number ?? null, 40) || "";
  const billingAddress = normalizeNullableText("billing_address", input.billing_address ?? null, 200) || "";
  const billingPostalCode = normalizeNullableText("billing_postal_code", input.billing_postal_code ?? null, 20) || "";
  const billingCity = normalizeNullableText("billing_city", input.billing_city ?? null, 120) || "";
  const billingCountry = normalizeNullableText("billing_country", input.billing_country ?? null, 80) || "";
  const billingEmail = (normalizeNullableText("billing_email", input.billing_email ?? null, 254) || "").toLowerCase();
  const email = normalizeText(input.email).toLowerCase();
  const phone = normalizeText(input.phone ?? "");
  const websiteType = normalizeText(input.website_type);
  const budget = normalizeText(input.budget);
  const timing = normalizeText(input.timing);
  const description = normalizeText(input.description);
  const honeypotValue = normalizeText(input.website ?? "");

  assertLength("name", name, 2, 120);
  if ((name.match(/[\p{L}\p{N}]/gu) || []).length < 2) {
    throw new InputValidationError("INVALID_FORMAT", "name");
  }
  if (company) assertLength("company", company, 2, 140);
  if (enterpriseNumber) assertLength("enterprise_number", enterpriseNumber, 2, 40);
  if (vatNumber) assertLength("vat_number", vatNumber, 2, 40);
  if (billingAddress) assertLength("billing_address", billingAddress, 2, 200);
  if (billingPostalCode) assertLength("billing_postal_code", billingPostalCode, 2, 20);
  if (billingCity) assertLength("billing_city", billingCity, 2, 120);
  if (billingCountry) assertLength("billing_country", billingCountry, 2, 80);
  if (billingEmail) assertLength("billing_email", billingEmail, 5, 254);
  for (const [field, value] of [
    ["company", company],
    ["billing_address", billingAddress],
    ["billing_postal_code", billingPostalCode],
    ["billing_city", billingCity],
    ["billing_country", billingCountry],
  ]) {
    if (value && !SAFE_BUSINESS_TEXT_REGEX.test(value)) {
      throw new InputValidationError("INVALID_FORMAT", field);
    }
  }
  for (const [field, value] of [["enterprise_number", enterpriseNumber], ["vat_number", vatNumber]]) {
    if (value && !BUSINESS_IDENTIFIER_REGEX.test(value)) {
      throw new InputValidationError("INVALID_FORMAT", field);
    }
  }
  if (billingEmail && (!EMAIL_REGEX.test(billingEmail) || /[\r\n]/.test(String(input.billing_email)))) {
    throw new InputValidationError("INVALID_FORMAT", "billing_email");
  }
  if (vatNumber) {
    vatNumber = vatNumber.toUpperCase().replace(/[\s.\-_/]/g, "");
    if (!/^[A-Z]{2}[A-Z0-9]{2,12}$/.test(vatNumber) || !VIES_COUNTRY_CODES.has(vatNumber.slice(0, 2))) {
      throw new InputValidationError("INVALID_FORMAT", "vat_number");
    }
  }
  const businessValues = [company, enterpriseNumber, vatNumber, billingAddress, billingPostalCode, billingCity, billingCountry, billingEmail];
  if (customerType === null && businessValues.slice(1).some(Boolean)) {
    throw new InputValidationError("INVALID_CONDITION", "customer_type");
  }
  if (customerType === "individual" && businessValues.some(Boolean)) {
    throw new InputValidationError("INVALID_CONDITION", "customer_type");
  }
  if (customerType === "business") {
    for (const [field, value] of [
      ["company", company],
      ["enterprise_number", enterpriseNumber],
      ["billing_address", billingAddress],
      ["billing_postal_code", billingPostalCode],
      ["billing_city", billingCity],
      ["billing_country", billingCountry],
    ]) {
      if (!value) throw new InputValidationError("REQUIRED_FIELD", field);
    }
  }
  let enterpriseValidationStatus: EnterpriseValidationStatus = "not_checked";
  if (customerType === "business" && /^(be|belgi[eë]|belgium)$/i.test(billingCountry)) {
    enterpriseNumber = enterpriseNumber.replace(/[\s.\-_/]/g, "");
    if (!/^\d{10}$/.test(enterpriseNumber)) {
      throw new InputValidationError("INVALID_FORMAT", "enterprise_number");
    }
    const base = Number(enterpriseNumber.slice(0, 8));
    const checkDigits = Number(enterpriseNumber.slice(8));
    if (97 - (base % 97) !== checkDigits) {
      throw new InputValidationError("INVALID_FORMAT", "enterprise_number");
    }
    enterpriseValidationStatus = "format_valid_not_externally_verified";
  }
  assertLength("email", email, 5, 254);
  if (phone) {
    assertLength("phone", phone, 6, 40);
    const digitCount = (phone.match(/\d/g) || []).length;
    if (!PHONE_CHARACTERS_REGEX.test(phone) || digitCount < 6 || digitCount > 15) {
      throw new InputValidationError("INVALID_FORMAT", "phone");
    }
  }
  assertLength("website_type", websiteType, 2, 80);
  assertLength("budget", budget, 2, 80);
  assertLength("timing", timing, 2, 80);
  assertLength("description", description, 10, 3000);
  assertAllowed("website_type", websiteType, WEBSITE_TYPES);
  assertAllowed("budget", budget, BUDGETS);
  assertAllowed("timing", timing, TIMINGS);

  if (!EMAIL_REGEX.test(email)) {
    throw new InputValidationError("INVALID_FORMAT", "email");
  }

  if (input.privacy_consent !== true) {
    throw new InputValidationError("PRIVACY_CONSENT_REQUIRED", "privacy_consent");
  }

  return {
    name,
    customer_type: customerType,
    company: company || null,
    enterprise_number: enterpriseNumber || null,
    enterprise_validation_status: enterpriseValidationStatus,
    vat_number: vatNumber || null,
    billing_address: billingAddress || null,
    billing_postal_code: billingPostalCode || null,
    billing_city: billingCity || null,
    billing_country: billingCountry || null,
    billing_email: billingEmail || null,
    email,
    phone: phone || null,
    website_type: websiteType,
    budget,
    timing,
    description,
    privacy_consent: true,
    honeypotValue,
  };
}

export function validateAction(action: unknown): ReviewAction {
  if (
    action === "approved" ||
    action === "rejected" ||
    action === "retry_confirmation" ||
    action === "send_intake_invitation" ||
    action === "retry_intake_invitation"
  ) return action;
  throw new InputValidationError("INVALID_REVIEW_ACTION", "action");
}

export function validateToken(token: unknown): string {
  if (typeof token !== "string") throw new InputValidationError("INVALID_TOKEN", "token");
  const trimmed = token.trim();
  if (trimmed.length !== 43) throw new InputValidationError("INVALID_TOKEN", "token");
  if (!/^[A-Za-z0-9_-]+$/.test(trimmed)) throw new InputValidationError("INVALID_TOKEN", "token");
  return trimmed;
}

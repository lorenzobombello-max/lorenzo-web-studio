export interface ApplicationRecurringService {
  productId: "care" | "care_plus";
  label: "LWS Care" | "LWS Care+";
  amountMinor: number;
  unit: "month";
}

export interface ApplicationOutput {
  applicationReference: string | null;
  submittedAt: string;
  customer: {
    name: string;
    company: string | null;
    email: string;
    phone: string | null;
  };
  commercial: {
    packageId: "starter_v1" | "professional_v2";
    packageLabel: "Starter" | "Professional";
    budgetLabel: string;
    knownMinimumMinor: number;
    currency: "EUR";
    vatBasis: "exclusive";
    budgetStatus: string;
    recurringServices: ApplicationRecurringService[];
  };
  project: {
    websiteType: string | null;
    businessDescription: string | null;
    targetAudience: string | null;
    hasExistingWebsite: boolean;
    currentWebsite: string | null;
    elementsToKeep: string | null;
    improvementAreas: string | null;
    domain: string | null;
    hostingStatus: string | null;
    goals: string[];
    primaryConversionGoal: string | null;
  };
  website: {
    pages: string[];
    otherPages: string | null;
    features: string[];
    webshop: boolean;
    webshopDetails: Record<string, unknown> | null;
    booking: boolean;
    bookingDetails: Record<string, unknown> | null;
    pageScopeDetails: Record<string, unknown> | null;
    quoteFormDetails: Record<string, unknown> | null;
    primaryLanguage: string | null;
    additionalLanguages: string[];
    multilingualDetails: Record<string, unknown> | null;
    downloadDetails: Record<string, unknown> | null;
    newsletterDetails: Record<string, unknown> | null;
    integrations: string[];
    socialChannels: string[];
    seoPriority: string | null;
    seoDetails: Record<string, unknown> | null;
  };
  brandingContent: {
    brandStatus: string | null;
    logoStatus: string | null;
    brandColors: string[];
    designStyles: string[];
    inspirationSites: string[];
    dislikedStyles: string | null;
    contentStatus: string | null;
    imageStatus: string | null;
    imageSupport: string[];
    contentMediaDetails: Record<string, unknown> | null;
  };
  servicePlanning: {
    domainStatus: string | null;
    maintenanceInterest: string | null;
    hostingSupport: string | null;
    hostingMaintenanceDetails: Record<string, unknown> | null;
    deadline: string | null;
    deadlineReason: string | null;
    deadlineDetails: Record<string, unknown> | null;
    timing: string | null;
    priorities: string[];
    budgetNotes: string | null;
    notes: string | null;
  };
}

interface ApplicationOutputInput {
  recordClassification?: unknown;
  applicationReference: unknown;
  submittedAt: unknown;
  request: Record<string, unknown>;
  evidence: Record<string, unknown>;
  authoritativeSnapshot: Record<string, unknown>;
}

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0)
      .map((item) => item.trim())
    : [];
}

function recurringServices(value: unknown): ApplicationRecurringService[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new TypeError("INVALID_APPLICATION_RECURRING_SERVICES");
  return value.map((item) => {
    const service = record(item);
    const productId = service?.productId;
    const amountMinor = service?.amountMinor;
    if (
      (productId !== "care" && productId !== "care_plus") ||
      typeof amountMinor !== "number" || !Number.isSafeInteger(amountMinor) ||
      amountMinor <= 0 || service?.unit !== "month"
    ) throw new TypeError("INVALID_APPLICATION_RECURRING_SERVICES");
    return {
      productId,
      label: productId === "care" ? "LWS Care" : "LWS Care+",
      amountMinor: amountMinor as number,
      unit: "month",
    };
  });
}

export function buildApplicationOutput(input: ApplicationOutputInput): ApplicationOutput {
  const recordClassification = input.recordClassification === undefined
    ? "production"
    : input.recordClassification;
  const applicationReference = stringValue(input.applicationReference);
  const submittedAt = stringValue(input.submittedAt);
  const name = stringValue(input.request.name);
  const email = stringValue(input.request.email);
  const calculation = record(input.authoritativeSnapshot.calculation);
  const packageDefinition = record(input.authoritativeSnapshot.packageDefinition);
  const budgetEvaluation = record(input.authoritativeSnapshot.budgetEvaluation);
  const explicitAdditionalLanguages = stringArray(input.evidence.additional_languages);
  const packageId = packageDefinition?.id;
  const knownMinimumMinor = calculation?.knownMinimumMinor;
  if (
    (recordClassification !== "production" && recordClassification !== "internal_e2e") ||
    (recordClassification === "production" &&
      (!applicationReference || !/^LWS-AAN-[0-9]{4}-[0-9]{4}$/.test(applicationReference))) ||
    (recordClassification === "internal_e2e" && applicationReference !== null) ||
    !submittedAt || Number.isNaN(Date.parse(submittedAt)) || !name || !email ||
    (packageId !== "starter_v1" && packageId !== "professional_v2") ||
    typeof knownMinimumMinor !== "number" || !Number.isSafeInteger(knownMinimumMinor) ||
    knownMinimumMinor < 0 ||
    calculation?.currency !== "EUR" || calculation?.vatBasis !== "exclusive" ||
    typeof budgetEvaluation?.status !== "string"
  ) throw new TypeError("INVALID_APPLICATION_OUTPUT_SOURCE");

  return {
    applicationReference,
    submittedAt,
    customer: {
      name,
      company: stringValue(input.request.company),
      email,
      phone: stringValue(input.request.phone),
    },
    commercial: {
      packageId,
      packageLabel: packageId === "starter_v1" ? "Starter" : "Professional",
      budgetLabel: stringValue(budgetEvaluation.originalLabel) || stringValue(input.evidence.budget_update_category) || stringValue(input.request.budget) || "Niet opgegeven",
      knownMinimumMinor: knownMinimumMinor as number,
      currency: "EUR",
      vatBasis: "exclusive",
      budgetStatus: budgetEvaluation.status,
      recurringServices: recurringServices(input.authoritativeSnapshot.recurringServices),
    },
    project: {
      websiteType: stringValue(input.request.website_type),
      businessDescription: stringValue(input.evidence.business_description),
      targetAudience: stringValue(input.evidence.target_audience),
      hasExistingWebsite: input.evidence.has_existing_website === true,
      currentWebsite: stringValue(input.evidence.existing_website_url),
      elementsToKeep: stringValue(input.evidence.elements_to_keep),
      improvementAreas: stringValue(input.evidence.improvement_areas),
      domain: stringValue(input.evidence.domain_name),
      hostingStatus: stringValue(input.evidence.hosting_status),
      goals: stringArray(input.evidence.website_goals),
      primaryConversionGoal: stringValue(input.evidence.primary_conversion_goal),
    },
    website: {
      pages: stringArray(input.evidence.requested_pages),
      otherPages: stringValue(input.evidence.other_pages),
      features: stringArray(input.evidence.requested_features),
      webshop: input.evidence.shop_required === true,
      webshopDetails: record(input.evidence.shop_details),
      booking: input.evidence.booking_required === true,
      bookingDetails: record(input.evidence.booking_details),
      pageScopeDetails: record(input.evidence.page_scope_details),
      quoteFormDetails: record(input.evidence.quote_form_details),
      primaryLanguage: stringValue(input.evidence.primary_language),
      additionalLanguages: explicitAdditionalLanguages.length
        ? explicitAdditionalLanguages
        : stringArray(input.evidence.languages).filter((language) => language !== input.evidence.primary_language),
      multilingualDetails: record(input.evidence.multilingual_details),
      downloadDetails: record(input.evidence.download_details),
      newsletterDetails: record(input.evidence.newsletter_details),
      integrations: stringArray(input.evidence.integrations),
      socialChannels: stringArray(input.evidence.social_channels),
      seoPriority: stringValue(input.evidence.seo_priority),
      seoDetails: record(input.evidence.seo_details),
    },
    brandingContent: {
      brandStatus: stringValue(input.evidence.brand_status),
      logoStatus: stringValue(input.evidence.logo_status),
      brandColors: stringArray(input.evidence.brand_colors),
      designStyles: stringArray(input.evidence.design_styles),
      inspirationSites: stringArray(input.evidence.inspiration_sites),
      dislikedStyles: stringValue(input.evidence.disliked_styles),
      contentStatus: stringValue(input.evidence.content_status),
      imageStatus: stringValue(input.evidence.image_status),
      imageSupport: stringArray(input.evidence.image_support),
      contentMediaDetails: record(input.evidence.content_media_details),
    },
    servicePlanning: {
      domainStatus: stringValue(input.evidence.domain_status),
      maintenanceInterest: stringValue(input.evidence.maintenance_interest),
      hostingSupport: stringValue(input.evidence.hosting_support),
      hostingMaintenanceDetails: record(input.evidence.hosting_maintenance_details),
      deadline: stringValue(input.evidence.deadline_date),
      deadlineReason: stringValue(input.evidence.deadline_reason),
      deadlineDetails: record(input.evidence.deadline_details),
      timing: stringValue(input.request.timing),
      priorities: stringArray(input.evidence.priorities),
      budgetNotes: stringValue(input.evidence.budget_notes),
      notes: stringValue(input.evidence.additional_notes),
    },
  };
}
type IntakeReadStatus = "submitted" | "reviewed";

export type CustomerBudgetIndicator =
  | "known_minimum_exceeds_selected_budget"
  | "no_known_minimum_conflict_detected"
  | "not_reliably_comparable";

export type CustomerPricingState =
  | "indicative_starting_price_available"
  | "personal_review_required"
  | "pricing_result_unavailable";

interface CustomerPackageDefinition {
  selectedPackageDefinitionId: "starter_v1" | "professional_v1";
  label: "Starter" | "Professional";
  floorMinor: number;
  standardPageLimit: number;
  includedCorrectionRounds: number;
}

export interface CustomerPricingDTOv1 {
  presentationContractVersion: 1;
  requestStatus: IntakeReadStatus;
  pricingState: CustomerPricingState;
  requiresPersonalReview: boolean;
  formalQuotationRequired: true;
  budgetIndicator: CustomerBudgetIndicator;
  indicativeStartingPrice?: {
    amountMinor: number;
    currency: "EUR";
    vatLabel: "excl_btw";
    nonBinding: true;
    qualifier: "indicative_starting_price";
    disclaimerCode: "formal_quotation_determines_final_scope_and_price";
  };
  selectedPackage?: CustomerPackageDefinition;
}

type PriceMode = "included" | "fixed" | "from" | "manual";
type PackageAdviceStatus =
  | "none"
  | "consider_professional"
  | "manual_scope_review";
type BudgetProvenance =
  | "budget_guard_v1"
  | "legacy_label"
  | "missing"
  | "ambiguous";
type BudgetStatus =
  | "below_starter_starting_price"
  | "known_minimum_exceeds_category_upper_bound"
  | "possibly_compatible_with_category"
  | "unbounded_category_indeterminate"
  | "legacy_category_not_safely_comparable"
  | "manual_review_required";
type BudgetCategoryCode =
  | "below_1800"
  | "1800_to_below_3200"
  | "3200_to_6000_inclusive"
  | "above_6000";

interface AdminReason {
  code: string;
  label: string;
}

interface AdminCalculation {
  basis: "starter_floor" | "package_floor";
  knownMinimumMinor: number;
  currency: "EUR";
  vatBasis: "exclusive";
  containsFromPricing: boolean;
  manualReviewRequired: boolean;
  manualReasons: AdminReason[];
  appliedRules: Array<{
    ruleId: string;
    mode: PriceMode;
    quantity: number;
    amountMinor?: number;
    knownMinimumContributionMinor: number;
  }>;
}

interface AdminPackageDefinition {
  id: "starter_v1" | "professional_v1";
  version: 1;
  label: "Starter" | "Professional";
  floorMinor: number;
  standardPageLimit: number;
  includedCorrectionRounds: number;
  entitlementSetId: "normal_web_v1";
  entitlements: string[];
}

interface AdminPackageAdvice {
  status: PackageAdviceStatus;
  reasons: AdminReason[];
  advisoryOnly: true;
  selectedPackage: null;
}

interface AdminBudgetEvaluation {
  evidenceProvenance: BudgetProvenance;
  categoryScheme: "budget_guard_v1" | null;
  categoryCode: BudgetCategoryCode | null;
  originalLabel: string | null;
  status: BudgetStatus;
  outsideBudgetWishes: boolean | null;
  explanation: string;
}

interface AdminNormalizedScope {
  standardPages: string[];
  standardPageCount: number;
  primaryLanguage: string | null;
  additionalLanguages: string[];
  unknownLanguages: string[];
  modules: Array<{
    id: string;
    classification: string;
    evidence: string[];
  }>;
  manualComponents: string[];
}

export interface AdminPricingDTOv1 {
  presentationContractVersion: 1;
  requestStatus: IntakeReadStatus;
  availability: "available" | "historical_limited" | "unavailable";
  historicalResult: true;
  snapshotCreatedAt?: string;
  calculation?: AdminCalculation;
  packageAdvice?: AdminPackageAdvice;
  budget?: AdminBudgetEvaluation;
  normalizedScope?: AdminNormalizedScope;
  packageDefinition?: AdminPackageDefinition;
  audit?: {
    pricingConfigVersion: string;
    pricingConfigHash: string;
  };
}

const MANUAL_REASON_LABELS: Readonly<Record<string, string>> = {
  shop_manual: "Webshop of e-commerce vereist beoordeling",
  booking_manual: "Booking of reservatie-integratie vereist beoordeling",
  complex_form_manual: "Complex formulier of workflow vereist beoordeling",
  multilingual_manual: "Complexe meertaligheid vereist beoordeling",
  hosting_maintenance_manual: "Hosting, migratie of onderhoud vereist beoordeling",
  extensive_seo: "Uitgebreide SEO vereist beoordeling",
  customer_login: "Klantlogin vereist beoordeling",
  external_integration: "Externe integratie vereist beoordeling",
  secured_downloads: "Beveiligde downloads vereisen beoordeling",
  professional_photography: "Professionele fotografie vereist beoordeling",
  unresolved_search: "Zoekfunctionaliteit vereist beoordeling",
  rush_review: "Deadline vereist beoordeling",
  substantial_copywriting: "Substantiële copywriting vereist beoordeling",
  exceptional_image_work: "Uitzonderlijk beeldwerk vereist beoordeling",
  paid_stock_handling: "Betaalde stock vereist beoordeling",
  complex_gallery_scope: "Complexe galerijscope vereist beoordeling",
  complex_reviews_scope: "Complexe reviewsscope vereist beoordeling",
  complex_blog_scope: "Complexe blogscope vereist beoordeling",
  complex_jobs_scope: "Complexe vacature- of jobsscope vereist beoordeling",
  other_page_scope: "Andere paginascope vereist beoordeling",
  unknown_page_scope: "Onbekende paginascope vereist beoordeling",
  newsletter_manual: "Nieuwsbriefscope vereist beoordeling",
  standard_page_count_above_professional_scope:
    "Pagina-aantal valt buiten automatische pakketscope",
};

const PACKAGE_REASON_LABELS: Readonly<Record<string, string>> = {
  standard_page_count_above_starter_scope:
    "Pagina-aantal ligt boven de Starter-scope",
  standard_page_count_above_professional_scope:
    "Pagina-aantal ligt boven de Professional-scope",
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function readStatus(value: unknown): IntakeReadStatus {
  if (value === "submitted" || value === "reviewed") return value;
  throw new TypeError("Pricing read requires a submitted or reviewed intake");
}

function safeInteger(value: unknown, positive = false): number | null {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) ||
    value < (positive ? 1 : 0)
  ) return null;
  return value;
}

function stringArray(value: unknown): string[] | null {
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string")) {
    return null;
  }
  return [...value];
}

function parsePackageDefinition(value: unknown): AdminPackageDefinition | null {
  if (!isRecord(value)) return null;
  const expected = value.id === "starter_v1"
    ? { label: "Starter", floorMinor: 180_000, standardPageLimit: 5, includedCorrectionRounds: 1 }
    : value.id === "professional_v1"
    ? { label: "Professional", floorMinor: 320_000, standardPageLimit: 12, includedCorrectionRounds: 2 }
    : null;
  const entitlements = stringArray(value.entitlements);
  if (
    !expected || value.version !== 1 || value.label !== expected.label ||
    value.floorMinor !== expected.floorMinor ||
    value.standardPageLimit !== expected.standardPageLimit ||
    value.includedCorrectionRounds !== expected.includedCorrectionRounds ||
    value.entitlementSetId !== "normal_web_v1" || entitlements === null ||
    entitlements.length === 0 || new Set(entitlements).size !== entitlements.length
  ) return null;
  return {
    id: value.id as AdminPackageDefinition["id"],
    version: 1,
    label: expected.label as AdminPackageDefinition["label"],
    floorMinor: expected.floorMinor,
    standardPageLimit: expected.standardPageLimit,
    includedCorrectionRounds: expected.includedCorrectionRounds,
    entitlementSetId: "normal_web_v1",
    entitlements,
  };
}

function unavailableCustomer(
  requestStatus: IntakeReadStatus,
): CustomerPricingDTOv1 {
  return {
    presentationContractVersion: 1,
    requestStatus,
    pricingState: "pricing_result_unavailable",
    requiresPersonalReview: true,
    formalQuotationRequired: true,
    budgetIndicator: "not_reliably_comparable",
  };
}

function isBudgetStatus(value: unknown): value is BudgetStatus {
  return value === "below_starter_starting_price" ||
    value === "known_minimum_exceeds_category_upper_bound" ||
    value === "possibly_compatible_with_category" ||
    value === "unbounded_category_indeterminate" ||
    value === "legacy_category_not_safely_comparable" ||
    value === "manual_review_required";
}

function coherentBudgetSource(row: Record<string, unknown>): boolean {
  if (row.budget_contract_version !== 2 || !isBudgetStatus(row.budget_status)) {
    return false;
  }
  const provenance = row.evidence_provenance;
  const outside = row.outside_budget_wishes;
  const status = row.budget_status;
  if (provenance === "budget_guard_v1") {
    if (status === "legacy_category_not_safely_comparable") return false;
    if (
      status === "below_starter_starting_price" ||
      status === "known_minimum_exceeds_category_upper_bound"
    ) return outside === true;
    if (status === "possibly_compatible_with_category") return outside === false;
    return outside === null;
  }
  if (provenance === "legacy_label") {
    return outside === null &&
      (status === "legacy_category_not_safely_comparable" ||
        status === "manual_review_required");
  }
  if (provenance === "missing" || provenance === "ambiguous") {
    return outside === null && status === "manual_review_required";
  }
  return false;
}

function customerBudgetIndicator(
  outsideBudgetWishes: unknown,
): CustomerBudgetIndicator {
  if (outsideBudgetWishes === true) {
    return "known_minimum_exceeds_selected_budget";
  }
  if (outsideBudgetWishes === false) {
    return "no_known_minimum_conflict_detected";
  }
  return "not_reliably_comparable";
}

export function mapCustomerPricingReadRow(rowValue: unknown): CustomerPricingDTOv1 {
  if (!isRecord(rowValue)) throw new TypeError("Invalid customer pricing read source");
  const requestStatus = readStatus(rowValue.intake_status);
  if (
    rowValue.snapshot_present !== true ||
    (rowValue.snapshot_contract_version !== 2 && rowValue.snapshot_contract_version !== 3)
  ) {
    return unavailableCustomer(requestStatus);
  }

  const amountMinor = safeInteger(rowValue.known_minimum_minor, true);
  const manualReviewRequired = rowValue.manual_review_required;
  const manualReasonCount = safeInteger(rowValue.manual_reason_count);
  const packageDefinition = rowValue.snapshot_contract_version === 3
    ? parsePackageDefinition(rowValue.package_definition)
    : null;
  const calculationValid = (
    (rowValue.snapshot_contract_version === 2 &&
      rowValue.calculation_basis === "starter_floor") ||
    (rowValue.snapshot_contract_version === 3 &&
      rowValue.calculation_basis === "package_floor" && packageDefinition !== null)
  ) &&
    rowValue.currency === "EUR" && rowValue.vat_basis === "exclusive" &&
    amountMinor !== null && typeof rowValue.contains_from_pricing === "boolean" &&
    typeof manualReviewRequired === "boolean" && manualReasonCount !== null &&
    ((manualReviewRequired && manualReasonCount > 0) ||
      (!manualReviewRequired && manualReasonCount === 0));
  if (!calculationValid || !coherentBudgetSource(rowValue)) {
    return unavailableCustomer(requestStatus);
  }

  const budgetIndicator = customerBudgetIndicator(rowValue.outside_budget_wishes);
  if (manualReviewRequired) {
    return {
      presentationContractVersion: 1,
      requestStatus,
      pricingState: "personal_review_required",
      requiresPersonalReview: true,
      formalQuotationRequired: true,
      budgetIndicator,
      indicativeStartingPrice: {
        amountMinor,
        currency: "EUR",
        vatLabel: "excl_btw",
        nonBinding: true,
        qualifier: "indicative_starting_price",
        disclaimerCode: "formal_quotation_determines_final_scope_and_price",
      },
    };
  }

  return {
    presentationContractVersion: 1,
    requestStatus,
    pricingState: "indicative_starting_price_available",
    requiresPersonalReview: false,
    formalQuotationRequired: true,
    budgetIndicator,
    indicativeStartingPrice: {
      amountMinor,
      currency: "EUR",
      vatLabel: "excl_btw",
      nonBinding: true,
      qualifier: "indicative_starting_price",
      disclaimerCode: "formal_quotation_determines_final_scope_and_price",
    },
    ...(packageDefinition
      ? {
        selectedPackage: {
          selectedPackageDefinitionId: packageDefinition.id,
          label: packageDefinition.label,
          floorMinor: packageDefinition.floorMinor,
          standardPageLimit: packageDefinition.standardPageLimit,
          includedCorrectionRounds: packageDefinition.includedCorrectionRounds,
        },
      }
      : {}),
  };
}

function adminReason(code: string, labels: Readonly<Record<string, string>>): AdminReason {
  return { code, label: labels[code] ?? "Onbekende historische reden" };
}

function parseCalculation(value: unknown): AdminCalculation | null {
  if (!isRecord(value)) return null;
  const knownMinimumMinor = safeInteger(value.knownMinimumMinor);
  const manualReasons = stringArray(value.manualReasons);
  if (
    (value.basis !== "starter_floor" && value.basis !== "package_floor") ||
    value.currency !== "EUR" ||
    value.vatBasis !== "exclusive" || knownMinimumMinor === null ||
    typeof value.containsFromPricing !== "boolean" ||
    typeof value.manualReviewRequired !== "boolean" || manualReasons === null ||
    !Array.isArray(value.appliedRules) ||
    (value.manualReviewRequired !== (manualReasons.length > 0))
  ) return null;

  const appliedRules: AdminCalculation["appliedRules"] = [];
  for (const rawRule of value.appliedRules) {
    if (!isRecord(rawRule) || typeof rawRule.ruleId !== "string") return null;
    if (
      rawRule.mode !== "included" && rawRule.mode !== "fixed" &&
      rawRule.mode !== "from" && rawRule.mode !== "manual"
    ) return null;
    const quantity = safeInteger(rawRule.quantity);
    const contribution = safeInteger(rawRule.knownMinimumContributionMinor);
    const amount = rawRule.amountMinor === undefined
      ? undefined
      : safeInteger(rawRule.amountMinor);
    if (quantity === null || contribution === null || amount === null) return null;
    appliedRules.push({
      ruleId: rawRule.ruleId,
      mode: rawRule.mode,
      quantity,
      ...(amount === undefined ? {} : { amountMinor: amount }),
      knownMinimumContributionMinor: contribution,
    });
  }

  return {
    basis: value.basis,
    knownMinimumMinor,
    currency: "EUR",
    vatBasis: "exclusive",
    containsFromPricing: value.containsFromPricing,
    manualReviewRequired: value.manualReviewRequired,
    manualReasons: manualReasons.map((code) =>
      adminReason(code, MANUAL_REASON_LABELS)
    ),
    appliedRules,
  };
}

function parsePackageAdvice(value: unknown): AdminPackageAdvice | null {
  if (!isRecord(value)) return null;
  if (
    value.status !== "none" && value.status !== "consider_professional" &&
    value.status !== "manual_scope_review"
  ) return null;
  const reasons = stringArray(value.reasons);
  if (reasons === null || value.advisoryOnly !== true || value.selectedPackage !== null) {
    return null;
  }
  return {
    status: value.status,
    reasons: reasons.map((code) => adminReason(code, PACKAGE_REASON_LABELS)),
    advisoryOnly: true,
    selectedPackage: null,
  };
}

function parseNormalizedScope(value: unknown): AdminNormalizedScope | null {
  if (!isRecord(value)) return null;
  const standardPages = stringArray(value.standardPages);
  const standardPageCount = safeInteger(value.standardPageCount);
  const additionalLanguages = stringArray(value.additionalLanguages);
  const unknownLanguages = stringArray(value.unknownLanguages);
  const manualComponents = stringArray(value.manualComponents);
  if (
    standardPages === null || standardPageCount === null ||
    (value.primaryLanguage !== null && typeof value.primaryLanguage !== "string") ||
    additionalLanguages === null || unknownLanguages === null ||
    manualComponents === null || !Array.isArray(value.modules)
  ) return null;

  const modules: AdminNormalizedScope["modules"] = [];
  for (const rawModule of value.modules) {
    if (
      !isRecord(rawModule) || typeof rawModule.id !== "string" ||
      typeof rawModule.classification !== "string"
    ) return null;
    const evidence = stringArray(rawModule.evidence);
    if (evidence === null) return null;
    modules.push({
      id: rawModule.id,
      classification: rawModule.classification,
      evidence,
    });
  }
  return {
    standardPages,
    standardPageCount,
    primaryLanguage: value.primaryLanguage,
    additionalLanguages,
    unknownLanguages,
    modules,
    manualComponents,
  };
}

function isProvenance(value: unknown): value is BudgetProvenance {
  return value === "budget_guard_v1" || value === "legacy_label" ||
    value === "missing" || value === "ambiguous";
}

function isCategoryCode(value: unknown): value is BudgetCategoryCode {
  return value === "below_1800" || value === "1800_to_below_3200" ||
    value === "3200_to_6000_inclusive" || value === "above_6000";
}

function budgetExplanation(provenance: BudgetProvenance, status: BudgetStatus): string {
  if (provenance === "legacy_label") return "Legacybudget is niet veilig vergelijkbaar";
  if (provenance === "missing") return "Budgetinformatie ontbreekt";
  if (provenance === "ambiguous") return "Budgetinformatie is niet eenduidig";
  if (status === "known_minimum_exceeds_category_upper_bound") {
    return "Bekend minimum overschrijdt de bovengrens van de budgetcategorie";
  }
  if (status === "below_starter_starting_price") {
    return "Budgetcategorie ligt onder de Starter-vanafprijs";
  }
  if (status === "possibly_compatible_with_category") {
    return "Geen conflict met de bovengrens van de budgetcategorie vastgesteld";
  }
  if (status === "unbounded_category_indeterminate") {
    return "Open budgetcategorie is niet begrensd vergelijkbaar";
  }
  return "Persoonlijke budgetbeoordeling vereist";
}

function parseBudgetEvaluation(value: unknown): AdminBudgetEvaluation | null {
  if (!isRecord(value) || value.contractVersion !== 2) return null;
  if (!isProvenance(value.evidenceProvenance) || !isBudgetStatus(value.status)) {
    return null;
  }
  const source = {
    budget_contract_version: value.contractVersion,
    evidence_provenance: value.evidenceProvenance,
    budget_status: value.status,
    outside_budget_wishes: value.outsideBudgetWishes,
  };
  if (!coherentBudgetSource(source)) return null;

  const categoryScheme = value.categoryScheme === "budget_guard_v1"
    ? "budget_guard_v1"
    : value.categoryScheme === null
    ? null
    : undefined;
  const categoryCode = isCategoryCode(value.categoryCode)
    ? value.categoryCode
    : value.categoryCode === null
    ? null
    : undefined;
  const originalLabel = typeof value.originalLabel === "string"
    ? value.originalLabel
    : value.originalLabel === null
    ? null
    : undefined;
  if (
    categoryScheme === undefined || categoryCode === undefined ||
    originalLabel === undefined
  ) return null;
  if (
    value.evidenceProvenance === "budget_guard_v1" &&
    (categoryScheme !== "budget_guard_v1" || categoryCode === null || originalLabel === null)
  ) return null;
  if (
    value.evidenceProvenance !== "budget_guard_v1" &&
    (categoryScheme !== null || categoryCode !== null)
  ) return null;
  if (value.evidenceProvenance === "missing" && originalLabel !== null) return null;
  if (
    (value.evidenceProvenance === "legacy_label" ||
      value.evidenceProvenance === "ambiguous") && originalLabel === null
  ) return null;

  return {
    evidenceProvenance: value.evidenceProvenance,
    categoryScheme,
    categoryCode,
    originalLabel,
    status: value.status,
    outsideBudgetWishes: value.outsideBudgetWishes as boolean | null,
    explanation: budgetExplanation(value.evidenceProvenance, value.status),
  };
}

function auditMetadata(row: Record<string, unknown>) {
  if (
    typeof row.config_version !== "string" ||
    !/^[0-9]+\.[0-9]+\.[0-9]+$/.test(row.config_version) ||
    typeof row.config_hash !== "string" || !/^[0-9a-f]{64}$/.test(row.config_hash)
  ) return null;
  return {
    pricingConfigVersion: row.config_version,
    pricingConfigHash: row.config_hash,
  };
}

function unavailableAdmin(requestStatus: IntakeReadStatus): AdminPricingDTOv1 {
  return {
    presentationContractVersion: 1,
    requestStatus,
    availability: "unavailable",
    historicalResult: true,
  };
}

export function mapAdminPricingReadRow(rowValue: unknown): AdminPricingDTOv1 {
  if (!isRecord(rowValue)) throw new TypeError("Invalid admin pricing read source");
  const requestStatus = readStatus(rowValue.intake_status);
  if (rowValue.snapshot_present !== true) return unavailableAdmin(requestStatus);
  if (typeof rowValue.snapshot_created_at !== "string") {
    return unavailableAdmin(requestStatus);
  }

  const calculation = parseCalculation(rowValue.calculation);
  const packageAdvice = parsePackageAdvice(rowValue.package_advice);
  const normalizedScope = parseNormalizedScope(rowValue.normalized_scope);
  const audit = auditMetadata(rowValue);
  if (!calculation || !packageAdvice || !normalizedScope || !audit) {
    return unavailableAdmin(requestStatus);
  }

  if (rowValue.snapshot_contract_version === null) {
    return {
      presentationContractVersion: 1,
      requestStatus,
      availability: "historical_limited",
      historicalResult: true,
      snapshotCreatedAt: rowValue.snapshot_created_at,
      calculation,
      packageAdvice,
      normalizedScope,
      audit,
    };
  }
  if (
    rowValue.snapshot_contract_version !== 2 &&
    rowValue.snapshot_contract_version !== 3
  ) {
    return unavailableAdmin(requestStatus);
  }
  const packageDefinition = rowValue.snapshot_contract_version === 3
    ? parsePackageDefinition(rowValue.package_definition)
    : null;
  if (
    (rowValue.snapshot_contract_version === 2 && calculation.basis !== "starter_floor") ||
    (rowValue.snapshot_contract_version === 3 &&
      (calculation.basis !== "package_floor" || packageDefinition === null))
  ) return unavailableAdmin(requestStatus);
  const budget = parseBudgetEvaluation(rowValue.budget_evaluation);
  if (!budget) return unavailableAdmin(requestStatus);
  return {
    presentationContractVersion: 1,
    requestStatus,
    availability: "available",
    historicalResult: true,
    snapshotCreatedAt: rowValue.snapshot_created_at,
    calculation,
    packageAdvice,
    budget,
    normalizedScope,
    ...(packageDefinition ? { packageDefinition } : {}),
    audit,
  };
}
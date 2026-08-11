(function () {
  "use strict";

  const form = document.getElementById("intakeForm");
  if (!form) return;

  const tokenCandidate = new URLSearchParams(window.location.search).get("token") || "";
  const token = /^[A-Za-z0-9_-]{43}$/.test(tokenCandidate.trim()) ? tokenCandidate.trim() : "";
  if (tokenCandidate) {
    const sanitizedUrl = new URL(window.location.href);
    sanitizedUrl.searchParams.delete("token");
    window.history.replaceState(window.history.state, "", `${sanitizedUrl.pathname}${sanitizedUrl.search}${sanitizedUrl.hash}`);
  }

  const metaBase = document.querySelector('meta[name="lws-functions-base-url"]')?.getAttribute("content") || "";
  const functionsBaseUrl = metaBase.replace(/\/$/, "");
  const endpoint = functionsBaseUrl ? `${functionsBaseUrl}/intake-quote-request` : "";
  const loading = document.getElementById("intakeLoading");
  const unavailable = document.getElementById("intakeUnavailable");
  const unavailableMessage = document.getElementById("intakeUnavailableMessage");
  const workspace = document.getElementById("intakeWorkspace");
  const success = document.getElementById("intakeSuccess");
  const message = document.getElementById("intakeMessage");
  const lastSaved = document.getElementById("lastSaved");
  const saveButton = document.getElementById("saveDraft");
  const submitButton = document.getElementById("submitIntake");
  const nextButton = document.getElementById("nextStep");
  const previousButton = document.getElementById("previousStep");
  const modal = document.getElementById("submitModal");
  const modalPanel = modal?.querySelector(".intake-modal__panel");
  const confirmSubmit = document.getElementById("confirmSubmit");
  const steps = Array.from(form.querySelectorAll(".intake-step"));
  const stepButtons = Array.from(document.querySelectorAll("[data-step-target]"));
  const stepCounter = document.getElementById("stepCounter");
  const completionValue = document.getElementById("completionValue");
  const progressBar = document.getElementById("progressBar");
  const contextStatus = document.getElementById("contextStatus");
  const priorityCount = document.getElementById("priorityCount");
  const budgetGuardPreview = document.getElementById("budgetGuardPreview");
  const budgetGuardState = document.getElementById("budgetGuardState");
  const budgetGuardStatus = document.getElementById("budgetGuardStatus");
  const budgetGuardBudget = document.getElementById("budgetGuardBudget");
  const budgetGuardPackageRow = document.getElementById("budgetGuardPackageRow");
  const budgetGuardPackage = document.getElementById("budgetGuardPackage");
  const budgetGuardMinimumRow = document.getElementById("budgetGuardMinimumRow");
  const budgetGuardMinimum = document.getElementById("budgetGuardMinimum");
  const budgetGuardPackageAdvice = document.getElementById("budgetGuardPackageAdvice");
  const budgetGuardWarningActions = document.getElementById("budgetGuardWarningActions");
  const packageSelectionGroup = form.querySelector(".package-grid");
  let currentStep = 0;
  let dirty = false;
  let busy = false;
  let readOnly = false;
  let modalReturnFocus = null;
  let restoredLegacyBudget = null;
  let restoredBudgetEvidence = null;
  let budgetChoiceChanged = false;
  let scopeRevision = 0;
  let pricingEvidenceFingerprint = "";
  let activeRequestFingerprint = "";
  let previewTimer = null;
  let previewAbortController = null;
  let previewPausedUntil = 0;
  let previewStopped = false;
  let currentBudgetGuardStatus = "";
  let currentBudgetGuardKey = "";
  let currentBudgetGuardEvidenceFingerprint = "";
  let acknowledgedBudgetGuardKey = "";

  const PREVIEW_DEBOUNCE_MS = 350;
  const commaFields = ["languages", "brand_colors", "seo_keywords", "social_channels", "integrations"];
  const arrayFields = ["website_goals", "requested_pages", "requested_features", "design_styles", "image_support", "priorities"];
  const booleanFields = ["has_existing_website", "shop_required", "booking_required", "budget_confirmed"];
  const requiredSubmitFields = ["business_description", "target_audience", "primary_conversion_goal", "brand_status", "logo_status", "content_status", "image_status", "domain_status", "hosting_status", "maintenance_interest", "seo_priority"];
  const scopedPages = ["reviews", "blog", "jobs", "gallery"];
  const budgetCodes = {
    "Minder dan EUR 1.800": "below_1800",
    "EUR 1.800 tot minder dan EUR 3.200": "1800_to_below_3200",
    "EUR 3.200 t/m EUR 6.000": "3200_to_6000_inclusive",
    "Meer dan EUR 6.000": "above_6000",
  };
  const budgetLabels = {
    below_1800: "Minder dan € 1.800",
    "1800_to_below_3200": "€ 1.800 tot minder dan € 3.200",
    "3200_to_6000_inclusive": "€ 3.200 t/m € 6.000",
    above_6000: "Meer dan € 6.000",
  };
  const packageDefinitionIds = new Set(["starter_v1", "professional_v1"]);
  const pricingEvidenceFields = [
    "requested_pages", "requested_features", "website_goals", "shop_required", "shop_details",
    "booking_required", "booking_details", "page_scope_details", "quote_form_details", "primary_language",
    "additional_languages", "languages", "multilingual_details", "content_status", "image_status",
    "image_support", "content_media_details", "download_details", "newsletter_details", "hosting_status",
    "hosting_support", "maintenance_interest", "hosting_maintenance_details", "seo_priority", "seo_details",
    "integrations", "deadline_details", "budget_update_category", "budget_update_category_scheme",
    "budget_update_category_code", "selected_package_definition_id",
  ];
  const directPricingNames = new Set([
    "website_goals", "requested_pages", "requested_features", "shop_required", "booking_required",
    "primary_language", "content_status", "image_status", "image_support", "hosting_status",
    "hosting_support", "maintenance_interest", "seo_priority", "integrations", "budget_update_category",
    "selected_package_definition_id",
  ]);
  const conditionalPricingIds = new Set([
    "shop_product_count", "shop_categories", "shop_payments", "shop_shipping", "shop_pickup", "shop_catalog",
    "booking_type", "booking_existing", "booking_system_name", "booking_calendar", "page_scope_reviews",
    "page_scope_blog", "page_scope_jobs", "page_scope_gallery", "quote_form_count", "quote_file_uploads",
    "quote_database_workflow", "quote_automated_processing", "quote_review_approval", "quote_custom_logic",
    "translations_supplied", "same_language_structure", "multilingual_extensive_seo", "language_integrations",
    "multilingual_complex_scope", "download_access", "newsletter_scope", "copywriting_scope",
    "image_work_scope", "paid_stock_handling", "seo_extensive_services", "deadline_commercially_critical",
    "deadline_hard", "deadline_date", "deadline_reason",
  ]);
  const presentationAnchorSelectors = Object.freeze({
    EXTRA_STANDARD_PAGE: '[data-name="requested_pages"]',
    EXTRA_LANGUAGE: "#additionalLanguageChoices",
    CONTACT_FORM: 'input[name="requested_features"][value="contact_form"]',
    SIMPLE_QUOTE_FORM: "#quoteFormFields",
    EXTENDED_QUOTE_FORM: "#quoteFormFields",
    COMPLEX_FORM: "#quoteFormFields",
    SHOP: 'input[name="shop_required"][value="true"]',
    BOOKING: 'input[name="booking_required"][value="true"]',
    MULTILINGUAL_SCOPE: "#multilingualFields",
    CONTENT_MEDIA: "#content_status",
    HOSTING_MAINTENANCE: "#hosting_support",
    SEO_BASE: "#seo_priority",
    EXTENSIVE_SEO: "#seo_extensive_services",
    CUSTOMER_LOGIN: 'input[name="requested_features"][value="customer_login"]',
    EXTERNAL_INTEGRATION: "#integrations",
    SECURED_DOWNLOADS: "#downloadFields",
    PROFESSIONAL_PHOTOGRAPHY: 'input[name="image_support"][value="professional_photography"]',
    SEARCH: 'input[name="requested_features"][value="search"]',
    RUSH_SCOPE: "#deadlineFields",
    COPYWRITING: "#copywriting_scope",
    IMAGE_WORK: "#image_work_scope",
    PAID_STOCK: "#paid_stock_handling",
    GALLERY_SCOPE: "#page_scope_gallery",
    REVIEWS_SCOPE: "#page_scope_reviews",
    BLOG_SCOPE: "#page_scope_blog",
    JOBS_SCOPE: "#page_scope_jobs",
    OTHER_PAGE_SCOPE: 'input[name="requested_pages"][value="other"]',
    UNKNOWN_PAGE_SCOPE: '[data-name="requested_pages"]',
    NEWSLETTER_SCOPE: "#newsletterFields",
    PACKAGE_SCOPE: null,
  });
  const pricingBadges = new Map();
  const budgetStates = new Set(["WITHIN_KNOWN_BUDGET", "KNOWN_MINIMUM_ABOVE_BUDGET", "INDETERMINATE", "MANUAL_REVIEW"]);
  const itemStates = new Set(["INCLUDED", "FIXED_EXTRA", "FROM_EXTRA", "MANUAL_REVIEW"]);
  const packageAdviceStates = new Set(["NO_PACKAGE_ADVICE", "CONSIDER_PROFESSIONAL", "PERSONAL_REVIEW_RECOMMENDED"]);
  const euroFormatter = new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR", minimumFractionDigits: 0, maximumFractionDigits: 2 });
  const euroNumberFormatter = new Intl.NumberFormat("nl-BE", { minimumFractionDigits: 0, maximumFractionDigits: 2 });

  document.querySelectorAll("[data-options]").forEach((container) => {
    const name = container.getAttribute("data-name");
    const options = (container.getAttribute("data-options") || "").split(",");
    options.forEach((entry) => {
      const separator = entry.indexOf(":");
      const value = entry.slice(0, separator);
      const labelText = entry.slice(separator + 1);
      const label = document.createElement("label");
      const input = document.createElement("input");
      input.type = "checkbox";
      input.name = name;
      input.value = value;
      label.append(input, document.createTextNode(` ${labelText}`));
      container.appendChild(label);
    });
  });

  function setMessage(text, type) {
    message.textContent = text;
    message.classList.toggle("is-error", type === "error");
    message.classList.toggle("is-success", type === "success");
  }

  function setBusy(value, label) {
    busy = value;
    [saveButton, submitButton, nextButton, previousButton, confirmSubmit].forEach((button) => {
      if (button) button.disabled = value || readOnly;
    });
    if (label) setMessage(label, null);
  }

  function showUnavailable(text) {
    stopPricingPreview();
    loading.hidden = true;
    workspace.hidden = true;
    success.hidden = true;
    unavailableMessage.textContent = text;
    unavailable.hidden = false;
  }

  function showStep(index, focusHeading) {
    currentStep = Math.max(0, Math.min(steps.length - 1, index));
    steps.forEach((step, stepIndex) => { step.hidden = stepIndex !== currentStep; });
    stepButtons.forEach((button, stepIndex) => {
      if (stepIndex === currentStep) button.setAttribute("aria-current", "step");
      else button.removeAttribute("aria-current");
    });
    const percent = Math.round(((currentStep + 1) / steps.length) * 100);
    stepCounter.textContent = `Stap ${currentStep + 1} van ${steps.length}`;
    completionValue.textContent = `${percent}%`;
    progressBar.style.width = `${percent}%`;
    previousButton.hidden = currentStep === 0;
    nextButton.hidden = currentStep === steps.length - 1 || readOnly;
    submitButton.hidden = currentStep !== steps.length - 1 || readOnly;
    if (focusHeading) steps[currentStep].querySelector("input, textarea, select")?.focus();
  }

  function selectedBoolean(name) {
    const checked = form.querySelector(`input[name="${name}"]:checked`);
    return checked ? checked.value === "true" : null;
  }

  function selectedValues(name) {
    return Array.from(form.querySelectorAll(`input[name="${name}"]:checked`)).map((input) => input.value);
  }

  function splitList(value, separator) {
    return value.split(separator).map((item) => item.trim()).filter(Boolean);
  }

  function collectData() {
    const data = {};
    form.querySelectorAll("input[name]:not([type=checkbox]):not([type=radio]), textarea[name], select[name]").forEach((field) => {
      if (commaFields.includes(field.name)) data[field.name] = splitList(field.value, ",");
      else if (field.name === "inspiration_sites") data[field.name] = splitList(field.value, /\r?\n/);
      else data[field.name] = field.value.trim() || null;
    });
    arrayFields.forEach((name) => { data[name] = selectedValues(name); });
    booleanFields.forEach((name) => {
      const value = selectedBoolean(name);
      if (value !== null) data[name] = value;
    });
    const selectedPackage = form.querySelector('input[name="selected_package_definition_id"]:checked')?.value;
    if (packageDefinitionIds.has(selectedPackage)) data.selected_package_definition_id = selectedPackage;
    data.confirmation = document.getElementById("confirmation").checked;

    if (data.has_existing_website !== true) {
      data.existing_website_url = null;
      data.elements_to_keep = null;
      data.improvement_areas = null;
    }
    if (data.shop_required === true) {
      data.shop_details = {
        approx_product_count: Number(document.getElementById("shop_product_count").value),
        categories: document.getElementById("shop_categories").checked,
        online_payments: document.getElementById("shop_payments").checked,
        shipping: document.getElementById("shop_shipping").checked,
        pickup: document.getElementById("shop_pickup").checked,
        existing_catalog: document.getElementById("shop_catalog").checked,
      };
    } else data.shop_details = null;
    if (data.booking_required === true) {
      const existingSystem = document.getElementById("booking_existing").checked;
      data.booking_details = {
        type: document.getElementById("booking_type").value,
        existing_system: existingSystem,
        existing_system_name: existingSystem ? document.getElementById("booking_system_name").value.trim() || null : null,
        calendar_integration: document.getElementById("booking_calendar").checked,
      };
    } else data.booking_details = null;

    const primaryLanguage = document.getElementById("primary_language").value;
    const additionalLanguages = Array.from(form.querySelectorAll("[data-additional-language]:checked"))
      .map((input) => input.value)
      .filter((language) => language !== primaryLanguage);
    data.primary_language = primaryLanguage;
    data.additional_languages = additionalLanguages;
    data.languages = [primaryLanguage, ...additionalLanguages];

    const requestedPages = new Set(data.requested_pages);
    const pageScopeDetails = {};
    scopedPages.forEach((page) => {
      if (requestedPages.has(page)) pageScopeDetails[page] = document.getElementById(`page_scope_${page}`).value;
    });
    data.page_scope_details = Object.keys(pageScopeDetails).length ? pageScopeDetails : null;

    const requestedFeatures = new Set(data.requested_features);
    if (requestedFeatures.has("quote_form")) {
      const structureScope = form.querySelector('input[name="quote_structure_scope"]:checked')?.value;
      const quoteDetails = {
        file_uploads: document.getElementById("quote_file_uploads").checked,
        database_workflow: document.getElementById("quote_database_workflow").checked,
        automated_processing: document.getElementById("quote_automated_processing").checked,
        review_approval: document.getElementById("quote_review_approval").checked,
        custom_logic: document.getElementById("quote_custom_logic").checked,
        form_count: Number(document.getElementById("quote_form_count").value),
      };
      if (structureScope) quoteDetails.structure_scope = structureScope;
      data.quote_form_details = quoteDetails;
    } else data.quote_form_details = null;

    const multilingual = requestedFeatures.has("multilingual") || additionalLanguages.length > 0;
    data.multilingual_details = multilingual ? {
      final_translations_supplied: document.getElementById("translations_supplied").checked,
      same_structure: document.getElementById("same_language_structure").checked,
      extensive_seo: document.getElementById("multilingual_extensive_seo").checked,
      language_specific_integrations: document.getElementById("language_integrations").checked,
      complex_scope: document.getElementById("multilingual_complex_scope").checked,
    } : null;
    data.download_details = requestedFeatures.has("downloads") ? { access: document.getElementById("download_access").value } : null;
    data.newsletter_details = requestedFeatures.has("newsletter") ? { scope: document.getElementById("newsletter_scope").value } : null;
    data.content_media_details = {
      copywriting_scope: document.getElementById("copywriting_scope").value,
      image_work_scope: document.getElementById("image_work_scope").value,
      paid_stock_handling: document.getElementById("paid_stock_handling").checked,
    };
    data.hosting_maintenance_details = data.hosting_support || data.maintenance_interest ? {
      ...(data.hosting_support ? { hosting_support: data.hosting_support } : {}),
      ...(data.maintenance_interest ? { maintenance_interest: data.maintenance_interest } : {}),
    } : null;
    data.deadline_details = data.deadline_date || data.deadline_reason ? {
      commercially_critical: document.getElementById("deadline_commercially_critical").checked,
      hard_deadline: document.getElementById("deadline_hard").checked,
    } : null;
    data.seo_details = { extensive_services: document.getElementById("seo_extensive_services").checked };

    if (!budgetChoiceChanged && restoredLegacyBudget) data.budget_update_category = restoredLegacyBudget;
    const budgetCode = budgetCodes[data.budget_update_category];
    if (budgetCode) {
      data.budget_update_category_scheme = "budget_guard_v1";
      data.budget_update_category_code = budgetCode;
    } else if (!budgetCode && restoredBudgetEvidence) {
      data.budget_update_category = restoredBudgetEvidence.label;
      data.budget_update_category_scheme = "budget_guard_v1";
      data.budget_update_category_code = restoredBudgetEvidence.code;
    }
    return data;
  }

  function collectPricingEvidence() {
    const source = collectData();
    const evidence = {};
    pricingEvidenceFields.forEach((field) => {
      const value = source[field];
      if (value !== null && value !== undefined) evidence[field] = value;
    });
    if (
      evidence.content_status == null && evidence.image_status == null &&
      (!Array.isArray(evidence.image_support) || evidence.image_support.length === 0) &&
      evidence.content_media_details?.copywriting_scope === "unknown" &&
      evidence.content_media_details?.image_work_scope === "unknown" &&
      evidence.content_media_details?.paid_stock_handling === false
    ) delete evidence.content_media_details;
    if (evidence.seo_priority == null && evidence.seo_details?.extensive_services !== true) delete evidence.seo_details;
    if (
      evidence.deadline_details?.commercially_critical !== true &&
      evidence.deadline_details?.hard_deadline !== true
    ) delete evidence.deadline_details;
    return evidence;
  }

  function canonicalValue(value) {
    if (Array.isArray(value)) return value.map(canonicalValue);
    if (value && typeof value === "object") {
      return Object.keys(value).sort().reduce((output, key) => {
        output[key] = canonicalValue(value[key]);
        return output;
      }, {});
    }
    return value;
  }

  function pricingFingerprint(evidence) {
    return JSON.stringify(canonicalValue(evidence));
  }

  function budgetGuardAcknowledgementKey(preview, evidenceFingerprint) {
    const itemSemantics = preview.items.map((item) => ({
      presentationKey: item.presentationKey,
      state: item.state,
      amountMinor: item.amountMinor ?? null,
      quantity: item.quantity ?? null,
    })).sort((left, right) => left.presentationKey.localeCompare(right.presentationKey));
    return pricingFingerprint({
      evidenceFingerprint,
      previewVersion: preview.previewVersion,
      pricingConfigVersion: preview.pricingConfigVersion,
      comparisonStatus: preview.budget.comparisonStatus,
      selectedBudgetCategoryCode: preview.budget.selectedBudgetCategoryCode,
      knownMinimumMinor: preview.summary.knownMinimumMinor ?? null,
      containsFromPricing: preview.summary.containsFromPricing,
      manualReviewRequired: preview.summary.manualReviewRequired,
      selectedPackageDefinitionId: preview.selectedPackage?.selectedPackageDefinitionId ?? null,
      selectedPackageLabel: preview.selectedPackage?.label ?? null,
      packageFloorMinor: preview.selectedPackage?.floorMinor ?? null,
      itemSemantics,
    });
  }

  function budgetGuardAllowsSubmit(
    comparisonStatus,
    currentKey,
    acknowledgementKey,
    previewEvidenceFingerprint,
    currentEvidenceFingerprint,
  ) {
    if (!previewEvidenceFingerprint || previewEvidenceFingerprint !== currentEvidenceFingerprint) return false;
    return comparisonStatus !== "KNOWN_MINIMUM_ABOVE_BUDGET" ||
      Boolean(currentKey) && acknowledgementKey === currentKey;
  }

  function pricingPreviewMatchesCurrentEvidence(
    requestRevision,
    currentRevision,
    requestFingerprint,
    currentEvidenceFingerprint,
    aborted,
  ) {
    return !aborted && requestRevision === currentRevision && requestFingerprint === currentEvidenceFingerprint;
  }

  function invalidateCurrentBudgetGuardPreview() {
    currentBudgetGuardStatus = "";
    currentBudgetGuardKey = "";
    currentBudgetGuardEvidenceFingerprint = "";
  }

  function isPackageFloorMismatch(preview) {
    return preview.previewVersion === 2 &&
      preview.budget.comparisonStatus === "KNOWN_MINIMUM_ABOVE_BUDGET" &&
      Number.isSafeInteger(preview.summary.knownMinimumMinor) &&
      preview.summary.knownMinimumMinor === preview.selectedPackage.floorMinor &&
      preview.summary.containsFromPricing === false &&
      preview.items.every((item) => item.state === "INCLUDED");
  }

  function budgetGuardMismatchMessage(preview) {
    if (!isPackageFloorMismatch(preview)) return "Het huidige bekende minimum ligt boven je gekozen budget.";
    const floor = euroFormatter.format(preview.selectedPackage.floorMinor / 100);
    return `Het ${preview.selectedPackage.label}-pakket start vanaf ${floor} excl. btw. Je opgegeven budget ligt onder dit minimum.`;
  }

  function hasPricingEvidence(evidence) {
    return Boolean(
      evidence.budget_update_category || evidence.selected_package_definition_id ||
      evidence.shop_required === true || evidence.booking_required === true ||
      evidence.content_status || evidence.image_status || evidence.hosting_status || evidence.hosting_support ||
      evidence.maintenance_interest || evidence.seo_priority ||
      ["website_goals", "requested_pages", "requested_features", "additional_languages", "image_support", "integrations"]
        .some((field) => Array.isArray(evidence[field]) && evidence[field].length > 0)
    );
  }

  function isPricingControl(target) {
    return target instanceof HTMLElement && (
      directPricingNames.has(target.getAttribute("name")) || conditionalPricingIds.has(target.id) ||
      target.matches("[data-additional-language], input[name=\"quote_structure_scope\"]")
    );
  }

  function initializePricingAnchors() {
    Object.entries(presentationAnchorSelectors).forEach(([key, selector]) => {
      if (!selector) return;
      const target = document.querySelector(selector);
      if (!target) return;
      const anchor = target.closest("label") || target.closest(".field") || target;
      const badge = document.createElement("span");
      badge.className = "pricing-status";
      badge.dataset.presentationKey = key;
      badge.hidden = true;
      badge.innerHTML = '<span class="pricing-status__visible" aria-hidden="true"></span><span class="sr-only"></span>';
      anchor.appendChild(badge);
      pricingBadges.set(key, badge);
    });
  }

  function clearPricingPresentation() {
    pricingBadges.forEach((badge) => {
      badge.hidden = true;
      badge.className = "pricing-status";
      badge.querySelector(".pricing-status__visible").textContent = "";
      badge.querySelector(".sr-only").textContent = "";
    });
    budgetGuardMinimumRow.hidden = true;
    budgetGuardMinimum.textContent = "";
    budgetGuardPackageRow.hidden = true;
    budgetGuardPackage.textContent = "";
    budgetGuardPackageAdvice.hidden = true;
    budgetGuardPackageAdvice.textContent = "";
    budgetGuardWarningActions.hidden = true;
    budgetGuardPreview.classList.remove("budget-guard--within", "budget-guard--warning", "budget-guard--manual", "budget-guard--indeterminate", "budget-guard--unavailable");
  }

  function setPreviewLoading() {
    clearPricingPresentation();
    budgetGuardPreview.hidden = false;
    budgetGuardPreview.setAttribute("aria-busy", "true");
    budgetGuardState.textContent = "Bijwerken";
    budgetGuardStatus.textContent = "Prijsinformatie wordt bijgewerkt.";
  }

  function showPreviewUnavailable(text) {
    invalidateCurrentBudgetGuardPreview();
    clearPricingPresentation();
    budgetGuardPreview.hidden = false;
    budgetGuardPreview.setAttribute("aria-busy", "false");
    budgetGuardPreview.classList.add("budget-guard--unavailable");
    budgetGuardState.textContent = "Niet beschikbaar";
    budgetGuardStatus.textContent = text;
    budgetGuardBudget.textContent = selectedBudgetLabel(null);
  }

  function stopPricingPreview() {
    previewStopped = true;
    clearTimeout(previewTimer);
    previewTimer = null;
    previewAbortController?.abort();
    previewAbortController = null;
    activeRequestFingerprint = "";
    invalidateCurrentBudgetGuardPreview();
    budgetGuardPreview?.setAttribute("aria-busy", "false");
  }

  function selectedBudgetLabel(categoryCode) {
    if (categoryCode && budgetLabels[categoryCode]) return budgetLabels[categoryCode];
    const selectedLabel = document.getElementById("budget_update_category").value;
    const selectedCode = budgetCodes[selectedLabel];
    return selectedCode ? budgetLabels[selectedCode] : "Nog niet gekozen";
  }

  function validPreview(preview, revision) {
    if (
      !preview || typeof preview !== "object" || ![1, 2].includes(preview.previewVersion) ||
      preview.scopeRevision !== revision || preview.currency !== "EUR" || preview.vatBasis !== "exclusive" ||
      preview.nonBinding !== true || !preview.budget || !budgetStates.has(preview.budget.comparisonStatus) ||
      !(preview.budget.selectedBudgetCategoryCode === null || preview.budget.selectedBudgetCategoryCode in budgetLabels) ||
      !preview.summary || typeof preview.summary.containsFromPricing !== "boolean" ||
      typeof preview.summary.manualReviewRequired !== "boolean" || !Array.isArray(preview.items) ||
      !preview.packageAdvice || !packageAdviceStates.has(preview.packageAdvice.state)
    ) return false;
    const selectedPackageId = form.querySelector('input[name="selected_package_definition_id"]:checked')?.value;
    if (preview.previewVersion === 1 && selectedPackageId) return false;
    if (preview.previewVersion === 2) {
      const selectedPackage = preview.selectedPackage;
      if (
        !selectedPackage || typeof selectedPackage !== "object" ||
        !packageDefinitionIds.has(selectedPackage.selectedPackageDefinitionId) ||
        selectedPackage.selectedPackageDefinitionId !== selectedPackageId ||
        !["Starter", "Professional"].includes(selectedPackage.label) ||
        !Number.isSafeInteger(selectedPackage.floorMinor) || selectedPackage.floorMinor < 1 ||
        !Number.isSafeInteger(selectedPackage.standardPageLimit) || selectedPackage.standardPageLimit < 1 ||
        !Number.isSafeInteger(selectedPackage.includedCorrectionRounds) || selectedPackage.includedCorrectionRounds < 1
      ) return false;
    } else if ("selectedPackage" in preview) return false;
    if (
      preview.summary.manualReviewRequired === true && "knownMinimumMinor" in preview.summary ||
      "knownMinimumMinor" in preview.summary &&
        (!Number.isSafeInteger(preview.summary.knownMinimumMinor) || preview.summary.knownMinimumMinor < 0)
    ) return false;
    const seenKeys = new Set();
    return preview.items.every((item) => {
      if (
        !item || typeof item !== "object" || !(item.presentationKey in presentationAnchorSelectors) ||
        seenKeys.has(item.presentationKey) || item.labelKey !== `pricing_preview.${item.presentationKey.toLowerCase()}` ||
        !itemStates.has(item.state) || ("quantity" in item && (!Number.isSafeInteger(item.quantity) || item.quantity < 2))
      ) return false;
      seenKeys.add(item.presentationKey);
      const hasAmount = "amountMinor" in item;
      if (preview.summary.manualReviewRequired && hasAmount) return false;
      if (item.state === "FIXED_EXTRA" || item.state === "FROM_EXTRA") {
        return preview.summary.manualReviewRequired || hasAmount && Number.isSafeInteger(item.amountMinor) && item.amountMinor > 0;
      }
      return !hasAmount;
    });
  }

  function setPricingBadge(item, suppressAmounts) {
    if (item.presentationKey === "PACKAGE_SCOPE") return;
    const badge = pricingBadges.get(item.presentationKey);
    if (!badge) throw new TypeError("Missing pricing presentation anchor");
    let visibleText;
    let accessibleText;
    let stateClass;
    if (item.state === "INCLUDED") {
      visibleText = "Inbegrepen";
      accessibleText = "Inbegrepen — geen supplement.";
      stateClass = "included";
    } else if (item.state === "MANUAL_REVIEW") {
      visibleText = "Prijs op maat";
      accessibleText = "Prijs op maat.";
      stateClass = "manual";
    } else if (suppressAmounts) {
      visibleText = "Prijs na beoordeling";
      accessibleText = "Prijs na persoonlijke beoordeling.";
      stateClass = "manual";
    } else {
      const amount = item.amountMinor / 100;
      const formattedAmount = euroFormatter.format(amount);
      const spokenAmount = euroNumberFormatter.format(amount);
      const quantityVisible = item.quantity ? ` × ${item.quantity}` : "";
      const quantitySpoken = item.quantity ? `, aantal ${item.quantity}` : "";
      if (item.state === "FIXED_EXTRA") {
        visibleText = `+ ${formattedAmount}${quantityVisible}`;
        accessibleText = `Plus ${spokenAmount} euro exclusief btw${quantitySpoken}.`;
        stateClass = "fixed";
      } else {
        visibleText = `Vanaf + ${formattedAmount}${quantityVisible}`;
        accessibleText = `Vanaf plus ${spokenAmount} euro exclusief btw${quantitySpoken}.`;
        stateClass = "from";
      }
    }
    badge.classList.add(`pricing-status--${stateClass}`);
    badge.querySelector(".pricing-status__visible").textContent = visibleText;
    badge.querySelector(".sr-only").textContent = accessibleText;
    badge.hidden = false;
  }

  function renderPricingPreview(preview, evidenceFingerprint) {
    clearPricingPresentation();
    currentBudgetGuardStatus = preview.budget.comparisonStatus;
    currentBudgetGuardKey = budgetGuardAcknowledgementKey(preview, evidenceFingerprint);
    currentBudgetGuardEvidenceFingerprint = evidenceFingerprint;
    if (acknowledgedBudgetGuardKey !== currentBudgetGuardKey) acknowledgedBudgetGuardKey = "";
    const manual = preview.summary.manualReviewRequired;
    preview.items.forEach((item) => setPricingBadge(item, manual));
    budgetGuardPreview.hidden = false;
    budgetGuardPreview.setAttribute("aria-busy", "false");
    budgetGuardBudget.textContent = selectedBudgetLabel(preview.budget.selectedBudgetCategoryCode);
    if (preview.previewVersion === 2) {
      const selectedPackage = preview.selectedPackage;
      const rounds = selectedPackage.includedCorrectionRounds === 1 ? "correctieronde" : "correctierondes";
      budgetGuardPackage.textContent = `${selectedPackage.label} — max. ${selectedPackage.standardPageLimit} standaardpagina's, ${selectedPackage.includedCorrectionRounds} ${rounds}`;
      budgetGuardPackageRow.hidden = false;
    }
    if (!manual && Number.isSafeInteger(preview.summary.knownMinimumMinor)) {
      budgetGuardMinimum.textContent = `${euroFormatter.format(preview.summary.knownMinimumMinor / 100)} excl. btw`;
      budgetGuardMinimumRow.hidden = false;
    }
    const state = preview.budget.comparisonStatus;
    if (state === "WITHIN_KNOWN_BUDGET") {
      budgetGuardPreview.classList.add("budget-guard--within");
      budgetGuardState.textContent = "Huidige vergelijking";
      budgetGuardStatus.textContent = "Het huidige bekende minimum overschrijdt je gekozen budget niet.";
    } else if (state === "KNOWN_MINIMUM_ABOVE_BUDGET") {
      budgetGuardPreview.classList.add("budget-guard--warning");
      budgetGuardState.textContent = "Budget en pakket niet compatibel";
      budgetGuardStatus.textContent = budgetGuardMismatchMessage(preview);
      budgetGuardWarningActions.hidden = budgetGuardAllowsSubmit(
        state,
        currentBudgetGuardKey,
        acknowledgedBudgetGuardKey,
        currentBudgetGuardEvidenceFingerprint,
        pricingEvidenceFingerprint,
      );
    } else if (state === "MANUAL_REVIEW") {
      budgetGuardPreview.classList.add("budget-guard--manual");
      budgetGuardState.textContent = "Persoonlijke beoordeling";
      budgetGuardStatus.textContent = "Persoonlijke prijsbeoordeling vereist.";
    } else {
      budgetGuardPreview.classList.add("budget-guard--indeterminate");
      budgetGuardState.textContent = "Nog te bepalen";
      budgetGuardStatus.textContent = "We kunnen budget en scope nog niet betrouwbaar vergelijken.";
    }
    if (preview.packageAdvice.state === "CONSIDER_PROFESSIONAL") {
      budgetGuardPackageAdvice.textContent = "Op basis van je wensen kan Professional interessanter zijn. Er is geen pakket automatisch geselecteerd.";
      budgetGuardPackageAdvice.hidden = false;
    } else if (preview.packageAdvice.state === "PERSONAL_REVIEW_RECOMMENDED") {
      budgetGuardPackageAdvice.textContent = "Je wensen vragen een persoonlijke beoordeling. Er is geen pakket automatisch geselecteerd.";
      budgetGuardPackageAdvice.hidden = false;
    }
  }

  async function handlePreviewError(response, revision) {
    if (revision !== scopeRevision) return;
    if (response.status === 401) {
      showUnavailable("Deze intake-link is ongeldig of niet meer geldig.");
      return;
    }
    if (response.status === 409) {
      stopPricingPreview();
      await inspect();
      return;
    }
    if (response.status === 429) {
      const retryAfter = Number(response.headers.get("Retry-After"));
      const pauseSeconds = Number.isSafeInteger(retryAfter) && retryAfter > 0 ? Math.min(retryAfter, 3600) : 60;
      previewPausedUntil = Date.now() + pauseSeconds * 1000;
      showPreviewUnavailable("Prijsinformatie is tijdelijk gepauzeerd. Probeer na een korte wachttijd opnieuw.");
      return;
    }
    if (response.status === 400) {
      showPreviewUnavailable("Prijsinformatie kan niet worden bijgewerkt. Controleer je keuzes.");
    } else if (response.status === 413) {
      showPreviewUnavailable("De prijsinformatie kon niet worden bijgewerkt. Je kunt de intake gewoon verder invullen.");
    } else {
      showPreviewUnavailable("Prijsinformatie is tijdelijk niet beschikbaar. Je kunt de intake gewoon verder invullen.");
    }
  }

  async function requestBudgetGuardPreview(revision, evidence, fingerprint) {
    if (
      previewStopped ||
      !pricingPreviewMatchesCurrentEvidence(revision, scopeRevision, fingerprint, pricingEvidenceFingerprint, false)
    ) return;
    const controller = new AbortController();
    previewAbortController = controller;
    activeRequestFingerprint = fingerprint;
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "preview_budget_guard", token, scopeRevision: revision, data: evidence }),
        signal: controller.signal,
      });
      let body = {};
      try { body = await response.json(); } catch { body = {}; }
      if (!pricingPreviewMatchesCurrentEvidence(
        revision,
        scopeRevision,
        fingerprint,
        pricingEvidenceFingerprint,
        controller.signal.aborted,
      )) return;
      if (!response.ok) return await handlePreviewError(response, revision);
      if (!body.ok || !validPreview(body.preview, revision)) {
        showPreviewUnavailable("Prijsinformatie is tijdelijk niet beschikbaar. Je kunt de intake gewoon verder invullen.");
        return;
      }
      renderPricingPreview(body.preview, fingerprint);
    } catch (error) {
      if (error.name !== "AbortError" && revision === scopeRevision) {
        showPreviewUnavailable("Prijsinformatie is tijdelijk niet beschikbaar. Je kunt de intake gewoon verder invullen.");
      }
    } finally {
      if (revision === scopeRevision && previewAbortController === controller) {
        previewAbortController = null;
        activeRequestFingerprint = "";
        budgetGuardPreview.setAttribute("aria-busy", "false");
      }
    }
  }

  function schedulePricingPreview({ force = false, immediate = false } = {}) {
    if (readOnly || previewStopped || !token || !endpoint) return;
    const evidence = collectPricingEvidence();
    const fingerprint = pricingFingerprint(evidence);
    if (!force && fingerprint === pricingEvidenceFingerprint) return;
    if (fingerprint !== pricingEvidenceFingerprint) acknowledgedBudgetGuardKey = "";
    pricingEvidenceFingerprint = fingerprint;
    scopeRevision += 1;
    const revision = scopeRevision;
    invalidateCurrentBudgetGuardPreview();
    clearTimeout(previewTimer);
    previewTimer = null;
    previewAbortController?.abort();
    previewAbortController = null;
    activeRequestFingerprint = "";
    if (!hasPricingEvidence(evidence)) {
      clearPricingPresentation();
      budgetGuardPreview.hidden = true;
      budgetGuardPreview.setAttribute("aria-busy", "false");
      return;
    }
    if (Date.now() < previewPausedUntil) {
      showPreviewUnavailable("Prijsinformatie is tijdelijk gepauzeerd. Probeer na een korte wachttijd opnieuw.");
      return;
    }
    setPreviewLoading();
    const send = () => {
      if (activeRequestFingerprint === fingerprint || revision !== scopeRevision) return;
      requestBudgetGuardPreview(revision, evidence, fingerprint);
    };
    previewTimer = window.setTimeout(send, immediate ? 0 : PREVIEW_DEBOUNCE_MS);
  }

  function setChoice(name, value) {
    const input = form.querySelector(`input[name="${name}"][value="${String(value)}"]`);
    if (input) input.checked = true;
  }

  function restoreData(data) {
    if (!data || typeof data !== "object" || Array.isArray(data)) return;
    const restoredBudgetLabel = typeof data.budget_update_category === "string" ? data.budget_update_category : null;
    const restoredBudgetCode = typeof data.budget_update_category_code === "string" ? data.budget_update_category_code : null;
    const hasBudgetEvidence = data.budget_update_category_scheme === "budget_guard_v1" &&
      restoredBudgetLabel !== null && budgetCodes[restoredBudgetLabel] === restoredBudgetCode;
    restoredBudgetEvidence = hasBudgetEvidence ? { label: restoredBudgetLabel, code: restoredBudgetCode } : null;
    restoredLegacyBudget = restoredBudgetLabel && !hasBudgetEvidence ? restoredBudgetLabel : null;
    budgetChoiceChanged = false;
    if (packageDefinitionIds.has(data.selected_package_definition_id)) {
      setChoice("selected_package_definition_id", data.selected_package_definition_id);
    }
    Object.entries(data).forEach(([name, value]) => {
      if (arrayFields.includes(name) && Array.isArray(value)) {
        value.forEach((item) => setChoice(name, item));
        return;
      }
      if (booleanFields.includes(name) && typeof value === "boolean") {
        setChoice(name, value);
        return;
      }
      const field = form.elements.namedItem(name);
      if (!field || value === null) return;
      if (commaFields.includes(name) && Array.isArray(value)) field.value = value.join(", ");
      else if (name === "inspiration_sites" && Array.isArray(value)) field.value = value.join("\n");
      else if (typeof value === "string") field.value = value;
    });
    if (data.confirmation === true) document.getElementById("confirmation").checked = true;
    if (data.shop_details) {
      document.getElementById("shop_product_count").value = data.shop_details.approx_product_count || 1;
      document.getElementById("shop_categories").checked = data.shop_details.categories === true;
      document.getElementById("shop_payments").checked = data.shop_details.online_payments === true;
      document.getElementById("shop_shipping").checked = data.shop_details.shipping === true;
      document.getElementById("shop_pickup").checked = data.shop_details.pickup === true;
      document.getElementById("shop_catalog").checked = data.shop_details.existing_catalog === true;
    }
    if (data.booking_details) {
      document.getElementById("booking_type").value = data.booking_details.type || "appointments";
      document.getElementById("booking_existing").checked = data.booking_details.existing_system === true;
      document.getElementById("booking_system_name").value = data.booking_details.existing_system_name || "";
      document.getElementById("booking_calendar").checked = data.booking_details.calendar_integration === true;
    }
    const restoredLanguages = typeof data.primary_language === "string"
      ? [data.primary_language, ...(Array.isArray(data.additional_languages) ? data.additional_languages : [])]
      : Array.isArray(data.languages) ? data.languages : [];
    if (restoredLanguages.length) {
      const primaryLanguage = restoredLanguages[0];
      const primaryField = document.getElementById("primary_language");
      if (Array.from(primaryField.options).some((option) => option.value === primaryLanguage)) primaryField.value = primaryLanguage;
      restoredLanguages.slice(1).forEach((language) => {
        const input = form.querySelector(`[data-additional-language][value="${CSS.escape(String(language))}"]`);
        if (input) input.checked = true;
      });
    }
    if (data.page_scope_details) scopedPages.forEach((page) => {
      if (typeof data.page_scope_details[page] === "string") document.getElementById(`page_scope_${page}`).value = data.page_scope_details[page];
    });
    if (data.quote_form_details) {
      if (typeof data.quote_form_details.structure_scope === "string") {
        setChoice("quote_structure_scope", data.quote_form_details.structure_scope);
      }
      document.getElementById("quote_form_count").value = data.quote_form_details.form_count || 1;
      document.getElementById("quote_file_uploads").checked = data.quote_form_details.file_uploads === true;
      document.getElementById("quote_database_workflow").checked = data.quote_form_details.database_workflow === true;
      document.getElementById("quote_automated_processing").checked = data.quote_form_details.automated_processing === true;
      document.getElementById("quote_review_approval").checked = data.quote_form_details.review_approval === true;
      document.getElementById("quote_custom_logic").checked = data.quote_form_details.custom_logic === true;
    }
    if (data.multilingual_details) {
      document.getElementById("translations_supplied").checked = data.multilingual_details.final_translations_supplied === true;
      document.getElementById("same_language_structure").checked = data.multilingual_details.same_structure === true;
      document.getElementById("multilingual_extensive_seo").checked = data.multilingual_details.extensive_seo === true;
      document.getElementById("language_integrations").checked = data.multilingual_details.language_specific_integrations === true;
      document.getElementById("multilingual_complex_scope").checked = data.multilingual_details.complex_scope === true;
    }
    if (data.download_details?.access) document.getElementById("download_access").value = data.download_details.access;
    if (data.newsletter_details?.scope) document.getElementById("newsletter_scope").value = data.newsletter_details.scope;
    if (data.content_media_details) {
      document.getElementById("copywriting_scope").value = data.content_media_details.copywriting_scope || "unknown";
      document.getElementById("image_work_scope").value = data.content_media_details.image_work_scope || "unknown";
      document.getElementById("paid_stock_handling").checked = data.content_media_details.paid_stock_handling === true;
    }
    if (data.deadline_details) {
      document.getElementById("deadline_commercially_critical").checked = data.deadline_details.commercially_critical === true;
      document.getElementById("deadline_hard").checked = data.deadline_details.hard_deadline === true;
    }
    document.getElementById("seo_extensive_services").checked = data.seo_details?.extensive_services === true;
    updateConditionals();
    updatePriorities();
  }

  function updateConditionals() {
    const hasWebsite = selectedBoolean("has_existing_website") === true;
    document.getElementById("existingWebsiteFields").hidden = !hasWebsite;
    if (!hasWebsite) ["existing_website_url", "elements_to_keep", "improvement_areas"].forEach((id) => { document.getElementById(id).value = ""; });
    const shop = selectedBoolean("shop_required") === true;
    document.getElementById("shopFields").hidden = !shop;
    const booking = selectedBoolean("booking_required") === true;
    document.getElementById("bookingFields").hidden = !booking;
    const requestedPages = new Set(selectedValues("requested_pages"));
    document.getElementById("pageScopeFields").hidden = !scopedPages.some((page) => requestedPages.has(page));
    scopedPages.forEach((page) => {
      document.querySelector(`[data-page-scope="${page}"]`).hidden = !requestedPages.has(page);
    });
    const requestedFeatures = new Set(selectedValues("requested_features"));
    document.getElementById("quoteFormFields").hidden = !requestedFeatures.has("quote_form");
    const hasAdditionalLanguage = form.querySelector("[data-additional-language]:checked") !== null;
    document.getElementById("multilingualFields").hidden = !(requestedFeatures.has("multilingual") || hasAdditionalLanguage);
    document.getElementById("downloadFields").hidden = !requestedFeatures.has("downloads");
    document.getElementById("newsletterFields").hidden = !requestedFeatures.has("newsletter");
    document.getElementById("deadlineFields").hidden = !(document.getElementById("deadline_date").value || document.getElementById("deadline_reason").value.trim());
    const primaryLanguage = document.getElementById("primary_language").value;
    form.querySelectorAll("[data-additional-language]").forEach((input) => {
      if (input.value === primaryLanguage) input.checked = false;
      input.disabled = input.value === primaryLanguage || readOnly;
    });
  }

  function updatePriorities(changedInput) {
    const checked = selectedValues("priorities");
    if (checked.length > 3 && changedInput) changedInput.checked = false;
    const count = selectedValues("priorities").length;
    priorityCount.textContent = `${count} van 3 gekozen`;
    form.querySelectorAll('input[name="priorities"]:not(:checked)').forEach((input) => { input.disabled = count >= 3 || readOnly; });
  }

  function clearErrors() {
    form.querySelectorAll("[aria-invalid=true]").forEach((field) => field.removeAttribute("aria-invalid"));
    form.querySelectorAll(".field-error").forEach((node) => { node.textContent = ""; });
  }

  function markError(name, text) {
    const field = form.elements.namedItem(name);
    const first = field instanceof RadioNodeList ? field[0] : field;
    first?.setAttribute?.("aria-invalid", "true");
    const error = document.getElementById(`${name}-error`);
    if (error) error.textContent = text;
    if (name === "selected_package_definition_id") packageSelectionGroup?.setAttribute("aria-invalid", "true");
    return first || error;
  }

  function validatePackageSelection() {
    if (form.querySelector('input[name="selected_package_definition_id"]:checked')) return true;
    const firstInvalid = markError("selected_package_definition_id", "Kies Starter of Professional om verder te gaan.");
    firstInvalid?.focus?.();
    setMessage("Kies eerst een pakket. Je budgetkeuze blijft onafhankelijk.", "error");
    return false;
  }

  function validateSubmit() {
    clearErrors();
    const data = collectData();
    let firstInvalid = null;
    requiredSubmitFields.forEach((name) => {
      if (!data[name]) firstInvalid ||= markError(name, "Dit veld is verplicht.");
    });
    ["website_goals", "requested_pages", "design_styles", "priorities"].forEach((name) => {
      if (!data[name]?.length) firstInvalid ||= markError(name, "Kies minstens één optie.");
    });
    if (!data.selected_package_definition_id) {
      const packageInvalid = markError("selected_package_definition_id", "Kies Starter of Professional om je intake te verzenden.");
      firstInvalid ||= packageInvalid;
    }
    if (data.has_existing_website === true && !data.existing_website_url) firstInvalid ||= markError("existing_website_url", "Vul je huidige website in.");
    if (data.domain_status === "has_domain" && !data.domain_name) firstInvalid ||= markError("domain_name", "Vul je domeinnaam in.");
    if (!data.confirmation) firstInvalid ||= markError("confirmation", "Bevestig je briefing voor verzending.");
    if (firstInvalid) {
      const step = firstInvalid.closest?.(".intake-step");
      if (step) showStep(steps.indexOf(step));
      firstInvalid.focus?.();
      setMessage("Controleer de gemarkeerde velden.", "error");
      return false;
    }
    return validateBudgetGuardAcknowledgement();
  }

  function validateBudgetGuardAcknowledgement() {
    const previewIsCurrent = Boolean(currentBudgetGuardEvidenceFingerprint) &&
      currentBudgetGuardEvidenceFingerprint === pricingEvidenceFingerprint;
    if (!previewIsCurrent) {
      budgetGuardPreview.scrollIntoView?.({ behavior: "smooth", block: "center" });
      setMessage("Wacht tot de actuele prijsinformatie is bijgewerkt voordat je verzendt.", "error");
      return false;
    }
    if (budgetGuardAllowsSubmit(
      currentBudgetGuardStatus,
      currentBudgetGuardKey,
      acknowledgedBudgetGuardKey,
      currentBudgetGuardEvidenceFingerprint,
      pricingEvidenceFingerprint,
    )) return true;
    budgetGuardWarningActions.hidden = false;
    budgetGuardPreview.scrollIntoView?.({ behavior: "smooth", block: "center" });
    document.getElementById("continuePersonalReview")?.focus?.();
    setMessage("Bevestig bij Budget Guard dat je toch een persoonlijke beoordeling wilt aanvragen.", "error");
    return false;
  }

  async function request(action, data) {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action, token, ...(data ? { data } : {}) }),
    });
    let body = {};
    try { body = await response.json(); } catch { body = {}; }
    return { response, body };
  }

  function handleApiError(response, body) {
    if (response.status === 400) {
      if (body.field) markError(body.field, "Controleer dit veld.");
      setMessage("Controleer de gemarkeerde velden.", "error");
    } else if (response.status === 401) showUnavailable("Deze intake-link is ongeldig of niet meer geldig.");
    else if (response.status === 409) setReadOnly(body.code === "INTAKE_ALREADY_SUBMITTED" ? "submitted" : "reviewed");
    else setMessage("Er ging iets mis. Probeer later opnieuw.", "error");
  }

  async function saveDraft() {
    if (busy || readOnly) return;
    setBusy(true, "Concept wordt opgeslagen...");
    try {
      const { response, body } = await request("save_draft", collectData());
      if (!response.ok) return handleApiError(response, body);
      dirty = false;
      contextStatus.textContent = "In uitvoering";
      setMessage("Concept opgeslagen.", "success");
      lastSaved.textContent = `Laatst opgeslagen om ${new Date().toLocaleTimeString("nl-BE", { hour: "2-digit", minute: "2-digit" })}.`;
    } catch { setMessage("Er ging iets mis. Probeer later opnieuw.", "error"); }
    finally { setBusy(false); }
  }

  function openModal() {
    modalReturnFocus = document.activeElement;
    modal.hidden = false;
    document.body.classList.add("modal-open");
    modalPanel.focus();
  }

  function closeModal() {
    modal.hidden = true;
    document.body.classList.remove("modal-open");
    modalReturnFocus?.focus?.();
  }

  async function submitFinal() {
    if (busy || readOnly) return;
    closeModal();
    if (!validateBudgetGuardAcknowledgement()) return;
    setBusy(true, "Intake wordt verzonden...");
    try {
      const { response, body } = await request("submit", collectData());
      if (!response.ok) return handleApiError(response, body);
      if (body.state === "submitted" || body.state === "already_submitted") {
        dirty = false;
        setReadOnly("submitted");
      }
    } catch { setMessage("Er ging iets mis. Probeer later opnieuw.", "error"); }
    finally { setBusy(false); }
  }

  function setReadOnly(status) {
    stopPricingPreview();
    readOnly = true;
    dirty = false;
    setMessage("", null);
    form.querySelectorAll("input, textarea, select, button").forEach((control) => { control.disabled = true; });
    document.getElementById("intakeActions").hidden = true;
    form.classList.add("is-readonly");
    contextStatus.textContent = status === "reviewed" ? "Verwerkt" : "Verzonden";
    success.hidden = false;
    success.querySelector("h2").textContent = status === "reviewed" ? "Je intake werd al verwerkt." : "Bedankt. Je websitebriefing is succesvol verzonden.";
    success.focus();
    showStep(currentStep);
  }

  async function inspect() {
    previewStopped = false;
    if (!token || !endpoint) return showUnavailable("Deze intake-link is ongeldig of niet meer geldig.");
    try {
      const { response, body } = await request("inspect");
      if (!response.ok) return handleApiError(response, body);
      restoreData(body.data);
      document.getElementById("contextName").textContent = body.request?.company || body.request?.name || "Websiteproject";
      document.getElementById("contextType").textContent = body.request?.website_type || "Website";
      const status = body.intake?.status;
      contextStatus.textContent = status === "in_progress" ? "Concept hersteld" : status === "submitted" ? "Verzonden" : status === "reviewed" ? "Verwerkt" : "Nog niet gestart";
      loading.hidden = true;
      workspace.hidden = false;
      showStep(0);
      if (status === "in_progress") setMessage("Je eerder opgeslagen concept is hersteld.", "success");
      if (status === "submitted" || status === "reviewed") setReadOnly(status);
      else schedulePricingPreview({ force: true, immediate: true });
    } catch { showUnavailable("De intake kon niet worden geladen. Probeer later opnieuw."); }
  }

  form.addEventListener("input", (event) => {
    if (readOnly) return;
    dirty = true;
    if (event.target.name === "budget_update_category") budgetChoiceChanged = true;
    if (event.target.name === "selected_package_definition_id") {
      packageSelectionGroup?.removeAttribute("aria-invalid");
      document.getElementById("selected_package_definition_id-error").textContent = "";
      setMessage("", null);
    }
    if (event.target.name === "priorities") updatePriorities(event.target);
    if (
      ["has_existing_website", "shop_required", "booking_required", "requested_pages", "requested_features", "primary_language"].includes(event.target.name) ||
      event.target.matches("[data-additional-language], #deadline_date, #deadline_reason")
    ) updateConditionals();
    if (isPricingControl(event.target)) schedulePricingPreview();
  });
  form.addEventListener("submit", (event) => { event.preventDefault(); if (validateSubmit()) openModal(); });
  saveButton.addEventListener("click", saveDraft);
  nextButton.addEventListener("click", () => {
    if (currentStep === 1 && !validatePackageSelection()) return;
    showStep(currentStep + 1, true);
  });
  previousButton.addEventListener("click", () => showStep(currentStep - 1, true));
  stepButtons.forEach((button) => button.addEventListener("click", () => {
    const targetStep = Number(button.dataset.stepTarget);
    if (currentStep === 1 && targetStep > currentStep && !validatePackageSelection()) return;
    showStep(targetStep, true);
  }));
  modal?.querySelectorAll("[data-close-modal]").forEach((button) => button.addEventListener("click", closeModal));
  confirmSubmit?.addEventListener("click", submitFinal);
  document.getElementById("adjustBudget").addEventListener("click", () => {
    showStep(1);
    document.getElementById("budget_update_category")?.focus?.();
  });
  document.getElementById("changePackage").addEventListener("click", () => {
    showStep(1);
    (form.querySelector('input[name="selected_package_definition_id"]:checked') ||
      form.querySelector('input[name="selected_package_definition_id"]'))?.focus?.();
  });
  document.getElementById("continuePersonalReview").addEventListener("click", () => {
    if (
      currentBudgetGuardStatus !== "KNOWN_MINIMUM_ABOVE_BUDGET" || !currentBudgetGuardKey ||
      currentBudgetGuardEvidenceFingerprint !== pricingEvidenceFingerprint
    ) return;
    acknowledgedBudgetGuardKey = currentBudgetGuardKey;
    budgetGuardWarningActions.hidden = true;
    setMessage("Je aanvraag wordt ondanks de budgetafwijking persoonlijk beoordeeld.", "success");
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !modal.hidden) closeModal();
    if (event.key === "Tab" && !modal.hidden) {
      const focusable = Array.from(modal.querySelectorAll("button:not([disabled])"));
      const first = focusable[0]; const last = focusable[focusable.length - 1];
      if (event.shiftKey && (document.activeElement === modalPanel || document.activeElement === first)) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
  window.addEventListener("beforeunload", (event) => { if (dirty && !readOnly) event.preventDefault(); });

  initializePricingAnchors();
  inspect();
})();

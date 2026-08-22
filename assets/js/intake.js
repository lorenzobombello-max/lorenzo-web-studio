(function () {
  "use strict";

  const form = document.getElementById("intakeForm");
  if (!form) return;

  const screenDefinitions = [
    { phase: 0, title: "Budget", intro: "Geef uw budgetverwachting mee. Zo vergelijken we uw keuzes meteen met een realistische projectbasis.", nodes: [
      ['input[name="budget_confirmed"]'], ["#budget_update_category"], ["#budget_notes"],
    ] },
    { phase: 0, title: "Huidige situatie", intro: "We brengen eerst uw bestaande website, domeinnaam en hosting in kaart.", nodes: [
      ['input[name="has_existing_website"]'], ["#existingWebsiteFields", ".conditional-panel"], ["#domain_status"], ["#domain_name"], ["#hosting_status"], ["#hosting_support"],
    ] },
    { phase: 0, title: "Webshop en reservaties", intro: "Bepaal vroeg of verkoop, reservaties of afspraken deel uitmaken van de technische oplossing.", nodes: [
      ['input[name="shop_required"]'], ["#shopFields", ".conditional-panel"], ['input[name="booking_required"]'], ["#bookingFields", ".conditional-panel"], ['input[name="online_payment_required"]'], ["#onlinePaymentFields", ".conditional-panel"],
    ] },
    { phase: 1, title: "Kies uw pakket", intro: "Kies de bestaande pakketbasis die het best aansluit bij de omvang van uw website.", nodes: [
      [".package-selection", ".package-selection"],
    ] },
    { phase: 1, title: "Bedrijf en doelen", intro: "Vertel wat uw organisatie doet, wie u wilt bereiken en welke actie uw website moet stimuleren.", nodes: [
      ["#business_description"], ["#target_audience"], ['[data-group="website_goals"]'], ["#primary_conversion_goal"],
    ] },
    { phase: 2, title: "Pagina's", intro: "Selecteer de pagina's die u nodig hebt. Elke geselecteerde standaardpagina telt binnen de bestaande pakketlimiet.", nodes: [
      ['[data-name="requested_pages"]'], ["#other_pages"], ["#pageScopeFields", ".conditional-panel"],
    ] },
    { phase: 2, title: "Functies en formulieren", intro: "Kies de functionaliteit die bezoekers nodig hebben en verfijn alleen de relevante onderdelen.", nodes: [
      ['[data-name="requested_features"]'], ["#quoteFormFields", ".conditional-panel"], ["#downloadFields", ".conditional-panel"], ["#newsletterFields", ".conditional-panel"],
    ] },
    { phase: 2, title: "Talen, SEO en integraties", intro: "Bepaal talen, vindbaarheid, metingen en koppelingen in één samenhangend overzicht.", nodes: [
      ["#primary_language"], ["#additionalLanguageChoices"], ["#multilingualFields", ".conditional-panel"], ["#seo_priority"], ["#seo_keywords"], ["#social_channels"], ["#integrations"], ["#seo_scope"], ["#seo_extra_language", ".choice-grid"], ["#analytics_scope"],
    ] },
    { phase: 3, title: "Merk en stijl", intro: "Leg de huidige merkbasis en de gewenste visuele richting vast.", nodes: [
      ['[data-name="design_styles"]'], ["#brand_status"], ["#logo_status"], ["#logoDeliveryFields"], ["#branding_tier"], ["#brand_colors"], ["#inspiration_sites"], ["#disliked_styles"],
    ] },
    { phase: 3, title: "Content en media", intro: "Geef aan wat beschikbaar is en waar tekst- of beeldondersteuning nodig is.", nodes: [
      ["#content_status"], ["#image_status"], ['[data-name="image_support"]'], ["#imageDeliveryFields"], ["#copywriting_scope", ".conditional-panel"],
    ] },
    { phase: 4, title: "Service en planning", intro: "Kies eventuele vervolgservice en geef een realistische gewenste planning mee.", nodes: [
      ["#maintenance_interest"], ["#domain_service"], ["#maintenance_plan"], ["#deadline_date"], ["#deadline_reason"], ["#deadlineFields", ".conditional-panel"],
    ] },
    { phase: 4, title: "Controle en verzenden", intro: "Controleer uw keuzes en de actuele niet-bindende prijsindicatie voordat u verzendt.", review: true, nodes: [
      ['[data-name="priorities"]'], ["#additional_notes"], ["#confirmation", ".confirmation-field"],
    ] },
  ];
  const phaseStartScreens = [0, 3, 5, 8, 10];
  const phaseLabels = ["Uw project", "Uw oplossing", "Uw website", "Uw uitstraling", "Afronding"];

  function initializeIntakeScreens() {
    const controlsBefore = new Set(form.querySelectorAll("input, select, textarea"));
    const originalSteps = Array.from(form.querySelectorAll(".intake-step"));
    const actions = document.getElementById("intakeActions");

    screenDefinitions.forEach((definition, index) => {
      const fieldset = document.createElement("fieldset");
      fieldset.className = "intake-step";
      fieldset.dataset.step = String(index);
      fieldset.dataset.phase = String(definition.phase);
      fieldset.hidden = true;
      const legend = document.createElement("legend");
      legend.textContent = definition.title;
      const intro = document.createElement("p");
      intro.className = "intake-step__intro";
      intro.textContent = definition.intro;
      fieldset.append(legend, intro);
      if (definition.review) {
        const review = document.createElement("div");
        review.id = "intakeReviewSummary";
        review.className = "intake-review field--full";
        review.setAttribute("aria-live", "polite");
        fieldset.append(review);
      }
      definition.nodes.forEach(([selector, closestSelector]) => {
        const control = form.querySelector(selector);
        const node = closestSelector ? control?.closest(closestSelector) : control?.closest(".field") || control;
        if (!node) throw new TypeError(`Missing intake screen node: ${selector}`);
        if (!fieldset.contains(node)) fieldset.append(node);
      });
      form.insertBefore(fieldset, actions);
    });
    originalSteps.forEach((step) => step.remove());

    const controlsAfter = new Set(form.querySelectorAll("input, select, textarea"));
    if (controlsBefore.size !== controlsAfter.size || [...controlsBefore].some((control) => !controlsAfter.has(control))) {
      throw new TypeError("INTAKE_SCREEN_CONTROL_MISMATCH");
    }
  }

  function intakeTokenCandidate(search, state) {
    const queryToken = new URLSearchParams(search).get("token") || "";
    const historyToken = state && typeof state === "object" && typeof state.intakeToken === "string"
      ? state.intakeToken
      : "";
    const candidate = (queryToken || historyToken).trim();
    return /^[A-Za-z0-9_-]{43}$/.test(candidate) ? candidate : "";
  }

  const queryTokenCandidate = new URLSearchParams(window.location.search).get("token") || "";
  const token = intakeTokenCandidate(window.location.search, window.history.state);
  if (queryTokenCandidate) {
    const sanitizedUrl = new URL(window.location.href);
    sanitizedUrl.searchParams.delete("token");
    const currentState = window.history.state && typeof window.history.state === "object"
      ? window.history.state
      : {};
    const nextState = token ? { ...currentState, intakeToken: token } : currentState;
    window.history.replaceState(nextState, "", `${sanitizedUrl.pathname}${sanitizedUrl.search}${sanitizedUrl.hash}`);
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
  const submitModal = document.getElementById("submitModal");
  const resetModal = document.getElementById("resetModal");
  const resetButton = document.getElementById("resetDraft");
  const confirmSubmit = document.getElementById("confirmSubmit");
  const confirmReset = document.getElementById("confirmReset");
  let steps = [];
  const phaseButtons = Array.from(document.querySelectorAll("[data-phase-target]"));
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
  const budgetGuardPackageName = document.getElementById("budgetGuardPackageName");
  const budgetGuardPackagePages = document.getElementById("budgetGuardPackagePages");
  const budgetGuardPackageRounds = document.getElementById("budgetGuardPackageRounds");
  const budgetGuardMinimumRow = document.getElementById("budgetGuardMinimumRow");
  const budgetGuardMinimum = document.getElementById("budgetGuardMinimum");
  const budgetGuardRecurringRow = document.getElementById("budgetGuardRecurringRow");
  const budgetGuardRecurring = document.getElementById("budgetGuardRecurring");
  const budgetGuardPackageAdvice = document.getElementById("budgetGuardPackageAdvice");
  const budgetGuardWarningActions = document.getElementById("budgetGuardWarningActions");
  const packageSelectionGroup = form.querySelector(".package-grid");
  let currentStep = 0;
  let furthestStep = 0;
  let dirty = false;
  let busy = false;
  let readOnly = false;
  let activeModal = null;
  let modalReturnFocus = null;
  let draftRevision = null;
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
  const validationErrors = new Map();
  let validationMessageActive = false;

  const PREVIEW_DEBOUNCE_MS = 350;
  const PREVIEW_CONTRACT_VERSION = 3;
  const commaFields = ["languages", "brand_colors", "seo_keywords", "social_channels", "integrations"];
  const arrayFields = ["website_goals", "requested_pages", "requested_features", "design_styles", "image_support", "priorities"];
  const booleanFields = ["has_existing_website", "shop_required", "booking_required", "budget_confirmed"];
  const requiredSubmitFields = ["budget_update_category", "business_description", "target_audience", "primary_conversion_goal", "brand_status", "logo_status", "content_status", "image_status", "domain_status", "hosting_status", "maintenance_interest", "seo_priority"];
  const scopedPages = ["portfolio", "reviews", "blog", "jobs", "gallery"];
  const onlinePaymentPurposeValues = ["products", "reservations", "appointments", "services", "registrations", "deposit", "other"];
  const onlinePaymentPurposeFeatures = onlinePaymentPurposeValues.map((purpose) => `online_payment_${purpose}`);
  const budgetCodes = {
    "Minder dan EUR 1.800": "below_1800",
    "EUR 1.800 tot minder dan EUR 3.500": "1800_to_below_3500",
    "EUR 3.500 t/m EUR 6.000": "3500_to_6000_inclusive",
    "Meer dan EUR 6.000": "above_6000",
  };
  const budgetLabels = {
    below_1800: "Minder dan € 1.800",
    "1800_to_below_3500": "€ 1.800 tot minder dan € 3.500",
    "3500_to_6000_inclusive": "€ 3.500 t/m € 6.000",
    above_6000: "Meer dan € 6.000",
    "1800_to_below_3200": "Historisch: € 1.800 tot minder dan € 3.200",
    "3200_to_6000_inclusive": "Historisch: € 3.200 t/m € 6.000",
  };
  const historicalBudgetCodes = {
    "Minder dan EUR 1.800": "below_1800",
    "EUR 1.800 tot minder dan EUR 3.200": "1800_to_below_3200",
    "EUR 3.200 t/m EUR 6.000": "3200_to_6000_inclusive",
    "Meer dan EUR 6.000": "above_6000",
  };
  const packageDefinitionIds = new Set(["starter_v1", "professional_v2"]);
  const pricingEvidenceFields = [
    "requested_pages", "requested_features", "website_goals", "shop_required", "shop_details",
    "booking_required", "booking_details", "page_scope_details", "quote_form_details", "primary_language",
    "additional_languages", "languages", "multilingual_details", "content_status", "image_status",
    "image_support", "content_media_details", "brand_status", "logo_status", "download_details", "newsletter_details", "hosting_status",
    "hosting_support", "maintenance_interest", "hosting_maintenance_details", "seo_priority", "seo_details",
    "integrations", "deadline_details", "budget_update_category", "budget_update_category_scheme",
    "budget_update_category_code", "selected_package_definition_id",
  ];
  const directPricingNames = new Set([
    "website_goals", "requested_pages", "requested_features", "shop_required", "booking_required",
    "online_payment_required", "online_payment_purposes",
    "primary_language", "brand_status", "logo_status", "content_status", "image_status", "image_support", "hosting_status",
    "hosting_support", "maintenance_interest", "seo_priority", "integrations", "budget_update_category",
    "selected_package_definition_id",
  ]);
  const conditionalPricingIds = new Set([
    "shop_product_count", "shop_complex_product_count", "shop_payment_provider_count", "shop_shipping_scope",
    "shop_categories", "shop_payments", "shop_shipping", "shop_pickup_scope", "shop_catalog", "shop_customer_accounts",
    "shop_catalog_import", "shop_erp_api", "booking_tier", "booking_type", "booking_existing",
    "booking_system_name", "booking_calendar", "page_scope_portfolio", "page_scope_reviews", "page_scope_blog",
    "page_scope_jobs", "jobs_application", "page_scope_gallery", "search_tier", "quote_form_count", "quote_file_uploads",
    "quote_database_workflow", "quote_automated_processing", "quote_review_approval", "quote_custom_logic",
    "translations_supplied", "same_language_structure", "translation_required", "seo_per_language",
    "advanced_seo_research", "language_integrations", "multilingual_complex_scope", "download_access",
    "newsletter_scope", "copywriting_scope", "copy_page_count", "image_work_scope", "paid_stock_handling",
    "branding_tier", "domain_service", "maintenance_plan", "seo_scope", "seo_extra_language",
    "seo_advanced_language", "analytics_scope", "custom_integration", "deadline_commercially_critical",
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
    EXTENSIVE_SEO: "#seo_scope",
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
    INDETERMINATE_SCOPE: 'input[name="image_support"][value="unsure"]',
    UNKNOWN_FEATURE_SCOPE: 'input[name="requested_features"][value="unsure"]',
    DYNAMIC_PORTFOLIO: "#page_scope_portfolio",
    DOCUMENT_FLOW: "#download_access",
    CUSTOMER_PORTAL: "#download_access",
    STOCK_SELECTION: "#image_work_scope",
    EXTENDED_BRANDING: "#branding_tier",
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

  initializeIntakeScreens();
  steps = Array.from(form.querySelectorAll(".intake-step"));

  function setMessage(text, type) {
    message.textContent = text;
    message.classList.toggle("is-error", type === "error");
    message.classList.toggle("is-success", type === "success");
  }

  function setBusy(value, label) {
    busy = value;
    [saveButton, submitButton, nextButton, previousButton, resetButton, confirmSubmit, confirmReset].forEach((button) => {
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
    furthestStep = Math.max(furthestStep, currentStep);
    steps.forEach((step, stepIndex) => { step.hidden = stepIndex !== currentStep; });
    const activePhase = Number(steps[currentStep].dataset.phase);
    phaseButtons.forEach((button, phaseIndex) => {
      const nextPhaseStart = phaseStartScreens[phaseIndex + 1];
      button.classList.toggle("is-complete", Number.isInteger(nextPhaseStart) && furthestStep >= nextPhaseStart);
      button.disabled = phaseStartScreens[phaseIndex] > furthestStep;
      if (phaseIndex === activePhase) button.setAttribute("aria-current", "step");
      else button.removeAttribute("aria-current");
    });
    const percent = Math.round(((currentStep + 1) / steps.length) * 100);
    stepCounter.textContent = steps[currentStep].querySelector("legend")?.textContent || "Intake";
    completionValue.textContent = `Fase ${activePhase + 1} van 5`;
    progressBar.style.width = `${percent}%`;
    previousButton.hidden = currentStep === 0;
    nextButton.hidden = currentStep === steps.length - 1 || readOnly;
    submitButton.hidden = currentStep !== steps.length - 1 || readOnly;
    if (currentStep === steps.length - 1) renderReviewSummary();
    if (focusHeading) steps[currentStep].querySelector("input, textarea, select")?.focus();
  }

  function selectedBoolean(name) {
    const checked = form.querySelector(`input[name="${name}"]:checked`);
    return checked ? checked.value === "true" : null;
  }

  function selectedValues(name) {
    return Array.from(form.querySelectorAll(`input[name="${name}"]:checked`)).map((input) => input.value);
  }

  function selectedLocalDelivery(name) {
    return form.querySelector(`input[name="${name}"]:checked`)?.value || "";
  }

  function formatLocalFileSize(bytes) {
    return bytes < 1024 * 1024
      ? `${Math.max(1, Math.round(bytes / 1024))} KB`
      : `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  function clearLocalFileSelection(inputId, summaryId, errorId) {
    document.getElementById(inputId).value = "";
    document.getElementById(summaryId).replaceChildren();
    document.getElementById(errorId).textContent = "";
  }

  function renderLocalFileSelection(input, summaryId, errorId, maxFiles, maxBytes) {
    const summary = document.getElementById(summaryId);
    const error = document.getElementById(errorId);
    const files = Array.from(input.files || []);
    summary.replaceChildren();
    error.textContent = "";
    if (files.length > maxFiles) {
      input.value = "";
      error.textContent = `Selecteer maximaal ${maxFiles} bestand${maxFiles === 1 ? "" : "en"}.`;
      return;
    }
    const invalid = files.find((file) => !["image/png", "image/jpeg", "image/webp"].includes(file.type) || file.size > maxBytes);
    if (invalid) {
      input.value = "";
      error.textContent = `${invalid.name}: kies PNG, JPEG of WebP binnen de toegestane bestandsgrootte.`;
      return;
    }
    files.forEach((file, fileIndex) => {
      const row = document.createElement("div");
      row.className = "local-file";
      const details = document.createElement("span");
      details.textContent = `${file.name} · ${file.type} · ${formatLocalFileSize(file.size)} · lokaal geselecteerd, niet verzonden`;
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "local-file__remove";
      remove.textContent = "Verwijderen";
      remove.addEventListener("click", () => {
        const transfer = new DataTransfer();
        files.filter((_, index) => index !== fileIndex).forEach((remainingFile) => transfer.items.add(remainingFile));
        input.files = transfer.files;
        renderLocalFileSelection(input, summaryId, errorId, maxFiles, maxBytes);
        dirty = true;
      });
      row.append(details, remove);
      summary.append(row);
    });
  }

  function bindLocalFilePreview(inputId, summaryId, errorId, maxFiles, maxBytes) {
    const input = document.getElementById(inputId);
    input.addEventListener("change", () => renderLocalFileSelection(input, summaryId, errorId, maxFiles, maxBytes));
  }

  function localDeliveryReview(method, inputId) {
    if (method === "later") return "Later aanleveren";
    if (method !== "now") return "";
    return document.getElementById(inputId).files?.length
      ? "Lokaal geselecteerd; nog niet verzonden"
      : "Nu aanleveren gekozen; nog geen bestand verzonden";
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
    data.requested_features = data.requested_features.filter((feature) =>
      feature !== "online_payment" && !onlinePaymentPurposeFeatures.includes(feature));
    if (selectedBoolean("online_payment_required") === true) {
      data.requested_features.push("online_payment");
      selectedValues("online_payment_purposes").forEach((purpose) => {
        if (onlinePaymentPurposeValues.includes(purpose)) data.requested_features.push(`online_payment_${purpose}`);
      });
    }
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
      const pickupScope = document.getElementById("shop_pickup_scope").value;
      const shippingScope = document.getElementById("shop_shipping_scope").value;
      const onlinePayment = selectedBoolean("online_payment_required") === true;
      data.shop_details = {
        approx_product_count: Number(document.getElementById("shop_product_count").value),
        complex_product_count: Number(document.getElementById("shop_complex_product_count").value),
        ...(onlinePayment ? { payment_provider_count: Number(document.getElementById("shop_payment_provider_count").value) } : {}),
        ...(shippingScope !== "none" ? { shipping_scope: shippingScope } : {}),
        categories: document.getElementById("shop_categories").checked,
        online_payments: document.getElementById("shop_payments").checked,
        shipping: shippingScope !== "none",
        pickup: pickupScope !== "none",
        pickup_scope: pickupScope,
        existing_catalog: document.getElementById("shop_catalog").checked,
        customer_accounts: document.getElementById("shop_customer_accounts").checked,
        catalog_import: document.getElementById("shop_catalog_import").checked,
        erp_api: document.getElementById("shop_erp_api").checked,
      };
    } else data.shop_details = null;
    if (data.booking_required === true) {
      const existingSystem = document.getElementById("booking_existing").checked;
      data.booking_details = {
        tier: document.getElementById("booking_tier").value,
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
    const requestedFeatures = new Set(data.requested_features);
    const pageScopeDetails = {};
    scopedPages.forEach((page) => {
      if (requestedPages.has(page)) pageScopeDetails[page] = document.getElementById(`page_scope_${page}`).value;
    });
    if (requestedPages.has("jobs")) {
      pageScopeDetails.jobs_application = document.getElementById("jobs_application").value;
    }
    if (requestedFeatures.has("search")) pageScopeDetails.search = document.getElementById("search_tier").value;
    data.page_scope_details = Object.keys(pageScopeDetails).length ? pageScopeDetails : null;

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
      translation_required: document.getElementById("translation_required").checked,
      seo_per_language: document.getElementById("seo_per_language").checked,
      advanced_seo_research: document.getElementById("advanced_seo_research").checked,
      language_specific_integrations: document.getElementById("language_integrations").checked,
      complex_scope: document.getElementById("multilingual_complex_scope").checked,
    } : null;
    data.download_details = requestedFeatures.has("downloads") ? { access: document.getElementById("download_access").value } : null;
    const advancedAnalytics = document.getElementById("analytics_scope").value === "advanced";
    const customIntegration = document.getElementById("custom_integration").checked;
    data.newsletter_details = requestedFeatures.has("newsletter") || advancedAnalytics || customIntegration ? {
      ...(requestedFeatures.has("newsletter") ? { scope: document.getElementById("newsletter_scope").value } : {}),
      analytics: document.getElementById("analytics_scope").value,
      custom_integration: customIntegration,
    } : null;
    const copywritingScope = document.getElementById("copywriting_scope").value;
    data.content_media_details = {
      copywriting_scope: copywritingScope,
      ...(["substantial", "new"].includes(copywritingScope)
        ? { copy_page_count: Number(document.getElementById("copy_page_count").value) }
        : {}),
      image_work_scope: document.getElementById("image_work_scope").value,
      paid_stock_handling: document.getElementById("paid_stock_handling").checked,
      branding_tier: document.getElementById("branding_tier").value,
    };
    data.hosting_maintenance_details = data.hosting_support || data.maintenance_interest ? {
      ...(data.hosting_support ? { hosting_support: data.hosting_support } : {}),
      ...(data.maintenance_interest ? { maintenance_interest: data.maintenance_interest } : {}),
      domain_service: document.getElementById("domain_service").value,
      maintenance_plan: document.getElementById("maintenance_plan").value,
    } : null;
    data.deadline_details = data.deadline_date || data.deadline_reason ? {
      commercially_critical: document.getElementById("deadline_commercially_critical").checked,
      hard_deadline: document.getElementById("deadline_hard").checked,
    } : null;
    data.seo_details = {
      scope: document.getElementById("seo_scope").value,
      extra_language_seo: document.getElementById("seo_extra_language").checked,
      advanced_language_seo: document.getElementById("seo_advanced_language").checked,
    };

    if (!budgetChoiceChanged && restoredLegacyBudget) data.budget_update_category = restoredLegacyBudget;
    const budgetCode = budgetCodes[data.budget_update_category];
    if (!budgetChoiceChanged && restoredBudgetEvidence) {
      data.budget_update_category = restoredBudgetEvidence.label;
      data.budget_update_category_scheme = restoredBudgetEvidence.scheme;
      data.budget_update_category_code = restoredBudgetEvidence.code;
    } else if (budgetCode) {
      data.budget_update_category_scheme = "budget_guard_v2";
      data.budget_update_category_code = budgetCode;
    }
    return data;
  }

  function selectedControlText(id) {
    const control = document.getElementById(id);
    if (!control) return "Niet ingevuld";
    if (control instanceof HTMLSelectElement) {
      return control.selectedOptions[0]?.textContent?.trim() || "Niet ingevuld";
    }
    return control.value?.trim() || "Niet ingevuld";
  }

  function selectedChoiceLabels(name) {
    return Array.from(form.querySelectorAll(`input[name="${name}"]:checked`))
      .filter((input) => !input.hidden)
      .map((input) => input.closest("label")?.textContent?.trim() || input.value);
  }

  function appendReviewSection(container, title, rows) {
    const section = document.createElement("section");
    section.className = "intake-review__section";
    const heading = document.createElement("h3");
    heading.textContent = title;
    const list = document.createElement("dl");
    rows.forEach(([label, value]) => {
      const row = document.createElement("div");
      const term = document.createElement("dt");
      const description = document.createElement("dd");
      term.textContent = label;
      description.textContent = Array.isArray(value) ? value.join(", ") || "Geen" : String(value || "Niet ingevuld");
      row.append(term, description);
      list.append(row);
    });
    section.append(heading, list);
    container.append(section);
  }

  function renderReviewSummary() {
    const container = document.getElementById("intakeReviewSummary");
    if (!container) return;
    const packageName = form.querySelector('input[name="selected_package_definition_id"]:checked')
      ?.closest(".package-card")?.querySelector(".package-card__name")?.textContent?.trim() || "Niet gekozen";
    const shopRequired = selectedBoolean("shop_required") === true;
    const bookingRequired = selectedBoolean("booking_required") === true;
    const hasShop = shopRequired ? "Ja" : "Nee";
    const hasBooking = bookingRequired ? "Ja" : "Nee";
    const hasOnlinePayment = selectedBoolean("online_payment_required") === true ? "Ja" : "Nee";
    const logoDelivery = selectedLocalDelivery("logo_delivery_method");
    const imageDelivery = selectedLocalDelivery("image_delivery_method");
    const additionalLanguages = Array.from(form.querySelectorAll("[data-additional-language]:checked"))
      .map((input) => input.closest("label")?.textContent?.trim() || input.value);
    const appearanceRows = [
      ["Huisstijl", selectedControlText("brand_status")],
      ["Logo", selectedControlText("logo_status")],
      ["Stijl", selectedChoiceLabels("design_styles")],
      ["Teksten", selectedControlText("content_status")],
      ["Beelden", selectedControlText("image_status")],
    ];
    if (logoDelivery) appearanceRows.splice(2, 0, ["Logo-aanlevering", localDeliveryReview(logoDelivery, "logoFilePreview")]);
    if (imageDelivery) appearanceRows.push(["Beeldaanlevering", localDeliveryReview(imageDelivery, "imageFilePreview")]);
    const solutionRows = [["Webshop", hasShop]];
    if (shopRequired) solutionRows.push(["Verzending", selectedControlText("shop_shipping_scope")]);
    solutionRows.push(["Reservaties of afspraken", hasBooking]);
    if (bookingRequired) {
      const existingSystem = document.getElementById("booking_existing").checked;
      solutionRows.push(
        ["Reservatieoplossing", selectedControlText("booking_tier")],
        ["Type reservatie of afspraak", selectedControlText("booking_type")],
        ["Bestaand systeem", existingSystem ? "Ja" : "Nee"],
      );
      const existingSystemName = document.getElementById("booking_system_name").value.trim();
      if (existingSystem && existingSystemName) solutionRows.push(["Naam bestaand systeem", existingSystemName]);
      solutionRows.push(["Kalenderkoppeling", document.getElementById("booking_calendar").checked ? "Ja" : "Nee"]);
    }
    solutionRows.push(
      ["Online betalingen", hasOnlinePayment],
      ["Betalingsdoel", selectedChoiceLabels("online_payment_purposes")],
      ["Domein", selectedControlText("domain_status")],
      ["Hosting", selectedControlText("hosting_status")],
    );
    container.replaceChildren();
    appendReviewSection(container, "Project", [
      ["Budget", selectedControlText("budget_update_category")],
      ["Pakket", packageName],
      ["Prijsindicatie", budgetGuardMinimumRow.hidden ? "Wordt berekend" : budgetGuardMinimum.textContent],
      ["Bedrijf", selectedControlText("business_description")],
      ["Doelgroep", selectedControlText("target_audience")],
    ]);
    appendReviewSection(container, "Oplossing", solutionRows);
    appendReviewSection(container, "Website", [
      ["Pagina's", selectedChoiceLabels("requested_pages")],
      ["Functies", selectedChoiceLabels("requested_features")],
      ["Hoofdtaal", selectedControlText("primary_language")],
      ["Extra talen", additionalLanguages],
      ["SEO", selectedControlText("seo_scope")],
    ]);
    appendReviewSection(container, "Uitstraling", appearanceRows);
    appendReviewSection(container, "Afronding", [
      ["Onderhoud", selectedControlText("maintenance_interest")],
      ["Deadline", selectedControlText("deadline_date")],
      ["Prioriteiten", selectedChoiceLabels("priorities")],
    ]);
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
    if (
      evidence.seo_priority == null && evidence.seo_details?.scope === "included" &&
      evidence.seo_details?.extra_language_seo !== true &&
      evidence.seo_details?.advanced_language_seo !== true
    ) delete evidence.seo_details;
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
    const recurringServices = (preview.recurringServices || []).map((service) => ({
      presentationKey: service.presentationKey,
      amountMinor: service.amountMinor,
      unit: service.unit,
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
      recurringServices,
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
      preview.summary.knownMinimumMinor === preview.selectedPackage.floorMinor;
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
    budgetGuardRecurringRow.hidden = true;
    budgetGuardRecurring.textContent = "";
    budgetGuardPackageRow.hidden = true;
    budgetGuardPackageName.textContent = "";
    budgetGuardPackagePages.textContent = "";
    budgetGuardPackageRounds.textContent = "";
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
      !preview || typeof preview !== "object" || preview.previewContractVersion !== PREVIEW_CONTRACT_VERSION ||
      ![1, 2].includes(preview.previewVersion) ||
      preview.scopeRevision !== revision || preview.currency !== "EUR" || preview.vatBasis !== "exclusive" ||
      preview.nonBinding !== true || !preview.budget || !budgetStates.has(preview.budget.comparisonStatus) ||
      !(preview.budget.selectedBudgetCategoryCode === null || preview.budget.selectedBudgetCategoryCode in budgetLabels) ||
      !preview.summary || typeof preview.summary.containsFromPricing !== "boolean" ||
      typeof preview.summary.manualReviewRequired !== "boolean" || !Array.isArray(preview.items) ||
      !preview.packageAdvice || !packageAdviceStates.has(preview.packageAdvice.state)
    ) return false;
    if (
      preview.summary.manualReviewRequired
        ? preview.summary.manualScope !== "ESSENTIAL" && preview.summary.manualScope !== "OPTIONAL"
        : "manualScope" in preview.summary
    ) return false;
    if ("recurringServices" in preview) {
      if (!Array.isArray(preview.recurringServices) || !preview.recurringServices.every((service) =>
        service && typeof service === "object" && ["CARE", "CARE_PLUS"].includes(service.presentationKey) &&
        Number.isSafeInteger(service.amountMinor) && service.amountMinor > 0 && service.unit === "MONTH"
      )) return false;
    }
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
      "knownMinimumMinor" in preview.summary &&
        (!Number.isSafeInteger(preview.summary.knownMinimumMinor) || preview.summary.knownMinimumMinor < 0)
    ) return false;
    const seenKeys = new Set();
    return preview.items.every((item) => {
      if (
        !item || typeof item !== "object" || !(item.presentationKey in presentationAnchorSelectors) ||
        seenKeys.has(item.presentationKey) || item.labelKey !== `pricing_preview.${item.presentationKey.toLowerCase()}` ||
        !itemStates.has(item.state) || ("quantity" in item && (!Number.isSafeInteger(item.quantity) || item.quantity < 2)) ||
        ("externalCost" in item && item.externalCost !== true)
      ) return false;
      seenKeys.add(item.presentationKey);
      const hasAmount = "amountMinor" in item;
      if (item.state === "FIXED_EXTRA" || item.state === "FROM_EXTRA") {
        return hasAmount && Number.isSafeInteger(item.amountMinor) && item.amountMinor > 0;
      }
      return !hasAmount;
    });
  }

  function previewValidationRejectCode(preview, revision) {
    if (!preview || typeof preview !== "object") return "INVALID_PREVIEW_DTO";
    if (preview.previewContractVersion !== PREVIEW_CONTRACT_VERSION) return "PREVIEW_CONTRACT_MISMATCH";
    return validPreview(preview, revision) ? "" : "INVALID_PREVIEW_DTO";
  }

  function setPricingBadge(item) {
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
    if (item.externalCost === true) {
      visibleText += " · licentiekosten niet inbegrepen";
      accessibleText += " Externe licentiekosten niet inbegrepen.";
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
    preview.items.forEach((item) => setPricingBadge(item));
    budgetGuardPreview.hidden = false;
    budgetGuardPreview.setAttribute("aria-busy", "false");
    budgetGuardBudget.textContent = selectedBudgetLabel(preview.budget.selectedBudgetCategoryCode);
    if (preview.previewVersion === 2) {
      const selectedPackage = preview.selectedPackage;
      const rounds = selectedPackage.includedCorrectionRounds === 1 ? "correctieronde" : "correctierondes";
      budgetGuardPackageName.textContent = selectedPackage.label;
      budgetGuardPackagePages.textContent = `Max. ${selectedPackage.standardPageLimit} standaardpagina's`;
      budgetGuardPackageRounds.textContent = `${selectedPackage.includedCorrectionRounds} ${rounds}`;
      budgetGuardPackageRow.hidden = false;
    }
    if (Number.isSafeInteger(preview.summary.knownMinimumMinor)) {
      budgetGuardMinimum.textContent = `${euroFormatter.format(preview.summary.knownMinimumMinor / 100)} excl. btw`;
      budgetGuardMinimumRow.hidden = false;
    }
    if (Array.isArray(preview.recurringServices) && preview.recurringServices.length) {
      budgetGuardRecurring.textContent = preview.recurringServices.map((service) => {
        const label = service.presentationKey === "CARE" ? "LWS Care" : "LWS Care+";
        return `${label}: ${euroFormatter.format(service.amountMinor / 100)} per maand`;
      }).join(" · ");
      budgetGuardRecurringRow.hidden = false;
    }
    const state = preview.budget.comparisonStatus;
    if (manual) {
      budgetGuardPreview.classList.add("budget-guard--manual");
      const essentialManual = preview.summary.manualScope === "ESSENTIAL";
      budgetGuardState.textContent = essentialManual
        ? "Essentieel maatwerk te beoordelen"
        : "Persoonlijke beoordeling vereist";
      if (state === "KNOWN_MINIMUM_ABOVE_BUDGET") {
        budgetGuardPreview.classList.add("budget-guard--warning");
        if (isPackageFloorMismatch(preview)) {
          const floor = euroFormatter.format(preview.selectedPackage.floorMinor / 100);
          budgetGuardStatus.textContent = `Je aanvraag bevat onderdelen waarvoor de prijs persoonlijk beoordeeld moet worden. Daarnaast start het gekozen ${preview.selectedPackage.label}-pakket vanaf ${floor} excl. btw, terwijl je opgegeven budget daaronder ligt.`;
        } else {
          budgetGuardStatus.textContent = `${essentialManual ? "Noodzakelijk maatwerk voor de aangevraagde functionaliteit" : "Je aanvraag bevat onderdelen"} waarvoor de prijs persoonlijk beoordeeld moet worden. Daarnaast ligt het huidige bekende minimum boven je opgegeven budget.`;
        }
        budgetGuardWarningActions.hidden = budgetGuardAllowsSubmit(
          state,
          currentBudgetGuardKey,
          acknowledgedBudgetGuardKey,
          currentBudgetGuardEvidenceFingerprint,
          pricingEvidenceFingerprint,
        );
      } else {
        budgetGuardStatus.textContent = essentialManual
          ? "Noodzakelijk maatwerk voor de aangevraagde functionaliteit wordt persoonlijk beoordeeld en komt boven op het getoonde bekende minimum. Dit maatwerk is niet geprijsd als €0."
          : "Je aanvraag bevat een vrijblijvende uitbreiding waarvoor de prijs persoonlijk beoordeeld moet worden.";
      }
    } else if (state === "WITHIN_KNOWN_BUDGET") {
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
    } else {
      budgetGuardPreview.classList.add("budget-guard--indeterminate");
      budgetGuardState.textContent = "Nog te bepalen";
      budgetGuardStatus.textContent = "We kunnen budget en scope nog niet betrouwbaar vergelijken.";
    }
    if (
      preview.packageAdvice.state === "CONSIDER_PROFESSIONAL" &&
      preview.selectedPackage?.selectedPackageDefinitionId !== "professional_v2"
    ) {
      budgetGuardPackageAdvice.textContent = "Op basis van je wensen kan Professional interessanter zijn. Er is geen pakket automatisch geselecteerd.";
      budgetGuardPackageAdvice.hidden = false;
    } else if (preview.packageAdvice.state === "PERSONAL_REVIEW_RECOMMENDED") {
      budgetGuardPackageAdvice.textContent = "Je wensen vragen een persoonlijke beoordeling. Er is geen pakket automatisch geselecteerd.";
      budgetGuardPackageAdvice.hidden = false;
    }
    if (typeof currentStep === "number" && currentStep === steps.length - 1) renderReviewSummary();
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
        body: JSON.stringify({
          action: "preview_budget_guard",
          token,
          scopeRevision: revision,
          clientPreviewVersion: PREVIEW_CONTRACT_VERSION,
          data: evidence,
        }),
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
      const rejectCode = body.ok
        ? previewValidationRejectCode(body.preview, revision)
        : "INVALID_SUCCESS_ENVELOPE";
      if (rejectCode) {
        console.warn("pricing_preview_contract_rejected", {
          expectedPreviewContractVersion: PREVIEW_CONTRACT_VERSION,
          receivedPreviewContractVersion: Number.isSafeInteger(body.preview?.previewContractVersion)
            ? body.preview.previewContractVersion
            : null,
          rejectCode,
        });
        showPreviewUnavailable("Deze intakepagina gebruikt een oudere versie. Open de intake opnieuw via je e-maillink om verder te gaan.");
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
    if (
      evidence.booking_required === true &&
      evidence.booking_details?.existing_system === true &&
      !evidence.booking_details.existing_system_name
    ) {
      clearTimeout(previewTimer);
      previewTimer = null;
      previewAbortController?.abort();
      previewAbortController = null;
      activeRequestFingerprint = "";
      return;
    }
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
    const restoredScheme = data.budget_update_category_scheme;
    const restoredCodes = restoredScheme === "budget_guard_v2" ? budgetCodes
      : restoredScheme === "budget_guard_v1" ? historicalBudgetCodes : null;
    const hasBudgetEvidence = restoredCodes !== null && restoredBudgetLabel !== null &&
      restoredCodes[restoredBudgetLabel] === restoredBudgetCode;
    restoredBudgetEvidence = hasBudgetEvidence
      ? { label: restoredBudgetLabel, code: restoredBudgetCode, scheme: restoredScheme }
      : null;
    restoredLegacyBudget = restoredBudgetLabel && !hasBudgetEvidence ? restoredBudgetLabel : null;
    if (restoredScheme === "budget_guard_v1" && restoredBudgetLabel) {
      const budgetSelect = document.getElementById("budget_update_category");
      if (![...budgetSelect.options].some((option) => option.value === restoredBudgetLabel)) {
        const historicalOption = new Option(`${restoredBudgetLabel} (historisch)`, restoredBudgetLabel);
        historicalOption.dataset.restoredHistorical = "true";
        budgetSelect.add(historicalOption);
      }
    }
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
    const restoredFeatures = Array.isArray(data.requested_features) ? data.requested_features : [];
    const hasOnlinePayment = restoredFeatures.includes("online_payment") || data.shop_details?.online_payments === true;
    setChoice("online_payment_required", hasOnlinePayment);
    onlinePaymentPurposeValues.forEach((purpose) => {
      if (restoredFeatures.includes(`online_payment_${purpose}`)) setChoice("online_payment_purposes", purpose);
    });
    if (hasOnlinePayment && !onlinePaymentPurposeValues.some((purpose) => restoredFeatures.includes(`online_payment_${purpose}`)) && data.shop_details?.online_payments === true) {
      setChoice("online_payment_purposes", "products");
    }
    if (data.confirmation === true) document.getElementById("confirmation").checked = true;
    if (data.shop_details) {
      document.getElementById("shop_product_count").value = data.shop_details.approx_product_count || 1;
      document.getElementById("shop_complex_product_count").value = data.shop_details.complex_product_count ?? 0;
      document.getElementById("shop_payment_provider_count").value = data.shop_details.payment_provider_count ?? 1;
      document.getElementById("shop_shipping_scope").value = restoredShippingScope(data.shop_details);
      document.getElementById("shop_categories").checked = data.shop_details.categories === true;
      document.getElementById("shop_payments").checked = data.shop_details.online_payments === true;
      document.getElementById("shop_shipping").checked = data.shop_details.shipping === true;
      document.getElementById("shop_pickup_scope").value = restoredPickupScope(data.shop_details);
      document.getElementById("shop_catalog").checked = data.shop_details.existing_catalog === true;
      document.getElementById("shop_customer_accounts").checked = data.shop_details.customer_accounts === true;
      document.getElementById("shop_catalog_import").checked = data.shop_details.catalog_import === true;
      document.getElementById("shop_erp_api").checked = data.shop_details.erp_api === true;
    }
    if (data.booking_details) {
      document.getElementById("booking_tier").value = data.booking_details.tier || "widget";
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
    if (typeof data.page_scope_details?.search === "string") document.getElementById("search_tier").value = data.page_scope_details.search;
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
      document.getElementById("translation_required").checked = data.multilingual_details.translation_required === true;
      document.getElementById("seo_per_language").checked = data.multilingual_details.seo_per_language === true;
      document.getElementById("advanced_seo_research").checked = data.multilingual_details.advanced_seo_research === true;
      document.getElementById("language_integrations").checked = data.multilingual_details.language_specific_integrations === true;
      document.getElementById("multilingual_complex_scope").checked = data.multilingual_details.complex_scope === true;
    }
    if (data.download_details?.access) document.getElementById("download_access").value = data.download_details.access;
    if (data.newsletter_details?.scope) document.getElementById("newsletter_scope").value = data.newsletter_details.scope;
    if (data.newsletter_details?.analytics) document.getElementById("analytics_scope").value = data.newsletter_details.analytics;
    document.getElementById("custom_integration").checked = data.newsletter_details?.custom_integration === true;
    if (data.content_media_details) {
      document.getElementById("copywriting_scope").value = data.content_media_details.copywriting_scope || "unknown";
      document.getElementById("copy_page_count").value = data.content_media_details.copy_page_count || 1;
      document.getElementById("image_work_scope").value = data.content_media_details.image_work_scope || "unknown";
      document.getElementById("paid_stock_handling").checked = data.content_media_details.paid_stock_handling === true;
      document.getElementById("branding_tier").value = data.content_media_details.branding_tier || "existing";
    }
    if (data.hosting_maintenance_details) {
      document.getElementById("domain_service").value = data.hosting_maintenance_details.domain_service || "existing";
      document.getElementById("maintenance_plan").value = data.hosting_maintenance_details.maintenance_plan || "none";
    }
    if (data.deadline_details) {
      document.getElementById("deadline_commercially_critical").checked = data.deadline_details.commercially_critical === true;
      document.getElementById("deadline_hard").checked = data.deadline_details.hard_deadline === true;
    }
    document.getElementById("seo_scope").value = data.seo_details?.scope ||
      (data.seo_details?.extensive_services === true ? "launch" : "included");
    document.getElementById("seo_extra_language").checked = data.seo_details?.extra_language_seo === true;
    document.getElementById("seo_advanced_language").checked = data.seo_details?.advanced_language_seo === true;
    synchronizePricingChoices();
    updateConditionals();
    updatePriorities();
  }

  function restoredPickupScope(shopDetails) {
    if (["none", "simple", "scheduled", "complex"].includes(shopDetails?.pickup_scope)) {
      return shopDetails.pickup_scope;
    }
    return shopDetails?.pickup === true ? "simple" : "none";
  }

  function restoredShippingScope(shopDetails) {
    if (shopDetails?.shipping === false) return "none";
    if (["standard", "complex"].includes(shopDetails?.shipping_scope)) return shopDetails.shipping_scope;
    return shopDetails?.shipping === true ? "standard" : "none";
  }

  function synchronizePricingChoices(target) {
    const translationsSupplied = document.getElementById("translations_supplied");
    const translationRequired = document.getElementById("translation_required");
    const seoPerLanguage = document.getElementById("seo_per_language");
    const advancedSeoResearch = document.getElementById("advanced_seo_research");
    const seoExtraLanguage = document.getElementById("seo_extra_language");
    const seoAdvancedLanguage = document.getElementById("seo_advanced_language");

    if (target === translationsSupplied && translationsSupplied.checked) translationRequired.checked = false;
    else if (target === translationRequired && translationRequired.checked) translationsSupplied.checked = false;
    else if (!target && translationsSupplied.checked && translationRequired.checked) translationsSupplied.checked = false;
    if (target === seoPerLanguage && !seoPerLanguage.checked) advancedSeoResearch.checked = false;
    else if (advancedSeoResearch.checked) seoPerLanguage.checked = true;
    if (target === seoExtraLanguage && !seoExtraLanguage.checked) seoAdvancedLanguage.checked = false;
    else if (seoAdvancedLanguage.checked) seoExtraLanguage.checked = true;

    const shopNo = form.querySelector('input[name="shop_required"][value="false"]');
    const bookingNo = form.querySelector('input[name="booking_required"][value="false"]');
    if (target === shopNo && shopNo.checked) {
      ['input[name="requested_pages"][value="shop"]', 'input[name="requested_features"][value="shop"]']
        .forEach((selector) => { form.querySelector(selector).checked = false; });
    }
    if (target === bookingNo && bookingNo.checked) {
      ['input[name="requested_pages"][value="reservations"]', 'input[name="requested_features"][value="appointments"]', 'input[name="requested_features"][value="reservations"]']
        .forEach((selector) => { form.querySelector(selector).checked = false; });
    }
  }

  function updateConditionals() {
    const hasWebsite = selectedBoolean("has_existing_website") === true;
    document.getElementById("existingWebsiteFields").hidden = !hasWebsite;
    if (!hasWebsite) ["existing_website_url", "elements_to_keep", "improvement_areas"].forEach((id) => { document.getElementById(id).value = ""; });
    const shop = selectedBoolean("shop_required") === true;
    document.getElementById("shopFields").hidden = !shop;
    const booking = selectedBoolean("booking_required") === true;
    document.getElementById("bookingFields").hidden = !booking;
    const onlinePayment = selectedBoolean("online_payment_required") === true;
    document.getElementById("onlinePaymentFields").hidden = !onlinePayment;
    if (!onlinePayment) form.querySelectorAll('input[name="online_payment_purposes"]').forEach((input) => { input.checked = false; });
    document.getElementById("shopPaymentProviderField").hidden = !(shop && onlinePayment);
    if (!onlinePayment) document.getElementById("shop_payment_provider_count").value = 1;
    document.getElementById("shop_payments").checked = shop && onlinePayment && selectedValues("online_payment_purposes").includes("products");
    document.getElementById("shop_shipping").checked = shop && document.getElementById("shop_shipping_scope").value !== "none";
    const existingBookingSystem = booking && document.getElementById("booking_existing").checked;
    document.getElementById("bookingSystemNameField").hidden = !existingBookingSystem;
    if (!existingBookingSystem) document.getElementById("booking_system_name").value = "";
    const requestedPages = new Set(selectedValues("requested_pages"));
    const requestedFeatures = new Set(selectedValues("requested_features"));
    document.getElementById("pageScopeFields").hidden =
      !scopedPages.some((page) => requestedPages.has(page)) && !requestedFeatures.has("search");
    scopedPages.forEach((page) => {
      document.querySelector(`[data-page-scope="${page}"]`).hidden = !requestedPages.has(page);
    });
    document.querySelector('[data-feature-scope="search"]').hidden = !requestedFeatures.has("search");
    document.getElementById("quoteFormFields").hidden = !requestedFeatures.has("quote_form");
    const hasAdditionalLanguage = form.querySelector("[data-additional-language]:checked") !== null;
    document.getElementById("multilingualFields").hidden = !(requestedFeatures.has("multilingual") || hasAdditionalLanguage);
    document.getElementById("downloadFields").hidden = !requestedFeatures.has("downloads");
    document.getElementById("newsletterFields").hidden = !requestedFeatures.has("newsletter");
    document.getElementById("copyPageCountField").hidden =
      !["substantial", "new"].includes(document.getElementById("copywriting_scope").value);
    const logoAvailable = ["available", "needs_update"].includes(document.getElementById("logo_status").value);
    document.getElementById("logoDeliveryFields").hidden = !logoAvailable;
    if (!logoAvailable) {
      form.querySelectorAll('input[name="logo_delivery_method"]').forEach((input) => { input.checked = false; });
      clearLocalFileSelection("logoFilePreview", "logoFileSummary", "logoFileError");
    }
    const logoDelivery = selectedLocalDelivery("logo_delivery_method");
    document.getElementById("logoUploadField").hidden = !logoAvailable || logoDelivery !== "now";
    if (logoDelivery !== "now") clearLocalFileSelection("logoFilePreview", "logoFileSummary", "logoFileError");
    const imagesAvailable = ["sufficient", "partial"].includes(document.getElementById("image_status").value);
    document.getElementById("imageDeliveryFields").hidden = !imagesAvailable;
    if (!imagesAvailable) {
      form.querySelectorAll('input[name="image_delivery_method"]').forEach((input) => { input.checked = false; });
      clearLocalFileSelection("imageFilePreview", "imageFileSummary", "imageFileError");
    }
    const imageDelivery = selectedLocalDelivery("image_delivery_method");
    document.getElementById("imageUploadField").hidden = !imagesAvailable || imageDelivery !== "now";
    if (imageDelivery !== "now") clearLocalFileSelection("imageFilePreview", "imageFileSummary", "imageFileError");
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
    validationErrors.clear();
    updateStepErrorIndicators();
  }

  function validationControl(name) {
    const field = form.elements.namedItem(name);
    return field instanceof RadioNodeList ? field[0] : field;
  }

  function validationTarget(name) {
    return form.querySelector(`[data-validation-group="${name}"]`) || validationControl(name);
  }

  function markError(name, text) {
    const control = validationControl(name);
    validationTarget(name)?.setAttribute?.("aria-invalid", "true");
    const error = document.getElementById(`${name}-error`);
    if (error) error.textContent = text;
    validationErrors.set(name, { name, message: text });
    return control || error;
  }

  function clearFieldError(name) {
    validationTarget(name)?.removeAttribute?.("aria-invalid");
    const error = document.getElementById(`${name}-error`);
    if (error) error.textContent = "";
    validationErrors.delete(name);
  }

  function validateInspirationSites(values) {
    if (!values?.length) return null;
    if (values.length > 10) return "Vul maximaal 10 inspiratie-URL's in.";
    if (values.some((value) => value.length > 2048)) return "Een inspiratie-URL mag maximaal 2048 tekens bevatten.";
    const invalid = values.some((value) => {
      try {
        const url = new URL(value);
        return !["http:", "https:"].includes(url.protocol) || Boolean(url.username || url.password);
      } catch {
        return true;
      }
    });
    return invalid ? "Vul geldige http- of https-URL's in, één per regel." : null;
  }

  function collectValidationIssues(data) {
    const issues = [];
    requiredSubmitFields.forEach((name) => {
      if (!data[name]) issues.push({ name, message: "Dit veld is verplicht." });
    });
    ["website_goals", "requested_pages", "design_styles", "priorities"].forEach((name) => {
      if (!data[name]?.length) issues.push({ name, message: "Kies minstens één optie." });
    });
    if (!data.selected_package_definition_id) {
      issues.push({ name: "selected_package_definition_id", message: "Kies Starter of Professional om je intake te verzenden." });
    }
    if (data.has_existing_website === true && !data.existing_website_url) {
      issues.push({ name: "existing_website_url", message: "Vul je huidige website in." });
    }
    if (data.domain_status === "has_domain" && !data.domain_name) {
      issues.push({ name: "domain_name", message: "Vul je domeinnaam in." });
    }
    if (data.requested_features?.includes("online_payment") && !onlinePaymentPurposeFeatures.some((purpose) => data.requested_features.includes(purpose))) {
      issues.push({ name: "online_payment_purposes", message: "Kies minstens één doel voor online betalingen." });
    }
    const inspirationSitesMessage = validateInspirationSites(data.inspiration_sites);
    if (inspirationSitesMessage) issues.push({ name: "inspiration_sites", message: inspirationSitesMessage });
    if (!data.confirmation) issues.push({ name: "confirmation", message: "Bevestig je briefing voor verzending." });
    return issues;
  }

  function orderValidationIssues(issues, orderedNames) {
    const order = new Map(orderedNames.map((name, index) => [name, index]));
    return [...issues].sort((left, right) =>
      (order.get(left.name) ?? Number.MAX_SAFE_INTEGER) - (order.get(right.name) ?? Number.MAX_SAFE_INTEGER));
  }

  function validationSummary(count) {
    if (!count) return "";
    return count === 1 ? "Controleer 1 gemarkeerd veld." : `Controleer ${count} gemarkeerde velden.`;
  }

  function updateStepErrorIndicators() {
    phaseButtons.forEach((button, phaseIndex) => {
      const hasError = steps.some((step) =>
        Number(step.dataset.phase) === phaseIndex && Boolean(step.querySelector('[aria-invalid="true"]')));
      button.classList.toggle("has-error", hasError);
      if (hasError) button.setAttribute("aria-label", `${phaseLabels[phaseIndex]}, bevat fouten`);
      else button.removeAttribute("aria-label");
    });
  }

  function renderValidationIssues(issues) {
    clearErrors();
    issues.forEach(({ name, message: text }) => markError(name, text));
    updateStepErrorIndicators();
    validationMessageActive = issues.length > 0;
    setMessage(validationSummary(issues.length), issues.length ? "error" : null);
  }

  function revealFirstValidationIssue(name) {
    const firstInvalid = validationControl(name);
    updateStepErrorIndicators();
    if (!firstInvalid) return;
    const step = firstInvalid.closest?.(".intake-step");
    if (step) showStep(steps.indexOf(step));
    firstInvalid.scrollIntoView?.({ behavior: "smooth", block: "center" });
    firstInvalid.focus?.();
  }

  function revalidateFields(names) {
    if (!validationMessageActive && !names.some((name) => validationErrors.has(name))) return;
    const currentIssues = new Map(collectValidationIssues(collectData()).map((issue) => [issue.name, issue]));
    names.forEach((name) => {
      clearFieldError(name);
      const issue = currentIssues.get(name);
      if (issue) markError(issue.name, issue.message);
    });
    updateStepErrorIndicators();
    if (validationErrors.size) setMessage(validationSummary(validationErrors.size), "error");
    else {
      validationMessageActive = false;
      setMessage("", null);
    }
  }

  function handleValidationInput(event) {
    const validationNames = [event.target.name].filter(Boolean);
    if (event.target.name === "has_existing_website") validationNames.push("existing_website_url");
    if (event.target.name === "domain_status") validationNames.push("domain_name");
    if (event.target.name === "online_payment_required" || event.target.name === "online_payment_purposes") validationNames.push("online_payment_purposes");
    revalidateFields(validationNames);
  }

  function validatePackageSelection() {
    if (form.querySelector('input[name="selected_package_definition_id"]:checked')) {
      clearFieldError("selected_package_definition_id");
      updateStepErrorIndicators();
      return true;
    }
    const firstInvalid = markError("selected_package_definition_id", "Kies Starter of Professional om verder te gaan.");
    validationMessageActive = true;
    updateStepErrorIndicators();
    firstInvalid?.focus?.();
    setMessage("Kies eerst een pakket. Je budgetkeuze blijft onafhankelijk.", "error");
    return false;
  }

  function validateBudgetSelection() {
    if (document.getElementById("budget_update_category").value) {
      clearFieldError("budget_update_category");
      updateStepErrorIndicators();
      return true;
    }
    const firstInvalid = markError("budget_update_category", "Kies een budgetverwachting om verder te gaan.");
    validationMessageActive = true;
    updateStepErrorIndicators();
    firstInvalid?.focus?.();
    setMessage("Kies eerst uw verwachte budget.", "error");
    return false;
  }

  function validateNavigationTo(targetStep) {
    if (targetStep > 0 && !validateBudgetSelection()) {
      showStep(0);
      return false;
    }
    if (targetStep > 3 && !form.querySelector('input[name="selected_package_definition_id"]:checked')) {
      showStep(3);
      validatePackageSelection();
      return false;
    }
    return true;
  }

  function validateSubmit() {
    const data = collectData();
    const orderedNames = Array.from(form.elements).map((field) => field.name).filter(Boolean);
    const issues = orderValidationIssues(collectValidationIssues(data), orderedNames);
    renderValidationIssues(issues);
    if (issues.length) {
      revealFirstValidationIssue(issues[0].name);
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
    const requiresRevision = action === "save_draft" || action === "reset_draft";
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action,
        token,
        ...(requiresRevision ? { expected_revision: draftRevision } : {}),
        ...(data ? { data } : {}),
      }),
    });
    let body = {};
    try { body = await response.json(); } catch { body = {}; }
    return { response, body };
  }

  function apiErrorPresentation(status, code) {
    if (status === 400) return { kind: "validation", message: "Controleer de gemarkeerde velden." };
    if (status === 401) return { kind: "unavailable", message: "Deze intake-link is ongeldig of niet meer geldig." };
    if (status === 409 && code === "INTAKE_REVISION_CONFLICT") return { kind: "conflict", message: "Deze intake werd ondertussen in een ander venster gewijzigd. Herlaad de pagina om de meest recente versie te gebruiken." };
    if (status === 409) return { kind: code === "INTAKE_ALREADY_SUBMITTED" ? "submitted" : "reviewed", message: "" };
    if (status === 429 || status >= 500) {
      return { kind: "temporary", message: "Verzenden lukt tijdelijk niet. Je antwoorden blijven staan. Probeer later opnieuw." };
    }
    return { kind: "unknown", message: "Er ging iets mis. Probeer later opnieuw." };
  }

  function handleApiError(response, body) {
    const presentation = apiErrorPresentation(response.status, body.code);
    if (presentation.kind === "validation") {
      if (body.field) {
        markError(body.field, "Controleer dit veld.");
        validationMessageActive = true;
        revealFirstValidationIssue(body.field);
      }
      setMessage(presentation.message, "error");
    } else if (presentation.kind === "unavailable") showUnavailable(presentation.message);
    else if (presentation.kind === "conflict") setMessage(presentation.message, "error");
    else if (["submitted", "reviewed"].includes(presentation.kind)) setReadOnly(presentation.kind);
    else setMessage(presentation.message, "error");
  }

  function handleNetworkError() {
    setMessage("De service is niet bereikbaar. Controleer je internetverbinding en probeer opnieuw.", "error");
  }

  async function saveDraft() {
    if (busy || readOnly) return;
    setBusy(true, "Concept wordt opgeslagen...");
    try {
      const { response, body } = await request("save_draft", collectData());
      if (!response.ok) return handleApiError(response, body);
      draftRevision = body.intake.revision;
      dirty = false;
      contextStatus.textContent = "In uitvoering";
      setMessage("Concept opgeslagen.", "success");
      lastSaved.textContent = `Laatst opgeslagen om ${new Date().toLocaleTimeString("nl-BE", { hour: "2-digit", minute: "2-digit" })}.`;
    } catch { handleNetworkError(); }
    finally { setBusy(false); }
  }

  function openModal(modal) {
    if (!modal) return;
    modalReturnFocus = document.activeElement;
    activeModal = modal;
    modal.hidden = false;
    document.body.classList.add("modal-open");
    modal.querySelector(".intake-modal__panel")?.focus();
  }

  function closeModal(modal = activeModal) {
    if (!modal) return;
    modal.hidden = true;
    document.body.classList.remove("modal-open");
    activeModal = null;
    modalReturnFocus?.focus?.();
  }

  async function submitFinal() {
    if (busy || readOnly) return;
    closeModal(submitModal);
    if (!validateBudgetGuardAcknowledgement()) return;
    setBusy(true, "Intake wordt verzonden...");
    try {
      const { response, body } = await request("submit", collectData());
      if (!response.ok) return handleApiError(response, body);
      if (body.state === "submitted" || body.state === "already_submitted") {
        dirty = false;
        setReadOnly("submitted", body.application);
      }
    } catch { handleNetworkError(); }
    finally { setBusy(false); }
  }

  function restoreInitialFormState(status) {
    stopPricingPreview();
    form.reset();
    document.querySelectorAll('#budget_update_category option[data-restored-historical="true"]').forEach((option) => option.remove());
    clearLocalFileSelection("logoFilePreview", "logoFileSummary", "logoFileError");
    clearLocalFileSelection("imageFilePreview", "imageFileSummary", "imageFileError");
    clearErrors();
    restoredLegacyBudget = null;
    restoredBudgetEvidence = null;
    budgetChoiceChanged = false;
    acknowledgedBudgetGuardKey = "";
    pricingEvidenceFingerprint = "";
    scopeRevision += 1;
    furthestStep = 0;
    dirty = false;
    lastSaved.textContent = "";
    contextStatus.textContent = status === "invited" ? "Nog niet gestart" : "In uitvoering";
    clearPricingPresentation();
    updateConditionals();
    updatePriorities();
    renderReviewSummary();
    showStep(0, true);
    previewStopped = false;
    schedulePricingPreview({ force: true, immediate: true });
  }

  async function resetDraft() {
    if (busy || readOnly) return;
    closeModal(resetModal);
    setBusy(true, "Concept wordt gewist...");
    try {
      const { response, body } = await request("reset_draft");
      if (!response.ok) return handleApiError(response, body);
      draftRevision = body.intake.revision;
      restoreInitialFormState(body.intake.status);
      setMessage("Je kunt opnieuw beginnen.", "success");
    } catch { handleNetworkError(); }
    finally { setBusy(false); }
  }

  function renderSuccessSummary(application) {
    const valid = application && typeof application === "object" &&
      /^LWS-AAN-[0-9]{4}-[0-9]{4}$/.test(application.applicationReference || "") &&
      application.customer && application.commercial;
    const summary = document.getElementById("intakeSuccessSummary");
    const reference = document.querySelector(".intake-success__reference");
    const customerNode = document.getElementById("intakeSuccessCustomer");
    if (!valid) {
      summary.hidden = true;
      reference.hidden = true;
      customerNode.hidden = true;
      return;
    }
    reference.hidden = false;
    customerNode.hidden = false;
    const setRow = (key, value) => {
      const row = document.querySelector(`[data-success-row="${key}"]`);
      const target = row?.querySelector("dd");
      const text = Array.isArray(value) ? value.filter(Boolean).join(", ") : value;
      row.hidden = !text;
      if (target) target.textContent = text || "";
    };
    const euro = (minor) => euroFormatter.format(minor / 100);
    const customer = application.customer.company
      ? `${application.customer.company} · ${application.customer.name}`
      : application.customer.name;
    const languages = [application.website?.primaryLanguage, ...(application.website?.additionalLanguages || [])];
    const recurring = (application.commercial.recurringServices || []).map((service) =>
      `${service.label}: ${euro(service.amountMinor)} per maand excl. btw`
    );
    document.getElementById("intakeSuccessReference").textContent = application.applicationReference;
    customerNode.textContent = customer;
    setRow("package", application.commercial.packageLabel);
    setRow("budget", application.commercial.budgetLabel);
    setRow("minimum", `${euro(application.commercial.knownMinimumMinor)} excl. btw`);
    setRow("pages", application.website?.pages);
    setRow("shop", application.website?.webshop ? "Ja" : "Nee");
    setRow("booking", application.website?.booking ? "Ja" : "Nee");
    setRow("languages", languages);
    setRow("branding", [application.brandingContent?.brandStatus, application.brandingContent?.logoStatus]);
    setRow("content", [application.brandingContent?.contentStatus, application.brandingContent?.imageStatus]);
    setRow("recurring", recurring);
    setRow("deadline", application.servicePlanning?.deadline || application.servicePlanning?.timing);
    setRow("submitted", new Date(application.submittedAt).toLocaleString("nl-BE", { dateStyle: "long", timeStyle: "short", timeZone: "Europe/Brussels" }));
    summary.hidden = false;
  }

  function setReadOnly(status, application) {
    stopPricingPreview();
    readOnly = true;
    dirty = false;
    setMessage("", null);
    form.querySelectorAll("input, textarea, select, button").forEach((control) => { control.disabled = true; });
    document.getElementById("intakeActions").hidden = true;
    form.classList.add("is-readonly");
    contextStatus.textContent = status === "reviewed" ? "Verwerkt" : "Verzonden";
    success.hidden = false;
    success.querySelector("h2").textContent = status === "reviewed" ? "Je aanvraag werd al verwerkt" : "Aanvraag ontvangen";
    renderSuccessSummary(application);
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
      if (!Number.isSafeInteger(body.intake?.revision) || body.intake.revision < 0) {
        return showUnavailable("De intake kon niet worden geladen. Probeer later opnieuw.");
      }
      draftRevision = body.intake.revision;
      document.getElementById("contextName").textContent = body.request?.company || body.request?.name || "Websiteproject";
      document.getElementById("contextType").textContent = body.request?.website_type || "Website";
      const status = body.intake?.status;
      contextStatus.textContent = status === "in_progress" ? "Concept hersteld" : status === "submitted" ? "Verzonden" : status === "reviewed" ? "Verwerkt" : "Nog niet gestart";
      loading.hidden = true;
      workspace.hidden = false;
      showStep(0);
      if (status === "in_progress") setMessage("Je eerder opgeslagen concept is hersteld.", "success");
      if (status === "submitted" || status === "reviewed") setReadOnly(status, body.application);
      else schedulePricingPreview({ force: true, immediate: true });
    } catch { showUnavailable("De intake kon niet worden geladen. Probeer later opnieuw."); }
  }

  form.addEventListener("input", (event) => {
    if (readOnly) return;
    synchronizePricingChoices(event.target);
    dirty = true;
    if (event.target.name === "budget_update_category") budgetChoiceChanged = true;
    if (event.target.name === "selected_package_definition_id") {
      packageSelectionGroup?.removeAttribute("aria-invalid");
      document.getElementById("selected_package_definition_id-error").textContent = "";
      setMessage("", null);
    }
    if (event.target.name === "priorities") updatePriorities(event.target);
    if (
      ["has_existing_website", "shop_required", "booking_required", "online_payment_required", "online_payment_purposes", "requested_pages", "requested_features", "website_goals", "primary_language", "logo_delivery_method", "image_delivery_method"].includes(event.target.name) ||
      ["logo_status", "image_status"].includes(event.target.id) ||
      event.target.matches("[data-additional-language], #booking_existing, #shop_shipping_scope, #deadline_date, #deadline_reason")
    ) updateConditionals();
    if (isPricingControl(event.target)) schedulePricingPreview();
    if (currentStep === steps.length - 1) renderReviewSummary();
  });
  form.addEventListener("input", handleValidationInput);
  bindLocalFilePreview("logoFilePreview", "logoFileSummary", "logoFileError", 1, 5 * 1024 * 1024);
  bindLocalFilePreview("imageFilePreview", "imageFileSummary", "imageFileError", 10, 10 * 1024 * 1024);
  form.addEventListener("submit", (event) => { event.preventDefault(); if (validateSubmit()) openModal(submitModal); });
  saveButton.addEventListener("click", saveDraft);
  resetButton?.addEventListener("click", () => openModal(resetModal));
  nextButton.addEventListener("click", () => {
    const targetStep = currentStep + 1;
    if (!validateNavigationTo(targetStep)) return;
    showStep(targetStep, true);
  });
  previousButton.addEventListener("click", () => showStep(currentStep - 1, true));
  phaseButtons.forEach((button) => button.addEventListener("click", () => {
    const targetStep = phaseStartScreens[Number(button.dataset.phaseTarget)];
    if (!validateNavigationTo(targetStep)) return;
    showStep(targetStep, true);
  }));
  document.querySelectorAll(".intake-modal [data-close-modal]").forEach((button) => button.addEventListener("click", () => closeModal(button.closest(".intake-modal"))));
  confirmSubmit?.addEventListener("click", submitFinal);
  confirmReset?.addEventListener("click", resetDraft);
  document.getElementById("adjustBudget").addEventListener("click", () => {
    showStep(0);
    document.getElementById("budget_update_category")?.focus?.();
  });
  document.getElementById("changePackage").addEventListener("click", () => {
    showStep(3);
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
    if (event.key === "Escape" && activeModal) closeModal();
    if (event.key === "Tab" && activeModal) {
      const modalPanel = activeModal.querySelector(".intake-modal__panel");
      const focusable = Array.from(activeModal.querySelectorAll("button:not([disabled])"));
      const first = focusable[0]; const last = focusable[focusable.length - 1];
      if (event.shiftKey && (document.activeElement === modalPanel || document.activeElement === first)) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
  window.addEventListener("beforeunload", (event) => { if (dirty && !readOnly) event.preventDefault(); });

  initializePricingAnchors();
  inspect();
})();

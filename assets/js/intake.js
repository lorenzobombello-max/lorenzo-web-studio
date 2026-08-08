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
  let currentStep = 0;
  let dirty = false;
  let busy = false;
  let readOnly = false;
  let modalReturnFocus = null;

  const commaFields = ["languages", "brand_colors", "seo_keywords", "social_channels", "integrations"];
  const arrayFields = ["website_goals", "requested_pages", "requested_features", "design_styles", "image_support", "priorities"];
  const booleanFields = ["has_existing_website", "shop_required", "booking_required", "budget_confirmed"];
  const requiredSubmitFields = ["business_description", "target_audience", "primary_conversion_goal", "brand_status", "logo_status", "content_status", "image_status", "domain_status", "hosting_status", "maintenance_interest", "seo_priority"];

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
    return data;
  }

  function setChoice(name, value) {
    const input = form.querySelector(`input[name="${name}"][value="${String(value)}"]`);
    if (input) input.checked = true;
  }

  function restoreData(data) {
    if (!data || typeof data !== "object" || Array.isArray(data)) return;
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
    return first || error;
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
    return true;
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
    readOnly = true;
    dirty = false;
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
    } catch { showUnavailable("De intake kon niet worden geladen. Probeer later opnieuw."); }
  }

  form.addEventListener("input", (event) => {
    if (readOnly) return;
    dirty = true;
    if (event.target.name === "priorities") updatePriorities(event.target);
    if (["has_existing_website", "shop_required", "booking_required"].includes(event.target.name)) updateConditionals();
  });
  form.addEventListener("submit", (event) => { event.preventDefault(); if (validateSubmit()) openModal(); });
  saveButton.addEventListener("click", saveDraft);
  nextButton.addEventListener("click", () => showStep(currentStep + 1, true));
  previousButton.addEventListener("click", () => showStep(currentStep - 1, true));
  stepButtons.forEach((button) => button.addEventListener("click", () => showStep(Number(button.dataset.stepTarget), true)));
  modal?.querySelectorAll("[data-close-modal]").forEach((button) => button.addEventListener("click", closeModal));
  confirmSubmit?.addEventListener("click", submitFinal);
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

  inspect();
})();

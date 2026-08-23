(function () {
  "use strict";

  document.documentElement.classList.replace("no-js", "js");

  const header = document.getElementById("previewHeader");
  const menuToggle = document.getElementById("menuToggle");
  const navigation = document.getElementById("previewNav");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const functionsBaseMeta = document.querySelector('meta[name="lws-functions-base-url"]');

  function closeMenu(restoreFocus) {
    if (!menuToggle || !navigation) return;
    const wasOpen = menuToggle.getAttribute("aria-expanded") === "true";
    menuToggle.setAttribute("aria-expanded", "false");
    menuToggle.querySelector(".sr-only").textContent = "Navigatiemenu openen";
    navigation.classList.remove("is-open");
    document.body.classList.remove("menu-open");
    if (restoreFocus && wasOpen) menuToggle.focus();
  }

  function toggleMenu() {
    if (!menuToggle || !navigation) return;
    const open = menuToggle.getAttribute("aria-expanded") !== "true";
    menuToggle.setAttribute("aria-expanded", String(open));
    menuToggle.querySelector(".sr-only").textContent = open ? "Navigatiemenu sluiten" : "Navigatiemenu openen";
    navigation.classList.toggle("is-open", open);
    document.body.classList.toggle("menu-open", open);
  }

  function initReveals() {
    const elements = Array.from(document.querySelectorAll("[data-reveal]"));
    if (!elements.length) return;
    if (reducedMotion.matches || !("IntersectionObserver" in window)) {
      elements.forEach((element) => element.classList.add("is-visible"));
      return;
    }
    document.documentElement.classList.add("motion-enabled");
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.08, rootMargin: "0px 0px -4%" });
    elements.forEach((element) => observer.observe(element));
  }

  function initPageSignals() {
    if (reducedMotion.matches) return;
    document.querySelectorAll(".page-hero, .page-section--dark, .page-cta").forEach((section, index) => {
      const signal = document.createElement("span");
      signal.className = "page-signal";
      signal.setAttribute("aria-hidden", "true");
      signal.style.setProperty("--signal-index", String(index));
      section.prepend(signal);
    });
  }

  function initDemoPagination() {
    const pages = Array.from(document.querySelectorAll("[data-demo-page]"));
    if (!pages.length) return;
    const carousel = document.querySelector("[data-demo-carousel]");
    const track = carousel?.querySelector("[data-demo-track]");
    if (!carousel || !track) return;
    const pageLinks = Array.from(document.querySelectorAll("[data-page-link]"));
    const label = document.querySelector("[data-current-page]");
    const previous = document.querySelector("[data-previous-page]");
    const next = document.querySelector("[data-next-page]");

    function getRequestedPage() {
      const requested = Number(new URLSearchParams(window.location.search).get("page"));
      return requested >= 1 && requested <= pages.length ? requested : 1;
    }

    function setTrackPosition(current, dragOffset = 0, immediate = false) {
      if (immediate) track.style.transition = "none";
      const position = -((current - 1) * carousel.clientWidth) + dragOffset;
      track.style.transform = `translate3d(${position}px,0,0)`;
      if (immediate) window.setTimeout(() => track.style.removeProperty("transition"), 20);
    }

    function renderPage(current, immediate = false) {
      pages.forEach((panel) => {
        const active = Number(panel.dataset.demoPage) === current;
        panel.classList.toggle("is-active", active);
        panel.setAttribute("aria-hidden", String(!active));
        panel.inert = !active;
      });
      pageLinks.forEach((link) => {
        if (Number(link.dataset.pageLink) === current) link.setAttribute("aria-current", "page");
        else link.removeAttribute("aria-current");
      });
      if (label) label.textContent = `${String(current).padStart(2, "0")} / ${String(pages.length).padStart(2, "0")}`;
      if (previous) {
        previous.href = `?page=${Math.max(1, current - 1)}`;
        previous.toggleAttribute("aria-disabled", current === 1);
      }
      if (next) {
        next.href = `?page=${Math.min(pages.length, current + 1)}`;
        next.toggleAttribute("aria-disabled", current === pages.length);
      }
      setTrackPosition(current, 0, immediate);
    }

    function navigateToPage(target) {
      if (target < 1 || target > pages.length || target === getRequestedPage()) return;
      const scrollPosition = window.scrollY;
      const url = new URL(window.location.href);
      url.searchParams.set("page", String(target));
      history.pushState({ demoPage: target }, "", url);
      renderPage(target);
      window.scrollTo({ top: scrollPosition, behavior: "instant" });
    }

    document.querySelector(".demo-pagination")?.addEventListener("click", (event) => {
      const link = event.target.closest("a");
      if (!link || link.getAttribute("aria-disabled") === "true") {
        event.preventDefault();
        return;
      }
      const target = Number(new URL(link.href).searchParams.get("page"));
      if (!Number.isInteger(target)) return;
      event.preventDefault();
      navigateToPage(target);
    });

    if (carousel) {
      let pointerId = null;
      let startX = 0;
      let startY = 0;
      let dragged = false;
      let suppressClickUntil = 0;
      let lastX = 0;
      let lastTime = 0;
      let velocityX = 0;
      const movementThreshold = 48;

      carousel.addEventListener("pointerdown", (event) => {
        if (event.target.closest(".demo-pagination")) return;
        if (event.pointerType === "mouse" && event.button !== 0) return;
        pointerId = event.pointerId;
        startX = event.clientX;
        startY = event.clientY;
        lastX = event.clientX;
        lastTime = performance.now();
        velocityX = 0;
        dragged = false;
      });

      carousel.addEventListener("pointermove", (event) => {
        if (event.pointerId !== pointerId) return;
        const horizontal = event.clientX - startX;
        const vertical = event.clientY - startY;
        if (!dragged && Math.abs(horizontal) > 8 && Math.abs(horizontal) > Math.abs(vertical)) {
          dragged = true;
          carousel.classList.add("is-dragging");
          carousel.setPointerCapture(pointerId);
        }
        if (!dragged) return;
        const now = performance.now();
        const elapsed = Math.max(now - lastTime, 8);
        velocityX = ((event.clientX - lastX) / elapsed) * 1000;
        lastX = event.clientX;
        lastTime = now;
        const current = getRequestedPage();
        const atStart = current === 1 && horizontal > 0;
        const atEnd = current === pages.length && horizontal < 0;
        const resistance = atStart || atEnd ? 0.24 : 1;
        setTrackPosition(current, horizontal * resistance);
      });

      function releaseGesture(event) {
        if (event.pointerId !== pointerId) return;
        const horizontal = event.clientX - startX;
        const vertical = event.clientY - startY;
        if (dragged) {
          suppressClickUntil = performance.now() + 500;
          const horizontalGesture = Math.abs(horizontal) > Math.abs(vertical) * 1.2;
          const shouldNavigate = horizontalGesture &&
            (Math.abs(horizontal) >= movementThreshold || (Math.abs(horizontal) > 12 && Math.abs(velocityX) >= 520));
          const direction = horizontal < 0 ? 1 : -1;
          const target = getRequestedPage() + direction;
          carousel.classList.remove("is-dragging");
          if (shouldNavigate && target >= 1 && target <= pages.length) {
            navigateToPage(target);
          } else {
            setTrackPosition(getRequestedPage());
          }
        }
        carousel.classList.remove("is-dragging");
        if (carousel.hasPointerCapture(pointerId)) carousel.releasePointerCapture(pointerId);
        pointerId = null;
      }

      carousel.addEventListener("pointerup", releaseGesture);
      carousel.addEventListener("pointercancel", releaseGesture);
      carousel.addEventListener("dragstart", (event) => event.preventDefault());
      carousel.addEventListener("click", (event) => {
        if (performance.now() >= suppressClickUntil || !event.target.closest(".demo-card")) return;
        event.preventDefault();
        event.stopPropagation();
      }, true);
      window.addEventListener("resize", () => renderPage(getRequestedPage(), true));
    }
    window.addEventListener("popstate", () => renderPage(getRequestedPage()));
    renderPage(getRequestedPage(), true);
  }

  function createIdempotencyKey() {
    if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0"));
    return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
  }

  function getSubmitEndpoint() {
    const baseUrl = functionsBaseMeta?.getAttribute("content")?.trim().replace(/\/$/, "") || "";
    return baseUrl ? `${baseUrl}/submit-quote-request` : "";
  }

  function getPrivacySubmitEndpoint() {
    const baseUrl = functionsBaseMeta?.getAttribute("content")?.trim().replace(/\/$/, "") || "";
    return baseUrl ? `${baseUrl}/submit-privacy-request` : "";
  }

  function initContactForm() {
    const form = document.getElementById("contactForm");
    if (!form) return;
    const message = document.getElementById("formMessage");
    const submit = document.getElementById("submitButton");
    const modal = document.getElementById("successPanel");
    const close = document.getElementById("successClose");
    const requestKind = document.getElementById("request-kind");
    const email = document.getElementById("email");
    const phone = document.getElementById("phone");
    const emailLabel = document.getElementById("emailLabel");
    const phoneLabel = document.getElementById("phoneLabel");
    const descriptionLabel = document.getElementById("descriptionLabel");
    const privacyNote = document.getElementById("privacyNote");
    const successTitle = document.getElementById("successTitle");
    const successDescription = document.getElementById("successDescription");
    const commercialFields = [...form.querySelectorAll("[data-commercial-field]")];
    const websiteFields = [...form.querySelectorAll("[data-website-field]")];
    const sdfFields = [...form.querySelectorAll("[data-sdf-field]")];
    const sdfPackage = document.getElementById("sdf-package");
    const customerTypeControls = [...form.querySelectorAll('input[name="customer-type"]')];
    const businessFields = document.getElementById("businessFields");
    const businessControls = [...businessFields.querySelectorAll("input, select, textarea")];
    const vatNumberField = document.getElementById("vatNumberField");
    const vatNumber = document.getElementById("vat-number");
    const packageInterest = document.getElementById("packageInterest");
    let idempotencyKey = "";
    let isSubmitting = false;
    let modalTimer = null;

    function setMessage(text, type) {
      message.classList.remove("is-error", "is-success");
      if (type === "error") message.classList.add("is-error");
      if (type === "success") message.classList.add("is-success");
      message.textContent = text;
    }

    function validateForm() {
      const isPrivacyRequest = requestKind?.value === "privacy";
      if (isPrivacyRequest && !email.value.trim() && !phone.value.trim()) {
        email.focus();
        setMessage("Vul minstens een e-mailadres of telefoonnummer in.", "error");
        return false;
      }

      const requiredFields = form.querySelectorAll("[required]");
      for (const field of requiredFields) {
        if (field instanceof HTMLInputElement && field.type === "checkbox") {
          if (!field.checked) {
            field.focus();
            setMessage("Gelieve de privacytoestemming te bevestigen.", "error");
            return false;
          }
          continue;
        }

        if (field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement || field instanceof HTMLSelectElement) {
          if (!field.value.trim()) {
            field.focus();
            setMessage("Gelieve alle verplichte velden in te vullen.", "error");
            return false;
          }
        }

        if (field instanceof HTMLInputElement && field.type === "email" && field.value.trim()) {
          const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(field.value);
          if (!validEmail) {
            field.focus();
            setMessage("Gelieve een geldig e-mailadres in te vullen.", "error");
            return false;
          }
        }

      }

      if (isPrivacyRequest && email.value.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.value)) {
        email.focus();
        setMessage("Gelieve een geldig e-mailadres in te vullen.", "error");
        return false;
      }

      if (isPrivacyRequest && phone.value.trim()) {
        const digitCount = (phone.value.match(/\d/g) || []).length;
        if (!/^[+0-9().\s-]+$/.test(phone.value) || digitCount < 6 || digitCount > 15) {
          phone.focus();
          setMessage("Gelieve een geldig telefoonnummer in te vullen.", "error");
          return false;
        }
      }
      for (const control of form.querySelectorAll("input, select, textarea")) {
        if (!control.disabled && !control.checkValidity()) {
          control.focus();
          setMessage("Controleer het gemarkeerde veld en probeer opnieuw.", "error");
          return false;
        }
      }
      return true;
    }

    function applyCustomerType() {
      const isPrivacyRequest = requestKind?.value === "privacy";
      const customerType = form.querySelector('input[name="customer-type"]:checked')?.value || "individual";
      const showBusinessFields = !isPrivacyRequest && customerType === "business";
      businessFields.hidden = !showBusinessFields;
      businessControls.forEach((control) => {
        control.disabled = !showBusinessFields;
        control.required = showBusinessFields && control.hasAttribute("data-business-required");
        if (!showBusinessFields && customerType === "individual") {
          if (control instanceof HTMLInputElement && (control.type === "radio" || control.type === "checkbox")) control.checked = false;
          else control.value = "";
        }
      });
      const hasVatNumber = form.querySelector('input[name="has-vat-number"]:checked')?.value;
      const showVatNumber = showBusinessFields && hasVatNumber === "yes";
      vatNumberField.hidden = !showVatNumber;
      vatNumber.disabled = !showVatNumber;
      vatNumber.required = showVatNumber;
      if (!showVatNumber) vatNumber.value = "";
    }

    function applyRequestMode() {
      const isPrivacyRequest = requestKind?.value === "privacy";
      const isDocumentenflowRequest = requestKind?.value === "slimme_documentenflow";
      commercialFields.forEach((field) => {
        field.hidden = isPrivacyRequest;
        field.querySelectorAll("input, select, textarea").forEach((control) => {
          control.required = !isPrivacyRequest;
        });
      });
      websiteFields.forEach((field) => {
        field.hidden = !(!isPrivacyRequest && !isDocumentenflowRequest);
        field.querySelectorAll("input, select, textarea").forEach((control) => {
          control.required = !isPrivacyRequest && !isDocumentenflowRequest;
          control.disabled = isPrivacyRequest || isDocumentenflowRequest;
        });
      });
      sdfFields.forEach((field) => {
        field.hidden = !isDocumentenflowRequest;
        field.querySelectorAll("select").forEach((control) => {
          control.required = isDocumentenflowRequest;
          control.disabled = !isDocumentenflowRequest;
        });
      });
      customerTypeControls.forEach((control) => { control.required = !isPrivacyRequest; });
      applyCustomerType();
      email.required = !isPrivacyRequest;
      emailLabel.textContent = isPrivacyRequest ? "E-mailadres (e-mail of telefoon vereist)" : "E-mailadres";
      phoneLabel.textContent = isPrivacyRequest ? "Telefoonnummer (e-mail of telefoon vereist)" : "Telefoonnummer (optioneel)";
      descriptionLabel.textContent = isPrivacyRequest
        ? "Bericht / privacyverzoek"
        : isDocumentenflowRequest ? "Welke documentenflow wil je bespreken?" : "Projectomschrijving";
      privacyNote.textContent = isPrivacyRequest
        ? "Je privacyverzoek wordt afzonderlijk en vertrouwelijk verwerkt. Vraag hier geen identiteitsbewijs mee te sturen."
        : isDocumentenflowRequest
        ? "Je aanvraag voor Slimme Documentenflow wordt afzonderlijk herkend en persoonlijk nagekeken."
        : "Je aanvraag wordt veilig verwerkt en persoonlijk nagekeken.";
      submit.textContent = isPrivacyRequest
        ? "Verstuur privacyverzoek"
        : isDocumentenflowRequest ? "Verstuur Documentenflow-aanvraag" : "Verstuur aanvraag";
      if (packageInterest && !isDocumentenflowRequest) packageInterest.hidden = true;
      setMessage("", null);
      idempotencyKey = "";
    }

    function closeModal() {
      if (modalTimer) {
        window.clearTimeout(modalTimer);
        modalTimer = null;
      }
      modal.hidden = true;
      submit.focus();
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (isSubmitting || !validateForm()) return;

      const isPrivacyRequest = requestKind?.value === "privacy";
      const endpoint = isPrivacyRequest ? getPrivacySubmitEndpoint() : getSubmitEndpoint();
      if (!endpoint) {
        setMessage("De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op.", "error");
        return;
      }

      const data = new FormData(form);
      const text = (name) => String(data.get(name) || "").trim();
      const isBusinessCustomer = text("customer-type") === "business";
      const isDocumentenflowRequest = requestKind?.value === "slimme_documentenflow";
      const payload = isPrivacyRequest
        ? {
            name: text("name"), email: text("email"), phone: text("phone"),
            message: text("description"), website: text("website")
          }
        : {
          request_kind: isDocumentenflowRequest ? "slimme_documentenflow" : "website",
            ...(isDocumentenflowRequest ? { sdf_package: text("sdf-package") } : {}),
            name: text("name"), customer_type: text("customer-type"),
            ...(isBusinessCustomer ? {
              company: text("company"), enterprise_number: text("enterprise-number"),
              has_vat_number: text("has-vat-number") === "yes", vat_number: text("vat-number"),
              billing_address: text("billing-address"), billing_postal_code: text("billing-postal-code"),
              billing_city: text("billing-city"), billing_country: text("billing-country"), billing_email: text("billing-email")
            } : {}),
            email: text("email"), phone: text("phone"),
            ...(!isDocumentenflowRequest ? {
              website_type: text("website-type"), budget: text("budget"), timing: text("timing")
            } : {}),
            description: text("description"), privacy_consent: data.get("privacy") === "on", website: text("website")
          };
      isSubmitting = true;
      submit.disabled = true;
      submit.setAttribute("aria-busy", "true");
      submit.textContent = "Bezig...";
      setMessage("", "");
      try {
        if (!idempotencyKey) idempotencyKey = createIdempotencyKey();
        const response = await fetch(endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json", "Idempotency-Key": idempotencyKey },
          body: JSON.stringify(payload)
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok && result.code === "VAT_VALIDATION_UNAVAILABLE") {
          document.getElementById("vat-number")?.focus();
          setMessage("De officiële btw-controle is tijdelijk niet beschikbaar. Probeer het later opnieuw.", "error");
          return;
        }
        if (!response.ok && result.field === "vat_number") {
          document.getElementById("vat-number")?.focus();
          setMessage(result.code === "VAT_NUMBER_INVALID"
            ? "Dit btw-nummer kon niet als geldig worden bevestigd. Controleer het nummer."
            : "Dit btw-nummer heeft geen geldig EU-formaat. Controleer het nummer.", "error");
          return;
        }
        if (!response.ok && result.field === "enterprise_number") {
          document.getElementById("enterprise-number")?.focus();
          setMessage("Controleer het ondernemingsnummer.", "error");
          return;
        }
        if (response.status !== 200 && response.status !== 202) throw new Error("Request failed");
        form.reset();
        idempotencyKey = "";
        applyRequestMode();
        successTitle.textContent = isPrivacyRequest ? "Je privacyverzoek is ontvangen." : "Bedankt voor je bericht.";
        successDescription.textContent = isPrivacyRequest
          ? "Je verzoek is veilig opgeslagen en wordt persoonlijk behandeld."
          : isBusinessCustomer && result.vat_validation_status === "valid"
          ? "BTW-nummer geverifieerd. Je aanvraag is veilig verzonden en wordt persoonlijk nagekeken."
          : isBusinessCustomer && text("has-vat-number") === "no"
          ? "Je aanvraag is veilig verzonden en wordt handmatig gecontroleerd op basis van het ondernemingsnummer."
          : "Je aanvraag is veilig verzonden en wordt persoonlijk nagekeken.";
        modal.hidden = false;
        modal.querySelector(".success-panel__inner").focus();
        if (modalTimer) window.clearTimeout(modalTimer);
        modalTimer = window.setTimeout(closeModal, 5000);
      } catch (_error) {
        setMessage("De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op.", "error");
      } finally {
        isSubmitting = false;
        submit.disabled = false;
        submit.removeAttribute("aria-busy");
        submit.textContent = requestKind?.value === "privacy"
          ? "Verstuur privacyverzoek"
          : requestKind?.value === "slimme_documentenflow" ? "Verstuur Documentenflow-aanvraag" : "Verstuur aanvraag";
      }
    });
    form.addEventListener("input", () => {
      if (!isSubmitting) idempotencyKey = "";
      setMessage("", null);
    });
    form.addEventListener("change", () => {
      if (!isSubmitting) idempotencyKey = "";
      setMessage("", null);
    });
    const params = new URLSearchParams(window.location.search);
    const requestedKind = params.get("request-kind");
    if (requestedKind === "slimme_documentenflow") requestKind.value = requestedKind;
    else if (requestedKind === "website") requestKind.value = "quote";
    else if (requestedKind === "privacy") requestKind.value = "privacy";
    const packageLabels = new Map([["start", "Start"], ["groei", "Groei"], ["maatwerk", "Maatwerk"]]);
    const requestedPackage = params.get("package-interest");
    const packageLabel = packageLabels.get(requestedPackage);
    if (packageInterest && requestedKind === "slimme_documentenflow" && packageLabel) {
      sdfPackage.value = requestedPackage;
      packageInterest.textContent = `Interesse in pakket ${packageLabel} (niet-bindende voorkeur).`;
      packageInterest.hidden = false;
    }
    requestKind?.addEventListener("change", applyRequestMode);
    customerTypeControls.forEach((control) => control.addEventListener("change", applyCustomerType));
    form.querySelectorAll('input[name="has-vat-number"]').forEach((control) => control.addEventListener("change", applyCustomerType));
    close.addEventListener("click", closeModal);
    modal.addEventListener("click", (event) => { if (event.target === modal) closeModal(); });
    document.addEventListener("keydown", (event) => { if (event.key === "Escape" && !modal.hidden) closeModal(); });
    applyRequestMode();
  }

  if (menuToggle) menuToggle.addEventListener("click", toggleMenu);
  if (navigation) navigation.addEventListener("click", (event) => { if (event.target.closest("a")) closeMenu(false); });
  document.addEventListener("keydown", (event) => { if (event.key === "Escape") closeMenu(true); });
  window.addEventListener("scroll", () => { if (header) header.classList.toggle("is-scrolled", window.scrollY > 24); }, { passive: true });
  window.addEventListener("resize", () => { if (window.innerWidth > 860) closeMenu(false); });
  document.querySelectorAll("[data-year]").forEach((node) => { node.textContent = String(new Date().getFullYear()); });

  initReveals();
  initPageSignals();
  initDemoPagination();
  initContactForm();
})();

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
    const pageLinks = Array.from(document.querySelectorAll("[data-page-link]"));
    const label = document.querySelector("[data-current-page]");
    const previous = document.querySelector("[data-previous-page]");
    const next = document.querySelector("[data-next-page]");

    function getRequestedPage() {
      const requested = Number(new URLSearchParams(window.location.search).get("page"));
      return requested >= 1 && requested <= pages.length ? requested : 1;
    }

    function renderPage(current) {
      const activePanel = pages.find((panel) => Number(panel.dataset.demoPage) === current);
      activePanel.hidden = false;
      activePanel.classList.add("is-active");
      pages.forEach((panel) => {
        if (panel === activePanel) return;
        panel.classList.remove("is-active");
        panel.hidden = true;
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
    window.addEventListener("popstate", () => renderPage(getRequestedPage()));
    renderPage(getRequestedPage());
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
    const projectFields = [...form.querySelectorAll("[data-project-field]")];
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
      return true;
    }

    function applyRequestMode() {
      const isPrivacyRequest = requestKind?.value === "privacy";
      projectFields.forEach((field) => {
        field.hidden = isPrivacyRequest;
        field.querySelectorAll("input, select, textarea").forEach((control) => {
          if (control.id === "company") return;
          control.required = !isPrivacyRequest;
        });
      });
      email.required = !isPrivacyRequest;
      emailLabel.textContent = isPrivacyRequest ? "E-mailadres (e-mail of telefoon vereist)" : "E-mailadres";
      phoneLabel.textContent = isPrivacyRequest ? "Telefoonnummer (e-mail of telefoon vereist)" : "Telefoonnummer (optioneel)";
      descriptionLabel.textContent = isPrivacyRequest ? "Bericht / privacyverzoek" : "Projectomschrijving";
      privacyNote.textContent = isPrivacyRequest
        ? "Je privacyverzoek wordt afzonderlijk en vertrouwelijk verwerkt. Vraag hier geen identiteitsbewijs mee te sturen."
        : "Je aanvraag wordt veilig verwerkt en persoonlijk nagekeken.";
      submit.textContent = isPrivacyRequest ? "Verstuur privacyverzoek" : "Verstuur aanvraag";
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
      const payload = isPrivacyRequest
        ? {
            name: text("name"), email: text("email"), phone: text("phone"),
            message: text("description"), website: text("website")
          }
        : {
            name: text("name"), company: text("company"), email: text("email"), phone: text("phone"),
            website_type: text("website-type"), budget: text("budget"), timing: text("timing"),
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
        if (response.status !== 200 && response.status !== 202) throw new Error("Request failed");
        form.reset();
        idempotencyKey = "";
        applyRequestMode();
        successTitle.textContent = isPrivacyRequest ? "Je privacyverzoek is ontvangen." : "Bedankt voor je bericht.";
        successDescription.textContent = isPrivacyRequest
          ? "Je verzoek is veilig opgeslagen en wordt persoonlijk behandeld."
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
        submit.textContent = requestKind?.value === "privacy" ? "Verstuur privacyverzoek" : "Verstuur aanvraag";
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
    requestKind?.addEventListener("change", applyRequestMode);
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

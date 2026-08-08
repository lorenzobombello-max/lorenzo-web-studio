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
    const requested = Number(new URLSearchParams(window.location.search).get("page"));
    const current = requested >= 1 && requested <= pages.length ? requested : 1;
    pages.forEach((panel) => {
      const active = Number(panel.dataset.demoPage) === current;
      panel.classList.toggle("is-active", active);
      panel.hidden = !active;
    });
    document.querySelectorAll("[data-page-link]").forEach((link) => {
      if (Number(link.dataset.pageLink) === current) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    });
    const label = document.querySelector("[data-current-page]");
    if (label) label.textContent = `${String(current).padStart(2, "0")} / ${String(pages.length).padStart(2, "0")}`;
    const previous = document.querySelector("[data-previous-page]");
    const next = document.querySelector("[data-next-page]");
    if (previous) {
      previous.href = `?page=${Math.max(1, current - 1)}`;
      previous.toggleAttribute("aria-disabled", current === 1);
    }
    if (next) {
      next.href = `?page=${Math.min(pages.length, current + 1)}`;
      next.toggleAttribute("aria-disabled", current === pages.length);
    }
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

  function initContactForm() {
    const form = document.getElementById("contactForm");
    if (!form) return;
    const message = document.getElementById("formMessage");
    const submit = document.getElementById("submitButton");
    const modal = document.getElementById("successPanel");
    const close = document.getElementById("successClose");
    let idempotencyKey = "";
    let isSubmitting = false;

    function setMessage(text, type) {
      message.classList.remove("is-error", "is-success");
      if (type === "error") message.classList.add("is-error");
      if (type === "success") message.classList.add("is-success");
      message.textContent = text;
    }

    function validateForm() {
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

        if (field instanceof HTMLInputElement && field.type === "email") {
          const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(field.value);
          if (!validEmail) {
            field.focus();
            setMessage("Gelieve een geldig e-mailadres in te vullen.", "error");
            return false;
          }
        }
      }
      return true;
    }

    function closeModal() {
      modal.hidden = true;
      submit.focus();
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (isSubmitting || !validateForm()) return;

      const endpoint = getSubmitEndpoint();
      if (!endpoint) {
        setMessage("De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op.", "error");
        return;
      }

      const data = new FormData(form);
      const text = (name) => String(data.get(name) || "").trim();
      const payload = {
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
        modal.hidden = false;
        modal.querySelector(".success-panel__inner").focus();
      } catch (_error) {
        setMessage("De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op.", "error");
      } finally {
        isSubmitting = false;
        submit.disabled = false;
        submit.removeAttribute("aria-busy");
        submit.textContent = "Verstuur aanvraag";
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
    close.addEventListener("click", closeModal);
    modal.addEventListener("click", (event) => { if (event.target === modal) closeModal(); });
    document.addEventListener("keydown", (event) => { if (event.key === "Escape" && !modal.hidden) closeModal(); });
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

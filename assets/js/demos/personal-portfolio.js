// Core interactions for the personal portfolio demo only.
(function () {
  const root = document.querySelector(".demo--personal-portfolio");
  if (!root) return;

  const docRoot = document.documentElement;
  const loader = root.querySelector("#pageLoader");
  const navToggle = root.querySelector("#navToggle");
  const siteNav = root.querySelector("#siteNav");
  const backToTop = root.querySelector("#backToTop");
  const themeToggle = root.querySelector("#themeToggle");
  const yearNode = root.querySelector("#year");
  const contactForm = root.querySelector("#contactForm") || root.querySelector(".contact-form");
  const formMessage = root.querySelector("#formMessage");
  const submitButton = root.querySelector("#submitButton");
  const functionsBaseMeta = document.querySelector('meta[name="lws-functions-base-url"]');
  const navLinks = root.querySelectorAll(".site-nav a");
  const sectionNavLinks = root.querySelectorAll('.site-nav a[href^="#"]');

  let modalTimer = null;

  function showSuccessModal() {
    const modal = root.querySelector("#successModal");
    const panel = root.querySelector("#successModalPanel");
    const closeBtn = root.querySelector("#successModalClose");
    const overlay = root.querySelector("#successModalOverlay");
    if (!modal || !panel) return;

    if (modalTimer) {
      window.clearTimeout(modalTimer);
      modalTimer = null;
    }

    modal.hidden = false;
    root.classList.add("modal-open");
    panel.focus();

    function closeModal() {
      modal.hidden = true;
      root.classList.remove("modal-open");
      if (modalTimer) {
        window.clearTimeout(modalTimer);
        modalTimer = null;
      }
      if (submitButton) submitButton.focus();
      document.removeEventListener("keydown", handleEscape);
    }

    function handleEscape(event) {
      if (event.key === "Escape") closeModal();
    }

    document.addEventListener("keydown", handleEscape);
    if (closeBtn) closeBtn.addEventListener("click", closeModal, { once: true });
    if (overlay) overlay.addEventListener("click", closeModal, { once: true });

    modalTimer = window.setTimeout(closeModal, 5000);
  }

  function canUseFunctionalStorage() {
    if (!window.LwsConsent || typeof window.LwsConsent.isAllowed !== "function") {
      return true;
    }
    return window.LwsConsent.isAllowed("functional");
  }

  function hideLoader() {
    if (loader) loader.classList.add("is-hidden");
  }

  function initTheme() {
    if (canUseFunctionalStorage()) {
      try {
        const saved = window.LwsConsent?.getFunctionalStorage("site-theme");
        if (saved === "dark" || saved === "light") {
          docRoot.setAttribute("data-theme", saved);
          return;
        }
      } catch (_error) {
        // Keep default behavior when storage is unavailable.
      }
    }

    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    docRoot.setAttribute("data-theme", prefersDark ? "dark" : "light");
  }

  function toggleTheme() {
    const current = docRoot.getAttribute("data-theme") || "light";
    const next = current === "dark" ? "light" : "dark";
    docRoot.setAttribute("data-theme", next);

    if (!canUseFunctionalStorage()) return;

    try {
      window.LwsConsent?.setFunctionalStorage("site-theme", next);
    } catch (_error) {
      // Ignore storage write errors in private contexts.
    }
  }

  function toggleMobileNav() {
    if (!siteNav || !navToggle) return;
    const isOpen = siteNav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
    root.classList.toggle("no-scroll", isOpen);
  }

  function closeMobileNav() {
    if (!siteNav || !navToggle) return;
    siteNav.classList.remove("is-open");
    navToggle.setAttribute("aria-expanded", "false");
    root.classList.remove("no-scroll");
  }

  function handleViewportChange() {
    if (window.innerWidth > 820) closeMobileNav();
  }

  function onScroll() {
    if (!backToTop) return;
    backToTop.classList.toggle("is-visible", window.scrollY > 500);
  }

  function initRevealObserver() {
    const revealNodes = root.querySelectorAll(".reveal");
    if (!revealNodes.length) return;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      revealNodes.forEach((node) => node.classList.add("in-view"));
      return;
    }

    root.classList.add("motion-ready");

    const observer = new IntersectionObserver(
      (entries, obs) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("in-view");
            obs.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.18 }
    );

    revealNodes.forEach((node) => observer.observe(node));
  }

  function updateActiveNavLink() {
    const sections = [...root.querySelectorAll("main section[id]")];
    if (!sections.length || !sectionNavLinks.length) return;

    const scrollPos = window.scrollY + 120;
    sections.forEach((section) => {
      const top = section.offsetTop;
      const bottom = top + section.offsetHeight;
      const id = section.getAttribute("id");
      if (scrollPos >= top && scrollPos < bottom) {
        sectionNavLinks.forEach((link) => {
          const matches = link.getAttribute("href") === `#${id}`;
          link.classList.toggle("is-active", matches);
        });
      }
    });
  }

  function setFormMessage(text, type) {
    if (!formMessage) return;
    formMessage.classList.remove("is-error", "is-success");
    if (type === "error") formMessage.classList.add("is-error");
    if (type === "success") formMessage.classList.add("is-success");
    formMessage.textContent = text;
  }

  function getFunctionsBaseUrl() {
    const value = functionsBaseMeta?.getAttribute("content") || "";
    return value.trim().replace(/\/$/, "");
  }

  function getSubmitEndpoint() {
    const baseUrl = getFunctionsBaseUrl();
    return baseUrl ? `${baseUrl}/submit-quote-request` : "";
  }

  function extractFormPayload(form) {
    const formData = new FormData(form);

    const getText = (name) => {
      const value = formData.get(name);
      return typeof value === "string" ? value.trim() : "";
    };

    return {
      name: getText("name"),
      company: getText("company"),
      email: getText("email"),
      phone: getText("phone"),
      website_type: getText("website-type"),
      budget: getText("budget"),
      timing: getText("timing"),
      description: getText("description"),
      privacy_consent: formData.get("privacy") === "on",
      website: getText("website"),
    };
  }

  function validateForm(form) {
    const requiredFields = form.querySelectorAll("[required]");
    for (const field of requiredFields) {
      if (field instanceof HTMLInputElement && field.type === "checkbox") {
        if (!field.checked) {
          field.focus();
          setFormMessage("Gelieve de privacytoestemming te bevestigen.", "error");
          return false;
        }
        continue;
      }

      if (field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement || field instanceof HTMLSelectElement) {
        if (!field.value.trim()) {
          field.focus();
          setFormMessage("Gelieve alle verplichte velden in te vullen.", "error");
          return false;
        }
      }

      if (field instanceof HTMLInputElement && field.type === "email") {
        const ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(field.value);
        if (!ok) {
          field.focus();
          setFormMessage("Gelieve een geldig e-mailadres in te vullen.", "error");
          return false;
        }
      }
    }
    return true;
  }

  async function handleContactFormSubmit(event) {
    event.preventDefault();
    if (!contactForm) return;

    if (!validateForm(contactForm)) {
      if (submitButton) submitButton.removeAttribute("aria-busy");
      return;
    }

    const endpoint = getSubmitEndpoint();
    if (!endpoint) {
      setFormMessage(
        "De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op.",
        "error"
      );
      return;
    }

    if (submitButton) {
      submitButton.disabled = true;
      submitButton.setAttribute("aria-busy", "true");
      submitButton.textContent = "Bezig...";
    }

    try {
      const payload = extractFormPayload(contactForm);

      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        throw new Error("Request failed");
      }

      contactForm.reset();
      showSuccessModal();
    } catch {
      setFormMessage(
        "De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op.",
        "error"
      );
    } finally {
      if (submitButton) {
        submitButton.disabled = false;
        submitButton.removeAttribute("aria-busy");
        submitButton.textContent = "Verstuur aanvraag";
      }
    }
  }

  window.addEventListener("load", () => {
    hideLoader();
    initRevealObserver();
    updateActiveNavLink();
  });

  window.addEventListener(
    "scroll",
    () => {
      onScroll();
      updateActiveNavLink();
    },
    { passive: true }
  );
  window.addEventListener("resize", handleViewportChange);

  if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
  if (navToggle) navToggle.addEventListener("click", toggleMobileNav);

  navLinks.forEach((link) => {
    link.addEventListener("click", () => {
      if (siteNav?.classList.contains("is-open")) closeMobileNav();
    });
  });

  if (backToTop) {
    backToTop.addEventListener("click", () => {
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
  }

  if (contactForm) {
    contactForm.addEventListener("submit", handleContactFormSubmit);

    contactForm.addEventListener("input", () => {
      setFormMessage("", null);
    });

    contactForm.addEventListener("change", () => {
      setFormMessage("", null);
    });
  }

  if (yearNode) yearNode.textContent = String(new Date().getFullYear());

  initTheme();

  document.addEventListener("lws:consent-changed", (event) => {
    const detail = event.detail;
    if (!detail || !detail.categories) return;

    if (!detail.categories.functional) {
      initTheme();
      return;
    }

    const current = docRoot.getAttribute("data-theme");
    if (current === "dark" || current === "light") {
      try {
        window.LwsConsent?.setFunctionalStorage("site-theme", current);
      } catch (_error) {
        // Ignore storage write errors in private contexts.
      }
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeMobileNav();
  });

  root.addEventListener("click", (event) => {
    if (!siteNav || !navToggle) return;
    const target = event.target;
    if (!(target instanceof Node)) return;
    if (!siteNav.contains(target) && !navToggle.contains(target)) closeMobileNav();
  });
})();

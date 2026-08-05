// Core interactions: theme, mobile nav, reveal animations, form validation and secure quote submit.
(function () {
  const root = document.documentElement;
  const body = document.body;
  const loader = document.getElementById("pageLoader");
  const navToggle = document.getElementById("navToggle");
  const siteNav = document.getElementById("siteNav");
  const backToTop = document.getElementById("backToTop");
  const themeToggle = document.getElementById("themeToggle");
  const yearNode = document.getElementById("year");
  const contactForm = document.getElementById("contactForm") || document.querySelector(".contact-form");
  const formMessage = document.getElementById("formMessage");
  const submitButton = document.getElementById("submitButton");
  const functionsBaseMeta = document.querySelector('meta[name="lws-functions-base-url"]');
  const navLinks = document.querySelectorAll(".site-nav a");
  const sectionNavLinks = document.querySelectorAll('.site-nav a[href^="#"]');

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
        const saved = localStorage.getItem("site-theme");
        if (saved === "dark" || saved === "light") {
          root.setAttribute("data-theme", saved);
          return;
        }
      } catch (_error) {
        // Keep default behavior when storage is unavailable.
      }
    }

    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    root.setAttribute("data-theme", prefersDark ? "dark" : "light");
  }

  function toggleTheme() {
    const current = root.getAttribute("data-theme") || "light";
    const next = current === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);

    if (!canUseFunctionalStorage()) return;

    try {
      localStorage.setItem("site-theme", next);
    } catch (_error) {
      // Ignore storage write errors in private contexts.
    }
  }

  function toggleMobileNav() {
    if (!siteNav || !navToggle) return;
    const isOpen = siteNav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
    body.classList.toggle("no-scroll", isOpen);
  }

  function closeMobileNav() {
    if (!siteNav || !navToggle) return;
    siteNav.classList.remove("is-open");
    navToggle.setAttribute("aria-expanded", "false");
    body.classList.remove("no-scroll");
  }

  function handleViewportChange() {
    if (window.innerWidth > 820) closeMobileNav();
  }

  function onScroll() {
    if (!backToTop) return;
    backToTop.classList.toggle("is-visible", window.scrollY > 500);
  }

  function initRevealObserver() {
    const revealNodes = document.querySelectorAll(
      ".reveal, .reveal-industrial, .reveal-restaurant, .reveal-mediterranean"
    );
    if (!revealNodes.length) return;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      revealNodes.forEach((node) => node.classList.add("in-view"));
      return;
    }

    body.classList.add("motion-ready");

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
    const sections = [...document.querySelectorAll("main section[id]")];
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

      setFormMessage(
        "Bedankt. Je aanvraag is veilig ontvangen en wordt persoonlijk nagekeken.",
        "success"
      );
      contactForm.reset();
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

  window.addEventListener("scroll", () => {
    onScroll();
    updateActiveNavLink();
  }, { passive: true });
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

    const current = root.getAttribute("data-theme");
    if (current === "dark" || current === "light") {
      try {
        localStorage.setItem("site-theme", current);
      } catch (_error) {
        // Ignore storage write errors in private contexts.
      }
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeMobileNav();
  });

  body.addEventListener("click", (event) => {
    if (!siteNav || !navToggle) return;
    const target = event.target;
    if (!(target instanceof Node)) return;
    if (!siteNav.contains(target) && !navToggle.contains(target)) closeMobileNav();
  });

})();

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
        const saved = localStorage.getItem("site-theme");
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
      localStorage.setItem("site-theme", next);
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
        localStorage.setItem("site-theme", current);
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

// Cookie consent (personal portfolio demo only, migrated from shared assets/js/cookie-consent.js).
(function () {
  const CONSENT_KEY = "lws_cookie_preferences";
  const CONSENT_VERSION = "2026-08-05";
  const FONT_FLAG_ATTRIBUTE = "data-lws-fonts-loaded";
  const FUNCTIONAL_STORAGE_KEYS = ["site-theme"];

  function nowIso() {
    return new Date().toISOString();
  }

  function baseConsent() {
    return {
      version: CONSENT_VERSION,
      updatedAt: nowIso(),
      categories: {
        necessary: true,
        functional: false,
        analytics: false,
        marketing: false,
      },
    };
  }

  function hasValidStoredConsentShape(value) {
    if (!value || typeof value !== "object") return false;
    if (value.version !== CONSENT_VERSION) return false;
    if (typeof value.updatedAt !== "string" || !value.updatedAt.trim()) return false;

    const categories = value.categories;
    if (!categories || typeof categories !== "object") return false;

    return categories.necessary === true
      && typeof categories.functional === "boolean"
      && typeof categories.analytics === "boolean"
      && typeof categories.marketing === "boolean";
  }

  function readConsent() {
    try {
      const raw = localStorage.getItem(CONSENT_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      if (!hasValidStoredConsentShape(parsed)) return null;

      const categories = parsed.categories;
      return {
        version: parsed.version,
        updatedAt: parsed.updatedAt,
        categories: {
          necessary: true,
          functional: Boolean(categories.functional),
          analytics: Boolean(categories.analytics),
          marketing: Boolean(categories.marketing),
        },
      };
    } catch (_error) {
      return null;
    }
  }

  function saveConsent(next) {
    const payload = {
      version: CONSENT_VERSION,
      updatedAt: nowIso(),
      categories: {
        necessary: true,
        functional: Boolean(next?.categories?.functional),
        analytics: Boolean(next?.categories?.analytics),
        marketing: Boolean(next?.categories?.marketing),
      },
    };

    localStorage.setItem(CONSENT_KEY, JSON.stringify(payload));
    return payload;
  }

  function createPreferencesButton() {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "cookie-preferences-link";
    button.id = "cookiePreferencesLink";
    button.setAttribute("aria-haspopup", "dialog");
    button.setAttribute("aria-controls", "cookieModal");
    button.textContent = "Cookievoorkeuren";
    return button;
  }

  function ensurePreferencesLauncher() {
    const existing = document.getElementById("cookiePreferencesLink");
    if (existing instanceof HTMLButtonElement) return existing;

    const button = createPreferencesButton();
    const footerList = document.querySelector(".site-footer .footer-grid > div:last-child ul");
    if (footerList instanceof HTMLUListElement) {
      const item = document.createElement("li");
      item.append(button);
      footerList.append(item);
      return button;
    }
    return null;
  }

  function clearFunctionalStorage() {
    FUNCTIONAL_STORAGE_KEYS.forEach((key) => {
      try {
        localStorage.removeItem(key);
      } catch (_error) {
        // Ignore quota and private-mode errors.
      }
    });
  }

  function loadGoogleFontsOnce() {
    if (document.documentElement.getAttribute(FONT_FLAG_ATTRIBUTE) === "1") return;

    const alreadyLoaded = Array.from(document.querySelectorAll("link[href]"))
      .some((link) => (link.getAttribute("href") || "").includes("fonts.googleapis.com"));

    if (alreadyLoaded) {
      document.documentElement.setAttribute(FONT_FLAG_ATTRIBUTE, "1");
      return;
    }

    const preconnectApi = document.createElement("link");
    preconnectApi.rel = "preconnect";
    preconnectApi.href = "https://fonts.googleapis.com";

    const preconnectStatic = document.createElement("link");
    preconnectStatic.rel = "preconnect";
    preconnectStatic.href = "https://fonts.gstatic.com";
    preconnectStatic.crossOrigin = "";

    const stylesheet = document.createElement("link");
    stylesheet.rel = "stylesheet";
    stylesheet.href = "https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Newsreader:opsz,wght@6..72,600;6..72,700&display=swap";

    document.head.append(preconnectApi, preconnectStatic, stylesheet);
    document.documentElement.setAttribute(FONT_FLAG_ATTRIBUTE, "1");
  }

  function applyConsent(consent) {
    const functionalAllowed = Boolean(consent?.categories?.functional);
    const analyticsAllowed = Boolean(consent?.categories?.analytics);
    const marketingAllowed = Boolean(consent?.categories?.marketing);

    document.documentElement.dataset.cookieFunctional = functionalAllowed ? "granted" : "denied";
    document.documentElement.dataset.cookieAnalytics = analyticsAllowed ? "granted" : "denied";
    document.documentElement.dataset.cookieMarketing = marketingAllowed ? "granted" : "denied";

    if (functionalAllowed) {
      loadGoogleFontsOnce();
    } else {
      clearFunctionalStorage();
    }
  }

  function createBanner() {
    const host = document.createElement("section");
    host.className = "cookie-consent";
    host.id = "cookieConsentBanner";
    host.hidden = true;
    host.setAttribute("role", "dialog");
    host.setAttribute("aria-modal", "true");
    host.setAttribute("aria-labelledby", "cookieConsentTitle");
    host.setAttribute("aria-describedby", "cookieConsentDescription");
    host.innerHTML = [
      '<div class="cookie-consent__content">',
      '<p class="cookie-consent__kicker">Cookievoorkeuren</p>',
      '<h2 id="cookieConsentTitle">Kies welke categorieen je toelaat</h2>',
      '<p id="cookieConsentDescription">Noodzakelijke opslag staat altijd aan. Functionele, analytische en marketingcategorieen kan je zelf beheren.</p>',
      '<div class="cookie-consent__actions">',
      '<button type="button" class="btn btn--primary" data-cookie-action="accept-all">Alles accepteren</button>',
      '<button type="button" class="btn btn--ghost" data-cookie-action="reject-all">Alles weigeren</button>',
      '<button type="button" class="btn btn--ghost" data-cookie-action="manage">Voorkeuren beheren</button>',
      '</div>',
      '</div>',
    ].join("");
    return host;
  }

  function createModal() {
    const host = document.createElement("section");
    host.className = "cookie-modal";
    host.id = "cookieModal";
    host.setAttribute("role", "dialog");
    host.setAttribute("aria-modal", "true");
    host.setAttribute("aria-labelledby", "cookieModalTitle");
    host.hidden = true;
    host.innerHTML = [
      '<div class="cookie-modal__panel">',
      '<h2 id="cookieModalTitle">Beheer cookievoorkeuren</h2>',
      '<p>Kies per categorie welke opslag of externe diensten je toelaat.</p>',
      '<form id="cookiePreferencesForm" novalidate>',
      '<fieldset class="cookie-modal__group">',
      '<legend>Noodzakelijk</legend>',
      '<label><input type="checkbox" checked disabled /> Altijd actief (vereist voor basisfunctionaliteit en beveiliging)</label>',
      '</fieldset>',
      '<fieldset class="cookie-modal__group">',
      '<legend>Functioneel</legend>',
      '<label><input type="checkbox" name="functional" /> Voorkeursopslag en externe lettertypes</label>',
      '</fieldset>',
      '<fieldset class="cookie-modal__group">',
      '<legend>Analytisch</legend>',
      '<label><input type="checkbox" name="analytics" /> Meten van gebruik en prestaties</label>',
      '</fieldset>',
      '<fieldset class="cookie-modal__group">',
      '<legend>Marketing</legend>',
      '<label><input type="checkbox" name="marketing" /> Tracking voor advertenties en remarketing</label>',
      '</fieldset>',
      '<div class="cookie-modal__actions">',
      '<button type="submit" class="btn btn--primary">Voorkeuren opslaan</button>',
      '<button type="button" class="btn btn--ghost" data-cookie-action="close-modal">Sluiten</button>',
      '</div>',
      '</form>',
      '</div>',
    ].join("");
    return host;
  }

  function syncModalFromConsent(modal, consent) {
    const functional = modal.querySelector('input[name="functional"]');
    const analytics = modal.querySelector('input[name="analytics"]');
    const marketing = modal.querySelector('input[name="marketing"]');
    if (!functional || !analytics || !marketing) return;

    functional.checked = Boolean(consent?.categories?.functional);
    analytics.checked = Boolean(consent?.categories?.analytics);
    marketing.checked = Boolean(consent?.categories?.marketing);
  }

  function setBannerVisibility(banner, visible) {
    banner.hidden = !visible;
    if (visible) {
      const firstButton = banner.querySelector("button");
      firstButton?.focus();
    }
  }

  function setModalVisibility(modal, visible) {
    modal.hidden = !visible;
    document.body.classList.toggle("no-scroll", visible);
    if (visible) {
      const firstFocusable = modal.querySelector("input[name='functional']");
      firstFocusable?.focus();
    }
  }

  let state = readConsent();

  const api = {
    getConsent() {
      return state;
    },
    isAllowed(category) {
      if (category === "necessary") return true;
      const categories = state?.categories;
      return Boolean(categories && categories[category]);
    },
    openPreferences() {
      const modal = document.getElementById("cookieModal");
      if (!modal) return;
      syncModalFromConsent(modal, state || baseConsent());
      setModalVisibility(modal, true);
    },
  };

  window.LwsConsent = api;

  function publishConsentChanged(consent) {
    document.dispatchEvent(
      new CustomEvent("lws:consent-changed", {
        detail: {
          consent,
          categories: consent.categories,
        },
      })
    );
  }

  document.addEventListener("DOMContentLoaded", () => {
    const banner = createBanner();
    const modal = createModal();
    document.body.append(banner, modal);
    const footerPreferencesLink = ensurePreferencesLauncher();

    const activeConsent = state || baseConsent();

    if (!state) {
      applyConsent(activeConsent);
      setBannerVisibility(banner, true);
    } else {
      applyConsent(activeConsent);
      setBannerVisibility(banner, false);
    }

    function openPreferencesFromLink() {
      syncModalFromConsent(modal, state || baseConsent());
      setModalVisibility(modal, true);
    }

    if (footerPreferencesLink) {
      footerPreferencesLink.addEventListener("click", openPreferencesFromLink);
    }

    document.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof HTMLElement)) return;
      if (target.id !== "cookiePreferencesLink") return;
      event.preventDefault();
      openPreferencesFromLink();
    });

    banner.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof HTMLElement)) return;
      const action = target.getAttribute("data-cookie-action");
      if (!action) return;

      if (action === "accept-all") {
        state = saveConsent({ categories: { functional: true, analytics: true, marketing: true } });
        applyConsent(state);
        setBannerVisibility(banner, false);
        publishConsentChanged(state);
        return;
      }

      if (action === "reject-all") {
        state = saveConsent({ categories: { functional: false, analytics: false, marketing: false } });
        applyConsent(state);
        setBannerVisibility(banner, false);
        publishConsentChanged(state);
        return;
      }

      if (action === "manage") {
        syncModalFromConsent(modal, state || baseConsent());
        setModalVisibility(modal, true);
      }
    });

    modal.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof HTMLElement)) return;
      const action = target.getAttribute("data-cookie-action");
      if (action === "close-modal") {
        setModalVisibility(modal, false);
      }
    });

    const form = modal.querySelector("#cookiePreferencesForm");
    if (form instanceof HTMLFormElement) {
      form.addEventListener("submit", (event) => {
        event.preventDefault();
        const formData = new FormData(form);
        state = saveConsent({
          categories: {
            functional: formData.get("functional") === "on",
            analytics: formData.get("analytics") === "on",
            marketing: formData.get("marketing") === "on",
          },
        });
        applyConsent(state);
        setBannerVisibility(banner, false);
        setModalVisibility(modal, false);
        publishConsentChanged(state);
      });
    }

    modal.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        setModalVisibility(modal, false);
      }
    });
  });
})();
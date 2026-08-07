(function () {
  const root = document.documentElement;
  const body = document.body;

  function canUseFunctionalStorage() {
    if (!window.LwsConsent || typeof window.LwsConsent.isAllowed !== "function") {
      return true;
    }
    return window.LwsConsent.isAllowed("functional");
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
        // Ignore storage read issues.
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
      // Ignore storage write issues.
    }
  }

  function hideLoader() {
    const loader = document.getElementById("pageLoader");
    if (loader) loader.classList.add("is-hidden");
  }

  function toggleMobileNav() {
    const siteNav = document.getElementById("siteNav");
    const navToggle = document.getElementById("navToggle");
    if (!siteNav || !navToggle) return;
    const isOpen = siteNav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
    body.classList.toggle("no-scroll", isOpen);
  }

  function closeMobileNav() {
    const siteNav = document.getElementById("siteNav");
    const navToggle = document.getElementById("navToggle");
    if (!siteNav || !navToggle) return;
    siteNav.classList.remove("is-open");
    navToggle.setAttribute("aria-expanded", "false");
    body.classList.remove("no-scroll");
  }

  function handleViewportChange() {
    if (window.innerWidth > 980) closeMobileNav();
  }

  function initRevealObserver() {
    const nodes = document.querySelectorAll(".reveal");
    if (!nodes.length) return;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      nodes.forEach((node) => node.classList.add("in-view"));
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

    nodes.forEach((node) => observer.observe(node));
  }

  function updateActiveNavLink() {
    const sections = [...document.querySelectorAll("main section[id]")];
    const links = document.querySelectorAll('.site-nav a[href^="#"]');
    if (!sections.length || !links.length) return;

    const scrollPos = window.scrollY + 120;
    sections.forEach((section) => {
      const top = section.offsetTop;
      const bottom = top + section.offsetHeight;
      const id = section.getAttribute("id");
      if (scrollPos >= top && scrollPos < bottom) {
        links.forEach((link) => {
          link.classList.toggle("is-active", link.getAttribute("href") === `#${id}`);
        });
      }
    });
  }

  function initBackToTop() {
    const backToTop = document.getElementById("backToTop");
    if (!backToTop) return;

    const onScroll = () => {
      backToTop.classList.toggle("is-visible", window.scrollY > 500);
      updateActiveNavLink();
    };

    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    backToTop.addEventListener("click", () => {
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
  }

  function initYear() {
    const yearNode = document.getElementById("year");
    if (yearNode) yearNode.textContent = String(new Date().getFullYear());
  }

  function initHeaderCondense() {
    const header = document.getElementById("siteHeader");
    if (!header) return;

    const sync = () => {
      header.classList.toggle("is-condensed", window.scrollY > 28);
    };

    sync();
    window.addEventListener("scroll", sync, { passive: true });
  }

  function initDrinkTabs() {
    const stage = document.getElementById("drinkStage");
    const tabs = Array.from(document.querySelectorAll(".cafe-drink-tab"));
    const panels = Array.from(document.querySelectorAll(".cafe-drink-panel"));
    if (!stage || !tabs.length || !panels.length) return;

    const activate = (panelKey) => {
      tabs.forEach((tab) => {
        const active = tab.dataset.panel === panelKey;
        tab.classList.toggle("is-active", active);
        tab.setAttribute("aria-selected", String(active));
        tab.tabIndex = active ? 0 : -1;
        if (active) stage.dataset.drinkTone = panelKey;
      });

      panels.forEach((panel) => {
        const active = panel.id === `panel-${panelKey}`;
        panel.classList.toggle("is-active", active);
        panel.hidden = !active;
      });
    };

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => activate(tab.dataset.panel || "beer"));
      tab.addEventListener("keydown", (event) => {
        const currentIndex = tabs.indexOf(tab);
        if (event.key === "ArrowRight") {
          event.preventDefault();
          const nextTab = tabs[(currentIndex + 1) % tabs.length];
          nextTab.focus();
          activate(nextTab.dataset.panel || "beer");
        }
        if (event.key === "ArrowLeft") {
          event.preventDefault();
          const previousTab = tabs[(currentIndex - 1 + tabs.length) % tabs.length];
          previousTab.focus();
          activate(previousTab.dataset.panel || "beer");
        }
        if (event.key === "Home") {
          event.preventDefault();
          tabs[0].focus();
          activate(tabs[0].dataset.panel || "beer");
        }
        if (event.key === "End") {
          event.preventDefault();
          tabs[tabs.length - 1].focus();
          activate(tabs[tabs.length - 1].dataset.panel || "cocktail");
        }
      });
    });

    activate("beer");
  }

  function initReservationForm() {
    const form = document.getElementById("reservationForm");
    const message = document.getElementById("reservationMessage");
    if (!(form instanceof HTMLFormElement) || !message) return;

    const setMessage = (text, type) => {
      message.textContent = text;
      message.classList.remove("is-error", "is-success");
      if (type === "error") message.classList.add("is-error");
      if (type === "success") message.classList.add("is-success");
    };

    form.addEventListener("submit", (event) => {
      event.preventDefault();
      setMessage("", null);

      if (!form.reportValidity()) return;

      const phoneInput = form.querySelector("#guest-phone");
      const emailInput = form.querySelector("#guest-email");
      const phone = phoneInput instanceof HTMLInputElement ? phoneInput.value.trim() : "";
      const email = emailInput instanceof HTMLInputElement ? emailInput.value.trim() : "";

      if (!phone && !email) {
        setMessage("Geef in deze demo minstens een telefoonnummer of e-mailadres op.", "error");
        if (phoneInput instanceof HTMLInputElement) phoneInput.focus();
        return;
      }

      if (email && emailInput instanceof HTMLInputElement) {
        const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
        if (!validEmail) {
          setMessage("Gebruik een geldig e-mailadres of laat het veld leeg en vul je telefoonnummer in.", "error");
          emailInput.focus();
          return;
        }
      }

      const sizeInput = form.querySelector("#party-size");
      const dateInput = form.querySelector("#reservation-date");
      const timeInput = form.querySelector("#reservation-time");
      const size = sizeInput instanceof HTMLSelectElement ? sizeInput.value : "je gezelschap";
      const date = dateInput instanceof HTMLInputElement ? dateInput.value : "de gekozen datum";
      const time = timeInput instanceof HTMLInputElement ? timeInput.value : "het gekozen tijdstip";

      setMessage(`Demobevestiging: reservatie-aanvraag ontvangen voor ${size} op ${date} om ${time}. Dit formulier verzendt niets buiten deze demo.`, "success");
      form.reset();
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    const themeToggle = document.getElementById("themeToggle");
    const navToggle = document.getElementById("navToggle");
    const navLinks = document.querySelectorAll(".site-nav a");

    initTheme();
    initYear();
    initHeaderCondense();
    initDrinkTabs();
    initReservationForm();

    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
    if (navToggle) navToggle.addEventListener("click", toggleMobileNav);

    navLinks.forEach((link) => {
      link.addEventListener("click", () => {
        const siteNav = document.getElementById("siteNav");
        if (siteNav?.classList.contains("is-open")) closeMobileNav();
      });
    });

    window.addEventListener("resize", handleViewportChange);
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeMobileNav();
    });

    body.addEventListener("click", (event) => {
      const siteNav = document.getElementById("siteNav");
      const navToggleButton = document.getElementById("navToggle");
      if (!siteNav || !navToggleButton) return;
      const target = event.target;
      if (!(target instanceof Node)) return;
      if (!siteNav.contains(target) && !navToggleButton.contains(target)) closeMobileNav();
    });
  });

  window.addEventListener("load", () => {
    hideLoader();
    initRevealObserver();
    updateActiveNavLink();
    initBackToTop();
  });

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
        // Ignore storage write issues.
      }
    }
  });
})();

// Cookie consent (cafe demo only, migrated from shared assets/js/cookie-consent.js).
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
    const footerTarget = document.querySelector(".cafe-footer");
    if (!(footerTarget instanceof HTMLElement)) return null;

    const slot = document.createElement("p");
    slot.className = "cookie-preferences-slot";
    slot.append(button);
    footerTarget.append(slot);
    return button;
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

(function () {
  const root = document.querySelector(".demo--mediterranean-brasserie");
  if (!root) return;

  const docRoot = document.documentElement;
  const header = root.querySelector("#mbHeader");
  const navToggle = root.querySelector("#mbMenuToggle");
  const nav = root.querySelector("#mbNav");
  const themeToggle = root.querySelector("#themeToggle");
  const tabs = Array.from(root.querySelectorAll('[role="tab"][data-tab]'));
  const panels = Array.from(root.querySelectorAll('[role="tabpanel"][data-panel]'));
  const reservationForm = root.querySelector("#mbReservationForm");
  const reservationMessage = root.querySelector("#mbReservationMessage");

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

  function updateHeader() {
    if (!header) return;
    header.classList.toggle("is-compact", window.scrollY > 44);
  }

  function closeMenu() {
    if (!nav || !navToggle) return;
    nav.classList.remove("is-open");
    navToggle.setAttribute("aria-expanded", "false");
  }

  function toggleMenu() {
    if (!nav || !navToggle) return;
    const isOpen = nav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
  }

  function activateTab(nextTab, focusTab) {
    if (!nextTab) return;
    const tabName = nextTab.dataset.tab;

    tabs.forEach((tab) => {
      const selected = tab === nextTab;
      tab.setAttribute("aria-selected", String(selected));
      tab.setAttribute("tabindex", selected ? "0" : "-1");
    });

    panels.forEach((panel) => {
      panel.hidden = panel.dataset.panel !== tabName;
    });

    if (focusTab) nextTab.focus();
  }

  function onTabKeydown(event) {
    const currentIndex = tabs.indexOf(event.currentTarget);
    if (currentIndex === -1) return;

    let nextIndex = currentIndex;

    if (event.key === "ArrowDown" || event.key === "ArrowRight") {
      nextIndex = (currentIndex + 1) % tabs.length;
    }

    if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
      nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
    }

    if (event.key === "Home") nextIndex = 0;
    if (event.key === "End") nextIndex = tabs.length - 1;

    if (nextIndex !== currentIndex) {
      event.preventDefault();
      activateTab(tabs[nextIndex], true);
    }
  }

  function setFormMessage(text, type) {
    if (!reservationMessage) return;
    reservationMessage.classList.remove("is-error", "is-success");
    if (type) reservationMessage.classList.add(type);
    reservationMessage.textContent = text;
  }

  function invalidateField(field, message) {
    field.setAttribute("aria-invalid", "true");
    setFormMessage(message, "is-error");
    field.focus();
  }

  function clearFieldState(field) {
    field.removeAttribute("aria-invalid");
  }

  function validateReservationForm() {
    if (!reservationForm) return false;

    const required = reservationForm.querySelectorAll("input[required]");

    for (const field of required) {
      clearFieldState(field);

      if (!field.value.trim()) {
        invalidateField(field, "Vul alle verplichte reservatievelden in.");
        return false;
      }

      if (field.type === "email") {
        const ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(field.value.trim());
        if (!ok) {
          invalidateField(field, "Vul een geldig e-mailadres in.");
          return false;
        }
      }

      if (field.type === "number") {
        const value = Number(field.value);
        if (!Number.isFinite(value) || value < 1 || value > 20) {
          invalidateField(field, "Aantal gasten moet tussen 1 en 20 liggen.");
          return false;
        }
      }
    }

    return true;
  }

  function handleReservationSubmit(event) {
    event.preventDefault();
    if (!reservationForm) return;

    if (!validateReservationForm()) return;

    setFormMessage("Bedankt. Dit is een demo-bevestiging: uw reservatieaanvraag is lokaal geregistreerd voor presentatie.", "is-success");
    reservationForm.reset();
  }

  function initTabs() {
    if (!tabs.length || !panels.length) return;
    tabs.forEach((tab) => {
      tab.addEventListener("click", () => activateTab(tab, false));
      tab.addEventListener("keydown", onTabKeydown);
    });
  }

  function initNav() {
    if (navToggle) navToggle.addEventListener("click", toggleMenu);
    if (nav) {
      nav.querySelectorAll("a").forEach((link) => {
        link.addEventListener("click", closeMenu);
      });
    }

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeMenu();
    });

    document.addEventListener("click", (event) => {
      if (!nav || !navToggle) return;
      if (!(event.target instanceof Node)) return;
      if (!nav.contains(event.target) && !navToggle.contains(event.target)) closeMenu();
    });
  }

  function initReservation() {
    if (!reservationForm) return;
    reservationForm.addEventListener("submit", handleReservationSubmit);
    reservationForm.addEventListener("input", () => {
      const fields = reservationForm.querySelectorAll("input, textarea");
      fields.forEach(clearFieldState);
      setFormMessage("", "");
    });
  }

  window.addEventListener("scroll", updateHeader, { passive: true });
  window.addEventListener("resize", () => {
    if (window.innerWidth > 900) closeMenu();
  });

  if (themeToggle) themeToggle.addEventListener("click", toggleTheme);

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

  updateHeader();
  initNav();
  initTabs();
  initReservation();
  initTheme();

  docRoot.classList.remove("no-js");
})();

// Cookie consent (mediterranean-brasserie demo only, migrated from shared assets/js/cookie-consent.js).
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
    const footerTarget = document.querySelector(".mb-footer__inner");
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

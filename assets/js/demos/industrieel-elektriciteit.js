(function () {
  "use strict";

  var doc = document;
  var root = doc.querySelector(".demo--industrial-electricity");
  if (!root) return;

  function qs(sel, scopeRoot) {
    return (scopeRoot || root).querySelector(sel);
  }

  function qsa(sel, scopeRoot) {
    return Array.prototype.slice.call((scopeRoot || root).querySelectorAll(sel));
  }

  function setYear() {
    var yearNode = qs("#year");
    if (yearNode) {
      yearNode.textContent = String(new Date().getFullYear());
    }
  }

  function initTheme() {
    var docRoot = document.documentElement;
    var saved = null;
    try {
      saved = localStorage.getItem("site-theme");
    } catch (error) {
      saved = null;
    }

    if (saved === "light" || saved === "dark") {
      docRoot.setAttribute("data-theme", saved);
      return;
    }

    var prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    docRoot.setAttribute("data-theme", prefersDark ? "dark" : "light");
  }

  function initThemeToggle() {
    var toggle = qs("#themeToggle");
    if (!toggle) return;

    toggle.addEventListener("click", function () {
      var docRoot = document.documentElement;
      var current = docRoot.getAttribute("data-theme") || "dark";
      var next = current === "dark" ? "light" : "dark";
      docRoot.setAttribute("data-theme", next);
      try {
        localStorage.setItem("site-theme", next);
      } catch (error) {
        // The theme still switches for this page when storage is unavailable.
      }
    });
  }

  function initHeaderCompact() {
    var header = qs("#industrialHeader");
    if (!header) return;

    function onScroll() {
      if (window.scrollY > 24) {
        header.classList.add("is-compact");
      } else {
        header.classList.remove("is-compact");
      }
    }

    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  function initMenu() {
    var toggle = qs("#menuToggle");
    var nav = qs("#siteNav");
    if (!toggle || !nav) return;

    toggle.addEventListener("click", function () {
      var expanded = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", expanded ? "false" : "true");
      nav.classList.toggle("is-open", !expanded);
    });

    qsa("a", nav).forEach(function (link) {
      link.addEventListener("click", function () {
        toggle.setAttribute("aria-expanded", "false");
        nav.classList.remove("is-open");
      });
    });

    doc.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        toggle.setAttribute("aria-expanded", "false");
        nav.classList.remove("is-open");
      }
    });

    root.addEventListener("click", function (event) {
      if (!nav || !toggle) return;
      var target = event.target;
      if (!(target instanceof Node)) return;
      if (!nav.contains(target) && !toggle.contains(target)) {
        toggle.setAttribute("aria-expanded", "false");
        nav.classList.remove("is-open");
      }
    });
  }

  function initUrgencySelector() {
    var buttons = qsa(".urgency-options button");
    var hidden = qs("#urgency");
    if (!buttons.length || !hidden) return;

    buttons.forEach(function (btn) {
      btn.addEventListener("click", function () {
        buttons.forEach(function (b) {
          b.setAttribute("aria-checked", "false");
        });
        btn.setAttribute("aria-checked", "true");
        hidden.value = btn.getAttribute("data-urgency") || "stop";
      });
    });
  }

  function markInvalid(el, invalid) {
    if (!el) return;
    if (invalid) {
      el.setAttribute("aria-invalid", "true");
    } else {
      el.removeAttribute("aria-invalid");
    }
  }

  function initIncidentForm() {
    var form = qs("#incidentForm");
    var feedback = qs("#incidentFeedback");
    if (!form || !feedback) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();

      feedback.classList.remove("is-error", "is-success");
      feedback.textContent = "";

      var fields = qsa("select[required], input[required], textarea[required]", form);
      var firstInvalid = null;

      fields.forEach(function (field) {
        var valid = field.checkValidity();
        markInvalid(field, !valid);
        if (!valid && !firstInvalid) {
          firstInvalid = field;
        }
      });

      if (firstInvalid) {
        feedback.classList.add("is-error");
        feedback.textContent = "Vul alle verplichte velden correct in voor de demonstratieve storingsmelding.";
        firstInvalid.focus();
        return;
      }

      feedback.classList.add("is-success");
      feedback.textContent = "Demo bevestigd: de storingsmelding is lokaal gesimuleerd en niet echt verzonden.";
      form.reset();

      var defaultUrgency = qs('.urgency-options button[data-urgency="stop"]');
      if (defaultUrgency) {
        qsa(".urgency-options button").forEach(function (b) {
          b.setAttribute("aria-checked", b === defaultUrgency ? "true" : "false");
        });
      }

      var hidden = qs("#urgency");
      if (hidden) hidden.value = "stop";
    });
  }

  function initDashboardFilter() {
    var buttons = qsa(".dashboard-filter button");
    var cards = qsa(".asset-card");
    if (!buttons.length || !cards.length) return;

    buttons.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var filter = btn.getAttribute("data-filter") || "all";

        buttons.forEach(function (b) {
          b.classList.toggle("is-active", b === btn);
        });

        cards.forEach(function (card) {
          var state = card.getAttribute("data-state");
          card.hidden = !(filter === "all" || state === filter);
        });
      });
    });
  }

  function initAnalyzer() {
    var options = qsa(".analyzer-options button");
    var titleNode = qs("#analyzerResultTitle");
    var listNode = qs("#analyzerChecklist");
    if (!options.length || !titleNode || !listNode) return;

    var mappings = {
      start: {
        title: "Mogelijke controlegebieden: installatie start niet",
        checks: ["Voeding", "Beveiligingen", "Besturing", "Mechanische blokkering"]
      },
      move: {
        title: "Mogelijke controlegebieden: onregelmatige beweging",
        checks: ["Aandrijving", "Uitlijning", "Sensoren", "Pneumatiek"]
      },
      air: {
        title: "Mogelijke controlegebieden: luchtverlies",
        checks: ["Pneumatiek", "Ventielen", "Cilinders", "Aansluitingen"]
      },
      heat: {
        title: "Mogelijke controlegebieden: oververhitting",
        checks: ["Koeling", "Lagerconditie", "Belasting", "Voeding"]
      },
      vibration: {
        title: "Mogelijke controlegebieden: trilling of lawaai",
        checks: ["Uitlijning", "Lagers", "Koppelingen", "Fundatie"]
      },
      sensor: {
        title: "Mogelijke controlegebieden: sensorfout",
        checks: ["Sensoren", "Bekabeling", "Besturing", "Voeding"]
      },
      drive: {
        title: "Mogelijke controlegebieden: aandrijving valt uit",
        checks: ["Aandrijving", "Beveiligingen", "Besturing", "Mechanische weerstand"]
      }
    };

    options.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var key = btn.getAttribute("data-symptom");
        var data = mappings[key];
        if (!data) return;

        options.forEach(function (b) {
          b.classList.toggle("is-selected", b === btn);
        });

        titleNode.textContent = data.title;
        listNode.innerHTML = "";
        data.checks.forEach(function (item) {
          var li = doc.createElement("li");
          li.textContent = item;
          listNode.appendChild(li);
        });
      });
    });
  }

  function init() {
    initTheme();
    initThemeToggle();
    setYear();
    initHeaderCompact();
    initMenu();
    initUrgencySelector();
    initIncidentForm();
    initDashboardFilter();
    initAnalyzer();
  }

  if (doc.readyState === "loading") {
    doc.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

// Cookie consent (industrieel-elektriciteit demo only, migrated from shared assets/js/cookie-consent.js).
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
    const footerTarget = document.querySelector(".industrial-footer__inner > div:last-child");
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

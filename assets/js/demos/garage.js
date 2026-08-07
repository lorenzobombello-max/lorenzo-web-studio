// TorquePoint Garage demo only: fully isolated interactive modules.
// Single IIFE, no globals, no dependency on main.js, no effect on other pages.
// Every module is defensive: it checks its own elements exist before wiring up,
// and a failure in one module cannot break the others.
(function () {
  "use strict";

  var root = document.documentElement;
  var body = document.body;
  var functionsBaseMeta = document.querySelector('meta[name="lws-functions-base-url"]');

  var prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function canUseFunctionalStorage() {
    if (!window.LwsConsent || typeof window.LwsConsent.isAllowed !== "function") {
      return true;
    }
    return window.LwsConsent.isAllowed("functional");
  }

  function initTheme() {
    if (canUseFunctionalStorage()) {
      try {
        var saved = localStorage.getItem("site-theme");
        if (saved === "dark" || saved === "light") {
          root.setAttribute("data-theme", saved);
          return;
        }
      } catch (_error) {
        // Ignore storage read errors.
      }
    }

    var prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    root.setAttribute("data-theme", prefersDark ? "dark" : "light");
  }

  function toggleTheme() {
    var current = root.getAttribute("data-theme") || "light";
    var next = current === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);

    if (!canUseFunctionalStorage()) return;

    try {
      localStorage.setItem("site-theme", next);
    } catch (_error) {
      // Ignore storage write errors.
    }
  }

  function hideLoader() {
    var loader = document.getElementById("pageLoader");
    if (loader) loader.classList.add("is-hidden");
  }

  function toggleMobileNav() {
    var siteNav = document.getElementById("siteNav");
    var navToggle = document.getElementById("navToggle");
    if (!siteNav || !navToggle) return;
    var isOpen = siteNav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
    body.classList.toggle("no-scroll", isOpen);
  }

  function closeMobileNav() {
    var siteNav = document.getElementById("siteNav");
    var navToggle = document.getElementById("navToggle");
    if (!siteNav || !navToggle) return;
    siteNav.classList.remove("is-open");
    navToggle.setAttribute("aria-expanded", "false");
    body.classList.remove("no-scroll");
  }

  function handleViewportChange() {
    if (window.innerWidth > 1100) closeMobileNav();
  }

  function initRevealObserver() {
    var nodes = document.querySelectorAll(".reveal");
    if (!nodes.length) return;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      nodes.forEach(function (node) { node.classList.add("in-view"); });
      return;
    }

    body.classList.add("motion-ready");

    var observer = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in-view");
          obs.unobserve(entry.target);
        }
      });
    }, { threshold: 0.18 });

    nodes.forEach(function (node) { observer.observe(node); });
  }

  function updateActiveNavLink() {
    var sections = Array.prototype.slice.call(document.querySelectorAll("main section[id]"));
    var links = document.querySelectorAll('.site-nav a[href^="#"]');
    if (!sections.length || !links.length) return;

    var scrollPos = window.scrollY + 120;
    sections.forEach(function (section) {
      var top = section.offsetTop;
      var bottom = top + section.offsetHeight;
      var id = section.getAttribute("id");
      if (scrollPos >= top && scrollPos < bottom) {
        links.forEach(function (link) {
          link.classList.toggle("is-active", link.getAttribute("href") === "#" + id);
        });
      }
    });
  }

  function initBackToTop() {
    var backToTop = document.getElementById("backToTop");
    if (!backToTop) return;

    function onScroll() {
      backToTop.classList.toggle("is-visible", window.scrollY > 500);
      updateActiveNavLink();
    }

    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    backToTop.addEventListener("click", function () {
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
  }

  function initYear() {
    var yearNode = document.getElementById("year");
    if (yearNode) yearNode.textContent = String(new Date().getFullYear());
  }

  function setFormMessage(text, type) {
    var formMessage = document.getElementById("formMessage");
    if (!formMessage) return;
    formMessage.classList.remove("is-error", "is-success");
    if (type === "error") formMessage.classList.add("is-error");
    if (type === "success") formMessage.classList.add("is-success");
    formMessage.textContent = text;
  }

  function getFunctionsBaseUrl() {
    var value = functionsBaseMeta ? functionsBaseMeta.getAttribute("content") || "" : "";
    return value.trim().replace(/\/$/, "");
  }

  function getSubmitEndpoint() {
    var baseUrl = getFunctionsBaseUrl();
    return baseUrl ? baseUrl + "/submit-quote-request" : "";
  }

  function extractFormPayload(form) {
    var formData = new FormData(form);

    function getText(name) {
      var value = formData.get(name);
      return typeof value === "string" ? value.trim() : "";
    }

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
      website: getText("website")
    };
  }

  function validateContactForm(form) {
    var requiredFields = form.querySelectorAll("[required]");
    for (var i = 0; i < requiredFields.length; i += 1) {
      var field = requiredFields[i];
      if (field instanceof HTMLInputElement && field.type === "checkbox") {
        if (!field.checked) {
          field.focus();
          setFormMessage("Gelieve de privacytoestemming te bevestigen.", "error");
          return false;
        }
        continue;
      }

      if ((field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement || field instanceof HTMLSelectElement) && !field.value.trim()) {
        field.focus();
        setFormMessage("Gelieve alle verplichte velden in te vullen.", "error");
        return false;
      }

      if (field instanceof HTMLInputElement && field.type === "email") {
        var ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(field.value);
        if (!ok) {
          field.focus();
          setFormMessage("Gelieve een geldig e-mailadres in te vullen.", "error");
          return false;
        }
      }
    }
    return true;
  }

  function initLeadForm() {
    var contactForm = document.getElementById("contactForm");
    var submitButton = document.getElementById("submitButton");
    if (!contactForm) return;

    contactForm.addEventListener("submit", function (event) {
      event.preventDefault();
      setFormMessage("", null);

      if (!validateContactForm(contactForm)) return;

      var endpoint = getSubmitEndpoint();
      if (!endpoint) {
        setFormMessage("De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op.", "error");
        return;
      }

      if (submitButton) {
        submitButton.disabled = true;
        submitButton.setAttribute("aria-busy", "true");
        submitButton.textContent = "Bezig...";
      }

      fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(extractFormPayload(contactForm))
      })
        .then(function (response) {
          if (!response.ok) throw new Error("Request failed");
          contactForm.reset();
          setFormMessage("Je aanvraag is veilig ontvangen en wordt persoonlijk nagekeken.", "success");
        })
        .catch(function () {
          setFormMessage("De aanvraag kon momenteel niet worden verzonden. Probeer later opnieuw of neem rechtstreeks contact op.", "error");
        })
        .finally(function () {
          if (submitButton) {
            submitButton.disabled = false;
            submitButton.removeAttribute("aria-busy");
            submitButton.textContent = "Verstuur aanvraag";
          }
        });
    });

    contactForm.addEventListener("input", function () {
      setFormMessage("", null);
    });

    contactForm.addEventListener("change", function () {
      setFormMessage("", null);
    });
  }

  function safeInit(name, fn) {
    try {
      fn();
    } catch (err) {
      if (window.console && console.warn) {
        console.warn("[garage.js] " + name + " kon niet initialiseren:", err);
      }
    }
  }

  // ---------- Header shrink on scroll ----------
  function initHeaderShrink() {
    var header = document.getElementById("siteHeader");
    if (!header) return;

    function update() {
      header.classList.toggle("torque-is-compact", window.scrollY > 40);
    }

    update();
    window.addEventListener("scroll", update, { passive: true });
  }

  // ---------- Vehicle inventory filtering ----------
  function initInventoryFilters() {
    var track = document.getElementById("showroomTrack");
    var searchForm = document.getElementById("vehicleSearch");
    var searchStatus = document.getElementById("searchStatus");
    var categoryTiles = document.querySelectorAll("[data-filter-category]");
    if (!track) return;

    var cards = Array.prototype.slice.call(track.querySelectorAll(".torque-vehicle-card"));
    if (!cards.length) return;

    function parsePriceRange(value) {
      if (!value) return null;
      var parts = value.split("-");
      var min = parseInt(parts[0], 10);
      var max = parseInt(parts[1], 10);
      if (!Number.isFinite(min) || !Number.isFinite(max)) return null;
      return { min: min, max: max };
    }

    function applyFilters(criteria) {
      var visibleCount = 0;
      cards.forEach(function (card) {
        var matches = true;

        if (criteria.brand && card.getAttribute("data-brand") !== criteria.brand) matches = false;
        if (matches && criteria.fuel && card.getAttribute("data-fuel") !== criteria.fuel) matches = false;
        if (matches && criteria.transmission && card.getAttribute("data-transmission") !== criteria.transmission) matches = false;
        if (matches && criteria.condition && card.getAttribute("data-condition") !== criteria.condition) matches = false;
        if (matches && criteria.category && card.getAttribute("data-category") !== criteria.category) matches = false;

        if (matches && criteria.priceRange) {
          var price = parseInt(card.getAttribute("data-price"), 10);
          if (!Number.isFinite(price) || price < criteria.priceRange.min || price > criteria.priceRange.max) {
            matches = false;
          }
        }

        card.hidden = !matches;
        if (matches) visibleCount += 1;
      });

      if (searchStatus) {
        searchStatus.textContent = visibleCount === cards.length
          ? cards.length + " wagens beschikbaar."
          : visibleCount + " van " + cards.length + " wagens komen overeen met je zoekopdracht.";
      }

      return visibleCount;
    }

    if (searchForm) {
      searchForm.addEventListener("submit", function (event) {
        event.preventDefault();
        var data = new FormData(searchForm);
        applyFilters({
          brand: String(data.get("brand") || ""),
          fuel: String(data.get("fuel") || ""),
          transmission: String(data.get("transmission") || ""),
          condition: String(data.get("condition") || ""),
          priceRange: parsePriceRange(String(data.get("price") || ""))
        });
        var showroom = document.getElementById("voorraad");
        if (showroom) showroom.scrollIntoView({ behavior: prefersReducedMotion ? "auto" : "smooth" });
      });
    }

    categoryTiles.forEach(function (tile) {
      tile.addEventListener("click", function () {
        var category = tile.getAttribute("data-filter-category");
        if (searchForm) searchForm.reset();
        applyFilters({ category: category });
        var showroom = document.getElementById("voorraad");
        if (showroom) showroom.scrollIntoView({ behavior: prefersReducedMotion ? "auto" : "smooth" });
      });
    });
  }

  // ---------- Showroom carousel controls ----------
  function initShowroomCarousel() {
    var track = document.getElementById("showroomTrack");
    var prevBtn = document.getElementById("showroomPrev");
    var nextBtn = document.getElementById("showroomNext");
    if (!track || (!prevBtn && !nextBtn)) return;

    function step(direction) {
      var card = track.querySelector(".torque-vehicle-card");
      var amount = card ? card.getBoundingClientRect().width + 18 : 320;
      track.scrollBy({ left: direction * amount, behavior: prefersReducedMotion ? "auto" : "smooth" });
    }

    if (prevBtn) prevBtn.addEventListener("click", function () { step(-1); });
    if (nextBtn) nextBtn.addEventListener("click", function () { step(1); });
  }

  // ---------- Gauge rings + counters ----------
  function initGauges() {
    var gauges = document.querySelectorAll(".torque-gauge-ring[data-gauge-percent]");
    var counters = document.querySelectorAll(".torque-gauge-value[data-counter-target]");
    if (!gauges.length && !counters.length) return;

    var circumference = 251.2;

    function animateGauge(ring) {
      var percent = parseFloat(ring.getAttribute("data-gauge-percent"));
      if (!Number.isFinite(percent)) return;
      var offset = circumference - (circumference * percent) / 100;
      if (prefersReducedMotion) {
        ring.style.transition = "none";
      }
      requestAnimationFrame(function () {
        ring.style.strokeDashoffset = String(offset);
      });
    }

    function animateCounter(node) {
      var target = parseInt(node.getAttribute("data-counter-target"), 10);
      var suffix = node.getAttribute("data-counter-suffix") || "";
      if (!Number.isFinite(target)) return;

      if (prefersReducedMotion) {
        node.textContent = target + suffix;
        return;
      }

      var duration = 1100;
      var startTime = null;

      function step(timestamp) {
        if (startTime === null) startTime = timestamp;
        var progress = Math.min((timestamp - startTime) / duration, 1);
        var eased = 1 - Math.pow(1 - progress, 3);
        node.textContent = Math.round(target * eased) + suffix;
        if (progress < 1) {
          window.requestAnimationFrame(step);
        } else {
          node.textContent = target + suffix;
        }
      }

      window.requestAnimationFrame(step);
    }

    if (!("IntersectionObserver" in window)) {
      gauges.forEach(animateGauge);
      counters.forEach(function (node) {
        var target = parseInt(node.getAttribute("data-counter-target"), 10);
        node.textContent = Number.isFinite(target) ? target + (node.getAttribute("data-counter-suffix") || "") : node.textContent;
      });
      return;
    }

    var trustSection = document.getElementById("vertrouwen");
    if (!trustSection) return;

    var observer = new IntersectionObserver(
      function (entries, obs) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            gauges.forEach(animateGauge);
            counters.forEach(animateCounter);
            obs.disconnect();
          }
        });
      },
      { threshold: 0.3 }
    );
    observer.observe(trustSection);
  }

  // ---------- Sticky action bar ----------
  function initStickyActions() {
    var bar = document.getElementById("stickyActions");
    var hero = document.getElementById("home");
    if (!bar || !hero) return;

    if (!("IntersectionObserver" in window)) {
      bar.classList.add("torque-is-visible");
      return;
    }

    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          bar.classList.toggle("torque-is-visible", !entry.isIntersecting);
        });
      },
      { threshold: 0 }
    );
    observer.observe(hero);
  }

  // ---------- Demonstrative appointment form (no submission) ----------
  function initAppointmentForm() {
    var form = document.getElementById("appointmentForm");
    var status = document.getElementById("appointmentStatus");
    if (!form) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      var plate = form.querySelector("#apptPlate");
      var service = form.querySelector("#apptService");
      var date = form.querySelector("#apptDate");
      var missing = [plate, service, date].filter(function (field) {
        return field && !field.value.trim();
      });

      if (missing.length) {
        if (status) {
          status.textContent = "Vul alle velden in om een afspraak aan te vragen.";
          status.setAttribute("data-state", "error");
        }
        if (missing[0]) missing[0].focus();
        return;
      }

      if (status) {
        status.textContent = "Demo-aanvraag klaar (niet verzonden): " + service.value + " voor " + plate.value + " op " + date.value + ".";
        status.setAttribute("data-state", "success");
      }
    });
  }

  safeInit("headerShrink", initHeaderShrink);
  safeInit("inventoryFilters", initInventoryFilters);
  safeInit("showroomCarousel", initShowroomCarousel);
  safeInit("gauges", initGauges);
  safeInit("stickyActions", initStickyActions);
  safeInit("appointmentForm", initAppointmentForm);

  document.addEventListener("DOMContentLoaded", function () {
    var themeToggle = document.getElementById("themeToggle");
    var navToggle = document.getElementById("navToggle");
    var navLinks = document.querySelectorAll(".site-nav a");

    initTheme();
    initYear();
    safeInit("leadForm", initLeadForm);

    if (themeToggle) themeToggle.addEventListener("click", toggleTheme);
    if (navToggle) navToggle.addEventListener("click", toggleMobileNav);

    navLinks.forEach(function (link) {
      link.addEventListener("click", function () {
        var siteNav = document.getElementById("siteNav");
        if (siteNav && siteNav.classList.contains("is-open")) closeMobileNav();
      });
    });

    window.addEventListener("resize", handleViewportChange);
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") closeMobileNav();
    });

    body.addEventListener("click", function (event) {
      var siteNav = document.getElementById("siteNav");
      var navToggleButton = document.getElementById("navToggle");
      var target = event.target;
      if (!siteNav || !navToggleButton || !(target instanceof Node)) return;
      if (!siteNav.contains(target) && !navToggleButton.contains(target)) closeMobileNav();
    });
  });

  window.addEventListener("load", function () {
    hideLoader();
    initRevealObserver();
    updateActiveNavLink();
    initBackToTop();
  });

  document.addEventListener("lws:consent-changed", function (event) {
    var detail = event.detail;
    if (!detail || !detail.categories) return;

    if (!detail.categories.functional) {
      initTheme();
      return;
    }

    var current = root.getAttribute("data-theme");
    if (current === "dark" || current === "light") {
      try {
        localStorage.setItem("site-theme", current);
      } catch (_error) {
        // Ignore storage write issues.
      }
    }
  });
})();

// Cookie consent (garage demo only, migrated from shared assets/js/cookie-consent.js).
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

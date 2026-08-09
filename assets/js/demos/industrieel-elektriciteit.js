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
      saved = window.LwsConsent?.getFunctionalStorage("site-theme");
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
        window.LwsConsent?.setFunctionalStorage("site-theme", next);
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

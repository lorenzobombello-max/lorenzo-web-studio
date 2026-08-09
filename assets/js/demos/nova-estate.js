(function () {
  const navToggle = document.getElementById("neNavToggle");
  const navLinks = document.getElementById("neNavLinks");
  const header = document.getElementById("neHeader");
  const yearNodes = document.querySelectorAll("[data-current-year]");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function initContrastStylesheet() {
    if (document.querySelector('link[data-nova-contrast="true"]')) return;
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = "../../../assets/css/demos/nova-estate-contrast.css";
    link.setAttribute("data-nova-contrast", "true");
    document.head.appendChild(link);
  }

  function initTheme() {
    const root = document.documentElement;
    let saved = null;
    try { saved = window.LwsConsent?.getFunctionalStorage("site-theme"); } catch (error) { saved = null; }
    if (saved === "light" || saved === "dark") {
      root.setAttribute("data-theme", saved);
      return;
    }
    const prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    root.setAttribute("data-theme", prefersDark ? "dark" : "light");
  }

  function initThemeToggle() {
    const toggle = document.getElementById("themeToggle");
    if (!toggle) return;
    toggle.addEventListener("click", function () {
      const root = document.documentElement;
      const current = root.getAttribute("data-theme") || "light";
      const next = current === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { window.LwsConsent?.setFunctionalStorage("site-theme", next); } catch (error) {}
    });
  }

  function initYear() {
    const year = String(new Date().getFullYear());
    yearNodes.forEach((node) => {
      node.textContent = year;
    });
  }

  function initNav() {
    if (!navToggle || !navLinks) return;

    navToggle.addEventListener("click", function () {
      const open = navLinks.classList.toggle("is-open");
      navToggle.setAttribute("aria-expanded", String(open));
    });

    navLinks.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", function () {
        navLinks.classList.remove("is-open");
        navToggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  function initHeaderState() {
    if (!header) return;

    function update() {
      const scrolled = window.scrollY > 12;
      header.classList.toggle("is-scrolled", scrolled);
    }

    update();
    window.addEventListener("scroll", update, { passive: true });
  }

  function initReveal() {
    const nodes = document.querySelectorAll(".ne-reveal");
    if (!nodes.length) return;

    if (reduceMotion || !("IntersectionObserver" in window)) {
      nodes.forEach((node) => node.classList.add("in-view"));
      return;
    }

    const observer = new IntersectionObserver(
      function (entries, obs) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("in-view");
          obs.unobserve(entry.target);
        });
      },
      { threshold: 0.2 }
    );

    nodes.forEach((node) => observer.observe(node));
  }

  function createFallbackDataUri(label) {
    const safeLabel = (label || "Nova Estate").replace(/[<>&]/g, "");
    const svg =
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1600 1000' role='img' aria-label='" +
      safeLabel +
      "'>" +
      "<defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0%' stop-color='#d8cebf'/><stop offset='55%' stop-color='#c7baa6'/><stop offset='100%' stop-color='#b2a087'/></linearGradient></defs>" +
      "<rect width='1600' height='1000' fill='url(#g)'/>" +
      "<rect x='90' y='90' width='1420' height='820' fill='none' stroke='#f5eee3' stroke-width='2' opacity='0.45'/>" +
      "<text x='140' y='820' font-family='Georgia,serif' font-size='82' fill='#f7f2ea' opacity='0.92'>Nova Estate</text>" +
      "<text x='140' y='880' font-family='Arial,sans-serif' font-size='28' fill='#f7f2ea' opacity='0.88'>" +
      safeLabel +
      "</text>" +
      "</svg>";
    return "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(svg);
  }

  function parseCandidates(img) {
    const raw = img.getAttribute("data-image-candidates") || "";
    return raw
      .split("|")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  function tryCandidates(img, candidates, index) {
    if (index >= candidates.length) {
      img.classList.add("ne-image-fallback");
      const label = img.getAttribute("data-fallback-label") || "Nova Estate";
      img.src = createFallbackDataUri(label);
      return;
    }

    img.src = candidates[index];
    img.addEventListener(
      "error",
      function onError() {
        img.removeEventListener("error", onError);
        tryCandidates(img, candidates, index + 1);
      },
      { once: true }
    );
  }

  function initImageFallbacks() {
    const imgs = document.querySelectorAll("img[data-fallback-label]");
    imgs.forEach((img) => {
      const candidates = parseCandidates(img);
      if (candidates.length) {
        tryCandidates(img, candidates, 0);
        return;
      }

      img.addEventListener(
        "error",
        function onError() {
          img.removeEventListener("error", onError);
          img.classList.add("ne-image-fallback");
          const label = img.getAttribute("data-fallback-label") || "Nova Estate";
          img.src = createFallbackDataUri(label);
        },
        { once: true }
      );
    });
  }

  function initRegionSelector() {
    const buttons = Array.from(document.querySelectorAll(".ne-regions button[data-region]"));
    const output = document.getElementById("neRegionOutput");
    if (!buttons.length || !output) return;

    buttons.forEach((button) => {
      button.addEventListener("click", function () {
        const region = button.getAttribute("data-region") || "Onbekend";
        buttons.forEach((item) => item.classList.toggle("is-active", item === button));
        output.textContent = "Actieve regio: " + region;
      });
    });
  }

  function initDemoSearch() {
    const form = document.getElementById("neQuickSearch");
    const output = document.getElementById("neSearchOutput");
    if (!form || !output) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      const location = document.getElementById("neLocation");
      const type = document.getElementById("neType");
      const budget = document.getElementById("neBudget");
      const beds = document.getElementById("neBeds");

      const parts = [
        location ? location.value : "",
        type ? type.value : "",
        budget ? budget.value : "",
        beds ? beds.value : "",
      ].filter(Boolean);

      if (!parts.length) {
        output.textContent = "Selecteer minstens een filter om het demo-aanbod te verfijnen.";
        return;
      }

      output.textContent = "Demofilter actief: " + parts.join(" | ") + ". Open het volledige aanbod voor detailresultaten.";
    });
  }

  function initFavorites() {
    const favorites = document.querySelectorAll("[data-favorite-toggle]");
    favorites.forEach((button) => {
      button.addEventListener("click", function () {
        const active = button.getAttribute("aria-pressed") === "true";
        const next = !active;
        button.setAttribute("aria-pressed", String(next));
        const icon = button.querySelector("span");
        if (icon) {
          icon.textContent = next ? "♥" : "♡";
        }
      });
    });
  }

  function initCounters() {
    const counters = Array.from(document.querySelectorAll("[data-counter]"));
    if (!counters.length) return;

    const animateCounter = function (node) {
      const max = Number(node.getAttribute("data-counter"));
      if (!Number.isFinite(max) || max <= 0) return;
      if (reduceMotion) {
        node.textContent = String(max);
        return;
      }

      const duration = 900;
      const start = performance.now();

      const tick = function (now) {
        const elapsed = now - start;
        const progress = Math.min(1, elapsed / duration);
        const eased = 1 - Math.pow(1 - progress, 3);
        const value = Math.round(max * eased);
        node.textContent = String(value);
        if (progress < 1) {
          window.requestAnimationFrame(tick);
        }
      };

      window.requestAnimationFrame(tick);
    };

    if (reduceMotion || !("IntersectionObserver" in window)) {
      counters.forEach(animateCounter);
      return;
    }

    const observer = new IntersectionObserver(
      function (entries, obs) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          animateCounter(entry.target);
          obs.unobserve(entry.target);
        });
      },
      { threshold: 0.45 }
    );

    counters.forEach((node) => observer.observe(node));
  }

  function initSoftParallax() {
    const nodes = Array.from(document.querySelectorAll('[data-parallax="soft"]'));
    if (!nodes.length || reduceMotion) return;

    const update = function () {
      const viewport = window.innerHeight || 1;
      nodes.forEach((node) => {
        const rect = node.getBoundingClientRect();
        const distance = (rect.top + rect.height * 0.5 - viewport * 0.5) / viewport;
        const translateY = Math.max(-8, Math.min(8, distance * -10));
        node.style.setProperty("--ne-parallax-y", translateY.toFixed(2) + "px");
      });
    };

    update();
    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
  }

  function initInterestForm() {
    const form = document.querySelector(".ne-interest-form");
    if (!form) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      const submitButton = form.querySelector('button[type="submit"]');
      if (submitButton) {
        submitButton.textContent = "Aanvraag ontvangen (demo)";
      }
    });
  }

  initContrastStylesheet();
  initTheme();
  initThemeToggle();
  initYear();
  initNav();
  initHeaderState();
  initReveal();
  initImageFallbacks();
  initDemoSearch();
  initRegionSelector();
  initFavorites();
  initCounters();
  initSoftParallax();
  initInterestForm();
})();
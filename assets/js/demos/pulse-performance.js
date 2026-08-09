(function () {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const header = document.getElementById("ppsHeader");
  const navToggle = document.getElementById("ppsNavToggle");
  const navLinks = document.getElementById("ppsNavLinks");
  const yearNodes = document.querySelectorAll("[data-current-year]");


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
      const current = root.getAttribute("data-theme") || "dark";
      const next = current === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { window.LwsConsent?.setFunctionalStorage("site-theme", next); } catch (error) {}
    });
  }

  function initYear() {
    const current = String(new Date().getFullYear());
    yearNodes.forEach((node) => {
      node.textContent = current;
    });
  }

  function initHeaderState() {
    if (!header) return;

    function update() {
      header.classList.toggle("is-scrolled", window.scrollY > 8);
    }

    update();
    window.addEventListener("scroll", update, { passive: true });
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

  function initReveal() {
    const nodes = document.querySelectorAll(".pps-reveal");
    if (!nodes.length) return;

    if (reduceMotion || !("IntersectionObserver" in window)) {
      nodes.forEach((node) => node.classList.add("in-view"));
      return;
    }

    const observer = new IntersectionObserver(
      function (entries, obs) {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("in-view");
          obs.unobserve(entry.target);
        });
      },
      { threshold: 0.18 }
    );

    nodes.forEach((node) => observer.observe(node));
  }

  function animateCounter(node) {
    const target = Number(node.getAttribute("data-counter"));
    if (!Number.isFinite(target) || target <= 0) return;

    if (reduceMotion) {
      node.textContent = String(target);
      return;
    }

    const startTime = performance.now();
    const duration = 950;

    function tick(now) {
      const progress = Math.min(1, (now - startTime) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      node.textContent = String(Math.round(target * eased));
      if (progress < 1) {
        window.requestAnimationFrame(tick);
      }
    }

    window.requestAnimationFrame(tick);
  }

  function initCounters() {
    const counters = Array.from(document.querySelectorAll("[data-counter]"));
    if (!counters.length) return;

    if (reduceMotion || !("IntersectionObserver" in window)) {
      counters.forEach(animateCounter);
      return;
    }

    const observer = new IntersectionObserver(
      function (entries, obs) {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          animateCounter(entry.target);
          obs.unobserve(entry.target);
        });
      },
      { threshold: 0.4 }
    );

    counters.forEach((counter) => observer.observe(counter));
  }

  function initProgressBars() {
    const bars = Array.from(document.querySelectorAll(".pps-progress"));
    if (!bars.length) return;

    const fill = (bar) => {
      const value = Number(bar.getAttribute("data-progress"));
      const clamped = Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : 0;
      const span = bar.querySelector("span");
      if (!span) return;
      span.style.width = clamped + "%";
      bar.setAttribute("aria-valuenow", String(clamped));
    };

    if (reduceMotion || !("IntersectionObserver" in window)) {
      bars.forEach(fill);
      return;
    }

    const observer = new IntersectionObserver(
      function (entries, obs) {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          fill(entry.target);
          obs.unobserve(entry.target);
        });
      },
      { threshold: 0.5 }
    );

    bars.forEach((bar) => observer.observe(bar));
  }

  function initFaq() {
    const faq = document.querySelector("[data-faq]");
    if (!faq) return;

    faq.querySelectorAll("details").forEach((item) => {
      item.addEventListener("toggle", function () {
        if (!item.open) return;
        faq.querySelectorAll("details").forEach((other) => {
          if (other !== item) {
            other.open = false;
          }
        });
      });
    });
  }

  function initContactForm() {
    const form = document.getElementById("ppsContactForm");
    const output = document.getElementById("ppsFormOutput");
    if (!form || !output) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();

      const name = document.getElementById("ppsName");
      const email = document.getElementById("ppsEmail");
      const goal = document.getElementById("ppsGoal");

      if (!name || !email || !goal || !name.value.trim() || !email.value.trim() || !goal.value.trim()) {
        output.textContent = "Vul naam, e-mail en doel in om je intakevoorstel te ontvangen.";
        output.style.color = "#ffe561";
        return;
      }

      output.textContent = "Dank je. Dit is een demoformulier: je intakeaanvraag is lokaal gevalideerd.";
      output.style.color = "#7fffc6";
      form.reset();
    });
  }

  initTheme();
  initThemeToggle();
  initYear();
  initHeaderState();
  initNav();
  initReveal();
  initCounters();
  initProgressBars();
  initFaq();
  initContactForm();
})();

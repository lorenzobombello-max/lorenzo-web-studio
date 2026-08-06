(function () {
  const body = document.body;
  if (!body || !body.classList.contains("aurelis")) return;

  const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function initYear() {
    const yearNode = document.getElementById("aurelisYear");
    if (yearNode) yearNode.textContent = String(new Date().getFullYear());
  }

  function initMobileNav() {
    const toggle = document.getElementById("aurelisNavToggle");
    const links = document.getElementById("aurelisNavLinks");
    if (!toggle || !links) return;

    toggle.addEventListener("click", function () {
      const open = links.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", String(open));
    });

    links.querySelectorAll("a").forEach(function (anchor) {
      anchor.addEventListener("click", function () {
        links.classList.remove("is-open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  function initReveal() {
    const nodes = Array.from(document.querySelectorAll("[data-reveal]"));
    if (!nodes.length) return;

    if (prefersReducedMotion || !("IntersectionObserver" in window)) {
      nodes.forEach(function (node) {
        node.classList.add("is-visible");
      });
      return;
    }

    const observer = new IntersectionObserver(
      function (entries, obs) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          obs.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -10% 0px", threshold: 0.22 }
    );

    nodes.forEach(function (node) {
      observer.observe(node);
    });
  }

  function initImageFallbacks() {
    const media = Array.from(document.querySelectorAll(".aurelis-media[data-filename]"));
    media.forEach(function (figure) {
      const img = figure.querySelector("img");
      const placeholder = figure.querySelector(".aurelis-placeholder");
      if (!img || !placeholder) return;

      function showFallback() {
        img.hidden = true;
        placeholder.hidden = false;
      }

      if (img.complete && (!img.naturalWidth || img.naturalWidth === 0)) {
        showFallback();
      }

      img.addEventListener("error", showFallback, { once: true });
      img.setAttribute("draggable", "false");
    });
  }

  function initFocusTabs() {
    const tabs = Array.from(document.querySelectorAll(".aurelis-tab"));
    if (!tabs.length) return;

    const panelMap = {
      concept: document.getElementById("panel-concept"),
      materialen: document.getElementById("panel-materialen"),
      programma: document.getElementById("panel-programma"),
    };

    function activate(tab) {
      const key = tab.getAttribute("data-panel");
      tabs.forEach(function (item) {
        const active = item === tab;
        item.classList.toggle("is-active", active);
        item.setAttribute("aria-selected", String(active));
      });

      Object.keys(panelMap).forEach(function (panelKey) {
        const panel = panelMap[panelKey];
        if (!panel) return;
        const active = panelKey === key;
        panel.classList.toggle("is-active", active);
        panel.hidden = !active;
      });
    }

    tabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        activate(tab);
      });
      tab.addEventListener("keydown", function (event) {
        if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
        event.preventDefault();
        const index = tabs.indexOf(tab);
        const next = event.key === "ArrowRight" ? (index + 1) % tabs.length : (index - 1 + tabs.length) % tabs.length;
        activate(tabs[next]);
        tabs[next].focus();
      });
    });
  }

  function initMaterialSwatches() {
    const section = document.getElementById("materials");
    const swatches = Array.from(document.querySelectorAll(".aurelis-swatch"));
    if (!section || !swatches.length) return;

    function activate(button) {
      const tone = button.getAttribute("data-tone") || "concrete";
      section.setAttribute("data-tone", tone);

      swatches.forEach(function (swatch) {
        const active = swatch === button;
        swatch.classList.toggle("is-active", active);
        swatch.setAttribute("aria-checked", String(active));
      });
    }

    swatches.forEach(function (swatch) {
      swatch.addEventListener("click", function () {
        activate(swatch);
      });
      swatch.addEventListener("keydown", function (event) {
        if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
        event.preventDefault();
        const index = swatches.indexOf(swatch);
        const next = event.key === "ArrowRight" ? (index + 1) % swatches.length : (index - 1 + swatches.length) % swatches.length;
        activate(swatches[next]);
        swatches[next].focus();
      });
    });
  }

  function initDemoForm() {
    const form = document.getElementById("aurelisForm");
    const message = document.getElementById("aurelisFormMessage");
    if (!form || !message) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();

      const formData = new FormData(form);
      const name = String(formData.get("name") || "").trim();
      const email = String(formData.get("email") || "").trim();
      const projectType = String(formData.get("projectType") || "").trim();
      const context = String(formData.get("context") || "").trim();
      const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

      if (!name || !email || !projectType || !context) {
        message.textContent = "Vul alle velden in om de demo-flow correct te testen.";
        return;
      }

      if (!emailPattern.test(email)) {
        message.textContent = "Gebruik een geldig e-mailadres in dit demoformulier.";
        return;
      }

      message.textContent = "Demo bevestigd: er werd niets verzonden. Deze pagina toont enkel de UX-flow.";
      form.reset();
    });
  }

  function initCursorTone() {
    if (prefersReducedMotion || window.innerWidth < 1024) return;
    body.classList.add("has-cursor");

    let ticking = false;
    let x = 0;
    let y = 0;

    function paint() {
      ticking = false;
      const xp = Math.max(8, Math.min(92, (x / window.innerWidth) * 100));
      const yp = Math.max(8, Math.min(92, (y / window.innerHeight) * 100));
      document.documentElement.style.setProperty("--cursor-x", xp + "%");
      document.documentElement.style.setProperty("--cursor-y", yp + "%");
    }

    window.addEventListener("pointermove", function (event) {
      x = event.clientX;
      y = event.clientY;
      if (!ticking) {
        ticking = true;
        window.requestAnimationFrame(paint);
      }
    }, { passive: true });
  }

  initYear();
  initMobileNav();
  initReveal();
  initImageFallbacks();
  initFocusTabs();
  initMaterialSwatches();
  initDemoForm();
  initCursorTone();
})();

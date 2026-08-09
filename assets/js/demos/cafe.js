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
        const saved = window.LwsConsent?.getFunctionalStorage("site-theme");
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
      window.LwsConsent?.setFunctionalStorage("site-theme", next);
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
        window.LwsConsent?.setFunctionalStorage("site-theme", current);
      } catch (_error) {
        // Ignore storage write issues.
      }
    }
  });
})();

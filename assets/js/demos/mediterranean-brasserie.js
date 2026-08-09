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
        const saved = window.LwsConsent?.getFunctionalStorage("site-theme");
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
      window.LwsConsent?.setFunctionalStorage("site-theme", next);
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
        window.LwsConsent?.setFunctionalStorage("site-theme", current);
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

(function () {
  const root = document.documentElement;
  const header = document.getElementById("mbHeader");
  const navToggle = document.getElementById("mbMenuToggle");
  const nav = document.getElementById("mbNav");
  const tabs = Array.from(document.querySelectorAll('[role="tab"][data-tab]'));
  const panels = Array.from(document.querySelectorAll('[role="tabpanel"][data-panel]'));
  const reservationForm = document.getElementById("mbReservationForm");
  const reservationMessage = document.getElementById("mbReservationMessage");

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

  updateHeader();
  initNav();
  initTabs();
  initReservation();

  root.classList.remove("no-js");
})();

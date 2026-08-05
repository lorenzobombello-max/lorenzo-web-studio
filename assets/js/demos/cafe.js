(function () {
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
    initHeaderCondense();
    initDrinkTabs();
    initReservationForm();
  });
})();
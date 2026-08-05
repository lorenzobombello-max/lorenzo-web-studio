(function () {
  "use strict";

  /* ── Scroll reveal ──────────────────────────────────────────── */
  function initReveal() {
    const items = document.querySelectorAll(".luna-reveal");
    if (!items.length || !window.IntersectionObserver) {
      items.forEach((el) => el.classList.add("is-visible"));
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
    );
    items.forEach((el) => observer.observe(el));
  }

  /* ── Nav scroll effect ──────────────────────────────────────── */
  function initNav() {
    const nav = document.getElementById("lunaNav");
    if (!nav) return;
    function update() {
      nav.classList.toggle("is-scrolled", window.scrollY > 40);
    }
    window.addEventListener("scroll", update, { passive: true });
    update();
  }

  /* ── Mobile nav toggle ──────────────────────────────────────── */
  function initMobileNav() {
    const toggle = document.getElementById("lunaNavToggle");
    const links = document.getElementById("lunaNavLinks");
    if (!toggle || !links) return;

    function close() {
      toggle.classList.remove("is-open");
      links.classList.remove("is-open");
      toggle.setAttribute("aria-expanded", "false");
      document.body.style.overflow = "";
    }

    toggle.addEventListener("click", () => {
      const open = links.classList.toggle("is-open");
      toggle.classList.toggle("is-open", open);
      toggle.setAttribute("aria-expanded", String(open));
      document.body.style.overflow = open ? "hidden" : "";
    });

    links.querySelectorAll("a").forEach((a) => a.addEventListener("click", close));

    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") close();
    });
  }

  /* ── Smooth scroll for anchor links ────────────────────────── */
  function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
      anchor.addEventListener("click", (e) => {
        const target = document.querySelector(anchor.getAttribute("href"));
        if (!target) return;
        e.preventDefault();
        const navHeight = document.getElementById("lunaNav")?.offsetHeight || 70;
        const top = target.getBoundingClientRect().top + window.scrollY - navHeight;
        window.scrollTo({ top, behavior: "smooth" });
      });
    });
  }

  /* ── Demo booking form (frontend-only) ─────────────────────── */
  function initForm() {
    const form = document.getElementById("lunaForm");
    const feedback = document.getElementById("lunaFormFeedback");
    if (!form || !feedback) return;

    form.addEventListener("submit", (e) => {
      e.preventDefault();
      feedback.className = "luna-form-feedback";
      feedback.textContent = "";

      const name = form.querySelector("#lf-name")?.value.trim();
      const email = form.querySelector("#lf-email")?.value.trim();
      const service = form.querySelector("#lf-service")?.value;

      if (!name) {
        feedback.textContent = "Vul jouw naam in.";
        feedback.className = "luna-form-feedback is-error";
        form.querySelector("#lf-name")?.focus();
        return;
      }
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        feedback.textContent = "Vul een geldig e-mailadres in.";
        feedback.className = "luna-form-feedback is-error";
        form.querySelector("#lf-email")?.focus();
        return;
      }
      if (!service) {
        feedback.textContent = "Kies een behandeling.";
        feedback.className = "luna-form-feedback is-error";
        form.querySelector("#lf-service")?.focus();
        return;
      }

      const btn = form.querySelector('[type="submit"]');
      if (btn) { btn.disabled = true; btn.textContent = "Versturen…"; }

      /* Simulate async submit (demo only) */
      window.setTimeout(() => {
        form.reset();
        feedback.textContent = "Bedankt! Jouw afspraakverzoek is ontvangen. We nemen snel contact met je op.";
        feedback.className = "luna-form-feedback is-success";
        if (btn) { btn.disabled = false; btn.textContent = "Afspraak aanvragen"; }
      }, 900);
    });

    /* Clear feedback on input */
    form.addEventListener("input", () => {
      feedback.textContent = "";
      feedback.className = "luna-form-feedback";
    });
  }

  /* ── Active nav link on scroll ──────────────────────────────── */
  function initActiveNav() {
    const sections = document.querySelectorAll("section[id]");
    const navLinks = document.querySelectorAll(".luna-nav__links a[href^='#']");
    if (!sections.length || !navLinks.length || !window.IntersectionObserver) return;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          const id = entry.target.id;
          navLinks.forEach((link) => {
            link.classList.toggle("is-active", link.getAttribute("href") === `#${id}`);
          });
        });
      },
      { threshold: 0.4 }
    );
    sections.forEach((s) => observer.observe(s));
  }

  /* ── Init ───────────────────────────────────────────────────── */
  function init() {
    initReveal();
    initNav();
    initMobileNav();
    initSmoothScroll();
    initForm();
    initActiveNav();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

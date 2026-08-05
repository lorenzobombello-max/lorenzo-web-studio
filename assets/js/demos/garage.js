// TorquePoint Garage demo only: fully isolated interactive modules.
// Single IIFE, no globals, no dependency on main.js, no effect on other pages.
// Every module is defensive: it checks its own elements exist before wiring up,
// and a failure in one module cannot break the others.
(function () {
  "use strict";

  var prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

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
})();

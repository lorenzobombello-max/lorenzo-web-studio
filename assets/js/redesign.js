(function () {
  "use strict";

  document.documentElement.classList.replace("no-js", "js");

  const header = document.getElementById("previewHeader");
  const menuToggle = document.getElementById("menuToggle");
  const navigation = document.getElementById("previewNav");
  const year = document.getElementById("previewYear");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)");

  function closeMenu(restoreFocus) {
    if (!menuToggle || !navigation) return;
    const wasOpen = menuToggle.getAttribute("aria-expanded") === "true";
    menuToggle.setAttribute("aria-expanded", "false");
    menuToggle.querySelector(".sr-only").textContent = "Navigatiemenu openen";
    navigation.classList.remove("is-open");
    document.body.classList.remove("menu-open");
    if (restoreFocus && wasOpen) menuToggle.focus();
  }

  function toggleMenu() {
    if (!menuToggle || !navigation) return;
    const open = menuToggle.getAttribute("aria-expanded") !== "true";
    menuToggle.setAttribute("aria-expanded", String(open));
    menuToggle.querySelector(".sr-only").textContent = open ? "Navigatiemenu sluiten" : "Navigatiemenu openen";
    navigation.classList.toggle("is-open", open);
    document.body.classList.toggle("menu-open", open);
  }

  function updateHeader() {
    if (header) header.classList.toggle("is-scrolled", window.scrollY > 24);
  }

  function initReveals() {
    const elements = Array.from(document.querySelectorAll("[data-reveal]"));
    if (!elements.length) return;

    if (reducedMotion.matches || !("IntersectionObserver" in window)) {
      elements.forEach((element) => element.classList.add("is-visible"));
      return;
    }

    document.documentElement.classList.add("motion-enabled");

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.08, rootMargin: "0px 0px -4%" });

    const heroElements = Array.from(document.querySelectorAll(".hero__copy [data-reveal]"));
    const heroDelays = [140, 1050, 1230, 1420];

    elements.forEach((element, index) => {
      const heroIndex = heroElements.indexOf(element);
      const delay = heroIndex >= 0 ? heroDelays[heroIndex] : Math.min(index % 3, 2) * 90;
      element.style.transitionDelay = `${delay}ms`;
      observer.observe(element);
    });
  }

  function initPointerMotion() {
    if (reducedMotion.matches || !finePointer.matches) return;

    document.querySelectorAll(".service-card").forEach((card) => {
      card.addEventListener("pointermove", (event) => {
        const rect = card.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width - 0.5;
        const y = (event.clientY - rect.top) / rect.height - 0.5;
        card.style.setProperty("--tilt-x", `${y * -5}deg`);
        card.style.setProperty("--tilt-y", `${x * 6}deg`);
      });
      card.addEventListener("pointerleave", () => {
        card.style.setProperty("--tilt-x", "0deg");
        card.style.setProperty("--tilt-y", "0deg");
      });
    });

    document.querySelectorAll("[data-magnetic]").forEach((button) => {
      button.addEventListener("pointermove", (event) => {
        const rect = button.getBoundingClientRect();
        button.style.setProperty("--magnetic-x", `${(event.clientX - rect.left - rect.width / 2) * 0.08}px`);
        button.style.setProperty("--magnetic-y", `${(event.clientY - rect.top - rect.height / 2) * 0.08}px`);
      });
      button.addEventListener("pointerleave", () => {
        button.style.setProperty("--magnetic-x", "0px");
        button.style.setProperty("--magnetic-y", "0px");
      });
    });
  }

  function initDemoLoop() {
    const loop = document.querySelector("[data-demo-loop]");
    const track = loop?.querySelector(".demo-loop__track");
    const firstSet = track?.querySelector(".demo-loop__set");
    if (!loop || !track || !firstSet || reducedMotion.matches) return;

    let position = 0;
    let velocity = 0;
    let dragging = false;
    let dragged = false;
    let pointerId = null;
    let previousX = 0;
    let previousTime = 0;
    let resumeAt = 0;
    let setWidth = firstSet.getBoundingClientRect().width;
    const autoplaySpeed = window.innerWidth < 600 ? 18 : 31;

    function wrap() {
      if (!setWidth) return;
      position = ((position % setWidth) + setWidth) % setWidth;
    }

    function render() {
      track.style.transform = `translate3d(${-position}px,0,0)`;
    }

    function frame(time) {
      const delta = Math.min((time - previousTime) / 1000 || 0, 0.04);
      previousTime = time;
      if (!dragging) {
        if (Math.abs(velocity) > 2) {
          position += velocity * delta;
          velocity *= Math.pow(0.006, delta);
        } else if (time >= resumeAt) {
          velocity = 0;
          position += autoplaySpeed * delta;
        }
        wrap();
        render();
      }
      requestAnimationFrame(frame);
    }

    loop.addEventListener("pointerdown", (event) => {
      if (event.button !== 0 && event.pointerType === "mouse") return;
      dragging = true;
      dragged = false;
      pointerId = event.pointerId;
      previousX = event.clientX;
      previousTime = performance.now();
      velocity = 0;
      loop.classList.add("is-dragging");
    });

    loop.addEventListener("pointermove", (event) => {
      if (!dragging || event.pointerId !== pointerId) return;
      const now = performance.now();
      const distance = event.clientX - previousX;
      const elapsed = Math.max(now - previousTime, 8);
      if (Math.abs(distance) > 2 && !dragged) {
        dragged = true;
        loop.setPointerCapture(pointerId);
      }
      position -= distance;
      velocity = Math.max(-650, Math.min(650, (-distance / elapsed) * 1000));
      previousX = event.clientX;
      previousTime = now;
      wrap();
      render();
    });

    function release(event) {
      if (!dragging || event.pointerId !== pointerId) return;
      dragging = false;
      resumeAt = performance.now() + 1400;
      loop.classList.remove("is-dragging");
      if (loop.hasPointerCapture(pointerId)) loop.releasePointerCapture(pointerId);
      pointerId = null;
    }

    loop.addEventListener("pointerup", release);
    loop.addEventListener("pointercancel", release);
    loop.addEventListener("dragstart", (event) => event.preventDefault());
    loop.addEventListener("click", (event) => {
      if (!dragged) return;
      event.preventDefault();
      event.stopPropagation();
      dragged = false;
    }, true);
    window.addEventListener("resize", () => {
      setWidth = firstSet.getBoundingClientRect().width;
      wrap();
      render();
    });

    requestAnimationFrame(frame);
  }

  if (navigation && !navigation.querySelector("[data-careers-link]")) {
    const careersLink = document.createElement("a");
    careersLink.href = "/werken-bij/";
    careersLink.dataset.careersLink = "";
    careersLink.textContent = "Werken bij ons";
    navigation.insertBefore(careersLink, navigation.querySelector(".nav-cta"));
  }
  if (menuToggle) menuToggle.addEventListener("click", toggleMenu);
  if (navigation) {
    navigation.addEventListener("click", (event) => {
      if (event.target.closest("a")) closeMenu();
    });
  }

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeMenu(true);
  });

  window.addEventListener("scroll", updateHeader, { passive: true });
  window.addEventListener("resize", () => {
    if (window.innerWidth > 860) closeMenu();
  });

  if (year) year.textContent = String(new Date().getFullYear());
  updateHeader();
  initReveals();
  initPointerMotion();
  initDemoLoop();
})();
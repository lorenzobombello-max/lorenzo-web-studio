(() => {
  "use strict";

  document.documentElement.classList.remove("no-js");

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const header = document.querySelector("[data-header]");
  const pageProgress = document.querySelector("[data-page-progress]");
  const menuToggle = document.querySelector("[data-menu-toggle]");
  const mobileNav = document.querySelector("[data-mobile-nav]");
  const translate = (dutch, english) => window.VesperI18n?.pick(dutch, english) || dutch;

  const updateScrollState = () => {
    const scrollable = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
    const progress = Math.min(window.scrollY / scrollable, 1);
    header?.classList.toggle("is-scrolled", window.scrollY > 24);
    if (pageProgress) pageProgress.style.transform = `scaleX(${progress})`;
  };

  window.addEventListener("scroll", updateScrollState, { passive: true });
  updateScrollState();

  const closeMenu = () => {
    menuToggle?.setAttribute("aria-expanded", "false");
    menuToggle?.setAttribute("aria-label", translate("Navigatie openen", "Open navigation"));
    mobileNav?.classList.remove("is-open");
    document.body.classList.remove("menu-open");
  };

  menuToggle?.addEventListener("click", () => {
    const open = menuToggle.getAttribute("aria-expanded") !== "true";
    menuToggle.setAttribute("aria-expanded", String(open));
    menuToggle.setAttribute("aria-label", open
      ? translate("Navigatie sluiten", "Close navigation")
      : translate("Navigatie openen", "Open navigation"));
    mobileNav?.classList.toggle("is-open", open);
    document.body.classList.toggle("menu-open", open);
  });
  mobileNav?.querySelectorAll("a").forEach((link) => link.addEventListener("click", closeMenu));

  const reveals = [...document.querySelectorAll("[data-reveal]")];
  reveals.forEach((element) => {
    element.style.setProperty("--delay", element.dataset.delay || "0");
  });

  if (reduceMotion.matches || !("IntersectionObserver" in window)) {
    reveals.forEach((element) => element.classList.add("is-visible"));
  } else {
    const revealObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.14, rootMargin: "0px 0px -7%" });
    reveals.forEach((element) => revealObserver.observe(element));
  }

  const storyProgress = document.querySelector("[data-story-progress]");
  const storyCurrent = document.querySelector("[data-story-current]");
  const chapters = [...document.querySelectorAll("[data-chapter]")];
  if ("IntersectionObserver" in window) {
    const chapterObserver = new IntersectionObserver((entries) => {
      const visible = entries.filter((entry) => entry.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (!visible) return;
      const chapter = Number(visible.target.dataset.chapter);
      if (storyCurrent) storyCurrent.textContent = String(chapter).padStart(2, "0");
      if (storyProgress) storyProgress.style.transform = `scaleX(${chapter / chapters.length})`;
    }, { threshold: [0.35, 0.6] });
    chapters.forEach((chapter) => chapterObserver.observe(chapter));
  }

  const counters = [...document.querySelectorAll("[data-count]")];
  const animateCounter = (element) => {
    const target = Number(element.dataset.count);
    const suffix = element.dataset.suffix || "";
    const decimals = Number.isInteger(target) ? 0 : 1;
    if (reduceMotion.matches) {
      element.textContent = `${target.toFixed(decimals)}${suffix}`;
      return;
    }
    const started = performance.now();
    const duration = 1100;
    const tick = (now) => {
      const amount = Math.min((now - started) / duration, 1);
      const eased = 1 - Math.pow(1 - amount, 3);
      element.textContent = `${(target * eased).toFixed(decimals)}${suffix}`;
      if (amount < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };
  if ("IntersectionObserver" in window) {
    const counterObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        animateCounter(entry.target);
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.65 });
    counters.forEach((counter) => counterObserver.observe(counter));
  } else {
    counters.forEach(animateCounter);
  }

  if (!reduceMotion.matches && window.matchMedia("(pointer: fine)").matches) {
    document.querySelectorAll("[data-magnetic]").forEach((button) => {
      button.addEventListener("pointermove", (event) => {
        const bounds = button.getBoundingClientRect();
        const x = (event.clientX - bounds.left - bounds.width / 2) * 0.12;
        const y = (event.clientY - bounds.top - bounds.height / 2) * 0.16;
        button.style.transform = `translate3d(${x}px, ${y}px, 0)`;
      });
      button.addEventListener("pointerleave", () => { button.style.transform = ""; });
    });
  }

  const signature = document.querySelector("[data-signature]");
  const signatureScene = document.querySelector("[data-signature-scene]");
  const mediaMotion = document.querySelector("[data-media-motion]");
  const mediaPanels = [...document.querySelectorAll("[data-media-panel]")];
  const manifesto = document.querySelector(".manifesto");
  const parallaxStage = document.querySelector("[data-parallax-stage]");
  const heroCanvas = document.querySelector("[data-signal-canvas]");
  let motionFrame = 0;
  let pointerDepthX = 0;
  let pointerDepthY = 0;

  const renderMotion = () => {
    motionFrame = 0;
    if (reduceMotion.matches) {
      signatureScene?.style.removeProperty("--scene-x");
      signatureScene?.style.removeProperty("--scene-y");
      heroCanvas?.style.removeProperty("transform");
      mediaPanels.forEach((panel) => panel.style.removeProperty("--panel-shift"));
      return;
    }

    if (heroCanvas instanceof HTMLElement) {
      const heroProgress = Math.min(window.scrollY / Math.max(window.innerHeight, 1), 1);
      heroCanvas.style.transform = `translate3d(${pointerDepthX * 12}px, ${pointerDepthY * 9 + heroProgress * 28}px, 0) scale(${1.025 + heroProgress * 0.035})`;
    }

    if (signature && signatureScene instanceof HTMLElement) {
      const bounds = signature.getBoundingClientRect();
      const scrollTurn = Math.max(-1, Math.min(1, (window.innerHeight / 2 - (bounds.top + bounds.height / 2)) / window.innerHeight));
      signatureScene.style.setProperty("--scene-x", `${pointerDepthX * 9 + scrollTurn * 7}deg`);
      signatureScene.style.setProperty("--scene-y", `${pointerDepthY * -7 + scrollTurn * -4}deg`);
    }

    if (mediaMotion) {
      const bounds = mediaMotion.getBoundingClientRect();
      const progress = Math.max(-1, Math.min(1, (window.innerHeight / 2 - (bounds.top + bounds.height / 2)) / window.innerHeight));
      const strengths = [-34, 52, -24, 43, -38];
      mediaPanels.forEach((panel, index) => {
        panel.style.setProperty("--panel-shift", `${progress * strengths[index]}px`);
        const visual = panel.querySelector(".media-panel__visual");
        if (visual instanceof HTMLElement) visual.style.transform = `translate3d(0, ${progress * strengths[index] * -0.42}px, 0) scale(1.08)`;
      });
    }

    if (parallaxStage instanceof HTMLElement) {
      const bounds = parallaxStage.parentElement?.getBoundingClientRect();
      const progress = bounds ? Math.max(0, Math.min(1, -bounds.top / Math.max(bounds.height - window.innerHeight, 1))) : 0;
      parallaxStage.style.setProperty("--nova-shift", `${(progress - 0.5) * 18}px`);
    }
  };

  const queueMotion = () => {
    if (!motionFrame) motionFrame = requestAnimationFrame(renderMotion);
  };
  window.addEventListener("scroll", queueMotion, { passive: true });
  window.addEventListener("resize", queueMotion);
  window.addEventListener("pointermove", (event) => {
    pointerDepthX = event.clientX / Math.max(window.innerWidth, 1) - 0.5;
    pointerDepthY = event.clientY / Math.max(window.innerHeight, 1) - 0.5;
    queueMotion();
  }, { passive: true });

  if (manifesto && "IntersectionObserver" in window) {
    const statementObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => manifesto.classList.toggle("is-assembled", entry.isIntersecting || reduceMotion.matches));
    }, { threshold: 0.42 });
    statementObserver.observe(manifesto);
  } else {
    manifesto?.classList.add("is-assembled");
  }

  const mediaPanelGroup = document.querySelector(".media-panels");
  if (mediaPanelGroup && "IntersectionObserver" in window && !reduceMotion.matches) {
    const mediaObserver = new IntersectionObserver((entries, observer) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      mediaPanelGroup.classList.add("is-entered");
      observer.disconnect();
    }, { threshold: 0.22 });
    mediaObserver.observe(mediaPanelGroup);
  } else {
    mediaPanelGroup?.classList.add("is-entered");
  }

  const novaPanel = document.querySelector(".case-study__interface");
  const novaBars = [...document.querySelectorAll(".interface__chart span")];
  const novaIndicators = [...document.querySelectorAll("[data-nova-key]")];
  const novaLabel = document.querySelector("[data-nova-label]");
  const liveValue = document.querySelector("[data-live-value]");
  const novaStatus = document.querySelector("[data-nova-status]");
  const novaStates = [
    { key: "engagement", label: ["Betrokkenheid", "Engagement"], value: "78%", bars: [42, 61, 48, 78, 72], status: ["De campagne-aandacht blijft boven de lanceringsdoelstelling.", "Campaign attention is holding above launch target."] },
    { key: "conversion", label: ["Conversie", "Conversion"], value: "+12.4%", bars: [34, 47, 59, 66, 84], status: ["Editorial productroutes converteren op +12,4%.", "Editorial product paths are converting at +12.4%."] },
    { key: "response", label: ["Respons", "Response"], value: "41 ms", bars: [82, 69, 58, 47, 41], status: ["De interactierespons blijft binnen de doelstelling van 50 ms.", "Interaction response remains inside the 50 ms target."] },
    { key: "stability", label: ["Stabiliteit", "Stability"], value: "98.6%", bars: [74, 82, 78, 91, 98], status: ["De stabiliteit van het lanceringsplatform blijft op 98,6%.", "Launch platform stability is holding at 98.6%."] }
  ];
  let novaTimer = 0;
  let novaStep = 0;
  const updateNova = (requestedIndex) => {
    const stateIndex = Number.isInteger(requestedIndex) ? requestedIndex : novaStep % novaStates.length;
    const state = novaStates[stateIndex];
    novaBars.forEach((bar, index) => {
      bar.style.setProperty("--bar-value", String(state.bars[index]));
      bar.style.opacity = index === stateIndex ? ".98" : ".58";
    });
    novaIndicators.forEach((indicator, index) => {
      const active = index === stateIndex;
      indicator.classList.toggle("is-live", active);
      indicator.setAttribute("aria-pressed", String(active));
    });
    if (novaLabel) novaLabel.textContent = translate(...state.label).toUpperCase();
    if (liveValue) liveValue.textContent = state.value;
    if (novaStatus) novaStatus.textContent = translate(...state.status);
    novaStep = stateIndex + 1;
  };
  const stopNova = () => { window.clearInterval(novaTimer); novaTimer = 0; };
  const startNova = () => {
    stopNova();
    updateNova(reduceMotion.matches ? 0 : undefined);
    if (!reduceMotion.matches) novaTimer = window.setInterval(updateNova, 1450);
  };
  novaIndicators.forEach((indicator, index) => indicator.addEventListener("click", () => {
    stopNova();
    updateNova(index);
    if (!reduceMotion.matches) novaTimer = window.setInterval(updateNova, 3200);
  }));
  if (novaPanel && "IntersectionObserver" in window) {
    const novaObserver = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) startNova();
      else stopNova();
    }, { threshold: 0.15 });
    novaObserver.observe(novaPanel);
  } else {
    startNova();
  }

  window.addEventListener("vesper:languagechange", () => {
    closeMenu();
    updateNova(Math.max(0, (novaStep - 1) % novaStates.length));
  });

  reduceMotion.addEventListener?.("change", () => {
    renderMotion();
    startNova();
    manifesto?.classList.toggle("is-assembled", true);
    mediaPanelGroup?.classList.add("is-entered");
  });
  renderMotion();

  document.querySelectorAll("[data-demo-form]").forEach((form) => {
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const status = form.querySelector("[data-form-status]");
      if (status) {
        status.textContent = translate(
          "Demo-aanvraag voorbereid. Er is geen informatie verzonden of opgeslagen.",
          "Demo enquiry prepared. No information was sent or stored."
        );
        status.classList.add("is-success");
      }
      form.reset();
    });
  });

  const canvas = document.querySelector("[data-signal-canvas]");
  if (!(canvas instanceof HTMLCanvasElement)) return;
  const context = canvas.getContext("2d", { alpha: true });
  if (!context) return;

  let width = 0;
  let height = 0;
  let animationFrame = 0;
  let pointerX = 0;
  let pointerY = 0;
  let targetPointerX = 0;
  let targetPointerY = 0;
  const particleCount = 42;
  const particles = Array.from({ length: particleCount }, (_, index) => ({
    phase: (index / particleCount) * Math.PI * 2,
    radius: 0.2 + ((index * 17) % 31) / 100,
    speed: 0.18 + ((index * 7) % 13) / 100,
    size: 0.5 + (index % 4) * 0.34
  }));

  const resizeCanvas = () => {
    const ratio = Math.min(window.devicePixelRatio || 1, 1.5);
    width = canvas.clientWidth;
    height = canvas.clientHeight;
    canvas.width = Math.max(1, Math.floor(width * ratio));
    canvas.height = Math.max(1, Math.floor(height * ratio));
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
  };

  const drawRibbon = (time, radius, offset, alpha, lineWidth) => {
    const centerX = width * 0.57 + pointerX * 22;
    const centerY = height * 0.43 + pointerY * 18;
    const points = 150;
    const gradient = context.createLinearGradient(centerX - radius, centerY, centerX + radius, centerY);
    gradient.addColorStop(0, `rgba(20, 79, 255, ${alpha * 0.08})`);
    gradient.addColorStop(0.42, `rgba(70, 132, 255, ${alpha})`);
    gradient.addColorStop(0.72, `rgba(84, 216, 255, ${alpha * 0.9})`);
    gradient.addColorStop(1, `rgba(84, 216, 255, 0)`);
    context.beginPath();
    for (let index = 0; index <= points; index += 1) {
      const angle = (index / points) * Math.PI * 2;
      const wave = Math.sin(angle * 3 + time * 0.00042 + offset) * radius * 0.12;
      const x = centerX + Math.cos(angle) * (radius + wave);
      const y = centerY + Math.sin(angle) * (radius * 0.48 + wave * 0.52);
      const tiltX = (y - centerY) * 0.24;
      if (index === 0) context.moveTo(x + tiltX, y);
      else context.lineTo(x + tiltX, y);
    }
    context.closePath();
    context.strokeStyle = gradient;
    context.lineWidth = lineWidth;
    context.shadowColor = "rgba(34, 126, 255, .9)";
    context.shadowBlur = lineWidth * 7;
    context.stroke();
    context.shadowBlur = 0;
  };

  const drawScene = (time = 0) => {
    context.clearRect(0, 0, width, height);
    pointerX += (targetPointerX - pointerX) * 0.035;
    pointerY += (targetPointerY - pointerY) * 0.035;
    const base = Math.min(width, height) * (width < 700 ? 0.34 : 0.29);

    drawRibbon(time, base, 0, 0.8, 1.2);
    drawRibbon(time * 0.84, base * 0.78, 1.9, 0.55, 0.8);
    drawRibbon(time * 1.12, base * 1.18, 3.5, 0.28, 0.6);

    const centerX = width * 0.57 + pointerX * 26;
    const centerY = height * 0.43 + pointerY * 20;
    particles.forEach((particle, index) => {
      const angle = particle.phase + time * 0.00005 * particle.speed;
      const depth = (Math.sin(angle * 2.3 + index) + 1) / 2;
      const x = centerX + Math.cos(angle) * base * particle.radius * 2.1;
      const y = centerY + Math.sin(angle) * base * particle.radius * 0.92;
      context.beginPath();
      context.arc(x, y, particle.size * (0.7 + depth), 0, Math.PI * 2);
      context.fillStyle = `rgba(126, 218, 255, ${0.12 + depth * 0.55})`;
      context.fill();
    });

    const glow = context.createRadialGradient(centerX, centerY, 0, centerX, centerY, base * 0.42);
    glow.addColorStop(0, "rgba(222, 249, 255, .82)");
    glow.addColorStop(0.06, "rgba(91, 220, 255, .48)");
    glow.addColorStop(0.25, "rgba(20, 100, 255, .16)");
    glow.addColorStop(1, "rgba(20, 100, 255, 0)");
    context.fillStyle = glow;
    context.fillRect(centerX - base, centerY - base, base * 2, base * 2);
  };

  const animate = (time) => {
    drawScene(time);
    animationFrame = requestAnimationFrame(animate);
  };

  const startCanvas = () => {
    cancelAnimationFrame(animationFrame);
    resizeCanvas();
    if (reduceMotion.matches) drawScene(0);
    else animationFrame = requestAnimationFrame(animate);
  };

  window.addEventListener("resize", startCanvas);
  window.addEventListener("pointermove", (event) => {
    targetPointerX = event.clientX / Math.max(window.innerWidth, 1) - 0.5;
    targetPointerY = event.clientY / Math.max(window.innerHeight, 1) - 0.5;
  }, { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) cancelAnimationFrame(animationFrame);
    else startCanvas();
  });
  reduceMotion.addEventListener?.("change", startCanvas);
  startCanvas();
})();

(function () {
  const body = document.body;
  if (!body || !body.classList.contains("home-studio")) return;

  const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  body.classList.add("js-home-studio");

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function initCursorGlow() {
    if (prefersReducedMotion || window.innerWidth < 900) return;

    let frameRequested = false;
    let pointerX = 0;
    let pointerY = 0;

    function updateGlow() {
      frameRequested = false;
      document.documentElement.style.setProperty("--cursor-x", `${pointerX}px`);
      document.documentElement.style.setProperty("--cursor-y", `${pointerY}px`);
    }

    window.addEventListener(
      "pointermove",
      (event) => {
        pointerX = event.clientX;
        pointerY = event.clientY;
        if (!frameRequested) {
          frameRequested = true;
          requestAnimationFrame(updateGlow);
        }
      },
      { passive: true }
    );
  }

  function initMagneticButtons() {
    if (prefersReducedMotion || window.innerWidth < 900) return;
    const magnetNodes = document.querySelectorAll(".studio-magnetic");
    if (!magnetNodes.length) return;

    magnetNodes.forEach((node) => {
      node.addEventListener("pointermove", (event) => {
        const rect = node.getBoundingClientRect();
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;
        const deltaX = clamp((event.clientX - centerX) * 0.08, -7, 7);
        const deltaY = clamp((event.clientY - centerY) * 0.08, -7, 7);
        node.style.setProperty("--mx", `${deltaX}px`);
        node.style.setProperty("--my", `${deltaY}px`);
      });

      node.addEventListener("pointerleave", () => {
        node.style.setProperty("--mx", "0px");
        node.style.setProperty("--my", "0px");
      });
    });
  }

  function initShowcase() {
    const root = document.getElementById("studioShowcase");
    if (!root) return;

    const tabs = Array.from(root.querySelectorAll(".studio-showcase__tab"));
    const iframeNode = document.getElementById("showcaseIframe");
    const iframeLoading = document.getElementById("showcaseIframeLoading");
    const iframeFallback = document.getElementById("showcaseIframeFallback");
    const iframePlaceholder = document.getElementById("showcaseIframePlaceholder");
    const iframeLabel = document.getElementById("showcaseIframeLabel");
    const fallbackLink = document.getElementById("showcaseFallbackLink");
    const statusNode = document.getElementById("showcaseStatus");
    const labelNode = document.getElementById("showcaseLabel");
    const titleNode = document.getElementById("showcaseTitle");
    const descriptionNode = document.getElementById("showcaseDescription");
    const traitsNode = document.getElementById("showcaseTraits");
    const fitNode = document.getElementById("showcaseFit");
    const benefitNode = document.getElementById("showcaseBenefit");
    const linkNode = document.getElementById("showcaseLink");
    const prevButton = document.getElementById("showcasePrev");
    const nextButton = document.getElementById("showcaseNext");

    if (
      !tabs.length ||
      !iframeNode ||
      !statusNode ||
      !labelNode ||
      !titleNode ||
      !descriptionNode ||
      !traitsNode ||
      !fitNode ||
      !benefitNode ||
      !linkNode
    ) {
      return;
    }

    let activeIndex = 0;
    let touchStartX = 0;

    const worldInsights = {
      industrial: {
        fit: "Geschikt voor industriële servicebedrijven met onderhoud, storingen en interventies.",
        benefit: "Verhoogt de kwaliteit van technische offerteaanvragen via een duidelijke flow.",
      },
      restaurant: {
        fit: "Geschikt voor restaurants met reservaties en menupresentatie.",
        benefit: "Stimuleert meer rechtstreekse reservatieaanvragen.",
      },
      mediterranean: {
        fit: "Geschikt voor fine dining en hospitalitymerken met merkbeleving.",
        benefit: "Positioneert je zaak sterker in waardeperceptie.",
      },
      personal: {
        fit: "Geschikt voor freelancers, consultants en experts met casegedreven verkoop.",
        benefit: "Zet expertise sneller om in kwalitatieve leads.",
      },
      cafe: {
        fit: "Geschikt voor cafés en bars met events, menu en avondsfeer.",
        benefit: "Maakt sfeer meteen tastbaar en verhoogt doorklik naar contact.",
      },
      garage: {
        fit: "Geschikt voor garages met afspraken, voorraad en diagnose.",
        benefit: "Versnelt de route naar afspraken en werkplaatsvragen.",
      },
      luna: {
        fit: "Geschikt voor premium kapsalons, schoonheidssalons en luxury beauty-merken.",
        benefit: "Straalt verfijning en vertrouwen uit — precies wat klanten zoeken bij een premium kapsalon.",
      },
      future: {
        fit: "Geschikt voor nieuwe branches die een unieke digitale identiteit willen.",
        benefit: "Laat je snel een branchegerichte demo valideren.",
      },
      default: {
        fit: "Geschikt voor bedrijven die een duidelijke online serviceflow willen.",
        benefit: "Versterkt je commerciële geloofwaardigheid in één duidelijke demo-ervaring.",
      },
    };

    function parseTraits(rawTraits) {
      if (!rawTraits) return [];
      return rawTraits
        .split("|")
        .map((item) => item.trim())
        .filter(Boolean)
        .slice(0, 4);
    }

    // Wire iframe load/error handlers once
    iframeNode.addEventListener("load", () => {
      if (iframeLoading) iframeLoading.hidden = true;
      if (iframeFallback) iframeFallback.hidden = true;
    });
    iframeNode.addEventListener("error", () => {
      if (iframeLoading) iframeLoading.hidden = true;
      iframeNode.hidden = true;
      if (iframeFallback) iframeFallback.hidden = false;
    });

    function setPreviewIframe(src, title, isFuture) {
      if (isFuture) {
        iframeNode.hidden = true;
        if (iframeLoading) iframeLoading.hidden = true;
        if (iframeFallback) iframeFallback.hidden = true;
        if (iframePlaceholder) iframePlaceholder.hidden = false;
        if (iframeLabel) iframeLabel.hidden = true;
        root.setAttribute("data-preview-mode", "placeholder");
        return;
      }

      if (iframePlaceholder) iframePlaceholder.hidden = true;
      if (iframeFallback) iframeFallback.hidden = true;
      if (iframeLabel) iframeLabel.hidden = false;
      iframeNode.hidden = false;
      root.setAttribute("data-preview-mode", "iframe");

      iframeNode.title = `Interactieve preview van ${title}`;
      iframeNode.setAttribute("aria-label", `Interactieve preview van ${title}`);
      if (fallbackLink) fallbackLink.href = src;

      // Only reload when src actually changes
      if (iframeNode.dataset.currentSrc !== src) {
        iframeNode.dataset.currentSrc = src;
        if (iframeLoading) iframeLoading.hidden = false;
        iframeNode.src = src;
      }
    }

    function applyTab(index) {
      activeIndex = (index + tabs.length) % tabs.length;
      const tab = tabs[activeIndex];
      if (!tab) return;

      tabs.forEach((button, buttonIndex) => {
        const isActive = buttonIndex === activeIndex;
        button.classList.toggle("is-active", isActive);
        button.setAttribute("aria-selected", String(isActive));
      });

      const isFuture = tab.dataset.status === "Op aanvraag";
      const demoSrc = tab.dataset.link || "";
      const title = tab.dataset.title || tab.textContent || "Demo";
      const traits = parseTraits(tab.dataset.traits || "");

      setPreviewIframe(demoSrc, title, isFuture);
      statusNode.textContent = tab.dataset.status || "Live demo";
      labelNode.textContent = tab.dataset.label || "Demo";
      titleNode.textContent = title;
      descriptionNode.textContent = tab.dataset.description || "";

      traitsNode.innerHTML = traits.map((trait) => `<li>${trait}</li>`).join("");
      const themeKey = tab.dataset.theme || "default";
      const insight = worldInsights[themeKey] || worldInsights.default;
      fitNode.textContent = insight.fit;
      benefitNode.textContent = insight.benefit;

      linkNode.setAttribute("href", isFuture ? "#contact" : demoSrc);
      linkNode.textContent = isFuture ? "Vraag deze demo aan" : "Open volledige demo";

      root.setAttribute("data-theme", themeKey);
      root.setAttribute("data-active-index", String(activeIndex));
    }

    tabs.forEach((tab, index) => {
      tab.addEventListener("click", () => applyTab(index));
      tab.addEventListener("keydown", (event) => {
        if (event.key === "ArrowDown" || event.key === "ArrowRight") {
          event.preventDefault();
          applyTab(index + 1);
          tabs[(index + 1) % tabs.length].focus();
        }
        if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
          event.preventDefault();
          applyTab(index - 1);
          tabs[(index - 1 + tabs.length) % tabs.length].focus();
        }
      });
    });

    if (prevButton) prevButton.addEventListener("click", () => applyTab(activeIndex - 1));
    if (nextButton) nextButton.addEventListener("click", () => applyTab(activeIndex + 1));

    root.addEventListener(
      "touchstart",
      (event) => {
        touchStartX = event.changedTouches[0]?.clientX || 0;
      },
      { passive: true }
    );

    root.addEventListener(
      "touchend",
      (event) => {
        const endX = event.changedTouches[0]?.clientX || 0;
        const deltaX = endX - touchStartX;
        if (Math.abs(deltaX) < 48) return;
        if (deltaX < 0) applyTab(activeIndex + 1);
        if (deltaX > 0) applyTab(activeIndex - 1);
      },
      { passive: true }
    );

    applyTab(0);
  }

  function initSpectrum() {
    const root = document.getElementById("spectrumBlock");
    if (!root) return;

    const chips = Array.from(root.querySelectorAll(".spectrum__chip"));
    const styleLabel = document.getElementById("spectrumStyleLabel");
    const description = document.getElementById("spectrumDescription");

    if (!chips.length) return;

    function activateChip(chip) {
      chips.forEach((card) => {
        const isActive = card === chip;
        card.classList.toggle("is-active", isActive);
        card.setAttribute("aria-selected", String(isActive));
        const cta = card.querySelector(".spectrum-card__cta");
        if (cta) cta.setAttribute("tabindex", isActive ? "0" : "-1");
      });
      root.setAttribute("data-style", chip.dataset.style || "minimalistisch");
      if (styleLabel) styleLabel.textContent = chip.dataset.name || chip.dataset.style || "";
      if (description) description.textContent = chip.dataset.copy || "";
    }

    chips.forEach((chip) => {
      chip.addEventListener("mouseenter", () => activateChip(chip));
      chip.addEventListener("focus", () => activateChip(chip));
      chip.addEventListener("click", () => activateChip(chip));
      chip.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          activateChip(chip);
        }
      });
    });
  }

  function initServiceModules() {
    const root = document.getElementById("serviceModules");
    if (!root) return;

    const nodes = Array.from(root.querySelectorAll(".studio-node"));
    const titleNode = document.getElementById("moduleTitle");
    const descriptionNode = document.getElementById("moduleDescription");
    const benefitsNode = document.getElementById("moduleBenefits");

    if (!nodes.length || !titleNode || !descriptionNode || !benefitsNode) return;

    const content = {
      strategie: {
        title: "Strategie",
        description: "We bepalen focus, doelgroep en prioriteiten zodat de website bezoekers gericht naar actie begeleidt.",
        benefits: ["Duidelijke richting voor inhoud en structuur", "Betere beslissingen tijdens ontwerp en ontwikkeling"],
      },
      structuur: {
        title: "Structuur",
        description: "Informatie wordt logisch geordend zodat bezoekers intuïtief begrijpen waar ze moeten klikken.",
        benefits: ["Snellere navigatie voor klanten", "Minder afhakers door heldere flow"],
      },
      webdesign: {
        title: "Webdesign",
        description: "Een visuele stijl op maat van je merk, met balans tussen onderscheidend karakter en leesbaarheid.",
        benefits: ["Professionele eerste indruk", "Sterkere merkherkenning"],
      },
      responsive: {
        title: "Responsive ontwikkeling",
        description: "De pagina werkt gecontroleerd op mobiel, tablet en desktop zonder concessies in gebruikservaring.",
        benefits: ["Gebruiksvriendelijk op elk toestel", "Betere mobiele conversie"],
      },
      seo: {
        title: "Technische SEO",
        description: "Semantische opbouw, metadata en indexeerbaarheid vormen de technische basis voor vindbaarheid.",
        benefits: ["Zoekmachines begrijpen de content beter", "Betere groeibasis op lange termijn"],
      },
      formulieren: {
        title: "Formulieren en conversie",
        description: "Contactflows worden compact, duidelijk en betrouwbaar uitgewerkt voor hogere aanvraagkwaliteit.",
        benefits: ["Meer bruikbare leads", "Minder frictie bij aanvraag"],
      },
      onderhoud: {
        title: "Onderhoud",
        description: "Updates en kleine verbeteringen blijven beheersbaar zodat de website actueel en veilig blijft.",
        benefits: ["Langere levensduur van je site", "Minder technische zorgen"],
      },
      uitbreidingen: {
        title: "Uitbreidingen",
        description: "Nieuwe pagina's, modules of functionaliteiten kunnen stapsgewijs worden toegevoegd wanneer je groeit.",
        benefits: ["Schaalbaarheid zonder herstart", "Flexibiliteit voor toekomstige plannen"],
      },
    };

    function activateNode(node) {
      const key = node.dataset.key || "strategie";
      const next = content[key] || content.strategie;

      nodes.forEach((item) => item.classList.toggle("is-active", item === node));
      titleNode.textContent = next.title;
      descriptionNode.textContent = next.description;
      benefitsNode.innerHTML = next.benefits.map((item) => `<li>${item}</li>`).join("");
    }

    nodes.forEach((node) => {
      node.addEventListener("mouseenter", () => activateNode(node));
      node.addEventListener("focus", () => activateNode(node));
      node.addEventListener("click", () => activateNode(node));
    });
  }

  function initJourney() {
    const root = document.getElementById("journey");
    if (!root) return;

    const scenes = Array.from(root.querySelectorAll(".journey-scene"));
    const steps = Array.from(root.querySelectorAll(".journey__steps li"));
    const currentNode = document.getElementById("journeyCurrent");
    const progressNode = document.getElementById("journeyProgress");

    if (!scenes.length || !steps.length || !currentNode || !progressNode || !window.IntersectionObserver) return;

    function setStep(stepIndex) {
      const normalized = clamp(stepIndex, 0, scenes.length - 1);
      const scene = scenes[normalized];
      const title = scene?.querySelector("h3")?.textContent || "Fase";

      currentNode.textContent = `${normalized + 1}. ${title}`;
      steps.forEach((step, index) => step.classList.toggle("is-active", index <= normalized));
      progressNode.style.setProperty("width", `${((normalized + 1) / scenes.length) * 100}%`);
    }

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          const step = Number(entry.target.getAttribute("data-step")) || 1;
          setStep(step - 1);
        });
      },
      {
        threshold: 0.55,
        rootMargin: "-8% 0px -24% 0px",
      }
    );

    scenes.forEach((scene) => observer.observe(scene));
    setStep(0);
  }

  function initIdeaLab() {
    const root = document.getElementById("ideaLab");
    if (!root) return;

    const tabs = Array.from(root.querySelectorAll(".idea-lab__tab"));
    const layers = Array.from(root.querySelectorAll(".idea-layer"));
    if (!tabs.length || !layers.length) return;

    function activateLayer(layerKey) {
      tabs.forEach((tab) => {
        const active = tab.dataset.layer === layerKey;
        tab.classList.toggle("is-active", active);
        tab.setAttribute("aria-selected", String(active));
      });

      layers.forEach((layer) => {
        layer.classList.toggle("is-active", layer.dataset.layer === layerKey);
      });
    }

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => activateLayer(tab.dataset.layer || "notitie"));
    });
  }

  function initPriceExplorer() {
    const root = document.getElementById("priceExplorer");
    if (!root) return;

    const inputs = Array.from(root.querySelectorAll("select"));
    const bandNode = document.getElementById("pricingBand");
    const rangeNode = document.getElementById("pricingRange");
    const factorsNode = document.getElementById("pricingFactors");

    if (!inputs.length || !bandNode || !rangeNode || !factorsNode) return;

    function toNumber(value) {
      const number = Number(value);
      return Number.isFinite(number) ? number : 1;
    }

    function updatePricing() {
      const multiplier = inputs.reduce((acc, input) => acc * toNumber(input.value), 1);
      const normalized = clamp(multiplier, 1, 4.6);

      let band = "Projectcategorie: Starter tot Professional";
      let range = "Indicatie: EUR 1.800 - EUR 3.200";
      let factors = "Belangrijkste factoren: pagina-omvang, interactiecomplexiteit en gewenste timing.";

      if (normalized > 1.55 && normalized <= 2.2) {
        band = "Projectcategorie: Professional";
        range = "Indicatie: EUR 3.200 - EUR 5.800";
        factors = "Belangrijkste factoren: extra pagina's, meertaligheid en meerdere conversieflows.";
      }

      if (normalized > 2.2) {
        band = "Projectcategorie: Professional tot Maatwerk";
        range = "Indicatie: vanaf EUR 5.800";
        factors = "Belangrijkste factoren: maatwerkinteracties, snelle planning en doorlopende ondersteuning.";
      }

      bandNode.textContent = band;
      rangeNode.textContent = range;
      factorsNode.textContent = factors;
    }

    inputs.forEach((input) => {
      input.addEventListener("change", updatePricing);
      input.addEventListener("input", updatePricing);
    });

    updatePricing();
  }

  function initKnowledgeWall() {
    const root = document.getElementById("knowledgeWall");
    if (!root) return;

    const tabs = Array.from(root.querySelectorAll(".knowledge-wall__topic"));
    const titleNode = document.getElementById("knowledgeTitle");
    const bodyNode = document.getElementById("knowledgeBody");

    if (!tabs.length || !titleNode || !bodyNode) return;

    const topics = {
      planning: {
        title: "Planning",
        body: "De timing hangt af van scope, feedbacktempo en inhoud. Je krijgt vooraf een realistische planning met duidelijke fases.",
      },
      kosten: {
        title: "Kosten",
        body: "De prijsrichting wordt bepaald door type website, omvang, interacties, timing en gewenste opvolging na oplevering.",
      },
      techniek: {
        title: "Techniek",
        body: "Responsive gedrag, performantie, toegankelijkheid en technische SEO vormen de standaardbasis van elk traject.",
      },
      onderhoud: {
        title: "Onderhoud",
        body: "Je website blijft uitbreidbaar met gerichte updates, verbeteringen en ondersteuning volgens de noden van je onderneming.",
      },
      inhoud: {
        title: "Inhoud",
        body: "Tijdens analyse begeleiden we de inhoudsstructuur zodat je aanbod helder, geloofwaardig en conversiegericht wordt gepresenteerd.",
      },
    };

    function setTopic(topicKey) {
      const topic = topics[topicKey] || topics.planning;
      tabs.forEach((tab) => {
        const active = tab.dataset.topic === topicKey;
        tab.classList.toggle("is-active", active);
        tab.setAttribute("aria-selected", String(active));
      });
      titleNode.textContent = topic.title;
      bodyNode.textContent = topic.body;
    }

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => setTopic(tab.dataset.topic || "planning"));
    });
  }

  function initHeroDepthShift() {
    if (prefersReducedMotion) return;
    const hero = document.querySelector(".studio-hero");
    if (!hero) return;

    let ticking = false;

    function update() {
      ticking = false;
      const rect = hero.getBoundingClientRect();
      const ratio = clamp((window.innerHeight - rect.top) / (window.innerHeight + rect.height), 0, 1);
      const beamOffset = (ratio - 0.5) * 20;
      hero.style.setProperty("--beam-shift", `${beamOffset}px`);
    }

    window.addEventListener(
      "scroll",
      () => {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(update);
      },
      { passive: true }
    );

    update();
  }

  function initDeferredStudioModules() {
    initShowcase();
    initSpectrum();
    initServiceModules();
    initJourney();
    initIdeaLab();
    initPriceExplorer();
    initKnowledgeWall();
  }

  initCursorGlow();
  initMagneticButtons();
  initHeroDepthShift();

  if ("requestIdleCallback" in window) {
    window.requestIdleCallback(initDeferredStudioModules, { timeout: 700 });
  } else {
    window.setTimeout(initDeferredStudioModules, 180);
  }
})();

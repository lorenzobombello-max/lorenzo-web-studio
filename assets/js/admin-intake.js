(function () {
  "use strict";

  const hashParameters = new URLSearchParams(window.location.hash.slice(1));
  const tokenCandidate = hashParameters.get("token") || "";
  const capability = /^[A-Za-z0-9_-]{43}$/.test(tokenCandidate) ? tokenCandidate : "";
  window.history.replaceState(window.history.state, "", `${window.location.pathname}${window.location.search}`);

  const loading = document.getElementById("adminBriefingLoading");
  const unavailable = document.getElementById("adminBriefingUnavailable");
  const technicalError = document.getElementById("adminBriefingTechnicalError");
  const workspace = document.getElementById("adminBriefingWorkspace");
  const sectionsNode = document.getElementById("adminBriefingSections");
  const clientNode = document.getElementById("adminBriefingClient");
  const referenceNode = document.getElementById("adminBriefingReference");
  const submittedNode = document.getElementById("adminBriefingSubmitted");
  const typeNode = document.getElementById("adminBriefingType");
  const printButton = document.getElementById("adminBriefingPrint");
  const applicationNode = document.getElementById("adminBriefingApplication");
  const functionsBaseUrl = (
    document.querySelector('meta[name="lws-functions-base-url"]')?.getAttribute("content") || ""
  ).replace(/\/$/, "");
  const endpoint = functionsBaseUrl ? `${functionsBaseUrl}/intake-quote-request` : "";

  printButton?.addEventListener("click", () => window.print());

  const valueLabels = {
    professional_presence: "Professionele uitstraling", generate_leads: "Leads genereren",
    quote_requests: "Offerteaanvragen", contact_requests: "Contactaanvragen", appointments: "Afspraken",
    reservations: "Reservaties", sell_products: "Producten verkopen", sell_services: "Diensten verkopen",
    portfolio: "Portfolio tonen", information: "Informeren", recruitment: "Werving", other: "Andere",
    home: "Home", about: "Over ons", services: "Diensten", products: "Producten", team: "Team",
    pricing: "Prijzen", faq: "FAQ", reviews: "Reviews", blog: "Blog", contact: "Contact",
    quote_request: "Offerteaanvraag", shop: "Webshop", jobs: "Vacatures", gallery: "Galerij",
    contact_form: "Contactformulier", quote_form: "Offerteformulier", google_maps: "Google Maps",
    social_links: "Social links", newsletter: "Nieuwsbrief", whatsapp: "WhatsApp",
    online_payment: "Online betaling", customer_login: "Klantlogin", downloads: "Downloads",
    search: "Zoeken", multilingual: "Meertalig", unsure: "Nog niet zeker", modern: "Modern",
    business: "Zakelijk", minimal: "Minimalistisch", elegant: "Elegant", luxury: "Luxueus", warm: "Warm",
    playful: "Speels", creative: "Creatief", technical: "Technisch", industrial: "Industrieel", calm: "Rustig",
    complete: "Volledig", partial: "Gedeeltelijk", none: "Niet beschikbaar", unknown: "Onbekend",
    available: "Beschikbaar", needs_update: "Moet bijgewerkt worden", needed: "Nog nodig",
    needs_help: "Hulp nodig", sufficient: "Voldoende", optimize_existing: "Bestaande beelden optimaliseren",
    ai_images: "AI-beelden", stock_images: "Stockbeelden", professional_photography: "Professionele fotografie",
    has_domain: "Domein aanwezig", no_domain: "Nog geen domein", has_hosting: "Hosting aanwezig",
    no_hosting: "Nog geen hosting", yes: "Ja", no: "Nee", advice: "Advies", maybe: "Misschien",
    info_requested: "Meer informatie", high: "Hoog", basic: "Basis", low: "Laag",
    professional_appearance: "Professionele uitstraling", usability: "Gebruiksgemak", more_requests: "Meer aanvragen",
    more_sales: "Meer verkoop", mobile_experience: "Mobiele ervaring", performance: "Snelheid", seo: "SEO",
    easy_management: "Eenvoudig beheer", fast_delivery: "Snelle oplevering", stay_within_budget: "Binnen budget",
    differentiate: "Onderscheiden", nl: "Nederlands", fr: "Frans", en: "Engels", de: "Duits",
    consultations: "Consultaties", classes: "Lessen"
  };

  function hideStates() {
    loading.hidden = true;
    unavailable.hidden = true;
    technicalError.hidden = true;
    workspace.hidden = true;
  }

  function showState(node) {
    hideStates();
    node.hidden = false;
  }

  function hasValue(value) {
    if (value === null || value === undefined || value === "") return false;
    if (Array.isArray(value)) return value.length > 0;
    if (typeof value === "object") return Object.keys(value).length > 0;
    return true;
  }

  function isRecord(value) {
    return Boolean(value) && typeof value === "object" && !Array.isArray(value);
  }

  function displayValue(value) {
    if (typeof value === "boolean") return value ? "Ja" : "Nee";
    if (typeof value === "string") return valueLabels[value] || value;
    if (typeof value === "number") return String(value);
    return "";
  }

  function formatDateTime(value) {
    if (typeof value !== "string") return "Niet opgegeven";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "Niet opgegeven";
    return date.toLocaleString("nl-BE", {
      dateStyle: "long",
      timeStyle: "short",
      timeZone: "Europe/Brussels"
    });
  }

  function formatDate(value) {
    if (typeof value !== "string") return "";
    const date = new Date(`${value}T12:00:00Z`);
    if (Number.isNaN(date.getTime())) return value;
    return date.toLocaleDateString("nl-BE", { dateStyle: "long", timeZone: "Europe/Brussels" });
  }

  function createSafeLink(value) {
    if (typeof value !== "string") return null;
    try {
      const url = new URL(value);
      if (url.protocol !== "http:" && url.protocol !== "https:") return null;
      if (url.username || url.password) return null;
      const link = document.createElement("a");
      link.href = url.toString();
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.referrerPolicy = "no-referrer";
      link.textContent = url.toString();
      return link;
    } catch {
      return null;
    }
  }

  function appendScalar(parent, value, options) {
    if (options?.url) {
      const link = createSafeLink(value);
      if (link) {
        parent.appendChild(link);
        return;
      }
    }
    const text = document.createElement("span");
    text.textContent = options?.date ? formatDate(value) : displayValue(value);
    parent.appendChild(text);
  }

  function appendValue(parent, value, options) {
    if (Array.isArray(value)) {
      const list = document.createElement("ul");
      list.className = "admin-briefing-tags";
      value.forEach((item) => {
        if (!hasValue(item)) return;
        const listItem = document.createElement("li");
        listItem.textContent = displayValue(item);
        list.appendChild(listItem);
      });
      parent.appendChild(list);
      return;
    }
    appendScalar(parent, value, options);
  }

  function createDetail(label, value, options) {
    if (!hasValue(value)) return null;
    const row = document.createElement("div");
    const term = document.createElement("dt");
    const description = document.createElement("dd");
    term.textContent = label;
    appendValue(description, value, options);
    row.append(term, description);
    return row;
  }

  function addDetail(list, label, value, options) {
    const row = createDetail(label, value, options);
    if (row) list.appendChild(row);
  }

  function addObjectDetails(list, object, fields) {
    if (!object || typeof object !== "object" || Array.isArray(object)) return;
    fields.forEach(([label, key]) => addDetail(list, label, object[key]));
  }

  function createSection(title, details) {
    const list = document.createElement("dl");
    list.className = "admin-briefing-details";
    details(list);
    if (!list.children.length) return null;

    const section = document.createElement("section");
    section.className = "admin-briefing-section";
    const heading = document.createElement("h2");
    heading.textContent = title;
    section.append(heading, list);
    return section;
  }

  function appendSection(title, details) {
    const section = createSection(title, details);
    if (section) sectionsNode.appendChild(section);
  }

  function groupReportColumns() {
    const sections = Array.from(sectionsNode.children);
    if (sections.length < 2) return;
    const firstColumn = document.createElement("div");
    const secondColumn = document.createElement("div");
    const splitIndex = Math.ceil(sections.length / 2);
    firstColumn.className = "admin-briefing-column";
    secondColumn.className = "admin-briefing-column";
    sections.forEach((section, index) => {
      (index < splitIndex ? firstColumn : secondColumn).appendChild(section);
    });
    sectionsNode.replaceChildren(firstColumn, secondColumn);
  }

  function renderBriefing(payload) {
    if (
      !isRecord(payload) || payload.ok !== true || !isRecord(payload.intake) ||
      payload.intake.status !== "submitted" || !isRecord(payload.request) || !isRecord(payload.data) ||
      (payload.application !== undefined && (!isRecord(payload.application) || !isRecord(payload.application.commercial)))
    ) {
      showState(technicalError);
      return;
    }

    const request = payload.request;
    const data = payload.data;
    const application = isRecord(payload.application) ? payload.application : null;
    const submittedAt = payload.intake.submitted_at;
    const isBusiness = request.customer_type === "business";
    const billingAddress = isBusiness
      ? [request.billing_address, [request.billing_postal_code, request.billing_city].filter(Boolean).join(" "), request.billing_country].filter(Boolean).join(", ")
      : null;
    const vatValidationStatus = request.vat_validation_status === "valid"
      ? `Geverifieerd${request.vat_validated_at ? ` op ${new Date(request.vat_validated_at).toLocaleDateString("nl-BE")}` : ""}`
      : request.vat_validation_status === "invalid"
      ? "Niet als geldig bevestigd"
      : request.vat_validation_status === "unavailable"
      ? "Controle tijdelijk niet beschikbaar; later opnieuw controleren"
      : "Niet gecontroleerd";
    clientNode.textContent = request.company ? `${request.company} · ${request.name}` : request.name || "Onbekende klant";
    const legacyReference = request.id ? `Legacy #${String(request.id).slice(0, 8).toUpperCase()}` : "Legacy aanvraag";
    applicationNode.textContent = application?.applicationReference || legacyReference;
    referenceNode.textContent = application?.applicationReference || legacyReference;
    submittedNode.textContent = formatDateTime(submittedAt);
    typeNode.textContent = displayValue(request.website_type) || "Niet opgegeven";
    sectionsNode.replaceChildren();

    if (application) appendSection("Application", (list) => {
      const euro = new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR" });
      addDetail(list, "Aanvraagnummer", application.applicationReference);
      addDetail(list, "Ingediend", formatDateTime(application.submittedAt));
      addDetail(list, "Status", "Definitief ingediend");
      addDetail(list, "Pakket", application.commercial.packageLabel);
      addDetail(list, "Budget", application.commercial.budgetLabel);
      addDetail(list, "Indicatief projectminimum", `${euro.format(application.commercial.knownMinimumMinor / 100)} excl. btw`);
      addDetail(list, "Budget Guard", application.commercial.budgetStatus);
      addDetail(list, "Vervolgservice", (application.commercial.recurringServices || []).map((service) => `${service.label}: ${euro.format(service.amountMinor / 100)} per maand excl. btw`));
    });

    appendSection("Klant & aanvraag", (list) => {
      addDetail(list, "Naam contactpersoon", request.name);
      if (isBusiness) {
        addDetail(list, "Bedrijfsnaam", request.company);
        addDetail(list, "Ondernemingsnummer", request.enterprise_number);
        addDetail(list, "Ondernemingsnummerstatus", request.enterprise_validation_status === "format_valid_not_externally_verified" ? "Formaat geldig; niet extern geverifieerd" : "Niet gecontroleerd");
        addDetail(list, "BTW-nummer", request.vat_number);
        if (request.vat_number) addDetail(list, "BTW-validatiestatus", vatValidationStatus);
        addDetail(list, "Facturatieadres", billingAddress);
        addDetail(list, "Facturatie-e-mail", request.billing_email || request.email);
      }
      addDetail(list, "Contact-e-mail", request.email);
      addDetail(list, "Telefoon", request.phone);
      addDetail(list, "Website type", request.website_type);
      addDetail(list, "Oorspronkelijke timing", request.timing);
      addDetail(list, "Oorspronkelijke budgetcategorie", request.budget);
      addDetail(list, "Aanvraagreferentie", application?.applicationReference || legacyReference);
    });

    appendSection("Bedrijf & doelgroep", (list) => {
      addDetail(list, "Bedrijfsomschrijving", data.business_description);
      addDetail(list, "Doelgroep", data.target_audience);
      addDetail(list, "Bestaande website", data.has_existing_website);
      addDetail(list, "Website URL", data.existing_website_url, { url: true });
      addDetail(list, "Te behouden", data.elements_to_keep);
      addDetail(list, "Verbeterpunten", data.improvement_areas);
    });

    appendSection("Doelen", (list) => {
      addDetail(list, "Websitedoelen", data.website_goals);
      addDetail(list, "Belangrijkste conversieactie", data.primary_conversion_goal);
    });

    appendSection("Pagina’s & functies", (list) => {
      addDetail(list, "Gewenste pagina’s", data.requested_pages);
      addDetail(list, "Andere pagina’s", data.other_pages);
      addDetail(list, "Functies", data.requested_features);
      addDetail(list, "Webshop", data.shop_required);
      if (data.shop_required === true) addObjectDetails(list, data.shop_details, [
        ["Aantal producten", "approx_product_count"], ["Categorieën", "categories"],
        ["Online betalen", "online_payments"], ["Verzending", "shipping"],
        ["Afhalen", "pickup"], ["Bestaande catalogus", "existing_catalog"]
      ]);
      addDetail(list, "Reservaties of afspraken", data.booking_required);
      if (data.booking_required === true) addObjectDetails(list, data.booking_details, [
        ["Type reservatie", "type"], ["Bestaand systeem", "existing_system"],
        ["Naam bestaand systeem", "existing_system_name"], ["Kalenderkoppeling", "calendar_integration"]
      ]);
      addDetail(list, "Talen", data.languages);
    });

    appendSection("Design & branding", (list) => {
      addDetail(list, "Stijlen", data.design_styles);
      addDetail(list, "Huisstijlstatus", data.brand_status);
      addDetail(list, "Logostatus", data.logo_status);
      addDetail(list, "Kleuren", data.brand_colors);
      addDetail(list, "Inspiratie", data.inspiration_sites);
      addDetail(list, "Wat niet aanspreekt", data.disliked_styles);
    });

    appendSection("Content & media", (list) => {
      addDetail(list, "Tekststatus", data.content_status);
      addDetail(list, "Beeldstatus", data.image_status);
      addDetail(list, "Gewenste beeldondersteuning", data.image_support);
    });

    appendSection("Domein & hosting", (list) => {
      addDetail(list, "Domeinstatus", data.domain_status);
      addDetail(list, "Domeinnaam", data.domain_name);
      addDetail(list, "Hostingstatus", data.hosting_status);
      addDetail(list, "Gewenste hostinghulp", data.hosting_support);
      addDetail(list, "Onderhoud", data.maintenance_interest);
    });

    appendSection("SEO & integraties", (list) => {
      addDetail(list, "SEO-prioriteit", data.seo_priority);
      addDetail(list, "Zoekwoorden", data.seo_keywords);
      addDetail(list, "Sociale kanalen", data.social_channels);
      addDetail(list, "Integraties", data.integrations);
    });

    appendSection("Planning & budget", (list) => {
      addDetail(list, "Deadline", data.deadline_date, { date: true });
      addDetail(list, "Reden deadline", data.deadline_reason);
      addDetail(list, "Budget bevestigd", data.budget_confirmed);
      addDetail(list, "Bijgewerkte budgetcategorie", data.budget_update_category);
      addDetail(list, "Budgetnotities", data.budget_notes);
    });

    appendSection("Prioriteiten & opmerkingen", (list) => {
      addDetail(list, "Prioriteiten", data.priorities);
      addDetail(list, "Aanvullende opmerkingen", data.additional_notes);
    });

    appendSection("Operationele scopedetails", (list) => {
      addObjectDetails(list, data.page_scope_details, Object.keys(data.page_scope_details || {}).map((key) => [key.replaceAll("_", " "), key]));
      addObjectDetails(list, data.quote_form_details, Object.keys(data.quote_form_details || {}).map((key) => [key.replaceAll("_", " "), key]));
      addObjectDetails(list, data.multilingual_details, Object.keys(data.multilingual_details || {}).map((key) => [key.replaceAll("_", " "), key]));
      addObjectDetails(list, data.download_details, Object.keys(data.download_details || {}).map((key) => [key.replaceAll("_", " "), key]));
      addObjectDetails(list, data.newsletter_details, Object.keys(data.newsletter_details || {}).map((key) => [key.replaceAll("_", " "), key]));
      addObjectDetails(list, data.content_media_details, Object.keys(data.content_media_details || {}).map((key) => [key.replaceAll("_", " "), key]));
      addObjectDetails(list, data.hosting_maintenance_details, Object.keys(data.hosting_maintenance_details || {}).map((key) => [key.replaceAll("_", " "), key]));
      addObjectDetails(list, data.seo_details, Object.keys(data.seo_details || {}).map((key) => [key.replaceAll("_", " "), key]));
      addObjectDetails(list, data.deadline_details, Object.keys(data.deadline_details || {}).map((key) => [key.replaceAll("_", " "), key]));
    });

    appendSection("Bevestiging", (list) => {
      addDetail(list, "Informatie bevestigd", data.confirmation);
      addDetail(list, "Definitief ingediend", formatDateTime(submittedAt));
    });

    groupReportColumns();

    hideStates();
    workspace.hidden = false;
  }

  async function loadBriefing() {
    if (!capability) {
      showState(unavailable);
      return;
    }
    if (!endpoint) {
      showState(technicalError);
      return;
    }

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        cache: "no-store",
        referrerPolicy: "no-referrer",
        body: JSON.stringify({ action: "inspect_submitted_intake_admin", token: capability })
      });
      const payload = await response.json();
      if (response.status === 401 || payload?.code === "INVALID_ADMIN_CAPABILITY") {
        showState(unavailable);
        return;
      }
      if (!response.ok) {
        showState(technicalError);
        return;
      }
      renderBriefing(payload);
    } catch {
      showState(technicalError);
    }
  }

  loadBriefing();
})();
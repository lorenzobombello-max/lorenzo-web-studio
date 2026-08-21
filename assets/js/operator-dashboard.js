import { callCommercialOperator } from "./operator-auth-core.mjs";

const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REQUEST_KINDS = new Set(["website", "slimme_documentenflow"]);
const PRODUCT_FILTERS = new Set(["all", ...REQUEST_KINDS]);
const WEBSITE_DOSSIER_IDS = Object.freeze([
  "pricingDossier", "projectDossier", "quotationDossier", "documentsDossier",
  "paymentDossier", "workflowDossier", "historyDossier"
]);
const PACKAGE_LABELS = Object.freeze({ starter_v1: "Starter", professional_v1: "Professional", professional_v2: "Professional" });
const STATE_LABELS = Object.freeze({
  QUOTE_ACCEPTED: "Offerte geaccepteerd",
  M1_PAYMENT_PENDING: "Mijlpaal 1 betaling verwacht",
  M1_PAYMENT_RECEIVED: "Mijlpaal 1 ontvangen",
  PROJECT_RELEASED: "Project vrijgegeven",
  PROJECT_IN_PROGRESS: "Project in uitvoering",
  PREVIEW_READY: "Preview gereed",
  FINAL_PAYMENT_PENDING: "Finale betaling verwacht",
  DELIVERED: "Opgeleverd",
  ARCHIVED: "Gearchiveerd"
});

export function applicationReferenceFromUrl(url) {
  const value = new URL(url).searchParams.get("application");
  return value && APPLICATION_REFERENCE.test(value) ? value : null;
}

export function canPromoteApplication(detail) {
  return Boolean(detail?.request_kind === "website" && detail.acceptance && !detail.project);
}

export function applicationsForFilter(applications, filter) {
  if (!Array.isArray(applications) || !PRODUCT_FILTERS.has(filter)) return [];
  return applications.filter((application) => REQUEST_KINDS.has(application?.request_kind)
    && (filter === "all" || application.request_kind === filter));
}

export function emptyStateForFilter(filter) {
  if (filter === "website") return "Geen Website-aanvragen.";
  if (filter === "slimme_documentenflow") return "Geen Slimme Documentenflow-aanvragen.";
  return "Geen ingediende aanvragen.";
}

export function selectionFallsOutsideFilter(application, filter) {
  return Boolean(application && applicationsForFilter([application], filter).length === 0);
}

export function applyDetailVisibility(requestKind, nodes) {
  if (requestKind === null) {
    nodes.detail.hidden = true;
    nodes.detailEmpty.hidden = false;
    nodes.promote.hidden = true;
    nodes.promote.disabled = false;
    for (const section of nodes.dossierSections) section.hidden = true;
    for (const row of nodes.websiteDetailRows) row.hidden = true;
    nodes.sdfDetailNotice.hidden = true;
    return;
  }
  if (!REQUEST_KINDS.has(requestKind)) throw new Error("UNSUPPORTED_REQUEST_KIND");
  const isWebsite = requestKind === "website";
  nodes.detailEmpty.hidden = true;
  nodes.detail.hidden = false;
  nodes.promote.hidden = true;
  for (const section of nodes.dossierSections) section.hidden = false;
  for (const section of nodes.websiteDossierSections) section.hidden = !isWebsite;
  for (const row of nodes.websiteDetailRows) row.hidden = !isWebsite;
  nodes.sdfDetailNotice.hidden = isWebsite;
}

function setText(id, value) {
  const element = document.getElementById(id);
  if (element) element.textContent = value ?? "-";
}

function badge(value, tone) {
  const element = document.createElement("span");
  element.className = `badge${tone ? ` badge--${tone}` : ""}`;
  element.textContent = value;
  return element;
}

function formatDate(value) {
  return value ? new Intl.DateTimeFormat("nl-BE", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "-";
}

function formatMoney(value) {
  return Number.isSafeInteger(value)
    ? new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR" }).format(value / 100)
    : "-";
}

function optionalDisplay(value) {
  return value === null || value === undefined || value === "" ? "-" : String(value);
}

export function customerCorePresentation(application) {
  return {
    detailCustomerType: optionalDisplay(application?.customer_type),
    detailCustomerName: optionalDisplay(application?.name),
    detailCompany: optionalDisplay(application?.company),
    detailEmail: optionalDisplay(application?.email),
    detailPhone: optionalDisplay(application?.phone),
    detailEnterpriseNumber: optionalDisplay(application?.enterprise_number),
    detailEnterpriseValidation: optionalDisplay(application?.enterprise_validation_status),
    detailVatNumber: optionalDisplay(application?.vat_number),
    detailVatValidation: optionalDisplay(application?.vat_validation_status),
    detailVatValidatedAt: application?.vat_validated_at ? formatDate(application.vat_validated_at) : "-",
    detailBillingAddress: optionalDisplay(application?.billing_address),
    detailBillingPostalCode: optionalDisplay(application?.billing_postal_code),
    detailBillingCity: optionalDisplay(application?.billing_city),
    detailBillingCountry: optionalDisplay(application?.billing_country),
    detailBillingEmail: optionalDisplay(application?.billing_email),
  };
}

export async function startOperatorDashboard({ client, functionsBaseUrl, callOperator = callCommercialOperator }) {
  const list = document.getElementById("applicationList");
  const empty = document.getElementById("applicationEmpty");
  const listMessage = document.getElementById("applicationListMessage");
  const detail = document.getElementById("applicationDetail");
  const detailEmpty = document.getElementById("applicationDetailEmpty");
  const detailMessage = document.getElementById("applicationDetailMessage");
  const promote = document.getElementById("promoteApplication");
  const confirmation = document.getElementById("promotionDialog");
  const dossierSections = Array.from(document.querySelectorAll(".dossier-section"));
  const websiteDossierSections = WEBSITE_DOSSIER_IDS.map((id) => document.getElementById(id));
  const websiteDetailRows = Array.from(document.querySelectorAll("[data-website-detail]"));
  const filterButtons = Array.from(document.querySelectorAll("[data-product-filter]"));
  const sdfDetailNotice = document.getElementById("sdfDetailNotice");
  let applications = [];
  let activeFilter = "all";
  let selectedLocator = applicationLocatorFromUrl(window.location.href);
  let selectedDetail = null;
  let detailRequestId = 0;

  async function invoke(input) {
    const response = await callOperator(client, functionsBaseUrl, input);
    if (response.status >= 400 || !response.body?.ok) throw new Error(response.body?.code || "OPERATOR_REQUEST_FAILED");
    return response.body.result;
  }

  function updateLocation(locator) {
    const url = new URL(window.location.href);
    url.searchParams.delete("application");
    url.searchParams.delete("request");
    if (locator?.application_reference) url.searchParams.set("application", locator.application_reference);
    else if (locator?.quote_request_id) url.searchParams.set("request", locator.quote_request_id);
    window.history.replaceState(null, "", `${url.pathname}${url.search}`);
  }

  function clearDetail() {
    detailRequestId += 1;
    selectedLocator = null;
    selectedDetail = null;
    applyDetailVisibility(null, { detail, detailEmpty, promote, dossierSections, websiteDossierSections, websiteDetailRows, sdfDetailNotice });
    detailMessage.textContent = "";
    updateLocation(null);
  }

  function renderRecurringServices(pricing) {
    const list = document.getElementById("recurringPricingList");
    const emptyMessage = document.getElementById("recurringPricingEmpty");
    list.replaceChildren();
    const services = Array.isArray(pricing?.recurring_services) ? pricing.recurring_services : [];
    emptyMessage.textContent = services.length ? "" : "Geen Care- of Care+-dienst vastgelegd.";
    for (const service of services) {
      const label = service.productId === "care_plus" ? "Care+" : service.productId === "care" ? "Care" : service.productId;
      appendStatusItem(list, label || "Terugkerende dienst", "Per maand", formatMoney(service.amountMinor), "green");
    }
  }

  function renderDocuments(application, project) {
    const list = document.getElementById("documentStatusList");
    list.replaceChildren();
    const quotation = application.quotation;
    if (quotation) {
      appendStatusItem(list, quotation.quotation_number || "Offerte zonder nummer", `Status: ${quotation.issuance_status || "Niet uitgegeven"}`, "METADATA AVAILABLE", "green");
      if (quotation.docx_sha256) appendStatusItem(list, "Offerte-uitgiftebewijs", `${quotation.docx_bytes || 0} bytes · hashmetadata vastgelegd`, "ISSUED EVIDENCE AVAILABLE", "green");
      if (quotation.acceptance_id) appendStatusItem(list, "Acceptatiebewijs", formatDate(quotation.accepted_at), "ACCEPTED EVIDENCE AVAILABLE", "green");
    } else {
      appendStatusItem(list, "Offerte", "Geen authoritatieve offertemetadata aanwezig", "NOT AVAILABLE", "");
    }
    for (const document of project?.documents || []) {
      appendStatusItem(list, document.commercial_reference, `${document.document_type} · ${document.workflow_state}`, "METADATA ONLY", "amber");
    }
    appendStatusItem(list, "Binair archief", "Geen downloadbare opslaglocatie geregistreerd", "NOT YET AVAILABLE", "amber");
  }

  function renderPayment(project) {
    setText("detailM1", formatMoney(project?.m1_minor));
    setText("detailM2", formatMoney(project?.m2_minor));
    setText("detailM3", formatMoney(project?.m3_minor));
    const list = document.getElementById("obligationList");
    const emptyMessage = document.getElementById("obligationEmpty");
    list.replaceChildren();
    const obligations = project?.obligations || [];
    emptyMessage.textContent = project
      ? obligations.length ? "" : "Nog geen betalingsverplichtingen voorbereid; er is geen betalingsbewijs of vervaldatum vastgelegd."
      : "Betalingssamenvatting wordt beschikbaar nadat een project bestaat.";
    for (const obligation of obligations) {
      const evidenceCount = Number(obligation.evidence_count) || 0;
      const reconciledCount = Number(obligation.reconciled_evidence_count) || 0;
      const reconciliation = evidenceCount === 0
        ? "NO EVIDENCE"
        : `${reconciledCount}/${evidenceCount} gereconcilieerd${obligation.latest_reconciliation_status ? ` · laatste: ${obligation.latest_reconciliation_status}` : ""}`;
      appendStatusItem(list, obligation.milestone ? `Mijlpaal ${obligation.milestone}` : obligation.obligation_type, `${formatMoney(obligation.amount_minor)} · ${obligation.status}`, reconciliation, evidenceCount > 0 && reconciledCount === evidenceCount ? "green" : "amber");
    }
  }

  function renderTimeline(project) {
    const list = document.getElementById("auditTimeline");
    const emptyMessage = document.getElementById("auditTimelineEmpty");
    list.replaceChildren();
    const events = project?.timeline || [];
    emptyMessage.textContent = events.length ? "" : "Nog geen workflow- of auditgebeurtenissen beschikbaar.";
    for (const event of events) {
      const item = document.createElement("li");
      const time = document.createElement("time");
      const content = document.createElement("div");
      const action = document.createElement("strong");
      const context = document.createElement("span");
      time.dateTime = event.occurred_at;
      time.textContent = formatDate(event.occurred_at);
      action.textContent = event.action || "Gebeurtenis";
      context.textContent = event.previous_state && event.new_state
        ? `${stateLabel(event.previous_state)} → ${stateLabel(event.new_state)}`
        : event.actor || event.evidence_reference || "Servergebeurtenis";
      content.append(action, context);
      item.append(time, content);
      list.append(item);
    }
  }

  function renderWorkflow(state, hasAcceptance, hasProject) {
    const current = hasProject ? stateLabel(state) : hasAcceptance ? "Offerte geaccepteerd, project nog niet aangemaakt" : "Aanvraag ingediend";
    const next = hasProject
      ? nextWorkflowStage(state)
      : hasAcceptance
      ? { label: "Project aanmaken", availability: "AVAILABLE NOW", tone: "amber" }
      : { label: "Offertevoorbereiding", availability: "LOCKED", tone: "red" };
    setText("workflowCurrentState", current);
    setText("workflowNextStage", next.label);
    setBadge("workflowAvailability", next.availability, next.tone);
  }

  function renderProjectDossier(project) {
    const application = selectedDetail;
    setText("detailProject", project?.project_id || application?.project?.project_id || "Nog niet aangemaakt");
    setText("detailProjectCreatedAt", formatDate(project?.created_at || application?.project?.created_at));
    setText("detailProjectRevision", project?.revision ?? application?.project?.revision ?? "-");
    setText("detailTotal", formatMoney(project?.accepted_total_minor ?? application?.project?.accepted_total_minor));
    setBadge("projectStateBadge", project ? stateLabel(project.current_state) : "GEEN PROJECT", project ? "green" : "amber");
    renderPayment(project);
    renderDocuments(application, project);
    renderWorkflow(project?.current_state, Boolean(application?.acceptance), Boolean(project));
    renderTimeline(project);
  }

  function renderDetail(application) {
    if (!REQUEST_KINDS.has(application?.request_kind)) throw new Error("UNSUPPORTED_REQUEST_KIND");
    const isWebsite = application.request_kind === "website";
    selectedDetail = application;
    applyDetailVisibility(application.request_kind, { detail, detailEmpty, promote, dossierSections, websiteDossierSections, websiteDetailRows, sdfDetailNotice });
    setText("detailReference", application.application_reference || `Oudere aanvraag · ${application.quote_request_id}`);
    setText("detailName", application.name);
    setText("detailRequestKind", isWebsite ? "Website" : "Slimme Documentenflow");
    for (const [id, value] of Object.entries(customerCorePresentation(application))) setText(id, value);
    setText("detailWebsiteType", application.website_type);
    setText("detailBudget", application.budget);
    setText("detailTiming", application.timing);
    setText("detailDescription", application.description);
    setText("detailIntakeStatus", application.intake_status || "Niet beschikbaar");
    setText("detailSubmittedAt", formatDate(application.submitted_at));
    promote.hidden = true;
    if (!isWebsite) return;
    setText("detailPackage", PACKAGE_LABELS[application.pricing?.selected_package] || application.pricing?.selected_package || "Niet vastgelegd");
    setText("detailIndicativeTotal", formatMoney(application.pricing?.known_minimum_minor));
    setText("detailBudgetGuard", application.pricing?.budget_guard_status || "Niet beschikbaar");
    setText("detailPricingSnapshot", application.pricing?.snapshot_id || "Niet beschikbaar");
    renderRecurringServices(application.pricing);
    setText("detailQuotation", application.quotation?.quotation_number || "Nog niet uitgegeven");
    setText("detailIssuedAt", formatDate(application.quotation?.issued_at));
    setText("detailAcceptanceState", application.acceptance ? "Geaccepteerd" : "Niet geaccepteerd");
    setText("detailAcceptedAt", formatDate(application.acceptance?.accepted_at));
    setText("detailQuotationTotal", formatMoney(application.quotation?.approved_total_minor));
    setText("detailQuotationTemplate", application.quotation?.template_id ? `${application.quotation.template_id} · ${application.quotation.template_version}` : "Niet beschikbaar");
    setBadge("quotationStateBadge", application.acceptance ? "ACCEPTED" : application.quotation?.issuance_status || "NOT ISSUED", application.acceptance ? "green" : "amber");
    promote.hidden = !canPromoteApplication(application);
    renderProjectDossier(null);
  }

  async function loadDetail(locator) {
    const requestId = ++detailRequestId;
    selectedDetail = null;
    promote.hidden = true;
    detailMessage.textContent = "Aanvraag wordt geladen.";
    try {
      const application = await invoke({ action: "get_application_detail", ...locator });
      if (requestId !== detailRequestId) return;
      if (selectionFallsOutsideFilter(application, activeFilter)) throw new Error("FILTERED_REQUEST_KIND");
      renderDetail(application);
      selectedLocator = locator;
      updateLocation(locator);
      if (application.request_kind === "website" && application.project?.project_id) {
        detailMessage.textContent = "Projectdossier wordt geladen.";
        const project = await invoke({ action: "get_project_dossier", project_id: application.project.project_id });
        if (requestId !== detailRequestId) return;
        renderProjectDossier(project);
      }
      detailMessage.textContent = "";
    } catch {
      if (requestId !== detailRequestId) return;
      if (!selectedDetail) {
        detail.hidden = true;
        detailEmpty.hidden = false;
      }
      detailMessage.textContent = selectedDetail ? "Het projectdossier kon niet worden geladen." : "De aanvraag kon niet worden geladen.";
    }
  }

  function renderList(applications) {
    list.replaceChildren();
    empty.hidden = applications.length > 0;
    for (const application of applications) {
      const item = document.createElement("li");
      const button = document.createElement("button");
      button.type = "button";
      button.className = "application-list__button";
      const identity = document.createElement("span");
      const name = document.createElement("strong");
      name.textContent = application.company || application.name;
      const reference = document.createElement("small");
      reference.textContent = `${application.application_reference || `Oudere aanvraag · ${application.quote_request_id}`} · ${formatDate(application.submitted_at)}`;
      identity.append(name, reference);
      const state = application.request_kind === "slimme_documentenflow"
        ? badge("Documentenflow")
        : application.project_state
        ? badge(application.project_state, "green")
        : application.acceptance_id
        ? badge("Geaccepteerd", "amber")
        : badge("Ingediend");
      button.append(identity, state);
      const locator = application.application_reference
        ? { application_reference: application.application_reference }
        : { quote_request_id: application.quote_request_id };
      if (locatorMatchesApplication(selectedLocator, application)) button.setAttribute("aria-current", "true");
      button.addEventListener("click", ()=>{
        for (const candidate of list.querySelectorAll("[aria-current]")) candidate.removeAttribute("aria-current");
        button.setAttribute("aria-current", "true");
        loadDetail(locator);
      });
      item.append(button);
      list.append(item);
    }
  }

  async function loadList() {
    listMessage.textContent = "Aanvragen worden geladen.";
    try {
      applications = applicationsForFilter(await invoke({ action: "list_applications", limit: 100, offset: 0 }), "all");
      renderList(applicationsForFilter(applications, activeFilter));
      empty.textContent = emptyStateForFilter(activeFilter);
      listMessage.textContent = "";
      if (selectedLocator) {
        const selectedApplication = applications.find((application) => locatorMatchesApplication(selectedLocator, application));
        if (selectedApplication && !selectionFallsOutsideFilter(selectedApplication, activeFilter)) {
          await loadDetail(selectedLocator);
        } else clearDetail();
      }
    } catch {
      listMessage.textContent = "De aanvragen konden niet worden geladen.";
    }
  }

  for (const button of filterButtons) {
    button.addEventListener("click", ()=>{
      const nextFilter = button.dataset.productFilter;
      if (!PRODUCT_FILTERS.has(nextFilter) || nextFilter === activeFilter) return;
      activeFilter = nextFilter;
      for (const candidate of filterButtons) candidate.setAttribute("aria-pressed", String(candidate === button));
      clearDetail();
      renderList(applicationsForFilter(applications, activeFilter));
      empty.textContent = emptyStateForFilter(activeFilter);
    });
  }

  promote.addEventListener("click", ()=>confirmation.showModal());
  confirmation.addEventListener("close", async ()=>{
    if (confirmation.returnValue !== "confirm" || !canPromoteApplication(selectedDetail)) return;
    promote.disabled = true;
    detailMessage.textContent = "Project wordt aangemaakt.";
    try {
      await invoke({ action: "promote_accepted_application", ...selectedLocator, idempotency_key: crypto.randomUUID() });
      await loadList();
      detailMessage.textContent = "Project is gekoppeld.";
    } catch {
      detailMessage.textContent = "Het project kon niet worden aangemaakt.";
    } finally {
      promote.disabled = false;
    }
  });

  await loadList();
}

export function applicationLocatorFromUrl(url) {
  const parsed = new URL(url);
  const reference = parsed.searchParams.get("application");
  if (reference && APPLICATION_REFERENCE.test(reference)) return { application_reference: reference };
  const quoteRequestId = parsed.searchParams.get("request");
  return quoteRequestId && UUID.test(quoteRequestId) ? { quote_request_id: quoteRequestId } : null;
}

export function nextWorkflowStage(state) {
  if (state === "QUOTE_ACCEPTED") return { label: "Mijlpaal 1 voorbereiden", availability: "AVAILABLE NOW", tone: "amber" };
  if (state === "ARCHIVED") return { label: "Dossier afgerond", availability: "COMPLETED", tone: "green" };
  if (state === "M1_PAYMENT_PENDING") return { label: "Betaling verifiëren", availability: "LOCKED", tone: "red" };
  if (state && STATE_LABELS[state]) return { label: "Volgende serverfase", availability: "LOCKED", tone: "red" };
  return { label: "Niet bepaald", availability: "NOT YET IMPLEMENTED", tone: "" };
}

function stateLabel(value) {
  return STATE_LABELS[value] || value || "Niet beschikbaar";
}

function setBadge(id, value, tone) {
  const element = document.getElementById(id);
  if (!element) return;
  element.className = `badge${tone ? ` badge--${tone}` : ""}`;
  element.textContent = value;
}

function appendStatusItem(list, title, detail, status, tone) {
  const item = document.createElement("li");
  const identity = document.createElement("div");
  const heading = document.createElement("strong");
  const description = document.createElement("small");
  heading.textContent = title;
  description.textContent = detail;
  identity.append(heading, description);
  item.append(identity, badge(status, tone));
  list.append(item);
}

function locatorMatchesApplication(locator, application) {
  return Boolean(locator?.application_reference
    ? locator.application_reference === application?.application_reference
    : locator?.quote_request_id === application?.quote_request_id);
}
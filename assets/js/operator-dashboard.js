import { callCommercialOperator } from "./operator-auth-core.mjs";

const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REQUEST_KINDS = new Set(["website", "slimme_documentenflow"]);
const PRODUCT_FILTERS = new Set(["all", ...REQUEST_KINDS]);
const WEBSITE_DOSSIER_IDS = Object.freeze([
  "lifecycleDossier", "pricingDossier", "projectDossier", "quotationDossier", "documentsDossier",
  "paymentDossier", "workflowDossier", "historyDossier"
]);
const SDF_DOSSIER_IDS = Object.freeze(["sdfPricingDossier", "sdfQuotationDossier", "sdfM1InvoiceDossier", "sdfProjectDossier"]);
const PACKAGE_LABELS = Object.freeze({ starter_v1: "Starter", professional_v1: "Professional", professional_v2: "Professional" });
const SDF_PACKAGE_LABELS = Object.freeze({ start: "START", groei: "GROEI", maatwerk: "MAATWERK" });
const LIFECYCLE_PRESENTATION = Object.freeze({
  ACTIVE: Object.freeze({ label: "Actief", tone: "green", actions: Object.freeze(["interrupt_intake", "cancel_intake"]) }),
  INTERRUPTED: Object.freeze({ label: "Onderbroken", tone: "amber", actions: Object.freeze(["resume_intake", "cancel_intake"]) }),
  EXPIRED: Object.freeze({ label: "Verlopen", tone: "red", actions: Object.freeze(["reactivate_intake"]) }),
  CANCELLED: Object.freeze({ label: "Geannuleerd", tone: "red", actions: Object.freeze([]) }),
});
const LIFECYCLE_ACTIONS = Object.freeze({
  interrupt_intake: Object.freeze({ label: "Onderbreken", title: "Intake onderbreken", description: "De klant kan deze intake niet gebruiken totdat een operator ze hervat." }),
  resume_intake: Object.freeze({ label: "Hervatten", title: "Intake hervatten", description: "De bestaande geldigheidstermijn blijft behouden." }),
  cancel_intake: Object.freeze({ label: "Definitief annuleren", title: "Intake definitief annuleren", description: "Annuleren is definitief voor deze intake en kan niet worden hervat." }),
  reactivate_intake: Object.freeze({ label: "Reactiveren", title: "Intake reactiveren", description: "De server start een nieuwe geldigheidstermijn van zeven dagen." }),
});
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

export function applicationIdentityPresentation(application) {
  const applicationReference = String(application?.application_reference || "");
  const quoteRequestId = String(application?.quote_request_id || "");
  if (APPLICATION_REFERENCE.test(applicationReference)) {
    return {
      visibleReference: applicationReference,
      locator: { application_reference: applicationReference },
    };
  }
  return {
    visibleReference: `Oudere aanvraag · ${quoteRequestId}`,
    locator: { quote_request_id: quoteRequestId },
  };
}

export function canPromoteApplication(detail) {
  return Boolean(detail?.request_kind === "website" && detail.acceptance && !detail.project);
}

export function intakeLifecyclePresentation(lifecycle) {
  const state = String(lifecycle?.effective_access || "");
  const presentation = LIFECYCLE_PRESENTATION[state];
  if (!presentation
      || !UUID.test(String(lifecycle?.intake_id || ""))
      || !Number.isSafeInteger(lifecycle?.lifecycle_revision)
      || lifecycle.lifecycle_revision < 0
      || !lifecycle?.access_token_expires_at) return null;
  return { state, ...presentation };
}

export function intakeLifecycleAction(action) {
  return LIFECYCLE_ACTIONS[action] || null;
}

export function buildIntakeLifecycleCommand(action, lifecycle, reason, idempotencyKey) {
  const presentation = intakeLifecyclePresentation(lifecycle);
  const normalizedReason = typeof reason === "string" ? reason.trim() : "";
  if (!presentation?.actions.includes(action)
      || !UUID.test(String(idempotencyKey || ""))
      || normalizedReason.length < 1
      || normalizedReason.length > 500) throw new Error("INVALID_LIFECYCLE_COMMAND");
  return {
    action,
    intake_id: lifecycle.intake_id,
    expected_revision: lifecycle.lifecycle_revision,
    idempotency_key: idempotencyKey,
    reason: normalizedReason,
  };
}

export function intakeLifecycleError(code) {
  if (code === "CONCURRENT_MODIFICATION") return { message: "Deze intake werd ondertussen gewijzigd. De gegevens worden opnieuw geladen.", refresh: true };
  if (code === "COMMAND_REJECTED" || code === "INVALID_INTAKE_LIFECYCLE_TRANSITION") return { message: "De status van deze intake is ondertussen gewijzigd. De gegevens worden opnieuw geladen.", refresh: true };
  if (code === "IDEMPOTENCY_CONFLICT") return { message: "Deze aanvraag conflicteert met een eerdere poging. De gegevens worden opnieuw geladen.", refresh: true };
  if (code === "INTAKE_NOT_FOUND" || code === "APPLICATION_NOT_FOUND") return { message: "Deze intake of aanvraag is niet meer beschikbaar.", refresh: true };
  if (["AUTHENTICATION_REQUIRED", "INVALID_JWT", "HUMAN_JWT_REQUIRED", "OPERATOR_NOT_AUTHORIZED", "INSUFFICIENT_PERMISSIONS"].includes(code)) {
    return { message: "Je sessie is verlopen of je hebt onvoldoende bevoegdheid voor deze actie.", refresh: false };
  }
  return { message: "De lifecycleactie kon niet worden uitgevoerd. Probeer het opnieuw.", refresh: false };
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
    for (const row of nodes.sdfDetailRows) row.hidden = true;
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
  for (const section of nodes.sdfDossierSections) section.hidden = isWebsite;
  for (const row of nodes.websiteDetailRows) row.hidden = !isWebsite;
  for (const row of nodes.sdfDetailRows) row.hidden = isWebsite;
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

export function sdfPackageLabel(value) {
  return SDF_PACKAGE_LABELS[value] || "Niet geregistreerd";
}

function formatSdfPrice(entry, recurring = false) {
  const amount = new Intl.NumberFormat("nl-BE", { maximumFractionDigits: 2 }).format(entry.amount_minor / 100);
  const prefix = entry.price_mode === "starting_at" ? "vanaf " : "";
  return `${prefix}€ ${amount} excl. btw${recurring ? " / maand" : ""}`;
}

export function sdfPricingPresentation(application) {
  if (application?.request_kind !== "slimme_documentenflow") return null;
  const unavailable = {
    package: sdfPackageLabel(application?.sdf_package),
    implementation: "Niet beschikbaar",
    recurring: "Niet beschikbaar",
  };
  const pricing = application?.sdf_pricing;
  const implementation = pricing?.implementation;
  const recurring = pricing?.recurring;
  const validMode = (entry) => entry?.price_mode === "fixed" || entry?.price_mode === "starting_at";
  if (!Object.hasOwn(SDF_PACKAGE_LABELS, application?.sdf_package)
      || pricing?.authority_version !== 1
      || pricing?.package !== application.sdf_package
      || pricing?.currency !== "EUR"
      || pricing?.vat_basis !== "exclusive"
      || !Number.isSafeInteger(implementation?.amount_minor)
      || implementation.amount_minor < 0
      || !validMode(implementation)
      || !Number.isSafeInteger(recurring?.amount_minor)
      || recurring.amount_minor < 0
      || !validMode(recurring)
      || recurring?.billing_period !== "month"
      || recurring?.commercial_package_price !== true
      || recurring?.active_recurring_obligation !== false) return unavailable;
  return {
    package: sdfPackageLabel(application.sdf_package),
    implementation: formatSdfPrice(implementation),
    recurring: formatSdfPrice(recurring, true),
  };
}

export function sdfQuotationPresentation(application) {
  if (application?.request_kind !== "slimme_documentenflow") return null;
  const unavailable = {
    quotationId: "Nog geen offerte",
    application: optionalDisplay(application?.application_reference || application?.quote_request_id),
    createdAt: "Niet beschikbaar",
    documentState: "Niet geregistreerd",
    quotationDate: "Niet beschikbaar",
    validUntil: "Niet beschikbaar",
    preparedAt: "Niet beschikbaar",
    documentReference: "Niet beschikbaar",
    documentHash: "Niet beschikbaar",
    acceptanceState: "Niet geregistreerd",
    acceptedAt: "Niet beschikbaar",
    acceptedDocument: "Niet beschikbaar",
    acceptedHash: "Niet beschikbaar",
  };
  const quotation = application?.sdf_quotation;
  if (!quotation) return unavailable;
  const document = quotation.document;
  const acceptance = quotation.acceptance;
  const validTimestamp = (value) => typeof value === "string" && !Number.isNaN(Date.parse(value));
  const validDate = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
  const validDocument = document === null || (
    document && validDate(document.quotation_date) && validDate(document.valid_until)
    && document.valid_until >= document.quotation_date
    && validTimestamp(document.prepared_at)
    && document.document_reference_present === true
    && document.document_sha256_present === true
    && !Object.hasOwn(document, "document_reference")
    && !Object.hasOwn(document, "document_sha256")
    && !Object.hasOwn(document, "status")
  );
  const validAcceptance = acceptance === null || (
    document !== null && acceptance && validTimestamp(acceptance.accepted_at)
    && acceptance.accepted_document_reference_present === true
    && acceptance.accepted_document_sha256_present === true
    && !Object.hasOwn(acceptance, "document_reference")
    && !Object.hasOwn(acceptance, "document_sha256")
    && !Object.hasOwn(acceptance, "status")
  );
  if (!UUID.test(quotation.quotation_id || "")
      || quotation.quote_request_id !== application.quote_request_id
      || quotation.application_reference !== (application.application_reference ?? null)
      || Object.hasOwn(quotation, "status")
      || !quotation.created_at
      || Number.isNaN(Date.parse(quotation.created_at))
      || !Object.hasOwn(quotation, "document")
      || !Object.hasOwn(quotation, "acceptance")
      || !validDocument
      || !validAcceptance) return unavailable;
  return {
    ...unavailable,
    quotationId: quotation.quotation_id,
    createdAt: formatDate(quotation.created_at),
    documentState: document ? "Geregistreerd" : "Niet geregistreerd",
    quotationDate: document ? formatDate(document.quotation_date) : "Niet beschikbaar",
    validUntil: document ? formatDate(document.valid_until) : "Niet beschikbaar",
    preparedAt: document ? formatDate(document.prepared_at) : "Niet beschikbaar",
    documentReference: document ? "Aanwezig" : "Niet beschikbaar",
    documentHash: document ? "Aanwezig" : "Niet beschikbaar",
    acceptanceState: acceptance ? "Geaccepteerd" : "Niet geregistreerd",
    acceptedAt: acceptance ? formatDate(acceptance.accepted_at) : "Niet beschikbaar",
    acceptedDocument: acceptance ? "Aanwezig" : "Niet beschikbaar",
    acceptedHash: acceptance ? "Aanwezig" : "Niet beschikbaar",
  };
}

export function sdfProjectPresentation(application) {
  if (application?.request_kind !== "slimme_documentenflow") return null;
  const unavailable = {
    projectId: "Nog geen project",
    product: "Slimme Documentenflow",
    application: optionalDisplay(application?.application_reference || application?.quote_request_id),
    customer: optionalDisplay(application?.name),
    package: sdfPackageLabel(application?.sdf_package),
    status: "Niet beschikbaar",
    operationalStatus: "Niet beschikbaar",
    createdAt: "Niet beschikbaar",
  };
  const project = application?.project;
  if (!project) return unavailable;
  if (!UUID.test(project.project_id || "")
      || project.request_kind !== "slimme_documentenflow"
      || project.quote_request_id !== application.quote_request_id
      || project.application_reference !== (application.application_reference ?? null)
      || project.customer_name !== application.name
      || project.sdf_package !== (application.sdf_package ?? null)
      || project.current_state != null
      || project.operational_status != null
      || !project.created_at
      || Number.isNaN(Date.parse(project.created_at))) return unavailable;
  return {
    ...unavailable,
    projectId: project.project_id,
    createdAt: formatDate(project.created_at),
  };
}

export function sdfM1InvoiceCandidatePresentation(application) {
  if (application?.request_kind !== "slimme_documentenflow") return null;
  const unavailable = {
    state: "Nog geen candidate",
    dossierReference: optionalDisplay(application?.application_reference),
    milestone: "Niet beschikbaar",
    percentage: "Niet beschikbaar",
    netAmount: "Niet beschikbaar",
    currency: "Niet beschikbaar",
    templateBinding: "Niet beschikbaar",
    invoiceNumber: "Niet toegewezen",
    fiscalAuthority: "Niet actief",
    issuance: "Geblokkeerd",
    preparedAt: "Niet beschikbaar",
  };
  const candidate = application?.sdf_m1_invoice_candidate;
  if (!candidate) return unavailable;
  if (!UUID.test(candidate.candidate_id || "")
      || candidate.candidate_state !== "PREPARED"
      || !APPLICATION_REFERENCE.test(candidate.application_reference || "")
      || candidate.application_reference !== application.application_reference
      || candidate.milestone_identity !== "M1"
      || candidate.percentage_basis_points !== 4000
      || candidate.currency !== "EUR"
      || !Number.isSafeInteger(candidate.net_amount_minor)
      || candidate.net_amount_minor < 0
      || candidate.template_binding_present !== true
      || candidate.invoice_number !== null
      || candidate.fiscal_authority_state !== "NOT_ACTIVE"
      || candidate.production_issuance_available !== false
      || !candidate.prepared_at
      || Number.isNaN(Date.parse(candidate.prepared_at))) return unavailable;
  return {
    state: "Voorbereid",
    dossierReference: candidate.application_reference,
    milestone: "M1",
    percentage: "40%",
    netAmount: formatMoney(candidate.net_amount_minor),
    currency: "EUR",
    templateBinding: "Aanwezig",
    invoiceNumber: "Niet toegewezen",
    fiscalAuthority: "Niet actief",
    issuance: "Geblokkeerd",
    preparedAt: formatDate(candidate.prepared_at),
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
  const lifecycleDossier = document.getElementById("lifecycleDossier");
  const lifecycleDossierTitle = document.getElementById("lifecycleDossierTitle");
  const lifecycleMessage = document.getElementById("lifecycleActionMessage");
  const lifecycleButtons = Array.from(document.querySelectorAll("[data-lifecycle-action]"));
  const lifecycleDialog = document.getElementById("lifecycleDialog");
  const lifecycleForm = document.getElementById("lifecycleForm");
  const lifecycleReason = document.getElementById("lifecycleReason");
  const lifecycleConfirm = document.getElementById("lifecycleConfirm");
  const lifecycleCancel = document.getElementById("lifecycleCancel");
  const dossierSections = Array.from(document.querySelectorAll(".dossier-section"));
  const websiteDossierSections = WEBSITE_DOSSIER_IDS.map((id) => document.getElementById(id));
  const sdfDossierSections = SDF_DOSSIER_IDS.map((id) => document.getElementById(id));
  const websiteDetailRows = Array.from(document.querySelectorAll("[data-website-detail]"));
  const sdfDetailRows = Array.from(document.querySelectorAll("[data-sdf-detail]"));
  const filterButtons = Array.from(document.querySelectorAll("[data-product-filter]"));
  const sdfDetailNotice = document.getElementById("sdfDetailNotice");
  let applications = [];
  let activeFilter = "all";
  let selectedLocator = applicationLocatorFromUrl(window.location.href);
  let selectedDetail = null;
  let detailRequestId = 0;
  let lifecycleBusy = false;
  let pendingLifecycleAction = null;

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
    applyDetailVisibility(null, { detail, detailEmpty, promote, dossierSections, websiteDossierSections, sdfDossierSections, websiteDetailRows, sdfDetailRows, sdfDetailNotice });
    detailMessage.textContent = "";
    lifecycleMessage.textContent = "";
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

  function renderIntakeLifecycle(lifecycle) {
    const presentation = intakeLifecyclePresentation(lifecycle);
    lifecycleDossier.hidden = !presentation;
    if (!presentation) {
      for (const button of lifecycleButtons) button.hidden = true;
      return;
    }
    setBadge("lifecycleStateBadge", presentation.label, presentation.tone);
    setText("detailLifecycleExpiresAt", formatDate(lifecycle.access_token_expires_at));
    setText("detailLifecycleRevision", lifecycle.lifecycle_revision);
    for (const button of lifecycleButtons) {
      button.hidden = !presentation.actions.includes(button.dataset.lifecycleAction);
      button.disabled = lifecycleBusy;
    }
  }

  function setLifecycleBusy(busy) {
    lifecycleBusy = busy;
    lifecycleConfirm.disabled = busy;
    for (const button of lifecycleButtons) button.disabled = busy;
  }

  function renderDetail(application) {
    if (!REQUEST_KINDS.has(application?.request_kind)) throw new Error("UNSUPPORTED_REQUEST_KIND");
    const isWebsite = application.request_kind === "website";
    selectedDetail = application;
    applyDetailVisibility(application.request_kind, { detail, detailEmpty, promote, dossierSections, websiteDossierSections, sdfDossierSections, websiteDetailRows, sdfDetailRows, sdfDetailNotice });
    setText("detailReference", applicationIdentityPresentation(application).visibleReference);
    setText("detailName", application.name);
    setText("detailRequestKind", isWebsite ? "Website" : "Slimme Documentenflow");
    setText("detailSdfPackage", sdfPackageLabel(application.sdf_package));
    const sdfPricing = sdfPricingPresentation(application);
    setText("detailSdfPricingPackage", sdfPricing?.package || "Niet beschikbaar");
    setText("detailSdfImplementationPrice", sdfPricing?.implementation || "Niet beschikbaar");
    setText("detailSdfRecurringPrice", sdfPricing?.recurring || "Niet beschikbaar");
    const sdfQuotation = sdfQuotationPresentation(application);
    setText("detailSdfQuotationId", sdfQuotation?.quotationId || "Nog geen offerte");
    setText("detailSdfQuotationApplication", sdfQuotation?.application || "Niet beschikbaar");
    setText("detailSdfQuotationCreatedAt", sdfQuotation?.createdAt || "Niet beschikbaar");
    setText("detailSdfQuotationDocumentState", sdfQuotation?.documentState || "Niet geregistreerd");
    setText("detailSdfQuotationDate", sdfQuotation?.quotationDate || "Niet beschikbaar");
    setText("detailSdfQuotationValidUntil", sdfQuotation?.validUntil || "Niet beschikbaar");
    setText("detailSdfQuotationPreparedAt", sdfQuotation?.preparedAt || "Niet beschikbaar");
    setText("detailSdfQuotationDocumentReference", sdfQuotation?.documentReference || "Niet beschikbaar");
    setText("detailSdfQuotationDocumentHash", sdfQuotation?.documentHash || "Niet beschikbaar");
    setText("detailSdfQuotationAcceptanceState", sdfQuotation?.acceptanceState || "Niet geregistreerd");
    setText("detailSdfQuotationAcceptedAt", sdfQuotation?.acceptedAt || "Niet beschikbaar");
    setText("detailSdfQuotationAcceptedDocument", sdfQuotation?.acceptedDocument || "Niet beschikbaar");
    setText("detailSdfQuotationAcceptedHash", sdfQuotation?.acceptedHash || "Niet beschikbaar");
    const sdfM1Invoice = sdfM1InvoiceCandidatePresentation(application);
    setText("detailSdfM1InvoiceState", sdfM1Invoice?.state || "Nog geen candidate");
    setText("detailSdfM1InvoiceDossierReference", sdfM1Invoice?.dossierReference || "Niet beschikbaar");
    setText("detailSdfM1InvoiceMilestone", sdfM1Invoice?.milestone || "Niet beschikbaar");
    setText("detailSdfM1InvoicePercentage", sdfM1Invoice?.percentage || "Niet beschikbaar");
    setText("detailSdfM1InvoiceNetAmount", sdfM1Invoice?.netAmount || "Niet beschikbaar");
    setText("detailSdfM1InvoiceCurrency", sdfM1Invoice?.currency || "Niet beschikbaar");
    setText("detailSdfM1InvoiceTemplate", sdfM1Invoice?.templateBinding || "Niet beschikbaar");
    setText("detailSdfM1InvoiceNumber", sdfM1Invoice?.invoiceNumber || "Niet toegewezen");
    setText("detailSdfM1InvoiceFiscalAuthority", sdfM1Invoice?.fiscalAuthority || "Niet actief");
    setText("detailSdfM1InvoiceIssuance", sdfM1Invoice?.issuance || "Geblokkeerd");
    setText("detailSdfM1InvoicePreparedAt", sdfM1Invoice?.preparedAt || "Niet beschikbaar");
    const sdfProject = sdfProjectPresentation(application);
    setText("detailSdfProjectId", sdfProject?.projectId || "Nog geen project");
    setText("detailSdfProjectProduct", sdfProject?.product || "Niet beschikbaar");
    setText("detailSdfProjectApplication", sdfProject?.application || "Niet beschikbaar");
    setText("detailSdfProjectCustomer", sdfProject?.customer || "Niet beschikbaar");
    setText("detailSdfProjectPackage", sdfProject?.package || "Niet geregistreerd");
    setText("detailSdfProjectStatus", sdfProject?.status || "Niet beschikbaar");
    setText("detailSdfOperationalStatus", sdfProject?.operationalStatus || "Niet beschikbaar");
    setText("detailSdfProjectCreatedAt", sdfProject?.createdAt || "Niet beschikbaar");
    for (const [id, value] of Object.entries(customerCorePresentation(application))) setText(id, value);
    setText("detailWebsiteType", application.website_type);
    setText("detailBudget", application.budget);
    setText("detailTiming", application.timing);
    setText("detailDescription", application.description);
    setText("detailIntakeStatus", application.intake_status || "Niet beschikbaar");
    setText("detailSubmittedAt", formatDate(application.submitted_at));
    promote.hidden = true;
    if (!isWebsite) return renderIntakeLifecycle(null);
    renderIntakeLifecycle(application.intake_lifecycle);
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
    lifecycleDossier.hidden = true;
    lifecycleMessage.textContent = "";
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
      const applicationPresentation = applicationIdentityPresentation(application);
      reference.textContent = `${applicationPresentation.visibleReference} · ${formatDate(application.submitted_at)}`;
      identity.append(name, reference);
      const state = application.request_kind === "slimme_documentenflow"
        ? badge("Documentenflow")
        : application.project_state
        ? badge(application.project_state, "green")
        : application.acceptance_id
        ? badge("Geaccepteerd", "amber")
        : badge("Ingediend");
      button.append(identity, state);
      const locator = applicationPresentation.locator;
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

  for (const button of lifecycleButtons) {
    button.addEventListener("click", ()=>{
      const action = button.dataset.lifecycleAction;
      const lifecycle = selectedDetail?.intake_lifecycle;
      const presentation = intakeLifecyclePresentation(lifecycle);
      const actionPresentation = intakeLifecycleAction(action);
      if (lifecycleBusy || !presentation?.actions.includes(action) || !actionPresentation || !selectedLocator) return;
      pendingLifecycleAction = {
        action,
        lifecycle,
        locator: { ...selectedLocator },
        presentation: actionPresentation,
      };
      setText("lifecycleDialogTitle", actionPresentation.title);
      setText("lifecycleDialogDescription", actionPresentation.description);
      lifecycleConfirm.textContent = actionPresentation.label;
      lifecycleConfirm.className = action === "cancel_intake" ? "danger-action" : "primary-action primary-action--compact";
      lifecycleReason.value = "";
      lifecycleReason.setCustomValidity("");
      lifecycleDialog.returnValue = "";
      lifecycleDialog.showModal();
      lifecycleReason.focus();
    });
  }

  lifecycleReason.addEventListener("input", ()=>lifecycleReason.setCustomValidity(""));
  lifecycleCancel.addEventListener("click", ()=>lifecycleDialog.close("cancel"));
  lifecycleForm.addEventListener("submit", (event)=>{
    const reason = lifecycleReason.value.trim();
    if (reason.length >= 1 && reason.length <= 500) return;
    event.preventDefault();
    lifecycleReason.setCustomValidity("Vul een korte reden in.");
    lifecycleReason.reportValidity();
  });
  lifecycleDialog.addEventListener("close", async ()=>{
    const command = pendingLifecycleAction;
    pendingLifecycleAction = null;
    if (lifecycleDialog.returnValue !== "confirm" || !command || lifecycleBusy) return;
    let input;
    try {
      input = buildIntakeLifecycleCommand(command.action, command.lifecycle, lifecycleReason.value, crypto.randomUUID());
    } catch {
      lifecycleMessage.textContent = "Vul een geldige reden in en probeer opnieuw.";
      return;
    }
    setLifecycleBusy(true);
    lifecycleMessage.textContent = `${command.presentation.label} wordt uitgevoerd.`;
    let completed = false;
    try {
      await invoke(input);
      await loadDetail(command.locator);
      completed = true;
      lifecycleMessage.textContent = `${command.presentation.label} is uitgevoerd. De actuele status is geladen.`;
    } catch (error) {
      const outcome = intakeLifecycleError(error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED");
      if (outcome.refresh) await loadDetail(command.locator);
      lifecycleMessage.textContent = outcome.message;
    } finally {
      setLifecycleBusy(false);
      if (selectedDetail?.request_kind === "website") renderIntakeLifecycle(selectedDetail.intake_lifecycle);
      if (completed) focusIntakeLifecycle(selectedDetail?.intake_lifecycle, lifecycleButtons, lifecycleDossierTitle);
    }
  });

  await loadList();
}

export function focusIntakeLifecycle(lifecycle, buttons, fallback) {
  const actions = intakeLifecyclePresentation(lifecycle)?.actions || [];
  const target = actions
    .map((action)=>buttons.find((button)=>button.dataset.lifecycleAction === action))
    .find((button)=>button && !button.hidden && !button.disabled)
    || fallback;
  target?.focus();
  return target || null;
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
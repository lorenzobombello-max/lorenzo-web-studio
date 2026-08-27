import { callCommercialOperator } from "./operator-auth-core.mjs";

const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;
const SUPPORT_REFERENCE = /^#?[0-9A-F]{8}$/i;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REQUEST_KINDS = new Set(["website", "slimme_documentenflow"]);
const PRODUCT_FILTERS = new Set(["all", ...REQUEST_KINDS]);
const OPERATOR_ZONES = new Set(["ACTIVE", "ARCHIVED", "TRASHED"]);
const OPERATOR_PAGE_LIMIT = 50;
const OPERATOR_ROLE_LABELS = Object.freeze({
  owner: "OWNER",
  operations_manager: "OPERATIONS MANAGER",
  operator: "OPERATOR",
  reviewer: "REVIEWER",
  read_only: "READ ONLY",
  admin: "ADMIN",
});
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
const DOSSIER_LIFECYCLE_PRESENTATION = Object.freeze({
  ACTIVE: Object.freeze({ label: "Actief", tone: "green", actions: Object.freeze(["archive_dossier", "trash_dossier"]) }),
  ARCHIVED: Object.freeze({ label: "Gearchiveerd", tone: "amber", actions: Object.freeze(["reactivate_dossier", "trash_dossier"]) }),
  TRASHED: Object.freeze({ label: "Prullenbak", tone: "red", actions: Object.freeze(["restore_dossier"]) }),
});
const DOSSIER_LIFECYCLE_ACTIONS = Object.freeze({
  archive_dossier: Object.freeze({ label: "Archiveren", title: "Dossier archiveren", description: "Het dossier wordt naar het archief verplaatst en blijft beschikbaar voor later gebruik." }),
  reactivate_dossier: Object.freeze({ label: "Terug activeren", title: "Dossier terug activeren", description: "Het dossier wordt opnieuw in de actieve werkruimte geplaatst." }),
  trash_dossier: Object.freeze({ label: "Naar prullenbak", title: "Dossier naar prullenbak verplaatsen", description: "Het dossier wordt naar de prullenbak verplaatst en niet permanent verwijderd. Bestaande gegevens, documenten en evidence worden niet hard gedeletet. Herstellen blijft mogelijk via ‘Herstellen uit prullenbak’." }),
  restore_dossier: Object.freeze({ label: "Herstellen uit prullenbak", title: "Dossier herstellen uit prullenbak", description: "Het dossier wordt hersteld naar de server-authoritatieve staat van vóór de prullenbak." }),
});

export function currentOperatorIdentityPresentation(identity) {
  if (!identity || typeof identity !== "object" || Array.isArray(identity)
    || Object.keys(identity).length !== 3
    || typeof identity.display_name !== "string" || !identity.display_name
    || identity.status !== "ACTIVE"
    || !Object.hasOwn(OPERATOR_ROLE_LABELS, identity.role)) {
    throw new Error("INVALID_OPERATOR_IDENTITY");
  }
  return { displayName: identity.display_name, roleLabel: OPERATOR_ROLE_LABELS[identity.role] };
}
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

export function normalizeSupportReference(value) {
  const normalized = String(value || "").trim().toUpperCase();
  return SUPPORT_REFERENCE.test(normalized) ? `#${normalized.replace(/^#/, "")}` : null;
}

export function dossierReferenceFromDetail(detail) {
  const applicationReference = String(detail?.application_reference || "");
  if (APPLICATION_REFERENCE.test(applicationReference)) return applicationReference;
  return normalizeSupportReference(detail?.support_reference);
}

export function assignmentPresentation(assignment) {
  const state = String(assignment?.assignment_state || "");
  const revision = assignment?.revision;
  const assigneeOperatorId = assignment?.assignee_operator_id ?? null;
  const assigneeDisplayName = assignment?.assignee_display_name ?? null;
  if (!new Set(["UNASSIGNED", "ASSIGNED"]).has(state)
      || !Number.isSafeInteger(revision) || revision < 0
      || (state === "UNASSIGNED" && (assigneeOperatorId !== null || assigneeDisplayName !== null))
      || (state === "ASSIGNED" && (!UUID.test(String(assigneeOperatorId || "")) || typeof assigneeDisplayName !== "string" || !assigneeDisplayName))) return null;
  return { state, revision, assigneeOperatorId, assigneeDisplayName };
}

export function buildAssignmentCommand(dossierReference, assignment, assigneeOperatorId, reason, idempotencyKey) {
  const presentation = assignmentPresentation(assignment);
  const normalizedReason = typeof reason === "string" ? reason.trim() : "";
  const isReassignment = presentation?.state === "ASSIGNED" && presentation.assigneeOperatorId !== assigneeOperatorId;
  if (!dossierReference || !presentation || !UUID.test(String(assigneeOperatorId || ""))
      || presentation.assigneeOperatorId === assigneeOperatorId || !UUID.test(String(idempotencyKey || ""))
      || normalizedReason.length > 500 || (isReassignment && normalizedReason.length < 1)) throw new Error("INVALID_ASSIGNMENT_COMMAND");
  return {
    action: "assign_dossier",
    dossier_reference: dossierReference,
    assignee_operator_id: assigneeOperatorId,
    expected_revision: presentation.revision,
    idempotency_key: idempotencyKey,
    ...(normalizedReason ? { reason: normalizedReason } : {}),
  };
}

export function assignmentError(code) {
  if (["AUTHENTICATION_REQUIRED", "INVALID_JWT", "HUMAN_JWT_REQUIRED", "OPERATOR_NOT_AUTHORIZED", "INSUFFICIENT_PERMISSIONS"].includes(code)) return { hide: true, refresh: false, message: "" };
  if (["DOSSIER_NOT_FOUND", "AMBIGUOUS_DOSSIER_REFERENCE"].includes(code)) return { hide: true, refresh: false, message: "Dossiertoewijzing is voor dit dossier niet beschikbaar." };
  if (["ASSIGNEE_OPERATOR_NOT_FOUND", "ASSIGNEE_NOT_ELIGIBLE"].includes(code)) return { hide: false, refresh: true, message: "Deze operator is niet meer beschikbaar. Kies opnieuw." };
  if (["COMMAND_REJECTED", "CONCURRENT_MODIFICATION"].includes(code)) return { hide: false, refresh: true, message: "Het dossier werd ondertussen gewijzigd. De actuele toewijzing is geladen; bevestig opnieuw." };
  if (code === "IDEMPOTENCY_CONFLICT") return { hide: false, refresh: true, message: "Deze poging conflicteert met een eerdere actie. De actuele toewijzing is geladen." };
  if (code === "INVALID_REQUEST") return { hide: false, refresh: false, message: "De toewijzing kon niet worden verwerkt. Controleer je keuze." };
  return { hide: false, refresh: false, message: "De toewijzing is tijdelijk niet beschikbaar. Probeer later opnieuw." };
}

export function projectSitePresentation(projectId, site) {
  if (!UUID.test(String(projectId || "")) || site?.project_id !== projectId) return null;
  const domain = String(site.canonical_domain || "");
  const canonicalUrl = String(site.canonical_url || "");
  if (!domain || domain !== domain.toLowerCase()) return null;
  try {
    const parsed = new URL(canonicalUrl);
    if (parsed.protocol !== "https:" || parsed.hostname !== domain || parsed.origin !== canonicalUrl
      || parsed.username || parsed.password || parsed.search || parsed.hash) return null;
  } catch {
    return null;
  }
  return { domain, canonicalUrl };
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

export function dossierLifecyclePresentation(lifecycle) {
  const state = String(lifecycle?.state || "");
  const presentation = DOSSIER_LIFECYCLE_PRESENTATION[state];
  if (!presentation
      || !Number.isSafeInteger(lifecycle?.revision)
      || lifecycle.revision < 0) return null;
  return { state, revision: lifecycle.revision, ...presentation };
}

export function dossierLifecycleAction(action) {
  return DOSSIER_LIFECYCLE_ACTIONS[action] || null;
}

export function buildDossierLifecycleCommand(action, detail, reason, idempotencyKey) {
  const presentation = dossierLifecyclePresentation(detail?.dossier_lifecycle);
  const normalizedReason = typeof reason === "string" ? reason.trim() : "";
  if (!presentation?.actions.includes(action)
      || !UUID.test(String(detail?.quote_request_id || ""))
      || !UUID.test(String(idempotencyKey || ""))
      || normalizedReason.length < 1
      || normalizedReason.length > 500) throw new Error("INVALID_DOSSIER_LIFECYCLE_COMMAND");
  return {
    action,
    quote_request_id: detail.quote_request_id,
    expected_revision: presentation.revision,
    idempotency_key: idempotencyKey,
    reason: normalizedReason,
  };
}

export function dossierLifecycleError(code) {
  if (["CONCURRENT_MODIFICATION", "COMMAND_REJECTED", "INVALID_DOSSIER_LIFECYCLE_TRANSITION", "INVALID_OPERATOR_DOSSIER_TRANSITION", "IDEMPOTENCY_CONFLICT"].includes(code)) {
    return { message: "De dossierstatus werd ondertussen gewijzigd. De actuele gegevens worden opnieuw geladen.", refresh: true };
  }
  if (code === "OPERATOR_DOSSIER_STATE_REQUIRED" || code === "APPLICATION_NOT_FOUND") {
    return { message: "Dit dossier is niet meer beschikbaar. De actuele gegevens worden opnieuw geladen.", refresh: true };
  }
  if (["AUTHENTICATION_REQUIRED", "INVALID_JWT", "HUMAN_JWT_REQUIRED", "OPERATOR_NOT_AUTHORIZED", "INSUFFICIENT_PERMISSIONS"].includes(code)) {
    return { message: "Je sessie is verlopen of je hebt onvoldoende bevoegdheid voor deze actie.", refresh: false };
  }
  return { message: "De dossieractie kon niet worden uitgevoerd. Controleer de actuele status en probeer opnieuw.", refresh: false };
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

const INTERNAL_SMOKE_FIELDS = Object.freeze([
  "SMOKE_STATUS",
  "run_id",
  "customer_request_id",
  "replay_same_request",
  "upload_request_id",
  "resolve_before_revoke",
  "revoke",
  "resolve_after_revoke",
  "customer_request_final_status",
  "internal_e2e_final_status",
]);

function internalSmokeResult() {
  return {
    SMOKE_STATUS: "FAILED: AUTH",
    run_id: null,
    customer_request_id: null,
    replay_same_request: false,
    upload_request_id: null,
    resolve_before_revoke: "FAIL",
    revoke: "FAIL",
    resolve_after_revoke: "FAIL",
    customer_request_final_status: null,
    internal_e2e_final_status: null,
  };
}

export function internalSmokeAvailable(url, identity) {
  return new URL(url).searchParams.get("internalSmoke") === "1"
    && identity?.status === "ACTIVE"
    && identity?.role === "owner";
}

export function createInternalSmokeOneShotTrigger({ button, confirmSmoke, runSmoke }) {
  let started = false;
  return async () => {
    if (started || !confirmSmoke()) return null;
    started = true;
    button.disabled = true;
    return await runSmoke();
  };
}

export async function runInternalSmokeA({ client, invoke, resolveCapability, randomUUID = ()=>crypto.randomUUID() }) {
  const result = internalSmokeResult();
  let capability = null;
  let runId = null;
  let customerRequestId = null;
  let uploadRequestId = null;
  let customerRequestRevision = null;
  let revokeAttempted = false;
  let cancelAttempted = false;
  let finalizeAttempted = false;
  let uploadLinkRevoked = false;
  let customerRequestCancelled = false;
  let runFinalized = false;
  let phase = "AUTH";
  const required = (condition) => {
    if (!condition) throw new Error("INTERNAL_SMOKE_FAILED");
  };
  try {
    const session = await client.auth.getSession();
    required(!session.error && session.data.session);
    const user = await client.auth.getUser();
    required(!user.error && user.data.user?.id);
    const identity = await invoke({ action: "get_current_operator_identity" });
    required(identity?.status === "ACTIVE" && identity?.role === "owner");

    phase = "FIXTURE_CREATE";
    const fixtureKey = randomUUID();
    const fixture = await invoke({ action: "create_customer_request_smoke_fixture", idempotency_key: fixtureKey });
    required(fixture?.replayed === false && fixture?.status === "NEW" && fixture?.revision === 0
      && UUID.test(String(fixture.run_id || "")) && UUID.test(String(fixture.request_id || "")));
    runId = fixture.run_id;
    customerRequestId = fixture.request_id;
    customerRequestRevision = fixture.revision;
    result.run_id = runId;
    result.customer_request_id = customerRequestId;

    phase = "FIXTURE_REPLAY";
    const replay = await invoke({ action: "create_customer_request_smoke_fixture", idempotency_key: fixtureKey });
    result.replay_same_request = replay?.replayed === true
      && replay.run_id === fixture.run_id
      && replay.request_id === fixture.request_id;
    required(result.replay_same_request);

    phase = "UPLOAD_LINK_CREATE";
    const link = await invoke({
      action: "create_customer_request_upload_link",
      request_id: fixture.request_id,
      idempotency_key: randomUUID(),
    });
    required(link?.state === "ACTIVE" && link?.was_created === true
      && UUID.test(String(link.upload_request_id || "")) && typeof link.upload_url === "string");
    uploadRequestId = link.upload_request_id;
    result.upload_request_id = uploadRequestId;
    const capabilityUrl = new URL(link.upload_url);
    delete link.upload_url;
    capability = new URLSearchParams(capabilityUrl.hash.slice(1)).get("token");
    capabilityUrl.hash = "";
    required(/^[A-Za-z0-9_-]{43}$/.test(capability || ""));

    phase = "RESOLVE_BEFORE_REVOKE";
    const before = await resolveCapability(capability);
    result.resolve_before_revoke = before?.status === 200
      && before.body?.ok === true
      && before.body?.state === "ACTIVE"
      && before.body?.title === "LWS-SMOKE-TEST-UPLOAD-LINK-20260827"
      && before.body?.file_count === 0 ? "PASS" : "FAIL";
    required(result.resolve_before_revoke === "PASS");

    phase = "REVOKE";
    revokeAttempted = true;
    const revoked = await invoke({
      action: "revoke_customer_request_upload_link",
      upload_request_id: uploadRequestId,
      reason: "Synthetic internal Smoke A completed without file upload.",
      idempotency_key: randomUUID(),
    });
    uploadLinkRevoked = revoked?.state === "REVOKED" && revoked.upload_request_id === uploadRequestId;
    result.revoke = uploadLinkRevoked ? "PASS" : "FAIL";
    required(result.revoke === "PASS");

    phase = "RESOLVE_AFTER_REVOKE";
    const after = await resolveCapability(capability);
    result.resolve_after_revoke = after?.status === 200
      && after.body?.ok === true
      && after.body?.state === "INVALID_OR_EXPIRED_LINK" ? "DENIED" : "FAIL";
    required(result.resolve_after_revoke === "DENIED");

    phase = "CANCEL";
    cancelAttempted = true;
    const cancelled = await client.rpc("transition_customer_request_v1", {
      p_request_id: customerRequestId,
      p_command_type: "CANCEL",
      p_expected_revision: customerRequestRevision,
      p_idempotency_key: randomUUID(),
      p_payload: {},
    });
    result.customer_request_final_status = cancelled.data?.status || null;
    customerRequestCancelled = !cancelled.error && result.customer_request_final_status === "CANCELLED";
    required(customerRequestCancelled);

    phase = "FINALIZE";
    finalizeAttempted = true;
    const finalized = await invoke({
      action: "finalize_internal_e2e_run",
      run_id: runId,
      terminal_status: "PASSED",
      expected_revision: 0,
      idempotency_key: randomUUID(),
    });
    result.internal_e2e_final_status = finalized?.status || null;
    runFinalized = result.internal_e2e_final_status === "PASSED";
    required(runFinalized);
    result.SMOKE_STATUS = "PASS";
  } catch {
    const failurePhase = phase;
    if (uploadRequestId) {
      if (!revokeAttempted && !uploadLinkRevoked) {
        try {
          revokeAttempted = true;
          const revoked = await invoke({
            action: "revoke_customer_request_upload_link",
            upload_request_id: uploadRequestId,
            reason: "Synthetic internal Smoke A failed after Upload Link creation.",
            idempotency_key: randomUUID(),
          });
          uploadLinkRevoked = revoked?.state === "REVOKED" && revoked.upload_request_id === uploadRequestId;
          if (uploadLinkRevoked) result.revoke = "PASS";
        } catch {}
      }
      if (!cancelAttempted && !customerRequestCancelled && customerRequestId) {
        try {
          cancelAttempted = true;
          const cancelled = await client.rpc("transition_customer_request_v1", {
            p_request_id: customerRequestId,
            p_command_type: "CANCEL",
            p_expected_revision: customerRequestRevision,
            p_idempotency_key: randomUUID(),
            p_payload: {},
          });
          customerRequestCancelled = !cancelled.error && cancelled.data?.status === "CANCELLED";
          if (customerRequestCancelled) result.customer_request_final_status = "CANCELLED";
        } catch {}
      }
      if (!finalizeAttempted && !runFinalized && runId && uploadLinkRevoked && customerRequestCancelled) {
        try {
          finalizeAttempted = true;
          const finalized = await invoke({
            action: "finalize_internal_e2e_run",
            run_id: runId,
            terminal_status: "FAILED",
            expected_revision: 0,
            idempotency_key: randomUUID(),
          });
          runFinalized = finalized?.status === "FAILED";
          if (runFinalized) result.internal_e2e_final_status = "FAILED";
        } catch {}
      }
    }
    result.SMOKE_STATUS = `FAILED: ${failurePhase}`;
  } finally {
    capability = null;
  }
  return Object.fromEntries(INTERNAL_SMOKE_FIELDS.map((field)=>[field, result[field]]));
}

export async function startOperatorDashboard({ client, functionsBaseUrl, callOperator = callCommercialOperator }) {
  const roleBadges = Array.from(document.querySelectorAll("[data-operator-role-badge]"));
  const personalQueueWorkspace = document.getElementById("personalQueueWorkspace");
  const personalQueueList = document.getElementById("personalQueueList");
  const personalQueueEmpty = document.getElementById("personalQueueEmpty");
  const personalQueueMessage = document.getElementById("personalQueueMessage");
  const personalQueueRefresh = document.getElementById("personalQueueRefresh");
  const personalQueueLoadMore = document.getElementById("personalQueueLoadMore");
  const customerRequestDossier = document.getElementById("customerRequestDossier");
  const customerRequestMessage = document.getElementById("customerRequestMessage");
  const customerRequestList = document.getElementById("customerRequestList");
  const customerRequestEmpty = document.getElementById("customerRequestEmpty");
  const customerRequestLoadMore = document.getElementById("customerRequestLoadMore");
  const customerRequestDetail = document.getElementById("customerRequestDetail");
  const customerRequestDetailEmpty = document.getElementById("customerRequestDetailEmpty");
  const customerRequestDetailMessage = document.getElementById("customerRequestDetailMessage");
  const customerRequestReference = document.getElementById("customerRequestReference");
  const customerRequestTitle = document.getElementById("customerRequestTitle");
  const customerRequestType = document.getElementById("customerRequestType");
  const customerRequestStatus = document.getElementById("customerRequestStatus");
  const customerRequestPriority = document.getElementById("customerRequestPriority");
  const customerRequestSubmittedAt = document.getElementById("customerRequestSubmittedAt");
  const customerRequestDescription = document.getElementById("customerRequestDescription");
  const customerRequestActionButtons = Array.from(document.querySelectorAll("[data-customer-request-command]"));
  const customerRequestUploadStatus = document.getElementById("customerRequestUploadStatus");
  const customerRequestUploadUrl = document.getElementById("customerRequestUploadUrl");
  const customerRequestUploadCreate = document.getElementById("customerRequestUploadCreate");
  const customerRequestUploadCopy = document.getElementById("customerRequestUploadCopy");
  const customerRequestUploadRevoke = document.getElementById("customerRequestUploadRevoke");
  const internalSmokePanel = document.getElementById("internalSmokePanel");
  const internalSmokeRun = document.getElementById("internalSmokeRun");
  const internalSmokeStatus = document.getElementById("internalSmokeStatus");
  const internalSmokeResultElement = document.getElementById("internalSmokeResult");
  const managerWorkspace = document.getElementById("managerWorkspace");
  const list = document.getElementById("applicationList");
  const empty = document.getElementById("applicationEmpty");
  const listMessage = document.getElementById("applicationListMessage");
  const detail = document.getElementById("applicationDetail");
  const detailEmpty = document.getElementById("applicationDetailEmpty");
  const detailMessage = document.getElementById("applicationDetailMessage");
  const promote = document.getElementById("promoteApplication");
  const assignmentDossier = document.getElementById("assignmentDossier");
  const assignmentCurrent = document.getElementById("assignmentCurrent");
  const assignmentForm = document.getElementById("assignmentForm");
  const assignmentOperator = document.getElementById("assignmentOperator");
  const assignmentReasonField = document.getElementById("assignmentReasonField");
  const assignmentReason = document.getElementById("assignmentReason");
  const assignmentSubmit = document.getElementById("assignmentSubmit");
  const assignmentMessage = document.getElementById("assignmentMessage");
  const confirmation = document.getElementById("promotionDialog");
  const dossierLifecycleDossier = document.getElementById("dossierLifecycleDossier");
  const dossierLifecycleTitle = document.getElementById("dossierLifecycleTitle");
  const dossierLifecycleMessage = document.getElementById("dossierLifecycleMessage");
  const dossierLifecycleButtons = Array.from(document.querySelectorAll("[data-dossier-lifecycle-action]"));
  const dossierLifecycleDialog = document.getElementById("dossierLifecycleDialog");
  const dossierLifecycleForm = document.getElementById("dossierLifecycleForm");
  const dossierLifecycleReason = document.getElementById("dossierLifecycleReason");
  const dossierLifecycleConfirm = document.getElementById("dossierLifecycleConfirm");
  const dossierLifecycleCancel = document.getElementById("dossierLifecycleCancel");
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
  const zoneButtons = Array.from(document.querySelectorAll("[data-zone]"));
  const searchInput = document.getElementById("applicationSearch");
  const statusFilter = document.getElementById("applicationStatusFilter");
  const yearFilter = document.getElementById("applicationYearFilter");
  const quarterFilter = document.getElementById("applicationQuarterFilter");
  const loadMore = document.getElementById("applicationLoadMore");
  const sdfDetailNotice = document.getElementById("sdfDetailNotice");
  let selectedLocator = applicationLocatorFromUrl(window.location.href);
  let selectedSummary = null;
  let selectedDetail = null;
  let detailRequestId = 0;
  let assignmentState = null;
  let assignmentRoster = [];
  let assignmentReference = null;
  let assignmentLoading = false;
  let assignmentSubmitting = false;
  let dossierLifecycleBusy = false;
  let pendingDossierLifecycleAction = null;
  let lifecycleBusy = false;
  let pendingLifecycleAction = null;
  let selectedDossierReference = null;

  async function invoke(input) {
    const response = await callOperator(client, functionsBaseUrl, input);
    if (response.status >= 400 || !response.body?.ok) throw new Error(response.body?.code || "OPERATOR_REQUEST_FAILED");
    return response.body.result;
  }

  const currentIdentity = await invoke({ action: "get_current_operator_identity" });
  const identity = currentOperatorIdentityPresentation(currentIdentity);
  for (const roleBadge of roleBadges) roleBadge.textContent = identity.roleLabel;
  if (internalSmokePanel && internalSmokeAvailable(window.location.href, currentIdentity)) {
    internalSmokePanel.hidden = false;
    const confirmationMessage = "Smoke A uitvoeren?\nEr wordt exact één synthetic Customer Request en één tijdelijke Upload Link gemaakt. Er wordt geen bestand geüpload en geen echte klantdata gebruikt.";
    const triggerInternalSmoke = createInternalSmokeOneShotTrigger({
      button: internalSmokeRun,
      confirmSmoke: ()=>window.confirm(confirmationMessage),
      runSmoke: async ()=>{
        internalSmokeStatus.textContent = "Test wordt uitgevoerd…";
        internalSmokeResultElement.textContent = "";
        const result = await runInternalSmokeA({
          client,
          invoke,
          resolveCapability: async (capability) => {
            const response = await fetch(`${functionsBaseUrl.replace(/\/$/, "")}/customer-request-upload`, {
              method: "GET",
              headers: { Authorization: `Bearer ${capability}`, Accept: "application/json" },
              cache: "no-store",
              referrerPolicy: "no-referrer",
            });
            return { status: response.status, body: await response.json().catch(()=>null) };
          },
        });
        internalSmokeStatus.textContent = result.SMOKE_STATUS === "PASS" ? "Test voltooid." : "Test gestopt.";
        internalSmokeResultElement.textContent = JSON.stringify(result, null, 2);
        return result;
      },
    });
    internalSmokeRun.addEventListener("click", triggerInternalSmoke);
  }

  function renderPersonalQueue(items) {
    personalQueueList.replaceChildren();
    for (const dossier of items) {
      const item = document.createElement("li");
      const button = document.createElement("button");
      const identity = document.createElement("div");
      const reference = document.createElement("strong");
      const assignedAt = document.createElement("small");
      const statuses = document.createElement("div");
      reference.textContent = dossier.reference;
      assignedAt.textContent = `Toegewezen op ${formatDate(dossier.assigned_at)}`;
      identity.append(reference, assignedAt);
      statuses.className = "personal-queue-list__statuses";
      statuses.append(badge(dossier.status), badge(dossier.zone));
      button.type = "button";
      button.className = "personal-queue-list__button";
      button.setAttribute("aria-current", String(dossier.reference === selectedDossierReference));
      button.addEventListener("click", ()=>{
        selectedDossierReference = dossier.reference;
        customerRequestDetailController.clear();
        customerRequestListController.selectDossier(dossier.reference);
        renderPersonalQueue(personalQueueController.state.items);
      });
      button.append(identity, statuses);
      item.append(button);
      personalQueueList.append(item);
    }
  }

  function renderCustomerRequestList(items, selectedRequestId) {
    customerRequestList.replaceChildren();
    for (const request of items) {
      const item = document.createElement("li");
      const button = document.createElement("button");
      const identity = document.createElement("span");
      const title = document.createElement("strong");
      const reference = document.createElement("small");
      title.textContent = request.title;
      reference.textContent = `${request.request_reference} · ${formatDate(request.submitted_at)}`;
      identity.append(title, reference);
      button.type = "button";
      button.className = "customer-request-list__button";
      button.setAttribute("aria-current", String(request.request_id === selectedRequestId));
      button.addEventListener("click", ()=>customerRequestDetailController.selectRequest(request.request_id));
      button.append(identity, badge(request.status));
      item.append(button);
      customerRequestList.append(item);
    }
  }

  function renderCustomerRequestDetail(state) {
    const request = state.request;
    customerRequestDetail.hidden = !request;
    customerRequestDetailEmpty.hidden = Boolean(request) || state.loading;
    customerRequestDetailMessage.textContent = state.loading
      ? "Request laden…"
      : state.submitting ? "Actie verwerken…"
      : state.error === "CONCURRENT_MODIFICATION"
      ? "De request is intussen gewijzigd. Selecteer de request opnieuw."
      : state.error ? "De request is niet langer beschikbaar." : "";
    if (!request) {
      for (const button of customerRequestActionButtons) button.hidden = true;
      customerRequestUploadUrl.value = "";
      customerRequestUploadUrl.hidden = true;
      customerRequestUploadCreate.hidden = true;
      customerRequestUploadCopy.hidden = true;
      customerRequestUploadRevoke.hidden = true;
      return;
    }
    customerRequestReference.textContent = request.request_reference;
    customerRequestTitle.textContent = request.title;
    customerRequestType.textContent = request.request_type.replaceAll("_", " ");
    customerRequestStatus.textContent = request.status.replaceAll("_", " ");
    customerRequestPriority.textContent = request.priority || "Niet toegewezen";
    customerRequestSubmittedAt.textContent = formatDate(request.submitted_at);
    customerRequestDescription.textContent = request.description;
    const command = customerRequestWorkCommand(request.status);
    for (const button of customerRequestActionButtons) {
      button.hidden = button.dataset.customerRequestCommand !== command;
      button.disabled = state.submitting;
    }
    const activeUpload = request.upload_request;
    customerRequestUploadStatus.textContent = activeUpload
      ? `Actief tot ${formatDate(activeUpload.expires_at)}.`
      : "Er is geen actieve uploadlink.";
    customerRequestUploadUrl.value = state.upload_url || "";
    customerRequestUploadUrl.hidden = !state.upload_url;
    customerRequestUploadCreate.hidden = Boolean(activeUpload);
    customerRequestUploadCopy.hidden = !state.upload_url;
    customerRequestUploadRevoke.hidden = !activeUpload;
    for (const button of [customerRequestUploadCreate, customerRequestUploadCopy, customerRequestUploadRevoke]) {
      button.disabled = state.submitting;
    }
  }

  let customerRequestListController;
  const customerRequestDetailController = createCustomerRequestDetailController(invoke, (state)=>{
    renderCustomerRequestDetail(state);
    renderCustomerRequestList(customerRequestListController?.state.items || [], state.request_id);
  });
  customerRequestListController = createCustomerRequestListController(invoke, (state)=>{
    customerRequestDossier.textContent = state.dossier_reference || "Selecteer een dossier";
    renderCustomerRequestList(state.items, customerRequestDetailController.state.request_id);
    customerRequestMessage.textContent = state.loading
      ? state.items.length ? "Meer requests laden…" : "Requests laden…"
      : state.error ? "De requests konden niet worden geladen." : "";
    customerRequestEmpty.hidden = !state.dossier_reference || state.loading || Boolean(state.error) || state.items.length > 0;
    customerRequestLoadMore.hidden = !state.has_more || !state.next_cursor;
    customerRequestLoadMore.disabled = state.loading || !state.has_more || !state.next_cursor;
  });
  customerRequestLoadMore.addEventListener("click", ()=>customerRequestListController.loadMore());
  for (const button of customerRequestActionButtons) {
    button.addEventListener("click", ()=>customerRequestDetailController.transition(button.dataset.customerRequestCommand));
  }
  customerRequestUploadCreate.addEventListener("click", ()=>customerRequestDetailController.createUploadLink());
  customerRequestUploadCopy.addEventListener("click", async ()=>{
    if (!customerRequestDetailController.state.upload_url) return;
    await navigator.clipboard.writeText(customerRequestDetailController.state.upload_url);
    customerRequestUploadStatus.textContent = "Uploadlink gekopieerd.";
  });
  customerRequestUploadRevoke.addEventListener("click", ()=>customerRequestDetailController.revokeUploadLink());

  const personalQueueController = createPersonalQueueController(invoke, (state)=>{
    renderPersonalQueue(state.items);
    personalQueueMessage.textContent = state.loading
      ? state.items.length ? "Meer dossiers laden…" : "Dossiers laden…"
      : state.error ? "De dossiers konden niet worden geladen. Probeer het later opnieuw." : "";
    personalQueueEmpty.hidden = state.loading || Boolean(state.error) || state.items.length > 0;
    personalQueueRefresh.disabled = state.loading;
    personalQueueLoadMore.hidden = !state.has_more || !state.next_cursor;
    personalQueueLoadMore.disabled = state.loading || !state.has_more || !state.next_cursor;
  });
  personalQueueRefresh.addEventListener("click", ()=>{
    selectedDossierReference = null;
    customerRequestListController.clear();
    customerRequestDetailController.clear();
    personalQueueController.refresh();
  });
  personalQueueLoadMore.addEventListener("click", ()=>personalQueueController.loadMore());
  personalQueueWorkspace.hidden = false;

  function renderFacets(facets, selectedYear, selectedQuarter) {
    const years = Array.isArray(facets?.years) ? facets.years : [];
    yearFilter.replaceChildren(new Option("Alle jaren", ""));
    for (const entry of years) yearFilter.add(new Option(`${entry.year} (${entry.count})`, String(entry.year)));
    yearFilter.value = selectedYear ? String(selectedYear) : "";
    const year = years.find((entry)=>entry.year === selectedYear);
    quarterFilter.replaceChildren(new Option("Alle kwartalen", ""));
    for (const quarter of year?.quarters || []) {
      const option = new Option(`${quarter.quarter} (${quarter.count})`, quarter.quarter);
      option.disabled = Number(quarter.count) === 0;
      quarterFilter.add(option);
    }
    quarterFilter.disabled = !year;
    quarterFilter.value = year && selectedQuarter ? selectedQuarter : "";
  }

  const listController = createOperatorListController(invoke, (state)=>{
    renderList(state.items);
    renderFacets(state.facets, state.year, state.quarter);
    const visibility = operatorListVisibility(state);
    empty.textContent = state.search ? "Geen resultaten voor deze zoekopdracht." : "Geen dossiers gevonden.";
    empty.hidden = visibility.emptyHidden;
    listMessage.textContent = visibility.message;
    loadMore.hidden = !state.next_cursor;
    loadMore.disabled = state.loading || !state.next_cursor;
  });

  const dashboardRoute = await resolveDashboardAuthority({
    loadPersonalQueue: ()=>personalQueueController.load(),
    getPersonalQueueError: ()=>personalQueueController.state.error,
    loadManagerAuthority: ()=>listController.load(),
  });
  if (dashboardRoute !== "manager") return;
  personalQueueWorkspace.hidden = true;
  managerWorkspace.hidden = false;

  function updateLocation(locator) {
    const url = new URL(window.location.href);
    url.searchParams.delete("application");
    url.searchParams.delete("request");
    url.searchParams.delete("support");
    if (locator?.application_reference) url.searchParams.set("application", locator.application_reference);
    else if (locator?.support_reference) url.searchParams.set("support", locator.support_reference.slice(1));
    else if (locator?.quote_request_id) url.searchParams.set("request", locator.quote_request_id);
    window.history.replaceState(null, "", `${url.pathname}${url.search}`);
  }

  function clearDetail() {
    detailRequestId += 1;
    selectedLocator = null;
    selectedSummary = null;
    selectedDetail = null;
    resetAssignment();
    applyDetailVisibility(null, { detail, detailEmpty, promote, dossierSections, websiteDossierSections, sdfDossierSections, websiteDetailRows, sdfDetailRows, sdfDetailNotice });
    detailMessage.textContent = "";
    dossierLifecycleMessage.textContent = "";
    lifecycleMessage.textContent = "";
    updateLocation(null);
  }

  function resetAssignment() {
    assignmentState = null;
    assignmentRoster = [];
    assignmentReference = null;
    assignmentLoading = false;
    assignmentSubmitting = false;
    assignmentDossier.hidden = true;
    assignmentOperator.replaceChildren(new Option("Kies een operator", ""));
    assignmentReason.value = "";
    assignmentReasonField.hidden = true;
    assignmentReason.required = false;
    assignmentMessage.textContent = "";
  }

  function renderAssignment() {
    const presentation = assignmentPresentation(assignmentState);
    assignmentDossier.hidden = !presentation;
    if (!presentation) return;
    assignmentCurrent.textContent = presentation.state === "UNASSIGNED" ? "Niet toegewezen" : presentation.assigneeDisplayName;
    const selected = assignmentOperator.value || presentation.assigneeOperatorId || "";
    assignmentOperator.replaceChildren(new Option("Kies een operator", ""));
    for (const operator of assignmentRoster) {
      if (!UUID.test(String(operator?.operator_id || "")) || typeof operator?.display_name !== "string" || !operator.display_name) continue;
      assignmentOperator.add(new Option(operator.display_name, operator.operator_id));
    }
    assignmentOperator.value = assignmentRoster.some((operator)=>operator.operator_id === selected) ? selected : "";
    const isReassignment = presentation.state === "ASSIGNED" && assignmentOperator.value && assignmentOperator.value !== presentation.assigneeOperatorId;
    assignmentReasonField.hidden = !isReassignment;
    assignmentReason.required = Boolean(isReassignment);
    const reasonLength = assignmentReason.value.trim().length;
    const validReason = !isReassignment || (reasonLength >= 1 && reasonLength <= 500);
    assignmentOperator.disabled = assignmentLoading || assignmentSubmitting || assignmentRoster.length === 0;
    assignmentReason.disabled = assignmentLoading || assignmentSubmitting;
    assignmentSubmit.disabled = assignmentLoading || assignmentSubmitting || !assignmentOperator.value
      || assignmentOperator.value === presentation.assigneeOperatorId || !validReason;
    if (assignmentLoading) assignmentMessage.textContent = "Toewijzing wordt geladen.";
    else if (!assignmentRoster.length) assignmentMessage.textContent = "Er zijn momenteel geen beschikbare operators.";
  }

  async function loadAssignment(application, requestId, successMessage = "") {
    const dossierReference = dossierReferenceFromDetail(application);
    resetAssignment();
    if (!dossierReference || requestId !== detailRequestId) return false;
    assignmentReference = dossierReference;
    assignmentLoading = true;
    assignmentDossier.hidden = false;
    assignmentMessage.textContent = "Toewijzing wordt geladen.";
    try {
      const [assignment, roster] = await Promise.all([
        invoke({ action: "get_dossier_assignment", dossier_reference: dossierReference }),
        invoke({ action: "get_assignment_operator_roster" }),
      ]);
      if (requestId !== detailRequestId || dossierReference !== dossierReferenceFromDetail(selectedDetail)) return false;
      if (!assignmentPresentation(assignment) || !Array.isArray(roster)) throw new Error("INVALID_ASSIGNMENT_RESPONSE");
      assignmentState = assignment;
      assignmentRoster = roster;
      assignmentLoading = false;
      assignmentMessage.textContent = successMessage;
      renderAssignment();
      return true;
    } catch (error) {
      if (requestId !== detailRequestId) return false;
      assignmentLoading = false;
      const outcome = assignmentError(error instanceof Error ? error.message : "INTERNAL_ERROR");
      assignmentDossier.hidden = outcome.hide;
      assignmentOperator.disabled = true;
      assignmentReason.disabled = true;
      assignmentSubmit.disabled = true;
      assignmentMessage.textContent = outcome.message;
      return false;
    }
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
    const projectId = project?.project_id || application?.project?.project_id || null;
    const site = projectSitePresentation(projectId, project?.site || application?.project_site);
    setText("detailProject", projectId || "Nog niet aangemaakt");
    setText("detailProjectCreatedAt", formatDate(project?.created_at || application?.project?.created_at));
    setText("detailProjectRevision", project?.revision ?? application?.project?.revision ?? "-");
    setText("detailTotal", formatMoney(project?.accepted_total_minor ?? application?.project?.accepted_total_minor));
    setText("detailProjectDomain", site?.domain || "Niet vastgelegd");
    const website = document.getElementById("detailProjectWebsite");
    website.replaceChildren();
    if (site) {
      const link = document.createElement("a");
      link.href = site.canonicalUrl;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.textContent = "Website openen";
      website.append(link);
    } else {
      website.textContent = "Niet vastgelegd";
    }
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

  function renderDossierLifecycle(detailApplication) {
    const presentation = dossierLifecyclePresentation(detailApplication?.dossier_lifecycle);
    dossierLifecycleDossier.hidden = false;
    if (!presentation) {
      setBadge("dossierLifecycleStateBadge", "NIET BESCHIKBAAR", "amber");
      for (const button of dossierLifecycleButtons) button.hidden = true;
      dossierLifecycleMessage.textContent = "Dossierbeheer is momenteel niet beschikbaar. Vernieuw het dossier.";
      return;
    }
    setBadge("dossierLifecycleStateBadge", presentation.label, presentation.tone);
    for (const button of dossierLifecycleButtons) {
      button.hidden = !presentation.actions.includes(button.dataset.dossierLifecycleAction);
      button.disabled = dossierLifecycleBusy;
    }
  }

  function setDossierLifecycleBusy(busy) {
    dossierLifecycleBusy = busy;
    dossierLifecycleConfirm.disabled = busy;
    for (const button of dossierLifecycleButtons) button.disabled = busy;
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
    setText("detailInternalReference", application.application_reference || "Niet beschikbaar");
    setText("detailSupportReference", application.support_reference || "Niet beschikbaar");
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
    const operationalStatus = operatorStatusPresentation(selectedSummary?.operational_status);
    setBadge("detailOperationalStatus", operationalStatus.label, operationalStatus.tone);
    setText("detailZone", selectedSummary?.zone || "Niet beschikbaar");
    setText("detailSubmittedAt", formatDate(selectedSummary?.dossier_date || application.submitted_at));
    renderDossierLifecycle(application);
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

  async function loadDetail(locator, summary = selectedSummary) {
    const requestId = ++detailRequestId;
    selectedSummary = summary;
    selectedDetail = null;
    promote.hidden = true;
    dossierLifecycleDossier.hidden = true;
    dossierLifecycleMessage.textContent = "";
    lifecycleDossier.hidden = true;
    lifecycleMessage.textContent = "";
    detailMessage.textContent = "Aanvraag wordt geladen.";
    try {
      const application = await invoke({ action: "get_application_detail", ...locator });
      if (requestId !== detailRequestId) return false;
      if (listController.state.request_kind && application.request_kind !== listController.state.request_kind) throw new Error("FILTERED_REQUEST_KIND");
      renderDetail(application);
      selectedLocator = locator;
      updateLocation(locator);
      await loadAssignment(application, requestId);
      if (requestId !== detailRequestId) return false;
      if (application.request_kind === "website" && application.project?.project_id) {
        detailMessage.textContent = "Projectdossier wordt geladen.";
        const project = await invoke({ action: "get_project_dossier", project_id: application.project.project_id });
        if (requestId !== detailRequestId) return false;
        renderProjectDossier(project);
      }
      detailMessage.textContent = "";
      return true;
    } catch {
      if (requestId !== detailRequestId) return false;
      if (!selectedDetail) {
        detail.hidden = true;
        detailEmpty.hidden = false;
      }
      detailMessage.textContent = selectedDetail ? "Het projectdossier kon niet worden geladen." : "De aanvraag kon niet worden geladen.";
      return false;
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
      name.textContent = application.organization || application.name;
      const reference = document.createElement("small");
      const applicationPresentation = applicationIdentityPresentation(application);
      reference.textContent = `${applicationPresentation.visibleReference} · ${formatDate(application.dossier_date)}`;
      identity.append(name, reference);
      const statuses = document.createElement("span");
      statuses.className = "application-list__statuses";
      const status = operatorStatusPresentation(application.operational_status);
      statuses.append(badge(status.label, status.tone));
      if (application.zone === "ARCHIVED") statuses.append(badge("ARCHIVED", "amber"));
      if (application.zone === "TRASHED") statuses.append(badge("TRASHED", "red"));
      button.append(identity, statuses);
      const locator = applicationPresentation.locator;
      if (locatorMatchesApplication(selectedLocator, application)) button.setAttribute("aria-current", "true");
      button.addEventListener("click", ()=>{
        for (const candidate of list.querySelectorAll("[aria-current]")) candidate.removeAttribute("aria-current");
        button.setAttribute("aria-current", "true");
        loadDetail(locator, application);
      });
      item.append(button);
      list.append(item);
    }
  }

  async function loadList() {
    return await listController.load();
  }

  async function refreshMutationDetail(locator, selectionRequestId) {
    return await refreshOperatorSelection(listController, locator, {
      isCurrent: ()=>selectionRequestId === detailRequestId && locatorMatchesApplication(locator, selectedLocator),
      close: clearDetail,
      show: async (summary)=>{
        selectedSummary = summary;
        return await loadDetail(locator, summary);
      },
    });
  }

  for (const button of filterButtons) {
    button.addEventListener("click", ()=>{
      const nextFilter = button.dataset.productFilter;
      const requestKind = nextFilter === "all" ? null : nextFilter;
      if (!PRODUCT_FILTERS.has(nextFilter) || requestKind === listController.state.request_kind) return;
      for (const candidate of filterButtons) candidate.setAttribute("aria-pressed", String(candidate === button));
      clearDetail();
      listController.updateQuery({ request_kind: requestKind });
    });
  }

  for (const button of zoneButtons) {
    button.addEventListener("click", ()=>{
      const zone = button.dataset.zone;
      if (!OPERATOR_ZONES.has(zone) || zone === listController.state.zone) return;
      for (const candidate of zoneButtons) candidate.setAttribute("aria-pressed", String(candidate === button));
      clearDetail();
      listController.updateQuery({ zone });
    });
  }

  let searchTimer = null;
  function applySearch() {
    clearTimeout(searchTimer);
    clearDetail();
    return listController.updateQuery({ search: searchInput.value });
  }
  searchInput.addEventListener("input", ()=>{
    clearTimeout(searchTimer);
    searchTimer = setTimeout(applySearch, 300);
  });
  document.getElementById("applicationSearchForm").addEventListener("submit", (event)=>{
    event.preventDefault();
    applySearch();
  });
  statusFilter.addEventListener("change", ()=>{
    clearDetail();
    listController.updateQuery({ operational_status: statusFilter.value || null });
  });
  yearFilter.addEventListener("change", ()=>{
    clearDetail();
    listController.updateQuery({ year: yearFilter.value ? Number(yearFilter.value) : null, quarter: null });
  });
  quarterFilter.addEventListener("change", ()=>{
    clearDetail();
    listController.updateQuery({ quarter: quarterFilter.value || null });
  });
  loadMore.addEventListener("click", ()=>listController.loadMore());

  assignmentOperator.addEventListener("change", renderAssignment);
  assignmentReason.addEventListener("input", renderAssignment);
  assignmentForm.addEventListener("submit", async (event)=>{
    event.preventDefault();
    if (assignmentSubmitting || !assignmentState || !assignmentReference) return;
    let input;
    try {
      input = buildAssignmentCommand(assignmentReference, assignmentState, assignmentOperator.value, assignmentReason.value, crypto.randomUUID());
    } catch {
      assignmentMessage.textContent = "Kies een andere operator en vul bij hertoewijzing een reden in.";
      renderAssignment();
      return;
    }
    const requestId = detailRequestId;
    assignmentSubmitting = true;
    assignmentMessage.textContent = "Toewijzing wordt opgeslagen.";
    renderAssignment();
    try {
      await invoke(input);
      if (requestId === detailRequestId) await loadAssignment(selectedDetail, requestId, "De actuele toewijzing is geladen.");
    } catch (error) {
      if (requestId !== detailRequestId) return;
      assignmentSubmitting = false;
      const outcome = assignmentError(error instanceof Error ? error.message : "INTERNAL_ERROR");
      if (outcome.refresh) await loadAssignment(selectedDetail, requestId, outcome.message);
      else {
        assignmentDossier.hidden = outcome.hide;
        assignmentMessage.textContent = outcome.message;
        renderAssignment();
      }
    } finally {
      assignmentSubmitting = false;
      if (requestId === detailRequestId && !assignmentDossier.hidden) renderAssignment();
    }
  });

  promote.addEventListener("click", ()=>confirmation.showModal());
  confirmation.addEventListener("close", async ()=>{
    if (confirmation.returnValue !== "confirm" || !canPromoteApplication(selectedDetail)) return;
    const locator = { ...selectedLocator };
    const selectionRequestId = detailRequestId;
    promote.disabled = true;
    detailMessage.textContent = "Project wordt aangemaakt.";
    try {
      await invoke({ action: "promote_accepted_application", ...locator, idempotency_key: crypto.randomUUID() });
      const refresh = await refreshMutationDetail(locator, selectionRequestId);
      if (refresh.status === "refreshed") detailMessage.textContent = "Project is gekoppeld.";
    } catch {
      detailMessage.textContent = "Het project kon niet worden aangemaakt.";
    } finally {
      promote.disabled = false;
    }
  });

  for (const button of dossierLifecycleButtons) {
    button.addEventListener("click", ()=>{
      const action = button.dataset.dossierLifecycleAction;
      const presentation = dossierLifecyclePresentation(selectedDetail?.dossier_lifecycle);
      const actionPresentation = dossierLifecycleAction(action);
      if (dossierLifecycleBusy || !presentation?.actions.includes(action) || !actionPresentation || !selectedLocator) return;
      pendingDossierLifecycleAction = {
        action,
        detail: selectedDetail,
        locator: { ...selectedLocator },
        selectionRequestId: detailRequestId,
        presentation: actionPresentation,
      };
      setText("dossierLifecycleDialogTitle", actionPresentation.title);
      setText("dossierLifecycleDialogDescription", actionPresentation.description);
      dossierLifecycleConfirm.textContent = actionPresentation.label;
      dossierLifecycleConfirm.className = action === "trash_dossier" ? "danger-action" : "primary-action primary-action--compact";
      dossierLifecycleReason.value = "";
      dossierLifecycleReason.setCustomValidity("");
      dossierLifecycleDialog.returnValue = "";
      dossierLifecycleDialog.showModal();
      dossierLifecycleReason.focus();
    });
  }

  dossierLifecycleReason.addEventListener("input", ()=>dossierLifecycleReason.setCustomValidity(""));
  dossierLifecycleCancel.addEventListener("click", ()=>dossierLifecycleDialog.close("cancel"));
  dossierLifecycleForm.addEventListener("submit", (event)=>{
    const reason = dossierLifecycleReason.value.trim();
    if (reason.length >= 1 && reason.length <= 500) return;
    event.preventDefault();
    dossierLifecycleReason.setCustomValidity("Vul een korte reden in.");
    dossierLifecycleReason.reportValidity();
  });
  dossierLifecycleDialog.addEventListener("close", async ()=>{
    const command = pendingDossierLifecycleAction;
    pendingDossierLifecycleAction = null;
    if (dossierLifecycleDialog.returnValue !== "confirm" || !command || dossierLifecycleBusy) return;
    if (command.selectionRequestId !== detailRequestId || !locatorMatchesApplication(command.locator, selectedDetail)) {
      dossierLifecycleMessage.textContent = "De dossierselectie is gewijzigd. Open de actie opnieuw vanuit het actuele dossier.";
      return;
    }
    let input;
    try {
      input = buildDossierLifecycleCommand(command.action, command.detail, dossierLifecycleReason.value, crypto.randomUUID());
    } catch {
      dossierLifecycleMessage.textContent = "Vul een geldige reden in en probeer opnieuw.";
      return;
    }
    setDossierLifecycleBusy(true);
    dossierLifecycleMessage.textContent = `${command.presentation.label} wordt uitgevoerd.`;
    let completed = false;
    try {
      const refresh = await refreshAfterOperatorMutation(
        ()=>invoke(input),
        (selectionRequestId)=>refreshMutationDetail(command.locator, selectionRequestId),
        ()=>detailRequestId,
      );
      completed = refresh.status === "refreshed";
      if (completed) dossierLifecycleMessage.textContent = `${command.presentation.label} is uitgevoerd. De actuele dossierstatus is geladen.`;
    } catch (error) {
      const outcome = dossierLifecycleError(error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED");
      if (outcome.refresh) await refreshMutationDetail(command.locator, command.selectionRequestId);
      dossierLifecycleMessage.textContent = outcome.message;
    } finally {
      setDossierLifecycleBusy(false);
      if (selectedDetail) renderDossierLifecycle(selectedDetail);
      if (completed) focusDossierLifecycle(selectedDetail?.dossier_lifecycle, dossierLifecycleButtons, dossierLifecycleTitle);
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
      const refresh = await refreshAfterOperatorMutation(
        ()=>invoke(input),
        (selectionRequestId)=>refreshMutationDetail(command.locator, selectionRequestId),
        ()=>detailRequestId,
      );
      completed = refresh.status === "refreshed";
      if (completed) lifecycleMessage.textContent = `${command.presentation.label} is uitgevoerd. De actuele status is geladen.`;
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

  if (selectedLocator) {
    const initialSearch = selectedLocator.application_reference || selectedLocator.support_reference || selectedLocator.quote_request_id;
    searchInput.value = initialSearch;
    await listController.updateQuery({ search: initialSearch });
    const summary = listController.state.items.find((item)=>locatorMatchesApplication(selectedLocator, item));
    if (summary) await loadDetail(selectedLocator, summary);
    else clearDetail();
  }
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

export function focusDossierLifecycle(lifecycle, buttons, fallback) {
  const actions = dossierLifecyclePresentation(lifecycle)?.actions || [];
  const target = actions
    .map((action)=>buttons.find((button)=>button.dataset.dossierLifecycleAction === action))
    .find((button)=>button && !button.hidden && !button.disabled)
    || fallback;
  target?.focus();
  return target || null;
}

export function applicationLocatorFromUrl(url) {
  const parsed = new URL(url);
  const reference = parsed.searchParams.get("application");
  if (reference && APPLICATION_REFERENCE.test(reference)) return { application_reference: reference };
  const supportReference = normalizeSupportReference(parsed.searchParams.get("support"));
  if (supportReference) return { support_reference: supportReference };
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
    : locator?.support_reference
    ? locator.support_reference === application?.support_reference
    : locator?.quote_request_id === application?.quote_request_id);
}

export function effectiveOperatorZone(zone, search) {
  if (!OPERATOR_ZONES.has(zone)) throw new Error("INVALID_OPERATOR_ZONE");
  if (zone === "ACTIVE" && String(search || "").trim()) return "ACTIVE_ARCHIVED";
  return zone;
}

export function operatorListRequest(query, cursor = null) {
  const search = String(query?.search || "").trim() || null;
  return {
    action: "list_applications_v2",
    zone: effectiveOperatorZone(query?.zone || "ACTIVE", search),
    operational_status: query?.operational_status || null,
    year: query?.year || null,
    quarter: query?.quarter || null,
    request_kind: query?.request_kind || null,
    search,
    cursor,
    limit: OPERATOR_PAGE_LIMIT,
  };
}

export function operatorFacetsRequest(query) {
  const listRequest = operatorListRequest(query);
  return {
    action: "get_application_facets_v2",
    zone: listRequest.zone,
    operational_status: listRequest.operational_status,
    request_kind: listRequest.request_kind,
    search: listRequest.search,
  };
}

export function operatorStatusPresentation(status) {
  if (status === "CANCELLED") return { label: "GEANNULEERD", tone: "red" };
  if (status === "ARCHIVED") return { label: "ARCHIVED", tone: "amber" };
  return { label: String(status || "ONBEKEND").replaceAll("_", " "), tone: status ? "green" : "" };
}

export function appendUniqueOperatorItems(current, incoming) {
  const items = [...current];
  const seen = new Set(items.map((item)=>item.quote_request_id));
  for (const item of incoming) {
    if (!UUID.test(String(item?.quote_request_id || "")) || seen.has(item.quote_request_id)) continue;
    seen.add(item.quote_request_id);
    items.push(item);
  }
  return items;
}

const PERSONAL_QUEUE_FIELDS = new Set(["reference", "source", "zone", "status", "assigned_at", "assignment_revision"]);

export function personalQueueRequest(cursor = null) {
  const request = { action: "get_my_assigned_dossiers", limit: 25 };
  if (cursor) request.cursor = cursor;
  return request;
}

export function appendUniquePersonalQueueItems(current, incoming) {
  const items = [...current];
  const seen = new Set(items.map((item)=>item.reference));
  for (const item of incoming) {
    const keys = item && typeof item === "object" ? Object.keys(item) : [];
    const valid = keys.length === PERSONAL_QUEUE_FIELDS.size
      && keys.every((key)=>PERSONAL_QUEUE_FIELDS.has(key))
      && [item.reference, item.source, item.zone, item.status, item.assigned_at].every((value)=>typeof value === "string" && value.length > 0)
      && Number.isSafeInteger(item.assignment_revision);
    if (!valid) throw new Error("INVALID_PERSONAL_QUEUE");
    if (seen.has(item.reference)) continue;
    seen.add(item.reference);
    items.push(item);
  }
  return items;
}

export async function resolveDashboardAuthority({ loadPersonalQueue, getPersonalQueueError, loadManagerAuthority }) {
  if (await loadPersonalQueue()) return "personal";
  if (getPersonalQueueError() !== "OPERATOR_NOT_AUTHORIZED") return "closed";
  try {
    return await loadManagerAuthority() ? "manager" : "closed";
  } catch {
    return "closed";
  }
}

export function createPersonalQueueController(invoke, onChange = ()=>{}) {
  const state = { items: [], has_more: false, next_cursor: null, loading: false, error: null };
  const publish = ()=>onChange({ ...state, items: [...state.items] });

  async function loadPage({ append = false } = {}) {
    if (state.loading || (append && (!state.has_more || !state.next_cursor))) return false;
    const cursor = append ? state.next_cursor : null;
    state.loading = true;
    state.error = null;
    publish();
    try {
      const page = await invoke(personalQueueRequest(cursor));
      if (!page || !Array.isArray(page.items) || typeof page.has_more !== "boolean"
        || (page.next_cursor !== null && typeof page.next_cursor !== "string")
        || (page.has_more && !page.next_cursor)) throw new Error("INVALID_PERSONAL_QUEUE");
      state.items = append
        ? appendUniquePersonalQueueItems(state.items, page.items)
        : appendUniquePersonalQueueItems([], page.items);
      state.has_more = page.has_more;
      state.next_cursor = page.next_cursor;
      return true;
    } catch (error) {
      state.error = error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED";
      return false;
    } finally {
      state.loading = false;
      publish();
    }
  }

  return {
    state,
    load: ()=>loadPage(),
    loadMore: ()=>loadPage({ append: true }),
    refresh: ()=>{
      if (state.loading) return Promise.resolve(false);
      state.items = [];
      state.has_more = false;
      state.next_cursor = null;
      state.error = null;
      publish();
      return loadPage();
    },
  };
}

const CUSTOMER_REQUEST_LIST_FIELDS = new Set([
  "request_id", "request_reference", "request_type", "title", "status",
  "priority", "submitted_at", "updated_at", "revision",
]);
const CUSTOMER_REQUEST_DETAIL_FIELDS = new Set([
  "request_id", "request_reference", "source", "request_type", "title",
  "description", "status", "priority", "submitted_at", "revision", "updated_at", "upload_request",
]);

function exactCustomerRequestProjection(value, fields) {
  const keys = value && typeof value === "object" ? Object.keys(value) : [];
  return keys.length === fields.size && keys.every((key)=>fields.has(key));
}

export function customerRequestsForDossierRequest(dossierReference, cursor = null) {
  const request = { action: "list_customer_requests_for_dossier", dossier_reference: dossierReference, limit: 25 };
  if (cursor) request.cursor = cursor;
  return request;
}

export function customerRequestDetailRequest(requestId) {
  return { action: "get_customer_request", request_id: requestId };
}

export function customerRequestTransitionRequest(request, commandType, idempotencyKey) {
  return {
    action: "transition_customer_request",
    request_id: request.request_id,
    command_type: commandType,
    expected_revision: request.revision,
    idempotency_key: idempotencyKey,
  };
}

export function customerRequestUploadCreateRequest(requestId, idempotencyKey) {
  return { action: "create_customer_request_upload_link", request_id: requestId, idempotency_key: idempotencyKey };
}

export function customerRequestUploadRevokeRequest(uploadRequestId, idempotencyKey) {
  return {
    action: "revoke_customer_request_upload_link",
    upload_request_id: uploadRequestId,
    reason: "Operator heeft de uploadlink ingetrokken.",
    idempotency_key: idempotencyKey,
  };
}

export function customerRequestWorkCommand(status) {
  if (status === "TRIAGED") return "START";
  if (status === "IN_PROGRESS") return "REQUIRE_CUSTOMER_RESPONSE";
  if (status === "WAITING_CUSTOMER") return "RESUME";
  return null;
}

export function appendUniqueCustomerRequestItems(current, incoming) {
  const items = [...current];
  const seen = new Set(items.map((item)=>item.request_id));
  for (const item of incoming) {
    const valid = exactCustomerRequestProjection(item, CUSTOMER_REQUEST_LIST_FIELDS)
      && UUID.test(String(item.request_id || ""))
      && [item.request_reference, item.request_type, item.title, item.status, item.submitted_at, item.updated_at]
        .every((value)=>typeof value === "string" && value.length > 0)
      && (item.priority === null || typeof item.priority === "string")
      && Number.isSafeInteger(item.revision) && item.revision >= 0;
    if (!valid) throw new Error("INVALID_CUSTOMER_REQUEST_LIST");
    if (seen.has(item.request_id)) continue;
    seen.add(item.request_id);
    items.push(item);
  }
  return items;
}

export function validateCustomerRequestDetail(request) {
  const uploadRequest = request?.upload_request;
  const validUploadRequest = uploadRequest === null || (
    exactCustomerRequestProjection(uploadRequest, new Set(["upload_request_id", "status", "expires_at"]))
    && UUID.test(String(uploadRequest.upload_request_id || ""))
    && uploadRequest.status === "ACTIVE"
    && typeof uploadRequest.expires_at === "string" && uploadRequest.expires_at.length > 0
  );
  const valid = exactCustomerRequestProjection(request, CUSTOMER_REQUEST_DETAIL_FIELDS)
    && UUID.test(String(request?.request_id || ""))
    && [request.request_reference, request.source, request.request_type, request.title, request.description, request.status, request.submitted_at, request.updated_at]
      .every((value)=>typeof value === "string" && value.length > 0)
    && (request.priority === null || typeof request.priority === "string")
    && Number.isSafeInteger(request.revision) && request.revision >= 0
    && validUploadRequest;
  if (!valid) throw new Error("INVALID_CUSTOMER_REQUEST_DETAIL");
  return request;
}

export function createCustomerRequestListController(invoke, onChange = ()=>{}) {
  const state = { dossier_reference: null, items: [], has_more: false, next_cursor: null, loading: false, error: null };
  let generation = 0;
  const publish = ()=>onChange({ ...state, items: [...state.items] });

  async function loadPage({ append = false, expectedGeneration = generation } = {}) {
    if (!state.dossier_reference || state.loading || expectedGeneration !== generation
      || (append && (!state.has_more || !state.next_cursor))) return false;
    const dossierReference = state.dossier_reference;
    const cursor = append ? state.next_cursor : null;
    state.loading = true;
    state.error = null;
    publish();
    try {
      const page = await invoke(customerRequestsForDossierRequest(dossierReference, cursor));
      if (expectedGeneration !== generation || dossierReference !== state.dossier_reference) return false;
      if (!page || !Array.isArray(page.items) || typeof page.has_more !== "boolean"
        || (page.next_cursor !== null && typeof page.next_cursor !== "string")
        || (page.has_more && !page.next_cursor)) throw new Error("INVALID_CUSTOMER_REQUEST_LIST");
      state.items = append
        ? appendUniqueCustomerRequestItems(state.items, page.items)
        : appendUniqueCustomerRequestItems([], page.items);
      state.has_more = page.has_more;
      state.next_cursor = page.next_cursor;
      return true;
    } catch (error) {
      if (expectedGeneration !== generation) return false;
      state.items = [];
      state.has_more = false;
      state.next_cursor = null;
      state.error = error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED";
      return false;
    } finally {
      if (expectedGeneration === generation) {
        state.loading = false;
        publish();
      }
    }
  }

  return {
    state,
    selectDossier: (dossierReference)=>{
      generation += 1;
      state.dossier_reference = dossierReference;
      state.items = [];
      state.has_more = false;
      state.next_cursor = null;
      state.loading = false;
      state.error = null;
      publish();
      return loadPage({ expectedGeneration: generation });
    },
    loadMore: ()=>loadPage({ append: true }),
    clear: ()=>{
      generation += 1;
      state.dossier_reference = null;
      state.items = [];
      state.has_more = false;
      state.next_cursor = null;
      state.loading = false;
      state.error = null;
      publish();
    },
  };
}

export function createCustomerRequestDetailController(invoke, onChange = ()=>{}, randomUUID = ()=>crypto.randomUUID()) {
  const state = { request_id: null, request: null, upload_url: null, loading: false, submitting: false, error: null };
  let generation = 0;
  const publish = ()=>onChange({ ...state, request: state.request ? { ...state.request } : null });

  async function selectRequest(requestId) {
    generation += 1;
    const expectedGeneration = generation;
    state.request_id = requestId;
    state.request = null;
    state.upload_url = null;
    state.loading = Boolean(requestId);
    state.submitting = false;
    state.error = null;
    publish();
    if (!requestId) return false;
    try {
      const request = validateCustomerRequestDetail(await invoke(customerRequestDetailRequest(requestId)));
      if (expectedGeneration !== generation || requestId !== state.request_id) return false;
      state.request = request;
      return true;
    } catch (error) {
      if (expectedGeneration !== generation) return false;
      state.request = null;
      state.error = error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED";
      return false;
    } finally {
      if (expectedGeneration === generation) {
        state.loading = false;
        publish();
      }
    }
  }

  async function transition(commandType) {
    const request = state.request;
    if (!request || state.submitting || customerRequestWorkCommand(request.status) !== commandType) return false;
    const expectedGeneration = generation;
    state.submitting = true;
    state.error = null;
    publish();
    try {
      await invoke(customerRequestTransitionRequest(request, commandType, randomUUID()));
      const refreshed = validateCustomerRequestDetail(await invoke(customerRequestDetailRequest(request.request_id)));
      if (expectedGeneration !== generation || request.request_id !== state.request_id) return false;
      state.request = refreshed;
      return true;
    } catch (error) {
      if (expectedGeneration !== generation) return false;
      state.request = null;
      state.error = error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED";
      return false;
    } finally {
      if (expectedGeneration === generation) {
        state.submitting = false;
        publish();
      }
    }
  }

  async function createUploadLink() {
    const request = state.request;
    if (!request || request.upload_request || state.submitting) return false;
    const expectedGeneration = generation;
    state.submitting = true;
    state.error = null;
    publish();
    try {
      const result = await invoke(customerRequestUploadCreateRequest(request.request_id, randomUUID()));
      const valid = exactCustomerRequestProjection(result, new Set(["state", "upload_request_id", "expires_at", "was_created", "upload_url"]))
        && result.state === "ACTIVE" && UUID.test(String(result.upload_request_id || ""))
        && typeof result.expires_at === "string" && typeof result.was_created === "boolean"
        && typeof result.upload_url === "string" && /^https:\/\/[^#]+\/pages\/customer-request-upload\.html#token=[A-Za-z0-9_-]{43}$/.test(result.upload_url);
      if (!valid) throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_LINK");
      if (expectedGeneration !== generation || request.request_id !== state.request_id) return false;
      state.request = { ...request, upload_request: { upload_request_id: result.upload_request_id, status: "ACTIVE", expires_at: result.expires_at } };
      state.upload_url = result.upload_url;
      return true;
    } catch (error) {
      if (expectedGeneration !== generation) return false;
      state.error = error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED";
      return false;
    } finally {
      if (expectedGeneration === generation) {
        state.submitting = false;
        publish();
      }
    }
  }

  async function revokeUploadLink() {
    const request = state.request;
    const uploadRequestId = request?.upload_request?.upload_request_id;
    if (!request || !uploadRequestId || state.submitting) return false;
    const expectedGeneration = generation;
    state.submitting = true;
    state.error = null;
    publish();
    try {
      const result = await invoke(customerRequestUploadRevokeRequest(uploadRequestId, randomUUID()));
      const valid = exactCustomerRequestProjection(result, new Set(["state", "upload_request_id", "was_revoked"]))
        && result.state === "REVOKED" && result.upload_request_id === uploadRequestId && result.was_revoked === true;
      if (!valid) throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_REVOKE");
      if (expectedGeneration !== generation || request.request_id !== state.request_id) return false;
      state.request = { ...request, upload_request: null };
      state.upload_url = null;
      return true;
    } catch (error) {
      if (expectedGeneration !== generation) return false;
      state.error = error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED";
      return false;
    } finally {
      if (expectedGeneration === generation) {
        state.submitting = false;
        publish();
      }
    }
  }

  return { state, selectRequest, transition, createUploadLink, revokeUploadLink, clear: ()=>selectRequest(null) };
}

export function operatorFacetSelection(facets, selectedYear, selectedQuarter) {
  const years = Array.isArray(facets?.years) ? facets.years : [];
  const year = years.find((entry)=>entry.year === selectedYear);
  const quarter = year?.quarters?.find((entry)=>entry.quarter === selectedQuarter && Number(entry.count) > 0);
  return {
    year: year ? selectedYear : null,
    quarter: quarter ? selectedQuarter : null,
  };
}

export function operatorListVisibility(state) {
  const loading = Boolean(state?.loading);
  const hasItems = Array.isArray(state?.items) && state.items.length > 0;
  return {
    message: loading
      ? hasItems ? "Meer dossiers laden..." : "Dossiers laden..."
      : state?.error ? "De dossiers konden niet worden geladen." : "",
    emptyHidden: loading || Boolean(state?.error) || hasItems,
  };
}

export async function refreshOperatorSelection(controller, locator, handlers) {
  const loaded = await controller.refresh();
  if (!handlers.isCurrent()) return { status: "superseded", summary: null };
  if (!loaded) {
    handlers.close();
    return { status: "closed", summary: null };
  }
  const summary = controller.state.items.find((item)=>locatorMatchesApplication(locator, item)) || null;
  if (!summary) {
    handlers.close();
    return { status: "closed", summary: null };
  }
  const shown = await handlers.show(summary);
  return { status: shown === false ? "superseded" : "refreshed", summary };
}

export async function refreshAfterOperatorMutation(invokeMutation, refreshSelection, getSelectionRequestId) {
  const selectionRequestId = getSelectionRequestId();
  await invokeMutation();
  return await refreshSelection(selectionRequestId);
}

export function createOperatorListController(invoke, onChange = ()=>{}) {
  const state = {
    zone: "ACTIVE",
    operational_status: null,
    year: null,
    quarter: null,
    request_kind: null,
    search: "",
    next_cursor: null,
    items: [],
    facets: { years: [] },
    loading: false,
    error: null,
    generation: 0,
  };

  const publish = ()=>onChange({ ...state, items: [...state.items], facets: state.facets });

  async function loadPage({ append = false, retryCursor = true } = {}) {
    if (state.loading) return false;
    const generation = state.generation;
    const cursor = append ? state.next_cursor : null;
    if (append && !cursor) return false;
    state.loading = true;
    state.error = null;
    publish();
    try {
      const listPromise = invoke(operatorListRequest(state, cursor));
      const facetsPromise = append ? null : invoke(operatorFacetsRequest(state));
      const [page, facets] = await Promise.all([listPromise, facetsPromise]);
      if (generation !== state.generation) return false;
      if (!page || !Array.isArray(page.items) || (page.next_cursor !== null && typeof page.next_cursor !== "string")) {
        throw new Error("INVALID_APPLICATION_LIST");
      }
      state.items = append ? appendUniqueOperatorItems(state.items, page.items) : appendUniqueOperatorItems([], page.items);
      state.next_cursor = page.next_cursor;
      if (facets !== null) {
        state.facets = facets && Array.isArray(facets.years) ? facets : { years: [] };
        const selection = operatorFacetSelection(state.facets, state.year, state.quarter);
        if (selection.year !== state.year || selection.quarter !== state.quarter) {
          state.year = selection.year;
          state.quarter = selection.quarter;
          state.items = [];
          state.next_cursor = null;
          state.loading = false;
          state.generation += 1;
          publish();
          return loadPage();
        }
      }
      return true;
    } catch (error) {
      if (generation !== state.generation) return false;
      const code = error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED";
      if (cursor && retryCursor && code === "INVALID_OPERATOR_CURSOR") {
        state.loading = false;
        state.items = [];
        state.next_cursor = null;
        return loadPage({ append: false, retryCursor: false });
      }
      state.error = code;
      return false;
    } finally {
      if (generation === state.generation) {
        state.loading = false;
        publish();
      }
    }
  }

  function updateQuery(patch) {
    const next = { ...patch };
    if (Object.hasOwn(next, "search")) next.search = String(next.search || "").trim();
    if (Object.hasOwn(next, "year") && !next.year) next.quarter = null;
    Object.assign(state, next, {
      next_cursor: null,
      items: [],
      loading: false,
      error: null,
      generation: state.generation + 1,
    });
    publish();
    return loadPage();
  }

  return {
    state,
    load: ()=>loadPage(),
    refresh: ()=>updateQuery({}),
    loadMore: ()=>loadPage({ append: true }),
    updateQuery,
  };
}
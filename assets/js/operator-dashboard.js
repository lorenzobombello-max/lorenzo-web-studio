import { callCommercialOperator } from "./operator-auth-core.mjs";
import {
  downloadApplicationDossierPdf,
  printApplicationDossier,
  renderApplicationDossier,
} from "./application-dossier-copy.js?v=20260828-dossier-purge-ui";
import {
  printSdfQualificationReview,
  renderSdfQualificationReview,
} from "./sdf-qualification-review.mjs?v=20260831-operator-parity";
import { initializeOperatorMessages } from "./operator-messages.mjs?v=20260903-auto-refresh-8s";
import { initializeOperatorCalendar } from "./operator-calendar.mjs?v=20260905-calendar-selection-r1";
import { initializeOperatorRecruitment } from "./operator-recruitment.mjs?v=20260903-auto-refresh-8s";
import { initializeOperatorWorkforce } from "./operator-workforce.mjs?v=20260903-auto-refresh-8s";
import { initializeOperatorFinance } from "./operator-finance.mjs?v=20260903-auto-refresh-8s";
import { initializeOperatorDossiers } from "./operator-dossiers.mjs?v=20260905-dossiers-purge-aal2-r1";
import { initializeOperatorProfile } from "./operator-profile.mjs?v=20260905-profile-welcome-r2";

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
  profile_only: "PROFIEL",
});
const OPERATOR_MODULES = new Set(["profile", "dossiers", "intake", "finance", "workforce", "recruitment", "messages", "calendar"]);
const FINANCE_TABS = new Set(["overview", "websites", "sdf", "workforce", "expenses", "inbox", "owner"]);

function exactObjectKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every((key)=>Object.hasOwn(value, key));
}

function localDateInputValue(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function operatorModuleFromUrl(url, role) {
  const parsed = new URL(url, "https://operator.invalid");
  const module = parsed.searchParams.get("module") || "profile";
  if (module === "profile") return module;
  if (parsed.searchParams.has("application") || parsed.searchParams.has("request") || parsed.searchParams.has("support")) {
    return "dossiers";
  }
  if (role === "profile_only") return "profile";
  if (module === "intake" && ["owner", "admin"].includes(role)) return module;
  if (role !== "owner") return "dossiers";
  return OPERATOR_MODULES.has(module) ? module : "dossiers";
}

export function financeTabFromUrl(url, role) {
  const parsed = new URL(url, "https://operator.invalid");
  if (operatorModuleFromUrl(parsed, role) !== "finance") return "overview";
  const tab = parsed.searchParams.get("financeTab") || "overview";
  return FINANCE_TABS.has(tab) ? tab : "overview";
}

function createOperatorNavigation({ identity, initialUrl, routeFromUrl, activateRoute, loadRoute, pushUrl, shouldReloadRoute = ()=>false }) {
  let verifiedIdentity = identity;
  let currentUrl = new URL(initialUrl, "https://operator.invalid");
  let currentRoute = routeFromUrl(currentUrl, identity?.role);
  let generation = 0;
  const initialized = new Set([currentRoute]);
  const initializing = new Map();

  async function navigate(url, { push = true } = {}) {
    if (!verifiedIdentity) return false;
    const nextUrl = new URL(url, currentUrl);
    const route = routeFromUrl(nextUrl, verifiedIdentity.role);
    currentUrl = nextUrl;
    currentRoute = route;
    const requestGeneration = ++generation;
    if (push) pushUrl(`${nextUrl.pathname}${nextUrl.search}${nextUrl.hash}`);
    activateRoute(route, nextUrl);
    if (initialized.has(route) && !shouldReloadRoute(route)) return true;
    if (!initializing.has(route)) {
      const initialization = Promise.resolve(loadRoute(route, {
        identity: verifiedIdentity,
        url: nextUrl,
        isCurrent: ()=>Boolean(verifiedIdentity) && currentRoute === route,
      })).then((loaded)=>{
        if (loaded !== false) initialized.add(route);
        return loaded;
      }).finally(()=>initializing.delete(route));
      initializing.set(route, initialization);
    }
    const loaded = await initializing.get(route);
    return Boolean(verifiedIdentity) && requestGeneration === generation && loaded !== false;
  }

  return {
    navigate,
    invalidateIdentity: ()=>{
      verifiedIdentity = null;
      generation += 1;
      initialized.clear();
      initializing.clear();
    },
    get identity() {
      return verifiedIdentity;
    },
  };
}

export function createOperatorModuleNavigation({ identity, initialUrl, activateModule, loadModule, pushUrl }) {
  return createOperatorNavigation({
    identity,
    initialUrl,
    routeFromUrl: operatorModuleFromUrl,
    activateRoute: activateModule,
    loadRoute: loadModule,
    pushUrl,
    shouldReloadRoute: (route)=>route === "dossiers",
  });
}

export function createOperatorFinanceNavigation({ identity, initialUrl, activateTab, loadTab, pushUrl }) {
  return createOperatorNavigation({
    identity,
    initialUrl,
    routeFromUrl: financeTabFromUrl,
    activateRoute: activateTab,
    loadRoute: loadTab,
    pushUrl,
  });
}

export function presentOperatorModule(root, module) {
  for (const link of root.querySelectorAll("[data-operator-module]")) {
    if (link.dataset.operatorModule === module) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  for (const panel of root.querySelectorAll("[data-module-panel]")) {
    panel.hidden = panel.dataset.modulePanel !== module;
  }
}

export function presentFinanceTab(root, tab) {
  for (const link of root.querySelectorAll("[data-finance-tab]")) {
    if (link.dataset.financeTab === tab) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  for (const panel of root.querySelectorAll("[data-finance-tab-panel]")) {
    panel.hidden = panel.dataset.financeTabPanel !== tab;
  }
}

export function isOperatorAuthorizationFailure(code) {
  return new Set([
    "AUTHENTICATION_REQUIRED",
    "INVALID_JWT",
    "HUMAN_JWT_REQUIRED",
    "OPERATOR_NOT_AUTHORIZED",
  ]).has(String(code || ""));
}

const FINANCE_UNAVAILABLE_FLAGS = Object.freeze([
  "invoice_projection_available",
  "outstanding_projection_available",
  "overdue_projection_available",
  "upcoming_projection_available",
  "recurring_amount_projection_available",
  "bank_actuals_projection_available",
]);

const SDF_FINANCE_UNAVAILABLE_FLAGS = Object.freeze([
  "expected_payment_available",
  "payment_evidence_available",
  "confirmed_received_available",
  "outstanding_projection_available",
  "overdue_projection_available",
  "upcoming_projection_available",
  "recurring_amount_projection_available",
]);
const SDF_FINANCE_PROJECT_PII = Object.freeze([
  "name", "company", "email", "phone", "address", "billing_address",
  "customer_snapshot", "seller_snapshot", "bank_snapshot",
]);
const BUSINESS_EXPENSE_AVAILABILITY_FLAGS = Object.freeze([
  "payment_state_available", "paid_amount_available", "paid_date_available",
  "confirmed_cash_out_available", "outstanding_available", "overdue_available",
  "upcoming_available", "vat_available", "deductible_vat_available",
  "bank_actuals_available", "recurring_available",
]);
const BUSINESS_EXPENSE_FIELDS = new Set([
  "id", "supplier_name", "description", "category", "amount_minor", "currency",
  "expense_date", "status", "document_count", "relation_types",
]);
const BUSINESS_EXPENSE_ROOT_FIELDS = new Set([
  "scope", "expense_count", "currency_totals", "expenses", "availability", "bank_actuals",
]);
const BUSINESS_EXPENSE_CATEGORY_LABELS = Object.freeze({
  software: "Software", hosting: "Hosting", telecom: "Telecom", accounting: "Boekhouding",
  hardware: "Hardware", marketing: "Marketing", insurance: "Verzekering", education: "Opleiding",
  office: "Kantoor", transport: "Transport", other: "Overig",
});
const BUSINESS_EXPENSE_RELATION_LABELS = Object.freeze({
  INVOICE: "Factuur", CREDIT_NOTE: "Creditnota", RECEIPT: "Kassaticket / ontvangstbewijs",
  CONTRACT: "Contract", OTHER: "Overig",
});
export const SUPPLIER_DOCUMENT_TYPES = Object.freeze(["INVOICE", "CREDIT_NOTE", "RECEIPT", "CONTRACT", "OTHER"]);
export const SUPPLIER_DOCUMENT_RELATION_TYPES = Object.freeze([...SUPPLIER_DOCUMENT_TYPES]);
export const SUPPLIER_DOCUMENT_ACCEPT = "application/pdf,image/png,image/jpeg";
export const SUPPLIER_DOCUMENT_MAX_BYTES = 10 * 1024 * 1024;
export const DOCUMENT_INBOX_STATUSES = Object.freeze(["RECEIVED", "REVIEW_REQUIRED", "APPROVED", "PROCESSED", "REJECTED"]);
export const DOCUMENT_INBOX_EXTRACTION_STATUSES = Object.freeze(["NOT_RECORDED", "SUCCEEDED", "PARTIAL", "ERROR"]);
export const DOCUMENT_INBOX_DOCUMENT_TYPES = Object.freeze([...SUPPLIER_DOCUMENT_TYPES]);
export const DOCUMENT_INBOX_CATEGORIES = Object.freeze([
  "software", "hosting", "telecom", "accounting", "hardware", "marketing",
  "insurance", "education", "office", "transport", "other",
]);
const DOCUMENT_INBOX_STATUS_LABELS = Object.freeze({
  RECEIVED: "Ontvangen", REVIEW_REQUIRED: "Te beoordelen", APPROVED: "Goedgekeurd",
  PROCESSED: "Verwerkt", REJECTED: "Afgewezen",
});
const DOCUMENT_INBOX_EXTRACTION_LABELS = Object.freeze({
  NOT_RECORDED: "Nog niet geanalyseerd", SUCCEEDED: "Analyse voltooid",
  PARTIAL: "Gedeeltelijke analyse", ERROR: "Analyse niet beschikbaar",
});
const DOCUMENT_INBOX_CANDIDATE_LABELS = Object.freeze({
  supplier_name: "Leverancier", document_reference: "Documentreferentie",
  document_date: "Documentdatum", document_type: "Documenttype", amount: "Bedrag",
  currency: "Valuta", due_date: "Vervaldatum", vat_amount: "Btw-bedrag",
});

export function documentInboxStatusPresentation(status) {
  if (!DOCUMENT_INBOX_STATUSES.includes(status)) throw new Error("INVALID_DOCUMENT_INBOX_STATUS");
  return {
    status,
    label: DOCUMENT_INBOX_STATUS_LABELS[status],
    tone: status === "PROCESSED" ? "green" : status === "REJECTED" ? "red" : status === "REVIEW_REQUIRED" ? "amber" : "neutral",
  };
}

export function documentInboxExtractionRequest(item) {
  if (!item || !["RECEIVED", "REVIEW_REQUIRED"].includes(item.lifecycle_status)) throw new Error("DOCUMENT_INBOX_NOT_REVIEWABLE");
  if (!UUID.test(String(item.id || "")) || !Number.isSafeInteger(item.revision) || item.revision < 1) throw new Error("INVALID_DOCUMENT_INBOX_EXTRACTION_REQUEST");
  return { document_inbox_item_id: item.id, expected_revision: item.revision };
}

export function documentInboxExtractionPresentation(item) {
  const extractionStatus = String(item?.extraction_status || "");
  const source = item?.extraction_candidates;
  if (!DOCUMENT_INBOX_EXTRACTION_STATUSES.includes(extractionStatus)
      || !source || typeof source !== "object" || Array.isArray(source)) throw new Error("INVALID_DOCUMENT_INBOX_EXTRACTION");
  const candidates = Object.entries(source).map(([name, candidate])=>{
    const value = candidate?.value;
    const confidence = candidate?.confidence;
    const evidence = candidate?.evidence;
    if (!/^[a-z][a-z0-9_]{0,63}$/.test(name)
        || (typeof value !== "string" && typeof value !== "number")
        || !Number.isFinite(confidence) || confidence < 0 || confidence > 1
        || typeof evidence !== "string" || !evidence.trim()) throw new Error("INVALID_DOCUMENT_INBOX_EXTRACTION_CANDIDATE");
    return {
      name,
      label: DOCUMENT_INBOX_CANDIDATE_LABELS[name] || name.replaceAll("_", " "),
      value: String(value),
      confidence: `${Math.round(confidence * 100)}%`,
      evidence: evidence.trim(),
    };
  });
  return {
    status: extractionStatus,
    label: DOCUMENT_INBOX_EXTRACTION_LABELS[extractionStatus],
    tone: extractionStatus === "SUCCEEDED" ? "green" : extractionStatus === "PARTIAL" ? "amber" : extractionStatus === "ERROR" ? "red" : "neutral",
    message: extractionStatus === "SUCCEEDED" ? "Extractievoorstellen zijn beschikbaar voor menselijke controle."
      : extractionStatus === "PARTIAL" ? "De analyse is gedeeltelijk. Controleer alle voorstellen en bewijsgegevens."
      : extractionStatus === "ERROR" ? "Analyse niet beschikbaar. Probeer opnieuw of beoordeel het document handmatig."
      : "Start de analyse om niet-definitieve voorstellen te verzamelen.",
    candidates,
  };
}

export function documentInboxExtractionResponse(data) {
  if (!data || data.ok !== true || data.code !== "DOCUMENT_INBOX_EXTRACTION_RECORDED"
      || !UUID.test(String(data.id || "")) || !DOCUMENT_INBOX_STATUSES.includes(data.status)
      || !Number.isSafeInteger(data.revision) || data.revision < 1
      || !DOCUMENT_INBOX_EXTRACTION_STATUSES.includes(data.extraction_status)
      || !data.extraction_candidates || typeof data.extraction_candidates !== "object" || Array.isArray(data.extraction_candidates)) {
    throw new Error("INVALID_DOCUMENT_INBOX_EXTRACTION_RESPONSE");
  }
  return data;
}

export function documentInboxExtractionFailure(error) {
  const code = String(error?.code || error?.message || "");
  const status = Number(error?.status || error?.context?.status || 0);
  if (status === 409 || code === "DOCUMENT_INBOX_REVISION_CONFLICT") return "REVISION_CONFLICT";
  if (status === 401 || status === 403 || /AUTHENTICATION_REQUIRED|OWNER_REQUIRED/.test(code)) return "AUTHORIZATION";
  return "UNAVAILABLE";
}

export function documentInboxReadPresentation(data) {
  if (!data || data.scope !== "document_inbox" || !Array.isArray(data.items)) throw new Error("INVALID_DOCUMENT_INBOX_RESPONSE");
  for (const item of data.items) {
    if (!item || !UUID.test(String(item.id || "")) || !DOCUMENT_INBOX_STATUSES.includes(item.lifecycle_status)
        || !Number.isSafeInteger(item.revision) || item.revision < 0 || !Array.isArray(item.warnings)
        || !DOCUMENT_INBOX_EXTRACTION_STATUSES.includes(item.extraction_status)
        || !item.extraction_candidates || typeof item.extraction_candidates !== "object" || Array.isArray(item.extraction_candidates)
        || !["production", "internal_e2e"].includes(item.record_classification)) {
      throw new Error("INVALID_DOCUMENT_INBOX_ITEM");
    }
  }
  return data;
}

export function documentInboxFilter(items, filters = {}) {
  const query = String(filters.search || "").trim().toLocaleLowerCase("nl-BE");
  const status = String(filters.status || "");
  const documentType = String(filters.documentType || "");
  const from = String(filters.from || "");
  const to = String(filters.to || "");
  if (status && !DOCUMENT_INBOX_STATUSES.includes(status)) throw new Error("INVALID_DOCUMENT_INBOX_FILTER");
  if (documentType && !DOCUMENT_INBOX_DOCUMENT_TYPES.includes(documentType)) throw new Error("INVALID_DOCUMENT_INBOX_FILTER");
  const filtered = items.filter((item) => {
    const haystack = [item.confirmed_supplier_name, item.proposed_supplier_name, item.confirmed_document_reference, item.proposed_document_reference]
      .filter(Boolean).join(" ").toLocaleLowerCase("nl-BE");
    const receivedDate = String(item.received_at || "").slice(0, 10);
    return (!query || haystack.includes(query))
      && (!status || item.lifecycle_status === status)
      && (!documentType || (item.confirmed_document_type || item.proposed_document_type) === documentType)
      && (!from || receivedDate >= from) && (!to || receivedDate <= to);
  });
  return filtered.sort((left, right) => {
    const order = String(right.received_at || "").localeCompare(String(left.received_at || "")) || String(right.id).localeCompare(String(left.id));
    return filters.sort === "oldest" ? -order : order;
  });
}

function documentInboxBoundedValues(values) {
  const supplierName = String(values?.supplier_name || "").trim();
  const documentType = String(values?.document_type || "");
  const documentReference = String(values?.document_reference || "").trim();
  const documentDate = String(values?.document_date || "");
  const amountMinor = businessExpenseAmountMinor(values?.amount);
  const description = String(values?.description || "").trim();
  const category = String(values?.category || "");
  const expenseDate = String(values?.expense_date || "");
  const relationType = String(values?.relation_type || "");
  if (!supplierName || supplierName.length > 200 || !DOCUMENT_INBOX_DOCUMENT_TYPES.includes(documentType)
      || documentReference.length > 200 || (documentDate && !/^\d{4}-\d{2}-\d{2}$/.test(documentDate))
      || amountMinor === null || String(values?.currency || "") !== "EUR"
      || !description || description.length > 1000 || !DOCUMENT_INBOX_CATEGORIES.includes(category)
      || !/^\d{4}-\d{2}-\d{2}$/.test(expenseDate) || !DOCUMENT_INBOX_DOCUMENT_TYPES.includes(relationType)) {
    throw new Error("INVALID_DOCUMENT_INBOX_VALUES");
  }
  return {
    p_supplier_name: supplierName, p_document_type: documentType,
    p_document_reference: documentReference || null, p_document_date: documentDate || null,
    p_amount_minor: amountMinor, p_currency: "EUR", p_description: description,
    p_category: category, p_expense_date: expenseDate, p_relation_type: relationType,
  };
}

export function documentInboxProposalRequest(item, values) {
  if (!item || !["RECEIVED", "REVIEW_REQUIRED"].includes(item.lifecycle_status)) throw new Error("DOCUMENT_INBOX_NOT_REVIEWABLE");
  return { p_inbox_item_id: item.id, p_expected_revision: item.revision, ...documentInboxBoundedValues(values), p_warnings: item.warnings };
}

export function documentInboxConfirmRequest(item, values) {
  if (!item || item.lifecycle_status !== "REVIEW_REQUIRED") throw new Error("DOCUMENT_INBOX_NOT_CONFIRMABLE");
  return { p_inbox_item_id: item.id, p_expected_revision: item.revision, ...documentInboxBoundedValues(values) };
}

export function documentInboxApproveRequest(item, acknowledgeWarnings) {
  if (!item || item.lifecycle_status !== "REVIEW_REQUIRED") throw new Error("DOCUMENT_INBOX_NOT_APPROVABLE");
  return { p_inbox_item_id: item.id, p_expected_revision: item.revision, p_acknowledge_warnings: Boolean(acknowledgeWarnings) };
}

export function documentInboxRejectRequest(item, reason = "") {
  const normalizedReason = String(reason).trim();
  if (!item || !["RECEIVED", "REVIEW_REQUIRED"].includes(item.lifecycle_status) || normalizedReason.length > 500) throw new Error("DOCUMENT_INBOX_NOT_REJECTABLE");
  return { p_inbox_item_id: item.id, p_expected_revision: item.revision, p_reason: normalizedReason || null };
}

export function documentInboxProcessRequest(item) {
  if (!item || item.lifecycle_status !== "APPROVED") throw new Error("DOCUMENT_INBOX_NOT_PROCESSABLE");
  return { p_inbox_item_id: item.id, p_expected_revision: item.revision };
}

export function createDocumentInboxCommandController({ execute, reload, onBusy, onSuccess, onFailure }) {
  let busy = false;
  return {
    get submitting() { return busy; },
    async submit(rpc, request) {
      if (busy) return false;
      busy = true;
      onBusy(true);
      try {
        const result = await execute(rpc, request);
        await reload();
        if (result?.ok === false) {
          onFailure(result.error_code || "DOCUMENT_INBOX_PROCESSING_ERROR");
          return false;
        }
        onSuccess(result);
        return true;
      } catch (error) {
        onFailure(error?.message || "DOCUMENT_INBOX_COMMAND_FAILED");
        return false;
      } finally {
        busy = false;
        onBusy(false);
      }
    },
  };
}

export function createDocumentInboxExtractionController({ execute, reload, onBusy, onSuccess, onFailure }) {
  let busy = false;
  return {
    get submitting() { return busy; },
    async submit(item) {
      if (busy) return false;
      const request = documentInboxExtractionRequest(item);
      busy = true;
      onBusy(true);
      try {
        const result = documentInboxExtractionResponse(await execute(request));
        await reload();
        onSuccess(result);
        return true;
      } catch (error) {
        try { await reload(); } catch {}
        onFailure(documentInboxExtractionFailure(error));
        return false;
      } finally {
        busy = false;
        onBusy(false);
      }
    },
  };
}

function documentInboxDisplayValue(value, fallback = "Niet voorgesteld") {
  return value === null || value === undefined || value === "" ? fallback : String(value);
}

function documentInboxInitialValues(item) {
  const value = (field) => item[`confirmed_${field}`] ?? item[`proposed_${field}`] ?? "";
  const amountMinor = value("amount_minor");
  return {
    supplier_name: value("supplier_name"), document_type: value("document_type"),
    document_reference: value("document_reference"), document_date: value("document_date"),
    expense_date: value("expense_date"), amount: Number.isSafeInteger(amountMinor) ? (amountMinor / 100).toFixed(2).replace(".", ",") : "",
    currency: value("currency") || "EUR", description: value("description"),
    category: value("category"), relation_type: value("relation_type"),
  };
}

function documentInboxHasConfirmedValues(item) {
  return Boolean(item.confirmed_supplier_name && item.confirmed_document_type && item.confirmed_amount_minor
    && item.confirmed_currency === "EUR" && item.confirmed_description && item.confirmed_category
    && item.confirmed_expense_date && item.confirmed_relation_type);
}

function documentInboxBadgeClass(status) {
  if (status === "PROCESSED") return "badge badge--green";
  if (status === "REJECTED") return "badge badge--red";
  if (status === "REVIEW_REQUIRED") return "badge badge--amber";
  return "badge";
}

function formatDocumentInboxBytes(byteCount) {
  if (!Number.isSafeInteger(byteCount) || byteCount < 0) return "Niet beschikbaar";
  if (byteCount < 1024) return `${byteCount} B`;
  if (byteCount < 1024 * 1024) return `${(byteCount / 1024).toFixed(1)} KiB`;
  return `${(byteCount / (1024 * 1024)).toFixed(1)} MiB`;
}

export function supplierDocumentFileError(file) {
  if (!file || typeof file.name !== "string" || !file.name || file.name.length > 200 || /[\\/]/.test(file.name)
      || !SUPPLIER_DOCUMENT_ACCEPT.split(",").includes(file.type)) return "INVALID_MIME";
  if (!Number.isSafeInteger(file.size) || file.size < 1) return "INVALID_FILE";
  if (file.size > SUPPLIER_DOCUMENT_MAX_BYTES) return "FILE_TOO_LARGE";
  return null;
}

export function supplierDocumentUploadResponse(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)
      || data.bucket !== "supplier-documents"
      || typeof data.object_path !== "string" || !/^documents\/[0-9a-f]{64}\.(?:pdf|png|jpg)$/.test(data.object_path)
      || typeof data.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(data.sha256)
      || !Number.isSafeInteger(data.byte_count) || data.byte_count < 1 || data.byte_count > SUPPLIER_DOCUMENT_MAX_BYTES
      || !SUPPLIER_DOCUMENT_ACCEPT.split(",").includes(data.mime_type)) throw new Error("INVALID_SUPPLIER_DOCUMENT_UPLOAD_RESPONSE");
  return {
    bucket: data.bucket,
    object_path: data.object_path,
    sha256: data.sha256,
    byte_count: data.byte_count,
    mime_type: data.mime_type,
  };
}

export function documentInboxUploadResponse(data) {
  if (!data || data.ok !== true || !["STORED", "DUPLICATE"].includes(data.code)) {
    throw new Error("INVALID_DOCUMENT_INBOX_UPLOAD_RESPONSE");
  }
  return { ...supplierDocumentUploadResponse(data), code: data.code };
}

export function documentInboxReceiveRequest(file, upload) {
  const authority = supplierDocumentUploadResponse(upload);
  const originalFileName = String(file?.name || "").trim();
  if (supplierDocumentFileError(file) || originalFileName.length > 200 || /[\\/]/.test(originalFileName)) {
    throw new Error("INVALID_DOCUMENT_INBOX_FILE");
  }
  return {
    p_sha256: authority.sha256,
    p_original_file_name: originalFileName,
    p_mime_type: authority.mime_type,
    p_byte_count: authority.byte_count,
    p_source_type: "MANUAL_UPLOAD",
    p_source_instance: null,
    p_external_id: null,
    p_record_classification: "production",
  };
}

function documentInboxReceiveResponse(data) {
  if (!data || !UUID.test(String(data.id || "")) || !DOCUMENT_INBOX_STATUSES.includes(data.status)
      || !Number.isSafeInteger(data.revision) || data.revision < 1 || typeof data.replayed !== "boolean") {
    throw new Error("INVALID_DOCUMENT_INBOX_RECEIVE_RESPONSE");
  }
  return data;
}

export function createDocumentInboxUploadController({ uploadDocument, receiveDocument, reloadInbox, onBusy, onFailure, onSuccess }) {
  let busy = false;
  let checkpoint = null;
  const controller = {
    get submitting() { return busy; },
    get retryStage() {
      if (!checkpoint) return null;
      return checkpoint.received ? "reload" : "receive";
    },
    reset() { if (!busy) checkpoint = null; },
    async submit(file) {
      if (busy) return false;
      if (!checkpoint && supplierDocumentFileError(file)) {
        onFailure("validation");
        return false;
      }
      busy = true;
      onBusy(true);
      let stage = "upload";
      try {
        if (!checkpoint) {
          checkpoint = { file, upload: documentInboxUploadResponse(await uploadDocument(file)), received: null };
        }
        if (!checkpoint.received) {
          stage = "receive";
          checkpoint.received = documentInboxReceiveResponse(await receiveDocument(documentInboxReceiveRequest(checkpoint.file, checkpoint.upload)));
        }
        stage = "reload";
        await reloadInbox();
        const result = { ...checkpoint.received, duplicate: checkpoint.upload.code === "DUPLICATE" || checkpoint.received.replayed };
        checkpoint = null;
        onSuccess(result);
        return true;
      } catch (error) {
        onFailure(stage, error);
        return false;
      } finally {
        busy = false;
        onBusy(false);
      }
    },
  };
  return controller;
}

export function supplierDocumentCreateRequest(values, file, upload) {
  const documentType = String(values?.document_type || "");
  const supplierName = String(values?.supplier_name || "").trim();
  const documentReference = String(values?.document_reference || "").trim();
  const documentDate = String(values?.document_date || "");
  const originalFileName = String(file?.name || "").trim();
  if (!SUPPLIER_DOCUMENT_TYPES.includes(documentType)
      || !supplierName || supplierName.length > 200
      || documentReference.length > 200
      || (documentDate && !/^\d{4}-\d{2}-\d{2}$/.test(documentDate))
      || !originalFileName || originalFileName.length > 200 || /[\\/]/.test(originalFileName)) {
    throw new Error("INVALID_SUPPLIER_DOCUMENT_ENTRY");
  }
  const authority = supplierDocumentUploadResponse(upload);
  return {
    p_document_type: documentType,
    p_supplier_name: supplierName,
    p_document_reference: documentReference || null,
    p_document_date: documentDate || null,
    p_original_file_name: originalFileName,
    p_mime_type: authority.mime_type,
    p_byte_count: authority.byte_count,
    p_sha256: authority.sha256,
  };
}

export function businessExpenseDocumentLinkRequest(expenseId, supplierDocumentId, relationType) {
  if (!UUID.test(String(expenseId || "")) || !UUID.test(String(supplierDocumentId || ""))
      || !SUPPLIER_DOCUMENT_RELATION_TYPES.includes(relationType)) throw new Error("INVALID_BUSINESS_EXPENSE_DOCUMENT_LINK");
  return {
    p_business_expense_id: expenseId,
    p_supplier_document_id: supplierDocumentId,
    p_relation_type: relationType,
  };
}

export function createSupplierDocumentExpenseLinkController({ uploadDocument, createDocument, linkDocument, reloadPortfolio, onBusy, onFailure, onSuccess }) {
  let busy = false;
  let checkpoint = null;
  const controller = {
    get submitting() { return busy; },
    get retryStage() {
      if (!checkpoint) return null;
      if (!checkpoint.documentId) return "create";
      if (!checkpoint.linked) return "link";
      return "reload";
    },
    reset() { if (!busy) checkpoint = null; },
    async submit({ expenseId, file, values }) {
      if (busy) return false;
      if (!checkpoint && supplierDocumentFileError(file)) {
        onFailure("validation");
        return false;
      }
      busy = true;
      onBusy(true);
      let stage = "upload";
      try {
        if (!checkpoint) {
          const upload = supplierDocumentUploadResponse(await uploadDocument(file));
          checkpoint = { expenseId, file, values: { ...values }, upload, documentId: null, linked: false };
        }
        if (checkpoint.expenseId !== expenseId) throw new Error("SUPPLIER_DOCUMENT_EXPENSE_CHANGED");
        if (!checkpoint.documentId) {
          stage = "create";
          const documentId = await createDocument(supplierDocumentCreateRequest(checkpoint.values, checkpoint.file, checkpoint.upload));
          if (!UUID.test(String(documentId || ""))) throw new Error("INVALID_SUPPLIER_DOCUMENT_ID");
          checkpoint.documentId = documentId;
        }
        if (!checkpoint.linked) {
          stage = "link";
          await linkDocument(businessExpenseDocumentLinkRequest(checkpoint.expenseId, checkpoint.documentId, checkpoint.values.relation_type));
          checkpoint.linked = true;
        }
        stage = "reload";
        await reloadPortfolio();
        checkpoint = null;
        onSuccess();
        return true;
      } catch (error) {
        onFailure(stage, error);
        return false;
      } finally {
        busy = false;
        onBusy(false);
      }
    },
  };
  return controller;
}

export function businessExpenseAmountMinor(value) {
  const normalized = String(value ?? "").trim().replace(",", ".");
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return null;
  const [units, decimals = ""] = normalized.split(".");
  const amountMinor = (BigInt(units) * 100n) + BigInt(decimals.padEnd(2, "0"));
  if (amountMinor <= 0n || amountMinor > BigInt(Number.MAX_SAFE_INTEGER)) return null;
  return Number(amountMinor);
}

export function businessExpenseCreateRequest(values) {
  const supplierName = String(values?.supplier_name ?? "").trim();
  const description = String(values?.description ?? "").trim();
  const category = String(values?.category ?? "");
  const amountMinor = businessExpenseAmountMinor(values?.amount);
  const currency = String(values?.currency ?? "");
  const expenseDate = String(values?.expense_date ?? "");
  if (!supplierName || supplierName.length > 200
      || !description || description.length > 1000
      || !Object.hasOwn(BUSINESS_EXPENSE_CATEGORY_LABELS, category)
      || amountMinor === null || currency !== "EUR"
      || !/^\d{4}-\d{2}-\d{2}$/.test(expenseDate)) throw new Error("INVALID_BUSINESS_EXPENSE_ENTRY");
  return {
    p_supplier_name: supplierName,
    p_description: description,
    p_category: category,
    p_amount_minor: amountMinor,
    p_currency: "EUR",
    p_expense_date: expenseDate,
  };
}

export function createBusinessExpenseEntryController({ createExpense, reloadPortfolio, onBusy, onCreated, onError }) {
  let submitting = false;
  return {
    get submitting() { return submitting; },
    async submit(values) {
      if (submitting) return false;
      let request;
      try {
        request = businessExpenseCreateRequest(values);
      } catch (error) {
        onError(error);
        return false;
      }
      submitting = true;
      onBusy(true);
      try {
        const result = await createExpense(request);
        onCreated(result);
        await reloadPortfolio();
        return true;
      } catch (error) {
        onError(error);
        return false;
      } finally {
        submitting = false;
        onBusy(false);
      }
    },
  };
}

export function websiteFinancePortfolioPresentation(portfolio) {
  const validMoney = (value)=>Number.isSafeInteger(value) && value >= 0;
  const validCurrency = (value)=>typeof value === "string" && /^[A-Z]{3}$/.test(value);
  if (!portfolio || typeof portfolio !== "object" || Array.isArray(portfolio)
      || portfolio.scope !== "website"
      || !Array.isArray(portfolio.currency_totals)
      || !Array.isArray(portfolio.projects)
      || portfolio.bank_actuals !== null
      || FINANCE_UNAVAILABLE_FLAGS.some((flag)=>portfolio[flag] !== false)) {
    throw new Error("INVALID_WEBSITE_FINANCE_PORTFOLIO");
  }
  for (const total of portfolio.currency_totals) {
    if (!validCurrency(total?.currency)
        || !validMoney(total?.total_commitment_minor)
        || !validMoney(total?.total_expected_minor)
        || !validMoney(total?.total_confirmed_received_minor)) throw new Error("INVALID_WEBSITE_FINANCE_PORTFOLIO");
  }
  for (const project of portfolio.projects) {
    if (!UUID.test(String(project?.project_id || ""))
        || project?.request_kind !== "website"
        || (project?.application_reference !== null && typeof project?.application_reference !== "string")
        || !validCurrency(project?.currency)
        || !validMoney(project?.accepted_total_minor)
        || !validMoney(project?.expected_minor)
        || !validMoney(project?.confirmed_received_minor)
        || !Array.isArray(project?.milestones)) throw new Error("INVALID_WEBSITE_FINANCE_PORTFOLIO");
  }
  return portfolio;
}

export function sdfFinancePortfolioPresentation(portfolio) {
  const validMoney = (value)=>Number.isSafeInteger(value) && value >= 0;
  const validCurrency = (value)=>typeof value === "string" && /^[A-Z]{3}$/.test(value);
  const validTimestamp = (value)=>typeof value === "string" && !Number.isNaN(Date.parse(value));
  if (!portfolio || typeof portfolio !== "object" || Array.isArray(portfolio)
      || portfolio.scope !== "sdf"
      || !Number.isSafeInteger(portfolio.project_count)
      || portfolio.project_count < 0
      || !Array.isArray(portfolio.currency_totals)
      || !Array.isArray(portfolio.projects)
      || portfolio.project_count !== portfolio.projects.length
      || portfolio.invoice_projection_available !== true
      || SDF_FINANCE_UNAVAILABLE_FLAGS.some((flag)=>portfolio[flag] !== false)) {
    throw new Error("INVALID_SDF_FINANCE_PORTFOLIO");
  }
  for (const total of portfolio.currency_totals) {
    if (!validCurrency(total?.currency)
        || !validMoney(total?.commitment_minor)
        || !validMoney(total?.m1_obligation_minor)
        || !validMoney(total?.issued_invoice_minor)) throw new Error("INVALID_SDF_FINANCE_PORTFOLIO");
  }
  for (const project of portfolio.projects) {
    const hasCandidate = project?.invoice_candidate_state === "PREPARED";
    const hasIssuance = project?.invoice_issuance_state === "ISSUED";
    if (!UUID.test(String(project?.quote_request_id || ""))
        || !UUID.test(String(project?.quotation_id || ""))
        || (project?.sdf_project_id !== null && !UUID.test(String(project?.sdf_project_id || "")))
        || (project?.application_reference !== null && !APPLICATION_REFERENCE.test(project.application_reference || ""))
        || !Object.hasOwn(SDF_PACKAGE_LABELS, project?.sdf_package)
        || !validCurrency(project?.currency)
        || !validMoney(project?.commitment_minor)
        || !validMoney(project?.m1_obligation_minor)
        || project?.m1_obligation_status !== "EXPECTED"
        || !validTimestamp(project?.accepted_at)
        || !validTimestamp(project?.accepted_terms_created_at)
        || !validTimestamp(project?.m1_obligation_created_at)
        || SDF_FINANCE_PROJECT_PII.some((field)=>Object.hasOwn(project, field))
        || (!hasCandidate && project?.invoice_candidate_state !== null)
        || (hasCandidate && (!validMoney(project?.invoice_candidate_net_amount_minor) || !validTimestamp(project?.prepared_at)))
        || (!hasCandidate && (project?.invoice_candidate_net_amount_minor !== null || project?.prepared_at !== null))
        || (!hasIssuance && project?.invoice_issuance_state !== null)
        || (hasIssuance && (!hasCandidate
          || typeof project?.invoice_number !== "string" || !project.invoice_number
          || !validMoney(project?.issued_net_amount_minor)
          || !validMoney(project?.issued_gross_amount_minor)
          || !validTimestamp(project?.issued_at)))
        || (!hasIssuance && (project?.invoice_number !== null
          || project?.issued_net_amount_minor !== null
          || project?.issued_gross_amount_minor !== null
          || project?.issued_at !== null))) throw new Error("INVALID_SDF_FINANCE_PORTFOLIO");
  }
  return portfolio;
}

export function businessExpenseFinancePortfolioPresentation(portfolio) {
  const validMoney = (value)=>Number.isSafeInteger(value) && value >= 0;
  const validCurrency = (value)=>typeof value === "string" && /^[A-Z]{3}$/.test(value);
  if (!portfolio || typeof portfolio !== "object" || Array.isArray(portfolio)
      || Object.keys(portfolio).some((field)=>!BUSINESS_EXPENSE_ROOT_FIELDS.has(field))
      || portfolio.scope !== "business_expenses"
      || !Number.isSafeInteger(portfolio.expense_count) || portfolio.expense_count < 0
      || !Array.isArray(portfolio.currency_totals) || !Array.isArray(portfolio.expenses)
      || portfolio.expense_count !== portfolio.expenses.length
      || !portfolio.availability || typeof portfolio.availability !== "object"
      || Object.keys(portfolio.availability).length !== BUSINESS_EXPENSE_AVAILABILITY_FLAGS.length
      || Object.keys(portfolio.availability).some((flag)=>!BUSINESS_EXPENSE_AVAILABILITY_FLAGS.includes(flag))
      || BUSINESS_EXPENSE_AVAILABILITY_FLAGS.some((flag)=>portfolio.availability[flag] !== false)
      || portfolio.bank_actuals !== null) throw new Error("INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO");
  for (const total of portfolio.currency_totals) {
    if (Object.keys(total || {}).length !== 2
        || Object.keys(total || {}).some((field)=>!["currency", "active_expense_minor"].includes(field))
        || !validCurrency(total?.currency) || !validMoney(total?.active_expense_minor)) {
      throw new Error("INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO");
    }
  }
  for (const expense of portfolio.expenses) {
    if (Object.keys(expense || {}).some((field)=>!BUSINESS_EXPENSE_FIELDS.has(field))
        || !UUID.test(String(expense?.id || ""))
        || typeof expense?.supplier_name !== "string" || !expense.supplier_name
        || typeof expense?.description !== "string" || typeof expense?.category !== "string"
        || !validMoney(expense?.amount_minor) || !validCurrency(expense?.currency)
        || typeof expense?.expense_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(expense.expense_date)
        || !["RECORDED", "CANCELLED"].includes(expense?.status)
        || !Number.isSafeInteger(expense?.document_count) || expense.document_count < 0
        || !Array.isArray(expense?.relation_types)
        || expense.relation_types.some((type)=>!Object.hasOwn(BUSINESS_EXPENSE_RELATION_LABELS, type))) {
      throw new Error("INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO");
    }
  }
  return portfolio;
}

export function businessExpenseCategoryLabel(category) {
  return BUSINESS_EXPENSE_CATEGORY_LABELS[category] || category;
}

export function businessExpenseRelationLabel(relationType) {
  return BUSINESS_EXPENSE_RELATION_LABELS[relationType] || relationType;
}

export function formatFinanceMoney(minor, currency) {
  return new Intl.NumberFormat("nl-BE", { style: "currency", currency }).format(minor / 100);
}

export function financeMilestoneStatus(project) {
  const statuses = new Set((project?.milestones || []).map((milestone)=>milestone?.payment_status));
  if (statuses.has("MATCHED_AWAITING_CONFIRMATION")) return "Afstemming wacht op bevestiging";
  if (statuses.has("EVIDENCE_RECORDED")) return "Betalingsbewijs geregistreerd";
  if (statuses.has("EXPECTED")) return "Betaling verwacht";
  if (statuses.size && [...statuses].every((status)=>status === "CONFIRMED")) return "Bevestigd ontvangen";
  return "Nog geen betaalstatus beschikbaar";
}
const WEBSITE_DOSSIER_IDS = Object.freeze([
  "lifecycleDossier", "pricingDossier", "projectDossier", "quotationDossier",
  "paymentDossier", "workflowDossier", "historyDossier"
]);
const SDF_DOSSIER_IDS = Object.freeze(["sdfQualificationDossier", "sdfPricingDossier", "sdfQuotationDossier", "sdfM1InvoiceDossier", "sdfProjectDossier", "sdfDossierDangerZone"]);
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
const QUOTATION_DELIVERY_PRESENTATION = Object.freeze({
  pending: Object.freeze({ status: "pending", label: "Verzending wacht op verwerking", tone: "amber" }),
  processing: Object.freeze({ status: "processing", label: "Offerte wordt verzonden", tone: "amber" }),
  sent: Object.freeze({ status: "sent", label: "Offerte verzonden", tone: "green" }),
  retry_wait: Object.freeze({ status: "retry_wait", label: "Verzending tijdelijk mislukt — nieuwe poging mogelijk", tone: "amber" }),
  failed: Object.freeze({ status: "failed", label: "Verzending mislukt — manuele controle vereist", tone: "red" }),
});
const DOSSIER_DOCUMENT_ACCESS_SOURCES = new Set(["QUOTATION_ARTIFACT", "CUSTOMER_UPLOAD"]);
const DOSSIER_DOCUMENT_TYPE_LABELS = Object.freeze({
  QUOTATION: "Offerte",
  QUOTATION_ARTIFACT: "Offertebestand",
  CUSTOMER_UPLOAD: "Klantupload",
});

export function dossierDocumentManifestRequest(application) {
  const quoteRequestId = String(application?.quote_request_id || "");
  if (!UUID.test(quoteRequestId)) throw new Error("INVALID_DOSSIER_DOCUMENT_REQUEST");
  return { action: "get_dossier_document_manifest", quote_request_id: quoteRequestId };
}

export function dossierDocumentAccessRequest(application, item) {
  const quoteRequestId = String(application?.quote_request_id || "");
  const documentId = String(item?.document_id || "");
  const sourceType = String(item?.source_type || "");
  if (!UUID.test(quoteRequestId) || item?.quote_request_id !== quoteRequestId
    || !UUID.test(documentId) || !DOSSIER_DOCUMENT_ACCESS_SOURCES.has(sourceType)
    || item?.can_open !== true || item?.can_download !== true) {
    throw new Error("INVALID_DOSSIER_DOCUMENT_ACCESS_REQUEST");
  }
  return {
    action: "create_dossier_document_access",
    quote_request_id: quoteRequestId,
    source_type: sourceType,
    document_id: documentId,
  };
}

export function dossierDocumentPresentation(item) {
  const sourceType = String(item?.source_type || "");
  if (!Object.hasOwn(DOSSIER_DOCUMENT_TYPE_LABELS, sourceType)
    || !UUID.test(String(item?.document_id || ""))
    || typeof item?.title !== "string" || !item.title
    || typeof item?.status !== "string" || !item.status
    || typeof item?.created_at !== "string" || !Number.isFinite(Date.parse(item.created_at))) {
    throw new Error("INVALID_DOSSIER_DOCUMENT");
  }
  return {
    type: DOSSIER_DOCUMENT_TYPE_LABELS[sourceType],
    name: item.filename || item.title,
    date: item.created_at,
    status: item.status.replaceAll("_", " "),
    actionable: DOSSIER_DOCUMENT_ACCESS_SOURCES.has(sourceType)
      && item.can_open === true && item.can_download === true,
  };
}

export function quotationDeliveryPresentation(delivery) {
  const status = String(delivery?.status || "");
  return QUOTATION_DELIVERY_PRESENTATION[status] || null;
}

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

export function canOfferDossierPurge(detail, identity, eligibility) {
  return Boolean(identity?.status === "ACTIVE"
    && identity.role === "owner"
    && ["ACTIVE", "TRASHED"].includes(detail?.dossier_lifecycle?.state)
    && UUID.test(String(detail?.quote_request_id || ""))
    && eligibility?.can_purge === true
    && eligibility.reason === null);
}

export function presentWebsiteDossierPurge(nodes, detail, identity, eligibility) {
  const eligibleContext = detail?.request_kind === "website"
    && identity?.status === "ACTIVE"
    && identity.role === "owner"
    && ["ACTIVE", "TRASHED"].includes(detail?.dossier_lifecycle?.state);
  nodes.section.hidden = !eligibleContext;
  nodes.action.hidden = !eligibleContext || !canOfferDossierPurge(detail, identity, eligibility);
  nodes.message.textContent = !eligibleContext ? ""
    : eligibility?.can_purge === true && eligibility.reason === null
    ? "Dit dossier bevat geen beschermde afhankelijkheden en kan definitief worden verwijderd."
    : eligibility
    ? "Definitief verwijderen is door de server geblokkeerd omdat beschermde afhankelijkheden bestaan."
    : "De verwijderstatus kon niet veilig worden vastgesteld. Vernieuw het dossier.";
}

export function dossierPurgeRequest(detail, reason, idempotencyKey) {
  const quoteRequestId = String(detail?.quote_request_id || "");
  const normalizedReason = typeof reason === "string" ? reason.trim() : "";
  if (!["ACTIVE", "TRASHED"].includes(detail?.dossier_lifecycle?.state)
      || !UUID.test(quoteRequestId)
      || !UUID.test(String(idempotencyKey || ""))
      || normalizedReason.length < 1
      || normalizedReason.length > 500) throw new Error("INVALID_DOSSIER_PURGE_REQUEST");
  return {
    p_quote_request_id: quoteRequestId,
    p_reason: normalizedReason,
    p_idempotency_key: idempotencyKey,
  };
}

const SDF_PURGE_BLOCKER_MESSAGES = Object.freeze({
  ALREADY_PURGED: "Dit dossier is al definitief verwijderd.",
  DOSSIER_NOT_FOUND: "Dit dossier is niet meer beschikbaar.",
  WRONG_PRODUCT_KIND: "Definitief verwijderen is niet beschikbaar voor dit type dossier.",
  DOSSIER_STATE_NOT_PURGEABLE: "Definitief verwijderen is niet beschikbaar in deze dossierstatus.",
  SDF_QUOTATION_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat er al een offerte bestaat.",
  QUOTATION_PREPARATION_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat de commerciële voorbereiding al is gestart.",
  QUOTATION_ACCEPTANCE_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat de offerte al is aanvaard.",
  ACCEPTED_COMMERCIAL_TERMS_EXIST: "Dit dossier kan niet definitief worden verwijderd omdat er al commerciële voorwaarden zijn aanvaard.",
  COMMERCIAL_OBLIGATION_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat er al een commerciële verplichting bestaat.",
  INVOICE_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat er al een factuur of factuurvoorbereiding bestaat.",
  VAT_COMMERCIAL_BINDING_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat er al fiscale gegevens aan gekoppeld zijn.",
  PROJECT_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat er al een project aan gekoppeld is.",
  PAYMENT_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat er betalingsgegevens aan gekoppeld zijn.",
  CUSTOMER_REQUEST_EXISTS: "Dit dossier kan niet definitief worden verwijderd omdat er al een klantverzoek aan gekoppeld is.",
  OTHER_PROTECTED_DEPENDENCY: "Dit dossier kan niet definitief worden verwijderd omdat er beschermde commerciële gegevens aan gekoppeld zijn.",
});

export function sdfDossierPurgePresentation(detail, identity, eligibility) {
  if (detail?.request_kind !== "slimme_documentenflow") return null;
  if (identity?.status !== "ACTIVE" || identity.role !== "owner"
  || !["ACTIVE", "TRASHED"].includes(detail?.dossier_lifecycle?.state)) return null;
  if (!eligibility || typeof eligibility !== "object") {
    return { canPurge: false, message: "De verwijderstatus kon niet veilig worden vastgesteld. Vernieuw het dossier." };
  }
  if (eligibility.can_purge === true && eligibility.reason === null) {
    return { canPurge: true, message: "Dit dossier bevat geen beschermde commerciële gegevens en kan definitief worden verwijderd." };
  }
  return {
    canPurge: false,
    message: SDF_PURGE_BLOCKER_MESSAGES[eligibility.reason]
      || "Dit dossier kan niet definitief worden verwijderd omdat er beschermde gegevens aan gekoppeld zijn.",
  };
}

export function pendingIntakePurgePresentation(item, eligibility = null) {
  if (item?.request_kind !== "slimme_documentenflow") {
    return item?.can_permanently_delete === true
      ? { canPurge: true, message: "Deze nog niet ingediende intake heeft geen beschermde afhankelijkheden en kan definitief worden verwijderd." }
      : { canPurge: false, message: "Definitief verwijderen is door de server geblokkeerd omdat beschermde dossierafhankelijkheden bestaan." };
  }
  if (!eligibility || typeof eligibility !== "object") {
    return { canPurge: false, message: "De verwijderstatus wordt veilig gecontroleerd." };
  }
  if (eligibility.can_purge === true && eligibility.reason === null) {
    return { canPurge: true, message: "Dit SDF-dossier bevat geen beschermde commerciële gegevens en kan definitief worden verwijderd." };
  }
  return {
    canPurge: false,
    message: SDF_PURGE_BLOCKER_MESSAGES[eligibility.reason]
      || "Dit SDF-dossier kan niet definitief worden verwijderd omdat er beschermde gegevens aan gekoppeld zijn.",
  };
}

export function pendingSdfDossierPurgeRequest(item, eligibility, reason, idempotencyKey) {
  const normalizedReason = typeof reason === "string" ? reason.trim() : "";
  if (item?.request_kind !== "slimme_documentenflow"
      || eligibility?.can_purge !== true
      || eligibility.reason !== null
      || !UUID.test(String(item?.quote_request_id || ""))
      || !UUID.test(String(idempotencyKey || ""))
      || normalizedReason.length < 1
      || normalizedReason.length > 500) throw new Error("INVALID_PENDING_SDF_PURGE_REQUEST");
  return {
    p_quote_request_id: item.quote_request_id,
    p_reason: normalizedReason,
    p_idempotency_key: idempotencyKey,
  };
}

export function presentSdfDossierPurge(nodes, detail, identity, eligibility) {
  const presentation = sdfDossierPurgePresentation(detail, identity, eligibility);
  nodes.section.hidden = !presentation;
  nodes.message.textContent = presentation?.message || "";
  nodes.action.hidden = !presentation?.canPurge;
  return presentation;
}

export function sdfDossierPurgeRequest(detail, reason, idempotencyKey) {
  if (detail?.request_kind !== "slimme_documentenflow") throw new Error("INVALID_SDF_DOSSIER_PURGE_REQUEST");
  return dossierPurgeRequest(detail, reason, idempotencyKey);
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
    visibleReference: `Oudere aanvraag · ${shortTechnicalReference(quoteRequestId)}`,
    locator: { quote_request_id: quoteRequestId },
  };
}

export function shortTechnicalReference(reference) {
  const value = String(reference || "").trim();
  return UUID.test(value) ? `#${value.slice(0, 8).toUpperCase()}` : "";
}

export function canPromoteApplication(detail) {
  return Boolean(detail?.request_kind === "website" && detail.acceptance && !detail.project);
}

export function canIssueApprovedQuotation(detail, identity) {
  return Boolean(identity?.status === "ACTIVE"
    && ["owner", "admin"].includes(identity.role)
    && detail?.request_kind === "website"
    && UUID.test(String(detail?.quote_request_id || ""))
    && UUID.test(String(detail?.quotation?.approval_id || ""))
    && !detail.acceptance);
}

export function quotationIssuanceRequest(detail) {
  const quoteRequestId = String(detail?.quote_request_id || "");
  if (!UUID.test(quoteRequestId)) return null;
  return {
    action: "issue_and_deliver_approved_quotation",
    quote_request_id: quoteRequestId,
  };
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

export function pendingIntakesRequest(retentionState = "ACTIVE") {
  if (!["ACTIVE", "ARCHIVED"].includes(retentionState)) throw new Error("INVALID_RETENTION_STATE");
  return { action: "list_pending_intakes", retention_state: retentionState };
}

export function pendingIntakeCountRequest() {
  return { action: "count_pending_intakes" };
}

export function pendingIntakeIdentityPresentation(item) {
  const display = (value) => typeof value === "string" && value.trim() ? value.trim() : "Niet opgegeven";
  return {
    contactName: display(item?.name),
    organization: display(item?.organization),
    supportReference: /^#[0-9A-F]{8}$/.test(String(item?.support_reference || ""))
      ? item.support_reference
      : "Niet opgegeven",
  };
}

export function pendingIntakePresentation(item) {
  if (!item || typeof item !== "object" || Array.isArray(item)
      || !UUID.test(String(item.quote_request_id || ""))
      || !UUID.test(String(item.intake_id || ""))
      || typeof item.name !== "string" || !item.name
      || !["website", "slimme_documentenflow"].includes(item.request_kind)
      || !["invited", "in_progress"].includes(item.intake_status)) return null;
  const lifecycle = {
    intake_id: item.intake_id,
    effective_access: item.effective_access,
    access_token_expires_at: item.access_token_expires_at,
    lifecycle_revision: item.lifecycle_revision,
  };
  const access = intakeLifecyclePresentation(lifecycle);
  if (!access || !item.invitation_created_at
      || !["ACTIVE", "ARCHIVED"].includes(item.retention_state)
      || !Number.isSafeInteger(item.retention_revision) || item.retention_revision < 0
      || typeof item.can_permanently_delete !== "boolean") return null;
  return {
    lifecycle,
    access,
    intake: item.intake_status === "invited"
      ? { label: "Uitnodiging verstuurd", tone: "amber" }
      : { label: "Intake gestart", tone: "green" },
    invitedAt: item.invitation_sent_at || item.invitation_created_at,
  };
}

export function pendingIntakeWorkspaceItems(items, { search = "", filter = "ALL", sort = "NEWEST" } = {}) {
  const normalizedSearch = String(search).trim().toLocaleLowerCase("nl-BE");
  const allowedFilters = new Set(["ALL", "INVITED", "IN_PROGRESS", "ACTIVE", "INTERRUPTED", "EXPIRED", "CANCELLED"]);
  const allowedSorts = new Set(["NEWEST", "OLDEST", "EXPIRY", "STATUS"]);
  if (!allowedFilters.has(filter) || !allowedSorts.has(sort)) throw new Error("INVALID_PENDING_WORKSPACE_QUERY");
  const result = items.filter((item)=>{
    if (!pendingIntakePresentation(item)) return false;
    if (normalizedSearch && ![item.name, item.organization, item.email]
      .filter(Boolean).some((value)=>String(value).toLocaleLowerCase("nl-BE").includes(normalizedSearch))) return false;
    if (filter === "INVITED" && item.intake_status !== "invited") return false;
    if (filter === "IN_PROGRESS" && item.intake_status !== "in_progress") return false;
    if (["ACTIVE", "INTERRUPTED", "EXPIRED", "CANCELLED"].includes(filter) && item.effective_access !== filter) return false;
    return true;
  });
  return result.sort((left, right)=>{
    if (sort === "OLDEST") return Date.parse(left.invitation_sent_at || left.invitation_created_at) - Date.parse(right.invitation_sent_at || right.invitation_created_at);
    if (sort === "EXPIRY") return Date.parse(left.access_token_expires_at) - Date.parse(right.access_token_expires_at);
    if (sort === "STATUS") return `${left.intake_status}|${left.effective_access}|${left.name}`.localeCompare(`${right.intake_status}|${right.effective_access}|${right.name}`, "nl-BE");
    return Date.parse(right.invitation_sent_at || right.invitation_created_at) - Date.parse(left.invitation_sent_at || left.invitation_created_at);
  });
}

export function buildPendingIntakeRetentionCommand(action, item, reason, idempotencyKey) {
  const target = action === "archive_pending_intake" ? "ACTIVE" : action === "restore_pending_intake" ? "ARCHIVED" : null;
  const normalizedReason = typeof reason === "string" ? reason.trim() : "";
  if (!target || item?.retention_state !== target || !UUID.test(String(item?.intake_id || ""))
      || !Number.isSafeInteger(item?.retention_revision) || item.retention_revision < 0
      || !UUID.test(String(idempotencyKey || "")) || normalizedReason.length < 1 || normalizedReason.length > 500) {
    throw new Error("INVALID_PENDING_RETENTION_COMMAND");
  }
  return {
    action,
    intake_id: item.intake_id,
    expected_revision: item.retention_revision,
    idempotency_key: idempotencyKey,
    reason: normalizedReason,
  };
}

export function buildPendingIntakeDeleteCommand(item, reason, idempotencyKey) {
  const normalizedReason = typeof reason === "string" ? reason.trim() : "";
  if (!item?.can_permanently_delete || !UUID.test(String(item.intake_id || ""))
      || !UUID.test(String(item.quote_request_id || "")) || !UUID.test(String(idempotencyKey || ""))
      || normalizedReason.length < 1 || normalizedReason.length > 500) {
    throw new Error("INVALID_PENDING_DELETE_COMMAND");
  }
  return {
    action: "permanently_delete_pending_intake",
    intake_id: item.intake_id,
    quote_request_id: item.quote_request_id,
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
  nodes.sdfDetailNotice.hidden = true;
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

const SDF_QUALIFICATION_STATUS_LABELS = Object.freeze({
  invited: "Uitgenodigd",
  in_progress: "In uitvoering",
  submitted: "Ingediend",
  under_review: "In beoordeling",
  changes_requested: "Aanvulling gevraagd",
  qualification_complete: "Kwalificatie voltooid",
  closed: "Gesloten",
});
const SDF_QUALIFICATION_TAXONOMIES = new Set(["sdf_qualification_intake/1.0.0", "sdf_qualification_intake/2.0.0"]);
const SDF_QUALIFICATION_SUBMITTED_STATUSES = new Set(["submitted", "under_review", "changes_requested", "qualification_complete", "closed"]);

export function sdfQualificationDetailRequest(application) {
  if (application?.request_kind !== "slimme_documentenflow" || !UUID.test(String(application?.quote_request_id || ""))) {
    throw new Error("INVALID_SDF_QUALIFICATION_DETAIL_REQUEST");
  }
  return { action: "inspect_sdf_qualification_intake", quote_request_id: application.quote_request_id };
}

export function sdfQualificationStatusPresentation(status) {
  const label = SDF_QUALIFICATION_STATUS_LABELS[status];
  if (!label) throw new Error("INVALID_SDF_QUALIFICATION_STATUS");
  return {
    value: status,
    label,
    activeWork: ["submitted", "under_review"].includes(status),
    tone: status === "qualification_complete" ? "green" : ["in_progress", "submitted", "under_review", "changes_requested"].includes(status) ? "amber" : "",
  };
}

export function sdfQualificationDetailPresentation(readModel, application, preparedAt = new Date().toISOString()) {
  const status = sdfQualificationStatusPresentation(readModel?.status);
  const answers = readModel?.latest_submission;
  const hasAnswers = answers !== null && answers !== undefined;
  if (!UUID.test(String(readModel?.quote_request_id || ""))
      || readModel.quote_request_id !== application?.quote_request_id
      || !UUID.test(String(readModel?.intake_id || ""))
      || !SDF_QUALIFICATION_TAXONOMIES.has(readModel?.taxonomy_version)
      || (hasAnswers && (typeof answers !== "object" || Array.isArray(answers)))
      || (SDF_QUALIFICATION_SUBMITTED_STATUSES.has(status.value) && !hasAnswers)
      || (hasAnswers && (!Number.isInteger(readModel?.latest_submission_sequence) || readModel.latest_submission_sequence < 1))) {
    throw new Error("INVALID_SDF_QUALIFICATION_DETAIL");
  }
  return {
    answers: hasAnswers ? answers : null,
    status,
    context: {
      reference: application.support_reference || "",
      customerName: readModel.name || application.name || "",
      organization: readModel.company || application.company || "",
      email: readModel.email || application.email || "",
      status: status.label,
      taxonomyVersion: readModel.taxonomy_version,
      preparedAt,
    },
    meta: {
      intakeReference: readModel.intake_id,
      taxonomyVersion: readModel.taxonomy_version,
      submissionSequence: hasAnswers ? String(readModel.latest_submission_sequence) : "Nog niet ingediend",
    },
  };
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

export function mountInternalSmokeB({
  panel,
  button,
  statusElement,
  resultElement,
  url,
  identity,
  requireAal2,
  confirmSmoke,
  runSmoke,
}) {
  if (panel) panel.hidden = true;
  if (!panel || !button || !statusElement || !resultElement || !internalSmokeAvailable(url, identity)) return false;
  panel.hidden = false;
  const trigger = createInternalSmokeOneShotTrigger({
    button,
    confirmSmoke,
    runSmoke: async ()=>{
      statusElement.textContent = "Test wordt uitgevoerd…";
      resultElement.textContent = "";
      try {
        await requireAal2();
      } catch {
        const result = { SMOKE_STATUS: "FAILED: AUTH" };
        statusElement.textContent = "Test gestopt.";
        resultElement.textContent = JSON.stringify(result, null, 2);
        return result;
      }
      const result = await runSmoke();
      statusElement.textContent = result.SMOKE_STATUS === "PASS" ? "Test voltooid." : "Test gestopt.";
      resultElement.textContent = JSON.stringify(result, null, 2);
      return result;
    },
  });
  button.addEventListener("click", trigger);
  return true;
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

const INTERNAL_SMOKE_B_FIELDS = Object.freeze([
  "SMOKE_STATUS",
  "run_id",
  "customer_request_id",
  "replay_same_request",
  "upload_request_id",
  "uploaded_file_id",
  "accepted_file_count",
  "upload_complete",
  "cleanup",
  "customer_request_final_status",
  "internal_e2e_final_status",
]);

export function createInternalSmokeBSyntheticPng() {
  const encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
  const binary = atob(encoded);
  const bytes = Uint8Array.from(binary, (character)=>character.charCodeAt(0));
  return {
    name: "lws-smoke-b-synthetic.png",
    blob: new Blob([bytes], { type: "image/png" }),
  };
}

export async function runInternalSmokeB({
  client,
  invoke,
  uploadRequest,
  putSignedBlob,
  randomUUID = ()=>crypto.randomUUID(),
}) {
  const result = {
    SMOKE_STATUS: "FAILED: AUTH",
    run_id: null,
    customer_request_id: null,
    replay_same_request: false,
    upload_request_id: null,
    uploaded_file_id: null,
    accepted_file_count: 0,
    upload_complete: "FAIL",
    cleanup: "FAIL",
    customer_request_final_status: null,
    internal_e2e_final_status: null,
  };
  let capability = null;
  let syntheticFile = null;
  let uploadAccepted = false;
  let uploadCompleted = false;
  let cleanupIdempotencyKey = null;
  let cleanupAttempted = false;
  let cleanupCompleted = false;
  let revokeAttempted = false;
  let uploadRevoked = false;
  let cancelAttempted = false;
  let requestCancelled = false;
  let finalizeAttempted = false;
  let phase = "AUTH";
  const required = (condition) => {
    if (!condition) throw new Error("INTERNAL_SMOKE_FAILED");
  };
  const acceptAuthoritativeList = (listed) => {
    const accepted = Array.isArray(listed?.files)
      ? listed.files.filter((file)=>file?.status === "ACCEPTED" && file?.file_id === result.uploaded_file_id)
      : [];
    result.accepted_file_count = accepted.length;
    required(listed?.state === "ACTIVE" && listed?.accepted_file_count === 1
      && listed.files.length === 1 && accepted.length === 1);
    uploadAccepted = true;
  };
  const reconcileCleanup = async () => {
    cleanupIdempotencyKey ||= randomUUID();
    cleanupAttempted = true;
    const input = {
      action: "cleanup_internal_e2e_accepted_file",
      run_id: result.run_id,
      request_id: result.customer_request_id,
      upload_request_id: result.upload_request_id,
      uploaded_file_id: result.uploaded_file_id,
      idempotency_key: cleanupIdempotencyKey,
    };
    let cleaned;
    try {
      cleaned = await invoke(input);
    } catch {
      cleaned = await invoke(input);
    }
    cleanupCompleted = cleaned?.state === "DELETED"
      && cleaned.run_id === result.run_id
      && cleaned.request_id === result.customer_request_id
      && cleaned.upload_request_id === result.upload_request_id
      && cleaned.uploaded_file_id === result.uploaded_file_id;
    if (cleanupCompleted) result.cleanup = "DELETED";
    return cleanupCompleted;
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
    result.run_id = fixture.run_id;
    result.customer_request_id = fixture.request_id;

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
    result.upload_request_id = link.upload_request_id;
    const capabilityUrl = new URL(link.upload_url);
    delete link.upload_url;
    capability = new URLSearchParams(capabilityUrl.hash.slice(1)).get("token");
    capabilityUrl.hash = "";
    required(/^[A-Za-z0-9_-]{43}$/.test(capability || ""));

    phase = "RESOLVE";
    const resolved = await uploadRequest(capability, { method: "GET" });
    required(resolved?.state === "ACTIVE"
      && resolved?.title === "LWS-SMOKE-TEST-UPLOAD-LINK-20260827"
      && resolved?.file_count === 0);

    phase = "PREPARE";
    syntheticFile = createInternalSmokeBSyntheticPng();
    required(syntheticFile.blob.size < 16 * 1024);
    const prepared = await uploadRequest(capability, {
      action: "prepare",
      payload: {
        file_name: syntheticFile.name,
        content_type: syntheticFile.blob.type,
        byte_count: syntheticFile.blob.size,
      },
      idempotencyKey: randomUUID(),
    });
    required(prepared?.state === "PREPARED"
      && UUID.test(String(prepared.file_id || ""))
      && typeof prepared.signed_upload_url === "string");
    result.uploaded_file_id = prepared.file_id;
    const signedUploadUrl = prepared.signed_upload_url;
    delete prepared.signed_upload_url;

    phase = "SIGNED_PUT";
    await putSignedBlob(signedUploadUrl, syntheticFile.blob);

    phase = "UPLOAD_FINALIZE";
    try {
      const finalizedUpload = await uploadRequest(capability, {
        action: "finalize",
        payload: { file_id: result.uploaded_file_id },
        idempotencyKey: randomUUID(),
      });
      required(finalizedUpload?.state === "ACTIVE");
      uploadAccepted = true;
    } catch {
      phase = "UPLOAD_FINALIZE_RECONCILE";
      acceptAuthoritativeList(await uploadRequest(capability, { method: "GET" }));
    }

    phase = "LIST_ACCEPTED";
    const listed = await uploadRequest(capability, { method: "GET" });
    acceptAuthoritativeList(listed);

    phase = "UPLOAD_COMPLETE";
    const completed = await uploadRequest(capability, {
      action: "complete",
      payload: {},
      idempotencyKey: randomUUID(),
    });
    result.upload_complete = completed?.state === "COMPLETED" ? "PASS" : "FAIL";
    required(result.upload_complete === "PASS");
    uploadCompleted = true;

    phase = "CLEANUP";
    required(await reconcileCleanup());

    phase = "CANCEL";
    cancelAttempted = true;
    const cancelled = await client.rpc("transition_customer_request_v1", {
      p_request_id: result.customer_request_id,
      p_command_type: "CANCEL",
      p_expected_revision: fixture.revision,
      p_idempotency_key: randomUUID(),
      p_payload: {},
    });
    result.customer_request_final_status = cancelled.data?.status || null;
    required(!cancelled.error && result.customer_request_final_status === "CANCELLED");
    requestCancelled = true;

    phase = "FINALIZE";
    finalizeAttempted = true;
    const finalizedRun = await invoke({
      action: "finalize_internal_e2e_run",
      run_id: result.run_id,
      terminal_status: "PASSED",
      expected_revision: 0,
      idempotency_key: randomUUID(),
    });
    result.internal_e2e_final_status = finalizedRun?.status || null;
    required(result.internal_e2e_final_status === "PASSED");
    result.SMOKE_STATUS = "PASS";
  } catch {
    const failurePhase = phase;
    if (result.upload_request_id && !uploadCompleted && !revokeAttempted && !uploadRevoked) {
      try {
        revokeAttempted = true;
        const revoked = await invoke({
          action: "revoke_customer_request_upload_link",
          upload_request_id: result.upload_request_id,
          reason: "Synthetic internal Smoke B stopped before upload completion.",
          idempotency_key: randomUUID(),
        });
        uploadRevoked = revoked?.state === "REVOKED" && revoked.upload_request_id === result.upload_request_id;
      } catch {}
    }
    if (uploadAccepted && (uploadCompleted || uploadRevoked) && !cleanupAttempted && !cleanupCompleted) {
      try {
        await reconcileCleanup();
      } catch {}
    }
    if (result.customer_request_id && !cancelAttempted && !requestCancelled) {
      try {
        cancelAttempted = true;
        const cancelled = await client.rpc("transition_customer_request_v1", {
          p_request_id: result.customer_request_id,
          p_command_type: "CANCEL",
          p_expected_revision: 0,
          p_idempotency_key: randomUUID(),
          p_payload: {},
        });
        requestCancelled = !cancelled.error && cancelled.data?.status === "CANCELLED";
        if (requestCancelled) result.customer_request_final_status = "CANCELLED";
      } catch {}
    }
    if (result.run_id && !finalizeAttempted && requestCancelled && cleanupCompleted
        && (uploadCompleted || uploadRevoked)) {
      try {
        finalizeAttempted = true;
        const finalizedRun = await invoke({
          action: "finalize_internal_e2e_run",
          run_id: result.run_id,
          terminal_status: "FAILED",
          expected_revision: 0,
          idempotency_key: randomUUID(),
        });
        if (finalizedRun?.status === "FAILED") result.internal_e2e_final_status = "FAILED";
      } catch {}
    }
    result.SMOKE_STATUS = `FAILED: ${failurePhase}`;
  } finally {
    capability = null;
    syntheticFile = null;
  }
  return Object.fromEntries(INTERNAL_SMOKE_B_FIELDS.map((field)=>[field, result[field]]));
}

export async function startOperatorDashboard({
  client,
  functionsBaseUrl,
  callOperator = callCommercialOperator,
  requireAal2 = async ()=>true,
  verifiedIdentity = null,
  isCurrent = ()=>true,
  onIdentityReady = ()=>{},
  onAuthorizationFailure = ()=>{},
  onDossierRoute = ()=>{},
}) {
  async function invoke(input) {
    const response = await callOperator(client, functionsBaseUrl, input);
    if (response.status >= 400 || !response.body?.ok) {
      if (response.status === 401) onAuthorizationFailure();
      throw new Error(response.body?.code || "OPERATOR_REQUEST_FAILED");
    }
    return response.body.result;
  }

  const currentIdentity = verifiedIdentity || await invoke({ action: "get_current_operator_identity" });
  onIdentityReady(currentIdentity);
  const identity = currentOperatorIdentityPresentation(currentIdentity);
  for (const roleBadge of document.querySelectorAll("[data-operator-role-badge]")) roleBadge.textContent = identity.roleLabel;
  const moduleNavigation = document.getElementById("operatorModuleNavigation");
  const activeModule = operatorModuleFromUrl(window.location.href, currentIdentity.role);
  moduleNavigation.hidden = currentIdentity.role !== "owner";
  presentOperatorModule(document, activeModule);
  if (activeModule === "profile") {
    await initializeOperatorProfile(document, client);
    return currentIdentity;
  }
  if (activeModule === "dossiers") {
    for (const id of ["internalSmokePanel", "internalSmokeBPanel", "personalQueueWorkspace", "managerWorkspace"]) {
      const legacyWorkspace = document.getElementById(id);
      if (legacyWorkspace) legacyWorkspace.hidden = true;
    }
    const controller = initializeOperatorDossiers(document, client, currentIdentity, { onAuthorizationFailure, requireAal2 });
    document.querySelector("[data-dossiers-workspace]").operatorDossiersController = controller;
    mountInternalSmokeB({
      panel: document.getElementById("internalSmokeBPanel"),
      button: document.getElementById("internalSmokeBRun"),
      statusElement: document.getElementById("internalSmokeBStatus"),
      resultElement: document.getElementById("internalSmokeBResult"),
      url: window.location.href,
      identity: currentIdentity,
      requireAal2,
      confirmSmoke: ()=>window.confirm("Smoke B uitvoeren?\nEr wordt exact één synthetic PNG via één tijdelijke Upload Link geüpload en daarna aantoonbaar verwijderd. Er wordt geen echte klantdata gebruikt."),
      runSmoke: ()=>{
        const endpoint = `${functionsBaseUrl.replace(/\/$/, "")}/customer-request-upload`;
        return runInternalSmokeB({
          client,
          invoke,
          uploadRequest: async (capability, request) => {
            const isRead = request.method === "GET";
            const response = await fetch(endpoint, {
              method: isRead ? "GET" : "POST",
              headers: isRead
                ? { Authorization: `Bearer ${capability}`, Accept: "application/json" }
                : {
                  Authorization: `Bearer ${capability}`,
                  "Content-Type": "application/json",
                  "Idempotency-Key": request.idempotencyKey,
                },
              body: isRead ? undefined : JSON.stringify({ action: request.action, ...request.payload }),
              cache: "no-store",
              referrerPolicy: "no-referrer",
            });
            const body = await response.json().catch(()=>null);
            if (!response.ok || !body?.ok) throw new Error("UPLOAD_REQUEST_FAILED");
            return body;
          },
          putSignedBlob: async (url, blob) => {
            const response = await fetch(url, {
              method: "PUT",
              headers: { "Content-Type": blob.type, "x-upsert": "false" },
              body: blob,
              referrerPolicy: "no-referrer",
            });
            if (!response.ok) throw new Error("UPLOAD_FAILED");
          },
        });
      },
    });
    onDossierRoute("dedicated");
    return currentIdentity;
  }
  if (activeModule === "finance") {
    initializeOperatorFinance(document, client, currentIdentity, { onAuthorizationFailure });
    return currentIdentity;
  }
  if (activeModule === "workforce") {
    initializeOperatorWorkforce(document, client, currentIdentity, { onAuthorizationFailure });
    return currentIdentity;
  }
  if (activeModule === "calendar") {
    initializeOperatorCalendar(document, client, currentIdentity, { onAuthorizationFailure });
    return currentIdentity;
  }
  if (activeModule === "recruitment") {
    initializeOperatorRecruitment(document, client, currentIdentity, { onAuthorizationFailure });
    return currentIdentity;
  }
  if (activeModule === "messages") {
    initializeOperatorMessages(document, client, currentIdentity);
    return currentIdentity;
  }
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
  const sdfDocumentActions = document.getElementById("sdfDocumentActions");
  const sdfDocumentActionStatus = document.getElementById("sdfDocumentActionStatus");
  const sdfDocumentUploadUrl = document.getElementById("sdfDocumentUploadUrl");
  const sdfDocumentUploadCreate = document.getElementById("sdfDocumentUploadCreate");
  const sdfDocumentUploadCopy = document.getElementById("sdfDocumentUploadCopy");
  const sdfDocumentUploadRevoke = document.getElementById("sdfDocumentUploadRevoke");
  const sdfQualificationMessage = document.getElementById("sdfQualificationMessage");
  const sdfQualificationReview = document.getElementById("sdfQualificationReview");
  const sdfQualificationPrint = document.getElementById("sdfQualificationPrint");
  const sdfQualificationActions = document.getElementById("sdfQualificationActions");
  const internalSmokePanel = document.getElementById("internalSmokePanel");
  const internalSmokeRun = document.getElementById("internalSmokeRun");
  const internalSmokeStatus = document.getElementById("internalSmokeStatus");
  const internalSmokeResultElement = document.getElementById("internalSmokeResult");
  const internalSmokeBPanel = document.getElementById("internalSmokeBPanel");
  const internalSmokeBRun = document.getElementById("internalSmokeBRun");
  const internalSmokeBStatus = document.getElementById("internalSmokeBStatus");
  const internalSmokeBResultElement = document.getElementById("internalSmokeBResult");
  const managerWorkspace = document.getElementById("managerWorkspace");
  const pendingIntakesList = document.getElementById("pendingIntakesList");
  const pendingIntakesEmpty = document.getElementById("pendingIntakesEmpty");
  const pendingIntakesMessage = document.getElementById("pendingIntakesMessage");
  const pendingIntakesRefresh = document.getElementById("pendingIntakesRefresh");
  const pendingIntakeDetail = document.getElementById("pendingIntakeDetail");
  const pendingIntakeDetailEmpty = document.getElementById("pendingIntakeDetailEmpty");
  const pendingIntakesEntry = document.getElementById("pendingIntakesEntry");
  const pendingIntakesCount = document.getElementById("pendingIntakesCount");
  const pendingWorkspaceCount = document.getElementById("pendingWorkspaceCount");
  const pendingRetentionButtons = Array.from(document.querySelectorAll("[data-pending-retention-state]"));
  const pendingIntakeSearch = document.getElementById("pendingIntakeSearch");
  const pendingIntakeStatusFilter = document.getElementById("pendingIntakeStatusFilter");
  const pendingIntakeSort = document.getElementById("pendingIntakeSort");
  const pendingIntakeClearFilters = document.getElementById("pendingIntakeClearFilters");
  const pendingIntakeRetentionAction = document.getElementById("pendingIntakeRetentionAction");
  const pendingIntakeDangerZone = document.getElementById("pendingIntakeDangerZone");
  const pendingIntakeDangerStatus = document.getElementById("pendingIntakeDangerStatus");
  const pendingIntakeProductLabel = document.getElementById("pendingIntakeProductLabel");
  const pendingIntakeDelete = document.getElementById("pendingIntakeDelete");
  const pendingIntakeDeleteUnavailable = document.getElementById("pendingIntakeDeleteUnavailable");
  const pendingIntakeCommandDialog = document.getElementById("pendingIntakeCommandDialog");
  const pendingIntakeCommandForm = document.getElementById("pendingIntakeCommandForm");
  const pendingIntakeCommandReason = document.getElementById("pendingIntakeCommandReason");
  const pendingIntakeCommandCancel = document.getElementById("pendingIntakeCommandCancel");
  const pendingIntakeCommandConfirm = document.getElementById("pendingIntakeCommandConfirm");
  const pendingLifecycleButtons = Array.from(document.querySelectorAll("[data-pending-lifecycle-action]"));
  const list = document.getElementById("applicationList");
  const applicationRefresh = document.getElementById("applicationRefresh");
  const empty = document.getElementById("applicationEmpty");
  const listMessage = document.getElementById("applicationListMessage");
  const detail = document.getElementById("applicationDetail");
  const detailEmpty = document.getElementById("applicationDetailEmpty");
  const detailMessage = document.getElementById("applicationDetailMessage");
  const promote = document.getElementById("promoteApplication");
  const quotationActionButton = document.getElementById("quotationIssueAndDeliver");
  const quotationActionMessage = document.getElementById("quotationActionMessage");
  const assignmentDossier = document.getElementById("assignmentDossier");
  const assignmentCurrent = document.getElementById("assignmentCurrent");
  const assignmentForm = document.getElementById("assignmentForm");
  const assignmentOperator = document.getElementById("assignmentOperator");
  const assignmentReasonField = document.getElementById("assignmentReasonField");
  const assignmentReason = document.getElementById("assignmentReason");
  const assignmentSubmit = document.getElementById("assignmentSubmit");
  const assignmentMessage = document.getElementById("assignmentMessage");
  const confirmation = document.getElementById("promotionDialog");
  const applicationDossierActions = document.getElementById("applicationDossierActions");
  const applicationDossierPreview = document.getElementById("applicationDossierPreview");
  const applicationDossierPreviewClose = document.getElementById("applicationDossierPreviewClose");
  const dossierLifecycleDossier = document.getElementById("dossierLifecycleDossier");
  const dossierLifecycleTitle = document.getElementById("dossierLifecycleTitle");
  const dossierLifecycleMessage = document.getElementById("dossierLifecycleMessage");
  const dossierLifecycleButtons = Array.from(document.querySelectorAll("[data-dossier-lifecycle-action]"));
  const dossierLifecycleDialog = document.getElementById("dossierLifecycleDialog");
  const dossierLifecycleForm = document.getElementById("dossierLifecycleForm");
  const dossierLifecycleReason = document.getElementById("dossierLifecycleReason");
  const dossierLifecycleConfirm = document.getElementById("dossierLifecycleConfirm");
  const dossierLifecycleCancel = document.getElementById("dossierLifecycleCancel");
  const dossierPurge = document.getElementById("dossierPurge");
  const websiteDossierDangerZone = document.getElementById("websiteDossierDangerZone");
  const websiteDossierPurgeMessage = document.getElementById("websiteDossierPurgeMessage");
  const dossierPurgeDialog = document.getElementById("dossierPurgeDialog");
  const dossierPurgeForm = document.getElementById("dossierPurgeForm");
  const dossierPurgeReason = document.getElementById("dossierPurgeReason");
  const dossierPurgeConfirm = document.getElementById("dossierPurgeConfirm");
  const dossierPurgeCancel = document.getElementById("dossierPurgeCancel");
  const sdfDossierDangerZone = document.getElementById("sdfDossierDangerZone");
  const sdfDossierPurge = document.getElementById("sdfDossierPurge");
  const sdfDossierPurgeMessage = document.getElementById("sdfDossierPurgeMessage");
  const sdfDossierPurgeDialog = document.getElementById("sdfDossierPurgeDialog");
  const sdfDossierPurgeForm = document.getElementById("sdfDossierPurgeForm");
  const sdfDossierPurgeReason = document.getElementById("sdfDossierPurgeReason");
  const sdfDossierPurgeConfirm = document.getElementById("sdfDossierPurgeConfirm");
  const sdfDossierPurgeCancel = document.getElementById("sdfDossierPurgeCancel");
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
  let dossierPurgeBusy = false;
  let pendingDossierPurge = null;
  let sdfDossierPurgeBusy = false;
  let pendingSdfDossierPurge = null;
  let pendingSdfPurgeEligibility = null;
  let lifecycleBusy = false;
  let pendingLifecycleAction = null;
  let pendingIntakeItems = [];
  let selectedPendingIntake = null;
  let pendingRetentionState = "ACTIVE";
  let pendingWorkspaceBusy = false;
  let pendingWorkspaceCommand = null;
  let selectedDossierReference = null;
  let quotationActionBusy = false;

  const sdfDocumentController = createSdfDocumentWorkspaceController(invoke, (state)=>{
    const activeUpload = state.request?.upload_request;
    sdfDocumentActions.hidden = !state.application;
    sdfDocumentActionStatus.textContent = state.loading
      ? "Documentactie wordt voorbereid."
      : state.error ? "De documentactie kon niet worden voorbereid. Probeer opnieuw."
      : state.upload_url ? "De veilige uploadlink is klaar."
      : activeUpload ? `Er bestaat een actieve uploadlink tot ${formatDate(activeUpload.expires_at)}.`
      : "Maak alleen wanneer nodig een veilige uploadlink voor dit SDF-dossier.";
    sdfDocumentUploadUrl.value = state.upload_url || "";
    sdfDocumentUploadUrl.hidden = !state.upload_url;
    sdfDocumentUploadCreate.hidden = Boolean(activeUpload);
    sdfDocumentUploadCreate.disabled = state.loading;
    sdfDocumentUploadCreate.textContent = state.error ? "Opnieuw proberen" : "Veilige uploadlink aanmaken";
    sdfDocumentUploadCopy.hidden = !state.upload_url;
    sdfDocumentUploadCopy.disabled = state.loading;
    sdfDocumentUploadRevoke.hidden = !activeUpload;
    sdfDocumentUploadRevoke.disabled = state.loading;
  });
  sdfDocumentUploadCreate.addEventListener("click", ()=>sdfDocumentController.startUpload());
  sdfDocumentUploadCopy.addEventListener("click", async ()=>{
    if (!sdfDocumentController.state.upload_url) return;
    await navigator.clipboard.writeText(sdfDocumentController.state.upload_url);
    sdfDocumentActionStatus.textContent = "Uploadlink gekopieerd.";
  });
  sdfDocumentUploadRevoke.addEventListener("click", ()=>sdfDocumentController.revokeUploadLink());

  for (const roleBadge of roleBadges) roleBadge.textContent = identity.roleLabel;
  if (activeModule !== "dossiers") {
    internalSmokePanel.hidden = true;
    internalSmokeBPanel.hidden = true;
    personalQueueWorkspace.hidden = true;
    managerWorkspace.hidden = true;
  }
  /* Legacy Finance runtime archived after extraction to operator-finance.mjs.
    const activeFinanceTab = financeTabFromUrl(window.location.href, currentIdentity.role);
    presentFinanceTab(document, activeFinanceTab);
    if (activeFinanceTab === "websites") {
      const status = document.getElementById("financeWebsiteStatus");
      const count = document.getElementById("financeWebsiteCount");
      const content = document.getElementById("financeWebsiteContent");
      const totals = document.getElementById("financeCurrencyTotals");
      const projects = document.getElementById("financeProjectList");
      const empty = document.getElementById("financeProjectEmpty");
      try {
        const response = await client.rpc("get_website_finance_portfolio_v1");
        if (!isCurrent()) return currentIdentity;
        if (response.error) throw response.error;
        const portfolio = websiteFinancePortfolioPresentation(response.data);
        totals.replaceChildren();
        projects.replaceChildren();
        for (const currencyTotal of portfolio.currency_totals) {
          const group = document.createElement("section");
          const heading = document.createElement("h3");
          const metrics = document.createElement("dl");
          group.className = "finance-currency-group";
          heading.textContent = currencyTotal.currency;
          metrics.className = "finance-metrics";
          for (const [label, field] of [
            ["Totale commerciële waarde / commitment", "total_commitment_minor"],
            ["Verwachte betalingen", "total_expected_minor"],
            ["Bevestigd ontvangen", "total_confirmed_received_minor"],
          ]) {
            const metric = document.createElement("div");
            const term = document.createElement("dt");
            const value = document.createElement("dd");
            term.textContent = label;
            value.textContent = formatFinanceMoney(currencyTotal[field], currencyTotal.currency);
            metric.append(term, value);
            metrics.append(metric);
          }
          group.append(heading, metrics);
          totals.append(group);
        }
        for (const project of portfolio.projects) {
          const item = document.createElement("li");
          const heading = document.createElement("div");
          const reference = document.createElement("strong");
          const currency = document.createElement("span");
          const metrics = document.createElement("dl");
          const paymentStatus = document.createElement("p");
          reference.textContent = project.application_reference || project.project_id;
          currency.textContent = project.currency;
          heading.className = "finance-project-heading";
          metrics.className = "finance-project-metrics";
          paymentStatus.className = "finance-payment-status";
          paymentStatus.textContent = financeMilestoneStatus(project);
          heading.append(reference, currency);
          for (const [label, field] of [["Commitment", "accepted_total_minor"], ["Verwacht", "expected_minor"], ["Bevestigd ontvangen", "confirmed_received_minor"]]) {
            const metric = document.createElement("div");
            const term = document.createElement("dt");
            const value = document.createElement("dd");
            term.textContent = label;
            value.textContent = formatFinanceMoney(project[field], project.currency);
            metric.append(term, value);
            metrics.append(metric);
          }
          item.append(heading, metrics, paymentStatus);
          projects.append(item);
        }
        count.textContent = `${portfolio.projects.length} ${portfolio.projects.length === 1 ? "project" : "projecten"}`;
        empty.hidden = portfolio.projects.length !== 0;
        status.textContent = portfolio.projects.length ? "Websiteportfolio beschikbaar." : "";
        content.hidden = false;
      } catch {
        count.textContent = "Niet beschikbaar";
        status.textContent = "De financiële Websiteportfolio kon niet veilig worden geladen.";
        content.hidden = true;
      }
    }
    if (activeFinanceTab === "sdf") {
      const status = document.getElementById("financeSdfStatus");
      const count = document.getElementById("financeSdfCount");
      const content = document.getElementById("financeSdfContent");
      const totals = document.getElementById("financeSdfCurrencyTotals");
      const projects = document.getElementById("financeSdfProjectList");
      const empty = document.getElementById("financeSdfProjectEmpty");
      try {
        const response = await client.rpc("get_sdf_finance_portfolio_v1");
        if (!isCurrent()) return currentIdentity;
        if (response.error) throw response.error;
        const portfolio = sdfFinancePortfolioPresentation(response.data);
        totals.replaceChildren();
        projects.replaceChildren();
        for (const currencyTotal of portfolio.currency_totals) {
          const group = document.createElement("section");
          const heading = document.createElement("h3");
          const metrics = document.createElement("dl");
          group.className = "finance-currency-group";
          heading.textContent = currencyTotal.currency;
          metrics.className = "finance-metrics";
          for (const [label, field] of [
            ["Commerciële waarde", "commitment_minor"],
            ["M1-verplichtingen", "m1_obligation_minor"],
            ["Uitgereikte facturen", "issued_invoice_minor"],
          ]) {
            const metric = document.createElement("div");
            const term = document.createElement("dt");
            const value = document.createElement("dd");
            term.textContent = label;
            value.textContent = formatFinanceMoney(currencyTotal[field], currencyTotal.currency);
            metric.append(term, value);
            metrics.append(metric);
          }
          group.append(heading, metrics);
          totals.append(group);
        }
        for (const project of portfolio.projects) {
          const item = document.createElement("li");
          const heading = document.createElement("div");
          const reference = document.createElement("strong");
          const packageLabel = document.createElement("span");
          const metrics = document.createElement("dl");
          const detail = document.createElement("p");
          reference.textContent = project.application_reference || project.quotation_id;
          packageLabel.textContent = sdfPackageLabel(project.sdf_package);
          heading.className = "finance-project-heading";
          metrics.className = "finance-project-metrics finance-project-metrics--sdf";
          detail.className = "finance-payment-status";
          heading.append(reference, packageLabel);
          for (const [label, value] of [
            ["Commerciële waarde", formatFinanceMoney(project.commitment_minor, project.currency)],
            ["M1-verplichting", formatFinanceMoney(project.m1_obligation_minor, project.currency)],
            ["M1-status", "Verwacht"],
            ["Factuurvoorbereiding", project.invoice_candidate_state === "PREPARED" ? "Voorbereid" : "Niet voorbereid"],
            ["Factuurstatus", project.invoice_issuance_state === "ISSUED" ? "Uitgereikt" : "Niet uitgereikt"],
            ["Factuurreferentie", project.invoice_number || "Niet toegewezen"],
          ]) {
            const metric = document.createElement("div");
            const term = document.createElement("dt");
            const description = document.createElement("dd");
            term.textContent = label;
            description.textContent = value;
            metric.append(term, description);
            metrics.append(metric);
          }
          const dates = [];
          if (project.prepared_at) dates.push(`Voorbereid ${formatDate(project.prepared_at)}`);
          if (project.issued_at) dates.push(`Uitgereikt ${formatDate(project.issued_at)}`);
          detail.textContent = dates.length ? dates.join(" · ") : "Nog geen factuurdatums beschikbaar.";
          item.append(heading, metrics, detail);
          projects.append(item);
        }
        count.textContent = `${portfolio.project_count} ${portfolio.project_count === 1 ? "project" : "projecten"}`;
        empty.hidden = portfolio.project_count !== 0;
        status.textContent = portfolio.project_count ? "SDF-portfolio beschikbaar." : "";
        content.hidden = false;
      } catch {
        count.textContent = "Niet beschikbaar";
        status.textContent = "SDF-financiële gegevens konden niet worden geladen.";
        content.hidden = true;
      }
    }
    if (activeFinanceTab === "inbox") {
      const status = document.getElementById("documentInboxStatus");
      const count = document.getElementById("documentInboxCount");
      const filters = document.getElementById("documentInboxFilters");
      const clearFilters = document.getElementById("documentInboxClearFilters");
      const list = document.getElementById("documentInboxList");
      const empty = document.getElementById("documentInboxEmpty");
      const uploadOpen = document.getElementById("documentInboxUploadOpen");
      const uploadDialog = document.getElementById("documentInboxUploadDialog");
      const uploadForm = document.getElementById("documentInboxUploadForm");
      const uploadZone = document.getElementById("documentInboxUploadZone");
      const uploadFile = document.getElementById("documentInboxUploadFile");
      const uploadFileName = document.getElementById("documentInboxUploadFileName");
      const uploadStatus = document.getElementById("documentInboxUploadStatus");
      const uploadSubmit = document.getElementById("documentInboxUploadSubmit");
      const uploadCancel = document.getElementById("documentInboxUploadCancel");
      const dialog = document.getElementById("documentInboxDialog");
      const dialogFile = document.getElementById("documentInboxDialogFile");
      const dialogStatus = document.getElementById("documentInboxDialogStatus");
      const metadata = document.getElementById("documentInboxMetadata");
      const warnings = document.getElementById("documentInboxWarnings");
      const warningList = document.getElementById("documentInboxWarningList");
      const acknowledgeWarnings = document.getElementById("documentInboxAcknowledgeWarnings");
      const extraction = document.getElementById("documentInboxExtraction");
      const extractionStatus = document.getElementById("documentInboxExtractionStatus");
      const extractionMessage = document.getElementById("documentInboxExtractionMessage");
      const extractionCandidates = document.getElementById("documentInboxExtractionCandidates");
      const proposed = document.getElementById("documentInboxProposed");
      const form = document.getElementById("documentInboxConfirmedForm");
      const processedResult = document.getElementById("documentInboxProcessedResult");
      const actionStatus = document.getElementById("documentInboxActionStatus");
      const close = document.getElementById("documentInboxClose");
      const reject = document.getElementById("documentInboxReject");
      const extract = document.getElementById("documentInboxExtract");
      const saveProposal = document.getElementById("documentInboxSaveProposal");
      const saveConfirmed = document.getElementById("documentInboxSaveConfirmed");
      const approve = document.getElementById("documentInboxApprove");
      const process = document.getElementById("documentInboxProcess");
      const actionButtons = [reject, extract, saveProposal, saveConfirmed, approve, process];
      let inboxItems = [];
      let selectedInboxItem = null;
      let selectedInboxTrigger = null;
      let confirmedFormDirty = false;

      function appendDefinition(target, label, value) {
        const row = document.createElement("div");
        const term = document.createElement("dt");
        const description = document.createElement("dd");
        term.textContent = label;
        description.textContent = documentInboxDisplayValue(value);
        row.append(term, description);
        target.append(row);
      }

      function currentInboxFilters() {
        return Object.fromEntries(new FormData(filters));
      }

      function renderInboxList() {
        const visibleItems = documentInboxFilter(inboxItems, currentInboxFilters());
        list.replaceChildren();
        for (const item of visibleItems) {
          const row = document.createElement("li");
          const button = document.createElement("button");
          const identity = document.createElement("span");
          const supplier = document.createElement("strong");
          const reference = document.createElement("small");
          const facts = document.createElement("span");
          const lifecycle = document.createElement("span");
          const attention = document.createElement("small");
          const presentation = documentInboxStatusPresentation(item.lifecycle_status);
          supplier.textContent = item.confirmed_supplier_name || item.proposed_supplier_name || "Leverancier nog niet ingevuld";
          reference.textContent = item.confirmed_document_reference || item.proposed_document_reference || item.original_file_name || item.id;
          identity.className = "document-inbox-item__identity";
          identity.append(supplier, reference);
          facts.className = "document-inbox-item__facts";
          facts.textContent = [
            item.confirmed_document_type || item.proposed_document_type || "Type onbekend",
            item.confirmed_document_date || item.proposed_document_date || "Datum onbekend",
            Number.isSafeInteger(item.confirmed_amount_minor ?? item.proposed_amount_minor)
              ? formatFinanceMoney(item.confirmed_amount_minor ?? item.proposed_amount_minor, item.confirmed_currency || item.proposed_currency || "EUR")
              : "Bedrag onbekend",
            `Ontvangen ${formatDate(item.received_at)}`,
          ].join(" · ");
          lifecycle.className = `${documentInboxBadgeClass(item.lifecycle_status)} document-inbox-item__status`;
          lifecycle.textContent = presentation.label;
          attention.className = "document-inbox-item__attention";
          attention.textContent = item.warnings.length ? `${item.warnings.length} ${item.warnings.length === 1 ? "waarschuwing" : "waarschuwingen"}` : "Geen waarschuwingen";
          button.type = "button";
          button.className = "document-inbox-item";
          button.dataset.documentInboxItemId = item.id;
          button.setAttribute("aria-label", `${supplier.textContent}, ${presentation.label}`);
          button.addEventListener("click", ()=>openInboxItem(item, button));
          button.append(identity, facts, lifecycle, attention);
          row.append(button);
          list.append(row);
        }
        count.textContent = `${visibleItems.length} van ${inboxItems.length}`;
        empty.hidden = visibleItems.length !== 0;
      }

      function renderInboxReview(item) {
        const presentation = documentInboxStatusPresentation(item.lifecycle_status);
        const editable = ["RECEIVED", "REVIEW_REQUIRED"].includes(item.lifecycle_status);
        dialogFile.textContent = `${item.original_file_name || "Bestandsnaam niet beschikbaar"} · ${item.mime_type || "MIME onbekend"}`;
        dialogStatus.className = documentInboxBadgeClass(item.lifecycle_status);
        dialogStatus.textContent = presentation.label;
        metadata.replaceChildren();
        for (const [label, value] of [
          ["Ontvangen", formatDate(item.received_at)], ["Bron", String(item.source_type || "Onbekend").replaceAll("_", " ")],
          ["Bestand", item.original_file_name], ["MIME", item.mime_type], ["Grootte", formatDocumentInboxBytes(item.byte_count)],
        ]) appendDefinition(metadata, label, value);
        warningList.replaceChildren();
        for (const warning of item.warnings) {
          const warningItem = document.createElement("li");
          warningItem.textContent = documentInboxDisplayValue(typeof warning === "string" ? warning : warning?.message || warning?.code, "Controle vereist");
          warningList.append(warningItem);
        }
        warnings.hidden = item.warnings.length === 0;
        acknowledgeWarnings.checked = Boolean(item.warnings_acknowledged);
        acknowledgeWarnings.disabled = !editable;
        const extractionPresentation = documentInboxExtractionPresentation(item);
        extraction.hidden = false;
        extractionStatus.className = `badge${extractionPresentation.tone === "neutral" ? "" : ` badge--${extractionPresentation.tone}`}`;
        extractionStatus.textContent = extractionPresentation.label;
        extractionMessage.textContent = extractionPresentation.message;
        extractionCandidates.replaceChildren();
        for (const candidate of extractionPresentation.candidates) {
          appendDefinition(extractionCandidates, candidate.label, `${candidate.value} · Zekerheid ${candidate.confidence} · Bewijs ${candidate.evidence}`);
        }
        proposed.replaceChildren();
        for (const [label, value] of [
          ["Leverancier", item.proposed_supplier_name], ["Documenttype", item.proposed_document_type],
          ["Referentie", item.proposed_document_reference], ["Documentdatum", item.proposed_document_date],
          ["Kostendatum", item.proposed_expense_date],
          ["Bedrag", Number.isSafeInteger(item.proposed_amount_minor) ? formatFinanceMoney(item.proposed_amount_minor, item.proposed_currency || "EUR") : null],
          ["Omschrijving", item.proposed_description], ["Categorie", item.proposed_category], ["Relatietype", item.proposed_relation_type],
        ]) appendDefinition(proposed, label, value);
        const initialValues = documentInboxInitialValues(item);
        for (const [name, value] of Object.entries(initialValues)) form.elements.namedItem(name).value = value;
        confirmedFormDirty = false;
        for (const field of form.querySelectorAll("input, select, textarea")) field.disabled = !editable;
        reject.hidden = !["RECEIVED", "REVIEW_REQUIRED"].includes(item.lifecycle_status);
        extract.hidden = !["RECEIVED", "REVIEW_REQUIRED"].includes(item.lifecycle_status);
        extract.textContent = item.extraction_status === "NOT_RECORDED" ? "Document analyseren" : "Opnieuw analyseren";
        saveProposal.hidden = item.lifecycle_status !== "RECEIVED";
        saveConfirmed.hidden = item.lifecycle_status !== "REVIEW_REQUIRED";
        approve.hidden = item.lifecycle_status !== "REVIEW_REQUIRED";
        approve.disabled = !documentInboxHasConfirmedValues(item) || (item.warnings.length > 0 && !acknowledgeWarnings.checked);
        process.hidden = item.lifecycle_status !== "APPROVED";
        process.textContent = item.processing_error_code ? "Opnieuw proberen" : "Verwerken";
        processedResult.hidden = item.lifecycle_status !== "PROCESSED";
        if (item.lifecycle_status === "PROCESSED") {
          document.getElementById("documentInboxExpenseResult").textContent = documentInboxDisplayValue(item.result_business_expense_id, "Niet beschikbaar");
          document.getElementById("documentInboxDocumentResult").textContent = documentInboxDisplayValue(item.result_supplier_document_id, "Niet beschikbaar");
          document.getElementById("documentInboxLinkResult").textContent = documentInboxDisplayValue(item.result_link_id, "Niet beschikbaar");
          document.getElementById("documentInboxProcessedAt").textContent = item.processed_at ? formatDate(item.processed_at) : "Niet beschikbaar";
        }
        actionStatus.textContent = item.processing_error_code
          ? "De vorige verwerking is niet voltooid. Controleer de gegevens en probeer opnieuw."
          : item.lifecycle_status === "REJECTED" ? "Dit document is definitief afgewezen." : "";
      }

      function openInboxItem(item, trigger) {
        selectedInboxItem = item;
        selectedInboxTrigger = trigger;
        renderInboxReview(item);
        dialog.showModal();
        close.focus();
      }

      async function loadDocumentInbox(successMessage = "") {
        try {
          const response = await client.rpc("get_document_inbox_v1", { p_lifecycle_status: null, p_record_classification: "production" });
          if (!isCurrent()) return;
          if (response.error) throw response.error;
          inboxItems = documentInboxReadPresentation(response.data).items;
          renderInboxList();
          if (dialog.open && selectedInboxItem) {
            const currentItem = inboxItems.find((item)=>item.id === selectedInboxItem.id);
            if (currentItem) {
              selectedInboxItem = currentItem;
              renderInboxReview(currentItem);
            } else {
              dialog.close();
            }
          }
          status.textContent = successMessage || (inboxItems.length ? "Document Inbox beschikbaar." : "Nog geen documenten ontvangen.");
        } catch {
          inboxItems = [];
          renderInboxList();
          count.textContent = "Niet beschikbaar";
          status.textContent = "Document Inbox kon niet veilig worden geladen.";
        }
      }

      const uploadController = createDocumentInboxUploadController({
        uploadDocument: async (file)=>{
          const response = await client.functions.invoke("supplier-document-upload", {
            method: "POST",
            headers: { "Content-Type": file.type },
            body: file,
          });
          if (response.error) throw response.error;
          return response.data;
        },
        receiveDocument: async (request)=>{
          const response = await client.rpc("receive_document_inbox_item_v1", request);
          if (response.error) throw response.error;
          return response.data;
        },
        reloadInbox: ()=>loadDocumentInbox(),
        onBusy: (busy)=>{
          uploadSubmit.disabled = busy;
          uploadCancel.disabled = busy;
          uploadFile.disabled = busy;
          uploadSubmit.textContent = busy ? "Document ontvangen..." : uploadController.retryStage === "receive" ? "Inbox-registratie opnieuw proberen" : "Document uploaden";
          if (busy) uploadStatus.textContent = uploadController.retryStage === "receive"
            ? "Veilig opgeslagen document registreren in de Inbox."
            : "Document veilig uploaden en ontvangen.";
        },
        onFailure: (stage)=>{
          if (stage === "validation") uploadStatus.textContent = "Kies een geldig PDF-, PNG- of JPEG-bestand van maximaal 10 MiB.";
          else if (stage === "upload") uploadStatus.textContent = "Document kon niet veilig worden geüpload.";
          else if (stage === "receive") uploadStatus.textContent = "Bestand veilig opgeslagen, registratie in de Inbox nog niet voltooid.";
          else uploadStatus.textContent = "Document is ontvangen, maar de actuele Inbox kon niet worden geladen.";
          uploadSubmit.textContent = stage === "receive" ? "Inbox-registratie opnieuw proberen" : stage === "reload" ? "Inbox opnieuw laden" : "Document uploaden";
        },
        onSuccess: (result)=>{
          uploadForm.reset();
          uploadFileName.textContent = "Sleep een document hierheen of selecteer een bestand";
          uploadDialog.close();
          status.textContent = result.duplicate ? "Dit document was al ontvangen." : "Document ontvangen en toegevoegd aan de Inbox.";
          uploadOpen.focus();
        },
      });

      async function extractionInvokeError(error) {
        let code = String(error?.message || "DOCUMENT_INBOX_EXTRACTION_NOT_AVAILABLE");
        const status = Number(error?.context?.status || 0);
        try {
          const payload = await error.context.clone().json();
          if (typeof payload?.code === "string") code = payload.code;
        } catch {}
        return Object.assign(new Error(code), { code, status });
      }

      const extractionController = createDocumentInboxExtractionController({
        execute: async (request)=>{
          const response = await client.functions.invoke("document-inbox-extract", {
            method: "POST",
            body: request,
          });
          if (response.error) throw await extractionInvokeError(response.error);
          return response.data;
        },
        reload: ()=>loadDocumentInbox(),
        onBusy: (busy)=>{
          for (const button of actionButtons) button.disabled = busy || (button === approve && (confirmedFormDirty
            || !selectedInboxItem || !documentInboxHasConfirmedValues(selectedInboxItem)
            || selectedInboxItem.warnings.length > 0 && !acknowledgeWarnings.checked));
          close.disabled = busy;
          for (const field of form.querySelectorAll("input, select, textarea")) field.disabled = busy || !["RECEIVED", "REVIEW_REQUIRED"].includes(selectedInboxItem?.lifecycle_status);
          acknowledgeWarnings.disabled = busy || !["RECEIVED", "REVIEW_REQUIRED"].includes(selectedInboxItem?.lifecycle_status);
          extract.textContent = busy ? "Analyseren..." : selectedInboxItem?.extraction_status === "NOT_RECORDED" ? "Document analyseren" : "Opnieuw analyseren";
          if (busy) actionStatus.textContent = "Document wordt veilig geanalyseerd.";
        },
        onSuccess: (result)=>{
          actionStatus.textContent = result.extraction_status === "ERROR"
            ? "Analyse niet beschikbaar. Probeer opnieuw of beoordeel het document handmatig."
            : result.extraction_status === "PARTIAL"
            ? "Gedeeltelijke analyse geladen. Controleer alle voorstellen en bewijsgegevens."
            : "Analysevoorstellen geladen voor menselijke controle.";
        },
        onFailure: (failure)=>{
          actionStatus.textContent = failure === "REVISION_CONFLICT"
            ? "Het document is intussen gewijzigd. De actuele versie is geladen; controleer deze opnieuw."
            : failure === "AUTHORIZATION"
            ? "Je bent niet bevoegd om dit document te analyseren."
            : "Analyse kon niet worden gestart. De actuele Inbox is opnieuw geladen.";
        },
      });

      const controller = createDocumentInboxCommandController({
        execute: async (rpc, request)=>{
          const allowed = new Set(["update_document_inbox_proposal_v1", "confirm_document_inbox_values_v1", "approve_document_inbox_item_v1", "reject_document_inbox_item_v1", "process_document_inbox_item_v1"]);
          if (!allowed.has(rpc)) throw new Error("DOCUMENT_INBOX_COMMAND_NOT_ALLOWED");
          const response = await client.rpc(rpc, request);
          if (response.error) throw response.error;
          return response.data;
        },
        reload: ()=>loadDocumentInbox("Document Inbox bijgewerkt."),
        onBusy: (busy)=>{
          for (const button of actionButtons) button.disabled = busy || (button === approve && (confirmedFormDirty
            || !selectedInboxItem || !documentInboxHasConfirmedValues(selectedInboxItem)
            || selectedInboxItem.warnings.length > 0 && !acknowledgeWarnings.checked));
          close.disabled = busy;
          for (const field of form.querySelectorAll("input, select, textarea")) field.disabled = busy || !["RECEIVED", "REVIEW_REQUIRED"].includes(selectedInboxItem?.lifecycle_status);
          acknowledgeWarnings.disabled = busy || !["RECEIVED", "REVIEW_REQUIRED"].includes(selectedInboxItem?.lifecycle_status);
          if (busy) actionStatus.textContent = "Actie wordt verwerkt.";
        },
        onSuccess: ()=>{
          dialog.close();
          selectedInboxTrigger?.focus();
        },
        onFailure: (errorCode)=>{ actionStatus.textContent = errorCode === "DOCUMENT_INBOX_PROCESSING_ERROR" || errorCode === "PROCESSING_FAILED"
          ? "Verwerking niet voltooid. De actuele status is geladen; controleer de gegevens en probeer opnieuw."
          : "De actie kon niet worden voltooid. De actuele status is opnieuw geladen."; },
      });

      filters.addEventListener("submit", (event)=>event.preventDefault());
      filters.addEventListener("input", renderInboxList);
      filters.addEventListener("change", renderInboxList);
      clearFilters.addEventListener("click", ()=>{ filters.reset(); renderInboxList(); document.getElementById("documentInboxSearch").focus(); });
      uploadOpen.addEventListener("click", ()=>{
        uploadController.reset();
        uploadForm.reset();
        uploadStatus.textContent = "";
        uploadFileName.textContent = "Sleep een document hierheen of selecteer een bestand";
        uploadSubmit.textContent = "Document uploaden";
        uploadDialog.showModal();
        uploadFile.focus();
      });
      uploadFile.addEventListener("change", ()=>{
        uploadFile.setCustomValidity("");
        uploadFileName.textContent = uploadFile.files?.[0]?.name || "Sleep een document hierheen of selecteer een bestand";
      });
      for (const eventName of ["dragenter", "dragover"]) uploadZone.addEventListener(eventName, (event)=>{
        event.preventDefault();
        uploadZone.classList.add("is-dragging");
      });
      for (const eventName of ["dragleave", "drop"]) uploadZone.addEventListener(eventName, (event)=>{
        event.preventDefault();
        uploadZone.classList.remove("is-dragging");
      });
      uploadZone.addEventListener("drop", (event)=>{
        if (uploadController.submitting || !event.dataTransfer?.files?.length) return;
        uploadFile.files = event.dataTransfer.files;
        uploadFile.dispatchEvent(new Event("change", { bubbles: true }));
      });
      uploadCancel.addEventListener("click", ()=>{
        if (uploadController.submitting) return;
        uploadController.reset();
        uploadForm.reset();
        uploadDialog.close();
        uploadOpen.focus();
      });
      uploadDialog.addEventListener("cancel", (event)=>{
        if (uploadController.submitting) event.preventDefault();
        else uploadController.reset();
      });
      uploadDialog.addEventListener("close", ()=>uploadOpen.focus());
      uploadForm.addEventListener("submit", async (event)=>{
        event.preventDefault();
        if (uploadController.submitting) return;
        const file = uploadFile.files?.[0];
        const fileError = supplierDocumentFileError(file);
        if (fileError) {
          uploadFile.setCustomValidity(fileError === "FILE_TOO_LARGE"
            ? "Kies een bestand van maximaal 10 MiB."
            : "Kies een PDF-, PNG- of JPEG-bestand.");
          uploadFile.reportValidity();
          return;
        }
        await uploadController.submit(file);
      });
      form.addEventListener("input", ()=>{ confirmedFormDirty = true; approve.disabled = true; });
      acknowledgeWarnings.addEventListener("change", ()=>{
        approve.disabled = confirmedFormDirty || !selectedInboxItem || !documentInboxHasConfirmedValues(selectedInboxItem)
          || (selectedInboxItem.warnings.length > 0 && !acknowledgeWarnings.checked);
      });
      close.addEventListener("click", ()=>{ if (!controller.submitting && !extractionController.submitting) dialog.close(); });
      dialog.addEventListener("cancel", (event)=>{ if (controller.submitting || extractionController.submitting) event.preventDefault(); });
      dialog.addEventListener("close", ()=>selectedInboxTrigger?.focus());
      extract.addEventListener("click", async ()=>{
        if (!selectedInboxItem) return;
        await extractionController.submit(selectedInboxItem);
      });
      saveProposal.addEventListener("click", async ()=>{
        if (!selectedInboxItem || !form.reportValidity()) return;
        await controller.submit("update_document_inbox_proposal_v1", documentInboxProposalRequest(selectedInboxItem, Object.fromEntries(new FormData(form))));
      });
      saveConfirmed.addEventListener("click", async ()=>{
        if (!selectedInboxItem || !form.reportValidity()) return;
        await controller.submit("confirm_document_inbox_values_v1", documentInboxConfirmRequest(selectedInboxItem, Object.fromEntries(new FormData(form))));
      });
      approve.addEventListener("click", async ()=>{
        if (!selectedInboxItem) return;
        await controller.submit("approve_document_inbox_item_v1", documentInboxApproveRequest(selectedInboxItem, acknowledgeWarnings.checked));
      });
      reject.addEventListener("click", async ()=>{
        if (!selectedInboxItem || !window.confirm("Dit document definitief afwijzen? Het kan daarna niet opnieuw worden geopend.")) return;
        await controller.submit("reject_document_inbox_item_v1", documentInboxRejectRequest(selectedInboxItem));
      });
      process.addEventListener("click", async ()=>{
        if (!selectedInboxItem) return;
        await controller.submit("process_document_inbox_item_v1", documentInboxProcessRequest(selectedInboxItem));
      });
      await loadDocumentInbox();
    }
    if (activeFinanceTab === "expenses") {
      const status = document.getElementById("financeExpenseStatus");
      const count = document.getElementById("financeExpenseCount");
      const content = document.getElementById("financeExpenseContent");
      const totals = document.getElementById("financeExpenseCurrencyTotals");
      const expenses = document.getElementById("financeExpenseList");
      const empty = document.getElementById("financeExpenseEmpty");
      const dialog = document.getElementById("businessExpenseDialog");
      const form = document.getElementById("businessExpenseForm");
      const formStatus = document.getElementById("businessExpenseFormStatus");
      const submit = document.getElementById("businessExpenseSubmit");
      const cancel = document.getElementById("businessExpenseCancel");
      const amount = document.getElementById("businessExpenseAmount");
      const expenseDate = document.getElementById("businessExpenseDate");
      const documentDialog = document.getElementById("supplierDocumentDialog");
      const documentForm = document.getElementById("supplierDocumentForm");
      const documentFormStatus = document.getElementById("supplierDocumentFormStatus");
      const documentExpense = document.getElementById("supplierDocumentExpense");
      const documentFile = document.getElementById("supplierDocumentFile");
      const documentSupplier = document.getElementById("supplierDocumentSupplier");
      const documentSubmit = document.getElementById("supplierDocumentSubmit");
      const documentCancel = document.getElementById("supplierDocumentCancel");
      let selectedExpense = null;
      const trigger = document.createElement("button");
      trigger.type = "button";
      trigger.className = "primary-action primary-action--compact";
      trigger.textContent = "Nieuwe bedrijfskost";
      trigger.id = "businessExpenseCreate";
      document.getElementById("financeExpensesTitle").closest(".finance-section-heading").append(trigger);
      const loadBusinessExpensePortfolio = async (successMessage = "")=>{
        try {
          const response = await client.rpc("get_business_expense_portfolio_v1");
          if (!isCurrent()) return;
          if (response.error) throw response.error;
          const portfolio = businessExpenseFinancePortfolioPresentation(response.data);
          totals.replaceChildren();
          expenses.replaceChildren();
          for (const currencyTotal of portfolio.currency_totals) {
            const group = document.createElement("section");
            const heading = document.createElement("h3");
            const metrics = document.createElement("dl");
            const metric = document.createElement("div");
            const term = document.createElement("dt");
            const value = document.createElement("dd");
            group.className = "finance-currency-group";
            heading.textContent = currencyTotal.currency;
            metrics.className = "finance-metrics finance-metrics--expense";
            term.textContent = "Geregistreerde kosten";
            value.textContent = formatFinanceMoney(currencyTotal.active_expense_minor, currencyTotal.currency);
            metric.append(term, value);
            metrics.append(metric);
            group.append(heading, metrics);
            totals.append(group);
          }
          for (const expense of portfolio.expenses) {
            const item = document.createElement("li");
            const heading = document.createElement("div");
            const supplier = document.createElement("strong");
            const lifecycle = document.createElement("span");
            const metrics = document.createElement("dl");
            const relations = document.createElement("p");
            supplier.textContent = expense.supplier_name;
            lifecycle.textContent = expense.status === "CANCELLED" ? "Geannuleerd" : "Geregistreerd";
            item.dataset.expenseStatus = expense.status;
            heading.className = "finance-project-heading";
            metrics.className = "finance-project-metrics finance-expense-metrics";
            relations.className = "finance-payment-status";
            heading.append(supplier, lifecycle);
            for (const [label, value] of [
              ["Omschrijving", expense.description || "Geen omschrijving"],
              ["Categorie", businessExpenseCategoryLabel(expense.category)],
              ["Bedrag", formatFinanceMoney(expense.amount_minor, expense.currency)],
              ["Datum", expense.expense_date],
              ["Documenten", `${expense.document_count} ${expense.document_count === 1 ? "document" : "documenten"}`],
            ]) {
              const metric = document.createElement("div");
              const term = document.createElement("dt");
              const description = document.createElement("dd");
              term.textContent = label;
              description.textContent = value;
              metric.append(term, description);
              metrics.append(metric);
            }
            relations.textContent = expense.relation_types.length
              ? expense.relation_types.map(businessExpenseRelationLabel).join(" · ")
              : "Geen documenttypes geregistreerd.";
            const actions = document.createElement("div");
            const addDocument = document.createElement("button");
            actions.className = "finance-expense-actions";
            addDocument.type = "button";
            addDocument.className = "secondary-action";
            addDocument.dataset.supplierDocumentExpenseId = expense.id;
            addDocument.textContent = "Document toevoegen";
            addDocument.setAttribute("aria-label", `Document toevoegen voor ${expense.supplier_name}`);
            addDocument.addEventListener("click", ()=>{
              selectedExpense = expense;
              documentForm.reset();
              documentSupplier.value = expense.supplier_name;
              documentExpense.textContent = `${expense.supplier_name} · ${expense.description || "Geen omschrijving"}`;
              documentFormStatus.textContent = "";
              documentSubmit.textContent = "Document opslaan en koppelen";
              documentDialog.showModal();
              documentFile.focus();
            });
            actions.append(addDocument);
            item.append(heading, metrics, relations, actions);
            expenses.append(item);
          }
          for (const availability of document.querySelectorAll("[data-expense-availability]")) {
            availability.textContent = portfolio.availability[availability.dataset.expenseAvailability]
              ? "Beschikbaar" : "Niet beschikbaar";
          }
          document.getElementById("financeExpenseBankAccount").textContent =
            portfolio.availability.bank_actuals_available || portfolio.bank_actuals !== null ? "Beschikbaar" : "Niet gekoppeld";
          count.textContent = `${portfolio.expense_count} ${portfolio.expense_count === 1 ? "kost" : "kosten"}`;
          empty.hidden = portfolio.expense_count !== 0;
          status.textContent = successMessage || (portfolio.expense_count ? "Bedrijfskosten beschikbaar." : "");
          content.hidden = false;
        } catch {
          count.textContent = "Niet beschikbaar";
          status.textContent = "Bedrijfskosten konden niet worden geladen.";
          content.hidden = true;
        }
      };
      await loadBusinessExpensePortfolio();
      const controller = createBusinessExpenseEntryController({
        createExpense: async (request)=>{
          const response = await client.rpc("create_business_expense_v1", request);
          if (response.error) throw response.error;
          return response.data;
        },
        reloadPortfolio: ()=>loadBusinessExpensePortfolio("Bedrijfskost opgeslagen."),
        onBusy: (busy)=>{
          submit.disabled = busy;
          cancel.disabled = busy;
          submit.textContent = busy ? "Opslaan..." : "Bedrijfskost opslaan";
          if (busy) formStatus.textContent = "Bedrijfskost opslaan.";
        },
        onCreated: ()=>{
          form.reset();
          dialog.close();
          trigger.focus();
        },
        onError: ()=>{ formStatus.textContent = "Bedrijfskost kon niet worden opgeslagen."; },
      });
      const documentController = createSupplierDocumentExpenseLinkController({
        uploadDocument: async (file)=>{
          const response = await client.functions.invoke("supplier-document-upload", {
            method: "POST",
            headers: { "Content-Type": file.type },
            body: file,
          });
          if (response.error) throw response.error;
          return response.data;
        },
        createDocument: async (request)=>{
          const response = await client.rpc("create_supplier_document_v1", request);
          if (response.error) throw response.error;
          return response.data;
        },
        linkDocument: async (request)=>{
          const response = await client.rpc("link_business_expense_document_v1", request);
          if (response.error || !UUID.test(String(response.data || ""))) throw response.error || new Error("INVALID_BUSINESS_EXPENSE_DOCUMENT_LINK_ID");
          return response.data;
        },
        reloadPortfolio: ()=>loadBusinessExpensePortfolio("Document opgeslagen en gekoppeld."),
        onBusy: (busy)=>{
          documentSubmit.disabled = busy;
          documentCancel.disabled = busy;
          for (const field of documentForm.querySelectorAll("input, select")) field.disabled = busy;
          if (busy) documentFormStatus.textContent = "Document wordt veilig opgeslagen en gekoppeld.";
        },
        onFailure: (stage)=>{
          if (stage === "upload") documentFormStatus.textContent = "Document kon niet veilig worden geüpload.";
          else if (stage === "create") documentFormStatus.textContent = "Document kon niet worden geregistreerd.";
          else if (stage === "link") documentFormStatus.textContent = "Document is opgeslagen maar kon niet aan de bedrijfskost worden gekoppeld.";
          else if (stage === "reload") documentFormStatus.textContent = "Document is gekoppeld maar de actuele bedrijfskosten konden niet worden geladen.";
          if (stage === "create") documentSubmit.textContent = "Registratie opnieuw proberen";
          if (stage === "link") documentSubmit.textContent = "Koppeling opnieuw proberen";
          if (stage === "reload") documentSubmit.textContent = "Portfolio opnieuw laden";
        },
        onSuccess: ()=>{
          const expenseId = selectedExpense?.id;
          documentForm.reset();
          documentDialog.close();
          selectedExpense = null;
          document.querySelector(`[data-supplier-document-expense-id="${expenseId}"]`)?.focus();
        },
      });
      trigger.addEventListener("click", ()=>{
        formStatus.textContent = "";
        if (!expenseDate.value) expenseDate.value = localDateInputValue();
        dialog.showModal();
        document.getElementById("businessExpenseSupplier").focus();
      });
      amount.addEventListener("input", ()=>amount.setCustomValidity(""));
      form.addEventListener("input", (event)=>event.target.setCustomValidity(""));
      cancel.addEventListener("click", ()=>{
        if (controller.submitting) return;
        form.reset();
        dialog.close();
        trigger.focus();
      });
      form.addEventListener("submit", async (event)=>{
        event.preventDefault();
        const values = Object.fromEntries(new FormData(form));
        const supplier = document.getElementById("businessExpenseSupplier");
        const description = document.getElementById("businessExpenseDescription");
        if (!String(values.supplier_name).trim()) {
          supplier.setCustomValidity("Vul een leverancier in.");
          supplier.reportValidity();
          return;
        }
        if (!String(values.description).trim()) {
          description.setCustomValidity("Vul een omschrijving in.");
          description.reportValidity();
          return;
        }
        if (businessExpenseAmountMinor(amount.value) === null) {
          amount.setCustomValidity("Voer een bedrag groter dan nul in met maximaal twee decimalen.");
          amount.reportValidity();
          return;
        }
        await controller.submit(values);
      });
      documentForm.addEventListener("input", (event)=>event.target.setCustomValidity(""));
      documentFile.addEventListener("change", ()=>documentFile.setCustomValidity(""));
      documentCancel.addEventListener("click", ()=>{
        if (documentController.submitting) return;
        if (documentController.retryStage) {
          documentFormStatus.textContent = "Voltooi eerst de openstaande documentstap zodat geen opgeslagen document ongekoppeld achterblijft.";
          documentSubmit.focus();
          return;
        }
        const returnTarget = selectedExpense?.id;
        documentController.reset();
        documentForm.reset();
        documentDialog.close();
        selectedExpense = null;
        document.querySelector(`[data-supplier-document-expense-id="${returnTarget}"]`)?.focus();
      });
      documentForm.addEventListener("submit", async (event)=>{
        event.preventDefault();
        if (!selectedExpense || documentController.submitting) return;
        const file = documentFile.files?.[0];
        const fileError = supplierDocumentFileError(file);
        if (fileError) {
          documentFile.setCustomValidity(fileError === "FILE_TOO_LARGE"
            ? "Kies een bestand van maximaal 10 MiB."
            : "Kies een PDF-, PNG- of JPEG-bestand.");
          documentFile.reportValidity();
          return;
        }
        if (!documentForm.reportValidity()) return;
        const values = Object.fromEntries(new FormData(documentForm));
        await documentController.submit({ expenseId: selectedExpense.id, file, values });
      });
    }
  }
  */
  const canManagePendingIntakes = ["owner", "admin"].includes(currentIdentity.role);
  if (pendingIntakesEntry) pendingIntakesEntry.hidden = !canManagePendingIntakes;

  async function loadPendingIntakeCount() {
    if (!canManagePendingIntakes || !pendingIntakesCount) return;
    try {
      const result = await invoke(pendingIntakeCountRequest());
      pendingIntakesCount.textContent = String(result.active_count);
      pendingIntakesCount.setAttribute("aria-label", `${result.active_count} actieve intakes`);
    } catch {
      pendingIntakesCount.textContent = "–";
      pendingIntakesCount.setAttribute("aria-label", "Actieve intakes niet beschikbaar");
    }
  }

  if (activeModule === "dossiers") await loadPendingIntakeCount();

  if (activeModule === "intake") {
    const clearPendingWorkspaceDetail = ()=>{
      selectedPendingIntake = null;
      pendingSdfPurgeEligibility = null;
      setText("pendingIntakeName", "Intakedetail");
      pendingIntakeDetail.hidden = true;
      pendingIntakeDetailEmpty.hidden = false;
      pendingIntakeDangerZone.hidden = true;
      for (const button of pendingLifecycleButtons) button.hidden = true;
    };
    const renderPendingWorkspaceDetail = (item)=>{
      const presentation = pendingIntakePresentation(item);
      if (!presentation) return clearPendingWorkspaceDetail();
      const identity = pendingIntakeIdentityPresentation(item);
      if (selectedPendingIntake?.quote_request_id !== item.quote_request_id) pendingSdfPurgeEligibility = null;
      selectedPendingIntake = item;
      pendingIntakeDetail.hidden = false;
      pendingIntakeDetailEmpty.hidden = true;
      setText("pendingIntakeName", identity.contactName);
      setText("pendingIntakeOrganization", identity.organization);
      setText("pendingIntakeContactName", identity.contactName);
      setText("pendingIntakeEmail", item.email);
      setText("pendingIntakePhone", item.phone || "Niet opgegeven");
      setText("pendingIntakeRequestKind", item.request_kind === "slimme_documentenflow" ? "Slimme documentenflow" : "Website");
      setText("pendingIntakeSupportReference", identity.supportReference);
      pendingIntakeProductLabel.textContent = item.request_kind === "slimme_documentenflow" ? "Pakket" : "Website";
      setText("pendingIntakeWebsiteType", item.website_type);
      setText("pendingIntakeInvitedAt", formatDate(presentation.invitedAt));
      setText("pendingIntakeExpiresAt", formatDate(item.access_token_expires_at));
      setText("pendingIntakeQuoteRequestId", item.quote_request_id);
      setText("pendingIntakeId", item.intake_id);
      setBadge("pendingIntakeStatus", presentation.intake.label, presentation.intake.tone);
      setBadge("pendingIntakeAccess", `Toegang ${presentation.access.label.toLowerCase()}`, presentation.access.tone);
      setBadge("pendingIntakeRetention", item.retention_state === "ARCHIVED" ? "Gearchiveerd" : "Actief", item.retention_state === "ARCHIVED" ? "gray" : "green");
      for (const button of pendingLifecycleButtons) {
        button.hidden = !presentation.access.actions.includes(button.dataset.pendingLifecycleAction);
        button.disabled = pendingWorkspaceBusy;
      }
      const archived = item.retention_state === "ARCHIVED";
      pendingIntakeRetentionAction.textContent = archived ? "Terugzetten naar actief" : "Archiveren";
      pendingIntakeRetentionAction.dataset.action = archived ? "restore" : "archive";
      pendingIntakeRetentionAction.disabled = pendingWorkspaceBusy;
      const isSdf = item.request_kind === "slimme_documentenflow";
      const purgePresentation = pendingIntakePurgePresentation(item, isSdf ? pendingSdfPurgeEligibility : null);
      pendingIntakeDangerZone.hidden = !isSdf && !purgePresentation.canPurge;
      pendingIntakeDelete.hidden = !purgePresentation.canPurge;
      pendingIntakeDangerStatus.textContent = purgePresentation.message;
      pendingIntakeDeleteUnavailable.textContent = purgePresentation.canPurge
        ? "Definitief verwijderen is voor dit dependency-vrije historie-item toegestaan."
        : "Definitief verwijderen is beschermd zolang commerciële of dossierafhankelijkheden bestaan.";
      if (isSdf && pendingSdfPurgeEligibility === null) void refreshPendingSdfPurgeEligibility(item);
    };
    const refreshPendingSdfPurgeEligibility = async (item)=>{
      const { data, error } = await client.rpc("can_purge_sdf_dossier_v1", {
        p_quote_request_id: item.quote_request_id,
      });
      if (selectedPendingIntake !== item) return;
      pendingSdfPurgeEligibility = error ? {} : data;
      const presentation = pendingIntakePurgePresentation(item, pendingSdfPurgeEligibility);
      pendingIntakeDelete.hidden = !presentation.canPurge;
      pendingIntakeDangerStatus.textContent = presentation.message;
      pendingIntakeDeleteUnavailable.textContent = presentation.canPurge
        ? "Definitief verwijderen is voor dit dependency-vrije historie-item toegestaan."
        : "Definitief verwijderen is beschermd zolang commerciële of dossierafhankelijkheden bestaan.";
    };
    const renderPendingWorkspaceList = ()=>{
      const items = pendingIntakeWorkspaceItems(pendingIntakeItems, {
        search: pendingIntakeSearch.value,
        filter: pendingIntakeStatusFilter.value,
        sort: pendingIntakeSort.value,
      });
      pendingIntakesList.replaceChildren();
      pendingIntakesEmpty.hidden = items.length > 0;
      pendingIntakesEmpty.textContent = pendingIntakeItems.length === 0
        ? (pendingRetentionState === "ARCHIVED" ? "Er zijn geen gearchiveerde intakes." : "Niemand wacht momenteel op intake.")
        : "Geen intakes voldoen aan deze zoekopdracht en filters.";
      pendingWorkspaceCount.textContent = `${items.length} van ${pendingIntakeItems.length}`;
      for (const item of items) {
        const presentation = pendingIntakePresentation(item);
        const row = document.createElement("li");
        const button = document.createElement("button");
        const identity = document.createElement("span");
        const name = document.createElement("strong");
        const context = document.createElement("small");
        const statuses = document.createElement("span");
        button.type = "button";
        button.className = "application-list__button";
        if (selectedPendingIntake?.intake_id === item.intake_id) button.setAttribute("aria-current", "true");
        name.textContent = item.organization || item.name;
        context.textContent = `${item.name} · ${formatDate(presentation.invitedAt)} · ${item.website_type}`;
        identity.append(name, context);
        statuses.className = "application-list__statuses";
        statuses.append(badge(presentation.intake.label, presentation.intake.tone));
        statuses.append(badge(`Toegang ${presentation.access.label.toLowerCase()}`, presentation.access.tone));
        button.append(identity, statuses);
        button.addEventListener("click", ()=>{
          renderPendingWorkspaceDetail(item);
          renderPendingWorkspaceList();
        });
        row.append(button);
        pendingIntakesList.append(row);
      }
    };
    const loadPendingWorkspace = async (message = "", { background = false } = {})=>{
      pendingIntakesRefresh.disabled = true;
      if (!background) pendingIntakesMessage.textContent = "Intakes worden geladen.";
      try {
        const result = await invoke(pendingIntakesRequest(pendingRetentionState));
        pendingIntakeItems = Array.isArray(result?.items) ? result.items.filter((item)=>pendingIntakePresentation(item)) : [];
        const selectedId = selectedPendingIntake?.intake_id;
        renderPendingWorkspaceList();
        renderPendingWorkspaceDetail(pendingIntakeItems.find((item)=>item.intake_id === selectedId) || null);
        pendingIntakesMessage.textContent = message;
      } catch {
        if (!background) pendingIntakesMessage.textContent = "Intakes konden niet worden geladen.";
      } finally {
        pendingIntakesRefresh.disabled = false;
      }
    };
    const setPendingWorkspaceBusy = (busy)=>{
      pendingWorkspaceBusy = busy;
      pendingIntakesRefresh.disabled = busy;
      pendingIntakeRetentionAction.disabled = busy;
      pendingIntakeDelete.disabled = busy;
      for (const button of pendingLifecycleButtons) button.disabled = busy;
    };

    for (const button of pendingRetentionButtons) {
      button.addEventListener("click", async ()=>{
        const state = button.dataset.pendingRetentionState;
        if (pendingWorkspaceBusy || state === pendingRetentionState) return;
        pendingRetentionState = state;
        for (const candidate of pendingRetentionButtons) candidate.setAttribute("aria-pressed", String(candidate === button));
        clearPendingWorkspaceDetail();
        await loadPendingWorkspace();
      });
    }
    for (const control of [pendingIntakeSearch, pendingIntakeStatusFilter, pendingIntakeSort]) {
      control.addEventListener(control === pendingIntakeSearch ? "input" : "change", renderPendingWorkspaceList);
    }
    pendingIntakeClearFilters.addEventListener("click", ()=>{
      pendingIntakeSearch.value = "";
      pendingIntakeStatusFilter.value = "ALL";
      pendingIntakeSort.value = "NEWEST";
      renderPendingWorkspaceList();
      pendingIntakeSearch.focus();
    });
    pendingIntakesRefresh.addEventListener("click", ()=>loadPendingWorkspace());
    pendingIntakeRetentionAction.addEventListener("click", ()=>{
      const item = selectedPendingIntake;
      if (!item || pendingWorkspaceBusy) return;
      const archive = pendingIntakeRetentionAction.dataset.action === "archive";
      pendingWorkspaceCommand = { type: archive ? "archive" : "restore", item };
      setText("pendingIntakeCommandEyebrow", "Bevestiging vereist");
      setText("pendingIntakeCommandTitle", archive ? "Intake archiveren" : "Intake terugzetten naar actief");
      setText("pendingIntakeCommandDescription", archive
        ? "De intake verdwijnt uit de actieve opvolging en blijft beschikbaar in het archief."
        : "De intake wordt opnieuw zichtbaar in de actieve opvolging.");
      pendingIntakeCommandConfirm.textContent = archive ? "Archiveren" : "Terugzetten";
      pendingIntakeCommandConfirm.className = "primary-action primary-action--compact";
      pendingIntakeCommandReason.value = "";
      pendingIntakeCommandDialog.showModal();
      pendingIntakeCommandReason.focus();
    });
    pendingIntakeDelete.addEventListener("click", ()=>{
      const item = selectedPendingIntake;
      const isSdf = item?.request_kind === "slimme_documentenflow";
      if (pendingWorkspaceBusy
          || (isSdf ? pendingSdfPurgeEligibility?.can_purge !== true : !item?.can_permanently_delete)) return;
      pendingWorkspaceCommand = { type: isSdf ? "delete_sdf" : "delete", item, eligibility: pendingSdfPurgeEligibility };
      setText("pendingIntakeCommandEyebrow", "Onomkeerbare actie");
      setText("pendingIntakeCommandTitle", "Intake definitief verwijderen");
      setText("pendingIntakeCommandDescription", `${item.name} en de bijbehorende nog niet ingediende intake worden definitief verwijderd. Dit kan niet ongedaan worden gemaakt.`);
      pendingIntakeCommandConfirm.textContent = "Definitief verwijderen";
      pendingIntakeCommandConfirm.className = "danger-action";
      pendingIntakeCommandReason.value = "";
      pendingIntakeCommandDialog.showModal();
      pendingIntakeCommandReason.focus();
    });
    pendingIntakeCommandReason.addEventListener("input", ()=>pendingIntakeCommandReason.setCustomValidity(""));
    pendingIntakeCommandCancel.addEventListener("click", ()=>pendingIntakeCommandDialog.close("cancel"));
    pendingIntakeCommandForm.addEventListener("submit", (event)=>{
      const reason = pendingIntakeCommandReason.value.trim();
      if (reason.length >= 1 && reason.length <= 500) return;
      event.preventDefault();
      pendingIntakeCommandReason.setCustomValidity("Vul een korte reden in.");
      pendingIntakeCommandReason.reportValidity();
    });
    pendingIntakeCommandDialog.addEventListener("close", async ()=>{
      const command = pendingWorkspaceCommand;
      pendingWorkspaceCommand = null;
      if (pendingIntakeCommandDialog.returnValue !== "confirm" || !command || pendingWorkspaceBusy) return;
      setPendingWorkspaceBusy(true);
      try {
        if (command.type === "delete_sdf") {
          await requireAal2();
          const input = pendingSdfDossierPurgeRequest(command.item, command.eligibility, pendingIntakeCommandReason.value, crypto.randomUUID());
          const { data, error } = await client.rpc("purge_sdf_dossier_v1", input);
          if (error || data?.quote_request_id !== command.item.quote_request_id
              || data?.deleted !== true || typeof data?.replayed !== "boolean") {
            throw new Error(error?.message || "SDF_DOSSIER_PURGE_FAILED");
          }
        } else if (command.type === "delete") {
          await requireAal2();
          await invoke(buildPendingIntakeDeleteCommand(command.item, pendingIntakeCommandReason.value, crypto.randomUUID()));
        } else {
          await invoke(buildPendingIntakeRetentionCommand(command.type === "archive" ? "archive_pending_intake" : "restore_pending_intake", command.item, pendingIntakeCommandReason.value, crypto.randomUUID()));
        }
        const successMessage = ["delete", "delete_sdf"].includes(command.type) ? "Intake is definitief verwijderd."
          : command.type === "archive" ? "Intake is gearchiveerd." : "Intake is teruggezet naar actief.";
        await Promise.all([loadPendingWorkspace(successMessage), loadPendingIntakeCount()]);
      } catch {
        const errorMessage = ["delete", "delete_sdf"].includes(command.type)
          ? "Definitief verwijderen is niet uitgevoerd. De serverbescherming blijft van kracht."
          : "De werkruimtestatus kon niet worden gewijzigd. De actuele status is opnieuw geladen.";
        await loadPendingWorkspace(errorMessage);
      } finally {
        setPendingWorkspaceBusy(false);
      }
    });
    for (const button of pendingLifecycleButtons) {
      button.addEventListener("click", ()=>{
        const presentation = pendingIntakePresentation(selectedPendingIntake);
        const action = button.dataset.pendingLifecycleAction;
        const actionPresentation = intakeLifecycleAction(action);
        if (pendingWorkspaceBusy || !presentation?.access.actions.includes(action) || !actionPresentation) return;
        pendingLifecycleAction = { action, lifecycle: presentation.lifecycle, presentation: actionPresentation };
        setText("lifecycleDialogTitle", actionPresentation.title);
        setText("lifecycleDialogDescription", actionPresentation.description);
        lifecycleConfirm.textContent = actionPresentation.label;
        lifecycleConfirm.className = action === "cancel_intake" ? "danger-action" : "primary-action primary-action--compact";
        lifecycleReason.value = "";
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
      if (lifecycleDialog.returnValue !== "confirm" || !command || pendingWorkspaceBusy) return;
      setPendingWorkspaceBusy(true);
      try {
        await invoke(buildIntakeLifecycleCommand(command.action, command.lifecycle, lifecycleReason.value, crypto.randomUUID()));
        await loadPendingWorkspace(`${command.presentation.label} is uitgevoerd.`);
      } catch {
        pendingIntakesMessage.textContent = "De lifecycleactie kon niet worden uitgevoerd. De actuele status is opnieuw geladen.";
        await loadPendingWorkspace(pendingIntakesMessage.textContent);
      } finally {
        setPendingWorkspaceBusy(false);
      }
    });
    internalSmokePanel.hidden = true;
    internalSmokeBPanel.hidden = true;
    personalQueueWorkspace.hidden = true;
    managerWorkspace.hidden = true;
    await Promise.all([loadPendingWorkspace(), loadPendingIntakeCount()]);
    const pendingRefreshController = createVisibilityRefreshController({
      refresh: async ()=>{
        if (pendingWorkspaceBusy || document.querySelector("dialog[open]")) return;
        await Promise.all([loadPendingWorkspace("", { background: true }), loadPendingIntakeCount()]);
      },
    });
    document.addEventListener("visibilitychange", pendingRefreshController.visibilityChanged);
    window.addEventListener("pagehide", pendingRefreshController.stop, { once: true });
    pendingRefreshController.start();
    return currentIdentity;
  }
  if (activeModule !== "dossiers") {
    return currentIdentity;
  }
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
  personalQueueWorkspace.hidden = currentIdentity.role === "owner";

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

  const dashboardRoute = currentIdentity.role === "owner"
    ? await listController.load() ? "manager" : "closed"
    : await resolveDashboardAuthority({
      loadPersonalQueue: ()=>personalQueueController.load(),
      getPersonalQueueError: ()=>personalQueueController.state.error,
      loadManagerAuthority: ()=>listController.load(),
    });
  onDossierRoute(dashboardRoute);
  if (!isCurrent()) return currentIdentity;
  if (dashboardRoute !== "manager") {
    if (isOperatorAuthorizationFailure(listController.state.error)) onAuthorizationFailure();
    if (dashboardRoute === "personal") {
      const personalRefreshController = createVisibilityRefreshController({
        refresh: ()=>personalQueueController.refresh(),
      });
      document.addEventListener("visibilitychange", personalRefreshController.visibilityChanged);
      window.addEventListener("pagehide", personalRefreshController.stop, { once: true });
      personalRefreshController.start();
    }
    return currentIdentity;
  }
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
    sdfDocumentController.selectApplication(null);
    resetAssignment();
    applyDetailVisibility(null, { detail, detailEmpty, promote, dossierSections, websiteDossierSections, sdfDossierSections, websiteDetailRows, sdfDetailRows, sdfDetailNotice });
    detailMessage.textContent = "";
    dossierLifecycleMessage.textContent = "";
    dossierPurge.hidden = true;
    websiteDossierDangerZone.hidden = true;
    sdfDossierPurge.hidden = true;
    sdfDossierPurgeMessage.textContent = "";
    lifecycleMessage.textContent = "";
    quotationActionButton.hidden = true;
    quotationActionMessage.textContent = "";
    applicationDossierActions.hidden = true;
    if (applicationDossierPreview.open) applicationDossierPreview.close();
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

  function renderDocumentState(message) {
    const list = document.getElementById("documentStatusList");
    list.replaceChildren();
    document.getElementById("documentManifestState").textContent = message;
  }

  function renderDocuments(application, manifest, requestId) {
    const list = document.getElementById("documentStatusList");
    const state = document.getElementById("documentManifestState");
    list.replaceChildren();
    state.textContent = manifest.length ? "" : "Geen dossierdocumenten beschikbaar.";
    for (const item of manifest) {
      const presentation = dossierDocumentPresentation(item);
      const row = document.createElement("li");
      const identity = document.createElement("div");
      const title = document.createElement("strong");
      const detail = document.createElement("small");
      title.textContent = presentation.name;
      detail.textContent = `${presentation.type} · ${formatDate(presentation.date)}`;
      identity.append(title, detail);
      row.append(identity, badge(presentation.status, item.accepted_at ? "green" : "amber"));
      if (presentation.actionable) {
        const open = document.createElement("button");
        open.type = "button";
        open.className = "secondary-action";
        open.textContent = "Openen / downloaden";
        open.addEventListener("click", async ()=>{
          open.disabled = true;
          const originalDetail = detail.textContent;
          detail.textContent = `${originalDetail} · Veilige link wordt gemaakt.`;
          try {
            const access = await invoke(dossierDocumentAccessRequest(application, item));
            if (requestId !== detailRequestId || selectedDetail?.quote_request_id !== application.quote_request_id) return;
            const url = new URL(String(access?.signed_url || ""));
            if (!["https:", "http:"].includes(url.protocol)
              || typeof access?.expires_at !== "string" || !Number.isFinite(Date.parse(access.expires_at))
              || typeof access?.filename !== "string" || !access.filename) {
              throw new Error("INVALID_DOSSIER_DOCUMENT_ACCESS");
            }
            const link = document.createElement("a");
            link.href = url.href;
            link.target = "_blank";
            link.rel = "noopener noreferrer";
            link.download = access.filename;
            document.body.append(link);
            link.click();
            link.remove();
            detail.textContent = originalDetail;
          } catch {
            if (requestId === detailRequestId) detail.textContent = `${originalDetail} · Document kon niet worden geopend.`;
          } finally {
            if (requestId === detailRequestId) open.disabled = false;
          }
        });
        row.append(open);
      }
      list.append(row);
    }
  }

  async function loadDossierDocuments(application, requestId) {
    renderDocumentState("Documenten worden geladen.");
    try {
      const manifest = await invoke(dossierDocumentManifestRequest(application));
      if (requestId !== detailRequestId || selectedDetail?.quote_request_id !== application.quote_request_id) return false;
      if (!Array.isArray(manifest)) throw new Error("INVALID_DOSSIER_DOCUMENT_MANIFEST");
      renderDocuments(application, manifest, requestId);
      return true;
    } catch {
      if (requestId !== detailRequestId) return false;
      renderDocumentState("Documenten konden niet worden geladen. Het dossier blijft beschikbaar.");
      return false;
    }
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
    dossierPurge.hidden = true;
    presentWebsiteDossierPurge(
      { section: websiteDossierDangerZone, message: websiteDossierPurgeMessage, action: dossierPurge },
      detailApplication,
      currentIdentity,
      null,
    );
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
    if (detailApplication?.request_kind === "website") {
      void refreshDossierPurgeEligibility(detailApplication, detailRequestId);
    } else {
      void refreshSdfDossierPurgeEligibility(detailApplication, detailRequestId);
    }
  }

  async function refreshDossierPurgeEligibility(detailApplication, requestId) {
    if (dossierPurgeBusy
        || currentIdentity?.status !== "ACTIVE"
        || currentIdentity.role !== "owner"
        || !["ACTIVE", "TRASHED"].includes(detailApplication?.dossier_lifecycle?.state)
        || !UUID.test(String(detailApplication?.quote_request_id || ""))) return;
    const { data, error } = await client.rpc("can_purge_dossier_v1", {
      p_quote_request_id: detailApplication.quote_request_id,
    });
    if (requestId !== detailRequestId || selectedDetail !== detailApplication) return;
    presentWebsiteDossierPurge(
      { section: websiteDossierDangerZone, message: websiteDossierPurgeMessage, action: dossierPurge },
      detailApplication,
      currentIdentity,
      error ? null : data,
    );
    dossierPurge.disabled = false;
  }

  async function refreshSdfDossierPurgeEligibility(detailApplication, requestId) {
    const nodes = { section: sdfDossierDangerZone, message: sdfDossierPurgeMessage, action: sdfDossierPurge };
    const initial = presentSdfDossierPurge(nodes, detailApplication, currentIdentity, null);
    if (sdfDossierPurgeBusy || !initial
        || !UUID.test(String(detailApplication?.quote_request_id || ""))) return;
    const { data, error } = await client.rpc("can_purge_sdf_dossier_v1", {
      p_quote_request_id: detailApplication.quote_request_id,
    });
    if (requestId !== detailRequestId || selectedDetail !== detailApplication) return;
    presentSdfDossierPurge(nodes, detailApplication, currentIdentity, error ? null : data);
    sdfDossierPurge.disabled = false;
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
    for (const button of pendingLifecycleButtons) button.disabled = busy;
  }

  function renderDetail(application) {
    if (!REQUEST_KINDS.has(application?.request_kind)) throw new Error("UNSUPPORTED_REQUEST_KIND");
    const isWebsite = application.request_kind === "website";
    selectedDetail = application;
    sdfDocumentController.selectApplication(isWebsite ? null : application);
    applyDetailVisibility(application.request_kind, { detail, detailEmpty, promote, dossierSections, websiteDossierSections, sdfDossierSections, websiteDetailRows, sdfDetailRows, sdfDetailNotice });
    const dossierOutput = application.application;
    applicationDossierActions.hidden = true;
    sdfQualificationReview.replaceChildren();
    sdfQualificationActions.hidden = true;
    sdfQualificationPrint.disabled = true;
    sdfQualificationMessage.textContent = isWebsite ? "" : "Qualification wordt geladen.";
    if (isWebsite && dossierOutput) {
      try {
        renderApplicationDossier(document.getElementById("applicationDossierCopyContent"), dossierOutput);
        setText("applicationDossierPreviewReference", dossierOutput.applicationReference);
        document.getElementById("applicationDossierView").onclick = () => applicationDossierPreview.showModal();
        document.getElementById("applicationDossierDownload").onclick = () => downloadApplicationDossierPdf(dossierOutput);
        document.getElementById("applicationDossierPrint").onclick = () => printApplicationDossier(dossierOutput);
        document.getElementById("applicationDossierPreviewDownload").onclick = () => downloadApplicationDossierPdf(dossierOutput);
        document.getElementById("applicationDossierPreviewPrint").onclick = () => printApplicationDossier(dossierOutput);
        applicationDossierActions.hidden = false;
      } catch {
        applicationDossierActions.hidden = true;
      }
    }
    const applicationPresentation = applicationIdentityPresentation(application);
    const detailReference = document.getElementById("detailReference");
    setText("detailReference", applicationPresentation.visibleReference);
    if (!APPLICATION_REFERENCE.test(String(application.application_reference || "")) && UUID.test(String(application.quote_request_id || ""))) {
      detailReference.title = application.quote_request_id;
      detailReference.setAttribute("aria-label", `${applicationPresentation.visibleReference}. Volledige technische referentie ${application.quote_request_id}`);
    } else {
      detailReference.removeAttribute("title");
      detailReference.removeAttribute("aria-label");
    }
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
    const quotationDelivery = quotationDeliveryPresentation(application.quotation?.delivery);
    setBadge("detailQuotationDelivery", quotationDelivery?.label || "Nog niet gestart", quotationDelivery?.tone);
    setBadge("quotationStateBadge", application.acceptance ? "ACCEPTED" : application.quotation?.issuance_status || "NOT ISSUED", application.acceptance ? "green" : "amber");
    quotationActionButton.hidden = !canIssueApprovedQuotation(application, currentIdentity);
    quotationActionButton.disabled = quotationActionBusy;
    promote.hidden = !canPromoteApplication(application);
    renderDocumentState("Documenten worden geladen.");
    renderProjectDossier(null);
  }

  async function loadSdfQualification(application, requestId) {
    if (application.request_kind !== "slimme_documentenflow") return true;
    try {
      const readModel = await invoke(sdfQualificationDetailRequest(application));
      if (requestId !== detailRequestId || selectedDetail !== application) return false;
      const output = sdfQualificationDetailPresentation(readModel, application);
      setBadge("sdfQualificationStatus", output.status.label, output.status.tone);
      setText("sdfQualificationCustomer", output.context.customerName || "Niet beschikbaar");
      setText("sdfQualificationOrganization", output.context.organization || "Niet beschikbaar");
      setText("sdfQualificationEmail", output.context.email || "Niet beschikbaar");
      setText("sdfQualificationIntakeReference", output.context.reference || "Niet beschikbaar");
      setText("sdfQualificationTaxonomy", output.meta.taxonomyVersion);
      setText("sdfQualificationSubmission", output.meta.submissionSequence);
      if (!output.answers) {
        sdfQualificationReview.replaceChildren();
        sdfQualificationMessage.textContent = "Er is nog geen ingediende qualification beschikbaar.";
        sdfQualificationActions.hidden = true;
        return true;
      }
      renderSdfQualificationReview(sdfQualificationReview, output.answers, output.context);
      sdfQualificationPrint.onclick = () => printSdfQualificationReview(output.answers, output.context);
      sdfQualificationPrint.disabled = false;
      sdfQualificationActions.hidden = false;
      sdfQualificationMessage.textContent = "";
      return true;
    } catch {
      if (requestId !== detailRequestId || selectedDetail !== application) return false;
      sdfQualificationReview.replaceChildren();
      sdfQualificationActions.hidden = true;
      sdfQualificationPrint.disabled = true;
      setBadge("sdfQualificationStatus", "Niet beschikbaar", "amber");
      sdfQualificationMessage.textContent = "De qualificationdetail is niet beschikbaar voor deze operator of aanvraag.";
      return false;
    }
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
      await Promise.all([
        loadAssignment(application, requestId),
        loadDossierDocuments(application, requestId),
        loadSdfQualification(application, requestId),
      ]);
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
      if (!APPLICATION_REFERENCE.test(String(application.application_reference || "")) && UUID.test(String(application.quote_request_id || ""))) reference.title = application.quote_request_id;
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

  async function refreshDashboard({ background = false } = {}) {
    const locator = selectedLocator ? { ...selectedLocator } : null;
    const loaded = await listController.refresh();
    if (!loaded || !locator) return loaded;
    if (background && (document.querySelector("dialog[open]")
        || document.activeElement?.matches("input, textarea, select"))) return true;
    const summary = listController.state.items.find((item)=>locatorMatchesApplication(locator, item));
    if (summary) await loadDetail(locator, summary);
    return true;
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
  applicationRefresh.addEventListener("click", ()=>void refreshDashboard());

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

  applicationDossierPreviewClose.addEventListener("click", () => applicationDossierPreview.close());
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

  quotationActionButton.addEventListener("click", async ()=>{
    const input = quotationIssuanceRequest(selectedDetail);
    if (quotationActionBusy || !input || !canIssueApprovedQuotation(selectedDetail, currentIdentity)
      || !selectedLocator || !window.confirm("Goedgekeurde offerte uitgeven en naar de vastgelegde ontvanger sturen?")) return;
    const locator = { ...selectedLocator };
    const selectionRequestId = detailRequestId;
    quotationActionBusy = true;
    quotationActionButton.disabled = true;
    quotationActionMessage.textContent = "Offerte wordt uitgegeven en gearchiveerd.";
    try {
      const result = await invoke(input);
      const refresh = await refreshMutationDetail(locator, selectionRequestId);
      if (refresh.status !== "refreshed") return;
      const delivery = quotationDeliveryPresentation({ status: result.delivery_status });
      quotationActionMessage.textContent = delivery?.label || "Offerte is uitgegeven en gearchiveerd. Controleer de leveringsstatus.";
    } catch (error) {
      if (selectionRequestId !== detailRequestId) return;
      const code = error instanceof Error ? error.message : "INTERNAL_ERROR";
      quotationActionMessage.textContent = code === "QUOTATION_NOT_ISSUABLE"
        ? "Deze offerte is niet uitgifteklaar. Controleer de approval en authoritystatus."
        : code === "QUOTATION_ARCHIVE_FAILED"
        ? "De offerte is niet afgeleverd omdat archivering niet kon worden bevestigd."
        : code === "QUOTATION_DELIVERY_FAILED"
        ? "De offerte is uitgegeven en gearchiveerd, maar de aflevering vereist manuele controle."
        : "De offerte kon niet veilig worden uitgegeven. Probeer later opnieuw.";
    } finally {
      quotationActionBusy = false;
      if (selectionRequestId === detailRequestId) quotationActionButton.disabled = false;
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

  dossierPurge.addEventListener("click", ()=>{
    if (dossierPurgeBusy || dossierPurge.hidden || !selectedDetail) return;
    pendingDossierPurge = {
      detail: selectedDetail,
      selectionRequestId: detailRequestId,
    };
    dossierPurgeReason.value = "";
    dossierPurgeReason.setCustomValidity("");
    dossierPurgeDialog.returnValue = "";
    dossierPurgeDialog.showModal();
    dossierPurgeReason.focus();
  });
  dossierPurgeReason.addEventListener("input", ()=>dossierPurgeReason.setCustomValidity(""));
  dossierPurgeCancel.addEventListener("click", ()=>dossierPurgeDialog.close("cancel"));
  dossierPurgeForm.addEventListener("submit", (event)=>{
    const reason = dossierPurgeReason.value.trim();
    if (reason.length >= 1 && reason.length <= 500) return;
    event.preventDefault();
    dossierPurgeReason.setCustomValidity("Vul een korte reden in.");
    dossierPurgeReason.reportValidity();
  });
  dossierPurgeDialog.addEventListener("close", async ()=>{
    const command = pendingDossierPurge;
    pendingDossierPurge = null;
    if (dossierPurgeDialog.returnValue !== "confirm" || !command || dossierPurgeBusy) return;
    if (command.selectionRequestId !== detailRequestId || selectedDetail !== command.detail) {
      dossierLifecycleMessage.textContent = "De dossierselectie is gewijzigd. Open de actie opnieuw vanuit het actuele dossier.";
      return;
    }
    let input;
    try {
      input = dossierPurgeRequest(command.detail, dossierPurgeReason.value, crypto.randomUUID());
    } catch {
      dossierLifecycleMessage.textContent = "Vul een geldige reden in en probeer opnieuw.";
      return;
    }
    dossierPurgeBusy = true;
    dossierPurge.disabled = true;
    dossierPurgeConfirm.disabled = true;
    dossierLifecycleMessage.textContent = "Dossier wordt permanent verwijderd.";
    try {
      await requireAal2();
      const { data, error } = await client.rpc("purge_dossier_v1", input);
      if (error
          || data?.quote_request_id !== command.detail.quote_request_id
          || typeof data?.replayed !== "boolean") throw new Error(error?.message || "DOSSIER_PURGE_FAILED");
      clearDetail();
      await listController.refresh();
      listMessage.textContent = "Dossier is permanent verwijderd.";
    } catch (error) {
      dossierLifecycleMessage.textContent = error instanceof Error && error.message.includes("OFFICIAL_QUOTATION_EXISTS")
        ? "Dit dossier heeft een officiële offerte en kan niet permanent worden verwijderd."
        : "Permanent verwijderen is niet uitgevoerd. Vernieuw het dossier en probeer opnieuw.";
      if (selectedDetail) await refreshDossierPurgeEligibility(selectedDetail, detailRequestId);
    } finally {
      dossierPurgeBusy = false;
      dossierPurgeConfirm.disabled = false;
      if (selectedDetail) dossierPurge.disabled = false;
    }
  });

  sdfDossierPurge.addEventListener("click", ()=>{
    if (sdfDossierPurgeBusy || sdfDossierPurge.hidden || !selectedDetail) return;
    pendingSdfDossierPurge = {
      detail: selectedDetail,
      selectionRequestId: detailRequestId,
    };
    sdfDossierPurgeReason.value = "";
    sdfDossierPurgeReason.setCustomValidity("");
    sdfDossierPurgeDialog.returnValue = "";
    sdfDossierPurgeDialog.showModal();
    sdfDossierPurgeReason.focus();
  });
  sdfDossierPurgeReason.addEventListener("input", ()=>sdfDossierPurgeReason.setCustomValidity(""));
  sdfDossierPurgeCancel.addEventListener("click", ()=>sdfDossierPurgeDialog.close("cancel"));
  sdfDossierPurgeForm.addEventListener("submit", (event)=>{
    const reason = sdfDossierPurgeReason.value.trim();
    if (reason.length >= 1 && reason.length <= 500) return;
    event.preventDefault();
    sdfDossierPurgeReason.setCustomValidity("Vul een korte reden in.");
    sdfDossierPurgeReason.reportValidity();
  });
  sdfDossierPurgeDialog.addEventListener("close", async ()=>{
    const command = pendingSdfDossierPurge;
    pendingSdfDossierPurge = null;
    if (sdfDossierPurgeDialog.returnValue !== "confirm" || !command || sdfDossierPurgeBusy) return;
    if (command.selectionRequestId !== detailRequestId || selectedDetail !== command.detail) {
      sdfDossierPurgeMessage.textContent = "De dossierselectie is gewijzigd. Open de actie opnieuw vanuit het actuele dossier.";
      return;
    }
    let input;
    try {
      input = sdfDossierPurgeRequest(command.detail, sdfDossierPurgeReason.value, crypto.randomUUID());
    } catch {
      sdfDossierPurgeMessage.textContent = "Vul een geldige reden in en probeer opnieuw.";
      return;
    }
    sdfDossierPurgeBusy = true;
    sdfDossierPurge.disabled = true;
    sdfDossierPurgeConfirm.disabled = true;
    sdfDossierPurgeMessage.textContent = "Dossier wordt definitief verwijderd.";
    try {
      await requireAal2();
      const { data, error } = await client.rpc("purge_sdf_dossier_v1", input);
      if (error
          || data?.quote_request_id !== command.detail.quote_request_id
          || data?.deleted !== true
          || typeof data?.replayed !== "boolean") throw new Error(error?.message || "SDF_DOSSIER_PURGE_FAILED");
      clearDetail();
      await listController.refresh();
      listMessage.textContent = "SDF-dossier is definitief verwijderd.";
    } catch {
      sdfDossierPurgeMessage.textContent = "Definitief verwijderen is niet uitgevoerd. De actuele dossierstatus wordt opnieuw geladen.";
      if (selectedDetail) await refreshSdfDossierPurgeEligibility(selectedDetail, detailRequestId);
    } finally {
      sdfDossierPurgeBusy = false;
      sdfDossierPurgeConfirm.disabled = false;
      if (selectedDetail) sdfDossierPurge.disabled = false;
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
        source: "dossier",
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
  const dashboardRefreshController = createVisibilityRefreshController({
    refresh: ()=>refreshDashboard({ background: true }),
  });
  document.addEventListener("visibilitychange", dashboardRefreshController.visibilityChanged);
  window.addEventListener("pagehide", dashboardRefreshController.stop, { once: true });
  dashboardRefreshController.start();
  return currentIdentity;
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
    refresh: ()=>loadPage(),
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
const SDF_DOCUMENT_REQUEST_STATUSES = new Set(["NEW", "TRIAGED", "IN_PROGRESS", "WAITING_CUSTOMER", "RESOLVED"]);

export function sdfDocumentCustomerRequest(application, idempotencyKey) {
  const quoteRequestId = String(application?.quote_request_id || "");
  if (application?.request_kind !== "slimme_documentenflow"
    || !UUID.test(quoteRequestId) || !UUID.test(String(idempotencyKey || ""))) {
    throw new Error("INVALID_SDF_DOCUMENT_REQUEST");
  }
  return {
    action: "create_sdf_customer_request",
    quote_request_id: quoteRequestId,
    idempotency_key: idempotencyKey,
    request_type: "FILE_DELIVERY",
    title: "Documenten aanleveren",
    description: "Lever de documenten voor dit Slimme Documentenflow-dossier veilig aan.",
    priority: "NORMAL",
  };
}

export async function sdfDocumentIdempotencyKey(quoteRequestId) {
  if (!UUID.test(String(quoteRequestId || ""))) throw new Error("INVALID_SDF_DOCUMENT_REQUEST");
  const digest = new Uint8Array(await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`SDF_DOCUMENT_REQUEST_V1:${quoteRequestId}`),
  ));
  digest[6] = (digest[6] & 0x0f) | 0x50;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = [...digest.slice(0, 16)].map((value)=>value.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function reusableSdfDocumentRequest(items) {
  const requests = appendUniqueCustomerRequestItems([], items);
  return requests.find((request)=>request.request_type === "FILE_DELIVERY"
    && SDF_DOCUMENT_REQUEST_STATUSES.has(request.status)) || null;
}

export function createSdfDocumentWorkspaceController(
  invoke,
  onChange = ()=>{},
  createRequestKey = sdfDocumentIdempotencyKey,
  createUploadKey = ()=>crypto.randomUUID(),
) {
  const state = { application: null, request: null, upload_url: null, loading: false, error: null };
  let generation = 0;
  let operation = null;
  const publish = ()=>onChange({ ...state, application: state.application ? { ...state.application } : null, request: state.request ? { ...state.request } : null });
  const detailController = createCustomerRequestDetailController(invoke, (detailState)=>{
    state.request = detailState.request;
    state.upload_url = detailState.upload_url;
    if (detailState.error) state.error = detailState.error;
    publish();
  }, createUploadKey);

  function selectApplication(application) {
    generation += 1;
    operation = null;
    state.application = application?.request_kind === "slimme_documentenflow" ? application : null;
    state.request = null;
    state.upload_url = null;
    state.loading = false;
    state.error = null;
    detailController.clear();
    publish();
  }

  async function startUpload() {
    if (!state.application) return false;
    if (operation) return operation;
    const application = state.application;
    const expectedGeneration = generation;
    operation = (async ()=>{
      state.loading = true;
      state.error = null;
      publish();
      try {
        const dossierReference = dossierReferenceFromDetail(application);
        if (!dossierReference) throw new Error("SDF_DOSSIER_REFERENCE_REQUIRED");
        let cursor = null;
        let request = null;
        do {
          const page = await invoke(customerRequestsForDossierRequest(dossierReference, cursor));
          if (expectedGeneration !== generation) return false;
          if (!page || !Array.isArray(page.items) || typeof page.has_more !== "boolean"
            || (page.next_cursor !== null && typeof page.next_cursor !== "string")
            || (page.has_more && !page.next_cursor)) throw new Error("INVALID_CUSTOMER_REQUEST_LIST");
          request = reusableSdfDocumentRequest(page.items);
          cursor = page.has_more && !request ? page.next_cursor : null;
        } while (cursor);
        let requestId = request?.request_id || null;
        if (!requestId) {
          const created = await invoke(sdfDocumentCustomerRequest(
            application,
            await createRequestKey(application.quote_request_id),
          ));
          if (!created || !UUID.test(String(created.request_id || ""))) throw new Error("INVALID_SDF_DOCUMENT_REQUEST");
          requestId = created.request_id;
        }
        if (expectedGeneration !== generation || !await detailController.selectRequest(requestId)) return false;
        if (detailController.state.request?.upload_request) return true;
        return await detailController.createUploadLink();
      } catch (error) {
        if (expectedGeneration === generation) state.error = error instanceof Error ? error.message : "OPERATOR_REQUEST_FAILED";
        return false;
      } finally {
        if (expectedGeneration === generation) {
          state.loading = false;
          operation = null;
          publish();
        }
      }
    })();
    return operation;
  }

  async function revokeUploadLink() {
    if (state.loading || operation || !state.request?.upload_request) return false;
    state.loading = true;
    state.error = null;
    publish();
    const revoked = await detailController.revokeUploadLink();
    state.loading = false;
    publish();
    return revoked;
  }

  publish();
  return { state, selectApplication, startUpload, revokeUploadLink };
}

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

export function createVisibilityRefreshController({
  refresh,
  isVisible = ()=>document.visibilityState === "visible",
  setTimer = (callback, delay)=>window.setInterval(callback, delay),
  clearTimer = (timer)=>window.clearInterval(timer),
  cadenceMs = 25_000,
}) {
  let timer = null;
  let refreshing = false;

  async function run() {
    if (!isVisible() || refreshing) return false;
    refreshing = true;
    try {
      await refresh();
      return true;
    } catch {
      return false;
    } finally {
      refreshing = false;
    }
  }

  function start() {
    if (timer !== null || !isVisible()) return;
    timer = setTimer(()=>void run(), cadenceMs);
  }

  function stop() {
    if (timer === null) return;
    clearTimer(timer);
    timer = null;
  }

  function visibilityChanged() {
    if (!isVisible()) return stop();
    void run();
    start();
  }

  return { run, start, stop, visibilityChanged };
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
    refresh: ()=>loadPage(),
    loadMore: ()=>loadPage({ append: true }),
    updateQuery,
  };
}
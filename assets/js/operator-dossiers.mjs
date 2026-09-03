import { buildSdfQualificationPresentation } from "./sdf-qualification-review.mjs";
import { createOperatorAutoRefresh } from "./operator-auto-refresh.mjs?v=20260903-auto-refresh-8s";

const DOSSIER_ROLES = new Set(["owner", "admin", "operations_manager", "operator", "reviewer", "read_only"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;
const SUPPORT_REFERENCE = /^#[0-9A-F]{8}$/;
const AUTHORIZATION_FAILURES = new Set([
  "AUTHENTICATION_REQUIRED", "INVALID_JWT", "HUMAN_JWT_REQUIRED", "UNKNOWN_OPERATOR",
  "OPERATOR_DISABLED", "OPERATOR_REVOKED", "OPERATOR_INACTIVE", "OPERATOR_NOT_ACTIVE",
  "OPERATOR_NOT_AUTHORIZED", "INSUFFICIENT_PERMISSIONS", "APPLICATION_SCOPE_DENIED",
  "DOSSIER_ASSIGNMENT_READER_REQUIRED", "DOSSIER_ASSIGNMENT_ACTOR_REQUIRED",
]);
const DOSSIER_GATEWAY_ACTIONS = new Set([
  "list_applications_v2", "list_pending_intakes", "count_pending_intakes", "get_application_facets_v2", "get_application_detail", "get_dossier_substance",
  "get_project_dossier", "get_my_assigned_dossiers", "get_dossier_document_manifest",
  "create_dossier_document_access", "list_customer_requests_for_dossier", "get_customer_request",
  "transition_customer_request", "create_customer_request_upload_link",
  "revoke_customer_request_upload_link", "create_sdf_customer_request",
  "get_dossier_assignment", "get_assignment_operator_roster", "assign_dossier",
  "archive_dossier", "reactivate_dossier", "trash_dossier", "restore_dossier",
  "archive_pending_intake", "restore_pending_intake",
  "promote_accepted_application", "issue_and_deliver_approved_quotation",
]);
const DOSSIER_RPC_ACTIONS = new Set(["can_purge_dossier_v1", "purge_dossier_v1", "can_purge_sdf_dossier_v1", "purge_sdf_dossier_v1"]);
const CUSTOMER_REQUEST_DETAIL_FIELDS = new Set([
  "request_id", "request_reference", "source", "request_type", "title", "description",
  "status", "priority", "submitted_at", "revision", "updated_at", "upload_request",
]);

export function formatOperatorDate(value) {
  if (value == null || value === "") return "Niet beschikbaar";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Niet beschikbaar";
  return new Intl.DateTimeFormat("nl-BE", {
    day: "2-digit", month: "2-digit", year: "numeric",
    hour: "2-digit", minute: "2-digit", hour12: false,
    timeZone: "Europe/Brussels",
  }).format(date).replace(",", " –");
}

function errorCode(error, fallback = "OPERATOR_REQUEST_FAILED") {
  return String(error?.context?.code || error?.code || error?.message || fallback);
}

function assertCurrent(disposed, signal) {
  if (disposed() || signal?.aborted) throw new Error("DOSSIER_DISPOSED");
}

export function dossierReference(value) {
  const applicationReference = String(value?.application_reference || value?.reference || "").trim().toUpperCase();
  if (APPLICATION_REFERENCE.test(applicationReference)) return applicationReference;
  const supportReference = String(value?.support_reference || value?.reference || "").trim().toUpperCase();
  const normalized = supportReference.startsWith("#") ? supportReference : `#${supportReference}`;
  return SUPPORT_REFERENCE.test(normalized) ? normalized : null;
}

export function dossierLocator(value) {
  const reference = dossierReference(value);
  if (reference?.startsWith("LWS-AAN-")) return { application_reference: reference };
  if (reference?.startsWith("#")) return { support_reference: reference };
  const quoteRequestId = String(value?.quote_request_id || "");
  if (UUID.test(quoteRequestId)) return { quote_request_id: quoteRequestId };
  throw new Error("INVALID_DOSSIER_LOCATOR");
}

export function dossierSubstanceRequest(value) {
  const quoteRequestId = String(value?.quote_request_id || value?.raw?.quote_request_id || "");
  if (!UUID.test(quoteRequestId)) throw new Error("INVALID_DOSSIER_SUBSTANCE_REQUEST");
  return { action: "get_dossier_substance", quote_request_id: quoteRequestId };
}

export function dossierListRequest(query = {}, cursor = null) {
  const zone = ["PENDING", "ACTIVE", "ARCHIVED", "TRASHED"].includes(query.zone) ? query.zone : "PENDING";
  if (zone === "PENDING") return {
    action: "list_pending_intakes",
    retention_state: query.retention_state === "ARCHIVED" ? "ARCHIVED" : "ACTIVE",
  };
  const request = {
    action: "list_applications_v2",
    zone: zone === "ACTIVE" && String(query.search || "").trim() ? "ACTIVE_ARCHIVED" : zone,
    operational_status: query.operational_status || null,
    year: null,
    quarter: null,
    request_kind: ["website", "slimme_documentenflow"].includes(query.request_kind) ? query.request_kind : null,
    search: String(query.search || "").trim() || null,
    cursor,
    limit: 50,
  };
  if (request.search?.length > 140) throw new Error("INVALID_DOSSIER_SEARCH");
  return request;
}

export function validateDossierCounters(pending, active, archived, trashed) {
  if (!Number.isSafeInteger(pending?.active_count) || pending.active_count < 0) throw new Error("INVALID_DOSSIER_COUNTERS");
  const countFacet = (facet)=>{
    if (!facet || !Array.isArray(facet.years)) throw new Error("INVALID_DOSSIER_COUNTERS");
    return facet.years.reduce((total, year)=>{
      if (!Number.isSafeInteger(year?.count) || year.count < 0) throw new Error("INVALID_DOSSIER_COUNTERS");
      return total + year.count;
    }, 0);
  };
  return {
    PENDING: pending.active_count,
    ACTIVE: countFacet(active),
    ARCHIVED: countFacet(archived),
    TRASHED: countFacet(trashed),
  };
}

export function pendingIntakeRetentionRequest(action, item, reason, idempotencyKey) {
  const expectedState = action === "archive_pending_intake" ? "ACTIVE"
    : action === "restore_pending_intake" ? "ARCHIVED" : null;
  const normalizedReason = String(reason || "").trim();
  if (!expectedState || item?.retention_state !== expectedState || !UUID.test(String(item?.intake_id || ""))
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

export function pendingDossierTrashRequest(item, reason, idempotencyKey) {
  const normalizedReason = String(reason || "").trim();
  if (item?.dossier_state !== "ACTIVE" || !Number.isSafeInteger(item?.dossier_revision) || item.dossier_revision < 0
    || !UUID.test(String(item?.quote_request_id || "")) || !UUID.test(String(idempotencyKey || ""))
    || normalizedReason.length < 1 || normalizedReason.length > 500) {
    throw new Error("INVALID_PENDING_DOSSIER_TRASH_COMMAND");
  }
  return {
    action: "trash_dossier",
    quote_request_id: item.quote_request_id,
    expected_revision: item.dossier_revision,
    idempotency_key: idempotencyKey,
    reason: normalizedReason,
  };
}

function purgeBlockMessage(reason) {
  return {
    COMMERCIAL_FOLLOW_UP_EXISTS: "Definitief verwijderen is niet mogelijk omdat commerciële opvolging bestaat.",
    QUOTATION_EXISTS: "Definitief verwijderen is niet mogelijk omdat reeds een offerte aan dit dossier gekoppeld is.",
    OFFICIAL_QUOTATION_EXISTS: "Definitief verwijderen is niet mogelijk omdat reeds een officiële offerte aan dit dossier gekoppeld is.",
    PROJECT_EXISTS: "Definitief verwijderen is niet mogelijk omdat een project aan dit dossier gekoppeld is.",
    INVOICE_EXISTS: "Definitief verwijderen is niet mogelijk omdat een factuurafhankelijkheid bestaat.",
    CUSTOMER_REQUEST_EXISTS: "Definitief verwijderen is niet mogelijk omdat klantverzoeken aan dit dossier gekoppeld zijn.",
    FINANCIAL_DEPENDENCY_EXISTS: "Definitief verwijderen is niet mogelijk omdat een financiële afhankelijkheid bestaat.",
  }[reason] || "Definitief verwijderen is niet toegestaan omdat een beschermde afhankelijkheid bestaat.";
}

export function dossierAssignmentRequest(detail, assignment, assigneeOperatorId, reason, idempotencyKey) {
  const reference = dossierReference(detail);
  const normalizedReason = String(reason || "").trim();
  const currentAssignee = assignment?.assignee_operator_id ?? null;
  const reassignment = currentAssignee !== null && currentAssignee !== assigneeOperatorId;
  if (!reference || !UUID.test(String(assigneeOperatorId || "")) || !UUID.test(String(idempotencyKey || ""))
    || !Number.isSafeInteger(assignment?.revision) || assignment.revision < 0
    || currentAssignee === assigneeOperatorId || normalizedReason.length > 500
    || (reassignment && normalizedReason.length < 1)) throw new Error("INVALID_ASSIGNMENT_COMMAND");
  return {
    action: "assign_dossier",
    dossier_reference: reference,
    assignee_operator_id: assigneeOperatorId,
    expected_revision: assignment.revision,
    idempotency_key: idempotencyKey,
    ...(normalizedReason ? { reason: normalizedReason } : {}),
  };
}

export function dossierLifecycleRequest(action, detail, reason, idempotencyKey) {
  const lifecycle = detail?.dossier_lifecycle;
  const allowed = {
    ACTIVE: ["archive_dossier", "trash_dossier"],
    ARCHIVED: ["reactivate_dossier", "trash_dossier"],
    TRASHED: ["restore_dossier"],
  }[lifecycle?.state] || [];
  const normalizedReason = String(reason || "").trim();
  if (!allowed.includes(action) || !UUID.test(String(detail?.quote_request_id || ""))
    || !Number.isSafeInteger(lifecycle?.revision) || lifecycle.revision < 0
    || !UUID.test(String(idempotencyKey || "")) || normalizedReason.length < 1 || normalizedReason.length > 500) {
    throw new Error("INVALID_DOSSIER_LIFECYCLE_COMMAND");
  }
  return {
    action,
    quote_request_id: detail.quote_request_id,
    expected_revision: lifecycle.revision,
    idempotency_key: idempotencyKey,
    reason: normalizedReason,
  };
}

export function dossierDocumentRequest(detail, item = null) {
  const quoteRequestId = String(detail?.quote_request_id || "");
  if (!UUID.test(quoteRequestId)) throw new Error("INVALID_DOSSIER_DOCUMENT_REQUEST");
  if (!item) return { action: "get_dossier_document_manifest", quote_request_id: quoteRequestId };
  if (item.quote_request_id !== quoteRequestId || !UUID.test(String(item.document_id || ""))
    || !["QUOTATION_ARTIFACT", "CUSTOMER_UPLOAD"].includes(item.source_type)
    || item.can_open !== true || item.can_download !== true) throw new Error("INVALID_DOSSIER_DOCUMENT_ACCESS_REQUEST");
  return {
    action: "create_dossier_document_access",
    quote_request_id: quoteRequestId,
    source_type: item.source_type,
    document_id: item.document_id,
  };
}

export function dossierPurgeEligibilityRequest(detail) {
  if (!UUID.test(String(detail?.quote_request_id || ""))
    || !["website", "slimme_documentenflow"].includes(detail?.request_kind)
    || detail?.dossier_lifecycle?.state !== "TRASHED") throw new Error("INVALID_DOSSIER_PURGE_ELIGIBILITY");
  const sdf = detail.request_kind === "slimme_documentenflow";
  return {
    name: sdf ? "can_purge_sdf_dossier_v1" : "can_purge_dossier_v1",
    parameters: { p_quote_request_id: detail.quote_request_id },
  };
}

export function dossierPurgeRequest(detail, reason, idempotencyKey) {
  try {
    dossierPurgeEligibilityRequest(detail);
  } catch {
    throw new Error("INVALID_DOSSIER_PURGE_COMMAND");
  }
  const normalizedReason = String(reason || "").trim();
  if (!UUID.test(String(idempotencyKey || "")) || normalizedReason.length < 1 || normalizedReason.length > 500) {
    throw new Error("INVALID_DOSSIER_PURGE_COMMAND");
  }
  const sdf = detail.request_kind === "slimme_documentenflow";
  return {
    name: sdf ? "purge_sdf_dossier_v1" : "purge_dossier_v1",
    parameters: {
      p_quote_request_id: detail.quote_request_id,
      p_reason: normalizedReason,
      p_idempotency_key: idempotencyKey,
    },
  };
}

export function customerRequestCommand(status) {
  if (status === "TRIAGED") return "START";
  if (status === "IN_PROGRESS") return "REQUIRE_CUSTOMER_RESPONSE";
  if (status === "WAITING_CUSTOMER") return "RESUME";
  return null;
}

export function customerRequestTransitionRequest(request, commandType, idempotencyKey) {
  if (!UUID.test(String(request?.request_id || "")) || !Number.isSafeInteger(request?.revision) || request.revision < 0
    || customerRequestCommand(request.status) !== commandType || !UUID.test(String(idempotencyKey || ""))) {
    throw new Error("INVALID_CUSTOMER_REQUEST_TRANSITION");
  }
  return { action: "transition_customer_request", request_id: request.request_id, command_type: commandType, expected_revision: request.revision, idempotency_key: idempotencyKey };
}

export function customerRequestUploadRequest(request, idempotencyKey, revoke = false) {
  if (!UUID.test(String(idempotencyKey || ""))) throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_COMMAND");
  if (!revoke && UUID.test(String(request?.request_id || "")) && !request.upload_request) {
    return { action: "create_customer_request_upload_link", request_id: request.request_id, idempotency_key: idempotencyKey };
  }
  const uploadRequestId = request?.upload_request?.upload_request_id;
  if (revoke && UUID.test(String(uploadRequestId || ""))) {
    return { action: "revoke_customer_request_upload_link", upload_request_id: uploadRequestId, reason: "Operator heeft de uploadlink ingetrokken.", idempotency_key: idempotencyKey };
  }
  throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_COMMAND");
}

export function validateCustomerRequestDetail(request) {
  const keys = request && typeof request === "object" ? Object.keys(request) : [];
  const upload = request?.upload_request;
  const validUpload = upload === null || (upload && Object.keys(upload).length === 3
    && ["upload_request_id", "status", "expires_at"].every((key)=>Object.hasOwn(upload, key))
    && UUID.test(String(upload.upload_request_id || "")) && upload.status === "ACTIVE" && typeof upload.expires_at === "string" && upload.expires_at);
  if (keys.length !== CUSTOMER_REQUEST_DETAIL_FIELDS.size || !keys.every((key)=>CUSTOMER_REQUEST_DETAIL_FIELDS.has(key))
    || !UUID.test(String(request?.request_id || "")) || !Number.isSafeInteger(request?.revision) || request.revision < 0
    || [request?.request_reference, request?.source, request?.request_type, request?.title, request?.description, request?.status, request?.submitted_at, request?.updated_at].some((value)=>typeof value !== "string" || !value)
    || (request.priority !== null && typeof request.priority !== "string") || !validUpload) throw new Error("INVALID_CUSTOMER_REQUEST_DETAIL");
  return request;
}

export function createOperatorDossierAuthority(client, options = {}) {
  let disposed = false;
  const abortController = new AbortController();
  const onAuthorizationFailure = options.onAuthorizationFailure || (()=>{});

  function fail(error) {
    const code = errorCode(error);
    if (AUTHORIZATION_FAILURES.has(code) || Number(error?.context?.status || error?.status) === 401) onAuthorizationFailure(code);
    throw new Error(code);
  }

  async function gateway(request) {
    assertCurrent(()=>disposed, abortController.signal);
    if (!request || !DOSSIER_GATEWAY_ACTIONS.has(request.action)) throw new Error("DOSSIER_ACTION_NOT_ALLOWED");
    try {
      const response = options.invoke
        ? await options.invoke(request, abortController.signal)
        : await client.functions.invoke("commercial-operator-command", { body: request, signal: abortController.signal });
      assertCurrent(()=>disposed, abortController.signal);
      if (response?.error) throw response.error;
      const body = response?.data;
      if (!body || body.ok !== true || !Object.hasOwn(body, "result")) throw new Error(body?.code || "INVALID_DOSSIER_RESPONSE");
      return body.result;
    } catch (error) {
      fail(error);
    }
  }

  async function rpc(name, parameters) {
    assertCurrent(()=>disposed, abortController.signal);
    if (!DOSSIER_RPC_ACTIONS.has(name)) throw new Error("DOSSIER_RPC_NOT_ALLOWED");
    try {
      const response = await client.rpc(name, parameters);
      assertCurrent(()=>disposed, abortController.signal);
      if (response?.error) throw response.error;
      if (!response || !Object.hasOwn(response, "data")) throw new Error("INVALID_DOSSIER_RESPONSE");
      return response.data;
    } catch (error) {
      fail(error);
    }
  }

  return Object.freeze({
    gateway,
    rpc,
    dispose() {
      if (disposed) return;
      disposed = true;
      abortController.abort();
    },
  });
}

export function createOperatorDossiersController({ load = async ()=>{}, onChange = ()=>{} } = {}) {
  let disposed = false;
  let generation = 0;
  const cleanups = [];

  async function refresh(options = {}) {
    if (disposed) return false;
    const requestGeneration = ++generation;
    const isCurrent = ()=>!disposed && requestGeneration === generation;
    await load(isCurrent, options);
    if (!isCurrent()) return false;
    onChange();
    return true;
  }

  return Object.freeze({
    refresh,
    listen(target, type, listener, options) {
      if (disposed) return false;
      target.addEventListener(type, listener, options);
      cleanups.push(()=>target.removeEventListener(type, listener, options));
      return true;
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      generation += 1;
      for (const cleanup of cleanups.splice(0).reverse()) cleanup();
    },
    get disposed() {
      return disposed;
    },
  });
}

function dossierWorkspaceMarkup() {
  return `
    <header class="project-heading dossiers-heading"><div><p class="eyebrow">Operator dossiers</p><h1>Dossiers</h1><p>Server-authoritatieve aanvragen, toewijzingen en documenten.</p></div><div class="dossiers-heading__actions"><button type="button" class="secondary-action" data-operator-window-module="dossiers" data-operator-window-slot="main" hidden>Open in nieuw venster</button><button type="button" class="secondary-action" data-dossiers-action="refresh">Vernieuwen</button></div></header>
    <nav class="dossiers-status-overview" aria-label="Dossierstatus"><button type="button" data-dossiers-zone="PENDING" aria-current="true"><span>Nieuwe aanvragen</span><strong data-dossiers-counter="PENDING">0</strong><small><span data-dossiers-counter="invited">0</span> uitgenodigd · <span data-dossiers-counter="in_progress">0</span> bezig</small></button><button type="button" data-dossiers-zone="ACTIVE"><span>Actieve dossiers</span><strong data-dossiers-counter="ACTIVE">—</strong><small>In behandeling en ingediend</small></button><button type="button" data-dossiers-zone="ARCHIVED"><span>Afgerond / Archief</span><strong data-dossiers-counter="ARCHIVED">—</strong><small>Afgeronde dossiers</small></button><button type="button" data-dossiers-zone="TRASHED"><span>Prullenbak</span><strong data-dossiers-counter="TRASHED">—</strong><small>Verwijderde dossiers</small></button></nav>
    <form class="application-search dossiers-filters" data-dossiers-filters role="search"><label><span>Zoeken</span><input name="search" type="search" maxlength="140" autocomplete="off" placeholder="Naam, bedrijf of referentie" /></label><label>Zone<select name="zone"><option value="PENDING">Nieuwe aanvragen</option><option value="ACTIVE">Actieve dossiers</option><option value="ARCHIVED">Afgerond / Archief</option><option value="TRASHED">Prullenbak</option></select></label><label>Product<select name="request_kind"><option value="">Alle producten</option><option value="website">Website</option><option value="slimme_documentenflow">Slimme Documentenflow</option></select></label><button type="submit" class="primary-action primary-action--compact">Zoeken</button></form>
    <div class="zone-filters pending-intake-tabs" data-dossiers-pending-retention role="group" aria-label="Intake-opvolging"><button type="button" data-dossiers-retention-state="ACTIVE" aria-pressed="true">Actief</button><button type="button" data-dossiers-retention-state="ARCHIVED" aria-pressed="false">Gearchiveerd</button></div>
    <p class="action-message action-message--dark" data-dossiers-status role="status" aria-live="polite"></p>
    <div class="dashboard-grid dossiers-grid"><section class="panel" aria-labelledby="dossiersListTitle"><div class="panel__heading"><div><p class="eyebrow">Werkvoorraad</p><h2 id="dossiersListTitle">Dossiers</h2></div><span class="badge" data-dossiers-count>0</span></div><ul class="application-list dossiers-list" data-dossiers-list></ul><p class="empty-state" data-dossiers-empty hidden>Geen dossiers gevonden.</p><button type="button" class="secondary-action" data-dossiers-action="more" hidden>Meer laden</button></section>
      <aside class="context-column" aria-label="Dossierdetail"><section class="panel" data-dossiers-detail-empty><h2>Selecteer een dossier</h2><p class="empty-state">Kies een dossier uit de werkvoorraad.</p></section>
        <article class="panel dossiers-detail" data-dossiers-detail hidden><div class="panel__heading"><div><p class="eyebrow">Dossierreferentie <strong data-dossiers-field="reference"></strong></p><h2 data-dossiers-field="name"></h2></div><span class="badge" data-dossiers-field="status"></span></div><h3 class="dossiers-substance-title">Aanvraag</h3><dl class="application-detail"><div><dt>Product</dt><dd data-dossiers-field="product"></dd></div><div><dt>Zone</dt><dd data-dossiers-field="zone"></dd></div><div><dt>Aangevraagd op</dt><dd data-dossiers-field="requested_at"></dd></div><div class="application-detail__wide dossiers-original-request"><dt>Originele klantaanvraag</dt><dd data-dossiers-field="description"></dd></div></dl></article>
        <section class="panel dossiers-customer" data-dossiers-customer hidden><div class="panel__heading"><div><p class="eyebrow">Relatie</p><h2>Klant</h2></div></div><dl class="application-detail"><div><dt>Naam</dt><dd data-dossiers-field="customer_name"></dd></div><div><dt>Bedrijf</dt><dd data-dossiers-field="company"></dd></div><div><dt>E-mail</dt><dd data-dossiers-field="email"></dd></div><div><dt>Telefoon</dt><dd data-dossiers-field="phone"></dd></div></dl></section>
        <section class="panel dossiers-intake" data-dossiers-intake hidden><div class="panel__heading"><div><p class="eyebrow">Klantinput</p><h2>Intake</h2></div><span class="badge" data-dossiers-intake-status></span></div><dl class="application-detail dossiers-intake-meta"><div><dt>Uitnodiging</dt><dd data-dossiers-field="invited_at"></dd></div><div><dt>Gestart</dt><dd data-dossiers-field="started_at"></dd></div><div><dt>Ingediend</dt><dd data-dossiers-field="submitted_at"></dd></div></dl><div class="dossiers-substance-sections" data-dossiers-intake-sections></div></section>
        <section class="panel dossiers-document-overview" data-dossiers-document-overview hidden><div class="panel__heading"><div><p class="eyebrow">Gekoppeld aan aanvraag</p><h2>Documenten</h2></div></div><dl class="application-detail"><div><dt>Klantverzoeken</dt><dd data-dossiers-field="customer_request_count"></dd></div><div><dt>Ontvangen documenten</dt><dd data-dossiers-field="uploaded_document_count"></dd></div></dl></section>
        <section class="panel dossiers-copy-actions" data-dossiers-copy-actions hidden><div class="panel__heading"><div><p class="eyebrow">Dossierdocument</p><h2>Dossierkopie</h2></div></div><div class="lifecycle-actions"><button type="button" class="primary-action primary-action--compact" data-dossiers-copy="view">Preview</button><button type="button" class="secondary-action" data-dossiers-copy="download">Download PDF</button><button type="button" class="secondary-action" data-dossiers-copy="print">Afdrukken</button></div></section>
        <section class="panel dossiers-actions" data-dossiers-lifecycle-panel hidden><div class="panel__heading"><div><p class="eyebrow">Dossierbeheer</p><h2>Dossieracties</h2></div><span class="badge" data-dossiers-lifecycle-state></span></div><div class="dossiers-actions__group"><h3>Acties</h3><div class="lifecycle-actions"><button type="button" class="secondary-action" data-dossiers-lifecycle="archive_dossier">Archiveren</button><button type="button" class="secondary-action" data-dossiers-lifecycle="reactivate_dossier">Terug activeren</button><button type="button" class="secondary-action" data-dossiers-lifecycle="restore_dossier">Herstellen uit prullenbak</button></div></div><div class="dossiers-actions__group dossiers-actions__group--danger"><h3>Verwijderen</h3><div class="lifecycle-actions"><button type="button" class="danger-action" data-dossiers-lifecycle="trash_dossier">Naar prullenbak</button><button type="button" class="danger-action" data-dossiers-purge hidden>Definitief verwijderen</button></div><p class="action-message" data-dossiers-purge-message></p></div></section>
        <section class="panel dossiers-actions" data-dossiers-pending-actions hidden><div class="panel__heading"><div><p class="eyebrow">Werkruimte</p><h2>Dossieracties</h2></div><span class="badge" data-dossiers-pending-retention-state></span></div><div class="dossiers-actions__group"><h3>Acties</h3><div class="lifecycle-actions"><button type="button" class="secondary-action" data-dossiers-pending-retention-action></button></div><p>Archiveren verwijdert deze intake alleen uit de actieve opvolging.</p></div><div class="dossiers-actions__group dossiers-actions__group--danger"><h3>Verwijderen</h3><div class="lifecycle-actions"><button type="button" class="danger-action" data-dossiers-pending-trash>Naar prullenbak</button></div><p class="action-message">Permanent verwijderen kan uitsluitend vanuit de prullenbak.</p></div></section>
        <section class="panel dossiers-assignment" data-dossiers-assignment hidden><div class="panel__heading"><div><p class="eyebrow">Toewijzing</p><h2>Operator</h2></div><strong data-dossiers-assignee></strong></div><form class="assignment-form" data-dossiers-assignment-form><label>Toewijzen aan<select name="assignee_operator_id" required><option value="">Kies een operator</option></select></label><label>Reden bij hertoewijzing<textarea name="reason" rows="3" maxlength="500"></textarea></label><button type="submit" class="primary-action primary-action--compact">Opslaan</button></form></section>
        <section class="panel" data-dossiers-documents hidden><div class="panel__heading"><div><p class="eyebrow">Documenten</p><h2>Dossierdocumenten</h2></div></div><ul class="document-list" data-dossiers-document-list></ul><p class="empty-state" data-dossiers-document-empty></p></section>
        <section class="panel" data-dossiers-requests hidden><div class="panel__heading"><div><p class="eyebrow">Klantverzoeken</p><h2>Requests</h2></div></div><ul class="customer-request-list" data-dossiers-request-list></ul><p class="empty-state" data-dossiers-request-empty></p><article data-dossiers-request-detail hidden><hr /><p class="eyebrow" data-dossiers-request-reference></p><h3 data-dossiers-request-title></h3><p data-dossiers-request-description></p><dl class="application-detail"><div><dt>Status</dt><dd data-dossiers-request-status></dd></div><div><dt>Prioriteit</dt><dd data-dossiers-request-priority></dd></div></dl><div class="lifecycle-actions"><button type="button" class="primary-action primary-action--compact" data-dossiers-request-transition hidden></button><button type="button" class="secondary-action" data-dossiers-upload-create>Uploadlink maken</button><button type="button" class="secondary-action" data-dossiers-upload-copy hidden>Uploadlink kopiëren</button><button type="button" class="danger-action" data-dossiers-upload-revoke hidden>Uploadlink intrekken</button></div><input type="url" readonly data-dossiers-upload-url hidden aria-label="Veilige uploadlink" /><p class="action-message" data-dossiers-request-message></p></article></section>
      </aside></div>
    <dialog class="operator-modal--reading dossier-preview-dialog" data-dossiers-copy-dialog aria-labelledby="dossiersCopyTitle"><div class="dossier-preview-dialog__shell"><header class="dossier-preview-dialog__header"><div><p class="eyebrow">Documentpreview</p><h2 id="dossiersCopyTitle">Historische dossierkopie</h2><p class="empty-state" data-dossiers-copy-reference></p></div><div class="dossier-preview-dialog__actions"><button type="button" class="primary-action primary-action--compact" data-dossiers-copy="download">Download PDF</button><button type="button" class="secondary-action" data-dossiers-copy="print">Afdrukken</button><button type="button" class="secondary-action" data-dossiers-copy-close>Sluiten</button></div></header><div class="dossier-preview-dialog__body"><div class="application-dossier-copy" data-dossiers-copy-content></div></div></div></dialog>
    <dialog class="operator-dialog" data-dossiers-command-dialog aria-labelledby="dossiersCommandTitle"><form data-dossiers-command-form><p class="eyebrow">Bevestiging vereist</p><h2 id="dossiersCommandTitle" data-dossiers-command-title>Dossieractie</h2><p data-dossiers-command-message></p><label>Reden<textarea name="reason" rows="4" minlength="1" maxlength="500" required></textarea></label><div class="dialog-actions"><button type="button" class="secondary-action" data-dossiers-command-cancel>Annuleren</button><button type="submit" class="danger-action">Bevestigen</button></div></form></dialog>`;
}

function setText(workspace, field, value) {
  const node = workspace.querySelector(`[data-dossiers-field="${field}"]`);
  if (node) node.textContent = value == null || value === "" ? "Niet beschikbaar" : String(value);
}

function resetDossierCopyPreview(workspace) {
  const dialog = workspace.querySelector("[data-dossiers-copy-dialog]");
  if (dialog.open) dialog.close();
  workspace.querySelector("[data-dossiers-copy-reference]").textContent = "";
  workspace.querySelector("[data-dossiers-copy-content]").replaceChildren();
}

function clearDetailSelection(workspace) {
  resetDossierCopyPreview(workspace);
  workspace.querySelector("[data-dossiers-detail-empty]").hidden = false;
  for (const panel of workspace.querySelectorAll(".context-column > [data-dossiers-detail], .context-column > [data-dossiers-customer], .context-column > [data-dossiers-intake], .context-column > [data-dossiers-document-overview], .context-column > [data-dossiers-copy-actions], .context-column > [data-dossiers-assignment], .context-column > [data-dossiers-documents], .context-column > [data-dossiers-requests], .context-column > [data-dossiers-lifecycle-panel], .context-column > [data-dossiers-pending-actions]")) {
    panel.hidden = true;
  }
}

function applicationSummary(item) {
  if (!item || typeof item !== "object") throw new Error("INVALID_DOSSIER_LIST_RESPONSE");
  const locator = dossierLocator(item);
  const reference = dossierReference(item) || Object.values(locator)[0];
  return { raw: item, locator, reference, name: String(item.organization || item.name || reference), status: String(item.operational_status || item.status || "ONBEKEND"), zone: String(item.zone || "ACTIVE") };
}

function pendingSummary(item) {
  if (!item || typeof item !== "object" || !UUID.test(String(item.quote_request_id || ""))
    || !UUID.test(String(item.intake_id || "")) || typeof item.name !== "string" || !item.name
    || typeof item.support_reference !== "string" || !SUPPORT_REFERENCE.test(item.support_reference)
    || !["website", "slimme_documentenflow"].includes(item.request_kind)
    || !["invited", "in_progress"].includes(item.intake_status) || !["ACTIVE", "ARCHIVED"].includes(item.retention_state)
    || item.dossier_state !== "ACTIVE" || !Number.isSafeInteger(item.dossier_revision) || item.dossier_revision < 0) {
    throw new Error("INVALID_PENDING_DOSSIER_LIST_RESPONSE");
  }
  return {
    raw: item,
    kind: "pending",
    locator: { quote_request_id: item.quote_request_id },
    reference: item.support_reference,
    name: String(item.organization || item.name),
    status: item.intake_status,
    zone: "PENDING",
  };
}

export function validateDossierListPage(page, action = "list_applications_v2") {
  if (action === "list_pending_intakes") {
    if (!page || !Array.isArray(page.items) || Object.keys(page).length !== 1) throw new Error("INVALID_PENDING_DOSSIER_LIST_RESPONSE");
    return { items: page.items.map(pendingSummary), hasMore: false, nextCursor: null };
  }
  if (!page || !Array.isArray(page.items) || typeof page.has_more !== "boolean"
    || (page.next_cursor !== null && typeof page.next_cursor !== "string") || (page.has_more && !page.next_cursor)) throw new Error("INVALID_DOSSIER_LIST_RESPONSE");
  return { items: page.items.map(applicationSummary), hasMore: page.has_more, nextCursor: page.next_cursor };
}

export function visibleDossierSelection(selected, items) {
  if (!selected || !Array.isArray(items)) return null;
  return items.find((item)=>item.reference === selected.reference) || null;
}

export function dossierCopyAvailable(detail) {
  return Boolean(detail?.request_kind === "website" && detail.application);
}

function detailIdentity(detail) {
  if (!detail || !UUID.test(String(detail.quote_request_id || "")) || !["website", "slimme_documentenflow"].includes(detail.request_kind)
    || typeof detail.name !== "string" || !detail.name) throw new Error("INVALID_DOSSIER_DETAIL_RESPONSE");
  return detail;
}

function customerValue(detail, key) {
  return detail?.customer?.[key] ?? detail?.application?.customer?.[key] ?? detail?.[key] ?? null;
}

const WEBSITE_INTAKE_SECTIONS = [
  ["Bedrijf & doelgroep", [["business_description", "Bedrijfsomschrijving"], ["target_audience", "Doelgroep"], ["has_existing_website", "Bestaande website"], ["existing_website_url", "Website URL"], ["elements_to_keep", "Te behouden"], ["improvement_areas", "Verbeterpunten"]]],
  ["Doelen", [["website_goals", "Websitedoelen"], ["primary_conversion_goal", "Belangrijkste conversieactie"]]],
  ["Pagina's & functies", [["requested_pages", "Gewenste pagina's"], ["other_pages", "Andere pagina's"], ["requested_features", "Functies"], ["shop_required", "Webshop"], ["booking_required", "Reservaties of afspraken"], ["languages", "Talen"], ["primary_language", "Primaire taal"], ["additional_languages", "Extra talen"]]],
  ["Design & branding", [["design_styles", "Stijlen"], ["brand_status", "Huisstijlstatus"], ["logo_status", "Logostatus"], ["brand_colors", "Kleuren"], ["inspiration_sites", "Inspiratie"], ["disliked_styles", "Wat niet aanspreekt"]]],
  ["Content & media", [["content_status", "Tekststatus"], ["image_status", "Beeldstatus"], ["image_support", "Gewenste beeldondersteuning"]]],
  ["Domein & hosting", [["domain_status", "Domeinstatus"], ["domain_name", "Domeinnaam"], ["hosting_status", "Hostingstatus"], ["hosting_support", "Gewenste hostinghulp"], ["maintenance_interest", "Onderhoud"]]],
  ["SEO & integraties", [["seo_priority", "SEO-prioriteit"], ["seo_keywords", "Zoekwoorden"], ["social_channels", "Sociale kanalen"], ["integrations", "Integraties"]]],
  ["Planning & budget", [["deadline_date", "Deadline"], ["deadline_reason", "Reden deadline"], ["budget_confirmed", "Budget bevestigd"], ["budget_update_category", "Bijgewerkte budgetcategorie"], ["budget_notes", "Budgetnotities"]]],
  ["Prioriteiten & opmerkingen", [["priorities", "Prioriteiten"], ["additional_notes", "Aanvullende opmerkingen"], ["confirmation", "Bevestigd door klant"]]],
];
const WEBSITE_OBJECT_SECTIONS = [
  ["Webshopdetails", "shop_details", [["approx_product_count", "Aantal producten"], ["complex_product_count", "Complexe producten of varianten"], ["payment_provider_count", "Aantal betaalproviders"], ["categories", "Categorieën"], ["online_payments", "Online betalingen"], ["shipping_scope", "Verzending"], ["pickup_scope", "Afhalen"], ["existing_catalog", "Bestaande catalogus"], ["customer_accounts", "Klantaccounts"], ["catalog_import", "Catalogus importeren"], ["erp_api", "Voorraad-, ERP- of API-koppeling"]]],
  ["Reservatiedetails", "booking_details", [["tier", "Reservatieoplossing"], ["type", "Type reservatie"], ["existing_system", "Bestaand systeem"], ["existing_system_name", "Naam bestaand systeem"], ["calendar_integration", "Kalenderkoppeling"]]],
  ["Pagina- en zoekscope", "page_scope_details", [["portfolio", "Portfolio"], ["reviews", "Reviews"], ["blog", "Blog"], ["jobs", "Vacatures"], ["gallery", "Galerij"], ["jobs_application", "Sollicitatieflow"], ["search", "Zoekfunctie"]]],
  ["Offerteformulier", "quote_form_details", [["file_uploads", "Bestandsuploads"], ["database_workflow", "Databaseworkflow"], ["automated_processing", "Automatische verwerking"], ["review_approval", "Controle en goedkeuring"], ["custom_logic", "Maatwerklogica"], ["form_count", "Aantal formulieren"], ["structure_scope", "Structuurscope"]]],
  ["Meertaligheid", "multilingual_details", [["final_translations_supplied", "Definitieve vertalingen aangeleverd"], ["same_structure", "Dezelfde structuur"], ["translation_required", "Vertaling nodig"], ["seo_per_language", "SEO per taal"], ["advanced_seo_research", "Uitgebreid SEO-onderzoek"], ["language_specific_integrations", "Taalspecifieke integraties"], ["complex_scope", "Complexe scope"]]],
  ["Downloads", "download_details", [["access", "Toegang"]]],
  ["Nieuwsbrief & analytics", "newsletter_details", [["scope", "Nieuwsbriefscope"], ["analytics", "Analytics"], ["custom_integration", "Maatwerkintegratie"]]],
  ["Content & media scope", "content_media_details", [["copywriting_scope", "Copywritingscope"], ["copy_page_count", "Aantal tekstpagina's"], ["image_work_scope", "Beeldbewerking"], ["paid_stock_handling", "Betaalde stockbeelden"], ["branding_tier", "Brandingscope"]]],
  ["Hosting & onderhoud scope", "hosting_maintenance_details", [["hosting_support", "Hostinghulp"], ["maintenance_interest", "Onderhoudsinteresse"], ["domain_service", "Domeinservice"], ["maintenance_plan", "Onderhoudsplan"]]],
  ["Deadlinescope", "deadline_details", [["commercially_critical", "Commercieel kritisch"], ["hard_deadline", "Harde deadline"]]],
  ["SEO-scope", "seo_details", [["scope", "Scope"], ["extra_language_seo", "SEO voor extra talen"], ["advanced_language_seo", "Uitgebreide meertalige SEO"]]],
];

function substanceValue(value) {
  if (value === null || value === undefined || value === "" || (Array.isArray(value) && value.length === 0)) return null;
  if (value === true) return "Ja";
  if (value === false) return "Nee";
  if (Array.isArray(value)) return value.map((item)=>String(item)).join(", ");
  if (typeof value === "string" || typeof value === "number") return String(value);
  return null;
}

export function websiteSubstanceSections(answers) {
  if (!answers || typeof answers !== "object" || Array.isArray(answers)) throw new Error("INVALID_DOSSIER_SUBSTANCE");
  const sections = WEBSITE_INTAKE_SECTIONS.map(([title, fields])=>({
    title,
    rows: fields.map(([key, label])=>({ label, value: substanceValue(answers[key]) })).filter((row)=>row.value !== null),
  }));
  for (const [title, key, fields] of WEBSITE_OBJECT_SECTIONS) {
    const object = answers[key];
    if (!object || typeof object !== "object" || Array.isArray(object)) continue;
    sections.push({ title, rows: fields.map(([field, label])=>({ label, value: substanceValue(object[field]) })).filter((row)=>row.value !== null) });
  }
  return sections.filter((section)=>section.rows.length > 0);
}

export function validateDossierSubstance(value, expectedQuoteRequestId) {
  const keys = value && typeof value === "object" ? Object.keys(value) : [];
  if (keys.length !== 6 || !["quote_request_id", "request_kind", "request", "customer", "intake", "documents"].every((key)=>Object.hasOwn(value, key))
    || value.quote_request_id !== expectedQuoteRequestId || !["website", "slimme_documentenflow"].includes(value.request_kind)
    || typeof value.request?.reference !== "string" || typeof value.customer?.name !== "string"
    || !UUID.test(String(value.intake?.intake_id || "")) || !value.intake?.structured_answers
    || !Number.isSafeInteger(value.documents?.customer_request_count) || !Number.isSafeInteger(value.documents?.uploaded_document_count)) {
    throw new Error("INVALID_DOSSIER_SUBSTANCE");
  }
  return value;
}

function renderSubstanceSections(workspace, sections) {
  const container = workspace.querySelector("[data-dossiers-intake-sections]");
  container.replaceChildren();
  for (const section of sections) {
    const sectionNode = container.ownerDocument.createElement("section");
    const heading = container.ownerDocument.createElement("h3");
    const rows = container.ownerDocument.createElement("dl");
    heading.textContent = section.title;
    for (const row of section.rows) {
      const item = container.ownerDocument.createElement("div");
      const label = container.ownerDocument.createElement("dt");
      const value = container.ownerDocument.createElement("dd");
      label.textContent = row.label;
      value.textContent = String(row.value);
      item.append(label, value);
      rows.append(item);
    }
    sectionNode.append(heading, rows);
    container.append(sectionNode);
  }
}

function renderSubstance(workspace, substance) {
  setText(workspace, "requested_at", formatOperatorDate(substance.request.requested_at));
  setText(workspace, "description", substance.request.original_text);
  setText(workspace, "customer_name", substance.customer.name);
  setText(workspace, "company", substance.customer.company);
  setText(workspace, "email", substance.customer.email);
  setText(workspace, "phone", substance.customer.phone);
  setText(workspace, "invited_at", formatOperatorDate(substance.intake.invited_at));
  setText(workspace, "started_at", formatOperatorDate(substance.intake.started_at));
  setText(workspace, "submitted_at", formatOperatorDate(substance.intake.submitted_at));
  setText(workspace, "customer_request_count", substance.documents.customer_request_count);
  setText(workspace, "uploaded_document_count", substance.documents.uploaded_document_count);
  workspace.querySelector("[data-dossiers-intake-status]").textContent = dossierStatus(substance.intake.status).label;
  const sections = substance.request_kind === "website"
    ? websiteSubstanceSections(substance.intake.structured_answers)
    : buildSdfQualificationPresentation(substance.intake.structured_answers, {
      reference: substance.request.reference,
      preparedAt: substance.request.requested_at,
      status: substance.intake.status,
    }).sections.slice(1);
  renderSubstanceSections(workspace, sections);
  for (const selector of ["[data-dossiers-customer]", "[data-dossiers-intake]", "[data-dossiers-document-overview]"]) {
    workspace.querySelector(selector).hidden = false;
  }
}

function dossierStatus(status) {
  return {
    invited: { label: "Uitgenodigd", className: "badge--amber" },
    in_progress: { label: "Intake bezig", className: "badge--cyan" },
    SUBMITTED: { label: "Ingediend", className: "badge--cyan" },
    REVIEWED: { label: "In behandeling", className: "badge--amber" },
    QUOTE_ACCEPTED: { label: "Geactiveerd", className: "badge--green" },
  }[status] || { label: String(status || "Onbekend").replaceAll("_", " "), className: "" };
}

function authorizedDocumentUrl(value) {
  const url = new URL(String(value || ""), globalThis.location?.origin || "https://operator.invalid");
  if (url.protocol !== "https:" && url.origin !== globalThis.location?.origin) throw new Error("INVALID_DOSSIER_DOCUMENT_ACCESS");
  return url.href;
}

function authorizedCustomerUploadUrl(value) {
  const url = String(value || "");
  if (!/^https:\/\/[^#]+\/pages\/customer-request-upload\.html#token=[A-Za-z0-9_-]{43}$/.test(url)) {
    throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_LINK");
  }
  return url;
}

function renderList(workspace, items, selectedReference) {
  const list = workspace.querySelector("[data-dossiers-list]");
  list.replaceChildren();
  for (const [index, item] of items.entries()) {
    const row = list.ownerDocument.createElement("li");
    const button = list.ownerDocument.createElement("button");
    const identity = list.ownerDocument.createElement("span");
    const name = list.ownerDocument.createElement("strong");
    const reference = list.ownerDocument.createElement("small");
    const status = list.ownerDocument.createElement("span");
    button.type = "button";
    button.className = "application-list__button";
    button.dataset.dossiersSelect = String(index);
    const selected = item.reference === selectedReference;
    button.setAttribute("aria-selected", String(selected));
    if (selected) button.setAttribute("aria-current", "true");
    name.textContent = item.name;
    reference.textContent = item.reference;
    const presentedStatus = dossierStatus(item.status);
    button.dataset.dossiersStatus = item.status;
    status.className = `badge ${presentedStatus.className}`.trim();
    status.textContent = presentedStatus.label;
    identity.append(name, reference);
    button.append(identity, status);
    row.append(button);
    list.append(row);
  }
  workspace.querySelector("[data-dossiers-count]").textContent = String(items.length);
  workspace.querySelector("[data-dossiers-empty]").hidden = items.length > 0;
}

function renderStatusOverview(workspace, state) {
  for (const button of workspace.querySelectorAll("[data-dossiers-zone]")) {
    button.setAttribute("aria-current", String(button.dataset.dossiersZone === state.query.zone));
  }
  for (const zone of ["PENDING", "ACTIVE", "ARCHIVED", "TRASHED"]) {
    const zoneCounter = workspace.querySelector(`[data-dossiers-counter="${zone}"]`);
    if (zoneCounter && Number.isSafeInteger(state.counters?.[zone])) zoneCounter.textContent = String(state.counters[zone]);
  }
  if (state.query.zone === "PENDING") {
    for (const pendingStatus of ["invited", "in_progress"]) {
      workspace.querySelector(`[data-dossiers-counter="${pendingStatus}"]`).textContent = String(
        state.items.filter((item)=>item.status === pendingStatus).length,
      );
    }
  }
  const retention = workspace.querySelector("[data-dossiers-pending-retention]");
  retention.hidden = state.query.zone !== "PENDING";
  for (const button of retention.querySelectorAll("[data-dossiers-retention-state]")) {
    button.setAttribute("aria-pressed", String(button.dataset.dossiersRetentionState === state.query.retention_state));
  }
}

function renderDetail(workspace, detail, summary, substance) {
  setText(workspace, "reference", dossierReference(detail));
  setText(workspace, "name", detail.name);
  const presentedStatus = dossierStatus(detail.operational_status || summary?.status);
  setText(workspace, "status", presentedStatus.label);
  workspace.querySelector('[data-dossiers-field="status"]').className = `badge ${presentedStatus.className}`.trim();
  setText(workspace, "product", detail.request_kind === "website" ? "Website" : "Slimme Documentenflow");
  setText(workspace, "zone", detail.dossier_lifecycle?.state || summary?.zone);
  renderSubstance(workspace, substance);
  workspace.querySelector("[data-dossiers-detail-empty]").hidden = true;
  workspace.querySelector("[data-dossiers-detail]").hidden = false;
  const lifecycle = workspace.querySelector("[data-dossiers-lifecycle-panel]");
  lifecycle.hidden = !detail.dossier_lifecycle;
  workspace.querySelector("[data-dossiers-pending-actions]").hidden = true;
  workspace.querySelector("[data-dossiers-copy-actions]").hidden = !dossierCopyAvailable(detail);
  if (detail.dossier_lifecycle) {
    workspace.querySelector("[data-dossiers-lifecycle-state]").textContent = detail.dossier_lifecycle.state;
    const allowed = { ACTIVE: ["archive_dossier", "trash_dossier"], ARCHIVED: ["reactivate_dossier", "trash_dossier"], TRASHED: ["restore_dossier"] }[detail.dossier_lifecycle.state] || [];
    for (const button of lifecycle.querySelectorAll("[data-dossiers-lifecycle]")) button.hidden = !allowed.includes(button.dataset.dossiersLifecycle);
  }
}

function renderPendingDetail(workspace, summary, substance) {
  const detail = summary.raw;
  setText(workspace, "reference", detail.support_reference);
  setText(workspace, "name", detail.name);
  const presentedStatus = dossierStatus(detail.intake_status);
  setText(workspace, "status", presentedStatus.label);
  workspace.querySelector('[data-dossiers-field="status"]').className = `badge ${presentedStatus.className}`.trim();
  setText(workspace, "product", detail.request_kind === "website" ? "Website" : "Slimme Documentenflow");
  setText(workspace, "zone", "Pending / Nieuwe aanvraag");
  renderSubstance(workspace, substance);
  workspace.querySelector("[data-dossiers-detail-empty]").hidden = true;
  workspace.querySelector("[data-dossiers-detail]").hidden = false;
  for (const selector of ["[data-dossiers-copy-actions]", "[data-dossiers-lifecycle-panel]", "[data-dossiers-assignment]", "[data-dossiers-documents]", "[data-dossiers-requests]"]) {
    workspace.querySelector(selector).hidden = true;
  }
  const actions = workspace.querySelector("[data-dossiers-pending-actions]");
  const retentionAction = actions.querySelector("[data-dossiers-pending-retention-action]");
  const archived = detail.retention_state === "ARCHIVED";
  actions.hidden = false;
  actions.querySelector("[data-dossiers-pending-retention-state]").textContent = archived ? "Gearchiveerd" : "Actief";
  retentionAction.dataset.dossiersPendingRetentionAction = archived ? "restore_pending_intake" : "archive_pending_intake";
  retentionAction.textContent = archived ? "Terugzetten naar actief" : "Archiveren";
}

function renderDocuments(workspace, documents) {
  const section = workspace.querySelector("[data-dossiers-documents]");
  const list = workspace.querySelector("[data-dossiers-document-list]");
  section.hidden = false;
  list.replaceChildren();
  for (const [index, document] of documents.entries()) {
    if (!UUID.test(String(document?.document_id || "")) || typeof document?.title !== "string") throw new Error("INVALID_DOSSIER_DOCUMENT_MANIFEST");
    const row = list.ownerDocument.createElement("li");
    const name = list.ownerDocument.createElement("strong");
    name.textContent = document.filename || document.title;
    row.append(name);
    if (document.can_open === true && document.can_download === true) {
      const open = list.ownerDocument.createElement("button");
      open.type = "button";
      open.className = "secondary-action";
      open.dataset.dossiersDocument = String(index);
      open.textContent = "Openen";
      row.append(open);
    }
    list.append(row);
  }
  workspace.querySelector("[data-dossiers-document-empty]").textContent = documents.length ? "" : "Geen dossierdocumenten beschikbaar.";
}

function renderRequests(workspace, requests) {
  const section = workspace.querySelector("[data-dossiers-requests]");
  const list = workspace.querySelector("[data-dossiers-request-list]");
  section.hidden = false;
  list.replaceChildren();
  for (const [index, request] of requests.entries()) {
    if (!UUID.test(String(request?.request_id || "")) || typeof request?.title !== "string") throw new Error("INVALID_CUSTOMER_REQUEST_LIST");
    const row = list.ownerDocument.createElement("li");
    const button = list.ownerDocument.createElement("button");
    const title = list.ownerDocument.createElement("strong");
    const status = list.ownerDocument.createElement("span");
    title.textContent = request.title;
    status.className = "badge";
    status.textContent = String(request.status || "ONBEKEND").replaceAll("_", " ");
    button.type = "button";
    button.className = "application-list__button";
    button.dataset.dossiersRequest = String(index);
    button.append(title, status);
    row.append(button);
    list.append(row);
  }
  workspace.querySelector("[data-dossiers-request-empty]").textContent = requests.length ? "" : "Geen requests voor dit dossier.";
}

function renderCustomerRequestDetail(workspace, request, uploadUrl = null) {
  workspace.querySelector("[data-dossiers-request-detail]").hidden = false;
  workspace.querySelector("[data-dossiers-request-reference]").textContent = request.request_reference;
  workspace.querySelector("[data-dossiers-request-title]").textContent = request.title;
  workspace.querySelector("[data-dossiers-request-description]").textContent = request.description;
  workspace.querySelector("[data-dossiers-request-status]").textContent = request.status.replaceAll("_", " ");
  workspace.querySelector("[data-dossiers-request-priority]").textContent = request.priority || "Niet toegewezen";
  const command = customerRequestCommand(request.status);
  const transition = workspace.querySelector("[data-dossiers-request-transition]");
  transition.hidden = !command;
  transition.dataset.command = command || "";
  transition.textContent = command === "START" ? "Starten" : command === "REQUIRE_CUSTOMER_RESPONSE" ? "Klantreactie vragen" : "Hervatten";
  workspace.querySelector("[data-dossiers-upload-create]").hidden = Boolean(request.upload_request);
  workspace.querySelector("[data-dossiers-upload-revoke]").hidden = !request.upload_request;
  const copy = workspace.querySelector("[data-dossiers-upload-copy]");
  const input = workspace.querySelector("[data-dossiers-upload-url]");
  copy.hidden = !uploadUrl;
  input.hidden = !uploadUrl;
  input.value = uploadUrl || "";
}

export function initializeOperatorDossiers(root, client, identity, options = {}) {
  if (!root || !client || identity?.status !== "ACTIVE" || !DOSSIER_ROLES.has(identity?.role)) {
    throw new Error("DOSSIER_OPERATOR_NOT_AUTHORIZED");
  }
  const workspace = root.querySelector?.("[data-dossiers-workspace]");
  if (!workspace) throw new Error("DOSSIER_WORKSPACE_REQUIRED");
  if (!workspace.ownerDocument) {
    const controller = createOperatorDossiersController({ load: options.load, onChange: options.onChange });
    workspace.dataset.dossiersMounted = "true";
    return Object.freeze({
      refresh: controller.refresh,
      dispose() {
        controller.dispose();
        workspace.removeAttribute("data-dossiers-mounted");
        workspace.replaceChildren();
      },
    });
  }

  workspace.innerHTML = dossierWorkspaceMarkup();
  const detailColumn = workspace.querySelector(".context-column");
  detailColumn.append(
    workspace.querySelector("[data-dossiers-lifecycle-panel]"),
    workspace.querySelector("[data-dossiers-pending-actions]"),
  );
  const authority = createOperatorDossierAuthority(client, options);
  const state = {
    query: { zone: "PENDING", retention_state: "ACTIVE", request_kind: null, search: "" },
    items: [],
    nextCursor: null,
    selected: null,
    detail: null,
    documents: [],
    assignment: null,
    roster: [],
    command: null,
    requests: [],
    request: null,
    uploadUrl: null,
    requestBusy: false,
    substance: null,
    pendingPurgeEligibility: null,
    counters: null,
  };
  const status = workspace.querySelector("[data-dossiers-status]");

  function revalidateSelection() {
    const visibleSelection = visibleDossierSelection(state.selected, state.items);
    if (visibleSelection) {
      state.selected = visibleSelection;
      return true;
    }
    selectDossier.generation += 1;
    selectCustomerRequest.generation += 1;
    state.selected = null;
    state.detail = null;
    state.substance = null;
    state.documents = [];
    state.assignment = null;
    state.roster = [];
    state.requests = [];
    state.request = null;
    state.uploadUrl = null;
    state.requestBusy = false;
    clearDetailSelection(workspace);
    return false;
  }

  async function loadList(isCurrent, append = false, { background = false } = {}) {
    if (!background) {
      status.textContent = "Dossiers laden.";
      workspace.setAttribute("aria-busy", "true");
    }
    if (!append && !background) {
      state.items = [];
      renderList(workspace, [], null);
    }
    const request = identity.role === "owner"
      ? dossierListRequest(state.query, append ? state.nextCursor : null)
      : { action: "get_my_assigned_dossiers", limit: 25, ...(append && state.nextCursor ? { cursor: state.nextCursor } : {}) };
    const loadCounters = ()=>Promise.all([
      authority.gateway({ action: "count_pending_intakes" }),
      ...["ACTIVE", "ARCHIVED", "TRASHED"].map((zone)=>authority.gateway({
        action: "get_application_facets_v2",
        zone,
        operational_status: null,
        request_kind: null,
        search: null,
      })),
    ]);
    const [pageResponse, counterResponses] = await Promise.all([
      authority.gateway(request),
      identity.role === "owner" && !append
        ? loadCounters()
        : Promise.resolve(null),
    ]);
    const page = validateDossierListPage(pageResponse, request.action);
    if (!isCurrent()) return;
    if (counterResponses) state.counters = validateDossierCounters(...counterResponses);
    const search = String(state.query.search || "").trim().toLowerCase();
    const visibleItems = request.action === "list_pending_intakes" ? page.items.filter((item)=>{
      const productMatches = !state.query.request_kind || item.raw.request_kind === state.query.request_kind;
      const searchMatches = !search || [item.raw.name, item.raw.organization, item.raw.support_reference]
        .some((value)=>String(value || "").toLowerCase().includes(search));
      return productMatches && searchMatches;
    }) : page.items;
    const combined = append ? [...state.items, ...visibleItems] : visibleItems;
    state.items = [...new Map(combined.map((item)=>[item.reference, item])).values()];
    state.nextCursor = page.nextCursor;
    revalidateSelection();
    renderList(workspace, state.items, state.selected?.reference);
    renderStatusOverview(workspace, state);
    workspace.querySelector('[data-dossiers-action="more"]').hidden = !page.hasMore;
    if (!background) {
      status.textContent = "";
      workspace.setAttribute("aria-busy", "false");
    }
  }

  const controller = createOperatorDossiersController({
    load: options.load || ((isCurrent, refreshOptions)=>loadList(isCurrent, false, refreshOptions)),
    onChange: options.onChange,
  });

  async function refreshWorkspace({ preserveSelection = true, background = false } = {}) {
    const selectedReference = preserveSelection ? state.selected?.reference : null;
    const queryFingerprint = JSON.stringify(state.query);
    const refreshed = await controller.refresh({ background });
    if (!refreshed || controller.disposed || !selectedReference) return refreshed;
    if (JSON.stringify(state.query) !== queryFingerprint || state.selected?.reference !== selectedReference) return refreshed;
    if (background && (state.command || workspace.ownerDocument.querySelector("dialog[open]"))) return refreshed;
    const selected = state.items.find((item)=>item.reference === selectedReference);
    if (selected) return await selectDossier(selected);
    clearDetailSelection(workspace);
    return true;
  }

  function refreshList() {
    void controller.refresh().catch((error)=>{
      if (controller.disposed) return;
      workspace.setAttribute("aria-busy", "false");
      status.textContent = errorCode(error) === "DOSSIER_DISPOSED" ? "" : "Dossiers konden niet veilig worden geladen.";
    });
  }

  const ownerDocument = workspace.ownerDocument;
  const ownerWindow = ownerDocument.defaultView;
  const panel = workspace.closest?.("[data-module-panel]");
  const assignmentForm = workspace.querySelector("[data-dossiers-assignment-form]");
  const autoRefresh = createOperatorAutoRefresh({
    moduleKey: "dossiers",
    refresh: (refreshOptions)=>refreshWorkspace(refreshOptions),
    isActive: ()=>!panel?.hidden,
    isBlocked: ()=>Boolean(state.command || ownerDocument.querySelector("dialog[open]")
      || assignmentForm.querySelector('textarea[name="reason"]').value.trim()
      || (state.assignment && assignmentForm.querySelector('select[name="assignee_operator_id"]').value
        !== (state.assignment.assignee_operator_id || ""))),
    documentTarget: ownerDocument,
    windowTarget: ownerWindow,
  });

  async function selectDossier(summary) {
    if (!summary) return false;
    const selection = ++selectDossier.generation;
    resetDossierCopyPreview(workspace);
    state.selected = summary;
    state.detail = null;
    state.substance = null;
    state.requests = [];
    state.request = null;
    state.uploadUrl = null;
    state.requestBusy = false;
    selectCustomerRequest.generation += 1;
    workspace.querySelector("[data-dossiers-request-detail]").hidden = true;
    workspace.querySelector("[data-dossiers-purge]").hidden = true;
    workspace.querySelector("[data-dossiers-purge-message]").textContent = "";
    renderList(workspace, state.items, summary.reference);
    if (summary.kind === "pending") {
      status.textContent = "Dossier laden.";
      try {
        const substanceResponse = await authority.gateway(dossierSubstanceRequest(summary));
        const substance = validateDossierSubstance(substanceResponse, summary.raw.quote_request_id);
        if (controller.disposed || selection !== selectDossier.generation) return false;
        state.substance = substance;
        renderPendingDetail(workspace, summary, substance);
        status.textContent = "";
        return true;
      } catch (error) {
        if (selection === selectDossier.generation) status.textContent = errorCode(error) === "DOSSIER_DISPOSED" ? "" : "Dossier kon niet veilig worden geladen.";
        return false;
      }
    }
    status.textContent = "Dossier laden.";
    try {
      const [detailResponse, substanceResponse] = await Promise.all([
        authority.gateway({ action: "get_application_detail", ...summary.locator }),
        authority.gateway(dossierSubstanceRequest(summary.raw)),
      ]);
      const detail = detailIdentity(detailResponse);
      const substance = validateDossierSubstance(substanceResponse, detail.quote_request_id);
      if (controller.disposed || selection !== selectDossier.generation) return false;
      state.detail = detail;
      state.substance = substance;
      renderDetail(workspace, detail, summary, substance);
      const reference = dossierReference(detail);
      const tasks = [
        authority.gateway(dossierDocumentRequest(detail)).then((documents)=>{
          if (!Array.isArray(documents) || selection !== selectDossier.generation) return;
          state.documents = documents;
          renderDocuments(workspace, documents);
        }),
        authority.gateway({ action: "list_customer_requests_for_dossier", dossier_reference: reference, cursor: null, limit: 25 }).then((page)=>{
          if (!Array.isArray(page?.items) || selection !== selectDossier.generation) return;
          state.requests = page.items;
          renderRequests(workspace, page.items);
        }),
      ];
      if (["owner", "operations_manager"].includes(identity.role)) {
        tasks.push(Promise.all([
          authority.gateway({ action: "get_dossier_assignment", dossier_reference: reference }),
          authority.gateway({ action: "get_assignment_operator_roster" }),
        ]).then(([assignment, roster])=>{
          if (selection !== selectDossier.generation || !Number.isSafeInteger(assignment?.revision) || !Array.isArray(roster)) return;
          state.assignment = assignment;
          state.roster = roster;
          const section = workspace.querySelector("[data-dossiers-assignment]");
          const select = section.querySelector("select");
          select.replaceChildren(new Option("Kies een operator", ""));
          for (const operator of roster) {
            if (UUID.test(String(operator?.operator_id || "")) && operator?.display_name) select.add(new Option(operator.display_name, operator.operator_id));
          }
          select.value = assignment.assignee_operator_id || "";
          workspace.querySelector("[data-dossiers-assignee]").textContent = assignment.assignee_display_name || "Niet toegewezen";
          section.hidden = false;
        }));
      }
      if (identity.role === "owner" && detail.dossier_lifecycle?.state === "TRASHED") {
        const request = dossierPurgeEligibilityRequest(detail);
        tasks.push(authority.rpc(request.name, request.parameters).then((eligibility)=>{
          if (selection !== selectDossier.generation) return;
          const purge = workspace.querySelector("[data-dossiers-purge]");
          purge.hidden = eligibility?.can_purge !== true;
          workspace.querySelector("[data-dossiers-purge-message]").textContent = eligibility?.can_purge === true
            ? "Permanent verwijderen is server-side toegestaan."
            : purgeBlockMessage(eligibility?.reason);
        }));
      }
      await Promise.allSettled(tasks);
      if (selection === selectDossier.generation) status.textContent = "";
      return true;
    } catch (error) {
      if (selection === selectDossier.generation) status.textContent = errorCode(error) === "DOSSIER_DISPOSED" ? "" : "Dossier kon niet veilig worden geladen.";
      return false;
    }
  }
  selectDossier.generation = 0;

  async function selectCustomerRequest(summary) {
    if (!UUID.test(String(summary?.request_id || "")) || state.requestBusy) return false;
    const generation = ++selectCustomerRequest.generation;
    state.requestBusy = true;
    workspace.querySelector("[data-dossiers-request-message]").textContent = "Request laden.";
    try {
      const request = validateCustomerRequestDetail(await authority.gateway({ action: "get_customer_request", request_id: summary.request_id }));
      if (controller.disposed || generation !== selectCustomerRequest.generation) return false;
      state.request = request;
      state.uploadUrl = null;
      renderCustomerRequestDetail(workspace, request);
      workspace.querySelector("[data-dossiers-request-message]").textContent = "";
      return true;
    } catch {
      if (!controller.disposed && generation === selectCustomerRequest.generation) workspace.querySelector("[data-dossiers-request-message]").textContent = "Request kon niet veilig worden geladen.";
      return false;
    } finally {
      if (generation === selectCustomerRequest.generation) state.requestBusy = false;
    }
  }
  selectCustomerRequest.generation = 0;

  async function refreshCustomerRequest(expectedGeneration = selectCustomerRequest.generation) {
    if (!state.request) return false;
    const request = validateCustomerRequestDetail(await authority.gateway({ action: "get_customer_request", request_id: state.request.request_id }));
    if (controller.disposed || expectedGeneration !== selectCustomerRequest.generation) return false;
    state.request = request;
    state.uploadUrl = null;
    renderCustomerRequestDetail(workspace, request);
    return true;
  }

  async function transitionCustomerRequest(commandType) {
    if (!state.request || state.requestBusy) return false;
    const generation = selectCustomerRequest.generation;
    state.requestBusy = true;
    try {
      await authority.gateway(customerRequestTransitionRequest(state.request, commandType, crypto.randomUUID()));
      if (generation !== selectCustomerRequest.generation) return false;
      return await refreshCustomerRequest(generation);
    } catch {
      if (!controller.disposed) workspace.querySelector("[data-dossiers-request-message]").textContent = "Requeststatus kon niet worden gewijzigd. Vernieuw de request.";
      return false;
    } finally {
      if (generation === selectCustomerRequest.generation) state.requestBusy = false;
    }
  }

  async function createCustomerUploadLink() {
    if (!state.request || state.requestBusy) return false;
    const generation = selectCustomerRequest.generation;
    state.requestBusy = true;
    try {
      const result = await authority.gateway(customerRequestUploadRequest(state.request, crypto.randomUUID()));
      const keys = result && typeof result === "object" ? Object.keys(result) : [];
      if (keys.length !== 5 || !["state", "upload_request_id", "expires_at", "was_created", "upload_url"].every((key)=>Object.hasOwn(result, key))
        || result.state !== "ACTIVE" || !UUID.test(String(result.upload_request_id || "")) || typeof result.expires_at !== "string"
        || typeof result.was_created !== "boolean" || typeof result.upload_url !== "string") throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_LINK");
      if (controller.disposed || generation !== selectCustomerRequest.generation) return false;
      state.request = { ...state.request, upload_request: { upload_request_id: result.upload_request_id, status: "ACTIVE", expires_at: result.expires_at } };
      state.uploadUrl = authorizedCustomerUploadUrl(result.upload_url);
      renderCustomerRequestDetail(workspace, state.request, state.uploadUrl);
      return true;
    } catch {
      if (!controller.disposed) workspace.querySelector("[data-dossiers-request-message]").textContent = "Uploadlink kon niet veilig worden aangemaakt.";
      return false;
    } finally {
      if (generation === selectCustomerRequest.generation) state.requestBusy = false;
    }
  }

  async function revokeCustomerUploadLink() {
    if (!state.request || state.requestBusy) return false;
    const generation = selectCustomerRequest.generation;
    state.requestBusy = true;
    try {
      const uploadRequestId = state.request.upload_request?.upload_request_id;
      const result = await authority.gateway(customerRequestUploadRequest(state.request, crypto.randomUUID(), true));
      if (result?.state !== "REVOKED" || result.upload_request_id !== uploadRequestId || result.was_revoked !== true || Object.keys(result).length !== 3) {
        throw new Error("INVALID_CUSTOMER_REQUEST_UPLOAD_REVOKE");
      }
      if (controller.disposed || generation !== selectCustomerRequest.generation) return false;
      state.request = { ...state.request, upload_request: null };
      state.uploadUrl = null;
      renderCustomerRequestDetail(workspace, state.request);
      return true;
    } catch {
      if (!controller.disposed) workspace.querySelector("[data-dossiers-request-message]").textContent = "Uploadlink kon niet veilig worden ingetrokken.";
      return false;
    } finally {
      if (generation === selectCustomerRequest.generation) state.requestBusy = false;
    }
  }

  async function mutate(request) {
    if (!state.detail) return false;
    const selectedReference = state.selected?.reference;
    try {
      status.textContent = "Dossieractie wordt uitgevoerd.";
      await authority.gateway(request);
      if (controller.disposed) return false;
      await controller.refresh();
      const refreshed = state.items.find((item)=>item.reference === selectedReference);
      if (refreshed) await selectDossier(refreshed);
      else clearDetailSelection(workspace);
      return true;
    } catch {
      if (!controller.disposed) status.textContent = "Dossieractie is niet uitgevoerd. Vernieuw het dossier en probeer opnieuw.";
      return false;
    }
  }

  async function mutatePending(request) {
    try {
      status.textContent = request.action === "trash_dossier" ? "Dossier wordt naar de prullenbak verplaatst." : "Werkruimtestatus wordt gewijzigd.";
      await authority.gateway(request);
      if (controller.disposed) return false;
      state.selected = null;
      await controller.refresh();
      clearDetailSelection(workspace);
      status.textContent = request.action === "trash_dossier" ? "Dossier staat in de prullenbak."
        : request.action === "archive_pending_intake" ? "Intake is gearchiveerd." : "Intake is teruggezet naar actief.";
      return true;
    } catch {
      if (!controller.disposed) status.textContent = "Intakeactie is niet uitgevoerd. Vernieuw het dossier en probeer opnieuw.";
      return false;
    }
  }

  function openCommandDialog(command) {
    const dialog = workspace.querySelector("[data-dossiers-command-dialog]");
    state.command = command;
    dialog.querySelector("[data-dossiers-command-title]").textContent = command.kind === "purge" ? "Dossier permanent verwijderen"
      : command.kind === "pending-trash" ? "Dossier naar prullenbak"
      : command.action === "archive_pending_intake" ? "Intake archiveren"
      : command.action === "restore_pending_intake" ? "Intake terugzetten naar actief" : "Dossierstatus wijzigen";
    dialog.querySelector("[data-dossiers-command-message]").textContent = command.kind === "purge"
      ? "Deze actie is definitief. Geef een concrete reden om door te gaan."
      : "Geef een reden voor deze dossieractie.";
    dialog.querySelector("textarea").value = "";
    dialog.showModal();
    dialog.querySelector("textarea").focus();
  }

  controller.listen(workspace, "submit", (event)=>{
    if (event.target.matches("[data-dossiers-filters]")) {
      event.preventDefault();
      const data = new FormData(event.target);
      state.query = { ...state.query, search: data.get("search"), zone: data.get("zone"), request_kind: data.get("request_kind") || null };
      refreshList();
    } else if (event.target.matches("[data-dossiers-assignment-form]")) {
      event.preventDefault();
      if (!state.detail || !state.assignment) return;
      const data = new FormData(event.target);
      void mutate(dossierAssignmentRequest(state.detail, state.assignment, data.get("assignee_operator_id"), data.get("reason"), crypto.randomUUID()));
    } else if (event.target.matches("[data-dossiers-command-form]")) {
      event.preventDefault();
      if (!state.command || (!state.detail && !["pending-retention", "pending-trash"].includes(state.command.kind))) return;
      const dialog = workspace.querySelector("[data-dossiers-command-dialog]");
      const reason = new FormData(event.target).get("reason");
      const command = state.command;
      state.command = null;
      dialog.close();
      if (command.kind === "lifecycle") {
        void mutate(dossierLifecycleRequest(command.action, state.detail, reason, crypto.randomUUID()));
      } else if (command.kind === "pending-retention") {
        void mutatePending(pendingIntakeRetentionRequest(command.action, state.selected.raw, reason, crypto.randomUUID()));
      } else if (command.kind === "pending-trash") {
        void mutatePending(pendingDossierTrashRequest(state.selected.raw, reason, crypto.randomUUID()));
      } else {
        const request = dossierPurgeRequest(state.detail, reason, crypto.randomUUID());
        status.textContent = "Dossier wordt permanent verwijderd.";
        void authority.rpc(request.name, request.parameters).then(async ()=>{
          if (controller.disposed) return;
          state.selected = null;
          state.detail = null;
          await controller.refresh();
        }).catch(()=>{
          if (!controller.disposed) status.textContent = "Het dossier kon niet permanent worden verwijderd.";
        });
      }
    }
  });
  controller.listen(workspace, "change", (event)=>{
    if (!event.target.matches('[data-dossiers-filters] select[name="zone"], [data-dossiers-filters] select[name="request_kind"]')) return;
    const form = event.target.form;
    const data = new FormData(form);
    state.query = { ...state.query, search: data.get("search"), zone: data.get("zone"), request_kind: data.get("request_kind") || null };
    refreshList();
  });
  controller.listen(workspace, "click", (event)=>{
    const target = event.target.closest?.("button");
    if (!target) return;
    if (target.dataset.dossiersZone) {
      state.query.zone = target.dataset.dossiersZone;
      workspace.querySelector('[data-dossiers-filters] select[name="zone"]').value = state.query.zone;
      refreshList();
    }
    else if (target.dataset.dossiersRetentionState) {
      state.query.retention_state = target.dataset.dossiersRetentionState;
      refreshList();
    }
    else if (target.dataset.dossiersAction === "refresh") void refreshWorkspace();
    else if (target.dataset.dossiersAction === "more") void loadList(()=>!controller.disposed, true);
    else if (target.dataset.dossiersSelect !== undefined) void selectDossier(state.items[Number(target.dataset.dossiersSelect)]);
    else if (target.dataset.dossiersRequest !== undefined) void selectCustomerRequest(state.requests[Number(target.dataset.dossiersRequest)]);
    else if (target.hasAttribute("data-dossiers-request-transition")) void transitionCustomerRequest(target.dataset.command);
    else if (target.hasAttribute("data-dossiers-upload-create")) void createCustomerUploadLink();
    else if (target.hasAttribute("data-dossiers-upload-revoke")) void revokeCustomerUploadLink();
    else if (target.hasAttribute("data-dossiers-upload-copy")) {
      if (state.uploadUrl) void navigator.clipboard.writeText(state.uploadUrl).then(()=>{
        if (!controller.disposed) workspace.querySelector("[data-dossiers-request-message]").textContent = "Uploadlink gekopieerd.";
      });
    }
    else if (target.dataset.dossiersLifecycle) {
      openCommandDialog({ kind: "lifecycle", action: target.dataset.dossiersLifecycle });
    } else if (target.dataset.dossiersPendingRetentionAction) {
      openCommandDialog({ kind: "pending-retention", action: target.dataset.dossiersPendingRetentionAction });
    } else if (target.hasAttribute("data-dossiers-pending-trash")) {
      openCommandDialog({ kind: "pending-trash" });
    } else if (target.hasAttribute("data-dossiers-purge")) {
      openCommandDialog({ kind: "purge" });
    } else if (target.dataset.dossiersCopy) {
      const selected = visibleDossierSelection(state.selected, state.items);
      const application = dossierCopyAvailable(state.detail)
        && selected?.reference === dossierReference(state.detail) ? state.detail.application : null;
      if (application) {
        void import("./application-dossier-copy.js?v=20260903-owner-flow-audit").then((copy)=>{
          const current = visibleDossierSelection(state.selected, state.items);
          if (controller.disposed || current?.reference !== selected.reference
            || state.detail?.application !== application || dossierReference(state.detail) !== selected.reference) return;
          if (target.dataset.dossiersCopy === "view") {
            copy.renderApplicationDossier(workspace.querySelector("[data-dossiers-copy-content]"), application);
            workspace.querySelector("[data-dossiers-copy-reference]").textContent = application.applicationReference;
            workspace.querySelector("[data-dossiers-copy-dialog]").showModal();
          } else if (target.dataset.dossiersCopy === "download") copy.downloadApplicationDossierPdf(application);
          else copy.printApplicationDossier(application);
        }).catch(()=>{
          if (!controller.disposed) status.textContent = "Dossierkopie kon niet veilig worden geopend.";
        });
      }
    } else if (target.hasAttribute("data-dossiers-copy-close")) {
      workspace.querySelector("[data-dossiers-copy-dialog]").close();
    } else if (target.hasAttribute("data-dossiers-command-cancel")) {
      state.command = null;
      workspace.querySelector("[data-dossiers-command-dialog]").close();
    } else if (target.dataset.dossiersDocument !== undefined) {
      const item = state.documents[Number(target.dataset.dossiersDocument)];
      void authority.gateway(dossierDocumentRequest(state.detail, item)).then((access)=>{
        if (!controller.disposed) globalThis.open?.(authorizedDocumentUrl(access?.signed_url), "_blank", "noopener,noreferrer");
      });
    }
  });
  workspace.dataset.dossiersMounted = "true";
  void controller.refresh().catch((error)=>{
    if (!controller.disposed) status.textContent = errorCode(error) === "DOSSIER_DISPOSED" ? "" : "Dossiers konden niet veilig worden geladen.";
  });
  return Object.freeze({
    refresh: refreshWorkspace,
    dispose() {
      selectDossier.generation += 1;
      selectCustomerRequest.generation += 1;
      state.uploadUrl = null;
      autoRefresh.dispose();
      controller.dispose();
      authority.dispose();
      workspace.removeAttribute("data-dossiers-mounted");
      workspace.replaceChildren();
    },
  });
}
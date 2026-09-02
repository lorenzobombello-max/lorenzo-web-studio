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
  "list_applications_v2", "list_pending_intakes", "get_application_facets_v2", "get_application_detail",
  "get_project_dossier", "get_my_assigned_dossiers", "get_dossier_document_manifest",
  "create_dossier_document_access", "list_customer_requests_for_dossier", "get_customer_request",
  "transition_customer_request", "create_customer_request_upload_link",
  "revoke_customer_request_upload_link", "create_sdf_customer_request",
  "get_dossier_assignment", "get_assignment_operator_roster", "assign_dossier",
  "archive_dossier", "reactivate_dossier", "trash_dossier", "restore_dossier",
  "promote_accepted_application", "issue_and_deliver_approved_quotation",
]);
const DOSSIER_RPC_ACTIONS = new Set(["can_purge_dossier_v1", "purge_dossier_v1", "can_purge_sdf_dossier_v1", "purge_sdf_dossier_v1"]);
const CUSTOMER_REQUEST_DETAIL_FIELDS = new Set([
  "request_id", "request_reference", "source", "request_type", "title", "description",
  "status", "priority", "submitted_at", "revision", "updated_at", "upload_request",
]);

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

export function dossierListRequest(query = {}, cursor = null) {
  const zone = ["PENDING", "ACTIVE", "ARCHIVED", "TRASHED"].includes(query.zone) ? query.zone : "PENDING";
  if (zone === "PENDING") return { action: "list_pending_intakes", retention_state: "ACTIVE" };
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
    || !["ACTIVE", "TRASHED"].includes(detail?.dossier_lifecycle?.state)) throw new Error("INVALID_DOSSIER_PURGE_ELIGIBILITY");
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

  async function refresh() {
    if (disposed) return false;
    const requestGeneration = ++generation;
    const isCurrent = ()=>!disposed && requestGeneration === generation;
    await load(isCurrent);
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
    <form class="application-search dossiers-filters" data-dossiers-filters role="search"><label><span>Zoeken</span><input name="search" type="search" maxlength="140" autocomplete="off" placeholder="Naam, bedrijf of referentie" /></label><label>Zone<select name="zone"><option value="PENDING">Pending / Nieuwe aanvragen</option><option value="ACTIVE">Actief</option><option value="ARCHIVED">Afgerond / Archief</option><option value="TRASHED">Prullenbak</option></select></label><label>Product<select name="request_kind"><option value="">Alle</option><option value="website">Website</option><option value="slimme_documentenflow">Slimme Documentenflow</option></select></label><button type="submit" class="primary-action primary-action--compact">Toepassen</button></form>
    <p class="action-message action-message--dark" data-dossiers-status role="status" aria-live="polite"></p>
    <div class="dashboard-grid dossiers-grid"><section class="panel" aria-labelledby="dossiersListTitle"><div class="panel__heading"><div><p class="eyebrow">Werkvoorraad</p><h2 id="dossiersListTitle">Dossiers</h2></div><span class="badge" data-dossiers-count>0</span></div><ul class="application-list" data-dossiers-list></ul><p class="empty-state" data-dossiers-empty hidden>Geen dossiers gevonden.</p><button type="button" class="secondary-action" data-dossiers-action="more" hidden>Meer laden</button></section>
      <aside class="context-column" aria-label="Dossierdetail"><section class="panel" data-dossiers-detail-empty><h2>Selecteer een dossier</h2><p class="empty-state">Kies een dossier uit de werkvoorraad.</p></section>
        <article class="panel dossiers-detail" data-dossiers-detail hidden><div class="panel__heading"><div><p class="eyebrow" data-dossiers-field="reference"></p><h2 data-dossiers-field="name"></h2></div><span class="badge" data-dossiers-field="status"></span></div><dl class="application-detail"><div><dt>Product</dt><dd data-dossiers-field="product"></dd></div><div><dt>Zone</dt><dd data-dossiers-field="zone"></dd></div><div><dt>Bedrijf</dt><dd data-dossiers-field="company"></dd></div><div><dt>E-mail</dt><dd data-dossiers-field="email"></dd></div><div><dt>Telefoon</dt><dd data-dossiers-field="phone"></dd></div><div class="application-detail__wide"><dt>Omschrijving</dt><dd data-dossiers-field="description"></dd></div></dl></article>
        <section class="panel dossiers-lifecycle" data-dossiers-lifecycle-panel hidden><div class="panel__heading"><div><p class="eyebrow">Dossierbeheer</p><h2>Status</h2></div><span class="badge" data-dossiers-lifecycle-state></span></div><div class="lifecycle-actions"><button type="button" class="secondary-action" data-dossiers-lifecycle="archive_dossier">Archiveren</button><button type="button" class="secondary-action" data-dossiers-lifecycle="reactivate_dossier">Activeren</button><button type="button" class="danger-action" data-dossiers-lifecycle="trash_dossier">Naar prullenbak</button><button type="button" class="secondary-action" data-dossiers-lifecycle="restore_dossier">Herstellen</button><button type="button" class="danger-action" data-dossiers-purge hidden>Permanent verwijderen</button></div><p class="action-message" data-dossiers-purge-message></p></section>
        <section class="panel dossiers-assignment" data-dossiers-assignment hidden><div class="panel__heading"><div><p class="eyebrow">Toewijzing</p><h2>Operator</h2></div><strong data-dossiers-assignee></strong></div><form data-dossiers-assignment-form><label>Toewijzen aan<select name="assignee_operator_id" required><option value="">Kies een operator</option></select></label><label>Reden bij hertoewijzing<textarea name="reason" rows="3" maxlength="500"></textarea></label><button type="submit" class="primary-action primary-action--compact">Opslaan</button></form></section>
        <section class="panel" data-dossiers-documents hidden><div class="panel__heading"><div><p class="eyebrow">Documenten</p><h2>Dossierdocumenten</h2></div></div><ul class="document-list" data-dossiers-document-list></ul><p class="empty-state" data-dossiers-document-empty></p></section>
        <section class="panel" data-dossiers-requests hidden><div class="panel__heading"><div><p class="eyebrow">Klantverzoeken</p><h2>Requests</h2></div></div><ul class="customer-request-list" data-dossiers-request-list></ul><p class="empty-state" data-dossiers-request-empty></p><article data-dossiers-request-detail hidden><hr /><p class="eyebrow" data-dossiers-request-reference></p><h3 data-dossiers-request-title></h3><p data-dossiers-request-description></p><dl class="application-detail"><div><dt>Status</dt><dd data-dossiers-request-status></dd></div><div><dt>Prioriteit</dt><dd data-dossiers-request-priority></dd></div></dl><div class="lifecycle-actions"><button type="button" class="primary-action primary-action--compact" data-dossiers-request-transition hidden></button><button type="button" class="secondary-action" data-dossiers-upload-create>Uploadlink maken</button><button type="button" class="secondary-action" data-dossiers-upload-copy hidden>Uploadlink kopiëren</button><button type="button" class="danger-action" data-dossiers-upload-revoke hidden>Uploadlink intrekken</button></div><input type="url" readonly data-dossiers-upload-url hidden aria-label="Veilige uploadlink" /><p class="action-message" data-dossiers-request-message></p></article></section>
      </aside></div>
    <dialog class="operator-dialog" data-dossiers-command-dialog aria-labelledby="dossiersCommandTitle"><form data-dossiers-command-form><p class="eyebrow">Bevestiging vereist</p><h2 id="dossiersCommandTitle" data-dossiers-command-title>Dossieractie</h2><p data-dossiers-command-message></p><label>Reden<textarea name="reason" rows="4" minlength="1" maxlength="500" required></textarea></label><div class="dialog-actions"><button type="button" class="secondary-action" data-dossiers-command-cancel>Annuleren</button><button type="submit" class="danger-action">Bevestigen</button></div></form></dialog>`;
}

function setText(workspace, field, value) {
  const node = workspace.querySelector(`[data-dossiers-field="${field}"]`);
  if (node) node.textContent = value == null || value === "" ? "Niet beschikbaar" : String(value);
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
    || !["invited", "in_progress"].includes(item.intake_status) || item.retention_state !== "ACTIVE") {
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

function detailIdentity(detail) {
  if (!detail || !UUID.test(String(detail.quote_request_id || "")) || !["website", "slimme_documentenflow"].includes(detail.request_kind)
    || typeof detail.name !== "string" || !detail.name) throw new Error("INVALID_DOSSIER_DETAIL_RESPONSE");
  return detail;
}

function customerValue(detail, key) {
  return detail?.customer?.[key] ?? detail?.application?.customer?.[key] ?? detail?.[key] ?? null;
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
    if (item.reference === selectedReference) button.setAttribute("aria-current", "true");
    name.textContent = item.name;
    reference.textContent = item.reference;
    status.className = "badge";
    status.textContent = item.status.replaceAll("_", " ");
    identity.append(name, reference);
    button.append(identity, status);
    row.append(button);
    list.append(row);
  }
  workspace.querySelector("[data-dossiers-count]").textContent = String(items.length);
  workspace.querySelector("[data-dossiers-empty]").hidden = items.length > 0;
}

function renderDetail(workspace, detail, summary) {
  setText(workspace, "reference", dossierReference(detail));
  setText(workspace, "name", detail.name);
  setText(workspace, "status", detail.operational_status || summary?.status);
  setText(workspace, "product", detail.request_kind === "website" ? "Website" : "Slimme Documentenflow");
  setText(workspace, "zone", detail.dossier_lifecycle?.state || summary?.zone);
  setText(workspace, "company", customerValue(detail, "company") || detail.organization);
  setText(workspace, "email", customerValue(detail, "email"));
  setText(workspace, "phone", customerValue(detail, "phone"));
  setText(workspace, "description", detail.description);
  workspace.querySelector("[data-dossiers-detail-empty]").hidden = true;
  workspace.querySelector("[data-dossiers-detail]").hidden = false;
  const lifecycle = workspace.querySelector("[data-dossiers-lifecycle-panel]");
  lifecycle.hidden = !detail.dossier_lifecycle;
  if (detail.dossier_lifecycle) {
    workspace.querySelector("[data-dossiers-lifecycle-state]").textContent = detail.dossier_lifecycle.state;
    const allowed = { ACTIVE: ["archive_dossier", "trash_dossier"], ARCHIVED: ["reactivate_dossier", "trash_dossier"], TRASHED: ["restore_dossier"] }[detail.dossier_lifecycle.state] || [];
    for (const button of lifecycle.querySelectorAll("[data-dossiers-lifecycle]")) button.hidden = !allowed.includes(button.dataset.dossiersLifecycle);
  }
}

function renderPendingDetail(workspace, summary) {
  const detail = summary.raw;
  setText(workspace, "reference", detail.support_reference);
  setText(workspace, "name", detail.name);
  setText(workspace, "status", detail.intake_status);
  setText(workspace, "product", detail.request_kind === "website" ? "Website" : "Slimme Documentenflow");
  setText(workspace, "zone", "Pending / Nieuwe aanvraag");
  setText(workspace, "company", detail.organization);
  setText(workspace, "email", detail.email);
  setText(workspace, "phone", detail.phone);
  setText(workspace, "description", detail.website_type);
  workspace.querySelector("[data-dossiers-detail-empty]").hidden = true;
  workspace.querySelector("[data-dossiers-detail]").hidden = false;
  for (const selector of ["[data-dossiers-lifecycle-panel]", "[data-dossiers-assignment]", "[data-dossiers-documents]", "[data-dossiers-requests]"]) {
    workspace.querySelector(selector).hidden = true;
  }
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
  const authority = createOperatorDossierAuthority(client, options);
  const state = {
    query: { zone: "PENDING", request_kind: null, search: "" },
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
  };
  const status = workspace.querySelector("[data-dossiers-status]");

  async function loadList(isCurrent, append = false) {
    status.textContent = "Dossiers laden.";
    const request = identity.role === "owner"
      ? dossierListRequest(state.query, append ? state.nextCursor : null)
      : { action: "get_my_assigned_dossiers", limit: 25, ...(append && state.nextCursor ? { cursor: state.nextCursor } : {}) };
    const page = validateDossierListPage(await authority.gateway(request), request.action);
    if (!isCurrent()) return;
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
    renderList(workspace, state.items, state.selected?.reference);
    workspace.querySelector('[data-dossiers-action="more"]').hidden = !page.hasMore;
    status.textContent = "";
  }

  const controller = createOperatorDossiersController({
    load: options.load || ((isCurrent)=>loadList(isCurrent)),
    onChange: options.onChange,
  });

  async function selectDossier(summary) {
    if (!summary) return false;
    const selection = ++selectDossier.generation;
    state.selected = summary;
    state.detail = null;
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
      renderPendingDetail(workspace, summary);
      status.textContent = "";
      return true;
    }
    status.textContent = "Dossier laden.";
    try {
      const detail = detailIdentity(await authority.gateway({ action: "get_application_detail", ...summary.locator }));
      if (controller.disposed || selection !== selectDossier.generation) return false;
      state.detail = detail;
      renderDetail(workspace, detail, summary);
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
          workspace.querySelector("[data-dossiers-assignee]").textContent = assignment.assignee_display_name || "Niet toegewezen";
          section.hidden = false;
        }));
      }
      if (identity.role === "owner" && ["ACTIVE", "TRASHED"].includes(detail.dossier_lifecycle?.state)) {
        const request = dossierPurgeEligibilityRequest(detail);
        tasks.push(authority.rpc(request.name, request.parameters).then((eligibility)=>{
          if (selection !== selectDossier.generation) return;
          const purge = workspace.querySelector("[data-dossiers-purge]");
          purge.hidden = eligibility?.can_purge !== true;
          workspace.querySelector("[data-dossiers-purge-message]").textContent = eligibility?.can_purge === true
            ? "Permanent verwijderen is server-side toegestaan."
            : String(eligibility?.reason || "Permanent verwijderen is niet toegestaan.");
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
    status.textContent = "Dossieractie wordt uitgevoerd.";
    await authority.gateway(request);
    if (controller.disposed) return false;
    await controller.refresh();
    const refreshed = state.items.find((item)=>item.reference === state.selected?.reference);
    if (refreshed) await selectDossier(refreshed);
    return true;
  }

  function openCommandDialog(command) {
    const dialog = workspace.querySelector("[data-dossiers-command-dialog]");
    state.command = command;
    dialog.querySelector("[data-dossiers-command-title]").textContent = command.kind === "purge" ? "Dossier permanent verwijderen" : "Dossierstatus wijzigen";
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
      state.query = { search: data.get("search"), zone: data.get("zone"), request_kind: data.get("request_kind") || null };
      void controller.refresh();
    } else if (event.target.matches("[data-dossiers-assignment-form]")) {
      event.preventDefault();
      if (!state.detail || !state.assignment) return;
      const data = new FormData(event.target);
      void mutate(dossierAssignmentRequest(state.detail, state.assignment, data.get("assignee_operator_id"), data.get("reason"), crypto.randomUUID()));
    } else if (event.target.matches("[data-dossiers-command-form]")) {
      event.preventDefault();
      if (!state.detail || !state.command) return;
      const dialog = workspace.querySelector("[data-dossiers-command-dialog]");
      const reason = new FormData(event.target).get("reason");
      const command = state.command;
      state.command = null;
      dialog.close();
      if (command.kind === "lifecycle") {
        void mutate(dossierLifecycleRequest(command.action, state.detail, reason, crypto.randomUUID()));
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
  controller.listen(workspace, "click", (event)=>{
    const target = event.target.closest?.("button");
    if (!target) return;
    if (target.dataset.dossiersAction === "refresh") void controller.refresh();
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
    } else if (target.hasAttribute("data-dossiers-purge")) {
      openCommandDialog({ kind: "purge" });
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
    refresh: controller.refresh,
    dispose() {
      selectDossier.generation += 1;
      selectCustomerRequest.generation += 1;
      state.uploadUrl = null;
      controller.dispose();
      authority.dispose();
      workspace.removeAttribute("data-dossiers-mounted");
      workspace.replaceChildren();
    },
  });
}
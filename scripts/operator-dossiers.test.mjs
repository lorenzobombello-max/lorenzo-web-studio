import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path)=>readFile(new URL(path, root), "utf8");

test("dedicated Dossiers module imports independently", async () => {
  const dossiers = await import("../assets/js/operator-dossiers.mjs");
  assert.equal(typeof dossiers.initializeOperatorDossiers, "function");
  assert.equal(typeof dossiers.createOperatorDossiersController, "function");
  const source = await read("assets/js/operator-dossiers.mjs");
  assert.doesNotMatch(source, /from ["'][^"']*(?:operator-dashboard|application-dossier|sdf-qualification-intake|website)[^"']*["']/i);
  assert.match(source, /from "\.\/sdf-qualification-review\.mjs"/);
  assert.doesNotMatch(source, /localStorage|sessionStorage|window\.name|localhost|127\.0\.0\.1/i);
});

test("Dossiers controller suppresses stale work and disposal is terminal", async () => {
  const { createOperatorDossiersController } = await import("../assets/js/operator-dossiers.mjs");
  const pending = [];
  let changes = 0;
  const controller = createOperatorDossiersController({
    load: (isCurrent)=>new Promise((resolve)=>pending.push({ isCurrent, resolve })),
    onChange: ()=>{ changes += 1; },
  });
  const first = controller.refresh();
  const second = controller.refresh();
  assert.equal(pending[0].isCurrent(), false);
  assert.equal(pending[1].isCurrent(), true);
  pending[0].resolve();
  assert.equal(await first, false);
  controller.dispose();
  assert.equal(pending[1].isCurrent(), false);
  pending[1].resolve();
  assert.equal(await second, false);
  assert.equal(await controller.refresh(), false);
  assert.equal(changes, 0);
});

test("Dossiers selection is valid only inside the current visible dataset", async () => {
  const { dossierCopyAvailable, validateDossierCounters, visibleDossierSelection } = await import("../assets/js/operator-dossiers.mjs");
  const selected = { reference: "#77EE2F45", zone: "PENDING" };
  const fresh = { reference: "#77EE2F45", zone: "PENDING", status: "in_progress" };
  assert.equal(visibleDossierSelection(selected, [fresh]), fresh);
  for (const visible of [
    [],
    [{ reference: "LWS-AAN-2099-0002", zone: "ACTIVE" }],
    [{ reference: "LWS-AAN-2099-0003", zone: "ARCHIVED" }],
    [{ reference: "LWS-AAN-2099-0004", zone: "TRASHED" }],
  ]) assert.equal(visibleDossierSelection(selected, visible), null);
  assert.equal(visibleDossierSelection(null, [fresh]), null);
  for (const lifecycleState of ["ACTIVE", "ARCHIVED", "TRASHED"]) {
    assert.equal(dossierCopyAvailable({
      request_kind: "website",
      application: { applicationReference: "LWS-AAN-2099-0001" },
      dossier_lifecycle: { state: lifecycleState },
    }), true);
  }
  assert.equal(dossierCopyAvailable({ request_kind: "website", application: null }), false);
  assert.equal(dossierCopyAvailable({ request_kind: "slimme_documentenflow", application: {} }), false);
  assert.equal(dossierCopyAvailable(null), false);
  assert.deepEqual(validateDossierCounters(
    { active_count: 4 },
    { years: [{ year: 2026, count: 2 }, { year: 2025, count: 1 }] },
    { years: [] },
    { years: [{ year: 2026, count: 3 }] },
  ), { PENDING: 4, ACTIVE: 3, ARCHIVED: 0, TRASHED: 3 });
  assert.throws(()=>validateDossierCounters({ active_count: 1 }, { years: [{ count: -1 }] }, { years: [] }, { years: [] }), /INVALID_DOSSIER_COUNTERS/);

  const source = await read("assets/js/operator-dossiers.mjs");
  assert.match(source, /state\.items = \[\.\.\.new Map[\s\S]*revalidateSelection\(\);[\s\S]*renderList/);
  assert.match(source, /selectDossier\.generation \+= 1;[\s\S]*state\.selected = null;[\s\S]*state\.detail = null;[\s\S]*clearDetailSelection\(workspace\)/);
  assert.match(source, /state\.selected\?\.reference !== selectedReference\) return refreshed/);
  assert.doesNotMatch(source, /if \(!append\) \{[\s\S]{0,120}state\.selected = null/);
});

test("Dossiers initializer mounts and dispose clears sensitive DOM", async () => {
  const { initializeOperatorDossiers } = await import("../assets/js/operator-dossiers.mjs");
  const workspace = {
    dataset: {},
    removeAttribute(name) { if (name === "data-dossiers-mounted") delete this.dataset.dossiersMounted; },
    replaceChildren() { this.clearCount = (this.clearCount || 0) + 1; },
  };
  const firstController = initializeOperatorDossiers(
    { querySelector: ()=>workspace },
    { rpc() {} },
    { role: "operator", status: "ACTIVE" },
  );
  assert.equal(workspace.dataset.dossiersMounted, "true");
  assert.equal(typeof firstController.dispose, "function");
  firstController.dispose();
  assert.equal(workspace.dataset.dossiersMounted, undefined);
  assert.equal(workspace.clearCount, 1);
  const secondController = initializeOperatorDossiers(
    { querySelector: ()=>workspace },
    { rpc() {} },
    { role: "operator", status: "ACTIVE" },
  );
  assert.notEqual(secondController, firstController);
  assert.equal(workspace.dataset.dossiersMounted, "true");
  secondController.dispose();
  assert.equal(workspace.clearCount, 2);
  for (const identity of [
    { role: "operator", status: "DISABLED" },
    { role: "unknown", status: "ACTIVE" },
  ]) assert.throws(
    ()=>initializeOperatorDossiers({ querySelector: ()=>workspace }, { rpc() {} }, identity),
    /DOSSIER_OPERATOR_NOT_AUTHORIZED/,
  );
});

test("Dossier authority permits only bounded contracts and fast-locks authorization failures", async () => {
  const {
    createOperatorDossierAuthority,
    dossierAssignmentRequest,
    dossierDocumentRequest,
    dossierLifecycleRequest,
    dossierListRequest,
    validateDossierListPage,
  } = await import("../assets/js/operator-dossiers.mjs");
  const calls = [];
  const locked = [];
  const detail = {
    quote_request_id: "10000000-0000-4000-8000-000000000001",
    application_reference: "LWS-AAN-2099-0001",
    dossier_lifecycle: { state: "ACTIVE", revision: 4 },
  };
  const client = {
    functions: { invoke: async (name, options)=>{
      calls.push({ name, options });
      return { data: { ok: true, result: { items: [], has_more: false, next_cursor: null } }, error: null };
    } },
    rpc: async (name, parameters)=>({ data: { name, parameters }, error: null }),
  };
  const authority = createOperatorDossierAuthority(client, { onAuthorizationFailure: (code)=>locked.push(code) });
  assert.deepEqual(dossierListRequest(), { action: "list_pending_intakes", retention_state: "ACTIVE" });
  assert.deepEqual(dossierListRequest({ zone: "ACTIVE" }), {
    action: "list_applications_v2", zone: "ACTIVE", operational_status: null,
    year: null, quarter: null, request_kind: null, search: null, cursor: null, limit: 50,
  });
  assert.deepEqual(dossierListRequest({ search: " Lorenzo " }), {
    action: "list_pending_intakes", retention_state: "ACTIVE",
  });
  const pending = {
    quote_request_id: "50000000-0000-4000-8000-000000000005", intake_id: "60000000-0000-4000-8000-000000000006",
    name: "Bestaande aanvraag", organization: null, support_reference: "#5C19F9DD", email: "existing@example.test",
    phone: null, request_kind: "website", website_type: "Website op maat", intake_status: "invited", retention_state: "ACTIVE",
    dossier_state: "ACTIVE", dossier_revision: 0,
  };
  assert.deepEqual(validateDossierListPage({ items: [] }, "list_pending_intakes"), { items: [], hasMore: false, nextCursor: null });
  assert.equal(validateDossierListPage({ items: [pending] }, "list_pending_intakes").items[0].zone, "PENDING");
  assert.throws(()=>validateDossierListPage({ items: [] }), /INVALID_DOSSIER_LIST_RESPONSE/);
  assert.throws(()=>validateDossierListPage({ items: [pending], error: "hidden" }, "list_pending_intakes"), /INVALID_PENDING_DOSSIER_LIST_RESPONSE/);
  assert.deepEqual(dossierLifecycleRequest("archive_dossier", detail, " Gereed ", "20000000-0000-4000-8000-000000000002"), {
    action: "archive_dossier", quote_request_id: detail.quote_request_id, expected_revision: 4,
    idempotency_key: "20000000-0000-4000-8000-000000000002", reason: "Gereed",
  });
  assert.equal(dossierAssignmentRequest(detail, { revision: 0, assignee_operator_id: null }, "30000000-0000-4000-8000-000000000003", "", "40000000-0000-4000-8000-000000000004").action, "assign_dossier");
  assert.deepEqual(dossierDocumentRequest(detail), { action: "get_dossier_document_manifest", quote_request_id: detail.quote_request_id });
  await authority.gateway(dossierListRequest({ zone: "ACTIVE" }));
  assert.equal(calls[0].name, "commercial-operator-command");
  assert.deepEqual(await authority.gateway(dossierListRequest()), { items: [], has_more: false, next_cursor: null });
  await assert.rejects(()=>authority.rpc("get_document_inbox_v1"), /DOSSIER_RPC_NOT_ALLOWED/);
  client.functions.invoke = async ()=>({ data: null, error: { message: "OPERATOR_DISABLED" } });
  await assert.rejects(()=>authority.gateway(dossierListRequest()), /OPERATOR_DISABLED/);
  assert.deepEqual(locked, ["OPERATOR_DISABLED"]);
  authority.dispose();
  await assert.rejects(()=>authority.gateway(dossierListRequest()), /DOSSIER_DISPOSED/);
});

test("permanent deletion is product-aware, owner-presented, and exact RPC-bound", async () => {
  const { dossierPurgeEligibilityRequest, dossierPurgeRequest } = await import("../assets/js/operator-dossiers.mjs");
  const quoteRequestId = "f4100000-0000-4000-8000-000000000001";
  const idempotencyKey = "f4100000-0000-4000-8000-000000000002";
  const website = dossierPurgeRequest({
    quote_request_id: quoteRequestId,
    request_kind: "website",
    dossier_lifecycle: { state: "TRASHED" },
  }, " Dubbele testaanvraag ", idempotencyKey);
  assert.deepEqual(website, {
    name: "purge_dossier_v1",
    parameters: { p_quote_request_id: quoteRequestId, p_reason: "Dubbele testaanvraag", p_idempotency_key: idempotencyKey },
  });
  assert.throws(()=>dossierPurgeEligibilityRequest({
    quote_request_id: quoteRequestId, request_kind: "website", dossier_lifecycle: { state: "ACTIVE" },
  }), /INVALID_DOSSIER_PURGE_ELIGIBILITY/);
  assert.equal(dossierPurgeRequest({
    quote_request_id: quoteRequestId,
    request_kind: "slimme_documentenflow",
    dossier_lifecycle: { state: "TRASHED" },
  }, "Opruimen", idempotencyKey).name, "purge_sdf_dossier_v1");
  assert.throws(()=>dossierPurgeRequest({
    quote_request_id: quoteRequestId,
    request_kind: "website",
    dossier_lifecycle: { state: "ARCHIVED" },
  }, "Niet toegestaan", idempotencyKey), /INVALID_DOSSIER_PURGE_COMMAND/);
  const source = await read("assets/js/operator-dossiers.mjs");
  assert.match(source, /data-dossiers-command-dialog/);
  assert.doesNotMatch(source, /globalThis\.prompt|\bprompt\s*\(/);
  assert.match(source, /identity\.role === "owner"/);
});

test("customer request actions are revision-bound, status-closed, and ephemeral", async () => {
  const {
    customerRequestCommand,
    customerRequestTransitionRequest,
    customerRequestUploadRequest,
    validateCustomerRequestDetail,
  } = await import("../assets/js/operator-dossiers.mjs");
  const requestId = "f4200000-0000-4000-8000-000000000001";
  const uploadRequestId = "f4200000-0000-4000-8000-000000000002";
  const idempotencyKey = "f4200000-0000-4000-8000-000000000003";
  assert.deepEqual(["TRIAGED", "IN_PROGRESS", "WAITING_CUSTOMER", "RESOLVED"].map(customerRequestCommand), ["START", "REQUIRE_CUSTOMER_RESPONSE", "RESUME", null]);
  const request = {
    request_id: requestId, request_reference: "LWS-REQ-0001", source: "OPERATOR", request_type: "FILE_DELIVERY",
    title: "Documenten", description: "Lever documenten aan.", status: "TRIAGED", priority: "NORMAL",
    submitted_at: "2026-09-02T12:00:00Z", revision: 4, updated_at: "2026-09-02T12:00:00Z", upload_request: null,
  };
  assert.equal(validateCustomerRequestDetail(request), request);
  assert.deepEqual(customerRequestTransitionRequest(request, "START", idempotencyKey), {
    action: "transition_customer_request", request_id: requestId, command_type: "START", expected_revision: 4, idempotency_key: idempotencyKey,
  });
  assert.throws(()=>customerRequestTransitionRequest(request, "RESUME", idempotencyKey), /INVALID_CUSTOMER_REQUEST_TRANSITION/);
  assert.deepEqual(customerRequestUploadRequest(request, idempotencyKey), { action: "create_customer_request_upload_link", request_id: requestId, idempotency_key: idempotencyKey });
  assert.deepEqual(customerRequestUploadRequest({ ...request, upload_request: { upload_request_id: uploadRequestId, status: "ACTIVE", expires_at: "2026-09-02T13:00:00Z" } }, idempotencyKey, true), {
    action: "revoke_customer_request_upload_link", upload_request_id: uploadRequestId,
    reason: "Operator heeft de uploadlink ingetrokken.", idempotency_key: idempotencyKey,
  });
  assert.throws(()=>validateCustomerRequestDetail({ ...request, role: "owner" }), /INVALID_CUSTOMER_REQUEST_DETAIL/);
  const source = await read("assets/js/operator-dossiers.mjs");
  assert.doesNotMatch(source, /localStorage|sessionStorage/);
  assert.match(source, /generation !== selectCustomerRequest\.generation/);
  assert.match(source, /state\.uploadUrl = null/);
  assert.match(source, /customer-request-upload\\\.html#token=\[A-Za-z0-9_-\]\{43\}/);
});

test("embedded dashboard and generic child use the same Dossiers initializer", async () => {
  const [dashboard, registry, childHtml, dashboardHtml, guard] = await Promise.all([
    read("assets/js/operator-dashboard.js"),
    read("assets/js/operator-module-registry.mjs"),
    read("operator/window/index.html"),
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard-guard.mjs"),
  ]);
  assert.match(dashboard, /initializeOperatorDossiers/);
  assert.match(dashboard, /activeModule === "dossiers"[\s\S]*return currentIdentity;[\s\S]*activeModule === "finance"[\s\S]*return currentIdentity;/);
  assert.match(registry, /moduleKey: "dossiers"[\s\S]*standaloneAllowed: true[\s\S]*multiScreenAllowed: true/);
  assert.match(registry, /initializeOperatorDossiers/);
  assert.match(childHtml, /id="operatorModuleTemplate-dossiers"/);
  assert.match(childHtml, /data-dossiers-workspace/);
  assert.match(dashboardHtml, /data-module-panel="dossiers"[^>]*data-dossiers-workspace/);
  assert.match(guard, /operatorDossiersController\?\.dispose/);
  assert.match(guard, /loadModule: async \(_module, context\)=>\{\s*disposeDossiers\(\)/);
  assert.match(guard, /workspaceMaster\.bindModuleButton\(button, button\.dataset\.operatorWindowModule/);
  for (const source of [dashboard, registry]) assert.match(source, /operator-dossiers\.mjs\?v=20260903-auto-refresh-8s/);
  for (const html of [dashboardHtml, childHtml]) assert.match(html, /operator-dashboard\.css\?v=20260903-owner-flow-audit/);
  const source = await read("assets/js/operator-dossiers.mjs");
  assert.match(source, /data-dossiers-status-overview|dossiers-status-overview/);
  assert.match(source, /Nieuwe aanvragen/);
  assert.match(source, /Uitgenodigd/);
  assert.match(source, /Intake bezig/);
  assert.match(source, /data-dossiers-zone="ACTIVE"/);
  assert.match(source, /data-dossiers-filters[^]*select\[name="zone"\]/);
  assert.match(source, /Originele klantaanvraag/);
  assert.match(source, /renderPendingDetail\(workspace, summary, substance\)/);
  assert.match(source, /data-operator-window-module="dossiers"[^>]*hidden>Open in nieuw venster<\/button>/);
  assert.match(source, /<form class="assignment-form" data-dossiers-assignment-form>/);
  assert.doesNotMatch(source, /setText\(workspace, "description", null\)/);
  assert.match(source, /workspace\.setAttribute\("aria-busy", "true"\)/);
  assert.doesNotMatch(source, />Toepassen</);
  const css = await read("assets/css/operator-dashboard.css");
  assert.match(css, /\.dossiers-status-overview/);
  assert.match(css, /\.dossiers-grid \{ grid-template-columns:/);
  assert.match(css, /\.dossiers-original-request/);
  assert.match(css, /\.assignment-form \{[^}]*grid-template-columns:/);
});

test("pending and active Dossiers reload on fresh instances after disposal", async () => {
  const { initializeOperatorDossiers } = await import("../assets/js/operator-dossiers.mjs");
  const workspace = {
    dataset: {},
    removeAttribute(name) { if (name === "data-dossiers-mounted") delete this.dataset.dossiersMounted; },
    replaceChildren() {},
  };
  const loaded = [];
  for (const zone of ["PENDING", "ACTIVE"]) {
    const controller = initializeOperatorDossiers(
      { querySelector: ()=>workspace },
      { rpc() {} },
      { role: "owner", status: "ACTIVE" },
      { load: async (isCurrent)=>{ if (isCurrent()) loaded.push(zone); } },
    );
    assert.equal(await controller.refresh(), true);
    controller.dispose();
  }
  assert.deepEqual(loaded, ["PENDING", "ACTIVE"]);
});

test("Dossiers disposal removes listeners before a new instance subscribes", async () => {
  const { createOperatorDossiersController } = await import("../assets/js/operator-dossiers.mjs");
  const listeners = new Set();
  const target = {
    addEventListener(_type, listener) { listeners.add(listener); },
    removeEventListener(_type, listener) { listeners.delete(listener); },
  };
  let calls = 0;
  const first = createOperatorDossiersController();
  first.listen(target, "click", ()=>{ calls += 1; });
  first.dispose();
  const second = createOperatorDossiersController();
  second.listen(target, "click", ()=>{ calls += 1; });
  for (const listener of listeners) listener();
  assert.equal(calls, 1);
  assert.equal(listeners.size, 1);
  second.dispose();
  assert.equal(listeners.size, 0);
});

test("Dossiers present Belgian dates, a labelled reference, and persistent accessible selection", async () => {
  const { formatOperatorDate } = await import("../assets/js/operator-dossiers.mjs");
  assert.equal(formatOperatorDate("2026-09-02T07:43:27.206665+00:00"), "02/09/2026 – 09:43");
  assert.equal(formatOperatorDate(null), "Niet beschikbaar");
  assert.equal(formatOperatorDate("not-a-date"), "Niet beschikbaar");
  const [source, css] = await Promise.all([
    read("assets/js/operator-dossiers.mjs"),
    read("assets/css/operator-dashboard.css"),
  ]);
  assert.match(source, /Dossierreferentie <strong data-dossiers-field="reference">/);
  assert.match(source, /button\.setAttribute\("aria-selected", String\(selected\)\)/);
  assert.match(source, /renderList\(workspace, state\.items, summary\.reference\)/);
  assert.match(css, /\.application-list__button\[aria-current="true"\]:hover/);
  assert.match(css, /\.dossiers-list \.application-list__button\[aria-current="true"\][^}]*background:#d9f3f0/);
  assert.match(css, /\.dossiers-actions\[hidden\],\.dossiers-actions \[hidden\]/);
});

test("Pending retention and trash-first lifecycle commands remain server-bound", async () => {
  const { dossierListRequest, pendingDossierTrashRequest, pendingIntakeRetentionRequest } = await import("../assets/js/operator-dossiers.mjs");
  const item = {
    intake_id: "f4300000-0000-4000-8000-000000000001",
    quote_request_id: "f4300000-0000-4000-8000-000000000002",
    retention_state: "ACTIVE",
    retention_revision: 3,
    dossier_state: "ACTIVE",
    dossier_revision: 7,
  };
  const idempotencyKey = "f4300000-0000-4000-8000-000000000003";
  assert.deepEqual(dossierListRequest({ zone: "PENDING", retention_state: "ARCHIVED" }), {
    action: "list_pending_intakes", retention_state: "ARCHIVED",
  });
  assert.deepEqual(pendingIntakeRetentionRequest("archive_pending_intake", item, " Dubbele intake ", idempotencyKey), {
    action: "archive_pending_intake", intake_id: item.intake_id, expected_revision: 3,
    idempotency_key: idempotencyKey, reason: "Dubbele intake",
  });
  assert.equal(pendingIntakeRetentionRequest("restore_pending_intake", {
    ...item, retention_state: "ARCHIVED",
  }, "Terugzetten", idempotencyKey).action, "restore_pending_intake");
  assert.deepEqual(pendingDossierTrashRequest(item, " Testrecord ", idempotencyKey), {
    action: "trash_dossier", quote_request_id: item.quote_request_id, expected_revision: 7,
    idempotency_key: idempotencyKey, reason: "Testrecord",
  });
  assert.throws(()=>pendingDossierTrashRequest({ ...item, dossier_state: "TRASHED" }, "Nee", idempotencyKey), /INVALID_PENDING_DOSSIER_TRASH_COMMAND/);
  const source = await read("assets/js/operator-dossiers.mjs");
  assert.match(source, />Actief<\/button><button[^>]+>Gearchiveerd<\/button>/);
  assert.match(source, />Dossieracties<\/h2>/);
  assert.match(source, /data-dossiers-copy-actions hidden/);
  assert.match(source, /data-dossiers-copy="view">Preview<\/button>/);
  assert.match(source, />Download PDF<\/button>/);
  assert.match(source, />Afdrukken<\/button>/);
  assert.match(source, />Naar prullenbak<\/button>/);
  assert.match(source, />Herstellen uit prullenbak<\/button>/);
  assert.match(source, /data-dossiers-command-dialog/);
  assert.match(source, /import\("\.\/application-dossier-copy\.js\?v=20260903-owner-flow-audit"\)/);
  assert.match(source, /visibleDossierSelection\(state\.selected, state\.items\)[\s\S]*state\.detail\?\.application !== application/);
  assert.match(source, /data-dossiers-copy-actions\]"\)\.hidden = !dossierCopyAvailable\(detail\)/);
  assert.match(source, /for \(const selector of \["\[data-dossiers-copy-actions\]", "\[data-dossiers-lifecycle-panel\]"/);
  assert.match(source, /function resetDossierCopyPreview[\s\S]*if \(dialog\.open\) dialog\.close\(\);[\s\S]*replaceChildren\(\)/);
  assert.match(source, /const selection = \+\+selectDossier\.generation;\s*resetDossierCopyPreview\(workspace\)/);
  assert.doesNotMatch(source, /permanently_delete_pending_intake|pendingSdfDossierPurgeRequest/);
  assert.match(source, /detail\.dossier_lifecycle\?\.state === "TRASHED"/);
  assert.match(source, /reeds een offerte aan dit dossier gekoppeld/);
  assert.match(source, /detailColumn\.append\([\s\S]*data-dossiers-lifecycle-panel[\s\S]*data-dossiers-pending-actions/);
});

test("archived Pending records remain valid in the retention workspace", async () => {
  const { validateDossierListPage } = await import("../assets/js/operator-dossiers.mjs");
  const item = {
    quote_request_id: "a1000000-0000-4000-8000-000000000001",
    intake_id: "a1000000-0000-4000-8000-000000000002",
    name: "Synthetic customer",
    organization: "Synthetic company",
    support_reference: "#A1000000",
    request_kind: "website",
    intake_status: "invited",
    retention_state: "ARCHIVED",
    dossier_state: "ACTIVE",
    dossier_revision: 2,
  };
  const page = validateDossierListPage({ items: [item] }, "list_pending_intakes");
  assert.equal(page.items[0].raw.retention_state, "ARCHIVED");
});

test("Dossiers uses the shared quiet refresh lifecycle and preserves dirty assignment input", async () => {
  const { createOperatorDossiersController } = await import("../assets/js/operator-dossiers.mjs");
  const options = [];
  const controller = createOperatorDossiersController({ load: async (_isCurrent, refreshOptions)=>options.push(refreshOptions) });
  assert.equal(await controller.refresh({ background: true }), true);
  assert.deepEqual(options, [{ background: true }]);
  controller.dispose();
  const source = await read("assets/js/operator-dossiers.mjs");
  assert.match(source, /createOperatorAutoRefresh\(\{[\s\S]*moduleKey: "dossiers"[\s\S]*refreshWorkspace\(refreshOptions\)/);
  assert.match(source, /assignmentForm\.querySelector\('textarea\[name="reason"\]'\)\.value\.trim\(\)/);
  assert.match(source, /if \(!append && !background\)/);
  assert.match(source, /autoRefresh\.dispose\(\)/);
});
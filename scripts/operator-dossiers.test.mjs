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

test("Dossier reads retry transient failures without retrying stale, invalid, or unauthorized work", async () => {
  const { loadDossierReadWithRetry } = await import("../assets/js/operator-dossiers.mjs");
  let attempts = 0;
  assert.equal(await loadDossierReadWithRetry(async ()=>{
    attempts += 1;
    if (attempts === 1) throw new Error("OPERATOR_REQUEST_FAILED");
    return "loaded";
  }), "loaded");
  assert.equal(attempts, 2);
  attempts = 0;
  await assert.rejects(loadDossierReadWithRetry(
    ()=>{ attempts += 1; return new Promise(()=>{}); },
    ()=>true,
    { timeoutMs: 1, setTimer: globalThis.setTimeout, clearTimer: globalThis.clearTimeout },
  ), /DOSSIER_READ_TIMEOUT/);
  assert.equal(attempts, 2);
  for (const [code, isCurrent] of [["INVALID_DOSSIER_SUBSTANCE", true], ["OPERATOR_NOT_AUTHORIZED", true], ["OPERATOR_REQUEST_FAILED", false]]) {
    attempts = 0;
    await assert.rejects(loadDossierReadWithRetry(async ()=>{
      attempts += 1;
      throw new Error(code);
    }, ()=>isCurrent), new RegExp(code));
    assert.equal(attempts, 1);
  }
  const source = await read("assets/js/operator-dossiers.mjs");
  assert.match(source, /loadDossierReadWithRetry\([\s\S]*dossierDocumentRequest\(detail\)/);
  assert.match(source, /state\.copySource = summary\.raw\.request_kind === "website" \? pendingDossierCopy\(summary, substance\) : null;/);
  assert.match(source, /Dossierdocumenten laden\.[\s\S]*Dossierdocumenten konden niet worden geladen\./);
  assert.match(source, /void Promise\.allSettled\(tasks\);[\s\S]*status\.textContent = ""/);
  assert.doesNotMatch(source, /await Promise\.allSettled\(tasks\)/);
});

test("Dossiers selection is valid only inside the current visible dataset", async () => {
  const { boundDossierCopy, dossierCopyAvailable, validateDossierCounters, visibleDossierSelection } = await import("../assets/js/operator-dossiers.mjs");
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
  const firstCopy = { kind: "pending_intake", reference: fresh.reference };
  const secondCopy = { kind: "pending_intake", reference: "#88EE2F46" };
  assert.equal(boundDossierCopy(selected, [fresh], firstCopy), firstCopy);
  assert.equal(boundDossierCopy(selected, [fresh], secondCopy), null);
  assert.equal(boundDossierCopy(selected, [], firstCopy), null);
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
    dossierSeenRequest,
    applyDossierSeen,
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
    dossier_state: "ACTIVE", dossier_revision: 0, invitation_created_at: "2026-09-03T05:33:00Z",
  };
  assert.deepEqual(validateDossierListPage({ items: [] }, "list_pending_intakes"), { items: [], hasMore: false, nextCursor: null });
  assert.deepEqual(
    validateDossierListPage({ items: [pending] }, "list_pending_intakes").items[0],
    {
      raw: pending,
      kind: "pending",
      locator: { quote_request_id: pending.quote_request_id },
      reference: "#5C19F9DD",
      name: "Bestaande aanvraag",
      company: "",
      product: "Website",
      requestedAt: "2026-09-03T05:33:00Z",
      status: "invited",
      zone: "PENDING",
      seenAt: null,
    },
  );
  assert.deepEqual(dossierSeenRequest({ raw: pending }), {
    action: "mark_dossier_seen",
    quote_request_id: pending.quote_request_id,
  });
  const seenAt = "2026-09-03T15:00:00Z";
  const unseenSummary = validateDossierListPage({ items: [pending] }, "list_pending_intakes").items[0];
  const seenItems = applyDossierSeen([unseenSummary], unseenSummary.reference, {
    quote_request_id: pending.quote_request_id,
    seen_at: seenAt,
  });
  assert.equal(unseenSummary.seenAt, null);
  assert.equal(seenItems[0].seenAt, seenAt);
  assert.equal(seenItems[0].raw.seen_at, seenAt);
  assert.throws(()=>applyDossierSeen([unseenSummary], unseenSummary.reference, {
    quote_request_id: "50000000-0000-4000-8000-000000000099",
    seen_at: seenAt,
  }), /INVALID_DOSSIER_SEEN_RESPONSE/);
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
  assert.match(source, /class="operator-modal--action-confirm dossiers-command-dialog"/);
  assert.match(source, /aria-modal="true" aria-labelledby="dossiersCommandTitle" aria-describedby="dossiersCommandDescription"/);
  assert.match(source, /class="confirmation" data-dossiers-command-form/);
  assert.match(source, /id="dossiersCommandDescription" data-dossiers-command-message/);
  assert.match(source, /class="confirmation__field" for="dossiersCommandReason"><span>Reden<\/span><textarea id="dossiersCommandReason"/);
  assert.match(source, /class="confirmation__actions"/);
  assert.match(source, /data-dossiers-command-confirm/);
  assert.doesNotMatch(source, /globalThis\.prompt|\bprompt\s*\(/);
  assert.match(source, /identity\.role === "owner"/);
  assert.match(source, /command\.kind === "pending-trash" \|\| command\.action === "trash_dossier" \? "Dossier naar prullenbak"/);
  assert.match(source, /command\.action === "restore_dossier" \? "Dossier herstellen"/);
  assert.match(source, /command\.kind === "purge" \? "Dossier permanent verwijderen"/);
  assert.match(source, /data-dossiers-command-confirm[^\n]+destructive \? "danger-action" : "primary-action primary-action--compact"/);
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
  const [dashboard, registry, childHtml, dashboardHtml, dashboardGuard, windowGuard] = await Promise.all([
    read("assets/js/operator-dashboard.js"),
    read("assets/js/operator-module-registry.mjs"),
    read("operator/window/index.html"),
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard-guard.mjs"),
    read("assets/js/operator-window-guard.mjs"),
  ]);
  assert.match(dashboard, /initializeOperatorDossiers/);
  assert.match(dashboard, /activeModule === "dossiers"[\s\S]*return currentIdentity;[\s\S]*activeModule === "finance"[\s\S]*return currentIdentity;/);
  assert.match(registry, /moduleKey: "dossiers"[\s\S]*standaloneAllowed: true[\s\S]*multiScreenAllowed: true/);
  assert.match(registry, /initializeOperatorDossiers/);
  assert.match(childHtml, /id="operatorModuleTemplate-dossiers"/);
  assert.match(childHtml, /data-dossiers-workspace/);
  assert.match(dashboardHtml, /data-module-panel="dossiers"[^>]*data-dossiers-workspace/);
  assert.match(dashboardGuard, /operatorDossiersController\?\.dispose/);
  assert.match(dashboardGuard, /loadModule: async \(_module, context\)=>\{\s*disposeDossiers\(\)/);
  assert.match(dashboardGuard, /workspaceMaster\.bindModuleButton\(button, button\.dataset\.operatorWindowModule/);
  const dossierCacheIdentity = "20260903-dossiers-seen-state-r1";
  const profileCacheIdentity = "20260903-operator-profiles-r1";
  assert.ok(dashboardHtml.includes(`operator-dashboard-guard.mjs?v=${profileCacheIdentity}`));
  assert.ok(dashboardGuard.includes(`operator-dashboard.js?v=${profileCacheIdentity}`));
  assert.ok(dashboard.includes(`operator-dossiers.mjs?v=${dossierCacheIdentity}`));
  assert.ok(childHtml.includes(`operator-window-guard.mjs?v=${dossierCacheIdentity}`));
  assert.ok(windowGuard.includes(`operator-module-registry.mjs?v=${dossierCacheIdentity}`));
  assert.ok(registry.includes(`operator-dossiers.mjs?v=${dossierCacheIdentity}`));
  assert.ok(dashboardHtml.includes(`operator-dashboard.css?v=${profileCacheIdentity}`));
  assert.ok(childHtml.includes(`operator-dashboard.css?v=${dossierCacheIdentity}`));
  const source = await read("assets/js/operator-dossiers.mjs");
  assert.match(source, /data-dossiers-status-overview|dossiers-status-overview/);
  assert.match(source, /Nieuwe aanvragen/);
  assert.match(source, /Uitgenodigd/);
  assert.match(source, /Intake bezig/);
  assert.match(source, /data-dossiers-zone="ACTIVE"/);
  assert.match(source, /data-dossiers-filters[^]*select\[name="zone"\]/);
  assert.match(source, /select\[name="zone"\]'\)\.value = state\.query\.zone;\s*renderStatusOverview\(workspace, state\);\s*refreshList\(\);/);
  assert.match(source, /async function selectDossier\(summary, \{ markSeen = false \} = \{\}\)/);
  assert.match(source, /renderPendingDetail\(workspace, summary, substance, state\.copySource\);\s*if \(markSeen\) void markSelectedDossierSeen/);
  assert.match(source, /renderDetail\(workspace, detail, summary, substance\);\s*if \(markSeen\) void markSelectedDossierSeen/);
  assert.match(source, /target\.dataset\.dossiersSelect[^\n]+selectDossier\([^\n]+\{ markSeen: true \}\)/);
  assert.equal(source.match(/\{ markSeen: true \}/g)?.length, 1);
  assert.match(source, /NIEUW \/ NIET GEZIEN/);
  assert.doesNotMatch(source, /textContent = "GEZIEN"/);
  assert.match(source, /if \(!item\.seenAt\)[\s\S]*unseen\.className = "badge badge--green"[\s\S]*badges\.append\(unseen\)/);
  assert.match(source, /Originele klantaanvraag/);
  assert.match(source, /renderPendingDetail\(workspace, summary, substance, state\.copySource\)/);
  assert.match(source, /data-operator-window-module="dossiers"[^>]*hidden>Open in nieuw venster<\/button>/);
  assert.match(source, /<form class="assignment-form" data-dossiers-assignment-form>/);
  assert.doesNotMatch(source, /setText\(workspace, "description", null\)/);
  assert.match(source, /workspace\.setAttribute\("aria-busy", "true"\)/);
  assert.doesNotMatch(source, />Toepassen</);
  const css = await read("assets/css/operator-dashboard.css");
  assert.match(css, /\.dossiers-status-overview/);
  assert.match(css, /\.dossiers-grid \{ grid-template-columns:/);
  assert.match(css, /\.dossiers-original-request/);
  assert.doesNotMatch(css, /\[data-dossiers-workspace\]\[aria-busy="true"\] \.dossiers-list \{[^}]*opacity:/);
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
  assert.match(source, /company\.textContent = item\.company \|\| "Niet beschikbaar"/);
  assert.match(source, /metadata\.textContent = `\$\{item\.product\} · \$\{formatOperatorDate\(item\.requestedAt\)/);
  assert.match(source, /identity\.append\(name, company, metadata, reference\);\s*button\.append\(identity, badges\)/);
  assert.match(source, /renderList\(workspace, state\.items, summary\.reference\)/);
  assert.match(css, /\.application-list__button\[aria-current="true"\]:hover/);
  assert.match(css, /\.dossiers-list \.application-list__button\[aria-current="true"\][^}]*background:#d9f3f0/);
  assert.match(css, /\.dossiers-list \.application-list__button \{[^}]*overflow:hidden[^}]*isolation:isolate/);
  assert.match(css, /\.dossiers-list \.application-list__button\[aria-current="true"\]::after[^}]*skewX\(-16deg\)[^}]*animation:dossier-card-light-sweep 9s/);
  assert.match(css, /@keyframes dossier-card-light-sweep[^}]*15%[^}]*opacity:0[^}]*skewX\(-16deg\)/);
  assert.doesNotMatch(css, /\.dossiers-list \.application-list__button:not\(\[aria-current="true"\]\)::after/);
  assert.match(css, /\.dossiers-list__company[^}]*overflow-wrap:anywhere/);
  assert.match(css, /\.dossiers-actions\[hidden\],\.dossiers-actions \[hidden\]/);
});

test("Dossiers cards preserve distinguishing list data for customers with the same name", async () => {
  const { validateDossierListPage } = await import("../assets/js/operator-dossiers.mjs");
  const items = Array.from({ length: 4 }, (_, index)=>({
    quote_request_id: `70000000-0000-4000-8000-00000000000${index + 1}`,
    application_reference: `LWS-AAN-2026-000${index + 1}`,
    support_reference: `#7000000${index + 1}`,
    name: "Lorenzo Bombello",
    organization: `Bedrijf ${index + 1}`,
    request_kind: index % 2 === 0 ? "website" : "slimme_documentenflow",
    dossier_date: `2026-09-03T0${index + 5}:33:00Z`,
    operational_status: index % 2 === 0 ? "SUBMITTED" : "REVIEWED",
    zone: "ACTIVE",
  }));
  const summaries = validateDossierListPage({ items, has_more: false, next_cursor: null }).items;
  assert.equal(new Set(summaries.map((item)=>item.name)).size, 1);
  for (const field of ["company", "product", "requestedAt", "reference", "status"]) {
    assert.ok(new Set(summaries.map((item)=>item[field])).size > 1, `${field} must distinguish equal names`);
  }
});

test("Pending retention and trash-first lifecycle commands remain server-bound", async () => {
  const { dossierListRequest, pendingDossierCopy, pendingDossierTrashRequest, pendingIntakeRetentionRequest } = await import("../assets/js/operator-dossiers.mjs");
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
  assert.match(source, /import\("\.\/application-dossier-copy\.js\?v=20260903-pending-dossier-copy-symbol"\)/);
  assert.match(source, /boundDossierCopy\(state\.selected, state\.items, state\.copySource\) !== copySource/);
  assert.match(source, /data-dossiers-copy-actions\]"\)\.hidden = !dossierCopyAvailable\(detail\)/);
  assert.match(source, /renderPendingDetail\(workspace, summary, substance, state\.copySource\)/);
  assert.match(source, /function resetDossierCopyPreview[\s\S]*if \(dialog\.open\) dialog\.close\(\);[\s\S]*replaceChildren\(\)/);
  assert.match(source, /const selection = \+\+selectDossier\.generation;\s*resetDossierCopyPreview\(workspace\)/);
  assert.doesNotMatch(source, /permanently_delete_pending_intake|pendingSdfDossierPurgeRequest/);
  assert.match(source, /detail\.dossier_lifecycle\?\.state === "TRASHED"/);
  assert.match(source, /reeds een offerte aan dit dossier gekoppeld/);
  assert.match(source, /detailColumn\.append\([\s\S]*data-dossiers-lifecycle-panel[\s\S]*data-dossiers-pending-actions/);

  const substance = {
    quote_request_id: item.quote_request_id,
    request_kind: "website",
    request: { reference: "#F4300000", requested_at: "2026-09-03T01:00:00Z", requested_service: "Website", original_text: "Authority text" },
    customer: { name: "Synthetic", company: null, email: "synthetic@example.test", phone: null },
    intake: { intake_id: item.intake_id, status: "invited", invited_at: "2026-09-03T01:01:00Z", started_at: null, submitted_at: null, structured_answers: { shop_required: false } },
    documents: { customer_request_count: 0, uploaded_document_count: 0 },
  };
  const summary = { kind: "pending", reference: "#F4300000", name: "Synthetic", raw: { ...item, support_reference: "#F4300000", request_kind: "website", intake_status: "invited", website_type: "Website op maat" } };
  const invitedCopy = pendingDossierCopy(summary, substance);
  assert.equal(invitedCopy.status, "invited");
  assert.equal(invitedCopy.request.originalText, "Authority text");
  const inProgressCopy = pendingDossierCopy(
    { ...summary, raw: { ...summary.raw, intake_status: "in_progress" } },
    { ...substance, intake: { ...substance.intake, status: "in_progress", started_at: "2026-09-03T01:02:00Z" } },
  );
  assert.equal(inProgressCopy.status, "in_progress");
  assert.equal(inProgressCopy.intake.startedAt, "2026-09-03T01:02:00Z");
  assert.throws(
    ()=>pendingDossierCopy(summary, { ...substance, intake: { ...substance.intake, status: "in_progress" } }),
    /INVALID_PENDING_DOSSIER_COPY/,
  );
  assert.match(source, /target\.dataset\.dossiersCopy === "view"[\s\S]*renderApplicationDossier[\s\S]*showModal\(\)/);
  assert.match(source, /target\.dataset\.dossiersCopy === "download"[\s\S]*downloadApplicationDossierPdf\(copySource\)/);
  assert.match(source, /printApplicationDossier\(copySource\)/);
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
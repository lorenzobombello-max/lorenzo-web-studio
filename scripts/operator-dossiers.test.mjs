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
  assert.doesNotMatch(source, /from ["'][^"']*(?:operator-dashboard|application-dossier|sdf-qualification|website)[^"']*["']/i);
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

test("Dossiers initializer mounts and dispose clears sensitive DOM", async () => {
  const { initializeOperatorDossiers } = await import("../assets/js/operator-dossiers.mjs");
  const workspace = {
    dataset: {},
    removeAttribute(name) { if (name === "data-dossiers-mounted") delete this.dataset.dossiersMounted; },
    replaceChildren() { this.cleared = true; },
  };
  const controller = initializeOperatorDossiers(
    { querySelector: ()=>workspace },
    { rpc() {} },
    { role: "operator", status: "ACTIVE" },
  );
  assert.equal(workspace.dataset.dossiersMounted, "true");
  assert.equal(typeof controller.dispose, "function");
  controller.dispose();
  assert.equal(workspace.dataset.dossiersMounted, undefined);
  assert.equal(workspace.cleared, true);
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
  assert.deepEqual(dossierListRequest({ search: " Lorenzo " }), {
    action: "list_applications_v2", zone: "ACTIVE_ARCHIVED", operational_status: null,
    year: null, quarter: null, request_kind: null, search: "Lorenzo", cursor: null, limit: 50,
  });
  assert.deepEqual(dossierLifecycleRequest("archive_dossier", detail, " Gereed ", "20000000-0000-4000-8000-000000000002"), {
    action: "archive_dossier", quote_request_id: detail.quote_request_id, expected_revision: 4,
    idempotency_key: "20000000-0000-4000-8000-000000000002", reason: "Gereed",
  });
  assert.equal(dossierAssignmentRequest(detail, { revision: 0, assignee_operator_id: null }, "30000000-0000-4000-8000-000000000003", "", "40000000-0000-4000-8000-000000000004").action, "assign_dossier");
  assert.deepEqual(dossierDocumentRequest(detail), { action: "get_dossier_document_manifest", quote_request_id: detail.quote_request_id });
  await authority.gateway(dossierListRequest());
  assert.equal(calls[0].name, "commercial-operator-command");
  await assert.rejects(()=>authority.gateway({ action: "list_pending_intakes" }), /DOSSIER_ACTION_NOT_ALLOWED/);
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
  assert.deepEqual(dossierPurgeEligibilityRequest({ quote_request_id: quoteRequestId, request_kind: "website", dossier_lifecycle: { state: "ACTIVE" } }), {
    name: "can_purge_dossier_v1", parameters: { p_quote_request_id: quoteRequestId },
  });
  assert.equal(dossierPurgeRequest({
    quote_request_id: quoteRequestId,
    request_kind: "slimme_documentenflow",
    dossier_lifecycle: { state: "ACTIVE" },
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
});
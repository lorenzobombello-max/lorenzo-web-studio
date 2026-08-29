import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { applicationIdentityPresentation, applicationLocatorFromUrl, applicationReferenceFromUrl, applyDetailVisibility, appendUniqueCustomerRequestItems, appendUniqueOperatorItems, appendUniquePersonalQueueItems, assignmentError, assignmentPresentation, buildAssignmentCommand, buildDossierLifecycleCommand, buildIntakeLifecycleCommand, businessExpenseAmountMinor, businessExpenseCategoryLabel, businessExpenseCreateRequest, businessExpenseFinancePortfolioPresentation, businessExpenseRelationLabel, canIssueApprovedQuotation, canOfferDossierPurge, canPromoteApplication, createBusinessExpenseEntryController, createCustomerRequestDetailController, createCustomerRequestListController, createDocumentInboxCommandController, createInternalSmokeBSyntheticPng, createInternalSmokeOneShotTrigger, createOperatorListController, createPersonalQueueController, currentOperatorIdentityPresentation, customerCorePresentation, customerRequestDetailRequest, customerRequestTransitionRequest, customerRequestUploadCreateRequest, customerRequestUploadRevokeRequest, customerRequestsForDossierRequest, customerRequestWorkCommand, DOCUMENT_INBOX_CATEGORIES, DOCUMENT_INBOX_DOCUMENT_TYPES, DOCUMENT_INBOX_STATUSES, documentInboxApproveRequest, documentInboxConfirmRequest, documentInboxFilter, documentInboxProcessRequest, documentInboxProposalRequest, documentInboxReadPresentation, documentInboxRejectRequest, documentInboxStatusPresentation, dossierLifecycleAction, dossierLifecycleError, dossierLifecyclePresentation, dossierPurgeRequest, dossierReferenceFromDetail, effectiveOperatorZone, financeMilestoneStatus, financeTabFromUrl, focusDossierLifecycle, focusIntakeLifecycle, formatFinanceMoney, intakeLifecycleError, intakeLifecyclePresentation, internalSmokeAvailable, nextWorkflowStage, normalizeSupportReference, operatorFacetsRequest, operatorListRequest, operatorListVisibility, operatorModuleFromUrl, operatorStatusPresentation, personalQueueRequest, projectSitePresentation, quotationDeliveryPresentation, quotationIssuanceRequest, refreshAfterOperatorMutation, refreshOperatorSelection, resolveDashboardAuthority, runInternalSmokeA, runInternalSmokeB, sdfFinancePortfolioPresentation, sdfM1InvoiceCandidatePresentation, sdfPackageLabel, sdfPricingPresentation, sdfProjectPresentation, sdfQuotationPresentation, validateCustomerRequestDetail, websiteFinancePortfolioPresentation } from "../assets/js/operator-dashboard.js";
import { businessExpenseDocumentLinkRequest, createDocumentInboxUploadController, createSupplierDocumentExpenseLinkController, documentInboxReceiveRequest, documentInboxUploadResponse, SUPPLIER_DOCUMENT_ACCEPT, SUPPLIER_DOCUMENT_MAX_BYTES, SUPPLIER_DOCUMENT_RELATION_TYPES, SUPPLIER_DOCUMENT_TYPES, supplierDocumentCreateRequest, supplierDocumentFileError, supplierDocumentUploadResponse } from "../assets/js/operator-dashboard.js";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");
const OPERATOR_ASSET_RELEASE = "20260829-finance-inbox-upload-ui";
const PREVIOUS_OPERATOR_ASSET_RELEASE = "20260829-finance-expense-link-ui";

test("all operator dialogs use one exclusive responsive modal type authority", async () => {
  const [html, css] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/css/operator-dashboard.css"),
  ]);
  const expectedTypes = new Map([
    ["applicationDossierPreview", "operator-modal--reading"],
    ["documentInboxDialog", "operator-modal--reading"],
    ["documentInboxUploadDialog", "operator-modal--work"],
    ["businessExpenseDialog", "operator-modal--work"],
    ["supplierDocumentDialog", "operator-modal--work"],
    ["promotionDialog", "operator-modal--compact"],
    ["lifecycleDialog", "operator-modal--action-confirm"],
    ["dossierLifecycleDialog", "operator-modal--action-confirm"],
    ["dossierPurgeDialog", "operator-modal--action-confirm"],
  ]);
  const dialogs = [...html.matchAll(/<dialog\b[^>]*>/g)].map(([tag])=>({
    tag,
    id: tag.match(/\bid="([^"]+)"/)?.[1],
  }));
  assert.equal(dialogs.length, expectedTypes.size);
  for (const { tag, id } of dialogs) {
    const classes = tag.match(/\bclass="([^"]*)"/)?.[1].split(/\s+/) || [];
    const modalTypes = classes.filter((name)=>name.startsWith("operator-modal--"));
    assert.deepEqual(modalTypes, [expectedTypes.get(id)], `${id} must have its one approved modal type`);
  }
  assert.match(css, /dialog\.operator-modal--reading \{ width:min\(85vw,118rem\); \}/);
  assert.match(css, /dialog\.operator-modal--work \{ width:90vw; \}/);
  assert.doesNotMatch(css, /dialog\.operator-modal--work \{[^}]*128rem/);
  assert.match(css, /dialog\.operator-modal--compact \{ width:min\(34rem,calc\(100vw - 2rem\)\); \}/);
  assert.match(css, /dialog\.operator-modal--action-confirm \{ width:68vw; \}/);
  assert.doesNotMatch(css, /dialog\.operator-modal--action-confirm \{[^}]*92rem/);
  assert.match(css, /@media \(min-width:2000px\) \{[\s\S]*?dialog\.operator-modal--reading \{ width:min\(90vw,128rem\); \}/);
  assert.match(css, /@media \(min-width:2000px\) \{[\s\S]*?:is\(\.operator-modal--reading,\.operator-modal--work\) \.finance-modal-brand img \{ width:clamp/);
  assert.match(css, /@media \(min-width:2000px\) \{[\s\S]*?:is\(\.operator-modal--reading,\.operator-modal--work\) :is\(input,select,textarea\) \{ min-height:clamp/);
  assert.match(css, /@media \(min-width:2000px\) \{[\s\S]*?#documentInboxUploadDialog \.document-inbox-upload-zone \{ min-height:clamp/);
  assert.match(css, /\.operator-modal--action-confirm \.confirmation__field textarea \{ min-height:clamp/);
  assert.match(css, /dialog\.operator-modal--reading,dialog\.operator-modal--work,dialog\.operator-modal--compact,dialog\.operator-modal--action-confirm \{ max-width:calc\(100vw - 4rem\); max-height:calc\(100dvh - 2rem\); \}/);
  assert.match(css, /@media \(max-width:900px\) \{ dialog\.operator-modal--reading,dialog\.operator-modal--work,dialog\.operator-modal--action-confirm \{ width:calc\(100vw - 1\.5rem\); max-width:none; \} \}/);
  assert.match(css, /@media \(max-width:540px\) \{ dialog\.operator-modal--reading,dialog\.operator-modal--work,dialog\.operator-modal--compact,dialog\.operator-modal--action-confirm \{ width:calc\(100vw - 1rem\); max-width:none; max-height:calc\(100dvh - 1rem\); \}/);
  for (const selector of ["#businessExpenseDialog", "#documentInboxUploadDialog", ".business-expense-dialog", ".supplier-document-dialog", ".document-inbox-dialog", ".dossier-preview-dialog"]) {
    assert.doesNotMatch(css, new RegExp(`${selector.replace(/[.#]/g, "\\$&")} \\{[^}]*\\bwidth:`));
  }
  assert.doesNotMatch(css, /(?:^|\n)dialog \{[^}]*\bwidth:/);
});

test("operator dashboard assets share one versioned Pages-compatible release identity", async () => {
  const [html, guard, prepare, verify] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard-guard.mjs"),
    read("scripts/prepare-pages-dist.ps1"),
    read("scripts/verify-pages-dist.ps1"),
  ]);
  const cssUrl = html.match(/href="([^"]*operator-dashboard\.css[^"]*)"/)?.[1];
  const guardUrl = html.match(/src="([^"]*operator-dashboard-guard\.mjs[^"]*)"/)?.[1];
  const dashboardUrl = guard.match(/from "([^"]*operator-dashboard\.js[^"]*)"/)?.[1];
  assert.deepEqual([cssUrl, guardUrl, dashboardUrl], [
    `/assets/css/operator-dashboard.css?v=${OPERATOR_ASSET_RELEASE}`,
    `/assets/js/operator-dashboard-guard.mjs?v=${OPERATOR_ASSET_RELEASE}`,
    `./operator-dashboard.js?v=${OPERATOR_ASSET_RELEASE}`,
  ]);
  for (const url of [cssUrl, guardUrl, dashboardUrl]) {
    assert.equal(new URL(url, "https://operator.example/").searchParams.get("v"), OPERATOR_ASSET_RELEASE);
    assert.doesNotMatch(url, /20260824-lifecycle-ui/);
    assert.doesNotMatch(url, new RegExp(PREVIOUS_OPERATOR_ASSET_RELEASE));
  }
  assert.match(guardUrl, /^\/assets\/js\/operator-dashboard-guard\.mjs\?v=/);
  assert.match(dashboardUrl, /^\.\/operator-dashboard\.js\?v=/);
  assert.match(prepare, /"assets\/css\/operator-dashboard\.css"/);
  assert.match(prepare, /"assets\/js\/operator-dashboard-guard\.mjs"/);
  assert.match(prepare, /"assets\/js\/operator-dashboard\.js"/);
  assert.match(verify, /\$clean = \(\$clean -split '\\\?'\)\[0\]/);
});

test("operator shell links to the canonical dashboard route", async () => {
  const source = await read("operator/index.html");
  assert.match(source, /href="\/operator\/dashboard\/"/);
});

test("dashboard remains hidden until the authorization guard succeeds", async () => {
  const source = await read("operator/dashboard/index.html");
  assert.match(source, /id="operatorDashboard" hidden/);
  assert.match(source, /operator-dashboard-guard\.mjs/);
});

test("dashboard preserves the locked Lorenzo Web Solutions branding", async () => {
  const source = await read("operator/dashboard/index.html");
  assert.match(source, /lorenzo-web-solution-logo-transparent\.png/);
  assert.match(source, /class="identity__mark"/);
  assert.match(source, /<strong>Lorenzo Web Solutions<\/strong>/);
  assert.doesNotMatch(source, />LW<\/|lw-badge/i);
});

test("dashboard guard requires database-backed operator authorization", async () => {
  const source = await read("assets/js/operator-dashboard-guard.mjs");
  assert.match(source, /requireAuthorizedOperator/);
  assert.match(source, /access\.status === "unauthenticated"/);
  assert.match(source, /access\.status === "unauthorized"/);
  assert.match(source, /startOperatorDashboard/);
  assert.match(source, /functionsBaseUrl/);
  assert.doesNotMatch(source, /operator-dashboard-contract\.js/);
  assert.match(source, /dashboard\.hidden = false/);
});

test("session shell uses the same database-backed authorization", async () => {
  const source = await read("assets/js/operator-shell.mjs");
  assert.match(source, /requireAuthorizedOperator/);
  assert.doesNotMatch(source, /requireOperatorSession/);
});

test("production dashboard uses real application data and no synthetic state", async () => {
  const [html, contract, script, css] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard-contract.js"),
    read("assets/js/operator-dashboard.js"),
    read("assets/css/operator-dashboard.css"),
  ]);
  assert.match(html, /id="applicationList"/);
  assert.match(html, /id="applicationDetail"/);
  assert.match(html, /id="promoteApplication"/);
  assert.match(html, /id="pricingDossier"/);
  assert.match(html, /id="documentsDossier"/);
  assert.match(html, /id="paymentDossier"/);
  assert.match(html, /id="auditTimeline"/);
  assert.doesNotMatch(html, /href=[^>]*(download|document)/i);
  assert.doesNotMatch(html, /Synthetic Project|TEST-LWS-OFF/);
  assert.match(contract, /LWS_DASHBOARD_CONTRACT/);
  assert.match(contract, /createScenario/);
  assert.match(script, /list_applications/);
  assert.match(script, /get_application_detail/);
  assert.match(script, /promote_accepted_application/);
  assert.match(script, /get_project_dossier/);
  assert.match(script, /requestId !== detailRequestId/);
  assert.match(script, /gereconcilieerd.*laatste:/);
  assert.doesNotMatch(script, /localStorage|lws-phase5d-synthetic-state-v1|LWS_DASHBOARD_CONTRACT/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
  assert.match(css, /\.dashboard-grid/);
  assert.match(css, /\.application-list/);
});

test("quotation issuance control is owner-admin gated and sends no client authority", async () => {
  const quoteRequestId = "a1800000-0000-4000-8000-000000000002";
  const approvalId = "a1800000-0000-4000-8000-000000000003";
  const detail = {
    request_kind: "website",
    quote_request_id: quoteRequestId,
    quotation: { approval_id: approvalId, issuance_status: null },
    acceptance: null,
  };
  assert.equal(canIssueApprovedQuotation(detail, { role: "owner", status: "ACTIVE" }), true);
  assert.equal(canIssueApprovedQuotation(detail, { role: "admin", status: "ACTIVE" }), true);
  assert.equal(canIssueApprovedQuotation({ ...detail, quotation: { ...detail.quotation, issuance_status: "ISSUED" } }, { role: "owner", status: "ACTIVE" }), true);
  assert.equal(canIssueApprovedQuotation(detail, { role: "operator", status: "ACTIVE" }), false);
  assert.equal(canIssueApprovedQuotation({ ...detail, acceptance: { acceptance_id: approvalId } }, { role: "owner", status: "ACTIVE" }), false);
  assert.deepEqual(quotationIssuanceRequest(detail), {
    action: "issue_and_deliver_approved_quotation",
    quote_request_id: quoteRequestId,
  });
  assert.equal(quotationIssuanceRequest({ ...detail, quote_request_id: "bad" }), null);

  const [html, script] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard.js"),
  ]);
  assert.match(html, /id="quotationIssueAndDeliver"[^>]*hidden/);
  assert.match(html, /id="quotationActionMessage"[^>]*role="status"/);
  assert.match(script, /quotationIssuanceRequest\(selectedDetail\)/);
  assert.doesNotMatch(script, /issue_and_deliver_approved_quotation[\s\S]{0,160}idempotency_key/);
});

test("quotation delivery presentation preserves persisted and action status semantics", async () => {
  assert.deepEqual(quotationDeliveryPresentation({ status: "sent" }), {
    status: "sent", label: "Offerte verzonden", tone: "green",
  });
  assert.deepEqual(quotationDeliveryPresentation({ status: "retry_wait" }), {
    status: "retry_wait", label: "Verzending tijdelijk mislukt — nieuwe poging mogelijk", tone: "amber",
  });
  assert.deepEqual(quotationDeliveryPresentation({ status: "failed" }), {
    status: "failed", label: "Verzending mislukt — manuele controle vereist", tone: "red",
  });
  assert.equal(quotationDeliveryPresentation(null), null);
  assert.doesNotMatch(quotationDeliveryPresentation({ status: "retry_wait" }).label, /manuele controle/i);
  assert.doesNotMatch(quotationDeliveryPresentation({ status: "failed" }).label, /nieuwe poging/i);

  const [html, script] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard.js"),
  ]);
  assert.match(html, /id="detailQuotationDelivery"/);
  assert.match(script, /quotationDeliveryPresentation\(application\.quotation\?\.delivery\)/);
  assert.match(script, /quotationDeliveryPresentation\(\{ status: result\.delivery_status \}\)/);
});

const personalQueueItem = (reference, revision = 1) => ({
  reference,
  source: "website",
  zone: "ACTIVE",
  status: "SUBMITTED",
  assigned_at: "2099-01-03T11:00:00Z",
  assignment_revision: revision,
});

test("personal queue request is caller-scoped and uses the bounded default", () => {
  assert.deepEqual(personalQueueRequest(), { action: "get_my_assigned_dossiers", limit: 25 });
  assert.deepEqual(personalQueueRequest("aabb"), { action: "get_my_assigned_dossiers", limit: 25, cursor: "aabb" });
  for (const forbidden of ["operator_id", "assignee_operator_id", "auth_user_id", "role", "status"]) {
    assert.equal(Object.hasOwn(personalQueueRequest(), forbidden), false);
  }
});

test("personal queue accepts only the exact safe projection and removes duplicates", () => {
  const first = personalQueueItem("LWS-AAN-2099-0001");
  assert.deepEqual(appendUniquePersonalQueueItems([first], [first, personalQueueItem("#F98B2F08")]).map((item)=>item.reference), ["LWS-AAN-2099-0001", "#F98B2F08"]);
  assert.throws(()=>appendUniquePersonalQueueItems([], [{ ...first, name: "Verboden klantveld" }]), /INVALID_PERSONAL_QUEUE/);
  assert.throws(()=>appendUniquePersonalQueueItems([], [{ ...first, email: "verboden@example.test" }]), /INVALID_PERSONAL_QUEUE/);
});

test("personal queue load-more appends by next cursor and busy guard blocks overlap", async () => {
  const requests = [];
  let releaseFirst;
  const firstPage = new Promise((resolve)=>{ releaseFirst = resolve; });
  const controller = createPersonalQueueController(async (request)=>{
    requests.push(request);
    if (requests.length === 1) return await firstPage;
    return { items: [personalQueueItem("#F98B2F08")], has_more: false, next_cursor: null };
  });
  const firstLoad = controller.load();
  assert.equal(await controller.load(), false);
  releaseFirst({ items: [personalQueueItem("LWS-AAN-2099-0001")], has_more: true, next_cursor: "aabb" });
  assert.equal(await firstLoad, true);
  assert.equal(await controller.loadMore(), true);
  assert.deepEqual(requests, [personalQueueRequest(), personalQueueRequest("aabb")]);
  assert.deepEqual(controller.state.items.map((item)=>item.reference), ["LWS-AAN-2099-0001", "#F98B2F08"]);
  assert.equal(await controller.loadMore(), false);
  assert.equal(requests.length, 2);
});

test("personal queue refresh clears pagination and replaces the queue", async () => {
  const requests = [];
  const controller = createPersonalQueueController(async (request)=>{
    requests.push(request);
    return requests.length === 1
      ? { items: [personalQueueItem("LWS-AAN-2099-0001")], has_more: true, next_cursor: "aabb" }
      : { items: [personalQueueItem("#F98B2F08", 2)], has_more: false, next_cursor: null };
  });
  await controller.load();
  await controller.refresh();
  assert.deepEqual(requests, [personalQueueRequest(), personalQueueRequest()]);
  assert.deepEqual(controller.state.items.map((item)=>item.reference), ["#F98B2F08"]);
  assert.equal(controller.state.next_cursor, null);
});

test("personal queue workspace renders safe selectable dossier information", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  const workspace = html.match(/<section id="personalQueueWorkspace"[\s\S]*?<\/section>\s*<div id="managerWorkspace"/)?.[0] || "";
  const renderer = script.match(/function renderPersonalQueue\(items\) \{[\s\S]*?\n  \}\n\n  const personalQueueController/)?.[0] || "";
  assert.match(workspace, /Mijn dossiers/);
  assert.match(workspace, /id="personalQueueList"/);
  assert.match(workspace, /Er zijn momenteel geen dossiers aan jou toegewezen\./);
  assert.match(workspace, />Vernieuwen</);
  assert.match(workspace, />Meer laden</);
  assert.doesNotMatch(workspace, /organisatie|e-mail|contact|uuid|history/i);
  assert.doesNotMatch(workspace, /href=|Open dossier|get_application_detail/);
  assert.match(script, /reference\.textContent = dossier\.reference/);
  assert.match(script, /badge\(dossier\.status\), badge\(dossier\.zone\)/);
  assert.match(script, /formatDate\(dossier\.assigned_at\)/);
  assert.doesNotMatch(renderer, /get_application_detail|get_operator_application_v1|support_reference/);
});

const customerRequestListItem = (requestId, revision = 1) => ({
  request_id: requestId, request_reference: "LWS-VRZ-2099-0001", request_type: "OTHER",
  title: "Operationele vraag", status: "TRIAGED", priority: "NORMAL",
  submitted_at: "2099-01-03T11:00:00Z", updated_at: "2099-01-03T11:30:00Z", revision,
});
const customerRequestDetail = (requestId, status = "TRIAGED", revision = 1) => ({
  ...customerRequestListItem(requestId, revision), status, source: "OPERATOR", description: "Operationele omschrijving.", upload_request: null,
});

test("Customer Requests builders expose no client authority or commercial identifiers", () => {
  const requestId = "a1800000-0000-4000-8000-000000000070";
  assert.deepEqual(customerRequestsForDossierRequest("LWS-AAN-2099-0001"), {
    action: "list_customer_requests_for_dossier", dossier_reference: "LWS-AAN-2099-0001", limit: 25,
  });
  assert.deepEqual(customerRequestDetailRequest(requestId), { action: "get_customer_request", request_id: requestId });
  assert.deepEqual(customerRequestTransitionRequest(customerRequestDetail(requestId), "START", "a1800000-0000-4000-8000-000000000071"), {
    action: "transition_customer_request", request_id: requestId, command_type: "START", expected_revision: 1,
    idempotency_key: "a1800000-0000-4000-8000-000000000071",
  });
  for (const request of [customerRequestsForDossierRequest("LWS-AAN-2099-0001"), customerRequestDetailRequest(requestId)]) {
    for (const forbidden of ["operator_id", "role", "access_level", "customer_id", "project_id", "quote_request_id"]) {
      assert.equal(Object.hasOwn(request, forbidden), false);
    }
  }
});

test("Customer Requests projections are exact and work controls are status-bound", () => {
  const requestId = "a1800000-0000-4000-8000-000000000070";
  assert.deepEqual(appendUniqueCustomerRequestItems([], [customerRequestListItem(requestId)]), [customerRequestListItem(requestId)]);
  assert.throws(()=>appendUniqueCustomerRequestItems([], [{ ...customerRequestListItem(requestId), customer_id: requestId }]), /INVALID_CUSTOMER_REQUEST_LIST/);
  assert.deepEqual(validateCustomerRequestDetail(customerRequestDetail(requestId)), customerRequestDetail(requestId));
  assert.throws(()=>validateCustomerRequestDetail({ ...customerRequestDetail(requestId), amount: 100 }), /INVALID_CUSTOMER_REQUEST_DETAIL/);
  assert.deepEqual(["NEW", "TRIAGED", "IN_PROGRESS", "WAITING_CUSTOMER", "RESOLVED"].map(customerRequestWorkCommand), [null, "START", "REQUIRE_CUSTOMER_RESPONSE", "RESUME", null]);
});

test("Customer Request upload-link builders expose only capability authority", () => {
  const requestId = "a1800000-0000-4000-8000-000000000070";
  const uploadRequestId = "a1800000-0000-4000-8000-000000000071";
  const idempotencyKey = "a1800000-0000-4000-8000-000000000072";
  assert.deepEqual(customerRequestUploadCreateRequest(requestId, idempotencyKey), {
    action: "create_customer_request_upload_link", request_id: requestId, idempotency_key: idempotencyKey,
  });
  assert.deepEqual(customerRequestUploadRevokeRequest(uploadRequestId, idempotencyKey), {
    action: "revoke_customer_request_upload_link", upload_request_id: uploadRequestId,
    reason: "Operator heeft de uploadlink ingetrokken.", idempotency_key: idempotencyKey,
  });
});

test("Customer Request upload URL exists only in controller memory until revoke or selection change", async () => {
  const requestId = "a1800000-0000-4000-8000-000000000070";
  const uploadRequestId = "a1800000-0000-4000-8000-000000000071";
  const token = "A".repeat(43);
  const calls = [];
  const controller = createCustomerRequestDetailController(async (input)=>{
    calls.push(input);
    if (input.action === "get_customer_request") return customerRequestDetail(requestId);
    if (input.action === "create_customer_request_upload_link") return {
      state: "ACTIVE", upload_request_id: uploadRequestId, expires_at: "2099-01-04T11:00:00Z",
      was_created: true, upload_url: `https://lorenzowebsolutions.be/pages/customer-request-upload.html#token=${token}`,
    };
    return { state: "REVOKED", upload_request_id: uploadRequestId, was_revoked: true };
  }, ()=>{}, ()=>"a1800000-0000-4000-8000-000000000072");
  await controller.selectRequest(requestId);
  assert.equal(await controller.createUploadLink(), true);
  assert.equal(controller.state.upload_url.endsWith(`#token=${token}`), true);
  assert.equal(controller.state.request.upload_request.upload_request_id, uploadRequestId);
  assert.equal(await controller.revokeUploadLink(), true);
  assert.equal(controller.state.upload_url, null);
  assert.equal(controller.state.request.upload_request, null);
  await controller.selectRequest(requestId);
  assert.equal(controller.state.upload_url, null);
  assert.equal(calls.some((input)=>Object.hasOwn(input, "upload_url") || Object.hasOwn(input, "token")), false);
});

test("dossier generation suppresses stale Customer Requests pages", async () => {
  const requests = [];
  const releases = [];
  const controller = createCustomerRequestListController((request)=>{
    requests.push(request);
    return new Promise((resolve)=>releases.push(resolve));
  });
  const first = controller.selectDossier("LWS-AAN-2099-0001");
  const second = controller.selectDossier("LWS-AAN-2099-0002");
  releases[0]({ items: [customerRequestListItem("a1800000-0000-4000-8000-000000000070")], has_more: false, next_cursor: null });
  assert.equal(await first, false);
  releases[1]({ items: [customerRequestListItem("a1800000-0000-4000-8000-000000000071")], has_more: false, next_cursor: null });
  assert.equal(await second, true);
  assert.equal(controller.state.dossier_reference, "LWS-AAN-2099-0002");
  assert.deepEqual(controller.state.items.map((item)=>item.request_id), ["a1800000-0000-4000-8000-000000000071"]);
  assert.deepEqual(requests, [customerRequestsForDossierRequest("LWS-AAN-2099-0001"), customerRequestsForDossierRequest("LWS-AAN-2099-0002")]);
});

test("request generation and concurrency failures fail closed", async () => {
  const firstId = "a1800000-0000-4000-8000-000000000070";
  const secondId = "a1800000-0000-4000-8000-000000000071";
  const releases = [];
  const staleController = createCustomerRequestDetailController(()=>new Promise((resolve)=>releases.push(resolve)));
  const first = staleController.selectRequest(firstId);
  const second = staleController.selectRequest(secondId);
  releases[0](customerRequestDetail(firstId));
  assert.equal(await first, false);
  releases[1](customerRequestDetail(secondId));
  assert.equal(await second, true);
  assert.equal(staleController.state.request.request_id, secondId);

  let calls = 0;
  const concurrencyController = createCustomerRequestDetailController(async ()=>{
    calls += 1;
    if (calls === 1) return customerRequestDetail(firstId);
    throw new Error("CONCURRENT_MODIFICATION");
  }, ()=>{}, ()=>"a1800000-0000-4000-8000-000000000072");
  await concurrencyController.selectRequest(firstId);
  assert.equal(await concurrencyController.transition("START"), false);
  assert.equal(concurrencyController.state.request, null);
  assert.equal(concurrencyController.state.error, "CONCURRENT_MODIFICATION");
});

test("Customer Requests UI stays inside personal workspace and exposes work actions only", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  const personal = html.split('<section id="personalQueueWorkspace"')[1]?.split('<div id="managerWorkspace"')[0] || "";
  assert.match(personal, /id="customerRequestList"/);
  assert.match(personal, /id="customerRequestDetail"/);
  assert.match(personal, /data-customer-request-command="START"/);
  assert.match(personal, /data-customer-request-command="REQUIRE_CUSTOMER_RESPONSE"/);
  assert.match(personal, /data-customer-request-command="RESUME"/);
  assert.match(personal, /id="customerRequestUploadCreate"/);
  assert.match(personal, /id="customerRequestUploadCopy"[^>]+hidden/);
  assert.match(personal, /id="customerRequestUploadRevoke"[^>]+hidden/);
  assert.doesNotMatch(personal, /TRIAGE|RESOLVE|CANCEL|SIGNAL_SCOPE_IMPACT|ACCEPT_CHANGE_ORDER|factuur|offerte|prijs/i);
  assert.match(script, /customerRequestDetailController\.clear\(\);\s*customerRequestListController\.selectDossier\(dossier\.reference\)/);
  assert.doesNotMatch(script, /service_role|SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(script, /localStorage|sessionStorage|document\.cookie/);
});

test("personal queue routing is server-result-driven and fails closed", async () => {
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /loadManagerAuthority: \(\)=>listController\.load\(\)/);
  assert.match(script, /if \(dashboardRoute !== "manager"\) return;\s*personalQueueWorkspace\.hidden = true;\s*managerWorkspace\.hidden = false/);
  assert.match(script, /De dossiers konden niet worden geladen\. Probeer het later opnieuw\./);
  assert.match(script, /callOperator\(client, functionsBaseUrl, input\)/);
  assert.equal((script.match(/client\.rpc\(/g) || []).length, 15);
  assert.match(script, /client\.rpc\("get_document_inbox_v1", \{ p_lifecycle_status: null, p_record_classification: "production" \}\)/);
  assert.match(script, /client\.rpc\("get_website_finance_portfolio_v1"\)/);
  assert.match(script, /client\.rpc\("get_sdf_finance_portfolio_v1"\)/);
  assert.match(script, /client\.rpc\("create_supplier_document_v1", request\)/);
  assert.match(script, /client\.rpc\("link_business_expense_document_v1", request\)/);
  assert.match(script, /client\.rpc\("transition_customer_request_v1"/);
  assert.match(script, /client\.rpc\("can_purge_dossier_v1"/);
  assert.match(script, /client\.rpc\("purge_dossier_v1"/);
  assert.doesNotMatch(script, /localStorage/);
});

test("dashboard authority resolver keeps operator success out of manager flow", async () => {
  let managerCalls = 0;
  const route = await resolveDashboardAuthority({
    loadPersonalQueue: async ()=>true,
    getPersonalQueueError: ()=>null,
    loadManagerAuthority: async ()=>{ managerCalls += 1; return true; },
  });
  assert.equal(route, "personal");
  assert.equal(managerCalls, 0);
});

test("dashboard authority resolver requires a separate successful manager proof", async () => {
  let managerVisible = false;
  let managerDataRendered = false;
  const route = await resolveDashboardAuthority({
    loadPersonalQueue: async ()=>false,
    getPersonalQueueError: ()=>"OPERATOR_NOT_AUTHORIZED",
    loadManagerAuthority: async ()=>{
      assert.equal(managerVisible, false);
      managerDataRendered = true;
      return true;
    },
  });
  assert.equal(route, "manager");
  assert.equal(managerVisible, false);
  assert.equal(managerDataRendered, true);
  if (route === "manager") managerVisible = true;
  assert.equal(managerVisible, true);
});

test("dashboard authority resolver fails closed for every unproven manager response", async () => {
  for (const code of ["AUTHENTICATION_REQUIRED", "OPERATOR_NOT_AUTHORIZED", "INTERNAL_ERROR"]) {
    const route = await resolveDashboardAuthority({
      loadPersonalQueue: async ()=>false,
      getPersonalQueueError: ()=>"OPERATOR_NOT_AUTHORIZED",
      loadManagerAuthority: async ()=>{ throw new Error(code); },
    });
    assert.equal(route, "closed", `manager ${code} must fail closed`);
  }
  const disabledOrRevoked = await resolveDashboardAuthority({
    loadPersonalQueue: async ()=>false,
    getPersonalQueueError: ()=>"OPERATOR_NOT_AUTHORIZED",
    loadManagerAuthority: async ()=>false,
  });
  assert.equal(disabledOrRevoked, "closed");
});

test("personal authentication and server failures never start a manager probe", async () => {
  for (const personalError of ["AUTHENTICATION_REQUIRED", "INVALID_JWT", "INTERNAL_ERROR", "OPERATOR_REQUEST_FAILED"]) {
    let managerCalls = 0;
    const route = await resolveDashboardAuthority({
      loadPersonalQueue: async ()=>false,
      getPersonalQueueError: ()=>personalError,
      loadManagerAuthority: async ()=>{ managerCalls += 1; return true; },
    });
    assert.equal(route, "closed");
    assert.equal(managerCalls, 0, `personal ${personalError} must not probe manager authority`);
  }
});

test("personal queue loading, refresh, pagination, and manager separation are explicit", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="managerWorkspace" hidden/);
  assert.match(script, /"Dossiers laden…"/);
  assert.match(script, /"Meer dossiers laden…"/);
  assert.match(script, /personalQueueRefresh\.addEventListener\("click", \(\)=>\{[\s\S]*selectedDossierReference = null;[\s\S]*customerRequestListController\.clear\(\);[\s\S]*customerRequestDetailController\.clear\(\);[\s\S]*personalQueueController\.refresh\(\);[\s\S]*\}\)/);
  assert.match(script, /personalQueueLoadMore\.addEventListener\("click", \(\)=>personalQueueController\.loadMore\(\)\)/);
  assert.match(script, /personalQueueLoadMore\.hidden = !state\.has_more \|\| !state\.next_cursor/);
  assert.match(script, /personalQueueRefresh\.disabled = state\.loading/);
});

test("application reference query is the only accepted human locator", () => {
  assert.equal(applicationReferenceFromUrl("https://example.test/operator/dashboard/?application=LWS-AAN-2099-0001"), "LWS-AAN-2099-0001");
  assert.equal(applicationReferenceFromUrl("https://example.test/operator/dashboard/?application=bad"), null);
});

test("support references normalize safely and route separately from application references", () => {
  assert.equal(normalizeSupportReference(" f98b2f08 "), "#F98B2F08");
  assert.equal(normalizeSupportReference("#f98b2f08"), "#F98B2F08");
  assert.equal(normalizeSupportReference("F98B2F0"), null);
  assert.deepEqual(applicationLocatorFromUrl("https://example.test/operator/dashboard/?support=f98b2f08"), { support_reference: "#F98B2F08" });
});

test("application identity presents the human reference and routes with the existing reference contract", () => {
  const application = {
    application_reference: "LWS-AAN-2099-0401",
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
  };
  assert.deepEqual(applicationIdentityPresentation(application), {
    visibleReference: "LWS-AAN-2099-0401",
    locator: { application_reference: "LWS-AAN-2099-0401" },
  });
  assert.equal(application.quote_request_id, "a1100000-0000-4000-8000-000000000003");
});

test("application identity preserves the technical UUID fallback for legacy records", () => {
  const quoteRequestId = "a1100000-0000-4000-8000-000000000003";
  assert.deepEqual(applicationIdentityPresentation({ application_reference: null, quote_request_id: quoteRequestId }), {
    visibleReference: `Oudere aanvraag · ${quoteRequestId}`,
    locator: { quote_request_id: quoteRequestId },
  });
  assert.deepEqual(applicationIdentityPresentation({ application_reference: "invalid", quote_request_id: quoteRequestId }).locator, { quote_request_id: quoteRequestId });
});

test("application list and detail use the same human-readable identity presentation", async () => {
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /setText\("detailReference", applicationIdentityPresentation\(application\)\.visibleReference\)/);
  assert.match(script, /reference\.textContent = `\$\{applicationPresentation\.visibleReference\}/);
  assert.match(script, /const locator = applicationPresentation\.locator/);
});

test("promotion is visible only for accepted applications without a project", () => {
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: { acceptance_id: "accepted" }, project: null }), true);
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: null, project: null }), false);
  assert.equal(canPromoteApplication({ request_kind: "website", acceptance: { acceptance_id: "accepted" }, project: { project_id: "project" } }), false);
  assert.equal(canPromoteApplication({ request_kind: "slimme_documentenflow", acceptance: { acceptance_id: "unexpected" }, project: null }), false);
});

function intakeLifecycle(effectiveAccess, overrides = {}) {
  return {
    intake_id: "a1800000-0000-4000-8000-000000000030",
    access_state: effectiveAccess === "EXPIRED" ? "ACTIVE" : effectiveAccess,
    effective_access: effectiveAccess,
    access_token_expires_at: "2099-08-30T12:00:00Z",
    lifecycle_revision: 2,
    ...overrides,
  };
}

test("lifecycle actions follow only the authoritative effective state", () => {
  assert.deepEqual(intakeLifecyclePresentation(intakeLifecycle("ACTIVE")).actions, ["interrupt_intake", "cancel_intake"]);
  assert.deepEqual(intakeLifecyclePresentation(intakeLifecycle("INTERRUPTED")).actions, ["resume_intake", "cancel_intake"]);
  assert.deepEqual(intakeLifecyclePresentation(intakeLifecycle("EXPIRED")).actions, ["reactivate_intake"]);
  assert.deepEqual(intakeLifecyclePresentation(intakeLifecycle("CANCELLED")).actions, []);
  assert.equal(intakeLifecyclePresentation(intakeLifecycle("UNKNOWN")), null);
  assert.equal(intakeLifecyclePresentation(null), null);
});

test("lifecycle command sends revision and idempotency without token or expiry authority", () => {
  const command = buildIntakeLifecycleCommand(
    "interrupt_intake",
    intakeLifecycle("ACTIVE"),
    "  Klant vroeg om een tijdelijke pauze.  ",
    "a1800000-0000-4000-8000-000000000031",
  );
  assert.deepEqual(command, {
    action: "interrupt_intake",
    intake_id: "a1800000-0000-4000-8000-000000000030",
    expected_revision: 2,
    idempotency_key: "a1800000-0000-4000-8000-000000000031",
    reason: "Klant vroeg om een tijdelijke pauze.",
  });
  assert.equal(Object.hasOwn(command, "access_token"), false);
  assert.equal(Object.hasOwn(command, "expires_at"), false);
});

test("lifecycle command fails closed for blank reason and forbidden transitions", () => {
  assert.throws(()=>buildIntakeLifecycleCommand("interrupt_intake", intakeLifecycle("ACTIVE"), "   ", "a1800000-0000-4000-8000-000000000031"), /INVALID_LIFECYCLE_COMMAND/);
  assert.throws(()=>buildIntakeLifecycleCommand("resume_intake", intakeLifecycle("ACTIVE"), "Reden", "a1800000-0000-4000-8000-000000000031"), /INVALID_LIFECYCLE_COMMAND/);
  assert.throws(()=>buildIntakeLifecycleCommand("reactivate_intake", intakeLifecycle("CANCELLED"), "Reden", "a1800000-0000-4000-8000-000000000031"), /INVALID_LIFECYCLE_COMMAND/);
});

test("lifecycle errors request authoritative refresh without exposing internals", () => {
  assert.equal(intakeLifecycleError("CONCURRENT_MODIFICATION").refresh, true);
  assert.equal(intakeLifecycleError("COMMAND_REJECTED").refresh, true);
  assert.equal(intakeLifecycleError("IDEMPOTENCY_CONFLICT").refresh, true);
  assert.equal(intakeLifecycleError("INTAKE_NOT_FOUND").refresh, true);
  assert.equal(intakeLifecycleError("OPERATOR_NOT_AUTHORIZED").refresh, false);
  assert.doesNotMatch(intakeLifecycleError("internal SQL detail").message, /SQL|postgres|internal/i);
});

test("lifecycle UI uses one accessible dialog, busy guard, and authoritative reload", async () => {
  const [html, script] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard.js"),
  ]);
  assert.match(html, /id="lifecycleDossier"/);
  assert.match(html, /id="lifecycleDialog"[^>]*aria-labelledby="lifecycleDialogTitle"[^>]*aria-describedby="lifecycleDialogDescription"/);
  assert.match(html, /id="lifecycleReason"[^>]*maxlength="500"[^>]*required/);
  assert.doesNotMatch(html, /customer token|access token|access_token/i);
  assert.match(script, /if \(lifecycleBusy \|\|/);
  assert.match(script, /button\.disabled = lifecycleBusy/);
  assert.match(script, /crypto\.randomUUID\(\)/);
  assert.match(script, /refreshAfterOperatorMutation\([\s\S]{0,300}\(\)=>invoke\(input\)[\s\S]{0,300}\(\)=>detailRequestId/);
  assert.match(script, /if \(outcome\.refresh\) await loadDetail\(command\.locator\)/);
});

test("successful interrupt focuses the visible resume action instead of the hidden trigger", () => {
  const focused = [];
  const buttons = [
    { dataset: { lifecycleAction: "interrupt_intake" }, hidden: true, disabled: false, focus: ()=>focused.push("interrupt_intake") },
    { dataset: { lifecycleAction: "resume_intake" }, hidden: false, disabled: false, focus: ()=>focused.push("resume_intake") },
    { dataset: { lifecycleAction: "cancel_intake" }, hidden: false, disabled: false, focus: ()=>focused.push("cancel_intake") },
  ];
  const body = { focus: ()=>focused.push("body") };

  assert.equal(focusIntakeLifecycle(intakeLifecycle("INTERRUPTED"), buttons, body), buttons[1]);
  assert.deepEqual(focused, ["resume_intake"]);
});

test("successful cancellation focuses the visible lifecycle heading fallback", () => {
  const focused = [];
  const hiddenTrigger = { dataset: { lifecycleAction: "cancel_intake" }, hidden: true, disabled: false, focus: ()=>focused.push("cancel_intake") };
  const heading = { focus: ()=>focused.push("heading") };

  assert.equal(focusIntakeLifecycle(intakeLifecycle("CANCELLED"), [hiddenTrigger], heading), heading);
  assert.deepEqual(focused, ["heading"]);
});

function dossierDetail(state, revision = 3) {
  return {
    quote_request_id: "a1800000-0000-4000-8000-000000000040",
    dossier_lifecycle: { state, revision },
  };
}

test("assignment uses only canonical dossier references and authoritative read state", () => {
  assert.equal(dossierReferenceFromDetail({ application_reference: "LWS-AAN-2099-0001", support_reference: "#F98B2F08", quote_request_id: "a1800000-0000-4000-8000-000000000040" }), "LWS-AAN-2099-0001");
  assert.equal(dossierReferenceFromDetail({ support_reference: " f98b2f08 ", quote_request_id: "a1800000-0000-4000-8000-000000000040" }), "#F98B2F08");
  assert.equal(dossierReferenceFromDetail({ quote_request_id: "a1800000-0000-4000-8000-000000000040" }), null);
  assert.deepEqual(assignmentPresentation({ assignment_state: "UNASSIGNED", assignee_operator_id: null, assignee_display_name: null, revision: 2 }), { state: "UNASSIGNED", revision: 2, assigneeOperatorId: null, assigneeDisplayName: null });
  assert.equal(assignmentPresentation({ assignment_state: "ASSIGNED", assignee_operator_id: "a1800000-0000-4000-8000-000000000050", assignee_display_name: "Operator", revision: 3 }).assigneeDisplayName, "Operator");
});

test("assignment command keeps read revision and requires reason only for true reassignment", () => {
  const uuid = "a1800000-0000-4000-8000-000000000051";
  const operator = "a1800000-0000-4000-8000-000000000050";
  const unassigned = { assignment_state: "UNASSIGNED", assignee_operator_id: null, assignee_display_name: null, revision: 2 };
  assert.deepEqual(buildAssignmentCommand("#F98B2F08", unassigned, operator, "", uuid), { action: "assign_dossier", dossier_reference: "#F98B2F08", assignee_operator_id: operator, expected_revision: 2, idempotency_key: uuid });
  const assigned = { assignment_state: "ASSIGNED", assignee_operator_id: "a1800000-0000-4000-8000-000000000052", assignee_display_name: "Vorige", revision: 7 };
  assert.equal(buildAssignmentCommand("#F98B2F08", assigned, operator, "  Nieuwe planning  ", uuid).reason, "Nieuwe planning");
  assert.throws(()=>buildAssignmentCommand("#F98B2F08", assigned, operator, "", uuid), /INVALID_ASSIGNMENT_COMMAND/);
  assert.throws(()=>buildAssignmentCommand("#F98B2F08", assigned, assigned.assignee_operator_id, "reden", uuid), /INVALID_ASSIGNMENT_COMMAND/);
  assert.equal(assigned.revision, 7);
});

test("assignment errors refresh server authority without mutation retry", () => {
  for (const code of ["AUTHENTICATION_REQUIRED", "INVALID_JWT", "HUMAN_JWT_REQUIRED", "OPERATOR_NOT_AUTHORIZED", "INSUFFICIENT_PERMISSIONS"]) assert.equal(assignmentError(code).hide, true);
  for (const code of ["CONCURRENT_MODIFICATION", "COMMAND_REJECTED", "IDEMPOTENCY_CONFLICT", "ASSIGNEE_NOT_ELIGIBLE"]) assert.equal(assignmentError(code).refresh, true);
  assert.doesNotMatch(assignmentError("raw postgres error").message, /postgres|SQL/i);
});

test("assignment UI is bounded, accessible, stale-safe, and Edge-only", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  const managerWorkspace = html.split('<div id="managerWorkspace" hidden>')[1] || "";
  const assignmentHandler = script.match(/assignmentForm\.addEventListener\("submit"[\s\S]*?promote\.addEventListener/)?.[0] || "";
  assert.match(html, /id="applicationDetail"[\s\S]*id="assignmentDossier"[\s\S]*id="dossierLifecycleDossier"/);
  assert.match(html, /<label for="assignmentOperator">[\s\S]*<select id="assignmentOperator"/);
  assert.match(html, /<label id="assignmentReasonField" for="assignmentReason" hidden>[\s\S]*maxlength="500"/);
  assert.match(html, /id="assignmentSubmit"[^>]*disabled>Toewijzen</);
  assert.match(html, /id="assignmentMessage"[^>]*role="status"[^>]*aria-live="polite"/);
  assert.match(html, /id="personalQueueWorkspace"[\s\S]*id="managerWorkspace"/);
  assert.doesNotMatch(managerWorkspace, /Mijn dossiers|unassign|assignment history/i);
  assert.match(script, /invoke\(\{ action: "get_dossier_assignment", dossier_reference: dossierReference \}\)/);
  assert.match(script, /invoke\(\{ action: "get_assignment_operator_roster" \}\)/);
  assert.match(script, /buildAssignmentCommand\(assignmentReference, assignmentState, assignmentOperator\.value, assignmentReason\.value, crypto\.randomUUID\(\)\)/);
  assert.match(script, /if \(assignmentSubmitting \|\| !assignmentState \|\| !assignmentReference\) return/);
  assert.match(script, /await invoke\(input\);[\s\S]{0,180}await loadAssignment\(selectedDetail, requestId/);
  assert.match(script, /if \(outcome\.refresh\) await loadAssignment\(selectedDetail, requestId, outcome\.message\)/);
  assert.match(script, /requestId !== detailRequestId \|\| dossierReference !== dossierReferenceFromDetail\(selectedDetail\)/);
  assert.match(script, /selectedDetail = null;\s*resetAssignment\(\)/);
  assert.doesNotMatch(assignmentHandler, /client\.rpc\(/);
  assert.doesNotMatch(script, /assignmentState\.revision\s*(?:\+\+|\+=|=\s*assignmentState\.revision\s*\+)/);
});

test("dossier lifecycle actions follow only authoritative detail state and revision", () => {
  assert.deepEqual(dossierLifecyclePresentation(dossierDetail("ACTIVE").dossier_lifecycle).actions, ["archive_dossier", "trash_dossier"]);
  assert.deepEqual(dossierLifecyclePresentation(dossierDetail("ARCHIVED").dossier_lifecycle).actions, ["reactivate_dossier", "trash_dossier"]);
  assert.deepEqual(dossierLifecyclePresentation(dossierDetail("TRASHED").dossier_lifecycle).actions, ["restore_dossier"]);
  assert.equal(dossierLifecyclePresentation({ state: "UNKNOWN", revision: 3 }), null);
  assert.equal(dossierLifecyclePresentation({ state: "ACTIVE" }), null);
  assert.equal(dossierLifecyclePresentation({ state: "ACTIVE", revision: -1 }), null);
  assert.equal(dossierLifecyclePresentation({ state: "ACTIVE", revision: 1.5 }), null);
  assert.equal(dossierLifecyclePresentation(null), null);
});

test("dossier lifecycle commands use current detail revision, UUID idempotency, and reason only", () => {
  for (const [state, action] of [
    ["ACTIVE", "archive_dossier"],
    ["ACTIVE", "trash_dossier"],
    ["ARCHIVED", "reactivate_dossier"],
    ["TRASHED", "restore_dossier"],
  ]) {
    const command = buildDossierLifecycleCommand(action, dossierDetail(state, 7), "  Operationele reden.  ", "a1800000-0000-4000-8000-000000000041");
    assert.deepEqual(command, {
      action,
      quote_request_id: "a1800000-0000-4000-8000-000000000040",
      expected_revision: 7,
      idempotency_key: "a1800000-0000-4000-8000-000000000041",
      reason: "Operationele reden.",
    });
    for (const forbidden of ["actor", "actor_id", "operator_id", "operator_role", "name", "email", "service_role"]) {
      assert.equal(Object.hasOwn(command, forbidden), false);
    }
  }
});

test("dossier lifecycle command validation fails closed", () => {
  assert.throws(()=>buildDossierLifecycleCommand("archive_dossier", dossierDetail("ACTIVE"), "", "a1800000-0000-4000-8000-000000000041"), /INVALID_DOSSIER_LIFECYCLE_COMMAND/);
  assert.throws(()=>buildDossierLifecycleCommand("restore_dossier", dossierDetail("ACTIVE"), "Reden", "a1800000-0000-4000-8000-000000000041"), /INVALID_DOSSIER_LIFECYCLE_COMMAND/);
  assert.throws(()=>buildDossierLifecycleCommand("archive_dossier", dossierDetail("ACTIVE"), "Reden", "invalid"), /INVALID_DOSSIER_LIFECYCLE_COMMAND/);
  assert.throws(()=>buildDossierLifecycleCommand("archive_dossier", dossierDetail("ACTIVE", -1), "Reden", "a1800000-0000-4000-8000-000000000041"), /INVALID_DOSSIER_LIFECYCLE_COMMAND/);
});

test("dossier lifecycle concurrency errors require refresh without automatic retry authority", () => {
  for (const code of ["CONCURRENT_MODIFICATION", "COMMAND_REJECTED", "INVALID_DOSSIER_LIFECYCLE_TRANSITION", "INVALID_OPERATOR_DOSSIER_TRANSITION", "IDEMPOTENCY_CONFLICT"]) {
    assert.equal(dossierLifecycleError(code).refresh, true);
  }
  assert.equal(dossierLifecycleError("OPERATOR_NOT_AUTHORIZED").refresh, false);
  assert.doesNotMatch(dossierLifecycleError("internal SQL detail").message, /SQL|postgres|internal/i);
});

test("dossier lifecycle UI keeps reversible Edge actions separate from owner-only permanent deletion", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="dossierLifecycleDossier"/);
  assert.match(html, /data-dossier-lifecycle-action="archive_dossier"[^>]*hidden>Archiveren</);
  assert.match(html, /data-dossier-lifecycle-action="reactivate_dossier"[^>]*hidden>Terug activeren</);
  assert.match(html, /data-dossier-lifecycle-action="trash_dossier"[^>]*hidden>Naar prullenbak</);
  assert.match(html, /data-dossier-lifecycle-action="restore_dossier"[^>]*hidden>Herstellen uit prullenbak</);
  assert.match(html, /id="dossierLifecycleReason"[^>]*maxlength="500"[^>]*required/);
  assert.match(html, /id="dossierPurge"[^>]*hidden>Permanent verwijderen</);
  assert.match(html, /id="dossierPurgeDialog"/);
  assert.match(html, /id="dossierPurgeReason"[^>]*maxlength="500"[^>]*required/);
  assert.match(html, /Dit kan niet ongedaan worden gemaakt/);
  assert.match(dossierLifecycleAction("trash_dossier").description, /niet permanent verwijderd/i);
  assert.match(dossierLifecycleAction("trash_dossier").description, /niet hard gedeletet/i);
  assert.match(dossierLifecycleAction("trash_dossier").description, /Herstellen uit prullenbak/i);
  assert.match(script, /import \{ callCommercialOperator \} from "\.\/operator-auth-core\.mjs"/);
  assert.match(script, /callOperator = callCommercialOperator/);
  assert.match(script, /buildDossierLifecycleCommand\(command\.action, command\.detail, dossierLifecycleReason\.value, crypto\.randomUUID\(\)\)/);
  assert.match(script, /command\.selectionRequestId !== detailRequestId \|\| !locatorMatchesApplication\(command\.locator, selectedDetail\)/);
  assert.match(script, /refreshAfterOperatorMutation\([\s\S]{0,300}\(\)=>invoke\(input\)[\s\S]{0,300}\(\)=>detailRequestId/);
  assert.match(script, /if \(outcome\.refresh\) await refreshMutationDetail\(command\.locator, command\.selectionRequestId\)/);
  assert.match(script, /currentIdentity\?\.status !== "ACTIVE"[\s\S]{0,160}currentIdentity\.role !== "owner"/);
  assert.match(script, /client\.rpc\("can_purge_dossier_v1", \{[\s\S]{0,100}p_quote_request_id: detailApplication\.quote_request_id/);
  assert.match(script, /command\.selectionRequestId !== detailRequestId \|\| selectedDetail !== command\.detail/);
  assert.match(script, /dossierPurgeRequest\(command\.detail, dossierPurgeReason\.value, crypto\.randomUUID\(\)\)/);
  assert.match(script, /client\.rpc\("purge_dossier_v1", input\)/);
  assert.match(script, /clearDetail\(\);[\s\S]{0,80}await listController\.refresh\(\)/);
  assert.doesNotMatch(script, /service_role|hard_delete|delete_dossier/i);
});

test("permanent dossier deletion is trashed, owner, server eligibility, reason, and UUID bound", () => {
  const detail = {
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
    dossier_lifecycle: { state: "TRASHED" },
  };
  const owner = { role: "owner", status: "ACTIVE" };
  assert.equal(canOfferDossierPurge(detail, owner, { can_purge: true, reason: null }), true);
  assert.equal(canOfferDossierPurge(detail, { role: "admin", status: "ACTIVE" }, { can_purge: true, reason: null }), false);
  assert.equal(canOfferDossierPurge({ ...detail, dossier_lifecycle: { state: "ACTIVE" } }, owner, { can_purge: true, reason: null }), false);
  assert.equal(canOfferDossierPurge(detail, owner, { can_purge: false, reason: "OFFICIAL_QUOTATION_EXISTS" }), false);
  assert.deepEqual(dossierPurgeRequest(detail, "  Lokale testdata opschonen  ", "a1800000-0000-4000-8000-000000000031"), {
    p_quote_request_id: detail.quote_request_id,
    p_reason: "Lokale testdata opschonen",
    p_idempotency_key: "a1800000-0000-4000-8000-000000000031",
  });
  assert.throws(()=>dossierPurgeRequest(detail, "   ", "a1800000-0000-4000-8000-000000000031"), /INVALID_DOSSIER_PURGE_REQUEST/);
  assert.throws(()=>dossierPurgeRequest(detail, "Reden", "geen-uuid"), /INVALID_DOSSIER_PURGE_REQUEST/);
});

test("legacy trash detail keeps lifecycle and purge eligibility reachable without output controls", async () => {
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /const dossierOutput = application\.application;\s*applicationDossierActions\.hidden = true;\s*if \(isWebsite && dossierOutput\)/);
  assert.match(script, /renderDossierLifecycle\(application\);/);
  assert.match(script, /void refreshDossierPurgeEligibility\(detailApplication, detailRequestId\);/);
  assert.match(script, /client\.rpc\("can_purge_dossier_v1"/);
});

test("successful dossier transition focuses only an action allowed by refreshed detail", () => {
  const focused = [];
  const buttons = [
    { dataset: { dossierLifecycleAction: "archive_dossier" }, hidden: true, disabled: false, focus: ()=>focused.push("archive") },
    { dataset: { dossierLifecycleAction: "restore_dossier" }, hidden: false, disabled: false, focus: ()=>focused.push("restore") },
  ];
  assert.equal(focusDossierLifecycle({ state: "TRASHED", revision: 4 }, buttons, null), buttons[1]);
  assert.deepEqual(focused, ["restore"]);
});

function detailVisibilityHarness() {
  const customer = { hidden: false };
  const websiteSections = Array.from({ length: 7 }, () => ({ hidden: false }));
  const sdfSections = Array.from({ length: 2 }, () => ({ hidden: false }));
  return {
    customer,
    websiteSections,
    sdfSections,
    nodes: {
      detail: { hidden: false },
      detailEmpty: { hidden: true },
      promote: { hidden: false, disabled: true },
      dossierSections: [customer, ...websiteSections, ...sdfSections],
      websiteDossierSections: websiteSections,
      sdfDossierSections: sdfSections,
      websiteDetailRows: Array.from({ length: 3 }, () => ({ hidden: false })),
      sdfDetailRows: Array.from({ length: 1 }, () => ({ hidden: false })),
      sdfDetailNotice: { hidden: false },
    },
  };
}

test("product switch fully clears Website and SDF dossier presentation", () => {
  for (const selectedKind of ["website", "slimme_documentenflow"]) {
    const harness = detailVisibilityHarness();
    applyDetailVisibility(selectedKind, harness.nodes);
    applyDetailVisibility(null, harness.nodes);
    assert.equal(harness.nodes.detail.hidden, true);
    assert.equal(harness.nodes.detailEmpty.hidden, false);
    assert.equal(harness.nodes.promote.hidden, true);
    assert.equal(harness.nodes.promote.disabled, false);
    assert.equal(harness.nodes.dossierSections.every((section) => section.hidden), true);
    assert.equal(harness.nodes.websiteDetailRows.every((row) => row.hidden), true);
    assert.equal(harness.nodes.sdfDetailRows.every((row) => row.hidden), true);
    assert.equal(harness.nodes.sdfDetailNotice.hidden, true);
  }
});

test("Website detail is restored only after Website reselection", () => {
  const harness = detailVisibilityHarness();
  applyDetailVisibility(null, harness.nodes);
  applyDetailVisibility("website", harness.nodes);
  assert.equal(harness.nodes.detail.hidden, false);
  assert.equal(harness.nodes.detailEmpty.hidden, true);
  assert.equal(harness.customer.hidden, false);
  assert.equal(harness.websiteSections.every((section) => !section.hidden), true);
  assert.equal(harness.sdfSections.every((section) => section.hidden), true);
  assert.equal(harness.nodes.websiteDetailRows.every((row) => !row.hidden), true);
  assert.equal(harness.nodes.sdfDetailRows.every((row) => row.hidden), true);
  assert.equal(harness.nodes.sdfDetailNotice.hidden, true);
});

test("SDF detail restores shared data without Website-only presentation", () => {
  const harness = detailVisibilityHarness();
  applyDetailVisibility(null, harness.nodes);
  applyDetailVisibility("slimme_documentenflow", harness.nodes);
  assert.equal(harness.nodes.detail.hidden, false);
  assert.equal(harness.nodes.detailEmpty.hidden, true);
  assert.equal(harness.customer.hidden, false);
  assert.equal(harness.websiteSections.every((section) => section.hidden), true);
  assert.equal(harness.sdfSections.every((section) => !section.hidden), true);
  assert.equal(harness.nodes.websiteDetailRows.every((row) => row.hidden), true);
  assert.equal(harness.nodes.sdfDetailRows.every((row) => !row.hidden), true);
  assert.equal(harness.nodes.sdfDetailNotice.hidden, false);
});

test("SDF detail hides every Website-only field and dossier section", async () => {
  const [html, script] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard.js"),
  ]);
  assert.match(html, /data-website-detail/);
  assert.match(html, /id="sdfDetailNotice"[^>]* hidden/);
  assert.match(script, /WEBSITE_DOSSIER_IDS/);
  assert.match(script, /section\.hidden = !isWebsite/);
  assert.match(script, /row\.hidden = !isWebsite/);
  assert.match(script, /if \(!isWebsite\) return/);
  assert.match(script, /application\.request_kind === "website" && application\.project/);
});

test("SDF package rendering uses canonical labels and a neutral legacy state", async () => {
  assert.equal(sdfPackageLabel("start"), "START");
  assert.equal(sdfPackageLabel("groei"), "GROEI");
  assert.equal(sdfPackageLabel("maatwerk"), "MAATWERK");
  assert.equal(sdfPackageLabel(null), "Niet geregistreerd");
  assert.equal(sdfPackageLabel('<img src=x onerror="alert(1)">'), "Niet geregistreerd");
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});

test("Website and SDF use the same persisted Customer Core presentation", () => {
  const customer = {
    customer_type: "business", name: "Test Klant", company: "Test BV", email: "klant@example.test", phone: "+32 470 00 00 00",
    enterprise_number: "0123456789", enterprise_validation_status: "format_valid_not_externally_verified",
    vat_number: "BE0123456789", vat_validation_status: "valid", vat_validated_at: "2026-08-21T10:00:00Z",
    billing_address: "Teststraat 1", billing_postal_code: "9000", billing_city: "Gent", billing_country: "BE", billing_email: "billing@example.test",
  };
  const website = customerCorePresentation({ ...customer, request_kind: "website" });
  const sdf = customerCorePresentation({ ...customer, request_kind: "slimme_documentenflow" });
  assert.deepEqual(sdf, website);
  assert.equal(website.detailEnterpriseNumber, "0123456789");
  assert.equal(website.detailBillingEmail, "billing@example.test");
});

test("missing optional Customer Core values clear stale dossier content", () => {
  const previous = customerCorePresentation({ company: "Vorige BV", vat_number: "BE0123456789", billing_city: "Gent" });
  const next = customerCorePresentation({ name: "Nieuwe klant", email: "nieuw@example.test" });
  assert.equal(previous.detailCompany, "Vorige BV");
  assert.equal(next.detailCompany, "-");
  assert.equal(next.detailVatNumber, "-");
  assert.equal(next.detailBillingCity, "-");
});

test("Customer Core presentation preserves untrusted text for textContent rendering", async () => {
  const payload = '<img src=x onerror="alert(1)">';
  assert.equal(customerCorePresentation({ company: payload }).detailCompany, payload);
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});

test("filter navigation is server-side and preserves out-of-order detail protection", async () => {
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /listController\.updateQuery\(\{ request_kind: requestKind \}\)/);
  assert.match(script, /listController\.updateQuery\(\{ operational_status:/);
  assert.doesNotMatch(script, /renderVisibleApplications|activeFilter = nextFilter/);
  assert.match(script, /requestId !== detailRequestId/);
  assert.match(script, /detailRequestId \+= 1/);
  assert.doesNotMatch(script, /action: "list_applications"|offset/);
});

test("legacy applications use the internal UUID locator without fabricating a reference", () => {
  assert.deepEqual(applicationLocatorFromUrl("https://example.test/operator/dashboard/?request=a1100000-0000-4000-8000-000000000003"), { quote_request_id: "a1100000-0000-4000-8000-000000000003" });
  assert.equal(applicationLocatorFromUrl("https://example.test/operator/dashboard/?request=bad"), null);
});

test("workflow display distinguishes available, locked, completed, and unimplemented states", () => {
  assert.equal(nextWorkflowStage("QUOTE_ACCEPTED").availability, "AVAILABLE NOW");
  assert.equal(nextWorkflowStage("M1_PAYMENT_PENDING").availability, "LOCKED");
  assert.equal(nextWorkflowStage("ARCHIVED").availability, "COMPLETED");
  assert.equal(nextWorkflowStage("UNKNOWN").availability, "NOT YET IMPLEMENTED");
});

function sdfPricing(packageName, implementationMinor, recurringMinor, priceMode = "fixed") {
  return {
    authority_version: 1,
    package: packageName,
    currency: "EUR",
    vat_basis: "exclusive",
    implementation: { amount_minor: implementationMinor, price_mode: priceMode },
    recurring: {
      amount_minor: recurringMinor,
      price_mode: priceMode,
      billing_period: "month",
      commercial_package_price: true,
      active_recurring_obligation: false,
    },
  };
}

test("SDF pricing renders exact START and GROEI commercial package prices", () => {
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "start", sdf_pricing: sdfPricing("start", 285000, 17500) }), {
    package: "START", implementation: "€ 2.850 excl. btw", recurring: "€ 175 excl. btw / maand",
  });
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "groei", sdf_pricing: sdfPricing("groei", 570000, 29900) }), {
    package: "GROEI", implementation: "€ 5.700 excl. btw", recurring: "€ 299 excl. btw / maand",
  });
});

test("SDF MAATWERK pricing preserves starting-at semantics", () => {
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "maatwerk", sdf_pricing: sdfPricing("maatwerk", 750000, 44900, "starting_at") }), {
    package: "MAATWERK", implementation: "vanaf € 7.500 excl. btw", recurring: "vanaf € 449 excl. btw / maand",
  });
});

test("SDF pricing fails closed for legacy, mismatched, and non-commercial contexts", () => {
  const unavailable = { package: "GROEI", implementation: "Niet beschikbaar", recurring: "Niet beschikbaar" };
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: null, sdf_pricing: null }), {
    package: "Niet geregistreerd", implementation: "Niet beschikbaar", recurring: "Niet beschikbaar",
  });
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "groei", sdf_pricing: sdfPricing("start", 285000, 17500) }), unavailable);
  const obligation = sdfPricing("groei", 570000, 29900);
  obligation.recurring.active_recurring_obligation = true;
  assert.deepEqual(sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "groei", sdf_pricing: obligation }), unavailable);
  assert.equal(sdfPricingPresentation({ request_kind: "website", sdf_package: "start", sdf_pricing: sdfPricing("start", 285000, 17500) }), null);
});

test("SDF pricing clears stale values and remains textContent-only", async () => {
  const previous = sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: "start", sdf_pricing: sdfPricing("start", 285000, 17500) });
  const next = sdfPricingPresentation({ request_kind: "slimme_documentenflow", sdf_package: null, sdf_pricing: null });
  assert.equal(previous.implementation, "€ 2.850 excl. btw");
  assert.equal(next.implementation, "Niet beschikbaar");
  assert.equal(next.recurring, "Niet beschikbaar");
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="sdfPricingDossier"[^>]* hidden/);
  assert.match(html, /commerciële pakketprijs en geen actieve terugkerende dienst of financiële verplichting/);
  assert.match(script, /setText\("detailSdfImplementationPrice", sdfPricing\?\.implementation \|\| "Niet beschikbaar"\)/);
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});

function sdfQuotation(overrides = {}) {
  return {
    quotation_id: "a1a00000-0000-4000-8000-000000000001",
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
    application_reference: null,
    created_at: "2099-01-03T10:00:00Z",
    document: null,
    acceptance: null,
    ...overrides,
  };
}

test("SDF quotation presenter renders exact identity without inventing status", () => {
  const presentation = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation() });
  assert.equal(presentation.quotationId, "a1a00000-0000-4000-8000-000000000001");
  assert.equal(presentation.application, "a1100000-0000-4000-8000-000000000003");
  assert.notEqual(presentation.createdAt, "Niet beschikbaar");
  assert.equal(presentation.documentState, "Niet geregistreerd");
  assert.equal(presentation.acceptanceState, "Niet geregistreerd");
});

test("SDF quotation presenter renders document evidence without acceptance", () => {
  const document = {
    quotation_date: "2099-01-03",
    valid_until: "2099-02-02",
    prepared_at: "2099-01-03T11:00:00Z",
    document_reference_present: true,
    document_sha256_present: true,
  };
  const presentation = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation({ document }) });
  assert.equal(presentation.documentState, "Geregistreerd");
  assert.notEqual(presentation.quotationDate, "Niet beschikbaar");
  assert.notEqual(presentation.validUntil, "Niet beschikbaar");
  assert.equal(presentation.documentReference, "Aanwezig");
  assert.equal(presentation.documentHash, "Aanwezig");
  assert.equal(presentation.acceptanceState, "Niet geregistreerd");
});

test("SDF quotation presenter renders active acceptance evidence", () => {
  const document = { quotation_date: "2099-01-03", valid_until: "2099-02-02", prepared_at: "2099-01-03T11:00:00Z", document_reference_present: true, document_sha256_present: true };
  const acceptance = { accepted_at: "2099-01-04T12:00:00Z", accepted_document_reference_present: true, accepted_document_sha256_present: true };
  const presentation = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation({ document, acceptance }) });
  assert.equal(presentation.acceptanceState, "Geaccepteerd");
  assert.notEqual(presentation.acceptedAt, "Niet beschikbaar");
  assert.equal(presentation.acceptedDocument, "Aanwezig");
  assert.equal(presentation.acceptedHash, "Aanwezig");
});

test("SDF quotation presenter handles absent, mismatched, Website, and legacy identities", () => {
  assert.deepEqual(sdfQuotationPresentation(sdfApplication()), {
    quotationId: "Nog geen offerte",
    application: "a1100000-0000-4000-8000-000000000003",
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
  });
  assert.equal(sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation({ quote_request_id: "b1100000-0000-4000-8000-000000000003" }) }).quotationId, "Nog geen offerte");
  assert.equal(sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation({ status: "DRAFT" }) }).quotationId, "Nog geen offerte");
  assert.equal(sdfQuotationPresentation({ request_kind: "website", sdf_quotation: sdfQuotation() }), null);
  assert.equal(sdfQuotationPresentation({ quote_request_id: "legacy", request_kind: "slimme_documentenflow", sdf_quotation: null }).application, "legacy");
});

test("SDF quotation presenter fails closed on malformed or mismatched evidence", () => {
  const validDocument = { quotation_date: "2099-01-03", valid_until: "2099-02-02", prepared_at: "2099-01-03T11:00:00Z", document_reference_present: true, document_sha256_present: true };
  const invalidCases = [
    sdfQuotation({ document: { ...validDocument, valid_until: "2099-01-02" } }),
    sdfQuotation({ document: { ...validDocument, document_sha256: "a".repeat(64) } }),
    sdfQuotation({ document: null, acceptance: { accepted_at: "2099-01-04T12:00:00Z", accepted_document_reference_present: true, accepted_document_sha256_present: true } }),
    sdfQuotation({ document: validDocument, acceptance: { accepted_at: "invalid", accepted_document_reference_present: true, accepted_document_sha256_present: true } }),
  ];
  for (const quotation of invalidCases) {
    const presentation = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: quotation });
    assert.equal(presentation.quotationId, "Nog geen offerte");
    assert.equal(presentation.documentState, "Niet geregistreerd");
    assert.equal(presentation.acceptanceState, "Niet geregistreerd");
  }
});

test("SDF quotation values clear on dossier switch and remain textContent-only", async () => {
  const previous = sdfQuotationPresentation({ ...sdfApplication(), sdf_quotation: sdfQuotation() });
  const next = sdfQuotationPresentation(sdfApplication());
  assert.notEqual(previous.quotationId, "Nog geen offerte");
  assert.equal(next.quotationId, "Nog geen offerte");
  assert.equal(next.createdAt, "Niet beschikbaar");
  assert.equal(next.documentReference, "Niet beschikbaar");
  assert.equal(next.acceptedDocument, "Niet beschikbaar");
  const payload = '<img src=x onerror="alert(1)">';
  assert.equal(sdfQuotationPresentation({ ...sdfApplication(), application_reference: payload }).application, payload);
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="sdfQuotationDossier"[^>]* hidden/);
  assert.match(html, /id="detailSdfQuotationAcceptanceState"><\/dd>/);
  assert.doesNotMatch(html, /detailSdfQuotationStatus/);
  assert.match(script, /setText\("detailSdfQuotationId", sdfQuotation\?\.quotationId \|\| "Nog geen offerte"\)/);
  assert.doesNotMatch(script, /detailSdfQuotationStatus/);
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});

test("SDF M1 invoice candidate presenter exposes only policy-neutral prepared evidence", async () => {
  const candidate = {
    candidate_id: "a1b00000-0000-4000-8000-000000000001",
    candidate_state: "PREPARED",
    application_reference: "LWS-AAN-2099-0401",
    milestone_identity: "M1",
    percentage_basis_points: 4000,
    currency: "EUR",
    net_amount_minor: 114000,
    template_binding_present: true,
    invoice_number: null,
    fiscal_authority_state: "NOT_ACTIVE",
    production_issuance_available: false,
    prepared_at: "2099-01-05T10:00:00Z",
  };
  const presentation = sdfM1InvoiceCandidatePresentation({ ...sdfApplication(), application_reference: "LWS-AAN-2099-0401", sdf_m1_invoice_candidate: candidate });
  assert.equal(presentation.state, "Voorbereid");
  assert.equal(presentation.dossierReference, "LWS-AAN-2099-0401");
  assert.equal(presentation.milestone, "M1");
  assert.equal(presentation.percentage, "40%");
  assert.match(presentation.netAmount, /1[.,\s]140/);
  assert.equal(presentation.invoiceNumber, "Niet toegewezen");
  assert.equal(presentation.fiscalAuthority, "Niet actief");
  assert.equal(presentation.issuance, "Geblokkeerd");
  const html = await read("operator/dashboard/index.html");
  assert.match(html, /id="sdfM1InvoiceDossier"[^>]* hidden/);
  assert.match(html, /Definitieve uitgifte blijft geblokkeerd/);
  assert.doesNotMatch(html, /id="[^\"]*SdfM1Invoice[^\"]*"[^>]*type="button"/);
});

test("SDF M1 invoice candidate presenter fails closed on issued or fiscal claims", () => {
  const base = {
    candidate_id: "a1b00000-0000-4000-8000-000000000001",
    candidate_state: "PREPARED",
    application_reference: "LWS-AAN-2099-0401",
    milestone_identity: "M1",
    percentage_basis_points: 4000,
    currency: "EUR",
    net_amount_minor: 114000,
    template_binding_present: true,
    invoice_number: null,
    fiscal_authority_state: "NOT_ACTIVE",
    production_issuance_available: false,
    prepared_at: "2099-01-05T10:00:00Z",
  };
  for (const candidate of [
    { ...base, invoice_number: "LWS-2099-0001" },
    { ...base, fiscal_authority_state: "ACTIVE" },
    { ...base, production_issuance_available: true },
    { ...base, percentage_basis_points: 2100 },
  ]) {
    assert.equal(sdfM1InvoiceCandidatePresentation({ ...sdfApplication(), application_reference: "LWS-AAN-2099-0401", sdf_m1_invoice_candidate: candidate }).state, "Nog geen candidate");
  }
  assert.equal(sdfM1InvoiceCandidatePresentation({ ...sdfApplication(), application_reference: "LWS-AAN-2099-0402", sdf_m1_invoice_candidate: base }).state, "Nog geen candidate");
  assert.equal(sdfM1InvoiceCandidatePresentation({ request_kind: "website", sdf_m1_invoice_candidate: base }), null);
});

function sdfApplication(project = null) {
  return {
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
    application_reference: null,
    request_kind: "slimme_documentenflow",
    sdf_package: "groei",
    name: "Documentenflow Application",
    project,
  };
}

function sdfProject(overrides = {}) {
  return {
    project_id: "a1900000-0000-4000-8000-000000000001",
    request_kind: "slimme_documentenflow",
    quote_request_id: "a1100000-0000-4000-8000-000000000003",
    application_reference: null,
    customer_name: "Documentenflow Application",
    sdf_package: "groei",
    current_state: null,
    operational_status: null,
    created_at: "2099-01-02T10:00:00Z",
    ...overrides,
  };
}

test("SDF application without project authority shows no fabricated project", () => {
  assert.deepEqual(sdfProjectPresentation(sdfApplication()), {
    projectId: "Nog geen project",
    product: "Slimme Documentenflow",
    application: "a1100000-0000-4000-8000-000000000003",
    customer: "Documentenflow Application",
    package: "GROEI",
    status: "Niet beschikbaar",
    operationalStatus: "Niet beschikbaar",
    createdAt: "Niet beschikbaar",
  });
});

test("SDF project authority renders exact linkage without inventing status", () => {
  const presentation = sdfProjectPresentation(sdfApplication(sdfProject()));
  assert.equal(presentation.projectId, "a1900000-0000-4000-8000-000000000001");
  assert.equal(presentation.product, "Slimme Documentenflow");
  assert.equal(presentation.application, "a1100000-0000-4000-8000-000000000003");
  assert.equal(presentation.customer, "Documentenflow Application");
  assert.equal(presentation.package, "GROEI");
  assert.equal(presentation.status, "Niet beschikbaar");
  assert.equal(presentation.operationalStatus, "Niet beschikbaar");
  assert.notEqual(presentation.createdAt, "Niet beschikbaar");
});

test("SDF project presentation fails closed for cross-product, mismatched, and legacy contexts", () => {
  assert.equal(sdfProjectPresentation({ request_kind: "website", project: sdfProject() }), null);
  assert.equal(sdfProjectPresentation(sdfApplication(sdfProject({ quote_request_id: "b1100000-0000-4000-8000-000000000003" }))).projectId, "Nog geen project");
  assert.equal(sdfProjectPresentation(sdfApplication(sdfProject({ current_state: "PROJECT_IN_PROGRESS" }))).projectId, "Nog geen project");
  const legacy = sdfProjectPresentation({ quote_request_id: "legacy", request_kind: "slimme_documentenflow", sdf_package: null, name: "Legacy", project: null });
  assert.equal(legacy.projectId, "Nog geen project");
  assert.equal(legacy.package, "Niet geregistreerd");
});

test("SDF project values clear on dossier switch and remain textContent-only", async () => {
  const previous = sdfProjectPresentation(sdfApplication(sdfProject()));
  const next = sdfProjectPresentation(sdfApplication());
  assert.notEqual(previous.projectId, "Nog geen project");
  assert.equal(next.projectId, "Nog geen project");
  assert.equal(next.createdAt, "Niet beschikbaar");
  const payload = '<img src=x onerror="alert(1)">';
  assert.equal(sdfProjectPresentation({ ...sdfApplication(), name: payload }).customer, payload);
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="sdfProjectDossier"[^>]* hidden/);
  assert.match(script, /setText\("detailSdfProjectId", sdfProject\?\.projectId \|\| "Nog geen project"\)/);
  assert.match(script, /element\.textContent = value/);
  assert.doesNotMatch(script, /\.innerHTML|insertAdjacentHTML/);
});

const operatorItem = (suffix, overrides = {}) => ({
  quote_request_id: `a1100000-0000-4000-8000-${suffix.padStart(12, "0")}`,
  application_reference: `LWS-AAN-2099-${suffix.padStart(4, "0")}`,
  support_reference: "#F98B2F08",
  name: "Lorenzo",
  organization: "Lorenzo Web Solutions",
  request_kind: "website",
  zone: "ACTIVE",
  operational_status: "SUBMITTED",
  dossier_date: "2099-01-01T10:00:00Z",
  ...overrides,
});

test("v2 request mapping defaults to ACTIVE and searches ACTIVE plus ARCHIVED without trash", () => {
  assert.equal(effectiveOperatorZone("ACTIVE", ""), "ACTIVE");
  assert.equal(effectiveOperatorZone("ACTIVE", "Lorenzo"), "ACTIVE_ARCHIVED");
  assert.equal(effectiveOperatorZone("ARCHIVED", "Lorenzo"), "ARCHIVED");
  assert.equal(effectiveOperatorZone("TRASHED", "Lorenzo"), "TRASHED");
  const request = operatorListRequest({ search: "Lorenzo", request_kind: "website" });
  assert.deepEqual(request, {
    action: "list_applications_v2", zone: "ACTIVE_ARCHIVED", operational_status: null,
    year: null, quarter: null, request_kind: "website", search: "Lorenzo", cursor: null, limit: 50,
  });
  assert.equal("offset" in request, false);
  assert.equal(operatorListRequest({ request_kind: null }).request_kind, null);
  assert.equal(operatorListRequest({ request_kind: "website" }).request_kind, "website");
  assert.equal(operatorListRequest({ request_kind: "slimme_documentenflow" }).request_kind, "slimme_documentenflow");
  assert.deepEqual(operatorFacetsRequest({ zone: "TRASHED", search: "Lorenzo" }), {
    action: "get_application_facets_v2", zone: "TRASHED", operational_status: null,
    request_kind: null, search: "Lorenzo",
  });
});

test("global search forwards name, organization, application, support, UUID, empty, and clear server-side", () => {
  const searches = ["Lorenzo", "Lorenzo Web Solutions", "LWS-AAN-2099-0001", "#F98B2F08", "a1100000-0000-4000-8000-000000000001"];
  for (const search of searches) assert.equal(operatorListRequest({ search }).search, search);
  assert.equal(operatorListRequest({ search: "   " }).search, null);
  assert.equal(operatorListRequest({ search: "" }).zone, "ACTIVE");
});

test("v2 status and identities are textual, authoritative, and defensively deduplicated", () => {
  assert.deepEqual(operatorStatusPresentation("CANCELLED"), { label: "GEANNULEERD", tone: "red" });
  assert.deepEqual(operatorStatusPresentation("ARCHIVED"), { label: "ARCHIVED", tone: "amber" });
  const first = operatorItem("1");
  const second = operatorItem("2");
  assert.deepEqual(appendUniqueOperatorItems([first], [first, second, { quote_request_id: "bad" }]), [first, second]);
});

test("keyset controller loads 50, appends next_cursor pages, and prevents double-more", async () => {
  const calls = [];
  let releaseMore;
  const controller = createOperatorListController(async (input) => {
    calls.push(input);
    if (input.action === "get_application_facets_v2") return { years: [{ year: 2099, count: 2, quarters: [{ quarter: "Q1", count: 2 }, { quarter: "Q2", count: 0 }, { quarter: "Q3", count: 0 }, { quarter: "Q4", count: 0 }] }] };
    if (!input.cursor) return { items: [operatorItem("1")], next_cursor: "signed-next" };
    return await new Promise((resolve)=>{ releaseMore = ()=>resolve({ items: [operatorItem("1"), operatorItem("2")], next_cursor: null }); });
  });
  await controller.load();
  const firstMore = controller.loadMore();
  assert.equal(await controller.loadMore(), false);
  releaseMore();
  assert.equal(await firstMore, true);
  assert.deepEqual(controller.state.items.map((item)=>item.quote_request_id), [operatorItem("1").quote_request_id, operatorItem("2").quote_request_id]);
  assert.equal(controller.state.next_cursor, null);
  assert.equal(calls.filter((input)=>input.action === "list_applications_v2").every((input)=>input.limit === 50 && !("offset" in input)), true);
  assert.equal(controller.state.facets.years[0].quarters[1].count, 0);
});

test("query generation ignores stale responses and resets cursor for search and filters", async () => {
  const pending = [];
  const controller = createOperatorListController((input)=>new Promise((resolve)=>pending.push({ input, resolve })));
  const oldLoad = controller.load();
  const newLoad = controller.updateQuery({ search: "Lorenzo", request_kind: "website" });
  const newer = pending.filter((entry)=>entry.input.search === "Lorenzo");
  newer.find((entry)=>entry.input.action === "list_applications_v2").resolve({ items: [operatorItem("2")], next_cursor: null });
  newer.find((entry)=>entry.input.action === "get_application_facets_v2").resolve({ years: [] });
  await newLoad;
  const older = pending.filter((entry)=>entry.input.search === null);
  older.find((entry)=>entry.input.action === "list_applications_v2").resolve({ items: [operatorItem("1")], next_cursor: "stale" });
  older.find((entry)=>entry.input.action === "get_application_facets_v2").resolve({ years: [] });
  await oldLoad;
  assert.deepEqual(controller.state.items, [operatorItem("2")]);
  assert.equal(controller.state.next_cursor, null);
  assert.equal(controller.state.generation, 1);
});

test("invalid cursor performs exactly one safe first-page retry", async () => {
  let listCalls = 0;
  const controller = createOperatorListController(async (input) => {
    if (input.action === "get_application_facets_v2") return { years: [] };
    listCalls += 1;
    if (listCalls === 1) return { items: [operatorItem("1")], next_cursor: "expired" };
    if (input.cursor) throw new Error("INVALID_OPERATOR_CURSOR");
    return { items: [operatorItem("2")], next_cursor: null };
  });
  await controller.load();
  await controller.loadMore();
  assert.equal(listCalls, 3);
  assert.deepEqual(controller.state.items, [operatorItem("2")]);
  assert.equal(controller.state.error, null);
});

test("mutation refresh replaces stale summary and reloads authoritative detail", async () => {
  const previous = operatorItem("1", { operational_status: "QUOTE_ACCEPTED" });
  const current = operatorItem("1", { operational_status: "PROJECT_RELEASED" });
  const controller = createOperatorListController(async (input) => input.action === "get_application_facets_v2"
    ? { years: [] }
    : { items: [current], next_cursor: null });
  controller.state.items = [previous];
  let selectedSummary = previous;
  let selectedDetail = { project: null };
  let promoteVisible = true;
  const result = await refreshOperatorSelection(controller, { application_reference: current.application_reference }, {
    isCurrent: ()=>true,
    close: ()=>assert.fail("selected dossier must remain visible"),
    show: async (summary)=>{
      selectedSummary = summary;
      selectedDetail = { project: { project_id: "project-1" } };
      promoteVisible = false;
      return true;
    },
  });
  assert.equal(result.status, "refreshed");
  assert.equal(selectedSummary.operational_status, "PROJECT_RELEASED");
  assert.equal(selectedDetail.project.project_id, "project-1");
  assert.equal(promoteVisible, false);
});

test("mutation refresh closes detail without retaining a stale summary when dossier leaves query", async () => {
  const previous = operatorItem("1", { operational_status: "QUOTE_ACCEPTED" });
  const controller = createOperatorListController(async (input) => input.action === "get_application_facets_v2"
    ? { years: [] }
    : { items: [], next_cursor: null });
  controller.state.items = [previous];
  let selectedSummary = previous;
  let detailVisible = true;
  const result = await refreshOperatorSelection(controller, { application_reference: previous.application_reference }, {
    isCurrent: ()=>true,
    close: ()=>{
      selectedSummary = null;
      detailVisible = false;
    },
    show: async ()=>assert.fail("missing dossier must not reload detail"),
  });
  assert.equal(result.status, "closed");
  assert.equal(selectedSummary, null);
  assert.equal(detailVisible, false);
});

test("mutation refresh cannot overwrite a selection changed during list reload", async () => {
  const current = operatorItem("1", { operational_status: "PROJECT_RELEASED" });
  const controller = createOperatorListController(async (input) => input.action === "get_application_facets_v2"
    ? { years: [] }
    : { items: [current], next_cursor: null });
  let currentSelection = false;
  let detailLoads = 0;
  const result = await refreshOperatorSelection(controller, { application_reference: current.application_reference }, {
    isCurrent: ()=>currentSelection,
    close: ()=>assert.fail("superseded refresh must not close the new selection"),
    show: async ()=>{ detailLoads += 1; },
  });
  assert.equal(result.status, "superseded");
  assert.equal(detailLoads, 0);
});

test("mutation refresh reports a detail response superseded after list reload", async () => {
  const current = operatorItem("1", { operational_status: "PROJECT_RELEASED" });
  const controller = createOperatorListController(async (input) => input.action === "get_application_facets_v2"
    ? { years: [] }
    : { items: [current], next_cursor: null });
  const result = await refreshOperatorSelection(controller, { application_reference: current.application_reference }, {
    isCurrent: ()=>true,
    close: ()=>assert.fail("selected dossier remains in the query"),
    show: async ()=>false,
  });
  assert.equal(result.status, "superseded");
  assert.equal(result.summary, current);
});

test("mutation refresh closes stale detail when its authoritative list reload fails", async () => {
  const controller = createOperatorListController(async (input) => {
    if (input.action === "get_application_facets_v2") return { years: [] };
    throw new Error("OPERATOR_REQUEST_FAILED");
  });
  let detailVisible = true;
  const result = await refreshOperatorSelection(controller, { application_reference: "LWS-AAN-2099-0001" }, {
    isCurrent: ()=>true,
    close: ()=>{ detailVisible = false; },
    show: async ()=>assert.fail("failed list reload must not request detail"),
  });
  assert.equal(result.status, "closed");
  assert.equal(detailVisible, false);
});

test("lifecycle mutation captures selection authority before pending B starts", async () => {
  let releaseMutation;
  const mutation = new Promise((resolve)=>{ releaseMutation = resolve; });
  let detailRequestId = 11;
  let activeSelection = "A";
  let reopened = null;
  const pendingRefresh = refreshAfterOperatorMutation(
    ()=>mutation,
    async (selectionRequestId)=>{
      if (selectionRequestId !== detailRequestId || activeSelection !== "A") return { status: "superseded" };
      reopened = "A";
      return { status: "refreshed" };
    },
    ()=>detailRequestId,
  );
  detailRequestId = 12;
  activeSelection = "B";
  releaseMutation();
  const result = await pendingRefresh;
  assert.equal(result.status, "superseded");
  assert.equal(reopened, null);
  assert.equal(detailRequestId, 12);
  assert.equal(activeSelection, "B");
});

test("lifecycle mutation refreshes A when selection authority remains unchanged", async () => {
  let releaseMutation;
  const mutation = new Promise((resolve)=>{ releaseMutation = resolve; });
  let detailRequestId = 21;
  let activeSelection = "A";
  let reopened = null;
  const pendingRefresh = refreshAfterOperatorMutation(
    ()=>mutation,
    async (selectionRequestId)=>{
      if (selectionRequestId !== detailRequestId || activeSelection !== "A") return { status: "superseded" };
      reopened = "A";
      return { status: "refreshed" };
    },
    ()=>detailRequestId,
  );
  releaseMutation();
  const result = await pendingRefresh;
  assert.equal(result.status, "refreshed");
  assert.equal(reopened, "A");
  assert.equal(detailRequestId, 21);
  assert.equal(activeSelection, "A");
});

test("facet invalidation atomically resets hidden year and quarter with one authoritative reload", async () => {
  const listRequests = [];
  let facetCalls = 0;
  const controller = createOperatorListController(async (input) => {
    if (input.action === "get_application_facets_v2") {
      facetCalls += 1;
      return facetCalls === 1
        ? { years: [{ year: 2099, count: 1, quarters: [{ quarter: "Q4", count: 1 }] }] }
        : { years: [{ year: 2098, count: 1, quarters: [{ quarter: "Q1", count: 1 }] }] };
    }
    listRequests.push({ year: input.year, quarter: input.quarter });
    return { items: [], next_cursor: null };
  });
  await controller.load();
  await controller.updateQuery({ year: 2099, quarter: "Q4", search: "Lorenzo" });
  assert.equal(controller.state.year, null);
  assert.equal(controller.state.quarter, null);
  assert.deepEqual(controller.state.facets.years.map((entry)=>entry.year), [2098]);
  assert.deepEqual(listRequests.slice(-2), [{ year: 2099, quarter: "Q4" }, { year: null, quarter: null }]);
});

test("facet invalidation resets an unavailable quarter while preserving its valid year", async () => {
  const listRequests = [];
  const controller = createOperatorListController(async (input) => {
    if (input.action === "get_application_facets_v2") {
      return { years: [{ year: 2099, count: 1, quarters: [{ quarter: "Q4", count: 0 }] }] };
    }
    listRequests.push({ year: input.year, quarter: input.quarter });
    return { items: [], next_cursor: null };
  });
  await controller.updateQuery({ year: 2099, quarter: "Q4" });
  assert.equal(controller.state.year, 2099);
  assert.equal(controller.state.quarter, null);
  assert.deepEqual(listRequests, [{ year: 2099, quarter: "Q4" }, { year: 2099, quarter: null }]);
});

test("loading and empty presentation are mutually exclusive", () => {
  assert.deepEqual(operatorListVisibility({ loading: true, items: [], error: null }), {
    message: "Dossiers laden...", emptyHidden: true,
  });
  assert.deepEqual(operatorListVisibility({ loading: false, items: [], error: null }), {
    message: "", emptyHidden: false,
  });
  assert.deepEqual(operatorListVisibility({ loading: false, items: [operatorItem("1")], error: null }), {
    message: "", emptyHidden: true,
  });
});

test("v2 controls, dynamic facets, loading states, and security boundary are explicit", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="applicationSearch"[^>]+placeholder="Zoek op naam, bedrijf of referentie"[^>]+maxlength="140"/);
  assert.match(html, /data-zone="ACTIVE"[^>]+aria-pressed="true"/);
  assert.match(html, /data-zone="ARCHIVED"/);
  assert.match(html, /data-zone="TRASHED"/);
  assert.match(html, /id="applicationYearFilter"/);
  assert.match(html, /id="applicationQuarterFilter" disabled/);
  assert.match(html, /id="applicationLoadMore"[^>]+hidden/);
  assert.match(html, /id="applicationEmpty"[^>]+role="status"[^>]+aria-live="polite"[^>]+aria-atomic="true"[^>]+hidden/);
  assert.match(script, /setTimeout\(applySearch, 300\)/);
  assert.match(script, /option\.disabled = Number\(quarter\.count\) === 0/);
  assert.match(script, /selectedSummary = summary/);
  assert.match(script, /get_application_detail/);
  assert.doesNotMatch(script, /client\.rpc\(["'](?:list_operator_applications_v2|get_operator_dossier_facets_v2)/);
  assert.doesNotMatch(script, /service_role|loadAllOperatorApplications|action: "list_applications"|offset/);
});

test("project site presentation accepts only the exact project-bound HTTPS origin", () => {
  const projectId = "a1800000-0000-4000-8000-000000000001";
  assert.deepEqual(projectSitePresentation(projectId, {
    project_id: projectId,
    canonical_domain: "project.example",
    canonical_url: "https://project.example"
  }), { domain: "project.example", canonicalUrl: "https://project.example" });
  assert.equal(projectSitePresentation(projectId, { project_id: "a1800000-0000-4000-8000-000000000002", canonical_domain: "project.example", canonical_url: "https://project.example" }), null);
  assert.equal(projectSitePresentation(projectId, { project_id: projectId, canonical_domain: "project.example", canonical_url: "http://project.example" }), null);
  assert.equal(projectSitePresentation(projectId, { project_id: projectId, canonical_domain: "project.example", canonical_url: "https://project.example/path" }), null);
  assert.equal(projectSitePresentation(projectId, { project_id: projectId, canonical_domain: "project.example", canonical_url: "https://attacker.example" }), null);
});

test("dashboard role presentation uses one exact server identity projection", async () => {
  const labels = {
    owner: "OWNER", operations_manager: "OPERATIONS MANAGER", operator: "OPERATOR",
    reviewer: "REVIEWER", read_only: "READ ONLY", admin: "ADMIN",
  };
  for (const [role, roleLabel] of Object.entries(labels)) {
    assert.deepEqual(currentOperatorIdentityPresentation({ display_name: "Current User", role, status: "ACTIVE" }), {
      displayName: "Current User", roleLabel,
    });
  }
  for (const identity of [
    null,
    { display_name: "Current User", role: "unknown", status: "ACTIVE" },
    { display_name: "Current User", role: "operator", status: "DISABLED" },
    { display_name: "Current User", role: "operator", status: "ACTIVE", email: "private@example.test" },
  ]) assert.throws(()=>currentOperatorIdentityPresentation(identity), /INVALID_OPERATOR_IDENTITY/);
});

test("dashboard resolves identity before routing and contains no contradictory static role labels", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.equal((html.match(/data-operator-role-badge/g) || []).length, 3);
  assert.doesNotMatch(html, />OPERATOR<|>OWNER \/ ADMIN</);
  assert.match(script, /invoke\(\{ action: "get_current_operator_identity" \}\)/);
  assert.ok(script.indexOf('invoke({ action: "get_current_operator_identity" })') < script.indexOf("resolveDashboardAuthority({"));
  assert.ok(script.indexOf('invoke({ action: "get_current_operator_identity" })') < script.indexOf("personalQueueWorkspace.hidden = false"));
  assert.match(script, /for \(const roleBadge of roleBadges\) roleBadge\.textContent = identity\.roleLabel/);
});

test("internal Smoke A UI requires the explicit URL flag and an ACTIVE owner", () => {
  const owner = { display_name: "Owner", role: "owner", status: "ACTIVE" };
  assert.equal(internalSmokeAvailable("https://operator.example/operator/dashboard/", owner), false);
  assert.equal(internalSmokeAvailable("https://operator.example/operator/dashboard/?internalSmoke=1", { ...owner, role: "operator" }), false);
  assert.equal(internalSmokeAvailable("https://operator.example/operator/dashboard/?internalSmoke=1", { ...owner, status: "REVOKED" }), false);
  assert.equal(internalSmokeAvailable("https://operator.example/operator/dashboard/?internalSmoke=1", owner), true);
});

test("internal Smoke A confirmation cancellation performs zero calls", async () => {
  const button = { disabled: false };
  let calls = 0;
  const trigger = createInternalSmokeOneShotTrigger({
    button,
    confirmSmoke: ()=>false,
    runSmoke: async ()=>{ calls += 1; },
  });
  assert.equal(await trigger(), null);
  assert.equal(calls, 0);
  assert.equal(button.disabled, false);
});

test("internal Smoke A trigger stays disabled after PASS", async () => {
  const button = { disabled: false };
  let runnerCalls = 0;
  const trigger = createInternalSmokeOneShotTrigger({
    button,
    confirmSmoke: ()=>true,
    runSmoke: async ()=>{
      runnerCalls += 1;
      return { SMOKE_STATUS: "PASS" };
    },
  });
  assert.equal((await trigger()).SMOKE_STATUS, "PASS");
  assert.equal(await trigger(), null);
  assert.equal(runnerCalls, 1);
  assert.equal(button.disabled, true);
});

test("internal Smoke A trigger stays one-shot after partial-state failure", async () => {
  const button = { disabled: false };
  let runnerCalls = 0;
  let fixtureCalls = 0;
  let uploadLinkCalls = 0;
  const trigger = createInternalSmokeOneShotTrigger({
    button,
    confirmSmoke: ()=>true,
    runSmoke: async ()=>{
      runnerCalls += 1;
      fixtureCalls += 2;
      uploadLinkCalls += 1;
      return { SMOKE_STATUS: "FAILED: RESOLVE_BEFORE_REVOKE" };
    },
  });

  assert.equal((await trigger()).SMOKE_STATUS, "FAILED: RESOLVE_BEFORE_REVOKE");
  assert.equal(await trigger(), null);
  assert.equal(runnerCalls, 1);
  assert.equal(fixtureCalls, 2);
  assert.equal(uploadLinkCalls, 1);
  assert.equal(button.disabled, true);
});

test("internal Smoke A runtime blocks a non-owner before fixture creation", async () => {
  const calls = [];
  const result = await runInternalSmokeA({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "operator" } }, error: null }),
      },
      rpc: async ()=>assert.fail("RPC must not run"),
    },
    invoke: async (input)=>{
      calls.push(input.action);
      return { role: "operator", status: "ACTIVE" };
    },
    resolveCapability: async ()=>assert.fail("resolve must not run"),
  });
  assert.deepEqual(calls, ["get_current_operator_identity"]);
  assert.equal(result.SMOKE_STATUS, "FAILED: AUTH");
});

function createInternalSmokeFailureHarness({
  linkCreateFails = false,
  uploadUrl = "https://operator.example/pages/customer-request-upload.html#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  resolveCapability = async ()=>{ throw new Error("primary-resolve-failure"); },
  revokeFails = false,
  cancelFails = false,
  finalizeFails = false,
} = {}) {
  const fixture = { run_id: "a2000000-0000-4000-8000-000000000001", request_id: "a2000000-0000-4000-8000-000000000002", status: "NEW", revision: 0, replayed: false };
  const uploadRequestId = "a2000000-0000-4000-8000-000000000003";
  const calls = [];
  const rpcCalls = [];
  const client = {
    auth: {
      getSession: async ()=>({ data: { session: {} }, error: null }),
      getUser: async ()=>({ data: { user: { id: "owner" } }, error: null }),
    },
    rpc: async (name, input) => {
      rpcCalls.push({ name, input });
      if (cancelFails) throw new Error("primary-cancel-failure");
      return { data: { status: "CANCELLED" }, error: null };
    },
  };
  const invoke = async (input) => {
    calls.push(input);
    if (input.action === "get_current_operator_identity") return { role: "owner", status: "ACTIVE" };
    if (input.action === "create_customer_request_smoke_fixture") return calls.filter((call)=>call.action === input.action).length === 1 ? fixture : { ...fixture, replayed: true };
    if (input.action === "create_customer_request_upload_link") {
      if (linkCreateFails) throw new Error("link-create-failure");
      return { state: "ACTIVE", was_created: true, upload_request_id: uploadRequestId, upload_url: uploadUrl };
    }
    if (input.action === "revoke_customer_request_upload_link") {
      if (revokeFails) throw new Error("cleanup-revoke-secret");
      return { state: "REVOKED", upload_request_id: uploadRequestId };
    }
    if (input.action === "finalize_internal_e2e_run") {
      if (finalizeFails) throw new Error("cleanup-finalize-secret");
      return { status: input.terminal_status };
    }
    throw new Error("UNEXPECTED_ACTION");
  };
  return {
    calls,
    rpcCalls,
    fixture,
    uploadRequestId,
    run: ()=>runInternalSmokeA({ client, invoke, resolveCapability, randomUUID: ()=>crypto.randomUUID() }),
  };
}

test("internal Smoke A cleans up a failure directly after Upload Link creation", async () => {
  const harness = createInternalSmokeFailureHarness({ uploadUrl: "not-a-valid-url" });
  const result = await harness.run();
  assert.equal(result.SMOKE_STATUS, "FAILED: UPLOAD_LINK_CREATE");
  assert.equal(harness.calls.filter((call)=>call.action === "create_customer_request_smoke_fixture").length, 2);
  assert.equal(harness.calls.filter((call)=>call.action === "create_customer_request_upload_link").length, 1);
  assert.deepEqual(harness.calls.filter((call)=>call.action === "revoke_customer_request_upload_link").map((call)=>call.upload_request_id), [harness.uploadRequestId]);
  assert.equal(harness.rpcCalls.length, 1);
  assert.equal(harness.rpcCalls[0].input.p_command_type, "CANCEL");
  assert.equal(harness.rpcCalls[0].input.p_request_id, harness.fixture.request_id);
  assert.deepEqual(harness.calls.filter((call)=>call.action === "finalize_internal_e2e_run").map((call)=>call.terminal_status), ["FAILED"]);
  assert.equal(result.revoke, "PASS");
  assert.equal(result.customer_request_final_status, "CANCELLED");
  assert.equal(result.internal_e2e_final_status, "FAILED");
});

test("internal Smoke A cleans up when positive capability resolution fails", async () => {
  const harness = createInternalSmokeFailureHarness();
  const result = await harness.run();
  assert.equal(result.SMOKE_STATUS, "FAILED: RESOLVE_BEFORE_REVOKE");
  assert.equal(harness.calls.filter((call)=>call.action === "create_customer_request_smoke_fixture").length, 2);
  assert.equal(harness.calls.filter((call)=>call.action === "create_customer_request_upload_link").length, 1);
  assert.equal(harness.calls.filter((call)=>call.action === "revoke_customer_request_upload_link").length, 1);
  assert.equal(harness.rpcCalls.length, 1);
  assert.equal(harness.calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 1);
  assert.equal(result.internal_e2e_final_status, "FAILED");
});

test("internal Smoke A continues CANCEL but skips unsafe finalization when revoke fails", async () => {
  const harness = createInternalSmokeFailureHarness({ revokeFails: true });
  const result = await harness.run();
  assert.equal(result.SMOKE_STATUS, "FAILED: RESOLVE_BEFORE_REVOKE");
  assert.equal(harness.calls.filter((call)=>call.action === "revoke_customer_request_upload_link").length, 1);
  assert.equal(harness.rpcCalls.length, 1);
  assert.equal(harness.calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 0);
  assert.equal(result.revoke, "FAIL");
  assert.equal(result.customer_request_final_status, "CANCELLED");
  assert.equal(result.internal_e2e_final_status, null);
  assert.doesNotMatch(JSON.stringify(result), /secret|token|capability/i);
});

test("internal Smoke A performs no terminal cleanup before Upload Link creation succeeds", async () => {
  const harness = createInternalSmokeFailureHarness({
    linkCreateFails: true,
    resolveCapability: async ()=>assert.fail("resolve must not run"),
  });
  const result = await harness.run();
  assert.equal(result.SMOKE_STATUS, "FAILED: UPLOAD_LINK_CREATE");
  assert.equal(harness.calls.filter((call)=>call.action === "create_customer_request_smoke_fixture").length, 2);
  assert.equal(harness.calls.filter((call)=>call.action === "create_customer_request_upload_link").length, 1);
  assert.equal(harness.calls.filter((call)=>call.action === "revoke_customer_request_upload_link").length, 0);
  assert.equal(harness.rpcCalls.length, 0);
  assert.equal(harness.calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 0);
});

function createSuccessfulResolveSequence() {
  let resolveCount = 0;
  return async () => {
    resolveCount += 1;
    return resolveCount === 1
      ? { status: 200, body: { ok: true, state: "ACTIVE", title: "LWS-SMOKE-TEST-UPLOAD-LINK-20260827", file_count: 0 } }
      : { status: 200, body: { ok: true, state: "INVALID_OR_EXPIRED_LINK" } };
  };
}

test("internal Smoke A does not retry a primary revoke exception", async () => {
  const harness = createInternalSmokeFailureHarness({
    resolveCapability: createSuccessfulResolveSequence(),
    revokeFails: true,
  });
  const result = await harness.run();
  assert.equal(result.SMOKE_STATUS, "FAILED: REVOKE");
  assert.equal(harness.calls.filter((call)=>call.action === "revoke_customer_request_upload_link").length, 1);
  assert.equal(harness.rpcCalls.length, 1);
  assert.equal(harness.calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 0);
});

test("internal Smoke A does not retry a primary CANCEL exception", async () => {
  const harness = createInternalSmokeFailureHarness({
    resolveCapability: createSuccessfulResolveSequence(),
    cancelFails: true,
  });
  const result = await harness.run();
  assert.equal(result.SMOKE_STATUS, "FAILED: CANCEL");
  assert.equal(harness.calls.filter((call)=>call.action === "revoke_customer_request_upload_link").length, 1);
  assert.equal(harness.rpcCalls.length, 1);
  assert.equal(harness.calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 0);
});

test("internal Smoke A does not replace a failed PASSED finalization with FAILED", async () => {
  const harness = createInternalSmokeFailureHarness({
    resolveCapability: createSuccessfulResolveSequence(),
    finalizeFails: true,
  });
  const result = await harness.run();
  assert.equal(result.SMOKE_STATUS, "FAILED: FINALIZE");
  assert.equal(harness.calls.filter((call)=>call.action === "revoke_customer_request_upload_link").length, 1);
  assert.equal(harness.rpcCalls.length, 1);
  assert.equal(harness.calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 1);
});

test("internal Smoke A runs one synthetic lifecycle and returns only sanitized evidence", async () => {
  const fixture = { run_id: "a1000000-0000-4000-8000-000000000001", request_id: "a1000000-0000-4000-8000-000000000002", status: "NEW", revision: 0, replayed: false };
  const uploadRequestId = "a1000000-0000-4000-8000-000000000003";
  const calls = [];
  let resolveCount = 0;
  const result = await runInternalSmokeA({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "owner" } }, error: null }),
      },
      rpc: async (name, input) => {
        calls.push({ name, input });
        return { data: { status: "CANCELLED" }, error: null };
      },
    },
    invoke: async (input) => {
      calls.push(input);
      if (input.action === "get_current_operator_identity") return { display_name: "Owner", role: "owner", status: "ACTIVE" };
      if (input.action === "create_customer_request_smoke_fixture") return calls.filter((call)=>call.action === input.action).length === 1 ? fixture : { ...fixture, replayed: true };
      if (input.action === "create_customer_request_upload_link") return { state: "ACTIVE", was_created: true, upload_request_id: uploadRequestId, upload_url: "https://operator.example/pages/customer-request-upload.html#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" };
      if (input.action === "revoke_customer_request_upload_link") return { state: "REVOKED", upload_request_id: uploadRequestId };
      if (input.action === "finalize_internal_e2e_run") return { status: "PASSED" };
      throw new Error("UNEXPECTED_ACTION");
    },
    resolveCapability: async (capability) => {
      assert.equal(capability, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
      resolveCount += 1;
      return resolveCount === 1
        ? { status: 200, body: { ok: true, state: "ACTIVE", title: "LWS-SMOKE-TEST-UPLOAD-LINK-20260827", file_count: 0 } }
        : { status: 200, body: { ok: true, state: "INVALID_OR_EXPIRED_LINK" } };
    },
    randomUUID: (()=>{ let value = 0; return ()=>`b1000000-0000-4000-8000-${String(++value).padStart(12, "0")}`; })(),
  });
  assert.deepEqual(result, {
    SMOKE_STATUS: "PASS",
    run_id: fixture.run_id,
    customer_request_id: fixture.request_id,
    replay_same_request: true,
    upload_request_id: uploadRequestId,
    resolve_before_revoke: "PASS",
    revoke: "PASS",
    resolve_after_revoke: "DENIED",
    customer_request_final_status: "CANCELLED",
    internal_e2e_final_status: "PASSED",
  });
  assert.equal(calls.filter((call)=>call.action === "create_customer_request_smoke_fixture").length, 2);
  assert.equal(calls.filter((call)=>call.action === "create_customer_request_upload_link").length, 1);
  assert.equal(calls.filter((call)=>call.action === "revoke_customer_request_upload_link").length, 1);
  assert.equal(calls.filter((call)=>call.name === "transition_customer_request_v1").length, 1);
  assert.equal(calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 1);
  assert.equal(resolveCount, 2);
  assert.deepEqual(Object.keys(result).sort(), ["SMOKE_STATUS", "customer_request_final_status", "customer_request_id", "internal_e2e_final_status", "replay_same_request", "resolve_after_revoke", "resolve_before_revoke", "revoke", "run_id", "upload_request_id"].sort());
  assert.doesNotMatch(JSON.stringify(result), /token|upload_url|Authorization|AAAA/);
});

test("internal Smoke A fails closed without retries or raw error leakage", async () => {
  const calls = [];
  const result = await runInternalSmokeA({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "owner" } }, error: null }),
      },
      rpc: async ()=>assert.fail("CANCEL must not run after fixture failure"),
    },
    invoke: async (input) => {
      calls.push(input.action);
      if (input.action === "get_current_operator_identity") return { role: "owner", status: "ACTIVE" };
      throw new Error("secret-token-must-not-render");
    },
    resolveCapability: async ()=>assert.fail("resolve must not run"),
    randomUUID: ()=>crypto.randomUUID(),
  });
  assert.deepEqual(calls, ["get_current_operator_identity", "create_customer_request_smoke_fixture"]);
  assert.equal(result.SMOKE_STATUS, "FAILED: FIXTURE_CREATE");
  assert.doesNotMatch(JSON.stringify(result), /secret|token/);
});

test("internal Smoke A static UI has confirmation and no upload surface", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  const smokeARunner = script.split("export async function runInternalSmokeA")[1]?.split("const INTERNAL_SMOKE_B_FIELDS")[0] || "";
  assert.match(html, /id="internalSmokePanel"[^>]* hidden/);
  assert.match(html, /id="internalSmokeRun"/);
  assert.match(html, /id="internalSmokeResult"/);
  assert.doesNotMatch(html.match(/id="internalSmokePanel"[\s\S]*?<\/section>/)?.[0] || "", /type="file"|drop|drag/i);
  assert.match(script, /Smoke A uitvoeren\?/);
  assert.doesNotMatch(script, /console\.(?:log|error|warn)/);
  assert.doesNotMatch(smokeARunner, /prepare_customer_request_upload|finalize_customer_request_uploaded_file|signed_upload_url/);
});

test("internal Smoke B uses one fixed metadata-free in-memory PNG below 16 KiB", async () => {
  const file = createInternalSmokeBSyntheticPng();
  assert.equal(file.name, "lws-smoke-b-synthetic.png");
  assert.equal(file.blob.type, "image/png");
  assert.ok(file.blob instanceof Blob);
  assert.ok(file.blob.size > 0 && file.blob.size < 16 * 1024);
  const bytes = new Uint8Array(await file.blob.arrayBuffer());
  assert.deepEqual(Array.from(bytes.slice(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.doesNotMatch(new TextDecoder().decode(bytes), /EXIF|tEXt|iTXt|eXIf|customer|user|machine/i);
});

test("internal Smoke B blocks a non-owner before creating a fixture", async () => {
  const calls = [];
  const result = await runInternalSmokeB({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "operator" } }, error: null }),
      },
      rpc: async ()=>assert.fail("RPC must not run"),
    },
    invoke: async (input)=>{ calls.push(input.action); return { role: "operator", status: "ACTIVE" }; },
    uploadRequest: async ()=>assert.fail("upload API must not run"),
    putSignedBlob: async ()=>assert.fail("PUT must not run"),
  });
  assert.deepEqual(calls, ["get_current_operator_identity"]);
  assert.equal(result.SMOKE_STATUS, "FAILED: AUTH");
});

test("internal Smoke B runs exactly one upload and returns only sanitized deletion evidence", async () => {
  const fixture = {
    run_id: "c1000000-0000-4000-8000-000000000001",
    request_id: "c1000000-0000-4000-8000-000000000002",
    status: "NEW",
    revision: 0,
    replayed: false,
  };
  const uploadRequestId = "c1000000-0000-4000-8000-000000000003";
  const uploadedFileId = "c1000000-0000-4000-8000-000000000004";
  const capability = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
  const calls = [];
  const result = await runInternalSmokeB({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "owner" } }, error: null }),
      },
      rpc: async (name, input)=>{
        calls.push({ channel: "rpc", name, input });
        return { data: { status: "CANCELLED" }, error: null };
      },
    },
    invoke: async (input)=>{
      calls.push({ channel: "operator", ...input });
      if (input.action === "get_current_operator_identity") return { role: "owner", status: "ACTIVE" };
      if (input.action === "create_customer_request_smoke_fixture") {
        return calls.filter((call)=>call.action === input.action).length === 1 ? fixture : { ...fixture, replayed: true };
      }
      if (input.action === "create_customer_request_upload_link") return {
        state: "ACTIVE",
        was_created: true,
        upload_request_id: uploadRequestId,
        upload_url: `https://operator.example/pages/customer-request-upload.html#token=${capability}`,
      };
      if (input.action === "cleanup_internal_e2e_accepted_file") return {
        state: "DELETED",
        run_id: fixture.run_id,
        request_id: fixture.request_id,
        upload_request_id: uploadRequestId,
        uploaded_file_id: uploadedFileId,
      };
      if (input.action === "finalize_internal_e2e_run") return { status: "PASSED" };
      throw new Error(`UNEXPECTED_ACTION:${input.action}`);
    },
    uploadRequest: async (memoryCapability, request)=>{
      assert.equal(memoryCapability, capability);
      calls.push({ channel: "upload", ...request });
      if (request.method === "GET") {
        const resolveCalls = calls.filter((call)=>call.channel === "upload" && call.method === "GET").length;
        return resolveCalls === 1
          ? { state: "ACTIVE", title: "LWS-SMOKE-TEST-UPLOAD-LINK-20260827", file_count: 0 }
          : { state: "ACTIVE", files: [{ file_id: uploadedFileId, status: "ACCEPTED" }], accepted_file_count: 1 };
      }
      if (request.action === "prepare") return {
        state: "PREPARED",
        file_id: uploadedFileId,
        signed_upload_url: "https://storage.example/signed/server-derived",
      };
      if (request.action === "finalize") return { state: "ACTIVE" };
      if (request.action === "complete") return { state: "COMPLETED" };
      throw new Error("UNEXPECTED_UPLOAD_REQUEST");
    },
    putSignedBlob: async (url, blob)=>{
      calls.push({ channel: "put", url, blob });
      assert.equal(url, "https://storage.example/signed/server-derived");
      assert.equal(blob.type, "image/png");
    },
    randomUUID: (()=>{ let value = 0; return ()=>`d1000000-0000-4000-8000-${String(++value).padStart(12, "0")}`; })(),
  });

  assert.equal(result.SMOKE_STATUS, "PASS");
  assert.equal(result.replay_same_request, true);
  assert.equal(result.accepted_file_count, 1);
  assert.equal(result.upload_complete, "PASS");
  assert.equal(result.cleanup, "DELETED");
  assert.equal(result.customer_request_final_status, "CANCELLED");
  assert.equal(result.internal_e2e_final_status, "PASSED");
  assert.equal(calls.filter((call)=>call.action === "create_customer_request_smoke_fixture").length, 2);
  assert.equal(calls.filter((call)=>call.action === "create_customer_request_upload_link").length, 1);
  assert.equal(calls.filter((call)=>call.channel === "put").length, 1);
  assert.equal(calls.filter((call)=>call.action === "cleanup_internal_e2e_accepted_file").length, 1);
  assert.deepEqual(calls.filter((call)=>call.channel === "upload").map((call)=>call.action || call.method), ["GET", "prepare", "finalize", "GET", "complete"]);
  assert.ok(calls.findIndex((call)=>call.action === "cleanup_internal_e2e_accepted_file") > calls.findIndex((call)=>call.action === "complete"));
  assert.ok(calls.findIndex((call)=>call.name === "transition_customer_request_v1") > calls.findIndex((call)=>call.action === "cleanup_internal_e2e_accepted_file"));
  assert.doesNotMatch(JSON.stringify(result), /token|upload_url|signed_upload_url|Authorization|BBBB/);
});

test("lost finalize acknowledgement reconciles ACCEPTED server state", async () => {
  const fixture = {
    run_id: "c3000000-0000-4000-8000-000000000001",
    request_id: "c3000000-0000-4000-8000-000000000002",
    status: "NEW",
    revision: 0,
    replayed: false,
  };
  const uploadRequestId = "c3000000-0000-4000-8000-000000000003";
  const uploadedFileId = "c3000000-0000-4000-8000-000000000004";
  const calls = [];
  const result = await runInternalSmokeB({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "owner" } }, error: null }),
      },
      rpc: async (name, input)=>{
        calls.push({ channel: "rpc", name, input });
        return { data: { status: "CANCELLED" }, error: null };
      },
    },
    invoke: async (input)=>{
      calls.push({ channel: "operator", ...input });
      if (input.action === "get_current_operator_identity") return { role: "owner", status: "ACTIVE" };
      if (input.action === "create_customer_request_smoke_fixture") {
        return calls.filter((call)=>call.action === input.action).length === 1 ? fixture : { ...fixture, replayed: true };
      }
      if (input.action === "create_customer_request_upload_link") return {
        state: "ACTIVE",
        was_created: true,
        upload_request_id: uploadRequestId,
        upload_url: "https://operator.example/pages/customer-request-upload.html#token=DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD",
      };
      if (input.action === "cleanup_internal_e2e_accepted_file") return {
        state: "DELETED",
        run_id: fixture.run_id,
        request_id: fixture.request_id,
        upload_request_id: uploadRequestId,
        uploaded_file_id: uploadedFileId,
      };
      if (input.action === "finalize_internal_e2e_run") return { status: "PASSED" };
      throw new Error("UNEXPECTED_ACTION");
    },
    uploadRequest: async (_capability, request)=>{
      calls.push({ channel: "upload", ...request });
      if (request.method === "GET") {
        const reads = calls.filter((call)=>call.channel === "upload" && call.method === "GET").length;
        return reads === 1
          ? { state: "ACTIVE", title: "LWS-SMOKE-TEST-UPLOAD-LINK-20260827", file_count: 0 }
          : { state: "ACTIVE", files: [{ file_id: uploadedFileId, status: "ACCEPTED" }], accepted_file_count: 1 };
      }
      if (request.action === "prepare") return { state: "PREPARED", file_id: uploadedFileId, signed_upload_url: "https://storage.example/signed/lost-finalize" };
      if (request.action === "finalize") throw new Error("FINALIZE_ACK_LOST");
      if (request.action === "complete") return { state: "COMPLETED" };
      throw new Error("UNEXPECTED_UPLOAD_REQUEST");
    },
    putSignedBlob: async ()=>{ calls.push({ channel: "put" }); },
    randomUUID: ()=>crypto.randomUUID(),
  });

  assert.equal(result.SMOKE_STATUS, "PASS");
  assert.equal(result.accepted_file_count, 1);
  assert.equal(result.cleanup, "DELETED");
  assert.equal(result.internal_e2e_final_status, "PASSED");
  assert.equal(calls.filter((call)=>call.channel === "put").length, 1);
  assert.equal(calls.filter((call)=>call.action === "create_customer_request_upload_link").length, 1);
  assert.equal(calls.filter((call)=>call.action === "cleanup_internal_e2e_accepted_file").length, 1);
});

test("lost cleanup acknowledgement reconciles terminal cleanup state", async () => {
  const fixture = {
    run_id: "c4000000-0000-4000-8000-000000000001",
    request_id: "c4000000-0000-4000-8000-000000000002",
    status: "NEW",
    revision: 0,
    replayed: false,
  };
  const uploadRequestId = "c4000000-0000-4000-8000-000000000003";
  const uploadedFileId = "c4000000-0000-4000-8000-000000000004";
  const calls = [];
  let cleanupServerEffects = 0;
  const result = await runInternalSmokeB({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "owner" } }, error: null }),
      },
      rpc: async (name, input)=>{
        calls.push({ channel: "rpc", name, input });
        return { data: { status: "CANCELLED" }, error: null };
      },
    },
    invoke: async (input)=>{
      calls.push({ channel: "operator", ...input });
      if (input.action === "get_current_operator_identity") return { role: "owner", status: "ACTIVE" };
      if (input.action === "create_customer_request_smoke_fixture") {
        return calls.filter((call)=>call.action === input.action).length === 1 ? fixture : { ...fixture, replayed: true };
      }
      if (input.action === "create_customer_request_upload_link") return {
        state: "ACTIVE",
        was_created: true,
        upload_request_id: uploadRequestId,
        upload_url: "https://operator.example/pages/customer-request-upload.html#token=EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE",
      };
      if (input.action === "cleanup_internal_e2e_accepted_file") {
        if (cleanupServerEffects === 0) {
          cleanupServerEffects = 1;
          throw new Error("CLEANUP_ACK_LOST");
        }
        return {
          state: "DELETED",
          run_id: fixture.run_id,
          request_id: fixture.request_id,
          upload_request_id: uploadRequestId,
          uploaded_file_id: uploadedFileId,
        };
      }
      if (input.action === "finalize_internal_e2e_run") return { status: "PASSED" };
      throw new Error("UNEXPECTED_ACTION");
    },
    uploadRequest: async (_capability, request)=>{
      calls.push({ channel: "upload", ...request });
      if (request.method === "GET") {
        const reads = calls.filter((call)=>call.channel === "upload" && call.method === "GET").length;
        return reads === 1
          ? { state: "ACTIVE", title: "LWS-SMOKE-TEST-UPLOAD-LINK-20260827", file_count: 0 }
          : { state: "ACTIVE", files: [{ file_id: uploadedFileId, status: "ACCEPTED" }], accepted_file_count: 1 };
      }
      if (request.action === "prepare") return { state: "PREPARED", file_id: uploadedFileId, signed_upload_url: "https://storage.example/signed/lost-cleanup" };
      if (request.action === "finalize") return { state: "ACTIVE" };
      if (request.action === "complete") return { state: "COMPLETED" };
      throw new Error("UNEXPECTED_UPLOAD_REQUEST");
    },
    putSignedBlob: async ()=>{ calls.push({ channel: "put" }); },
    randomUUID: ()=>crypto.randomUUID(),
  });

  const cleanupCalls = calls.filter((call)=>call.action === "cleanup_internal_e2e_accepted_file");
  assert.equal(result.SMOKE_STATUS, "PASS");
  assert.equal(result.cleanup, "DELETED");
  assert.equal(cleanupCalls.length, 2);
  assert.equal(cleanupCalls[0].idempotency_key, cleanupCalls[1].idempotency_key);
  assert.equal(cleanupServerEffects, 1);
  assert.equal(calls.filter((call)=>call.channel === "put").length, 1);
  assert.equal(calls.filter((call)=>call.action === "create_customer_request_upload_link").length, 1);
});

test("actual cleanup failure never reports terminal cleanup success", async () => {
  const fixture = {
    run_id: "c5000000-0000-4000-8000-000000000001",
    request_id: "c5000000-0000-4000-8000-000000000002",
    status: "NEW",
    revision: 0,
    replayed: false,
  };
  const uploadRequestId = "c5000000-0000-4000-8000-000000000003";
  const uploadedFileId = "c5000000-0000-4000-8000-000000000004";
  const calls = [];
  const result = await runInternalSmokeB({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "owner" } }, error: null }),
      },
      rpc: async (name, input)=>{
        calls.push({ channel: "rpc", name, input });
        return { data: { status: "CANCELLED" }, error: null };
      },
    },
    invoke: async (input)=>{
      calls.push({ channel: "operator", ...input });
      if (input.action === "get_current_operator_identity") return { role: "owner", status: "ACTIVE" };
      if (input.action === "create_customer_request_smoke_fixture") {
        return calls.filter((call)=>call.action === input.action).length === 1 ? fixture : { ...fixture, replayed: true };
      }
      if (input.action === "create_customer_request_upload_link") return {
        state: "ACTIVE",
        was_created: true,
        upload_request_id: uploadRequestId,
        upload_url: "https://operator.example/pages/customer-request-upload.html#token=FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
      };
      if (input.action === "cleanup_internal_e2e_accepted_file") throw new Error("CLEANUP_FAILED");
      if (input.action === "finalize_internal_e2e_run") return { status: "PASSED" };
      throw new Error("UNEXPECTED_ACTION");
    },
    uploadRequest: async (_capability, request)=>{
      if (request.method === "GET") {
        const reads = calls.filter((call)=>call.channel === "upload" && call.method === "GET").length;
        calls.push({ channel: "upload", ...request });
        return reads === 0
          ? { state: "ACTIVE", title: "LWS-SMOKE-TEST-UPLOAD-LINK-20260827", file_count: 0 }
          : { state: "ACTIVE", files: [{ file_id: uploadedFileId, status: "ACCEPTED" }], accepted_file_count: 1 };
      }
      calls.push({ channel: "upload", ...request });
      if (request.action === "prepare") return { state: "PREPARED", file_id: uploadedFileId, signed_upload_url: "https://storage.example/signed/cleanup-failure" };
      if (request.action === "finalize") return { state: "ACTIVE" };
      if (request.action === "complete") return { state: "COMPLETED" };
      throw new Error("UNEXPECTED_UPLOAD_REQUEST");
    },
    putSignedBlob: async ()=>{},
    randomUUID: ()=>crypto.randomUUID(),
  });

  assert.equal(result.SMOKE_STATUS, "FAILED: CLEANUP");
  assert.equal(result.cleanup, "FAIL");
  assert.equal(result.internal_e2e_final_status, null);
  assert.notEqual(result.SMOKE_STATUS, "PASS");
  const cleanupCalls = calls.filter((call)=>call.action === "cleanup_internal_e2e_accepted_file");
  assert.equal(cleanupCalls.length, 2);
  assert.equal(cleanupCalls[0].idempotency_key, cleanupCalls[1].idempotency_key);
  assert.equal(calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 0);
});

test("internal Smoke B revokes before cleaning an accepted partial upload and failing terminally", async () => {
  const fixture = {
    run_id: "c2000000-0000-4000-8000-000000000001",
    request_id: "c2000000-0000-4000-8000-000000000002",
    status: "NEW",
    revision: 0,
    replayed: false,
  };
  const uploadRequestId = "c2000000-0000-4000-8000-000000000003";
  const uploadedFileId = "c2000000-0000-4000-8000-000000000004";
  const calls = [];
  let readCount = 0;
  const result = await runInternalSmokeB({
    client: {
      auth: {
        getSession: async ()=>({ data: { session: {} }, error: null }),
        getUser: async ()=>({ data: { user: { id: "owner" } }, error: null }),
      },
      rpc: async (name, input)=>{
        calls.push({ channel: "rpc", name, input });
        return { data: { status: "CANCELLED" }, error: null };
      },
    },
    invoke: async (input)=>{
      calls.push({ channel: "operator", ...input });
      if (input.action === "get_current_operator_identity") return { role: "owner", status: "ACTIVE" };
      if (input.action === "create_customer_request_smoke_fixture") {
        return calls.filter((call)=>call.action === input.action).length === 1 ? fixture : { ...fixture, replayed: true };
      }
      if (input.action === "create_customer_request_upload_link") return {
        state: "ACTIVE",
        was_created: true,
        upload_request_id: uploadRequestId,
        upload_url: "https://operator.example/pages/customer-request-upload.html#token=CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
      };
      if (input.action === "cleanup_internal_e2e_accepted_file") return {
        state: "DELETED",
        run_id: fixture.run_id,
        request_id: fixture.request_id,
        upload_request_id: uploadRequestId,
        uploaded_file_id: uploadedFileId,
      };
      if (input.action === "revoke_customer_request_upload_link") return { state: "REVOKED", upload_request_id: uploadRequestId };
      if (input.action === "finalize_internal_e2e_run") return { status: "FAILED" };
      throw new Error("UNEXPECTED_ACTION");
    },
    uploadRequest: async (_capability, request)=>{
      calls.push({ channel: "upload", ...request });
      if (request.method === "GET") {
        readCount += 1;
        if (readCount === 1) return { state: "ACTIVE", title: "LWS-SMOKE-TEST-UPLOAD-LINK-20260827", file_count: 0 };
        throw new Error("LIST_FAILED_AFTER_ACCEPT");
      }
      if (request.action === "prepare") return { state: "PREPARED", file_id: uploadedFileId, signed_upload_url: "https://storage.example/signed/partial" };
      if (request.action === "finalize") return { state: "ACTIVE" };
      throw new Error("UNEXPECTED_UPLOAD_REQUEST");
    },
    putSignedBlob: async ()=>{},
    randomUUID: ()=>crypto.randomUUID(),
  });

  assert.equal(result.SMOKE_STATUS, "FAILED: LIST_ACCEPTED");
  assert.equal(result.cleanup, "DELETED");
  assert.equal(result.customer_request_final_status, "CANCELLED");
  assert.equal(result.internal_e2e_final_status, "FAILED");
  assert.equal(calls.filter((call)=>call.action === "cleanup_internal_e2e_accepted_file").length, 1);
  assert.equal(calls.filter((call)=>call.action === "revoke_customer_request_upload_link").length, 1);
  assert.equal(calls.filter((call)=>call.name === "transition_customer_request_v1").length, 1);
  assert.equal(calls.filter((call)=>call.action === "finalize_internal_e2e_run").length, 1);
  assert.ok(calls.findIndex((call)=>call.action === "revoke_customer_request_upload_link") < calls.findIndex((call)=>call.action === "cleanup_internal_e2e_accepted_file"));
  assert.doesNotMatch(JSON.stringify(result), /token|upload_url|signed_upload_url|Authorization|CCCC/);
});

test("internal Smoke B static UI is separate, hidden, confirmed, and has no capability surface", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="internalSmokeBPanel"[^>]* hidden/);
  assert.match(html, /id="internalSmokeBRun"/);
  assert.match(html, /id="internalSmokeBResult"/);
  const panel = html.match(/id="internalSmokeBPanel"[\s\S]*?<\/section>/)?.[0] || "";
  assert.doesNotMatch(panel, /type="file"|upload_url|signed_upload_url|token|capability/i);
  assert.match(script, /Smoke B uitvoeren\?/);
  assert.match(script, /createInternalSmokeOneShotTrigger/);
  assert.doesNotMatch(script, /localStorage|sessionStorage|console\.(?:log|error|warn)/);
});

test("owner module shell exposes six accessible query-routed modules without mock data", async () => {
  const [html, css] = await Promise.all([read("operator/dashboard/index.html"), read("assets/css/operator-dashboard.css")]);
  const modules = [["dossiers", "Dossiers"], ["finance", "Financieel"], ["workforce", "Personeel"], ["recruitment", "Rekrutering"], ["messages", "Berichten"], ["calendar", "Kalender"]];
  for (const [module, label] of modules) {
    assert.match(html, new RegExp(`href="/operator/dashboard/\\?module=${module}"[^>]*data-operator-module="${module}"[^>]*>${label}</a>`));
  }
  const navigation = html.match(/<nav id="operatorModuleNavigation"[\s\S]*?<\/nav>/)?.[0] || "";
  assert.deepEqual([...navigation.matchAll(/data-operator-module="([^"]+)"/g)].map((match) => match[1]), modules.map(([module]) => module));
  for (const [module, title] of modules.slice(1)) {
    assert.match(html, new RegExp(`data-module-panel="${module}"[\\s\\S]{0,180}<h1[^>]*>${title}</h1>`));
  }
  assert.match(html, /id="operatorModuleNavigation"[^>]*aria-label="Operatormodules"[^>]*hidden/);
  assert.doesNotMatch(html, /fictieve|testbedrag|ongelezen bericht/i);
  assert.match(css, /\.module-navigation a\[aria-current="page"\]/);
  assert.match(css, /@media \(max-width:1100px\)/);
  assert.match(css, /\.module-navigation \{[^}]*flex-wrap:wrap/);
  assert.match(css, /@media \(max-width:540px\)[^{]*\{[^}]*\.topbar[^}]*grid-template-columns:1fr/);
});

test("module routing defaults and fails safe to dossiers", () => {
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/", "owner"), "dossiers");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=finance", "owner"), "finance");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=workforce", "owner"), "workforce");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=recruitment", "owner"), "recruitment");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=messages", "owner"), "messages");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=calendar", "owner"), "calendar");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=unknown", "owner"), "dossiers");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=recruitment", "operator"), "dossiers");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=finance", "operator"), "dossiers");
});

test("recruitment route remains active when the URL is resolved after refresh", () => {
  const url = "https://operator.example/operator/dashboard/?module=recruitment";
  assert.equal(operatorModuleFromUrl(url, "owner"), "recruitment");
  assert.equal(operatorModuleFromUrl(url, "owner"), "recruitment");
});

test("application and legacy dossier locators always activate dossiers", () => {
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=recruitment&application=LWS-AAN-2026-0003", "owner"), "dossiers");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=finance&application=LWS-AAN-2026-0003", "owner"), "dossiers");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=calendar&request=19877689-7c72-4ad4-9a7c-7b9459b22ea1", "owner"), "dossiers");
  assert.equal(operatorModuleFromUrl("https://operator.example/operator/dashboard/?module=messages&support=B4D5140C", "owner"), "dossiers");
});

test("module motion remains decorative, finite, and reduced-motion safe", async () => {
  const [html, css] = await Promise.all([read("operator/dashboard/index.html"), read("assets/css/operator-dashboard.css")]);
  assert.match(html, /class="finance-visual" aria-hidden="true"/);
  assert.match(html, /class="finance-visual__graph"[\s\S]*class="finance-visual__line"/);
  assert.match(html, /class="finance-visual__laser"/);
  const financeGraph = html.match(/<div class="finance-visual"[\s\S]*?<\/svg><\/div>/)?.[0] || "";
  assert.doesNotMatch(financeGraph, /€|EUR|omzet|openstaand|betaald|periode|maand/i);
  assert.match(css, /@keyframes module-nav-reveal/);
  assert.match(css, /@keyframes module-panel-enter/);
  assert.match(css, /@keyframes module-title-sweep/);
  assert.match(css, /@keyframes finance-line-draw/);
  assert.match(css, /@media \(prefers-reduced-motion:reduce\)/);
  assert.match(css, /prefers-reduced-motion:reduce[\s\S]*animation:none!important/);
  assert.doesNotMatch(css, /infinite/);
});

test("finance tab routing is closed, persistent, and cannot override application deeplinks", () => {
  assert.equal(financeTabFromUrl("https://example.test/operator/dashboard/?module=finance", "owner"), "overview");
  assert.equal(financeTabFromUrl("https://example.test/operator/dashboard/?module=finance&financeTab=websites", "owner"), "websites");
  assert.equal(financeTabFromUrl("https://example.test/operator/dashboard/?module=finance&financeTab=sdf", "owner"), "sdf");
  assert.equal(financeTabFromUrl("https://example.test/operator/dashboard/?module=finance&financeTab=expenses", "owner"), "expenses");
  assert.equal(financeTabFromUrl("https://example.test/operator/dashboard/?module=finance&financeTab=inbox", "owner"), "inbox");
  assert.equal(financeTabFromUrl("https://example.test/operator/dashboard/?module=finance&financeTab=unknown", "owner"), "overview");
  assert.equal(financeTabFromUrl("https://example.test/operator/dashboard/?module=finance&financeTab=websites&application=LWS-AAN-2099-0001", "owner"), "overview");
  assert.equal(operatorModuleFromUrl("https://example.test/operator/dashboard/?module=finance&financeTab=websites&application=LWS-AAN-2099-0001", "owner"), "dossiers");
  assert.equal(financeTabFromUrl("https://example.test/operator/dashboard/?module=finance&financeTab=websites", "operator"), "overview");
});

const inboxItem = (overrides = {}) => ({
  id: "f6d00000-0000-4000-8000-000000000001", lifecycle_status: "REVIEW_REQUIRED", revision: 2,
  received_at: "2026-08-29T09:00:00Z", record_classification: "internal_e2e", warnings: [],
  proposed_supplier_name: "Proposed BV", proposed_document_reference: "P-100", proposed_document_type: "INVOICE",
  confirmed_supplier_name: null, confirmed_document_reference: null, confirmed_document_type: null,
  ...overrides,
});
const inboxValues = () => ({
  supplier_name: " Leverancier BV ", document_type: "INVOICE", document_reference: " INV-100 ",
  document_date: "2026-08-28", amount: "121,00", currency: "EUR", description: " Hosting ",
  category: "hosting", expense_date: "2026-08-29", relation_type: "INVOICE",
});

test("document inbox presentation supports exactly five authoritative statuses", () => {
  assert.deepEqual(DOCUMENT_INBOX_STATUSES, ["RECEIVED", "REVIEW_REQUIRED", "APPROVED", "PROCESSED", "REJECTED"]);
  assert.deepEqual(DOCUMENT_INBOX_STATUSES.map((status)=>documentInboxStatusPresentation(status).label), ["Ontvangen", "Te beoordelen", "Goedgekeurd", "Verwerkt", "Afgewezen"]);
  assert.deepEqual(DOCUMENT_INBOX_DOCUMENT_TYPES, ["INVOICE", "CREDIT_NOTE", "RECEIPT", "CONTRACT", "OTHER"]);
  assert.deepEqual(DOCUMENT_INBOX_CATEGORIES, ["software", "hosting", "telecom", "accounting", "hardware", "marketing", "insurance", "education", "office", "transport", "other"]);
  assert.throws(()=>documentInboxStatusPresentation("FAILED"), /INVALID_DOCUMENT_INBOX_STATUS/);
  assert.equal(documentInboxReadPresentation({ scope: "document_inbox", items: [inboxItem()] }).items.length, 1);
  assert.throws(()=>documentInboxReadPresentation({ scope: "document_inbox", items: [inboxItem({ warnings: null })] }), /INVALID_DOCUMENT_INBOX_ITEM/);
});

test("document inbox filters are view-only and cover search status type date and ordering", () => {
  const items = [
    inboxItem(),
    inboxItem({ id: "f6d00000-0000-4000-8000-000000000002", lifecycle_status: "PROCESSED", revision: 4, received_at: "2026-08-28T09:00:00Z", confirmed_supplier_name: "Confirmed NV", confirmed_document_reference: "C-200", confirmed_document_type: "RECEIPT" }),
  ];
  assert.deepEqual(documentInboxFilter(items, { search: "confirmed", status: "PROCESSED", documentType: "RECEIPT", from: "2026-08-28", to: "2026-08-28" }).map(({ id })=>id), [items[1].id]);
  assert.deepEqual(documentInboxFilter(items, { sort: "oldest" }).map(({ id })=>id), [items[1].id, items[0].id]);
  assert.equal(items.length, 2);
});

test("document inbox commands expose only exact RPC parameters and lifecycle steps", () => {
  const review = inboxItem({ warnings: [{ code: "CHECK_TOTAL" }] });
  const proposed = documentInboxProposalRequest(review, inboxValues());
  const confirmed = documentInboxConfirmRequest(review, inboxValues());
  assert.deepEqual(Object.keys(proposed), [...Object.keys(confirmed), "p_warnings"]);
  assert.deepEqual(confirmed, {
    p_inbox_item_id: review.id, p_expected_revision: 2, p_supplier_name: "Leverancier BV",
    p_document_type: "INVOICE", p_document_reference: "INV-100", p_document_date: "2026-08-28",
    p_amount_minor: 12100, p_currency: "EUR", p_description: "Hosting", p_category: "hosting",
    p_expense_date: "2026-08-29", p_relation_type: "INVOICE",
  });
  assert.deepEqual(documentInboxApproveRequest(review, true), { p_inbox_item_id: review.id, p_expected_revision: 2, p_acknowledge_warnings: true });
  assert.deepEqual(documentInboxRejectRequest(review, " Onjuist document "), { p_inbox_item_id: review.id, p_expected_revision: 2, p_reason: "Onjuist document" });
  assert.deepEqual(documentInboxProcessRequest(inboxItem({ lifecycle_status: "APPROVED" })), { p_inbox_item_id: review.id, p_expected_revision: 2 });
  assert.throws(()=>documentInboxConfirmRequest(inboxItem({ lifecycle_status: "RECEIVED" }), inboxValues()), /NOT_CONFIRMABLE/);
  assert.throws(()=>documentInboxProcessRequest(review), /NOT_PROCESSABLE/);
  assert.throws(()=>documentInboxConfirmRequest(review, { ...inboxValues(), currency: "USD" }), /INVALID_DOCUMENT_INBOX_VALUES/);
});

test("document inbox command controller prevents overlap and reloads authoritative state", async () => {
  const calls = [];
  let release;
  const controller = createDocumentInboxCommandController({
    execute: async (rpc, request)=>{ calls.push(["execute", rpc, request]); await new Promise((resolve)=>{ release = resolve; }); return { ok: true }; },
    reload: async ()=>calls.push(["reload"]), onBusy: (busy)=>calls.push(["busy", busy]),
    onSuccess: ()=>calls.push(["success"]), onFailure: ()=>calls.push(["failure"]),
  });
  const first = controller.submit("confirm_document_inbox_values_v1", { id: "request" });
  assert.equal(await controller.submit("approve_document_inbox_item_v1", {}), false);
  release();
  assert.equal(await first, true);
  assert.deepEqual(calls.map(([kind])=>kind), ["busy", "execute", "reload", "success", "busy"]);
});

test("document inbox direct upload uses only verified metadata and exact manual receive parameters", () => {
  const file = supplierDocumentFixture();
  const upload = supplierUploadFixture();
  assert.deepEqual(documentInboxUploadResponse(upload), { ...supplierDocumentUploadResponse(upload), code: "STORED" });
  assert.deepEqual(documentInboxReceiveRequest(file, upload), {
    p_sha256: "a".repeat(64), p_original_file_name: "factuur-2026.pdf", p_mime_type: "application/pdf",
    p_byte_count: 321, p_source_type: "MANUAL_UPLOAD", p_source_instance: null, p_external_id: null,
    p_record_classification: "production",
  });
  assert.throws(()=>documentInboxUploadResponse({ ...upload, code: "UNKNOWN" }), /INVALID_DOCUMENT_INBOX_UPLOAD_RESPONSE/);
  assert.throws(()=>documentInboxReceiveRequest(file, { ...upload, sha256: "client-value" }), /INVALID_SUPPLIER_DOCUMENT_UPLOAD_RESPONSE/);
});

test("document inbox direct upload retries receive without uploading the binary twice", async () => {
  const calls = [];
  let receiveFails = true;
  const controller = createDocumentInboxUploadController({
    uploadDocument: async ()=>{ calls.push("upload"); return supplierUploadFixture(); },
    receiveDocument: async (request)=>{ calls.push(["receive", request.p_source_type]); if (receiveFails) throw new Error("receive"); return { id: inboxItem().id, status: "RECEIVED", revision: 1, replayed: false }; },
    reloadInbox: async ()=>calls.push("reload"), onBusy: ()=>{}, onFailure: (stage)=>calls.push(`failure:${stage}`),
    onSuccess: (result)=>calls.push(["success", result.duplicate]),
  });
  assert.equal(await controller.submit(supplierDocumentFixture()), false);
  assert.equal(controller.retryStage, "receive");
  receiveFails = false;
  assert.equal(await controller.submit(supplierDocumentFixture()), true);
  assert.equal(calls.filter((call)=>call === "upload").length, 1);
  assert.deepEqual(calls.map((call)=>Array.isArray(call) ? call[0] : call), ["upload", "receive", "failure:receive", "receive", "reload", "success"]);
});

test("document inbox direct upload reports authoritative duplicate and blocks overlap", async () => {
  const calls = [];
  let releaseUpload;
  const controller = createDocumentInboxUploadController({
    uploadDocument: async ()=>{ calls.push("upload"); await new Promise((resolve)=>{ releaseUpload = resolve; }); return { ...supplierUploadFixture(), code: "DUPLICATE" }; },
    receiveDocument: async ()=>({ id: inboxItem().id, status: "RECEIVED", revision: 1, replayed: true }),
    reloadInbox: async ()=>calls.push("reload"), onBusy: (busy)=>calls.push(`busy:${busy}`), onFailure: ()=>calls.push("failure"),
    onSuccess: (result)=>calls.push(`duplicate:${result.duplicate}`),
  });
  const first = controller.submit(supplierDocumentFixture());
  assert.equal(await controller.submit(supplierDocumentFixture()), false);
  assert.equal(calls.filter((call)=>call === "upload").length, 1);
  releaseUpload();
  assert.equal(await first, true);
  assert.deepEqual(calls, ["busy:true", "upload", "reload", "duplicate:true", "busy:false"]);
});

test("document inbox direct upload UI is bounded accessible authority-only and responsive", async () => {
  const [html, script, css] = await Promise.all([
    read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js"), read("assets/css/operator-dashboard.css"),
  ]);
  const panel = html.match(/<section class="finance-tab-panel document-inbox"[\s\S]*?<\/section>/)?.[0] || "";
  const dialog = html.match(/<dialog id="documentInboxUploadDialog"[\s\S]*?<\/dialog>/)?.[0] || "";
  const uploadBlock = script.match(/const uploadController = createDocumentInboxUploadController\([\s\S]*?const controller = createDocumentInboxCommandController/)?.[0] || "";
  assert.match(panel, /id="documentInboxUploadOpen"[^>]*>Document uploaden<\/button>/);
  assert.match(panel, /id="documentInboxEmpty"[\s\S]*?Geen documenten gevonden/);
  assert.match(dialog, /aria-labelledby="documentInboxUploadTitle"/);
  assert.match(dialog, /aria-describedby="documentInboxUploadDescription"/);
  assert.match(dialog, /class="finance-modal-brand"[\s\S]*?lorenzo-web-solution-logo-transparent\.png[\s\S]*?Lorenzo <strong>Web Solutions<\/strong>/);
  assert.match(dialog, /name="file"[^>]*accept="application\/pdf,image\/png,image\/jpeg"[^>]*required/);
  assert.match(dialog, /Maximaal 10 MiB · PDF, PNG, JPEG/);
  assert.equal((dialog.match(/<label\b/g) || []).length, 1);
  assert.doesNotMatch(dialog, /bedrag|categorie|omschrijving|name="(?:amount|category|description|supplier_name|document_type)"|betaling|btw|bank|preview|ocr|gmail|drive|peppol/i);
  assert.match(uploadBlock, /client\.functions\.invoke\("supplier-document-upload", \{[\s\S]*?body: file/);
  assert.match(uploadBlock, /client\.rpc\("receive_document_inbox_item_v1", request\)/);
  assert.match(script, /p_source_type: "MANUAL_UPLOAD"/);
  assert.match(uploadBlock, /reloadInbox: \(\)=>loadDocumentInbox\(\)/);
  assert.match(uploadBlock, /Bestand veilig opgeslagen, registratie in de Inbox nog niet voltooid\./);
  assert.match(uploadBlock, /Dit document was al ontvangen\./);
  for (const forbidden of ["create_business_expense_v1", "create_supplier_document_v1", "link_business_expense_document_v1", "approve_document_inbox_item_v1", "process_document_inbox_item_v1"]) {
    assert.doesNotMatch(uploadBlock, new RegExp(`client\\.rpc\\("${forbidden}"`));
  }
  assert.match(css, /dialog\.operator-modal--work \{ width:90vw; \}/);
  assert.doesNotMatch(css, /dialog\.operator-modal--work \{[^}]*128rem/);
  assert.match(css, /\.document-inbox-upload-zone \{[^}]*min-height:190px/);
  assert.match(css, /@media \(max-width:540px\)[\s\S]*?\.document-inbox-upload-actions \{ flex-direction:column-reverse; \}/);
  assert.match(css, /@media \(prefers-reduced-motion:reduce\)/);
});

test("document inbox UI preserves backend authority lifecycle and responsive review semantics", async () => {
  const [html, script, css] = await Promise.all([
    read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js"), read("assets/css/operator-dashboard.css"),
  ]);
  const panel = html.match(/<section class="finance-tab-panel document-inbox"[\s\S]*?<\/section>/)?.[0] || "";
  const dialog = html.match(/<dialog id="documentInboxDialog"[\s\S]*?<\/dialog>/)?.[0] || "";
  assert.match(panel, /data-finance-tab-panel="inbox"/);
  for (const label of ["Ontvangen", "Te beoordelen", "Goedgekeurd", "Verwerkt", "Afgewezen"]) assert.match(`${panel}${script}`, new RegExp(label));
  for (const control of ["documentInboxSearch", "documentInboxStatusFilter", "documentInboxTypeFilter", "documentInboxFrom", "documentInboxTo", "documentInboxSort", "documentInboxClearFilters"]) assert.match(panel, new RegExp(`id="${control}"`));
  assert.match(dialog, /id="documentInboxProposedTitle">Voorgesteld/);
  assert.match(dialog, /id="documentInboxConfirmedTitle">Bevestigd/);
  assert.match(dialog, /id="documentInboxWarnings"/);
  assert.match(dialog, /id="documentInboxProcessedResult"/);
  for (const action of ["documentInboxSaveProposal", "documentInboxSaveConfirmed", "documentInboxApprove", "documentInboxReject", "documentInboxProcess"]) assert.match(dialog, new RegExp(`id="${action}"`));
  assert.equal((script.match(/client\.rpc\("get_document_inbox_v1"/g) || []).length, 1);
  assert.match(script, /client\.rpc\("get_document_inbox_v1", \{ p_lifecycle_status: null, p_record_classification: "production" \}\)/);
  assert.doesNotMatch(script, /\.from\(["']document_inbox_items["']\)/);
  for (const rpc of ["update_document_inbox_proposal_v1", "confirm_document_inbox_values_v1", "approve_document_inbox_item_v1", "reject_document_inbox_item_v1", "process_document_inbox_item_v1"]) assert.match(script, new RegExp(`"${rpc}"`));
  assert.match(script, /filters\.addEventListener\("(?:input|change)", renderInboxList\)/);
  assert.match(script, /processedResult\.hidden = item\.lifecycle_status !== "PROCESSED"/);
  assert.match(script, /reject\.hidden = !\["RECEIVED", "REVIEW_REQUIRED"\]\.includes/);
  assert.match(script, /const editable = \["RECEIVED", "REVIEW_REQUIRED"\]\.includes/);
  assert.match(script, /inboxItems\.find\(\(item\)=>item\.id === selectedInboxItem\.id\)/);
  assert.match(script, /form\.addEventListener\("input", \(\)=>\{ confirmedFormDirty = true; approve\.disabled = true; \}\)/);
  assert.match(script, /process\.textContent = item\.processing_error_code \? "Opnieuw proberen" : "Verwerken"/);
  assert.doesNotMatch(`${html}${script}`, /Proposed BV|Confirmed NV|INV-100/);
  assert.match(css, /\.document-inbox-values--proposed[^}]*border-left:4px solid #b67b10/);
  assert.match(css, /\.document-inbox-values--confirmed[^}]*border-left:4px solid var\(--turquoise-deep\)/);
  assert.match(css, /\.document-inbox-review__body[^}]*overflow:auto/);
  assert.match(css, /@media \(max-width:900px\)[^{]*\{[^}]*\.document-inbox-filters/);
  assert.match(css, /@media \(max-width:540px\)[\s\S]*?\.document-inbox-filters/);
  assert.match(css, /@media \(prefers-reduced-motion:reduce\)/);
});

test("finance contains exactly seven internal query-routed tabs and defaults to overview", async () => {
  const html = await read("operator/dashboard/index.html");
  const navigation = html.match(/<nav class="finance-tabs"[\s\S]*?<\/nav>/)?.[0] || "";
  const expected = [
    ["overview", "Overzicht / Budgetbeheer"], ["websites", "Websites"], ["sdf", "SDF"],
    ["workforce", "Werknemers"], ["expenses", "Bedrijfskosten"], ["inbox", "Documenten"], ["owner", "Eigenaar"],
  ];
  assert.deepEqual([...navigation.matchAll(/data-finance-tab="([^"]+)"[^>]*>([^<]+)<\/a>/g)].map((match)=>[match[1], match[2]]), expected);
  assert.match(navigation, /href="\/operator\/dashboard\/\?module=finance" data-finance-tab="overview"/);
  assert.match(navigation, /module=finance&amp;financeTab=websites/);
  assert.match(navigation, /module=finance&amp;financeTab=expenses/);
  assert.match(navigation, /module=finance&amp;financeTab=inbox/);
  assert.equal((html.match(/data-finance-tab-panel=/g) || []).length, 7);
});

const emptyBusinessExpensePortfolio = () => ({
  scope: "business_expenses",
  expense_count: 0,
  currency_totals: [],
  expenses: [],
  availability: {
    payment_state_available: false, paid_amount_available: false, paid_date_available: false,
    confirmed_cash_out_available: false, outstanding_available: false, overdue_available: false,
    upcoming_available: false, vat_available: false, deductible_vat_available: false,
    bank_actuals_available: false, recurring_available: false,
  },
  bank_actuals: null,
});

test("business expense amount input converts exact decimal strings to positive minor units", () => {
  assert.equal(businessExpenseAmountMinor("12,50"), 1250);
  assert.equal(businessExpenseAmountMinor("12.5"), 1250);
  assert.equal(businessExpenseAmountMinor("0,01"), 1);
  assert.equal(businessExpenseAmountMinor(" 7 "), 700);
  for (const invalid of ["", "0", "0,00", "-1", "1,234", "1.2.3", "90071992547409,92"]) {
    assert.equal(businessExpenseAmountMinor(invalid), null);
  }
});

test("business expense create request is bounded to the six production authority fields", () => {
  const request = businessExpenseCreateRequest({ supplier_name: "  Supplier  ", description: "  Tool  ", category: "software", amount: "12,50", currency: "EUR", expense_date: "2026-08-29" });
  assert.deepEqual(request, { p_supplier_name: "Supplier", p_description: "Tool", p_category: "software", p_amount_minor: 1250, p_currency: "EUR", p_expense_date: "2026-08-29" });
  for (const override of [{ supplier_name: " " }, { description: " " }, { category: "travel" }, { amount: "0" }, { currency: "USD" }, { expense_date: "" }]) {
    assert.throws(()=>businessExpenseCreateRequest({ supplier_name: "Supplier", description: "Tool", category: "software", amount: "12,50", currency: "EUR", expense_date: "2026-08-29", ...override }), /INVALID_BUSINESS_EXPENSE_ENTRY/);
  }
});

test("business expense entry controller prevents overlap and reloads only after successful create", async () => {
  let releaseCreate;
  const calls = [];
  const errors = [];
  const controller = createBusinessExpenseEntryController({
    createExpense: async (request)=>{ calls.push(["create", request]); await new Promise((resolve)=>{ releaseCreate = resolve; }); return "expense-id"; },
    reloadPortfolio: async ()=>calls.push(["reload"]),
    onBusy: (busy)=>calls.push(["busy", busy]),
    onCreated: (id)=>calls.push(["created", id]),
    onError: (error)=>errors.push(error),
  });
  const values = { supplier_name: "Supplier", description: "Tool", category: "software", amount: "12,50", currency: "EUR", expense_date: "2026-08-29" };
  const first = controller.submit(values);
  const second = await controller.submit(values);
  assert.equal(second, false);
  assert.equal(calls.filter(([kind])=>kind === "create").length, 1);
  releaseCreate();
  assert.equal(await first, true);
  assert.deepEqual(calls.map(([kind])=>kind), ["busy", "create", "created", "reload", "busy"]);
  assert.equal(errors.length, 0);
});

test("business expense entry controller reports create errors without reload or created state", async () => {
  const calls = [];
  const controller = createBusinessExpenseEntryController({
    createExpense: async ()=>{ throw new Error("backend"); },
    reloadPortfolio: async ()=>calls.push("reload"),
    onBusy: ()=>{}, onCreated: ()=>calls.push("created"), onError: ()=>calls.push("error"),
  });
  assert.equal(await controller.submit({ supplier_name: "Supplier", description: "Tool", category: "software", amount: "1", currency: "EUR", expense_date: "2026-08-29" }), false);
  assert.deepEqual(calls, ["error"]);
});

const supplierDocumentFixture = () => ({ name: "factuur-2026.pdf", type: "application/pdf", size: 321 });
const supplierUploadFixture = () => ({
  ok: true,
  code: "STORED",
  bucket: "supplier-documents",
  object_path: `documents/${"a".repeat(64)}.pdf`,
  sha256: "a".repeat(64),
  byte_count: 321,
  mime_type: "application/pdf",
});
const supplierDocumentValues = () => ({
  document_type: "INVOICE",
  supplier_name: " Leverancier BV ",
  document_reference: " INV-2026-01 ",
  document_date: "2026-08-29",
  relation_type: "INVOICE",
});

test("supplier document form contracts expose exact types and client file boundaries", () => {
  const exactTypes = ["INVOICE", "CREDIT_NOTE", "RECEIPT", "CONTRACT", "OTHER"];
  assert.deepEqual(SUPPLIER_DOCUMENT_TYPES, exactTypes);
  assert.deepEqual(SUPPLIER_DOCUMENT_RELATION_TYPES, exactTypes);
  assert.equal(SUPPLIER_DOCUMENT_ACCEPT, "application/pdf,image/png,image/jpeg");
  assert.equal(SUPPLIER_DOCUMENT_MAX_BYTES, 10485760);
  for (const type of SUPPLIER_DOCUMENT_ACCEPT.split(",")) {
    assert.equal(supplierDocumentFileError({ name: "document", type, size: 1 }), null);
  }
  assert.equal(supplierDocumentFileError({ name: "document.txt", type: "text/plain", size: 1 }), "INVALID_MIME");
  assert.equal(supplierDocumentFileError({ name: "large.pdf", type: "application/pdf", size: 10485761 }), "FILE_TOO_LARGE");
});

test("supplier document create and link requests use only exact server-authoritative contracts", () => {
  const upload = supplierDocumentUploadResponse(supplierUploadFixture());
  assert.deepEqual(upload, {
    bucket: "supplier-documents", object_path: `documents/${"a".repeat(64)}.pdf`, sha256: "a".repeat(64),
    byte_count: 321, mime_type: "application/pdf",
  });
  assert.deepEqual(supplierDocumentCreateRequest(supplierDocumentValues(), supplierDocumentFixture(), upload), {
    p_document_type: "INVOICE", p_supplier_name: "Leverancier BV", p_document_reference: "INV-2026-01",
    p_document_date: "2026-08-29", p_original_file_name: "factuur-2026.pdf", p_mime_type: "application/pdf",
    p_byte_count: 321, p_sha256: "a".repeat(64),
  });
  assert.deepEqual(businessExpenseDocumentLinkRequest(
    "f6e00000-0000-4000-8000-000000000001", "f6d00000-0000-4000-8000-000000000001", "INVOICE",
  ), {
    p_business_expense_id: "f6e00000-0000-4000-8000-000000000001",
    p_supplier_document_id: "f6d00000-0000-4000-8000-000000000001",
    p_relation_type: "INVOICE",
  });
  assert.throws(()=>supplierDocumentUploadResponse({ ...supplierUploadFixture(), sha256: "client-value" }), /INVALID_SUPPLIER_DOCUMENT_UPLOAD_RESPONSE/);
  assert.throws(()=>supplierDocumentCreateRequest({ ...supplierDocumentValues(), document_type: "PAYMENT_EVIDENCE" }, supplierDocumentFixture(), upload), /INVALID_SUPPLIER_DOCUMENT_ENTRY/);
});

test("supplier document flow runs upload then create then link then authoritative reload", async () => {
  const calls = [];
  const controller = createSupplierDocumentExpenseLinkController({
    uploadDocument: async (file)=>{ calls.push(["upload", file]); return supplierUploadFixture(); },
    createDocument: async (request)=>{ calls.push(["create", request]); return "f6d00000-0000-4000-8000-000000000001"; },
    linkDocument: async (request)=>{ calls.push(["link", request]); return "f6f00000-0000-4000-8000-000000000001"; },
    reloadPortfolio: async ()=>calls.push(["reload"]),
    onBusy: (busy)=>calls.push(["busy", busy]), onFailure: ()=>calls.push(["failure"]), onSuccess: ()=>calls.push(["success"]),
  });
  assert.equal(await controller.submit({ expenseId: "f6e00000-0000-4000-8000-000000000001", file: supplierDocumentFixture(), values: supplierDocumentValues() }), true);
  assert.deepEqual(calls.map(([kind])=>kind), ["busy", "upload", "create", "link", "reload", "success", "busy"]);
  assert.equal(controller.retryStage, null);
});

test("supplier document flow stops at each failure and retries only the incomplete checkpoint", async () => {
  for (const failedStage of ["upload", "create", "link"]) {
    const calls = [];
    let fail = true;
    const controller = createSupplierDocumentExpenseLinkController({
      uploadDocument: async ()=>{ calls.push("upload"); if (failedStage === "upload" && fail) throw new Error("upload"); return supplierUploadFixture(); },
      createDocument: async ()=>{ calls.push("create"); if (failedStage === "create" && fail) throw new Error("create"); return "f6d00000-0000-4000-8000-000000000001"; },
      linkDocument: async ()=>{ calls.push("link"); if (failedStage === "link" && fail) throw new Error("link"); },
      reloadPortfolio: async ()=>calls.push("reload"), onBusy: ()=>{}, onFailure: (stage)=>calls.push(`failure:${stage}`), onSuccess: ()=>calls.push("success"),
    });
    const input = { expenseId: "f6e00000-0000-4000-8000-000000000001", file: supplierDocumentFixture(), values: supplierDocumentValues() };
    assert.equal(await controller.submit(input), false);
    const beforeRetry = [...calls];
    fail = false;
    assert.equal(await controller.submit(input), true);
    assert.equal(calls.filter((call)=>call === "upload").length, failedStage === "upload" ? 2 : 1);
    assert.equal(calls.filter((call)=>call === "create").length, failedStage === "create" ? 2 : 1);
    assert.equal(calls.filter((call)=>call === "link").length, failedStage === "link" ? 2 : 1);
    if (failedStage === "upload") assert.deepEqual(beforeRetry, ["upload", "failure:upload"]);
    if (failedStage === "create") assert.deepEqual(beforeRetry, ["upload", "create", "failure:create"]);
    if (failedStage === "link") assert.deepEqual(beforeRetry, ["upload", "create", "link", "failure:link"]);
  }
});

test("supplier document flow blocks overlapping submits and cancel reset performs no writes", async () => {
  let releaseUpload;
  const calls = [];
  const controller = createSupplierDocumentExpenseLinkController({
    uploadDocument: async ()=>{ calls.push("upload"); await new Promise((resolve)=>{ releaseUpload = resolve; }); return supplierUploadFixture(); },
    createDocument: async ()=>"f6d00000-0000-4000-8000-000000000001", linkDocument: async ()=>{}, reloadPortfolio: async ()=>{},
    onBusy: ()=>{}, onFailure: ()=>{}, onSuccess: ()=>{},
  });
  controller.reset();
  assert.deepEqual(calls, []);
  const input = { expenseId: "f6e00000-0000-4000-8000-000000000001", file: supplierDocumentFixture(), values: supplierDocumentValues() };
  const first = controller.submit(input);
  assert.equal(await controller.submit(input), false);
  assert.equal(calls.filter((call)=>call === "upload").length, 1);
  releaseUpload();
  assert.equal(await first, true);
});

test("supplier document expense UI preserves the exact frontend-only production contract", async () => {
  const [html, script, css] = await Promise.all([
    read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js"), read("assets/css/operator-dashboard.css"),
  ]);
  const dialog = html.match(/<dialog id="supplierDocumentDialog"[\s\S]*?<\/dialog>/)?.[0] || "";
  const fields = [...dialog.matchAll(/name="([^"]+)"/g)].map((match)=>match[1]);
  const selects = [...dialog.matchAll(/<select[^>]*name="(?:document_type|relation_type)"[\s\S]*?<\/select>/g)]
    .map((select)=>[...select[0].matchAll(/<option value="([A-Z_]+)">/g)].map((option)=>option[1]));
  assert.match(script, /textContent = "Document toevoegen"/);
  assert.match(script, /setAttribute\("aria-label", `Document toevoegen voor \$\{expense\.supplier_name\}`\)/);
  assert.deepEqual(fields, ["file", "document_type", "supplier_name", "document_reference", "document_date", "relation_type"]);
  assert.deepEqual(selects, [SUPPLIER_DOCUMENT_TYPES, SUPPLIER_DOCUMENT_RELATION_TYPES]);
  assert.match(dialog, /name="file"[^>]*type="file"[^>]*accept="application\/pdf,image\/png,image\/jpeg"[^>]*required/);
  assert.match(dialog, /name="supplier_name"[^>]*required/);
  assert.match(script, /documentSupplier\.value = expense\.supplier_name/);
  assert.match(script, /client\.functions\.invoke\("supplier-document-upload", \{[\s\S]*?body: file/);
  assert.equal((script.match(/client\.functions\.invoke\("supplier-document-upload"/g) || []).length, 2);
  assert.doesNotMatch(script, /client\.storage\.from\(/);
  assert.doesNotMatch(script, /client\.from\("(?:business_expenses|supplier_documents|business_expense_documents)"\)/);
  assert.match(script, /client\.rpc\("create_supplier_document_v1", request\)/);
  assert.match(script, /client\.rpc\("link_business_expense_document_v1", request\)/);
  assert.match(script, /reloadPortfolio: \(\)=>loadBusinessExpensePortfolio\("Document opgeslagen en gekoppeld\."\)/);
  assert.match(script, /Document kon niet veilig worden geüpload\./);
  assert.match(script, /Document kon niet worden geregistreerd\./);
  assert.match(script, /Document is opgeslagen maar kon niet aan de bedrijfskost worden gekoppeld\./);
  assert.match(script, /documentSubmit\.disabled = busy/);
  assert.match(script, /documentController\.retryStage/);
  assert.doesNotMatch(script, /document_count\s*(?:\+\+|\+=)|relation_types\.(?:push|splice)/);
  assert.doesNotMatch(dialog, /record_classification|internal_e2e|PAYMENT_EVIDENCE|paid|unpaid|payment|vat|btw|iban|bank|kbc|gocardless|enable banking|download|signed.?url|preview|ocr|gmail|drive|peppol|titeca|james|yuki|exact|billit/i);
  assert.match(dialog, /src="\/assets\/images\/branding\/logo\/lorenzo-web-solution-logo-transparent\.png"/);
  assert.doesNotMatch(dialog, /<svg|data:image\/svg|lorenzo-web-solution-logo\.svg/i);
  assert.match(dialog, /Maximaal 10 MiB · PDF, PNG, JPEG/);
  assert.doesNotMatch(dialog, /25\s*(?:MB|MiB)|DOCX/i);
  assert.match(dialog, /id="supplierDocumentCancel"[^>]*>Annuleren<\/button>/);
  assert.match(dialog, /id="supplierDocumentSubmit"[^>]*>Document opslaan en koppelen<\/button>/);
  assert.match(dialog, /aria-labelledby="supplierDocumentDialogTitle"/);
  assert.match(dialog, /aria-describedby="supplierDocumentExpense"/);
  assert.equal((dialog.match(/<label\b/g) || []).length, 6);
  assert.match(css, /\.supplier-document-dialog \{ overflow:auto; \}/);
  assert.match(css, /@media \(max-width:540px\)[^{]*\{[\s\S]*?\.supplier-document-file \{ grid-column:auto; \}/);
  assert.equal((html.match(/data-finance-tab=/g) || []).length, 7);
  assert.match(html, /module=finance&amp;financeTab=inbox/);
  assert.match(html, /module=finance&amp;financeTab=expenses/);
});

test("Finance expense modals share the fixed official company branding", async () => {
  const [html, css] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/css/operator-dashboard.css"),
  ]);
  const expenseDialog = html.match(/<dialog id="businessExpenseDialog"[\s\S]*?<\/dialog>/)?.[0] || "";
  const documentDialog = html.match(/<dialog id="supplierDocumentDialog"[\s\S]*?<\/dialog>/)?.[0] || "";
  const branding = /<div class="finance-modal-brand"><img src="\/assets\/images\/branding\/logo\/lorenzo-web-solution-logo-transparent\.png" alt=""[^>]*><span class="finance-modal-brand__name">Lorenzo <strong>Web Solutions<\/strong><\/span><\/div>/;
  assert.match(expenseDialog, branding);
  assert.match(documentDialog, branding);
  assert.equal((html.match(/class="finance-modal-brand"/g) || []).length, 4);
  assert.doesNotMatch(`${expenseDialog}${documentDialog}`, /<svg|data:image\/svg|lorenzo-web-solution-logo\.svg/i);
  assert.match(css, /\.finance-modal-brand \{ height:82px;[^}]*gap:1rem;/);
  assert.match(css, /\.finance-modal-brand img \{ width:58px; height:58px;[^}]*object-fit:contain;/);
  assert.match(css, /@media \(min-width:901px\) \{[\s\S]*?:is\(\.operator-modal--reading,\.operator-modal--work\) \.finance-modal-brand img \{ width:82px; height:82px; \}/);
  assert.match(css, /@media \(min-width:2000px\) \{[\s\S]*?:is\(\.operator-modal--reading,\.operator-modal--work\) \.finance-modal-brand__name \{ font-size:clamp\(1\.625rem,1\.05vw,2rem\); \}/);
  assert.doesNotMatch(css, /\.operator-modal--work \.finance-modal-brand(?:\s|\{| img|__name)/);
  assert.match(css, /\.operator-modal--reading \.dossier-preview-dialog__header > div:first-child::before,\r?\n\.operator-modal--action-confirm \.confirmation::before \{/);
  assert.match(css, /\.operator-modal--action-confirm \.confirmation::before \{[^}]*background:url\("\/assets\/images\/branding\/logo\/lorenzo-web-solution-logo-transparent\.png"\)[^}]*font-size:clamp\(1\.35rem,1\.35vw,1\.9rem\)/);
  assert.match(css, /@media \(max-width:540px\) \{[^\n]*\.finance-modal-brand \{ height:72px;/);
  assert.match(css, /@media \(max-width:540px\) \{[^\n]*\.finance-modal-brand img \{ width:52px; height:52px;/);
  assert.match(css, /@media \(max-width:540px\) \{[^\n]*\.finance-modal-brand__name \{ font-size:1\.05rem;/);
  assert.match(css, /@media \(max-width:540px\) \{[^\n]*\.operator-modal--reading \.dossier-preview-dialog__header > div:first-child::before,\.operator-modal--action-confirm \.confirmation::before \{ min-height:3\.75rem; padding-left:4\.5rem; background-size:3\.75rem 3\.75rem; font-size:1\.2rem; \}/);
  assert.deepEqual([...expenseDialog.matchAll(/name="([^"]+)"/g)].map((match)=>match[1]), ["supplier_name", "description", "category", "amount", "currency", "expense_date"]);
  assert.deepEqual([...documentDialog.matchAll(/name="([^"]+)"/g)].map((match)=>match[1]), ["file", "document_type", "supplier_name", "document_reference", "document_date", "relation_type"]);
});

test("operator dashboard exposes one CSS-only reduced-motion-safe LWS motion system", async () => {
  const [html, css, script] = await Promise.all([
    read("operator/dashboard/index.html"), read("assets/css/operator-dashboard.css"), read("assets/js/operator-dashboard.js"),
  ]);
  for (const token of ["--motion-duration-fast", "--motion-duration-normal", "--motion-duration-slow", "--motion-ease", "--motion-glow", "--motion-distance"]) assert.match(css, new RegExp(`${token}:`));
  assert.match(css, /@keyframes lws-energy-flow/);
  assert.match(css, /\.finance-modal-header::after[^}]*animation:lws-energy-flow/);
  assert.match(css, /\.finance-section-heading::after[^}]*animation:lws-energy-flow/);
  assert.match(css, /\.business-expense-dialog\[open\][^}]*animation:modal-enter/);
  assert.match(css, /@media \(prefers-reduced-motion:reduce\)/);
  assert.equal((html.match(/data-finance-tab=/g) || []).length, 7);
  assert.match(html, /module=finance&amp;financeTab=inbox/);
  assert.match(html, /module=finance&amp;financeTab=expenses/);
  assert.match(html, /id="businessExpenseDialog"/);
  assert.match(html, /id="supplierDocumentDialog"/);
  assert.match(script, /client\.rpc\("create_business_expense_v1"/);
  assert.match(script, /client\.rpc\("create_supplier_document_v1"/);
  assert.match(script, /client\.rpc\("link_business_expense_document_v1"/);
});

test("business expense entry UI exposes only the approved authority and create flow", async () => {
  const [html, script, css] = await Promise.all([
    read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js"), read("assets/css/operator-dashboard.css"),
  ]);
  const form = html.match(/<dialog id="businessExpenseDialog"[\s\S]*?<\/dialog>/)?.[0] || "";
  assert.match(script, /textContent = "Nieuwe bedrijfskost"/);
  assert.match(form, /name="supplier_name"[^>]*required/);
  assert.match(form, /name="description"[^>]*required/);
  assert.deepEqual([...form.matchAll(/<option value="([a-z]+)">/g)].map((match)=>match[1]), [
    "software", "hosting", "telecom", "accounting", "hardware", "marketing",
    "insurance", "education", "office", "transport", "other",
  ]);
  assert.match(form, /name="amount"[^>]*inputmode="decimal"[^>]*required/);
  assert.match(form, /name="currency"[^>]*value="EUR"[^>]*readonly/);
  assert.match(form, /name="expense_date"[^>]*type="date"[^>]*required/);
  assert.doesNotMatch(form, /record_classification|internal_e2e|paid|payment|vat|btw|bank|outstanding|overdue|due_date|document|upload|file/i);
  assert.match(script, /client\.rpc\("create_business_expense_v1", request\)/);
  assert.doesNotMatch(script, /client\.from\("business_expenses"\)\.insert/);
  assert.match(script, /submit\.disabled = busy/);
  assert.match(script, /form\.reset\(\);\s*dialog\.close\(\);\s*trigger\.focus\(\)/);
  assert.match(script, /reloadPortfolio: \(\)=>loadBusinessExpensePortfolio\("Bedrijfskost opgeslagen\."\)/);
  assert.match(script, /Bedrijfskost kon niet worden opgeslagen\./);
  assert.match(css, /dialog\.operator-modal--reading,dialog\.operator-modal--work,dialog\.operator-modal--compact,dialog\.operator-modal--action-confirm \{[^}]*max-height:calc\(100dvh - 2rem\)/);
  assert.match(css, /@media \(max-width:540px\)[^}]*\{[\s\S]*?\.business-expense-form__fields \{ grid-template-columns:1fr/);
});

test("business expense finance presentation preserves authority, cancellation, currencies, and safe document summaries", () => {
  const portfolio = emptyBusinessExpensePortfolio();
  portfolio.expense_count = 3;
  portfolio.currency_totals.push(
    { currency: "EUR", active_expense_minor: 3000 },
    { currency: "USD", active_expense_minor: 2500 },
  );
  portfolio.expenses.push(
    { id: "f6e00000-0000-4000-8000-000000000001", supplier_name: "Hosting BV", description: "Platform", category: "hosting", amount_minor: 1000, currency: "EUR", expense_date: "2026-08-29", status: "RECORDED", document_count: 3, relation_types: ["INVOICE", "CONTRACT", "OTHER"] },
    { id: "f6e00000-0000-4000-8000-000000000002", supplier_name: "Kantoor BV", description: "Materiaal", category: "office", amount_minor: 2000, currency: "EUR", expense_date: "2026-08-28", status: "RECORDED", document_count: 1, relation_types: ["RECEIPT"] },
    { id: "f6e00000-0000-4000-8000-000000000003", supplier_name: "Tools Inc", description: "Geannuleerd", category: "software", amount_minor: 9000, currency: "USD", expense_date: "2026-08-27", status: "CANCELLED", document_count: 2, relation_types: ["CREDIT_NOTE"] },
  );
  assert.equal(businessExpenseFinancePortfolioPresentation(portfolio), portfolio);
  assert.deepEqual(portfolio.currency_totals.map((total)=>total.active_expense_minor), [3000, 2500]);
  assert.equal(businessExpenseCategoryLabel("accounting"), "Boekhouding");
  assert.equal(businessExpenseRelationLabel("RECEIPT"), "Kassaticket / ontvangstbewijs");
  assert.match(formatFinanceMoney(3000, "EUR"), /30,00/);
  assert.throws(()=>businessExpenseFinancePortfolioPresentation({ ...portfolio, expense_count: 4 }), /INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO/);
  assert.throws(()=>businessExpenseFinancePortfolioPresentation({ ...portfolio, bank_actuals: [] }), /INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO/);
  assert.throws(()=>businessExpenseFinancePortfolioPresentation({ ...portfolio, availability: { ...portfolio.availability, payment_state_available: true } }), /INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO/);
  assert.throws(()=>businessExpenseFinancePortfolioPresentation({ ...portfolio, expenses: [{ ...portfolio.expenses[0], storage_object_path: "private/file.pdf" }], expense_count: 1 }), /INVALID_BUSINESS_EXPENSE_FINANCE_PORTFOLIO/);
});

test("business expense tab uses one RPC, explicit states, unavailable semantics, and no direct authority access", async () => {
  const [html, script, css] = await Promise.all([
    read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js"), read("assets/css/operator-dashboard.css"),
  ]);
  const panel = html.match(/<section class="finance-tab-panel" data-finance-tab-panel="expenses"[\s\S]*?<\/section><\/div><\/section>/)?.[0] || "";
  assert.match(panel, /financeExpenseCount[^>]*>Laden</);
  assert.match(panel, /Bedrijfskosten laden\./);
  assert.match(panel, /Nog geen bedrijfskosten[\s\S]*0 kosten/);
  assert.match(panel, /Betaalstatus[\s\S]*Betaald bedrag[\s\S]*Betaaldatum[\s\S]*Bevestigde kasuitstroom[\s\S]*Openstaand[\s\S]*Achterstallig[\s\S]*Komend[\s\S]*BTW[\s\S]*Aftrekbare BTW[\s\S]*Bankrekening[\s\S]*Terugkerende kosten/);
  assert.match(script, /client\.rpc\("get_business_expense_portfolio_v1"\)/);
  assert.doesNotMatch(script, /client\.from\("(?:business_expenses|supplier_documents|business_expense_documents)"\)/);
  assert.match(script, /Bedrijfskosten konden niet worden geladen\./);
  assert.match(script, /expense\.status === "CANCELLED" \? "Geannuleerd" : "Geregistreerd"/);
  assert.match(script, /currencyTotal\.active_expense_minor/);
  assert.doesNotMatch(script, /amount_minor\s*\*\s*(?:expense\.)?document_count|document_count\s*\*\s*(?:expense\.)?amount_minor/);
  assert.doesNotMatch(panel, /Onbetaald|€0 openstaand|€0 achterstallig|€0 btw|0% btw/i);
  assert.doesNotMatch(panel, /storage|bucket|sha256|signed_url|download/i);
  assert.match(css, /\.finance-expense-metrics/);
  assert.match(css, /@media \(max-width:900px\)[^{]*\{[^}]*\.finance-expense-metrics/);
  assert.match(css, /@media \(max-width:540px\)[^{]*\{[^}]*\.finance-tabs/);
});

const emptyWebsiteFinancePortfolio = () => ({
  scope: "website",
  invoice_projection_available: false,
  outstanding_projection_available: false,
  overdue_projection_available: false,
  upcoming_projection_available: false,
  recurring_amount_projection_available: false,
  bank_actuals_projection_available: false,
  bank_actuals: null,
  currency_totals: [],
  projects: [],
});

test("Website finance projection keeps commitment expected and confirmed received separate", () => {
  const portfolio = emptyWebsiteFinancePortfolio();
  portfolio.currency_totals.push({ currency: "EUR", total_commitment_minor: 350000, total_expected_minor: 350000, total_confirmed_received_minor: 140000 });
  portfolio.projects.push({
    project_id: "f2100000-0000-4000-8000-000000000001",
    application_reference: "LWS-AAN-2099-0101",
    request_kind: "website",
    currency: "EUR",
    accepted_total_minor: 350000,
    expected_minor: 350000,
    confirmed_received_minor: 140000,
    milestones: [{ payment_status: "MATCHED_AWAITING_CONFIRMATION" }],
  });
  assert.equal(websiteFinancePortfolioPresentation(portfolio), portfolio);
  assert.match(formatFinanceMoney(350000, "EUR"), /3[.\s]500,00/);
  assert.equal(financeMilestoneStatus(portfolio.projects[0]), "Afstemming wacht op bevestiging");
  assert.throws(()=>websiteFinancePortfolioPresentation({ ...portfolio, scope: "all" }), /INVALID_WEBSITE_FINANCE_PORTFOLIO/);
  assert.throws(()=>websiteFinancePortfolioPresentation({ ...portfolio, bank_actuals: [] }), /INVALID_WEBSITE_FINANCE_PORTFOLIO/);
  assert.throws(()=>websiteFinancePortfolioPresentation({ ...portfolio, projects: [{ ...portfolio.projects[0], request_kind: "slimme_documentenflow" }] }), /INVALID_WEBSITE_FINANCE_PORTFOLIO/);
});

const emptySdfFinancePortfolio = () => ({
  scope: "sdf",
  project_count: 0,
  invoice_projection_available: true,
  expected_payment_available: false,
  payment_evidence_available: false,
  confirmed_received_available: false,
  outstanding_projection_available: false,
  overdue_projection_available: false,
  upcoming_projection_available: false,
  recurring_amount_projection_available: false,
  currency_totals: [],
  projects: [],
});

test("SDF finance projection accepts only the bounded authority payload", () => {
  const portfolio = emptySdfFinancePortfolio();
  portfolio.project_count = 1;
  portfolio.currency_totals.push({ currency: "EUR", commitment_minor: 1000000, m1_obligation_minor: 400000, issued_invoice_minor: 400000 });
  portfolio.projects.push({
    quote_request_id: "fa200001-0000-4000-8000-000000000001",
    application_reference: "LWS-AAN-2099-7001",
    quotation_id: "fa300000-0000-4000-8000-000000000001",
    sdf_project_id: null,
    sdf_package: "start",
    currency: "EUR",
    commitment_minor: 1000000,
    accepted_at: "2099-01-05T10:00:00+00:00",
    accepted_terms_created_at: "2099-01-05T10:01:00+00:00",
    m1_obligation_minor: 400000,
    m1_obligation_status: "EXPECTED",
    m1_obligation_created_at: "2099-01-05T10:02:00+00:00",
    invoice_candidate_state: "PREPARED",
    invoice_candidate_net_amount_minor: 400000,
    prepared_at: "2099-01-06T10:00:00+00:00",
    invoice_issuance_state: "ISSUED",
    issued_at: "2099-01-07T10:00:00+00:00",
    invoice_number: "LWS-2099-0001",
    issued_net_amount_minor: 400000,
    issued_gross_amount_minor: 400000,
    vat_authority_version: "1.0.0",
  });
  assert.equal(sdfFinancePortfolioPresentation(emptySdfFinancePortfolio()).project_count, 0);
  assert.equal(sdfFinancePortfolioPresentation(portfolio), portfolio);
  assert.throws(()=>sdfFinancePortfolioPresentation({ ...portfolio, scope: "all" }), /INVALID_SDF_FINANCE_PORTFOLIO/);
  assert.throws(()=>sdfFinancePortfolioPresentation({ ...portfolio, project_count: 2 }), /INVALID_SDF_FINANCE_PORTFOLIO/);
  assert.throws(()=>sdfFinancePortfolioPresentation({ ...portfolio, expected_payment_available: true }), /INVALID_SDF_FINANCE_PORTFOLIO/);
  assert.throws(()=>sdfFinancePortfolioPresentation({ ...portfolio, currency_totals: [{ ...portfolio.currency_totals[0], commitment_minor: 1.5 }] }), /INVALID_SDF_FINANCE_PORTFOLIO/);
  assert.throws(()=>sdfFinancePortfolioPresentation({ ...portfolio, projects: [{ ...portfolio.projects[0], email: "hidden@example.test" }] }), /INVALID_SDF_FINANCE_PORTFOLIO/);
});

test("SDF Finance uses only its portfolio RPC and preserves unavailable payment layers", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(script, /client\.rpc\("get_sdf_finance_portfolio_v1"\)/);
  assert.doesNotMatch(script, /client\.from\(|from\(["'](?:sdf_|payment_|recurring_)/);
  assert.match(script, /\["Commerciële waarde", "commitment_minor"\]/);
  assert.match(script, /\["M1-verplichtingen", "m1_obligation_minor"\]/);
  assert.match(script, /\["Uitgereikte facturen", "issued_invoice_minor"\]/);
  assert.doesNotMatch(script, /commitment_minor\s*\+|m1_obligation_minor\s*\+|issued_invoice_minor\s*\+/);
  const sdfPanel = html.split('data-finance-tab-panel="sdf"')[1]?.split('data-finance-tab-panel="workforce"')[0] || "";
  for (const label of ["Verwachte betaling", "Betalingsbewijs", "Bevestigd ontvangen", "Openstaand", "Vervallen", "Upcoming", "Recurring amount"]) {
    assert.match(sdfPanel, new RegExp(`${label}[\\s\\S]*?Niet beschikbaar`, "i"));
  }
  assert.match(sdfPanel, /Nog geen SDF-projecten/);
  assert.match(script, /SDF-financiële gegevens konden niet worden geladen\./);
  assert.doesNotMatch(sdfPanel, /€0(?:,00)?|voorbeeldbedrag|demo-data|omzet|inkomsten|e-mail|telefoon|adres/i);
});

test("Websites uses only the portfolio RPC and exposes safe loading empty and read-error states", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(script, /client\.rpc\("get_website_finance_portfolio_v1"\)/);
  assert.doesNotMatch(script, /client\.from\(|from\(["'](?:quote_requests|commercial_projects|payment_|commercial_obligations)/);
  assert.match(html, /Financiële portfolio laden\./);
  assert.match(html, /Nog geen Website-projecten beschikbaar in de financiële portfolio\./);
  assert.match(script, /De financiële Websiteportfolio kon niet veilig worden geladen\./);
  assert.match(script, /content\.hidden = true/);
  assert.doesNotMatch(html, /€0(?:,00)?/);
});

test("finance labels unavailable metrics and leaves inactive domains data-free", async () => {
  const html = await read("operator/dashboard/index.html");
  const finance = html.split('data-module-panel="finance"')[1]?.split('data-module-panel="workforce"')[0] || "";
  for (const label of ["Factuurprojectie", "Openstaand", "Vervallen", "Upcoming", "Recurring amount", "Bankactuals"]) assert.match(finance, new RegExp(label, "i"));
  assert.match(finance, /Bankrekening<\/dt><dd>Niet gekoppeld/);
  assert.match(finance, /Banksaldo en transacties<\/dt><dd>Niet beschikbaar/);
  for (const tab of ["workforce", "owner"]) {
    const panel = finance.match(new RegExp(`data-finance-tab-panel="${tab}"[\\s\\S]*?<\\/section>`))?.[0] || "";
    assert.match(panel, /nog niet beschikbaar/i);
    assert.doesNotMatch(panel, /€|EUR|[0-9]+[,.][0-9]{2}|payroll|loon|omzet/i);
  }
});

test("finance layout is responsive and reduced-motion safe", async () => {
  const css = await read("assets/css/operator-dashboard.css");
  assert.match(css, /\.module-shell--finance \{[^}]*max-width:none/);
  assert.match(css, /\.finance-tabs \{[^}]*overflow-x:auto/);
  assert.match(css, /\.finance-metrics \{[^}]*grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
  assert.match(css, /@media \(max-width:900px\)[\s\S]{0,220}\.finance-metrics \{[^}]*grid-template-columns:1fr/);
  assert.match(css, /@media \(max-width:540px\)[\s\S]{0,420}\.finance-project-metrics \{[^}]*grid-template-columns:1fr/);
  assert.match(css, /prefers-reduced-motion:reduce[\s\S]*animation:none!important/);
  assert.doesNotMatch(css, /\.finance-[^{]+\{[^}]*animation:[^;}]*infinite/);
});
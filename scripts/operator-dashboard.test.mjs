import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { applicationIdentityPresentation, applicationLocatorFromUrl, applicationReferenceFromUrl, applyDetailVisibility, appendUniqueOperatorItems, appendUniquePersonalQueueItems, assignmentError, assignmentPresentation, buildAssignmentCommand, buildDossierLifecycleCommand, buildIntakeLifecycleCommand, canPromoteApplication, createOperatorListController, createPersonalQueueController, customerCorePresentation, dossierLifecycleAction, dossierLifecycleError, dossierLifecyclePresentation, dossierReferenceFromDetail, effectiveOperatorZone, focusDossierLifecycle, focusIntakeLifecycle, intakeLifecycleError, intakeLifecyclePresentation, nextWorkflowStage, normalizeSupportReference, operatorFacetsRequest, operatorListRequest, operatorListVisibility, operatorStatusPresentation, personalQueueRequest, projectSitePresentation, refreshAfterOperatorMutation, refreshOperatorSelection, resolveDashboardAuthority, sdfM1InvoiceCandidatePresentation, sdfPackageLabel, sdfPricingPresentation, sdfProjectPresentation, sdfQuotationPresentation } from "../assets/js/operator-dashboard.js";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");
const OPERATOR_ASSET_RELEASE = "20260825-personal-queue-ui";

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
  }
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

test("personal queue workspace renders only safe non-clickable dossier information", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  const workspace = html.match(/<section id="personalQueueWorkspace"[\s\S]*?<\/section>\s*<div id="managerWorkspace"/)?.[0] || "";
  const renderer = script.match(/function renderPersonalQueue\(items\) \{[\s\S]*?\n  \}\n\n  const personalQueueController/)?.[0] || "";
  assert.match(workspace, /Mijn dossiers/);
  assert.match(workspace, /id="personalQueueList"/);
  assert.match(workspace, /Er zijn momenteel geen dossiers aan jou toegewezen\./);
  assert.match(workspace, />Vernieuwen</);
  assert.match(workspace, />Meer laden</);
  assert.doesNotMatch(workspace, /klant|organisatie|e-mail|contact|uuid|history/i);
  assert.doesNotMatch(workspace, /href=|Open dossier|get_application_detail/);
  assert.match(script, /reference\.textContent = dossier\.reference/);
  assert.match(script, /badge\(dossier\.status\), badge\(dossier\.zone\)/);
  assert.match(script, /formatDate\(dossier\.assigned_at\)/);
  assert.doesNotMatch(renderer, /get_application_detail|get_operator_application_v1|support_reference/);
});

test("personal queue routing is server-result-driven and fails closed", async () => {
  const script = await read("assets/js/operator-dashboard.js");
  assert.match(script, /loadManagerAuthority: \(\)=>listController\.load\(\)/);
  assert.match(script, /if \(dashboardRoute !== "manager"\) return;\s*personalQueueWorkspace\.hidden = true;\s*managerWorkspace\.hidden = false/);
  assert.match(script, /De dossiers konden niet worden geladen\. Probeer het later opnieuw\./);
  assert.match(script, /callOperator\(client, functionsBaseUrl, input\)/);
  assert.doesNotMatch(script, /\.rpc\(/);
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
  assert.match(script, /personalQueueRefresh\.addEventListener\("click", \(\)=>personalQueueController\.refresh\(\)\)/);
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
  assert.doesNotMatch(script, /client\.rpc\(/);
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

test("dossier lifecycle UI is minimal, non-destructive, and uses the Edge refresh flow", async () => {
  const [html, script] = await Promise.all([read("operator/dashboard/index.html"), read("assets/js/operator-dashboard.js")]);
  assert.match(html, /id="dossierLifecycleDossier"/);
  assert.match(html, /data-dossier-lifecycle-action="archive_dossier"[^>]*hidden>Archiveren</);
  assert.match(html, /data-dossier-lifecycle-action="reactivate_dossier"[^>]*hidden>Terug activeren</);
  assert.match(html, /data-dossier-lifecycle-action="trash_dossier"[^>]*hidden>Naar prullenbak</);
  assert.match(html, /data-dossier-lifecycle-action="restore_dossier"[^>]*hidden>Herstellen uit prullenbak</);
  assert.match(html, /id="dossierLifecycleReason"[^>]*maxlength="500"[^>]*required/);
  assert.doesNotMatch(html, /Permanent verwijderen|Definitief verwijderen|Hard delete|Purge/i);
  assert.match(dossierLifecycleAction("trash_dossier").description, /niet permanent verwijderd/i);
  assert.match(dossierLifecycleAction("trash_dossier").description, /niet hard gedeletet/i);
  assert.match(dossierLifecycleAction("trash_dossier").description, /Herstellen uit prullenbak/i);
  assert.match(script, /import \{ callCommercialOperator \} from "\.\/operator-auth-core\.mjs"/);
  assert.match(script, /callOperator = callCommercialOperator/);
  assert.match(script, /buildDossierLifecycleCommand\(command\.action, command\.detail, dossierLifecycleReason\.value, crypto\.randomUUID\(\)\)/);
  assert.match(script, /command\.selectionRequestId !== detailRequestId \|\| !locatorMatchesApplication\(command\.locator, selectedDetail\)/);
  assert.match(script, /refreshAfterOperatorMutation\([\s\S]{0,300}\(\)=>invoke\(input\)[\s\S]{0,300}\(\)=>detailRequestId/);
  assert.match(script, /if \(outcome\.refresh\) await refreshMutationDetail\(command\.locator, command\.selectionRequestId\)/);
  assert.doesNotMatch(script, /client\.rpc\([^)]*(?:dossier|lifecycle)/i);
  assert.doesNotMatch(script, /service_role|hard_delete|purge_dossier|delete_dossier/i);
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
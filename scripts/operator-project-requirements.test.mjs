import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  buildProjectRequirementAction,
  filterProjectRequirements,
  projectRequirementsRequest,
  projectRequirementsView,
  quoteRequestIdFromRequirementsBoardSlot,
  requirementsBoardSlot,
  validateProjectRequirementsBoard,
} from "../assets/js/operator-project-requirements.mjs";

const quoteRequestId = "a1100000-0000-4000-8000-000000000001";
const projectId = "a1800000-0000-4000-8000-000000000002";
const boardId = "a1800000-0000-4000-8000-000000000003";
const operatorId = "a1800000-0000-4000-8000-000000000004";
const statuses = [
  "PENDING", "ACTIVE", "BLOCKED", "COMPLETED", "COMPLETED", "COMPLETED",
  "COMPLETED", "COMPLETED", "COMPLETED", "COMPLETED", "COMPLETED", "COMPLETED",
];
const titles = [
  "Homepage", "Over ons", "Contactformulier", "Mobiele navigatie",
  "SEO basis", "Cookiebanner", "Google Maps", "Afspraakmodule",
  "Automatische e-mail", "Klantenlogin", "Fotogalerij", "Meertaligheid",
];
const categories = [
  "PAGE", "CONTENT", "FORM", "DESIGN", "SEO", "TECHNICAL",
  "INTEGRATION", "INTEGRATION", "AUTOMATION", "AUTH", "MULTIMEDIA", "CONTENT",
];
const modes = [
  "OPERATOR", "OPERATOR", "OPERATOR", "OPERATOR", "AUTO", "OPERATOR",
  "EXTERNAL", "HYBRID", "AUTO", "HYBRID", "OPERATOR", "OPERATOR",
];

function permittedActions(status, mode, itemNumber) {
  if (itemNumber === 1) return ["start_project_requirement"];
  if (status === "ACTIVE") return ["block_project_requirement", "complete_project_requirement"];
  if (status === "BLOCKED") return ["start_project_requirement"];
  if (status === "COMPLETED" && itemNumber === 12) return ["reopen_project_requirement"];
  return [];
}

function requirement(index, overrides = {}) {
  const itemNumber = index + 1;
  const status = statuses[index];
  const mode = modes[index];
  return {
    requirement_id: `b1800000-0000-4000-8000-${String(itemNumber).padStart(12, "0")}`,
    item_number: itemNumber,
    title: titles[index],
    description: `${titles[index]} uitvoeren volgens de geaccepteerde projectscope.`,
    category: categories[index],
    source: {
      authority_type: itemNumber === 1 ? "ACCEPTED_PROJECT_SCOPE" : "ACCEPTED_LINE_ITEM",
      label: itemNumber === 1 ? "Geaccepteerde projectscope" : "Geaccepteerde offerteregel 1",
    },
    linked_page_or_module: itemNumber <= 4 ? `/${titles[index].toLowerCase().replaceAll(" ", "-")}` : null,
    status,
    completion_mode: mode,
    sort_order: itemNumber,
    required: itemNumber <= 10,
    started_at: status === "ACTIVE" || status === "COMPLETED" ? "2026-09-10T09:00:00Z" : null,
    completed_at: status === "COMPLETED" ? "2026-09-10T10:00:00Z" : null,
    verification_result: mode === "OPERATOR" ? "NOT_APPLICABLE" : status === "COMPLETED" ? "PASS" : "UNKNOWN",
    blocked_reason: status === "BLOCKED" ? "Wacht op goedgekeurde klantinhoud." : null,
    revision: status === "PENDING" ? 1 : 2,
    permitted_actions: permittedActions(status, mode, itemNumber),
    ...overrides,
  };
}

function projection(overrides = {}) {
  const items = Array.from({ length: 12 }, (_, index) => requirement(index));
  return {
    contract_version: 1,
    quote_request_id: quoteRequestId,
    project_id: projectId,
    context: {
      customer: "Atelier Noord",
      dossier_reference: "LWS-AAN-2026-0042",
      project_reference: projectId,
      assigned_operator: { operator_id: operatorId, display_name: "Noor Janssens" },
    },
    board: {
      requirements_board_id: boardId,
      status: "FINALIZED",
      revision: 14,
      finalized_at: "2026-09-10T08:00:00Z",
    },
    items,
    empty_state: null,
    readiness: {
      required_total: 10,
      required_completed: 7,
      required_open: 2,
      required_blocked: 1,
      active_requirement_id: items[1].requirement_id,
      active_item_number: 2,
      ready_for_preview: false,
      readiness: "BLOCKED",
      reason: "REQUIRED_REQUIREMENTS_OPEN",
    },
    actions: { can_create_board: false, can_create_item: false, can_finalize: false },
    ...overrides,
  };
}

function validated(value = projection()) {
  return validateProjectRequirementsBoard(value, { quoteRequestId, projectId });
}

const registrySource = readFileSync(
  new URL("../assets/js/operator-module-registry.mjs", import.meta.url),
  "utf8",
);
const requirementsChildSource = readFileSync(
  new URL("../assets/js/operator-project-requirements-child.mjs", import.meta.url),
  "utf8",
);
const projectChildSource = readFileSync(
  new URL("../assets/js/operator-project-workspace-child.mjs", import.meta.url),
  "utf8",
);
const websiteChildSource = readFileSync(
  new URL("../assets/js/operator-website-execution-child.mjs", import.meta.url),
  "utf8",
);
const dashboardCss = readFileSync(
  new URL("../assets/css/operator-dashboard.css", import.meta.url),
  "utf8",
);

test("requirements module is registered as a managed dossiers child", async () => {
  assert.match(registrySource, /startsWith\("req-"\)[\s\S]*operator-project-requirements-child\.mjs/);
  const child = await import("../assets/js/operator-project-requirements-child.mjs");
  assert.equal(typeof child.initializeOperatorProjectRequirements, "function");
});

test("requirements child binds server detail to the exact slot quote and project", async () => {
  const { requirementsChildContext, requirementsChildDetailRequest } =
    await import("../assets/js/operator-project-requirements-child.mjs");
  assert.deepEqual(requirementsChildDetailRequest(requirementsBoardSlot(quoteRequestId)), {
    action: "get_application_detail",
    quote_request_id: quoteRequestId,
  });
  assert.deepEqual(requirementsChildContext({
    quote_request_id: quoteRequestId,
    request_kind: "website",
    application_reference: "LWS-AAN-2026-0042",
    project: { project_id: projectId },
  }, quoteRequestId, { customer: { company: "Atelier Noord" } }), {
    quoteRequestId,
    projectId,
    dossierReference: "LWS-AAN-2026-0042",
    customerName: "Atelier Noord",
  });
  assert.throws(() => requirementsChildDetailRequest("req-wrong"), /INVALID_REQUIREMENTS_BOARD_SLOT/);
  assert.throws(() => requirementsChildContext({
    quote_request_id: quoteRequestId,
    request_kind: "website",
    application_reference: "LWS-AAN-2026-0042",
    project: { project_id: crypto.randomUUID() },
  }, quoteRequestId, null, projectId), /PROJECT_REQUIREMENTS_BINDING_MISMATCH/);
});

test("requirements child reuses Task 7, invalidation and bounded sibling opening only", () => {
  const childSource = readFileSync(
    new URL("../assets/js/operator-project-requirements-child.mjs", import.meta.url),
    "utf8",
  );
  assert.match(childSource, /operator-project-requirements\.mjs/);
  assert.match(childSource, /createOperatorDossierAuthority/);
  assert.match(childSource, /createOperatorAutoRefresh/);
  assert.match(childSource, /options\.requestOpen\?\.\("dossiers",\s*websiteExecutionSlot/);
  assert.match(childSource, /runProjectRequirementMutation\(\{/);
  assert.match(childSource, /options\.onInvalidate\?\.\(moduleKey\)/);
  assert.doesNotMatch(childSource, /window\.open|location\.reload/);
  assert.doesNotMatch(childSource, /identity\?\.role|completion_mode\s*===/);
});

test("successful requirement mutation refreshes authority then invalidates every sibling", async () => {
  const { runProjectRequirementMutation } =
    await import("../assets/js/operator-project-requirements-child.mjs");
  const calls = [];
  assert.equal(await runProjectRequirementMutation({
    request: { action: "start_project_requirement" },
    gateway: async () => { calls.push("server"); return { status: "ACTIVE" }; },
    refresh: async () => { calls.push("refresh"); return true; },
    invalidate: (moduleKey) => calls.push(`invalidate:${moduleKey}`),
  }), true);
  assert.deepEqual(calls, ["server", "refresh", "invalidate:dossiers"]);
});

test("failed requirement mutation publishes no invalidation or fake progress", async () => {
  const { runProjectRequirementMutation } =
    await import("../assets/js/operator-project-requirements-child.mjs");
  const calls = [];
  await assert.rejects(() => runProjectRequirementMutation({
    request: { action: "complete_project_requirement" },
    gateway: async () => { calls.push("server"); throw new Error("SERVER_REJECTED"); },
    refresh: async () => { calls.push("refresh"); },
    invalidate: () => calls.push("invalidate"),
  }), /SERVER_REJECTED/);
  assert.deepEqual(calls, ["server"]);
});

test("requirement mutation finishing after logout cannot refresh or invalidate", async () => {
  const { runProjectRequirementMutation } =
    await import("../assets/js/operator-project-requirements-child.mjs");
  const calls = [];
  let active = true;
  assert.equal(await runProjectRequirementMutation({
    request: { action: "block_project_requirement" },
    gateway: async () => { calls.push("server"); active = false; },
    refresh: async () => { calls.push("refresh"); },
    invalidate: () => calls.push("invalidate"),
    isActive: () => active,
  }), false);
  assert.deepEqual(calls, ["server"]);
});

test("Requirements invalidation is exact-quote scoped and shared by all three children", async () => {
  const { requirementsInvalidationMatches } =
    await import("../assets/js/operator-project-requirements-child.mjs");
  assert.equal(requirementsInvalidationMatches(`req-${quoteRequestId}`, quoteRequestId), true);
  assert.equal(requirementsInvalidationMatches(`req-${crypto.randomUUID()}`, quoteRequestId), false);
  assert.equal(requirementsInvalidationMatches("main", quoteRequestId), true);
  for (const source of [requirementsChildSource, websiteChildSource, projectChildSource]) {
    assert.match(source, /invalidationSlotKey/);
    assert.match(source, /requirementsInvalidationMatches\(invalidationSlotKey/);
    assert.match(source, /createOperatorAutoRefresh/);
    assert.match(source, /if \((?:background && )?current/);
    assert.doesNotMatch(source, /location\.reload|record_preview_ready/);
  }
  const windowGuard = readFileSync(
    new URL("../assets/js/operator-window-guard.mjs", import.meta.url),
    "utf8",
  );
  assert.match(windowGuard, /refresh\(\{ background: true, invalidationSlotKey \}\)/);
});

test("Task 11 synchronization has one coherent source hard-refresh cache chain", () => {
  const token = "20260912-dossier-continuity-project-r1";
  const paths = [
    "../operator/dashboard/index.html",
    "../assets/js/operator-dashboard-guard.mjs",
    "../assets/js/operator-workspace-master.mjs",
    "../operator/window/index.html",
    "../assets/js/operator-window-guard.mjs",
    "../assets/js/operator-project-requirements-child.mjs",
    "../assets/js/operator-project-workspace-child.mjs",
    "../assets/js/operator-website-execution-child.mjs",
  ];
  for (const path of paths) {
    assert.match(readFileSync(new URL(path, import.meta.url), "utf8"), new RegExp(token));
  }
  assert.match(registrySource, new RegExp(token));
});

test("requirements slot roundtrips exactly one quote request", () => {
  assert.equal(requirementsBoardSlot(quoteRequestId.toUpperCase()), `req-${quoteRequestId}`);
  assert.equal(quoteRequestIdFromRequirementsBoardSlot(`req-${quoteRequestId}`), quoteRequestId);
  assert.equal(quoteRequestIdFromRequirementsBoardSlot("main"), null);
  assert.throws(() => requirementsBoardSlot("bad"), /INVALID_REQUIREMENTS_BOARD_SLOT/);
});

test("requirements request binds the exact quote and Website project", () => {
  assert.deepEqual(projectRequirementsRequest({ quoteRequestId, projectId }), {
    action: "get_project_requirements_board",
    quote_request_id: quoteRequestId,
    project_id: projectId,
  });
  assert.throws(() => projectRequirementsRequest({ quoteRequestId, projectId: "bad" }), /INVALID_PROJECT_REQUIREMENTS_CONTEXT/);
});

test("valid exact server DTO is accepted and deeply frozen", () => {
  const value = validated();
  assert.equal(value.items.length, 12);
  assert.equal(Object.isFrozen(value), true);
  assert.equal(Object.isFrozen(value.items), true);
  assert.equal(Object.isFrozen(value.items[0]), true);
  assert.equal(Object.isFrozen(value.items[0].source), true);
  assert.equal(Object.isFrozen(value.items[0].permitted_actions), true);
});

test("malformed or surplus DTO data is rejected", () => {
  assert.throws(() => validated({ ...projection(), leak: "secret" }), /INVALID_PROJECT_REQUIREMENTS_RESPONSE/);
  const malformed = projection();
  malformed.items[0] = { ...malformed.items[0], description: "" };
  assert.throws(() => validated(malformed), /INVALID_PROJECT_REQUIREMENTS_RESPONSE/);
});

test("wrong project and quote request fail closed", () => {
  assert.throws(() => validated({ ...projection(), project_id: crypto.randomUUID() }), /PROJECT_REQUIREMENTS_BINDING_MISMATCH/);
  assert.throws(() => validated({ ...projection(), quote_request_id: crypto.randomUUID() }), /PROJECT_REQUIREMENTS_BINDING_MISMATCH/);
});

test("inconsistent required progress counts are rejected", () => {
  const value = projection();
  value.readiness = { ...value.readiness, required_completed: 6 };
  assert.throws(() => validated(value), /INVALID_PROJECT_REQUIREMENTS_PROGRESS/);
});

test("server order and sequential item numbers are preserved", () => {
  assert.deepEqual(validated().items.map(({ item_number }) => item_number), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  const value = projection();
  [value.items[0], value.items[1]] = [value.items[1], value.items[0]];
  assert.throws(() => validated(value), /INVALID_PROJECT_REQUIREMENTS_ORDER/);
});

test("all four presentation filters are deterministic", () => {
  const items = validated().items;
  assert.equal(filterProjectRequirements(items, "ALL").length, 12);
  assert.deepEqual(filterProjectRequirements(items, "ACTIVE").map((item) => item.item_number), [2]);
  assert.deepEqual(filterProjectRequirements(items, "OPEN").map((item) => item.item_number), [1, 2, 3]);
  assert.deepEqual(filterProjectRequirements(items, "COMPLETED").map((item) => item.item_number), [4, 5, 6, 7, 8, 9, 10, 11, 12]);
  assert.throws(() => filterProjectRequirements(items, "UNKNOWN"), /INVALID_PROJECT_REQUIREMENTS_FILTER/);
});

test("view exposes header, context, progress and text-safe card data", () => {
  const view = projectRequirementsView(validated());
  assert.equal(view.heading, "PROJECTVEREISTEN");
  assert.equal(view.progress.value, "07 / 10");
  assert.equal(view.progress.label, "VEREISTEN AFGEROND");
  assert.deepEqual(view.context, {
    customer: "Atelier Noord",
    dossier: "LWS-AAN-2026-0042",
    project: projectId,
    operator: "Noor Janssens",
  });
  assert.deepEqual(view.cards.map((card) => card.statusClass), [
    "pending", "active", "blocked", "completed", "completed", "completed",
    "completed", "completed", "completed", "completed", "completed", "completed",
  ]);
  assert.equal(view.cards[0].number, "01");
  assert.equal(view.cards[2].blockedReason, "Wacht op goedgekeurde klantinhoud.");
  assert.equal(view.cards[4].verificationLabel, "Geverifieerd");
  assert.equal("html" in view.cards[0], false);
});

test("actions are copied only from server permitted_actions", () => {
  const cards = projectRequirementsView(validated()).cards;
  assert.deepEqual(cards[0].actions.map(({ action }) => action), ["start_project_requirement"]);
  assert.deepEqual(cards[1].actions.map(({ action }) => action), ["block_project_requirement", "complete_project_requirement"]);
  assert.deepEqual(cards[3].actions, []);
  assert.deepEqual(cards[11].actions.map(({ action }) => action), ["reopen_project_requirement"]);
});

test("unknown or duplicate permitted actions reject the whole DTO", () => {
  for (const permitted_actions of [["approve_requirement"], ["start_project_requirement", "start_project_requirement"]]) {
    const value = projection();
    value.items[0] = { ...value.items[0], permitted_actions };
    assert.throws(() => validated(value), /INVALID_PROJECT_REQUIREMENTS_ACTIONS/);
  }
});

test("AUTO and EXTERNAL cannot gain client completion authority", () => {
  const cards = projectRequirementsView(validated()).cards;
  for (const itemNumber of [5, 7, 9]) {
    assert.equal(cards[itemNumber - 1].completionMode === "AUTO" || cards[itemNumber - 1].completionMode === "EXTERNAL", true);
    assert.equal(cards[itemNumber - 1].actions.some(({ action }) => action === "complete_project_requirement"), false);
  }
});

test("management reopen appears only when projected by the server", () => {
  const cards = projectRequirementsView(validated()).cards;
  assert.equal(cards[10].actions.some(({ action }) => action === "reopen_project_requirement"), false);
  assert.equal(cards[11].actions.some(({ action }) => action === "reopen_project_requirement"), true);
});

test("all lifecycle action builders are revision-bound and exact", () => {
  const context = { quoteRequestId, projectId };
  const item = validated().items[0];
  const idempotencyKey = crypto.randomUUID();
  assert.deepEqual(buildProjectRequirementAction(context, item, "start_project_requirement", idempotencyKey), {
    action: "start_project_requirement",
    quote_request_id: quoteRequestId,
    project_id: projectId,
    requirement_id: item.requirement_id,
    expected_revision: item.revision,
    idempotency_key: idempotencyKey,
  });
});

test("action builder cannot invoke an action absent from server authority", () => {
  const item = validated().items[0];
  assert.throws(() => buildProjectRequirementAction(
    { quoteRequestId, projectId }, item, "complete_project_requirement", crypto.randomUUID(),
    { attestation: "Niet toegestaan." },
  ), /PROJECT_REQUIREMENT_ACTION_NOT_PERMITTED/);
});

test("block, complete and reopen builders use exact bounded payloads", () => {
  const context = { quoteRequestId, projectId };
  const items = validated().items;
  const blockKey = crypto.randomUUID();
  assert.deepEqual(buildProjectRequirementAction(context, items[1], "block_project_requirement", blockKey, { reason: "Wacht op input." }), {
    action: "block_project_requirement", quote_request_id: quoteRequestId, project_id: projectId,
    requirement_id: items[1].requirement_id, expected_revision: 2, reason: "Wacht op input.", idempotency_key: blockKey,
  });
  const completeKey = crypto.randomUUID();
  assert.deepEqual(buildProjectRequirementAction(context, items[1], "complete_project_requirement", completeKey, { attestation: "Gecontroleerd." }), {
    action: "complete_project_requirement", quote_request_id: quoteRequestId, project_id: projectId,
    requirement_id: items[1].requirement_id, expected_revision: 2,
    evidence_reference: { attestation: "Gecontroleerd." }, idempotency_key: completeKey,
  });
  const reopenKey = crypto.randomUUID();
  assert.deepEqual(buildProjectRequirementAction(context, items[11], "reopen_project_requirement", reopenKey, { reason: "Hercontrole nodig." }), {
    action: "reopen_project_requirement", quote_request_id: quoteRequestId, project_id: projectId,
    requirement_id: items[11].requirement_id, expected_revision: 2, reason: "Hercontrole nodig.", idempotency_key: reopenKey,
  });
});

test("no-board projection renders a real empty state without fake 0/0 readiness", () => {
  const empty = projection({
    board: null,
    items: [],
    empty_state: "NO_BOARD",
    readiness: {
      required_total: 0, required_completed: 0, required_open: 0, required_blocked: 0,
      active_requirement_id: null, active_item_number: null, ready_for_preview: false,
      readiness: "UNKNOWN", reason: "REQUIREMENTS_BOARD_MISSING",
    },
    actions: { can_create_board: true, can_create_item: false, can_finalize: false },
  });
  const view = projectRequirementsView(validated(empty));
  assert.equal(view.state, "empty");
  assert.equal(view.message, "Nog geen projectvereisten beschikbaar.");
  assert.equal(view.progress, null);
  assert.deepEqual(view.cards, []);
});

test("R2 fixture contains 12 realistic mixed-state customer requirements", () => {
  const view = projectRequirementsView(validated());
  assert.equal(view.cards.length, 12);
  assert.deepEqual(view.cards.map(({ title }) => title), titles);
  assert.deepEqual(new Set(view.cards.map(({ status }) => status)), new Set(["PENDING", "ACTIVE", "BLOCKED", "COMPLETED"]));
});

test("completed requirement cards are static green without a light sweep", () => {
  assert.match(dashboardCss, /\.project-requirements__card--completed\s*\{[^}]*background:[^;}]*(?:#|green|var\(--green)/i);
  assert.match(dashboardCss, /\.project-requirements__card--completed\s*\{[^}]*animation:none/);
  assert.match(dashboardCss, /\.project-requirements__card--completed::before\s*\{[^}]*display:none/);
  assert.doesNotMatch(dashboardCss, /\.project-requirements__card--completed[^,{]*\{[^}]*(?:pulse|light-sweep)/);
});

test("only ACTIVE requirement cards receive pulse and bounded light sweep", () => {
  assert.match(dashboardCss, /\.project-requirements__card--active\s*\{[^}]*animation:project-requirement-active-pulse/);
  assert.match(dashboardCss, /\.project-requirements__card--active::before\s*\{[^}]*animation:dossier-card-light-sweep/);
  assert.match(dashboardCss, /\.project-requirements__card\s*\{[^}]*overflow:hidden/);
  assert.match(dashboardCss, /@keyframes project-requirement-active-pulse\s*\{/);
  for (const state of ["completed", "pending", "blocked"]) {
    assert.doesNotMatch(dashboardCss, new RegExp(`\\.project-requirements__card--${state}[^,{]*\\{[^}]*(?:project-requirement-active-pulse|dossier-card-light-sweep)`));
  }
});

test("pending stays neutral and blocked stays non-green with readable reason", () => {
  assert.match(dashboardCss, /\.project-requirements__card--pending\s*\{[^}]*background:var\(--white\)[^}]*animation:none/);
  assert.match(dashboardCss, /\.project-requirements__card--blocked\s*\{[^}]*border-color:var\(--(?:amber|red)\)/);
  assert.match(dashboardCss, /\.project-requirements__card--blocked\s*\{[^}]*animation:none/);
  assert.doesNotMatch(dashboardCss, /\.project-requirements__card--blocked\s*\{[^}]*(?:var\(--green\)|#f3faf6|#e1f3e8)/);
  assert.match(requirementsChildSource, /if \(card\.blockedReason\)[\s\S]*reason\.textContent = card\.blockedReason/);
});

test("animation ownership transfers with the server-projected ACTIVE state", () => {
  const before = projectRequirementsView(validated());
  assert.deepEqual(before.cards.filter(({ status }) => status === "ACTIVE").map(({ itemNumber }) => itemNumber), [2]);

  const value = projection();
  value.items[0] = {
    ...value.items[0],
    status: "ACTIVE",
    started_at: "2026-09-10T11:00:00Z",
    permitted_actions: ["block_project_requirement", "complete_project_requirement"],
  };
  value.items[1] = {
    ...value.items[1],
    status: "COMPLETED",
    completed_at: "2026-09-10T11:00:00Z",
    permitted_actions: [],
  };
  value.readiness = {
    ...value.readiness,
    required_completed: 8,
    required_open: 1,
    active_requirement_id: value.items[0].requirement_id,
    active_item_number: 1,
  };
  const after = projectRequirementsView(validated(value));
  assert.equal(after.cards[1].statusClass, "completed");
  assert.deepEqual(after.cards.filter(({ status }) => status === "ACTIVE").map(({ itemNumber }) => itemNumber), [1]);
});

test("all-completed projection has zero animated card candidates", () => {
  const value = projection();
  value.items = value.items.map((item) => ({
    ...item,
    status: "COMPLETED",
    blocked_reason: null,
    completed_at: item.completed_at || "2026-09-10T12:00:00Z",
    permitted_actions: [],
  }));
  value.readiness = {
    required_total: 10,
    required_completed: 10,
    required_open: 0,
    required_blocked: 0,
    active_requirement_id: null,
    active_item_number: null,
    ready_for_preview: true,
    readiness: "READY",
    reason: "REQUIREMENTS_READY",
  };
  const cards = projectRequirementsView(validated(value)).cards;
  assert.equal(cards.filter(({ status }) => status === "ACTIVE").length, 0);
  assert.equal(cards.every(({ statusClass }) => statusClass === "completed"), true);
});

test("reduced motion removes Requirements pulse and sweep but keeps ACTIVE green", () => {
  assert.match(dashboardCss, /@media \(prefers-reduced-motion:reduce\)[^{]*\{[\s\S]*?\.project-requirements__card--active\s*\{[^}]*animation:none!important/);
  assert.match(dashboardCss, /@media \(prefers-reduced-motion:reduce\)[^{]*\{[\s\S]*?\.project-requirements__card--active::before\s*\{[^}]*display:none[^}]*animation:none!important/);
  assert.match(dashboardCss, /\.project-requirements__card--active\s*\{[^}]*(?:border-color:var\(--green\)|background:#f3faf6)/);
});

test("Requirements cards have stable readable no-shift layout contracts", () => {
  assert.match(dashboardCss, /\.project-requirements__card\s*\{[^}]*min-height:[^;}]+[^}]*isolation:isolate/);
  assert.match(dashboardCss, /\.project-requirements__card\s*>\s*\*\s*\{[^}]*position:relative[^}]*z-index:1/);
  assert.match(dashboardCss, /\.project-requirements__card\s+(?:h2|p)[^{]*\{[^}]*overflow-wrap:anywhere/);
  assert.match(dashboardCss, /\.project-requirements__cards\s*\{[^}]*grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
});

test("Requirements layout declares 1440, 900 and 390-safe overflow behavior", () => {
  assert.match(dashboardCss, /\.project-requirements-workspace,\.project-requirements\s*\{[^}]*width:100%[^}]*min-width:0/);
  assert.match(dashboardCss, /@media \(max-width:900px\)[^{]*\{[^}]*\.project-requirements__cards\s*\{[^}]*grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/);
  assert.match(dashboardCss, /@media \(max-width:540px\)[^{]*\{[^}]*\.project-requirements__cards\s*\{[^}]*grid-template-columns:1fr/);
  assert.match(dashboardCss, /\.project-requirements__card\s*\{[^}]*min-width:0[^}]*overflow:hidden/);
  assert.doesNotMatch(requirementsChildSource, /window\.open|location\.reload|identity\?\.role|completion_mode\s*===/);
});

test("Requirements visual CSS has a coherent managed-window cache key", () => {
  const token = "operator-dashboard.css?v=20260912-dossier-continuity-project-r1";
  for (const path of ["../operator/dashboard/index.html", "../operator/window/index.html"]) {
    assert.equal(readFileSync(new URL(path, import.meta.url), "utf8").includes(token), true);
  }
});

test("Task 12 owner fixture exposes the complete Operator requirements flow", () => {
  const fixture = readFileSync(
    new URL("../operator/test/project-requirements.html", import.meta.url),
    "utf8",
  );
  assert.match(fixture, /Content-Security-Policy/);
  assert.match(fixture, /operator-dashboard\.css\?v=20260910-requirements-summary-v1/);
  assert.match(fixture, /operator-project-requirements-test\.css\?v=20260910-task12-v1/);
  assert.match(fixture, /Q12\.1[\s\S]*Actieve dossiers/);
  assert.match(fixture, /href="#project-workspace"[^>]*>Project openen/);
  assert.match(fixture, /href="#website-workspace"[^>]*>Website openen/);
  assert.match(fixture, /href="#requirements-board"[^>]*>Takenbord openen/);
  assert.match(fixture, /id="project-workspace"[\s\S]*01 Intake afgerond[\s\S]*05 Oplevering/);
  assert.match(fixture, /id="website-workspace"[\s\S]*Repository[\s\S]*Actieve branch[\s\S]*Preview[\s\S]*Productie URL/);
  assert.match(fixture, /id="requirements-board"/);
  assert.equal((fixture.match(/data-requirement-card/g) || []).length, 12);
  for (const status of ["PENDING", "ACTIVE", "BLOCKED", "COMPLETED"]) {
    assert.match(fixture, new RegExp(`data-status="${status}"`));
  }
  assert.match(fixture, /Wacht op goedgekeurde klantinhoud/);
  assert.match(fixture, /ready_for_preview: false[\s\S]*ready_for_preview: true/);
  assert.match(fixture, /Q12\.12/);
  assert.doesNotMatch(fixture, /<script|https?:\/\/(?!www\.example\.test|preview\.example\.test)|window\.open|location\.reload/);
});

test("Task 12 fixture shell is stable across the complete responsive matrix", () => {
  const css = readFileSync(
    new URL("../assets/css/operator-project-requirements-test.css", import.meta.url),
    "utf8",
  );
  assert.match(css, /\.requirements-checkpoint\s*\{[^}]*min-width:0[^}]*overflow-x:clip/);
  assert.match(css, /\.requirements-checkpoint__siblings\s*\{[^}]*grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
  assert.match(css, /@media \(max-width:1100px\)[^{]*\{[^}]*\.requirements-checkpoint__siblings\s*\{[^}]*grid-template-columns:1fr/);
  assert.match(css, /@media \(max-width:760px\)[^{]*\{[^}]*\.requirements-checkpoint__dossier-actions/);
  assert.match(css, /@media \(max-width:430px\)[^{]*\{[^}]*\.requirements-checkpoint__facts\s*\{[^}]*grid-template-columns:1fr/);
  assert.match(css, /overflow-wrap:anywhere/);
  assert.doesNotMatch(css, /project-requirement-active-pulse|dossier-card-light-sweep|\.project-requirements__card--(?:active|completed|pending|blocked)/);
});

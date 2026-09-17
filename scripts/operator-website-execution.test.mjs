import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import test from "node:test";
import { chromium } from "@playwright/test";
import {
  websiteExecutionProvisionRequest,
  quoteRequestIdFromWebsiteExecutionSlot,
  safeWebsiteExecutionLinks,
  websiteRequirementsSummary,
  validateWebsiteExecutionWorkspace,
  websiteExecutionRequest,
  websiteExecutionSlot,
  websiteExecutionView,
} from "../assets/js/operator-website-execution.mjs";
import { createOperatorDossierAuthority } from "../assets/js/operator-dossiers.mjs";
import {
  requirementsChildContext,
} from "../assets/js/operator-project-requirements-child.mjs";
import { requirementsBoardSlot } from "../assets/js/operator-project-requirements.mjs";

const quoteRequestId = "a1800000-0000-4000-8000-000000000001";
const projectId = "a1800000-0000-4000-8000-000000000002";
const conceptId = "a1800000-0000-4000-8000-000000000004";
const websiteWorkContextId = "a1800000-0000-4000-8000-000000000005";
const expected = {
  quoteRequestId,
  projectId,
  conceptId: null,
  websiteWorkContextId,
  mode: "OFFICIAL_PROJECT",
};
const root = new URL("../", import.meta.url);
const rootPath = decodeURIComponent(root.pathname).replace(/^\/(?:([A-Za-z]:))/, "$1");
const read = (path) => readFile(new URL(path, root), "utf8");
const base = {
  contract_version: 2,
  mode: "OFFICIAL_PROJECT",
  quote_request_id: quoteRequestId,
  concept_id: null,
  project_id: projectId,
  website_work_context_id: websiteWorkContextId,
  context_revision: 1,
  briefing_status: "COMPLETE",
  commercially_released: false,
  project: { project_id: projectId, site: null },
  start_gate: { project_id: projectId, quote_request_id: quoteRequestId },
  workspace: null,
  requirements: { state: "PROJECT_BOUND", message: null },
};

const officialWork = {
  state: "OFFICIAL_PROJECT",
  quote_request_id: quoteRequestId,
  concept_id: null,
  project_id: projectId,
  website_work_context_id: websiteWorkContextId,
  mode: "OFFICIAL_PROJECT",
  briefing_status: "COMPLETE",
  commercially_released: false,
  revision: 1,
  permitted_actions: ["OPEN_WEBSITE"],
};

function workspaceFixture(overrides = {}) {
  return {
    website_workspace_id: "a1800000-0000-4000-8000-000000000006",
    website_work_context_id: websiteWorkContextId,
    project_id: projectId,
    quote_request_id: quoteRequestId,
    repository_provider: "GITHUB",
    repository_owner: "lws-studio",
    repository_name: "lws-web-2026-0042",
    default_branch: "main",
    preview_branch: "develop",
    preview_url: "https://preview.example.com/build/42#private",
    last_commit_sha: "a".repeat(40),
    last_commit_at: "2026-09-12T12:00:00Z",
    last_build_result: "PASS",
    last_build_at: "2026-09-12T12:01:00Z",
    binding_revision: 1,
    created_at: "2026-09-12T10:00:00Z",
    updated_at: "2026-09-12T12:01:00Z",
    ...overrides,
  };
}

function currentWorkspaceFixture(workspaceState, overrides = {}) {
  return workspaceFixture({
    workspace_state: workspaceState,
    provisioned_by: "a1800000-0000-4000-8000-000000000010",
    provisioned_at: "2026-09-12T10:00:00Z",
    ...overrides,
  });
}

const preProjectWork = {
  state: "PRE_PROJECT",
  quote_request_id: quoteRequestId,
  concept_id: conceptId,
  project_id: null,
  website_work_context_id: websiteWorkContextId,
  mode: "PRE_PROJECT",
  briefing_status: "COMPLETE",
  commercially_released: false,
  revision: 1,
  permitted_actions: ["OPEN_WEBSITE"],
};

const preProjectV2 = {
  contract_version: 2,
  mode: "PRE_PROJECT",
  quote_request_id: quoteRequestId,
  concept_id: conceptId,
  project_id: null,
  website_work_context_id: websiteWorkContextId,
  context_revision: 1,
  briefing_status: "COMPLETE",
  commercially_released: false,
  project: null,
  start_gate: null,
  workspace: null,
  requirements: {
    state: "NOT_AVAILABLE",
    message: "Requirements volgen na intake-sync.",
  },
};

test("PRE_PROJECT provisioning request accepts only the stable dossier locator", () => {
  assert.deepEqual(websiteExecutionProvisionRequest({
    quoteRequestId,
    idempotencyKey: "a1800000-0000-4000-8000-000000000009",
  }), {
    action: "provision_website_execution_workspace",
    quote_request_id: quoteRequestId,
    idempotency_key: "a1800000-0000-4000-8000-000000000009",
  });
  assert.throws(() => websiteExecutionProvisionRequest({
    quoteRequestId,
    idempotencyKey: "invalid",
    projectId,
  }), /INVALID_WEBSITE_WORKSPACE_PROVISION_REQUEST/);
});

test("PRE_PROJECT provisioning passes through the shared caller-JWT gateway", async () => {
  const requests = [];
  const authority = createOperatorDossierAuthority({
    functions: {
      invoke: async (name, options) => {
        requests.push({ name, body: options.body });
        return { data: { ok: true, result: { created: true } }, error: null };
      },
    },
  });
  const request = websiteExecutionProvisionRequest({
    quoteRequestId,
    idempotencyKey: "a1800000-0000-4000-8000-000000000009",
  });
  assert.deepEqual(await authority.gateway(request), { created: true });
  assert.deepEqual(requests, [{
    name: "commercial-operator-command",
    body: request,
  }]);
});

test("PRE_PROJECT provision action remains coherent with the deployable command", async () => {
  const [dossiers, handler, index] = await Promise.all([
    read("assets/js/operator-dossiers.mjs"),
    read("supabase/functions/commercial-operator-command/handler.ts"),
    read("supabase/functions/commercial-operator-command/index.ts"),
  ]);
  const action = "provision_website_execution_workspace";
  assert.match(dossiers, new RegExp(`"${action}"`));
  assert.match(handler, new RegExp(`"${action}"`));
  assert.match(index, new RegExp(`input\\.action === "${action}"`));
  assert.match(index, /"provision_website_execution_workspace_v1"/);
});

test("PRE_PROJECT pending workspace is context-bound without fake repository data", () => {
  const context = {
    quoteRequestId,
    projectId: null,
    conceptId,
    websiteWorkContextId,
    websiteWorkRevision: 1,
    mode: "PRE_PROJECT",
  };
  const projection = validateWebsiteExecutionWorkspace({
    ...preProjectV2,
    workspace: currentWorkspaceFixture("PENDING_REPOSITORY", {
      project_id: null,
      repository_owner: null,
      repository_name: null,
      preview_branch: null,
      preview_url: null,
      last_commit_sha: null,
      last_commit_at: null,
      last_build_result: null,
      last_build_at: null,
    }),
  }, context);
  const view = websiteExecutionView(projection);
  assert.equal(view.state, "pending_repository");
  assert.equal(view.repository, "Repository provisioning nog niet uitgevoerd");
  assert.equal(view.branch, "main");
  assert.equal(view.production, "Production URL nog niet beschikbaar");
  assert.equal(view.links.github, null);
});

function requirementsProjection(overrides = {}) {
  return {
    contract_version: 1,
    quote_request_id: quoteRequestId,
    project_id: projectId,
    context: {
      customer: "Acme",
      dossier_reference: "LWS-AAN-2026-0042",
      project_reference: projectId,
      assigned_operator: null,
    },
    board: {
      requirements_board_id: "a1800000-0000-4000-8000-000000000003",
      status: "FINALIZED",
      revision: 1,
      finalized_at: "2026-09-10T10:00:00Z",
    },
    items: [
      ...Array.from({ length: 8 }, (_, index) => requirement(index + 1, "COMPLETED")),
      ...Array.from({ length: 3 }, (_, index) => requirement(index + 9, "PENDING")),
      requirement(12, "BLOCKED"),
    ],
    empty_state: null,
    readiness: {
      required_total: 12,
      required_completed: 8,
      required_open: 3,
      required_blocked: 1,
      active_requirement_id: null,
      active_item_number: null,
      ready_for_preview: false,
      readiness: "BLOCKED",
      reason: "REQUIREMENTS_OPEN",
    },
    actions: { can_create_board: false, can_create_item: false, can_finalize: false },
    ...overrides,
  };
}

function requirement(itemNumber, status) {
  return {
    requirement_id: `b1800000-0000-4000-8000-${String(itemNumber).padStart(12, "0")}`,
    item_number: itemNumber,
    title: `Requirement ${itemNumber}`,
    description: "Server-authoritative requirement.",
    category: "TECHNICAL",
    source: { authority_type: "ACCEPTED_PROJECT_SCOPE", label: "Scope" },
    linked_page_or_module: null,
    status,
    completion_mode: "OPERATOR",
    sort_order: itemNumber,
    required: true,
    started_at: null,
    completed_at: status === "COMPLETED" ? "2026-09-10T11:00:00Z" : null,
    verification_result: "UNKNOWN",
    blocked_reason: status === "BLOCKED" ? "Klantinhoud ontbreekt." : null,
    revision: 1,
    permitted_actions: [],
  };
}

test("website slot and request retain the exact dossier context", () => {
  const slot = websiteExecutionSlot(quoteRequestId.toUpperCase());
  assert.equal(slot, `website-${quoteRequestId}`);
  assert.equal(quoteRequestIdFromWebsiteExecutionSlot(slot), quoteRequestId);
  assert.equal(quoteRequestIdFromWebsiteExecutionSlot("website-invalid"), null);
  assert.deepEqual(websiteExecutionRequest({
    request_kind: "website",
    quote_request_id: quoteRequestId,
    website_work: officialWork,
  }), {
    action: "get_website_execution_workspace",
    quote_request_id: quoteRequestId,
  });
  assert.equal(websiteExecutionRequest({ request_kind: "sdf" }), null);
});

test("NONE to PRE_PROJECT keeps the Website slot and never creates concept authority", async () => {
  const [dossiers, child, registry] = await Promise.all([
    read("assets/js/operator-dossiers.mjs"),
    read("assets/js/operator-website-execution-child.mjs"),
    read("assets/js/operator-module-registry.mjs"),
  ]);
  assert.equal(websiteExecutionSlot(quoteRequestId), `website-${quoteRequestId}`);
  assert.match(child, /websiteChildDetailRequest\(options\.slotKey\)/);
  assert.match(child, /get_application_detail/);
  assert.match(child, /websiteExecutionRequest\(detail\)/);
  assert.doesNotMatch(`${dossiers}\n${child}\n${registry}`, /concept-\$\{|`concept-|"concept-/);
});

test("PRE_PROJECT request uses only the stable dossier locator", () => {
  assert.deepEqual(websiteExecutionRequest({
    request_kind: "website",
    quote_request_id: quoteRequestId,
    website_work: preProjectWork,
  }), {
    action: "get_website_execution_workspace",
    quote_request_id: quoteRequestId,
  });
  assert.throws(() => websiteExecutionRequest({
    request_kind: "website",
    quote_request_id: quoteRequestId,
    website_work: { ...preProjectWork, concept_id: null },
  }), /INVALID_WEBSITE_EXECUTION_CONTEXT/);
});

test("PRE_PROJECT V2 validation is exact and context-bound", () => {
  const context = {
    quoteRequestId,
    projectId: null,
    conceptId,
    websiteWorkContextId,
    websiteWorkRevision: 1,
    mode: "PRE_PROJECT",
  };
  const projection = validateWebsiteExecutionWorkspace(preProjectV2, context);
  const view = websiteExecutionView(projection);
  assert.equal(projection.mode, "PRE_PROJECT");
  assert.equal(view.modeLabel, "Voorlopig concept");
  assert.equal(view.releaseLabel, "Niet commercieel vrijgegeven");
  assert.equal(view.briefingLabel, "COMPLETE");
  assert.equal(projection.requirements.message, "Requirements volgen na intake-sync.");
  for (const malformed of [
    { ...preProjectV2, unknown: true },
    { ...preProjectV2, commercially_released: true },
    { ...preProjectV2, website_work_context_id: crypto.randomUUID() },
    { ...preProjectV2, project_id: crypto.randomUUID() },
    { ...preProjectV2, requirements: { state: "EMPTY", message: "Other" } },
  ]) assert.throws(
    () => validateWebsiteExecutionWorkspace(malformed, context),
    /INVALID_WEBSITE_EXECUTION_RESPONSE|WEBSITE_WORKSPACE_BINDING_MISMATCH/,
  );
});

test("Website child branches PRE_PROJECT without Project or Requirements authority", async () => {
  const [child, website] = await Promise.all([
    read("assets/js/operator-website-execution-child.mjs"),
    read("assets/js/operator-website-execution.mjs"),
  ]);
  assert.doesNotMatch(child, /projectWorkspaceRequest/);
  assert.match(child, /websiteExecutionRequest\(detail\)/);
  assert.match(child, /projection\.mode === "OFFICIAL_PROJECT"[^]*projectRequirementsRequest\(context\)/);
  assert.match(child, /: websiteRequirementsSummary\(projection\.requirements, context\)/);
  assert.match(website, /Requirements volgen na intake-sync\./);
  assert.match(child, /data-website-mode/);
  assert.match(child, /data-website-briefing/);
  assert.match(child, /data-website-release/);
});

test("website projection fails closed for the wrong dossier or project", () => {
  assert.throws(() => validateWebsiteExecutionWorkspace({
    ...base,
    start_gate: { ...base.start_gate, quote_request_id: crypto.randomUUID() },
  }, expected), /WEBSITE_WORKSPACE_BINDING_MISMATCH/);
  assert.throws(() => validateWebsiteExecutionWorkspace({
    ...base,
    project: { project_id: crypto.randomUUID() },
  }, expected), /WEBSITE_WORKSPACE_BINDING_MISMATCH/);
});

test("empty workspace and missing preview/production states are explicit", () => {
  const projection = validateWebsiteExecutionWorkspace(base, expected);
  assert.deepEqual(websiteExecutionView(projection), {
    state: "empty",
    message: "Website workspace niet gekoppeld.",
    modeLabel: "Officieel project",
    briefingLabel: "COMPLETE",
    releaseLabel: "Niet commercieel vrijgegeven",
    repository: "Repository niet gekoppeld",
    branch: "Niet beschikbaar",
    preview: "Preview nog niet beschikbaar",
    production: "Production URL nog niet beschikbaar",
    commit: "Nog geen commit geregistreerd",
    links: { github: null, vscode: null, preview: null, production: null },
  });
});

test("repository metadata renders safe GitHub and VS Code Web links", () => {
  const projection = validateWebsiteExecutionWorkspace({
    ...base,
    project: {
      project_id: projectId,
      site: { canonical_url: "https://www.example.com" },
    },
    workspace: workspaceFixture(),
  }, expected);
  const view = websiteExecutionView(projection);
  assert.equal(view.repository, "lws-studio/lws-web-2026-0042");
  assert.equal(view.branch, "develop");
  assert.equal(view.preview, "https://preview.example.com/build/42");
  assert.equal(view.production, "https://www.example.com/");
  assert.equal(view.links.github, "https://github.com/lws-studio/lws-web-2026-0042");
  assert.equal(view.links.vscode, "https://vscode.dev/github/lws-studio/lws-web-2026-0042");
  assert.equal(JSON.stringify(projection).includes("token"), false);
});

test("READY and REPOSITORY_READY retain repository actions", () => {
  for (const workspaceState of ["READY", "REPOSITORY_READY"]) {
    const projection = validateWebsiteExecutionWorkspace({
      ...base,
      workspace: currentWorkspaceFixture(workspaceState),
    }, expected);
    const view = websiteExecutionView(projection);
    assert.equal(view.state, "ready");
    assert.equal(view.links.github, "https://github.com/lws-studio/lws-web-2026-0042");
    assert.equal(view.links.vscode, "https://vscode.dev/github/lws-studio/lws-web-2026-0042");
  }
});

test("non-ready and malformed current workspace states fail closed", () => {
  for (const workspace of [
    currentWorkspaceFixture("PENDING_REPOSITORY"),
    currentWorkspaceFixture("REPOSITORY_FAILED"),
    currentWorkspaceFixture("UNKNOWN"),
    currentWorkspaceFixture("REPOSITORY_READY", { provisioned_by: null }),
    currentWorkspaceFixture("REPOSITORY_READY", { provisioned_at: null }),
  ]) {
    assert.throws(() => validateWebsiteExecutionWorkspace({
      ...base,
      workspace,
    }, expected), /INVALID_WEBSITE_EXECUTION_RESPONSE/);
  }
});

test("unsafe repository and URL references are rejected", () => {
  assert.throws(() => safeWebsiteExecutionLinks("lws-studio", "../other"),
    /INVALID_WEBSITE_REPOSITORY_REFERENCE/);
  assert.throws(() => validateWebsiteExecutionWorkspace({
    ...base,
    workspace: workspaceFixture({
      repository_name: "client-site",
      preview_url: "javascript:alert(1)",
    }),
  }, expected), /INVALID_WEBSITE_EXECUTION_URL/);
});

test("Website Workspace server projection reuses existing authorities and exposes no secrets", async () => {
  const migration = await read("supabase/migrations/20260910030000_add_website_execution_workspace_v1.sql");
  const table = migration.match(/create table public\.website_execution_workspaces \([^]*?\n\);/)?.[0] || "";
  assert.match(migration, /get_operator_project_start_gate_v1/);
  assert.match(migration, /get_commercial_project_view_v2/);
  assert.match(migration, /event\.event_type = 'PROJECT_WORK_STARTED'/);
  assert.match(migration, /event\.metadata->>'quote_request_id'/);
  assert.match(migration, /WEBSITE_WORKSPACE_BINDING_MISMATCH/);
  assert.match(migration, /enable row level security/);
  assert.match(migration, /force row level security/);
  assert.doesNotMatch(table, /production_url|canonical_url|token|secret|source_code/i);
  assert.match(migration, /revoke all privileges on table public\.website_execution_workspaces/);
});

test("Website Workspace V2 is anchored to the stable work context", async () => {
  const migration = await read("supabase/migrations/20260912132000_reanchor_website_execution_workspace_v1.sql");
  assert.match(migration, /add column website_work_context_id uuid/);
  assert.match(migration, /alter column website_work_context_id set not null/);
  assert.match(migration, /unique \(website_work_context_id\)/);
  assert.match(migration, /references public\.website_work_contexts\(website_work_context_id\)/);
  assert.match(migration, /create function public\.get_website_execution_workspace_v2\(/);
  assert.match(migration, /public\.get_operator_website_work_v1/);
  assert.match(migration, /if v_context\.phase = 'PRE_PROJECT'/);
  assert.match(migration, /public\.get_website_execution_workspace_v1/);
  assert.match(migration, /WEBSITE_WORKSPACE_BINDING_MISMATCH/);
  assert.doesNotMatch(migration, /drop column (?:project_id|quote_request_id)/i);
});

test("Website managed child retains lifecycle, safe actions, and explicit denial", async () => {
  const child = await read("assets/js/operator-website-execution-child.mjs");
  const registry = await read("assets/js/operator-module-registry.mjs");
  const projectChild = await read("assets/js/operator-project-workspace-child.mjs");
  assert.match(registry, /startsWith\("website-"\)/);
  assert.match(child, /createOperatorAutoRefresh/);
  assert.match(child, /onAuthorizationFailure/);
  assert.match(child, /Geen toegang tot deze Website Workspace/);
  assert.match(child, /rel="noopener noreferrer"/);
  assert.match(child, /Open GitHub/);
  assert.match(child, /Open Preview/);
  assert.match(child, /Open in VS Code Web/);
  assert.match(child, /Projectbestanden/);
  assert.match(child, /Terug naar Project/);
  assert.match(projectChild, /data-project-website-open/);
  assert.match(projectChild, /!view\.workStarted/);
  assert.doesNotMatch(child, /localStorage|sessionStorage|window\.open|vscode:\/\/file/i);
});

test("Website Workspace opens Requirements through the bounded sibling context", async () => {
  const child = await read("assets/js/operator-website-execution-child.mjs");
  assert.match(child, /data-website-action="requirements"/);
  assert.match(child, /requirementsBoardSlot\(currentSnapshot\.context\.quoteRequestId\)/);
  assert.match(child, /options\.requestOpen\?\.\("dossiers"/);
  assert.doesNotMatch(child, /window\.open|location\.reload/);
});

test("Website child has compact and mobile overflow contracts", async () => {
  const css = await read("assets/css/operator-dashboard.css");
  assert.match(css, /\.website-execution-workspace,\.website-execution \{ width:100%; min-width:0/);
  assert.match(css, /\.website-execution__heading > div \{[^}]*min-width:0/);
  assert.match(css, /\.website-execution__references \{ grid-template-columns:1fr/);
  assert.match(css, /\.website-execution__actions \{ display:grid; grid-template-columns:1fr/);
});

test("commercial command dispatch uses the exact caller-scoped Website RPC", async () => {
  const handler = await read("supabase/functions/commercial-operator-command/handler.ts");
  const index = await read("supabase/functions/commercial-operator-command/index.ts");
  assert.match(handler, /"get_website_execution_workspace"/);
  const branch = index.match(/if \(input\.action === "get_website_execution_workspace"\) \{[^]*?return data;\s*\}/)?.[0] || "";
  assert.match(branch, /"get_website_execution_workspace_v2"[^]*p_quote_request_id: input\.quote_request_id/);
  assert.doesNotMatch(branch, /p_project_id/);
});

test("Website Requirements summary accepts only validated exact project and quote data", () => {
  assert.deepEqual(websiteRequirementsSummary(requirementsProjection(), expected), {
    state: "ready",
    heading: "PROJECTVEREISTEN",
    completed: 8,
    total: 12,
    open: 3,
    blocked: 1,
    readyForPreview: false,
    progress: "08 / 12",
  });
  assert.throws(() => websiteRequirementsSummary({
    ...requirementsProjection(),
    project_id: crypto.randomUUID(),
  }, expected), /PROJECT_REQUIREMENTS_BINDING_MISMATCH/);
  assert.throws(() => websiteRequirementsSummary({
    ...requirementsProjection(),
    quote_request_id: crypto.randomUUID(),
  }, expected), /PROJECT_REQUIREMENTS_BINDING_MISMATCH/);
  assert.throws(() => websiteRequirementsSummary({
    ...requirementsProjection(),
    readiness: { ...requirementsProjection().readiness, required_completed: 9 },
  }, expected), /INVALID_PROJECT_REQUIREMENTS_PROGRESS/);
});

test("Website Requirements summary exposes explicit no-board and preview-ready states", () => {
  const empty = requirementsProjection({
    board: null,
    items: [],
    empty_state: "NO_BOARD",
    readiness: {
      required_total: 0,
      required_completed: 0,
      required_open: 0,
      required_blocked: 0,
      active_requirement_id: null,
      active_item_number: null,
      ready_for_preview: false,
      readiness: "UNKNOWN",
      reason: "NO_BOARD",
    },
    actions: { can_create_board: true, can_create_item: false, can_finalize: false },
  });
  assert.deepEqual(websiteRequirementsSummary(empty, expected), {
    state: "empty",
    heading: "PROJECTVEREISTEN",
    message: "Nog geen projectvereisten beschikbaar.",
  });
  const items = Array.from({ length: 12 }, (_, index) => requirement(index + 1, "COMPLETED"));
  const ready = requirementsProjection({
    items,
    readiness: {
      required_total: 12,
      required_completed: 12,
      required_open: 0,
      required_blocked: 0,
      active_requirement_id: null,
      active_item_number: null,
      ready_for_preview: true,
      readiness: "READY",
      reason: "REQUIREMENTS_READY",
    },
  });
  assert.equal(websiteRequirementsSummary(ready, expected).readyForPreview, true);
});

test("refreshed server DTO replaces Website Requirements summary without client state", () => {
  const before = websiteRequirementsSummary(requirementsProjection(), expected);
  const items = [
    ...Array.from({ length: 9 }, (_, index) => requirement(index + 1, "COMPLETED")),
    ...Array.from({ length: 2 }, (_, index) => requirement(index + 10, "PENDING")),
    requirement(12, "BLOCKED"),
  ];
  const after = websiteRequirementsSummary(requirementsProjection({
    items,
    readiness: {
      required_total: 12,
      required_completed: 9,
      required_open: 2,
      required_blocked: 1,
      active_requirement_id: null,
      active_item_number: null,
      ready_for_preview: false,
      readiness: "BLOCKED",
      reason: "REQUIREMENTS_OPEN",
    },
  }), expected);
  assert.equal(before.progress, "08 / 12");
  assert.equal(after.progress, "09 / 12");
  assert.equal(after.open, 2);
  assert.notEqual(after, before);
  assert.equal(Object.isFrozen(after), true);
});

test("Website child fetches and renders summary through existing refresh and managed sibling flow", async () => {
  const child = await read("assets/js/operator-website-execution-child.mjs");
  assert.match(child, /projectRequirementsRequest\(context\)/);
  assert.match(child, /Promise\.all\(\[[^]*websiteExecutionRequest\(detail\)[^]*get_dossier_assignment/);
  assert.match(child, /validateWebsiteExecutionWorkspace\(rawWorkspace, context\)[^]*projection\.mode === "OFFICIAL_PROJECT"[^]*projectRequirementsRequest\(context\)/);
  assert.match(child, /data-website-requirements-progress/);
  assert.match(child, /data-website-requirements-open/);
  assert.match(child, /data-website-requirements-blocked/);
  assert.match(child, /data-website-requirements-preview/);
  assert.match(child, /summary,/);
  assert.equal(child.indexOf("function renderRequirementsSummary"), child.lastIndexOf("function renderRequirementsSummary"));
  assert.equal(child.indexOf("function renderRequirementsSummary") < child.indexOf("function setLink"), true);
  assert.match(child, /data-website-action="requirements"/);
  assert.match(child, /requirementsBoardSlot\(currentSnapshot\.context\.quoteRequestId\)/);
  assert.doesNotMatch(child, /window\.open|location\.reload|items\.filter|items\.reduce/);
});

test("Website Requirements summary has compact responsive no-overflow contracts", async () => {
  const css = await read("assets/css/operator-dashboard.css");
  assert.match(css, /\.website-execution__requirements \{[^}]*min-width:0[^}]*overflow:hidden/);
  assert.match(css, /\.website-execution__requirements-progress \{[^}]*white-space:nowrap/);
  assert.match(css, /@media \(max-width:900px\)[^{]*\{[^}]*\.website-execution__requirements-facts \{[^}]*grid-template-columns:repeat\(2/);
  assert.match(css, /@media \(max-width:540px\)[^{]*\{[^}]*\.website-execution__requirements-facts \{[^}]*grid-template-columns:1fr/);
});

test("PRE_PROJECT workspace release has one coherent active cache chain", async () => {
  const token = "20260917-pre-project-workspace-r2";
  const [windowPage, guard, registry, child, dossiers] = await Promise.all([
    "operator/window/index.html",
    "assets/js/operator-window-guard.mjs",
    "assets/js/operator-module-registry.mjs",
    "assets/js/operator-website-execution-child.mjs",
    "assets/js/operator-dossiers.mjs",
  ].map(read));
  assert.equal(windowPage.includes(`operator-dashboard.css?v=${token}`), true);
  assert.equal(windowPage.includes(`operator-window-guard.mjs?v=${token}`), true);
  assert.equal(guard.includes(`operator-module-registry.mjs?v=${token}`), true);
  assert.equal(registry.includes(`operator-website-execution-child.mjs?v=${token}`), true);
  assert.equal(child.includes(`operator-website-execution.mjs?v=${token}`), true);
  assert.equal(child.includes(`operator-dossiers.mjs?v=${token}`), true);
  assert.equal(dossiers.includes(`operator-website-execution.mjs?v=${token}`), true);
  assert.doesNotMatch(
    registry,
    /operator-website-execution-child\.mjs\?v=20260913-requirements-wiring-r1/,
  );
});

test("PRE_PROJECT Website opens the existing Requirements managed sibling with the same work context", async () => {
  const child = await read("assets/js/operator-website-execution-child.mjs");
  const detail = {
    quote_request_id: quoteRequestId,
    request_kind: "website",
    application_reference: "LWS-AAN-2026-0042",
    project: null,
    website_work: preProjectWork,
  };
  assert.equal(requirementsBoardSlot(quoteRequestId), `req-${quoteRequestId}`);
  assert.deepEqual(requirementsChildContext(detail, quoteRequestId), {
    quoteRequestId,
    projectId: null,
    conceptId,
    websiteWorkContextId,
    websiteWorkRevision: 1,
    mode: "PRE_PROJECT",
    dossierReference: "LWS-AAN-2026-0042",
    customerName: "Niet beschikbaar",
  });
  assert.doesNotMatch(child, /button[^>]*data-website-requirements-open/);
  assert.doesNotMatch(child, /querySelector\("\[data-website-requirements-open\]"\)\.hidden/);
  assert.match(
    child,
    /action === "requirements"[^]*requestOpen\?\.\("dossiers", requirementsBoardSlot/,
  );
});

const provisionControlHarness = `<!doctype html><html><body><main data-dossiers-workspace></main><script type="module">
window.setInterval = () => 1;
window.clearInterval = () => {};
const params = new URLSearchParams(location.search);
const role = params.get("role") || "owner";
const mode = params.get("mode") || "PRE_PROJECT";
const hasWorkspace = params.get("workspace") === "present";
const quoteRequestId = "${quoteRequestId}";
const projectId = mode === "OFFICIAL_PROJECT" ? "${projectId}" : null;
const conceptId = mode === "PRE_PROJECT" ? "${conceptId}" : null;
const detail = { quote_request_id: quoteRequestId, request_kind: "website", application_reference: "LWS-AAN-2099-0001", website_work: { state: mode, quote_request_id: quoteRequestId, concept_id: conceptId, project_id: projectId, website_work_context_id: "${websiteWorkContextId}", mode, briefing_status: "COMPLETE", commercially_released: false, revision: 1, permitted_actions: ["OPEN_WEBSITE"] } };
const workspace = hasWorkspace ? { website_workspace_id: "a1800000-0000-4000-8000-000000000006", website_work_context_id: "${websiteWorkContextId}", project_id: projectId, quote_request_id: quoteRequestId, workspace_state: "REPOSITORY_READY", repository_provider: "GITHUB", repository_owner: "lws-studio", repository_name: "lws-web-2099-0001", default_branch: "main", preview_branch: null, preview_url: null, last_commit_sha: null, last_commit_at: null, last_build_result: null, last_build_at: null, binding_revision: 1, provisioned_by: "a1800000-0000-4000-8000-000000000010", provisioned_at: "2099-01-01T10:00:00Z", created_at: "2099-01-01T10:00:00Z", updated_at: "2099-01-01T10:00:00Z" } : null;
const projection = { contract_version: 2, mode, quote_request_id: quoteRequestId, concept_id: conceptId, project_id: projectId, website_work_context_id: "${websiteWorkContextId}", context_revision: 1, briefing_status: "COMPLETE", commercially_released: false, project: mode === "OFFICIAL_PROJECT" ? { project_id: projectId, site: null } : null, start_gate: mode === "OFFICIAL_PROJECT" ? { project_id: projectId, quote_request_id: quoteRequestId } : null, workspace, requirements: mode === "OFFICIAL_PROJECT" ? { state: "PROJECT_BOUND", message: null } : { state: "NOT_AVAILABLE", message: "Requirements volgen na intake-sync." } };
const requirements = { contract_version: 1, quote_request_id: quoteRequestId, project_id: projectId, context: { customer: "Preview customer", dossier_reference: "LWS-AAN-2099-0001", project_reference: projectId, assigned_operator: null }, board: null, items: [], empty_state: "NO_BOARD", readiness: { required_total: 0, required_completed: 0, required_open: 0, required_blocked: 0, active_requirement_id: null, active_item_number: null, ready_for_preview: false, readiness: "UNKNOWN", reason: "NO_BOARD" }, actions: { can_create_board: true, can_create_item: false, can_finalize: false } };
const client = { functions: { async invoke(_name, { body }) { let result; if (body.action === "get_application_detail") result = detail; else if (body.action === "get_dossier_substance") result = { customer: { name: "Preview customer" } }; else if (body.action === "get_website_execution_workspace") result = projection; else if (body.action === "get_dossier_assignment") result = { assignee_display_name: "Operator A" }; else if (body.action === "get_project_requirements_board") result = requirements; return { data: { ok: true, result }, error: null }; } } };
const { initializeOperatorWebsiteExecution } = await import("/assets/js/operator-website-execution-child.mjs");
window.controller = initializeOperatorWebsiteExecution(document, client, { role, status: "ACTIVE" }, { slotKey: "website-${quoteRequestId}", onAuthorizationFailure() {}, requireAal2: async () => {} });
</script></body></html>`;

function serveProvisionControlHarness() {
  const server = createServer(async (request, response) => {
    if (request.url?.startsWith("/__provision-control-harness")) {
      response.setHeader("content-type", "text/html; charset=utf-8");
      response.end(provisionControlHarness);
      return;
    }
    const relative = normalize(decodeURIComponent(request.url.split("?")[0])).replace(/^[/\\]+/, "");
    if (relative.includes("..")) { response.writeHead(403).end(); return; }
    try {
      const body = await readFile(join(rootPath, relative));
      response.setHeader("content-type", extname(relative) === ".mjs" ? "text/javascript" : "text/css");
      response.end(body);
    } catch { response.writeHead(404).end(); }
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

test("provision control follows owner PRE_PROJECT empty-workspace render state", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const address = server.address();
    const scenarios = [
      { query: "role=owner&mode=PRE_PROJECT&workspace=null", visible: true },
      { query: "role=operator&mode=PRE_PROJECT&workspace=null", visible: false },
      { query: "role=owner&mode=PRE_PROJECT&workspace=present", visible: false },
      { query: "role=owner&mode=OFFICIAL_PROJECT&workspace=null", visible: false },
    ];
    for (const scenario of scenarios) {
      const page = await browser.newPage();
      await page.goto(`http://127.0.0.1:${address.port}/__provision-control-harness?${scenario.query}`);
      await page.waitForFunction(() => document.querySelector("[data-website-content]")?.hidden === false);
      const control = page.locator('[data-website-action="provision"]');
      assert.equal(await control.count(), 1, "provision control must exist in the rendered child DOM");
      assert.equal(await control.textContent(), "Technische werkruimte starten");
      assert.equal(await control.isVisible(), scenario.visible, scenario.query);
      await page.close();
    }
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});
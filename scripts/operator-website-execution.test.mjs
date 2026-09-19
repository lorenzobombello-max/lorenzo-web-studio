import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";
import test from "node:test";
import { chromium } from "@playwright/test";
import {
  websiteExecutionProvisionRequest,
  quoteRequestIdFromWebsiteExecutionSlot,
  websiteRequirementsSummary,
  validateWebsiteExecutionWorkspace,
  websiteExecutionRequest,
  websiteExecutionSlot,
  websiteExecutionView,
} from "../assets/js/operator-website-execution.mjs";
import { createOperatorDossierAuthority } from "../assets/js/operator-dossiers.mjs";
import * as requirementsModule from "../assets/js/operator-project-requirements.mjs";

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
  contract_version: 3,
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
  const workspaceState = overrides.workspace_state || "REPOSITORY_READY";
  const operationState = Object.hasOwn(overrides, "repository_operation_state")
    ? overrides.repository_operation_state : "COMPLETE";
  const lifecycle = serverLifecycleProjection(workspaceState, operationState);
  const repositoryOwner = Object.hasOwn(overrides, "repository_owner")
    ? overrides.repository_owner : "lws-studio";
  const repositoryName = Object.hasOwn(overrides, "repository_name")
    ? overrides.repository_name : "lws-web-2026-0042";
  return {
    website_workspace_id: "a1800000-0000-4000-8000-000000000006",
    website_work_context_id: websiteWorkContextId,
    project_id: projectId,
    quote_request_id: quoteRequestId,
    workspace_state: workspaceState,
    repository_operation_state: operationState,
    repository_failure_category: lifecycle.repository_failure_category,
    repository_recovery_guidance: lifecycle.repository_recovery_guidance,
    repository_provider: "GITHUB",
    repository_owner: repositoryOwner,
    repository_name: repositoryName,
    repository_navigation_url: repositoryOwner && repositoryName
      ? `https://github.com/${repositoryOwner}/${repositoryName}` : null,
    default_branch: "main",
    preview_branch: "develop",
    preview_url: "https://preview.example.com/build/42#private",
    last_commit_sha: "a".repeat(40),
    last_commit_at: "2026-09-12T12:00:00Z",
    last_build_result: "PASS",
    last_build_at: "2026-09-12T12:01:00Z",
    binding_revision: 1,
    provisioned_by: "a1800000-0000-4000-8000-000000000010",
    provisioned_at: "2026-09-12T10:00:00Z",
    created_at: "2026-09-12T10:00:00Z",
    updated_at: "2026-09-12T12:01:00Z",
    capabilities: { project_files_read: lifecycle.project_files_read },
    ...overrides,
  };
}

function currentWorkspaceFixture(workspaceState, overrides = {}) {
  return workspaceFixture({
    workspace_state: workspaceState,
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

const preProjectV3 = {
  contract_version: 3,
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
    ...preProjectV3,
    workspace: currentWorkspaceFixture("PENDING_REPOSITORY", {
      project_id: null,
      repository_operation_state: null,
      repository_failure_category: null,
      repository_recovery_guidance: "WAIT",
      repository_owner: null,
      repository_name: null,
      repository_navigation_url: null,
      preview_branch: null,
      preview_url: null,
      last_commit_sha: null,
      last_commit_at: null,
      last_build_result: null,
      last_build_at: null,
      capabilities: { project_files_read: false },
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
    website_work_context_id: websiteWorkContextId,
    project_id: null,
    phase: "PRE_PROJECT",
    context: {
      customer: "Acme",
      dossier_reference: "LWS-AAN-2026-0042",
      assigned_operator: null,
    },
    board: {
      requirements_board_id: "a1800000-0000-4000-8000-000000000003",
      sync_state: "CURRENT",
      revision: 12,
      mapping_version: 1,
      current_intake_id: "a1800000-0000-4000-8000-000000000007",
      current_intake_revision: 3,
      current_intake_snapshot_sha256: "a".repeat(64),
    },
    items: [],
    progress: {
      required_total: 12,
      required_completed: 8,
      required_open: 3,
      required_blocked: 1,
      review_pending: 0,
    },
    empty_state: null,
    readiness: {
      ready_for_preview: false,
      readiness: "BLOCKED",
      reason: "REQUIRED_REQUIREMENTS_OPEN",
    },
    ...overrides,
  };
}

function validatedRequirements(overrides = {}) {
  return requirementsModule.validateWebsiteRequirementsBoard(
    requirementsProjection(overrides),
    { quoteRequestId, websiteWorkContextId },
  );
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

test("PRE_PROJECT V3 validation is exact and context-bound", () => {
  const context = {
    quoteRequestId,
    projectId: null,
    conceptId,
    websiteWorkContextId,
    websiteWorkRevision: 1,
    mode: "PRE_PROJECT",
  };
  const projection = validateWebsiteExecutionWorkspace(preProjectV3, context);
  const view = websiteExecutionView(projection);
  assert.equal(projection.mode, "PRE_PROJECT");
  assert.equal(view.modeLabel, "Voorlopig concept");
  assert.equal(view.releaseLabel, "Niet commercieel vrijgegeven");
  assert.equal(view.briefingLabel, "COMPLETE");
  assert.equal(projection.requirements.message, "Requirements volgen na intake-sync.");
  for (const malformed of [
    { ...preProjectV3, unknown: true },
    { ...preProjectV3, commercially_released: true },
    { ...preProjectV3, website_work_context_id: crypto.randomUUID() },
    { ...preProjectV3, project_id: crypto.randomUUID() },
    { ...preProjectV3, requirements: { state: "EMPTY", message: "Other" } },
  ]) assert.throws(
    () => validateWebsiteExecutionWorkspace(malformed, context),
    /INVALID_WEBSITE_EXECUTION_RESPONSE|WEBSITE_WORKSPACE_BINDING_MISMATCH/,
  );
});

test("Website child reads Website Requirements independently in both phases", async () => {
  const [child, website] = await Promise.all([
    read("assets/js/operator-website-execution-child.mjs"),
    read("assets/js/operator-website-execution.mjs"),
  ]);
  assert.doesNotMatch(child, /projectWorkspaceRequest/);
  assert.match(child, /websiteExecutionRequest\(detail\)/);
  assert.match(child, /websiteRequirementsBoardRequest\(requirementsContext\)/);
  assert.match(child, /validateWebsiteRequirementsBoard\([^]*rawRequirements,[^]*requirementsContext/);
  assert.doesNotMatch(child, /projectRequirementsRequest|projectRequirementsSummary/);
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
    links: { github: null, preview: null, production: null },
  });
});

test("repository metadata uses only server-projected GitHub navigation", () => {
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
  assert.equal(Object.hasOwn(view.links, "vscode"), false);
  assert.equal(JSON.stringify(projection).includes("token"), false);
});

test("only server-capable REPOSITORY_READY enables project files", () => {
  for (const [workspaceState, expectedState] of [
    ["READY", "repository_unavailable"],
    ["REPOSITORY_READY", "ready"],
  ]) {
    const projection = validateWebsiteExecutionWorkspace({
      ...base,
      workspace: currentWorkspaceFixture(workspaceState),
    }, expected);
    const view = websiteExecutionView(projection);
    assert.equal(view.state, expectedState);
    assert.equal(view.links.github, "https://github.com/lws-studio/lws-web-2026-0042");
    assert.equal(Object.hasOwn(view.links, "vscode"), false);
  }
});

test("malformed current workspace states fail closed", () => {
  for (const workspace of [
    currentWorkspaceFixture("UNKNOWN"),
    currentWorkspaceFixture("REPOSITORY_READY", { provisioned_by: null }),
    currentWorkspaceFixture("REPOSITORY_READY", { provisioned_at: null }),
    currentWorkspaceFixture("REPOSITORY_READY", { repository_owner: null }),
    currentWorkspaceFixture("REPOSITORY_READY", { repository_name: null }),
    currentWorkspaceFixture("REPOSITORY_READY", { repository_owner: "../other" }),
    currentWorkspaceFixture("REPOSITORY_READY", { repository_name: "../other" }),
    currentWorkspaceFixture("REPOSITORY_READY", {
      repository_url: "https://github.com/client-selected/repository",
    }),
  ]) {
    assert.throws(() => validateWebsiteExecutionWorkspace({
      ...base,
      workspace,
    }, expected), /INVALID_WEBSITE_EXECUTION_RESPONSE/);
  }
});

test("unsafe repository and URL references are rejected", () => {
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
  assert.doesNotMatch(child, /Open Preview|Open in VS Code Web/);
  assert.match(child, /Projectbestanden/);
  assert.match(child, /Terug naar Project/);
  assert.match(projectChild, /data-project-website-open/);
  assert.match(projectChild, /!view\.workStarted/);
  assert.doesNotMatch(child, /localStorage|sessionStorage|window\.open|vscode:\/\/file/i);
});

test("Website Workspace exposes only the Task 7 managed Requirements route", async () => {
  const child = await read("assets/js/operator-website-execution-child.mjs");
  assert.match(child, /data-website-action="requirements"/);
  assert.doesNotMatch(child, /data-website-action="requirements" disabled aria-disabled="true"/);
  assert.match(child, /requirementsBoardSlot\(currentSnapshot\.context\.quoteRequestId\)/);
  assert.match(child, /action === "requirements"[^]*requestOpen\?\.\("dossiers"/);
  assert.doesNotMatch(child, /De volledige Website Requirements-werkruimte wordt in de volgende stap geactiveerd\./);
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
  assert.match(branch, /executeCallerJwtWebsiteExecutionWorkspaceReadAction/);
  assert.match(index, /"get_website_execution_workspace_v3"[^]*p_quote_request_id: input\.quote_request_id/);
  assert.doesNotMatch(branch, /p_project_id/);
});

test("Website Requirements summary accepts only validated Website board data", () => {
  assert.deepEqual(websiteRequirementsSummary(validatedRequirements()), {
    state: "READY",
    requirements_board_id: "a1800000-0000-4000-8000-000000000003",
    board_revision: 12,
    completed: 8,
    total: 12,
    open: 3,
    blocked: 1,
    review_required: false,
  });
  assert.throws(
    () => websiteRequirementsSummary(requirementsProjection()),
    /UNVALIDATED_WEBSITE_REQUIREMENTS_RESPONSE/,
  );
});

test("Website Requirements summary exposes both exact empty states", () => {
  const progress = {
    required_total: 0,
    required_completed: 0,
    required_open: 0,
    required_blocked: 0,
    review_pending: 0,
  };
  const noBoard = validatedRequirements({
    board: null,
    items: [],
    empty_state: "NO_BOARD",
    progress,
  });
  assert.deepEqual(websiteRequirementsSummary(noBoard), {
    state: "NO_BOARD", requirements_board_id: null, board_revision: null,
    completed: 0, total: 0, open: 0, blocked: 0, review_required: false,
  });
  const ineligible = validatedRequirements({
    board: null, items: [], empty_state: "INTAKE_NOT_ELIGIBLE", progress,
  });
  assert.deepEqual(websiteRequirementsSummary(ineligible), {
    state: "INTAKE_NOT_ELIGIBLE", requirements_board_id: null, board_revision: null,
    completed: null, total: null, open: null, blocked: null, review_required: false,
  });
});

test("refreshed server DTO replaces Website Requirements summary without client state", () => {
  const before = websiteRequirementsSummary(validatedRequirements());
  const after = websiteRequirementsSummary(validatedRequirements({
    board: { ...requirementsProjection().board, sync_state: "REVIEW_REQUIRED", revision: 13 },
    progress: {
      required_total: 12,
      required_completed: 9,
      required_open: 2,
      required_blocked: 1,
      review_pending: 1,
    },
  }));
  assert.equal(before.completed, 8);
  assert.equal(after.completed, 9);
  assert.equal(after.open, 2);
  assert.equal(after.state, "REVIEW_REQUIRED");
  assert.equal(after.review_required, true);
  assert.notEqual(after, before);
  assert.equal(Object.isFrozen(after), true);
});

test("Website child fetches and renders an independent localized summary", async () => {
  const child = await read("assets/js/operator-website-execution-child.mjs");
  assert.match(child, /websiteRequirementsBoardRequest\(requirementsContext\)/);
  assert.match(child, /Promise\.all\(\[[^]*websiteExecutionRequest\(detail\)[^]*get_dossier_assignment/);
  assert.match(child, /validateWebsiteExecutionWorkspace\(rawWorkspace, context\)[^]*validateWebsiteRequirementsBoard\([^]*rawRequirements,[^]*requirementsContext/);
  assert.match(child, /data-website-requirements-progress/);
  assert.match(child, /data-website-requirements-open/);
  assert.match(child, /data-website-requirements-blocked/);
  assert.match(child, /data-website-requirements-preview/);
  assert.match(child, /requirementsState:/);
  assert.equal(child.indexOf("function renderRequirementsSummary"), child.lastIndexOf("function renderRequirementsSummary"));
  assert.equal(child.indexOf("function renderRequirementsSummary") < child.indexOf("function setLink"), true);
  assert.match(child, /data-website-action="requirements"/);
  assert.match(child, /"LOADING"[^]*"ERROR"[^]*"STALE"/);
  assert.doesNotMatch(child, /projectRequirementsRequest|projectRequirementsSummary|window\.open|location\.reload|items\.filter|items\.reduce/);
});

test("Website Requirements summary has compact responsive no-overflow contracts", async () => {
  const css = await read("assets/css/operator-dashboard.css");
  assert.match(css, /\.website-execution__requirements \{[^}]*min-width:0[^}]*overflow:hidden/);
  for (const state of ["LOADING", "ERROR", "REVIEW_REQUIRED", "STALE"]) {
    assert.match(css, new RegExp(`data-website-requirements-state="${state}"`));
  }
  assert.match(css, /data-website-action="requirements"\]:disabled/);
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

test("PRE_PROJECT Website activates the canonical Requirements child route", async () => {
  const child = await read("assets/js/operator-website-execution-child.mjs");
  assert.doesNotMatch(child, /data-website-action="requirements" disabled aria-disabled="true"/);
  assert.match(child, /requirementsBoardSlot/);
  assert.match(child, /action === "requirements"/);
});

const provisionControlHarness = `<!doctype html><html><body><main data-dossiers-workspace></main><script type="module">
window.setInterval = () => 1;
window.clearInterval = () => {};
const params = new URLSearchParams(location.search);
const role = params.get("role") || "owner";
const mode = params.get("mode") || "PRE_PROJECT";
const hasWorkspace = params.get("workspace") === "present";
window.task8Events = [];
window.task8Requests = [];
window.task6Requests = [];
window.task7Opens = [];
window.task6Fail = params.get("requirements") === "error";
window.open = () => window.task8Events.push("window.open");
const quoteRequestId = "${quoteRequestId}";
const projectId = mode === "OFFICIAL_PROJECT" ? "${projectId}" : null;
const conceptId = mode === "PRE_PROJECT" ? "${conceptId}" : null;
const detail = { quote_request_id: quoteRequestId, request_kind: "website", application_reference: "LWS-AAN-2099-0001", website_work: { state: mode, quote_request_id: quoteRequestId, concept_id: conceptId, project_id: projectId, website_work_context_id: "${websiteWorkContextId}", mode, briefing_status: "COMPLETE", commercially_released: false, revision: 1, permitted_actions: ["OPEN_WEBSITE"] } };
const workspace = hasWorkspace ? { website_workspace_id: "a1800000-0000-4000-8000-000000000006", website_work_context_id: "${websiteWorkContextId}", project_id: projectId, quote_request_id: quoteRequestId, workspace_state: "REPOSITORY_READY", repository_operation_state: "COMPLETE", repository_failure_category: null, repository_recovery_guidance: null, repository_provider: "GITHUB", repository_owner: "lws-studio", repository_name: "lws-web-2099-0001", repository_navigation_url: "https://github.com/lws-studio/lws-web-2099-0001", default_branch: "main", preview_branch: null, preview_url: null, last_commit_sha: null, last_commit_at: null, last_build_result: null, last_build_at: null, binding_revision: 1, provisioned_by: "a1800000-0000-4000-8000-000000000010", provisioned_at: "2099-01-01T10:00:00Z", created_at: "2099-01-01T10:00:00Z", updated_at: "2099-01-01T10:00:00Z", capabilities: { project_files_read: role === "owner" } } : null;
const projection = { contract_version: 3, mode, quote_request_id: quoteRequestId, concept_id: conceptId, project_id: projectId, website_work_context_id: "${websiteWorkContextId}", context_revision: 1, briefing_status: "COMPLETE", commercially_released: false, project: mode === "OFFICIAL_PROJECT" ? { project_id: projectId, site: null } : null, start_gate: mode === "OFFICIAL_PROJECT" ? { project_id: projectId, quote_request_id: quoteRequestId } : null, workspace, requirements: mode === "OFFICIAL_PROJECT" ? { state: "PROJECT_BOUND", message: null } : { state: "NOT_AVAILABLE", message: "Requirements volgen na intake-sync." } };
const requirements = { contract_version: 1, quote_request_id: quoteRequestId, website_work_context_id: "${websiteWorkContextId}", project_id: projectId, phase: mode, context: { customer: "Preview customer", dossier_reference: "LWS-AAN-2099-0001", assigned_operator: null }, board: { requirements_board_id: "a1800000-0000-4000-8000-000000000003", sync_state: params.get("requirements") === "review" ? "REVIEW_REQUIRED" : "CURRENT", revision: 12, mapping_version: 1, current_intake_id: "a1800000-0000-4000-8000-000000000007", current_intake_revision: 3, current_intake_snapshot_sha256: "a".repeat(64) }, items: [], progress: { required_total: 0, required_completed: 0, required_open: 0, required_blocked: 0, review_pending: params.get("requirements") === "review" ? 1 : 0 }, readiness: { ready_for_preview: true, readiness: "READY", reason: "REQUIREMENTS_READY" }, empty_state: null };
const snapshot = { commit_sha: "a".repeat(40), ref_label: "main" };
const directoryResult = (request) => {
  let entries;
  let nextCursor = null;
  if (request.path === "src") {
    entries = [{ entry_type: "ENTRY", name: "nested.js", path: "src/nested.js", kind: "FILE", size_bytes: 8, readability: "READABLE_CANDIDATE", selectable: true }];
  } else if (request.cursor === "opaque-next") {
    entries = [{ entry_type: "ENTRY", name: "z-last.txt", path: "z-last.txt", kind: "FILE", size_bytes: 3, readability: "READABLE_CANDIDATE", selectable: true }];
  } else if (params.get("empty") === "1") {
    entries = [];
  } else if (params.get("page") === "500") {
    entries = Array.from({ length: 500 }, (_, index) => ({ entry_type: "ENTRY", name: \`file-\${String(index).padStart(3, "0")}.txt\`, path: \`file-\${String(index).padStart(3, "0")}.txt\`, kind: "FILE", size_bytes: index, readability: "READABLE_CANDIDATE", selectable: true }));
    nextCursor = "opaque-next";
  } else {
    entries = [
      { entry_type: "ENTRY", name: "src", path: "src", kind: "DIRECTORY", size_bytes: null, readability: "DIRECTORY", selectable: true },
      { entry_type: "ENTRY", name: "README.md", path: "README.md", kind: "FILE", size_bytes: 12, readability: "READABLE_CANDIDATE", selectable: true },
      { entry_type: "ENTRY", name: "archive.zip", path: "archive.zip", kind: "FILE", size_bytes: 2000000, readability: "TOO_LARGE", selectable: false },
      { entry_type: "ENTRY", name: "linked", path: "linked", kind: "UNSUPPORTED", size_bytes: null, readability: "UNSUPPORTED", selectable: false },
      { entry_type: "BLOCKED_CREDENTIAL", name: "Geblokkeerd bestand", kind: "UNSUPPORTED", readability: "SENSITIVE_BLOCKED", selectable: false },
    ];
    nextCursor = "opaque-next";
  }
  return { contract_version: 1, quote_request_id: quoteRequestId, website_work_context_id: "${websiteWorkContextId}", workspace_state: "REPOSITORY_READY", repository: { display_name: "lws-studio/lws-web-2099-0001", binding_revision: 1 }, snapshot, directory: request.path, entries, next_cursor: nextCursor };
};
const client = { functions: { async invoke(_name, { body }) { let result; if (body.action === "get_application_detail") result = detail; else if (body.action === "get_dossier_substance") result = { customer: { name: "Preview customer" } }; else if (body.action === "get_website_execution_workspace") result = projection; else if (body.action === "get_dossier_assignment") result = { assignee_display_name: "Operator A" }; else if (body.action === "get_website_requirements_board") { window.task6Requests.push(structuredClone(body)); if (params.get("requirementsDelay") === "1") await new Promise((resolve) => setTimeout(resolve, 150)); if (window.task6Fail) return { data: null, error: new Error("requirements unavailable") }; result = requirements; } else if (body.action === "list_website_project_directory") { window.task8Events.push("gateway"); window.task8Requests.push(structuredClone(body)); if (params.get("delay") === "1") await new Promise((resolve) => setTimeout(resolve, 150)); result = directoryResult(body); } else if (body.action === "read_website_project_file") { window.task8Events.push("gateway"); window.task8Requests.push(structuredClone(body)); result = { contract_version: 1, quote_request_id: quoteRequestId, website_work_context_id: "${websiteWorkContextId}", workspace_state: "REPOSITORY_READY", repository: { display_name: "lws-studio/lws-web-2099-0001", binding_revision: 1 }, snapshot, file: { path: body.path, size_bytes: 4, media_type: "text/plain", encoding: "utf-8", content: "safe" } }; } return { data: { ok: true, result }, error: null }; } } };
const { initializeOperatorWebsiteExecution } = await import("/assets/js/operator-website-execution-child.mjs");
window.controller = initializeOperatorWebsiteExecution(document, client, { role, status: "ACTIVE" }, { slotKey: "website-${quoteRequestId}", onAuthorizationFailure() {}, requireAal2: async () => { window.task8Events.push("aal2"); }, requestOpen: (moduleKey, slotKey) => { window.task7Opens.push({ moduleKey, slotKey }); return true; } });
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

async function openTask8Page(browser, server, query = "") {
  const address = server.address();
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${address.port}/__provision-control-harness?${query}`);
  await page.waitForFunction(() => document.querySelector("[data-website-content]")?.hidden === false);
  return page;
}

test("Website Requirements renders loading, review and the active Task 7 control", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const loadingPage = await openTask8Page(
      browser,
      server,
      "role=owner&mode=PRE_PROJECT&workspace=present&requirementsDelay=1",
    );
    const loadingPanel = loadingPage.locator("[data-website-requirements-panel]");
    assert.equal(await loadingPanel.getAttribute("data-website-requirements-state"), "LOADING");
    assert.match(await loadingPanel.textContent(), /Websitevereisten laden/);
    await loadingPage.waitForFunction(() =>
      document.querySelector("[data-website-requirements-panel]")?.dataset.websiteRequirementsState === "READY");
    assert.deepEqual(await loadingPage.evaluate(() => window.task6Requests[0]), {
      action: "get_website_requirements_board",
      quote_request_id: quoteRequestId,
      website_work_context_id: websiteWorkContextId,
    });
    const openControl = loadingPage.locator('[data-website-action="requirements"]');
    assert.equal(await openControl.isVisible(), true);
    assert.equal(await openControl.isDisabled(), false);
    await openControl.click();
    assert.deepEqual(await loadingPage.evaluate(() => window.task7Opens), [{
      moduleKey: "dossiers",
      slotKey: `req-${quoteRequestId}`,
    }]);
    await loadingPage.close();

    const reviewPage = await openTask8Page(
      browser,
      server,
      "role=owner&mode=OFFICIAL_PROJECT&workspace=present&requirements=review",
    );
    await reviewPage.waitForFunction(() =>
      document.querySelector("[data-website-requirements-panel]")?.dataset.websiteRequirementsState === "REVIEW_REQUIRED");
    assert.match(await reviewPage.locator("[data-website-requirements-panel]").textContent(), /Controle vereist/);
    await reviewPage.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("Website Requirements failure stays local and preserves Projectbestanden", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await openTask8Page(
      browser,
      server,
      "role=owner&mode=PRE_PROJECT&workspace=present&requirements=error",
    );
    await page.waitForFunction(() =>
      document.querySelector("[data-website-requirements-panel]")?.dataset.websiteRequirementsState === "ERROR");
    assert.equal(await page.locator("[data-website-content]").isVisible(), true);
    assert.match(await page.locator("[data-website-requirements-panel]").textContent(), /niet veilig worden geladen/);
    await page.locator('[data-website-action="files"]').click();
    await page.waitForFunction(() => window.task8Requests.length === 1);
    assert.equal(await page.locator(".website-project-files__row").count() > 0, true);
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("failed Website Requirements refresh keeps the last server summary stale", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await openTask8Page(
      browser,
      server,
      "role=owner&mode=PRE_PROJECT&workspace=present",
    );
    await page.waitForFunction(() =>
      document.querySelector("[data-website-requirements-panel]")?.dataset.websiteRequirementsState === "READY");
    await page.evaluate(() => { window.task6Fail = true; });
    await page.evaluate(() => window.controller.refresh());
    await page.waitForFunction(() =>
      document.querySelector("[data-website-requirements-panel]")?.dataset.websiteRequirementsState === "STALE");
    const panel = page.locator("[data-website-requirements-panel]");
    assert.match(await panel.textContent(), /00 \/ 00/);
    assert.match(await panel.textContent(), /Verouderde gegevens/);
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("Projectbestanden activates one internal host with exact owner AAL2 root intent", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await openTask8Page(browser, server, "role=owner&mode=PRE_PROJECT&workspace=present");
    assert.equal(await page.locator("[data-website-project-files]").count(), 1);
    await page.locator('[data-website-action="files"]').click();
    await page.waitForFunction(() => window.task8Requests.length === 1);
    assert.deepEqual(await page.evaluate(() => window.task8Requests[0]), {
      action: "list_website_project_directory",
      quote_request_id: quoteRequestId,
      path: "",
      cursor: null,
    });
    assert.deepEqual(await page.evaluate(() => window.task8Events.slice(0, 2)), ["aal2", "gateway"]);
    assert.equal(await page.evaluate(() => document.querySelector("[data-website-project-files]").contains(document.activeElement)), true);
    assert.equal(await page.locator('[data-website-link="github"]').getAttribute("href"),
      "https://github.com/lws-studio/lws-web-2099-0001");
    assert.equal(await page.locator('[data-website-link="preview"], [data-website-link="vscode"]').count(), 0);
    assert.equal(await page.evaluate(() => window.task8Events.includes("window.open")), false);
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("owner-ineligible Projectbestanden remains visible and makes zero file requests", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await openTask8Page(browser, server, "role=operator&mode=PRE_PROJECT&workspace=present");
    await page.locator('[data-website-action="files"]').click();
    await page.waitForTimeout(30);
    assert.deepEqual(await page.evaluate(() => window.task8Requests), []);
    assert.deepEqual(await page.evaluate(() => window.task8Events), []);
    assert.match(await page.locator(".website-project-files__status").textContent(), /geen toegang|niet beschikbaar/i);
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("Projectbestanden expands lazily and renders exact inert redacted entry behavior", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await openTask8Page(browser, server, "role=owner&mode=PRE_PROJECT&workspace=present");
    await page.locator('[data-website-action="files"]').click();
    await page.waitForSelector('.website-project-files__row--directory');
    const initialLabels = await page.locator(".website-project-files__row").allTextContents();
    assert.deepEqual(initialLabels.slice(0, 2), ["src", "README.md"]);
    await page.getByRole("treeitem", { name: /Map src/ }).click();
    await page.waitForFunction(() => window.task8Requests.some((request) => request.path === "src"));
    assert.deepEqual(await page.evaluate(() => window.task8Requests.at(-1)), {
      action: "list_website_project_directory",
      quote_request_id: quoteRequestId,
      path: "src",
      cursor: null,
    });
    assert.equal(await page.getByText("nested.js", { exact: true }).count(), 1);
    const inert = page.locator(".website-project-files__row--inert");
    assert.equal(await inert.count(), 3);
    assert.equal(await inert.locator("button, a").count(), 0);
    const blocked = page.getByText("Geblokkeerd bestand", { exact: true });
    assert.equal(await blocked.count(), 1);
    assert.equal(await blocked.evaluate((node) => [...node.attributes].some((attribute) => /env|npmrc|sha|path/i.test(attribute.value))), false);
    assert.equal((await page.locator("[data-website-project-files]").textContent()).includes("TEXT"), false);
    assert.equal((await page.locator("[data-website-project-files]").textContent()).includes("BINARY_UNSUPPORTED"), false);
    await page.getByRole("treeitem", { name: /README\.md/ }).click();
    await page.waitForFunction(() => window.task8Requests.some((request) => request.action === "read_website_project_file"));
    assert.equal(await page.locator("[data-project-file-content], .website-project-files__content").count(), 0);
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("Projectbestanden supports 500-entry pagination, opaque continuation and canonical refresh", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await openTask8Page(browser, server, "role=owner&mode=PRE_PROJECT&workspace=present&page=500");
    await page.locator('[data-website-action="files"]').click();
    await page.waitForFunction(() => document.querySelectorAll(".website-project-files__row").length === 500);
    await page.getByRole("button", { name: "Meer laden" }).click();
    await page.waitForFunction(() => document.querySelectorAll(".website-project-files__row").length === 501);
    assert.deepEqual(await page.evaluate(() => window.task8Requests[1]), {
      action: "list_website_project_directory",
      quote_request_id: quoteRequestId,
      path: "",
      cursor: "opaque-next",
    });
    await page.locator(".website-project-files__refresh").click();
    await page.waitForFunction(() => window.task8Requests.length === 3);
    assert.deepEqual(await page.evaluate(() => window.task8Requests[2]), {
      action: "list_website_project_directory",
      quote_request_id: quoteRequestId,
      path: "",
      cursor: null,
    });
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("Projectbestanden empty, loading lockout, keyboard focus and mobile overflow are stable", async () => {
  const server = await serveProvisionControlHarness();
  const browser = await chromium.launch({ headless: true });
  try {
    const emptyPage = await openTask8Page(browser, server, "role=owner&mode=PRE_PROJECT&workspace=present&empty=1");
    await emptyPage.locator('[data-website-action="files"]').click();
    await emptyPage.waitForSelector('.website-project-files__empty:not([hidden])');
    assert.match(await emptyPage.locator(".website-project-files__empty").textContent(), /geen bestanden/i);
    await emptyPage.close();

    const page = await openTask8Page(browser, server, "role=owner&mode=PRE_PROJECT&workspace=present&delay=1");
    await page.setViewportSize({ width: 375, height: 740 });
    const trigger = page.locator('[data-website-action="files"]');
    await trigger.press("Enter");
    await trigger.click();
    await page.waitForFunction(() => window.task8Requests.length === 1);
    assert.equal(await page.locator(".website-project-files__refresh").isDisabled(), true);
    await page.waitForSelector('.website-project-files__row');
    await page.locator('.website-project-files__row--directory').focus();
    assert.equal(await page.locator('.website-project-files__row--directory').evaluate((node) => node === document.activeElement), true);
    const dimensions = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      document: document.documentElement.scrollWidth,
      host: document.querySelector("[data-website-project-files]").scrollWidth,
      hostClient: document.querySelector("[data-website-project-files]").clientWidth,
    }));
    assert.equal(dimensions.document <= dimensions.viewport, true);
    assert.equal(dimensions.host <= dimensions.hostClient + 1, true);
    await page.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("Task 8 keeps one Website child and adds no files build editor or workspace slot", async () => {
  const [child, registry, css] = await Promise.all([
    read("assets/js/operator-website-execution-child.mjs"),
    read("assets/js/operator-module-registry.mjs"),
    read("assets/css/operator-dashboard.css"),
  ]);
  assert.match(child, /mountWebsiteProjectFilesTree/);
  assert.equal((child.match(/data-website-project-files/g) || []).length, 1);
  assert.match(child, /WEBSITE_PROJECT_FILE_ACTIONS\.has\(request\.action\)/);
  assert.match(child, /client\.functions\.invoke\("commercial-operator-command"/);
  assert.doesNotMatch(child, /scrollIntoView\(\{ block: "start", behavior: "smooth" \}\)/);
  assert.doesNotMatch(child, /Open Preview|Open in VS Code Web|data-website-link="(?:preview|vscode)"/);
  assert.doesNotMatch(child, /window\.open|vscode\.dev|github\.dev/);
  assert.equal((registry.match(/startsWith\("website-"\)/g) || []).length, 1);
  assert.doesNotMatch(registry, /startsWith\("(?:files|build|editor)-"\)/);
  assert.match(css, /\.website-project-files/);
});

const repositoryOperationStates = [
  "CLAIMED", "CREATING", "EXTERNAL_CREATED", "VERIFYING",
  "RETRYABLE_FAILED", "RETRY_SCHEDULED", "BLOCKED", "QUARANTINED",
  "TERMINAL_FAILED", "COMPLETE", null,
];
const repositoryWorkspaceStates = [
  "PENDING_REPOSITORY", "REPOSITORY_PROVISIONING", "REPOSITORY_READY",
  "REPOSITORY_FAILED", "READY",
];

function serverLifecycleProjection(workspaceState, operationState) {
  const failure = operationState === "QUARANTINED" ? "QUARANTINED"
    : operationState === "BLOCKED" ? "BLOCKED"
    : operationState === "TERMINAL_FAILED" ? "TERMINAL"
    : ["RETRYABLE_FAILED", "RETRY_SCHEDULED"].includes(operationState) ? "RETRYABLE"
    : null;
  const recovery = operationState === "QUARANTINED" ? "RECONCILIATION_REQUIRED"
    : ["BLOCKED", "TERMINAL_FAILED"].includes(operationState) ? "CONTACT_OWNER"
    : ["RETRYABLE_FAILED", "RETRY_SCHEDULED"].includes(operationState) ? "REFRESH_LATER"
    : workspaceState === "READY" ? "RECONCILIATION_REQUIRED"
    : workspaceState === "REPOSITORY_FAILED" ? "CONTACT_OWNER"
    : ["PENDING_REPOSITORY", "REPOSITORY_PROVISIONING"].includes(workspaceState)
      || ["CLAIMED", "CREATING", "EXTERNAL_CREATED", "VERIFYING"].includes(operationState)
      ? "WAIT"
    : workspaceState === "REPOSITORY_READY" && operationState === "COMPLETE"
      ? null : "RECONCILIATION_REQUIRED";
  return {
    repository_failure_category: failure,
    repository_recovery_guidance: recovery,
    project_files_read: workspaceState === "REPOSITORY_READY" && operationState === "COMPLETE",
  };
}

function v3WorkspaceFixture(workspaceState, operationState, overrides = {}) {
  const lifecycle = serverLifecycleProjection(workspaceState, operationState);
  return {
    website_workspace_id: "a1800000-0000-4000-8000-000000000006",
    website_work_context_id: websiteWorkContextId,
    project_id: projectId,
    quote_request_id: quoteRequestId,
    workspace_state: workspaceState,
    repository_operation_state: operationState,
    repository_failure_category: lifecycle.repository_failure_category,
    repository_recovery_guidance: lifecycle.repository_recovery_guidance,
    repository_provider: "GITHUB",
    repository_owner: "lws-studio",
    repository_name: "lws-web-2026-0042",
    repository_navigation_url: "https://github.com/lws-studio/lws-web-2026-0042",
    default_branch: "main",
    preview_branch: "develop",
    preview_url: "https://preview.example.com/build/42",
    last_commit_sha: "a".repeat(40),
    last_commit_at: "2026-09-12T12:00:00Z",
    last_build_result: "PASS",
    last_build_at: "2026-09-12T12:01:00Z",
    binding_revision: 1,
    provisioned_by: "a1800000-0000-4000-8000-000000000010",
    provisioned_at: "2026-09-12T10:00:00Z",
    created_at: "2026-09-12T10:00:00Z",
    updated_at: "2026-09-12T12:01:00Z",
    capabilities: { project_files_read: lifecycle.project_files_read },
    ...overrides,
  };
}

function v3Fixture(workspace, overrides = {}) {
  return { ...base, contract_version: 3, workspace, ...overrides };
}

test("Website Execution v3 validates the complete server lifecycle matrix", () => {
  for (const workspaceState of repositoryWorkspaceStates) {
    for (const operationState of [...repositoryOperationStates, "SERVER_UNKNOWN_NORMALIZED_TO_NULL"]) {
      const normalizedOperation = operationState === "SERVER_UNKNOWN_NORMALIZED_TO_NULL"
        ? null : operationState;
      const projected = serverLifecycleProjection(workspaceState, normalizedOperation);
      const result = validateWebsiteExecutionWorkspace(v3Fixture(
        v3WorkspaceFixture(workspaceState, normalizedOperation),
      ), expected);
      assert.equal(result.workspace.repository_operation_state, normalizedOperation);
      assert.equal(result.workspace.repository_failure_category,
        projected.repository_failure_category);
      assert.equal(result.workspace.repository_recovery_guidance,
        projected.repository_recovery_guidance);
      assert.equal(result.workspace.capabilities.project_files_read,
        projected.project_files_read);
    }
  }
});

test("Website Execution v3 preserves independently projected lifecycle fields", () => {
  const contradictory = v3WorkspaceFixture("REPOSITORY_READY", "COMPLETE", {
    repository_failure_category: "BLOCKED",
    repository_recovery_guidance: "REFRESH_LATER",
    capabilities: { project_files_read: false },
  });
  const result = validateWebsiteExecutionWorkspace(v3Fixture(contradictory), expected);
  assert.equal(result.workspace.repository_failure_category, "BLOCKED");
  assert.equal(result.workspace.repository_recovery_guidance, "REFRESH_LATER");
  assert.equal(result.workspace.capabilities.project_files_read, false);
  for (const malformed of [
    { repository_failure_category: "INVENTED" },
    { repository_recovery_guidance: "RETRY_NOW" },
    { capabilities: { project_files_read: "yes" } },
    { repository_operation_state: "UNKNOWN" },
  ]) assert.throws(() => validateWebsiteExecutionWorkspace(v3Fixture(
    v3WorkspaceFixture("REPOSITORY_READY", "COMPLETE", malformed),
  ), expected), /INVALID_WEBSITE_EXECUTION_RESPONSE/);
});

test("Website Execution v3 keeps PRE_PROJECT project_id null", () => {
  const context = {
    quoteRequestId,
    projectId: null,
    conceptId,
    websiteWorkContextId,
    websiteWorkRevision: 1,
    mode: "PRE_PROJECT",
  };
  const workspace = v3WorkspaceFixture("REPOSITORY_READY", "COMPLETE", {
    project_id: null,
  });
  const result = validateWebsiteExecutionWorkspace({
    ...preProjectV3,
    contract_version: 3,
    workspace,
  }, context);
  assert.equal(result.project_id, null);
  assert.equal(result.workspace.project_id, null);
  assert.equal(result.workspace.capabilities.project_files_read, true);
});

test("Website Execution uses only safe server-projected GitHub navigation", async () => {
  const projection = validateWebsiteExecutionWorkspace(v3Fixture(
    v3WorkspaceFixture("REPOSITORY_READY", "COMPLETE"),
  ), expected);
  const view = websiteExecutionView(projection);
  assert.equal(view.links.github, "https://github.com/lws-studio/lws-web-2026-0042");
  assert.equal(Object.hasOwn(view.links, "vscode"), false);
  for (const repository_navigation_url of [
    "https://example.com/lws-studio/lws-web-2026-0042",
    "https://github.com/other/repository",
    "https://user:pass@github.com/lws-studio/lws-web-2026-0042",
    "https://github.com/lws-studio/lws-web-2026-0042?token=secret",
    "https://github.com/lws-studio/lws-web-2026-0042#fragment",
    "https://vscode.dev/github/lws-studio/lws-web-2026-0042",
  ]) assert.throws(() => validateWebsiteExecutionWorkspace(v3Fixture(
    v3WorkspaceFixture("REPOSITORY_READY", "COMPLETE", { repository_navigation_url }),
  ), expected), /INVALID_WEBSITE_EXECUTION_(?:URL|RESPONSE)/);

  const source = await read("assets/js/operator-website-execution.mjs");
  assert.doesNotMatch(source, /vscode\.dev|github\.dev/);
  assert.doesNotMatch(source, /`https:\/\/github\.com\/\$\{/);
});
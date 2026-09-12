import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  loadProjectWorkspace,
  projectSummaryMarkup,
  projectWorkspaceMarkup,
  projectWorkspaceRequest,
  projectWorkspaceSlot,
  projectWorkspaceViewModel,
  projectWorkspaceWithAssignment,
  quoteRequestIdFromProjectWorkspaceSlot,
  startProjectAndReload,
} from "../assets/js/operator-project-workspace.mjs";
import {
  projectChildContext,
  projectChildDetailRequest,
} from "../assets/js/operator-project-workspace-child.mjs";

const quoteRequestId = "a1100000-0000-4000-8000-000000000001";
const projectId = "a1800000-0000-4000-8000-000000000002";
const dossierSource = readFileSync(
  new URL("../assets/js/operator-dossiers.mjs", import.meta.url),
  "utf8",
);
const childSource = readFileSync(
  new URL("../assets/js/operator-project-workspace-child.mjs", import.meta.url),
  "utf8",
);
const registrySource = readFileSync(
  new URL("../assets/js/operator-module-registry.mjs", import.meta.url),
  "utf8",
);
const windowGuardSource = readFileSync(
  new URL("../assets/js/operator-window-guard.mjs", import.meta.url),
  "utf8",
);
const dashboardGuardSource = readFileSync(
  new URL("../assets/js/operator-dashboard-guard.mjs", import.meta.url),
  "utf8",
);
const dashboardCss = readFileSync(
  new URL("../assets/css/operator-dashboard.css", import.meta.url),
  "utf8",
);

function projection(blockReason, overrides = {}) {
  const allowed = blockReason === "READY_TO_START";
  return {
    project: {
      project_id: projectId,
      current_state: "PROJECT_RELEASED",
      revision: 4,
      financial_summary: {
        milestones: [{ milestone: 1, payment_status: "CONFIRMED" }],
      },
      timeline: [{
        event_type: "RELEASE_PROJECT",
        occurred_at: "2026-09-10T08:00:00Z",
      }],
    },
    start_gate: {
      intake_complete: true,
      m1_confirmed: true,
      commercially_released: true,
      project_start_allowed: allowed,
      block_reason: blockReason,
      current_project_state: "PROJECT_RELEASED",
      project_id: projectId,
      quote_request_id: quoteRequestId,
    },
    ...overrides,
  };
}

test("project child slot binds exactly one quote request", () => {
  const slot = projectWorkspaceSlot(quoteRequestId.toUpperCase());
  assert.equal(slot, `project-${quoteRequestId}`);
  assert.equal(quoteRequestIdFromProjectWorkspaceSlot(slot), quoteRequestId);
  assert.equal(quoteRequestIdFromProjectWorkspaceSlot("main"), null);
  assert.throws(() => projectWorkspaceSlot("invalid"), /INVALID_PROJECT_WORKSPACE_SLOT/);
});

test("project child resolves its project from the server-authoritative dossier detail", () => {
  assert.deepEqual(projectChildDetailRequest(projectWorkspaceSlot(quoteRequestId)), {
    action: "get_application_detail",
    quote_request_id: quoteRequestId,
  });
  const context = projectChildContext({
    quote_request_id: quoteRequestId,
    request_kind: "website",
    application_reference: "LWS-AAN-2026-0042",
    project: { project_id: projectId },
  }, quoteRequestId, { customer: { company: "Acme" } });
  assert.deepEqual(context, {
    quoteRequestId,
    projectId,
    dossierReference: "LWS-AAN-2026-0042",
    customerName: "Acme",
  });
  assert.equal(projectChildContext({
    quote_request_id: quoteRequestId,
    request_kind: "website",
    application_reference: "LWS-AAN-2026-0042",
    project: null,
  }, quoteRequestId), null);
  assert.throws(() => projectChildContext({
    quote_request_id: "a1100000-0000-4000-8000-000000000099",
    request_kind: "website",
    application_reference: "LWS-AAN-2026-0042",
    project: { project_id: projectId },
  }, quoteRequestId), /PROJECT_WORKSPACE_BINDING_MISMATCH/);
});

test("workspace request is absent without a linked Website project", () => {
  assert.equal(projectWorkspaceRequest({
    quote_request_id: quoteRequestId,
    request_kind: "website",
    project: null,
  }), null);
  assert.equal(projectWorkspaceViewModel(null).state, "empty");
  assert.equal(projectWorkspaceViewModel(null).message, "Geen project gekoppeld.");
  assert.match(
    dossierSource,
    /view\?\.state === "empty" \? "Nog geen project" : "Project niet beschikbaar"/,
  );
});

test("blocked projections expose deterministic copy and never a start command", () => {
  const cases = [
    ["BLOCKED_INTAKE", "Intake nog niet afgerond"],
    ["BLOCKED_M1_PAYMENT", "Eerste 40% nog niet bevestigd"],
    ["READY_FOR_RELEASE", "Wacht op commerciële vrijgave"],
  ];
  for (const [reason, copy] of cases) {
    const view = projectWorkspaceViewModel(projection(reason));
    assert.equal(view.startAllowed, false);
    assert.equal(view.blockReason, reason);
    assert.equal(view.permissionLabel, "Geblokkeerd");
    assert.equal(view.permissionCopy, copy);
  }
});

test("READY_TO_START is green and exposes the server-authorized start action", () => {
  const view = projectWorkspaceViewModel(projection("READY_TO_START"), {
    assignee_display_name: "Operator Noor",
  });
  assert.equal(view.startAllowed, true);
  assert.equal(view.workStarted, false);
  assert.equal(view.permissionTone, "ready");
  assert.equal(view.permissionLabel, "Groen");
  assert.equal(view.assignee, "Operator Noor");
  assert.equal(view.projectStatusLabel, "Klaar om project te starten");
  assert.equal(view.lastActivityLabel, "Project commercieel vrijgegeven");
  assert.equal(view.completedSteps, 2);
  assert.equal(view.steps[0].state, "done");
  assert.equal(view.steps[1].state, "done");
  assert.equal(view.steps[2].state, "ready");
});

test("STARTED marks step 03 in progress and removes the start action", () => {
  const view = projectWorkspaceViewModel(projection("STARTED", {
    project: {
      ...projection("STARTED").project,
      timeline: [
        ...projection("STARTED").project.timeline,
        {
          event_type: "PROJECT_WORK_STARTED",
          occurred_at: "2026-09-10T09:00:00Z",
        },
      ],
    },
  }));
  assert.equal(view.startAllowed, false);
  assert.equal(view.workStarted, true);
  assert.equal(view.permissionLabel, "Project gestart");
  assert.equal(view.projectStatusLabel, "Website in uitvoering");
  assert.equal(view.steps[2].state, "in_progress");
  assert.equal(view.steps[3].state, "locked");
  assert.equal(view.steps[4].state, "locked");
});

test("assignment refresh updates the child view without changing project authority", () => {
  const view = projectWorkspaceViewModel(projection("STARTED"));
  const assigned = projectWorkspaceWithAssignment(view, {
    assignee_display_name: "Operator Lina",
  });
  assert.equal(assigned.assignee, "Operator Lina");
  assert.equal(assigned.projectId, view.projectId);
  assert.equal(assigned.quoteRequestId, view.quoteRequestId);
  assert.equal(assigned.blockReason, view.blockReason);
});

test("dossier summary is compact and delegates execution to a managed child", () => {
  const markup = projectSummaryMarkup();
  assert.match(markup, /data-project-summary-status/);
  assert.match(markup, /data-project-summary-progress/);
  assert.match(markup, /data-project-summary-payment/);
  assert.match(markup, /data-operator-window-module="dossiers"/);
  assert.match(markup, /Project openen/);
  assert.doesNotMatch(markup, /project-progress/);
  assert.doesNotMatch(markup, /data-project-start/);
});

test("dossier detail mounts only the compact Project summary", () => {
  assert.match(dossierSource, /\$\{projectSummaryMarkup\(\)\}/);
  assert.doesNotMatch(dossierSource, /projectWorkspaceMarkup/);
  assert.doesNotMatch(dossierSource, /data-project-start/);
  assert.match(dossierSource, /projectWorkspaceSlot\(view\.quoteRequestId\)/);
});

test("Project opening and mounting stay inside the existing managed dossiers child", () => {
  assert.match(registrySource, /slotKey[^]*startsWith\("project-"\)/);
  assert.match(registrySource, /operator-project-workspace-child\.mjs/);
  assert.match(windowGuardSource, /slotKey: bootstrap\.slotKey/);
  assert.doesNotMatch(childSource, /window\.open|window\.location\.reload/);
});

test("Project Workspace exposes the server-context Requirements sibling request", () => {
  assert.match(projectWorkspaceMarkup(), /data-project-requirements-open/);
  assert.match(childSource, /requirementsBoardSlot\(currentContext\.quoteRequestId\)/);
  assert.match(childSource, /data-project-requirements-open/);
  assert.match(childSource, /options\.requestOpen\?\.\("dossiers"/);
});

test("Project Workspace loads one validated Requirements summary without changing D1-D5", () => {
  assert.match(childSource, /projectRequirementsRequest\(context\)/);
  assert.match(childSource, /projectRequirementsSummary\(rawRequirements, context\)/);
  assert.match(childSource, /data-project-requirements-summary/);
  assert.match(childSource, /data-project-requirements-progress/);
  assert.match(childSource, /data-project-requirements-open-count/);
  assert.match(childSource, /data-project-requirements-blocked/);
  assert.match(childSource, /data-project-requirements-preview/);
  assert.match(childSource, /requirementsSummary[^]*!view\.workStarted/);
  assert.doesNotMatch(childSource, /items\.filter|items\.reduce|window\.open|location\.reload/);
  assert.doesNotMatch(childSource, /record_preview_ready|start_project_requirement|complete_project_requirement/);
});

test("Project Requirements summary markup is compact and responsive", () => {
  assert.match(projectWorkspaceMarkup(), /data-project-requirements-summary/);
  assert.match(projectWorkspaceMarkup(), /PROJECTVEREISTEN/);
  assert.match(dashboardCss, /\.project-workspace-requirements \{[^}]*min-width:0[^}]*overflow:hidden/);
  assert.match(dashboardCss, /@media \(max-width:540px\)[^{]*\{[^}]*\.project-workspace-requirements__facts \{[^}]*grid-template-columns:1fr/);
});

test("child refresh and mutation reuse existing synchronization primitives", () => {
  assert.match(childSource, /createOperatorAutoRefresh/);
  assert.match(childSource, /action: "get_dossier_assignment"/);
  assert.match(childSource, /options\.onInvalidate\?\.\("dossiers"\)/);
  assert.match(dashboardGuardSource, /moduleKey === "dossiers"[^]*operatorDossiersController\?\.refresh/);
});

test("child workspace has explicit narrow-window stacking contracts", () => {
  const mediumRule = dashboardCss.split("\n").find((line) =>
    line.startsWith("@media (max-width:900px)") &&
    line.includes(".project-child-context")
  );
  const compactRule = dashboardCss.split("\n").find((line) =>
    line.startsWith("@media (max-width:540px)") &&
    line.includes(".project-child-heading")
  );
  assert.match(mediumRule || "", /\.project-child-context \{ grid-template-columns:repeat\(2/);
  assert.match(compactRule || "", /\.project-progress \{ grid-template-columns:1fr/);
  assert.match(dashboardCss, /\.project-child-context dd \{[^}]*overflow-wrap:anywhere/);
});

test("workspace markup contains the complete project surface", () => {
  const markup = projectWorkspaceMarkup();
  assert.match(markup, /data-dossiers-project/);
  assert.match(markup, /Projectstatus/);
  assert.match(markup, /Starttoestemming/);
  assert.match(markup, /Toegewezen operator/);
  assert.match(markup, /Laatste projectactiviteit/);
  assert.match(markup, /01 Intake afgerond/);
  assert.match(markup, /05 Oplevering/);
  assert.match(markup, /data-project-start/);
});

test("successful start reloads the authoritative projection before showing STARTED", async () => {
  const calls = [];
  const gateway = async (request) => {
    calls.push(request);
    if (request.action === "start_project_work") {
      return { event_type: "PROJECT_WORK_STARTED" };
    }
    return projection(calls.length === 1 ? "READY_TO_START" : "STARTED");
  };
  const context = {
    quoteRequestId,
    projectId,
    expectedState: "PROJECT_RELEASED",
    expectedRevision: 4,
  };
  const ready = await loadProjectWorkspace(gateway, context);
  const started = await startProjectAndReload(gateway, context, () =>
    "b1800000-0000-4000-8000-000000000001"
  );
  assert.equal(ready.blockReason, "READY_TO_START");
  assert.equal(started.blockReason, "STARTED");
  assert.deepEqual(calls.map(({ action }) => action), [
    "get_project_workspace",
    "start_project_work",
    "get_project_workspace",
  ]);
});

test("failed start never fabricates optimistic success", async () => {
  const gateway = async (request) => {
    if (request.action === "start_project_work") {
      throw new Error("PROJECT_START_BLOCKED");
    }
    return projection("READY_TO_START");
  };
  await assert.rejects(
    startProjectAndReload(gateway, {
      quoteRequestId,
      projectId,
      expectedState: "PROJECT_RELEASED",
      expectedRevision: 4,
    }, () => "b1800000-0000-4000-8000-000000000002"),
    /PROJECT_START_BLOCKED/,
  );
});

test("unauthorized workspace reads return a denied view without project data", async () => {
  const view = await loadProjectWorkspace(async () => {
    const error = new Error("PROJECT_SCOPE_DENIED");
    error.code = "PROJECT_SCOPE_DENIED";
    throw error;
  }, { quoteRequestId, projectId });
  assert.deepEqual(view, {
    state: "denied",
    message: "Geen toegang tot dit project.",
  });
});

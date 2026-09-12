import {
  createOperatorAutoRefresh,
  createOperatorRefreshGenerationGuard,
} from "./operator-auto-refresh.mjs?v=20260912-dossier-continuity-project-r1";
import {
  createOperatorDossierAuthority,
  dossierReference,
  formatOperatorDate,
} from "./operator-dossiers.mjs";
import {
  loadProjectWorkspace,
  projectProgressReasonLabel,
  projectWorkspaceMarkup,
  projectWorkspaceRequest,
  projectWorkspaceWithAssignment,
  quoteRequestIdFromProjectWorkspaceSlot,
  startProjectAndReload,
} from "./operator-project-workspace.mjs?v=20260912-dossier-continuity-project-r1";
import {
  projectRequirementsRequest,
  projectRequirementsSummary,
  requirementsBoardSlot,
  requirementsInvalidationMatches,
} from "./operator-project-requirements.mjs?v=20260912-dossier-continuity-project-r1";
import { websiteExecutionSlot } from "./operator-website-execution.mjs?v=20260912-dossier-continuity-project-r1";

const PROJECT_CHILD_ROLES = new Set(["owner"]);

export function projectChildDetailRequest(slotKey) {
  const quoteRequestId = quoteRequestIdFromProjectWorkspaceSlot(slotKey);
  if (!quoteRequestId) throw new Error("INVALID_PROJECT_WORKSPACE_SLOT");
  return Object.freeze({
    action: "get_application_detail",
    quote_request_id: quoteRequestId,
  });
}

export function projectChildContext(detail, quoteRequestId, substance = null) {
  if (detail?.request_kind !== "website" ||
    detail?.quote_request_id !== quoteRequestId) {
    throw new Error("PROJECT_WORKSPACE_BINDING_MISMATCH");
  }
  const request = projectWorkspaceRequest(detail);
  if (!request) return null;
  if (request.quote_request_id !== quoteRequestId) {
    throw new Error("PROJECT_WORKSPACE_BINDING_MISMATCH");
  }
  const reference = dossierReference(detail);
  if (!reference) throw new Error("PROJECT_WORKSPACE_DOSSIER_REQUIRED");
  return Object.freeze({
    quoteRequestId,
    projectId: request.project_id,
    dossierReference: reference,
    customerName: String(
      substance?.customer?.company || substance?.customer?.name ||
        detail?.customer?.company || detail?.customer?.name ||
        detail?.customer?.full_name || "Niet beschikbaar",
    ),
  });
}

function childMarkup() {
  return `<header class="project-child-heading">
    <div><p class="eyebrow">Project / Website uitvoering</p><h1 class="module-shell__title">Projectwerkruimte</h1><p>Server-authoritatieve uitvoering van het geselecteerde Website-project.</p></div>
    <button type="button" class="secondary-action" data-project-refresh>Vernieuwen</button>
  </header>
  <dl class="project-child-context" data-project-context hidden>
    <div><dt>Klant</dt><dd data-project-context-field="customer"></dd></div>
    <div><dt>Dossier</dt><dd data-project-context-field="dossier"></dd></div>
    <div><dt>Projectreferentie</dt><dd data-project-context-field="project"></dd></div>
    <div><dt>Toegewezen operator</dt><dd data-project-context-field="assignee"></dd></div>
  </dl>
  ${projectWorkspaceMarkup()}`;
}

function renderChild(workspace, view, context = null, requirementsSummary = null) {
  const panel = workspace.querySelector("[data-dossiers-project]");
  const empty = panel.querySelector("[data-project-empty]");
  const content = panel.querySelector("[data-project-content]");
  const contextPanel = workspace.querySelector("[data-project-context]");
  panel.hidden = false;
  if (view?.state !== "ready") {
    empty.textContent = view?.message || "Project kon niet veilig worden geladen.";
    empty.hidden = false;
    content.hidden = true;
    contextPanel.hidden = true;
    return;
  }
  empty.hidden = true;
  content.hidden = false;
  contextPanel.hidden = false;
  workspace.querySelector('[data-project-context-field="customer"]').textContent =
    context.customerName;
  workspace.querySelector('[data-project-context-field="dossier"]').textContent =
    context.dossierReference;
  workspace.querySelector('[data-project-context-field="project"]').textContent =
    context.projectId;
  workspace.querySelector('[data-project-context-field="assignee"]').textContent =
    view.assignee;
  const badge = panel.querySelector("[data-project-status-badge]");
  badge.textContent = view.currentPhase;
  badge.className = `badge badge--${view.permissionTone}`;
  const permission = panel.querySelector("[data-project-permission]");
  permission.dataset.tone = view.permissionTone;
  panel.querySelector("[data-project-permission-label]").textContent =
    view.permissionLabel;
  panel.querySelector("[data-project-permission-copy]").textContent =
    view.permissionCopy;
  const fields = {
    status: view.projectStatusLabel,
    permission: view.permissionCopy,
    intake: view.intakeStatus,
    m1: view.firstPaymentStatus,
    phase: view.currentPhase,
    assignee: view.assignee,
    activity: view.lastActivity
      ? `${view.lastActivityLabel} · ${formatOperatorDate(view.lastActivity)}`
      : "Niet beschikbaar",
  };
  for (const [field, value] of Object.entries(fields)) {
    panel.querySelector(`[data-project-field="${field}"]`).textContent = value;
  }
  for (const step of view.steps) {
    const stepNode = panel.querySelector(`[data-project-step="${step.number}"]`);
    stepNode.dataset.state = step.status;
    stepNode.querySelector("[data-project-step-reason]").textContent =
      projectProgressReasonLabel(step.reason);
  }
  const start = panel.querySelector("[data-project-start]");
  start.hidden = !view.startAllowed;
  start.disabled = false;
  panel.querySelector("[data-project-website-open]").hidden =
    !view.workStarted;
  panel.querySelector("[data-project-requirements-open]").hidden =
    !view.workStarted;
  const requirementsPanel = panel.querySelector("[data-project-requirements-summary]");
  requirementsPanel.hidden = !view.workStarted || !requirementsSummary;
  if (!requirementsPanel.hidden) {
    const emptyRequirements = requirementsPanel.querySelector("[data-project-requirements-empty]");
    const requirementsContent = requirementsPanel.querySelector("[data-project-requirements-content]");
    if (requirementsSummary.state === "empty") {
      emptyRequirements.textContent = requirementsSummary.message;
      emptyRequirements.hidden = false;
      requirementsContent.hidden = true;
    } else {
      emptyRequirements.hidden = true;
      requirementsContent.hidden = false;
      requirementsPanel.querySelector("[data-project-requirements-progress]").textContent =
        requirementsSummary.progress;
      requirementsPanel.querySelector("[data-project-requirements-completed]").textContent =
        requirementsSummary.completed;
      requirementsPanel.querySelector("[data-project-requirements-open-count]").textContent =
        requirementsSummary.open;
      requirementsPanel.querySelector("[data-project-requirements-blocked]").textContent =
        requirementsSummary.blocked;
      requirementsPanel.querySelector("[data-project-requirements-preview]").textContent =
        `Preview gereed: ${requirementsSummary.readyForPreview ? "JA" : "NEE"}`;
    }
  }
  panel.querySelector("[data-project-message]").textContent = "";
}

export function initializeOperatorProjectWorkspace(root, client, identity, options = {}) {
  if (!root || !client || identity?.status !== "ACTIVE" ||
    !PROJECT_CHILD_ROLES.has(identity?.role)) {
    throw new Error("PROJECT_WORKSPACE_OPERATOR_NOT_AUTHORIZED");
  }
  const detailRequest = projectChildDetailRequest(options.slotKey);
  const workspace = root.querySelector?.("[data-dossiers-workspace]");
  if (!workspace) throw new Error("PROJECT_WORKSPACE_HOST_REQUIRED");
  workspace.className = "module-shell project-child-workspace";
  workspace.innerHTML = childMarkup();
  const authority = createOperatorDossierAuthority(client, {
    onAuthorizationFailure: options.onAuthorizationFailure,
  });
  let disposed = false;
  const refreshGeneration = createOperatorRefreshGenerationGuard();
  let currentContext = null;
  let currentView = null;

  async function refresh({ background = false, invalidationSlotKey } = {}) {
    if (!requirementsInvalidationMatches(invalidationSlotKey, detailRequest.quote_request_id)) {
      return false;
    }
    const selection = refreshGeneration.begin();
    if (selection === null) return false;
    try {
      const [detail, substance] = await Promise.all([
        authority.gateway(detailRequest),
        authority.gateway({
          action: "get_dossier_substance",
          quote_request_id: detailRequest.quote_request_id,
        }),
      ]);
      const context = projectChildContext(
        detail,
        detailRequest.quote_request_id,
        substance,
      );
      if (!context) {
        if (!refreshGeneration.isCurrent(selection)) return false;
        currentContext = null;
        currentView = { state: "empty", message: "Geen project beschikbaar." };
        renderChild(workspace, currentView);
        return true;
      }
      const [view, rawRequirements, assignment] = await Promise.all([
        loadProjectWorkspace(authority.gateway, context),
        authority.gateway(projectRequirementsRequest(context)),
        authority.gateway({
          action: "get_dossier_assignment",
          dossier_reference: context.dossierReference,
        }).catch(() => null),
      ]);
      if (!refreshGeneration.isCurrent(selection)) return false;
      currentContext = context;
      currentView = projectWorkspaceWithAssignment(view, assignment);
      renderChild(
        workspace,
        currentView,
        currentContext,
        projectRequirementsSummary(rawRequirements, context),
      );
      return true;
    } catch {
      if (!refreshGeneration.isCurrent(selection)) return false;
      if (background && currentContext && currentView?.state === "ready") return false;
      currentContext = null;
      currentView = { state: "error", message: "Project kon niet veilig worden geladen." };
      renderChild(workspace, currentView);
      return false;
    }
  }

  async function startProject() {
    if (!currentContext || !currentView?.startAllowed ||
      currentView.projectStatus !== "PROJECT_RELEASED") return false;
    const selection = refreshGeneration.begin();
    if (selection === null) return false;
    const start = workspace.querySelector("[data-project-start]");
    const message = workspace.querySelector("[data-project-message]");
    start.disabled = true;
    message.textContent = "Project wordt gestart.";
    try {
      const view = await startProjectAndReload(authority.gateway, {
        ...currentContext,
        expectedState: currentView.projectStatus,
        expectedRevision: currentView.revision,
      }, () => crypto.randomUUID());
      if (!refreshGeneration.isCurrent(selection)) return false;
      currentView = projectWorkspaceWithAssignment(view, {
        assignee_display_name: currentView.assignee,
      });
      renderChild(workspace, currentView, currentContext);
      options.onInvalidate?.("dossiers");
      return true;
    } catch {
      if (!refreshGeneration.isCurrent(selection)) return false;
      start.disabled = false;
      message.textContent =
        "Project kon niet worden gestart. De serverstatus is niet gewijzigd.";
      return false;
    }
  }

  const click = (event) => {
    const target = event.target.closest?.("button");
    if (target?.hasAttribute("data-project-refresh")) void refresh();
    if (target?.hasAttribute("data-project-start")) void startProject();
    if (target?.hasAttribute("data-project-website-open") && currentContext) {
      options.requestOpen?.("dossiers", websiteExecutionSlot(currentContext.quoteRequestId));
    }
    if (target?.hasAttribute("data-project-requirements-open") && currentContext) {
      options.requestOpen?.("dossiers", requirementsBoardSlot(currentContext.quoteRequestId));
    }
  };
  workspace.addEventListener("click", click);
  const autoRefresh = createOperatorAutoRefresh({
    moduleKey: "dossiers",
    refresh,
    documentTarget: root,
    windowTarget: root.defaultView,
  });
  void refresh();

  return Object.freeze({
    displayName: "Projectwerkruimte",
    refresh,
    dispose() {
      if (disposed) return;
      disposed = true;
      refreshGeneration.dispose();
      autoRefresh.dispose();
      workspace.removeEventListener("click", click);
      authority.dispose();
    },
    setInvalidationPublisher() {},
  });
}
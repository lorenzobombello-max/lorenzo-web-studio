import {
  createOperatorAutoRefresh,
  createOperatorRefreshGenerationGuard,
} from "./operator-auto-refresh.mjs?v=20260912-dossier-continuity-project-r1";
import {
  createOperatorDossierAuthority,
  dossierReference,
} from "./operator-dossiers.mjs?v=20260917-pre-project-workspace-r2";
import {
  quoteRequestIdFromWebsiteExecutionSlot,
  validateWebsiteExecutionWorkspace,
  websiteExecutionProvisionRequest,
  websiteExecutionRequest,
  websiteRequirementsSummary,
  websiteExecutionView,
} from "./operator-website-execution.mjs?v=20260917-pre-project-workspace-r2";
import {
  requirementsInvalidationMatches,
  validateWebsiteRequirementsBoard,
  websiteRequirementsBoardRequest,
} from "./operator-project-requirements.mjs?v=20260912-dossier-continuity-project-r1";
import {
  mountWebsiteProjectFilesTree,
} from "./operator-website-project-files.mjs?v=20260919-project-files-tree-r1";

const WEBSITE_CHILD_ROLES = new Set([
  "owner",
  "admin",
  "operations_manager",
  "operator",
]);
const WEBSITE_PROJECT_FILE_ACTIONS = new Set([
  "list_website_project_directory",
  "read_website_project_file",
]);

async function websiteRequirementsGateway(client, request) {
  if (request?.action !== "get_website_requirements_board") {
    throw new Error("WEBSITE_REQUIREMENTS_ACTION_NOT_ALLOWED");
  }
  const response = await client.functions.invoke("commercial-operator-command", {
    body: request,
  });
  if (response?.error) throw response.error;
  const body = response?.data;
  if (!body || body.ok !== true || !Object.hasOwn(body, "result")) {
    throw new Error(body?.code || "INVALID_WEBSITE_REQUIREMENTS_RESPONSE");
  }
  return body.result;
}

async function websiteProjectFilesGateway(client, request) {
  if (!request || !WEBSITE_PROJECT_FILE_ACTIONS.has(request.action)) {
    throw new Error("WEBSITE_PROJECT_FILES_ACTION_NOT_ALLOWED");
  }
  const response = await client.functions.invoke("commercial-operator-command", {
    body: request,
  });
  if (response?.error) throw response.error;
  const body = response?.data;
  if (!body || body.ok !== true || !Object.hasOwn(body, "result")) {
    throw new Error(body?.code || "INVALID_WEBSITE_PROJECT_FILES_RESPONSE");
  }
  return body.result;
}

export function websiteChildDetailRequest(slotKey) {
  const quoteRequestId = quoteRequestIdFromWebsiteExecutionSlot(slotKey);
  if (!quoteRequestId) throw new Error("INVALID_WEBSITE_EXECUTION_SLOT");
  return Object.freeze({
    action: "get_application_detail",
    quote_request_id: quoteRequestId,
  });
}

export function websiteChildContext(detail, quoteRequestId, substance = null) {
  if (detail?.request_kind !== "website" ||
    detail?.quote_request_id !== quoteRequestId) {
    throw new Error("WEBSITE_WORKSPACE_BINDING_MISMATCH");
  }
  const request = websiteExecutionRequest(detail);
  const work = detail.website_work;
  if (!request || request.quote_request_id !== quoteRequestId) {
    throw new Error("WEBSITE_WORKSPACE_BINDING_MISMATCH");
  }
  const reference = dossierReference(detail);
  if (!reference) throw new Error("WEBSITE_WORKSPACE_DOSSIER_REQUIRED");
  return Object.freeze({
    quoteRequestId,
    projectId: work.project_id,
    conceptId: work.concept_id,
    websiteWorkContextId: work.website_work_context_id,
    websiteWorkRevision: work.revision,
    mode: work.mode,
    dossierReference: reference,
    customerName: String(
      substance?.customer?.company || substance?.customer?.name ||
        detail?.customer?.company || detail?.customer?.name ||
        detail?.customer?.full_name || "Niet beschikbaar",
    ),
  });
}

function childMarkup() {
  return `<section class="website-execution" data-website-execution>
    <header class="project-child-heading website-execution__heading">
      <div><p class="eyebrow">Website / Technische uitvoering</p><h1 class="module-shell__title">Website Execution Workspace</h1><p>Technische projectreferenties, veilig gebonden aan het geselecteerde klantdossier.</p></div>
      <button type="button" class="secondary-action" data-website-action="refresh">Vernieuwen</button>
    </header>
    <p class="empty-state" data-website-empty>Website workspace laden...</p>
    <div data-website-content hidden>
      <dl class="project-child-context website-execution__context">
        <div><dt>Werkfase</dt><dd data-website-mode></dd></div>
        <div><dt>Briefing</dt><dd data-website-briefing></dd></div>
        <div><dt>Vrijgave</dt><dd data-website-release></dd></div>
      </dl>
      <dl class="project-child-context website-execution__context">
        <div><dt>Klant</dt><dd data-website-context="customer"></dd></div>
        <div><dt>Dossier</dt><dd data-website-context="dossier"></dd></div>
        <div data-website-project-context><dt>Projectreferentie</dt><dd data-website-context="project"></dd></div>
        <div><dt>Toegewezen operator</dt><dd data-website-context="assignee"></dd></div>
      </dl>
      <div class="website-execution__development" data-website-development tabindex="-1">
      <section class="website-execution__requirements" data-website-requirements-panel aria-labelledby="websiteRequirementsTitle">
        <div><p class="eyebrow">Projectvereisten</p><h2 id="websiteRequirementsTitle">PROJECTVEREISTEN</h2></div>
        <p class="website-execution__requirements-empty" data-website-requirements-empty hidden></p>
        <div data-website-requirements-content>
          <strong class="website-execution__requirements-progress" data-website-requirements-progress></strong>
          <dl class="website-execution__requirements-facts">
            <div><dt>Afgerond</dt><dd data-website-requirements-completed></dd></div>
            <div><dt>Open</dt><dd data-website-requirements-open></dd></div>
            <div><dt>Geblokkeerd</dt><dd data-website-requirements-blocked></dd></div>
          </dl>
          <p data-website-requirements-preview></p>
        </div>
        <button type="button" class="secondary-action" data-website-action="requirements" disabled aria-disabled="true" title="Beschikbaar in een volgende fase">Takenbord openen</button>
      </section>
      <section class="website-execution__board" aria-labelledby="websiteTechnicalTitle">
        <div class="website-execution__board-heading"><div><p class="eyebrow">Development references</p><h2 id="websiteTechnicalTitle">Technische werkruimte</h2></div><span class="badge badge--active" data-website-build>UNKNOWN</span></div>
        <p class="website-execution__notice" data-website-notice hidden></p>
        <dl class="website-execution__references">
          <div><dt>Repository</dt><dd data-website-field="repository"></dd></div>
          <div><dt>Actieve branch</dt><dd data-website-field="branch"></dd></div>
          <div><dt>Preview</dt><dd data-website-field="preview"></dd></div>
          <div><dt>Productie URL</dt><dd data-website-field="production"></dd></div>
          <div class="website-execution__reference-wide"><dt>Laatste commit</dt><dd data-website-field="commit"></dd></div>
        </dl>
      </section>
      </div>
      <section class="website-project-files" data-website-project-files tabindex="-1" aria-label="Projectbestanden"></section>
      <nav class="website-execution__actions" aria-label="Website werkruimte acties">
        <button type="button" class="primary-action primary-action--compact" data-website-action="provision" hidden>Technische werkruimte starten</button>
        <a class="primary-action primary-action--compact" data-website-link="github" target="_blank" rel="noopener noreferrer">Open GitHub</a>
        <button type="button" class="secondary-action" data-website-action="files">Projectbestanden</button>
        <button type="button" class="secondary-action" data-website-action="back" data-website-project-back>Terug naar Project</button>
      </nav>
      <p class="action-message" data-website-message role="status" aria-live="polite"></p>
    </div>
  </section>`;
}

function renderRequirementsSummary(workspace, summaryState) {
  const empty = workspace.querySelector("[data-website-requirements-empty]");
  const content = workspace.querySelector("[data-website-requirements-content]");
  const panel = workspace.querySelector("[data-website-requirements-panel]");
  panel.dataset.websiteRequirementsState = summaryState.state;
  if (["LOADING", "ERROR"].includes(summaryState.state)) {
    empty.textContent = summaryState.state === "LOADING"
      ? "Websitevereisten laden..."
      : "Websitevereisten konden niet veilig worden geladen.";
    empty.hidden = false;
    content.hidden = true;
    return;
  }
  const summary = summaryState.summary;
  if (["NO_BOARD", "INTAKE_NOT_ELIGIBLE"].includes(summary.state)) {
    empty.textContent = summary.state === "NO_BOARD"
      ? "Nog geen Website Requirements-board beschikbaar."
      : "De intake is nog niet geschikt voor Website Requirements.";
    empty.hidden = false;
    content.hidden = true;
    return;
  }
  empty.hidden = true;
  content.hidden = false;
  workspace.querySelector("[data-website-requirements-progress]").textContent =
    `${String(summary.completed).padStart(2, "0")} / ${String(summary.total).padStart(2, "0")}`;
  workspace.querySelector("[data-website-requirements-completed]").textContent = summary.completed;
  workspace.querySelector("[data-website-requirements-open]").textContent = summary.open;
  workspace.querySelector("[data-website-requirements-blocked]").textContent = summary.blocked;
  workspace.querySelector("[data-website-requirements-preview]").textContent =
    summaryState.state === "STALE"
      ? "Verouderde gegevens: vernieuwen is mislukt."
      : summary.review_required
      ? "Controle vereist na een gewijzigde intake."
      : "Website Requirements zijn actueel.";
}

function setLink(workspace, name, href) {
  const link = workspace.querySelector(`[data-website-link="${name}"]`);
  link.hidden = !href;
  if (href) link.href = href;
  else link.removeAttribute("href");
}

function renderChild(workspace, state) {
  const empty = workspace.querySelector("[data-website-empty]");
  const content = workspace.querySelector("[data-website-content]");
  if (state.state === "denied" || state.state === "error") {
    empty.textContent = state.message;
    empty.hidden = false;
    content.hidden = true;
    return;
  }
  empty.hidden = true;
  content.hidden = false;
  const { context, assignment, requirementsState, view } = state;
  const contextFields = {
    customer: context.customerName,
    dossier: context.dossierReference,
    project: context.projectId || "Niet van toepassing",
    assignee: assignment?.assignee_display_name || "Niet toegewezen",
  };
  for (const [field, value] of Object.entries(contextFields)) {
    workspace.querySelector(`[data-website-context="${field}"]`).textContent = value;
  }
  workspace.querySelector("[data-website-mode]").textContent = view.modeLabel;
  workspace.querySelector("[data-website-briefing]").textContent = view.briefingLabel;
  workspace.querySelector("[data-website-release]").textContent = view.releaseLabel;
  const officialProject = context.mode === "OFFICIAL_PROJECT";
  workspace.querySelector("[data-website-project-context]").hidden = !officialProject;
  workspace.querySelector("[data-website-project-back]").hidden = !officialProject;
  for (const field of ["repository", "branch", "preview", "production", "commit"]) {
    workspace.querySelector(`[data-website-field="${field}"]`).textContent = view[field];
  }
  const notice = workspace.querySelector("[data-website-notice]");
  notice.textContent = view.message;
  notice.hidden = !view.message;
  workspace.querySelector("[data-website-build]").textContent = view.buildResult || "NIET GEKOPPELD";
  renderRequirementsSummary(workspace, requirementsState);
  setLink(workspace, "github", view.links.github);
  workspace.querySelector("[data-website-action=\"provision\"]").hidden = !(
    state.canProvision && context.mode === "PRE_PROJECT" && view.state === "empty"
  );
  workspace.querySelector("[data-website-message]").textContent = "";
}

export function initializeOperatorWebsiteExecution(root, client, identity, options = {}) {
  if (!root || !client || identity?.status !== "ACTIVE" ||
    !WEBSITE_CHILD_ROLES.has(identity?.role)) {
    throw new Error("WEBSITE_WORKSPACE_OPERATOR_NOT_AUTHORIZED");
  }
  const detailRequest = websiteChildDetailRequest(options.slotKey);
  const workspace = root.querySelector?.("[data-dossiers-workspace]");
  if (!workspace) throw new Error("WEBSITE_WORKSPACE_HOST_REQUIRED");
  workspace.className = "module-shell project-child-workspace website-execution-workspace";
  workspace.innerHTML = childMarkup();
  const projectFiles = mountWebsiteProjectFilesTree(
    workspace.querySelector(".website-project-files"),
    {
      gateway: (request) => websiteProjectFilesGateway(client, request),
      requireAal2: typeof options.requireAal2 === "function"
        ? options.requireAal2
        : async () => { throw new Error("OPERATOR_AAL2_REQUIRED"); },
      ownerEligible: identity.role === "owner",
    },
  );
  const authority = createOperatorDossierAuthority(client, {
    onAuthorizationFailure: (code) => {
      projectFiles.clearAuthorityState("authorization_failure");
      options.onAuthorizationFailure?.(code);
    },
  });
  let disposed = false;
  const refreshGeneration = createOperatorRefreshGenerationGuard();
  let currentSnapshot = null;

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
      const context = websiteChildContext(detail, detailRequest.quote_request_id, substance);
      const [rawWorkspace, assignment] = await Promise.all([
        authority.gateway(websiteExecutionRequest(detail)),
        authority.gateway({
          action: "get_dossier_assignment",
          dossier_reference: context.dossierReference,
        }),
      ]);
      const projection = validateWebsiteExecutionWorkspace(rawWorkspace, context);
      if (projection.context_revision !== context.websiteWorkRevision) {
        throw new Error("WEBSITE_WORKSPACE_REVISION_MISMATCH");
      }
      if (!refreshGeneration.isCurrent(selection)) return false;
      const previousRequirementsSummary = currentSnapshot?.requirementsState?.summary || null;
      const nextSnapshot = Object.freeze({
        state: "ready",
        context,
        assignment,
        projection,
        requirementsState: Object.freeze({ state: "LOADING", summary: null }),
        view: websiteExecutionView(projection),
        canProvision: identity.role === "owner",
      });
      currentSnapshot = nextSnapshot;
      projectFiles.updateContext(Object.freeze({
        quoteRequestId: context.quoteRequestId,
        websiteWorkContextId: context.websiteWorkContextId,
        websiteWorkspaceId: projection.workspace?.website_workspace_id || null,
        bindingRevision: projection.workspace?.binding_revision || null,
        projectFilesRead: projection.workspace?.capabilities.project_files_read === true,
        workspaceState: projection.workspace?.workspace_state || null,
        repositoryOperationState:
          projection.workspace?.repository_operation_state || null,
        failureCategory: projection.workspace?.repository_failure_category || null,
        recoveryGuidance: projection.workspace?.repository_recovery_guidance || null,
      }));
      renderChild(workspace, currentSnapshot);
      try {
        const requirementsContext = Object.freeze({
          quoteRequestId: context.quoteRequestId,
          websiteWorkContextId: context.websiteWorkContextId,
        });
        const rawRequirements = await websiteRequirementsGateway(
          client,
          websiteRequirementsBoardRequest(requirementsContext),
        );
        const requirements = validateWebsiteRequirementsBoard(
          rawRequirements,
          requirementsContext,
        );
        if (!refreshGeneration.isCurrent(selection)) return false;
        const summary = websiteRequirementsSummary(requirements);
        currentSnapshot = Object.freeze({
          ...currentSnapshot,
          requirementsState: Object.freeze({
            state: summary.state,
            summary,
          }),
        });
      } catch {
        if (!refreshGeneration.isCurrent(selection)) return false;
        currentSnapshot = Object.freeze({
          ...currentSnapshot,
          requirementsState: previousRequirementsSummary
            ? Object.freeze({ state: "STALE", summary: previousRequirementsSummary })
            : Object.freeze({ state: "ERROR", summary: null }),
        });
      }
      renderRequirementsSummary(workspace, currentSnapshot.requirementsState);
      return true;
    } catch (error) {
      if (!refreshGeneration.isCurrent(selection)) return false;
      const denied = /DENIED|NOT_AUTHORIZED|NO_ACCESS|42501/.test(
        String(error?.context?.code || error?.code || error?.message || ""),
      );
      if (denied) {
        currentSnapshot = null;
        projectFiles.updateContext(null);
        renderChild(workspace, {
          state: "denied",
          message: "Geen toegang tot deze Website Workspace.",
        });
        return false;
      }
      if (currentSnapshot) {
        projectFiles.markUnavailable();
        workspace.querySelector("[data-website-message]").textContent = background
          ? "De achtergrondvernieuwing kon niet veilig worden geladen."
          : "Website workspace kon niet veilig worden vernieuwd.";
        return false;
      }
      renderChild(workspace, {
        state: "error",
        message: "Website workspace kon niet veilig worden geladen.",
      });
      projectFiles.updateContext(null);
      return false;
    }
  }

  async function provision(button) {
    if (disposed || identity.role !== "owner"
      || currentSnapshot?.context.mode !== "PRE_PROJECT"
      || currentSnapshot?.projection.workspace !== null
      || typeof options.requireAal2 !== "function") return false;
    const confirmed = root.defaultView?.confirm(
      "Technische werkruimte starten? Dit maakt alleen een interne werkruimte aan. Er ontstaat geen bestelling, factuur, betaling, publicatierecht of externe repository.",
    );
    if (!confirmed) return false;
    button.disabled = true;
    const message = workspace.querySelector("[data-website-message]");
    try {
      await options.requireAal2();
      await authority.gateway(websiteExecutionProvisionRequest({
        quoteRequestId: currentSnapshot.context.quoteRequestId,
        idempotencyKey: crypto.randomUUID(),
      }));
      const refreshed = await refresh();
      if (!refreshed || disposed) return false;
      options.onInvalidate?.("dossiers");
      message.textContent = "Technische werkruimte is gestart.";
      return true;
    } catch {
      if (!disposed) {
        button.disabled = false;
        message.textContent = "Technische werkruimte kon niet veilig worden gestart.";
      }
      return false;
    }
  }

  const click = (event) => {
    const target = event.target.closest?.("[data-website-action]");
    const action = target?.dataset.websiteAction;
    if (action === "refresh") void refresh();
    if (action === "provision") void provision(target);
    if (action === "files") void projectFiles.activate();
    if (action === "back" && currentSnapshot?.context.mode === "OFFICIAL_PROJECT") {
      options.requestOpen?.("dossiers", `project-${currentSnapshot.context.quoteRequestId}`);
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
    displayName: "Website Execution Workspace",
    refresh,
    dispose() {
      if (disposed) return;
      disposed = true;
      refreshGeneration.dispose();
      autoRefresh.dispose();
      workspace.removeEventListener("click", click);
      projectFiles.dispose();
      authority.dispose();
      currentSnapshot = null;
      workspace.replaceChildren();
    },
    setInvalidationPublisher() {},
  });
}
import {
  createOperatorAutoRefresh,
  createOperatorRefreshGenerationGuard,
} from "./operator-auto-refresh.mjs?v=20260912-dossier-continuity-project-r1";
import {
  createOperatorDossierAuthority,
  dossierReference,
} from "./operator-dossiers.mjs";
import {
  quoteRequestIdFromWebsiteExecutionSlot,
  validateWebsiteExecutionWorkspace,
  websiteExecutionRequest,
  websiteRequirementsSummary,
  websiteExecutionView,
} from "./operator-website-execution.mjs?v=20260912-website-concept-pre-project-v1";
import {
  projectRequirementsRequest,
  requirementsBoardSlot,
  requirementsInvalidationMatches,
} from "./operator-project-requirements.mjs?v=20260912-dossier-continuity-project-r1";

const WEBSITE_CHILD_ROLES = new Set([
  "owner",
  "admin",
  "operations_manager",
  "operator",
]);

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
      <section class="website-execution__requirements" aria-labelledby="websiteRequirementsTitle">
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
        <button type="button" class="secondary-action" data-website-action="requirements" data-website-requirements-open>Takenbord openen</button>
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
      <nav class="website-execution__actions" aria-label="Website werkruimte acties">
        <a class="primary-action primary-action--compact" data-website-link="github" target="_blank" rel="noopener noreferrer">Open GitHub</a>
        <a class="secondary-action" data-website-link="preview" target="_blank" rel="noopener noreferrer">Open Preview</a>
        <a class="secondary-action" data-website-link="vscode" target="_blank" rel="noopener noreferrer">Open in VS Code Web</a>
        <button type="button" class="secondary-action" data-website-action="files">Projectbestanden</button>
        <button type="button" class="secondary-action" data-website-action="back" data-website-project-back>Terug naar Project</button>
      </nav>
      <p class="action-message" data-website-message role="status" aria-live="polite"></p>
    </div>
  </section>`;
}

function renderRequirementsSummary(workspace, summary) {
  const empty = workspace.querySelector("[data-website-requirements-empty]");
  const content = workspace.querySelector("[data-website-requirements-content]");
  if (summary.state === "empty") {
    empty.textContent = summary.message;
    empty.hidden = false;
    content.hidden = true;
    return;
  }
  empty.hidden = true;
  content.hidden = false;
  workspace.querySelector("[data-website-requirements-progress]").textContent = summary.progress;
  workspace.querySelector("[data-website-requirements-completed]").textContent = summary.completed;
  workspace.querySelector("[data-website-requirements-open]").textContent = summary.open;
  workspace.querySelector("[data-website-requirements-blocked]").textContent = summary.blocked;
  workspace.querySelector("[data-website-requirements-preview]").textContent =
    `Preview gereed: ${summary.readyForPreview ? "JA" : "NEE"}`;
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
  const { context, assignment, summary, view } = state;
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
  workspace.querySelector("[data-website-requirements-open]").hidden = !officialProject;
  workspace.querySelector("[data-website-project-back]").hidden = !officialProject;
  for (const field of ["repository", "branch", "preview", "production", "commit"]) {
    workspace.querySelector(`[data-website-field="${field}"]`).textContent = view[field];
  }
  const notice = workspace.querySelector("[data-website-notice]");
  notice.textContent = view.message;
  notice.hidden = !view.message;
  workspace.querySelector("[data-website-build]").textContent = view.buildResult || "NIET GEKOPPELD";
  renderRequirementsSummary(workspace, summary);
  setLink(workspace, "github", view.links.github);
  setLink(workspace, "preview", view.links.preview);
  setLink(workspace, "vscode", view.links.vscode);
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
  const authority = createOperatorDossierAuthority(client, {
    onAuthorizationFailure: options.onAuthorizationFailure,
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
      const summary = projection.mode === "OFFICIAL_PROJECT"
        ? websiteRequirementsSummary(
          await authority.gateway(projectRequirementsRequest(context)),
          context,
        )
        : websiteRequirementsSummary(projection.requirements, context);
      if (!refreshGeneration.isCurrent(selection)) return false;
      const nextSnapshot = Object.freeze({
        state: "ready",
        context,
        assignment,
        summary,
        view: websiteExecutionView(projection),
      });
      currentSnapshot = nextSnapshot;
      renderChild(workspace, currentSnapshot);
      return true;
    } catch (error) {
      if (!refreshGeneration.isCurrent(selection)) return false;
      const denied = /DENIED|NOT_AUTHORIZED|NO_ACCESS|42501/.test(
        String(error?.context?.code || error?.code || error?.message || ""),
      );
      if (denied) {
        currentSnapshot = null;
        renderChild(workspace, {
          state: "denied",
          message: "Geen toegang tot deze Website Workspace.",
        });
        return false;
      }
      if (currentSnapshot) {
        workspace.querySelector("[data-website-message]").textContent = background
          ? "De achtergrondvernieuwing kon niet veilig worden geladen."
          : "Website workspace kon niet veilig worden vernieuwd.";
        return false;
      }
      renderChild(workspace, {
        state: "error",
        message: "Website workspace kon niet veilig worden geladen.",
      });
      return false;
    }
  }

  const click = (event) => {
    const action = event.target.closest?.("[data-website-action]")?.dataset.websiteAction;
    if (action === "refresh") void refresh();
    if (action === "files") options.requestOpen?.("dossiers", "main");
    if (action === "requirements" && currentSnapshot?.context.mode === "OFFICIAL_PROJECT") {
      options.requestOpen?.("dossiers", requirementsBoardSlot(currentSnapshot.context.quoteRequestId));
    }
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
      authority.dispose();
      currentSnapshot = null;
      workspace.replaceChildren();
    },
    setInvalidationPublisher() {},
  });
}
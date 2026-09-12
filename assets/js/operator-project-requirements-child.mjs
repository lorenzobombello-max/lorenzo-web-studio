import {
  createOperatorAutoRefresh,
  createOperatorRefreshGenerationGuard,
} from "./operator-auto-refresh.mjs?v=20260912-dossier-continuity-project-r1";
import {
  createOperatorDossierAuthority,
  dossierReference,
} from "./operator-dossiers.mjs";
import {
  buildProjectRequirementAction,
  filterProjectRequirements,
  projectRequirementsRequest,
  projectRequirementsView,
  quoteRequestIdFromRequirementsBoardSlot,
  requirementsInvalidationMatches,
  validateProjectRequirementsBoard,
} from "./operator-project-requirements.mjs?v=20260912-dossier-continuity-project-r1";
import { projectWorkspaceRequest } from "./operator-project-workspace.mjs?v=20260912-dossier-continuity-project-r1";
import { websiteExecutionSlot } from "./operator-website-execution.mjs?v=20260912-dossier-continuity-project-r1";

const FILTERS = Object.freeze([
  ["ALL", "Alle"],
  ["ACTIVE", "Actief"],
  ["OPEN", "Open"],
  ["COMPLETED", "Afgerond"],
]);

export function requirementsChildDetailRequest(slotKey) {
  const quoteRequestId = quoteRequestIdFromRequirementsBoardSlot(slotKey);
  if (!quoteRequestId) throw new Error("INVALID_REQUIREMENTS_BOARD_SLOT");
  return Object.freeze({
    action: "get_application_detail",
    quote_request_id: quoteRequestId,
  });
}

export function requirementsChildContext(
  detail,
  quoteRequestId,
  substance = null,
  expectedProjectId = null,
) {
  if (detail?.request_kind !== "website" || detail?.quote_request_id !== quoteRequestId) {
    throw new Error("PROJECT_REQUIREMENTS_BINDING_MISMATCH");
  }
  const request = projectWorkspaceRequest(detail);
  if (!request || request.quote_request_id !== quoteRequestId ||
    (expectedProjectId && request.project_id !== expectedProjectId)) {
    throw new Error("PROJECT_REQUIREMENTS_BINDING_MISMATCH");
  }
  const reference = dossierReference(detail);
  if (!reference) throw new Error("PROJECT_REQUIREMENTS_DOSSIER_REQUIRED");
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
  const filters = FILTERS.map(([filter, label]) =>
    `<button type="button" class="secondary-action" data-requirements-filter="${filter}">${label}</button>`
  ).join("");
  return `<section class="project-requirements" data-project-requirements>
    <header class="project-child-heading">
      <div><p class="eyebrow">Project / Uitvoeringsvereisten</p><h1 class="module-shell__title">Project Requirements</h1><p>Server-gebonden takenbord voor het geselecteerde Website-project.</p></div>
      <button type="button" class="secondary-action" data-requirements-refresh>Vernieuwen</button>
    </header>
    <p class="empty-state" data-requirements-empty>Projectvereisten laden...</p>
    <div data-requirements-content hidden>
      <dl class="project-child-context">
        <div><dt>Klant</dt><dd data-requirements-context="customer"></dd></div>
        <div><dt>Dossier</dt><dd data-requirements-context="dossier"></dd></div>
        <div><dt>Projectreferentie</dt><dd data-requirements-context="project"></dd></div>
        <div><dt>Toegewezen operator</dt><dd data-requirements-context="operator"></dd></div>
      </dl>
      <div class="project-requirements__progress"><strong data-requirements-progress></strong><span data-requirements-progress-label></span></div>
      <nav class="project-requirements__filters" aria-label="Projectvereisten filter">${filters}</nav>
      <div class="project-requirements__cards" data-requirements-cards></div>
      <nav class="website-execution__actions" aria-label="Projectvereisten acties">
        <button type="button" class="primary-action primary-action--compact" data-requirements-website-open>Website openen</button>
      </nav>
      <p class="action-message" data-requirements-message role="status" aria-live="polite"></p>
    </div>
  </section>`;
}

function appendCard(root, container, card) {
  const article = root.createElement("article");
  article.className = `project-requirements__card project-requirements__card--${card.statusClass}`;
  article.dataset.status = card.status;

  const heading = root.createElement("h2");
  heading.textContent = `${card.number} ${card.title}`;
  const description = root.createElement("p");
  description.textContent = card.description;
  const metadata = root.createElement("p");
  metadata.textContent = `${card.statusLabel} · ${card.category} · ${card.requiredLabel} · ${card.completionMode} · ${card.verificationLabel}`;
  article.append(heading, description, metadata);

  if (card.blockedReason) {
    const reason = root.createElement("p");
    reason.textContent = card.blockedReason;
    article.append(reason);
  }
  for (const permitted of card.actions) {
    const button = root.createElement("button");
    button.type = "button";
    button.className = "secondary-action";
    button.dataset.requirementAction = permitted.action;
    button.dataset.requirementId = card.requirementId;
    button.textContent = permitted.label;
    article.append(button);
  }
  container.append(article);
}

function renderChild(root, workspace, state, activeFilter) {
  const empty = workspace.querySelector("[data-requirements-empty]");
  const content = workspace.querySelector("[data-requirements-content]");
  if (state.state === "denied" || state.state === "error") {
    empty.textContent = state.message;
    empty.hidden = false;
    content.hidden = true;
    workspace.querySelector("[data-requirements-cards]").replaceChildren();
    return;
  }
  if (state.view.state === "empty") {
    empty.textContent = state.view.message;
    empty.hidden = false;
    content.hidden = true;
    workspace.querySelector("[data-requirements-cards]").replaceChildren();
    return;
  }
  empty.hidden = true;
  content.hidden = false;
  for (const [field, value] of Object.entries(state.view.context)) {
    workspace.querySelector(`[data-requirements-context="${field}"]`).textContent = value;
  }
  workspace.querySelector("[data-requirements-progress]").textContent = state.view.progress.value;
  workspace.querySelector("[data-requirements-progress-label]").textContent = state.view.progress.label;
  for (const button of workspace.querySelectorAll("[data-requirements-filter]")) {
    button.setAttribute("aria-pressed", String(button.dataset.requirementsFilter === activeFilter));
  }
  const cards = workspace.querySelector("[data-requirements-cards]");
  cards.replaceChildren();
  const filtered = filterProjectRequirements(state.projection.items, activeFilter);
  const byId = new Map(state.view.cards.map((card) => [card.requirementId, card]));
  for (const requirement of filtered) appendCard(root, cards, byId.get(requirement.requirement_id));
}

function actionDetails(root, action) {
  if (action === "start_project_requirement") return {};
  const label = action === "complete_project_requirement"
    ? "Bevestig de uitgevoerde controle"
    : "Geef een reden";
  const value = root.defaultView?.prompt?.(label);
  if (!value) return null;
  return action === "complete_project_requirement"
    ? { attestation: value }
    : { reason: value };
}

export { requirementsInvalidationMatches };

export async function runProjectRequirementMutation({
  request,
  gateway,
  refresh,
  invalidate,
  isActive = () => true,
}) {
  await gateway(request);
  if (!isActive()) return false;
  await refresh({ background: true });
  if (!isActive()) return false;
  invalidate("dossiers");
  return true;
}

export function initializeOperatorProjectRequirements(root, client, identity, options = {}) {
  if (!root || !client || !identity) {
    throw new Error("PROJECT_REQUIREMENTS_OPERATOR_NOT_AUTHORIZED");
  }
  const detailRequest = requirementsChildDetailRequest(options.slotKey);
  const workspace = root.querySelector?.("[data-dossiers-workspace]");
  if (!workspace) throw new Error("PROJECT_REQUIREMENTS_HOST_REQUIRED");
  workspace.className = "module-shell project-child-workspace project-requirements-workspace";
  workspace.innerHTML = childMarkup();
  const authority = createOperatorDossierAuthority(client, {
    onAuthorizationFailure: options.onAuthorizationFailure,
  });
  let disposed = false;
  const refreshGeneration = createOperatorRefreshGenerationGuard();
  let currentContext = null;
  let currentProjection = null;
  let currentView = null;
  let activeFilter = "ALL";

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
      const context = requirementsChildContext(detail, detailRequest.quote_request_id, substance);
      const rawBoard = await authority.gateway(projectRequirementsRequest(context));
      const projection = validateProjectRequirementsBoard(rawBoard, context);
      if (!refreshGeneration.isCurrent(selection)) return false;
      currentContext = context;
      currentProjection = projection;
      currentView = projectRequirementsView(projection);
      renderChild(root, workspace, { state: "ready", projection, view: currentView }, activeFilter);
      return true;
    } catch (error) {
      if (!refreshGeneration.isCurrent(selection)) return false;
      if (background && currentProjection && currentView) return false;
      currentContext = null;
      currentProjection = null;
      currentView = null;
      const denied = /DENIED|NOT_AUTHORIZED|NO_ACCESS|42501/.test(
        String(error?.context?.code || error?.code || error?.message || ""),
      );
      renderChild(root, workspace, {
        state: denied ? "denied" : "error",
        message: denied
          ? "Geen toegang tot dit project."
          : "Projectcontext kon niet veilig worden gekoppeld.",
      }, activeFilter);
      return false;
    }
  }

  async function runAction(button) {
    if (!currentContext || !currentProjection) return false;
    const requirement = currentProjection.items.find(
      (item) => item.requirement_id === button.dataset.requirementId,
    );
    const details = actionDetails(root, button.dataset.requirementAction);
    if (!requirement || details === null) return false;
    const request = buildProjectRequirementAction(
      currentContext,
      requirement,
      button.dataset.requirementAction,
      crypto.randomUUID(),
      details,
    );
    button.disabled = true;
    try {
      return await runProjectRequirementMutation({
        request,
        gateway: authority.gateway,
        refresh,
        invalidate: (moduleKey) => options.onInvalidate?.(moduleKey),
        isActive: () => !disposed,
      });
    } catch {
      button.disabled = false;
      workspace.querySelector("[data-requirements-message]").textContent =
        "Actie kon niet veilig worden uitgevoerd.";
      return false;
    }
  }

  const click = (event) => {
    const target = event.target.closest?.("button");
    if (target?.hasAttribute("data-requirements-refresh")) void refresh();
    if (target?.hasAttribute("data-requirements-filter") && currentProjection && currentView) {
      activeFilter = target.dataset.requirementsFilter;
      renderChild(root, workspace, {
        state: "ready",
        projection: currentProjection,
        view: currentView,
      }, activeFilter);
    }
    if (target?.hasAttribute("data-requirement-action")) void runAction(target);
    if (target?.hasAttribute("data-requirements-website-open") && currentContext) {
      options.requestOpen?.("dossiers", websiteExecutionSlot(currentContext.quoteRequestId));
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
    displayName: "Project Requirements",
    refresh,
    dispose() {
      if (disposed) return;
      disposed = true;
      refreshGeneration.dispose();
      autoRefresh.dispose();
      workspace.removeEventListener("click", click);
      workspace.querySelector("[data-requirements-cards]")?.replaceChildren();
      authority.dispose();
    },
    setInvalidationPublisher() {},
  });
}
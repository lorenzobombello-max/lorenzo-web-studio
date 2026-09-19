import {
  createOperatorAutoRefresh,
  createOperatorRefreshGenerationGuard,
} from "./operator-auto-refresh.mjs?v=20260917-pre-project-workspace-r2";
import {
  createOperatorDossierAuthority,
  dossierReference,
} from "./operator-dossiers.mjs";
import {
  buildProjectRequirementAction,
  createWebsiteRequirementMutationIntent,
  filterProjectRequirements,
  projectRequirementsInvalidationMatches,
  projectRequirementsRequest,
  projectRequirementsView,
  quoteRequestIdFromProjectRequirementsBoardSlot,
  quoteRequestIdFromRequirementsBoardSlot,
  requirementsInvalidationMatches,
  validateProjectRequirementsBoard,
  validateWebsiteRequirementMutationResult,
  validateWebsiteRequirementsBoard,
  validateWebsiteRequirementsSyncResult,
  websiteRequirementAcceptSourceChangeRequest,
  websiteRequirementBlockRequest,
  websiteRequirementCompleteRequest,
  websiteRequirementKeepExistingSourceRequest,
  websiteRequirementReopenRequest,
  websiteRequirementRetireSourceRequest,
  websiteRequirementStartRequest,
  websiteRequirementsBoardRequest,
  websiteRequirementsSyncRequest,
} from "./operator-project-requirements.mjs?v=20260917-pre-project-workspace-r2";
import { projectWorkspaceRequest } from "./operator-project-workspace.mjs?v=20260917-pre-project-workspace-r2";
import {
  websiteExecutionRequest,
  websiteExecutionSlot,
} from "./operator-website-execution.mjs?v=20260917-pre-project-workspace-r2";

const FILTERS = Object.freeze([
  ["ALL", "Alle"],
  ["ACTIVE", "Actief"],
  ["OPEN", "Open"],
  ["COMPLETED", "Afgerond"],
]);

const WEBSITE_MODE = "WEBSITE";
const COMMERCIAL_PROJECT_MODE = "COMMERCIAL_PROJECT";
const WEBSITE_SYNC_ROLES = new Set(["owner", "operations_manager"]);
const WEBSITE_GATEWAY_ACTIONS = new Set([
  "get_website_requirements_board",
  "sync_website_requirements_from_intake",
  "start_website_requirement",
  "block_website_requirement",
  "complete_website_requirement",
  "reopen_website_requirement",
  "accept_website_requirement_source_change",
  "keep_existing_website_requirement_source",
  "retire_website_requirement_source",
]);
const WEBSITE_ACTIONS = Object.freeze({
  start_website_requirement: Object.freeze({ label: "Start", builder: websiteRequirementStartRequest }),
  block_website_requirement: Object.freeze({ label: "Blokkeren", field: "reason", fieldLabel: "Reden blokkering", builder: websiteRequirementBlockRequest }),
  complete_website_requirement: Object.freeze({ label: "Afronden", field: "attestation", fieldLabel: "Uitvoeringsbevestiging", builder: websiteRequirementCompleteRequest }),
  reopen_website_requirement: Object.freeze({ label: "Heropenen", field: "reason", fieldLabel: "Reden heropening", builder: websiteRequirementReopenRequest }),
  accept_website_requirement_source_change: Object.freeze({ label: "Wijziging aanvaarden", field: "reason", fieldLabel: "Reden wijziging aanvaarden", builder: websiteRequirementAcceptSourceChangeRequest }),
  keep_existing_website_requirement_source: Object.freeze({ label: "Bestaande vereiste behouden", field: "reason", fieldLabel: "Reden bestaande vereiste behouden", builder: websiteRequirementKeepExistingSourceRequest }),
  retire_website_requirement_source: Object.freeze({ label: "Vereiste uitfaseren", field: "reason", fieldLabel: "Reden vereiste uitfaseren", builder: websiteRequirementRetireSourceRequest }),
});

export function requirementsChildMode(slotKey) {
  if (quoteRequestIdFromProjectRequirementsBoardSlot(slotKey)) return COMMERCIAL_PROJECT_MODE;
  if (quoteRequestIdFromRequirementsBoardSlot(slotKey)) return WEBSITE_MODE;
  return null;
}

export function requirementsChildDetailRequest(slotKey) {
  const mode = requirementsChildMode(slotKey);
  const quoteRequestId = mode === COMMERCIAL_PROJECT_MODE
    ? quoteRequestIdFromProjectRequirementsBoardSlot(slotKey)
    : quoteRequestIdFromRequirementsBoardSlot(slotKey);
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
  childMode = COMMERCIAL_PROJECT_MODE,
  expectedProjectId = null,
) {
  if (detail?.request_kind !== "website" || detail?.quote_request_id !== quoteRequestId) {
    throw new Error("PROJECT_REQUIREMENTS_BINDING_MISMATCH");
  }
  if (![WEBSITE_MODE, COMMERCIAL_PROJECT_MODE].includes(childMode)) {
    throw new Error("PROJECT_REQUIREMENTS_BINDING_MISMATCH");
  }
  const work = detail.website_work;
  const websiteRequest = work ? websiteExecutionRequest(detail) : null;
  if (childMode === WEBSITE_MODE &&
    (!work || !websiteRequest || websiteRequest.quote_request_id !== quoteRequestId)) {
    throw new Error("PROJECT_REQUIREMENTS_BINDING_MISMATCH");
  }
  const request = projectWorkspaceRequest(detail);
  if (childMode === COMMERCIAL_PROJECT_MODE &&
    (work?.mode === "PRE_PROJECT" ||
    (!request || request.quote_request_id !== quoteRequestId ||
      (expectedProjectId && request.project_id !== expectedProjectId)))) {
    throw new Error("PROJECT_REQUIREMENTS_BINDING_MISMATCH");
  }
  const reference = dossierReference(detail);
  if (!reference) throw new Error("PROJECT_REQUIREMENTS_DOSSIER_REQUIRED");
  const context = {
    quoteRequestId,
    projectId: request?.project_id || null,
    dossierReference: reference,
    customerName: String(
      substance?.customer?.company || substance?.customer?.name ||
        detail?.customer?.company || detail?.customer?.name ||
        detail?.customer?.full_name || "Niet beschikbaar",
    ),
  };
  if (childMode === COMMERCIAL_PROJECT_MODE) return Object.freeze(context);
  return Object.freeze({
    ...context,
    conceptId: work.concept_id,
    websiteWorkContextId: work.website_work_context_id,
    websiteWorkRevision: work.revision,
    mode: work.mode,
  });
}

function childMarkup(mode) {
  const filters = FILTERS.map(([filter, label]) =>
    `<button type="button" class="secondary-action" data-requirements-filter="${filter}">${label}</button>`
  ).join("");
  const websiteMode = mode === WEBSITE_MODE;
  return `<section class="project-requirements" data-project-requirements>
    <header class="project-child-heading">
      <div><p class="eyebrow">${websiteMode ? "Website / Requirements" : "Project / Uitvoeringsvereisten"}</p><h1 class="module-shell__title" data-requirements-heading tabindex="-1">${websiteMode ? "WEBSITE REQUIREMENTS" : "Project Requirements"}</h1><p>${websiteMode ? "Server-gebonden Website Requirements voor het geselecteerde dossier." : "Server-gebonden takenbord voor het geselecteerde Website-project."}</p></div>
      <button type="button" class="secondary-action" data-requirements-refresh>Vernieuwen</button>
    </header>
    <p class="empty-state" data-requirements-empty>${websiteMode ? "Website Requirements laden..." : "Projectvereisten laden..."}</p>
    <div data-requirements-content hidden>
      <dl class="project-child-context">
        <div><dt>Klant</dt><dd data-requirements-context="customer"></dd></div>
        <div><dt>Dossier</dt><dd data-requirements-context="dossier"></dd></div>
        <div><dt>Projectreferentie</dt><dd data-requirements-context="project"></dd></div>
        <div><dt>Toegewezen operator</dt><dd data-requirements-context="operator"></dd></div>
      </dl>
      <div class="project-requirements__progress"><strong data-requirements-progress></strong><span data-requirements-progress-label></span></div>
      <nav class="project-requirements__filters" aria-label="Projectvereisten filter">${filters}</nav>
      <p class="project-requirements__banner" data-requirements-banner hidden></p>
      <div class="project-requirements__cards" data-requirements-cards></div>
      <nav class="website-execution__actions" aria-label="Projectvereisten acties">
        ${websiteMode ? '<button type="button" class="primary-action primary-action--compact" data-requirements-sync hidden>Intake synchroniseren</button>' : ""}
        <button type="button" class="primary-action primary-action--compact" data-requirements-website-open>Website openen</button>
      </nav>
      <p class="action-message" data-requirements-message role="status" aria-live="polite"></p>
      <div class="project-requirements__retry-actions" data-requirements-retry-actions hidden>
        <button type="button" class="primary-action primary-action--compact" data-requirements-retry>Opnieuw proberen</button>
        <button type="button" class="secondary-action" data-requirements-retry-cancel>Annuleren</button>
      </div>
    </div>
  </section>`;
}

function appendCommercialCard(root, container, card) {
  const article = root.createElement("article");
  article.className = `project-requirements__card project-requirements__card--${card.statusClass}`;
  article.dataset.status = card.status;
  article.dataset.requirementId = card.requirementId;

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

function websiteRootState(projection) {
  if (projection.board === null) return projection.empty_state;
  return projection.board.sync_state === "REVIEW_REQUIRED" ||
      projection.progress.review_pending > 0
    ? "REVIEW_REQUIRED"
    : "READY";
}

function websiteContextView(context, projection) {
  return Object.freeze({
    customer: projection.context.customer,
    dossier: projection.context.dossier_reference,
    project: context.projectId || "Niet van toepassing",
    operator: projection.context.assigned_operator?.display_name || "Niet toegewezen",
  });
}

function websiteSourceReviewCopy(state) {
  if (state === "CHANGE_PENDING") {
    return "Nieuwe intake-informatie wacht op beoordeling.";
  }
  if (state === "REMOVAL_PENDING") {
    return "Deze vereiste komt niet meer voor in de actuele intake en wacht op beoordeling.";
  }
  return state === "RETIRED" ? "Deze vereiste is uitgefaseerd." : "Bron is actueel.";
}

function appendWebsiteCard(root, container, item) {
  const article = root.createElement("article");
  article.className = `project-requirements__card project-requirements__card--${item.status.toLowerCase()}`;
  article.dataset.status = item.status;
  article.dataset.requirementId = item.requirement_id;

  const heading = root.createElement("h2");
  heading.textContent = `${String(item.item_number).padStart(2, "0")} ${item.title}`;
  const description = root.createElement("p");
  description.textContent = item.description;
  const metadata = root.createElement("p");
  metadata.textContent = [
    item.status,
    item.category,
    item.required ? "Verplicht" : "Optioneel",
    item.completion_mode,
    item.verification_result,
    `Revisie ${item.revision}`,
  ].join(" · ");
  const source = root.createElement("p");
  source.textContent = `Bron: ${item.source.source_key} · intake ${item.source.intake_revision}`;
  const sourceReview = root.createElement("p");
  sourceReview.textContent = websiteSourceReviewCopy(item.source_review_state);
  article.append(heading, description, metadata, source, sourceReview);

  if (item.linked_page_or_module) {
    const linked = root.createElement("p");
    linked.textContent = `Pagina/module: ${item.linked_page_or_module}`;
    article.append(linked);
  }
  if (item.blocked_reason) {
    const reason = root.createElement("p");
    reason.textContent = item.blocked_reason;
    article.append(reason);
  }
  const actions = root.createElement("div");
  actions.className = "project-requirements__card-actions";
  for (const action of item.permitted_actions) {
    const definition = WEBSITE_ACTIONS[action];
    const button = root.createElement("button");
    button.type = "button";
    button.className = "secondary-action";
    button.dataset.requirementAction = action;
    button.dataset.requirementId = item.requirement_id;
    button.textContent = definition.label;
    actions.append(button);
  }
  article.append(actions);
  container.append(article);
}

function setContext(workspace, values) {
  for (const [field, value] of Object.entries(values)) {
    workspace.querySelector(`[data-requirements-context="${field}"]`).textContent = value;
  }
}

function renderCommercialChild(root, workspace, state, activeFilter) {
  const empty = workspace.querySelector("[data-requirements-empty]");
  const content = workspace.querySelector("[data-requirements-content]");
  if (state.state === "denied" || state.state === "error") {
    empty.textContent = state.message;
    empty.hidden = false;
    content.hidden = true;
    workspace.querySelector("[data-requirements-cards]").replaceChildren();
    return;
  }
  const progress = workspace.querySelector("[data-requirements-progress]").parentElement;
  const filters = workspace.querySelector("[data-requirements-filter]").parentElement;
  const cards = workspace.querySelector("[data-requirements-cards]");
  if (state.view.state === "empty") {
    empty.textContent = state.view.message;
    empty.hidden = false;
    content.hidden = true;
    workspace.querySelector("[data-requirements-cards]").replaceChildren();
    return;
  }
  empty.hidden = true;
  content.hidden = false;
  progress.hidden = false;
  filters.hidden = false;
  cards.hidden = false;
  setContext(workspace, state.view.context);
  workspace.querySelector("[data-requirements-progress]").textContent = state.view.progress.value;
  workspace.querySelector("[data-requirements-progress-label]").textContent = state.view.progress.label;
  for (const button of workspace.querySelectorAll("[data-requirements-filter]")) {
    button.setAttribute("aria-pressed", String(button.dataset.requirementsFilter === activeFilter));
  }
  cards.replaceChildren();
  const filtered = filterProjectRequirements(state.projection.items, activeFilter);
  const byId = new Map(state.view.cards.map((card) => [card.requirementId, card]));
  for (const requirement of filtered) {
    appendCommercialCard(root, cards, byId.get(requirement.requirement_id));
  }
}

function renderWebsiteChild(root, workspace, state, activeFilter, identity, mutationState) {
  const empty = workspace.querySelector("[data-requirements-empty]");
  const content = workspace.querySelector("[data-requirements-content]");
  const progress = workspace.querySelector("[data-requirements-progress]").parentElement;
  const filters = workspace.querySelector("[data-requirements-filter]").parentElement;
  const cards = workspace.querySelector("[data-requirements-cards]");
  const banner = workspace.querySelector("[data-requirements-banner]");
  const sync = workspace.querySelector("[data-requirements-sync]");
  if (["denied", "ERROR", "LOADING"].includes(state.state) && !state.projection) {
    empty.textContent = state.message || (state.state === "LOADING"
      ? "Website Requirements laden..."
      : "Requirements konden niet veilig worden geladen.");
    empty.hidden = false;
    content.hidden = true;
    cards.replaceChildren();
    return;
  }

  const rootState = state.state;
  const projection = state.projection;
  const hasBoard = projection?.board !== null;
  empty.hidden = !["NO_BOARD", "INTAKE_NOT_ELIGIBLE"].includes(rootState);
  empty.textContent = rootState === "NO_BOARD"
    ? "Nog geen Website Requirements-board beschikbaar."
    : rootState === "INTAKE_NOT_ELIGIBLE"
    ? "Website Requirements zijn nog niet beschikbaar voor deze intake."
    : "";
  content.hidden = false;
  setContext(workspace, websiteContextView(state.context, projection));
  progress.hidden = !hasBoard;
  filters.hidden = !hasBoard;
  cards.hidden = !hasBoard;
  banner.hidden = rootState !== "REVIEW_REQUIRED" && rootState !== "STALE";
  banner.textContent = rootState === "REVIEW_REQUIRED"
    ? "Wijzigingen uit de intake moeten eerst beoordeeld worden."
    : rootState === "STALE"
    ? "Requirements konden niet worden vernieuwd. Laatst geldige gegevens blijven zichtbaar."
    : "";
  sync.hidden = !WEBSITE_SYNC_ROLES.has(identity.role) ||
    !["NO_BOARD", "READY", "REVIEW_REQUIRED", "STALE"].includes(rootState);
  sync.disabled = ["PENDING", "AMBIGUOUS_RETRY"].includes(mutationState);
  if (!hasBoard) {
    cards.replaceChildren();
    return;
  }
  workspace.querySelector("[data-requirements-progress]").textContent =
    `${String(projection.progress.required_completed).padStart(2, "0")} / ${String(projection.progress.required_total).padStart(2, "0")}`;
  workspace.querySelector("[data-requirements-progress-label]").textContent = "VEREISTEN AFGEROND";
  for (const button of workspace.querySelectorAll("[data-requirements-filter]")) {
    button.setAttribute("aria-pressed", String(button.dataset.requirementsFilter === activeFilter));
  }
  cards.replaceChildren();
  const items = activeFilter === "ALL"
    ? projection.items
    : activeFilter === "ACTIVE"
    ? projection.items.filter((item) => item.status === "ACTIVE")
    : activeFilter === "OPEN"
    ? projection.items.filter((item) => ["PENDING", "ACTIVE", "BLOCKED"].includes(item.status))
    : projection.items.filter((item) => item.status === "COMPLETED");
  for (const item of items) appendWebsiteCard(root, cards, item);
  const blocked = ["PENDING", "AMBIGUOUS_RETRY"].includes(mutationState);
  for (const button of workspace.querySelectorAll("[data-requirement-action]")) {
    button.disabled = blocked;
  }
}

function websiteRequirementsGateway(client, request) {
  if (!WEBSITE_GATEWAY_ACTIONS.has(request?.action)) {
    throw new Error("WEBSITE_REQUIREMENTS_ACTION_NOT_ALLOWED");
  }
  return client.functions.invoke("commercial-operator-command", { body: request })
    .then((response) => {
      if (response?.error) throw response.error;
      if (response?.data?.ok !== true || !Object.hasOwn(response.data, "result")) {
        const error = new Error(response?.data?.code || "SERVER_RESPONSE_INVALID");
        error.code = response?.data?.code || "SERVER_RESPONSE_INVALID";
        error.status = response?.data?.status || 500;
        throw error;
      }
      return response.data.result;
    });
}

function websiteMutationError(error) {
  const code = String(error?.context?.code || error?.code || error?.message || "");
  const status = Number(error?.context?.status || error?.status || 0);
  const messages = {
    INVALID_REQUEST: "Aanvraag is ongeldig. Controleer de invoer.",
    OPERATOR_NOT_AUTHORIZED: "Je hebt geen toestemming voor deze actie.",
    NOT_FOUND: "De vereiste is niet meer beschikbaar.",
    CONCURRENT_MODIFICATION: "De gegevens zijn gewijzigd. Het bord wordt vernieuwd.",
    IDEMPOTENCY_CONFLICT: "Deze aanvraag kon niet veilig worden herhaald. Het bord wordt vernieuwd.",
    COMMAND_REJECTED: "Deze actie is niet meer toegestaan. Het bord wordt vernieuwd.",
  };
  if (Object.hasOwn(messages, code)) {
    return Object.freeze({ ambiguous: false, refresh: code.startsWith("CONCURRENT") || code.startsWith("IDEMPOTENCY") || code === "COMMAND_REJECTED", message: messages[code] });
  }
  if (status === 500 || ["INTERNAL_ERROR", "SERVER_RESPONSE_INVALID"].includes(code) || status === 0) {
    return Object.freeze({
      ambiguous: true,
      refresh: false,
      message: "Uitkomst niet bevestigd. Opnieuw proberen gebruikt dezelfde veilige aanvraag.",
    });
  }
  return Object.freeze({
    ambiguous: false,
    refresh: false,
    message: "Aanvraag is ongeldig. Controleer de invoer.",
  });
}

function sameWebsiteBinding(intent, context, slotKey) {
  return intent.slotKey === slotKey && intent.quoteRequestId === context?.quoteRequestId &&
    intent.websiteWorkContextId === context?.websiteWorkContextId;
}

export { projectRequirementsInvalidationMatches, requirementsInvalidationMatches };

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
  const childMode = requirementsChildMode(options.slotKey);
  if (!childMode) throw new Error("INVALID_REQUIREMENTS_BOARD_SLOT");
  const detailRequest = requirementsChildDetailRequest(options.slotKey);
  const workspace = root.querySelector?.("[data-dossiers-workspace]");
  if (!workspace) throw new Error("PROJECT_REQUIREMENTS_HOST_REQUIRED");
  workspace.className = "module-shell project-child-workspace project-requirements-workspace";
  workspace.innerHTML = childMarkup(childMode);
  function clearSensitiveState() {
    currentContext = null;
    currentProjection = null;
    currentView = null;
    pendingWebsiteIntent = null;
    mutationState = "IDLE";
    closeWebsiteForm(false);
    workspace.querySelector("[data-requirements-cards]")?.replaceChildren();
  }
  const authority = createOperatorDossierAuthority(client, {
    onAuthorizationFailure: (code) => {
      clearSensitiveState();
      options.onAuthorizationFailure?.(code);
    },
  });
  let disposed = false;
  const refreshGeneration = createOperatorRefreshGenerationGuard();
  let currentContext = null;
  let currentProjection = null;
  let currentView = null;
  let activeFilter = "ALL";
  let mutationState = "IDLE";
  let pendingWebsiteIntent = null;
  let activeWebsiteForm = null;

  function websiteBinding(context = currentContext) {
    return context
      ? `${options.slotKey}:${context.quoteRequestId}:${context.websiteWorkContextId}`
      : null;
  }

  function setMutationPresentation(state, message = "") {
    mutationState = state;
    const status = workspace.querySelector("[data-requirements-message]");
    const retry = workspace.querySelector("[data-requirements-retry-actions]");
    status.textContent = message;
    retry.hidden = state !== "AMBIGUOUS_RETRY";
    const blocked = ["PENDING", "AMBIGUOUS_RETRY"].includes(state);
    for (const button of workspace.querySelectorAll(
      "[data-requirement-action], [data-requirements-sync]",
    )) button.disabled = blocked;
  }

  function closeWebsiteForm(restoreFocus = true) {
    const formState = activeWebsiteForm;
    activeWebsiteForm = null;
    workspace.querySelector("[data-requirements-form]")?.remove();
    if (restoreFocus) formState?.trigger?.focus();
    if (mutationState === "FORM_OPEN") mutationState = "IDLE";
  }

  function discardWebsiteIntent() {
    pendingWebsiteIntent = null;
    workspace.querySelector("[data-requirements-retry-actions]").hidden = true;
  }

  function renderWebsiteState(state, focusHeading = false) {
    renderWebsiteChild(root, workspace, state, activeFilter, identity, mutationState);
    if (focusHeading) workspace.querySelector("[data-requirements-heading]")?.focus();
  }

  async function refresh({ background = false, invalidationSlotKey } = {}) {
    if (childMode === WEBSITE_MODE &&
      !requirementsInvalidationMatches(invalidationSlotKey, detailRequest.quote_request_id)) {
      return false;
    }
    if (childMode === COMMERCIAL_PROJECT_MODE &&
      !projectRequirementsInvalidationMatches(invalidationSlotKey, detailRequest.quote_request_id)) {
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
      const context = requirementsChildContext(
        detail,
        detailRequest.quote_request_id,
        substance,
        childMode,
      );
      const previousBinding = websiteBinding();
      const nextBinding = childMode === WEBSITE_MODE
        ? `${options.slotKey}:${context.quoteRequestId}:${context.websiteWorkContextId}`
        : null;
      let projection;
      let view;
      if (childMode === WEBSITE_MODE) {
        const rawBoard = await websiteRequirementsGateway(
          client,
          websiteRequirementsBoardRequest({
            quoteRequestId: context.quoteRequestId,
            websiteWorkContextId: context.websiteWorkContextId,
          }),
        );
        projection = validateWebsiteRequirementsBoard(rawBoard, {
          quoteRequestId: context.quoteRequestId,
          websiteWorkContextId: context.websiteWorkContextId,
        });
        view = null;
      } else {
        const rawBoard = await authority.gateway(projectRequirementsRequest(context));
        projection = validateProjectRequirementsBoard(rawBoard, context);
        view = projectRequirementsView(projection);
      }
      if (!refreshGeneration.isCurrent(selection)) return false;
      if (childMode === WEBSITE_MODE && previousBinding && previousBinding !== nextBinding) {
        discardWebsiteIntent();
        closeWebsiteForm(false);
      }
      currentContext = context;
      currentProjection = projection;
      currentView = view;
      if (childMode === WEBSITE_MODE) {
        renderWebsiteState({
          state: websiteRootState(projection),
          context,
          projection,
        }, true);
      } else {
        closeWebsiteForm(false);
        renderCommercialChild(
          root,
          workspace,
          { state: "ready", projection, view: currentView },
          activeFilter,
        );
      }
      return true;
    } catch (error) {
      if (!refreshGeneration.isCurrent(selection)) return false;
      if (background && currentProjection) {
        if (childMode === WEBSITE_MODE) {
          renderWebsiteState({
            state: "STALE",
            context: currentContext,
            projection: currentProjection,
          });
        }
        return false;
      }
      currentContext = null;
      currentProjection = null;
      currentView = null;
      discardWebsiteIntent();
      closeWebsiteForm(false);
      const denied = /DENIED|NOT_AUTHORIZED|NO_ACCESS|42501/.test(
        String(error?.context?.code || error?.code || error?.message || ""),
      );
      const state = {
        state: denied ? "denied" : childMode === WEBSITE_MODE ? "ERROR" : "error",
        message: denied
          ? "Geen toegang tot dit project."
          : childMode === WEBSITE_MODE
          ? "Requirements konden niet veilig worden geladen."
          : "Projectcontext kon niet veilig worden gekoppeld.",
      };
      if (childMode === WEBSITE_MODE) renderWebsiteState(state);
      else renderCommercialChild(root, workspace, state, activeFilter);
      return false;
    }
  }

  async function runCommercialAction(button, details = {}) {
    if (!currentContext || !currentProjection) return false;
    const requirement = currentProjection.items.find(
      (item) => item.requirement_id === button.dataset.requirementId,
    );
    if (!requirement) return false;
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

  function openCommercialForm(button) {
    if (!currentProjection || mutationState === "FORM_OPEN") return false;
    closeWebsiteForm(false);
    const action = button.dataset.requirementAction;
    const field = action === "complete_project_requirement" ? "attestation" : "reason";
    const form = root.createElement("form");
    form.className = "project-requirements__form";
    form.setAttribute("data-requirements-form", "");
    const label = root.createElement("label");
    label.textContent = field === "attestation"
      ? "Bevestig de uitgevoerde controle"
      : "Geef een reden";
    const textarea = root.createElement("textarea");
    textarea.name = field;
    textarea.rows = 4;
    textarea.minLength = 1;
    textarea.maxLength = 500;
    textarea.required = true;
    label.append(textarea);
    const actions = root.createElement("div");
    actions.className = "project-requirements__form-actions";
    const cancel = root.createElement("button");
    cancel.type = "button";
    cancel.className = "secondary-action";
    cancel.dataset.requirementsFormCancel = "";
    cancel.textContent = "Annuleren";
    const submit = root.createElement("button");
    submit.type = "submit";
    submit.className = "primary-action primary-action--compact";
    submit.textContent = button.textContent;
    actions.append(cancel, submit);
    form.append(label, actions);
    button.closest("[data-requirement-id]")?.append(form);
    activeWebsiteForm = Object.freeze({ action, field, trigger: button, form });
    mutationState = "FORM_OPEN";
    textarea.focus();
    return true;
  }

  function submitCommercialForm(form) {
    if (!activeWebsiteForm || activeWebsiteForm.form !== form) return false;
    const value = String(new FormData(form).get(activeWebsiteForm.field) || "").trim();
    if (value.length < 1 || value.length > 500) {
      workspace.querySelector("[data-requirements-message]").textContent =
        "Vul 1 tot en met 500 tekens in.";
      form.querySelector("textarea")?.focus();
      return false;
    }
    const { action, field, trigger } = activeWebsiteForm;
    closeWebsiteForm(false);
    void runCommercialAction(trigger, field === "attestation"
      ? { attestation: value }
      : { reason: value });
    return action.length > 0;
  }

  function openWebsiteForm(button) {
    if (!currentProjection?.board || ["PENDING", "AMBIGUOUS_RETRY"].includes(mutationState)) {
      return false;
    }
    const definition = WEBSITE_ACTIONS[button.dataset.requirementAction];
    if (!definition?.field) return false;
    closeWebsiteForm(false);
    const form = root.createElement("form");
    form.className = "project-requirements__form";
    form.setAttribute("data-requirements-form", "");
    const label = root.createElement("label");
    label.textContent = definition.fieldLabel;
    const textarea = root.createElement("textarea");
    textarea.name = definition.field;
    textarea.rows = 4;
    textarea.minLength = 1;
    textarea.maxLength = 500;
    textarea.required = true;
    label.append(textarea);
    const actions = root.createElement("div");
    actions.className = "project-requirements__form-actions";
    const cancel = root.createElement("button");
    cancel.type = "button";
    cancel.className = "secondary-action";
    cancel.dataset.requirementsFormCancel = "";
    cancel.textContent = "Annuleren";
    const submit = root.createElement("button");
    submit.type = "submit";
    submit.className = "primary-action primary-action--compact";
    submit.textContent = definition.label;
    actions.append(cancel, submit);
    form.append(label, actions);
    button.closest("[data-requirement-id]")?.append(form);
    activeWebsiteForm = Object.freeze({
      action: button.dataset.requirementAction,
      requirementId: button.dataset.requirementId,
      trigger: button,
      form,
    });
    mutationState = "FORM_OPEN";
    textarea.focus();
    return true;
  }

  function createPendingIntent(action, requirement = null, value = null) {
    if (!currentContext || !currentProjection || pendingWebsiteIntent) return null;
    const definition = WEBSITE_ACTIONS[action];
    const common = {
      quoteRequestId: currentContext.quoteRequestId,
      websiteWorkContextId: currentContext.websiteWorkContextId,
    };
    let builder;
    let builderArguments;
    if (action === "sync_website_requirements_from_intake") {
      builder = websiteRequirementsSyncRequest;
      builderArguments = {
        ...common,
        expectedBoardRevision: currentProjection.board?.revision ?? 0,
      };
    } else {
      if (!definition || !requirement || !requirement.permitted_actions.includes(action)) return null;
      builder = definition.builder;
      builderArguments = {
        ...common,
        requirementId: requirement.requirement_id,
        expectedRevision: requirement.revision,
      };
      if (definition.field === "attestation") {
        builderArguments.attestation = { attestation: value };
      } else if (definition.field === "reason") {
        builderArguments.reason = value;
      }
    }
    const intent = createWebsiteRequirementMutationIntent(builder, builderArguments);
    pendingWebsiteIntent = Object.freeze({
      intent,
      action,
      slotKey: options.slotKey,
      quoteRequestId: currentContext.quoteRequestId,
      websiteWorkContextId: currentContext.websiteWorkContextId,
      requirementId: requirement?.requirement_id || null,
    });
    return pendingWebsiteIntent;
  }

  async function executeWebsiteIntent() {
    const pending = pendingWebsiteIntent;
    if (!pending || disposed || !sameWebsiteBinding(pending, currentContext, options.slotKey)) {
      discardWebsiteIntent();
      return false;
    }
    if (typeof options.requireAal2 !== "function") {
      discardWebsiteIntent();
      setMutationPresentation("DEFINITIVE_ERROR", "Je hebt geen toestemming voor deze actie.");
      return false;
    }
    setMutationPresentation("PENDING", "Actie wordt veilig uitgevoerd.");
    try {
      await options.requireAal2();
    } catch {
      discardWebsiteIntent();
      setMutationPresentation("DEFINITIVE_ERROR", "Je hebt geen toestemming voor deze actie.");
      return false;
    }
    if (disposed || pendingWebsiteIntent !== pending ||
      !sameWebsiteBinding(pending, currentContext, options.slotKey)) {
      if (pendingWebsiteIntent === pending) discardWebsiteIntent();
      return false;
    }
    try {
      const rawResult = await websiteRequirementsGateway(client, pending.intent.request);
      let result;
      try {
        result = pending.action === "sync_website_requirements_from_intake"
          ? validateWebsiteRequirementsSyncResult(rawResult, {
            quoteRequestId: pending.quoteRequestId,
            websiteWorkContextId: pending.websiteWorkContextId,
          })
          : validateWebsiteRequirementMutationResult(rawResult, {
            quoteRequestId: pending.quoteRequestId,
            websiteWorkContextId: pending.websiteWorkContextId,
            requirementId: pending.requirementId,
            action: pending.action,
          });
      } catch {
        const invalid = new Error("SERVER_RESPONSE_INVALID");
        invalid.code = "SERVER_RESPONSE_INVALID";
        invalid.status = 500;
        throw invalid;
      }
      if (disposed || !sameWebsiteBinding(pending, currentContext, options.slotKey)) {
        discardWebsiteIntent();
        if (result) options.onInvalidate?.("dossiers");
        return false;
      }
      discardWebsiteIntent();
      closeWebsiteForm(false);
      mutationState = "IDLE";
      const refreshed = await refresh({ background: true });
      if (!disposed) {
        options.onInvalidate?.("dossiers");
        setMutationPresentation(
          refreshed ? "IDLE" : "DEFINITIVE_ERROR",
          refreshed ? "Actie uitgevoerd." : "Actie uitgevoerd, maar het bord kon niet veilig worden vernieuwd.",
        );
      }
      return refreshed;
    } catch (error) {
      if (disposed || !sameWebsiteBinding(pending, currentContext, options.slotKey)) {
        discardWebsiteIntent();
        return false;
      }
      const failure = websiteMutationError(error);
      if (failure.ambiguous) {
        setMutationPresentation("AMBIGUOUS_RETRY", failure.message);
        return false;
      }
      discardWebsiteIntent();
      closeWebsiteForm(false);
      mutationState = "DEFINITIVE_ERROR";
      if (failure.refresh) await refresh({ background: true });
      setMutationPresentation("DEFINITIVE_ERROR", failure.message);
      return false;
    }
  }

  function startWebsiteAction(button) {
    if (!currentProjection?.board || pendingWebsiteIntent) return false;
    const requirement = currentProjection.items.find(
      (item) => item.requirement_id === button.dataset.requirementId,
    );
    if (!requirement) return false;
    if (!createPendingIntent(button.dataset.requirementAction, requirement)) return false;
    closeWebsiteForm(false);
    void executeWebsiteIntent();
    return true;
  }

  function submitWebsiteForm(form) {
    if (!activeWebsiteForm || activeWebsiteForm.form !== form || pendingWebsiteIntent) return false;
    const value = String(new FormData(form).get(
      WEBSITE_ACTIONS[activeWebsiteForm.action].field,
    ) || "").trim();
    if (value.length < 1 || value.length > 500) {
      setMutationPresentation("FORM_OPEN", "Vul 1 tot en met 500 tekens in.");
      form.querySelector("textarea")?.focus();
      return false;
    }
    const requirement = currentProjection?.items.find(
      (item) => item.requirement_id === activeWebsiteForm.requirementId,
    );
    if (!requirement || !createPendingIntent(activeWebsiteForm.action, requirement, value)) {
      return false;
    }
    closeWebsiteForm(false);
    void executeWebsiteIntent();
    return true;
  }

  const click = (event) => {
    const target = event.target.closest?.("button");
    if (target?.hasAttribute("data-requirements-refresh")) void refresh();
    if (target?.hasAttribute("data-requirements-filter") && currentProjection) {
      activeFilter = target.dataset.requirementsFilter;
      if (childMode === WEBSITE_MODE) {
        renderWebsiteState({
          state: websiteRootState(currentProjection),
          context: currentContext,
          projection: currentProjection,
        });
      } else if (currentView) {
        closeWebsiteForm(false);
        renderCommercialChild(root, workspace, {
          state: "ready", projection: currentProjection, view: currentView,
        }, activeFilter);
      }
    }
    if (target?.hasAttribute("data-requirement-action")) {
      if (childMode === COMMERCIAL_PROJECT_MODE &&
        target.dataset.requirementAction === "start_project_requirement") {
        void runCommercialAction(target);
      } else if (childMode === COMMERCIAL_PROJECT_MODE) openCommercialForm(target);
      else if (WEBSITE_ACTIONS[target.dataset.requirementAction]?.field) openWebsiteForm(target);
      else startWebsiteAction(target);
    }
    if (target?.hasAttribute("data-requirements-form-cancel")) closeWebsiteForm();
    if (target?.hasAttribute("data-requirements-sync") && childMode === WEBSITE_MODE &&
      WEBSITE_SYNC_ROLES.has(identity.role) && !pendingWebsiteIntent) {
      if (createPendingIntent("sync_website_requirements_from_intake")) {
        void executeWebsiteIntent();
      }
    }
    if (target?.hasAttribute("data-requirements-retry") &&
      mutationState === "AMBIGUOUS_RETRY") void executeWebsiteIntent();
    if (target?.hasAttribute("data-requirements-retry-cancel")) {
      discardWebsiteIntent();
      setMutationPresentation("IDLE");
    }
    if (target?.hasAttribute("data-requirements-website-open") && currentContext) {
      options.requestOpen?.("dossiers", websiteExecutionSlot(currentContext.quoteRequestId));
    }
  };
  const submit = (event) => {
    if (!event.target.matches?.("[data-requirements-form]")) return;
    event.preventDefault();
    if (childMode === COMMERCIAL_PROJECT_MODE) submitCommercialForm(event.target);
    else submitWebsiteForm(event.target);
  };
  const keydown = (event) => {
    if (event.key === "Escape" && mutationState === "FORM_OPEN") {
      event.preventDefault();
      closeWebsiteForm();
    }
  };
  workspace.addEventListener("click", click);
  workspace.addEventListener("submit", submit);
  workspace.addEventListener("keydown", keydown);
  const autoRefresh = createOperatorAutoRefresh({
    moduleKey: "dossiers",
    refresh,
    documentTarget: root,
    windowTarget: root.defaultView,
  });
  void refresh();

  return Object.freeze({
    displayName: childMode === WEBSITE_MODE ? "Website Requirements" : "Project Requirements",
    refresh,
    dispose() {
      if (disposed) return;
      disposed = true;
      refreshGeneration.dispose();
      autoRefresh.dispose();
      workspace.removeEventListener("click", click);
      workspace.removeEventListener("submit", submit);
      workspace.removeEventListener("keydown", keydown);
      clearSensitiveState();
      workspace.replaceChildren();
      authority.dispose();
    },
    setInvalidationPublisher() {},
  });
}
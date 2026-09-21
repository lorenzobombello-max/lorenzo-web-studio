import {
  createOperatorAutoRefresh,
  createOperatorRefreshGenerationGuard,
} from "./operator-auto-refresh.mjs?v=20260912-dossier-continuity-project-r1";
import {
  createOperatorDossierAuthority,
  dossierReference,
} from "./operator-dossiers.mjs?v=20260917-pre-project-workspace-r2";
import {
  createWebsiteConceptPromotionIntent,
  quoteRequestIdFromWebsiteExecutionSlot,
  validateWebsiteConceptPromotionResult,
  validateWebsiteExecutionWorkspace,
  validateWebsiteRepositoryProvisionResult,
  validateWebsiteRepositoryRecoveryResult,
  websiteExecutionProvisionRequest,
  websiteRepositoryProvisionRequest,
  websiteRepositoryRecoveryRequest,
  websiteExecutionRequest,
  websiteRequirementsSummary,
  websiteExecutionView,
} from "./operator-website-execution.mjs?v=20260917-pre-project-workspace-r2";
import {
  requirementsBoardSlot,
  requirementsInvalidationMatches,
  validateWebsiteRequirementsBoard,
  validateWebsiteRequirementsSyncResult,
  websiteRequirementsBoardRequest,
  websiteRequirementsSyncRequest,
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
  "save_website_project_file",
]);

function websiteProjectPreviewRequest(quoteRequestId, expectedCommitSha) {
  if (!quoteRequestId || !/^[0-9a-f]{40}$/i.test(expectedCommitSha || "")) {
    throw new Error("INVALID_WEBSITE_PROJECT_PREVIEW_REQUEST");
  }
  return Object.freeze({
    action: "build_website_project_preview",
    quote_request_id: quoteRequestId,
    expected_commit_sha: expectedCommitSha,
    idempotency_key: crypto.randomUUID(),
  });
}

async function websiteProjectPreviewGateway(client, request) {
  if (request?.action !== "build_website_project_preview") {
    throw new Error("WEBSITE_PROJECT_PREVIEW_ACTION_NOT_ALLOWED");
  }
  const response = await client.functions.invoke("commercial-operator-command", {
    body: request,
  });
  if (response?.error) throw response.error;
  const result = response?.data?.result;
  if (!result || result.contract_version !== 1
    || result.snapshot?.commit_sha !== request.expected_commit_sha
    || result.build?.status !== "PASS"
    || typeof result.preview?.signed_url !== "string"
    || !result.preview.signed_url.startsWith("https://")) {
    throw new Error("INVALID_WEBSITE_PROJECT_PREVIEW_RESPONSE");
  }
  return Object.freeze(structuredClone(result));
}

async function websiteRequirementsGateway(client, request) {
  if (!["get_website_requirements_board", "sync_website_requirements_from_intake"]
    .includes(request?.action)) {
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

async function websiteConceptPromotionGateway(client, request) {
  if (request?.action !== "promote_website_concept") {
    throw new Error("WEBSITE_CONCEPT_PROMOTION_ACTION_NOT_ALLOWED");
  }
  const response = await client.functions.invoke("commercial-operator-command", {
    body: request,
  });
  if (response?.error) {
    let code = "NETWORK_ERROR";
    const status = Number(response.error?.context?.status || 0);
    try {
      const payload = await response.error.context.clone().json();
      if (typeof payload?.code === "string") code = payload.code;
    } catch {}
    throw Object.assign(new Error(code), { code, status });
  }
  const body = response?.data;
  if (!body || body.ok !== true || !Object.hasOwn(body, "result")) {
    throw new Error(body?.code || "SERVER_RESPONSE_INVALID");
  }
  return body.result;
}

export async function websiteProjectFilesGateway(client, request) {
  if (!request || !WEBSITE_PROJECT_FILE_ACTIONS.has(request.action)) {
    throw new Error("WEBSITE_PROJECT_FILES_ACTION_NOT_ALLOWED");
  }
  const response = await client.functions.invoke("commercial-operator-command", {
    body: request,
  });
  if (response?.error) {
    let code = "NETWORK_ERROR";
    const status = Number(response.error?.context?.status || 0);
    try {
      const payload = await response.error.context.clone().json();
      if ([
        "GITHUB_PROVIDER_DISABLED",
        "PROJECT_FILES_PROVIDER_UNAVAILABLE",
      ].includes(payload?.code)) code = payload.code;
    } catch {}
    throw Object.assign(new Error(code), { code, status });
  }
  const body = response?.data;
  if (!body || body.ok !== true || !Object.hasOwn(body, "result")) {
    throw new Error(body?.code || "INVALID_WEBSITE_PROJECT_FILES_RESPONSE");
  }
  return body.result;
}

export async function websiteRepositoryRecoveryGateway(client, request) {
  if (request?.action !== "recover_existing_website_repository") {
    throw new Error("WEBSITE_REPOSITORY_RECOVERY_ACTION_NOT_ALLOWED");
  }
  const response = await client.functions.invoke("commercial-operator-command", {
    body: request,
  });
  if (response?.error) {
    let code = "NETWORK_ERROR";
    const status = Number(response.error?.context?.status || 0);
    try {
      const payload = await response.error.context.clone().json();
      if (typeof payload?.code === "string") code = payload.code;
    } catch {}
    throw Object.assign(new Error(code), { code, status });
  }
  const body = response?.data;
  if (!body || body.ok !== true || !Object.hasOwn(body, "result")) {
    throw new Error(body?.code || "INVALID_WEBSITE_REPOSITORY_RECOVERY_RESPONSE");
  }
  return body.result;
}

// Only a bare machine-readable identifier (e.g. "GITHUB_TOKEN_EXCHANGE_FAILED") is ever
// surfaced to the operator UI. Any other error shape (raw messages, provider payloads,
// stack traces) is reduced to "UNKNOWN" so no diagnostic/secret detail can leak.
const SAFE_RECOVERY_ERROR_CODE = /^[A-Z][A-Z0-9_]*$/;
function safeWebsiteRepositoryRecoveryErrorCode(error) {
  const candidate = typeof error?.code === "string" ? error.code
    : typeof error?.message === "string" ? error.message
    : "";
  return SAFE_RECOVERY_ERROR_CODE.test(candidate) ? candidate : "UNKNOWN";
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
        <button type="button" class="secondary-action" data-website-action="requirements">Requirements openen</button>
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
        <button type="button" class="secondary-action" data-website-action="repository-retry" hidden>Technische werkruimte opnieuw proberen</button>
        <button type="button" class="secondary-action" data-website-action="repository-recovery" hidden>Bestaande technische werkruimte herstellen</button>
        <button type="button" class="primary-action primary-action--compact" data-website-action="promote" hidden>Naar officieel project</button>
        <button type="button" class="secondary-action" data-website-action="promotion-retry" hidden>Opnieuw proberen</button>
        <a class="primary-action primary-action--compact" data-website-link="github" target="_blank" rel="noopener noreferrer">Open GitHub</a>
        <button type="button" class="secondary-action" data-website-action="files">Projectbestanden</button>
        <button type="button" class="secondary-action" data-website-action="preview-build">Preview bouwen / vernieuwen</button>
        <a class="primary-action primary-action--compact" data-website-preview-open target="_blank" rel="noopener noreferrer" hidden>Preview openen</a>
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

function repositoryRetryEligible(identity, context, workspaceProjection, pending = false) {
  return !pending
    && identity.role === "owner"
    && context?.mode === "PRE_PROJECT"
    && workspaceProjection?.workspace_state === "REPOSITORY_FAILED"
    && workspaceProjection.repository_operation_state === "TERMINAL_FAILED"
    && workspaceProjection.repository_failure_category === "TERMINAL"
    && workspaceProjection.repository_recovery_guidance === "CONTACT_OWNER"
    && workspaceProjection.capabilities.repository_recovery_required !== true
    && workspaceProjection.capabilities.repository_retry_allowed !== false
    && workspaceProjection.project_id === null
    && workspaceProjection.repository_owner === null
    && workspaceProjection.repository_name === null
    && workspaceProjection.repository_navigation_url === null
    && workspaceProjection.capabilities.project_files_read === false
    && workspaceProjection.capabilities.project_files_write === false;
}

function repositoryRecoveryEligible(identity, context, workspaceProjection, pending = false) {
  return !pending
    && identity.role === "owner"
    && context?.mode === "PRE_PROJECT"
    && workspaceProjection?.workspace_state === "REPOSITORY_FAILED"
    && workspaceProjection.repository_operation_state === "TERMINAL_FAILED"
    && workspaceProjection.project_id === null
    && workspaceProjection.capabilities.repository_retry_allowed === false
    && workspaceProjection.capabilities.repository_recovery_required === true
    && typeof workspaceProjection.repository_recovery_operation_id === "string";
}

function renderChild(workspace, state, background = false) {
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
  const repositoryRetry = workspace.querySelector(
    "[data-website-action=\"repository-retry\"]",
  );
  repositoryRetry.hidden = state.repositoryRetryEligible !== true;
  repositoryRetry.disabled = state.technicalPreparationPending === true;
  const repositoryRecovery = workspace.querySelector(
    "[data-website-action=\"repository-recovery\"]",
  );
  repositoryRecovery.hidden = state.repositoryRecoveryEligible !== true;
  repositoryRecovery.disabled = state.repositoryRecoveryPending === true;
  const promote = workspace.querySelector("[data-website-action=\"promote\"]");
  promote.hidden = !(state.canPromote && context.mode === "PRE_PROJECT");
  promote.disabled = state.promotionPending === true;
  const retry = workspace.querySelector("[data-website-action=\"promotion-retry\"]");
  retry.hidden = state.promotionRetry !== true;
  retry.disabled = state.promotionPending === true;
  // A background auto-refresh (interval/focus/visibilitychange) must not erase
  // a just-shown recovery status message before the operator can read it. Any
  // foreground render (a new explicit action, the initial load, etc.) clears
  // it as before.
  const message = workspace.querySelector("[data-website-message]");
  const stickyRecoveryMessage = workspace.__recoveryStatusMessage;
  if (background && stickyRecoveryMessage) {
    message.textContent = stickyRecoveryMessage.text;
    message.classList.toggle("action-message--dark", stickyRecoveryMessage.dark === true);
  } else {
    message.textContent = "";
    message.classList.remove("action-message--dark");
    workspace.__recoveryStatusMessage = null;
  }
}

function setRecoveryStatusMessage(workspace, text, { dark = false } = {}) {
  const message = workspace.querySelector("[data-website-message]");
  message.textContent = text;
  message.classList.toggle("action-message--dark", dark);
  workspace.__recoveryStatusMessage = text ? { text, dark } : null;
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
  let promotionIntent = null;
  let promotionPending = false;
  let previewPending = false;
  let technicalPreparationPending = false;
  let repositoryProvisionIntent = null;
  let repositoryRetryAuthorityEligible = false;
  let repositoryRecoveryPending = false;
  let repositoryRecoveryAuthorityEligible = false;

  async function buildPreview() {
    const commitSha = projectFiles.currentCommitSha()
      || currentSnapshot?.projection.workspace?.last_commit_sha;
    if (disposed || previewPending || identity.role !== "owner" || !commitSha
      || typeof options.requireAal2 !== "function") return false;
    previewPending = true;
    const button = workspace.querySelector('[data-website-action="preview-build"]');
    const open = workspace.querySelector("[data-website-preview-open]");
    const message = workspace.querySelector("[data-website-message]");
    button.disabled = true;
    message.textContent = "Preview wordt gebouwd.";
    try {
      await options.requireAal2();
      const result = await websiteProjectPreviewGateway(client,
        websiteProjectPreviewRequest(
          currentSnapshot.context.quoteRequestId,
          commitSha,
        ));
      open.href = result.preview.signed_url;
      open.hidden = false;
      message.textContent = "Preview is gereed voor de opgeslagen commit.";
      return true;
    } catch {
      open.hidden = true;
      open.removeAttribute("href");
      message.textContent = "Preview kon niet veilig worden gebouwd.";
      return false;
    } finally {
      previewPending = false;
      button.disabled = false;
    }
  }

  function promotionIntentMatches(intent) {
    return !disposed && currentSnapshot?.context.mode === "PRE_PROJECT"
      && currentSnapshot.context.quoteRequestId === intent.quoteRequestId
      && currentSnapshot.context.websiteWorkContextId === intent.websiteWorkContextId
      && currentSnapshot.context.websiteWorkRevision === intent.expectedContextRevision;
  }

  function setPromotionControls({ retry = false } = {}) {
    const promote = workspace.querySelector("[data-website-action=\"promote\"]");
    const retryButton = workspace.querySelector("[data-website-action=\"promotion-retry\"]");
    if (!promote || !retryButton) return;
    promote.disabled = promotionPending;
    retryButton.hidden = !retry;
    retryButton.disabled = promotionPending;
  }

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
      repositoryRetryAuthorityEligible = repositoryRetryEligible(
        identity,
        context,
        projection.workspace,
      );
      repositoryRecoveryAuthorityEligible = repositoryRecoveryEligible(
        identity,
        context,
        projection.workspace,
      );
      const nextSnapshot = Object.freeze({
        state: "ready",
        context,
        assignment,
        projection,
        requirementsState: Object.freeze({ state: "LOADING", summary: null }),
        view: websiteExecutionView(projection),
        canProvision: identity.role === "owner",
        canPromote: identity.role === "owner",
        promotionPending,
        promotionRetry: promotionIntent !== null,
        repositoryRetryEligible:
          repositoryRetryAuthorityEligible && !technicalPreparationPending,
        technicalPreparationPending,
        repositoryRecoveryEligible:
          repositoryRecoveryAuthorityEligible && !repositoryRecoveryPending,
        repositoryRecoveryPending,
      });
      currentSnapshot = nextSnapshot;
      if (promotionIntent && !promotionIntentMatches(promotionIntent)) {
        promotionIntent = null;
      }
      projectFiles.updateContext(Object.freeze({
        quoteRequestId: context.quoteRequestId,
        websiteWorkContextId: context.websiteWorkContextId,
        websiteWorkspaceId: projection.workspace?.website_workspace_id || null,
        bindingRevision: projection.workspace?.binding_revision || null,
        projectFilesRead: projection.workspace?.capabilities.project_files_read === true,
        projectFilesWrite:
          projection.workspace?.capabilities.project_files_write === true,
        workspaceState: projection.workspace?.workspace_state || null,
        repositoryOperationState:
          projection.workspace?.repository_operation_state || null,
        failureCategory: projection.workspace?.repository_failure_category || null,
        recoveryGuidance: projection.workspace?.repository_recovery_guidance || null,
      }));
      renderChild(workspace, currentSnapshot, background);
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
      if (projection.workspace?.workspace_state !== "PENDING_REPOSITORY") {
        repositoryProvisionIntent = null;
      }
      if (
        identity.role === "owner" && context.mode === "PRE_PROJECT" &&
        projection.workspace?.workspace_state === "PENDING_REPOSITORY" &&
        !technicalPreparationPending
      ) {
        repositoryProvisionIntent ||= websiteRepositoryProvisionRequest({
          quoteRequestId: context.quoteRequestId,
          websiteWorkContextId: context.websiteWorkContextId,
          websiteWorkspaceId: projection.workspace.website_workspace_id,
          idempotencyKey: crypto.randomUUID(),
        });
        queueMicrotask(() => void prepareTechnicalWorkspace());
      }
      return true;
    } catch (error) {
      if (!refreshGeneration.isCurrent(selection)) return false;
      repositoryRetryAuthorityEligible = false;
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
      return await prepareTechnicalWorkspace();
    } catch {
      if (!disposed) {
        button.disabled = false;
        message.textContent = "Technische werkruimte kon niet veilig worden gestart.";
      }
      return false;
    }
  }

  async function prepareTechnicalWorkspace() {
    if (disposed || technicalPreparationPending || identity.role !== "owner"
      || currentSnapshot?.context.mode !== "PRE_PROJECT"
      || currentSnapshot?.projection.workspace?.workspace_state !== "PENDING_REPOSITORY"
      || typeof options.requireAal2 !== "function") return false;
    const context = currentSnapshot.context;
    const workspaceProjection = currentSnapshot.projection.workspace;
    repositoryProvisionIntent ||= websiteRepositoryProvisionRequest({
      quoteRequestId: context.quoteRequestId,
      websiteWorkContextId: context.websiteWorkContextId,
      websiteWorkspaceId: workspaceProjection.website_workspace_id,
      idempotencyKey: crypto.randomUUID(),
    });
    const request = repositoryProvisionIntent;
    technicalPreparationPending = true;
    const message = workspace.querySelector("[data-website-message]");
    message.textContent = "Technische werkruimte wordt voorbereid.";
    try {
      await options.requireAal2();
      const rawResult = await authority.gateway(request);
      validateWebsiteRepositoryProvisionResult(rawResult, {
        websiteWorkContextId: context.websiteWorkContextId,
      });
      repositoryProvisionIntent = null;
      if (!await refresh() || disposed) return false;
      let requirementsSynchronized = true;
      if (currentSnapshot?.requirementsState.state === "NO_BOARD") {
        try {
          const syncRequest = websiteRequirementsSyncRequest({
            quoteRequestId: context.quoteRequestId,
            websiteWorkContextId: context.websiteWorkContextId,
            expectedBoardRevision: 0,
            idempotencyKey: crypto.randomUUID(),
          });
          const rawSync = await websiteRequirementsGateway(client, syncRequest);
          validateWebsiteRequirementsSyncResult(rawSync, {
            quoteRequestId: context.quoteRequestId,
            websiteWorkContextId: context.websiteWorkContextId,
          });
          await refresh();
        } catch {
          requirementsSynchronized = false;
          currentSnapshot = Object.freeze({
            ...currentSnapshot,
            requirementsState: Object.freeze({ state: "ERROR", summary: null }),
          });
          renderRequirementsSummary(workspace, currentSnapshot.requirementsState);
        }
      }
      if (!disposed) {
        options.onInvalidate?.("dossiers");
        message.textContent = requirementsSynchronized
          ? "Technische werkruimte is klaar."
          : "Technische werkruimte is klaar. Requirements konden niet worden gesynchroniseerd.";
      }
      return true;
    } catch {
      if (!disposed) {
        message.textContent = "Technische werkruimte kon niet veilig worden voorbereid. Vernieuw om opnieuw te proberen.";
      }
      return false;
    } finally {
      technicalPreparationPending = false;
    }
  }

  async function retryTechnicalWorkspace(button) {
    const context = currentSnapshot?.context;
    const workspaceProjection = currentSnapshot?.projection.workspace;
    if (disposed || technicalPreparationPending
      || !repositoryRetryAuthorityEligible
      || !repositoryRetryEligible(identity, context, workspaceProjection)
      || typeof options.requireAal2 !== "function") return false;
    technicalPreparationPending = true;
    button.disabled = true;
    let authorityRefreshed = false;
    const message = workspace.querySelector("[data-website-message]");
    message.textContent = "Technische werkruimte wordt opnieuw voorbereid.";
    try {
      await options.requireAal2();
      const request = websiteRepositoryProvisionRequest({
        quoteRequestId: context.quoteRequestId,
        websiteWorkContextId: context.websiteWorkContextId,
        websiteWorkspaceId: workspaceProjection.website_workspace_id,
        idempotencyKey: crypto.randomUUID(),
      });
      const rawResult = await authority.gateway(request);
      validateWebsiteRepositoryProvisionResult(rawResult, {
        websiteWorkContextId: context.websiteWorkContextId,
      });
      if (!await refresh() || disposed) return false;
      let requirementsSynchronized = true;
      if (currentSnapshot?.requirementsState.state === "NO_BOARD") {
        try {
          const syncRequest = websiteRequirementsSyncRequest({
            quoteRequestId: context.quoteRequestId,
            websiteWorkContextId: context.websiteWorkContextId,
            expectedBoardRevision: 0,
            idempotencyKey: crypto.randomUUID(),
          });
          const rawSync = await websiteRequirementsGateway(client, syncRequest);
          validateWebsiteRequirementsSyncResult(rawSync, {
            quoteRequestId: context.quoteRequestId,
            websiteWorkContextId: context.websiteWorkContextId,
          });
          await refresh();
        } catch {
          requirementsSynchronized = false;
          currentSnapshot = Object.freeze({
            ...currentSnapshot,
            requirementsState: Object.freeze({ state: "ERROR", summary: null }),
          });
          renderRequirementsSummary(workspace, currentSnapshot.requirementsState);
        }
      }
      if (!disposed) {
        options.onInvalidate?.("dossiers");
        message.textContent = requirementsSynchronized
          ? "Technische werkruimte is klaar."
          : "Technische werkruimte is klaar. Requirements konden niet worden gesynchroniseerd.";
      }
      return true;
    } catch {
      if (!disposed) {
        authorityRefreshed = await refresh();
        if (!disposed) {
          message.textContent = "Technische werkruimte kon niet veilig opnieuw worden voorbereid.";
        }
      }
      return false;
    } finally {
      technicalPreparationPending = false;
      if (!disposed) {
        const retry = workspace.querySelector('[data-website-action="repository-retry"]');
        retry.hidden = !(authorityRefreshed && repositoryRetryAuthorityEligible
          && repositoryRetryEligible(
          identity, currentSnapshot?.context, currentSnapshot?.projection.workspace,
        ));
        retry.disabled = false;
      }
    }
  }

  async function recoverExistingTechnicalWorkspace(button) {
    const context = currentSnapshot?.context;
    const workspaceProjection = currentSnapshot?.projection.workspace;
    if (disposed || repositoryRecoveryPending
      || !repositoryRecoveryAuthorityEligible
      || !repositoryRecoveryEligible(identity, context, workspaceProjection)
      || typeof options.requireAal2 !== "function") return false;
    repositoryRecoveryPending = true;
    button.disabled = true;
    setRecoveryStatusMessage(workspace, "Bestaande technische werkruimte wordt hersteld.", { dark: true });
    try {
      await options.requireAal2();
      const request = websiteRepositoryRecoveryRequest({
        quoteRequestId: context.quoteRequestId,
        websiteWorkContextId: context.websiteWorkContextId,
        websiteWorkspaceId: workspaceProjection.website_workspace_id,
      });
      validateWebsiteRepositoryRecoveryResult(
        await websiteRepositoryRecoveryGateway(client, request),
      );
      if (!await refresh() || disposed) return false;
      options.onInvalidate?.("dossiers");
      setRecoveryStatusMessage(workspace, "Bestaande technische werkruimte is hersteld.", { dark: true });
      return true;
    } catch (error) {
      if (!disposed) {
        await refresh();
        if (!disposed) {
          const code = safeWebsiteRepositoryRecoveryErrorCode(error);
          setRecoveryStatusMessage(
            workspace,
            "Bestaande technische werkruimte kon niet veilig worden hersteld."
              + ` (RECOVERY_ERROR: ${code})`,
            { dark: true },
          );
        }
      }
      return false;
    } finally {
      repositoryRecoveryPending = false;
      if (!disposed) button.disabled = false;
    }
  }

  async function promote({ retry = false } = {}) {
    if (disposed || promotionPending || identity.role !== "owner"
      || currentSnapshot?.context.mode !== "PRE_PROJECT") return false;
    if (typeof options.requireAal2 !== "function") {
      promotionIntent = null;
      workspace.querySelector("[data-website-message]").textContent =
        "Je hebt geen toestemming om deze Website-context te promoveren.";
      return false;
    }
    if (!retry) {
      const confirmed = root.defaultView?.confirm(
        "Website-context promoveren naar het officiële project? De bestaande werkruimte, Website Requirements, historie en verificaties blijven behouden. Dit maakt geen factuur, betaling, publicatie of deployment aan.",
      );
      if (!confirmed) {
        promotionIntent = null;
        return false;
      }
      promotionIntent = createWebsiteConceptPromotionIntent({
        quoteRequestId: currentSnapshot.context.quoteRequestId,
        websiteWorkContextId: currentSnapshot.context.websiteWorkContextId,
        expectedContextRevision: currentSnapshot.context.websiteWorkRevision,
      }, () => root.defaultView.crypto.randomUUID());
    }
    const intent = promotionIntent;
    if (!intent || !promotionIntentMatches(intent)) {
      promotionIntent = null;
      return false;
    }
    promotionPending = true;
    setPromotionControls();
    const message = workspace.querySelector("[data-website-message]");
    message.textContent = "Website-context wordt gekoppeld aan het officiële project.";
    try {
      await options.requireAal2();
      if (!promotionIntentMatches(intent)) {
        promotionIntent = null;
        return false;
      }
      const rawResult = await websiteConceptPromotionGateway(client, intent.request);
      const result = validateWebsiteConceptPromotionResult(rawResult, {
        quoteRequestId: intent.quoteRequestId,
        websiteWorkContextId: intent.websiteWorkContextId,
        expectedContextRevision: intent.expectedContextRevision,
      });
      if (!promotionIntentMatches(intent)) {
        promotionIntent = null;
        return false;
      }
      promotionIntent = null;
      const refreshed = await refresh();
      if (disposed) return false;
      options.onInvalidate?.("dossiers");
      if (!refreshed || currentSnapshot?.context.mode !== "OFFICIAL_PROJECT"
        || currentSnapshot.context.websiteWorkContextId !== result.website_work_context_id) {
        message.textContent = "Promotie uitgevoerd, maar de Website Workspace kon niet veilig worden vernieuwd.";
        return false;
      }
      message.textContent = "Website-context is gekoppeld aan het officiële project.";
      return true;
    } catch (error) {
      if (disposed) return false;
      const code = String(error?.code || error?.message || "");
      const messages = {
        INVALID_REQUEST: "Aanvraag is ongeldig. Vernieuw de Website Workspace en probeer opnieuw.",
        OPERATOR_NOT_AUTHORIZED: "Je hebt geen toestemming om deze Website-context te promoveren.",
        NOT_FOUND: "Het officiële project of de Website-context is niet meer beschikbaar.",
        CONCURRENT_MODIFICATION: "De Website-context is gewijzigd. De werkruimte wordt vernieuwd.",
        IDEMPOTENCY_CONFLICT: "Deze promotieaanvraag kon niet veilig worden herhaald. De werkruimte wordt vernieuwd.",
        COMMAND_REJECTED: "Promotie is niet meer toegestaan. De werkruimte wordt vernieuwd.",
      };
      if (["NETWORK_ERROR", "INTERNAL_ERROR", "SERVER_RESPONSE_INVALID"].includes(code)) {
        message.textContent = "Uitkomst niet bevestigd. Opnieuw proberen gebruikt dezelfde veilige promotieaanvraag.";
        return false;
      }
      promotionIntent = null;
      const shouldRefresh = new Set([
        "NOT_FOUND", "CONCURRENT_MODIFICATION", "IDEMPOTENCY_CONFLICT", "COMMAND_REJECTED",
      ]).has(code);
      if (shouldRefresh) await refresh();
      if (!disposed) message.textContent = messages[code]
        || (/AAL2/.test(code)
          ? "Je hebt geen toestemming om deze Website-context te promoveren."
          : "Promotie kon niet veilig worden uitgevoerd.");
      return false;
    } finally {
      promotionPending = false;
      if (!disposed) setPromotionControls({ retry: promotionIntent !== null });
    }
  }

  const click = (event) => {
    const target = event.target.closest?.("[data-website-action]");
    const action = target?.dataset.websiteAction;
    if (action === "refresh") void refresh();
    if (action === "provision") void provision(target);
    if (action === "repository-retry") void retryTechnicalWorkspace(target);
    if (action === "repository-recovery") {
      void recoverExistingTechnicalWorkspace(target);
    }
    if (action === "promote") void promote();
    if (action === "promotion-retry") void promote({ retry: true });
    if (action === "files") void projectFiles.activate();
    if (action === "preview-build") void buildPreview();
    if (action === "requirements" && currentSnapshot?.context) {
      options.requestOpen?.(
        "dossiers",
        requirementsBoardSlot(currentSnapshot.context.quoteRequestId),
      );
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
      projectFiles.dispose();
      authority.dispose();
      promotionIntent = null;
      promotionPending = false;
      currentSnapshot = null;
      workspace.replaceChildren();
    },
    setInvalidationPublisher() {},
  });
}
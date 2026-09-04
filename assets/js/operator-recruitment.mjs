import { createOperatorAutoRefresh } from "./operator-auto-refresh.mjs?v=20260903-auto-refresh-8s";
import { createOperatorRefreshHeartbeat } from "./operator-refresh-heartbeat.mjs?v=20260903-live-heartbeat";
import { initializeRecruitmentCandidateTests } from "./operator-recruitment-tests.mjs?v=20260904-r1";
import { initializeRecruitmentOpenApplications } from "./operator-recruitment-applications.mjs?v=20260904-open-r1";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const VACANCY_FIELDS = Object.freeze(["title", "department", "location", "employment_type", "summary", "description", "requirements"]);
const VACANCY_KEYS = Object.freeze(["id", ...VACANCY_FIELDS, "slug", "status", "published_at", "closed_at", "created_at", "updated_at"]);
const AUTHORIZATION_CODES = /HUMAN_JWT_REQUIRED|RECRUITMENT_OWNER_REQUIRED|OPERATOR_NOT_AUTHORIZED|WORKSPACE_MODULE_NOT_AUTHORIZED/;

function exactObjectKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every((key)=>Object.hasOwn(value, key));
}

function validTimestamp(value, nullable = false) {
  return (nullable && value === null) || (typeof value === "string" && Number.isFinite(Date.parse(value)));
}

function authorizationFailure(error) {
  return error?.code === "42501" || AUTHORIZATION_CODES.test(String(error?.message || ""));
}

export function recruitmentVacanciesResponse(value) {
  if (!Array.isArray(value)) throw new Error("INVALID_RECRUITMENT_VACANCY_RESPONSE");
  for (const vacancy of value) {
    if (!exactObjectKeys(vacancy, VACANCY_KEYS)
      || !UUID.test(vacancy.id) || !["DRAFT", "PUBLISHED", "CLOSED"].includes(vacancy.status)
      || !VACANCY_FIELDS.every((field)=>typeof vacancy[field] === "string" && vacancy[field].length > 0)
      || typeof vacancy.slug !== "string" || !vacancy.slug
      || !validTimestamp(vacancy.created_at) || !validTimestamp(vacancy.updated_at)
      || !validTimestamp(vacancy.published_at, true) || !validTimestamp(vacancy.closed_at, true)) {
      throw new Error("INVALID_RECRUITMENT_VACANCY_RESPONSE");
    }
  }
  return value;
}

function vacancyContent(input) {
  const content = {};
  for (const field of VACANCY_FIELDS) {
    const value = typeof input?.[field] === "string" ? input[field].trim() : "";
    if (!value) throw new TypeError("INVALID_RECRUITMENT_VACANCY_INPUT");
    content[field] = value;
  }
  return content;
}

export function recruitmentVacancyCreateRequest(input) {
  const slug = typeof input?.slug === "string" ? input.slug.trim() : "";
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) throw new TypeError("INVALID_RECRUITMENT_VACANCY_INPUT");
  return { action: "create_recruitment_vacancy", slug, ...vacancyContent(input) };
}

export function recruitmentVacancyUpdateRequest(vacancyId, input) {
  if (!UUID.test(vacancyId)) throw new TypeError("INVALID_RECRUITMENT_VACANCY_INPUT");
  return { action: "update_recruitment_vacancy", vacancy_id: vacancyId, ...vacancyContent(input) };
}

export function recruitmentVacancyStatusRequest(vacancyId, status) {
  if (!UUID.test(vacancyId) || !["PUBLISHED", "CLOSED"].includes(status)) throw new TypeError("INVALID_RECRUITMENT_VACANCY_INPUT");
  return { action: "set_recruitment_vacancy_status", vacancy_id: vacancyId, status };
}

export function recruitmentPublicationResponse(value) {
  if (!exactObjectKeys(value, ["enabled"]) || typeof value.enabled !== "boolean") {
    throw new TypeError("INVALID_RECRUITMENT_PUBLICATION_RESPONSE");
  }
  return { enabled: value.enabled };
}

export function recruitmentPublicationRequest(enabled) {
  if (typeof enabled !== "boolean") throw new TypeError("INVALID_RECRUITMENT_PUBLICATION_INPUT");
  return { action: "set_recruitment_publication_enabled", enabled };
}

export async function executeOperatorRecruitmentRequest(client, request, { onAuthorizationFailure = ()=>{} } = {}) {
  if (!client?.rpc) throw new TypeError("RECRUITMENT_CLIENT_REQUIRED");
  const content = request.action === "create_recruitment_vacancy" || request.action === "update_recruitment_vacancy"
    ? Object.fromEntries(VACANCY_FIELDS.map((field)=>[`p_${field}`, request[field]])) : {};
  const [name, parameters] = request.action === "get_recruitment_publication_state"
    ? ["get_public_recruitment_publication_state_v1", {}]
    : request.action === "set_recruitment_publication_enabled"
    ? ["set_recruitment_publication_enabled_v1", { p_enabled: request.enabled }]
    : request.action === "list_recruitment_vacancies"
    ? ["list_owner_recruitment_vacancies_v1", {}]
    : request.action === "create_recruitment_vacancy"
    ? ["create_recruitment_vacancy_v1", { p_slug: request.slug, ...content }]
    : request.action === "update_recruitment_vacancy"
    ? ["update_recruitment_vacancy_v1", { p_vacancy_id: request.vacancy_id, ...content }]
    : request.action === "set_recruitment_vacancy_status"
    ? ["set_recruitment_vacancy_status_v1", { p_vacancy_id: request.vacancy_id, p_status: request.status }]
    : [null, null];
  if (!name) throw new TypeError("INVALID_RECRUITMENT_REQUEST");
  const { data, error } = await client.rpc(name, parameters);
  if (error) {
    if (authorizationFailure(error)) onAuthorizationFailure(error);
    throw error;
  }
  return data;
}

function createControllerState({ initialState, readRequest, readResponse, readError, execute, onChange }) {
  let current = initialState;
  let generation = 0;
  let disposed = false;
  const notify = ()=>{ if (!disposed) onChange({ ...current }); };
  async function run(request, response, errorMessage, mode, { background = false } = {}) {
    if (disposed || current.mutating) return false;
    const requestGeneration = ++generation;
    if (!background) {
      current = { ...current, [mode]: true, error: null };
      notify();
    }
    try {
      const value = response(await execute(request));
      if (disposed || requestGeneration !== generation) return false;
      current = { ...current, ...value, [mode]: false };
      notify();
      return true;
    } catch {
      if (disposed || requestGeneration !== generation) return false;
      if (background) return false;
      current = { ...current, [mode]: false, error: errorMessage };
      notify();
      return false;
    }
  }
  return {
    get state() { return { ...current }; },
    refresh: (options)=>run(readRequest, readResponse, readError, "loading", options),
    mutate: (request, response=(value)=>value)=>run(request, response, "De wijziging kon niet worden opgeslagen.", "mutating"),
    dispose() { disposed = true; generation += 1; },
  };
}

export function createRecruitmentPublicationController({ load = null, execute, onChange = ()=>{} }) {
  const run = (request)=>request.action === "get_recruitment_publication_state" && load ? load(request) : execute(request);
  const controller = createControllerState({
    initialState: { enabled: null, loading: false, mutating: false, error: null },
    readRequest: { action: "get_recruitment_publication_state" },
    readResponse: (value)=>recruitmentPublicationResponse(value),
    readError: "Publicatiestatus kon niet worden geladen.",
    execute: run,
    onChange,
  });
  return {
    get state() { return controller.state; },
    refresh: controller.refresh,
    async setEnabled(enabled) {
      const changed = await controller.mutate(recruitmentPublicationRequest(enabled), recruitmentPublicationResponse);
      return changed && controller.state.enabled === enabled;
    },
    dispose: controller.dispose,
  };
}

export function createRecruitmentVacancyController({ load = null, execute, onChange = ()=>{} }) {
  const run = (request)=>request.action === "list_recruitment_vacancies" && load ? load(request) : execute(request);
  let items = [];
  const controller = createControllerState({
    initialState: { items, loading: false, mutating: false, error: null },
    readRequest: { action: "list_recruitment_vacancies" },
    readResponse: (value)=>({ items: recruitmentVacanciesResponse(value) }),
    readError: "Vacatures konden niet worden geladen.",
    execute: run,
    onChange: (state)=>{ items = state.items; onChange({ ...state, items: [...state.items] }); },
  });
  async function mutate(request) {
    const changed = await controller.mutate(request);
    return changed ? controller.refresh() : false;
  }
  return {
    get state() { const state = controller.state; return { ...state, items: [...state.items] }; },
    refresh: controller.refresh,
    create: (input)=>mutate(recruitmentVacancyCreateRequest(input)),
    update: (id, input)=>mutate(recruitmentVacancyUpdateRequest(id, input)),
    setStatus: (id, status)=>mutate(recruitmentVacancyStatusRequest(id, status)),
    dispose: controller.dispose,
  };
}

function recruitmentDate(value) {
  return new Intl.DateTimeFormat("nl-BE", { dateStyle: "medium" }).format(new Date(value));
}

export function initializeOperatorRecruitment(root, client, identity, { onAuthorizationFailure = ()=>{} } = {}) {
  const list = root.getElementById("recruitmentVacancyList");
  if (!list || list.dataset.initialized === "true") return null;
  if (identity?.role !== "owner") throw new Error("RECRUITMENT_OWNER_REQUIRED");
  list.dataset.initialized = "true";
  const listenerController = new AbortController();
  const listen = (target, type, handler)=>target.addEventListener(type, handler, { signal: listenerController.signal });
  const execute = (request)=>executeOperatorRecruitmentRequest(client, request, { onAuthorizationFailure });
  const count = root.getElementById("recruitmentVacancyCount");
  const message = root.getElementById("recruitmentVacancyMessage");
  const empty = root.getElementById("recruitmentVacancyEmpty");
  const workDialog = root.getElementById("recruitmentVacancyDialog");
  const form = root.getElementById("recruitmentVacancyForm");
  const formMessage = root.getElementById("recruitmentVacancyFormMessage");
  const statusDialog = root.getElementById("recruitmentVacancyStatusDialog");
  const statusForm = root.getElementById("recruitmentVacancyStatusForm");
  const publicationBadge = root.getElementById("recruitmentPublicationStatus");
  const publicationAction = root.getElementById("recruitmentPublicationAction");
  const publicationMessage = root.getElementById("recruitmentPublicationMessage");
  const publicationDialog = root.getElementById("recruitmentPublicationDialog");
  const publicationForm = root.getElementById("recruitmentPublicationForm");
  const statusButtons = Array.from(root.querySelectorAll("[data-recruitment-status]"));
  let filter = "ALL";
  let editingId = null;
  let pendingStatus = null;
  let lastTrigger = null;
  let disposed = false;
  let controller;
  let publicationController;
  const labels = { DRAFT: "Concept", PUBLISHED: "Gepubliceerd", CLOSED: "Gesloten" };

  const formContent = ()=>Object.fromEntries([...VACANCY_FIELDS, "slug"].map((field)=>[field, form.elements.namedItem(field).value]));
  function openWorkDialog(vacancy = null, trigger = null) {
    if (disposed) return;
    editingId = vacancy?.id || null;
    lastTrigger = trigger;
    form.reset();
    for (const field of VACANCY_FIELDS) form.elements.namedItem(field).value = vacancy?.[field] || "";
    const slug = form.elements.namedItem("slug");
    slug.value = vacancy?.slug || "";
    slug.readOnly = Boolean(vacancy);
    root.getElementById("recruitmentVacancyDialogTitle").textContent = vacancy ? "Vacature bewerken" : "Nieuwe vacature";
    root.getElementById("recruitmentVacancySave").textContent = vacancy ? "Wijzigingen opslaan" : "Concept aanmaken";
    formMessage.textContent = "";
    workDialog.showModal();
    form.elements.namedItem("title").focus();
  }
  function render(state = controller.state) {
    if (disposed) return;
    const visible = filter === "ALL" ? state.items : state.items.filter((vacancy)=>vacancy.status === filter);
    count.textContent = `${state.items.length} ${state.items.length === 1 ? "vacature" : "vacatures"}`;
    message.textContent = state.error || (state.loading ? "Vacatures laden..." : state.mutating ? "Wijziging opslaan..." : "");
    list.setAttribute("aria-busy", String(state.loading || state.mutating));
    list.replaceChildren();
    for (const vacancy of visible) {
      const item = root.createElement("li");
      const heading = root.createElement("div");
      const title = root.createElement("h2");
      const badge = root.createElement("span");
      const metadata = root.createElement("p");
      const summary = root.createElement("p");
      const updated = root.createElement("p");
      const actions = root.createElement("div");
      item.className = "recruitment-vacancy-item";
      heading.className = "recruitment-vacancy-item__heading";
      title.textContent = vacancy.title;
      badge.className = "badge";
      badge.dataset.vacancyStatus = vacancy.status;
      badge.textContent = labels[vacancy.status];
      metadata.className = "recruitment-vacancy-item__metadata";
      metadata.textContent = `${vacancy.department} / ${vacancy.location} / ${vacancy.employment_type}`;
      summary.textContent = vacancy.summary;
      updated.className = "recruitment-vacancy-item__updated";
      updated.textContent = `Bijgewerkt ${recruitmentDate(vacancy.updated_at)}`;
      actions.className = "recruitment-vacancy-item__actions";
      const edit = root.createElement("button");
      edit.type = "button";
      edit.className = "secondary-action";
      edit.textContent = "Bewerken";
      edit.disabled = state.mutating;
      listen(edit, "click", ()=>openWorkDialog(vacancy, edit));
      actions.append(edit);
      const nextStatus = vacancy.status === "DRAFT" ? "PUBLISHED" : vacancy.status === "PUBLISHED" ? "CLOSED" : null;
      if (nextStatus) {
        const lifecycle = root.createElement("button");
        lifecycle.type = "button";
        lifecycle.className = nextStatus === "CLOSED" ? "danger-action" : "primary-action primary-action--compact";
        lifecycle.textContent = nextStatus === "PUBLISHED" ? "Publiceren" : "Sluiten";
        lifecycle.disabled = state.mutating;
        listen(lifecycle, "click", ()=>{
          pendingStatus = { vacancy, status: nextStatus };
          lastTrigger = lifecycle;
          root.getElementById("recruitmentVacancyStatusTitle").textContent = nextStatus === "PUBLISHED" ? "Vacature publiceren" : "Vacature sluiten";
          root.getElementById("recruitmentVacancyStatusDescription").textContent = nextStatus === "PUBLISHED" ? `Publiceer \"${vacancy.title}\".` : `Sluit \"${vacancy.title}\".`;
          root.getElementById("recruitmentVacancyStatusConfirm").textContent = nextStatus === "PUBLISHED" ? "Publiceren" : "Sluiten";
          statusDialog.showModal();
        });
        actions.append(lifecycle);
      }
      heading.append(title, badge);
      item.append(heading, metadata, summary, updated, actions);
      list.append(item);
    }
    empty.hidden = state.loading || visible.length > 0;
  }
  function renderPublication(state = publicationController.state) {
    if (disposed) return;
    const known = typeof state.enabled === "boolean";
    publicationBadge.textContent = known ? (state.enabled ? "ACTIEF" : "NIET ACTIEF") : "NIET BESCHIKBAAR";
    publicationBadge.dataset.publicationEnabled = known ? String(state.enabled) : "unknown";
    publicationAction.textContent = state.enabled ? "Rekrutering offline zetten" : "Rekrutering publiceren";
    publicationAction.disabled = !known || state.loading || state.mutating;
    publicationAction.setAttribute("aria-busy", String(state.mutating));
    publicationMessage.textContent = state.error || (state.loading ? "Publicatiestatus laden..." : state.mutating ? "Publicatiestatus wijzigen..." : "");
  }

  controller = createRecruitmentVacancyController({ execute, onChange: render });
  publicationController = createRecruitmentPublicationController({ execute, onChange: renderPublication });
  const candidateTests = initializeRecruitmentCandidateTests(root, client, { onAuthorizationFailure });
  const openApplications = initializeRecruitmentOpenApplications(root, client, { onAuthorizationFailure });
  const panel = list.closest?.("[data-module-panel]");
  const heartbeat = createOperatorRefreshHeartbeat({ root, moduleKey: "recruitment", titleElement: root.getElementById("recruitmentModuleTitle") });
  const autoRefresh = createOperatorAutoRefresh({
    moduleKey: "recruitment",
    refresh: async (options)=>(await Promise.all([controller.refresh(options), publicationController.refresh(options), candidateTests?.refresh(), openApplications?.refresh()])).every((result)=>result !== false),
    isActive: ()=>!panel?.hidden,
    isBlocked: ()=>[workDialog, statusDialog, publicationDialog, root.getElementById("recruitmentCandidateDialog"), root.getElementById("recruitmentAssignmentDialog"), root.getElementById("recruitmentReviewDialog"), root.getElementById("recruitmentOpenApplicationDetailDialog"), root.getElementById("recruitmentOpenApplicationProfileDialog")].some((dialog)=>dialog?.open)
      || controller.state.mutating || publicationController.state.mutating,
    documentTarget: root,
    windowTarget: root.defaultView,
    onLifecycle: heartbeat.update,
  });
  listen(publicationAction, "click", ()=>{
    const activating = publicationController.state.enabled === false;
    lastTrigger = publicationAction;
    root.getElementById("recruitmentPublicationDialogTitle").textContent = activating ? "Rekrutering publiceren?" : "Rekrutering offline zetten?";
    root.getElementById("recruitmentPublicationDialogDescription").textContent = activating
      ? "De headerlink, footerlink en recruitmentpagina worden samen zichtbaar."
      : "De headerlink, footerlink en recruitmentpagina worden samen verborgen. Vacatures blijven bewaard.";
    root.getElementById("recruitmentPublicationConfirm").textContent = activating ? "Rekrutering publiceren" : "Offline zetten";
    publicationDialog.showModal();
  });
  listen(root.getElementById("recruitmentPublicationCancel"), "click", ()=>{ if (!publicationController.state.mutating) publicationDialog.close(); });
  listen(publicationDialog, "close", ()=>lastTrigger?.focus());
  listen(publicationForm, "submit", async (event)=>{
    event.preventDefault();
    if (publicationController.state.mutating || typeof publicationController.state.enabled !== "boolean") return;
    if (await publicationController.setEnabled(!publicationController.state.enabled)) publicationDialog.close();
  });
  listen(root.getElementById("recruitmentVacancyCreate"), "click", (event)=>openWorkDialog(null, event.currentTarget));
  listen(root.getElementById("recruitmentVacancyRefresh"), "click", ()=>{ void controller.refresh(); });
  for (const button of statusButtons) listen(button, "click", ()=>{
    filter = button.dataset.recruitmentStatus;
    for (const candidate of statusButtons) candidate.setAttribute("aria-pressed", String(candidate === button));
    render();
  });
  listen(root.getElementById("recruitmentVacancyCancel"), "click", ()=>{ if (!controller.state.mutating) workDialog.close(); });
  listen(workDialog, "close", ()=>lastTrigger?.focus());
  listen(form, "submit", async (event)=>{
    event.preventDefault();
    if (!form.reportValidity() || controller.state.mutating) return;
    const saved = editingId ? await controller.update(editingId, formContent()) : await controller.create(formContent());
    if (disposed) return;
    if (saved) workDialog.close();
    else formMessage.textContent = controller.state.error || "De vacature kon niet worden opgeslagen.";
  });
  listen(root.getElementById("recruitmentVacancyStatusCancel"), "click", ()=>{ if (!controller.state.mutating) statusDialog.close(); });
  listen(statusDialog, "close", ()=>{ pendingStatus = null; lastTrigger?.focus(); });
  listen(statusForm, "submit", async (event)=>{
    event.preventDefault();
    if (!pendingStatus || controller.state.mutating) return;
    if (await controller.setStatus(pendingStatus.vacancy.id, pendingStatus.status)) statusDialog.close();
  });
  render();
  renderPublication();
  void publicationController.refresh();
  void controller.refresh();
  return Object.freeze({
    get state() { return controller.state; },
    refresh: (options)=>Promise.all([controller.refresh(options), publicationController.refresh(options), candidateTests?.refresh(), openApplications?.refresh()]),
    dispose() {
      if (disposed) return;
      disposed = true;
      autoRefresh.dispose();
      heartbeat.dispose();
      listenerController.abort();
      controller.dispose();
      publicationController.dispose();
      candidateTests?.dispose();
      openApplications?.dispose();
      for (const dialog of [workDialog, statusDialog, publicationDialog]) if (dialog.open) dialog.close();
    },
  });
}

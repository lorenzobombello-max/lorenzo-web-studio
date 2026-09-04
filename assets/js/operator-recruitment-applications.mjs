const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PROFILES = new Set(["Webdesign", "Development", "Security", "SEO", "Content"]);
const STATUSES = new Set(["OPEN", "BEWAARD", "AFGEWEZEN", "UITGENODIGD"]);
const APPLICATION_KEYS = ["id", "application_type", "first_name", "last_name", "email", "phone", "motivation", "interest_area", "experience_skills", "portfolio_url", "availability", "cv_storage_path", "workflow_status", "linked_test_profile", "linked_test_candidate_id", "submitted_at", "updated_at"];

function exactKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === keys.length && keys.every((key)=>Object.hasOwn(value, key));
}

export function openApplicationsResponse(value) {
  if (!Array.isArray(value)) throw new Error("INVALID_OPEN_APPLICATION_RESPONSE");
  for (const item of value) {
    if (!exactKeys(item, APPLICATION_KEYS) || !UUID.test(item.id) || item.application_type !== "OPEN_SOLLICITATIE"
      || !STATUSES.has(item.workflow_status) || !["first_name", "last_name", "email", "motivation", "interest_area", "experience_skills", "availability", "cv_storage_path"].every((key)=>typeof item[key] === "string" && item[key].length > 0)
      || (item.linked_test_profile !== null && !PROFILES.has(item.linked_test_profile))
      || (item.linked_test_candidate_id !== null && !UUID.test(item.linked_test_candidate_id))) throw new Error("INVALID_OPEN_APPLICATION_RESPONSE");
  }
  return value;
}

export function updateOpenApplicationRequest(applicationId, workflowStatus, linkedTestProfile = null, linkedTestCandidateId = null) {
  if (!UUID.test(applicationId) || !STATUSES.has(workflowStatus)
    || (linkedTestProfile !== null && !PROFILES.has(linkedTestProfile))
    || (linkedTestCandidateId !== null && !UUID.test(linkedTestCandidateId))) throw new TypeError("INVALID_OPEN_APPLICATION_ACTION");
  return { action: "update_open_application", application_id: applicationId, workflow_status: workflowStatus, linked_test_profile: linkedTestProfile, linked_test_candidate_id: linkedTestCandidateId };
}

export async function executeOpenApplicationRequest(client, request, { onAuthorizationFailure = ()=>{} } = {}) {
  const routes = {
    list_open_applications: ["list_owner_recruitment_open_applications_v1", {}],
    update_open_application: ["update_owner_recruitment_open_application_v1", { p_application_id: request.application_id, p_workflow_status: request.workflow_status, p_linked_test_profile: request.linked_test_profile, p_linked_test_candidate_id: request.linked_test_candidate_id }],
  };
  const route = routes[request?.action];
  if (!route || !client?.rpc) throw new TypeError("INVALID_OPEN_APPLICATION_REQUEST");
  const { data, error } = await client.rpc(route[0], route[1]);
  if (error) {
    if (error.code === "42501") onAuthorizationFailure(error);
    throw error;
  }
  return request.action === "list_open_applications" ? openApplicationsResponse(data) : data;
}

export async function inviteOpenApplicationToTest(client, application, profile, options) {
  if (!PROFILES.has(profile)) throw new TypeError("INVALID_OPEN_APPLICATION_ACTION");
  const { data, error } = await client.functions.invoke("recruitment-candidate-invitation", {
    body: { name: `${application.first_name} ${application.last_name}`, email: application.email, test_profile: profile },
  });
  if (error || data?.ok !== true || !UUID.test(data.candidate_id)) throw error || new Error("RECRUITMENT_INVITATION_FAILED");
  return executeOpenApplicationRequest(client, updateOpenApplicationRequest(application.id, "UITGENODIGD", profile, data.candidate_id), options);
}

function formatDate(value) {
  return new Intl.DateTimeFormat("nl-BE", { dateStyle: "medium" }).format(new Date(value));
}

export function initializeRecruitmentOpenApplications(root, client, { onAuthorizationFailure = ()=>{} } = {}) {
  const list = root.getElementById("recruitmentOpenApplicationList");
  if (!list || list.dataset.initialized === "true") return null;
  list.dataset.initialized = "true";
  const message = root.getElementById("recruitmentOpenApplicationMessage");
  const empty = root.getElementById("recruitmentOpenApplicationEmpty");
  const detailDialog = root.getElementById("recruitmentOpenApplicationDetailDialog");
  const profileDialog = root.getElementById("recruitmentOpenApplicationProfileDialog");
  const profileForm = root.getElementById("recruitmentOpenApplicationProfileForm");
  const listener = new AbortController();
  const listen = (target, type, handler)=>target.addEventListener(type, handler, { signal: listener.signal });
  const execute = (request)=>executeOpenApplicationRequest(client, request, { onAuthorizationFailure });
  let applications = [];
  let selected = null;

  async function update(item, status, profile = item.linked_test_profile) {
    await execute(updateOpenApplicationRequest(item.id, status, profile));
    await refresh();
  }

  function button(label, action, secondary = false) {
    const element = root.createElement("button");
    element.type = "button";
    element.className = secondary ? "secondary-action" : "primary-action primary-action--compact";
    element.textContent = label;
    listen(element, "click", action);
    return element;
  }

  function render() {
    list.replaceChildren();
    for (const item of applications) {
      const card = root.createElement("li");
      card.className = "recruitment-open-application-item";
      const heading = root.createElement("div");
      heading.className = "recruitment-candidate-item__heading";
      const title = root.createElement("h3");
      title.textContent = `${item.first_name} ${item.last_name}`;
      const badge = root.createElement("span");
      badge.className = "badge";
      badge.textContent = item.workflow_status;
      heading.append(title, badge);
      const label = root.createElement("p");
      label.className = "recruitment-open-application-label";
      label.textContent = "OPEN SOLLICITATIE";
      const summary = root.createElement("p");
      summary.textContent = `${item.interest_area} · ${item.email} · ${formatDate(item.submitted_at)}`;
      const actions = root.createElement("div");
      actions.className = "recruitment-open-application-actions";
      actions.append(
        button("Bekijken", ()=>showDetail(item), true),
        button("Bewaren", ()=>void update(item, "BEWAARD"), true),
        button("Afwijzen", ()=>void update(item, "AFGEWEZEN"), true),
        button(item.linked_test_profile ? "Profiel wijzigen" : "Aan profiel koppelen", ()=>{ selected = item; profileForm.elements.namedItem("test_profile").value = item.linked_test_profile || ""; profileDialog.showModal(); }),
      );
      if (item.linked_test_profile && !item.linked_test_candidate_id) actions.append(button("Testpakket verzenden", async ()=>{
        try { await inviteOpenApplicationToTest(client, item, item.linked_test_profile, { onAuthorizationFailure }); await refresh(); message.textContent = "Testpakket verzonden en gekoppeld."; }
        catch { message.textContent = "Testpakket kon niet veilig worden verzonden."; }
      }));
      card.append(heading, label, summary, actions);
      list.append(card);
    }
    empty.hidden = applications.length > 0;
  }

  function showDetail(item) {
    const fields = { Naam: `${item.first_name} ${item.last_name}`, "E-mail": item.email, Telefoon: item.phone || "-", Interessegebied: item.interest_area, Motivatie: item.motivation, Ervaring: item.experience_skills, Beschikbaarheid: item.availability, Portfolio: item.portfolio_url || "-" };
    const detail = root.getElementById("recruitmentOpenApplicationDetail");
    detail.replaceChildren();
    for (const [label, value] of Object.entries(fields)) {
      const row = root.createElement("div"); const term = root.createElement("dt"); const description = root.createElement("dd");
      term.textContent = label; description.textContent = value; row.append(term, description); detail.append(row);
    }
    root.getElementById("recruitmentOpenApplicationCv").onclick = async ()=>{
      const { data, error } = await client.storage.from("recruitment-cvs").createSignedUrl(item.cv_storage_path, 60);
      if (error || !data?.signedUrl) { message.textContent = "CV kon niet veilig worden geopend."; return; }
      root.defaultView.open(data.signedUrl, "_blank", "noopener");
    };
    detailDialog.showModal();
  }

  async function refresh() {
    try { applications = await execute({ action: "list_open_applications" }); render(); message.textContent = ""; return true; }
    catch { message.textContent = "Open sollicitaties konden niet veilig worden geladen."; return false; }
  }

  listen(root.getElementById("recruitmentOpenApplicationRefresh"), "click", ()=>void refresh());
  listen(root.getElementById("recruitmentOpenApplicationDetailClose"), "click", ()=>detailDialog.close());
  listen(root.getElementById("recruitmentOpenApplicationProfileCancel"), "click", ()=>profileDialog.close());
  listen(profileForm, "submit", async (event)=>{
    event.preventDefault();
    if (!selected || !profileForm.reportValidity()) return;
    try { await update(selected, selected.workflow_status, profileForm.elements.namedItem("test_profile").value); profileDialog.close(); message.textContent = "Functieprofiel gekoppeld."; }
    catch { root.getElementById("recruitmentOpenApplicationProfileMessage").textContent = "Profiel kon niet worden gekoppeld."; }
  });
  void refresh();
  return Object.freeze({ refresh, dispose() { listener.abort(); for (const dialog of [detailDialog, profileDialog]) if (dialog.open) dialog.close(); } });
}
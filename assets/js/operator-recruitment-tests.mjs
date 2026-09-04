const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const STATUS_LABELS = Object.freeze({ GEPLAND: "Gepland", BESCHIKBAAR: "Beschikbaar", BEZIG: "Bezig", INGEDIEND: "Ingediend", BEOORDEELD: "Beoordeeld" });
const PROFILES = new Set(["Webdesign", "Development", "Security", "SEO", "Content"]);

function text(value, maximum = 120) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!normalized || normalized.length > maximum) throw new TypeError("INVALID_RECRUITMENT_CANDIDATE_INPUT");
  return normalized;
}

export function recruitmentCandidateCreateRequest(input) {
  const email = text(input?.email, 254).toLowerCase();
  const testProfile = text(input?.test_profile);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !PROFILES.has(testProfile)) throw new TypeError("INVALID_RECRUITMENT_CANDIDATE_INPUT");
  return { action: "invite_recruitment_test_candidate", name: text(input?.name), email, test_profile: testProfile };
}

export function recruitmentTestReviewRequest(assignmentId, reviewNotes) {
  if (!UUID.test(assignmentId)) throw new TypeError("INVALID_RECRUITMENT_REVIEW_INPUT");
  return { action: "review_recruitment_candidate_test", assignment_id: assignmentId, review_notes: text(reviewNotes, 2000) };
}

export async function executeRecruitmentTestRequest(client, request, { onAuthorizationFailure = ()=>{} } = {}) {
  if (request?.action === "invite_recruitment_test_candidate") {
    if (!client?.functions?.invoke) throw new TypeError("INVALID_RECRUITMENT_TEST_REQUEST");
    const { data, error } = await client.functions.invoke("recruitment-candidate-invitation", {
      body: { name: request.name, email: request.email, test_profile: request.test_profile },
    });
    if (error || data?.ok !== true) {
      if (error?.context?.status === 401 || data?.code === "RECRUITMENT_OWNER_REQUIRED") onAuthorizationFailure(error || data);
      throw error || new Error(data?.code || "RECRUITMENT_INVITATION_FAILED");
    }
    return data;
  }
  const routes = {
    list_recruitment_candidate_tests: ["list_owner_recruitment_candidate_tests_v1", {}],
    review_recruitment_candidate_test: ["review_recruitment_candidate_test_v1", { p_assignment_id: request.assignment_id, p_review_notes: request.review_notes }],
  };
  const route = routes[request?.action];
  if (!route || !client?.rpc) throw new TypeError("INVALID_RECRUITMENT_TEST_REQUEST");
  const { data, error } = await client.rpc(route[0], route[1]);
  if (error) {
    if (error.code === "42501") onAuthorizationFailure(error);
    throw error;
  }
  return data;
}

function formatDate(value) {
  return value ? new Intl.DateTimeFormat("nl-BE", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "-";
}

export function initializeRecruitmentCandidateTests(root, client, { onAuthorizationFailure = ()=>{} } = {}) {
  const list = root.getElementById("recruitmentCandidateList");
  if (!list || list.dataset.initialized === "true") return null;
  list.dataset.initialized = "true";
  const execute = (request)=>executeRecruitmentTestRequest(client, request, { onAuthorizationFailure });
  const createDialog = root.getElementById("recruitmentCandidateDialog");
  const createForm = root.getElementById("recruitmentCandidateForm");
  const reviewDialog = root.getElementById("recruitmentReviewDialog");
  const reviewForm = root.getElementById("recruitmentReviewForm");
  const message = root.getElementById("recruitmentCandidateMessage");
  const empty = root.getElementById("recruitmentCandidateEmpty");
  const listener = new AbortController();
  let candidates = [];
  let reviewAssignmentId = null;
  let disposed = false;
  const listen = (target, type, handler)=>target.addEventListener(type, handler, { signal: listener.signal });

  function render() {
    if (disposed) return;
    list.replaceChildren();
    for (const item of candidates) {
      const card = root.createElement("li");
      card.className = "recruitment-candidate-item";
      const heading = root.createElement("div");
      heading.className = "recruitment-candidate-item__heading";
      const title = root.createElement("h3");
      title.textContent = item.name;
      const badge = root.createElement("span");
      badge.className = "badge";
      badge.textContent = item.assignment_status ? STATUS_LABELS[item.assignment_status] : "Geen test";
      heading.append(title, badge);
      const identity = root.createElement("p");
      identity.className = "recruitment-candidate-item__identity";
      identity.textContent = `${item.candidate_id} · ${item.email}`;
      const profile = root.createElement("p");
      profile.textContent = item.test_profile;
      card.append(heading, identity, profile);
      if (Array.isArray(item.selected_tests) && item.selected_tests.length) {
        const selected = root.createElement("ol");
        selected.className = "recruitment-candidate-selected-tests";
        for (const test of item.selected_tests) {
          const entry = root.createElement("li");
          entry.textContent = test.title;
          selected.append(entry);
        }
        card.append(selected);
      }
      const delivery = root.createElement("p");
      delivery.className = "recruitment-candidate-delivery";
      delivery.textContent = item.invitation_status === "sent"
        ? `Uitnodiging verzonden · ${formatDate(item.invitation_sent_at)}`
        : `Uitnodiging: ${item.invitation_status || "niet voorbereid"}`;
      card.append(delivery);
      const timing = root.createElement("p");
      timing.className = "recruitment-candidate-timing";
      timing.textContent = `Gestart ${formatDate(item.started_at)} · Ingediend ${formatDate(item.submitted_at)} · Beoordeeld ${formatDate(item.reviewed_at)}`;
      card.append(timing);
      if (item.submitted_answers) {
        const answers = root.createElement("dl");
        answers.className = "recruitment-candidate-answers";
        for (const [key, value] of Object.entries(item.submitted_answers)) {
          const row = root.createElement("div");
          const term = root.createElement("dt");
          const detail = root.createElement("dd");
          term.textContent = key;
          detail.textContent = String(value);
          row.append(term, detail);
          answers.append(row);
        }
        card.append(answers);
      }
      if (Array.isArray(item.history) && item.history.length) {
        const history = root.createElement("ol");
        history.className = "recruitment-candidate-history";
        for (const event of item.history) {
          const entry = root.createElement("li");
          entry.textContent = `${STATUS_LABELS[event.to_status]} · ${formatDate(event.occurred_at)}`;
          history.append(entry);
        }
        card.append(history);
      }
      if (item.assignment_status === "INGEDIEND") {
        const review = root.createElement("button");
        review.type = "button";
        review.className = "primary-action primary-action--compact";
        review.textContent = "Beoordelen";
        listen(review, "click", ()=>{ reviewAssignmentId = item.assignment_id; reviewForm.reset(); reviewDialog.showModal(); });
        card.append(review);
      } else if (item.assignment_status === "BEOORDEELD" && item.review_notes) {
        const notes = root.createElement("p");
        notes.className = "recruitment-candidate-review";
        notes.textContent = `Beoordeling: ${item.review_notes}`;
        card.append(notes);
      }
      list.append(card);
    }
    empty.hidden = candidates.length > 0;
  }

  async function refresh() {
    message.textContent = "Kandidaatkamer laden...";
    try {
      candidates = await execute({ action: "list_recruitment_candidate_tests" });
      render();
      message.textContent = "";
      return true;
    } catch {
      message.textContent = "Kandidaatkamer kon niet veilig worden geladen.";
      return false;
    }
  }

  listen(root.getElementById("recruitmentCandidateCreate"), "click", ()=>{ createForm.reset(); createDialog.showModal(); });
  listen(root.getElementById("recruitmentCandidateRefresh"), "click", ()=>{ void refresh(); });
  listen(root.getElementById("recruitmentCandidateCancel"), "click", ()=>createDialog.close());
  listen(root.getElementById("recruitmentReviewCancel"), "click", ()=>reviewDialog.close());
  listen(createForm, "submit", async (event)=>{
    event.preventDefault();
    if (!createForm.reportValidity()) return;
    const request = recruitmentCandidateCreateRequest(Object.fromEntries(new FormData(createForm)));
    try {
      const result = await execute(request);
      createDialog.close();
      await refresh();
      message.textContent = `Uitnodiging verzonden met ${result.selection_count} automatisch gekozen tests.`;
    } catch { root.getElementById("recruitmentCandidateFormMessage").textContent = "Uitnodiging kon niet veilig worden verzonden."; }
  });
  listen(reviewForm, "submit", async (event)=>{
    event.preventDefault();
    if (!reviewForm.reportValidity() || !reviewAssignmentId) return;
    try { await execute(recruitmentTestReviewRequest(reviewAssignmentId, reviewForm.elements.namedItem("review_notes").value)); reviewDialog.close(); await refresh(); } catch { root.getElementById("recruitmentReviewMessage").textContent = "Beoordeling kon niet worden opgeslagen."; }
  });

  render();
  void refresh();
  return Object.freeze({
    refresh,
    dispose() {
      disposed = true;
      listener.abort();
      for (const dialog of [createDialog, reviewDialog]) if (dialog.open) dialog.close();
    },
  });
}

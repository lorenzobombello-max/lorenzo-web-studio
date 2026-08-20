import { callCommercialOperator } from "./operator-auth-core.mjs";

const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;

export function applicationReferenceFromUrl(url) {
  const value = new URL(url).searchParams.get("application");
  return value && APPLICATION_REFERENCE.test(value) ? value : null;
}

export function canPromoteApplication(detail) {
  return Boolean(detail?.acceptance && !detail?.project);
}

function setText(id, value) {
  const element = document.getElementById(id);
  if (element) element.textContent = value ?? "-";
}

function badge(value, tone) {
  const element = document.createElement("span");
  element.className = `badge${tone ? ` badge--${tone}` : ""}`;
  element.textContent = value;
  return element;
}

function formatDate(value) {
  return value ? new Intl.DateTimeFormat("nl-BE", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "-";
}

function formatMoney(value) {
  return Number.isSafeInteger(value)
    ? new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR" }).format(value / 100)
    : "-";
}

export async function startOperatorDashboard({ client, functionsBaseUrl, callOperator = callCommercialOperator }) {
  const list = document.getElementById("applicationList");
  const empty = document.getElementById("applicationEmpty");
  const listMessage = document.getElementById("applicationListMessage");
  const detail = document.getElementById("applicationDetail");
  const detailEmpty = document.getElementById("applicationDetailEmpty");
  const detailMessage = document.getElementById("applicationDetailMessage");
  const promote = document.getElementById("promoteApplication");
  const confirmation = document.getElementById("promotionDialog");
  let selectedReference = applicationReferenceFromUrl(window.location.href);
  let selectedDetail = null;

  async function invoke(input) {
    const response = await callOperator(client, functionsBaseUrl, input);
    if (response.status >= 400 || !response.body?.ok) throw new Error(response.body?.code || "OPERATOR_REQUEST_FAILED");
    return response.body.result;
  }

  function updateLocation(reference) {
    const url = new URL(window.location.href);
    url.searchParams.set("application", reference);
    window.history.replaceState(null, "", `${url.pathname}${url.search}`);
  }

  function renderDetail(application) {
    selectedDetail = application;
    detailEmpty.hidden = true;
    detail.hidden = false;
    setText("detailReference", application.application_reference);
    setText("detailName", application.name);
    setText("detailCompany", application.company || "Geen onderneming");
    setText("detailEmail", application.email);
    setText("detailPhone", application.phone || "-");
    setText("detailWebsiteType", application.website_type);
    setText("detailBudget", application.budget);
    setText("detailTiming", application.timing);
    setText("detailDescription", application.description);
    setText("detailSubmittedAt", formatDate(application.submitted_at));
    setText("detailQuotation", application.acceptance?.quotation_number || "Nog niet geaccepteerd");
    setText("detailAcceptedAt", formatDate(application.acceptance?.accepted_at));
    setText("detailProject", application.project?.project_id || "Nog niet aangemaakt");
    setText("detailProjectState", application.project?.current_state || "-");
    setText("detailTotal", formatMoney(application.project?.accepted_total_minor));
    promote.hidden = !canPromoteApplication(application);
  }

  async function loadDetail(reference) {
    detailMessage.textContent = "Aanvraag wordt geladen.";
    try {
      const application = await invoke({ action: "get_application_detail", application_reference: reference });
      renderDetail(application);
      detailMessage.textContent = "";
      selectedReference = reference;
      updateLocation(reference);
    } catch {
      detail.hidden = true;
      detailEmpty.hidden = false;
      detailMessage.textContent = "De aanvraag kon niet worden geladen.";
    }
  }

  function renderList(applications) {
    list.replaceChildren();
    empty.hidden = applications.length > 0;
    for (const application of applications) {
      const item = document.createElement("li");
      const button = document.createElement("button");
      button.type = "button";
      button.className = "application-list__button";
      button.dataset.reference = application.application_reference;
      const identity = document.createElement("span");
      const name = document.createElement("strong");
      name.textContent = application.company || application.name;
      const reference = document.createElement("small");
      reference.textContent = `${application.application_reference} · ${formatDate(application.submitted_at)}`;
      identity.append(name, reference);
      const state = application.project_state
        ? badge(application.project_state, "green")
        : application.acceptance_id
        ? badge("Geaccepteerd", "amber")
        : badge("Ingediend");
      button.append(identity, state);
      button.addEventListener("click", ()=>loadDetail(application.application_reference));
      item.append(button);
      list.append(item);
    }
  }

  async function loadList() {
    listMessage.textContent = "Aanvragen worden geladen.";
    try {
      const applications = await invoke({ action: "list_applications", limit: 100, offset: 0 });
      renderList(applications);
      listMessage.textContent = "";
      if (selectedReference) await loadDetail(selectedReference);
    } catch {
      listMessage.textContent = "De aanvragen konden niet worden geladen.";
    }
  }

  promote.addEventListener("click", ()=>confirmation.showModal());
  confirmation.addEventListener("close", async ()=>{
    if (confirmation.returnValue !== "confirm" || !canPromoteApplication(selectedDetail)) return;
    promote.disabled = true;
    detailMessage.textContent = "Project wordt aangemaakt.";
    try {
      await invoke({ action: "promote_accepted_application", application_reference: selectedReference, idempotency_key: crypto.randomUUID() });
      await loadList();
      detailMessage.textContent = "Project is gekoppeld.";
    } catch {
      detailMessage.textContent = "Het project kon niet worden aangemaakt.";
    } finally {
      promote.disabled = false;
    }
  });

  await loadList();
}
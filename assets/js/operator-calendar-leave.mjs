const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const EMPLOYEE_NUMBER = /^LWS-[0-9]{5}$/;
const LEAVE_STATUSES = new Set(["REQUESTED", "WAITING", "APPROVED", "REJECTED"]);
const DAY_PARTS = new Set(["FULL_DAY", "AM", "PM"]);
const STATUS_PRESENTATION = Object.freeze({
  REQUESTED: { label: "Nieuw", tone: "requested" },
  WAITING: { label: "In wacht", tone: "waiting" },
  APPROVED: { label: "Goedgekeurd", tone: "approved" },
  REJECTED: { label: "Geweigerd", tone: "rejected" },
});
const DAY_PART_LABELS = Object.freeze({ FULL_DAY: "Volledige dag", AM: "Voormiddag", PM: "Namiddag" });

function exactKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every((key)=>Object.hasOwn(value, key));
}

function validTimestamp(value) {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function validNullableText(value) {
  return value === null || typeof value === "string";
}

function validCount(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function leaveDate(value) {
  return new Date(`${value}T12:00:00Z`);
}

function formatDate(value) {
  return new Intl.DateTimeFormat("nl-BE", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC" }).format(leaveDate(value));
}

function formatTimestamp(value) {
  return new Intl.DateTimeFormat("nl-BE", {
    day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit",
  }).format(new Date(value));
}

function requestPeriod(request) {
  return request.start_date === request.end_date
    ? formatDate(request.start_date)
    : `${formatDate(request.start_date)} - ${formatDate(request.end_date)}`;
}

export function emptyOperatorLeaveQueue(range) {
  return {
    start_date: range.start_date,
    end_date: range.end_date,
    counters: { requested: 0, waiting: 0, approved: 0, rejected: 0 },
    requests: [],
  };
}

export function operatorLeaveQueueResponse(value, expectedRange) {
  if (!exactKeys(value, ["start_date", "end_date", "counters", "requests"])
    || value.start_date !== expectedRange.start_date || value.end_date !== expectedRange.end_date
    || !exactKeys(value.counters, ["requested", "waiting", "approved", "rejected"])
    || !Object.values(value.counters).every(validCount) || !Array.isArray(value.requests)) {
    throw new Error("INVALID_OPERATOR_LEAVE_QUEUE_RESPONSE");
  }
  for (const request of value.requests) {
    if (!exactKeys(request, [
      "request_id", "employee_id", "employee_number", "display_name", "leave_type", "start_date", "end_date",
      "day_part", "request_status", "revision", "employee_note", "submitted_at", "decided_at",
      "decided_by_operator_id", "management_note", "capacity_context", "history",
    ]) || !UUID.test(request.request_id) || !UUID.test(request.employee_id)
      || (request.employee_number !== null && !EMPLOYEE_NUMBER.test(request.employee_number))
      || typeof request.display_name !== "string" || !request.display_name.trim() || request.leave_type !== "LEAVE"
      || !DATE.test(request.start_date) || !DATE.test(request.end_date) || request.start_date > request.end_date
      || !DAY_PARTS.has(request.day_part) || (request.day_part !== "FULL_DAY" && request.start_date !== request.end_date)
      || !LEAVE_STATUSES.has(request.request_status) || !Number.isSafeInteger(request.revision) || request.revision < 1
      || !validNullableText(request.employee_note) || !validTimestamp(request.submitted_at)
      || (request.decided_at !== null && !validTimestamp(request.decided_at))
      || (request.decided_by_operator_id !== null && !UUID.test(request.decided_by_operator_id))
      || !validNullableText(request.management_note) || !Array.isArray(request.capacity_context)
      || !Array.isArray(request.history)) {
      throw new Error("INVALID_OPERATOR_LEAVE_QUEUE_RESPONSE");
    }
    if ((request.request_status === "REQUESTED" && (request.decided_at !== null || request.decided_by_operator_id !== null))
      || (request.request_status !== "REQUESTED" && (request.decided_at === null || request.decided_by_operator_id === null))) {
      throw new Error("INVALID_OPERATOR_LEAVE_QUEUE_RESPONSE");
    }
    for (const context of request.capacity_context) {
      if (!exactKeys(context, [
        "date", "employees_total", "approved_leave_count", "sick_count", "other_absence_count",
        "requested_count", "waiting_count",
      ]) || !DATE.test(context.date) || context.date < request.start_date || context.date > request.end_date
        || !Object.entries(context).filter(([key])=>key !== "date").every(([, count])=>validCount(count))) {
        throw new Error("INVALID_OPERATOR_LEAVE_QUEUE_RESPONSE");
      }
    }
    for (const event of request.history) {
      if (!exactKeys(event, [
        "event_id", "event_type", "previous_status", "new_status", "actor_operator_id", "actor_display_name",
        "management_note", "occurred_at",
      ]) || !UUID.test(event.event_id) || !["SUBMITTED", "DECISION"].includes(event.event_type)
        || (event.previous_status !== null && !LEAVE_STATUSES.has(event.previous_status))
        || !LEAVE_STATUSES.has(event.new_status) || !UUID.test(event.actor_operator_id)
        || typeof event.actor_display_name !== "string" || !event.actor_display_name.trim()
        || !validNullableText(event.management_note) || !validTimestamp(event.occurred_at)) {
        throw new Error("INVALID_OPERATOR_LEAVE_QUEUE_RESPONSE");
      }
    }
  }
  return value;
}

export function calendarLeaveQueueView(queue, status = "REQUESTED") {
  const selectedStatus = LEAVE_STATUSES.has(status) ? status : "REQUESTED";
  return {
    selectedStatus,
    counters: queue.counters,
    requests: queue.requests.filter((request)=>request.request_status === selectedStatus),
  };
}

export function calendarLeaveDecisionRequest(request, decision, managementNote = null) {
  if (!request || !UUID.test(request.request_id) || !LEAVE_STATUSES.has(request.request_status)
    || !Number.isSafeInteger(request.revision) || request.revision < 1
    || !["WAITING", "APPROVED", "REJECTED"].includes(decision)
    || (decision === "WAITING" && request.request_status !== "REQUESTED")
    || (["APPROVED", "REJECTED"].includes(decision) && !["REQUESTED", "WAITING"].includes(request.request_status))) {
    throw new Error("INVALID_OPERATOR_LEAVE_DECISION");
  }
  const note = typeof managementNote === "string" ? managementNote.trim() : "";
  if (note.length > 2000) throw new Error("INVALID_OPERATOR_LEAVE_DECISION_NOTE");
  return {
    p_request_id: request.request_id,
    p_expected_status: request.request_status,
    p_expected_revision: request.revision,
    p_decision: decision,
    p_management_note: note || null,
  };
}

function authorizationFailure(error) {
  return error?.code === "42501" || /42501|OWNER_REQUIRED|AUTHENTICATION_REQUIRED|HUMAN_JWT_REQUIRED/.test(error?.message || "");
}

export function staleLeaveDecision(error) {
  return error?.code === "40001" || /LEAVE_REQUEST_STALE_DECISION|40001/.test(error?.message || "");
}

export async function loadOperatorLeaveQueue(client, range, { onAuthorizationFailure = ()=>{} } = {}) {
  if (!client?.rpc) throw new TypeError("OPERATOR_LEAVE_CLIENT_REQUIRED");
  const { data, error } = await client.rpc("get_operator_leave_requests_v1", {
    p_start_date: range.start_date,
    p_end_date: range.end_date,
  });
  if (error) {
    if (authorizationFailure(error)) onAuthorizationFailure(error);
    throw error;
  }
  return operatorLeaveQueueResponse(data, range);
}

export async function decideOperatorLeaveRequest(client, request, decision, managementNote, { onAuthorizationFailure = ()=>{} } = {}) {
  if (!client?.rpc) throw new TypeError("OPERATOR_LEAVE_CLIENT_REQUIRED");
  const { data, error } = await client.rpc("decide_operator_leave_request_v1", calendarLeaveDecisionRequest(request, decision, managementNote));
  if (error) {
    if (authorizationFailure(error)) onAuthorizationFailure(error);
    throw error;
  }
  if (!exactKeys(data, ["request_id", "previous_status", "request_status", "revision", "decided_at"])
    || data.request_id !== request.request_id || data.previous_status !== request.request_status
    || data.request_status !== decision || data.revision !== request.revision + 1 || !validTimestamp(data.decided_at)) {
    throw new Error("INVALID_OPERATOR_LEAVE_DECISION_RESPONSE");
  }
  return data;
}

function appendDefinition(root, list, label, value) {
  const item = root.createElement("div");
  const term = root.createElement("dt");
  const definition = root.createElement("dd");
  term.textContent = label;
  definition.textContent = value || "—";
  item.append(term, definition);
  list.append(item);
}

export function initializeCalendarLeaveManagement({ root, panel, before, onDecide, onRefresh }) {
  if (!root || !panel || !before || typeof onDecide !== "function" || typeof onRefresh !== "function") {
    throw new TypeError("CALENDAR_LEAVE_MANAGEMENT_CONFIGURATION_REQUIRED");
  }
  const listeners = new AbortController();
  const signal = listeners.signal;
  const section = root.createElement("section");
  const heading = root.createElement("div");
  const headingCopy = root.createElement("div");
  const eyebrow = root.createElement("p");
  const title = root.createElement("h2");
  const description = root.createElement("p");
  const filters = root.createElement("div");
  const list = root.createElement("div");
  const empty = root.createElement("p");
  const detail = root.createElement("section");
  const message = root.createElement("p");
  const dialog = root.createElement("dialog");
  const form = root.createElement("form");
  const dialogEyebrow = root.createElement("p");
  const dialogTitle = root.createElement("h2");
  const dialogDescription = root.createElement("p");
  const noteLabel = root.createElement("label");
  const note = root.createElement("textarea");
  const dialogActions = root.createElement("div");
  const cancel = root.createElement("button");
  const confirm = root.createElement("button");
  let queue = emptyOperatorLeaveQueue({ start_date: "1970-01-01", end_date: "1970-01-01" });
  let selectedStatus = "REQUESTED";
  let selectedRequestId = null;
  let pendingDecision = null;
  let returnFocus = null;

  section.className = "calendar-leave-management";
  section.setAttribute("aria-labelledby", "calendarLeaveTitle");
  heading.className = "calendar-leave-management__heading";
  eyebrow.className = "eyebrow";
  eyebrow.textContent = "Managementbeslissing";
  title.id = "calendarLeaveTitle";
  title.textContent = "Verlofaanvragen";
  description.textContent = "Nieuwe en wachtende aanvragen vereisen een expliciete beslissing.";
  headingCopy.append(eyebrow, title, description);
  heading.append(headingCopy);
  filters.className = "calendar-leave-filters";
  filters.setAttribute("aria-label", "Verlofaanvraagstatus");
  list.className = "calendar-leave-list";
  empty.className = "calendar-leave-empty";
  empty.hidden = true;
  detail.className = "calendar-leave-detail";
  detail.hidden = true;
  message.className = "calendar-leave-message";
  message.setAttribute("role", "status");
  message.setAttribute("aria-live", "polite");
  section.append(heading, filters, list, empty, detail, message);
  before.before(section);

  dialog.className = "calendar-leave-dialog operator-modal--action-confirm";
  dialog.setAttribute("aria-labelledby", "calendarLeaveDialogTitle");
  dialog.setAttribute("aria-describedby", "calendarLeaveDialogDescription");
  form.className = "confirmation calendar-leave-dialog__form";
  dialogEyebrow.className = "eyebrow eyebrow--red";
  dialogEyebrow.textContent = "Managementbeslissing";
  dialogTitle.id = "calendarLeaveDialogTitle";
  dialogDescription.id = "calendarLeaveDialogDescription";
  noteLabel.textContent = "Managementnotitie (optioneel)";
  note.name = "management_note";
  note.rows = 4;
  note.maxLength = 2000;
  note.autocomplete = "off";
  noteLabel.append(note);
  dialogActions.className = "confirmation__actions";
  cancel.type = "button";
  cancel.className = "secondary-action";
  cancel.textContent = "Terug";
  confirm.type = "submit";
  confirm.className = "primary-action primary-action--compact";
  dialogActions.append(cancel, confirm);
  form.append(dialogEyebrow, dialogTitle, dialogDescription, noteLabel, dialogActions);
  dialog.append(form);
  panel.append(dialog);

  function closeDetail({ restoreFocus = false } = {}) {
    const requestId = selectedRequestId;
    selectedRequestId = null;
    detail.hidden = true;
    detail.replaceChildren();
    if (restoreFocus && requestId) list.querySelector(`[data-leave-request-id="${requestId}"]`)?.focus();
  }

  function openDecision(request, decision, trigger) {
    pendingDecision = { request, decision };
    returnFocus = trigger;
    note.value = "";
    dialogTitle.textContent = decision === "APPROVED" ? "Verlof goedkeuren" : decision === "WAITING" ? "Aanvraag in wacht zetten" : "Verlofaanvraag weigeren";
    dialogDescription.textContent = decision === "APPROVED"
      ? `Verlof goedkeuren voor ${request.display_name} op ${requestPeriod(request)}?`
      : decision === "WAITING"
      ? `${request.display_name} in wacht zetten voor verdere controle?`
      : `Verlofaanvraag van ${request.display_name} voor ${requestPeriod(request)} weigeren?`;
    confirm.textContent = decision === "APPROVED" ? "Goedkeuren" : decision === "WAITING" ? "In wacht zetten" : "Weigeren";
    confirm.className = decision === "REJECTED" ? "danger-action" : "primary-action primary-action--compact";
    dialog.showModal();
    note.focus();
  }

  function renderDetail(request, { focus = false } = {}) {
    selectedRequestId = request.request_id;
    detail.replaceChildren();
    const detailHeading = root.createElement("header");
    const identity = root.createElement("div");
    const detailEyebrow = root.createElement("p");
    const detailTitle = root.createElement("h3");
    const close = root.createElement("button");
    const facts = root.createElement("dl");
    const contextTitle = root.createElement("h4");
    const contextViewport = root.createElement("div");
    const contextTable = root.createElement("table");
    const contextHead = root.createElement("thead");
    const contextHeaderRow = root.createElement("tr");
    const contextBody = root.createElement("tbody");
    const historyTitle = root.createElement("h4");
    const history = root.createElement("ol");
    const actions = root.createElement("div");
    detailHeading.className = "calendar-leave-detail__heading";
    detailEyebrow.className = "eyebrow";
    detailEyebrow.textContent = "Aanvraagdetail · authoritative";
    detailTitle.id = "calendarLeaveDetailTitle";
    detailTitle.textContent = request.display_name;
    identity.append(detailEyebrow, detailTitle);
    close.type = "button";
    close.className = "calendar-leave-detail__close";
    close.setAttribute("aria-label", "Verlofaanvraag sluiten");
    close.textContent = "×";
    close.addEventListener("click", ()=>closeDetail({ restoreFocus: true }), { signal });
    detailHeading.append(identity, close);
    facts.className = "calendar-leave-detail__facts";
    appendDefinition(root, facts, "Werknemer", request.display_name);
    appendDefinition(root, facts, "Personeelsnummer", request.employee_number);
    appendDefinition(root, facts, "Aanvraag", "Verlof");
    appendDefinition(root, facts, "Periode", requestPeriod(request));
    appendDefinition(root, facts, "Dagdeel", DAY_PART_LABELS[request.day_part]);
    appendDefinition(root, facts, "Status", STATUS_PRESENTATION[request.request_status].label);
    appendDefinition(root, facts, "Ingediend op", formatTimestamp(request.submitted_at));
    appendDefinition(root, facts, "Opmerking werknemer", request.employee_note);
    contextTitle.textContent = "Dagcapaciteit / afwezigheidscontext";
    for (const label of ["Datum", "Medewerkers", "Goedgekeurd verlof", "Ziek", "Andere afwezigheid", "Nieuw", "In wacht"]) {
      const header = root.createElement("th");
      header.scope = "col";
      header.textContent = label;
      contextHeaderRow.append(header);
    }
    contextHead.append(contextHeaderRow);
    for (const context of request.capacity_context) {
      const row = root.createElement("tr");
      for (const [index, value] of [
        formatDate(context.date), context.employees_total, context.approved_leave_count, context.sick_count,
        context.other_absence_count, context.requested_count, context.waiting_count,
      ].entries()) {
        const cell = root.createElement(index === 0 ? "th" : "td");
        if (index === 0) cell.scope = "row";
        cell.textContent = String(value);
        row.append(cell);
      }
      contextBody.append(row);
    }
    contextTable.append(contextHead, contextBody);
    contextViewport.className = "calendar-leave-detail__context";
    contextViewport.append(contextTable);
    historyTitle.textContent = "Beslishistorie";
    history.className = "calendar-leave-history";
    for (const event of request.history) {
      const item = root.createElement("li");
      const status = root.createElement("strong");
      const metadata = root.createElement("span");
      const eventNote = root.createElement("p");
      status.textContent = event.previous_status ? `${event.previous_status} → ${event.new_status}` : event.new_status;
      metadata.textContent = `${event.actor_display_name} · ${formatTimestamp(event.occurred_at)}`;
      item.append(status, metadata);
      if (event.management_note) {
        eventNote.textContent = event.management_note;
        item.append(eventNote);
      }
      history.append(item);
    }
    actions.className = "calendar-leave-detail__actions";
    const decisions = request.request_status === "REQUESTED" ? ["APPROVED", "WAITING", "REJECTED"]
      : request.request_status === "WAITING" ? ["APPROVED", "REJECTED"] : [];
    for (const decision of decisions) {
      const action = root.createElement("button");
      action.type = "button";
      action.dataset.leaveDecision = decision;
      action.className = decision === "REJECTED" ? "danger-action" : decision === "WAITING" ? "secondary-action" : "primary-action primary-action--compact";
      action.textContent = decision === "APPROVED" ? "Goedkeuren" : decision === "WAITING" ? "In wacht zetten" : "Weigeren";
      action.addEventListener("click", ()=>openDecision(request, decision, action), { signal });
      actions.append(action);
    }
    detail.append(detailHeading, facts, contextTitle, contextViewport, historyTitle, history, actions);
    detail.setAttribute("aria-labelledby", "calendarLeaveDetailTitle");
    detail.hidden = false;
    if (focus) close.focus();
  }

  function renderList() {
    const view = calendarLeaveQueueView(queue, selectedStatus);
    filters.replaceChildren();
    for (const status of LEAVE_STATUSES) {
      const button = root.createElement("button");
      const count = queue.counters[status.toLowerCase()];
      button.type = "button";
      button.dataset.leaveStatus = status;
      button.setAttribute("aria-pressed", String(status === selectedStatus));
      button.textContent = `${STATUS_PRESENTATION[status].label} ${count}`;
      button.addEventListener("click", ()=>{
        selectedStatus = status;
        closeDetail();
        renderList();
      }, { signal });
      filters.append(button);
    }
    list.replaceChildren();
    for (const request of view.requests) {
      const button = root.createElement("button");
      const heading = root.createElement("span");
      const employee = root.createElement("strong");
      const badge = root.createElement("span");
      const metadata = root.createElement("span");
      const submitted = root.createElement("small");
      button.type = "button";
      button.className = "calendar-leave-item";
      button.dataset.leaveRequestId = request.request_id;
      button.setAttribute("aria-label", `${request.display_name} verlofaanvraag openen`);
      heading.className = "calendar-leave-item__heading";
      employee.textContent = request.display_name;
      badge.className = "calendar-leave-status";
      badge.dataset.leaveRequestStatus = request.request_status;
      badge.textContent = STATUS_PRESENTATION[request.request_status].label;
      heading.append(employee, badge);
      metadata.className = "calendar-leave-item__metadata";
      metadata.textContent = `${request.employee_number || "Geen personeelsnummer"} · ${requestPeriod(request)} · ${DAY_PART_LABELS[request.day_part]}`;
      submitted.textContent = `${formatTimestamp(request.submitted_at)}${request.employee_note ? " · Opmerking werknemer" : ""}`;
      button.append(heading, metadata, submitted);
      button.addEventListener("click", ()=>renderDetail(request, { focus: true }), { signal });
      list.append(button);
    }
    empty.hidden = view.requests.length > 0;
    empty.textContent = `Geen ${STATUS_PRESENTATION[selectedStatus].label.toLowerCase()} verlofaanvragen in deze periode.`;
    if (selectedRequestId) {
      const selected = queue.requests.find((request)=>request.request_id === selectedRequestId);
      if (selected) renderDetail(selected);
      else closeDetail();
    }
  }

  cancel.addEventListener("click", ()=>dialog.close(), { signal });
  dialog.addEventListener("close", ()=>{
    pendingDecision = null;
    returnFocus?.focus();
    returnFocus = null;
  }, { signal });
  form.addEventListener("submit", async (event)=>{
    event.preventDefault();
    if (!pendingDecision) return;
    confirm.disabled = true;
    cancel.disabled = true;
    message.textContent = "Beslissing verwerken...";
    try {
      await onDecide(pendingDecision.request, pendingDecision.decision, note.value);
      message.textContent = "Beslissing opgeslagen.";
      dialog.close();
      await onRefresh();
    } catch (error) {
      if (staleLeaveDecision(error)) {
        message.textContent = "Deze aanvraag werd intussen door iemand anders verwerkt. Vernieuw de gegevens.";
        dialog.close();
        await onRefresh();
      } else {
        message.textContent = error?.message === "LEAVE_REQUEST_CALENDAR_CONFLICT"
          ? "Goedkeuring geblokkeerd: er bestaat al een definitieve kalenderstatus voor deze werknemer en datum."
          : "De beslissing kon niet worden opgeslagen.";
      }
    } finally {
      confirm.disabled = false;
      cancel.disabled = false;
    }
  }, { signal });
  root.addEventListener("keydown", (event)=>{
    if (event.key === "Escape" && !detail.hidden && !dialog.open) closeDetail({ restoreFocus: true });
  }, { signal });

  return {
    render(nextQueue) {
      queue = nextQueue;
      renderList();
    },
    dispose() {
      listeners.abort();
      if (dialog.open) dialog.close();
      dialog.remove();
      section.remove();
    },
  };
}
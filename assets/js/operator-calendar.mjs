import { createOperatorAutoRefresh } from "./operator-auto-refresh.mjs?v=20260903-auto-refresh-8s";
import { createOperatorRefreshHeartbeat } from "./operator-refresh-heartbeat.mjs?v=20260903-live-heartbeat";
import {
  decideOperatorLeaveRequest,
  emptyOperatorLeaveQueue,
  initializeCalendarLeaveManagement,
  loadOperatorLeaveQueue,
  operatorLeaveQueueResponse,
} from "./operator-calendar-leave.mjs?v=20260903-cal-c1";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CALENDAR_VIEWS = new Set(["day", "week", "month", "year"]);
const CALENDAR_STATUSES = Object.freeze({
  full_day: { label: "Volledige werkdag", icon: "A" },
  half_day_am: { label: "Halve dag voormiddag", icon: "1/2" },
  half_day_pm: { label: "Halve dag namiddag", icon: "1/2" },
  leave: { label: "Verlof", icon: "V" },
  sick: { label: "Ziek", icon: "Z" },
  other_absence: { label: "Andere afwezigheid", icon: "A" },
  no_data: { label: "Geen planning / geen data", icon: "-" },
});
const STATUS_MAP = Object.freeze({
  WORKED_FULL_DAY: "full_day",
  WORKED_HALF_DAY_AM: "half_day_am",
  WORKED_HALF_DAY_PM: "half_day_pm",
  LEAVE: "leave",
  SICK: "sick",
  OTHER_ABSENCE: "other_absence",
});
const SOURCE_STATUS_BY_KEY = Object.freeze(Object.fromEntries(Object.entries(STATUS_MAP).map(([source, key])=>[key, source])));
const SUMMARY_ITEMS = Object.freeze([
  { key: "totalEmployees", label: "Totaal medewerkers", unit: "in deze periode" },
  { key: "worked", label: "Aanwezig / gewerkt", unit: "statusdagen" },
  { key: "leave", label: "Verlof", unit: "statusdagen" },
  { key: "sick", label: "Ziek", unit: "statusdagen" },
  { key: "otherAbsence", label: "Andere afwezigheid", unit: "statusdagen" },
  { key: "noData", label: "Geen data", unit: "statusdagen" },
]);

function calendarDate(value) {
  const date = value instanceof Date ? new Date(value) : new Date(`${value}T12:00:00Z`);
  if (Number.isNaN(date.getTime())) throw new TypeError("INVALID_CALENDAR_DATE");
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 12));
}

function dateKey(date) { return date.toISOString().slice(0, 10); }
function addDays(date, days) { const result = calendarDate(date); result.setUTCDate(result.getUTCDate() + days); return result; }
function exactKeys(value, keys) { return value && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === keys.length && keys.every((key)=>Object.hasOwn(value, key)); }

function periodDates(view, anchor) {
  if (view === "day") return [anchor];
  if (view === "week") {
    const mondayOffset = (anchor.getUTCDay() + 6) % 7;
    return Array.from({ length: 7 }, (_, index)=>addDays(anchor, index - mondayOffset));
  }
  if (view === "month") {
    const count = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + 1, 0)).getUTCDate();
    return Array.from({ length: count }, (_, index)=>new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth(), index + 1, 12)));
  }
  return Array.from({ length: 12 }, (_, month)=>new Date(Date.UTC(anchor.getUTCFullYear(), month, 1, 12)));
}

function periodLabel(view, dates, anchor) {
  const day = new Intl.DateTimeFormat("nl-BE", { weekday: "long", day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
  const short = new Intl.DateTimeFormat("nl-BE", { day: "numeric", month: "short", timeZone: "UTC" });
  const month = new Intl.DateTimeFormat("nl-BE", { month: "long", year: "numeric", timeZone: "UTC" });
  if (view === "day") return day.format(anchor);
  if (view === "week") return `${short.format(dates[0])} - ${short.format(dates.at(-1))} ${dates.at(-1).getUTCFullYear()}`;
  if (view === "month") return month.format(anchor);
  return String(anchor.getUTCFullYear());
}

export function calendarStatusPresentation(status, sourceStatus = SOURCE_STATUS_BY_KEY[status] || "NO_DATA") {
  const key = Object.hasOwn(CALENDAR_STATUSES, status) ? status : "no_data";
  return { key, sourceStatus: key === "no_data" ? "NO_DATA" : sourceStatus, ...CALENDAR_STATUSES[key] };
}

function calendarCapacity(statuses) {
  const capacity = { worked: 0, leave: 0, sick: 0, otherAbsence: 0, noData: 0 };
  for (const status of statuses) {
    if (["full_day", "half_day_am", "half_day_pm"].includes(status.key)) capacity.worked += 1;
    else if (status.key === "leave") capacity.leave += 1;
    else if (status.key === "sick") capacity.sick += 1;
    else if (status.key === "other_absence") capacity.otherAbsence += 1;
    else capacity.noData += 1;
  }
  return capacity;
}

export function calendarEmployeePeriodDetail(state, employeeId) {
  const employee = state.employees.find((candidate)=>candidate.id === employeeId);
  if (!employee) return null;
  if (state.view === "year") {
    return {
      available: false,
      employee: { id: employee.id, name: employee.name, role: employee.role, team: employee.team },
      periodLabel: state.label,
      message: "Gedetailleerde werknemerstotalen zijn in Jaarweergave niet beschikbaar zonder maandaggregatie.",
    };
  }
  const totals = {
    visibleDays: state.dates.length,
    fullDay: 0,
    halfDayAm: 0,
    halfDayPm: 0,
    leave: 0,
    sick: 0,
    otherAbsence: 0,
    noData: 0,
  };
  const history = state.dates.map((date, index)=>{
    const status = employee.statuses[index] || calendarStatusPresentation("no_data");
    if (status.key === "full_day") totals.fullDay += 1;
    else if (status.key === "half_day_am") totals.halfDayAm += 1;
    else if (status.key === "half_day_pm") totals.halfDayPm += 1;
    else if (status.key === "leave") totals.leave += 1;
    else if (status.key === "sick") totals.sick += 1;
    else if (status.key === "other_absence") totals.otherAbsence += 1;
    else totals.noData += 1;
    return { date, status, info: "—" };
  });
  return {
    available: true,
    employee: { id: employee.id, name: employee.name, role: employee.role, team: employee.team },
    periodLabel: state.label,
    totals,
    workedHours: null,
    history,
  };
}

export function calendarPayrollInputPreview(state, employeeId) {
  const detail = calendarEmployeePeriodDetail(state, employeeId);
  if (!detail) return null;
  if (!detail.available) {
    return {
      available: false,
      employee: detail.employee,
      periodLabel: detail.periodLabel,
      message: "Loonvoorbereiding is niet beschikbaar in Jaarweergave. Kies Dag, Week of Maand.",
    };
  }
  const dayLines = detail.history.map(({ date, status })=>({
    date,
    status,
    hours: null,
    sourceStatus: status.sourceStatus,
    control: status.key === "no_data" ? "CONTROLEREN" : "OK",
  }));
  const incompleteDays = dayLines.filter((line)=>line.control === "CONTROLEREN").map((line)=>line.date);
  return {
    available: true,
    employee: detail.employee,
    periodLabel: detail.periodLabel,
    completeness: incompleteDays.length ? "ONVOLLEDIGE GEGEVENS" : "COMPLEET",
    completenessMessage: incompleteDays.length
      ? `${incompleteDays.length} ${incompleteDays.length === 1 ? "dag" : "dagen"} zonder planning/gegevensaanduiding`
      : "Alle zichtbare dagen hebben een bruikbare canonieke status.",
    incompleteDays,
    totals: detail.totals,
    workedHours: null,
    dayLines,
  };
}

export function operatorCalendarResponse(value, expectedRange) {
  if (!exactKeys(value, ["start_date", "end_date", "employees"])
    || value.start_date !== expectedRange.start_date || value.end_date !== expectedRange.end_date
    || !Array.isArray(value.employees)) throw new Error("INVALID_OPERATOR_CALENDAR_RESPONSE");
  for (const employee of value.employees) {
    if (!exactKeys(employee, ["employee_id", "display_name", "role_title", "team_name", "employment_status", "entries"])
      || !UUID.test(employee.employee_id) || typeof employee.display_name !== "string" || !employee.display_name
      || (employee.role_title !== null && typeof employee.role_title !== "string")
      || (employee.team_name !== null && typeof employee.team_name !== "string")
      || !["ACTIVE", "INACTIVE"].includes(employee.employment_status) || !Array.isArray(employee.entries)) {
      throw new Error("INVALID_OPERATOR_CALENDAR_RESPONSE");
    }
    for (const entry of employee.entries) {
      if (!exactKeys(entry, ["date", "status"]) || typeof entry.date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(entry.date)
        || entry.date < expectedRange.start_date || entry.date > expectedRange.end_date || !Object.hasOwn(STATUS_MAP, entry.status)) {
        throw new Error("INVALID_OPERATOR_CALENDAR_RESPONSE");
      }
    }
  }
  return value;
}

export function createOperatorCalendarModel({ today = ()=>new Date(), employees = [], initialView = "week", leaveQueue = null } = {}) {
  let view = CALENDAR_VIEWS.has(initialView) ? initialView : "week";
  let anchor = calendarDate(today());
  let currentEmployees = employees;
  let currentLeaveQueue = leaveQueue;
  function snapshot() {
    const dates = periodDates(view, anchor);
    const range = view === "year"
      ? { start_date: `${anchor.getUTCFullYear()}-01-01`, end_date: `${anchor.getUTCFullYear()}-12-31` }
      : { start_date: dateKey(dates[0]), end_date: dateKey(dates.at(-1)) };
    const mappedEmployees = currentEmployees.map((employee)=>{
      const entries = new Map(employee.entries.map((entry)=>[entry.date, calendarStatusPresentation(STATUS_MAP[entry.status], entry.status)]));
      return {
        id: employee.employee_id, name: employee.display_name, role: employee.role_title || "", team: employee.team_name || "",
        employmentStatus: employee.employment_status,
        statuses: dates.map((date)=>entries.get(dateKey(date)) || calendarStatusPresentation("no_data")),
      };
    });
    const dailyCapacity = dates.map((date, index)=>({
      date: dateKey(date),
      ...calendarCapacity(mappedEmployees.map((employee)=>employee.statuses[index])),
    }));
    const rangeLeaveQueue = currentLeaveQueue?.start_date === range.start_date && currentLeaveQueue?.end_date === range.end_date
      ? currentLeaveQueue : emptyOperatorLeaveQueue(range);
    return {
      view, anchor: dateKey(anchor), label: periodLabel(view, dates, anchor), dates: dates.map(dateKey), range,
      employees: mappedEmployees,
      summary: {
        totalEmployees: mappedEmployees.length,
        ...calendarCapacity(mappedEmployees.flatMap((employee)=>employee.statuses)),
      },
      dailyCapacity,
      leaveQueue: rangeLeaveQueue,
    };
  }
  return {
    snapshot,
    setView(nextView) { if (CALENDAR_VIEWS.has(nextView)) { view = nextView; currentLeaveQueue = null; } return snapshot(); },
    navigate(direction) {
      const amount = Number(direction) < 0 ? -1 : 1;
      if (view === "day") anchor = addDays(anchor, amount);
      else if (view === "week") anchor = addDays(anchor, amount * 7);
      else if (view === "month") anchor = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + amount, 1, 12));
      else anchor = new Date(Date.UTC(anchor.getUTCFullYear() + amount, anchor.getUTCMonth(), 1, 12));
      currentLeaveQueue = null;
      return snapshot();
    },
    goToday() { anchor = calendarDate(today()); currentLeaveQueue = null; return snapshot(); },
    openMonth(date) { anchor = calendarDate(date); view = "month"; currentLeaveQueue = null; return snapshot(); },
    replaceEmployees(nextEmployees) { currentEmployees = nextEmployees; return snapshot(); },
    replaceLeaveQueue(nextLeaveQueue) { currentLeaveQueue = nextLeaveQueue; return snapshot(); },
  };
}

export function createOperatorCalendarController({ model, load, loadLeaveRequests = (range)=>emptyOperatorLeaveQueue(range), onChange = ()=>{} }) {
  let loading = false;
  let error = null;
  let generation = 0;
  let pendingKey = null;
  let pendingPromise = null;
  let disposed = false;
  const state = ()=>({ ...model.snapshot(), loading, error });
  const notify = ()=>{ if (!disposed) onChange(state()); };
  async function reload({ background = false } = {}) {
    if (disposed) return false;
    const request = model.snapshot().range;
    const key = `${request.start_date}:${request.end_date}`;
    if (pendingKey === key && pendingPromise) return await pendingPromise;
    const requestGeneration = ++generation;
    if (!background) {
      loading = true;
      error = null;
      notify();
    }
    const task = (async ()=>{
      try {
        const [calendarValue, leaveValue] = await Promise.all([load(request), loadLeaveRequests(request)]);
        const result = operatorCalendarResponse(calendarValue, request);
        const leaveQueue = operatorLeaveQueueResponse(leaveValue, request);
        if (disposed || requestGeneration !== generation) return false;
        model.replaceEmployees(result.employees);
        model.replaceLeaveQueue(leaveQueue);
        loading = false;
        notify();
        return true;
      } catch {
        if (disposed || requestGeneration !== generation) return false;
        if (background) return false;
        loading = false;
        error = "Kalendergegevens konden niet worden geladen.";
        notify();
        return false;
      } finally {
        if (requestGeneration === generation) { pendingKey = null; pendingPromise = null; }
      }
    })();
    pendingKey = key;
    pendingPromise = task;
    return await task;
  }
  return {
    get state() { return state(); },
    reload,
    setView(view) { if (disposed) return false; model.setView(view); return reload(); },
    navigate(direction) { if (disposed) return false; model.navigate(direction); return reload(); },
    goToday() { if (disposed) return false; model.goToday(); return reload(); },
    openMonth(date) { if (disposed) return false; model.openMonth(date); return reload(); },
    dispose() { if (disposed) return; disposed = true; generation += 1; loading = false; pendingKey = null; pendingPromise = null; },
  };
}

export function initializeOperatorCalendar(root, client, identity, { onAuthorizationFailure = ()=>{} } = {}) {
  if (!root || !client?.rpc || !identity || !["owner", "admin", "operations_manager"].includes(identity.role)) {
    throw new Error("OPERATOR_CALENDAR_NOT_AUTHORIZED");
  }
  const viewport = root.getElementById("calendarViewport");
  if (!viewport) throw new Error("OPERATOR_CALENDAR_TEMPLATE_MISSING");
  if (viewport.operatorCalendarController) return viewport.operatorCalendarController;
  const panel = viewport.closest?.("[data-module-panel]");
  const periodLabel = root.getElementById("calendarPeriodLabel");
  const employeeCount = root.getElementById("calendarEmployeeCount");
  const empty = root.getElementById("calendarEmpty");
  const viewButtons = Array.from(root.querySelectorAll("[data-calendar-view]"));
  const emptyTitle = root.createElement("strong");
  const emptyDescription = root.createElement("p");
  emptyTitle.textContent = "Nog geen werknemersgegevens beschikbaar";
  emptyDescription.textContent = "De Kalender is klaar om personeelsplanning en afwezigheidsstatussen te tonen zodra medewerkers via de bevoegde personeelsflow beschikbaar zijn.";
  empty.replaceChildren(emptyTitle, emptyDescription);
  const emptyContent = Array.from(empty.childNodes);
  const listeners = new AbortController();
  const summarySection = root.createElement("section");
  const capacitySection = root.createElement("section");
  const detailSection = root.createElement("section");
  const employeeDetailSection = root.createElement("section");
  const summaryHeading = root.createElement("div");
  const summaryCards = root.createElement("div");
  const capacityHeading = root.createElement("div");
  const capacityGrid = root.createElement("div");
  const detailHeading = root.createElement("div");
  const detailContent = root.createElement("div");
  const detailClose = root.createElement("button");
  let selectedDate = null;
  let selectedEmployeeId = null;
  let payrollPreviewOpen = false;
  let leaveManagement = null;
  let controller;

  panel.querySelector(".calendar-heading p:last-child").textContent = "Personeelsplanning en afwezigheden";
  summarySection.className = "calendar-summary";
  summarySection.setAttribute("aria-labelledby", "calendarSummaryTitle");
  summaryHeading.className = "calendar-section-heading";
  summaryHeading.innerHTML = '<div><p class="eyebrow">Geselecteerde periode</p><h2 id="calendarSummaryTitle">Periodeoverzicht</h2></div><p>Zichtbare medewerker-dagen</p>';
  summaryCards.className = "calendar-summary-grid";
  summarySection.append(summaryHeading, summaryCards);
  capacitySection.className = "calendar-capacity";
  capacitySection.setAttribute("aria-labelledby", "calendarCapacityTitle");
  capacityHeading.className = "calendar-section-heading";
  capacityHeading.innerHTML = '<div><p class="eyebrow">Planning</p><h2 id="calendarCapacityTitle">Dagcapaciteit</h2></div>';
  capacityGrid.className = "calendar-capacity-grid";
  capacitySection.append(capacityHeading, capacityGrid);
  detailSection.className = "calendar-day-detail";
  detailSection.hidden = true;
  detailSection.setAttribute("aria-labelledby", "calendarDayDetailTitle");
  detailHeading.className = "calendar-day-detail__heading";
  detailClose.type = "button";
  detailClose.className = "calendar-day-detail__close";
  detailClose.setAttribute("aria-label", "Dagdetail sluiten");
  detailClose.title = "Sluiten";
  detailClose.textContent = "×";
  detailHeading.append(detailClose);
  detailContent.className = "calendar-day-detail__content";
  detailSection.append(detailHeading, detailContent);
  employeeDetailSection.className = "calendar-employee-detail";
  employeeDetailSection.hidden = true;
  employeeDetailSection.setAttribute("aria-labelledby", "calendarEmployeeDetailTitle");
  panel.querySelector(".calendar-legend").before(summarySection, capacitySection);
  viewport.after(detailSection);
  detailSection.after(employeeDetailSection);
  if (identity.role === "owner") {
    leaveManagement = initializeCalendarLeaveManagement({
      root,
      panel,
      before: summarySection,
      onDecide: (request, decision, managementNote)=>decideOperatorLeaveRequest(
        client,
        request,
        decision,
        managementNote,
        { onAuthorizationFailure },
      ),
      onRefresh: ()=>controller.reload({ background: true }),
    });
  }

  function renderSelectedDate() {
    for (const button of root.querySelectorAll("[data-calendar-date]")) {
      button.setAttribute("aria-pressed", String(selectedDate !== null && button.dataset.calendarDate === selectedDate));
    }
  }

  function renderSummary(state) {
    summarySection.dataset.calendarSummaryView = state.view;
    summaryHeading.lastElementChild.textContent = state.view === "year" ? "Alleen eerste dag per maand" : "Zichtbare medewerker-dagen";
    summaryCards.replaceChildren();
    for (const item of SUMMARY_ITEMS) {
      const card = root.createElement("article");
      const label = root.createElement("span");
      const value = root.createElement("strong");
      const unit = root.createElement("small");
      card.className = "calendar-summary-card";
      card.dataset.calendarSummary = item.key;
      label.textContent = item.label;
      value.textContent = String(state.summary[item.key]);
      unit.textContent = state.view === "year" && item.key !== "totalEmployees" ? "representatieve maanddagen" : item.unit;
      card.append(label, value, unit);
      summaryCards.append(card);
    }
  }

  function renderDayDetail(state, date) {
    const dateIndex = state.dates.indexOf(date);
    if (dateIndex < 0 || state.view === "year") {
      selectedDate = null;
      renderSelectedDate();
      detailSection.hidden = true;
      return;
    }
    selectedDate = date;
    renderSelectedDate();
    const capacity = state.dailyCapacity[dateIndex];
    const title = root.createElement("div");
    const eyebrow = root.createElement("p");
    const heading = root.createElement("h2");
    eyebrow.className = "eyebrow";
    eyebrow.textContent = "Dagdetail · read-only";
    heading.id = "calendarDayDetailTitle";
    heading.textContent = new Intl.DateTimeFormat("nl-BE", { weekday: "long", day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).format(calendarDate(date));
    title.append(eyebrow, heading);
    detailHeading.replaceChildren(title, detailClose);
    detailContent.replaceChildren();
    const totals = root.createElement("dl");
    totals.className = "calendar-day-detail__totals";
    const detailItems = [
      ["Totaal medewerkers", state.summary.totalEmployees], ["Gewerkt", capacity.worked], ["Verlof", capacity.leave],
      ["Ziek", capacity.sick], ["Andere afwezigheid", capacity.otherAbsence], ["Geen data", capacity.noData],
    ];
    for (const [label, value] of detailItems) {
      const item = root.createElement("div");
      const term = root.createElement("dt");
      const definition = root.createElement("dd");
      term.textContent = label;
      definition.textContent = String(value);
      item.append(term, definition);
      totals.append(item);
    }
    const list = root.createElement("ul");
    list.className = "calendar-day-detail__employees";
    for (const employee of state.employees) {
      const item = root.createElement("li");
      const identity = root.createElement("span");
      const name = root.createElement("strong");
      const metadata = root.createElement("small");
      const status = employee.statuses[dateIndex];
      const marker = root.createElement("span");
      name.textContent = employee.name;
      metadata.textContent = [employee.role, employee.team].filter(Boolean).join(" / ");
      identity.append(name, metadata);
      marker.className = "calendar-status calendar-day-detail__status";
      marker.dataset.calendarStatus = status.key;
      marker.title = status.label;
      marker.setAttribute("aria-label", `${employee.name}: ${status.label}`);
      marker.textContent = status.icon;
      item.append(identity, marker);
      list.append(item);
    }
    if (!state.employees.length) {
      const item = root.createElement("li");
      item.className = "calendar-day-detail__empty";
      item.textContent = "Geen werknemersgegevens voor deze datum.";
      list.append(item);
    }
    detailContent.append(totals, list);
    detailSection.hidden = false;
  }

  function closeEmployeeDetail({ restoreFocus = false } = {}) {
    const employeeId = selectedEmployeeId;
    selectedEmployeeId = null;
    payrollPreviewOpen = false;
    employeeDetailSection.hidden = true;
    employeeDetailSection.replaceChildren();
    if (restoreFocus && employeeId) viewport.querySelector(`[data-calendar-employee-id="${employeeId}"]`)?.focus();
  }

  function renderPayrollPreview(state, employeeId, { focus = false } = {}) {
    const preview = calendarPayrollInputPreview(state, employeeId);
    if (!preview) {
      closeEmployeeDetail();
      return;
    }
    employeeDetailSection.querySelector(".calendar-payroll-preview")?.remove();
    const section = root.createElement("section");
    const heading = root.createElement("header");
    const identity = root.createElement("div");
    const eyebrow = root.createElement("p");
    const title = root.createElement("h3");
    const metadata = root.createElement("p");
    const period = root.createElement("p");
    const close = root.createElement("button");
    section.className = "calendar-payroll-preview";
    section.setAttribute("aria-labelledby", "calendarPayrollPreviewTitle");
    heading.className = "calendar-payroll-preview__heading";
    eyebrow.className = "eyebrow";
    eyebrow.textContent = "Loonvoorbereiding · read-only";
    title.id = "calendarPayrollPreviewTitle";
    title.textContent = preview.employee.name;
    metadata.className = "calendar-payroll-preview__metadata";
    metadata.textContent = [preview.employee.role, preview.employee.team].filter(Boolean).join(" / ") || "Geen functie of team beschikbaar";
    period.className = "calendar-payroll-preview__period";
    period.textContent = `Periode: ${preview.periodLabel}`;
    identity.append(eyebrow, title, metadata, period);
    close.type = "button";
    close.className = "calendar-payroll-preview__close";
    close.setAttribute("aria-label", "Loonvoorbereiding sluiten");
    close.title = "Sluiten";
    close.textContent = "×";
    close.addEventListener("click", ()=>{
      payrollPreviewOpen = false;
      renderEmployeeDetail(state, employeeId);
      employeeDetailSection.querySelector(".calendar-employee-detail__payroll-action")?.focus();
    }, { signal: listeners.signal });
    heading.append(identity, close);
    section.append(heading);
    if (!preview.available) {
      const notice = root.createElement("p");
      notice.className = "calendar-payroll-preview__notice";
      notice.textContent = preview.message;
      section.append(notice);
      employeeDetailSection.append(section);
      if (focus) close.focus();
      return;
    }
    const status = root.createElement("div");
    const statusLabel = root.createElement("span");
    const statusValue = root.createElement("strong");
    const statusMessage = root.createElement("p");
    status.className = "calendar-payroll-preview__status";
    status.dataset.calendarPayrollCompleteness = preview.completeness;
    statusLabel.textContent = "Status";
    statusValue.textContent = preview.completeness;
    statusMessage.textContent = preview.completenessMessage;
    status.append(statusLabel, statusValue, statusMessage);
    if (preview.incompleteDays.length) {
      const incompleteList = root.createElement("ul");
      incompleteList.className = "calendar-payroll-preview__incomplete-days";
      for (const date of preview.incompleteDays) {
        const item = root.createElement("li");
        item.textContent = new Intl.DateTimeFormat("nl-BE", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC" }).format(calendarDate(date));
        incompleteList.append(item);
      }
      status.append(incompleteList);
    }
    const summary = root.createElement("dl");
    summary.className = "calendar-payroll-preview__summary";
    for (const [label, value] of [
      ["Volledige werkdagen", preview.totals.fullDay],
      ["Halve dag voormiddag", preview.totals.halfDayAm],
      ["Halve dag namiddag", preview.totals.halfDayPm],
      ["Verlof", preview.totals.leave],
      ["Ziek", preview.totals.sick],
      ["Andere afwezigheid", preview.totals.otherAbsence],
      ["Geen planning / geen data", preview.totals.noData],
    ]) {
      const item = root.createElement("div");
      const term = root.createElement("dt");
      const definition = root.createElement("dd");
      term.textContent = label;
      definition.textContent = String(value);
      item.append(term, definition);
      summary.append(item);
    }
    const hours = root.createElement("p");
    hours.className = "calendar-payroll-preview__hours";
    hours.textContent = "Gewerkte uren nog niet beschikbaar vanuit de huidige gegevensbron.";
    const tableRegion = root.createElement("div");
    const tableTitle = root.createElement("h4");
    const tableViewport = root.createElement("div");
    const table = root.createElement("table");
    const tableHead = root.createElement("thead");
    const headerRow = root.createElement("tr");
    for (const label of ["Datum", "Status", "Uren", "Bronstatus", "Controle"]) {
      const header = root.createElement("th");
      header.scope = "col";
      header.textContent = label;
      headerRow.append(header);
    }
    tableHead.append(headerRow);
    table.append(tableHead);
    const tableBody = root.createElement("tbody");
    for (const line of preview.dayLines) {
      const row = root.createElement("tr");
      const values = [
        new Intl.DateTimeFormat("nl-BE", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC" }).format(calendarDate(line.date)),
        line.status.label,
        "—",
        line.sourceStatus,
        line.control,
      ];
      for (const [index, value] of values.entries()) {
        const cell = root.createElement(index === 0 ? "th" : "td");
        if (index === 0) cell.scope = "row";
        cell.textContent = value;
        if (index === 4) cell.dataset.calendarPayrollControl = line.control;
        row.append(cell);
      }
      tableBody.append(row);
    }
    table.append(tableBody);
    tableRegion.className = "calendar-payroll-preview__lines";
    tableTitle.textContent = "Dagen in deze periode";
    tableViewport.className = "calendar-payroll-preview__table-viewport";
    tableViewport.append(table);
    tableRegion.append(tableTitle, tableViewport);
    const identityNote = root.createElement("p");
    identityNote.className = "calendar-payroll-preview__identity-note";
    identityNote.textContent = `Technische referentie: employee_id ${preview.employee.id}. Vast personeelsnummer: nog niet beschikbaar; toekomstig centraal identity-contract vereist.`;
    section.append(status, summary, hours, tableRegion, identityNote);
    employeeDetailSection.append(section);
    if (focus) {
      close.focus();
      section.scrollIntoView({ block: "nearest" });
    }
  }

  function renderEmployeeDetail(state, employeeId, { focus = false } = {}) {
    const detail = calendarEmployeePeriodDetail(state, employeeId);
    if (!detail) {
      closeEmployeeDetail();
      return;
    }
    selectedEmployeeId = employeeId;
    employeeDetailSection.replaceChildren();
    const heading = root.createElement("header");
    const identity = root.createElement("div");
    const eyebrow = root.createElement("p");
    const title = root.createElement("h2");
    const metadata = root.createElement("p");
    const period = root.createElement("p");
    const close = root.createElement("button");
    heading.className = "calendar-employee-detail__heading";
    eyebrow.className = "eyebrow";
    eyebrow.textContent = "Werknemerdetail · read-only";
    title.id = "calendarEmployeeDetailTitle";
    title.textContent = detail.employee.name;
    metadata.className = "calendar-employee-detail__metadata";
    metadata.textContent = [detail.employee.role, detail.employee.team].filter(Boolean).join(" / ") || "Geen functie of team beschikbaar";
    period.className = "calendar-employee-detail__period";
    period.textContent = `Periode: ${detail.periodLabel}`;
    identity.append(eyebrow, title, metadata, period);
    close.type = "button";
    close.className = "calendar-employee-detail__close";
    close.setAttribute("aria-label", "Werknemerdetail sluiten");
    close.title = "Sluiten";
    close.textContent = "×";
    close.addEventListener("click", ()=>closeEmployeeDetail({ restoreFocus: true }), { signal: listeners.signal });
    heading.append(identity, close);
    employeeDetailSection.append(heading);
    if (!detail.available) {
      const notice = root.createElement("p");
      notice.className = "calendar-employee-detail__notice";
      notice.textContent = detail.message;
      employeeDetailSection.append(notice);
      employeeDetailSection.hidden = false;
      if (payrollPreviewOpen) renderPayrollPreview(state, employeeId);
      if (focus) close.focus();
      return;
    }
    const summary = root.createElement("dl");
    summary.className = "calendar-employee-detail__summary";
    const summaryItems = [
      ["Totaal kalenderdagen zichtbaar", detail.totals.visibleDays],
      ["Volledige werkdagen", detail.totals.fullDay],
      ["Halve dag voormiddag", detail.totals.halfDayAm],
      ["Halve dag namiddag", detail.totals.halfDayPm],
      ["Verlof", detail.totals.leave],
      ["Ziek", detail.totals.sick],
      ["Andere afwezigheid", detail.totals.otherAbsence],
      ["Geen planning / geen data", detail.totals.noData],
    ];
    for (const [label, value] of summaryItems) {
      const item = root.createElement("div");
      const term = root.createElement("dt");
      const definition = root.createElement("dd");
      term.textContent = label;
      definition.textContent = String(value);
      item.append(term, definition);
      summary.append(item);
    }
    const hours = root.createElement("p");
    hours.className = "calendar-employee-detail__hours";
    hours.innerHTML = "<strong>Gewerkte uren:</strong> nog niet beschikbaar";
    const historyRegion = root.createElement("div");
    const historyTitle = root.createElement("h3");
    const historyViewport = root.createElement("div");
    const table = root.createElement("table");
    const tableHead = root.createElement("thead");
    const headerRow = root.createElement("tr");
    for (const label of ["Datum", "Status", "Uren/info"]) {
      const header = root.createElement("th");
      header.scope = "col";
      header.textContent = label;
      headerRow.append(header);
    }
    tableHead.append(headerRow);
    table.append(tableHead);
    const tableBody = root.createElement("tbody");
    for (const item of detail.history) {
      const row = root.createElement("tr");
      const date = root.createElement("th");
      const statusCell = root.createElement("td");
      const info = root.createElement("td");
      const marker = root.createElement("span");
      date.scope = "row";
      date.textContent = new Intl.DateTimeFormat("nl-BE", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC" }).format(calendarDate(item.date));
      marker.className = "calendar-employee-detail__history-status";
      marker.dataset.calendarStatus = item.status.key;
      marker.title = item.status.label;
      marker.setAttribute("aria-label", item.status.label);
      marker.textContent = item.status.label;
      statusCell.append(marker);
      info.textContent = item.info;
      row.append(date, statusCell, info);
      tableBody.append(row);
    }
    table.append(tableBody);
    historyRegion.className = "calendar-employee-detail__history";
    historyTitle.textContent = "Daghistoriek";
    historyViewport.className = "calendar-employee-detail__history-viewport";
    historyViewport.append(table);
    historyRegion.append(historyTitle, historyViewport);
    const payroll = root.createElement("aside");
    const payrollTitle = root.createElement("h3");
    const payrollText = root.createElement("p");
    const payrollAction = root.createElement("button");
    payroll.className = "calendar-employee-detail__payroll";
    payrollTitle.textContent = "Loonvoorbereiding";
    payrollText.textContent = "Deze kalendergegevens kunnen later als input dienen voor de bevoegde payrollflow.";
    payrollAction.type = "button";
    payrollAction.className = "secondary-action calendar-employee-detail__payroll-action";
    payrollAction.textContent = "Bekijk loonvoorbereiding";
    payrollAction.addEventListener("click", ()=>{
      payrollPreviewOpen = true;
      renderPayrollPreview(state, employeeId, { focus: true });
    }, { signal: listeners.signal });
    payroll.append(payrollTitle, payrollText, payrollAction);
    employeeDetailSection.append(summary, hours, historyRegion, payroll);
    employeeDetailSection.hidden = false;
    if (payrollPreviewOpen) renderPayrollPreview(state, employeeId);
    if (focus) {
      close.focus();
      employeeDetailSection.scrollIntoView({ block: "nearest" });
    }
  }

  function renderCapacity(state) {
    const visible = state.view === "week" || state.view === "month" || state.view === "year";
    capacitySection.hidden = !visible;
    capacityGrid.replaceChildren();
    if (!visible) return;
    capacitySection.dataset.calendarCapacityView = state.view;
    capacityHeading.querySelector("h2").textContent = state.view === "year" ? "Maandnavigatie" : "Dagcapaciteit";
    for (const [index, capacity] of state.dailyCapacity.entries()) {
      const button = root.createElement("button");
      const date = state.dates[index];
      const label = root.createElement("strong");
      button.type = "button";
      button.className = "calendar-capacity-day";
      if (state.view === "year") {
        const monthLabel = new Intl.DateTimeFormat("nl-BE", { month: "long", timeZone: "UTC" }).format(calendarDate(date));
        label.textContent = monthLabel;
        button.setAttribute("aria-label", `${monthLabel} openen`);
        const hint = root.createElement("span");
        hint.textContent = "Open maand";
        button.append(label, hint);
        button.addEventListener("click", ()=>{ selectedDate = null; void controller.openMonth(date); });
      } else {
        button.dataset.calendarDate = date;
        button.setAttribute("aria-pressed", String(date === selectedDate));
        label.textContent = new Intl.DateTimeFormat("nl-BE", { weekday: "short", day: "numeric", timeZone: "UTC" }).format(calendarDate(date));
        button.setAttribute("aria-label", `Dagdetail openen voor ${label.textContent}`);
        const worked = root.createElement("span");
        const absence = root.createElement("span");
        const noData = root.createElement("span");
        worked.textContent = `${capacity.worked} gewerkt`;
        absence.textContent = `${capacity.leave} verlof · ${capacity.sick} ziek`;
        noData.textContent = `${capacity.otherAbsence} ander · ${capacity.noData} geen data`;
        button.append(label, worked, absence, noData);
        button.addEventListener("click", ()=>renderDayDetail(state, date));
        if (state.view === "month" && index === 0) button.style.gridColumnStart = String(((calendarDate(date).getUTCDay() + 6) % 7) + 1);
      }
      capacityGrid.append(button);
    }
  }

  function render(state = controller.state) {
    periodLabel.textContent = state.label;
    employeeCount.textContent = `${state.employees.length} ${state.employees.length === 1 ? "werknemer" : "werknemers"}`;
    empty.hidden = state.employees.length > 0 && !state.error;
    if (state.error || state.loading) empty.textContent = state.error || "Kalendergegevens laden...";
    else empty.replaceChildren(...emptyContent);
    viewport.setAttribute("aria-busy", String(state.loading));
    for (const button of viewButtons) button.setAttribute("aria-pressed", String(button.dataset.calendarView === state.view));
    renderSummary(state);
    renderCapacity(state);
    leaveManagement?.render(state.leaveQueue);
    if (selectedDate) renderDayDetail(state, selectedDate);
    if (selectedEmployeeId) renderEmployeeDetail(state, selectedEmployeeId);
    viewport.replaceChildren();
    const table = root.createElement("table");
    const head = root.createElement("thead");
    const headerRow = root.createElement("tr");
    const employeeHeader = root.createElement("th");
    employeeHeader.scope = "col";
    employeeHeader.textContent = "Werknemer";
    headerRow.append(employeeHeader);
    for (const date of state.dates) {
      const header = root.createElement("th");
      header.scope = "col";
      const dateLabel = state.view === "year"
        ? new Intl.DateTimeFormat("nl-BE", { month: "short", timeZone: "UTC" }).format(calendarDate(date))
        : new Intl.DateTimeFormat("nl-BE", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(calendarDate(date));
      if (state.view === "year") header.textContent = dateLabel;
      else {
        const button = root.createElement("button");
        button.type = "button";
        button.className = "calendar-date-trigger";
        button.dataset.calendarDate = date;
        button.textContent = dateLabel;
        button.setAttribute("aria-label", `Dagdetail openen voor ${dateLabel}`);
        button.setAttribute("aria-pressed", String(date === selectedDate));
        button.addEventListener("click", ()=>renderDayDetail(state, date));
        header.append(button);
      }
      headerRow.append(header);
    }
    head.append(headerRow);
    table.append(head);
    const body = root.createElement("tbody");
    for (const employee of state.employees) {
      const row = root.createElement("tr");
      const nameCell = root.createElement("th");
      nameCell.scope = "row";
      const employeeButton = root.createElement("button");
      const name = root.createElement("strong");
      const detail = root.createElement("span");
      employeeButton.type = "button";
      employeeButton.className = "calendar-employee-trigger";
      employeeButton.dataset.calendarEmployeeId = employee.id;
      employeeButton.setAttribute("aria-label", `${employee.name} openen voor ${state.label}`);
      name.textContent = employee.name;
      detail.textContent = [employee.role, employee.team].filter(Boolean).join(" / ");
      employeeButton.append(name, detail);
      employeeButton.addEventListener("click", ()=>renderEmployeeDetail(state, employee.id, { focus: true }));
      nameCell.append(employeeButton);
      row.append(nameCell);
      for (const status of employee.statuses) {
        const cell = root.createElement("td");
        const marker = root.createElement("span");
        marker.className = "calendar-status";
        marker.dataset.calendarStatus = status.key;
        marker.title = status.label;
        marker.setAttribute("aria-label", status.label);
        marker.textContent = status.icon;
        cell.append(marker);
        row.append(cell);
      }
      body.append(row);
    }
    table.append(body);
    viewport.append(table);
  }

  const load = async (range)=>{
    const { data, error } = await client.rpc("get_operator_calendar_v1", { p_start_date: range.start_date, p_end_date: range.end_date });
    if (error) {
      if (error.code === "42501") onAuthorizationFailure(error);
      throw error;
    }
    return data;
  };
  const loadLeaveRequests = identity.role === "owner"
    ? (range)=>loadOperatorLeaveQueue(client, range, { onAuthorizationFailure })
    : (range)=>emptyOperatorLeaveQueue(range);
  controller = createOperatorCalendarController({
    model: createOperatorCalendarModel(),
    load,
    loadLeaveRequests,
    onChange: render,
  });
  const heartbeat = createOperatorRefreshHeartbeat({ root, moduleKey: "calendar", titleElement: root.getElementById("calendarModuleTitle") });
  const autoRefresh = createOperatorAutoRefresh({
    moduleKey: "calendar",
    refresh: ()=>controller.reload({ background: true }),
    isActive: ()=>!panel?.hidden,
    documentTarget: root,
    windowTarget: root.defaultView,
    onLifecycle: heartbeat.update,
  });
  const signal = listeners.signal;
  for (const button of viewButtons) button.addEventListener("click", ()=>{ void controller.setView(button.dataset.calendarView); }, { signal });
  root.getElementById("calendarPrevious").addEventListener("click", ()=>{ void controller.navigate(-1); }, { signal });
  root.getElementById("calendarNext").addEventListener("click", ()=>{ void controller.navigate(1); }, { signal });
  root.getElementById("calendarToday").addEventListener("click", ()=>{ void controller.goToday(); }, { signal });
  detailClose.addEventListener("click", ()=>{ selectedDate = null; renderSelectedDate(); detailSection.hidden = true; }, { signal });
  root.addEventListener("keydown", (event)=>{
    if (event.key !== "Escape" || employeeDetailSection.hidden) return;
    if (payrollPreviewOpen) {
      payrollPreviewOpen = false;
      renderEmployeeDetail(controller.state, selectedEmployeeId);
      employeeDetailSection.querySelector(".calendar-employee-detail__payroll-action")?.focus();
    } else closeEmployeeDetail({ restoreFocus: true });
  }, { signal });
  const dispose = controller.dispose.bind(controller);
  controller.dispose = ()=>{ autoRefresh.dispose(); heartbeat.dispose(); leaveManagement?.dispose(); listeners.abort(); dispose(); delete viewport.operatorCalendarController; };
  viewport.operatorCalendarController = controller;
  render();
  void controller.reload();
  return controller;
}

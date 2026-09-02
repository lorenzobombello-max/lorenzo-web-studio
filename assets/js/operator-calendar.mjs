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

export function calendarStatusPresentation(status) {
  const key = Object.hasOwn(CALENDAR_STATUSES, status) ? status : "no_data";
  return { key, ...CALENDAR_STATUSES[key] };
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

export function createOperatorCalendarModel({ today = ()=>new Date(), employees = [], initialView = "week" } = {}) {
  let view = CALENDAR_VIEWS.has(initialView) ? initialView : "week";
  let anchor = calendarDate(today());
  let currentEmployees = employees;
  function snapshot() {
    const dates = periodDates(view, anchor);
    const range = view === "year"
      ? { start_date: `${anchor.getUTCFullYear()}-01-01`, end_date: `${anchor.getUTCFullYear()}-12-31` }
      : { start_date: dateKey(dates[0]), end_date: dateKey(dates.at(-1)) };
    return {
      view, anchor: dateKey(anchor), label: periodLabel(view, dates, anchor), dates: dates.map(dateKey), range,
      employees: currentEmployees.map((employee)=>{
        const entries = new Map(employee.entries.map((entry)=>[entry.date, calendarStatusPresentation(STATUS_MAP[entry.status])]));
        return {
          id: employee.employee_id, name: employee.display_name, role: employee.role_title || "", team: employee.team_name || "",
          employmentStatus: employee.employment_status,
          statuses: dates.map((date)=>entries.get(dateKey(date)) || calendarStatusPresentation("no_data")),
        };
      }),
    };
  }
  return {
    snapshot,
    setView(nextView) { if (CALENDAR_VIEWS.has(nextView)) view = nextView; return snapshot(); },
    navigate(direction) {
      const amount = Number(direction) < 0 ? -1 : 1;
      if (view === "day") anchor = addDays(anchor, amount);
      else if (view === "week") anchor = addDays(anchor, amount * 7);
      else if (view === "month") anchor = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + amount, 1, 12));
      else anchor = new Date(Date.UTC(anchor.getUTCFullYear() + amount, anchor.getUTCMonth(), 1, 12));
      return snapshot();
    },
    goToday() { anchor = calendarDate(today()); return snapshot(); },
    replaceEmployees(nextEmployees) { currentEmployees = nextEmployees; return snapshot(); },
  };
}

export function createOperatorCalendarController({ model, load, onChange = ()=>{} }) {
  let loading = false;
  let error = null;
  let generation = 0;
  let pendingKey = null;
  let pendingPromise = null;
  let disposed = false;
  const state = ()=>({ ...model.snapshot(), loading, error });
  const notify = ()=>{ if (!disposed) onChange(state()); };
  async function reload() {
    if (disposed) return false;
    const request = model.snapshot().range;
    const key = `${request.start_date}:${request.end_date}`;
    if (pendingKey === key && pendingPromise) return await pendingPromise;
    const requestGeneration = ++generation;
    loading = true;
    error = null;
    notify();
    const task = (async ()=>{
      try {
        const result = operatorCalendarResponse(await load(request), request);
        if (disposed || requestGeneration !== generation) return false;
        model.replaceEmployees(result.employees);
        loading = false;
        notify();
        return true;
      } catch {
        if (disposed || requestGeneration !== generation) return false;
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
  const periodLabel = root.getElementById("calendarPeriodLabel");
  const employeeCount = root.getElementById("calendarEmployeeCount");
  const empty = root.getElementById("calendarEmpty");
  const viewButtons = Array.from(root.querySelectorAll("[data-calendar-view]"));
  const emptyContent = Array.from(empty.childNodes);
  const listeners = new AbortController();
  let controller;

  function render(state = controller.state) {
    periodLabel.textContent = state.label;
    employeeCount.textContent = `${state.employees.length} ${state.employees.length === 1 ? "werknemer" : "werknemers"}`;
    empty.hidden = state.employees.length > 0 && !state.error;
    if (state.error || state.loading) empty.textContent = state.error || "Kalendergegevens laden...";
    else empty.replaceChildren(...emptyContent);
    viewport.setAttribute("aria-busy", String(state.loading));
    for (const button of viewButtons) button.setAttribute("aria-pressed", String(button.dataset.calendarView === state.view));
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
      header.textContent = state.view === "year"
        ? new Intl.DateTimeFormat("nl-BE", { month: "short", timeZone: "UTC" }).format(calendarDate(date))
        : new Intl.DateTimeFormat("nl-BE", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(calendarDate(date));
      headerRow.append(header);
    }
    head.append(headerRow);
    table.append(head);
    const body = root.createElement("tbody");
    for (const employee of state.employees) {
      const row = root.createElement("tr");
      const nameCell = root.createElement("th");
      nameCell.scope = "row";
      const name = root.createElement("strong");
      const detail = root.createElement("span");
      name.textContent = employee.name;
      detail.textContent = [employee.role, employee.team].filter(Boolean).join(" / ");
      nameCell.append(name, detail);
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
  controller = createOperatorCalendarController({ model: createOperatorCalendarModel(), load, onChange: render });
  const signal = listeners.signal;
  for (const button of viewButtons) button.addEventListener("click", ()=>{ void controller.setView(button.dataset.calendarView); }, { signal });
  root.getElementById("calendarPrevious").addEventListener("click", ()=>{ void controller.navigate(-1); }, { signal });
  root.getElementById("calendarNext").addEventListener("click", ()=>{ void controller.navigate(1); }, { signal });
  root.getElementById("calendarToday").addEventListener("click", ()=>{ void controller.goToday(); }, { signal });
  const dispose = controller.dispose.bind(controller);
  controller.dispose = ()=>{ listeners.abort(); dispose(); delete viewport.operatorCalendarController; };
  viewport.operatorCalendarController = controller;
  render();
  void controller.reload();
  return controller;
}

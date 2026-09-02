const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const AUTHORIZED_ROLES = new Set(["owner", "admin", "operations_manager"]);
const EMPLOYEE_KEYS = Object.freeze(["employee_id", "display_name", "role_title", "team_name", "employment_status", "start_date"]);
const AUTHORIZATION_MESSAGES = /HUMAN_JWT_REQUIRED|OPERATOR_NOT_ACTIVE|WORKFORCE_MANAGEMENT_READER_REQUIRED|WORKSPACE_MODULE_NOT_AUTHORIZED/;

function exactKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every((key)=>Object.hasOwn(value, key));
}

function authorizationFailure(error) {
  return error?.code === "42501" || AUTHORIZATION_MESSAGES.test(String(error?.message || ""));
}

export function operatorWorkforceResponse(value) {
  if (!exactKeys(value, ["employees"]) || !Array.isArray(value.employees)) {
    throw new Error("INVALID_OPERATOR_WORKFORCE_RESPONSE");
  }
  for (const employee of value.employees) {
    if (!exactKeys(employee, EMPLOYEE_KEYS)
      || !UUID.test(employee.employee_id)
      || typeof employee.display_name !== "string" || !employee.display_name
      || (employee.role_title !== null && typeof employee.role_title !== "string")
      || (employee.team_name !== null && typeof employee.team_name !== "string")
      || !["ACTIVE", "INACTIVE"].includes(employee.employment_status)
      || typeof employee.start_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(employee.start_date)) {
      throw new Error("INVALID_OPERATOR_WORKFORCE_RESPONSE");
    }
  }
  return value;
}

export async function loadOperatorWorkforce(client, { onAuthorizationFailure = ()=>{} } = {}) {
  if (!client?.rpc) throw new TypeError("WORKFORCE_CLIENT_REQUIRED");
  const { data, error } = await client.rpc("list_operator_workforce_v1", {});
  if (error) {
    if (authorizationFailure(error)) onAuthorizationFailure(error);
    throw error;
  }
  return operatorWorkforceResponse(data);
}

export function createOperatorWorkforceController({ load, onChange = ()=>{} }) {
  let items = [];
  let loading = false;
  let error = null;
  let generation = 0;
  let disposed = false;
  const state = ()=>({ items: [...items], loading, error });
  const notify = ()=>{ if (!disposed) onChange(state()); };
  async function refresh() {
    if (disposed) return false;
    const requestGeneration = ++generation;
    loading = true;
    error = null;
    notify();
    try {
      const response = operatorWorkforceResponse(await load());
      if (disposed || requestGeneration !== generation) return false;
      items = response.employees;
      loading = false;
      notify();
      return true;
    } catch {
      if (disposed || requestGeneration !== generation) return false;
      loading = false;
      error = "Personeelsgegevens konden niet worden geladen.";
      notify();
      return false;
    }
  }
  return {
    get state() { return state(); },
    refresh,
    dispose() {
      if (disposed) return;
      disposed = true;
      generation += 1;
      items = [];
      loading = false;
      error = null;
    },
  };
}

function workforceDate(value) {
  return new Intl.DateTimeFormat("nl-BE", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(`${value}T12:00:00Z`));
}

export function initializeOperatorWorkforce(root, client, identity, { onAuthorizationFailure = ()=>{} } = {}) {
  if (!root || !client?.rpc || !AUTHORIZED_ROLES.has(identity?.role)) throw new Error("WORKFORCE_MANAGEMENT_READER_REQUIRED");
  const list = root.getElementById("workforceEmployeeList");
  if (!list) throw new Error("OPERATOR_WORKFORCE_TEMPLATE_MISSING");
  if (list.operatorWorkforceController) return list.operatorWorkforceController;
  const listeners = new AbortController();
  const count = root.getElementById("workforceEmployeeCount");
  const message = root.getElementById("workforceMessage");
  const empty = root.getElementById("workforceEmpty");
  let disposed = false;
  let controller;

  function render(state = controller.state) {
    if (disposed) return;
    count.textContent = `${state.items.length} ${state.items.length === 1 ? "medewerker" : "medewerkers"}`;
    message.textContent = state.error || (state.loading ? "Personeelsgegevens laden..." : "");
    list.setAttribute("aria-busy", String(state.loading));
    list.replaceChildren();
    for (const employee of state.items) {
      const item = root.createElement("li");
      const heading = root.createElement("div");
      const name = root.createElement("h2");
      const status = root.createElement("span");
      const details = root.createElement("dl");
      item.className = "workforce-employee-item";
      heading.className = "workforce-employee-item__heading";
      name.textContent = employee.display_name;
      status.className = "badge";
      status.dataset.employmentStatus = employee.employment_status;
      status.textContent = employee.employment_status === "ACTIVE" ? "ACTIEF" : "INACTIEF";
      for (const [label, value] of [
        ["Functie", employee.role_title || "Niet vastgelegd"],
        ["Team", employee.team_name || "Niet vastgelegd"],
        ["Startdatum", workforceDate(employee.start_date)],
      ]) {
        const group = root.createElement("div");
        const term = root.createElement("dt");
        const definition = root.createElement("dd");
        term.textContent = label;
        definition.textContent = value;
        group.append(term, definition);
        details.append(group);
      }
      heading.append(name, status);
      item.append(heading, details);
      list.append(item);
    }
    empty.hidden = state.loading || state.items.length > 0 || Boolean(state.error);
  }

  controller = createOperatorWorkforceController({
    load: ()=>loadOperatorWorkforce(client, { onAuthorizationFailure }),
    onChange: render,
  });
  root.getElementById("workforceRefresh").addEventListener("click", ()=>{ void controller.refresh(); }, { signal: listeners.signal });
  const dispose = controller.dispose.bind(controller);
  controller.dispose = ()=>{
    if (disposed) return;
    disposed = true;
    listeners.abort();
    dispose();
    delete list.operatorWorkforceController;
  };
  list.operatorWorkforceController = controller;
  render();
  void controller.refresh();
  return controller;
}
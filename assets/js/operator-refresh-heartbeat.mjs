const STATES = new Set(["idle", "refreshing", "success", "error", "stale"]);
const LABELS = Object.freeze({
  idle: "Wachten op verversing",
  refreshing: "Verversen",
  success: "Actueel",
  error: "Verversen mislukt",
  stale: "Mogelijk verouderd",
});

function heartbeatIcon(root) {
  const namespace = "http://www.w3.org/2000/svg";
  const svg = root.createElementNS(namespace, "svg");
  const path = root.createElementNS(namespace, "path");
  svg.setAttribute("viewBox", "0 0 36 16");
  svg.setAttribute("aria-hidden", "true");
  svg.classList.add("operator-refresh-heartbeat__icon");
  path.setAttribute("d", "M1 8h7l3-6 5 12 5-10 4 8 3-4h7");
  path.setAttribute("pathLength", "1");
  svg.append(path);
  return svg;
}

export function createOperatorRefreshHeartbeat({
  root = globalThis.document,
  moduleKey,
  titleElement,
}) {
  if (!root?.createElement || !root?.createElementNS || typeof moduleKey !== "string" || !moduleKey
    || !titleElement?.parentElement) {
    throw new TypeError("INVALID_OPERATOR_REFRESH_HEARTBEAT");
  }
  const existing = titleElement.parentElement.querySelector?.(`[data-operator-refresh-heartbeat="${moduleKey}"]`);
  if (existing?.operatorRefreshHeartbeat) return existing.operatorRefreshHeartbeat;

  const heading = root.createElement("span");
  const indicator = root.createElement("span");
  const label = root.createElement("span");
  let disposed = false;

  heading.className = "operator-refresh-heading";
  indicator.className = "operator-refresh-heartbeat";
  indicator.dataset.operatorRefreshHeartbeat = moduleKey;
  indicator.setAttribute("role", "status");
  indicator.setAttribute("aria-live", "polite");
  label.className = "operator-refresh-heartbeat__label";
  indicator.append(heartbeatIcon(root), label);
  titleElement.before(heading);
  heading.append(titleElement, indicator);

  function update(event) {
    if (disposed || event?.moduleKey !== moduleKey || !STATES.has(event?.state)) return;
    indicator.dataset.state = event.state;
    label.textContent = LABELS[event.state];
  }

  function dispose() {
    if (disposed) return;
    disposed = true;
    heading.before(titleElement);
    heading.remove();
  }

  const controller = Object.freeze({ update, dispose });
  indicator.operatorRefreshHeartbeat = controller;
  update({ moduleKey, state: "idle" });
  return controller;
}

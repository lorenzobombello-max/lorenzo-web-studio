const STATES = new Set(["idle", "refreshing", "success", "error", "stale"]);
const DEFERRED_STATES = new Set(["success", "error"]);
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
  const icon = heartbeatIcon(root);
  const path = icon.children[0];
  let disposed = false;
  let animationCompleted = false;
  let pendingState = null;

  heading.className = "operator-refresh-heading";
  indicator.className = "operator-refresh-heartbeat";
  indicator.dataset.operatorRefreshHeartbeat = moduleKey;
  indicator.setAttribute("role", "status");
  indicator.setAttribute("aria-live", "polite");
  label.className = "operator-refresh-heartbeat__label";
  indicator.append(icon, label);
  titleElement.before(heading);
  heading.append(titleElement, indicator);

  function present(state) {
    indicator.dataset.state = state;
    label.textContent = LABELS[state];
  }

  function animationFinished(event) {
    if (disposed || event?.target !== path || event?.animationName !== "operator-heartbeat-flow") return;
    animationCompleted = true;
    if (!pendingState) return;
    const state = pendingState;
    pendingState = null;
    present(state);
  }

  function update(event) {
    if (disposed || event?.moduleKey !== moduleKey || !STATES.has(event?.state)) return;
    if (event.state === "refreshing") {
      animationCompleted = false;
      pendingState = null;
      present("refreshing");
      return;
    }
    const heartbeatIsAnimating = typeof path.getAnimations !== "function"
      || path.getAnimations().some((animation)=>animation.animationName === "operator-heartbeat-flow");
    if (indicator.dataset.state === "refreshing" && !animationCompleted && heartbeatIsAnimating && DEFERRED_STATES.has(event.state)) {
      pendingState = event.state;
      return;
    }
    pendingState = null;
    present(event.state);
  }

  function dispose() {
    if (disposed) return;
    disposed = true;
    path.removeEventListener("animationend", animationFinished);
    heading.before(titleElement);
    heading.remove();
  }

  path.addEventListener("animationend", animationFinished);
  const controller = Object.freeze({ update, dispose });
  indicator.operatorRefreshHeartbeat = controller;
  update({ moduleKey, state: "idle" });
  return controller;
}

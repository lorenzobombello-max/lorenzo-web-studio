export const OPERATOR_AUTO_REFRESH_CADENCE_MS = 8_000;

export function createOperatorAutoRefresh({
  moduleKey,
  refresh,
  isActive = ()=>true,
  isBlocked = ()=>false,
  documentTarget = globalThis.document,
  windowTarget = globalThis.window,
  setTimer = globalThis.setInterval,
  clearTimer = globalThis.clearInterval,
  cadenceMs = OPERATOR_AUTO_REFRESH_CADENCE_MS,
  onLifecycle = ()=>{},
}) {
  if (typeof moduleKey !== "string" || !moduleKey || typeof refresh !== "function"
    || typeof isActive !== "function" || typeof isBlocked !== "function"
    || typeof setTimer !== "function" || typeof clearTimer !== "function"
    || typeof onLifecycle !== "function"
    || !Number.isSafeInteger(cadenceMs) || cadenceMs < 1) {
    throw new TypeError("INVALID_OPERATOR_AUTO_REFRESH");
  }
  let timer = null;
  let refreshing = false;
  let disposed = false;

  const isVisible = ()=>documentTarget?.visibilityState !== "hidden";
  const notify = (state)=>{
    try { onLifecycle({ moduleKey, state }); } catch { /* Presentation cannot interrupt refresh authority. */ }
  };

  async function request() {
    if (disposed || refreshing || !isVisible() || !isActive() || isBlocked()) return false;
    refreshing = true;
    notify("refreshing");
    try {
      const succeeded = await refresh({ background: true }) !== false;
      notify(succeeded ? "success" : "error");
      return succeeded;
    } catch {
      notify("error");
      return false;
    } finally {
      refreshing = false;
    }
  }

  function start() {
    if (!disposed && timer === null && isVisible()) timer = setTimer(()=>{ void request(); }, cadenceMs);
  }

  function stop() {
    if (timer === null) return;
    clearTimer(timer);
    timer = null;
  }

  function visibilityChanged() {
    if (!isVisible()) {
      stop();
      notify("idle");
      return;
    }
    start();
    void request();
  }

  function focused() { void request(); }

  function moduleActivated(event) {
    if (event?.detail?.moduleKey !== moduleKey) {
      stop();
      notify("idle");
      return;
    }
    start();
    void request();
  }

  documentTarget?.addEventListener?.("visibilitychange", visibilityChanged);
  documentTarget?.addEventListener?.("operator:module-active", moduleActivated);
  windowTarget?.addEventListener?.("focus", focused);
  start();

  return Object.freeze({
    request,
    start,
    stop,
    dispose() {
      if (disposed) return;
      disposed = true;
      stop();
      notify("idle");
      documentTarget?.removeEventListener?.("visibilitychange", visibilityChanged);
      documentTarget?.removeEventListener?.("operator:module-active", moduleActivated);
      windowTarget?.removeEventListener?.("focus", focused);
    },
  });
}
import assert from "node:assert/strict";
import test from "node:test";

import { createOperatorAutoRefresh, OPERATOR_AUTO_REFRESH_CADENCE_MS } from "../assets/js/operator-auto-refresh.mjs";

test("Operator active-module fallback cadence is eight seconds", () => {
  assert.equal(OPERATOR_AUTO_REFRESH_CADENCE_MS, 8_000);
});

function eventTarget() {
  const listeners = new Map();
  return {
    visibilityState: "visible",
    addEventListener(type, listener) { listeners.set(type, listener); },
    removeEventListener(type, listener) { if (listeners.get(type) === listener) listeners.delete(type); },
    dispatch(type, event = {}) { listeners.get(type)?.(event); },
    listenerCount() { return listeners.size; },
  };
}

test("Operator auto-refresh owns one active lifecycle and disposes it", async () => {
  const documentTarget = eventTarget();
  const windowTarget = eventTarget();
  const timers = new Map();
  let nextTimer = 0;
  let active = true;
  let blocked = false;
  let refreshes = 0;
  const coordinator = createOperatorAutoRefresh({
    moduleKey: "finance",
    refresh: async ()=>{ refreshes += 1; },
    isActive: ()=>active,
    isBlocked: ()=>blocked,
    documentTarget,
    windowTarget,
    setTimer: (callback, cadence)=>{ timers.set(++nextTimer, { callback, cadence }); return nextTimer; },
    clearTimer: (timer)=>timers.delete(timer),
  });
  assert.equal(timers.size, 1);
  assert.equal([...timers.values()][0].cadence, OPERATOR_AUTO_REFRESH_CADENCE_MS);
  coordinator.start();
  assert.equal(timers.size, 1);
  await [...timers.values()][0].callback();
  assert.equal(refreshes, 1);
  active = false;
  await [...timers.values()][0].callback();
  assert.equal(refreshes, 1);
  documentTarget.dispatch("operator:module-active", { detail: { moduleKey: "calendar" } });
  assert.equal(timers.size, 0);
  active = true;
  blocked = true;
  documentTarget.dispatch("operator:module-active", { detail: { moduleKey: "finance" } });
  await Promise.resolve();
  assert.equal(timers.size, 1);
  assert.equal(refreshes, 1);
  blocked = false;
  documentTarget.dispatch("operator:module-active", { detail: { moduleKey: "finance" } });
  await Promise.resolve();
  assert.equal(refreshes, 2);
  coordinator.dispose();
  assert.equal(timers.size, 0);
  assert.equal(documentTarget.listenerCount(), 0);
  assert.equal(windowTarget.listenerCount(), 0);
});

test("Operator auto-refresh resumes on visibility and recovers after failure", async () => {
  const documentTarget = eventTarget();
  const windowTarget = eventTarget();
  const timers = new Map();
  let calls = 0;
  const coordinator = createOperatorAutoRefresh({
    moduleKey: "messages",
    refresh: async ()=>{ calls += 1; if (calls === 1) throw new Error("TEMPORARY"); },
    documentTarget,
    windowTarget,
    setTimer: (callback)=>{ timers.set(1, callback); return 1; },
    clearTimer: (timer)=>timers.delete(timer),
  });
  assert.equal(await coordinator.request(), false);
  assert.equal(await coordinator.request(), true);
  documentTarget.visibilityState = "hidden";
  documentTarget.dispatch("visibilitychange");
  assert.equal(timers.size, 0);
  documentTarget.visibilityState = "visible";
  documentTarget.dispatch("visibilitychange");
  await Promise.resolve();
  assert.equal(timers.size, 1);
  assert.equal(calls, 3);
  windowTarget.dispatch("focus");
  await Promise.resolve();
  assert.equal(calls, 4);
  coordinator.dispose();
});

test("Operator auto-refresh reports only real refresh lifecycle activity", async () => {
  const documentTarget = eventTarget();
  const lifecycle = [];
  let blocked = true;
  let succeeds = true;
  const coordinator = createOperatorAutoRefresh({
    moduleKey: "dossiers",
    refresh: async ()=>succeeds,
    isBlocked: ()=>blocked,
    documentTarget,
    windowTarget: eventTarget(),
    setTimer: ()=>1,
    clearTimer: ()=>{},
    onLifecycle: (event)=>lifecycle.push(event),
  });
  assert.equal(await coordinator.request(), false);
  assert.deepEqual(lifecycle, []);
  blocked = false;
  assert.equal(await coordinator.request(), true);
  succeeds = false;
  assert.equal(await coordinator.request(), false);
  documentTarget.visibilityState = "hidden";
  documentTarget.dispatch("visibilitychange");
  assert.deepEqual(lifecycle.map(({ state })=>state), ["refreshing", "success", "refreshing", "error", "idle"]);
  assert.ok(lifecycle.every(({ moduleKey })=>moduleKey === "dossiers"));
  coordinator.dispose();
  assert.equal(lifecycle.at(-1).state, "idle");
});

test("Operator refresh authority is isolated from lifecycle presentation failures", async () => {
  let refreshes = 0;
  const coordinator = createOperatorAutoRefresh({
    moduleKey: "calendar",
    refresh: async ()=>{ refreshes += 1; },
    documentTarget: eventTarget(),
    windowTarget: eventTarget(),
    setTimer: ()=>1,
    clearTimer: ()=>{},
    onLifecycle: ()=>{ throw new Error("PRESENTATION_FAILURE"); },
  });
  assert.equal(await coordinator.request(), true);
  assert.equal(refreshes, 1);
  assert.doesNotThrow(()=>coordinator.dispose());
});
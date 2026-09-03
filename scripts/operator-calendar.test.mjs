import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  calendarStatusPresentation,
  createOperatorCalendarController,
  createOperatorCalendarModel,
  operatorCalendarResponse,
} from "../assets/js/operator-calendar.mjs";

const range = { start_date: "2026-08-24", end_date: "2026-08-30" };
const emptyResult = { ...range, employees: [] };

test("calendar model preserves day week month and year navigation", ()=>{
  const model = createOperatorCalendarModel({ today: ()=>new Date("2026-08-30T12:00:00Z") });
  assert.deepEqual(model.snapshot().range, range);
  assert.deepEqual(model.setView("day").range, { start_date: "2026-08-30", end_date: "2026-08-30" });
  assert.deepEqual(model.setView("month").range, { start_date: "2026-08-01", end_date: "2026-08-31" });
  assert.deepEqual(model.setView("year").range, { start_date: "2026-01-01", end_date: "2026-12-31" });
  assert.equal(calendarStatusPresentation("unknown").key, "no_data");
});

test("calendar response accepts only the narrow authority DTO", ()=>{
  assert.deepEqual(operatorCalendarResponse(emptyResult, range), emptyResult);
  assert.throws(()=>operatorCalendarResponse({ ...emptyResult, role: "owner" }, range), /INVALID_OPERATOR_CALENDAR_RESPONSE/);
});

test("calendar controller returns dispose and ignores pending work after disposal", async ()=>{
  let resolveLoad;
  let renders = 0;
  const controller = createOperatorCalendarController({
    model: createOperatorCalendarModel({ today: ()=>new Date("2026-08-30T12:00:00Z") }),
    load: ()=>new Promise((resolve)=>{ resolveLoad = resolve; }),
    onChange: ()=>{ renders += 1; },
  });
  const pending = controller.reload();
  assert.equal(typeof controller.dispose, "function");
  assert.equal(renders, 1);
  controller.dispose();
  resolveLoad(emptyResult);
  assert.equal(await pending, false);
  assert.equal(renders, 1);
  assert.equal(await controller.reload(), false);
});

test("calendar controller deduplicates an identical pending range", async ()=>{
  let calls = 0;
  let resolveLoad;
  const controller = createOperatorCalendarController({
    model: createOperatorCalendarModel({ today: ()=>new Date("2026-08-30T12:00:00Z") }),
    load: ()=>{ calls += 1; return new Promise((resolve)=>{ resolveLoad = resolve; }); },
  });
  const first = controller.reload();
  const second = controller.reload();
  assert.equal(calls, 1);
  resolveLoad(emptyResult);
  assert.equal(await first, true);
  assert.equal(await second, true);
});

test("calendar background refresh preserves the current view through failure and recovery", async ()=>{
  const model = createOperatorCalendarModel({ today: ()=>new Date("2026-08-30T12:00:00Z") });
  const responses = [emptyResult, new Error("TEMPORARY"), emptyResult];
  const renders = [];
  const controller = createOperatorCalendarController({
    model,
    load: async ()=>{
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return response;
    },
    onChange: (state)=>renders.push(state),
  });
  await controller.reload();
  const renderCount = renders.length;
  assert.equal(await controller.reload({ background: true }), false);
  assert.equal(renders.length, renderCount);
  assert.deepEqual(controller.state.range, range);
  assert.equal(await controller.reload({ background: true }), true);
  assert.deepEqual(controller.state.range, range);
  const source = await readFile(new URL("../assets/js/operator-calendar.mjs", import.meta.url), "utf8");
  assert.match(source, /createOperatorAutoRefresh\(\{[\s\S]*moduleKey: "calendar"[\s\S]*background: true/);
  assert.match(source, /autoRefresh\.dispose\(\)/);
  controller.dispose();
});

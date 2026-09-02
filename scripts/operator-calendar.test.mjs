import assert from "node:assert/strict";
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

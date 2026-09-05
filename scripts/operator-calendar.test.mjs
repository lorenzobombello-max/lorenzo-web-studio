import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  calendarEmployeePeriodDetail,
  calendarPayrollInputPreview,
  calendarStatusPresentation,
  createOperatorCalendarController,
  createOperatorCalendarModel,
  operatorCalendarResponse,
} from "../assets/js/operator-calendar.mjs";

const range = { start_date: "2026-08-24", end_date: "2026-08-30" };
const emptyResult = { ...range, employees: [] };
const employee = (employee_id, entries)=>({
  employee_id,
  display_name: `Medewerker ${employee_id.slice(-2)}`,
  role_title: "Planner",
  team_name: "Operations",
  employment_status: "ACTIVE",
  entries,
});

test("calendar model preserves day week month and year navigation", ()=>{
  const model = createOperatorCalendarModel({ today: ()=>new Date("2026-08-30T12:00:00Z") });
  assert.deepEqual(model.snapshot().range, range);
  assert.deepEqual(model.setView("day").range, { start_date: "2026-08-30", end_date: "2026-08-30" });
  assert.deepEqual(model.navigate(-1).range, { start_date: "2026-08-29", end_date: "2026-08-29" });
  assert.deepEqual(model.navigate(1).range, { start_date: "2026-08-30", end_date: "2026-08-30" });
  assert.deepEqual(model.goToday().range, { start_date: "2026-08-30", end_date: "2026-08-30" });
  assert.deepEqual(model.setView("month").range, { start_date: "2026-08-01", end_date: "2026-08-31" });
  assert.deepEqual(model.setView("year").range, { start_date: "2026-01-01", end_date: "2026-12-31" });
  assert.equal(calendarStatusPresentation("unknown").key, "no_data");
});

test("calendar response accepts only the narrow authority DTO", ()=>{
  assert.deepEqual(operatorCalendarResponse(emptyResult, range), emptyResult);
  assert.throws(()=>operatorCalendarResponse({ ...emptyResult, role: "owner" }, range), /INVALID_OPERATOR_CALENDAR_RESPONSE/);
});

test("calendar model derives period and daily capacity only from canonical DTO statuses", ()=>{
  const model = createOperatorCalendarModel({
    today: ()=>new Date("2026-08-24T12:00:00Z"),
    employees: [
      employee("a1000000-0000-4000-8000-000000000001", [
        { date: "2026-08-24", status: "WORKED_FULL_DAY" },
        { date: "2026-08-25", status: "LEAVE" },
        { date: "2026-08-26", status: "WORKED_HALF_DAY_PM" },
      ]),
      employee("a1000000-0000-4000-8000-000000000002", [
        { date: "2026-08-24", status: "WORKED_HALF_DAY_AM" },
        { date: "2026-08-25", status: "SICK" },
        { date: "2026-08-26", status: "OTHER_ABSENCE" },
      ]),
    ],
  });
  const state = model.snapshot();
  assert.deepEqual(state.summary, {
    totalEmployees: 2,
    worked: 3,
    leave: 1,
    sick: 1,
    otherAbsence: 1,
    noData: 8,
  });
  assert.deepEqual(state.dailyCapacity[0], {
    date: "2026-08-24", worked: 2, leave: 0, sick: 0, otherAbsence: 0, noData: 0,
  });
  assert.deepEqual(state.dailyCapacity[1], {
    date: "2026-08-25", worked: 0, leave: 1, sick: 1, otherAbsence: 0, noData: 0,
  });
  assert.deepEqual(state.dailyCapacity[2], {
    date: "2026-08-26", worked: 1, leave: 0, sick: 0, otherAbsence: 1, noData: 0,
  });
});

test("calendar model exposes exact zero summaries without production data", ()=>{
  const state = createOperatorCalendarModel({ today: ()=>new Date("2026-08-24T12:00:00Z") }).snapshot();
  assert.deepEqual(state.summary, {
    totalEmployees: 0, worked: 0, leave: 0, sick: 0, otherAbsence: 0, noData: 0,
  });
  assert.equal(state.dailyCapacity.length, 7);
  assert.ok(state.dailyCapacity.every((day)=>Object.values(day).slice(1).every((count)=>count === 0)));
});

test("employee period detail derives exact separate status totals and daily history", ()=>{
  const lanaId = "a1000000-0000-4000-8000-000000000011";
  const model = createOperatorCalendarModel({
    today: ()=>new Date("2026-08-24T12:00:00Z"),
    employees: [employee(lanaId, [
      { date: "2026-08-24", status: "WORKED_FULL_DAY" },
      { date: "2026-08-25", status: "WORKED_HALF_DAY_AM" },
      { date: "2026-08-26", status: "WORKED_HALF_DAY_PM" },
      { date: "2026-08-27", status: "LEAVE" },
      { date: "2026-08-28", status: "SICK" },
      { date: "2026-08-29", status: "OTHER_ABSENCE" },
    ])],
  });
  const detail = calendarEmployeePeriodDetail(model.snapshot(), lanaId);
  assert.deepEqual(detail.totals, {
    visibleDays: 7, fullDay: 1, halfDayAm: 1, halfDayPm: 1, leave: 1, sick: 1, otherAbsence: 1, noData: 1,
  });
  assert.equal(detail.available, true);
  assert.equal(detail.employee.name, "Medewerker 11");
  assert.equal(detail.periodLabel, "24 aug - 30 aug 2026");
  assert.equal(detail.workedHours, null);
  assert.deepEqual(detail.history.map(({ date, status, info })=>[date, status.label, info]), [
    ["2026-08-24", "Volledige werkdag", "—"],
    ["2026-08-25", "Halve dag voormiddag", "—"],
    ["2026-08-26", "Halve dag namiddag", "—"],
    ["2026-08-27", "Verlof", "—"],
    ["2026-08-28", "Ziek", "—"],
    ["2026-08-29", "Andere afwezigheid", "—"],
    ["2026-08-30", "Geen planning / geen data", "—"],
  ]);
});

test("employee period detail fails safe for missing employees and blocks fake Year totals", ()=>{
  const employeeId = "a1000000-0000-4000-8000-000000000012";
  const model = createOperatorCalendarModel({
    today: ()=>new Date("2026-08-24T12:00:00Z"),
    employees: [employee(employeeId, [])],
  });
  assert.equal(calendarEmployeePeriodDetail(model.snapshot(), "a1000000-0000-4000-8000-000000000099"), null);
  const detail = calendarEmployeePeriodDetail(model.setView("year"), employeeId);
  assert.equal(detail.available, false);
  assert.equal(detail.totals, undefined);
  assert.match(detail.message, /niet beschikbaar zonder maandaggregatie/);
});

test("payroll input preview derives completeness and source statuses without hours or amounts", ()=>{
  const lanaId = "a1000000-0000-4000-8000-000000000011";
  const model = createOperatorCalendarModel({
    today: ()=>new Date("2026-08-24T12:00:00Z"),
    employees: [employee(lanaId, [
      { date: "2026-08-24", status: "WORKED_FULL_DAY" },
      { date: "2026-08-25", status: "WORKED_HALF_DAY_AM" },
      { date: "2026-08-26", status: "WORKED_HALF_DAY_PM" },
      { date: "2026-08-27", status: "LEAVE" },
      { date: "2026-08-28", status: "SICK" },
      { date: "2026-08-29", status: "OTHER_ABSENCE" },
    ])],
  });
  const preview = calendarPayrollInputPreview(model.snapshot(), lanaId);
  assert.equal(preview.completeness, "ONVOLLEDIGE GEGEVENS");
  assert.equal(preview.completenessMessage, "1 dag zonder planning/gegevensaanduiding");
  assert.deepEqual(preview.incompleteDays, ["2026-08-30"]);
  assert.equal(preview.workedHours, null);
  assert.deepEqual(preview.dayLines.map(({ sourceStatus, control, hours })=>[sourceStatus, control, hours]), [
    ["WORKED_FULL_DAY", "OK", null],
    ["WORKED_HALF_DAY_AM", "OK", null],
    ["WORKED_HALF_DAY_PM", "OK", null],
    ["LEAVE", "OK", null],
    ["SICK", "OK", null],
    ["OTHER_ABSENCE", "OK", null],
    ["NO_DATA", "CONTROLEREN", null],
  ]);
  assert.equal(calendarPayrollInputPreview(model.setView("year"), lanaId).available, false);
  assert.equal(calendarPayrollInputPreview(model.snapshot(), "a1000000-0000-4000-8000-000000000099"), null);
});

test("payroll input preview is complete only when every visible day has a canonical status", ()=>{
  const employeeId = "a1000000-0000-4000-8000-000000000012";
  const model = createOperatorCalendarModel({
    today: ()=>new Date("2026-08-24T12:00:00Z"),
    initialView: "day",
    employees: [employee(employeeId, [{ date: "2026-08-24", status: "WORKED_FULL_DAY" }])],
  });
  const preview = calendarPayrollInputPreview(model.snapshot(), employeeId);
  assert.equal(preview.completeness, "COMPLEET");
  assert.deepEqual(preview.incompleteDays, []);
});

test("calendar year remains representative and opens an exact month without aggregation", ()=>{
  const model = createOperatorCalendarModel({ today: ()=>new Date("2026-08-24T12:00:00Z") });
  const year = model.setView("year");
  assert.equal(year.dailyCapacity.length, 12);
  assert.deepEqual(year.dates, [
    "2026-01-01", "2026-02-01", "2026-03-01", "2026-04-01", "2026-05-01", "2026-06-01",
    "2026-07-01", "2026-08-01", "2026-09-01", "2026-10-01", "2026-11-01", "2026-12-01",
  ]);
  assert.deepEqual(model.openMonth("2026-09-01").range, { start_date: "2026-09-01", end_date: "2026-09-30" });
  assert.equal(model.snapshot().view, "month");
  return readFile(new URL("../assets/js/operator-calendar.mjs", import.meta.url), "utf8").then((source)=>{
    assert.match(source, /Alleen eerste dag per maand/);
    assert.match(source, /representatieve maanddagen/);
  });
});

test("calendar source preserves one read endpoint and exposes no mutation controls", async ()=>{
  const source = await readFile(new URL("../assets/js/operator-calendar.mjs", import.meta.url), "utf8");
  const css = await readFile(new URL("../assets/css/operator-dashboard.css", import.meta.url), "utf8");
  assert.equal(source.match(/client\.rpc\(/g)?.length, 1);
  assert.match(source, /client\.rpc\("get_operator_calendar_v1", \{ p_start_date: range\.start_date, p_end_date: range\.end_date \}\)/);
  assert.doesNotMatch(source, /client\.(?:from|functions)|fetch\(|create.*calendar.*entry|update.*calendar.*entry|delete.*calendar.*entry/i);
  assert.doesNotMatch(source, /Goedkeuren|Weigeren|Verlof aanvragen|Ziek melden|Uren schrijven/);
  assert.match(source, /Nog geen werknemersgegevens beschikbaar/);
  assert.match(source, /calendar-summary-grid/);
  assert.match(source, /calendar-capacity-grid/);
  assert.match(source, /calendar-day-detail/);
  assert.match(source, /function renderSelectedDate\(\)[\s\S]*data-calendar-date[\s\S]*aria-pressed/);
  assert.equal((source.match(/button\.dataset\.calendarDate = date/g) || []).length, 2);
  assert.match(source, /selectedDate = date;\s*renderSelectedDate\(\)/);
  assert.match(source, /selectedDate = null; renderSelectedDate\(\); detailSection\.hidden = true/);
  assert.match(source, /calendar-employee-trigger/);
  assert.match(source, /calendar-employee-detail/);
  assert.match(source, /Gewerkte uren:<\/strong> nog niet beschikbaar/);
  assert.match(source, /niet beschikbaar zonder maandaggregatie/);
  assert.match(source, /Bekijk loonvoorbereiding/);
  assert.match(source, /Loonvoorbereiding is niet beschikbaar in Jaarweergave\. Kies Dag, Week of Maand\./);
  assert.match(source, /Gewerkte uren nog niet beschikbaar vanuit de huidige gegevensbron\./);
  assert.match(source, /\["Datum", "Status", "Uren", "Bronstatus", "Controle"\]/);
  assert.match(source, /Technische referentie: employee_id/);
  assert.doesNotMatch(source, /LWS-\d{5}/);
  assert.match(source, /if \(selectedEmployeeId\) renderEmployeeDetail\(state, selectedEmployeeId\)/);
  assert.match(source, /if \(!detail\) \{[\s\S]*?closeEmployeeDetail\(\);[\s\S]*?return;[\s\S]*?\}/);
  assert.match(source, /event\.key !== "Escape"[\s\S]*payrollPreviewOpen[\s\S]*closeEmployeeDetail\(\{ restoreFocus: true \}\)/);
  assert.doesNotMatch(source, /(?:payroll|finance|workforce).*(?:rpc|fetch)|(?:rpc|fetch).*(?:payroll|finance|workforce)/i);
  assert.doesNotMatch(source, /(?:8|7\.6)\s*\*|\*\s*(?:8|7\.6)/);
  assert.doesNotMatch(source, /brutoloon|nettoloon|RSZ|bedrijfsvoorheffing|werkgeversbijdragen|vakantiegeld|toeslagen|premies|betaalbedrag/i);
  assert.doesNotMatch(source, /method\s*:\s*["'](?:POST|PUT|PATCH|DELETE)["']/i);
  assert.doesNotMatch(source, /Loonfiche maken|Loon berekenen|Naar Finance sturen/);
  assert.match(css, /@media \(max-width:540px\)[\s\S]*\.calendar-summary-grid \{ grid-template-columns:repeat\(2,minmax\(0,1fr\)\); \}/);
  assert.match(css, /\.calendar-employee-detail__summary \{[^}]*grid-template-columns:repeat\(4,minmax\(0,1fr\)\)/);
  assert.match(css, /@media \(max-width:540px\)[\s\S]*\.calendar-employee-detail__summary \{ grid-template-columns:repeat\(2,minmax\(0,1fr\)\); \}/);
  assert.match(css, /\.calendar-payroll-preview__table-viewport \{[^}]*overflow:auto/);
  assert.match(css, /\.calendar-viewport \{[^}]*overflow-x:auto[^}]*overflow-y:auto/);
  assert.match(css, /\.calendar-capacity-day\[aria-pressed="true"\][^{]*\{[^}]*animation:calendar-selected-day-heartbeat 4\.8s ease-in-out infinite/);
  assert.match(css, /\.calendar-capacity-day\[aria-pressed="true"\]::before[^{]*\{[^}]*animation:dossier-card-light-sweep 9s \.6s[^}]*infinite/);
  assert.match(css, /\.calendar-date-trigger\[aria-pressed="true"\][^{]*\{[^}]*animation:calendar-selected-day-heartbeat 4\.8s ease-in-out infinite/);
});

test("calendar selection release identity reaches dashboard and standalone windows", async ()=>{
  const release = "20260905-calendar-selection-r1";
  const [dashboard, dashboardGuard, dashboardHtml, registry, windowGuard, windowHtml] = await Promise.all([
    readFile(new URL("../assets/js/operator-dashboard.js", import.meta.url), "utf8"),
    readFile(new URL("../assets/js/operator-dashboard-guard.mjs", import.meta.url), "utf8"),
    readFile(new URL("../operator/dashboard/index.html", import.meta.url), "utf8"),
    readFile(new URL("../assets/js/operator-module-registry.mjs", import.meta.url), "utf8"),
    readFile(new URL("../assets/js/operator-window-guard.mjs", import.meta.url), "utf8"),
    readFile(new URL("../operator/window/index.html", import.meta.url), "utf8"),
  ]);
  assert.ok(dashboard.includes(`operator-calendar.mjs?v=${release}`));
  assert.ok(dashboardGuard.includes(`calendar=${release}`));
  assert.ok(dashboardHtml.includes(`calendar-selection=20260905-r1`));
  assert.ok(registry.includes(`operator-calendar.mjs?v=${release}`));
  assert.ok(windowGuard.includes(`calendar=${release}`));
  assert.ok(windowHtml.includes(`calendar-selection=20260905-r1`));
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

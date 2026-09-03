import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  calendarLeaveDecisionRequest,
  calendarLeaveQueueView,
  decideOperatorLeaveRequest,
  emptyOperatorLeaveQueue,
  loadOperatorLeaveQueue,
  operatorLeaveQueueResponse,
  staleLeaveDecision,
} from "../assets/js/operator-calendar-leave.mjs";

const range = { start_date: "2026-09-14", end_date: "2026-09-20" };
const request = (status, suffix, overrides = {})=>({
  request_id: `da100000-0000-4000-8000-${suffix.padStart(12, "0")}`,
  employee_id: `da200000-0000-4000-8000-${suffix.padStart(12, "0")}`,
  employee_number: `LWS-${suffix.padStart(5, "0")}`,
  display_name: `Medewerker ${suffix}`,
  leave_type: "LEAVE",
  start_date: "2026-09-18",
  end_date: "2026-09-18",
  day_part: "FULL_DAY",
  request_status: status,
  revision: status === "REQUESTED" ? 1 : 2,
  employee_note: "Familiedag",
  submitted_at: "2026-09-03T08:00:00.000Z",
  decided_at: status === "REQUESTED" ? null : "2026-09-03T09:00:00.000Z",
  decided_by_operator_id: status === "REQUESTED" ? null : "da300000-0000-4000-8000-000000000001",
  management_note: status === "REQUESTED" ? null : "Beoordeeld",
  capacity_context: [{
    date: "2026-09-18", employees_total: 3, approved_leave_count: 1, sick_count: 0,
    other_absence_count: 0, requested_count: 1, waiting_count: 1,
  }],
  history: [{
    event_id: `da400000-0000-4000-8000-${suffix.padStart(12, "0")}`,
    event_type: "SUBMITTED", previous_status: null, new_status: "REQUESTED",
    actor_operator_id: `da500000-0000-4000-8000-${suffix.padStart(12, "0")}`,
    actor_display_name: `Medewerker ${suffix}`, management_note: null,
    occurred_at: "2026-09-03T08:00:00.000Z",
  }],
  ...overrides,
});

const queue = {
  ...range,
  counters: { requested: 1, waiting: 1, approved: 1, rejected: 1 },
  requests: [
    request("REQUESTED", "1"),
    request("WAITING", "2"),
    request("APPROVED", "3"),
    request("REJECTED", "4"),
  ],
};

test("leave queue validates the exact authoritative DTO and factual context", ()=>{
  assert.deepEqual(operatorLeaveQueueResponse(queue, range), queue);
  assert.throws(
    ()=>operatorLeaveQueueResponse({ ...queue, capacity_maximum: 4 }, range),
    /INVALID_OPERATOR_LEAVE_QUEUE_RESPONSE/,
  );
  assert.throws(
    ()=>operatorLeaveQueueResponse({ ...queue, requests: [request("REQUESTED", "1", { day_part: "AM", end_date: "2026-09-19" })] }, range),
    /INVALID_OPERATOR_LEAVE_QUEUE_RESPONSE/,
  );
  assert.deepEqual(emptyOperatorLeaveQueue(range).counters, { requested: 0, waiting: 0, approved: 0, rejected: 0 });
});

test("queue counters preserve requested waiting approved and rejected views", ()=>{
  for (const status of ["REQUESTED", "WAITING", "APPROVED", "REJECTED"]) {
    const view = calendarLeaveQueueView(queue, status);
    assert.equal(view.selectedStatus, status);
    assert.equal(view.requests.length, 1);
    assert.equal(view.requests[0].request_status, status);
  }
  assert.equal(calendarLeaveQueueView(queue, "UNKNOWN").selectedStatus, "REQUESTED");
});

test("decision payload includes status and revision preconditions", ()=>{
  const requested = queue.requests[0];
  assert.deepEqual(calendarLeaveDecisionRequest(requested, "APPROVED", "  Akkoord  "), {
    p_request_id: requested.request_id,
    p_expected_status: "REQUESTED",
    p_expected_revision: 1,
    p_decision: "APPROVED",
    p_management_note: "Akkoord",
  });
  assert.equal(calendarLeaveDecisionRequest(requested, "WAITING").p_management_note, null);
  assert.throws(()=>calendarLeaveDecisionRequest(queue.requests[1], "WAITING"), /INVALID_OPERATOR_LEAVE_DECISION/);
  assert.throws(()=>calendarLeaveDecisionRequest(queue.requests[2], "REJECTED"), /INVALID_OPERATOR_LEAVE_DECISION/);
});

test("leave queue transport uses only the bounded authenticated Calendar RPC", async ()=>{
  const calls = [];
  const result = await loadOperatorLeaveQueue({
    rpc: (name, params)=>{ calls.push({ name, params }); return Promise.resolve({ data: queue, error: null }); },
  }, range);
  assert.equal(result, queue);
  assert.deepEqual(calls, [{ name: "get_operator_leave_requests_v1", params: { p_start_date: range.start_date, p_end_date: range.end_date } }]);
});

test("decision transport validates response and preserves optimistic locking", async ()=>{
  const requested = queue.requests[0];
  const calls = [];
  const result = await decideOperatorLeaveRequest({
    rpc: (name, params)=>{
      calls.push({ name, params });
      return Promise.resolve({ data: {
        request_id: requested.request_id,
        previous_status: "REQUESTED",
        request_status: "APPROVED",
        revision: 2,
        decided_at: "2026-09-03T10:00:00.000Z",
      }, error: null });
    },
  }, requested, "APPROVED", null);
  assert.equal(result.request_status, "APPROVED");
  assert.equal(calls[0].name, "decide_operator_leave_request_v1");
  assert.equal(calls[0].params.p_expected_revision, 1);
});

test("stale decision errors use the required management conflict message path", async ()=>{
  assert.equal(staleLeaveDecision({ code: "40001" }), true);
  assert.equal(staleLeaveDecision({ message: "LEAVE_REQUEST_STALE_DECISION" }), true);
  assert.equal(staleLeaveDecision({ code: "23P01" }), false);
  await assert.rejects(
    decideOperatorLeaveRequest({ rpc: ()=>Promise.resolve({ data: null, error: { code: "40001", message: "LEAVE_REQUEST_STALE_DECISION" } }) }, queue.requests[0], "REJECTED", null),
    (error)=>staleLeaveDecision(error),
  );
});

test("management UI exposes queue detail decisions history refresh and focus behavior", async ()=>{
  const source = await readFile(new URL("../assets/js/operator-calendar-leave.mjs", import.meta.url), "utf8");
  assert.match(source, /Verlofaanvragen/);
  assert.match(source, /Nieuwe en wachtende aanvragen/);
  assert.match(source, /Goedkeuren/);
  assert.match(source, /In wacht zetten/);
  assert.match(source, /Weigeren/);
  assert.match(source, /Dagcapaciteit \/ afwezigheidscontext/);
  assert.match(source, /Beslishistorie/);
  assert.match(source, /Deze aanvraag werd intussen door iemand anders verwerkt\. Vernieuw de gegevens\./);
  assert.match(source, /await onRefresh\(\)/);
  assert.match(source, /event\.key === "Escape"[\s\S]*closeDetail\(\{ restoreFocus: true \}\)/);
  assert.match(source, /returnFocus\?\.focus\(\)/);
  assert.doesNotMatch(source, /setInterval|setTimeout|createOperatorAutoRefresh|createOperatorRefreshHeartbeat/);
  assert.doesNotMatch(source, /submit_workforce_leave_request_v1|request as any employee/i);
  assert.doesNotMatch(source, /plaatsen|capacity_maximum|Nog \d+ plaatsen/i);
  assert.doesNotMatch(source, /window\.confirm|confirm\(/);
});

test("Calendar coordinates queue refresh and mobile layout without payroll linkage", async ()=>{
  const calendar = await readFile(new URL("../assets/js/operator-calendar.mjs", import.meta.url), "utf8");
  const leave = await readFile(new URL("../assets/js/operator-calendar-leave.mjs", import.meta.url), "utf8");
  const css = await readFile(new URL("../assets/css/operator-dashboard.css", import.meta.url), "utf8");
  assert.match(calendar, /Promise\.all\(\[load\(request\), loadLeaveRequests\(request\)\]\)/);
  assert.match(calendar, /model\.replaceEmployees\(result\.employees\)[\s\S]*model\.replaceLeaveQueue\(leaveQueue\)/);
  assert.match(calendar, /identity\.role === "owner"/);
  assert.match(calendar, /onRefresh: \(\)=>controller\.reload\(\{ background: true \}\)/);
  assert.equal(leave.match(/client\.rpc\(/g)?.length, 2);
  assert.doesNotMatch(leave, /\b(?:payroll|finance|loon|bedrag|EUR)\b|€/i);
  assert.match(css, /@media \(max-width:540px\)[\s\S]*\.calendar-leave-list \{ grid-template-columns:1fr; \}/);
  assert.match(css, /\.calendar-leave-detail__context \{[^}]*overflow:auto/);
  assert.match(css, /@media \(max-width:540px\)[\s\S]*\.calendar-leave-detail__actions \{ flex-direction:column; \}/);
});
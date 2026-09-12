import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  deriveProjectProgress,
  projectSummaryMarkup,
  projectWorkspaceViewModel,
} from "../assets/js/operator-project-workspace.mjs";

const projectId = "a1800000-0000-4000-8000-000000000002";
const quoteRequestId = "a1100000-0000-4000-8000-000000000001";
const progressSource = readFileSync(
  new URL("../assets/js/operator-project-workspace.mjs", import.meta.url),
  "utf8",
);
const childSource = readFileSync(
  new URL("../assets/js/operator-project-workspace-child.mjs", import.meta.url),
  "utf8",
);
const dashboardCss = readFileSync(
  new URL("../assets/css/operator-dashboard.css", import.meta.url),
  "utf8",
);

function authority({
  state = "PROJECT_RELEASED",
  intakeComplete = true,
  m1Status = "CONFIRMED",
  m3Status = "EXPECTED",
  blockReason = state === "PROJECT_RELEASED" ? "READY_TO_START" : "ADVANCED",
  events = [],
} = {}) {
  return {
    project: {
      project_id: projectId,
      current_state: state,
      revision: 7,
      financial_summary: {
        milestones: [
          { milestone: 1, payment_status: m1Status },
          { milestone: 2, payment_status: "EXPECTED" },
          { milestone: 3, payment_status: m3Status },
        ],
      },
      timeline: events.map((eventType, index) => ({
        event_type: eventType,
        occurred_at: `2026-09-10T0${index}:00:00Z`,
      })),
    },
    startGate: {
      intake_complete: intakeComplete,
      m1_confirmed: m1Status === "CONFIRMED",
      commercially_released: state === "PROJECT_RELEASED" ||
        !["M1_PAYMENT_RECEIVED", "M1_PAYMENT_PENDING"].includes(state),
      project_start_allowed: blockReason === "READY_TO_START",
      block_reason: blockReason,
      current_project_state: state,
      project_id: projectId,
      quote_request_id: quoteRequestId,
    },
  };
}

function statuses(progress) {
  return progress.steps.map(({ status }) => status);
}

test("intake incomplete blocks step 01 and locks every dependent step", () => {
  const progress = deriveProjectProgress(authority({
    intakeComplete: false,
    m1Status: "EXPECTED",
    state: "M1_PAYMENT_PENDING",
    blockReason: "BLOCKED_INTAKE",
  }));
  assert.deepEqual(statuses(progress), ["blocked", "locked", "locked", "locked", "locked"]);
  assert.equal(progress.steps[0].reason, "INTAKE_INCOMPLETE");
});

test("complete intake with pending M1 blocks step 02", () => {
  for (const m1Status of [
    "PARTIAL",
    "MATCHED_AWAITING_CONFIRMATION",
    "EVIDENCE_RECORDED",
    "EXPECTED",
  ]) {
    const progress = deriveProjectProgress(authority({
      m1Status,
      state: "M1_PAYMENT_PENDING",
      blockReason: "BLOCKED_M1_PAYMENT",
    }));
    assert.deepEqual(
      statuses(progress),
      ["done", "blocked", "locked", "locked", "locked"],
      m1Status,
    );
    assert.equal(progress.steps[1].source_state, m1Status);
  }
});

test("confirmed M1 without commercial release keeps build locked", () => {
  const progress = deriveProjectProgress(authority({
    state: "M1_PAYMENT_RECEIVED",
    blockReason: "READY_FOR_RELEASE",
  }));
  assert.deepEqual(statuses(progress), ["done", "done", "locked", "locked", "locked"]);
  assert.equal(progress.steps[2].reason, "COMMERCIAL_RELEASE_REQUIRED");
});

test("READY_TO_START makes only build ready", () => {
  const progress = deriveProjectProgress(authority());
  assert.deepEqual(statuses(progress), ["done", "done", "ready", "locked", "locked"]);
  assert.equal(progress.current_step, "03");
  assert.equal(progress.project_phase, "Klaar om te starten");
});

test("PROJECT_WORK_STARTED makes build in progress", () => {
  const progress = deriveProjectProgress(authority({
    blockReason: "STARTED",
    events: ["PROJECT_WORK_STARTED"],
  }));
  assert.equal(progress.steps[2].status, "in_progress");
  assert.equal(progress.project_phase, "Website in uitvoering");
});

test("PREVIEW_READY completes build and opens review", () => {
  const progress = deriveProjectProgress(authority({ state: "PREVIEW_READY" }));
  assert.deepEqual(statuses(progress), ["done", "done", "done", "ready", "locked"]);
  assert.equal(progress.project_phase, "Klaar voor review");
});

test("feedback and revision authority make review active", () => {
  for (const eventType of ["CLASSIFY_FEEDBACK", "CREATE_REVISION", "MARK_REVISION_READY", "CREATE_PREVIEW_VERSION"]) {
    const progress = deriveProjectProgress(authority({
      state: "PREVIEW_READY",
      events: [eventType],
    }));
    assert.equal(progress.steps[3].status, "in_progress", eventType);
    assert.equal(progress.project_phase, "Review en feedback", eventType);
  }
});

test("FINAL_APPROVAL_RECORDED completes review", () => {
  const progress = deriveProjectProgress(authority({ state: "FINAL_APPROVAL_RECORDED" }));
  assert.equal(progress.steps[3].status, "done");
  assert.equal(progress.project_phase, "Klant heeft definitief goedgekeurd");
});

test("final approval with incomplete payment blocks delivery", () => {
  const progress = deriveProjectProgress(authority({
    state: "FINAL_APPROVAL_RECORDED",
    m3Status: "PARTIAL",
  }));
  assert.equal(progress.steps[4].status, "blocked");
  assert.equal(progress.steps[4].reason, "FULL_PAYMENT_REQUIRED");
});

test("FINAL_TRANSFER_AUTHORIZED makes delivery ready", () => {
  const progress = deriveProjectProgress(authority({
    state: "FINAL_TRANSFER_AUTHORIZED",
    m3Status: "CONFIRMED",
  }));
  assert.equal(progress.steps[4].status, "ready");
  assert.equal(progress.project_phase, "Klaar voor oplevering");
});

test("DELIVERED completes all five steps", () => {
  const progress = deriveProjectProgress(authority({
    state: "DELIVERED",
    m3Status: "CONFIRMED",
  }));
  assert.deepEqual(statuses(progress), ["done", "done", "done", "done", "done"]);
  assert.equal(progress.project_phase, "Opgeleverd");
});

test("ARCHIVED after delivery remains complete", () => {
  const progress = deriveProjectProgress(authority({
    state: "ARCHIVED",
    m3Status: "CONFIRMED",
  }));
  assert.deepEqual(statuses(progress), ["done", "done", "done", "done", "done"]);
});

test("impossible advanced state fails closed", () => {
  const progress = deriveProjectProgress(authority({
    state: "PREVIEW_READY",
    m1Status: "PARTIAL",
  }));
  assert.deepEqual(statuses(progress), ["done", "blocked", "blocked", "locked", "locked"]);
  assert.equal(progress.steps[2].reason, "PREVIEW_STATE_INCONSISTENT");
});

test("unauthorized view exposes no progress or actions", () => {
  const denied = projectWorkspaceViewModel({
    state: "denied",
    message: "Geen toegang tot dit project.",
  });
  assert.deepEqual(denied, {
    state: "denied",
    message: "Geen toegang tot dit project.",
  });
  assert.equal("steps" in denied, false);
  assert.equal("startAllowed" in denied, false);
});

test("master compact summary exposes X of 5 and current step only", () => {
  const view = projectWorkspaceViewModel(authority({ state: "PREVIEW_READY" }));
  assert.equal(view.completedSteps, 3);
  assert.equal(view.steps.length, 5);
  assert.equal(view.currentStepLabel, "Review en feedback");
  const markup = projectSummaryMarkup();
  assert.match(markup, /data-project-summary-current-step/);
  assert.doesNotMatch(markup, /project-progress/);
});

test("child workspace receives reason and source state for every derived step", () => {
  const view = projectWorkspaceViewModel(authority({
    state: "FINAL_APPROVAL_RECORDED",
    m3Status: "PARTIAL",
  }));
  assert.equal(view.steps.length, 5);
  for (const step of view.steps) {
    assert.equal(typeof step.reason, "string");
    assert.equal(typeof step.source_state, "string");
  }
  assert.match(childSource, /data-project-step-reason/);
});

test("automatic refresh replaces derived progress without reloading", () => {
  const before = projectWorkspaceViewModel(authority());
  const after = projectWorkspaceViewModel(authority({
    blockReason: "STARTED",
    events: ["PROJECT_WORK_STARTED"],
  }));
  assert.equal(before.steps[2].status, "ready");
  assert.equal(after.steps[2].status, "in_progress");
  assert.match(childSource, /createOperatorAutoRefresh/);
  assert.doesNotMatch(childSource, /location\.reload/);
});

test("progress remains derived without duplicate business models", () => {
  assert.match(progressSource, /function deriveProjectProgress/);
  assert.doesNotMatch(progressSource, /progress_status\s*=|payment_received|intake_done|build_complete/);
  assert.doesNotMatch(progressSource, /fetch\(|\.from\(|\.insert\(|\.update\(/);
});

test("completed project steps are static green", () => {
  assert.match(
    dashboardCss,
    /\.project-progress li\[data-state="done"\] \.project-progress__copy \{[^}]*background:#f3faf6;[^}]*animation:none;/,
  );
  assert.doesNotMatch(
    dashboardCss,
    /li\[data-state="done"\][^{]*\{[^}]*(?:project-active-step-pulse|dossier-card-light-sweep)/,
  );
});

test("only the in-progress step receives the green pulse and dossier laser", () => {
  assert.match(
    dashboardCss,
    /\.project-progress li\[data-state="in_progress"\] \.project-progress__copy \{[^}]*animation:project-active-step-pulse/,
  );
  assert.match(
    dashboardCss,
    /\.project-progress li\[data-state="in_progress"\] \.project-progress__copy::before \{[^}]*animation:dossier-card-light-sweep/,
  );
  assert.equal((dashboardCss.match(/animation:project-active-step-pulse/g) || []).length, 1);
  assert.equal((dashboardCss.match(/\.project-progress li\[data-state="in_progress"\] \.project-progress__copy::before \{[^}]*animation:dossier-card-light-sweep/g) || []).length, 1);
  assert.doesNotMatch(
    dashboardCss,
    /\.project-progress li\[data-state="(?:done|ready|locked|blocked)"\][^{]*\{[^}]*(?:project-active-step-pulse|dossier-card-light-sweep)/,
  );
});

test("ready and locked project steps remain neutral", () => {
  assert.match(
    dashboardCss,
    /\.project-progress li\[data-state="ready"\] \.project-progress__copy,\.project-progress li\[data-state="locked"\] \.project-progress__copy \{[^}]*background:var\(--white\);[^}]*animation:none;/,
  );
});

test("all-complete progress has no active visual state", () => {
  const progress = deriveProjectProgress(authority({
    state: "DELIVERED",
    m3Status: "CONFIRMED",
  }));
  assert.deepEqual(statuses(progress), ["done", "done", "done", "done", "done"]);
  assert.equal(progress.steps.some(({ status }) => status === "in_progress"), false);
});

test("reduced motion disables project pulse and laser while preserving active green", () => {
  assert.match(
    dashboardCss,
    /@media \(prefers-reduced-motion:reduce\) \{[^}]*animation:none!important;/,
  );
  assert.match(
    dashboardCss,
    /\.project-progress li\[data-state="in_progress"\] \.project-progress__copy \{[^}]*background:#f3faf6;/,
  );
});
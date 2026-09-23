import assert from "node:assert/strict";
import test from "node:test";
import {
  createPreviewBuildController,
  describePreviewBuildState,
  isTerminalBuildStatus,
} from "./operator-website-preview-build.mjs";

test("isTerminalBuildStatus recognizes exactly the three terminal statuses", () => {
  assert.equal(isTerminalBuildStatus("PASS"), true);
  assert.equal(isTerminalBuildStatus("PASS_WITH_WARNINGS"), true);
  assert.equal(isTerminalBuildStatus("FAILED"), true);
  assert.equal(isTerminalBuildStatus("BUILD_IN_PROGRESS"), false);
  assert.equal(isTerminalBuildStatus("SOMETHING_ELSE"), false);
});

test("describePreviewBuildState never exposes anything beyond a fixed label/tone pair", () => {
  for (const status of ["BUILD_IN_PROGRESS", "PASS", "PASS_WITH_WARNINGS", "FAILED", "UNKNOWN"]) {
    const described = describePreviewBuildState(status);
    assert.deepEqual(Object.keys(described).sort(), ["label", "tone"]);
    assert.equal(typeof described.label, "string");
    assert.equal(typeof described.tone, "string");
  }
});

test("controller polls until PASS and emits BUILD_IN_PROGRESS then the terminal state", async () => {
  const emitted = [];
  let statusCalls = 0;
  const controller = createPreviewBuildController({
    startBuild: async () => ({ leaseId: "lease-1" }),
    getBuildStatus: async (leaseId) => {
      statusCalls += 1;
      assert.equal(leaseId, "lease-1");
      return statusCalls < 3
        ? { status: "BUILD_IN_PROGRESS" }
        : { status: "PASS", previewBuildId: "build-1" };
    },
    onStateChange: (state) => emitted.push(state.status),
    wait: async () => {}, // no real delay in tests
  });
  const result = await controller.start({ quoteRequestId: "qr-1" });
  assert.equal(result.status, "PASS");
  assert.equal(result.previewBuildId, "build-1");
  assert.deepEqual(emitted, ["BUILD_IN_PROGRESS", "BUILD_IN_PROGRESS", "BUILD_IN_PROGRESS", "PASS"]);
});

test("controller reports PASS_WITH_WARNINGS as a terminal state without further polling", async () => {
  let statusCalls = 0;
  const controller = createPreviewBuildController({
    startBuild: async () => ({ leaseId: "lease-2" }),
    getBuildStatus: async () => {
      statusCalls += 1;
      return { status: "PASS_WITH_WARNINGS", previewBuildId: "build-2" };
    },
    onStateChange: () => {},
    wait: async () => {},
  });
  const result = await controller.start({ quoteRequestId: "qr-1" });
  assert.equal(result.status, "PASS_WITH_WARNINGS");
  assert.equal(statusCalls, 1);
});

test("controller stops polling and reports FAILED once the build lease TTL is exceeded", async () => {
  let simulatedNow = 0;
  const controller = createPreviewBuildController({
    startBuild: async () => ({ leaseId: "lease-3" }),
    getBuildStatus: async () => ({ status: "BUILD_IN_PROGRESS" }),
    onStateChange: () => {},
    now: () => simulatedNow,
    wait: async () => {
      simulatedNow += 10 * 60 * 1000; // fast-forward 10 minutes per poll
    },
    leaseTtlMs: 20 * 60 * 1000,
  });
  const result = await controller.start({ quoteRequestId: "qr-1" });
  assert.equal(result.status, "FAILED");
  assert.equal(result.reason, "BUILD_LEASE_EXPIRED");
});

test("cancel() stops the poll loop without throwing", async () => {
  let cancelledAfterFirstPoll = false;
  const controller = createPreviewBuildController({
    startBuild: async () => ({ leaseId: "lease-4" }),
    getBuildStatus: async () => {
      if (!cancelledAfterFirstPoll) {
        cancelledAfterFirstPoll = true;
        controller.cancel();
      }
      return { status: "BUILD_IN_PROGRESS" };
    },
    onStateChange: () => {},
    wait: async () => {},
  });
  const result = await controller.start({ quoteRequestId: "qr-1" });
  assert.equal(result.status, "CANCELLED");
});

test("throws a clear configuration error when required dependencies are missing", () => {
  assert.throws(
    () => createPreviewBuildController({}),
    /PREVIEW_BUILD_CONTROLLER_CONFIGURATION_ERROR/,
  );
});

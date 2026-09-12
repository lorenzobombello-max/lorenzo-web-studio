import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

import {
  REQUIRED_RELEASE_CHECKS,
  compareDossierCounts,
  evaluateReleaseGate,
} from "./dossier-continuity-regression-gate.mjs";

const root = new URL("../", import.meta.url);
const text = (path) => readFile(new URL(path, root), "utf8");

test("every mandatory continuity failure blocks production", () => {
  const passing = Object.fromEntries(REQUIRED_RELEASE_CHECKS.map((name) => [name, true]));
  assert.equal(evaluateReleaseGate(passing).productionReleaseAllowed, "JA");

  for (const check of [
    "CORS",
    "JWT_FORWARDING",
    "PENDING_RPC",
    "ACTIVE_RPC",
    "DETAIL_RPC",
    "SENTINEL",
    "PRE_POST_COUNT_GUARD",
  ]) {
    const result = evaluateReleaseGate({ ...passing, [check]: false });
    assert.equal(result.releaseGate, "FAIL", check);
    assert.equal(result.productionReleaseAllowed, "NEE", check);
  }
});

test("count drift returns a non-zero release decision", async () => {
  const before = { TOTAL_RAW: 2, TOTAL_PENDING: 1, TOTAL_ACTIVE: 1, TOTAL_TRASHED: 0 };
  const after = { ...before, TOTAL_ACTIVE: 0 };
  assert.deepEqual(compareDossierCounts(before, after), {
    pass: false,
    changed: ["TOTAL_ACTIVE"],
  });

  const directory = await mkdtemp(join(tmpdir(), "lws-dossier-gate-"));
  try {
    const beforePath = join(directory, "before.json");
    const afterPath = join(directory, "after.json");
    await writeFile(beforePath, JSON.stringify(before));
    await writeFile(afterPath, JSON.stringify(after));
    const result = spawnSync(process.execPath, [
      fileURLToPath(new URL("scripts/dossier-continuity-regression-gate.mjs", root)),
      "compare",
      "--before",
      beforePath,
      "--after",
      afterPath,
    ], { encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stdout, /PRE_POST_COUNT_GUARD=FAIL/);
    assert.match(result.stdout, /PRODUCTION_RELEASE_ALLOWED=NEE/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("the release runner exits non-zero and denies approval when a phase cannot complete", async () => {
  const directory = await mkdtemp(join(tmpdir(), "lws-release-runner-"));
  try {
    const result = spawnSync("pwsh", [
      "-NoProfile",
      "-File",
      fileURLToPath(new URL("scripts/invoke-dossier-continuity-release-gate.ps1", root)),
      "-Phase",
      "PostDeploy",
      "-BeforeSnapshot",
      join(directory, "missing-before.json"),
      "-AfterSnapshot",
      join(directory, "after.json"),
    ], { encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(`${result.stdout}\n${result.stderr}`, /PRODUCTION_RELEASE_ALLOWED=NEE/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("Pages and Edge releases require the same pre and post continuity gates", async () => {
  const [pages, edge, runner, preservation] = await Promise.all([
    text(".github/workflows/deploy-pages.yml"),
    text(".github/workflows/deploy-commercial-operator-command.yml"),
    text("scripts/invoke-dossier-continuity-release-gate.ps1"),
    text("scripts/test-production-release.ps1"),
  ]);

  for (const workflow of [pages, edge]) {
    assert.match(workflow, /invoke-dossier-continuity-release-gate\.ps1 -Phase PreDeploy/);
    assert.match(workflow, /invoke-dossier-continuity-release-gate\.ps1 -Phase PostDeploy/);
    assert.match(workflow, /dossier-continuity-before/);
    assert.doesNotMatch(workflow, /continue-on-error\s*:\s*true/i);
  }
  assert.match(pages, /needs:\s*continuity-predeploy/);
  assert.match(pages, /needs:\s*continuity-postdeploy/);
  assert.match(edge, /functions deploy commercial-operator-command/);
  assert.match(edge, /github\.ref[^\n]+refs\/heads\/main/);
  assert.match(runner, /PRODUCTION_RELEASE_ALLOWED=NEE/);
  assert.match(runner, /dossier-continuity-regression-gate\.mjs local/);
  assert.match(runner, /dossier-continuity-regression-gate\.mjs snapshot/);
  assert.match(runner, /dossier-continuity-regression-gate\.mjs compare/);
  assert.match(preservation, /invoke-dossier-continuity-release-gate\.ps1 -Phase Local/);
});

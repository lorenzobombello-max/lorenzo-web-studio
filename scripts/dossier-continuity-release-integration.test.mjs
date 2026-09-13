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
const psQuote = (value) => `'${String(value).replaceAll("'", "''")}'`;

function ciEnvironment(overrides = {}) {
  return {
    ...process.env,
    LWS_RELEASE_SMOKE_EMAIL: "release-smoke@example.invalid",
    LWS_RELEASE_SMOKE_PASSWORD: "synthetic-password-never-use",
    LWS_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_synthetic_public_key",
    ...overrides,
  };
}

test("CI auth wrapper mints only a short-lived caller JWT and fails closed", async () => {
  const wrapperPath = fileURLToPath(new URL("scripts/invoke-dossier-continuity-ci-gate.ps1", root));
  const wrapper = await text("scripts/invoke-dossier-continuity-ci-gate.ps1");
  assert.match(wrapper, /auth\/v1\/token\?grant_type=password/);
  assert.match(wrapper, /\.access_token/);
  assert.match(wrapper, /\$env:LWS_OPERATOR_JWT\s*=\s*\$accessToken/);
  assert.match(wrapper, /invoke-dossier-continuity-release-gate\.ps1/);
  assert.match(wrapper, /finally\s*\{/);
  for (const name of [
    "LWS_OPERATOR_JWT",
    "LWS_SUPABASE_ANON_KEY",
    "LWS_RELEASE_SMOKE_EMAIL",
    "LWS_RELEASE_SMOKE_PASSWORD",
  ]) assert.match(wrapper, new RegExp(`Remove-Item Env:${name}`));
  assert.doesNotMatch(wrapper, /refresh_token/i);
  assert.doesNotMatch(wrapper, /\$env:(?:SUPABASE_)?SERVICE[_-]?ROLE/i);
  assert.doesNotMatch(wrapper, /Authorization[^\n]*service[_-]?role/i);
  assert.doesNotMatch(wrapper, /Write-(?:Host|Output)[^\n]*(?:accessToken|LWS_OPERATOR_JWT)/i);

  const missing = spawnSync("pwsh", ["-NoProfile", "-File", wrapperPath, "-Phase", "PreDeploy"], {
    encoding: "utf8",
    env: ciEnvironment({ LWS_RELEASE_SMOKE_EMAIL: "" }),
  });
  assert.notEqual(missing.status, 0);
  assert.match(`${missing.stdout}\n${missing.stderr}`, /LWS_RELEASE_SMOKE_EMAIL_REQUIRED/);

  const missingPassword = spawnSync("pwsh", ["-NoProfile", "-File", wrapperPath, "-Phase", "PreDeploy"], {
    encoding: "utf8",
    env: ciEnvironment({ LWS_RELEASE_SMOKE_PASSWORD: "" }),
  });
  assert.notEqual(missingPassword.status, 0);
  assert.match(`${missingPassword.stdout}\n${missingPassword.stderr}`, /LWS_RELEASE_SMOKE_PASSWORD_REQUIRED/);

  const authFailure = spawnSync("pwsh", ["-NoProfile", "-Command", [
    "function global:Invoke-RestMethod { param($Method,$Uri,$Headers,$ContentType,$Body) throw 'synthetic rejection' }",
    `& ${psQuote(wrapperPath)} -Phase PreDeploy`,
  ].join("; ")], { encoding: "utf8", env: ciEnvironment() });
  assert.notEqual(authFailure.status, 0);
  const authFailureOutput = `${authFailure.stdout}\n${authFailure.stderr}`;
  assert.match(authFailureOutput, /RELEASE_SMOKE_AUTH_FAILED/);
  assert.doesNotMatch(authFailureOutput, /synthetic-password-never-use/);

  const payload = Buffer.from(JSON.stringify({ exp: 4102444800 })).toString("base64url");
  const token = `eyJhbGciOiJub25lIn0.${payload}.${"s".repeat(96)}`;
  const directory = await mkdtemp(join(tmpdir(), "lws-ci-auth-cleanup-"));
  try {
    const cleanup = spawnSync("pwsh", ["-NoProfile", "-Command", [
      "function global:Invoke-RestMethod { param($Method,$Uri,$Headers,$ContentType,$Body) [pscustomobject]@{ access_token = $env:LWS_TEST_ACCESS_TOKEN } }",
      `try { & ${psQuote(wrapperPath)} -Phase PostDeploy -BeforeSnapshot ${psQuote(join(directory, "missing-before.json"))} } catch { }`,
      "Write-Output ('JWT_CLEARED=' + [string]::IsNullOrEmpty($env:LWS_OPERATOR_JWT))",
      "Write-Output ('ANON_CLEARED=' + [string]::IsNullOrEmpty($env:LWS_SUPABASE_ANON_KEY))",
      "Write-Output ('EMAIL_CLEARED=' + [string]::IsNullOrEmpty($env:LWS_RELEASE_SMOKE_EMAIL))",
      "Write-Output ('PASSWORD_CLEARED=' + [string]::IsNullOrEmpty($env:LWS_RELEASE_SMOKE_PASSWORD))",
    ].join("; ")], {
      encoding: "utf8",
      env: ciEnvironment({ LWS_TEST_ACCESS_TOKEN: token }),
    });
    assert.equal(cleanup.status, 0);
    assert.match(cleanup.stdout, /JWT_CLEARED=True/);
    assert.match(cleanup.stdout, /ANON_CLEARED=True/);
    assert.match(cleanup.stdout, /EMAIL_CLEARED=True/);
    assert.match(cleanup.stdout, /PASSWORD_CLEARED=True/);
    assert.doesNotMatch(`${cleanup.stdout}\n${cleanup.stderr}`, new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

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

test("Pages and Edge releases require the same runtime-authenticated pre and post continuity gates", async () => {
  const [pages, edge, runner, ciRunner, preservation] = await Promise.all([
    text(".github/workflows/deploy-pages.yml"),
    text(".github/workflows/deploy-commercial-operator-command.yml"),
    text("scripts/invoke-dossier-continuity-release-gate.ps1"),
    text("scripts/invoke-dossier-continuity-ci-gate.ps1"),
    text("scripts/test-production-release.ps1"),
  ]);

  for (const workflow of [pages, edge]) {
    assert.match(workflow, /invoke-dossier-continuity-ci-gate\.ps1 -Phase PreDeploy/);
    assert.match(workflow, /invoke-dossier-continuity-ci-gate\.ps1 -Phase PostDeploy/);
    assert.match(workflow, /environment:\s*production-continuity/g);
    assert.match(workflow, /secrets\.LWS_RELEASE_SMOKE_EMAIL/);
    assert.match(workflow, /secrets\.LWS_RELEASE_SMOKE_PASSWORD/);
    assert.match(workflow, /vars\.LWS_SUPABASE_PUBLISHABLE_KEY/);
    assert.doesNotMatch(workflow, /LWS_OPERATOR_JWT/);
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
  assert.match(ciRunner, /invoke-dossier-continuity-release-gate\.ps1/);
  assert.doesNotMatch(ciRunner, /refresh_token/i);
  assert.match(preservation, /invoke-dossier-continuity-release-gate\.ps1 -Phase Local/);
});

test("PRE_PROJECT release evidence includes deterministic desktop and mobile frame sampling", async () => {
  const preview = await text("scripts/website-concept-pre-project-live-preview.test.mjs");
  assert.match(preview, /initializeOperatorWebsiteExecution/);
  assert.match(preview, /new MutationObserver/);
  assert.match(preview, /waitForTimeout\(16\)/);
  assert.match(preview, /\{ width: 1280, height: 800 \}/);
  assert.match(preview, /\{ width: 390, height: 844 \}/);
  assert.match(preview, /for \(const phase of \[1, 2, 3\]\)/);
  assert.match(preview, /OPERATOR_NOT_AUTHORIZED/);
});

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("operator shell links to the canonical dashboard route", async () => {
  const source = await read("operator/index.html");
  assert.match(source, /href="\/operator\/dashboard\/"/);
});

test("dashboard remains hidden until the authorization guard succeeds", async () => {
  const source = await read("operator/dashboard/index.html");
  assert.match(source, /id="operatorDashboard" hidden/);
  assert.match(source, /operator-dashboard-guard\.mjs/);
});

test("dashboard guard requires database-backed operator authorization", async () => {
  const source = await read("assets/js/operator-dashboard-guard.mjs");
  assert.match(source, /requireAuthorizedOperator/);
  assert.match(source, /access\.status === "unauthenticated"/);
  assert.match(source, /access\.status === "unauthorized"/);
  assert.match(source, /await loadScript\("\/assets\/js\/operator-dashboard-contract\.js"\)/);
  assert.match(source, /await loadScript\("\/assets\/js\/operator-dashboard\.js"\)/);
  assert.match(source, /dashboard\.hidden = false/);
});

test("session shell uses the same database-backed authorization", async () => {
  const source = await read("assets/js/operator-shell.mjs");
  assert.match(source, /requireAuthorizedOperator/);
  assert.doesNotMatch(source, /requireOperatorSession/);
});

test("Phase-5D dashboard contract and presentation remain present", async () => {
  const [html, contract, script, css] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard-contract.js"),
    read("assets/js/operator-dashboard.js"),
    read("assets/css/operator-dashboard.css"),
  ]);
  assert.match(html, /Synthetic Project/);
  assert.match(html, /FISCAL PRODUCTION STATUS:/);
  assert.match(contract, /LWS_DASHBOARD_CONTRACT/);
  assert.match(script, /lws-phase5d-synthetic-state-v1/);
  assert.match(css, /\.dashboard-grid/);
});
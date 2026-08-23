import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { operatorHandoffPath, scrubAdminIntakeUrl } from "../assets/js/admin-intake.js";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("Open in Operator routes only by the exact human application reference", () => {
  assert.equal(
    operatorHandoffPath("LWS-AAN-2099-0401"),
    "/operator/dashboard/?application=LWS-AAN-2099-0401",
  );
  assert.equal(operatorHandoffPath("a1100000-0000-4000-8000-000000000003"), null);
  assert.equal(operatorHandoffPath("LWS-2099-0401"), null);
  assert.equal(operatorHandoffPath(null), null);
});

test("Open in Operator never forwards the secure admin capability", () => {
  const sourceUrl = new URL("https://example.test/pages/admin-intake.html?token=QUERY_SECRET#token=HASH_SECRET");
  const target = new URL(operatorHandoffPath("LWS-AAN-2099-0401"), sourceUrl);
  assert.equal(target.pathname, "/operator/dashboard/");
  assert.equal(target.search, "?application=LWS-AAN-2099-0401");
  assert.equal(target.hash, "");
  assert.equal(target.searchParams.has("token"), false);
  assert.doesNotMatch(target.href, /QUERY_SECRET|HASH_SECRET/);
});

test("admin intake removes hash and every query-token case before rendering", () => {
  assert.equal(
    scrubAdminIntakeUrl("https://example.test/pages/admin-intake.html?view=detail&Token=QUERY_SECRET#token=HASH_SECRET"),
    "/pages/admin-intake.html?view=detail",
  );
  assert.equal(
    scrubAdminIntakeUrl("https://example.test/pages/admin-intake.html?token=one&TOKEN=two"),
    "/pages/admin-intake.html",
  );
});

test("admin intake exposes the handoff only after validated detail and blocks referrer leakage", async () => {
  const [html, script] = await Promise.all([
    read("pages/admin-intake.html"),
    read("assets/js/admin-intake.js"),
  ]);
  assert.match(html, /id="adminBriefingOperator"[^>]+referrerpolicy="no-referrer"[^>]+hidden/);
  assert.match(html, /<meta name="referrer" content="no-referrer"/);
  assert.match(script, /operatorHandoffPath\(application\?\.applicationReference\)/);
  assert.match(script, /operatorLink\.hidden = !operatorPath/);
  assert.match(script, /history\.replaceState\(null, "", scrubAdminIntakeUrl\(window\.location\.href\)\)/);
  assert.doesNotMatch(script, /localStorage|console\.(?:log|info|debug)/);
});

test("handoff lands on the existing authorization guard without bypassing login", async () => {
  const [dashboard, guard] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard-guard.mjs"),
  ]);
  assert.match(dashboard, /id="operatorDashboard" hidden/);
  assert.match(dashboard, /operator-dashboard-guard\.mjs/);
  assert.match(guard, /requireAuthorizedOperator/);
  assert.match(guard, /OPERATOR_ROUTES\.login/);
});
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { operatorProfilePresentation } from "../assets/js/operator-profile.mjs";

const root = new URL("../", import.meta.url);
const read = (path)=>readFile(new URL(path, root), "utf8");
const profiles = [
  { profile_code: "OP-01", display_name: "Lorenzo Bombello", email: "lorenzo@lorenzowebsolutions.be", role: "owner", role_label: "Owner", status: "ACTIVE" },
  { profile_code: "OP-02", display_name: "Herlinde Verlodt", email: "herlinde@lorenzowebsolutions.be", role: "operations_manager", role_label: "Management / HR & Operations", status: "ACTIVE" },
  { profile_code: "OP-03", display_name: "Daisy Defraine", email: "finance@lorenzowebsolutions.be", role: "finance", role_label: "Finance", status: "ACTIVE" },
];

test("the shared renderer accepts exactly the three approved server profiles", () => {
  for (const profile of profiles) {
    assert.deepEqual(operatorProfilePresentation(profile), {
      code: profile.profile_code,
      displayName: profile.display_name,
      email: profile.email,
      roleLabel: profile.role_label,
    });
  }
});

test("profile presentation rejects client role drift and extra authority fields", () => {
  assert.throws(()=>operatorProfilePresentation({ ...profiles[2], role: "owner" }), /INVALID_OPERATOR_PROFILE/);
  assert.throws(()=>operatorProfilePresentation({ ...profiles[0], operator_id: "not-client-authority" }), /INVALID_OPERATOR_PROFILE/);
  assert.throws(()=>operatorProfilePresentation({ ...profiles[1], email: profiles[1].email.toUpperCase() }), /INVALID_OPERATOR_PROFILE/);
});

test("migration binds exact Auth email and keeps Finance outside commercial work roles", async () => {
  const migration = await read("supabase/migrations/20260903170000_add_operator_profile_authority_v1.sql");
  for (const profile of profiles) assert.match(migration, new RegExp(profile.email.replaceAll(".", "\\.")));
  assert.match(migration, /auth_user\.email = profile\.email/);
  assert.match(migration, /auth_user\.id = v_subject/);
  assert.match(migration, /auth_user\.email_confirmed_at is not null/);
  assert.match(migration, /'role', 'profile_only'/);
  assert.doesNotMatch(migration, /commercial_operators_role_check[\s\S]*finance/);
});

test("dashboard contains one shared profile panel and no profile-specific test screen", async () => {
  const [html, dashboard] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/js/operator-dashboard.js"),
  ]);
  assert.equal((html.match(/data-module-panel="profile"/g) || []).length, 1);
  assert.match(dashboard, /initializeOperatorProfile\(document, client\)/);
  assert.doesNotMatch(html, /testprofiel|profile-test|profieltest/i);
});

test("separate Operator test screen is static synthetic and action-free", async () => {
  const [html, prepare, verify] = await Promise.all([
    read("operator/test/index.html"),
    read("scripts/prepare-pages-dist.ps1"),
    read("scripts/verify-pages-dist.ps1"),
  ]);
  assert.match(html, /TESTOMGEVING/);
  assert.match(html, /Synthetische lokale testdata/);
  assert.match(html, /Geen productiegegevens of echte acties/);
  assert.doesNotMatch(html, /<script\b|<button\b|<form\b|\bsupabase\b|\bfetch\s*\(|\.rpc\s*\(/i);
  for (const source of [prepare, verify]) {
    assert.match(source, /operator\/test\/index\.html/);
    assert.match(source, /assets\/css\/operator-test\.css/);
    assert.match(source, /assets\/js\/operator-profile\.mjs/);
  }
});
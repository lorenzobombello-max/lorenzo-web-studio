import assert from "node:assert/strict";
import test from "node:test";
import { buildSdfCapacityPreviewPresentation } from "../assets/js/sdf-budget-guard-capacity-preview.mjs";

const ready = (minimum, reasons = []) => ({
  preview_status: "READY",
  preview_kind: "CAPACITY_ONLY",
  minimum_capacity_package: minimum,
  maatwerk_required_by_capacity: minimum === "maatwerk",
  reasons,
  final_decision_pending: true,
  pending_authorities: ["complexity_level", "exceptional_scope"],
});

test("incomplete preview stays neutral and disables no package", () => {
  const view = buildSdfCapacityPreviewPresentation({ preview_status: "INCOMPLETE", preview_kind: "CAPACITY_ONLY", minimum_capacity_package: null, reasons: [], final_decision_pending: true, pending_authorities: ["complexity_level", "exceptional_scope"] });
  assert.equal(view.state, "incomplete");
  assert.match(view.message, /wordt berekend zodra/i);
  assert.deepEqual(view.disabledPackages, []);
});

test("START is capacity-fit but explicitly not final", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("start"));
  assert.equal(view.minimumLabel, "START");
  assert.match(view.message, /past START momenteel/i);
  assert.match(view.detail, /definitieve minimale formule volgt/i);
  assert.deepEqual(view.disabledPackages, []);
});

test("GROEI makes only START capacity-incompatible", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("groei"));
  assert.deepEqual(view.disabledPackages, ["start"]);
  assert.match(view.unavailableReason, /past niet bij huidige capaciteit/i);
});

test("PRO makes START and GROEI capacity-incompatible", () => {
  assert.deepEqual(buildSdfCapacityPreviewPresentation(ready("pro")).disabledPackages, ["start", "groei"]);
});

test("numeric MAATWERK makes every fixed package capacity-incompatible", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("maatwerk"));
  assert.deepEqual(view.disabledPackages, ["start", "groei", "pro"]);
  assert.match(view.message, /Maatwerk is vereist op basis van de opgegeven capaciteit/i);
  assert.match(view.detail, /volledige scope wordt na indiening commercieel bevestigd/i);
});

test("higher package tiers remain selectable", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("groei"));
  assert.equal(view.packageStates.groei.disabled, false);
  assert.equal(view.packageStates.pro.disabled, false);
  assert.equal(view.packageStates.maatwerk.disabled, false);
});

test("ADVIES GEWENST remains selectable and does not erase preview minimum", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("pro"), "advice_requested");
  assert.equal(view.minimumLabel, "PRO");
  assert.equal(view.packageStates.advice_requested.disabled, false);
});

test("preview is visibly labeled preliminary and capacity-based", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("groei"));
  assert.equal(view.heading, "Budget Guard — voorlopige capaciteitscheck");
  assert.equal(view.badge, "Voorlopig · alleen capaciteit");
});

test("owner/admin complexity and exceptional-scope review stays visibly pending", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("groei"));
  assert.match(view.detail, /complexiteit en uitzonderlijke scope/i);
  assert.equal(view.finalDecisionPending, true);
});

test("technical failure presents no package default or locks", () => {
  const view = buildSdfCapacityPreviewPresentation(null);
  assert.equal(view.state, "error");
  assert.match(view.message, /kon momenteel niet worden berekend/i);
  assert.equal(view.minimumLabel, "");
  assert.deepEqual(view.disabledPackages, []);
});

test("presentation excludes internal IDs, hashes, and fingerprints", () => {
  const view = buildSdfCapacityPreviewPresentation({ ...ready("start"), intake_id: "secret", owner_id: "secret", decision_fingerprint: "secret", sha256: "secret" });
  assert.doesNotMatch(JSON.stringify(view), /secret|intake_id|owner_id|fingerprint|sha256/i);
});

test("disabled lower package states support native keyboard blocking and text reasons", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("pro"));
  assert.deepEqual(view.packageStates.start, { disabled: true, reason: "Past niet bij huidige capaciteit" });
  assert.deepEqual(view.packageStates.groei, { disabled: true, reason: "Past niet bij huidige capaciteit" });
});

test("server dimension reasons are rendered as customer-safe capacity facts", () => {
  const view = buildSdfCapacityPreviewPresentation(ready("groei", [{ dimension: "flow_count", value: 2, minimum_capacity_package: "groei" }]));
  assert.deepEqual(view.reasons, ["Aantal flows: 2 — minimaal GROEI op basis van capaciteit."]);
});
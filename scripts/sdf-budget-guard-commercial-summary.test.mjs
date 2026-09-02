import assert from "node:assert/strict";
import test from "node:test";
import {
  buildSdfCommercialSummary,
  shouldApplySdfCapacityPreview,
} from "../assets/js/sdf-budget-guard-commercial-summary.mjs";

const ready = (minimum, overrides = {}) => ({
  preview_status: "READY",
  preview_kind: "CAPACITY_ONLY",
  minimum_capacity_package: minimum,
  maatwerk_required_by_capacity: minimum === "maatwerk",
  normalized_capacity: {
    flow_count: 3,
    document_type_count: 4,
    pages_per_month: 1800,
    user_count: 8,
  },
  reasons: [],
  final_decision_pending: true,
  pending_authorities: ["complexity_level", "exceptional_scope"],
  ...overrides,
});

const summary = (previewResult, selectedDirection = "", loading = false) =>
  buildSdfCommercialSummary({ previewResult, selectedDirection, loading });

test("incomplete capacity shows no package price", () => {
  const view = summary({
    preview_status: "INCOMPLETE",
    preview_kind: "CAPACITY_ONLY",
    minimum_capacity_package: null,
    final_decision_pending: true,
    pending_authorities: ["complexity_level", "exceptional_scope"],
  });
  assert.equal(view.state, "incomplete");
  assert.equal(view.packageLabel, "Nog niet berekend");
  assert.equal(view.implementationPrice, "");
  assert.equal(view.recurringPrice, "");
});

for (const [minimum, implementationPrice, recurringPrice] of [
  ["start", "€ 2.850", "€ 175 / maand"],
  ["groei", "€ 5.700", "€ 299 / maand"],
  ["pro", "€ 7.500", "€ 449 / maand"],
]) {
  test(`${minimum.toUpperCase()} capacity maps to its frozen public prices`, () => {
    const view = summary(ready(minimum));
    assert.equal(view.packageLabel, minimum.toUpperCase());
    assert.equal(view.implementationPrice, implementationPrice);
    assert.equal(view.recurringPrice, recurringPrice);
    assert.equal(view.minimumLabel, minimum.toUpperCase());
    assert.equal(view.isPreliminary, true);
    assert.equal(view.finalReviewPending, true);
  });
}

test("MAATWERK capacity has no fixed implementation or recurring price", () => {
  const view = summary(ready("maatwerk"));
  assert.equal(view.packageLabel, "MAATWERK");
  assert.equal(view.implementationPrice, "");
  assert.equal(view.recurringPrice, "");
  assert.match(view.priceMessage, /Prijs na beoordeling\/offerte/);
});

test("START to GROEI server update changes both prices", () => {
  assert.equal(summary(ready("start")).implementationPrice, "€ 2.850");
  const updated = summary(ready("groei"));
  assert.equal(updated.implementationPrice, "€ 5.700");
  assert.equal(updated.recurringPrice, "€ 299 / maand");
});

test("GROEI to PRO server update changes both prices", () => {
  assert.equal(summary(ready("groei")).packageLabel, "GROEI");
  const updated = summary(ready("pro"));
  assert.equal(updated.packageLabel, "PRO");
  assert.equal(updated.implementationPrice, "€ 7.500");
  assert.equal(updated.recurringPrice, "€ 449 / maand");
});

test("PRO to MAATWERK server update removes every fixed price", () => {
  assert.equal(summary(ready("pro")).recurringPrice, "€ 449 / maand");
  const updated = summary(ready("maatwerk"));
  assert.equal(updated.implementationPrice, "");
  assert.equal(updated.recurringPrice, "");
});

test("only the newest async preview response may render", () => {
  assert.equal(shouldApplySdfCapacityPreview(7, 8), false);
  assert.equal(shouldApplySdfCapacityPreview(8, 8), true);
});

test("server failure has no package or price fallback", () => {
  const view = summary(null);
  assert.equal(view.state, "error");
  assert.equal(view.packageLabel, "Tijdelijk niet beschikbaar");
  assert.equal(view.implementationPrice, "");
  assert.equal(view.recurringPrice, "");
});

test("selected PRO while minimum GROEI shows PRO prices and retains GROEI minimum", () => {
  const view = summary(ready("groei"), "pro");
  assert.equal(view.packageLabel, "PRO");
  assert.equal(view.implementationPrice, "€ 7.500");
  assert.equal(view.recurringPrice, "€ 449 / maand");
  assert.equal(view.minimumLabel, "GROEI");
  assert.match(view.selectionContext, /Gekozen formule/);
});

test("ADVIES GEWENST retains the GROEI capacity basis without an advice price", () => {
  const view = summary(ready("groei"), "advice_requested");
  assert.equal(view.packageLabel, "ADVIES GEWENST");
  assert.equal(view.minimumLabel, "GROEI");
  assert.equal(view.implementationPrice, "€ 5.700");
  assert.equal(view.recurringPrice, "€ 299 / maand");
  assert.match(view.selectionContext, /Indicatieve pakketbasis/);
  assert.match(view.detail, /Definitieve keuze wordt samen bevestigd/);
});

test("MAATWERK never receives the PRO recurring fallback", () => {
  const serialized = JSON.stringify(summary(ready("maatwerk")));
  assert.doesNotMatch(serialized, /449/);
});

test("presenter never invents per-page, per-flow, or per-user pricing", () => {
  for (const minimum of ["start", "groei", "pro", "maatwerk"]) {
    assert.doesNotMatch(JSON.stringify(summary(ready(minimum))), /€\s*\/\s*(?:pagina|page|flow|gebruiker|user)/i);
  }
});

test("a UI-selected lower or unknown package cannot forge the server minimum", () => {
  for (const forged of ["start", "invalid", "START", null]) {
    const view = summary(ready("pro"), forged);
    assert.equal(view.packageLabel, "PRO");
    assert.equal(view.minimumLabel, "PRO");
  }
});

test("loading state removes stale package and prices", () => {
  const view = summary(ready("pro"), "pro", true);
  assert.equal(view.state, "loading");
  assert.equal(view.packageLabel, "Nieuwe inschatting wordt berekend…");
  assert.equal(view.implementationPrice, "");
  assert.equal(view.recurringPrice, "");
});

test("normalized capacity is presented as concise customer facts", () => {
  assert.deepEqual(summary(ready("groei")).capacityFacts, [
    "3 flows",
    "4 documenttypes",
    "1.800 pagina's / maand",
    "8 gebruikers",
  ]);
});

test("server reasons are converted to customer-safe package explanations", () => {
  const view = summary(ready("pro", {
    reasons: [{ dimension: "flow_count", value: 4, minimum_capacity_package: "pro" }],
  }));
  assert.deepEqual(view.reasons, ["Aantal flows: 4 — minimaal PRO op basis van capaciteit."]);
});

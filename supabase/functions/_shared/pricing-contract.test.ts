import { assertEquals, assertMatch, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import {
  canonicalizePricingConfig,
  computePricingConfigHash,
  PRICING_CONFIG,
} from "./pricing-config.ts";
import {
  buildPricingSnapshotV2,
  calculateBudgetGuard,
  evaluateBudget,
  resolveBudgetEvidence,
  selectPricingSnapshotForSubmit,
} from "./pricing-engine.ts";

function calculation(knownMinimumMinor: number, manualReviewRequired = false) {
  const value = calculateBudgetGuard({ requested_pages: ["home"] }).calculation;
  return {
    ...value,
    knownMinimumMinor,
    manualReviewRequired,
    manualReasons: manualReviewRequired ? ["manual_test"] : [],
  };
}

function budgetGuardEvidence(code: keyof typeof PRICING_CONFIG.budgetEvaluation.categories) {
  const category = PRICING_CONFIG.budgetEvaluation.categories[code];
  return resolveBudgetEvidence(
    category.originalLabel,
    "budget_guard_v1",
    code,
  );
}

Deno.test("canonical config serialization ignores object insertion order and preserves arrays", () => {
  const left = { z: ["first", "second"], a: { y: 2, x: 1 } };
  const right = { a: { x: 1, y: 2 }, z: ["first", "second"] };
  assertEquals(canonicalizePricingConfig(left), canonicalizePricingConfig(right));
  assertEquals(canonicalizePricingConfig(left), '{"a":{"x":1,"y":2},"z":["first","second"]}');
  assertNotEquals(
    canonicalizePricingConfig(left),
    canonicalizePricingConfig({ ...left, z: ["second", "first"] }),
  );
});

Deno.test("canonical config rejects unsupported JSON representations", async () => {
  for (const value of [NaN, Infinity, -Infinity, -0, 1.5, undefined, 1n, () => null, Symbol("x")]) {
    await assertRejects(
      async () => await computePricingConfigHash({ value }),
      TypeError,
    );
  }
  const sparse = Array(1);
  await assertRejects(async () => await computePricingConfigHash(sparse), TypeError);
  const cyclic: Record<string, unknown> = {};
  cyclic.self = cyclic;
  await assertRejects(async () => await computePricingConfigHash(cyclic), TypeError);
  await assertRejects(async () => await computePricingConfigHash(new Date()), TypeError);
});

Deno.test("canonical config rejects hidden, accessor and non-ASCII state", async () => {
  const symbolKeyed = { visible: true } as Record<PropertyKey, unknown>;
  symbolKeyed[Symbol("hidden")] = true;

  const nonEnumerable = { visible: true };
  Object.defineProperty(nonEnumerable, "hidden", {
    value: true,
    enumerable: false,
  });

  const getter = { visible: true };
  Object.defineProperty(getter, "hidden", {
    enumerable: true,
    get: () => {
      throw new Error("canonicalizer must not execute getters");
    },
  });

  const setter = { visible: true };
  Object.defineProperty(setter, "hidden", {
    enumerable: true,
    set: () => undefined,
  });

  for (const value of [
    symbolKeyed,
    nonEnumerable,
    getter,
    setter,
    { "caf\u00e9": true },
  ]) {
    await assertRejects(
      async () => await computePricingConfigHash(value),
      TypeError,
    );
  }
});

Deno.test("config hash is lowercase SHA-256 and covers all authoritative policy", async () => {
  const baseline = await computePricingConfigHash();
  assertMatch(baseline, /^[0-9a-f]{64}$/);

  const reordered = Object.fromEntries(Object.entries(PRICING_CONFIG).reverse());
  assertEquals(await computePricingConfigHash(reordered), baseline);

  const priceChanged = {
    ...PRICING_CONFIG,
    rules: {
      ...PRICING_CONFIG.rules,
      simple_quote_form: {
        ...PRICING_CONFIG.rules.simple_quote_form,
        amountMinor: PRICING_CONFIG.rules.simple_quote_form.amountMinor + 1,
      },
    },
  };
  assertNotEquals(await computePricingConfigHash(priceChanged), baseline);

  const budgetChanged = {
    ...PRICING_CONFIG,
    budgetEvaluation: {
      ...PRICING_CONFIG.budgetEvaluation,
      categories: {
        ...PRICING_CONFIG.budgetEvaluation.categories,
        below_1800: {
          ...PRICING_CONFIG.budgetEvaluation.categories.below_1800,
          upperInclusiveMinor:
            PRICING_CONFIG.budgetEvaluation.categories.below_1800
              .upperInclusiveMinor - 1,
        },
      },
    },
  };
  assertNotEquals(await computePricingConfigHash(budgetChanged), baseline);

  const versionChanged = { ...PRICING_CONFIG, version: "1.0.1" };
  assertNotEquals(await computePricingConfigHash(versionChanged), baseline);
});

Deno.test("budget evaluator applies manual, missing, ambiguous and legacy precedence", () => {
  const below = budgetGuardEvidence("below_1800");
  assertEquals(evaluateBudget(calculation(180_000, true), below), {
    contractVersion: 2,
    ...below,
    status: "manual_review_required",
    outsideBudgetWishes: null,
  });

  const legacy = resolveBudgetEvidence("EUR 3.000 - EUR 6.000", null, null);
  assertEquals(evaluateBudget(calculation(180_000), legacy).status, "legacy_category_not_safely_comparable");
  assertEquals(evaluateBudget(calculation(180_000), legacy).outsideBudgetWishes, null);

  const missing = resolveBudgetEvidence(null, null, null);
  assertEquals(evaluateBudget(calculation(180_000), missing).status, "manual_review_required");
  assertEquals(evaluateBudget(calculation(180_000), missing).outsideBudgetWishes, null);

  const ambiguous = resolveBudgetEvidence("EUR 3.200 t/m EUR 6.000", null, "3200_to_6000_inclusive");
  assertEquals(evaluateBudget(calculation(180_000), ambiguous).status, "manual_review_required");
  assertEquals(evaluateBudget(calculation(180_000), ambiguous).outsideBudgetWishes, null);
});

Deno.test("budget evaluator honors every approved bounded and unbounded edge", () => {
  const below = evaluateBudget(calculation(180_000), budgetGuardEvidence("below_1800"));
  assertEquals([below.status, below.outsideBudgetWishes], ["below_starter_starting_price", true]);

  const lower = budgetGuardEvidence("1800_to_below_3200");
  for (const amount of [180_000, 319_900, 319_999]) {
    const result = evaluateBudget(calculation(amount), lower);
    assertEquals([result.status, result.outsideBudgetWishes], ["possibly_compatible_with_category", false]);
  }
  const exact3200 = evaluateBudget(calculation(320_000), lower);
  assertEquals([exact3200.status, exact3200.outsideBudgetWishes], ["known_minimum_exceeds_category_upper_bound", true]);

  const upper = budgetGuardEvidence("3200_to_6000_inclusive");
  for (const amount of [320_000, 600_000]) {
    const result = evaluateBudget(calculation(amount), upper);
    assertEquals([result.status, result.outsideBudgetWishes], ["possibly_compatible_with_category", false]);
  }
  const above6000 = evaluateBudget(calculation(600_100), upper);
  assertEquals([above6000.status, above6000.outsideBudgetWishes], ["known_minimum_exceeds_category_upper_bound", true]);

  const open = evaluateBudget(calculation(600_100), budgetGuardEvidence("above_6000"));
  assertEquals([open.status, open.outsideBudgetWishes], ["unbounded_category_indeterminate", null]);
});

Deno.test("shared above-6000 label remains legacy without scheme and code", () => {
  const evidence = resolveBudgetEvidence("Meer dan EUR 6.000", null, null);
  assertEquals(evidence.evidenceProvenance, "legacy_label");
  assertEquals(evidence.categoryCode, null);
});

Deno.test("authoritative snapshot has exactly the closed v2 shape", async () => {
  const snapshot = await buildPricingSnapshotV2(
    { requested_pages: ["home"] },
    budgetGuardEvidence("1800_to_below_3200"),
  );
  assertEquals(Object.keys(snapshot).sort(), [
    "budgetEvaluation",
    "calculation",
    "normalizedScope",
    "packageAdvice",
    "pricingConfigHash",
    "pricingConfigVersion",
    "snapshotContractVersion",
  ]);
  assertEquals(snapshot.snapshotContractVersion, 2);
  assertMatch(snapshot.pricingConfigHash, /^[0-9a-f]{64}$/);
  assertEquals(snapshot.budgetEvaluation.outsideBudgetWishes, false);
});

Deno.test("idempotent retry returns the historical snapshot without rebuilding", async () => {
  const historicalSnapshot = {
    snapshotContractVersion: 2,
    pricingConfigVersion: "historical",
    pricingConfigHash: "a".repeat(64),
  };
  let buildCalls = 0;
  const selected = await selectPricingSnapshotForSubmit(
    { requested_pages: ["home"] },
    budgetGuardEvidence("1800_to_below_3200"),
    historicalSnapshot,
    () => {
      buildCalls += 1;
      throw new Error("retry must not rebuild pricing");
    },
  );
  assertEquals(selected, historicalSnapshot);
  assertEquals(buildCalls, 0);
});
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildPricingSnapshotV2,
  buildPricingSnapshotV3,
  resolveBudgetEvidence,
} from "./pricing-engine.ts";
import {
  createPricingSnapshotIntegrity,
  PRICING_SNAPSHOT_INTEGRITY_VERSION,
  verifyPricingSnapshotIntegrity,
} from "./pricing-snapshot-integrity.ts";

const secret = "fix3-test-integrity-key-material-0000000000000001";
const context = "32c31000-0000-4000-8000-000000000001";

function clone<T>(value: T): T {
  return structuredClone(value);
}

async function fixture() {
  const snapshot = await buildPricingSnapshotV2(
    {
      requested_pages: ["home", "quote_request"],
      requested_features: ["quote_form"],
      quote_form_details: { structure_scope: "extended_standard_structure" },
    },
    resolveBudgetEvidence(
      "EUR 3.200 t/m EUR 6.000",
      "budget_guard_v1",
      "3200_to_6000_inclusive",
    ),
  );
  const integrity = await createPricingSnapshotIntegrity(
    snapshot,
    context,
    "v1",
    secret,
  );
  return { snapshot, integrity };
}

Deno.test("authoritative snapshot integrity verifies and is deterministic", async () => {
  const { snapshot, integrity } = await fixture();
  assertEquals(integrity.algorithmVersion, PRICING_SNAPSHOT_INTEGRITY_VERSION);
  assertEquals(integrity.keyId, "v1");
  assert(
    await verifyPricingSnapshotIntegrity(
      snapshot,
      context,
      integrity,
      () => secret,
    ),
  );
  assertEquals(
    await createPricingSnapshotIntegrity(snapshot, context, "v1", secret),
    integrity,
  );
});

Deno.test("snapshot v3 package definition is integrity protected", async () => {
  const snapshot = await buildPricingSnapshotV3(
    {
      selected_package_definition_id: "professional_v2",
      requested_pages: ["home"],
    },
    resolveBudgetEvidence(
      "EUR 3.200 t/m EUR 6.000",
      "budget_guard_v1",
      "3200_to_6000_inclusive",
    ),
  );
  const integrity = await createPricingSnapshotIntegrity(
    snapshot,
    context,
    "v1",
    secret,
  );
  assert(await verifyPricingSnapshotIntegrity(snapshot, context, integrity, () => secret));
  const changed = clone(snapshot) as unknown as Record<string, unknown>;
  (changed.packageDefinition as Record<string, unknown>).floorMinor = 180_000;
  assertEquals(
    await verifyPricingSnapshotIntegrity(changed, context, integrity, () => secret),
    false,
  );
});

Deno.test("every integrity-root mutation invalidates the producer proof", async () => {
  const { snapshot, integrity } = await fixture();
  const mutations: Array<[string, (value: Record<string, unknown>) => void]> = [
    ["amount", (value) => {
      const calculation = value.calculation as Record<string, unknown>;
      calculation.knownMinimumMinor = 999_999;
    }],
    ["quantity", (value) => {
      const rules = (value.calculation as Record<string, unknown>)
        .appliedRules as Record<string, unknown>[];
      rules[1].quantity = 2;
    }],
    ["rule id", (value) => {
      const rules = (value.calculation as Record<string, unknown>)
        .appliedRules as Record<string, unknown>[];
      rules[1].ruleId = "invented_rule";
    }],
    ["normalized scope", (value) => {
      (value.normalizedScope as Record<string, unknown>).standardPageCount = 12;
    }],
    ["invented evidence", (value) => {
      const modules = (value.normalizedScope as Record<string, unknown>)
        .modules as Record<string, unknown>[];
      modules[0].evidence = ["invented_evidence"];
    }],
    ["language overlap", (value) => {
      const scope = value.normalizedScope as Record<string, unknown>;
      scope.additionalLanguages = [scope.primaryLanguage];
    }],
    ["budget evaluation", (value) => {
      (value.budgetEvaluation as Record<string, unknown>).outsideBudgetWishes =
        true;
    }],
    ["package advice", (value) => {
      (value.packageAdvice as Record<string, unknown>).status =
        "manual_scope_review";
    }],
    ["config hash", (value) => value.pricingConfigHash = "f".repeat(64)],
    ["unknown internal field", (value) => {
      (value.calculation as Record<string, unknown>).futureField = "forbidden";
    }],
    ["new counterexample", (value) => {
      (value.calculation as Record<string, unknown>).containsFromPricing =
        false;
    }],
  ];

  for (const [name, mutate] of mutations) {
    const changed = clone(snapshot) as unknown as Record<string, unknown>;
    mutate(changed);
    assertEquals(
      await verifyPricingSnapshotIntegrity(
        changed,
        context,
        integrity,
        () => secret,
      ),
      false,
      name,
    );
  }
});

Deno.test("integrity metadata removal mutation and transplant fail closed", async () => {
  const { snapshot, integrity } = await fixture();
  const other = clone(snapshot) as unknown as Record<string, unknown>;
  (other.normalizedScope as Record<string, unknown>).standardPages = [
    "home",
    "about",
  ];

  assertEquals(
    await verifyPricingSnapshotIntegrity(snapshot, context, null, () => secret),
    false,
  );
  assertEquals(
    await verifyPricingSnapshotIntegrity(snapshot, context, {
      ...integrity,
      mac: "0".repeat(64),
    }, () => secret),
    false,
  );
  assertEquals(
    await verifyPricingSnapshotIntegrity(snapshot, context, {
      ...integrity,
      algorithmVersion: "unsupported",
    }, () => secret),
    false,
  );
  assertEquals(
    await verifyPricingSnapshotIntegrity(snapshot, context, {
      ...integrity,
      keyId: "v2",
    }, () => secret),
    false,
  );
  assertEquals(
    await verifyPricingSnapshotIntegrity(snapshot, context, {
      ...integrity,
      unknown: true,
    }, () => secret),
    false,
  );
  assertEquals(
    await verifyPricingSnapshotIntegrity(
      other,
      context,
      integrity,
      () => secret,
    ),
    false,
  );
  assertEquals(
    await verifyPricingSnapshotIntegrity(
      snapshot,
      context,
      integrity,
      () => "wrong-secret-material-000000000000000000000",
    ),
    false,
  );
  assertEquals(
    await verifyPricingSnapshotIntegrity(
      snapshot,
      "32c31000-0000-4000-8000-000000000002",
      integrity,
      () => secret,
    ),
    false,
  );
});

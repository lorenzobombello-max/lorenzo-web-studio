import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildPricingSnapshotV3,
  calculateBudgetGuard,
  evaluateBudget,
  type PricingSnapshotV3,
  resolveBudgetEvidence,
} from "./pricing-engine.ts";
import { buildCustomerPricingPreview } from "./pricing-preview-dto.ts";
import {
  createPricingSnapshotIntegrity,
  verifyPricingSnapshotIntegrity,
} from "./pricing-snapshot-integrity.ts";
import type { RawPricingScope } from "./pricing-normalization.ts";

const budgetEvidence = resolveBudgetEvidence(
  "Meer dan EUR 6.000",
  "budget_guard_v2",
  "above_6000",
);
const integritySecret = "recurring-submit-integrity-secret-0000000000000001";

const cases: Array<{
  name: string;
  packageId: "starter_v1" | "professional_v2";
  plan: "none" | "care" | "care_plus";
  extra?: RawPricingScope;
}> = [
  { name: "A Starter no Care", packageId: "starter_v1", plan: "none" },
  {
    name: "B Professional no Care",
    packageId: "professional_v2",
    plan: "none",
  },
  { name: "C Starter Care", packageId: "starter_v1", plan: "care" },
  { name: "D Starter Care+", packageId: "starter_v1", plan: "care_plus" },
  { name: "E Professional Care", packageId: "professional_v2", plan: "care" },
  {
    name: "F Professional Care+",
    packageId: "professional_v2",
    plan: "care_plus",
  },
  {
    name: "G Care webshop",
    packageId: "starter_v1",
    plan: "care",
    extra: {
      shop_required: true,
      shop_details: {
        approx_product_count: 10,
        complex_product_count: 0,
        payment_provider_count: 1,
        shipping_scope: "standard",
        pickup_scope: "none",
      },
    },
  },
  {
    name: "H Care extra language",
    packageId: "starter_v1",
    plan: "care",
    extra: { primary_language: "nl", additional_languages: ["fr"] },
  },
  {
    name: "I Care branding and logo",
    packageId: "starter_v1",
    plan: "care",
    extra: { brand_status: "none", logo_status: "needed" },
  },
  {
    name: "J Care SEO Launch",
    packageId: "starter_v1",
    plan: "care",
    extra: { seo_priority: "high", seo_details: { scope: "launch" } },
  },
];

function scope(
  testCase: (typeof cases)[number],
  plan = testCase.plan,
): RawPricingScope {
  return {
    selected_package_definition_id: testCase.packageId,
    requested_pages: ["home"],
    ...testCase.extra,
    hosting_maintenance_details: { maintenance_plan: plan },
  };
}

Deno.test("Care and Care+ submit matrix preserves preview, Snapshot V3, price, and HMAC", async () => {
  for (const [index, testCase] of cases.entries()) {
    const pricing = calculateBudgetGuard(scope(testCase));
    const budget = evaluateBudget(pricing.calculation, budgetEvidence);
    const preview = buildCustomerPricingPreview(index, pricing, budget, 3);
    const snapshot = await buildPricingSnapshotV3(
      scope(testCase),
      budgetEvidence,
    );
    const baseline = calculateBudgetGuard(scope(testCase, "none"));

    assertEquals(snapshot.snapshotContractVersion, 3, testCase.name);
    assertEquals(
      snapshot.calculation.knownMinimumMinor,
      baseline.calculation.knownMinimumMinor,
      testCase.name,
    );
    assertEquals(
      preview.summary.knownMinimumMinor,
      snapshot.calculation.knownMinimumMinor,
      testCase.name,
    );

    if (testCase.plan === "none") {
      assertEquals(snapshot.recurringServices, undefined, testCase.name);
      assertEquals(preview.recurringServices, undefined, testCase.name);
      assertEquals(Object.keys(snapshot).length, 8, testCase.name);
    } else {
      const productId = testCase.plan === "care" ? "care" : "care_plus";
      const amountMinor = testCase.plan === "care" ? 4_900 : 9_900;
      assertEquals(snapshot.recurringServices, [{
        productId,
        amountMinor,
        unit: "month",
      }], testCase.name);
      assertEquals(preview.recurringServices, [{
        presentationKey: productId === "care" ? "CARE" : "CARE_PLUS",
        amountMinor,
        unit: "MONTH",
      }], testCase.name);
      assertEquals(Object.keys(snapshot).length, 9, testCase.name);
    }

    const context = `19a12000-0000-4000-8000-${
      String(index + 1).padStart(12, "0")
    }`;
    const integrity = await createPricingSnapshotIntegrity(
      snapshot,
      context,
      "v1",
      integritySecret,
    );
    assert(
      await verifyPricingSnapshotIntegrity(
        snapshot,
        context,
        integrity,
        () => integritySecret,
      ),
      testCase.name,
    );

    if (snapshot.recurringServices) {
      const changed = structuredClone(snapshot) as PricingSnapshotV3;
      changed.recurringServices![0].amountMinor += 1;
      assertEquals(
        await verifyPricingSnapshotIntegrity(
          changed,
          context,
          integrity,
          () => integritySecret,
        ),
        false,
        `${testCase.name} tamper detection`,
      );
    }
  }
});

import { assertEquals, assertExists } from "jsr:@std/assert@1";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const mappingMatch = source.match(/const budgetCodes = (\{[\s\S]*?\n  \});/);
assertExists(mappingMatch);
const budgetCodes = Function(`"use strict"; return (${mappingMatch[1]});`)() as Record<string, string>;

const serializationMatch = source.match(
  /(if \(!budgetChoiceChanged && restoredLegacyBudget\)[\s\S]*?data\.budget_update_category_code = restoredBudgetEvidence\.code;\r?\n    })/,
);
assertExists(serializationMatch);
const serializeBudgetEvidence = Function(
  "data",
  "budgetChoiceChanged",
  "restoredLegacyBudget",
  "restoredBudgetEvidence",
  "budgetCodes",
  `"use strict"; ${serializationMatch[1]}; return data;`,
) as (
  data: Record<string, unknown>,
  budgetChoiceChanged: boolean,
  restoredLegacyBudget: string | null,
  restoredBudgetEvidence: { label: string; code: string } | null,
  budgetCodes: Record<string, string>,
) => Record<string, unknown>;

const expectedMappings = new Map([
  ["Minder dan EUR 1.800", "below_1800"],
  ["EUR 1.800 tot minder dan EUR 3.200", "1800_to_below_3200"],
  ["EUR 3.200 t/m EUR 6.000", "3200_to_6000_inclusive"],
  ["Meer dan EUR 6.000", "above_6000"],
]);

function assertTriplet(data: Record<string, unknown>, label: string, code: string) {
  assertEquals(data.budget_update_category, label);
  assertEquals(data.budget_update_category_scheme, "budget_guard_v1");
  assertEquals(data.budget_update_category_code, code);
}

Deno.test("recognized budget labels serialize their complete evidence triplet", () => {
  for (const [label, code] of expectedMappings) {
    assertEquals(budgetCodes[label], code);
    const data = serializeBudgetEvidence(
      { budget_update_category: label },
      false,
      null,
      null,
      budgetCodes,
    );
    assertTriplet(data, label, code);
  }
});

Deno.test("restored, package-only and direct changes retain the complete budget triplet", () => {
  const label = "Minder dan EUR 1.800";
  const code = "below_1800";
  const scenarios = [
    serializeBudgetEvidence({ budget_update_category: label }, false, label, null, budgetCodes),
    serializeBudgetEvidence(
      { budget_update_category: label },
      false,
      null,
      { label, code },
      budgetCodes,
    ),
    serializeBudgetEvidence(
      { budget_update_category: label, selected_package_definition_id: "professional_v2" },
      false,
      null,
      null,
      budgetCodes,
    ),
    serializeBudgetEvidence({ budget_update_category: label }, true, null, null, budgetCodes),
  ];
  scenarios.forEach((data) => assertTriplet(data, label, code));
});

Deno.test("unrecognized budget labels do not fabricate evidence", () => {
  const data = serializeBudgetEvidence(
    { budget_update_category: "Unknown budget" },
    false,
    null,
    null,
    budgetCodes,
  );
  assertEquals(data, { budget_update_category: "Unknown budget" });
});
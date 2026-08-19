import { assertEquals, assertExists } from "jsr:@std/assert@1";
import { calculateBudgetGuard } from "../../supabase/functions/_shared/pricing-engine.ts";
import { sanitizeAndValidatePricingPreviewInput } from "../../supabase/functions/_shared/validation.ts";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const contactHtml = await Deno.readTextFile(new URL("../../pages/contact.html", import.meta.url));
const mappingMatch = source.match(/const budgetCodes = (\{[\s\S]*?\n  \});/);
assertExists(mappingMatch);
const budgetCodes = Function(`"use strict"; return (${mappingMatch[1]});`)() as Record<string, string>;

const serializationMatch = source.match(
  /(if \(!budgetChoiceChanged && restoredLegacyBudget\)[\s\S]*?data\.budget_update_category_code = budgetCode;\r?\n    })/,
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
  restoredBudgetEvidence: { label: string; code: string; scheme: string } | null,
  budgetCodes: Record<string, string>,
) => Record<string, unknown>;

const expectedMappings = new Map([
  ["Minder dan EUR 1.800", "below_1800"],
  ["EUR 1.800 tot minder dan EUR 3.500", "1800_to_below_3500"],
  ["EUR 3.500 t/m EUR 6.000", "3500_to_6000_inclusive"],
  ["Meer dan EUR 6.000", "above_6000"],
]);

function assertTriplet(data: Record<string, unknown>, label: string, code: string, scheme = "budget_guard_v2") {
  assertEquals(data.budget_update_category, label);
  assertEquals(data.budget_update_category_scheme, scheme);
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

Deno.test("restored v2, package-only and direct changes retain the complete current triplet", () => {
  const label = "Minder dan EUR 1.800";
  const code = "below_1800";
  const scenarios = [
    serializeBudgetEvidence({ budget_update_category: label }, false, label, null, budgetCodes),
    serializeBudgetEvidence(
      { budget_update_category: label },
      false,
      null,
      { label, code, scheme: "budget_guard_v2" },
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

Deno.test("unchanged restored v1 evidence remains historical", () => {
  const data = serializeBudgetEvidence(
    { budget_update_category: "EUR 3.200 t/m EUR 6.000" },
    false,
    null,
    {
      label: "EUR 3.200 t/m EUR 6.000",
      code: "3200_to_6000_inclusive",
      scheme: "budget_guard_v1",
    },
    budgetCodes,
  );
  assertTriplet(
    data,
    "EUR 3.200 t/m EUR 6.000",
    "3200_to_6000_inclusive",
    "budget_guard_v1",
  );
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

Deno.test("public contact budget options follow current Budget Guard labels", () => {
  const select = contactHtml.match(/<select id="budget"[^>]*>([\s\S]*?)<\/select>/);
  assertExists(select);
  const options = Array.from(select[1].matchAll(/<option(?:\s+value="[^"]*")?>([^<]*)<\/option>/g))
    .map((match) => match[1].trim())
    .filter((label) => label !== "Selecteer");

  assertEquals(options, Array.from(expectedMappings.keys()));
  assertEquals(options.some((label) => /(?:1\.500|3\.000|3\.200)/.test(label)), false);
});

Deno.test("brand and logo status preview evidence matches submit pricing", () => {
  const fieldsMatch = source.match(/const pricingEvidenceFields = \[([\s\S]*?)\];/);
  assertExists(fieldsMatch);
  const pricingEvidenceFields = Array.from(fieldsMatch[1].matchAll(/"([^"]+)"/g), (match) => match[1]);
  const states = [
    { brand_status: "complete", logo_status: "available" },
    { brand_status: "none", logo_status: "available" },
    { brand_status: "complete", logo_status: "needed" },
    { brand_status: "none", logo_status: "needed" },
  ];

  states.forEach((state) => {
    const submitEvidence = {
      selected_package_definition_id: "starter_v1",
      requested_pages: ["home"],
      ...state,
    };
    const previewEvidence = Object.fromEntries(
      pricingEvidenceFields
        .filter((field) => field in submitEvidence)
        .map((field) => [field, submitEvidence[field as keyof typeof submitEvidence]]),
    );
    const validatedPreviewEvidence = sanitizeAndValidatePricingPreviewInput(previewEvidence);

    assertEquals(
      calculateBudgetGuard(validatedPreviewEvidence).calculation,
      calculateBudgetGuard(submitEvidence).calculation,
    );
  });
});
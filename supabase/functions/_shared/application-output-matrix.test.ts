import { assertEquals, assertFalse, assertMatch, assertStringIncludes } from "jsr:@std/assert@1";
import { buildApplicationOutput } from "./application-output.ts";
import { buildSubmittedIntakeAdminEmail } from "./email-templates.ts";

interface MatrixCase {
  name: string;
  packageId: "starter_v1" | "professional_v2";
  minimum: number;
  evidence: Record<string, unknown>;
  recurring?: "care" | "care_plus";
  budgetStatus?: string;
  budget?: string;
}

const cases: MatrixCase[] = [
  { name: "A Starter basic", packageId: "starter_v1", minimum: 180000, evidence: {} },
  { name: "B Professional basic", packageId: "professional_v2", minimum: 350000, evidence: {} },
  { name: "C webshop", packageId: "professional_v2", minimum: 525000, evidence: { shop_required: true, shop_details: { approx_product_count: "20" } } },
  { name: "D extra language", packageId: "starter_v1", minimum: 245000, evidence: { primary_language: "nl", additional_languages: ["fr"] } },
  { name: "E branding logo", packageId: "starter_v1", minimum: 320000, evidence: { brand_status: "none", logo_status: "needed", content_media_details: { branding_tier: "logo_identity_combo" } } },
  { name: "F SEO Launch", packageId: "starter_v1", minimum: 245000, evidence: { seo_priority: "high", seo_details: { scope: "launch" } } },
  { name: "G Care", packageId: "starter_v1", minimum: 180000, recurring: "care", evidence: { maintenance_interest: "yes", hosting_maintenance_details: { maintenance_plan: "care" } } },
  { name: "H Care+", packageId: "professional_v2", minimum: 350000, recurring: "care_plus", evidence: { maintenance_interest: "yes", hosting_maintenance_details: { maintenance_plan: "care_plus" } } },
  { name: "I low-budget Budget Guard", packageId: "professional_v2", minimum: 350000, budgetStatus: "known_minimum_above_budget", budget: "Minder dan EUR 1.800", evidence: {} },
  { name: "J complex combined intake", packageId: "professional_v2", minimum: 730000, recurring: "care_plus", budgetStatus: "known_minimum_above_budget", budget: "EUR 3.500 t/m EUR 6.000", evidence: { shop_required: true, shop_details: { approx_product_count: "50", online_payments: true }, booking_required: true, booking_details: { type: "consultations" }, primary_language: "nl", additional_languages: ["fr"], page_scope_details: { portfolio: "dynamic" }, quote_form_details: { tier: "extended" }, multilingual_details: { translations_supplied: false }, download_details: { access: "secured" }, newsletter_details: { scope: "advanced" }, seo_priority: "high", seo_details: { scope: "launch" }, integrations: ["crm"], brand_status: "none", logo_status: "needed", content_media_details: { copywriting_scope: "substantial" }, deadline_details: { hard: true } } },
];

for (const [index, testCase] of cases.entries()) {
  Deno.test(`application output matrix ${testCase.name}`, () => {
    const reference = `LWS-AAN-2026-${String(index + 1).padStart(4, "0")}`;
    const recurringServices = testCase.recurring
      ? [{ productId: testCase.recurring, amountMinor: testCase.recurring === "care" ? 4900 : 9900, unit: "month" as const }]
      : undefined;
    const output = buildApplicationOutput({
      applicationReference: reference,
      submittedAt: "2026-08-19T18:00:00Z",
      request: { name: "Matrix Customer", company: `Case ${testCase.name}`, email: "matrix@example.test", phone: "+32 9 000 00 00", website_type: "business", budget: testCase.budget || "Meer dan EUR 6.000", timing: "flexible" },
      evidence: { business_description: "Matrix project", target_audience: "Local businesses", website_goals: ["generate_leads"], primary_conversion_goal: "quote_requests", requested_pages: ["home", "services"], requested_features: ["contact_form"], design_styles: ["modern"], content_status: "complete", image_status: "sufficient", domain_status: "has_domain", hosting_status: "has_hosting", priorities: ["usability"], ...testCase.evidence },
      authoritativeSnapshot: { calculation: { knownMinimumMinor: testCase.minimum, currency: "EUR", vatBasis: "exclusive" }, packageDefinition: { id: testCase.packageId }, budgetEvaluation: { status: testCase.budgetStatus || "within_known_budget", originalLabel: testCase.budget || "Meer dan EUR 6.000" }, ...(recurringServices ? { recurringServices } : {}) },
    });
    const email = buildSubmittedIntakeAdminEmail({ output, adminUrl: "https://example.test/secure-briefing" });
    const formattedMinimum = new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR" }).format(testCase.minimum / 100);
    assertMatch(output.applicationReference || "", /^LWS-AAN-2026-[0-9]{4}$/);
    assertEquals(output.commercial.knownMinimumMinor, testCase.minimum);
    assertStringIncludes(email.text, `Aanvraagnummer: ${reference}`);
    assertStringIncludes(email.text, `Indicatief projectminimum: ${formattedMinimum} excl. btw`);
    assertEquals(output.website.webshop, testCase.evidence.shop_required === true);
    assertEquals(output.commercial.recurringServices.length, testCase.recurring ? 1 : 0);
    if (testCase.recurring) {
      assertStringIncludes(email.text, `per maand excl. btw`);
      assertEquals(output.commercial.knownMinimumMinor, testCase.minimum);
    }
    const serialized = JSON.stringify(output);
    assertFalse(/hmac|pricingConfigHash|snapshotContractVersion|[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}/i.test(serialized));
  });
}

Deno.test("application output matrix references are unique", () => {
  const references = cases.map((_, index) => `LWS-AAN-2026-${String(index + 1).padStart(4, "0")}`);
  assertEquals(new Set(references).size, cases.length);
});
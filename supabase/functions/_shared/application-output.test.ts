import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { buildApplicationOutput } from "./application-output.ts";

function fixture(packageId: "starter_v1" | "professional_v2", recurring?: "care" | "care_plus") {
  return buildApplicationOutput({
    applicationReference: "LWS-AAN-2026-0001",
    submittedAt: "2026-08-19T18:00:00.000Z",
    request: {
      name: "Lorenzo <script>alert(1)</script>", company: "Studio & Co", email: "test@example.test",
      phone: "+32 9 000 00 00", website_type: "business", budget: "Meer dan EUR 6.000", timing: "flexible",
    },
    evidence: {
      budget_update_category: "Meer dan EUR 6.000", website_goals: ["generate_leads"],
      requested_pages: ["home", "services"], requested_features: ["contact_form"],
      shop_required: true, shop_details: { approx_product_count: "20" }, booking_required: false,
      primary_language: "nl", additional_languages: ["fr"], integrations: ["crm"],
      seo_priority: "high", seo_details: { scope: "launch" }, brand_status: "none", logo_status: "needed",
      design_styles: ["modern"], content_status: "partial", image_status: "needed", image_support: ["ai_images"],
      maintenance_interest: "yes", hosting_maintenance_details: { maintenance_plan: recurring || "none" },
      deadline_date: "2026-12-01", additional_notes: "Notes </div><script>alert(2)</script>",
    },
    authoritativeSnapshot: {
      calculation: { knownMinimumMinor: packageId === "starter_v1" ? 180000 : 350000, currency: "EUR", vatBasis: "exclusive" },
      packageDefinition: { id: packageId },
      budgetEvaluation: { status: "within_known_budget", originalLabel: "Meer dan EUR 6.000" },
      ...(recurring ? { recurringServices: [{ productId: recurring, amountMinor: recurring === "care" ? 4900 : 9900, unit: "month" }] } : {}),
    },
  });
}

Deno.test("application output preserves Starter and essential combined scope", () => {
  const output = fixture("starter_v1");
  assertEquals(output.commercial.packageLabel, "Starter");
  assertEquals(output.commercial.knownMinimumMinor, 180000);
  assertEquals(output.website.webshop, true);
  assertEquals(output.website.additionalLanguages, ["fr"]);
  assertEquals(output.website.seoDetails, { scope: "launch" });
  assertEquals(output.brandingContent.logoStatus, "needed");
});

Deno.test("application output keeps Care separate from Professional one-time minimum", () => {
  const output = fixture("professional_v2", "care");
  assertEquals(output.commercial.knownMinimumMinor, 350000);
  assertEquals(output.commercial.recurringServices, [{ productId: "care", label: "LWS Care", amountMinor: 4900, unit: "month" }]);
});

Deno.test("application output keeps Care+ at 99 euro per month", () => {
  const output = fixture("professional_v2", "care_plus");
  assertEquals(output.commercial.knownMinimumMinor, 350000);
  assertEquals(output.commercial.recurringServices[0].amountMinor, 9900);
});

Deno.test("application output preserves user text as data without interpreting markup", () => {
  const output = fixture("starter_v1");
  assertEquals(output.customer.name, "Lorenzo <script>alert(1)</script>");
  assertEquals(output.servicePlanning.notes, "Notes </div><script>alert(2)</script>");
});

Deno.test("application output rejects non-authoritative pricing input", () => {
  assertThrows(() => buildApplicationOutput({
    applicationReference: "LWS-AAN-2026-0001", submittedAt: "2026-08-19T18:00:00Z",
    request: { name: "Test", email: "test@example.test" }, evidence: {},
    authoritativeSnapshot: { calculation: { knownMinimumMinor: 1, currency: "EUR", vatBasis: "exclusive" } },
  }), TypeError, "INVALID_APPLICATION_OUTPUT_SOURCE");
});
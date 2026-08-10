import {
  assertEquals,
  assertNotEquals,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  PACKAGE_DEFINITION_REGISTRY,
  resolvePackageDefinition,
} from "./pricing-config.ts";
import { calculateBudgetGuard } from "./pricing-engine.ts";

const STANDARD_PAGES = [
  "home",
  "about",
  "services",
  "products",
  "portfolio",
  "team",
  "pricing",
  "faq",
  "reviews",
  "blog",
  "contact",
  "jobs",
  "gallery",
];
const NORMAL_PAGE_SCOPES = {
  reviews: "normal",
  blog: "normal",
  jobs: "normal",
  gallery: "normal",
};

function price(pageCount: number, packageDefinitionId: string) {
  return calculateBudgetGuard({
    selected_package_definition_id: packageDefinitionId,
    requested_pages: STANDARD_PAGES.slice(0, pageCount),
    page_scope_details: NORMAL_PAGE_SCOPES,
  });
}

Deno.test("package definitions resolve immutable commercial floors and limits", () => {
  const starter = resolvePackageDefinition("starter_v1");
  const professional = resolvePackageDefinition("professional_v1");

  assertEquals(starter.floorMinor, 180_000);
  assertEquals(starter.standardPageLimit, 5);
  assertEquals(starter.includedCorrectionRounds, 1);
  assertEquals(professional.floorMinor, 320_000);
  assertEquals(professional.standardPageLimit, 12);
  assertEquals(professional.includedCorrectionRounds, 2);
});

Deno.test("Professional inherits normal Starter entitlements exactly once", () => {
  const starter = resolvePackageDefinition("starter_v1");
  const professional = resolvePackageDefinition("professional_v1");

  assertEquals(professional.entitlements, starter.entitlements);
  assertEquals(
    professional.entitlements.length,
    new Set(professional.entitlements).size,
  );
  assertEquals(PACKAGE_DEFINITION_REGISTRY.professional_v1.inheritsFrom, "starter_v1");
  assertNotEquals(professional.floorMinor, starter.floorMinor);
});

Deno.test("package-aware page limits charge genuine excess exactly once", () => {
  assertEquals(price(5, "starter_v1").calculation.knownMinimumMinor, 180_000);
  assertEquals(price(6, "starter_v1").calculation.knownMinimumMinor, 200_000);
  assertEquals(
    price(12, "professional_v1").calculation.knownMinimumMinor,
    320_000,
  );
  const professionalThirteen = price(13, "professional_v1");
  assertEquals(professionalThirteen.calculation.knownMinimumMinor, 340_000);
  assertEquals(
    professionalThirteen.calculation.appliedRules.map((rule) => rule.ruleId),
    ["professional_v1_floor", "extra_standard_page"],
  );
  assertEquals(professionalThirteen.calculation.manualReviewRequired, false);
});

Deno.test("invalid package evidence is rejected and advice never selects a package", () => {
  assertThrows(
    () => calculateBudgetGuard({ selected_package_definition_id: "professional" }),
    TypeError,
    "INVALID_PACKAGE_DEFINITION_ID",
  );
  const legacy = calculateBudgetGuard({
    requested_pages: STANDARD_PAGES.slice(0, 12),
    page_scope_details: NORMAL_PAGE_SCOPES,
  });
  assertEquals(legacy.selectedPackageDefinition, null);
  assertEquals(legacy.packageAdvice.status, "consider_professional");
  assertEquals(legacy.packageAdvice.selectedPackage, null);
});

Deno.test("Professional inherited contact entitlement neutralizes supplements once", () => {
  const result = calculateBudgetGuard({
    selected_package_definition_id: "professional_v1",
    requested_pages: ["home", "contact"],
    requested_features: ["contact_form", "contact_form"],
    website_goals: ["contact_requests", "generate_leads"],
  });
  const contactRules = result.calculation.appliedRules.filter((rule) =>
    rule.ruleId === "contact_form"
  );
  assertEquals(contactRules.length, 1);
  assertEquals(contactRules[0].mode, "included");
  assertEquals(contactRules[0].knownMinimumContributionMinor, 0);
  assertEquals(result.calculation.knownMinimumMinor, 320_000);
});
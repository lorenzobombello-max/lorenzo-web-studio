import { assertEquals, assertExists, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const html = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));
const css = await Deno.readTextFile(new URL("../css/intake.css", import.meta.url));

function sourceFunction(name: string) {
  const signature = `function ${name}(`;
  const start = source.indexOf(signature);
  assertFalse(start === -1, `${name} must exist`);
  const bodyStart = source.indexOf("{", start);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}") depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

const collectValidationIssues = Function(
  "requiredSubmitFields",
  `"use strict"; return (${sourceFunction("collectValidationIssues")});`,
)([
  "business_description", "target_audience", "primary_conversion_goal", "brand_status", "logo_status",
  "content_status", "image_status", "domain_status", "hosting_status", "maintenance_interest", "seo_priority",
]) as (data: Record<string, unknown>) => Array<{ name: string; message: string }>;
const orderValidationIssues = Function(
  `"use strict"; return (${sourceFunction("orderValidationIssues")});`,
)() as (
  issues: Array<{ name: string; message: string }>,
  orderedNames: string[],
) => Array<{ name: string; message: string }>;
const validationSummary = Function(
  `"use strict"; return (${sourceFunction("validationSummary")});`,
)() as (count: number) => string;

function validData(): Record<string, unknown> {
  return {
    business_description: "Een webstudio",
    target_audience: "Lokale ondernemingen",
    primary_conversion_goal: "Een offerte aanvragen",
    brand_status: "complete",
    logo_status: "available",
    content_status: "complete",
    image_status: "sufficient",
    domain_status: "no_domain",
    hosting_status: "no_hosting",
    maintenance_interest: "yes",
    seo_priority: "basic",
    website_goals: ["generate_leads"],
    requested_pages: ["home"],
    design_styles: ["modern"],
    priorities: ["usability"],
    selected_package_definition_id: "starter_v1",
    has_existing_website: false,
    existing_website_url: null,
    domain_name: null,
    confirmation: true,
  };
}

Deno.test("multiple simultaneous failures are all collected with concrete messages", () => {
  const data = validData();
  data.business_description = "";
  data.primary_conversion_goal = null;
  data.website_goals = [];
  data.confirmation = false;

  const issues = collectValidationIssues(data);
  assertEquals(issues.map(({ name }) => name), [
    "business_description",
    "primary_conversion_goal",
    "website_goals",
    "confirmation",
  ]);
  issues.forEach(({ message }) => assertFalse(message.trim() === ""));
});

Deno.test("valid fields are not returned as validation failures", () => {
  assertEquals(collectValidationIssues(validData()), []);
});

Deno.test("first invalid follows earliest step and DOM order", () => {
  const issues = [
    { name: "brand_status", message: "required" },
    { name: "target_audience", message: "required" },
    { name: "website_goals", message: "required" },
  ];
  const ordered = orderValidationIssues(issues, ["business_description", "target_audience", "website_goals", "brand_status"]);
  assertEquals(ordered.map(({ name }) => name), ["target_audience", "website_goals", "brand_status"]);
});

Deno.test("conditional failures disappear when their parent condition no longer applies", () => {
  const existingWebsite = { ...validData(), has_existing_website: true, existing_website_url: null };
  assertEquals(collectValidationIssues(existingWebsite).some(({ name }) => name === "existing_website_url"), true);
  existingWebsite.has_existing_website = false;
  assertEquals(collectValidationIssues(existingWebsite).some(({ name }) => name === "existing_website_url"), false);

  const domain = { ...validData(), domain_status: "has_domain", domain_name: null };
  assertEquals(collectValidationIssues(domain).some(({ name }) => name === "domain_name"), true);
  domain.domain_status = "no_domain";
  assertEquals(collectValidationIssues(domain).some(({ name }) => name === "domain_name"), false);
});

Deno.test("every client-validated field has a concrete described error container", () => {
  const names = [
    "business_description", "target_audience", "primary_conversion_goal", "brand_status", "logo_status",
    "content_status", "image_status", "domain_status", "hosting_status", "maintenance_interest", "seo_priority",
    "website_goals", "requested_pages", "design_styles", "priorities", "selected_package_definition_id",
    "existing_website_url", "domain_name", "confirmation",
  ];
  names.forEach((name) => {
    assertStringIncludes(html, `id="${name}-error"`);
    assertEquals(new RegExp(`aria-describedby="[^"]*\\b${name}-error\\b[^"]*"`).test(html), true);
  });
});

Deno.test("required checkbox and radio sets expose group-level validation targets", () => {
  ["website_goals", "requested_pages", "design_styles", "priorities", "selected_package_definition_id"].forEach((name) => {
    assertStringIncludes(html, `data-validation-group="${name}"`);
  });
  assertStringIncludes(css, '[data-validation-group][aria-invalid="true"]');
});

Deno.test("validation rendering tracks all errors and step indicators", () => {
  assertStringIncludes(source, "const validationErrors = new Map()");
  assertStringIncludes(sourceFunction("renderValidationIssues"), "issues.forEach");
  assertStringIncludes(sourceFunction("updateStepErrorIndicators"), 'classList.toggle("has-error"');
  assertStringIncludes(sourceFunction("updateStepErrorIndicators"), 'aria-label');
  assertStringIncludes(css, ".intake-progress button.has-error");
});

Deno.test("live correction clears only revalidated fields and refreshes conditional dependants", () => {
  const inputHandler = sourceFunction("handleValidationInput");
  assertStringIncludes(source, 'form.addEventListener("input", handleValidationInput)');
  assertStringIncludes(inputHandler, "revalidateFields");
  assertStringIncludes(inputHandler, 'event.target.name === "has_existing_website"');
  assertStringIncludes(inputHandler, 'event.target.name === "domain_status"');
  assertStringIncludes(sourceFunction("revalidateFields"), "names.forEach");
  assertFalse(sourceFunction("revalidateFields").includes("clearErrors()"));
});

Deno.test("failed validation opens and reveals the first invalid control", () => {
  const validator = sourceFunction("validateSubmit");
  assertStringIncludes(validator, "showStep(steps.indexOf(step))");
  assertStringIncludes(validator, "scrollIntoView");
  assertStringIncludes(validator, "focus");
  assertFalse(validator.includes("firstInvalid ||="));
});

Deno.test("validation summary reflects the actual remaining error count", () => {
  assertEquals(validationSummary(0), "");
  assertEquals(validationSummary(1), "Controleer 1 gemarkeerd veld.");
  assertEquals(validationSummary(3), "Controleer 3 gemarkeerde velden.");
});

Deno.test("validation failure does not mutate answers or protected Budget Guard state", () => {
  const validator = sourceFunction("validateSubmit");
  assertFalse(/\.value\s*=|\.checked\s*=/.test(validator));
  assertFalse(validator.includes("currentBudgetGuardStatus ="));
  assertFalse(validator.includes("currentBudgetGuardKey ="));
  assertFalse(validator.includes("currentBudgetGuardEvidenceFingerprint ="));
  assertFalse(validator.includes("acknowledgedBudgetGuardKey ="));
  assertStringIncludes(validator, "return validateBudgetGuardAcknowledgement()");
});

Deno.test("ordinary form errors stop submission before the modal and Budget Guard gate", () => {
  const validator = sourceFunction("validateSubmit");
  assertStringIncludes(validator, "return false");
  assertStringIncludes(source, 'if (validateSubmit()) openModal()');
  assertStringIncludes(source, 'if (isPricingControl(event.target)) schedulePricingPreview()');
});
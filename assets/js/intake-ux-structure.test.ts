import { assertEquals, assertExists, assertMatch, assertStringIncludes } from "jsr:@std/assert@1";
import { DOMParser } from "npm:linkedom@0.18.12";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const html = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));
const document = new DOMParser().parseFromString(html, "text/html");

Deno.test("customer progress exposes exactly five professional phases", () => {
  const phases = [...document.querySelectorAll("[data-phase-target]")];
  assertEquals(phases.length, 5);
  assertEquals(phases.map((phase) => [...phase.querySelectorAll("span")].map((span) => span.textContent.trim())), [
    ["1", "Uw project"],
    ["2", "Uw oplossing"],
    ["3", "Uw website"],
    ["4", "Uw uitstraling"],
    ["5", "Afronding"],
  ]);
  assertEquals(document.querySelectorAll("[data-step-target]").length, 0);
});

Deno.test("runtime defines twelve screens across all five phases", () => {
  const definitions = source.match(/const screenDefinitions = \[([\s\S]*?)\n  \];/);
  assertExists(definitions);
  assertEquals([...definitions[1].matchAll(/\{ phase: ([0-4]), title:/g)].length, 12);
  assertEquals(new Set([...definitions[1].matchAll(/\{ phase: ([0-4]), title:/g)].map((match) => match[1])).size, 5);
  assertEquals([...definitions[1].matchAll(/\{ phase: [0-4], title: "([^"]+)"/g)].map((match) => match[1]).slice(0, 4), [
    "Budget",
    "Kies uw pakket",
    "Huidige situatie",
    "Webshop en reservaties",
  ]);
  assertStringIncludes(source, "INTAKE_SCREEN_CONTROL_MISMATCH");
});

Deno.test("pricing presentation selectors still resolve before runtime regrouping", () => {
  const mapping = source.match(/const presentationAnchorSelectors = Object\.freeze\(\{([\s\S]*?)\n  \}\);/);
  assertExists(mapping);
  const selectors = [...mapping[1].matchAll(/^[ ]{4}[A-Z_]+: ([^,]+),?$/gm)]
    .map((match) => match[1])
    .filter((value) => value !== "null")
    .map((value) => value.slice(1, -1));
  selectors.forEach((selector) => {
    if (document.querySelector(selector)) return;
    const dynamic = selector.match(/^input\[name="([^"]+)"\]\[value="([^"]+)"\]$/);
    assertExists(dynamic, selector);
    const container = document.querySelector(`[data-name="${dynamic[1]}"]`);
    assertExists(container, selector);
    assertEquals(
      (container.getAttribute("data-options") || "").split(",").some((option: string) => option.startsWith(`${dynamic[2]}:`)),
      true,
      selector,
    );
  });
});

Deno.test("budget is first, required and keeps exact authoritative values", () => {
  const budget = document.getElementById("budget_update_category");
  assertExists(budget);
  assertEquals(budget.hasAttribute("required"), true);
  assertEquals(budget.value, "");
  assertEquals([...budget.querySelectorAll("option")].map((option) => option.getAttribute("value") ?? option.textContent.trim()), [
    "",
    "Minder dan EUR 1.800",
    "EUR 1.800 tot minder dan EUR 3.500",
    "EUR 3.500 t/m EUR 6.000",
    "Meer dan EUR 6.000",
  ]);
  assertStringIncludes(source, '{ phase: 0, title: "Budget"');
});

Deno.test("package navigation targets the second screen", () => {
  assertStringIncludes(source, "if (targetStep > 1");
  assertMatch(source, /if \(targetStep > 1[\s\S]*showStep\(1\);[\s\S]*validatePackageSelection\(\);/);
  assertMatch(source, /getElementById\("changePackage"\)[\s\S]*showStep\(1\);/);
});

Deno.test("review screen uses existing form data and server preview text", () => {
  assertStringIncludes(source, 'budgetGuardMinimum.textContent');
  assertStringIncludes(source, 'selectedChoiceLabels("requested_pages")');
  assertStringIncludes(source, 'selectedChoiceLabels("requested_features")');
  assertEquals(source.includes("calculateBudgetGuard"), false);
});
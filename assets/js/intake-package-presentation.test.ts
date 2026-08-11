import { assertEquals, assertExists, assertStringIncludes } from "jsr:@std/assert@1";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const html = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));

const limitMatch = source.match(/function packageLimitPresentation\(selectedPackage\) \{[\s\S]*?\n  \}/);
assertExists(limitMatch);
const packageLimitPresentation = Function(`"use strict"; return (${limitMatch[0]});`)() as (
  selectedPackage: {
    label: string;
    standardPageCount: number;
    standardPageLimit: number;
    includedCorrectionRounds: number;
  },
) => {
  packageName: string;
  pageLimit: string;
  corrections: string;
  pageCounter: string;
  overLimit: boolean;
};

Deno.test("package limits use server-derived Starter and Professional values", () => {
  assertEquals(packageLimitPresentation({
    label: "Starter",
    standardPageCount: 3,
    standardPageLimit: 5,
    includedCorrectionRounds: 1,
  }), {
    packageName: "Starter",
    pageLimit: "Maximaal 5 standaardpagina's",
    corrections: "1 correctieronde",
    pageCounter: "3 van maximaal 5 standaardpagina's",
    overLimit: false,
  });
  assertEquals(packageLimitPresentation({
    label: "Professional",
    standardPageCount: 13,
    standardPageLimit: 12,
    includedCorrectionRounds: 2,
  }), {
    packageName: "Professional",
    pageLimit: "Maximaal 12 standaardpagina's",
    corrections: "2 correctierondes",
    pageCounter: "13 van maximaal 12 standaardpagina's",
    overLimit: true,
  });
});

Deno.test("package presentation cannot mutate feature choices or intake serialization", () => {
  const renderer = source.slice(
    source.indexOf("function renderPackagePresentation"),
    source.indexOf("function renderPricingPreview"),
  );
  const serializer = source.slice(source.indexOf("function collectData"), source.indexOf("function collectPricingEvidence"));
  for (const mutation of [".checked =", ".disabled =", ".value =", "dispatchEvent("]) {
    assertEquals(renderer.includes(mutation), false);
  }
  assertEquals(serializer.includes("includedPresentation"), false);
  assertEquals(serializer.includes("entitlement"), false);
});

Deno.test("package presentation rejects unknown entitlements and separates SEO scope", () => {
  assertStringIncludes(source, "!packageEntitlementIds.has(item.entitlement)");
  assertStringIncludes(source, "selectedPackage.includedPresentation.length !== packageEntitlementIds.size");
  assertStringIncludes(source, 'technical_seo_base: ["#seo_priority"]');
  assertStringIncludes(source, 'EXTENSIVE_SEO: "#seo_extensive_services"');
  assertStringIncludes(html, "De technische SEO-basis is pakketkwaliteit. Uitgebreid SEO-werk blijft een afzonderlijke wens.");
});

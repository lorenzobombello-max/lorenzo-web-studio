import { assertEquals, assertExists, assertStringIncludes } from "jsr:@std/assert@1";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const html = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));

function sourceFunction(name: string) {
  const match = source.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}`));
  assertExists(match);
  return match[0];
}

const preview = {
  previewVersion: 2,
  scopeRevision: 5,
  pricingConfigVersion: "production",
  currency: "EUR",
  vatBasis: "exclusive",
  nonBinding: true,
  budget: {
    selectedBudgetCategoryCode: "below_1800",
    comparisonStatus: "KNOWN_MINIMUM_ABOVE_BUDGET",
    knownMinimumExceedsBudget: true,
  },
  summary: {
    knownMinimumMinor: 320_000,
    containsFromPricing: false,
    manualReviewRequired: false,
  },
  items: [],
  packageAdvice: { state: "NO_PACKAGE_ADVICE" },
  selectedPackage: {
    selectedPackageDefinitionId: "professional_v1",
    label: "Professional",
    floorMinor: 320_000,
    standardPageLimit: 12,
    includedCorrectionRounds: 2,
  },
};

const validPreview = Function(
  "form",
  "budgetStates",
  "budgetLabels",
  "packageAdviceStates",
  "packageDefinitionIds",
  "presentationAnchorSelectors",
  "itemStates",
  `"use strict"; return (${sourceFunction("validPreview")});`,
)(
  { querySelector: () => ({ value: "professional_v1" }) },
  new Set(["WITHIN_KNOWN_BUDGET", "KNOWN_MINIMUM_ABOVE_BUDGET", "INDETERMINATE", "MANUAL_REVIEW"]),
  { below_1800: "Minder dan € 1.800" },
  new Set(["NO_PACKAGE_ADVICE", "CONSIDER_PROFESSIONAL", "PERSONAL_REVIEW_RECOMMENDED"]),
  new Set(["starter_v1", "professional_v1"]),
  { PACKAGE_SCOPE: null },
  new Set(["INCLUDED", "FIXED_EXTRA", "FROM_EXTRA", "MANUAL_REVIEW"]),
) as (preview: unknown, revision: number) => boolean;

function element() {
  const classes = new Set<string>();
  return {
    textContent: "",
    hidden: true,
    classList: {
      add: (...names: string[]) => names.forEach((name) => classes.add(name)),
      contains: (name: string) => classes.has(name),
    },
    setAttribute: () => {},
  };
}

Deno.test("exact Professional above-budget response renders instead of unavailable", () => {
  const ui = {
    preview: element(), budget: element(), package: element(), packageRow: element(), minimum: element(),
    minimumRow: element(), state: element(), status: element(), warning: element(), advice: element(),
  };
  const renderPricingPreview = Function(
    "clearPricingPresentation",
    "setPricingBadge",
    "budgetGuardPreview",
    "budgetGuardBudget",
    "selectedBudgetLabel",
    "budgetGuardPackage",
    "budgetGuardPackageRow",
    "euroFormatter",
    "budgetGuardMinimum",
    "budgetGuardMinimumRow",
    "budgetGuardState",
    "budgetGuardStatus",
    "budgetGuardWarningActions",
    "budgetGuardPackageAdvice",
    `"use strict"; return (${sourceFunction("renderPricingPreview")});`,
  )(
    () => {},
    () => {},
    ui.preview,
    ui.budget,
    () => "Minder dan € 1.800",
    ui.package,
    ui.packageRow,
    new Intl.NumberFormat("nl-BE", {
      style: "currency",
      currency: "EUR",
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }),
    ui.minimum,
    ui.minimumRow,
    ui.state,
    ui.status,
    ui.warning,
    ui.advice,
  ) as (renderedPreview: typeof preview) => void;

  let unavailable = false;
  if (!validPreview(preview, 5)) unavailable = true;
  else renderPricingPreview(preview);

  assertEquals(unavailable, false);
  assertEquals(ui.state.textContent, "Aandachtspunt");
  assertStringIncludes(ui.status.textContent, "boven je gekozen budget");
  assertStringIncludes(ui.package.textContent, "Professional");
  assertStringIncludes(ui.package.textContent, "12 standaardpagina's");
  assertEquals(ui.minimum.textContent.replaceAll(/\s/g, ""), "€3.200excl.btw");
  assertEquals(ui.minimumRow.hidden, false);
  assertEquals(ui.warning.hidden, false);
  assertEquals(ui.preview.classList.contains("budget-guard--warning"), true);
});

Deno.test("intake uses a fresh stable frontend cache key", () => {
  assertStringIncludes(html, '../assets/js/intake.js?v=20260811-3');
});

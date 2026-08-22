import { assertEquals, assertExists, assertFalse, assertNotEquals, assertStringIncludes } from "jsr:@std/assert@1";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const html = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));
const css = await Deno.readTextFile(new URL("../css/intake.css", import.meta.url));

function sourceFunction(name: string) {
  const match = source.match(new RegExp(`(?:async )?function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}`));
  assertExists(match);
  return match[0];
}

Deno.test("SEO pricing presentation anchor resolves to intake markup", () => {
  const selector = source.match(/EXTENSIVE_SEO: "([^"]+)"/)?.[1];
  assertExists(selector);
  assertEquals(selector, "#seo_scope");
  assertStringIncludes(html, `id="${selector.slice(1)}"`);
});

const preview = {
  previewContractVersion: 3,
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
    knownMinimumMinor: 350_000,
    containsFromPricing: false,
    manualReviewRequired: false,
    ...(false as boolean
      ? { manualScope: "ESSENTIAL" as "ESSENTIAL" | "OPTIONAL" }
      : {}),
  },
  items: [] as Array<Record<string, unknown>>,
  packageAdvice: { state: "NO_PACKAGE_ADVICE" },
  selectedPackage: {
    selectedPackageDefinitionId: "professional_v2",
    label: "Professional",
    floorMinor: 350_000,
    standardPageLimit: 10,
    includedCorrectionRounds: 2,
  },
};

const validPreview = Function(
  "form",
  "PREVIEW_CONTRACT_VERSION",
  "budgetStates",
  "budgetLabels",
  "packageAdviceStates",
  "packageDefinitionIds",
  "presentationAnchorSelectors",
  "itemStates",
  `"use strict"; return (${sourceFunction("validPreview")});`,
)(
  { querySelector: () => ({ value: "professional_v2" }) },
  3,
  new Set(["WITHIN_KNOWN_BUDGET", "KNOWN_MINIMUM_ABOVE_BUDGET", "INDETERMINATE", "MANUAL_REVIEW"]),
  { below_1800: "Minder dan € 1.800" },
  new Set(["NO_PACKAGE_ADVICE", "CONSIDER_PROFESSIONAL", "PERSONAL_REVIEW_RECOMMENDED"]),
  new Set(["starter_v1", "professional_v2"]),
  { PACKAGE_SCOPE: null, CUSTOMER_LOGIN: "#customer_login" },
  new Set(["INCLUDED", "FIXED_EXTRA", "FROM_EXTRA", "MANUAL_REVIEW"]),
) as (preview: unknown, revision: number) => boolean;

const canonicalValue = Function(`"use strict"; return (${sourceFunction("canonicalValue")});`)() as (value: unknown) => unknown;
const pricingFingerprint = Function(
  "canonicalValue",
  `"use strict"; return (${sourceFunction("pricingFingerprint")});`,
)(canonicalValue) as (value: unknown) => string;
const budgetGuardAcknowledgementKey = Function(
  "pricingFingerprint",
  `"use strict"; return (${sourceFunction("budgetGuardAcknowledgementKey")});`,
)(pricingFingerprint) as (renderedPreview: typeof preview, evidenceFingerprint: string) => string;
const budgetGuardAllowsSubmit = Function(
  `"use strict"; return (${sourceFunction("budgetGuardAllowsSubmit")});`,
)() as (
  status: string,
  currentKey: string,
  acknowledgementKey: string,
  previewEvidenceFingerprint: string,
  currentEvidenceFingerprint: string,
) => boolean;
const pricingPreviewMatchesCurrentEvidence = Function(
  `"use strict"; return (${sourceFunction("pricingPreviewMatchesCurrentEvidence")});`,
)() as (
  requestRevision: number,
  currentRevision: number,
  requestFingerprint: string,
  currentEvidenceFingerprint: string,
  aborted: boolean,
) => boolean;
const isPackageFloorMismatch = Function(
  `"use strict"; return (${sourceFunction("isPackageFloorMismatch")});`,
)() as (renderedPreview: typeof preview) => boolean;
const budgetGuardMismatchMessage = Function(
  "isPackageFloorMismatch",
  "euroFormatter",
  `"use strict"; return (${sourceFunction("budgetGuardMismatchMessage")});`,
)(isPackageFloorMismatch, new Intl.NumberFormat("nl-BE", {
  style: "currency",
  currency: "EUR",
  minimumFractionDigits: 0,
  maximumFractionDigits: 2,
})) as (renderedPreview: typeof preview) => string;

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

function renderSequence(renderedPreviews: Array<typeof preview>) {
  const ui = {
    preview: element(), budget: element(), packageRow: element(), minimum: element(),
    packageName: element(), packagePages: element(), packageRounds: element(),
    minimumRow: element(), state: element(), status: element(), warning: element(), advice: element(),
  };
  const renderPricingPreview = Function(
    "clearPricingPresentation",
    "setPricingBadge",
    "budgetGuardPreview",
    "budgetGuardBudget",
    "selectedBudgetLabel",
    "budgetGuardPackageName",
    "budgetGuardPackagePages",
    "budgetGuardPackageRounds",
    "budgetGuardPackageRow",
    "euroFormatter",
    "budgetGuardMinimum",
    "budgetGuardMinimumRow",
    "budgetGuardState",
    "budgetGuardStatus",
    "budgetGuardWarningActions",
    "budgetGuardPackageAdvice",
    "budgetGuardAcknowledgementKey",
    "budgetGuardAllowsSubmit",
    "isPackageFloorMismatch",
    "budgetGuardMismatchMessage",
    "currentBudgetGuardStatus",
    "currentBudgetGuardKey",
    "currentBudgetGuardEvidenceFingerprint",
    "acknowledgedBudgetGuardKey",
    "pricingEvidenceFingerprint",
    `"use strict"; return (${sourceFunction("renderPricingPreview")});`,
  )(
    () => {
      ui.advice.textContent = "";
      ui.advice.hidden = true;
    },
    () => {},
    ui.preview,
    ui.budget,
    () => "Minder dan € 1.800",
    ui.packageName,
    ui.packagePages,
    ui.packageRounds,
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
    budgetGuardAcknowledgementKey,
    budgetGuardAllowsSubmit,
    isPackageFloorMismatch,
    budgetGuardMismatchMessage,
    "",
    "",
    pricingFingerprint({ budget: "below_1800", package: "professional_v2" }),
    "",
    pricingFingerprint({ budget: "below_1800", package: "professional_v1" }),
  ) as (renderedPreview: typeof preview, evidenceFingerprint: string) => void;

  renderedPreviews.forEach((renderedPreview) => {
    renderPricingPreview(renderedPreview, pricingFingerprint({
      budget: "below_1800",
      package: renderedPreview.selectedPackage.selectedPackageDefinitionId,
    }));
  });
  return ui;
}

function render(renderedPreview: typeof preview) {
  return renderSequence([renderedPreview]);
}

Deno.test("package summary renders structured lines for Starter and Professional", () => {
  assertStringIncludes(html, 'class="budget-guard__package"><strong id="budgetGuardPackageName"></strong><span id="budgetGuardPackagePages"></span><span id="budgetGuardPackageRounds"></span>');
  assertStringIncludes(css, ".budget-guard__package { display: grid;");
  assertStringIncludes(css, ".budget-guard__package span { color: var(--color-text-soft);");

  const professionalUi = render(preview);
  assertEquals(professionalUi.packageName.textContent, "Professional");
  assertEquals(professionalUi.packagePages.textContent, "Max. 10 standaardpagina's");
  assertEquals(professionalUi.packageRounds.textContent, "2 correctierondes");

  const starterPreview = structuredClone(preview);
  starterPreview.selectedPackage.selectedPackageDefinitionId = "starter_v1";
  starterPreview.selectedPackage.label = "Starter";
  starterPreview.selectedPackage.floorMinor = 180_000;
  starterPreview.selectedPackage.standardPageLimit = 5;
  starterPreview.selectedPackage.includedCorrectionRounds = 1;
  const starterUi = render(starterPreview);
  assertEquals(starterUi.packageName.textContent, "Starter");
  assertEquals(starterUi.packagePages.textContent, "Max. 5 standaardpagina's");
  assertEquals(starterUi.packageRounds.textContent, "1 correctieronde");
});

Deno.test("selected Professional suppresses redundant Professional recommendation", () => {
  const professionalPreview = structuredClone(preview);
  professionalPreview.packageAdvice.state = "CONSIDER_PROFESSIONAL";

  const ui = render(professionalPreview);

  assertEquals(ui.packageName.textContent, "Professional");
  assertEquals(ui.advice.hidden, true);
  assertEquals(ui.advice.textContent, "");
});

Deno.test("Professional recommendation remains visible when Starter is selected", () => {
  const starterPreview = structuredClone(preview);
  starterPreview.selectedPackage.selectedPackageDefinitionId = "starter_v1";
  starterPreview.selectedPackage.label = "Starter";
  starterPreview.selectedPackage.floorMinor = 180_000;
  starterPreview.selectedPackage.standardPageLimit = 5;
  starterPreview.selectedPackage.includedCorrectionRounds = 1;
  starterPreview.packageAdvice.state = "CONSIDER_PROFESSIONAL";

  const ui = render(starterPreview);

  assertEquals(ui.packageName.textContent, "Starter");
  assertEquals(ui.advice.hidden, false);
  assertEquals(
    ui.advice.textContent,
    "Op basis van je wensen kan Professional interessanter zijn. Er is geen pakket automatisch geselecteerd.",
  );
});

Deno.test("current Professional render clears prior advice from print-visible DOM", () => {
  const starterPreview = structuredClone(preview);
  starterPreview.selectedPackage.selectedPackageDefinitionId = "starter_v1";
  starterPreview.selectedPackage.label = "Starter";
  starterPreview.packageAdvice.state = "CONSIDER_PROFESSIONAL";
  const professionalPreview = structuredClone(preview);
  professionalPreview.packageAdvice.state = "CONSIDER_PROFESSIONAL";

  const ui = renderSequence([starterPreview, professionalPreview]);

  assertEquals(ui.packageName.textContent, "Professional");
  assertEquals(ui.advice.hidden, true);
  assertEquals(ui.advice.textContent, "");
});

Deno.test("exact Professional above-budget response renders instead of unavailable", () => {
  const ui = render(preview);

  let unavailable = false;
  if (!validPreview(preview, 5)) unavailable = true;

  assertEquals(unavailable, false);
  assertEquals(ui.state.textContent, "Budget en pakket niet compatibel");
  assertEquals(ui.status.textContent.replaceAll(/\s/g, " "), "Het Professional-pakket start vanaf € 3.500 excl. btw. Je opgegeven budget ligt onder dit minimum.");
  assertEquals(ui.packageName.textContent, "Professional");
  assertEquals(ui.packagePages.textContent, "Max. 10 standaardpagina's");
  assertEquals(ui.packageRounds.textContent, "2 correctierondes");
  assertEquals(ui.minimum.textContent.replaceAll(/\s/g, ""), "€3.500excl.btw");
  assertEquals(ui.minimumRow.hidden, false);
  assertNotEquals(ui.state.textContent, "Niet beschikbaar");
  assertEquals(ui.warning.hidden, false);
  assertEquals(ui.preview.classList.contains("budget-guard--warning"), true);
});

Deno.test("Starter and Professional package floors remain unchanged", () => {
  const starterPreview = structuredClone(preview);
  starterPreview.selectedPackage.selectedPackageDefinitionId = "starter_v1";
  starterPreview.selectedPackage.label = "Starter";
  starterPreview.selectedPackage.floorMinor = 180_000;
  starterPreview.selectedPackage.standardPageLimit = 5;
  starterPreview.selectedPackage.includedCorrectionRounds = 1;
  starterPreview.summary.knownMinimumMinor = 180_000;
  const starterUi = render(starterPreview);
  const professionalUi = render(preview);

  assertEquals(starterUi.packageName.textContent, "Starter");
  assertEquals(starterUi.minimum.textContent.replaceAll(/\s/g, ""), "€1.800excl.btw");
  assertEquals(professionalUi.packageName.textContent, "Professional");
  assertEquals(professionalUi.minimum.textContent.replaceAll(/\s/g, ""), "€3.500excl.btw");
});

Deno.test("combined manual review and package-floor mismatch renders both warnings", () => {
  const combinedPreview = structuredClone(preview);
  combinedPreview.summary.manualReviewRequired = true;
  combinedPreview.summary.manualScope = "ESSENTIAL";
  combinedPreview.summary.containsFromPricing = true;
  combinedPreview.items = [{
    presentationKey: "CUSTOMER_LOGIN",
    labelKey: "pricing_preview.customer_login",
    state: "MANUAL_REVIEW",
  }];

  assertEquals(validPreview(combinedPreview, 5), true);
  const ui = render(combinedPreview);
  assertEquals(ui.state.textContent, "Essentieel maatwerk te beoordelen");
  assertStringIncludes(ui.status.textContent, "onderdelen waarvoor de prijs persoonlijk beoordeeld moet worden");
  assertStringIncludes(ui.status.textContent.replaceAll(/\s/g, " "), "start het gekozen Professional-pakket vanaf € 3.500 excl. btw");
  assertStringIncludes(ui.status.textContent, "budget daaronder ligt");
  assertEquals(ui.warning.hidden, false);
  assertEquals(ui.preview.classList.contains("budget-guard--manual"), true);
  assertEquals(ui.preview.classList.contains("budget-guard--warning"), true);
});

Deno.test("manual review with a compatible budget keeps the known minimum visible", () => {
  const combinedPreview = structuredClone(preview);
  combinedPreview.budget.comparisonStatus = "WITHIN_KNOWN_BUDGET";
  combinedPreview.budget.knownMinimumExceedsBudget = false;
  combinedPreview.summary.manualReviewRequired = true;
  combinedPreview.summary.manualScope = "ESSENTIAL";
  combinedPreview.summary.containsFromPricing = true;
  combinedPreview.items = [{
    presentationKey: "CUSTOMER_LOGIN",
    labelKey: "pricing_preview.customer_login",
    state: "MANUAL_REVIEW",
  }];

  assertEquals(validPreview(combinedPreview, 5), true);
  const ui = render(combinedPreview);
  assertEquals(ui.minimum.textContent.replaceAll(/\s/g, ""), "€3.500excl.btw");
  assertEquals(ui.minimumRow.hidden, false);
  assertEquals(ui.state.textContent, "Essentieel maatwerk te beoordelen");
  assertStringIncludes(ui.status.textContent, "persoonlijk beoordeeld");
});

Deno.test("known fixed and from badges keep their amounts beside manual review", () => {
  function badge() {
    const visible = { textContent: "" };
    const accessible = { textContent: "" };
    const classes = new Set<string>();
    return {
      hidden: true,
      visible,
      accessible,
      classList: { add: (name: string) => classes.add(name), contains: (name: string) => classes.has(name) },
      querySelector: (selector: string) => selector === ".pricing-status__visible" ? visible : accessible,
    };
  }
  const fixedBadge = badge();
  const fromBadge = badge();
  const setPricingBadge = Function(
    "pricingBadges",
    "euroFormatter",
    "euroNumberFormatter",
    `"use strict"; return (${sourceFunction("setPricingBadge")});`,
  )(
    new Map([["SIMPLE_QUOTE_FORM", fixedBadge], ["EXTRA_LANGUAGE", fromBadge]]),
    new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR", maximumFractionDigits: 2 }),
    new Intl.NumberFormat("nl-BE", { maximumFractionDigits: 2 }),
  ) as (item: Record<string, unknown>) => void;

  setPricingBadge({ presentationKey: "SIMPLE_QUOTE_FORM", state: "FIXED_EXTRA", amountMinor: 20_000 });
  setPricingBadge({ presentationKey: "EXTRA_LANGUAGE", state: "FROM_EXTRA", amountMinor: 50_000, quantity: 2 });

  assertStringIncludes(fixedBadge.visible.textContent, "€\u00a0200");
  assertEquals(fixedBadge.classList.contains("pricing-status--fixed"), true);
  assertStringIncludes(fromBadge.visible.textContent, "€\u00a0500");
  assertStringIncludes(fromBadge.visible.textContent, "× 2");
  assertEquals(fromBadge.classList.contains("pricing-status--from"), true);
});

Deno.test("paid stock badge discloses separate external licence costs", () => {
  const visible = { textContent: "" };
  const accessible = { textContent: "" };
  const classes = new Set<string>();
  const paidStockBadge = {
    hidden: true,
    classList: { add: (name: string) => classes.add(name) },
    querySelector: (selector: string) => selector === ".pricing-status__visible" ? visible : accessible,
  };
  const setPricingBadge = Function(
    "pricingBadges",
    "euroFormatter",
    "euroNumberFormatter",
    `"use strict"; return (${sourceFunction("setPricingBadge")});`,
  )(
    new Map([["PAID_STOCK", paidStockBadge]]),
    new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR", maximumFractionDigits: 2 }),
    new Intl.NumberFormat("nl-BE", { maximumFractionDigits: 2 }),
  ) as (item: Record<string, unknown>) => void;

  setPricingBadge({
    presentationKey: "PAID_STOCK",
    state: "FROM_EXTRA",
    amountMinor: 10_000,
    externalCost: true,
  });

  assertStringIncludes(visible.textContent, "€\u00a0100");
  assertStringIncludes(visible.textContent, "licentiekosten niet inbegrepen");
  assertStringIncludes(accessible.textContent, "Externe licentiekosten niet inbegrepen");
  assertEquals(classes.has("pricing-status--from"), true);
  assertEquals(paidStockBadge.hidden, false);
});

Deno.test("supplement mismatch keeps generic copy", () => {
  const supplementPreview = structuredClone(preview);
  supplementPreview.summary.knownMinimumMinor = 380_000;
  supplementPreview.items = [{
    presentationKey: "PACKAGE_SCOPE",
    labelKey: "pricing_preview.package_scope",
    state: "FIXED_EXTRA",
    amountMinor: 30_000,
  }];
  const ui = render(supplementPreview);
  assertEquals(ui.status.textContent, "Het huidige bekende minimum ligt boven je gekozen budget.");
  assertFalse(ui.status.textContent.includes("Professional-pakket start vanaf"));
});

Deno.test("package action replaces scope review action", () => {
  assertStringIncludes(html, 'id="changePackage" type="button">Pakket wijzigen</button>');
  assertFalse(html.includes('id="reviewScope"'));
  assertStringIncludes(source, 'document.getElementById("changePackage").addEventListener');
});

Deno.test("mismatch requires acknowledgement for the current key", () => {
  const evidence = pricingFingerprint({ budget: "below_1800" });
  const key = budgetGuardAcknowledgementKey(preview, evidence);
  assertEquals(budgetGuardAllowsSubmit("KNOWN_MINIMUM_ABOVE_BUDGET", key, "", evidence, evidence), false);
  assertEquals(budgetGuardAllowsSubmit("KNOWN_MINIMUM_ABOVE_BUDGET", key, key, evidence, evidence), true);
});

Deno.test("combined state requires a current Model B acknowledgement", () => {
  const combinedPreview = structuredClone(preview);
  combinedPreview.summary.manualReviewRequired = true;
  combinedPreview.summary.manualScope = "ESSENTIAL";
  const evidence = pricingFingerprint({ budget: "below_1800", manual: true });
  const key = budgetGuardAcknowledgementKey(combinedPreview, evidence);
  assertEquals(budgetGuardAllowsSubmit(combinedPreview.budget.comparisonStatus, key, "", evidence, evidence), false);
  assertEquals(budgetGuardAllowsSubmit(combinedPreview.budget.comparisonStatus, key, key, evidence, evidence), true);
});

Deno.test("review or budget status changes invalidate acknowledgement", () => {
  const evidence = pricingFingerprint({ budget: "below_1800" });
  const before = budgetGuardAcknowledgementKey(preview, evidence);

  const reviewChanged = structuredClone(preview);
  reviewChanged.summary.manualReviewRequired = true;
  reviewChanged.summary.manualScope = "ESSENTIAL";
  assertNotEquals(budgetGuardAcknowledgementKey(reviewChanged, evidence), before);

  const budgetChanged = structuredClone(preview);
  budgetChanged.budget.comparisonStatus = "WITHIN_KNOWN_BUDGET";
  budgetChanged.budget.knownMinimumExceedsBudget = false;
  assertNotEquals(budgetGuardAcknowledgementKey(budgetChanged, evidence), before);
});

Deno.test("multilingual A-B-C-B-A fingerprints reject stale and aborted responses", () => {
  const sequence = [["fr"], ["fr", "en"], ["fr", "en", "de"], ["fr", "en"], ["fr"]];
  let previousFingerprint = "";

  sequence.forEach((additionalLanguages, index) => {
    const revision = index + 1;
    const fingerprint = pricingFingerprint({
      primary_language: "nl",
      additional_languages: additionalLanguages,
      multilingual_details: {
        final_translations_supplied: false,
        same_structure: true,
        translation_required: true,
      },
    });

    assertNotEquals(fingerprint, previousFingerprint);
    assertEquals(
      pricingPreviewMatchesCurrentEvidence(revision, revision, fingerprint, fingerprint, false),
      true,
    );
    assertEquals(
      pricingPreviewMatchesCurrentEvidence(revision, revision, fingerprint, fingerprint, true),
      false,
    );
    if (previousFingerprint) {
      assertEquals(
        pricingPreviewMatchesCurrentEvidence(
          revision - 1,
          revision,
          previousFingerprint,
          fingerprint,
          false,
        ),
        false,
      );
    }
    previousFingerprint = fingerprint;
  });
});

Deno.test("budget change invalidates acknowledgement", () => {
  const before = budgetGuardAcknowledgementKey(preview, pricingFingerprint({ budget: "below_1800" }));
  const after = budgetGuardAcknowledgementKey(preview, pricingFingerprint({ budget: "1800_to_below_3500" }));
  assertNotEquals(after, before);
  assertEquals(budgetGuardAllowsSubmit("KNOWN_MINIMUM_ABOVE_BUDGET", after, before, "budget-after", "budget-after"), false);
});

Deno.test("package change invalidates acknowledgement", () => {
  const before = budgetGuardAcknowledgementKey(preview, pricingFingerprint({ package: "professional_v1" }));
  const changedPreview = structuredClone(preview);
  changedPreview.selectedPackage.selectedPackageDefinitionId = "starter_v1";
  changedPreview.selectedPackage.label = "Starter";
  changedPreview.selectedPackage.floorMinor = 180_000;
  changedPreview.summary.knownMinimumMinor = 180_000;
  const after = budgetGuardAcknowledgementKey(changedPreview, pricingFingerprint({ package: "starter_v1" }));
  assertNotEquals(after, before);
});

Deno.test("pricing-relevant scope change invalidates acknowledgement", () => {
  const before = budgetGuardAcknowledgementKey(preview, pricingFingerprint({ requested_pages: ["home"] }));
  const after = budgetGuardAcknowledgementKey(preview, pricingFingerprint({ requested_pages: ["home", "blog"] }));
  assertNotEquals(after, before);
});

Deno.test("changed server preview invalidates old acknowledgement", () => {
  const evidence = pricingFingerprint({ budget: "below_1800", package: "professional_v1" });
  const before = budgetGuardAcknowledgementKey(preview, evidence);
  const changedPreview = structuredClone(preview);
  changedPreview.pricingConfigVersion = "production-next";
  changedPreview.summary.knownMinimumMinor = 330_000;
  const after = budgetGuardAcknowledgementKey(changedPreview, evidence);
  assertNotEquals(after, before);
  assertEquals(budgetGuardAllowsSubmit("KNOWN_MINIMUM_ABOVE_BUDGET", after, before, evidence, evidence), false);
});

Deno.test("compatible preview needs no acknowledgement", () => {
  assertEquals(budgetGuardAllowsSubmit("WITHIN_KNOWN_BUDGET", "compatible-key", "", "evidence", "evidence"), true);
});

Deno.test("pending or stale preview fails closed until current compatible response arrives", () => {
  assertEquals(budgetGuardAllowsSubmit("", "", "", "", "changed-evidence"), false);
  assertEquals(budgetGuardAllowsSubmit("WITHIN_KNOWN_BUDGET", "old-key", "", "old-evidence", "changed-evidence"), false);
  assertEquals(budgetGuardAllowsSubmit("WITHIN_KNOWN_BUDGET", "new-key", "", "changed-evidence", "changed-evidence"), true);
});

Deno.test("stale or aborted response cannot validate current evidence", () => {
  assertEquals(pricingPreviewMatchesCurrentEvidence(4, 5, "old", "current", false), false);
  assertEquals(pricingPreviewMatchesCurrentEvidence(5, 5, "old", "current", false), false);
  assertEquals(pricingPreviewMatchesCurrentEvidence(5, 5, "current", "current", true), false);
  assertEquals(pricingPreviewMatchesCurrentEvidence(5, 5, "current", "current", false), true);
});

Deno.test("contains-from pricing change invalidates acknowledgement", () => {
  const evidence = pricingFingerprint({ budget: "below_1800", package: "professional_v1" });
  const before = budgetGuardAcknowledgementKey(preview, evidence);
  const changedPreview = structuredClone(preview);
  changedPreview.summary.containsFromPricing = true;
  const after = budgetGuardAcknowledgementKey(changedPreview, evidence);
  assertNotEquals(after, before);
  assertEquals(budgetGuardAllowsSubmit("KNOWN_MINIMUM_ABOVE_BUDGET", after, before, evidence, evidence), false);
});

Deno.test("item semantics invalidate acknowledgement but item order does not", () => {
  const evidence = pricingFingerprint({ budget: "below_1800", package: "professional_v1" });
  const withItems = structuredClone(preview);
  withItems.items = [
    { presentationKey: "SEO_BASE", state: "INCLUDED" },
    { presentationKey: "CONTACT_FORM", state: "INCLUDED" },
  ];
  const before = budgetGuardAcknowledgementKey(withItems, evidence);
  const reordered = structuredClone(withItems);
  reordered.items.reverse();
  assertEquals(budgetGuardAcknowledgementKey(reordered, evidence), before);
  const changed = structuredClone(withItems);
  changed.items[0] = { presentationKey: "SEO_BASE", state: "FIXED_EXTRA", amountMinor: 10_000 };
  const after = budgetGuardAcknowledgementKey(changed, evidence);
  assertNotEquals(after, before);
  assertEquals(budgetGuardAllowsSubmit("KNOWN_MINIMUM_ABOVE_BUDGET", after, before, evidence, evidence), false);
});

Deno.test("irrelevant response revision does not invalidate acknowledgement", () => {
  const evidence = pricingFingerprint({ budget: "below_1800", package: "professional_v1" });
  const before = budgetGuardAcknowledgementKey(preview, evidence);
  const refreshed = structuredClone(preview);
  refreshed.scopeRevision += 1;
  assertEquals(budgetGuardAcknowledgementKey(refreshed, evidence), before);
});

Deno.test("normal submit executes the pending-preview gate", () => {
  const data = Object.fromEntries([
    "business_description", "target_audience", "primary_conversion_goal", "brand_status", "logo_status",
    "content_status", "image_status", "domain_status", "hosting_status", "maintenance_interest", "seo_priority",
  ].map((name) => [name, "valid"]));
  Object.assign(data, {
    website_goals: ["professional_presence"], requested_pages: ["home"], design_styles: ["modern"],
    priorities: ["usability"], selected_package_definition_id: "professional_v1", confirmation: true,
  });
  let gateCalls = 0;
  let gateResult = false;
  const validateSubmit = Function(
    "collectData", "collectValidationIssues", "orderValidationIssues", "renderValidationIssues", "form",
    "validationControl", "showStep", "steps", "validateBudgetGuardAcknowledgement",
    `"use strict"; return (${sourceFunction("validateSubmit")});`,
  )(
    () => data, () => [], (issues: unknown[]) => issues, () => {}, { elements: [] }, () => null, () => {}, [],
    () => { gateCalls += 1; return gateResult; },
  ) as () => boolean;
  assertEquals(validateSubmit(), false);
  assertEquals(gateCalls, 1);
  gateResult = true;
  assertEquals(validateSubmit(), true);
  assertEquals(gateCalls, 2);
});

Deno.test("final modal submit cannot bypass the pending-preview gate", async () => {
  let requestCalls = 0;
  let closeCalls = 0;
  const submitFinal = Function(
    "busy", "readOnly", "closeModal", "validateBudgetGuardAcknowledgement", "setBusy", "request", "collectData",
    "handleApiError", "setReadOnly", "setMessage", "dirty",
    `"use strict"; return (${sourceFunction("submitFinal")});`,
  )(
    false, false, () => { closeCalls += 1; }, () => false, () => {},
    async () => { requestCalls += 1; return { response: { ok: true }, body: { state: "submitted" } }; },
    () => ({}), () => {}, () => {}, () => {}, false,
  ) as () => Promise<void>;
  await submitFinal();
  assertEquals(closeCalls, 1);
  assertEquals(requestCalls, 0);
});

Deno.test("unknown and manual-only rendering do not invent a budget warning", () => {
  const unknownPreview = structuredClone(preview);
  unknownPreview.budget.comparisonStatus = "INDETERMINATE";
  unknownPreview.budget.knownMinimumExceedsBudget = false;
  unknownPreview.summary.knownMinimumMinor = undefined as unknown as number;
  const unknownUi = render(unknownPreview);
  assertEquals(unknownUi.state.textContent, "Nog te bepalen");
  assertStringIncludes(unknownUi.status.textContent, "nog niet betrouwbaar vergelijken");

  const manualPreview = structuredClone(preview);
  manualPreview.budget.comparisonStatus = "WITHIN_KNOWN_BUDGET";
  manualPreview.budget.knownMinimumExceedsBudget = false;
  delete (manualPreview.summary as Partial<typeof manualPreview.summary>).knownMinimumMinor;
  manualPreview.summary.manualReviewRequired = true;
  manualPreview.summary.manualScope = "ESSENTIAL";
  const manualUi = render(manualPreview);
  assertEquals(manualUi.state.textContent, "Essentieel maatwerk te beoordelen");
  assertStringIncludes(manualUi.status.textContent, "Noodzakelijk maatwerk");
  assertStringIncludes(manualUi.status.textContent, "niet geprijsd als €0");
  assertEquals(manualUi.warning.hidden, true);
  assertEquals(manualUi.preview.classList.contains("budget-guard--warning"), false);
});

Deno.test("unavailable rendering remains distinct from mismatch", () => {
  const unavailable = sourceFunction("showPreviewUnavailable");
  assertStringIncludes(unavailable, 'budgetGuardState.textContent = "Niet beschikbaar"');
  assertStringIncludes(unavailable, "budget-guard--unavailable");
  assertStringIncludes(unavailable, "clearPricingPresentation()");
  assertStringIncludes(unavailable, "budgetGuardBudget.textContent = selectedBudgetLabel(null)");
  assertStringIncludes(css, '.budget-guard__summary div[hidden] { display: none; }');
  assertStringIncludes(css, '.budget-guard--unavailable .budget-guard__summary div:first-child { grid-column: 1 / -1; }');
});

Deno.test("preview request explicitly negotiates the current contract", () => {
  assertStringIncludes(sourceFunction("requestBudgetGuardPreview"), "clientPreviewVersion: PREVIEW_CONTRACT_VERSION");
});

Deno.test("invalid HTTP 200 preview uses stale-version guidance and safe diagnostics", () => {
  const requestSource = sourceFunction("requestBudgetGuardPreview");
  assertStringIncludes(requestSource, "previewValidationRejectCode");
  assertStringIncludes(requestSource, "Deze intakepagina gebruikt een oudere versie");
  assertStringIncludes(requestSource, "expectedPreviewContractVersion");
  assertStringIncludes(requestSource, "receivedPreviewContractVersion");
  assertFalse(requestSource.includes("console.log(body)"));
});

Deno.test("429, 401 and generic unavailable flows remain distinct", () => {
  const errorSource = sourceFunction("handlePreviewError");
  assertStringIncludes(errorSource, "response.status === 401");
  assertStringIncludes(errorSource, "response.status === 429");
  assertStringIncludes(errorSource, "Prijsinformatie is tijdelijk gepauzeerd");
  assertStringIncludes(errorSource, "Prijsinformatie is tijdelijk niet beschikbaar");
});

Deno.test("intake uses a fresh stable frontend cache key", () => {
  assertStringIncludes(html, '../assets/css/intake.css?v=20260819-output2');
  assertStringIncludes(html, '../assets/js/intake.js?v=20260819-output2');
});

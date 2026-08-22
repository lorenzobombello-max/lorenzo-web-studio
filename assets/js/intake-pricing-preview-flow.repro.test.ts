import { assert, assertEquals, assertExists } from "jsr:@std/assert@1";
import { parseHTML } from "npm:linkedom@0.18.12";
import { calculateBudgetGuard } from "../../supabase/functions/_shared/pricing-engine.ts";
import type { RawPricingScope } from "../../supabase/functions/_shared/pricing-normalization.ts";
import { handlePricingPreview } from "../../supabase/functions/_shared/pricing-preview-handler.ts";
import type { PreviewRateLimitRpcClient } from "../../supabase/functions/_shared/preview-rate-limit.ts";
import {
  InputValidationError,
  sanitizeAndValidatePricingPreviewInput,
} from "../../supabase/functions/_shared/validation.ts";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const html = await Deno.readTextFile(new URL("../../pages/intake.html", import.meta.url));
const validationSource = await Deno.readTextFile(
  new URL("../../supabase/functions/_shared/validation.ts", import.meta.url),
);
const token = "A".repeat(43);
const origin = "https://lorenzowebsolutions.be";

function sourceFunction(name: string): string {
  const match = source.match(new RegExp(`  (?:async )?function ${name}\\([^]*?\\n  }`));
  assertExists(match, `Missing frontend function ${name}`);
  return match[0].trim();
}

function sourceValue<T>(name: string): T {
  const match = source.match(new RegExp(`const ${name} = ([^;]+);`));
  assertExists(match, `Missing frontend value ${name}`);
  return Function(`"use strict"; return (${match[1]});`)() as T;
}

function buildFrontendHarness() {
  const { document } = parseHTML(html) as unknown as { document: any };
  const form = document.getElementById("intakeForm") ?? document.querySelector("form");
  assertExists(form);

  for (const group of document.querySelectorAll("[data-options][data-name]")) {
    const name = group.dataset.name;
    assertExists(name);
    for (const pair of (group.dataset.options ?? "").split(",")) {
      const separator = pair.indexOf(":");
      const input = document.createElement("input");
      input.type = "checkbox";
      input.name = name;
      input.value = pair.slice(0, separator);
      group.append(input);
    }
  }
  for (const control of form.querySelectorAll("input, textarea, select")) {
    if (control.localName === "select") {
      for (const option of control.querySelectorAll("option")) {
        if (!option.hasAttribute("value")) option.setAttribute("value", option.textContent.trim());
      }
    }
    if (typeof control.value !== "string") {
      const initialValue = control.localName === "select"
        ? control.querySelector("option[selected]")?.value ?? control.querySelector("option")?.value ?? ""
        : control.getAttribute("value") ?? control.textContent ?? "";
      Object.defineProperty(control, "value", { configurable: true, writable: true, value: initialValue });
    }
    if (control.localName === "input" && ["checkbox", "radio"].includes(control.type) &&
      typeof control.checked !== "boolean") {
      Object.defineProperty(control, "checked", {
        configurable: true,
        writable: true,
        value: control.hasAttribute("checked"),
      });
    }
  }

  const commaFields = sourceValue<string[]>("commaFields");
  const arrayFields = sourceValue<string[]>("arrayFields");
  const booleanFields = sourceValue<string[]>("booleanFields");
  const pricingEvidenceFields = sourceValue<string[]>("pricingEvidenceFields");
  const packageDefinitionIds = sourceValue<Set<string>>("packageDefinitionIds");
  const scopedPages = sourceValue<string[]>("scopedPages");
  const onlinePaymentPurposeValues = sourceValue<string[]>("onlinePaymentPurposeValues");
  const onlinePaymentPurposeFeatures = onlinePaymentPurposeValues.map((purpose) => `online_payment_${purpose}`);
  const budgetCodes = sourceValue<Record<string, string>>("budgetCodes");
  const splitList = Function(`"use strict"; return (${sourceFunction("splitList")});`)();
  const selectedBoolean = Function("form", `"use strict"; return (${sourceFunction("selectedBoolean")});`)(form);
  const selectedValues = Function("form", `"use strict"; return (${sourceFunction("selectedValues")});`)(form);
  const collectData = Function(
    "form", "document", "commaFields", "arrayFields", "booleanFields", "packageDefinitionIds", "scopedPages",
    "onlinePaymentPurposeValues", "onlinePaymentPurposeFeatures",
    "budgetChoiceChanged", "restoredLegacyBudget", "budgetCodes", "restoredBudgetEvidence", "splitList",
    "selectedBoolean", "selectedValues", `"use strict"; return (${sourceFunction("collectData")});`,
  )(
    form, document, commaFields, arrayFields, booleanFields, packageDefinitionIds, scopedPages,
    onlinePaymentPurposeValues, onlinePaymentPurposeFeatures,
    false, null, budgetCodes, null, splitList, selectedBoolean, selectedValues,
  ) as () => Record<string, unknown>;
  const collectPricingEvidence = Function(
    "collectData", "pricingEvidenceFields", `"use strict"; return (${sourceFunction("collectPricingEvidence")});`,
  )(collectData, pricingEvidenceFields) as () => Record<string, unknown>;
  const canonicalValue = Function(`"use strict"; return (${sourceFunction("canonicalValue")});`)();
  const pricingFingerprint = Function(
    "canonicalValue", `"use strict"; return (${sourceFunction("pricingFingerprint")});`,
  )(canonicalValue) as (evidence: Record<string, unknown>) => string;
  const validPreview = Function(
    "form", "PREVIEW_CONTRACT_VERSION", "budgetStates", "budgetLabels", "packageAdviceStates",
    "packageDefinitionIds", "presentationAnchorSelectors", "itemStates",
    `"use strict"; return (${sourceFunction("validPreview")});`,
  )(
    form,
    3,
    sourceValue<Set<string>>("budgetStates"),
    sourceValue<Record<string, string>>("budgetLabels"),
    sourceValue<Set<string>>("packageAdviceStates"),
    packageDefinitionIds,
    sourceValue<Record<string, string | null>>("presentationAnchorSelectors"),
    sourceValue<Set<string>>("itemStates"),
  ) as (preview: Record<string, unknown>, revision: number) => boolean;

  function choose(name: string, value: string, checked = true) {
    const input = form.querySelector(`input[name="${name}"][value="${value}"]`);
    assertExists(input, `${name}=${value}`);
    if (checked && input.type === "radio") {
      for (const peer of form.querySelectorAll(`input[name="${name}"]`)) {
        peer.checked = false;
        peer.removeAttribute("checked");
      }
    }
    input.checked = checked;
    if (checked) input.setAttribute("checked", "");
    else input.removeAttribute("checked");
  }

  function value(id: string, nextValue: string) {
    const input = document.getElementById(id);
    assertExists(input, id);
    if (input.localName === "select") {
      for (const entry of input.querySelectorAll("option")) {
        if (!entry.hasAttribute("value")) entry.setAttribute("value", entry.textContent.trim());
      }
      const option = [...input.querySelectorAll("option")].find((entry) => entry.value === nextValue);
      assertExists(option, `${id}=${nextValue}`);
      for (const entry of input.querySelectorAll("option")) entry.selected = entry === option;
      Object.defineProperty(input, "value", { configurable: true, writable: true, value: nextValue });
    } else input.value = nextValue;
  }

  function check(selector: string, checked = true) {
    const input = selector.startsWith("#") ? document.querySelector(selector) : form.querySelector(selector);
    assertExists(input, selector);
    input.checked = checked;
    if (checked) input.setAttribute("checked", "");
    else input.removeAttribute("checked");
  }

  choose("shop_required", "false");
  choose("booking_required", "false");
  value("budget_update_category", "Minder dan EUR 1.800");
  choose("selected_package_definition_id", "starter_v1");

  return {
    document,
    form,
    choose,
    value,
    check,
    collectPricingEvidence,
    pricingFingerprint,
    validPreview,
  };
}

function allowedDecision() {
  return {
    data: [{ allowed: true, remaining: 20, reset_at: "2026-08-11T12:01:00Z", retry_after_seconds: 0 }],
    error: null,
  };
}

const client: PreviewRateLimitRpcClient = {
  rpc(name) {
    if (name === "inspect_preview_budget_guard_context_v1") {
      return Promise.resolve({
        data: [{
          intake_status: "in_progress",
          budget_label: "Minder dan EUR 1.800",
          budget_category_scheme: "budget_guard_v1",
          budget_category_code: "below_1800",
        }],
        error: null,
      });
    }
    return Promise.resolve(allowedDecision());
  },
};

const dependencies = {
  validateCapability(value: unknown) {
    if (value !== token) throw new Error("invalid token");
    return token;
  },
  hashCapability: () => Promise.resolve("a".repeat(64)),
  globalLimitKey: () => Promise.resolve("b".repeat(64)),
  capabilityLimitKey: () => Promise.resolve("c".repeat(64)),
  calculate(input: RawPricingScope) {
    return calculateBudgetGuard(input);
  },
};

type FrontendHarness = ReturnType<typeof buildFrontendHarness>;
type Mutation = (frontend: FrontendHarness) => void;

type TransitionResult = {
  name: string;
  evidence: Record<string, unknown>;
  delta: Record<string, { before?: unknown; after?: unknown }>;
  status: number;
  backendCode: string | null;
  validatorCode: string | null;
  validatorField: string | null;
  frontendAccepted: boolean;
  duplicatePresentationKeys: string[];
  items: Array<Record<string, unknown>>;
  knownMinimumMinor: number | null;
};

function evidenceDelta(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): Record<string, { before?: unknown; after?: unknown }> {
  const delta: Record<string, { before?: unknown; after?: unknown }> = {};
  for (const key of [...new Set([...Object.keys(before), ...Object.keys(after)])].sort()) {
    if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) {
      delta[key] = { before: before[key], after: after[key] };
    }
  }
  return delta;
}

async function runTransition(
  name: string,
  frontend: FrontendHarness,
  revision: number,
  previousEvidence: Record<string, unknown> = {},
): Promise<TransitionResult> {
  const evidence = frontend.collectPricingEvidence();
  let validatorCode: string | null = null;
  let validatorField: string | null = null;
  try {
    sanitizeAndValidatePricingPreviewInput(evidence);
  } catch (error) {
    if (!(error instanceof InputValidationError)) throw error;
    validatorCode = error.code;
    validatorField = error.field ?? null;
  }
  const response = await handlePricingPreview({
    action: "preview_budget_guard",
    token,
    scopeRevision: revision,
    clientPreviewVersion: 3,
    data: evidence,
  }, origin, client, dependencies);
  const body = await response.json();
  const presentationKeys = Array.isArray(body.preview?.items)
    ? body.preview.items.map((item: Record<string, unknown>) => String(item.presentationKey))
    : [];
  const duplicatePresentationKeys = [...new Set<string>(
    presentationKeys.filter((key: string, index: number) => presentationKeys.indexOf(key) !== index),
  )];
  const result: TransitionResult = {
    name,
    evidence,
    delta: evidenceDelta(previousEvidence, evidence),
    status: response.status,
    backendCode: typeof body.code === "string" ? body.code : null,
    validatorCode,
    validatorField,
    frontendAccepted: response.status === 200 && body.ok === true && frontend.validPreview(body.preview, revision),
    duplicatePresentationKeys,
    items: Array.isArray(body.preview?.items) ? body.preview.items : [],
    knownMinimumMinor: Number.isSafeInteger(body.preview?.summary?.knownMinimumMinor)
      ? body.preview.summary.knownMinimumMinor
      : null,
  };
  console.log(`REPRO_TRANSITION ${JSON.stringify({
    name: result.name,
    delta: result.delta,
    status: result.status,
    backendCode: result.backendCode,
    validatorCode: result.validatorCode,
    validatorField: result.validatorField,
    frontendAccepted: result.frontendAccepted,
    duplicatePresentationKeys: result.duplicatePresentationKeys,
    knownMinimumMinor: result.knownMinimumMinor,
  })}`);
  return result;
}

function selectPages(frontend: FrontendHarness, pages: string[]) {
  for (const page of pages) frontend.choose("requested_pages", page);
}

function setShop(frontend: FrontendHarness) {
  frontend.choose("shop_required", "true");
  frontend.value("shop_product_count", "24");
  frontend.check("#shop_categories");
  frontend.check("#shop_payments");
  frontend.check("#shop_shipping");
}

function setBooking(frontend: FrontendHarness) {
  frontend.choose("booking_required", "true");
  frontend.value("booking_type", "appointments");
  frontend.check("#booking_calendar");
}

function setQuoteForm(frontend: FrontendHarness, custom = false) {
  frontend.choose("requested_features", "quote_form");
  frontend.choose("quote_structure_scope", custom ? "unsure_or_other" : "basic_single_section");
  if (custom) frontend.check("#quote_custom_logic");
}

function setMultilingual(frontend: FrontendHarness) {
  frontend.choose("requested_features", "multilingual");
  frontend.check('[data-additional-language][value="fr"]');
  frontend.check("#translations_supplied");
}

function backendSet(name: string): Set<string> {
  const match = validationSource.match(new RegExp(`const ${name} = new Set\\((\\[[^]*?\\])\\);`));
  assertExists(match, `Missing backend set ${name}`);
  return Function(`"use strict"; return new Set(${match[1]});`)() as Set<string>;
}

function backendPreviewFields(): Set<string> {
  const match = validationSource.match(/const PRICING_PREVIEW_FIELDS = new Set\((\[[^]*?\])\);/);
  assertExists(match);
  return Function(`"use strict"; return new Set(${match[1]});`)() as Set<string>;
}

function controlValues(frontend: FrontendHarness, selector: string): Set<string> {
  return new Set(
    [...frontend.form.querySelectorAll(selector)]
      .map((control) => String(control.value ?? ""))
      .filter(Boolean),
  );
}

function sorted(values: Set<string>): string[] {
  return [...values].sort();
}

Deno.test("reproduction baseline uses real frontend evidence and returns a usable Starter preview", async () => {
  const frontend = buildFrontendHarness();
  const result = await runTransition("baseline", frontend, 1);
  const sanitized = sanitizeAndValidatePricingPreviewInput(result.evidence);
  assertEquals(sanitized.selected_package_definition_id, "starter_v1");
  assertEquals(sanitized.budget_update_category_code, "below_1800");
  assertEquals(result.status, 200);
  assertEquals(result.frontendAccepted, true);
  assertEquals(result.knownMinimumMinor, 180_000);
  assertEquals(frontend.pricingFingerprint(result.evidence).length > 0, true);
});

Deno.test("Professional multilingual transitions update the visible preview minimum", async () => {
  const frontend = buildFrontendHarness();
  frontend.choose("selected_package_definition_id", "professional_v2");
  let previous = frontend.collectPricingEvidence();
  let revision = 2;
  const amounts: number[] = [];
  const transition = async (name: string) => {
    const result = await runTransition(name, frontend, revision++, previous);
    assertEquals(result.frontendAccepted, true);
    assertEquals(result.duplicatePresentationKeys, []);
    amounts.push(result.knownMinimumMinor!);
    previous = result.evidence;
  };

  await transition("languages: 0");
  frontend.check('[data-additional-language][value="fr"]');
  await transition("languages: add fr");
  frontend.check('[data-additional-language][value="en"]');
  await transition("languages: add en");
  frontend.check('[data-additional-language][value="de"]');
  await transition("languages: add de");
  frontend.check('[data-additional-language][value="en"]', false);
  await transition("languages: remove en");
  frontend.check('[data-additional-language][value="fr"]', false);
  frontend.check('[data-additional-language][value="en"]');
  await transition("languages: change fr to en");
  frontend.check('[data-additional-language][value="en"]', false);
  frontend.check('[data-additional-language][value="de"]', false);
  await transition("languages: remove all");

  assertEquals(amounts, [350_000, 415_000, 460_000, 505_000, 460_000, 460_000, 350_000]);
});

Deno.test("multilingual SEO controls scale once across step 3 and step 8", async () => {
  const frontend = buildFrontendHarness();
  frontend.choose("selected_package_definition_id", "professional_v2");
  frontend.check('[data-additional-language][value="fr"]');
  frontend.check('[data-additional-language][value="en"]');
  frontend.check("#translations_supplied");
  frontend.check("#seo_per_language");
  frontend.check("#advanced_seo_research");
  frontend.check("#seo_extra_language");
  frontend.check("#seo_advanced_language");

  const result = await runTransition("languages: deduplicated SEO", frontend, 20);
  assertEquals(result.frontendAccepted, true);
  assertEquals(result.duplicatePresentationKeys, []);
  assertEquals(result.knownMinimumMinor, 630_000);
  const seo = result.items.find((item) => item.presentationKey === "EXTENSIVE_SEO");
  assertEquals(seo?.amountMinor, 170_000);
  assertEquals("quantity" in (seo ?? {}), false);
});

Deno.test("frontend and backend pricing preview schemas remain machine-readable peers", () => {
  const frontend = buildFrontendHarness();
  const frontendFields = new Set(sourceValue<string[]>("pricingEvidenceFields"));
  const backendFields = backendPreviewFields();
  const missingBackend = sorted(new Set([...frontendFields].filter((field) => !backendFields.has(field))));
  const extraBackend = sorted(new Set([...backendFields].filter((field) => !frontendFields.has(field))));
  assertEquals(missingBackend, []);
  assertEquals(extraBackend, []);

  const requestedFeatureValues = controlValues(frontend, 'input[name="requested_features"]');
  requestedFeatureValues.add("online_payment");
  for (const purpose of controlValues(frontend, 'input[name="online_payment_purposes"]')) {
    requestedFeatureValues.add(`online_payment_${purpose}`);
  }
  const valuePairs: Array<[string, Set<string>, Set<string>]> = [
    ["website_goals", controlValues(frontend, 'input[name="website_goals"]'), backendSet("WEBSITE_GOALS")],
    ["requested_pages", controlValues(frontend, 'input[name="requested_pages"]'), backendSet("REQUESTED_PAGES")],
    ["requested_features", requestedFeatureValues, backendSet("REQUESTED_FEATURES")],
    ["image_support", controlValues(frontend, 'input[name="image_support"]'), backendSet("IMAGE_SUPPORT")],
    ["content_status", controlValues(frontend, '#content_status option:not([value=""])'), backendSet("CONTENT_STATUSES")],
    ["image_status", controlValues(frontend, '#image_status option:not([value=""])'), backendSet("IMAGE_STATUSES")],
    ["hosting_status", controlValues(frontend, '#hosting_status option:not([value=""])'), backendSet("HOSTING_STATUSES")],
    ["hosting_support", controlValues(frontend, '#hosting_support option:not([value=""])'), backendSet("HOSTING_SUPPORT")],
    ["maintenance_interest", controlValues(frontend, '#maintenance_interest option:not([value=""])'), backendSet("MAINTENANCE_INTEREST")],
    ["seo_priority", controlValues(frontend, '#seo_priority option:not([value=""])'), backendSet("SEO_PRIORITIES")],
    ["booking_details.type", controlValues(frontend, "#booking_type option"), backendSet("BOOKING_TYPES")],
    ["selected_package_definition_id", controlValues(frontend, 'input[name="selected_package_definition_id"]'), backendSet("PACKAGE_DEFINITION_IDS")],
  ];
  const valueMismatch = valuePairs.flatMap(([field, frontendValues, backendValues]) =>
    JSON.stringify(sorted(frontendValues)) === JSON.stringify(sorted(backendValues))
      ? []
      : [{ field, frontend: sorted(frontendValues), backend: sorted(backendValues) }]
  );
  console.log(`REPRO_PARITY ${JSON.stringify({ missingBackend, extraBackend, valueMismatch, typeMismatch: [] })}`);
  assertEquals(valueMismatch, []);
});

Deno.test("incomplete existing booking system pauses preview until the name is valid", () => {
  const frontend = buildFrontendHarness();
  frontend.choose("booking_required", "true");
  frontend.value("booking_type", "reservations");

  const scheduler = Function(
    "collectPricingEvidence",
    "pricingFingerprint",
    "hasPricingEvidence",
    `"use strict";
      let readOnly = false;
      let previewStopped = false;
      const token = "${token}";
      const endpoint = "${origin}/functions/v1/intake-quote-request";
      let pricingEvidenceFingerprint = "";
      let acknowledgedBudgetGuardKey = "";
      let scopeRevision = 0;
      let previewTimer = null;
      let previewAbortController = null;
      let activeRequestFingerprint = "";
      let previewPausedUntil = 0;
      const PREVIEW_DEBOUNCE_MS = 350;
      const queued = new Map();
      let nextTimer = 0;
      const requests = [];
      let invalidations = 0;
      let loadingStates = 0;
      let unavailableStates = 0;
      const window = {
        setTimeout(callback) {
          nextTimer += 1;
          queued.set(nextTimer, callback);
          return nextTimer;
        },
      };
      function clearTimeout(id) { queued.delete(id); }
      const budgetGuardPreview = { hidden: false, setAttribute() {} };
      function invalidateCurrentBudgetGuardPreview() { invalidations += 1; }
      function clearPricingPresentation() {}
      function showPreviewUnavailable() { unavailableStates += 1; }
      function setPreviewLoading() { loadingStates += 1; }
      function requestBudgetGuardPreview(revision, evidence, fingerprint) {
        requests.push({ revision, evidence, fingerprint });
      }
      ${sourceFunction("schedulePricingPreview")}
      return {
        schedulePricingPreview,
        flush() {
          const callbacks = [...queued.values()];
          queued.clear();
          callbacks.forEach((callback) => callback());
        },
        requests,
        counts() { return { invalidations, loadingStates, unavailableStates }; },
      };`,
  )(
    frontend.collectPricingEvidence,
    frontend.pricingFingerprint,
    (evidence: Record<string, unknown>) => Object.keys(evidence).length > 0,
  ) as {
    schedulePricingPreview: (options?: { force?: boolean; immediate?: boolean }) => void;
    flush: () => void;
    requests: Array<{ evidence: Record<string, unknown> }>;
    counts: () => { invalidations: number; loadingStates: number; unavailableStates: number };
  };

  scheduler.schedulePricingPreview({ immediate: true });
  scheduler.flush();
  assertEquals(scheduler.requests.length, 1);
  assertEquals((scheduler.requests[0].evidence.booking_details as Record<string, unknown>).existing_system, false);

  frontend.check("#booking_calendar");
  scheduler.schedulePricingPreview();
  frontend.check("#booking_existing");
  const incompleteEvidence = frontend.collectPricingEvidence();
  let validatorError: InputValidationError | null = null;
  try {
    sanitizeAndValidatePricingPreviewInput(incompleteEvidence);
  } catch (error) {
    if (!(error instanceof InputValidationError)) throw error;
    validatorError = error;
  }
  assertExists(validatorError);
  assertEquals(validatorError.code, "REQUIRED_FIELD");
  assertEquals(validatorError.field, "booking_details.existing_system_name");

  const validCounts = scheduler.counts();
  scheduler.schedulePricingPreview({ immediate: true });
  scheduler.flush();
  assertEquals(scheduler.requests.length, 1);
  assertEquals(scheduler.counts(), validCounts);

  frontend.value("booking_system_name", "Calendly");
  scheduler.schedulePricingPreview({ immediate: true });
  scheduler.flush();
  assertEquals(scheduler.requests.length, 2);
  assertEquals(
    (scheduler.requests[1].evidence.booking_details as Record<string, unknown>).existing_system_name,
    "Calendly",
  );

  frontend.check("#booking_existing", false);
  scheduler.schedulePricingPreview({ immediate: true });
  scheduler.flush();
  assertEquals(scheduler.requests.length, 3);
  assertEquals(
    (scheduler.requests[2].evidence.booking_details as Record<string, unknown>).existing_system_name,
    null,
  );
  assertEquals(scheduler.counts().unavailableStates, 0);
});

Deno.test("every individual late-step pricing choice remains accepted", async () => {
  const scenarios: Array<[string, Mutation]> = [
    ["six standard pages", (f) => selectPages(f, ["home", "about", "services", "portfolio", "faq", "contact"])],
    ["complex reviews page", (f) => { f.choose("requested_pages", "reviews"); f.value("page_scope_reviews", "complex"); }],
    ["webshop and payments", (f) => { setShop(f); f.choose("online_payment_required", "true"); f.choose("online_payment_purposes", "products"); }],
    ["booking with calendar", setBooking],
    ["multilingual normal", setMultilingual],
    ["customer login", (f) => f.choose("requested_features", "customer_login")],
    ["basic quote form", (f) => setQuoteForm(f)],
    ["custom quote logic", (f) => setQuoteForm(f, true)],
    ["document flow", (f) => { f.choose("requested_features", "downloads"); f.value("download_access", "document_flow"); }],
    ["newsletter automation", (f) => { f.choose("requested_features", "newsletter"); f.value("newsletter_scope", "automation_or_segmentation"); }],
    ["external integration", (f) => f.value("integrations", "crm_example")],
    ["content help", (f) => f.value("content_status", "needs_help")],
    ["substantial copywriting", (f) => f.value("copywriting_scope", "substantial")],
    ["professional photography", (f) => f.choose("image_support", "professional_photography")],
    ["uncertain image support", (f) => f.choose("image_support", "unsure")],
    ["advanced image work", (f) => f.value("image_work_scope", "advanced")],
    ["paid stock handling", (f) => f.check("#paid_stock_handling")],
    ["search", (f) => f.choose("requested_features", "search")],
    ["complex SEO", (f) => { f.value("seo_priority", "high"); f.value("seo_scope", "complex"); }],
    ["hosting support", (f) => { f.value("hosting_status", "no_hosting"); f.value("hosting_support", "yes"); }],
    ["maintenance", (f) => f.value("maintenance_interest", "info_requested")],
    ["rush deadline", (f) => { f.value("deadline_date", "2026-12-01"); f.check("#deadline_hard"); }],
    ["other custom page", (f) => f.choose("requested_pages", "other")],
    ["uncertain feature scope", (f) => f.choose("requested_features", "unsure")],
    ["included analytics-adjacent controls", (f) => {
      f.choose("requested_features", "google_maps");
      f.choose("requested_features", "social_links");
    }],
  ];
  const failures: TransitionResult[] = [];
  let revision = 10;
  for (const [name, mutate] of scenarios) {
    const frontend = buildFrontendHarness();
    const previous = frontend.collectPricingEvidence();
    mutate(frontend);
    const result = await runTransition(`individual: ${name}`, frontend, revision++, previous);
    if (result.status !== 200 || !result.frontendAccepted) failures.push(result);
  }
  assertEquals(failures, []);
});

Deno.test("content help plus substantial copywriting yields one frontend-valid manual item", async () => {
  const frontend = buildFrontendHarness();
  frontend.value("content_status", "needs_help");
  const contentHelp = await runTransition("pair: content help", frontend, 80);
  frontend.value("copywriting_scope", "substantial");
  const combined = await runTransition("pair: substantial copywriting", frontend, 81, contentHelp.evidence);

  assertEquals(contentHelp.status, 200);
  assertEquals(contentHelp.frontendAccepted, true);
  assertEquals(combined.status, 200);
  assertEquals(combined.validatorCode, null);
  assertEquals(combined.frontendAccepted, true);
  assertEquals(combined.duplicatePresentationKeys, []);
  const copywritingItems = combined.items.filter((item) => item.presentationKey === "COPYWRITING");
  assertEquals(copywritingItems.length, 1);
  assertEquals(copywritingItems[0].state, "FROM_EXTRA");
  assertEquals("amountMinor" in copywritingItems[0], true);
});

Deno.test("full realistic flow accepts every pricing transition", async () => {
  const frontend = buildFrontendHarness();
  const steps: Array<[string, Mutation]> = [
    ["five standard pages", (f) => selectPages(f, ["home", "about", "services", "faq", "contact"])],
    ["sixth standard page", (f) => f.choose("requested_pages", "portfolio")],
    ["contact form", (f) => f.choose("requested_features", "contact_form")],
    ["basic quote form", (f) => setQuoteForm(f)],
    ["custom quote logic", (f) => { f.choose("quote_structure_scope", "unsure_or_other"); f.check("#quote_custom_logic"); }],
    ["webshop", setShop],
    ["online payment", (f) => { f.choose("online_payment_required", "true"); f.choose("online_payment_purposes", "services"); }],
    ["booking", setBooking],
    ["multilingual", setMultilingual],
    ["customer login", (f) => f.choose("requested_features", "customer_login")],
    ["document flow", (f) => { f.choose("requested_features", "downloads"); f.value("download_access", "document_flow"); }],
    ["newsletter automation", (f) => { f.choose("requested_features", "newsletter"); f.value("newsletter_scope", "automation_or_segmentation"); }],
    ["content help", (f) => f.value("content_status", "needs_help")],
    ["substantial copywriting", (f) => f.value("copywriting_scope", "substantial")],
    ["images partial", (f) => f.value("image_status", "partial")],
    ["professional photography", (f) => f.choose("image_support", "professional_photography")],
    ["advanced image work", (f) => f.value("image_work_scope", "advanced")],
    ["paid stock handling", (f) => f.check("#paid_stock_handling")],
    ["search", (f) => f.choose("requested_features", "search")],
    ["external integration", (f) => f.value("integrations", "crm_example")],
    ["complex SEO", (f) => { f.value("seo_priority", "high"); f.value("seo_scope", "complex"); }],
    ["hosting support", (f) => { f.value("hosting_status", "no_hosting"); f.value("hosting_support", "yes"); }],
    ["maintenance", (f) => f.value("maintenance_interest", "info_requested")],
    ["rush deadline", (f) => { f.value("deadline_date", "2026-12-01"); f.check("#deadline_hard"); }],
    ["custom page", (f) => f.choose("requested_pages", "other")],
  ];
  let previous: Record<string, unknown> = {};
  const results: TransitionResult[] = [];
  results.push(await runTransition("flow: baseline", frontend, 100, previous));
  previous = results.at(-1)!.evidence;
  let revision = 101;
  for (const [name, mutate] of steps) {
    mutate(frontend);
    const result = await runTransition(`flow: ${name}`, frontend, revision++, previous);
    results.push(result);
    previous = result.evidence;
  }
  const firstFailure = results.find((result) => result.status !== 200 || !result.frontendAccepted);
  const sixthPage = results.find((result) => result.name === "flow: sixth standard page");
  assertEquals(sixthPage?.knownMinimumMinor, 202_500);
  assertEquals(results.length, 26);
  assertEquals(firstFailure, undefined);
  assertEquals(results.every((result) => result.duplicatePresentationKeys.length === 0), true);
});
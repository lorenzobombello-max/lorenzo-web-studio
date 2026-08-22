import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1";
import { parseHTML } from "npm:linkedom@0.18.12";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const adminSource = await Deno.readTextFile(new URL("./admin-intake.js", import.meta.url));
const css = await Deno.readTextFile(new URL("../css/intake.css", import.meta.url));
const html = await Deno.readTextFile(
  new URL("../../pages/intake.html", import.meta.url),
);
const document = (parseHTML(html) as unknown as { document: any }).document;

function sourceFunction(name: string) {
  const signature = `function ${name}(`;
  const start = source.indexOf(signature);
  assert(start >= 0, `${name} must exist`);
  const bodyStart = source.indexOf("{", start);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}") depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

const stableControls: Record<string, string[]> = {
  page_scope_portfolio: ["normal", "dynamic"],
  page_scope_gallery: ["normal", "advanced", "complex", "unknown"],
  page_scope_reviews: ["normal", "live", "complex", "unknown"],
  search_tier: ["none", "basic", "advanced"],
  booking_tier: ["widget", "advanced", "custom"],
  download_access: [
    "none",
    "public",
    "download",
    "document_flow",
    "portal",
    "unknown",
  ],
  copywriting_scope: [
    "supplied",
    "light",
    "substantial",
    "new",
    "specialist",
    "unknown",
  ],
  image_work_scope: [
    "none",
    "standard",
    "advanced",
    "ai_set",
    "stock",
    "photography",
    "unknown",
  ],
  branding_tier: ["existing", "logo", "identity", "logo_identity", "extended"],
  domain_service: [
    "existing",
    "new",
    "dns",
    "transfer",
    "migration",
    "complex_dns_mail",
    "complex_migration",
  ],
  maintenance_plan: ["none", "care", "care_plus"],
  seo_scope: ["included", "launch", "complex"],
  analytics_scope: ["standard", "advanced"],
};

Deno.test("D47 D59 Phase D controls expose stable values with accessible labels", () => {
  for (const [id, expectedValues] of Object.entries(stableControls)) {
    const control = document.getElementById(id);
    assert(control, `missing #${id}`);
    assert(
      document.querySelector(`label[for="${id}"]`),
      `missing label for #${id}`,
    );
    const values = [...control.querySelectorAll("option")].map((option) =>
      option.getAttribute("value") ?? ""
    );
    for (const value of expectedValues) {
      assert(values.includes(value), `${id} missing ${value}`);
    }
  }
  for (
    const id of [
      "shop_complex_product_count",
      "shop_payment_provider_count",
      "shop_shipping_scope",
      "shop_customer_accounts",
      "shop_catalog_import",
      "shop_erp_api",
      "copy_page_count",
      "translation_required",
      "seo_per_language",
      "advanced_seo_research",
      "seo_extra_language",
      "seo_advanced_language",
      "custom_integration",
    ]
  ) assert(document.getElementById(id), `missing #${id}`);
  assert(document.getElementById("budgetGuardRecurringRow"));
  assert(document.getElementById("budgetGuardRecurring"));
});

Deno.test("D47-D48 collect and restore cover every Phase D evidence field", () => {
  const collect =
    source.match(/  function collectData\(\) \{[^]*?\n  \}/)?.[0] ?? "";
  const restore =
    source.match(/  function restoreData\(data\) \{[^]*?\n  \}/)?.[0] ?? "";
  for (
    const id of Object.keys(stableControls).concat([
      "shop_complex_product_count",
      "shop_payment_provider_count",
      "shop_shipping_scope",
      "shop_customer_accounts",
      "shop_catalog_import",
      "shop_erp_api",
      "copy_page_count",
      "translation_required",
      "seo_per_language",
      "advanced_seo_research",
      "seo_extra_language",
      "seo_advanced_language",
      "custom_integration",
    ])
  ) {
    if (id.startsWith("page_scope_")) {
      const page = id.replace("page_scope_", "");
      assertMatch(
        source,
        new RegExp(`const scopedPages = \\[[^\\]]*"${page}"`),
      );
      assert(
        collect.includes("`page_scope_${page}`"),
        `collectData missing scoped page loop for ${id}`,
      );
      assert(
        restore.includes("`page_scope_${page}`"),
        `restoreData missing scoped page loop for ${id}`,
      );
      continue;
    }
    assert(collect.includes(`"${id}"`), `collectData missing ${id}`);
    assert(restore.includes(`"${id}"`), `restoreData missing ${id}`);
  }
  for (
    const field of [
      "page_scope_details",
      "shop_details",
      "booking_details",
      "multilingual_details",
      "download_details",
      "content_media_details",
      "hosting_maintenance_details",
      "seo_details",
      "newsletter_details",
    ]
  ) {
    assertMatch(collect, new RegExp(`data\\.${field}`));
  }
});

Deno.test("D53 recurring preview is validated, fingerprinted, cleared and rendered separately", () => {
  assertMatch(source, /preview\.recurringServices/);
  assertMatch(source, /recurringServices[:,]/);
  assertMatch(source, /budgetGuardRecurringRow\.hidden = true/);
  assertMatch(source, /budgetGuardRecurring\.textContent/);
  assertEquals(/knownMinimumMinor[^\n]*recurringServices/.test(source), false);
});

Deno.test("webshop restore uses pickup scope with a conservative legacy fallback", () => {
  assertMatch(source, /function restoredPickupScope\(shopDetails\)/);
  assertMatch(source, /getElementById\("shop_pickup_scope"\)\.value = restoredPickupScope\(data\.shop_details\)/);
  assert(!source.includes('getElementById("shop_pickup").checked = data.shop_details.pickup'));
});

Deno.test("pricing dependencies and contradictory choices synchronize client-side", () => {
  const synchronize = sourceFunction("synchronizePricingChoices");
  for (const id of [
    "advanced_seo_research", "seo_per_language", "seo_advanced_language",
    "seo_extra_language", "translations_supplied", "translation_required",
  ]) assert(synchronize.includes(id));
  assertMatch(synchronize, /requested_pages[\s\S]*requested_features/);
  assertEquals(synchronize.includes("website_goals"), false);
  assertEquals(synchronize.includes('setChoice("shop_required"'), false);
  assertEquals(synchronize.includes('setChoice("booking_required"'), false);
  assertMatch(source, /synchronizePricingChoices\(event\.target\)/);
});

Deno.test("online payment is independent, structured and backward compatible", () => {
  const required = [...document.querySelectorAll('input[name="online_payment_required"]')];
  assertEquals(required.map((input) => input.getAttribute("value")), ["true", "false"]);
  const purposes = [...document.querySelectorAll('input[name="online_payment_purposes"]')]
    .map((input) => input.getAttribute("value"));
  assertEquals(purposes, [
    "products", "reservations", "appointments", "services", "registrations", "deposit", "other",
  ]);
  assert(document.getElementById("onlinePaymentFields"));

  const featureOptions = document.querySelector('[data-name="requested_features"]')
    ?.getAttribute("data-options") || "";
  for (const duplicate of ["appointments:", "reservations:", "shop:", "online_payment:"]) {
    assertEquals(featureOptions.includes(duplicate), false);
  }
  const goalOptions = [...document.querySelectorAll('input[name="website_goals"]')]
    .find((input) => input.getAttribute("value") === "professional_presence");
  assert(goalOptions?.hasAttribute("hidden"));

  const collect = sourceFunction("collectData");
  const restore = sourceFunction("restoreData");
  const conditionals = sourceFunction("updateConditionals");
  assertMatch(collect, /online_payment_required[\s\S]*online_payment_purposes/);
  assertMatch(restore, /requested_features[\s\S]*shop_details\?\.online_payments[\s\S]*online_payment_purposes/);
  assertMatch(conditionals, /online_payment_required[\s\S]*onlinePaymentFields/);
  assertMatch(conditionals, /shop_payments[\s\S]*onlinePayment[\s\S]*products/);
});

Deno.test("targeted shop and booking details only expose relevant customer controls", () => {
  const providerField = document.getElementById("shopPaymentProviderField");
  const bookingSystemNameField = document.getElementById("bookingSystemNameField");
  assert(providerField?.hasAttribute("hidden"));
  assert(bookingSystemNameField?.hasAttribute("hidden"));
  assert(document.getElementById("shop_shipping")?.hasAttribute("hidden"));
  assertEquals(document.querySelectorAll('label[for="shop_shipping_scope"]').length, 1);
  assertEquals(
    [...document.querySelectorAll("#shop_shipping_scope option")].map((option) => option.getAttribute("value")),
    ["none", "standard", "complex"],
  );

  const collect = sourceFunction("collectData");
  const restore = sourceFunction("restoreData");
  const conditionals = sourceFunction("updateConditionals");
  assertMatch(collect, /onlinePayment[\s\S]*payment_provider_count/);
  assertMatch(collect, /shippingScope !== "none"[\s\S]*shipping_scope/);
  assertMatch(collect, /shipping: shippingScope !== "none"/);
  assertMatch(restore, /restoredShippingScope\(data\.shop_details\)/);
  assertMatch(conditionals, /shopPaymentProviderField[\s\S]*shop && onlinePayment/);
  assertMatch(conditionals, /shop_shipping[\s\S]*shop_shipping_scope/);
  assertMatch(conditionals, /bookingSystemNameField[\s\S]*existingBookingSystem/);
  assertMatch(conditionals, /booking_system_name[\s\S]*value = ""/);
  assertMatch(css, /\.intake-step \.field\[hidden\] \{ display: none; \}/);
});

Deno.test("legacy shipping and booking drafts restore without duplicate requirements", () => {
  const shippingRestore = sourceFunction("restoredShippingScope");
  assertMatch(shippingRestore, /shipping === false[\s\S]*return "none"/);
  assertMatch(shippingRestore, /"standard", "complex"/);
  assertMatch(shippingRestore, /shipping === true[\s\S]*"standard"/);
  const restore = sourceFunction("restoreData");
  assertMatch(restore, /booking_existing[\s\S]*existing_system === true/);
  assertMatch(restore, /booking_system_name[\s\S]*existing_system_name/);
});

Deno.test("admin output labels every structured online payment purpose", () => {
  for (const purpose of [
    "products", "reservations", "appointments", "services", "registrations", "deposit", "other",
  ]) assert(adminSource.includes(`online_payment_${purpose}:`));
});

Deno.test("admin output omits legacy payment duplication and shows stored scope details", () => {
  assertEquals(adminSource.includes('["Online betalen", "online_payments"]'), false);
  assertMatch(adminSource, /detailValueLabels[\s\S]*tier[\s\S]*shipping_scope[\s\S]*pickup_scope/);
  for (const key of [
    "approx_product_count", "complex_product_count", "payment_provider_count", "shipping_scope",
    "pickup_scope", "customer_accounts", "existing_catalog", "catalog_import", "erp_api",
    "tier", "type", "existing_system", "existing_system_name", "calendar_integration",
  ]) assert(adminSource.includes(`"${key}"`), `admin output missing ${key}`);
});

Deno.test("customer review conditionally shows existing shop and booking details", () => {
  const review = sourceFunction("renderReviewSummary");
  assertMatch(review, /shopRequired[\s\S]*Verzending[\s\S]*shop_shipping_scope/);
  assertMatch(review, /bookingRequired[\s\S]*Reservatieoplossing[\s\S]*booking_tier/);
  assertMatch(review, /Type reservatie of afspraak[\s\S]*booking_type/);
  assertMatch(review, /Bestaand systeem[\s\S]*existingSystem \? "Ja" : "Nee"/);
  assertMatch(review, /existingSystem && existingSystemName[\s\S]*Naam bestaand systeem/);
  assertMatch(review, /Kalenderkoppeling[\s\S]*booking_calendar/);
});

Deno.test("intake navigation preserves five phases and twelve screens", () => {
  const definitions = source.slice(source.indexOf("const screenDefinitions"), source.indexOf("const phaseStartScreens"));
  assertEquals([...definitions.matchAll(/\{ phase: \d/g)].length, 12);
  assertMatch(source, /const phaseStartScreens = \[0, 3, 5, 8, 10\]/);
  assertMatch(source, /const phaseLabels = \[[^\]]*"Uw project"[^\]]*"Afronding"/);
});

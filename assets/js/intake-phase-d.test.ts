import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1";
import { parseHTML } from "npm:linkedom@0.18.12";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const html = await Deno.readTextFile(
  new URL("../../pages/intake.html", import.meta.url),
);
const document = (parseHTML(html) as unknown as { document: any }).document;

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
  assertMatch(source, /function synchronizePricingChoices\(target\)/);
  assertMatch(source, /advanced_seo_research[\s\S]*seo_per_language/);
  assertMatch(source, /seo_advanced_language[\s\S]*seo_extra_language/);
  assertMatch(source, /translations_supplied[\s\S]*translation_required/);
  assertMatch(source, /shop_required[\s\S]*requested_features/);
  assertMatch(source, /booking_required[\s\S]*appointments[\s\S]*reservations/);
  assertMatch(source, /synchronizePricingChoices\(event\.target\)/);
});

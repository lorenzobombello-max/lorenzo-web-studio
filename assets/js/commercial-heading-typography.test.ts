import { assertEquals, assertFalse, assertMatch, assertStringIncludes } from "jsr:@std/assert@1";

const css = await Deno.readTextFile(new URL("../css/pages.css", import.meta.url));
const homepageCss = await Deno.readTextFile(new URL("../css/redesign.css", import.meta.url));
const commercialPages = [
  "hosting-onderhoud.html",
  "integraties-automatisering.html",
  "klanten-ledenomgevingen.html",
  "multimedia-social.html",
  "pricing.html",
  "seo.html",
  "services.html",
  "webshops.html",
  "websites-op-maat.html",
] as const;
const versionedCorePages = [
  "pricing.html",
  "seo.html",
  "services.html",
  "websites-op-maat.html",
] as const;

const commercialRule = css.match(/\.page-hero--commercial h1 \{([^}]+)\}/)?.[1] ?? "";

Deno.test("commercial H1 typography is markup-independent and descender-safe", () => {
  assertFalse(css.includes(".page-hero--commercial h1:has(em)"));
  assertStringIncludes(commercialRule, "animation-name:page-title-entry-unclipped");
  assertStringIncludes(commercialRule, "line-height:1.08");
  assertStringIncludes(commercialRule, "padding-block:.14em");
  assertFalse(/clip-path/.test(commercialRule));
  assertMatch(
    css,
    /@keyframes page-title-entry-unclipped \{ from \{ opacity:0; transform:[^}]+\} to \{ opacity:1; transform:none; \} \}/,
  );
});

Deno.test("every commercial hero uses the protected stylesheet", async () => {
  for (const page of commercialPages) {
    const html = await Deno.readTextFile(new URL(`../../pages/${page}`, import.meta.url));
    assertStringIncludes(html, "page-hero--commercial");
    assertStringIncludes(html, "../assets/css/pages.css");
  }
});

Deno.test("core commercial routes propagate the corrected CSS version", async () => {
  for (const page of versionedCorePages) {
    const html = await Deno.readTextFile(new URL(`../../pages/${page}`, import.meta.url));
    assertStringIncludes(html, "../assets/css/pages.css?v=20260816-1");
  }
});

Deno.test("pricing H1 remains protected without requiring emphasis markup", async () => {
  const html = await Deno.readTextFile(new URL("../../pages/pricing.html", import.meta.url));
  const heading = html.match(/<section class="page-hero page-hero--commercial"[\s\S]*?<h1>([\s\S]*?)<\/h1>/)?.[1] ?? "";
  assertEquals(heading, "Indicatieve startprijzen per type project.");
  assertFalse(heading.includes("<em>"));
});

Deno.test("homepage services heading keeps its descender allowance", () => {
  assertStringIncludes(
    homepageCss,
    ".motion-enabled .services .section-heading.reveal.is-visible { clip-path: inset(-0.2em -0.08em); }",
  );
});
import { assert, assertEquals, assertMatch } from "jsr:@std/assert";

const pricingUrl = new URL("../../pages/pricing.html", import.meta.url);
const pricingHtml = await Deno.readTextFile(pricingUrl);

function packageCard(packageName: string): string {
  const match = pricingHtml.match(
    new RegExp(
      `<article[^>]*>[^]*?<h3>${packageName}</h3>[^]*?</article>`,
      "i",
    ),
  );
  assert(match, `${packageName} package card must exist`);
  return match[0];
}

Deno.test("C32 public Starter presents catalog v1 package terms", () => {
  const starter = packageCard("Starter");
  assertMatch(starter, /Vanaf EUR 1\.800 excl\. btw/);
  assertMatch(starter, /Maximaal 5 standaardpagina's/);
  assertMatch(starter, /1 correctieronde inbegrepen/);
});

Deno.test("C33 public Professional presents catalog v1 package terms", () => {
  const professional = packageCard("Professional");
  assertMatch(professional, /Vanaf EUR 3\.500 excl\. btw/);
  assertMatch(professional, /Maximaal 10 standaardpagina's/);
  assertMatch(professional, /Blog\/Nieuwsmodule inbegrepen/);
  assertMatch(professional, /2 correctierondes inbegrepen/);
});

Deno.test("C34 public pricing excludes historical Professional v1 claims", () => {
  assertEquals(pricingHtml.includes("Vanaf EUR 3.200"), false);
  assertEquals(pricingHtml.includes("Tot 12 pagina's"), false);
});

Deno.test("C35 package quote calls to action keep valid contact targets", () => {
  const cards = pricingHtml.match(
    /<article class="pricing-option[^]*?<\/article>/g,
  );
  assertEquals(cards?.length, 3);
  for (const card of cards ?? []) {
    assertMatch(card, /<a class="button[^>]*" href="contact\.html">/);
  }
});

Deno.test("C36 pricing page keeps the responsive viewport contract", () => {
  assertMatch(
    pricingHtml,
    /<meta name="viewport" content="width=device-width, initial-scale=1\.0" \/>/,
  );
  assertMatch(pricingHtml, /href="\.\.\/assets\/css\/pages\.css\?v=20260816-1"/);
});

Deno.test("C37 every local pricing-page link resolves", async () => {
  const links = [...pricingHtml.matchAll(/(?:href|src)="([^"]+)"/g)]
    .map((match) => match[1])
    .filter((value) =>
      !value.startsWith("http") &&
      !value.startsWith("#") &&
      !value.startsWith("mailto:")
    );
  for (const link of new Set(links)) {
    const target = new URL(link, pricingUrl);
    const stat = await Deno.stat(target);
    assert(stat.isFile, `${link} must resolve to a file`);
  }
});

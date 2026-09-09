import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, resolve, sep } from "node:path";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

const root = resolve(fileURLToPath(new URL("../", import.meta.url)));
const publicRoutes = [
  "/index.html",
  "/pages/websites-op-maat.html",
  "/pages/webshops.html",
  "/pages/seo.html",
  "/pages/services.html",
  "/pages/contact.html",
  "/pages/hosting-onderhoud.html",
  "/pages/integraties-automatisering.html",
  "/pages/slimme-documentenflow.html",
  "/pages/klanten-ledenomgevingen.html",
  "/pages/portfolio.html",
  "/pages/about.html",
  "/pages/process.html",
  "/pages/faq.html",
  "/pages/multimedia-social.html",
  "/pages/pricing.html",
  "/werken-bij/index.html",
];
const viewports = [
  { name: "desktop-1440", width: 1440, height: 900 },
  { name: "mobile-390", width: 390, height: 844 },
  { name: "mobile-320", width: 320, height: 844 },
];
const contentTypes = new Map([
  [".css", "text/css"],
  [".html", "text/html"],
  [".ico", "image/x-icon"],
  [".jpeg", "image/jpeg"],
  [".jpg", "image/jpeg"],
  [".js", "text/javascript"],
  [".json", "application/json"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".webmanifest", "application/manifest+json"],
  [".webp", "image/webp"],
]);

let browser;
let origin;
let server;

before(async () => {
  server = createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
      let filePath = resolve(root, `.${pathname}`);
      if (filePath !== root && !filePath.startsWith(`${root}${sep}`)) throw new Error("Path outside root");
      if ((await stat(filePath)).isDirectory()) filePath = join(filePath, "index.html");
      response.writeHead(200, { "content-type": contentTypes.get(extname(filePath)) || "application/octet-stream" });
      response.end(await readFile(filePath));
    } catch {
      response.writeHead(404).end("Not found");
    }
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch();
});

after(async () => {
  await browser?.close();
  await new Promise((resolveClose) => server?.close(resolveClose));
});

async function exposeRecruitmentContent(page, route) {
  if (route !== "/werken-bij/index.html") return;
  await page.evaluate(() => {
    document.getElementById("careersPublishedContent").hidden = false;
    document.getElementById("vacancyLoading").hidden = true;
    document.getElementById("vacancyEmpty").hidden = false;
  });
}

test("public route inventory is exactly 17", async () => {
  assert.equal(publicRoutes.length, 17);
  assert.equal(new Set(publicRoutes).size, 17);
  await Promise.all(publicRoutes.map((route) => stat(join(root, route.slice(1)))));
});

for (const viewport of viewports) {
  test(`public visual contract: ${viewport.name}`, async () => {
    const context = await browser.newContext({ viewport });
    const page = await context.newPage();

    for (const route of publicRoutes) {
      await page.goto(`${origin}${route}`, { waitUntil: "load" });
      await exposeRecruitmentContent(page, route);
      await page.evaluate(async () => {
        await document.fonts.ready;
        await new Promise((resolveFrame) => requestAnimationFrame(() => requestAnimationFrame(resolveFrame)));
      });

      const contract = await page.evaluate(() => {
        const heading = document.querySelector("h1");
        const container = heading?.closest(".hero,.page-hero") || heading?.parentElement;
        if (!heading || !container) return { headingFound: false };
        const headingRect = heading.getBoundingClientRect();
        const containerRect = container.getBoundingClientRect();
        const style = getComputedStyle(heading);
        return {
          headingFound: true,
          headingContained: headingRect.left >= containerRect.left - 1
            && headingRect.right <= containerRect.right + 1
            && headingRect.top >= containerRect.top - 1
            && headingRect.bottom <= containerRect.bottom + 1,
          clipPath: style.clipPath,
          overflow: style.overflow,
          fontFamily: style.fontFamily,
          horizontalOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        };
      });

      assert.equal(contract.headingFound, true, `${route} must have an h1`);
      assert.equal(contract.headingContained, true, `${route} h1 must remain inside its hero/container`);
      assert.equal(contract.clipPath, "none", `${route} h1 must not clip glyphs`);
      assert.equal(contract.overflow, "visible", `${route} h1 overflow must remain visible`);
      assert.equal(contract.fontFamily, '"Segoe UI", Arial, sans-serif', `${route} h1 font changed`);
      assert.equal(contract.horizontalOverflow, 0, `${route} has horizontal overflow`);
    }

    await context.close();
  });
}

test("approved typography and descenders remain readable", async () => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();

  await page.goto(`${origin}/pages/process.html`, { waitUntil: "load" });
  const process = await page.evaluate(() => {
    const heading = document.querySelector("h1");
    const glyph = document.querySelector(".process-title-g");
    const headingRect = heading.getBoundingClientRect();
    const glyphRect = glyph.getBoundingClientRect();
    return {
      bodyFont: getComputedStyle(document.body).fontFamily,
      headingFont: getComputedStyle(heading).fontFamily,
      glyphFont: getComputedStyle(glyph).fontFamily,
      glyphContained: glyphRect.top >= headingRect.top - 1 && glyphRect.bottom <= headingRect.bottom + 1,
    };
  });
  assert.equal(process.bodyFont, '"Segoe UI", Arial, sans-serif');
  assert.equal(process.headingFont, '"Segoe UI", Arial, sans-serif');
  assert.equal(process.glyphFont, "Arial, sans-serif");
  assert.equal(process.glyphContained, true, "Aanpak g must remain inside the h1 box");

  await page.goto(`${origin}/pages/contact.html`, { waitUntil: "load" });
  const contact = await page.evaluate(() => {
    const heading = document.querySelector("h1");
    const style = getComputedStyle(heading);
    return {
      text: heading.textContent,
      fontFamily: style.fontFamily,
      lineHeight: Number.parseFloat(style.lineHeight),
      fontSize: Number.parseFloat(style.fontSize),
      paddingBottom: Number.parseFloat(style.paddingBottom),
      clipPath: style.clipPath,
      overflow: style.overflow,
    };
  });
  assert.match(contact.text, /j/);
  assert.equal(contact.fontFamily, '"Segoe UI", Arial, sans-serif');
  assert.ok(contact.lineHeight / contact.fontSize >= 1.05, "Contact h1 line-height must preserve the j descender");
  assert.ok(contact.paddingBottom > 0, "Contact h1 needs glyph-safe bottom padding");
  assert.equal(contact.clipPath, "none");
  assert.equal(contact.overflow, "visible");

  await context.close();
});

for (const width of [390, 320]) {
  test(`mobile process steps settle without horizontal translation: ${width}`, async () => {
    const context = await browser.newContext({ viewport: { width, height: 844 } });
    const page = await context.newPage();
    await page.goto(`${origin}/pages/process.html`, { waitUntil: "load" });
    const transforms = await page.evaluate(async () => {
      const steps = [...document.querySelectorAll(".process-detail-list [data-reveal]")];
      steps.forEach((step) => step.classList.add("is-visible"));
      await new Promise((resolveWait) => setTimeout(resolveWait, 900));
      return steps.map((step) => {
        const transform = getComputedStyle(step).transform;
        if (transform === "none") return 0;
        return new DOMMatrixReadOnly(transform).m41;
      });
    });
    assert.equal(transforms.length, 7);
    assert.ok(transforms.every((translateX) => Math.abs(translateX) <= 0.01), "Process steps retain translateX");
    await context.close();
  });
}

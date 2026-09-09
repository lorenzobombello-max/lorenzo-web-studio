import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readdir, readFile, stat } from "node:fs/promises";
import { extname, join, relative, resolve, sep } from "node:path";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

const root = resolve(fileURLToPath(new URL("../", import.meta.url)));
const demoRoot = join(root, "pages", "demos");
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
const demoRoutes = [
  "/pages/demos/aldara-atelier/index.html",
  "/pages/demos/aurelis-architecture/index.html",
  "/pages/demos/cafe/index.html",
  "/pages/demos/garage/index.html",
  "/pages/demos/industrieel-elektriciteit/index.html",
  "/pages/demos/luna-hair-studio/index.html",
  "/pages/demos/mediterranean-brasserie/index.html",
  "/pages/demos/nova-estate/index.html",
  "/pages/demos/personal-portfolio/index.html",
  "/pages/demos/pulse-performance/index.html",
  "/pages/demos/restaurant/index.html",
  "/pages/demos/vesper-systems/index.html",
];
const routes = [...publicRoutes, ...demoRoutes];
const viewports = [
  { name: "desktop", width: 1440, height: 900 },
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

test("page-end baseline includes every source demo", async () => {
  const sourceDemoRoutes = (await readdir(demoRoot, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => `/pages/demos/${entry.name}/index.html`)
    .sort();
  await Promise.all(sourceDemoRoutes.map((route) => stat(join(root, route.slice(1)))));
  assert.deepEqual(demoRoutes.toSorted(), sourceDemoRoutes);
});

test("page-end baseline includes all 17 public routes", () => {
  assert.equal(publicRoutes.length, 17);
  assert.equal(new Set(publicRoutes).size, 17);
});

for (const motion of ["no-preference", "reduce"]) {
  for (const viewport of viewports) {
    test(`footer is the page end: ${viewport.name}, motion=${motion}`, async () => {
      const context = await browser.newContext({
        reducedMotion: motion,
        viewport: { width: viewport.width, height: viewport.height },
      });
      const page = await context.newPage();

      for (const route of routes) {
        await page.goto(`${origin}${route}`, { waitUntil: "load" });
        await page.evaluate(async () => {
          await document.fonts.ready;
          await new Promise((resolveFrame) => requestAnimationFrame(() => requestAnimationFrame(resolveFrame)));
          scrollTo(0, document.documentElement.scrollHeight);
        });

        const geometry = await page.evaluate(() => {
          const footer = [...document.querySelectorAll("body footer")].at(-1);
          if (!footer) return { footerFound: false };
          const footerBottom = footer.getBoundingClientRect().bottom + scrollY;
          const scrollHeight = document.documentElement.scrollHeight;
          scrollTo(document.documentElement.scrollWidth, scrollY);
          return {
            footerFound: true,
            scrollHeight,
            footerBottom,
            viewportHeight: innerHeight,
            extraAfterFooter: Math.max(0, scrollHeight - footerBottom),
            horizontalScroll: scrollX,
          };
        });

        assert.equal(geometry.footerFound, true, `${route} must have a body footer`);
        assert.ok(
          geometry.extraAfterFooter <= 1,
          `${route} has ${geometry.extraAfterFooter.toFixed(2)}px after its footer ` +
            `(scrollHeight=${geometry.scrollHeight}, footerBottom=${geometry.footerBottom.toFixed(2)}, viewport=${geometry.viewportHeight})`,
        );
        assert.ok(geometry.horizontalScroll <= 1, `${route} scrolls ${geometry.horizontalScroll.toFixed(2)}px horizontally`);
      }

      await context.close();
    });
  }
}
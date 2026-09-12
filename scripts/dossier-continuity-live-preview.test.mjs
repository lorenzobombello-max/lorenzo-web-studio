import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { chromium } from "@playwright/test";

const sentinel = "LWS-AAN-2026-0006";
const states = [
  ["pending", "Pending", "#A1000001", "Nieuwe aanvraag"],
  ["active", "Active", sentinel, "Actief dossier"],
  ["trash", "Trash", "LWS-AAN-2099-0003", "Verwijderd dossier"],
  ["failure", "Laadfout", "Dossiers konden niet veilig worden geladen.", "Probeer opnieuw"],
  ["empty", "Leeg resultaat", "Geen dossiers gevonden.", "Serverantwoord: 200"],
  ["populated", "Gevuld resultaat", sentinel, "1 dossier gevonden"],
];

function previewHtml() {
  const panels = states.map(([key, title, primary, secondary]) => `
    <article class="state state--${key}" data-preview-state="${key}">
      <span class="state__key">${title}</span><strong>${primary}</strong><small>${secondary}</small>
    </article>`).join("");
  return `<!doctype html><html lang="nl"><meta charset="utf-8"><style>
    *{box-sizing:border-box}body{margin:0;background:#f3f1eb;color:#17211d;font-family:Georgia,serif}
    main{max-width:1160px;margin:auto;padding:32px}header{border-bottom:3px solid #17211d;padding-bottom:18px}
    h1{font-size:clamp(28px,5vw,56px);margin:0;letter-spacing:0}p{font-family:Verdana,sans-serif}
    .grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-top:22px}
    .state{min-height:180px;border:1px solid #78827d;border-top:8px solid #147d70;background:#fff;padding:20px;display:flex;flex-direction:column;gap:14px}
    .state--trash{border-top-color:#59615d}.state--failure{border-top-color:#b63a2b;background:#fff4f1}.state--empty{border-top-color:#b59435}
    .state__key{font:700 12px Verdana,sans-serif;text-transform:uppercase}.state strong{font-size:22px;overflow-wrap:anywhere}.state small{font:14px Verdana,sans-serif}
    @media(max-width:720px){main{padding:18px}.grid{grid-template-columns:1fr}.state{min-height:128px}}
  </style><main><header><h1>Dossiercontinuiteit</h1><p>Lokale synthetische releasepreview</p></header><section class="grid">${panels}</section></main></html>`;
}

test("local live preview renders all six continuity states on desktop and mobile", async () => {
  const output = resolve("test-results");
  await mkdir(output, { recursive: true });
  const browser = await chromium.launch();
  try {
    for (const viewport of [{ name: "desktop", width: 1440, height: 900 }, { name: "mobile", width: 390, height: 844 }]) {
      const page = await browser.newPage({ viewport });
      await page.setContent(previewHtml(), { waitUntil: "load" });
      assert.equal(await page.locator("[data-preview-state]").count(), 6);
      for (const [key] of states) assert.equal(await page.locator(`[data-preview-state="${key}"]`).isVisible(), true);
      assert.equal(await page.getByText(sentinel, { exact: true }).count(), 2);
      assert.equal(await page.getByText("Geen dossiers gevonden.", { exact: true }).isVisible(), true);
      assert.equal(await page.getByText("Dossiers konden niet veilig worden geladen.", { exact: true }).isVisible(), true);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
      await page.screenshot({ path: resolve(output, `dossier-continuity-live-preview-${viewport.name}.png`), fullPage: true });
      await page.close();
    }
  } finally {
    await browser.close();
  }
});
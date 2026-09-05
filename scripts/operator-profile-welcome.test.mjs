import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { operatorProfileNameParts } from "../assets/js/operator-profile.mjs";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("profile names enter as opposing given and family name parts", async () => {
  assert.deepEqual(operatorProfileNameParts("Lorenzo Bombello"), { givenName: "Lorenzo", familyName: "Bombello" });
  assert.deepEqual(operatorProfileNameParts("Herlinde Van den Berg"), { givenName: "Herlinde", familyName: "Van den Berg" });
  const [source, css] = await Promise.all([
    read("assets/js/operator-profile.mjs"),
    read("assets/css/operator-dashboard.css"),
  ]);
  assert.match(source, /operator-profile__name-part--\$\{modifier\}/);
  assert.match(css, /operator-profile-name-from-left/);
  assert.match(css, /operator-profile-name-from-right/);
});

test("profile welcome presentation is prominent and cache-versioned", async () => {
  const [html, css] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/css/operator-dashboard.css"),
  ]);
  assert.match(html, /operator-dashboard\.css\?v=20260905-profile-welcome-r2/);
  assert.match(css, /width:min\(100%,96rem\)/);
  assert.match(css, /grid-template-columns:clamp\(13rem,24vw,21rem\)/);
  assert.match(css, /font-size:clamp\(4\.25rem,9vw,8\.5rem\)/);
});

test("magic-link completion opens the profile welcome route", async () => {
  const callback = await read("assets/js/operator-callback.mjs");
  assert.match(callback, /window\.location\.replace\(OPERATOR_ROUTES\.profile\)/);
});
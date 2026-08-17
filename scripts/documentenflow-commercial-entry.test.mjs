import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const contact = fs.readFileSync(new URL("../pages/contact.html", import.meta.url), "utf8");
const contactClient = fs.readFileSync(new URL("../assets/js/pages.js", import.meta.url), "utf8");
const documentenflow = fs.readFileSync(new URL("../pages/slimme-documentenflow.html", import.meta.url), "utf8");
const websitePricing = fs.readFileSync(new URL("../pages/pricing.html", import.meta.url), "utf8");

test("contact offers three distinct request routes", () => {
  assert.match(contact, /option value="quote">Website \/ offerte/);
  assert.match(contact, /option value="slimme_documentenflow">Slimme Documentenflow/);
  assert.match(contact, /option value="privacy">Privacy \/ persoonsgegevens/);
});

test("client maps website and Documentenflow to the durable request_kind contract", () => {
  assert.match(contactClient, /request_kind: isDocumentenflowRequest \? "slimme_documentenflow" : "website"/);
  assert.match(contactClient, /\.\.\.\(!isDocumentenflowRequest \? \{/);
  assert.match(contactClient, /requestedKind === "slimme_documentenflow"/);
});

test("package interest is display-only and excluded from payload", () => {
  assert.match(contactClient, /Interesse in pakket \$\{packageLabel\} \(niet-bindende voorkeur\)/);
  assert.doesNotMatch(contactClient, /package_interest\s*:/);
});

test("Documentenflow packages contain the exact approved prices", () => {
  for (const value of ["€ 2.850", "€ 175", "€ 5.700", "€ 299", "vanaf € 7.500", "vanaf € 449"]) {
    assert.equal(documentenflow.split(value).length - 1, 1, `${value} appears exactly once`);
  }
  assert.equal(documentenflow.split("excl. btw").length - 1, 6);
  assert.equal(documentenflow.split("/ maand").length - 1, 3);
});

test("every package CTA enters the Documentenflow request route", () => {
  for (const packageInterest of ["start", "groei", "maatwerk"]) {
    assert.match(documentenflow, new RegExp(`contact\\.html\\?request-kind=slimme_documentenflow&amp;package-interest=${packageInterest}`));
  }
});

test("website pricing remains authoritative and contains no Documentenflow prices", () => {
  assert.match(websitePricing, /Vanaf EUR 1\.800 excl\. btw/);
  assert.match(websitePricing, /Vanaf EUR 3\.500 excl\. btw/);
  assert.match(websitePricing, /Prijs op aanvraag/);
  assert.doesNotMatch(websitePricing, /2\.850|5\.700|7\.500|175 \/ maand|299 \/ maand|449 \/ maand/);
});
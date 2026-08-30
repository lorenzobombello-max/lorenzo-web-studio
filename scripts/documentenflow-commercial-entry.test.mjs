import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const contact = fs.readFileSync(new URL("../pages/contact.html", import.meta.url), "utf8");
const contactClient = fs.readFileSync(new URL("../assets/js/pages.js", import.meta.url), "utf8");
const submitFunction = fs.readFileSync(new URL("../supabase/functions/submit-quote-request/index.ts", import.meta.url), "utf8");
const documentenflow = fs.readFileSync(new URL("../pages/slimme-documentenflow.html", import.meta.url), "utf8");
const qualificationIntake = fs.readFileSync(new URL("../pages/sdf-qualification-intake.html", import.meta.url), "utf8");
const qualificationReview = fs.readFileSync(new URL("../assets/js/sdf-qualification-review.mjs", import.meta.url), "utf8");
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

test("package interest selects and submits canonical SDF package identity", () => {
  assert.match(contactClient, /Interesse in pakket \$\{packageLabel\} \(niet-bindende voorkeur\)/);
  assert.match(contactClient, /sdfPackage\.value = requestedPackage/);
  assert.match(contactClient, /sdf_package: text\("sdf-package"\)/);
  assert.match(contact, /data-sdf-field hidden/);
  for (const sdfPackage of ["start", "groei", "maatwerk"]) {
    assert.match(contact, new RegExp(`<option value="${sdfPackage}">${sdfPackage.toUpperCase()}<\/option>`));
  }
  assert.match(submitFunction, /sanitized\.request_kind === "slimme_documentenflow" \? \{ sdf_package: sanitized\.sdf_package \} : \{\}/);
  assert.match(submitFunction, /p_sdf_package: sanitized\.sdf_package/);
});

test("Documentenflow packages contain the exact approved prices", () => {
  for (const value of ["€ 2.850", "€ 175", "€ 5.700", "€ 299", "€ 7.500", "€ 449"]) {
    assert.equal(documentenflow.split(value).length - 1, 1, `${value} appears exactly once`);
  }
  assert.equal(documentenflow.split("excl. btw").length - 1, 7);
  assert.equal(documentenflow.split("/ maand").length - 1, 3);
});

test("Documentenflow package cards show exact public capacities without classification logic", () => {
  assert.match(documentenflow, /slimme-documentenflow\.css\?v=20260831-packages/);
  for (const value of [
    "1 documentflow", "2 documenttypes/templates", "500 pagina's/maand", "Tot 3 gebruikersaccounts",
    "3 documentflows", "5 documenttypes/templates", "2.500 pagina's/maand", "Tot 10 gebruikersaccounts",
    "6 documentflows", "10 documenttypes/templates", "7.500 pagina's/maand", "Tot 25 gebruikersaccounts",
    "Boven PRO-grenzen", "Uitzonderlijke complexiteit", "Na beoordeling", "en offerte",
  ]) assert.match(documentenflow, new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(documentenflow, /Niet zeker welk pakket past\?/);
  assert.match(documentenflow, />Advies gewenst </);
  assert.match(documentenflow, /De uiteindelijke scope en prijs worden bevestigd in jouw offerte/);
  assert.doesNotMatch(documentenflow, /budget.?guard|automatisch pakket kiezen|packageclassificatie/i);
});

test("qualification package presentation uses the same user-account copy", () => {
  for (const value of ["Tot 3 gebruikersaccounts", "Tot 10 gebruikersaccounts", "Tot 25 gebruikersaccounts"]) {
    assert.match(qualificationIntake, new RegExp(value));
    assert.match(qualificationReview, new RegExp(value));
  }
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
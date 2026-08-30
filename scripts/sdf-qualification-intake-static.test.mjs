import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("SDF qualification intake preserves its three-step form contract", async () => {
  const html = await read("pages/sdf-qualification-intake.html");

  assert.equal(html.match(/<fieldset[^>]*data-step="\d"[^>]*>/g)?.length, 3);
  assert.match(html, /<legend>Welke documenten gebruikt u\?<\/legend>/);
  assert.match(html, /<legend>Welke werkstappen zijn nodig\?<\/legend>/);
  assert.match(html, /<legend>Beschrijf uw huidige en gewenste flow\.<\/legend>/);

  for (const id of [
    "qualificationForm",
    "documentCategories",
    "workflowCapabilities",
    "currentWorkflow",
    "desiredWorkflow",
    "volumeBand",
    "frequency",
    "relevantDocumentTypes",
    "rolesUsers",
    "sampleAvailable",
    "sampleRequestedByLws",
    "sampleUploadRequiredLater",
    "confirmation",
    "submitButton",
  ]) {
    assert.match(html, new RegExp(`id="${id}"`), `Missing required #${id}`);
  }
});

test("SDF qualification intake preserves capability and API contracts", async () => {
  const script = await read("assets/js/sdf-qualification-intake.js");

  assert.match(script, /new URLSearchParams\(location\.hash\.slice\(1\)\)/);
  assert.match(script, /history\.replaceState\(null,"",location\.pathname\)/);
  assert.doesNotMatch(script, /location\.search/);

  for (const key of [
    "documentPurpose",
    "workflowCapabilities",
    "businessRequirements",
    "sampleDocumentMetadata",
  ]) {
    assert.match(script, new RegExp(`${key}:`), `Missing payload key ${key}`);
  }

  for (const action of ["inspect", "save_draft", "submit"]) {
    assert.match(script, new RegExp(`action:"${action}"`), `Missing API action ${action}`);
  }
});

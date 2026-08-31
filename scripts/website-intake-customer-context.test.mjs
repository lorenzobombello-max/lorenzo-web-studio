import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { websiteIntakeContextPresentation } from "../assets/js/intake-customer-context.js";

test("Website intake context uses only the Website customer projection", () => {
  const context = websiteIntakeContextPresentation({
    request: {
      created_at: "2026-08-31T23:05:00Z",
      name: "Lorenzo Bombello",
      email: "lorenzo_bombello@telenet.be",
      website_type: "Bedrijfswebsite",
    },
    intake: { status: "in_progress" },
  });
  assert.equal(context.name, "Lorenzo Bombello");
  assert.equal(context.email, "lorenzo_bombello@telenet.be");
  assert.equal(context.service, "Website");
  assert.match(context.requestedAt, /1 september 2026/);
  assert.equal(context.reference, "Beschikbaar na indiening");
  assert.equal(context.projectType, "Bedrijfswebsite");
  assert.equal(context.status, "Concept hersteld");
  assert.doesNotMatch(JSON.stringify(context), /[0-9a-f]{8}-[0-9a-f-]{27}/i);
});

test("Website intake context exposes the public application reference after submit", () => {
  const context = websiteIntakeContextPresentation({
    request: { name: "Lorenzo Bombello" },
    intake: { status: "submitted" },
    application: { applicationReference: "LWS-AAN-2026-0042" },
  });
  assert.equal(context.reference, "LWS-AAN-2026-0042");
  assert.equal(context.status, "Verzonden");
});

test("Website intake markup keeps the existing form and navigation intact", async () => {
  const [html, script] = await Promise.all([
    readFile(new URL("../pages/intake.html", import.meta.url), "utf8"),
    readFile(new URL("../assets/js/intake.js", import.meta.url), "utf8"),
  ]);
  for (const id of ["contextGreetingName", "contextName", "contextEmail", "contextService", "contextRequestedAt", "contextReference", "contextType", "contextStatus"]) {
    assert.match(html, new RegExp(`id="${id}"`));
  }
  assert.match(html, /id="intakeForm"/);
  assert.match(script, /saveButton\.addEventListener\("click", saveDraft\)/);
  assert.match(script, /nextButton\.addEventListener\("click"/);
  assert.doesNotMatch(script, /sdf.*authority|support_reference/i);
});
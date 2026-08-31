import assert from "node:assert/strict";
import test from "node:test";
import { buildSdfQualificationCustomer } from "../assets/js/sdf-qualification-customer.mjs";

test("full customer projection becomes a personal dossier without internal metadata", () => {
  const presentation = buildSdfQualificationCustomer({
    customer: { name: "Ada Lovelace", company: "Analytical Engines BV", email: "ada@example.test", phone: "+32 470 00 00 01" },
    request_created_at: "2026-09-01T08:00:00.000Z",
    support_reference: "#E07F8F06",
    intake_id: "68000000-0000-4000-8000-000000000001",
    application_reference: "LWS-INTERNAL-1",
    metadata: { secret: true },
  });
  assert.equal(presentation.greeting, "Beste Ada Lovelace,");
  assert.deepEqual(presentation.rows.map(([field]) => field), ["name", "company", "email", "phone", "service", "request_created_at", "support_reference"]);
  const output = JSON.stringify(presentation);
  for (const expected of ["Ada Lovelace", "Analytical Engines BV", "ada@example.test", "+32 470 00 00 01", "Slimme Documentenflow", "#E07F8F06"]) assert.match(output, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.doesNotMatch(output, /68000000-0000|LWS-INTERNAL|secret/);
});

test("optional customer rows are omitted rather than rendered empty", () => {
  const presentation = buildSdfQualificationCustomer({ customer: { name: "Grace Hopper", company: "", phone: null }, support_reference: "#5C19F9DD" });
  assert.equal(presentation.greeting, "Beste Grace Hopper,");
  assert.deepEqual(presentation.rows.map(([field]) => field), ["name", "service", "support_reference"]);
  assert.doesNotMatch(JSON.stringify(presentation), /Niet opgegeven|Bedrijf|E-mail|Telefoon/);
});
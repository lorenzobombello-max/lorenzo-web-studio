import assert from "node:assert/strict";
import test from "node:test";
import { buildPrivacyRequestNotificationEmail } from "./privacy-email-template.ts";

test("builds a privacy-only notification and escapes submitted content", () => {
  const email = buildPrivacyRequestNotificationEmail({
    requestId: "12345678-1234-4234-8234-123456789abc",
    createdAt: "2026-08-09T12:00:00.000Z",
    name: "Lorenzo <script>",
    email: "privacy@example.com",
    phone: null,
    message: "Verwijder <strong>mijn gegevens</strong>.",
  });

  assert.match(email.subject, /Nieuw privacyverzoek #12345678/);
  assert.match(email.html, /Lorenzo &lt;script&gt;/);
  assert.match(email.html, /Verwijder &lt;strong&gt;mijn gegevens&lt;\/strong&gt;\./);
  assert.match(email.text, /privacy@example\.com/);
  assert.doesNotMatch(`${email.subject}\n${email.html}\n${email.text}`, /offerte|budget|website-type|review|intake/i);
});
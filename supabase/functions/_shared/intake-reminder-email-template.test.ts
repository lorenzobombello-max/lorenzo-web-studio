import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { buildIntakeReminderEmail } from "./email-templates.ts";

const base = {
  clientName: "Klant",
  company: "Voorbeeld BV",
  requestId: "ab123456-2222-4222-8222-222222222222",
  intakeUrl: "https://example.test/pages/intake.html#token=personal-capability",
  expiresAt: "2026-08-30T10:00:00.000Z",
} as const;

Deno.test("invited reminder reuses branded responsive email and invited CTA", () => {
  const result = buildIntakeReminderEmail({
    ...base,
    progressStatus: "invited",
    reminderPhase: "REMINDER_1",
  });

  assertStringIncludes(result.text, "Uw intake staat nog voor u klaar.");
  assertStringIncludes(result.text, "Intake invullen:");
  assertStringIncludes(result.html, 'role="presentation"');
  assertStringIncludes(result.html, 'bgcolor="#0ed8e6"');
  assertStringIncludes(result.html, "https://lorenzowebsolutions.be/assets/images/branding/logo/lorenzo-web-solution-logo-transparent.png");
  assertStringIncludes(result.html, ">Intake invullen</a>");
});

Deno.test("in-progress reminder preserves progress and uses continuation CTA", () => {
  const result = buildIntakeReminderEmail({
    ...base,
    progressStatus: "in_progress",
    reminderPhase: "REMINDER_1",
  });

  assertStringIncludes(result.text, "U bent al begonnen. U kunt verdergaan waar u stopte.");
  assertStringIncludes(result.text, "Uw opgeslagen antwoorden blijven behouden.");
  assertStringIncludes(result.html, ">Intake verder invullen</a>");
  assertFalse(result.text.toLowerCase().includes("opnieuw beginnen"));
});

Deno.test("REMINDER_2 communicates the real Brussels-localized expiry without threat", () => {
  const result = buildIntakeReminderEmail({
    ...base,
    progressStatus: "invited",
    reminderPhase: "REMINDER_2",
  });

  assertEquals(result.subject, "Uw persoonlijke websitebriefing vervalt binnenkort");
  assertStringIncludes(result.text, "Uw persoonlijke intake blijft beschikbaar tot 30 augustus 2026");
  assertStringIncludes(result.text, "12:00");
  assertFalse(/laatste waarschuwing|onmiddellijk|definitief verloren/i.test(result.text));
});

Deno.test("reminder template escapes customer fields and exposes no internal secret fields", () => {
  const result = buildIntakeReminderEmail({
    ...base,
    clientName: "Klant <script>alert(1)</script>",
    company: "Bedrijf & Partners",
    intakeUrl: "https://example.test/intake?a=1&b=2#token=personal-capability",
    progressStatus: "invited",
    reminderPhase: "REMINDER_1",
  });

  assertStringIncludes(result.html, "Klant &lt;script&gt;alert(1)&lt;/script&gt;");
  assertStringIncludes(result.html, "Bedrijf &amp; Partners");
  assertStringIncludes(result.html, "a=1&amp;b=2#token=personal-capability");
  assertFalse(result.html.includes("<script>alert(1)</script>"));
  assertFalse(/encrypted_payload|claim_token|access_token_hash|provider_message_id/i.test(`${result.subject}\n${result.html}\n${result.text}`));
});

import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { buildIntakeReminderEmail } from "./email-templates.ts";

const base = {
  clientName: "Klant",
  company: "Voorbeeld BV",
  requestId: "ab123456-2222-4222-8222-222222222222",
  intakeUrl: "https://example.test/pages/intake.html#token=personal-capability",
  expiresAt: "2026-08-30T10:00:00.000Z",
  requestKind: "website",
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

Deno.test("day 3 and day 7 subjects remain professional for Website and SDF", () => {
  const website = buildIntakeReminderEmail({ ...base, progressStatus: "invited", reminderPhase: "REMINDER_1" });
  const sdf = buildIntakeReminderEmail({
    ...base,
    requestKind: "slimme_documentenflow",
    progressStatus: "invited",
    reminderPhase: "REMINDER_2",
  });
  assertEquals(website.subject, "Uw persoonlijke website-intake staat nog klaar");
  assertEquals(sdf.subject, "Uw SDF-kwalificatie-intake staat nog klaar");
  assertStringIncludes(sdf.html, "Slimme Documentenflow");
});

Deno.test("day 13 warning says the link expires tomorrow and keeps one CTA", () => {
  const result = buildIntakeReminderEmail({ ...base, progressStatus: "invited", reminderPhase: "FINAL_WARNING" });
  assertEquals(result.subject, "Laatste waarschuwing: uw persoonlijke intakelink verloopt morgen");
  assertStringIncludes(result.text, "verloopt morgen");
  assertEquals((result.html.match(/href="https:\/\/example\.test\/pages\/intake\.html#token=personal-capability"/g) || []).length, 1);
});

Deno.test("day 14 expiry has branded layout and no CTA or capability link", () => {
  const result = buildIntakeReminderEmail({
    ...base,
    requestKind: "slimme_documentenflow",
    intakeUrl: null,
    progressStatus: "invited",
    reminderPhase: "EXPIRY",
  });
  assertEquals(result.subject, "Uw SDF-kwalificatie-intake is vervallen");
  assertStringIncludes(result.html, "lorenzo-web-solution-logo-transparent.png");
  assertStringIncludes(result.text, "is vervallen");
  assertFalse(result.html.includes("personal-capability"));
  assertFalse(result.html.includes("<a href=\"null\""));
  assertFalse(result.text.includes("Intake invullen:"));
});

Deno.test("Website and SDF reminders share the golden wrapper, CTA, footer, and link discipline", () => {
  for (const reminderPhase of ["REMINDER_1", "REMINDER_2", "FINAL_WARNING", "EXPIRY"] as const) {
    const intakeUrl = reminderPhase === "EXPIRY" ? null : base.intakeUrl;
    const website = buildIntakeReminderEmail({ ...base, intakeUrl, requestKind: "website", progressStatus: "invited", reminderPhase });
    const sdf = buildIntakeReminderEmail({ ...base, intakeUrl, requestKind: "slimme_documentenflow", progressStatus: "invited", reminderPhase });
    for (const email of [website, sdf]) {
      assertStringIncludes(email.html, 'max-width:600px;background-color:#ffffff;border:1px solid #dfe4ea;border-radius:8px');
      assertStringIncludes(email.html, 'padding:24px 32px 12px;border-top:4px solid #12346b');
      assertStringIncludes(email.html, 'padding:22px 32px;background-color:#eef2f6;border-top:1px solid #dfe4ea');
      assertStringIncludes(email.html, "Beste Klant,");
      assertStringIncludes(email.html, "#AB123456");
      assertEquals((email.html.match(/<img\b/g) || []).length, 1);
      assertEquals((email.html.match(/lorenzowebsolutions\.be/g) || []).length, 3);
    }
    assertEquals((sdf.html.match(/personal-capability/g) || []).length, reminderPhase === "EXPIRY" ? 0 : 1);
    assertEquals((sdf.text.match(/personal-capability/g) || []).length, reminderPhase === "EXPIRY" ? 0 : 1);
    if (reminderPhase !== "EXPIRY") {
      const websiteCtaStyle = website.html.match(/<a href="[^"]+" style="([^"]+)">Intake invullen<\/a>/)?.[1];
      const sdfCtaStyle = sdf.html.match(/<a href="[^"]+" style="([^"]+)">Intake invullen<\/a>/)?.[1];
      assertEquals(sdfCtaStyle, websiteCtaStyle);
    } else {
      assertFalse(sdf.html.includes("bgcolor=\"#0ed8e6\""));
    }
  }
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

import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { buildAdminNotificationEmail } from "./email-templates.ts";

const base = {
  requestId: "22222222-2222-4222-8222-222222222222",
  createdAt: "2026-08-09T10:00:00.000Z",
  name: "Test Contact",
  email: "contact@example.com",
  phone: null,
  websiteType: "Bedrijfswebsite",
  budget: "EUR 1.500 - EUR 3.000",
  timing: "Binnen 2 tot 3 maanden",
  description: "Lokale testaanvraag",
  reviewUrl: "https://example.com/review",
};

Deno.test("admin email includes and escapes business billing details", () => {
  const result = buildAdminNotificationEmail({
    ...base,
    customerType: "business",
    company: "Voorbeeld & Partners",
    enterpriseNumber: "0123456749",
    enterpriseValidationStatus: "format_valid_not_externally_verified",
    vatNumber: "BE0123456749",
    vatValidationStatus: "valid",
    vatValidatedAt: "2026-08-09T11:00:00.000Z",
    billingAddress: "Voorbeeldstraat 10",
    billingPostalCode: "9000",
    billingCity: "Gent",
    billingCountry: "Belgie",
    billingEmail: "billing@example.com",
  });
  assertStringIncludes(result.html, "Voorbeeld &amp; Partners");
  assertStringIncludes(result.html, "0123456749");
  assertStringIncludes(result.text, "BTW-validatiestatus: Geverifieerd");
  assertStringIncludes(result.text, "Ondernemingsnummerstatus: formaat geldig, niet extern geverifieerd");
  assertStringIncludes(result.text, "Facturatie-e-mail: billing@example.com");
  assertStringIncludes(result.html, 'bgcolor="#0b1118"');
  assertStringIncludes(result.html, "display:none!important;visibility:hidden;mso-hide:all;font-size:1px;line-height:1px;max-height:0;max-width:0;overflow:hidden");
  assertStringIncludes(result.html, "https://lorenzowebsolutions.be/assets/images/branding/logo/lorenzo-web-solution-logo-transparent.png");
  assertFalse(result.html.includes("https://lorenzowebsolutions.be/assets/images/hero/lorenzo-web-solution-logo-transparent.png"));
  assertStringIncludes(result.html, 'font-size:14px;word-break:break-word;">Voorbeeld &amp; Partners');
  assertStringIncludes(result.html, 'font-size:14px;word-break:break-word;">Bedrijfsnaam: Voorbeeld &amp; Partners');
});

Deno.test("admin email omits business lines for individual requests", () => {
  const result = buildAdminNotificationEmail({
    ...base,
    customerType: "individual",
    company: null,
    enterpriseNumber: null,
    enterpriseValidationStatus: "not_checked",
    vatNumber: null,
    vatValidationStatus: "not_checked",
    vatValidatedAt: null,
    billingAddress: null,
    billingPostalCode: null,
    billingCity: null,
    billingCountry: null,
    billingEmail: null,
  });
  assertStringIncludes(result.text, "Klanttype: Particulier");
  assertEquals(result.text.includes("Ondernemingsnummer:"), false);
  assertEquals(result.text.includes("Facturatieadres:"), false);
});
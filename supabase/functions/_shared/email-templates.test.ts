import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { buildAdminNotificationEmail, buildQuotationEmail } from "./email-templates.ts";

const base = {
  requestId: "22222222-2222-4222-8222-222222222222",
  createdAt: "2026-08-09T10:00:00.000Z",
  requestKind: "website" as const,
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

Deno.test("admin email identifies Documentenflow without fabricated website fields", () => {
  const result = buildAdminNotificationEmail({
    ...base,
    requestKind: "slimme_documentenflow",
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
    websiteType: null,
    budget: null,
    timing: null,
  });
  assertStringIncludes(result.subject, "Slimme Documentenflow");
  assertStringIncludes(result.text, "Aanvraagtype: Slimme Documentenflow");
  assertStringIncludes(result.text, "Type website: Niet van toepassing");
});

Deno.test("quotation delivery keeps the capability transient and contains no remote assets or trackers", () => {
  const tokenUrl = "https://example.test/pages/quotation-acceptance.html#token=secret-token";
  const result = buildQuotationEmail("QUOTATION_DELIVERY_NL_BE_v1", {
    clientName: "Klant <Test>", quotationNumber: "LWS-OFF-2026-0001", quotationVersion: 1,
    projectTitle: "Website & shop", validUntil: "31 augustus 2026", acceptanceUrl: tokenUrl,
  });
  assertStringIncludes(result.html, "Klant &lt;Test&gt;");
  assertStringIncludes(result.text, tokenUrl);
  assertFalse(result.html.includes("<img"));
  assertFalse(result.html.includes("https://lorenzowebsolutions.be"));
  assertFalse(/tracking|pixel|open[-_ ]?track/i.test(result.html));
  assertFalse(/factuur|betaling|betaald/i.test(`${result.subject} ${result.html} ${result.text}`));
});

Deno.test("acceptance confirmations record acceptance without invoice side effects", () => {
  for (const template of ["ACCEPTANCE_CONFIRMATION_CUSTOMER_NL_BE_v1", "ACCEPTANCE_CONFIRMATION_INTERNAL_NL_BE_v1"] as const) {
    const result = buildQuotationEmail(template, {
      clientName: "Klant", quotationNumber: "LWS-OFF-2026-0001", quotationVersion: 1,
      projectTitle: "Website", acceptedAt: "2026-08-15T10:00:00Z", acceptingName: "Bevoegde Persoon",
    });
    assertStringIncludes(result.text, "Aanvaarding geregistreerd");
    assertStringIncludes(result.text, "geen factuur of betalingsbewijs");
    assertFalse(/betaald|betaling ontvangen|factuur aangemaakt/i.test(`${result.subject} ${result.html} ${result.text}`));
  }
});
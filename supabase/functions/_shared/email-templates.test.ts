import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { buildAdminNotificationEmail, buildQuotationEmail, buildSubmittedIntakeAdminEmail } from "./email-templates.ts";
import { buildApplicationOutput } from "./application-output.ts";

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

Deno.test("submitted intake email uses application reference and authoritative complete output", () => {
  const output = buildApplicationOutput({
    applicationReference: "LWS-AAN-2026-0042",
    submittedAt: "2026-08-19T18:00:00Z",
    request: { name: "Klant <script>alert(1)</script>", company: "Bedrijf & Co", email: "klant@example.test", phone: "+32 9 000 00 00", website_type: "business", timing: "december" },
    evidence: {
      website_goals: ["generate_leads"], primary_conversion_goal: "quote_requests", existing_website_url: "https://example.test",
      domain_name: "example.test", hosting_status: "has_hosting", requested_pages: ["home", "services"], requested_features: [
        "contact_form", "online_payment", "online_payment_products", "online_payment_reservations",
        "online_payment_appointments", "online_payment_services", "online_payment_registrations",
        "online_payment_deposit", "online_payment_other",
      ],
      shop_required: true, shop_details: { approx_product_count: "20" }, booking_required: true, booking_details: { type: "consultations" },
      primary_language: "nl", additional_languages: ["fr"], integrations: ["crm"], seo_priority: "high", seo_details: { scope: "launch" },
      brand_status: "none", logo_status: "needed", design_styles: ["modern"], content_status: "partial", image_status: "needed",
      image_support: ["ai_images"], content_media_details: { copywriting_scope: "light" }, maintenance_interest: "yes",
      hosting_support: "advice", hosting_maintenance_details: { maintenance_plan: "care_plus" }, deadline_date: "2026-12-01",
      deadline_reason: "Launch <img src=x onerror=alert(2)>", additional_notes: "Volledige notitie",
    },
    authoritativeSnapshot: {
      calculation: { knownMinimumMinor: 350000, currency: "EUR", vatBasis: "exclusive" },
      packageDefinition: { id: "professional_v2" },
      budgetEvaluation: { status: "known_minimum_above_budget", originalLabel: "Minder dan EUR 1.800" },
      recurringServices: [{ productId: "care_plus", amountMinor: 9900, unit: "month" }],
    },
  });
  const result = buildSubmittedIntakeAdminEmail({ output, adminUrl: "https://example.test/admin#token=secure" });
  assertEquals(result.subject, "Nieuwe aanvraag LWS-AAN-2026-0042 — Bedrijf & Co");
  for (const expected of ["Identiteit", "Commercieel", "Project", "Website", "Branding &amp; content", "Service &amp; planning", "Professional", "€ 3.500,00 excl. btw", "LWS Care+: € 99,00 per maand excl. btw", "Beveiligde briefing bekijken"]) {
    assertStringIncludes(result.html, expected);
  }
  assertStringIncludes(result.text, "Aanvraagnummer: LWS-AAN-2026-0042");
  for (const expected of [
    "Contactformulier", "Online betaling", "Producten", "Reservaties", "Afspraken", "Diensten",
    "Inschrijvingen / activiteiten", "Voorschot / reservatiebedrag", "Andere online betaling",
  ]) {
    assertStringIncludes(result.text, expected);
    assertStringIncludes(result.html, expected);
  }
  assertFalse(/online_payment(?:_[a-z_]+)?/.test(`${result.text}\n${result.html}`));
  assertStringIncludes(result.text, "Webshopdetails: approx product count: 20");
  assertStringIncludes(result.html, "Klant &lt;script&gt;alert(1)&lt;/script&gt;");
  assertStringIncludes(result.html, "Launch &lt;img src=x onerror=alert(2)&gt;");
  assertFalse(result.html.includes("22222222-2222"));
  assertFalse(/hmac|pricingConfigHash|admin_access_token/i.test(result.html));
});
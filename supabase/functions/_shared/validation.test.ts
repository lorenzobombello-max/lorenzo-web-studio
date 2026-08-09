import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { InputValidationError, sanitizeAndValidateSubmitPayload } from "./validation.ts";

const basePayload = {
  name: "Lorenzo Bombello",
  email: "hello@example.com",
  phone: "",
  website_type: "Bedrijfswebsite",
  budget: "EUR 1.500 - EUR 3.000",
  timing: "Binnen 2 tot 3 maanden",
  description: "Een veilige testaanvraag voor een nieuwe website.",
  privacy_consent: true,
  website: "",
};

Deno.test("individual quote strips no hidden business values", () => {
  const result = sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "individual" });
  assertEquals(result.customer_type, "individual");
  assertEquals(result.company, null);
  assertEquals(result.vat_number, null);
  assertEquals(result.billing_email, null);
});

Deno.test("business quote keeps required billing data and optional VAT", () => {
  const result = sanitizeAndValidateSubmitPayload({
    ...basePayload,
    customer_type: "business",
    company: "Voorbeeld BV",
    enterprise_number: "0123.456.749",
    vat_number: "",
    billing_address: "Voorbeeldstraat 10",
    billing_postal_code: "9000",
    billing_city: "Gent",
    billing_country: "Belgie",
    billing_email: "billing@example.com",
  });
  assertEquals(result.enterprise_number, "0123456749");
  assertEquals(result.enterprise_validation_status, "format_valid_not_externally_verified");
  assertEquals(result.vat_number, null);
  assertEquals(result.billing_email, "billing@example.com");
});

Deno.test("legacy quote payload remains compatible", () => {
  const result = sanitizeAndValidateSubmitPayload({ ...basePayload, company: "Legacy BV" });
  assertEquals(result.customer_type, null);
  assertEquals(result.company, "Legacy BV");
});

Deno.test("rejects invalid customer type", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "other" }),
    InputValidationError,
    "INVALID_OPTION",
  );
});

Deno.test("rejects missing required business data", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "business", company: "Voorbeeld BV" }),
    InputValidationError,
    "REQUIRED_FIELD",
  );
});

Deno.test("rejects invalid billing email", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({
      ...basePayload,
      customer_type: "business",
      company: "Voorbeeld BV",
      enterprise_number: "0123.456.749",
      billing_address: "Voorbeeldstraat 10",
      billing_postal_code: "9000",
      billing_city: "Gent",
      billing_country: "Belgie",
      billing_email: "geen-email",
    }),
    InputValidationError,
    "INVALID_FORMAT",
  );
});

Deno.test("rejects script markup and overlong business values", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "business", company: "<script>alert(1)</script>" }),
    InputValidationError,
    "INVALID_FORMAT",
  );
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, company: "x".repeat(141) }),
    InputValidationError,
    "INVALID_LENGTH",
  );
});

Deno.test("rejects non-string identifiers and new fields without customer type", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, customer_type: "business", enterprise_number: 123 } as never),
    InputValidationError,
    "INVALID_TYPE",
  );
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...basePayload, billing_city: "Gent" }),
    InputValidationError,
    "INVALID_CONDITION",
  );
});

Deno.test("normalizes EU VAT and rejects malformed VAT before external validation", () => {
  const result = sanitizeAndValidateSubmitPayload({
    ...basePayload,
    customer_type: "business",
    company: "Voorbeeld BV",
    enterprise_number: "0123.456.749",
    vat_number: "be 0123.456.749",
    billing_address: "Voorbeeldstraat 10",
    billing_postal_code: "9000",
    billing_city: "Gent",
    billing_country: "Belgie",
  });
  assertEquals(result.vat_number, "BE0123456749");
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({ ...result, vat_number: "geen btw nummer", privacy_consent: true }),
    InputValidationError,
    "INVALID_FORMAT",
  );
});

Deno.test("rejects a Belgian enterprise number with an invalid check digit", () => {
  assertThrows(
    () => sanitizeAndValidateSubmitPayload({
      ...basePayload,
      customer_type: "business",
      company: "Voorbeeld BV",
      enterprise_number: "0123.456.789",
      billing_address: "Voorbeeldstraat 10",
      billing_postal_code: "9000",
      billing_city: "Gent",
      billing_country: "Belgie",
    }),
    InputValidationError,
    "INVALID_FORMAT",
  );
});
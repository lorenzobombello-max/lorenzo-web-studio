import assert from "node:assert/strict";
import test from "node:test";
import {
  PrivacyRequestValidationError,
  sanitizeAndValidatePrivacyRequest,
} from "./privacy-validation.ts";

test("accepts name, email and message", () => {
  assert.deepEqual(sanitizeAndValidatePrivacyRequest({
    name: "Ada Lovelace",
    email: "ADA@example.com",
    phone: "",
    message: "Ik wil graag inzage in mijn persoonsgegevens.",
    website: "",
  }), {
    name: "Ada Lovelace",
    email: "ada@example.com",
    phone: null,
    message: "Ik wil graag inzage in mijn persoonsgegevens.",
  });
});

test("accepts name, phone and message without email", () => {
  const result = sanitizeAndValidatePrivacyRequest({
    name: "Jan Peeters",
    email: "",
    phone: "+32 470 12 34 56",
    message: "Gelieve mijn persoonsgegevens te corrigeren.",
    website: "",
  });

  assert.equal(result.email, null);
  assert.equal(result.phone, "+32 470 12 34 56");
});

test("rejects a request without contact details", () => {
  assert.throws(
    () => sanitizeAndValidatePrivacyRequest({ name: "Jan Peeters", message: "Een geldig privacyverzoek." }),
    (error) => error instanceof PrivacyRequestValidationError && error.code === "CONTACT_REQUIRED",
  );
});

test("rejects an empty message", () => {
  assert.throws(
    () => sanitizeAndValidatePrivacyRequest({ name: "Jan Peeters", email: "jan@example.com", message: "" }),
    (error) => error instanceof PrivacyRequestValidationError && error.field === "message",
  );
});

test("rejects a filled honeypot", () => {
  assert.throws(
    () => sanitizeAndValidatePrivacyRequest({
      name: "Jan Peeters",
      email: "jan@example.com",
      message: "Een geldig privacyverzoek.",
      website: "https://spam.example",
    }),
    (error) => error instanceof PrivacyRequestValidationError && error.code === "HONEYPOT_TRIGGERED",
  );
});

test("rejects quote-specific fields", () => {
  assert.throws(
    () => sanitizeAndValidatePrivacyRequest({
      name: "Jan Peeters",
      email: "jan@example.com",
      message: "Een geldig privacyverzoek.",
      budget: "EUR 1.500 - EUR 3.000",
    }),
    (error) => error instanceof PrivacyRequestValidationError && error.code === "UNEXPECTED_FIELD",
  );
});
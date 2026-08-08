import type { ReviewAction, SanitizedQuotePayload, SubmitQuotePayload } from "./types.ts";

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_CHARACTERS_REGEX = /^[+0-9().\s-]+$/;
const WEBSITE_TYPES = new Set([
  "Bedrijfswebsite",
  "Portfolio-website",
  "Website voor lokale onderneming",
  "Demo of showcase concept",
  "Automotive website",
  "Technische dienstensite",
  "Personal portfolio",
  "Technische profielsite",
  "Consultancy website",
  "Restaurantwebsite",
  "Horeca website",
  "Andere",
]);
const BUDGETS = new Set([
  "Tot EUR 1.500",
  "EUR 1.500 - EUR 3.000",
  "EUR 3.000 - EUR 6.000",
  "Meer dan EUR 6.000",
]);
const TIMINGS = new Set([
  "Binnen 1 maand",
  "Binnen 2 tot 3 maanden",
  "Flexibel / nog te bepalen",
]);

export class InputValidationError extends Error {
  readonly code: string;
  readonly field?: string;

  constructor(code: string, field?: string) {
    super(code);
    this.name = "InputValidationError";
    this.code = code;
    this.field = field;
  }
}

function normalizeText(value: unknown): string {
  if (typeof value !== "string") return "";
  return value
    .normalize("NFKC")
    .replace(/\r\n?/g, "\n")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .trim();
}

function assertLength(field: string, value: string, min: number, max: number): void {
  if (value.length < min || value.length > max) {
    throw new InputValidationError("INVALID_LENGTH", field);
  }
}

function assertAllowed(field: string, value: string, allowed: Set<string>): void {
  if (!allowed.has(value)) throw new InputValidationError("INVALID_OPTION", field);
}

export function sanitizeAndValidateSubmitPayload(payload: unknown): SanitizedQuotePayload {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new InputValidationError("INVALID_PAYLOAD");
  }

  const input = payload as Partial<SubmitQuotePayload>;
  if (typeof input.email === "string" && /[\r\n]/.test(input.email)) {
    throw new InputValidationError("INVALID_FORMAT", "email");
  }

  const name = normalizeText(input.name);
  const company = normalizeText(input.company ?? "");
  const email = normalizeText(input.email).toLowerCase();
  const phone = normalizeText(input.phone ?? "");
  const websiteType = normalizeText(input.website_type);
  const budget = normalizeText(input.budget);
  const timing = normalizeText(input.timing);
  const description = normalizeText(input.description);
  const honeypotValue = normalizeText(input.website ?? "");

  assertLength("name", name, 2, 120);
  if ((name.match(/[\p{L}\p{N}]/gu) || []).length < 2) {
    throw new InputValidationError("INVALID_FORMAT", "name");
  }
  if (company) assertLength("company", company, 2, 140);
  assertLength("email", email, 5, 254);
  if (phone) {
    assertLength("phone", phone, 6, 40);
    const digitCount = (phone.match(/\d/g) || []).length;
    if (!PHONE_CHARACTERS_REGEX.test(phone) || digitCount < 6 || digitCount > 15) {
      throw new InputValidationError("INVALID_FORMAT", "phone");
    }
  }
  assertLength("website_type", websiteType, 2, 80);
  assertLength("budget", budget, 2, 80);
  assertLength("timing", timing, 2, 80);
  assertLength("description", description, 10, 3000);
  assertAllowed("website_type", websiteType, WEBSITE_TYPES);
  assertAllowed("budget", budget, BUDGETS);
  assertAllowed("timing", timing, TIMINGS);

  if (!EMAIL_REGEX.test(email)) {
    throw new InputValidationError("INVALID_FORMAT", "email");
  }

  if (input.privacy_consent !== true) {
    throw new InputValidationError("PRIVACY_CONSENT_REQUIRED", "privacy_consent");
  }

  return {
    name,
    company: company || null,
    email,
    phone: phone || null,
    website_type: websiteType,
    budget,
    timing,
    description,
    privacy_consent: true,
    honeypotValue,
  };
}

export function validateAction(action: unknown): ReviewAction {
  if (action === "approved" || action === "rejected" || action === "retry_confirmation") return action;
  throw new InputValidationError("INVALID_REVIEW_ACTION", "action");
}

export function validateToken(token: unknown): string {
  if (typeof token !== "string") throw new InputValidationError("INVALID_TOKEN", "token");
  const trimmed = token.trim();
  if (trimmed.length !== 43) throw new InputValidationError("INVALID_TOKEN", "token");
  if (!/^[A-Za-z0-9_-]+$/.test(trimmed)) throw new InputValidationError("INVALID_TOKEN", "token");
  return trimmed;
}

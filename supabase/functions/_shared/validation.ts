import { SanitizedQuotePayload, SubmitQuotePayload } from "./types.ts";

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function normalizeText(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replace(/[\u0000-\u001F\u007F]/g, "").trim();
}

function assertLength(label: string, value: string, min: number, max: number): void {
  if (value.length < min || value.length > max) {
    throw new Error(`${label} has invalid length`);
  }
}

export function sanitizeAndValidateSubmitPayload(payload: SubmitQuotePayload): SanitizedQuotePayload {
  const name = normalizeText(payload.name);
  const company = normalizeText(payload.company ?? "");
  const email = normalizeText(payload.email).toLowerCase();
  const phone = normalizeText(payload.phone ?? "");
  const websiteType = normalizeText(payload.website_type);
  const budget = normalizeText(payload.budget);
  const timing = normalizeText(payload.timing);
  const description = normalizeText(payload.description);
  const honeypotValue = normalizeText(payload.website ?? "");

  assertLength("name", name, 2, 120);
  if (company) assertLength("company", company, 2, 140);
  assertLength("email", email, 5, 254);
  if (phone) assertLength("phone", phone, 6, 40);
  assertLength("website_type", websiteType, 2, 80);
  assertLength("budget", budget, 2, 80);
  assertLength("timing", timing, 2, 80);
  assertLength("description", description, 10, 3000);

  if (!EMAIL_REGEX.test(email)) {
    throw new Error("email has invalid format");
  }

  if (payload.privacy_consent !== true) {
    throw new Error("privacy consent is required");
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

export function validateAction(action: unknown): "approved" | "rejected" {
  if (action === "approved" || action === "rejected") return action;
  throw new Error("invalid action");
}

export function validateToken(token: unknown): string {
  if (typeof token !== "string") throw new Error("invalid token");
  const trimmed = token.trim();
  if (trimmed.length < 20 || trimmed.length > 200) throw new Error("invalid token");
  if (!/^[A-Za-z0-9_-]+$/.test(trimmed)) throw new Error("invalid token");
  return trimmed;
}

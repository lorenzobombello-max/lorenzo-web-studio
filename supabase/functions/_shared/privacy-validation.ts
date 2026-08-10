const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_CHARACTERS_REGEX = /^[+0-9().\s-]+$/;
const ALLOWED_FIELDS = new Set(["name", "email", "phone", "message", "website"]);

export class PrivacyRequestValidationError extends Error {
  readonly code: string;
  readonly field?: string;

  constructor(code: string, field?: string) {
    super(code);
    this.name = "PrivacyRequestValidationError";
    this.code = code;
    this.field = field;
  }
}

export interface SanitizedPrivacyRequest {
  name: string;
  email: string | null;
  phone: string | null;
  message: string;
}

function normalizeText(value: unknown): string {
  if (typeof value !== "string") return "";
  return value
    .normalize("NFKC")
    .replace(/\r\n?/g, "\n")
    .split("")
    .filter((character) => {
      const codeUnit = character.charCodeAt(0);
      return !(
        codeUnit <= 0x08 ||
        codeUnit === 0x0b ||
        codeUnit === 0x0c ||
        (codeUnit >= 0x0e && codeUnit <= 0x1f) ||
        codeUnit === 0x7f
      );
    })
    .join("")
    .trim();
}

function assertLength(field: string, value: string, min: number, max: number): void {
  if (value.length < min || value.length > max) {
    throw new PrivacyRequestValidationError("INVALID_LENGTH", field);
  }
}

export function sanitizeAndValidatePrivacyRequest(payload: unknown): SanitizedPrivacyRequest {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new PrivacyRequestValidationError("INVALID_PAYLOAD");
  }

  const input = payload as Record<string, unknown>;
  if (Object.keys(input).some((key) => !ALLOWED_FIELDS.has(key))) {
    throw new PrivacyRequestValidationError("UNEXPECTED_FIELD");
  }

  if (typeof input.email === "string" && /[\r\n]/.test(input.email)) {
    throw new PrivacyRequestValidationError("INVALID_FORMAT", "email");
  }

  const name = normalizeText(input.name);
  const email = normalizeText(input.email).toLowerCase();
  const phone = normalizeText(input.phone);
  const message = normalizeText(input.message);
  const honeypot = normalizeText(input.website);

  if (honeypot) throw new PrivacyRequestValidationError("HONEYPOT_TRIGGERED", "website");

  assertLength("name", name, 2, 120);
  if ((name.match(/[\p{L}\p{N}]/gu) || []).length < 2) {
    throw new PrivacyRequestValidationError("INVALID_FORMAT", "name");
  }

  if (!email && !phone) {
    throw new PrivacyRequestValidationError("CONTACT_REQUIRED", "email_or_phone");
  }

  if (email) {
    assertLength("email", email, 5, 254);
    if (!EMAIL_REGEX.test(email)) throw new PrivacyRequestValidationError("INVALID_FORMAT", "email");
  }

  if (phone) {
    assertLength("phone", phone, 6, 40);
    const digitCount = (phone.match(/\d/g) || []).length;
    if (!PHONE_CHARACTERS_REGEX.test(phone) || digitCount < 6 || digitCount > 15) {
      throw new PrivacyRequestValidationError("INVALID_FORMAT", "phone");
    }
  }

  assertLength("message", message, 10, 3000);

  return {
    name,
    email: email || null,
    phone: phone || null,
    message,
  };
}
export interface ResendTransportInput {
  apiKey: string;
  from: string;
  to: string;
  subject: string;
  html: string;
  text: string;
  idempotencyKey: string;
  timeoutMs?: number;
}

export type ResendTransportErrorCode =
  | "EMAIL_CONFIGURATION_INVALID"
  | "EMAIL_INPUT_INVALID"
  | "EMAIL_HEADER_INVALID"
  | "RESEND_HTTP_RETRYABLE"
  | "RESEND_HTTP_PERMANENT"
  | "RESEND_TIMEOUT"
  | "RESEND_NETWORK_ERROR"
  | "PROVIDER_RESPONSE_INVALID";

export type ResendTransportResult =
  | { ok: true; providerMessageId: string }
  | { ok: false; retryable: boolean; code: ResendTransportErrorCode };

const RESEND_API_URL = "https://api.resend.com/emails";
const RETRYABLE_HTTP_STATUSES = new Set([408, 425, 429]);
const MAILBOX_PATTERN = /^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/;
const DISPLAY_MAILBOX_PATTERN = /^.+\s<([^\s<>@]+@[^\s<>@]+\.[^\s<>@]+)>$/;

function failure(
  code: ResendTransportErrorCode,
  retryable = false,
): ResendTransportResult {
  return { ok: false, retryable, code };
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function containsLineBreak(value: unknown): boolean {
  return typeof value === "string" && /[\r\n]/.test(value);
}

function isMailbox(value: string): boolean {
  const trimmed = value.trim();
  const displayMatch = trimmed.match(DISPLAY_MAILBOX_PATTERN);
  return MAILBOX_PATTERN.test(displayMatch?.[1] ?? trimmed);
}

function validateInput(
  input: ResendTransportInput,
): ResendTransportResult | null {
  if (
    [input.apiKey, input.from, input.to, input.subject, input.idempotencyKey]
      .some(containsLineBreak)
  ) {
    return failure("EMAIL_HEADER_INVALID");
  }
  if (!isNonEmptyString(input.apiKey)) {
    return failure("EMAIL_CONFIGURATION_INVALID");
  }
  if (
    !isNonEmptyString(input.from) ||
    !isNonEmptyString(input.to) ||
    !isNonEmptyString(input.subject) ||
    !isNonEmptyString(input.html) ||
    !isNonEmptyString(input.text) ||
    !isNonEmptyString(input.idempotencyKey) ||
    !isMailbox(input.from) ||
    !isMailbox(input.to)
  ) {
    return failure("EMAIL_INPUT_INVALID");
  }
  return null;
}

export async function sendEmailViaResend(
  input: ResendTransportInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ResendTransportResult> {
  const invalid = validateInput(input);
  if (invalid) return invalid;

  const controller = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, input.timeoutMs ?? 10_000);

  try {
    const response = await fetchImpl(RESEND_API_URL, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${input.apiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": input.idempotencyKey,
      },
      body: JSON.stringify({
        from: input.from,
        to: [input.to],
        subject: input.subject,
        html: input.html,
        text: input.text,
      }),
    });

    if (!response.ok) {
      const retryable = RETRYABLE_HTTP_STATUSES.has(response.status) ||
        response.status >= 500;
      return failure(
        retryable ? "RESEND_HTTP_RETRYABLE" : "RESEND_HTTP_PERMANENT",
        retryable,
      );
    }

    try {
      const body: unknown = await response.json();
      const providerMessageId =
        typeof body === "object" && body !== null && "id" in body
          ? (body as { id?: unknown }).id
          : null;
      if (isNonEmptyString(providerMessageId)) {
        return { ok: true, providerMessageId };
      }
    } catch {
      // Invalid success payloads share one safe technical classification.
    }
    return failure("PROVIDER_RESPONSE_INVALID", true);
  } catch {
    return failure(timedOut ? "RESEND_TIMEOUT" : "RESEND_NETWORK_ERROR", true);
  } finally {
    clearTimeout(timeout);
  }
}

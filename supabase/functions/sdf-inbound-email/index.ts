import { createClient } from "npm:@supabase/supabase-js@2";
import { Resend } from "npm:resend@6.25.0";
import {
  getSupabaseServerSecretKey,
  SUPABASE_KEY_BINDING_ERROR,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";

interface ResendReceivedEvent {
  type: "email.received";
  created_at: string;
  data: {
    email_id: string;
    message_id?: string | null;
    from: string;
    to: string[];
    created_at: string;
  };
}

export interface ReceiptRegistration {
  providerEmailId: string;
  webhookDeliveryId: string;
  rfcMessageId: string | null;
  senderEmail: string;
  matchedRecipient: string;
  receivedAt: string;
  canonicalFingerprint: string;
}

interface RegistrationResult {
  receipt_id: string;
  replayed: boolean;
}

interface RegistrationClient {
  rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message?: string } | null }>;
}

type RegistrationClientFactory = (
  url: string,
  key: string,
  options: Readonly<{
    auth: Readonly<{ persistSession: false; autoRefreshToken: false }>;
  }>,
) => RegistrationClient;

interface HandlerDependencies {
  verify(
    payload: string,
    headers: { id: string; timestamp: string; signature: string },
    secret: string,
  ): Promise<unknown> | unknown;
  register(input: ReceiptRegistration): Promise<RegistrationResult>;
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PROVIDER_ID_PATTERN = /^[A-Za-z0-9_-]{1,200}$/;
const resend = new Resend("re_webhook_verification_only");

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function normalizeEmail(value: unknown): string | null {
  if (typeof value !== "string" || /[\r\n]/.test(value)) return null;
  const normalized = value.trim().toLowerCase();
  return normalized.length <= 254 && EMAIL_PATTERN.test(normalized)
    ? normalized
    : null;
}

function normalizeProviderId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return PROVIDER_ID_PATTERN.test(normalized) ? normalized : null;
}

function normalizeRfcMessageId(value: unknown): string | null | undefined {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || /[\r\n]/.test(value)) return undefined;
  const normalized = value.trim();
  return normalized.length >= 3 && normalized.length <= 998
    ? normalized
    : undefined;
}

function normalizeReceivedAt(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : null;
}

function parseReceivedEvent(value: unknown): ResendReceivedEvent | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const event = value as Record<string, unknown>;
  if (
    event.type !== "email.received" || !event.data ||
    typeof event.data !== "object" || Array.isArray(event.data)
  ) return null;
  return event as unknown as ResendReceivedEvent;
}

async function sha256(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function createReceiptRegistration(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
  clientFactory: RegistrationClientFactory = (url, key, options) =>
    createClient(url, key, options),
): HandlerDependencies["register"] {
  return async (input) => {
    const supabaseUrl = environment.get("SUPABASE_URL");
    if (!supabaseUrl) throw new Error("SERVER_CONFIGURATION_ERROR");
    const serverSecretKey = getSupabaseServerSecretKey("default", environment);
    const client = clientFactory(supabaseUrl, serverSecretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await client.rpc(
      "register_resend_sdf_inbound_receipt_v1",
      {
        p_provider_email_id: input.providerEmailId,
        p_webhook_delivery_id: input.webhookDeliveryId,
        p_rfc_message_id: input.rfcMessageId,
        p_sender_email: input.senderEmail,
        p_matched_recipient: input.matchedRecipient,
        p_received_at: input.receivedAt,
        p_canonical_fingerprint: input.canonicalFingerprint,
      },
    );
    if (error) {
      if (error.message?.includes("INBOUND_RECEIPT_CONFLICT")) {
        throw new Error("INBOUND_RECEIPT_CONFLICT");
      }
      throw new Error("INBOUND_RECEIPT_PERSIST_FAILED");
    }
    const result = Array.isArray(data) ? data[0] : data;
    if (
      !result || typeof result.receipt_id !== "string" ||
      typeof result.replayed !== "boolean"
    ) {
      throw new Error("INBOUND_RECEIPT_PERSIST_FAILED");
    }
    return result as RegistrationResult;
  };
}

function defaultDependencies(): HandlerDependencies {
  return {
    async verify(payload, headers, secret) {
      return await resend.webhooks.verify({
        payload,
        headers,
        webhookSecret: secret,
      });
    },
    register: createReceiptRegistration(),
  };
}

export async function handleRequest(
  request: Request,
  overrides: Partial<HandlerDependencies> = {},
): Promise<Response> {
  if (request.method !== "POST") {
    return json(405, { ok: false, code: "METHOD_NOT_ALLOWED" });
  }

  const rawBody = await request.text();
  const deliveryId = request.headers.get("svix-id");
  const timestamp = request.headers.get("svix-timestamp");
  const signature = request.headers.get("svix-signature");
  const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET") || "";
  const configuredRecipient = normalizeEmail(
    Deno.env.get("SDF_INBOUND_RECIPIENT"),
  );
  if (!deliveryId || !timestamp || !signature) {
    return json(401, { ok: false, code: "WEBHOOK_SIGNATURE_REQUIRED" });
  }
  if (!webhookSecret || !configuredRecipient) {
    return json(500, { ok: false, code: "SERVER_CONFIGURATION_ERROR" });
  }

  const dependencies = { ...defaultDependencies(), ...overrides };
  let verified: unknown;
  try {
    verified = await dependencies.verify(
      rawBody,
      { id: deliveryId, timestamp, signature },
      webhookSecret,
    );
  } catch {
    return json(401, { ok: false, code: "INVALID_WEBHOOK_SIGNATURE" });
  }

  if (!verified || typeof verified !== "object" || Array.isArray(verified)) {
    return json(400, { ok: false, code: "INVALID_WEBHOOK_PAYLOAD" });
  }
  if ((verified as Record<string, unknown>).type !== "email.received") {
    return json(202, { ok: true, state: "ignored" });
  }
  const event = parseReceivedEvent(verified);
  if (!event) {
    return json(400, { ok: false, code: "INVALID_WEBHOOK_PAYLOAD" });
  }

  const providerEmailId = normalizeProviderId(event.data.email_id);
  const webhookDeliveryId = normalizeProviderId(deliveryId);
  const senderEmail = normalizeEmail(event.data.from);
  const receivedAt = normalizeReceivedAt(event.data.created_at);
  const rfcMessageId = normalizeRfcMessageId(event.data.message_id);
  if (
    !providerEmailId || !webhookDeliveryId || !senderEmail || !receivedAt ||
    rfcMessageId === undefined || !Array.isArray(event.data.to)
  ) {
    return json(400, { ok: false, code: "INVALID_WEBHOOK_PAYLOAD" });
  }
  const recipients = event.data.to.map(normalizeEmail);
  if (recipients.some((recipient) => recipient === null)) {
    return json(400, { ok: false, code: "INVALID_WEBHOOK_PAYLOAD" });
  }
  if (!recipients.includes(configuredRecipient)) {
    return json(202, { ok: true, state: "recipient_not_routed" });
  }

  const canonicalFingerprint = await sha256({
    provider: "RESEND",
    provider_email_id: providerEmailId,
    rfc_message_id: rfcMessageId,
    sender_email: senderEmail,
    matched_recipient: configuredRecipient,
    received_at: receivedAt,
  });
  try {
    const result = await dependencies.register({
      providerEmailId,
      webhookDeliveryId,
      rfcMessageId,
      senderEmail,
      matchedRecipient: configuredRecipient,
      receivedAt,
      canonicalFingerprint,
    });
    return json(200, {
      ok: true,
      state: result.replayed ? "replayed" : "received",
      receipt_id: result.receipt_id,
    });
  } catch (error) {
    if (
      error instanceof Error && error.message === "INBOUND_RECEIPT_CONFLICT"
    ) {
      return json(409, { ok: false, code: "INBOUND_RECEIPT_CONFLICT" });
    }
    if (
      error instanceof Error && error.message === SUPABASE_KEY_BINDING_ERROR
    ) {
      return json(500, { ok: false, code: SUPABASE_KEY_BINDING_ERROR });
    }
    return json(500, { ok: false, code: "INBOUND_RECEIPT_PERSIST_FAILED" });
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));

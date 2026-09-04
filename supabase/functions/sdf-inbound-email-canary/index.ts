import { createClient } from "npm:@supabase/supabase-js@2";
import {
  getSupabasePublishableKey,
  SUPABASE_KEY_BINDING_ERROR,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";

const CANARY = Object.freeze({
  providerEmailId: "internal_e2e_sdf_inbound_canary_v1",
  webhookDeliveryId: "internal_e2e_sdf_inbound_delivery_v1",
  rfcMessageId: "<internal-e2e-sdf-inbound-canary-v1@invalid.local>",
  senderEmail: "sdf-inbound-canary@invalid.local",
  recipient: "sdf-inbound-canary@invalid.local",
  receivedAt: "2000-01-01T00:00:00.000Z",
  marker: "SDF_INBOUND_SIGNED_CANARY_V1",
});

export interface CanaryEvidence {
  authorized: true;
  receipt_count: number;
  delivery_count: number;
  classification: "internal_e2e" | null;
}

interface CanaryDependencies {
  authorize(jwt: string): Promise<"allowed" | "unauthenticated" | "forbidden">;
  readEvidence(jwt: string): Promise<CanaryEvidence>;
  invoke(url: string, init: RequestInit): Promise<Response>;
  environment: SupabaseKeyBindingEnvironment;
  now(): number;
  callTimeoutMs: number;
  totalTimeoutMs: number;
}

class CanaryError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function bearerToken(request: Request): string {
  const match = request.headers.get("authorization")?.match(
    /^Bearer\s+([^\s]+)$/i,
  );
  if (!match) throw new CanaryError(401, "AUTHENTICATION_REQUIRED");
  return match[1];
}

function canonicalPayload(): string {
  return JSON.stringify({
    type: "email.received",
    created_at: CANARY.receivedAt,
    marker: CANARY.marker,
    data: {
      email_id: CANARY.providerEmailId,
      message_id: CANARY.rfcMessageId,
      from: CANARY.senderEmail,
      to: [CANARY.recipient],
      created_at: CANARY.receivedAt,
    },
  });
}

function decodeWebhookSecret(secret: string): ArrayBuffer {
  if (!secret.startsWith("whsec_")) {
    throw new CanaryError(500, "SERVER_CONFIGURATION_ERROR");
  }
  try {
    const decoded = atob(secret.slice("whsec_".length));
    if (!decoded) throw new Error();
    return Uint8Array.from(
      decoded,
      (character) => character.charCodeAt(0),
    ).buffer as ArrayBuffer;
  } catch {
    throw new CanaryError(500, "SERVER_CONFIGURATION_ERROR");
  }
}

export async function createSvixSignature(
  secret: string,
  payload: string,
  id: string,
  timestamp: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    decodeWebhookSecret(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(`${id}.${timestamp}.${payload}`),
    ),
  );
  return `v1,${btoa(String.fromCharCode(...digest))}`;
}

function parseEvidence(value: unknown): CanaryEvidence {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new CanaryError(502, "CANARY_EVIDENCE_INVALID");
  }
  const evidence = value as Record<string, unknown>;
  if (
    evidence.authorized !== true ||
    !Number.isSafeInteger(evidence.receipt_count) ||
    !Number.isSafeInteger(evidence.delivery_count) ||
    (evidence.classification !== null &&
      evidence.classification !== "internal_e2e")
  ) {
    throw new CanaryError(502, "CANARY_EVIDENCE_INVALID");
  }
  return evidence as unknown as CanaryEvidence;
}

function createAuthorityDependencies(
  environment: SupabaseKeyBindingEnvironment,
): Pick<CanaryDependencies, "authorize" | "readEvidence"> {
  const url = environment.get("SUPABASE_URL");
  if (!url) throw new CanaryError(500, "SERVER_CONFIGURATION_ERROR");
  const publishableKey = getSupabasePublishableKey("default", environment);

  const evidenceFor = async (jwt: string): Promise<CanaryEvidence> => {
    const client = createClient(url, publishableKey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await client.auth.getUser(jwt);
    if (userError || !userData.user) {
      throw new CanaryError(401, "AUTHENTICATION_REQUIRED");
    }
    const { data, error } = await client.rpc(
      "get_sdf_inbound_signed_canary_evidence_v1",
    );
    if (error) throw new CanaryError(403, "AUTHORIZATION_DENIED");
    return parseEvidence(data);
  };

  return {
    authorize: async (jwt) => {
      try {
        await evidenceFor(jwt);
        return "allowed";
      } catch (error) {
        return error instanceof CanaryError && error.status === 401
          ? "unauthenticated"
          : "forbidden";
      }
    },
    readEvidence: evidenceFor,
  };
}

function resolveDependencies(
  overrides: Partial<CanaryDependencies>,
): CanaryDependencies {
  const environment = overrides.environment ?? Deno.env;
  const authority = overrides.authorize && overrides.readEvidence
    ? null
    : createAuthorityDependencies(environment);
  return {
    authorize: overrides.authorize ?? authority!.authorize,
    readEvidence: overrides.readEvidence ?? authority!.readEvidence,
    invoke: overrides.invoke ?? ((url, init) => fetch(url, init)),
    environment,
    now: overrides.now ?? (() => Date.now()),
    callTimeoutMs: overrides.callTimeoutMs ?? 5_000,
    totalTimeoutMs: overrides.totalTimeoutMs ?? 12_000,
  };
}

async function withTimeout<T>(
  operation: (signal: AbortSignal) => Promise<T>,
  timeoutMs: number,
): Promise<T> {
  const controller = new AbortController();
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      operation(controller.signal),
      new Promise<T>((_resolve, reject) => {
        timeout = setTimeout(() => {
          controller.abort();
          reject(new CanaryError(504, "CANARY_TIMEOUT"));
        }, timeoutMs);
      }),
    ]);
  } catch (error) {
    if (controller.signal.aborted) {
      throw new CanaryError(504, "CANARY_TIMEOUT");
    }
    throw error;
  } finally {
    if (timeout !== undefined) clearTimeout(timeout);
  }
}

async function readState(response: Response): Promise<string> {
  let value: unknown;
  try {
    value = await response.json();
  } catch {
    throw new CanaryError(502, "CANARY_INBOUND_FAILED");
  }
  const state = value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>).state
    : null;
  if (!response.ok || (state !== "received" && state !== "replayed")) {
    throw new CanaryError(502, "CANARY_INBOUND_FAILED");
  }
  return state;
}

export async function handleRequest(
  request: Request,
  overrides: Partial<CanaryDependencies> = {},
): Promise<Response> {
  try {
    if (request.method !== "POST") {
      throw new CanaryError(405, "METHOD_NOT_ALLOWED");
    }
    const contentType = (request.headers.get("content-type") || "")
      .split(";", 1)[0].trim().toLowerCase();
    if (contentType !== "application/json") {
      throw new CanaryError(415, "UNSUPPORTED_CONTENT_TYPE");
    }
    let body: unknown;
    try {
      body = JSON.parse(await request.text());
    } catch {
      throw new CanaryError(400, "INVALID_REQUEST");
    }
    if (
      !body || typeof body !== "object" || Array.isArray(body) ||
      Object.keys(body as Record<string, unknown>).length !== 0
    ) {
      throw new CanaryError(400, "INVALID_REQUEST");
    }

    const jwt = bearerToken(request);
    const dependencies = resolveDependencies(overrides);
    const startedAt = dependencies.now();
    const remaining = () =>
      dependencies.totalTimeoutMs -
      (dependencies.now() - startedAt);
    const withinTotal = <T>(operation: (signal: AbortSignal) => Promise<T>) => {
      const timeoutMs = Math.min(dependencies.callTimeoutMs, remaining());
      if (timeoutMs <= 0) throw new CanaryError(504, "CANARY_TIMEOUT");
      return withTimeout(operation, timeoutMs);
    };

    const authority = await withinTotal(() => dependencies.authorize(jwt));
    if (authority === "unauthenticated") {
      throw new CanaryError(401, "AUTHENTICATION_REQUIRED");
    }
    if (authority !== "allowed") {
      throw new CanaryError(403, "AUTHORIZATION_DENIED");
    }

    const url = dependencies.environment.get("SUPABASE_URL");
    const secret = dependencies.environment.get("RESEND_WEBHOOK_SECRET");
    if (!url || !secret) {
      throw new CanaryError(500, "SERVER_CONFIGURATION_ERROR");
    }
    const payload = canonicalPayload();
    const timestamp = String(Math.floor(dependencies.now() / 1000));
    const signature = await createSvixSignature(
      secret,
      payload,
      CANARY.webhookDeliveryId,
      timestamp,
    );
    const headers = {
      "content-type": "application/json",
      "svix-id": CANARY.webhookDeliveryId,
      "svix-timestamp": timestamp,
      "svix-signature": signature,
    };
    const invoke = (signal: AbortSignal) =>
      dependencies.invoke(
        `${url}/functions/v1/sdf-inbound-email`,
        { method: "POST", headers, body: payload, signal },
      );
    const first = await readState(await withinTotal(invoke));
    const replay = await readState(await withinTotal(invoke));
    if (first !== "received" || replay !== "replayed") {
      throw new CanaryError(502, "CANARY_RESULT_MISMATCH");
    }

    const evidence = await withinTotal(() => dependencies.readEvidence(jwt));
    if (
      evidence.receipt_count !== 1 || evidence.delivery_count !== 1 ||
      evidence.classification !== "internal_e2e"
    ) {
      throw new CanaryError(502, "CANARY_EVIDENCE_MISMATCH");
    }

    return json(200, {
      ok: true,
      canary: CANARY.marker,
      first,
      replay,
      classification: evidence.classification,
      receipt_count: evidence.receipt_count,
      delivery_count: evidence.delivery_count,
    });
  } catch (error) {
    if (error instanceof CanaryError) {
      return json(error.status, { ok: false, code: error.code });
    }
    if (
      error instanceof Error && error.message === SUPABASE_KEY_BINDING_ERROR
    ) {
      return json(500, { ok: false, code: SUPABASE_KEY_BINDING_ERROR });
    }
    return json(500, { ok: false, code: "CANARY_EXECUTION_FAILED" });
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));

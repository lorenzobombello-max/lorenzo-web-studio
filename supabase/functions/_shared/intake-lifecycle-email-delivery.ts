import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { EmailDeliveryResult } from "./email-delivery.ts";

interface LifecycleEmailContent {
  from: string;
  to: string;
  subject: string;
  html: string;
  text: string;
}

interface LifecycleEmailDeliveryOptions {
  supabase: SupabaseClient;
  jobId: string;
  resendApiKey: string;
  email: LifecycleEmailContent;
  timeoutMs?: number;
}

const RETRYABLE_HTTP_STATUSES = new Set([408, 425, 429]);
const RESEND_API_URL = "https://api.resend.com/emails";

function sanitizeHeaderValue(value: string): string {
  return value.replace(/[\r\n]+/g, "").trim();
}

function deliveryUrl(): string {
  const configured = Deno.env.get("RESEND_API_URL");
  if (!configured || configured === RESEND_API_URL) return RESEND_API_URL;
  const url = new URL(configured);
  const localAllowed = Deno.env.get("ALLOW_LOCAL_EMAIL_DELIVERY") === "true";
  if (!localAllowed || !["127.0.0.1", "localhost", "host.docker.internal"].includes(url.hostname)) {
    throw new Error("Invalid local email delivery URL");
  }
  return url.toString();
}

export async function deliverIntakeLifecycleEmail(
  options: LifecycleEmailDeliveryOptions,
): Promise<EmailDeliveryResult> {
  const { data: claimData, error: claimError } = await options.supabase.rpc(
    "claim_intake_lifecycle_email_job_v2",
    { p_job_id: options.jobId },
  );
  const claim = Array.isArray(claimData) ? claimData[0] : claimData;
  if (claimError || !claim?.delivery_lease_token) {
    return { status: "failed", attempted: false, attemptCount: 0, errorCode: "JOB_CLAIM_FAILED" };
  }

  const complete = async (
    succeeded: boolean,
    retryable: boolean,
    errorCode?: string,
    providerMessageId?: string,
  ): Promise<EmailDeliveryResult> => {
    const { data, error } = await options.supabase.rpc(
      "complete_intake_lifecycle_email_job_v2",
      {
        p_job_id: options.jobId,
        p_delivery_lease_token: claim.delivery_lease_token,
        p_succeeded: succeeded,
        p_retryable: retryable,
        p_error_code: errorCode ?? null,
        p_provider_message_id: providerMessageId ?? null,
      },
    );
    if (error || !data?.status) {
      return { status: "failed", attempted: true, attemptCount: 0, errorCode: "JOB_COMPLETION_FAILED" };
    }
    return {
      status: data.status,
      attempted: true,
      attemptCount: Number(data.attempt_count) || 0,
      errorCode,
    };
  };

  const resendApiKey = sanitizeHeaderValue(options.resendApiKey);
  const from = sanitizeHeaderValue(options.email.from);
  const to = sanitizeHeaderValue(options.email.to);
  if (!resendApiKey || !from || !to) {
    return await complete(false, false, "EMAIL_CONFIGURATION_INVALID");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 10_000);
  try {
    const response = await fetch(deliveryUrl(), {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `intake-lifecycle-email/${options.jobId}`,
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject: options.email.subject,
        html: options.email.html,
        text: options.email.text,
      }),
    });
    if (!response.ok) {
      const retryable = RETRYABLE_HTTP_STATUSES.has(response.status) || response.status >= 500;
      return await complete(false, retryable, `RESEND_HTTP_${response.status}`);
    }
    let providerMessageId: string | undefined;
    try {
      const body = await response.json();
      if (body && typeof body.id === "string") providerMessageId = body.id;
    } catch {
      // A successful provider response without JSON is still successful.
    }
    return await complete(true, false, undefined, providerMessageId);
  } catch (error) {
    const errorCode = error instanceof DOMException && error.name === "AbortError"
      ? "RESEND_TIMEOUT"
      : "RESEND_NETWORK_ERROR";
    return await complete(false, true, errorCode);
  } finally {
    clearTimeout(timeout);
  }
}

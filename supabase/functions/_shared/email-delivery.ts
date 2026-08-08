import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { EmailJobStatus } from "./types.ts";

interface EmailContent {
  from: string;
  to: string;
  subject: string;
  html: string;
  text: string;
}

interface DeliverEmailJobOptions {
  supabase: SupabaseClient;
  jobId: string;
  resendApiKey: string;
  email: EmailContent;
  timeoutMs?: number;
}

export interface EmailDeliveryResult {
  status: EmailJobStatus;
  attempted: boolean;
  attemptCount: number;
  errorCode?: string;
}

const RETRYABLE_HTTP_STATUSES = new Set([408, 425, 429]);
const RESEND_API_URL = "https://api.resend.com/emails";

function sanitizeHeaderValue(value: string): string {
  return value.replace(/[\r\n]+/g, "").trim();
}

function isEmailJobStatus(value: unknown): value is EmailJobStatus {
  return value === "pending" || value === "processing" || value === "sent" || value === "retry_wait" || value === "failed";
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

async function currentJobState(supabase: SupabaseClient, jobId: string): Promise<EmailDeliveryResult> {
  const { data, error } = await supabase
    .from("quote_request_email_jobs")
    .select("status, attempt_count")
    .eq("id", jobId)
    .maybeSingle();

  if (error || !data || !isEmailJobStatus(data.status)) {
    return { status: "failed", attempted: false, attemptCount: 0, errorCode: "JOB_STATE_UNAVAILABLE" };
  }

  return {
    status: data.status,
    attempted: false,
    attemptCount: Number(data.attempt_count) || 0,
  };
}

async function completeJob(
  supabase: SupabaseClient,
  jobId: string,
  succeeded: boolean,
  retryable: boolean,
  errorCode?: string,
  providerMessageId?: string,
): Promise<EmailDeliveryResult> {
  const { data, error } = await supabase.rpc("complete_quote_request_email_job", {
    p_job_id: jobId,
    p_succeeded: succeeded,
    p_retryable: retryable,
    p_error_code: errorCode ?? null,
    p_provider_message_id: providerMessageId ?? null,
  });

  const completed = Array.isArray(data) ? data[0] : data;
  if (error || !completed || !isEmailJobStatus(completed.job_status)) {
    return { status: "failed", attempted: true, attemptCount: 0, errorCode: "JOB_COMPLETION_FAILED" };
  }

  return {
    status: completed.job_status,
    attempted: true,
    attemptCount: Number(completed.attempt_count) || 0,
    errorCode,
  };
}

export async function deliverEmailJob(options: DeliverEmailJobOptions): Promise<EmailDeliveryResult> {
  const { supabase, jobId } = options;
  const { data: claimData, error: claimError } = await supabase.rpc("claim_quote_request_email_job", {
    p_job_id: jobId,
  });
  const claim = Array.isArray(claimData) ? claimData[0] : claimData;

  if (claimError) {
    return { status: "failed", attempted: false, attemptCount: 0, errorCode: "JOB_CLAIM_FAILED" };
  }
  if (!claim) return await currentJobState(supabase, jobId);

  const resendApiKey = sanitizeHeaderValue(options.resendApiKey);
  const from = sanitizeHeaderValue(options.email.from);
  const to = sanitizeHeaderValue(options.email.to);
  if (!resendApiKey || !from || !to) {
    return await completeJob(supabase, jobId, false, false, "EMAIL_CONFIGURATION_INVALID");
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
        "Idempotency-Key": `quote-request-email/${jobId}`,
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
      return await completeJob(supabase, jobId, false, retryable, `RESEND_HTTP_${response.status}`);
    }

    let providerMessageId: string | undefined;
    try {
      const responseBody = await response.json();
      if (responseBody && typeof responseBody.id === "string") providerMessageId = responseBody.id;
    } catch {
      // A successful provider response without JSON is still a successful delivery.
    }

    return await completeJob(supabase, jobId, true, false, undefined, providerMessageId);
  } catch (error) {
    const code = error instanceof DOMException && error.name === "AbortError" ? "RESEND_TIMEOUT" : "RESEND_NETWORK_ERROR";
    return await completeJob(supabase, jobId, false, true, code);
  } finally {
    clearTimeout(timeout);
  }
}
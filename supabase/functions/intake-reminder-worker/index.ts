import { createClient } from "npm:@supabase/supabase-js@2";
import { deliverEmailJob } from "../_shared/email-delivery.ts";
import { buildIntakeReminderEmail } from "../_shared/email-templates.ts";
import { decryptIntakeInvitationToken } from "../_shared/security.ts";
import {
  automationSecretMatches,
  isReminderPhase,
  type ReminderCandidate,
  type ReminderPhase,
  runReminderWorker,
  type WorkerDatabase,
} from "./handler.ts";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function first<T>(data: T[] | T | null): T | null {
  return Array.isArray(data) ? data[0] ?? null : data;
}

function intakeUrl(rawToken: string): string {
  const url = new URL(
    "/pages/intake.html",
    Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be",
  );
  url.searchParams.set("token", rawToken);
  return url.toString();
}

export async function handleRequest(request: Request): Promise<Response> {
  if (request.method !== "POST") {
    return json(405, { ok: false, code: "METHOD_NOT_ALLOWED" });
  }

  const automationSecret = Deno.env.get("INTAKE_REMINDER_AUTOMATION_SECRET") ||
    "";
  if (
    !await automationSecretMatches(
      request.headers.get("x-lws-automation-secret"),
      automationSecret,
    )
  ) {
    return json(401, { ok: false, code: "UNAUTHORIZED" });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json(400, { ok: false, code: "INVALID_JSON" });
  }
  if (
    typeof body.dry_run !== "boolean" ||
    (body.phase !== undefined && !isReminderPhase(body.phase))
  ) {
    return json(400, { ok: false, code: "INVALID_WORKER_REQUEST" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { ok: false, code: "SERVER_CONFIGURATION_ERROR" });
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const database: WorkerDatabase = {
    async listCandidates(phase, limit) {
      const { data, error } = await supabase.rpc(
        "list_intake_reminder_candidates_v1",
        {
          p_reminder_phase: phase,
          p_limit: limit,
        },
      );
      if (error) throw new Error("CANDIDATE_DISCOVERY_FAILED");
      return (data || []) as ReminderCandidate[];
    },
    async claim(candidate) {
      const { data, error } = await supabase.rpc("claim_intake_reminder_v1", {
        p_intake_id: candidate.intake_id,
        p_reminder_phase: candidate.reminder_phase,
      });
      if (error) throw new Error("REMINDER_CLAIM_FAILED");
      return first(data);
    },
    async prepare(candidate, claim) {
      const { data, error } = await supabase.rpc(
        "prepare_intake_reminder_email_job_v1",
        {
          p_intake_id: candidate.intake_id,
          p_access_cycle: candidate.access_cycle,
          p_reminder_phase: candidate.reminder_phase,
          p_claim_token: claim.claim_token,
        },
      );
      if (error) throw new Error("REMINDER_PREPARATION_FAILED");
      return first(data);
    },
    async getDelivery(jobId) {
      const { data, error } = await supabase.rpc(
        "get_intake_reminder_email_delivery_v1",
        { p_job_id: jobId },
      );
      if (error) throw new Error("REMINDER_RECHECK_FAILED");
      return first(data);
    },
    async getCapability(intakeId, accessCycle) {
      const { data, error } = await supabase.rpc(
        "get_intake_reminder_capability_v1",
        {
          p_intake_id: intakeId,
          p_access_cycle: accessCycle,
        },
      );
      if (error) throw new Error("REMINDER_CAPABILITY_FAILED");
      return first(data);
    },
  };

  try {
    const result = await runReminderWorker(
      { dryRun: body.dry_run, phase: body.phase as ReminderPhase | undefined },
      {
        database,
        decryptToken: decryptIntakeInvitationToken,
        buildIntakeUrl: intakeUrl,
        buildEmail: buildIntakeReminderEmail,
        deliver: async ({ jobId, recipientEmail, email }) =>
          await deliverEmailJob({
            supabase,
            jobId,
            resendApiKey: Deno.env.get("RESEND_API_KEY") || "",
            email: {
              from: Deno.env.get("FROM_EMAIL") || "",
              to: recipientEmail,
              subject: email.subject,
              html: email.html,
              text: email.text,
            },
          }),
      },
    );
    return json(200, result);
  } catch {
    return json(500, { ok: false, code: "WORKER_FAILED" });
  }
}

if (import.meta.main) Deno.serve(handleRequest);

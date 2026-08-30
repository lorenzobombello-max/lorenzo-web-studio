export type ReminderPhase = "REMINDER_1" | "REMINDER_2";
export type ProgressStatus = "invited" | "in_progress";

export interface ReminderCandidate {
  quote_request_id: string;
  intake_id: string;
  access_cycle: number;
  reminder_phase: ReminderPhase;
  progress_status: ProgressStatus;
  expires_at: string;
}

export interface ReminderClaim {
  intake_id: string;
  access_cycle: number;
  reminder_phase: ReminderPhase;
  claim_token: string;
}

export interface PreparedReminder {
  outcome: "prepared" | "already_sent" | "CAPABILITY_UNAVAILABLE";
  email_job_id: string | null;
}

export interface ReminderDeliveryContext {
  email_job_id: string;
  reminder_phase: ReminderPhase;
  access_cycle: number;
  recipient_email: string;
  client_name: string;
  company: string | null;
  progress_status: ProgressStatus;
  expires_at: string;
  encrypted_token: string;
}

export interface ReminderCapability {
  outcome: "CAPABILITY_AVAILABLE" | "CAPABILITY_UNAVAILABLE";
  access_token_hash: string | null;
}

export interface WorkerDatabase {
  listCandidates(
    phase: ReminderPhase,
    limit: number,
  ): Promise<ReminderCandidate[]>;
  claim(candidate: ReminderCandidate): Promise<ReminderClaim | null>;
  prepare(
    candidate: ReminderCandidate,
    claim: ReminderClaim,
  ): Promise<PreparedReminder | null>;
  getDelivery(jobId: string): Promise<ReminderDeliveryContext | null>;
  getCapability(
    intakeId: string,
    accessCycle: number,
  ): Promise<ReminderCapability | null>;
}

export interface ReminderEmail {
  subject: string;
  html: string;
  text: string;
}

export interface WorkerDependencies {
  database: WorkerDatabase;
  decryptToken(
    encryptedToken: string,
    accessTokenHash: string,
  ): Promise<string>;
  buildIntakeUrl(rawToken: string): string;
  buildEmail(input: {
    clientName: string;
    company: string | null;
    requestId: string;
    intakeUrl: string;
    progressStatus: ProgressStatus;
    reminderPhase: ReminderPhase;
    expiresAt: string;
  }): ReminderEmail;
  deliver(input: {
    jobId: string;
    recipientEmail: string;
    email: ReminderEmail;
  }): Promise<{ status: string }>;
}

export interface WorkerRequest {
  dryRun: boolean;
  phase?: ReminderPhase;
}

export interface WorkerCounters {
  candidates_seen: number;
  claimed: number;
  prepared: number;
  sent_mocked: number;
  skipped_not_eligible: number;
  skipped_duplicate: number;
  skipped_capability_unavailable: number;
  failed: number;
}

export interface WorkerResult extends WorkerCounters {
  ok: true;
  dry_run: boolean;
  candidates: ReminderCandidate[];
}

export const WORKER_BATCH_LIMIT = 25;

function counters(): WorkerCounters {
  return {
    candidates_seen: 0,
    claimed: 0,
    prepared: 0,
    sent_mocked: 0,
    skipped_not_eligible: 0,
    skipped_duplicate: 0,
    skipped_capability_unavailable: 0,
    failed: 0,
  };
}

export function isReminderPhase(value: unknown): value is ReminderPhase {
  return value === "REMINDER_1" || value === "REMINDER_2";
}

export async function automationSecretMatches(
  provided: string | null,
  expected: string,
): Promise<boolean> {
  if (!provided || expected.length < 32) return false;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(expected),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expectedMac = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode("intake-reminder-worker:v1"),
    ),
  );
  const providedKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(provided),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const providedMac = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      providedKey,
      encoder.encode("intake-reminder-worker:v1"),
    ),
  );
  let difference = 0;
  for (let index = 0; index < expectedMac.length; index++) {
    difference |= expectedMac[index] ^ providedMac[index];
  }
  return difference === 0;
}

async function discoverCandidates(
  database: WorkerDatabase,
  requestedPhase?: ReminderPhase,
): Promise<ReminderCandidate[]> {
  const phases: ReminderPhase[] = requestedPhase
    ? [requestedPhase]
    : ["REMINDER_1", "REMINDER_2"];
  const candidates: ReminderCandidate[] = [];
  for (const phase of phases) {
    const remaining = WORKER_BATCH_LIMIT - candidates.length;
    if (remaining === 0) break;
    candidates.push(...await database.listCandidates(phase, remaining));
  }
  return candidates.slice(0, WORKER_BATCH_LIMIT);
}

export async function runReminderWorker(
  request: WorkerRequest,
  dependencies: WorkerDependencies,
): Promise<WorkerResult> {
  const result: WorkerResult = {
    ok: true,
    dry_run: request.dryRun,
    candidates: [],
    ...counters(),
  };
  const candidates = await discoverCandidates(
    dependencies.database,
    request.phase,
  );
  result.candidates_seen = candidates.length;

  if (request.dryRun) {
    result.candidates = candidates.map((candidate) => ({
      quote_request_id: candidate.quote_request_id,
      intake_id: candidate.intake_id,
      access_cycle: candidate.access_cycle,
      reminder_phase: candidate.reminder_phase,
      progress_status: candidate.progress_status,
      expires_at: candidate.expires_at,
    }));
    return result;
  }

  for (const candidate of candidates) {
    try {
      const claim = await dependencies.database.claim(candidate);
      if (!claim) {
        result.skipped_duplicate++;
        continue;
      }
      result.claimed++;

      const prepared = await dependencies.database.prepare(candidate, claim);
      if (prepared?.outcome === "CAPABILITY_UNAVAILABLE") {
        result.skipped_capability_unavailable++;
        continue;
      }
      if (!prepared?.email_job_id) {
        result.skipped_not_eligible++;
        continue;
      }
      if (prepared.outcome === "already_sent") {
        result.skipped_duplicate++;
        continue;
      }
      result.prepared++;

      const delivery = await dependencies.database.getDelivery(
        prepared.email_job_id,
      );
      if (!delivery) {
        result.skipped_not_eligible++;
        continue;
      }
      const capability = await dependencies.database.getCapability(
        candidate.intake_id,
        candidate.access_cycle,
      );
      if (
        capability?.outcome !== "CAPABILITY_AVAILABLE" ||
        !capability.access_token_hash
      ) {
        result.skipped_capability_unavailable++;
        continue;
      }

      const rawToken = await dependencies.decryptToken(
        delivery.encrypted_token,
        capability.access_token_hash,
      );
      const email = dependencies.buildEmail({
        clientName: delivery.client_name,
        company: delivery.company,
        requestId: candidate.quote_request_id,
        intakeUrl: dependencies.buildIntakeUrl(rawToken),
        progressStatus: delivery.progress_status,
        reminderPhase: delivery.reminder_phase,
        expiresAt: delivery.expires_at,
      });
      const deliveryResult = await dependencies.deliver({
        jobId: delivery.email_job_id,
        recipientEmail: delivery.recipient_email,
        email,
      });
      if (deliveryResult.status === "sent") result.sent_mocked++;
      else result.failed++;
    } catch (error) {
      result.failed++;
      console.error("intake_reminder_candidate_failed", {
        intake_id: candidate.intake_id,
        access_cycle: candidate.access_cycle,
        reminder_phase: candidate.reminder_phase,
        error_code: error instanceof Error ? error.name : "UNKNOWN_ERROR",
      });
    }
  }

  return result;
}

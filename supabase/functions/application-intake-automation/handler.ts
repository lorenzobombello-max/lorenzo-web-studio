const MAX_BODY_BYTES = 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AutomationPhase = "APPROVAL" | "INTAKE" | "SDF_CONFIRMATION" | "SDF_INTAKE";
export interface AutomationClaim { work_id: number; quote_request_id: string; phase: AutomationPhase; claim_token: string }
interface RpcResult { data: unknown; error: { message: string } | null }
interface DeliveryResult { status: "pending" | "processing" | "sent" | "retry_wait" | "failed" }

export function websiteTypeOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function validTimestamp(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

export function websiteIntakeOutcome(value: unknown): "deliver" | "stopped" | "invalid" {
  if (!value || typeof value !== "object" || Array.isArray(value)) return "invalid";
  const authority = value as Record<string, unknown>;
  if (
    authority.outcome === "stopped" && authority.invitation_job_id === null &&
    UUID.test(String(authority.intake_id || "")) && validTimestamp(authority.access_token_expires_at)
  ) return "stopped";
  if (
    authority.outcome === "intake_completed" &&
    UUID.test(String(authority.invitation_job_id || "")) &&
    UUID.test(String(authority.intake_id || "")) &&
    typeof authority.request_name === "string" && authority.request_name.trim() &&
    typeof authority.request_email === "string" && authority.request_email.trim() &&
    (authority.request_company === null || typeof authority.request_company === "string") &&
    validTimestamp(authority.access_token_expires_at)
  ) return "deliver";
  return "invalid";
}

export function hasCanonicalSdfConfirmationTemplate(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const authority = value as Record<string, unknown>;
  return authority.template_key === "SDF_REQUEST_RECEIVED_NL_BE_v1" && authority.template_version === "v1";
}

export interface AutomationDependencies {
  configurationReady: boolean;
  workerSecret?: string;
  randomUUID(): string;
  digest(data: Uint8Array): Promise<ArrayBuffer>;
  rpc(name: string, parameters: Record<string, unknown>): Promise<RpcResult>;
  executeWebsite(claim: AutomationClaim): Promise<DeliveryResult>;
  executeSdfConfirmation(claim: AutomationClaim): Promise<DeliveryResult>;
  executeSdfInvitation(claim: AutomationClaim): Promise<DeliveryResult>;
  executeQueuedSdfEmail(): Promise<DeliveryResult | null>;
}

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function validBody(request: Request): Promise<boolean> {
  if (request.headers.get("content-type")?.split(";", 1)[0].trim() !== "application/json") return false;
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) return false;
  try {
    const value = JSON.parse(text);
    return value && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 1 && value.version === 1;
  } catch { return false; }
}

async function secretMatches(incoming: string | null, expected: string | undefined, digest: AutomationDependencies["digest"]) {
  if (!incoming || !expected || incoming.length < 32 || incoming.length !== expected.length) return false;
  const encoder = new TextEncoder();
  const [leftBuffer, rightBuffer] = await Promise.all([digest(encoder.encode(incoming)), digest(encoder.encode(expected))]);
  const left = new Uint8Array(leftBuffer); const right = new Uint8Array(rightBuffer);
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

function claims(data: unknown): AutomationClaim[] | null {
  if (!Array.isArray(data)) return null;
  const result: AutomationClaim[] = [];
  for (const item of data) {
    if (!item || typeof item !== "object") return null;
    const row = item as Record<string, unknown>;
    if (!Number.isSafeInteger(row.work_id) || !UUID.test(String(row.quote_request_id)) || !UUID.test(String(row.claim_token)) || !["APPROVAL", "INTAKE", "SDF_CONFIRMATION", "SDF_INTAKE"].includes(String(row.phase))) return null;
    result.push(row as unknown as AutomationClaim);
  }
  return result;
}

export async function handleApplicationIntakeAutomation(request: Request, dependencies: AutomationDependencies): Promise<Response> {
  const rejected = { ok: false, claimed: 0, completed: 0, retry_scheduled: 0, manual_review: 0 };
  if (request.method !== "POST" || new URL(request.url).search || !await validBody(request)) return response(400, rejected);
  if (!dependencies.configurationReady || !await secretMatches(request.headers.get("x-lws-automation-secret"), dependencies.workerSecret, dependencies.digest)) return response(401, rejected);
  const workerId = dependencies.randomUUID();
  if (!UUID.test(workerId)) return response(500, rejected);
  const claimed = await dependencies.rpc("claim_application_intake_automation_work_v1", { p_worker_id: workerId, p_limit: 5 });
  const work = claimed.error ? null : claims(claimed.data);
  if (!work) return response(500, rejected);
  const counters = { ok: true, claimed: work.length, completed: 0, retry_scheduled: 0, manual_review: 0 };
  for (const claim of work) {
    try {
      const delivery = claim.phase === "SDF_CONFIRMATION"
        ? await dependencies.executeSdfConfirmation(claim)
        : claim.phase === "SDF_INTAKE"
        ? await dependencies.executeSdfInvitation(claim)
        : await dependencies.executeWebsite(claim);
      if (delivery.status === "sent") counters.completed += 1;
      else if (delivery.status === "retry_wait") counters.retry_scheduled += 1;
      else if (delivery.status === "failed") counters.manual_review += 1;
    } catch {
      const failure = await dependencies.rpc("fail_application_intake_automation_work_v1", {
        p_work_id: claim.work_id, p_claim_token: claim.claim_token,
        p_error_code: "WORKER_INTERRUPTED", p_retryable: true,
      });
      const row = Array.isArray(failure.data) ? failure.data[0] : failure.data;
      if ((row as Record<string, unknown> | null)?.outcome === "retry_scheduled") counters.retry_scheduled += 1;
      else counters.manual_review += 1;
    }
  }
  try {
    const queued = await dependencies.executeQueuedSdfEmail();
    if (queued?.status === "sent") counters.completed += 1;
    else if (queued?.status === "retry_wait") counters.retry_scheduled += 1;
    else if (queued?.status === "failed") counters.manual_review += 1;
  } catch {
    counters.manual_review += 1;
  }
  return response(200, counters);
}
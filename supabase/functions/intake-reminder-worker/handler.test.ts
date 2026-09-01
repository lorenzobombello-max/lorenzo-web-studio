import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  automationSecretMatches,
  type ReminderCandidate,
  type ReminderDeliveryContext,
  runReminderWorker,
  WORKER_BATCH_LIMIT,
  type WorkerDatabase,
  type WorkerDependencies,
} from "./handler.ts";
import { handleRequest } from "./index.ts";

const secret = "a".repeat(32);

function candidate(
  overrides: Partial<ReminderCandidate> = {},
): ReminderCandidate {
  return {
    quote_request_id: "request-1",
    intake_id: "intake-1",
    request_kind: "website",
    access_cycle: 0,
    reminder_phase: "REMINDER_1",
    progress_status: "invited",
    expires_at: "2030-01-08T12:00:00.000Z",
    ...overrides,
  };
}

function context(value: ReminderCandidate): ReminderDeliveryContext {
  return {
    email_job_id: `job-${value.intake_id}-${value.reminder_phase}`,
    reminder_phase: value.reminder_phase,
    access_cycle: value.access_cycle,
    recipient_email: "internal@example.test",
    client_name: "Client",
    company: null,
    progress_status: value.progress_status,
    expires_at: value.expires_at,
    encrypted_token: "encrypted-not-logged",
  };
}

function harness(values: ReminderCandidate[], options: {
  capabilityUnavailable?: boolean;
  ineligible?: Set<string>;
  claimed?: Set<string>;
  fail?: Set<string>;
} = {}) {
  const calls = {
    list: 0,
    claim: 0,
    prepare: 0,
    delivery: 0,
    capability: 0,
    decrypt: 0,
    template: 0,
  };
  const delivered: string[] = [];
  const claimed = options.claimed ?? new Set<string>();
  const database: WorkerDatabase = {
    async listCandidates(phase, limit) {
      calls.list++;
      return values.filter((value) => value.reminder_phase === phase).slice(
        0,
        limit,
      );
    },
    async claim(value) {
      calls.claim++;
      const key =
        `${value.intake_id}:${value.access_cycle}:${value.reminder_phase}`;
      if (claimed.has(key)) return null;
      claimed.add(key);
      return { ...value, claim_token: `claim-${key}` };
    },
    async prepare(value) {
      calls.prepare++;
      if (options.fail?.has(value.intake_id)) {
        throw new Error("fixture failure");
      }
      if (options.capabilityUnavailable) {
        return { outcome: "CAPABILITY_UNAVAILABLE", email_job_id: null };
      }
      return {
        outcome: "prepared",
        email_job_id: `job-${value.intake_id}-${value.reminder_phase}`,
      };
    },
    async getDelivery(jobId) {
      calls.delivery++;
      const value = values.find((item) =>
        jobId === `job-${item.intake_id}-${item.reminder_phase}`
      )!;
      return options.ineligible?.has(value.intake_id) ? null : context(value);
    },
    async getCapability() {
      calls.capability++;
      return {
        outcome: "CAPABILITY_AVAILABLE",
        access_token_hash: "b".repeat(64),
      };
    },
  };
  const dependencies: WorkerDependencies = {
    database,
    async decryptToken() {
      calls.decrypt++;
      return "A".repeat(43);
    },
    buildIntakeUrl: () => "https://example.test/intake?token=hidden",
    buildEmail(input) {
      calls.template++;
      return {
        subject: `${input.reminderPhase}:${input.progressStatus}`,
        html: "html",
        text: "text",
      };
    },
    async deliver(input) {
      delivered.push(input.email.subject);
      return { status: "sent" };
    },
  };
  return { calls, claimed, delivered, dependencies };
}

Deno.test("worker discovers all four lifecycle phases for Website and SDF", async () => {
  const fixture = harness([
    candidate({ reminder_phase: "REMINDER_1" }),
    candidate({ reminder_phase: "REMINDER_2" }),
    candidate({ reminder_phase: "FINAL_WARNING", request_kind: "slimme_documentenflow" }),
    candidate({ reminder_phase: "EXPIRY", request_kind: "slimme_documentenflow" }),
  ]);
  const result = await runReminderWorker({ dryRun: true }, fixture.dependencies);
  assertEquals(result.candidates.map((item) => item.reminder_phase), [
    "REMINDER_1",
    "REMINDER_2",
    "FINAL_WARNING",
    "EXPIRY",
  ]);
  assertEquals(result.candidates.map((item) => item.request_kind), [
    "website",
    "website",
    "slimme_documentenflow",
    "slimme_documentenflow",
  ]);
});

Deno.test("expiry sends without decrypting or rebuilding an active capability link", async () => {
  const value = candidate({ reminder_phase: "EXPIRY", request_kind: "slimme_documentenflow" });
  const fixture = harness([value]);
  fixture.dependencies.database.getCapability = () => Promise.resolve(null);
  fixture.dependencies.database.getDelivery = () => Promise.resolve({
    ...context(value),
    encrypted_token: null,
  });
  const result = await runReminderWorker({ dryRun: false, phase: "EXPIRY" }, fixture.dependencies);
  assertEquals(result.sent_mocked, 1);
  assertEquals(fixture.calls.decrypt, 0);
  assertEquals(fixture.calls.capability, 0);
});

Deno.test("auth rejects a missing automation secret", async () => {
  assertEquals(await automationSecretMatches(null, secret), false);
});

Deno.test("auth rejects a wrong automation secret", async () => {
  assertEquals(await automationSecretMatches("b".repeat(32), secret), false);
});

Deno.test("auth accepts the configured automation secret", async () => {
  assertEquals(await automationSecretMatches(secret, secret), true);
});

Deno.test("auth rejects an invalid server-side secret configuration", async () => {
  assertEquals(await automationSecretMatches("short", "short"), false);
});

async function withWorkerEnvironment(run: () => Promise<void>): Promise<void> {
  const previous = {
    secret: Deno.env.get("INTAKE_REMINDER_AUTOMATION_SECRET"),
    url: Deno.env.get("SUPABASE_URL"),
    key: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  };
  Deno.env.set("INTAKE_REMINDER_AUTOMATION_SECRET", secret);
  Deno.env.delete("SUPABASE_URL");
  Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
  try {
    await run();
  } finally {
    for (
      const [name, value] of [
        ["INTAKE_REMINDER_AUTOMATION_SECRET", previous.secret],
        ["SUPABASE_URL", previous.url],
        ["SUPABASE_SERVICE_ROLE_KEY", previous.key],
      ] as const
    ) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

Deno.test("endpoint rejects a missing automation secret", async () => {
  await withWorkerEnvironment(async () => {
    const response = await handleRequest(
      new Request("https://worker.test", {
        method: "POST",
        body: JSON.stringify({ dry_run: true }),
      }),
    );
    assertEquals(response.status, 401);
  });
});

Deno.test("endpoint rejects a wrong automation secret", async () => {
  await withWorkerEnvironment(async () => {
    const response = await handleRequest(
      new Request("https://worker.test", {
        method: "POST",
        headers: { "x-lws-automation-secret": "b".repeat(32) },
        body: JSON.stringify({ dry_run: true }),
      }),
    );
    assertEquals(response.status, 401);
  });
});

Deno.test("endpoint accepts the correct secret before server configuration", async () => {
  await withWorkerEnvironment(async () => {
    const response = await handleRequest(
      new Request("https://worker.test", {
        method: "POST",
        headers: { "x-lws-automation-secret": secret },
        body: JSON.stringify({ dry_run: true }),
      }),
    );
    assertEquals(response.status, 500);
    assertEquals(await response.json(), {
      ok: false,
      code: "SERVER_CONFIGURATION_ERROR",
    });
  });
});

Deno.test("dry-run succeeds with zero candidates and zero writes", async () => {
  const fixture = harness([]);
  const result = await runReminderWorker(
    { dryRun: true },
    fixture.dependencies,
  );
  assertEquals(result.candidates_seen, 0);
  assertEquals(fixture.calls.claim, 0);
  assertEquals(fixture.calls.prepare, 0);
  assertEquals(fixture.calls.delivery, 0);
});

Deno.test("dry-run returns R1 invited safe metadata only", async () => {
  const fixture = harness([candidate()]);
  const result = await runReminderWorker(
    { dryRun: true, phase: "REMINDER_1" },
    fixture.dependencies,
  );
  assertEquals(result.candidates[0].progress_status, "invited");
  assertEquals(JSON.stringify(result).includes("encrypted"), false);
  assertEquals(fixture.calls.capability, 0);
});

Deno.test("dry-run returns R1 in-progress", async () => {
  const fixture = harness([candidate({ progress_status: "in_progress" })]);
  const result = await runReminderWorker(
    { dryRun: true, phase: "REMINDER_1" },
    fixture.dependencies,
  );
  assertEquals(result.candidates[0].progress_status, "in_progress");
});

Deno.test("dry-run selects R2", async () => {
  const fixture = harness([candidate({ reminder_phase: "REMINDER_2" })]);
  const result = await runReminderWorker(
    { dryRun: true, phase: "REMINDER_2" },
    fixture.dependencies,
  );
  assertEquals(result.candidates[0].reminder_phase, "REMINDER_2");
});

for (const reminder_phase of ["REMINDER_1", "REMINDER_2", "FINAL_WARNING"] as const) {
  for (const progress_status of ["invited", "in_progress"] as const) {
    Deno.test(`${reminder_phase} ${progress_status} claims, prepares, rechecks and sends mocked`, async () => {
      const fixture = harness([candidate({ reminder_phase, progress_status })]);
      const result = await runReminderWorker({
        dryRun: false,
        phase: reminder_phase,
      }, fixture.dependencies);
      assertEquals(result.claimed, 1);
      assertEquals(result.prepared, 1);
      assertEquals(result.sent_mocked, 1);
      assertEquals(fixture.delivered, [`${reminder_phase}:${progress_status}`]);
    });
  }
}

Deno.test("duplicate concurrent invocation delivers at most once", async () => {
  const fixture = harness([candidate()]);
  const first = await runReminderWorker(
    { dryRun: false, phase: "REMINDER_1" },
    fixture.dependencies,
  );
  const second = await runReminderWorker(
    { dryRun: false, phase: "REMINDER_1" },
    fixture.dependencies,
  );
  assertEquals(first.sent_mocked, 1);
  assertEquals(second.skipped_duplicate, 1);
  assertEquals(fixture.delivered.length, 1);
});

Deno.test("legacy capability unavailable skips safely", async () => {
  const fixture = harness([candidate()], { capabilityUnavailable: true });
  const result = await runReminderWorker(
    { dryRun: false },
    fixture.dependencies,
  );
  assertEquals(result.skipped_capability_unavailable, 1);
  assertEquals(fixture.calls.delivery, 0);
});

for (const state of ["submitted", "cancelled", "interrupted", "expired"]) {
  Deno.test(`claim then ${state} is skipped by final server recheck`, async () => {
    const fixture = harness([candidate()], {
      ineligible: new Set(["intake-1"]),
    });
    const result = await runReminderWorker(
      { dryRun: false },
      fixture.dependencies,
    );
    assertEquals(result.skipped_not_eligible, 1);
    assertEquals(fixture.delivered.length, 0);
  });
}

Deno.test("R1 sent does not block later R2", async () => {
  const fixture = harness([
    candidate(),
    candidate({ reminder_phase: "REMINDER_2" }),
  ]);
  const first = await runReminderWorker(
    { dryRun: false, phase: "REMINDER_1" },
    fixture.dependencies,
  );
  const second = await runReminderWorker(
    { dryRun: false, phase: "REMINDER_2" },
    fixture.dependencies,
  );
  assertEquals([first.sent_mocked, second.sent_mocked], [1, 1]);
});

Deno.test("reactivation cycle B permits both phases independently", async () => {
  const fixture = harness([
    candidate({ access_cycle: 1 }),
    candidate({ access_cycle: 1, reminder_phase: "REMINDER_2" }),
  ]);
  const result = await runReminderWorker(
    { dryRun: false },
    fixture.dependencies,
  );
  assertEquals(result.sent_mocked, 2);
});

Deno.test("resume keeps cycle and skips sent R1 while R2 remains possible", async () => {
  const sentR1 = "intake-1:0:REMINDER_1";
  const fixture = harness(
    [candidate(), candidate({ reminder_phase: "REMINDER_2" })],
    { claimed: new Set([sentR1]) },
  );
  const result = await runReminderWorker(
    { dryRun: false },
    fixture.dependencies,
  );
  assertEquals(result.skipped_duplicate, 1);
  assertEquals(result.sent_mocked, 1);
});

Deno.test("batch is bounded to 25 candidates", async () => {
  const values = Array.from(
    { length: 40 },
    (_, index) => candidate({ intake_id: `intake-${index}` }),
  );
  const fixture = harness(values);
  const result = await runReminderWorker(
    { dryRun: true },
    fixture.dependencies,
  );
  assertEquals(result.candidates_seen, WORKER_BATCH_LIMIT);
});

Deno.test("one candidate failure does not block the batch", async () => {
  const fixture = harness(
    [candidate({ intake_id: "bad" }), candidate({ intake_id: "good" })],
    { fail: new Set(["bad"]) },
  );
  const result = await runReminderWorker(
    { dryRun: false },
    fixture.dependencies,
  );
  assertEquals(result.failed, 1);
  assertEquals(result.sent_mocked, 1);
});

Deno.test("candidate discovery failures are explicit", async () => {
  const fixture = harness([]);
  fixture.dependencies.database.listCandidates = () =>
    Promise.reject(new Error("unavailable"));
  await assertRejects(() =>
    runReminderWorker({ dryRun: true }, fixture.dependencies)
  );
});

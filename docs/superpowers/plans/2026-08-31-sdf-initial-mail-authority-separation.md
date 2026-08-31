# SDF Initial Mail Authority Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate the SDF initial customer-confirmation business authority from Website mail businessstate without changing Website behavior.

**Architecture:** Introduce a dedicated SDF initial-confirmation mail authority, migrate only new SDF confirmation production to it after additive schema and compatibility gates, drain legacy shared SDF jobs without copying or resending them, and preserve stateless shared provider transport only.

**Tech Stack:** PostgreSQL/Supabase migrations, pgTAP, Deno Edge Functions, Resend transport, GitHub Pages repository conventions.

**Spec:** docs/superpowers/specs/2026-08-31-sdf-initial-mail-authority-separation-design.md

## Global Constraints

- Website production authority is frozen. Do not change Website approval, customer confirmation, intake, reminders, quotation, acceptance or project behavior.
- Do not alter `public.quote_request_email_jobs`, its Website constraints/indexes, `public.transition_quote_request_review`, or the existing Website claim/completion/requeue contracts.
- New SDF initial customer confirmations must use only `public.sdf_initial_confirmation_email_jobs`.
- Never use `supabase/functions/_shared/email-delivery.ts` for a new-authority SDF confirmation.
- Never fall back from a new SDF confirmation to `public.quote_request_email_jobs`.
- `public.sdf_qualification_intake_email_jobs` remains unchanged and keeps qualification-only ownership.
- `public.quote_requests` and `confirmation_sent_at` remain the temporary shared request root/projection; every new SDF RPC must enforce `request_kind = 'slimme_documentenflow'` and `record_classification = 'production'`.
- The existing shared automation workqueue, cron and Edge Function remain in place in this phase. They dispatch SDF work but do not own new SDF mail state.
- Shared provider code must be stateless: no database client, table name, product RPC, status transition or lifecycle decision.
- Use one stable provider key, `sdf-initial-confirmation/{job_id}`, for every attempt of one job.
- Legacy SDF shared jobs are never copied. Their current job-id, attempts and `quote-request-email/{job_id}` provider key remain authoritative until drained.
- Historical `sent` and `failed` legacy rows remain untouched. No destructive cleanup is allowed.
- All schema changes are forward-only. The finalization migration is created only after production drain proof and separate authorization.
- Missing or invalid cutover configuration must fail the SDF confirmation branch closed; it must not select shared Website mail authority implicitly.
- Full SDF workqueue/cron/worker separation, operator splitting, customer-request splitting, physical request-root splitting, Offerte voorbereiden, Budget Guard and EMAIL-2B are excluded.

## File Structure

### Files created during local implementation

- `supabase/migrations/20260901040000_add_sdf_initial_confirmation_email_authority_v1.sql`: committed Task-2 additive table and integrity boundary; immutable after checkpoint `f2fc45895936ee7bbeb4b7dc55c2fa7e7de8bbfb`.
- `supabase/migrations/20260901050000_add_sdf_initial_confirmation_mail_authorities_v1.sql`: forward-only Task-3 prepare, claim, lease-validation, completion and retry/failure authorities plus their grants and revokes; consumes but does not redefine the Task-2 table.
- `supabase/functions/_shared/resend-transport.ts`: stateless Resend HTTP transport.
- `supabase/functions/_shared/resend-transport.test.ts`: transport-only Deno tests.
- `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`: pgTAP authority, isolation and cutover-contract tests.
- `scripts/sdf-initial-confirmation-email-concurrency.integration.cjs`: concurrent prepare/claim proof.

### Files modified during local implementation

- `supabase/functions/application-intake-automation/index.ts`: change only the SDF initial-confirmation execution branch; preserve `executeWebsite`, SDF qualification delivery and scheduler handling.
- `supabase/functions/application-intake-automation/handler.test.ts`: preserve dispatcher assertions and add fail-closed SDF mode/result cases.
- `supabase/tests/sdf_qualification_automation_bridge_v1.sql`: replace only assertions that prescribe shared initial-confirmation state; retain qualification lifecycle coverage.

### Deferred file created only after production drain proof

- `supabase/migrations/20260901060000_finalize_sdf_initial_confirmation_email_cutover_v1.sql`: remove temporary legacy selection from the SDF producer without deleting historical rows.

### Explicitly untouched files

- `supabase/functions/_shared/email-delivery.ts`
- `supabase/functions/review-quote-request/index.ts`
- `supabase/migrations/20260901030000_fix_customer_confirmation_partial_conflict_target.sql`
- all Website intake, reminder, quotation, acceptance and project files

## Local Implementation

### Task 1: Lock the Website preservation baseline

**Files:**
- Create: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`
- Modify: none
- Test: `supabase/tests/quote_request_review_partial_conflict_target.sql`, `supabase/tests/request_kind_contract.sql`, `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`

**Interfaces:**
- Consumes: `public.transition_quote_request_review`, `public.quote_request_email_jobs`, existing Website claim/completion/requeue RPCs
- Produces: an executable baseline proving Website semantics before any schema change

- [ ] Start from the approved checkpoint and verify only the spec and plan are locally present:

  ```powershell
  git rev-parse HEAD
  git rev-parse origin/main
  git rev-list --left-right --count HEAD...origin/main
  git status --short --untracked-files=all
  git diff --cached --name-only
  ```

  Expected authority is `2e09dfb3dfff80c4625b36fe3db0462d572680f6`, divergence `0 0`, and empty staging.

- [ ] Create the pgTAP file with `begin`, `create extension if not exists pgtap with schema extensions`, `set local search_path = public, lws_internal, extensions`, `select no_plan()`, and rollback cleanup.

- [ ] Add a Website fixture and assertions that remain valid before and after isolation:

  ```sql
  insert into public.quote_requests (
    id, record_classification, request_kind, name, email, website_type,
    budget, timing, description, privacy_consent, status,
    approval_token_hash, approval_token_expires_at
  ) values (
    'fa210000-0000-4000-8000-000000000001', 'production', 'website',
    'Website preservation', 'website-preservation@example.test', 'business',
    'EUR 3.000', 'flexible', 'Website preservation fixture.', true, 'pending',
    repeat('a', 64), clock_timestamp() + interval '1 day'
  );

  create temporary table website_before as
  select * from public.transition_quote_request_review(repeat('a', 64), 'approved');

  select is((select confirmation_job_status from website_before), 'pending',
    'Website approval still creates its existing pending confirmation');
  select is((select count(*)::integer from public.quote_request_email_jobs
             where quote_request_id = 'fa210000-0000-4000-8000-000000000001'
               and kind = 'customer_confirmation'), 1,
    'Website confirmation remains in Website mail authority');
  select lives_ok(
    $$select * from public.transition_quote_request_review(repeat('a', 64), 'approved')$$,
    'Website approval replay remains idempotent');
  ```

- [ ] Assert that Website `claim_quote_request_email_job`, retryable `complete_quote_request_email_job`, and `requeue_quote_request_email_job` retain the same statuses, attempt progression and provider-id fields. Do not change those RPCs to make the assertions pass.

- [ ] Run the pre-change safety gate:

  ```powershell
  npx supabase test db supabase/tests/quote_request_review_partial_conflict_target.sql
  npx supabase test db supabase/tests/request_kind_contract.sql
  npx supabase test db supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  ```

  Expected: all three PASS. This task intentionally starts with passing characterization tests because it freezes existing Website behavior rather than introducing behavior.

- [ ] Proposed checkpoint commit after review:

  ```powershell
  git add supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  git commit -m "test(mail): lock website confirmation authority"
  ```

### Task 2: Add the isolated SDF mail-state schema

**Files:**
- Create: `supabase/migrations/20260901040000_add_sdf_initial_confirmation_email_authority_v1.sql`
- Modify: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`
- Test: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`

**Interfaces:**
- Consumes: `public.quote_requests(id)` as the temporary neutral request root
- Produces: `public.sdf_initial_confirmation_email_jobs` and its SDF-only integrity boundary

- [ ] First add failing pgTAP assertions for table existence, column types/nullability, primary key, FK, unique `quote_request_id`, RLS, forced RLS and revoked direct privileges:

  ```sql
  select has_table('public', 'sdf_initial_confirmation_email_jobs');
  select col_is_pk('public', 'sdf_initial_confirmation_email_jobs', 'job_id');
  select col_is_unique('public', 'sdf_initial_confirmation_email_jobs', 'quote_request_id');
  select ok((select relrowsecurity and relforcerowsecurity
             from pg_class where oid='public.sdf_initial_confirmation_email_jobs'::regclass),
    'SDF initial confirmation state forces RLS');
  ```

- [ ] Run the focused test and record the expected failure: `relation "public.sdf_initial_confirmation_email_jobs" does not exist`.

  ```powershell
  npx supabase test db supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  ```

- [ ] Create the additive migration with this exact conceptual shape; use named constraints and no shared Website enum:

  ```sql
  create table public.sdf_initial_confirmation_email_jobs (
    job_id uuid primary key default gen_random_uuid(),
    quote_request_id uuid not null unique
      references public.quote_requests(id) on delete restrict,
    template_version text not null default 'SDF_REQUEST_RECEIVED_NL_BE_v1'
      check (template_version = 'SDF_REQUEST_RECEIVED_NL_BE_v1'),
    status text not null default 'pending'
      check (status in ('pending','processing','retry_wait','sent','failed')),
    attempt_count integer not null default 0 check (attempt_count between 0 and 5),
    max_attempts integer not null default 5 check (max_attempts = 5),
    next_attempt_at timestamptz not null default clock_timestamp(),
    locked_at timestamptz,
    delivery_lease_token uuid,
    delivery_lease_expires_at timestamptz,
    sent_at timestamptz,
    provider_message_id text,
    last_error_code text check (last_error_code is null or char_length(last_error_code) <= 120),
    created_at timestamptz not null default clock_timestamp(),
    updated_at timestamptz not null default clock_timestamp()
  );
  ```

- [ ] Add named shape checks: all three lease fields are non-null only for `processing`; all are null outside it; `sent` requires `sent_at`; non-sent insertion cannot supply `sent_at`; and `attempt_count <= max_attempts`.

- [ ] Add only an SDF-table due index on `(status, next_attempt_at, created_at)` restricted to `pending` and `retry_wait`. Do not add or alter an index on `public.quote_request_email_jobs`.

- [ ] Add a `before insert or update of quote_request_id` guard that rejects absent, non-production or non-`slimme_documentenflow` roots with `SDF_INITIAL_CONFIRMATION_REQUEST_REQUIRED`.

- [ ] Enable and force RLS. Revoke all table privileges from `public`, `anon`, `authenticated` and `service_role`; later security-definer RPCs are the only mutation surface.

- [ ] Reset the local database so the migration chain is applied, rerun the focused test, and require PASS:

  ```powershell
  npx supabase db reset
  npx supabase test db supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  ```

- [ ] Proposed checkpoint commit:

  ```powershell
  git add supabase/migrations/20260901040000_add_sdf_initial_confirmation_email_authority_v1.sql supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  git commit -m "feat(sdf): add isolated initial mail state"
  ```

### Task 3: Add SDF prepare, claim, lease and completion authorities

**Files:**
- Create: `supabase/migrations/20260901050000_add_sdf_initial_confirmation_mail_authorities_v1.sql`
- Modify: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`
- Do not modify: `supabase/migrations/20260901040000_add_sdf_initial_confirmation_email_authority_v1.sql`
- Test: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`

**Interfaces:**
- Consumes: a valid `SDF_CONFIRMATION` automation work lease and production SDF request
- Produces: `prepare_sdf_initial_confirmation_v2`, `claim_sdf_initial_confirmation_email_job_v1`, `validate_sdf_initial_confirmation_email_delivery_v1`, `complete_sdf_initial_confirmation_email_job_v1`

- [ ] Add failing `has_function` and behavior tests for these exact signatures:

  ```sql
  public.prepare_sdf_initial_confirmation_v2(bigint, uuid)
  public.claim_sdf_initial_confirmation_email_job_v1(uuid)
  public.validate_sdf_initial_confirmation_email_delivery_v1(uuid, uuid)
  public.complete_sdf_initial_confirmation_email_job_v1(
    uuid, uuid, boolean, boolean, text, text
  )
  ```

  The completion parameters are `job_id`, `delivery_lease_token`, `succeeded`, `retryable`, `error_code`, `provider_message_id`. Mail completion is authorized exclusively by the mail lease; it does not consume or own a work claim.

- [ ] Assert the initial failure is missing functions, then add all four functions to the new forward-only `20260901050000_add_sdf_initial_confirmation_mail_authorities_v1.sql` migration. Consume the table created by committed Task-2 migration `20260901040000_add_sdf_initial_confirmation_email_authority_v1.sql`; do not redefine or modify that migration.

- [ ] Implement `prepare_sdf_initial_confirmation_v2` with this transaction order:

  ```sql
  select * from lws_internal.application_intake_automation_work
   where work_id=p_work_id and claim_token=p_work_claim_token
     and claim_expires_at>clock_timestamp() and phase='SDF_CONFIRMATION'
   for update;
  select * from public.quote_requests
   where id=v_work.quote_request_id
     and request_kind='slimme_documentenflow'
     and record_classification='production'
   for update;
  ```

  Return no authority for an invalid lease or wrong product. Return `already_sent` when `confirmation_sent_at` exists. During compatibility, check for an existing shared SDF `customer_confirmation` before inserting the new row and return `authority_source='legacy'` with that exact legacy job-id. Otherwise insert on `quote_request_id`, `on conflict (quote_request_id) do nothing`, then return `authority_source='sdf_initial'` and the canonical row.

- [ ] Define the prepare result consistently everywhere:

  ```text
  outcome, authority_source, job_id, job_status, next_attempt_at,
  request_name, request_email, application_reference, created_at,
  request_kind, template_version
  ```

  Allowed `authority_source` values are only `legacy` and `sdf_initial`; `already_sent` has no delivery job.

- [ ] Implement claim with row locking and one ten-minute lease. Before selecting a claim, convert an expired `processing` job to `retry_wait` with `STALE_PROCESSING_LEASE` when attempts remain, or `failed` with `STALE_PROCESSING_LEASE_EXHAUSTED` at attempt 5. Claim only due `pending`/`retry_wait` rows and increment `attempt_count` once.

- [ ] Return recipientdata by joining `public.quote_requests`; never persist name, email, reference or body in the SDF job table. Recheck request kind/classification in the claim query.

- [ ] Implement validation as a stable boolean check requiring `status='processing'`, matching lease-token, unexpired lease, SDF request kind/classification and canonical template.

- [ ] Implement completion so only the current unexpired mail lease can mutate. Use this exact status decision:

  ```sql
  case
    when p_succeeded then 'sent'
    when p_retryable and attempt_count < max_attempts then 'retry_wait'
    else 'failed'
  end
  ```

  For retry, compute `30 * 2^(attempt_count - 1)` seconds capped at 3600. On `failed`, set the matching production-SDF workrow to `MANUAL_REVIEW`; terminal mail state invalidates SDF confirmation dispatch regardless of work-claim age. On retry, mutate only the mail job. Do not consume, clear or overwrite a work claim from completion.

- [ ] Make `prepare_sdf_initial_confirmation_v2`, which receives the current work-id/token, the only SDF RPC allowed to synchronize a non-terminal work claim with existing mail state. If the canonical mailjob is actively `processing`, release that same current work claim and defer it until `delivery_lease_expires_at`; if the job is non-due `retry_wait`, release that same claim and defer it until the job's `next_attempt_at`; if it is `failed`, move only its matching SDF workrow to `MANUAL_REVIEW`. Match both `p_work_id` and `p_work_claim_token` in every non-terminal work update so a newer claim is never cleared. This reconciles the 90-second work lease with the ten-minute mail lease while leaving mail completion authorized only by the mail lease.

- [ ] Revoke all four functions from `public`, `anon` and `authenticated`. Grant execute only to `service_role`.

- [ ] Add tests for wrong request kind, internal fixture rejection, invalid/expired work lease, idempotent prepare, due claim, non-due refusal, wrong lease validation, expired lease recovery, retry progression and terminal attempt 5.

- [ ] Apply the full migration chain, including the new forward-only Task-3 migration, from a clean local reset and require the focused pgTAP test to PASS.

- [ ] Proposed checkpoint commit:

  ```powershell
  git add supabase/migrations/20260901050000_add_sdf_initial_confirmation_mail_authorities_v1.sql supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  git commit -m "feat(sdf): add initial mail delivery authority"
  ```

### Task 4: Prove semantic and concurrent duplicate protection

**Files:**
- Create: `scripts/sdf-initial-confirmation-email-concurrency.integration.cjs`
- Modify: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`
- Test: both files

**Interfaces:**
- Consumes: SDF prepare/claim/validate/complete RPCs
- Produces: deterministic proof of one semantic job, one live lease and one provider identity

- [ ] Add failing pgTAP assertions that two sequential prepare calls return the same `job_id`, leave one SDF row and leave zero SDF `customer_confirmation` rows in `public.quote_request_email_jobs`.

- [ ] Build the concurrency script from `scripts/sdf-qualification-delivery-reissue-concurrency.integration.cjs`: use the local container `supabase_db_xcsptvntvrizwhskaphr`, fixed UUID fixtures, `application_name` markers, `pg_blocking_pids`, and `finally` cleanup.

- [ ] Run two `prepare_sdf_initial_confirmation_v2` transactions for the same request and assert:

  ```js
  if (summary.job_count !== 1) throw new Error("DUPLICATE_SEMANTIC_CONFIRMATION");
  if (summary.distinct_job_ids !== 1) throw new Error("UNSTABLE_JOB_ID");
  if (summary.shared_confirmation_count !== 0) throw new Error("SHARED_SDF_JOB_CREATED");
  ```

- [ ] Run two concurrent claim calls and prove exactly one receives a lease. Validate that a spoofed token returns false and cannot complete.

- [ ] Model provider acceptance before database completion by leaving the first lease in `processing`, expiring it, reclaiming the same job and asserting the derived provider key remains exactly `sdf-initial-confirmation/{same_job_id}`. Do not claim database-level exactly-once delivery; the invariant is stable provider idempotency plus no send after durable `sent`.

- [ ] Complete successfully, then prove all later claims return zero rows and the job-id never changes.

- [ ] Run and require PASS:

  ```powershell
  npx supabase test db supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  node scripts/sdf-initial-confirmation-email-concurrency.integration.cjs
  ```

- [ ] Proposed checkpoint commit:

  ```powershell
  git add supabase/tests/sdf_initial_confirmation_email_authority_v1.sql scripts/sdf-initial-confirmation-email-concurrency.integration.cjs
  git commit -m "test(sdf): prove initial mail concurrency safety"
  ```

### Task 5: Project successful SDF completion without mail ownership duplication

**Files:**
- Create: none
- Modify: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`, `supabase/tests/sdf_qualification_automation_bridge_v1.sql`
- Test: both pgTAP files

**Forward-only prerequisite:** Hard-stop before Task 5 implementation until a separate forward-only migration path after `20260901050000` and before `20260901060000` is explicitly approved. Do not modify committed migration `20260901040000` or the Task-3-only migration `20260901050000`.

**Interfaces:**
- Consumes: durable `sent_at` from the new SDF job
- Produces: one-way `quote_requests.confirmation_sent_at` projection and existing `SDF_INTAKE` scheduling

- [ ] First add failing tests proving that successful SDF completion sets `quote_requests.confirmation_sent_at` to the new job's `sent_at`, changes the matching work phase once to `SDF_INTAKE`, and sets qualification invitation due time to `sent_at + interval '120 seconds'`.

- [ ] Add `lws_internal.advance_sdf_automation_from_initial_confirmation_v1` and a trigger only on `public.sdf_initial_confirmation_email_jobs`. Guard all work with a join that requires production SDF. Use:

  ```sql
  update public.quote_requests
     set confirmation_sent_at=coalesce(confirmation_sent_at,new.sent_at)
   where id=new.quote_request_id
     and request_kind='slimme_documentenflow'
     and record_classification='production';
  ```

- [ ] Reuse the existing downstream `advance_sdf_automation_after_confirmation_v1` projection from `quote_requests.confirmation_sent_at`; do not duplicate Website mail completion logic and do not add a trigger to `public.quote_request_email_jobs`.

- [ ] Prove that replaying completion or an update with unchanged `sent_at` does not advance twice, create a qualification job, or alter a Website request.

- [ ] Update only the old bridge assertions that locate SDF initial confirmation in the shared table. Keep all qualification invitation, submission, reissue and quotation-preparation assertions intact.

- [ ] Run both focused suites and require PASS:

  ```powershell
  npx supabase test db supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  npx supabase test db supabase/tests/sdf_qualification_automation_bridge_v1.sql
  ```

- [ ] Proposed checkpoint commit:

  ```powershell
  git add supabase/tests/sdf_initial_confirmation_email_authority_v1.sql supabase/tests/sdf_qualification_automation_bridge_v1.sql
  git commit -m "feat(sdf): project isolated confirmation completion"
  ```

### Task 6: Add stateless Resend transport

**Files:**
- Create: `supabase/functions/_shared/resend-transport.ts`, `supabase/functions/_shared/resend-transport.test.ts`
- Modify: none
- Test: `supabase/functions/_shared/resend-transport.test.ts`

**Interfaces:**
- Consumes: provider configuration, email payload and caller-owned idempotency key
- Produces: technical provider result only; no businessstate mutation

- [ ] Write failing Deno tests for HTTP 2xx, 408, 425, 429, 4xx, 5xx, timeout, network error, missing configuration and header sanitization.

- [ ] Fix the transport interface before implementation:

  ```ts
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

  export interface ResendTransportResult {
    accepted: boolean;
    retryable: boolean;
    errorCode: string | null;
    providerMessageId: string | null;
  }
  ```

- [ ] Implement `sendEmailViaResend(input, fetchImpl = fetch)` with no Supabase import, no database client, no RPC name, no table name and no Website/SDF status. It may classify only technical outcomes.

- [ ] Require the caller-supplied idempotency key verbatim after CR/LF rejection. Do not construct product keys inside the generic helper.

- [ ] Assert that the fake fetch receives `Idempotency-Key: sdf-initial-confirmation/fa240000-0000-4000-8000-000000000001` and that a 2xx response exposes only `providerMessageId` and technical flags.

- [ ] Run the test before implementation and expect import/module failure, then implement and require PASS:

  ```powershell
  deno test --allow-env --allow-net supabase/functions/_shared/resend-transport.test.ts
  ```

- [ ] Proposed checkpoint commit:

  ```powershell
  git add supabase/functions/_shared/resend-transport.ts supabase/functions/_shared/resend-transport.test.ts
  git commit -m "refactor(mail): add stateless resend transport"
  ```

### Task 7: Add the compatible Edge delivery path

**Files:**
- Create: none
- Modify: `supabase/functions/application-intake-automation/index.ts`, `supabase/functions/application-intake-automation/handler.test.ts`
- Test: `supabase/functions/application-intake-automation/handler.test.ts`, `supabase/functions/_shared/resend-transport.test.ts`

**Interfaces:**
- Consumes: `SDF_INITIAL_CONFIRMATION_AUTHORITY_MODE`, prepare authority source, SDF delivery lease and stateless transport
- Produces: `EmailDeliveryResult` for the unchanged dispatcher counters

- [ ] Add failing handler tests for the unchanged phase dispatch and for these SDF mode outcomes: explicit `legacy` routes only an existing legacy authority; explicit `isolated` routes `sdf_initial`; missing/unknown mode returns a failed SDF result without invoking either mailauthority. Website dispatch must still execute under every SDF mode value.

- [ ] In `index.ts`, parse only `SDF_INITIAL_CONFIRMATION_AUTHORITY_MODE` with allowed values `legacy` and `isolated`. Do not include this variable in global `configurationReady`, because invalid SDF configuration must not stop Website work.

- [ ] Define missing or invalid mode behavior exactly: `executeSdfConfirmation` throws `SDF_INITIAL_CONFIRMATION_MODE_INVALID` before calling any prepare, shared mail, SDF mail or provider function. The existing handler catch invokes `fail_application_intake_automation_work_v1` with `WORKER_INTERRUPTED` and `p_retryable=true`, so only that SDF workrow receives the existing workqueue backoff. The HTTP invocation continues processing other claims, including Website claims. No mail row is created or mutated and no provider call occurs.

- [ ] Preserve the current `executeWebsite` function byte-for-byte. Keep `deliverEmailJob` imported solely for Website and temporary legacy SDF jobs.

- [ ] In `legacy` mode, call only `execute_application_intake_automation_sdf_confirmation_v1` and existing `deliverEmailJob`. This mode exists only for the compatible deployment before cutover.

- [ ] In `isolated` mode, call `prepare_sdf_initial_confirmation_v2`. Handle outcomes exactly:

  ```text
  already_sent       -> sent, no provider call
  legacy             -> existing deliverEmailJob with the returned legacy job_id
  sdf_initial/due    -> claim, validate, stateless send, complete
  sdf_initial/deferred or processing -> retry_wait, no provider call
  sdf_initial/failed -> failed, no provider call
  anything else      -> fail closed, no provider call
  ```

- [ ] For `sdf_initial/due`, derive `sdf-initial-confirmation/${jobId}`, validate the lease immediately before `sendEmailViaResend`, then pass only the technical result, job-id and mail lease-token to `complete_sdf_initial_confirmation_email_job_v1`. The completion call must not receive the work-id or work-token.

- [ ] Do not retry through `deliverEmailJob` when the new path fails. RPC, template, lease or transport ambiguity returns `failed` or schedules within the SDF authority only.

- [ ] Keep `executeSdfInvitation` and `executeQueuedSdfEmail` unchanged; qualification-mail separation is outside scope.

- [ ] Run focused Deno tests and type-check the deployed entrypoint:

  ```powershell
  deno test --allow-env --allow-net supabase/functions/application-intake-automation/handler.test.ts supabase/functions/_shared/resend-transport.test.ts
  deno check supabase/functions/application-intake-automation/index.ts
  ```

- [ ] Rerun the Website pgTAP baseline after the shared Edge file changes:

  ```powershell
  npx supabase test db supabase/tests/quote_request_review_partial_conflict_target.sql
  npx supabase test db supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  ```

- [ ] Proposed checkpoint commit:

  ```powershell
  git add supabase/functions/application-intake-automation/index.ts supabase/functions/application-intake-automation/handler.test.ts
  git commit -m "feat(sdf): route initial mail through isolated authority"
  ```

### Task 8: Make legacy drain exclusive and race-safe

**Files:**
- Create: none
- Modify: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`, `scripts/sdf-initial-confirmation-email-concurrency.integration.cjs`
- Test: both test files

**Forward-only prerequisite:** Hard-stop before Task 8 implementation until its compatibility SQL receives a separate forward-only migration path after `20260901050000` and before `20260901060000`. Do not modify committed migration `20260901040000` or the Task-3-only migration `20260901050000`.

**Interfaces:**
- Consumes: existing SDF `customer_confirmation` rows in `public.quote_request_email_jobs`
- Produces: one exclusive authority source per request during cutover

- [ ] Add fixtures for every legacy state: `sent`, `failed`, `pending`, `retry_wait`, `processing`. Snapshot all columns before invoking v2.

- [ ] Assert the exact policy:

  ```text
  sent       -> already_sent; historical row unchanged; no new SDF row
  failed     -> manual_review; historical row unchanged; no new SDF row
  pending    -> legacy; same legacy job_id; no new SDF row
  retry_wait -> legacy; same job_id/attempt_count/next_attempt_at; no new SDF row
  processing -> legacy; same job_id/lock/stale-recovery contract; no new SDF row
  no row     -> sdf_initial; exactly one new SDF row
  ```

- [ ] In the foundation migration, replace only the SDF-specific `execute_application_intake_automation_sdf_confirmation_v1` body to lock the same request row and fail closed when a new SDF initial job already exists. Preserve its return signature for old Edge instances. Do not modify shared Website tables, indexes or delivery RPCs.

- [ ] Extend the concurrency script with the rollout race: hold producer-v1 after request lock acquisition, start producer-v2, release v1, and prove v2 selects the legacy row; reverse the order and prove producer-v1 creates no shared row after v2 has created the SDF row.

- [ ] Ensure legacy delivery uses the existing `quote-request-email/{legacy_job_id}` key. Never derive the new namespace for a legacy job.

- [ ] Assert historical rows are byte-identical after preparation. Delivery tests may mutate active legacy statuses only through the existing claim/completion path.

- [ ] Run and require PASS:

  ```powershell
  npx supabase test db supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  node scripts/sdf-initial-confirmation-email-concurrency.integration.cjs
  ```

- [ ] Proposed checkpoint commit:

  ```powershell
  git add supabase/tests/sdf_initial_confirmation_email_authority_v1.sql scripts/sdf-initial-confirmation-email-concurrency.integration.cjs
  git commit -m "feat(sdf): guard legacy initial mail drain"
  ```

### Task 9: Prove cross-product isolation

**Files:**
- Create: none
- Modify: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`, `supabase/tests/sdf_qualification_automation_bridge_v1.sql`, `supabase/functions/application-intake-automation/handler.test.ts`
- Test: all three files plus the existing Website regression test

**Interfaces:**
- Consumes: complete Website and new SDF mail authorities
- Produces: bidirectional negative preservation proof

- [ ] Add a Website-table snapshot containing row count plus ordered JSON of ids, statuses, attempts, due times, locks and errors. Run SDF prepare, retry and terminal failure, then assert the snapshot is unchanged.

- [ ] Add an SDF-table snapshot, run Website approval, claim, retryable completion and requeue, then assert the SDF snapshot is unchanged.

- [ ] Assert a Website request passed to every SDF RPC returns no authority and performs no mutation.

- [ ] Assert a new SDF `job_id` passed to existing Website claim, completion and requeue RPCs returns no row/false and leaves the SDF row unchanged.

- [ ] Verify catalog isolation with concrete predicates:

  ```sql
  select ok(not exists (
    select 1 from pg_indexes
    where tablename='quote_request_email_jobs'
      and indexdef ilike '%sdf_initial_confirmation%'
  ), 'Website indexes contain no SDF initial authority');

  select ok(
    not (pg_get_functiondef('public.transition_quote_request_review(text,text)'::regprocedure)
      ilike '%sdf_initial_confirmation_email_jobs%'),
    'Website review contains no SDF authority dependency'
  );
  ```

- [ ] In Deno tests, prove the stateless transport has no Supabase dependency and `executeWebsite` receives the same claim and returns the same counters under legacy, isolated and invalid SDF modes.

- [ ] Run the complete focused isolation set:

  ```powershell
  npx supabase test db supabase/tests/quote_request_review_partial_conflict_target.sql
  npx supabase test db supabase/tests/request_kind_contract.sql
  npx supabase test db supabase/tests/sdf_initial_confirmation_email_authority_v1.sql
  npx supabase test db supabase/tests/sdf_qualification_automation_bridge_v1.sql
  deno test --allow-env --allow-net supabase/functions/application-intake-automation/handler.test.ts supabase/functions/_shared/resend-transport.test.ts
  node scripts/sdf-initial-confirmation-email-concurrency.integration.cjs
  ```

- [ ] Proposed checkpoint commit:

  ```powershell
  git add supabase/tests/sdf_initial_confirmation_email_authority_v1.sql supabase/tests/sdf_qualification_automation_bridge_v1.sql supabase/functions/application-intake-automation/handler.test.ts
  git commit -m "test(mail): prove website sdf isolation"
  ```

### Task 10: Establish local parity and release readiness

**Files:**
- Create: none
- Modify: none
- Test: full migration chain and all scoped tests

**Interfaces:**
- Consumes: the complete local implementation diff
- Produces: a reviewable local checkpoint; no production mutation

- [ ] Rebuild from the full migration chain:

  ```powershell
  npx supabase db reset
  ```

- [ ] Run focused pgTAP, Deno and concurrency checks from Task 9, then run the repository-wide database suite:

  ```powershell
  npx supabase test db
  deno test --allow-env --allow-net supabase/functions/application-intake-automation/handler.test.ts supabase/functions/_shared/resend-transport.test.ts
  node scripts/sdf-initial-confirmation-email-concurrency.integration.cjs
  ```

- [ ] Inspect the final diff and enforce scope:

  ```powershell
  git diff --check
  git diff --stat
  git status --short --untracked-files=all
  git diff --cached --name-only
  ```

  Allowed implementation files are exactly those listed under File Structure, excluding the deferred finalization migration.

- [ ] Verify by text search that the new SDF Edge branch does not call `claim_quote_request_email_job`, `complete_quote_request_email_job`, `requeue_quote_request_email_job` or read `quote_request_email_jobs` when `authority_source='sdf_initial'`.

- [ ] Verify `public.transition_quote_request_review(text,text)` and the Website partial unique index definitions are unchanged from checkpoint `2e09dfb3dfff80c4625b36fe3db0462d572680f6`.

- [ ] Record a local evidence summary containing exact test counts, migration chain result, changed files and unresolved legacy-row counts as unknown until production preflight.

- [ ] Do not deploy. Present the local checkpoint for user review and explicit release authorization.

## Local Checkpoint

The local checkpoint is reached only after Tasks 1 through 10 pass. It contains implementation and tests but no production mutation. Proposed commits remain small and task-scoped; do not squash them into a deployment commit. The approved design and this plan should be committed separately as documentation before or with the first local test checkpoint, never mixed into a production deployment operation.

## Deferred Release Runbook

Every task below requires a new, explicit user authorization. Do not execute any release step as part of local implementation.

### Task 11: Controlled production schema release

**Files:**
- Create: none
- Modify: none
- Test: production read-only preflight and migration verification

**Interfaces:**
- Consumes: approved local checkpoint and forward-only migrations `20260901040000` and `20260901050000`; hard-stop unless later SQL tasks have separately approved forward-only migrations
- Produces: additive production schema with no active producer switch

- [ ] Re-run the exact preservation gate against the then-current approved production SHA.
- [ ] Query production read-only counts of legacy SDF `customer_confirmation` rows grouped by `status`; list each active job-id, attempt count, next-attempt time and lock age.
- [ ] Hard-stop if a legacy `sent` row has null `quote_requests.confirmation_sent_at`, if one request has more than one semantic confirmation, or if an active row cannot be tied to a production SDF request.
- [ ] Apply `20260901040000_add_sdf_initial_confirmation_email_authority_v1.sql` followed by `20260901050000_add_sdf_initial_confirmation_mail_authorities_v1.sql` through the repository's approved Supabase release procedure, together with any separately approved forward-only migrations required by later SQL tasks. Do not deploy Edge in this task.
- [ ] Verify read-only that the new table/RPCs exist, contain zero rows, all legacy rows are unchanged, and a Website smoke transaction rolls back successfully.
- [ ] Record schema release evidence separately from code deployment evidence.

### Task 12: Compatible Edge release

**Files:**
- Create: none
- Modify: none
- Test: production function health and Website preservation probes

**Interfaces:**
- Consumes: additive production schema and reviewed Edge artifact
- Produces: a worker capable of both explicit legacy drain and isolated authority, still operating in `legacy` mode

- [ ] Set `SDF_INITIAL_CONFIRMATION_AUTHORITY_MODE=legacy` explicitly before deploying the compatible Edge artifact. Missing mode is not accepted as legacy.
- [ ] Deploy only `application-intake-automation`; do not alter cron, Website functions or database objects.
- [ ] Verify Website work continues and an existing legacy SDF job retains the same table, job-id and provider namespace.
- [ ] Verify no row exists yet in `public.sdf_initial_confirmation_email_jobs` as a consequence of compatibility deployment alone.
- [ ] Hard-stop on any Website counter, retry or delivery regression.

### Task 13: Producer cutover

**Files:**
- Create: none
- Modify: none
- Test: one controlled post-cutover SDF request plus Website preservation

**Interfaces:**
- Consumes: compatible Edge release and additive SDF authority
- Produces: new SDF requests routed to isolated mail state

- [ ] Reconfirm the legacy inventory immediately before activation.
- [ ] Set `SDF_INITIAL_CONFIRMATION_AUTHORITY_MODE=isolated`; do not change any Website configuration.
- [ ] Submit one controlled SDF request and prove exactly one new SDF job, zero shared SDF `customer_confirmation` rows, canonical template, stable job-id and provider key.
- [ ] Prove one Website approval still creates and delivers through `public.quote_request_email_jobs` with unchanged semantics.
- [ ] If the SDF probe fails, stop new SDF confirmation processing fail-closed. Do not set mode back to `legacy` for requests that have a new SDF job and do not create a shared fallback row.

### Task 14: Legacy drain and production isolation proof

**Files:**
- Create: none
- Modify: none
- Test: read-only production evidence

**Interfaces:**
- Consumes: pre-cutover legacy rows and post-cutover isolated rows
- Produces: proof that active legacy delivery is exhausted without copying

- [ ] Monitor each pre-cutover `pending`, `retry_wait` and `processing` row by its original job-id until it reaches `sent` or terminal `failed`.
- [ ] Prove no legacy row was copied to the new table and no request owns both authorities.
- [ ] Prove every post-cutover SDF confirmation exists only in the new table.
- [ ] Prove historical `sent`/`failed` rows are byte-unchanged except active legacy rows changed through their existing delivery lifecycle.
- [ ] Require zero legacy `pending`, `retry_wait` and `processing` rows; require every legacy failed request's workrow to remain `MANUAL_REVIEW`.
- [ ] Repeat Website customer confirmation, retry and approval preservation checks.
- [ ] Publish the production isolation evidence for user approval before finalization.

### Task 15: Finalize legacy removal after separate approval

**Files:**
- Create: `supabase/migrations/20260901060000_finalize_sdf_initial_confirmation_email_cutover_v1.sql`
- Modify: `supabase/tests/sdf_initial_confirmation_email_authority_v1.sql`, `supabase/functions/application-intake-automation/index.ts`, `supabase/functions/application-intake-automation/handler.test.ts`
- Test: focused isolation suite and full migration chain

**Interfaces:**
- Consumes: approved zero-active-legacy proof
- Produces: SDF producer with no runtime dependency on Website mail businessstate

- [ ] First add failing tests that reject `authority_source='legacy'`, reject `legacy` mode, and prove the SDF producer never reads or returns a shared confirmation job.
- [ ] Create the finalization migration only now. It must hard-stop unless no legacy SDF rows are active and no unresolved pre-cutover SDF work lacks an authority.
- [ ] Replace `prepare_sdf_initial_confirmation_v2` so it returns only `already_sent` or `sdf_initial` and never reads `public.quote_request_email_jobs`.
- [ ] Remove the temporary producer-v1 compatibility body and legacy Edge branch without deleting historical rows or modifying Website functions.
- [ ] Require `isolated` mode or remove the mode entirely in favor of unconditional isolated routing; missing configuration must never restore legacy behavior.
- [ ] Run `npx supabase db reset`, the complete focused suite, all database tests, Deno tests and concurrency test.
- [ ] Treat finalization as a separate implementation/release checkpoint and obtain new production authorization.

## Commit Strategy

Use the proposed checkpoint commits in Tasks 1 through 9. Task 10 is validation-only. Do not combine schema foundation, Edge compatibility, producer activation or production evidence into one commit. The deferred finalization migration receives its own commit only after Task 14 evidence is approved.

## Release Boundaries

1. **LOCAL IMPLEMENTATION:** Tasks 1 through 9; no production access.
2. **LOCAL CHECKPOINT:** Task 10; full local proof and scoped diff review.
3. **RELEASE READINESS:** user reviews local evidence and explicitly authorizes release.
4. **CONTROLLED PRODUCTION SCHEMA RELEASE:** Task 11; additive schema only.
5. **COMPATIBLE EDGE RELEASE:** Task 12; explicit legacy mode.
6. **PRODUCER CUTOVER:** Task 13; explicit isolated mode.
7. **LEGACY DRAIN PROOF:** first half of Task 14.
8. **PRODUCTION ISOLATION PROOF:** completion of Task 14.
9. **FINALIZATION:** Task 15 under a new authorization; no destructive row cleanup.

## Plan Self-Review

- **Spec coverage:** every design section maps to at least one numbered task; acceptance criteria map to Tasks 2 through 10 and release Tasks 11 through 15.
- **Placeholder scan:** all interfaces, object names, statuses, files, commands, cutover modes and expected outcomes are explicit.
- **Type/name consistency:** the table is always `public.sdf_initial_confirmation_email_jobs`; producer is always `prepare_sdf_initial_confirmation_v2`; claim, validate and completion names match the approved design.
- **Scope:** only the SDF initial customer-confirmation authority is changed. Qualification mail, root ingress, admin notification, workqueue, cron and operator boundaries remain outside scope.
- **Website preservation:** Website businessobjects are untouched; the shared Edge entrypoint is guarded by before/after Website tests and its Website executor remains unchanged.
- **Cutover safety:** one request selects exactly one authority; old and new producers lock the same request row; legacy jobs retain identity; new jobs never fall back; finalization waits for zero active legacy rows.
- **TDD:** each behavior-changing task introduces or changes a failing test before its minimal implementation and reruns the narrowest check immediately afterward.
- **No big bang:** schema, Edge compatibility, activation, drain proof and finalization are separate checkpoints with separate authorization boundaries.
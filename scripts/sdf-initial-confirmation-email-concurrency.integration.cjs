const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const quoteRequestId = "db200000-0000-4000-8000-000000000001";
const workClaimToken = "db210000-0000-4000-8000-000000000001";
const claimedBy = "db220000-0000-4000-8000-000000000001";
const spoofedLeaseToken = "db230000-0000-4000-8000-000000000099";
const websiteControlRequestId = "db200003-0000-4000-8000-000000000004";
const websiteControlJobId = "db240003-0000-4000-8000-000000000004";

function query(sql) {
  const result = spawnSync("docker", [...baseArgs, "-c", sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) || "";
}

function run(sql) {
  return new Promise((resolve) => {
    const child = spawn("docker", [...baseArgs, "-c", sql]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => stdout += data);
    child.stderr.on("data", (data) => stderr += data);
    child.on("exit", (code) => resolve({ code, stdout, stderr }));
  });
}

function startHoldingTransaction({ applicationName, sql, marker }) {
  const child = spawn("docker", baseArgs);
  let stdout = "";
  let stderr = "";
  let settled = false;
  let readyResolve;
  let readyReject;
  const ready = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });
  const timeout = setTimeout(() => {
    if (!settled) readyReject(new Error(`${marker}_TIMEOUT:${stderr || stdout}`));
  }, 5000);
  child.stdout.on("data", (data) => {
    stdout += data;
    if (!settled && stdout.includes(marker)) {
      settled = true;
      clearTimeout(timeout);
      readyResolve();
    }
  });
  child.stderr.on("data", (data) => stderr += data);
  const exited = new Promise((resolve) => child.on("exit", (code) => {
    if (!settled) {
      settled = true;
      clearTimeout(timeout);
      readyReject(new Error(`${marker}_EXITED:${code}:${stderr || stdout}`));
    }
    resolve({ code, stdout, stderr });
  }));
  child.stdin.write(`
    set application_name = '${applicationName}';
    begin;
    set local role service_role;
    ${sql}
    select '${marker}';
  `);
  return {
    ready,
    release: async () => {
      child.stdin.end("commit;\n");
      return await exited;
    },
    abort: async () => {
      if (child.exitCode === null) child.stdin.end("rollback;\n");
      return await exited;
    },
  };
}

function parseJsonRows(output) {
  return output.split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith("{") && line.endsWith("}"))
    .map((line) => JSON.parse(line));
}

async function proveBlocked(waitingApplication, blockingApplication, errorCode) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (query(`
      select exists (
        select 1
        from pg_stat_activity as waiting
        join pg_stat_activity as blocker
          on blocker.pid = any(pg_blocking_pids(waiting.pid))
        where waiting.application_name = '${waitingApplication}'
          and blocker.application_name = '${blockingApplication}'
          and waiting.wait_event_type = 'Lock'
      )
    `) === "t") return;
  }
  throw new Error(errorCode);
}

function websiteMailSnapshot() {
  return JSON.parse(query(`
    select json_build_object(
      'row_count', count(*)::integer,
      'content_digest', coalesce(
        md5(string_agg(to_jsonb(job)::text, '|' order by job.id)),
        md5('')
      )
    )
    from public.quote_request_email_jobs as job
    where job.quote_request_id = '${websiteControlRequestId}'
  `));
}

function cleanup() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from public.sdf_initial_confirmation_email_jobs
    where quote_request_id = '${quoteRequestId}';
    delete from public.quote_request_email_jobs
    where quote_request_id in (
      '${quoteRequestId}', '${websiteControlRequestId}'
    );
    delete from lws_internal.application_intake_automation_work
    where quote_request_id in (
      '${quoteRequestId}', '${websiteControlRequestId}'
    );
    delete from lws_internal.operator_dossier_assignments
    where quote_request_id in (
      '${quoteRequestId}', '${websiteControlRequestId}'
    );
    delete from lws_internal.operator_dossier_states
    where quote_request_id in (
      '${quoteRequestId}', '${websiteControlRequestId}'
    );
    delete from lws_internal.dossier_identity_anchors
    where quote_request_id in (
      '${quoteRequestId}', '${websiteControlRequestId}'
    );
    delete from public.quote_requests
    where id in (
      '${quoteRequestId}', '${websiteControlRequestId}'
    );
    commit;
  `);
}

async function main() {
  let prepareHolder = null;
  let prepareWaiter = null;
  let claimHolder = null;
  let claimWaiter = null;

  if (query("select current_database()") !== "postgres") {
    throw new Error("LOCAL_TEST_ENVIRONMENT_REQUIRED");
  }
  if (query("select to_regprocedure('public.execute_application_intake_automation_sdf_confirmation_v1(bigint,uuid)') is null") !== "t") {
    throw new Error("LEGACY_SDF_PRODUCER_STILL_EXISTS");
  }

  try {
    cleanup();
    query(`
      insert into public.quote_requests (
        id, record_classification, request_kind, sdf_package, name, email,
        description, privacy_consent, status, approval_token_hash,
        approval_token_expires_at
      ) values (
        '${quoteRequestId}', 'production', 'slimme_documentenflow', 'start',
        'SDF initial mail concurrency', 'sdf-initial-concurrency@example.test',
        'Local Task-4 concurrency fixture.', true, 'pending', repeat('8', 64),
        clock_timestamp() + interval '1 day'
      );

      insert into lws_internal.application_intake_automation_work (
        quote_request_id, phase, approval_due_at, next_attempt_at,
        claim_token, claimed_by, claimed_at, claim_expires_at
      ) values (
        '${quoteRequestId}', 'SDF_CONFIRMATION', clock_timestamp(), clock_timestamp(),
        '${workClaimToken}', '${claimedBy}', clock_timestamp(),
        clock_timestamp() + interval '10 minutes'
      );

      insert into public.quote_requests (
        id, record_classification, request_kind, name, email, website_type,
        budget, timing, description, privacy_consent, status,
        approval_token_hash, approval_token_expires_at
      ) values (
        '${websiteControlRequestId}', 'production', 'website',
        'Website rollout control', 'website-rollout-control@example.test',
        'Website op maat', 'EUR 3.000 - 6.000', 'Binnen 2-3 maanden',
        'Ordinary Website preservation fixture.', true, 'pending',
        repeat('5', 64), clock_timestamp() + interval '1 day'
      );

      insert into public.quote_request_email_jobs (
        id, quote_request_id, kind, status, next_attempt_at
      ) values (
        '${websiteControlJobId}', '${websiteControlRequestId}',
        'customer_confirmation', 'pending', clock_timestamp()
      );
    `);

    const workId = query(`
      select work_id
      from lws_internal.application_intake_automation_work
      where quote_request_id = '${quoteRequestId}'
    `);
    const websiteBefore = websiteMailSnapshot();

    prepareHolder = startHoldingTransaction({
      applicationName: "sdf_initial_prepare_winner",
      marker: "PREPARE_HELD",
      sql: `
        select row_to_json(prepared)::text
        from public.prepare_sdf_initial_confirmation_v2(
          ${workId}, '${workClaimToken}'
        ) as prepared;
      `,
    });
    await prepareHolder.ready;

    prepareWaiter = run(`
      set application_name = 'sdf_initial_prepare_waiter';
      begin;
      set local role service_role;
      select row_to_json(prepared)::text
      from public.prepare_sdf_initial_confirmation_v2(
        ${workId}, '${workClaimToken}'
      ) as prepared;
      commit;
    `);
    await proveBlocked(
      "sdf_initial_prepare_waiter",
      "sdf_initial_prepare_winner",
      "CONCURRENT_PREPARE_LOCK_WAIT_NOT_PROVEN",
    );

    const prepareWinnerResult = await prepareHolder.release();
    prepareHolder = null;
    const prepareWaiterResult = await prepareWaiter;
    prepareWaiter = null;
    if (prepareWinnerResult.code !== 0) {
      throw new Error(`PREPARE_WINNER_FAILED:${JSON.stringify(prepareWinnerResult)}`);
    }
    if (prepareWaiterResult.code !== 0) {
      throw new Error(`PREPARE_WAITER_FAILED:${JSON.stringify(prepareWaiterResult)}`);
    }

    const prepareWinnerRows = parseJsonRows(prepareWinnerResult.stdout);
    const prepareWaiterRows = parseJsonRows(prepareWaiterResult.stdout);
    if (prepareWinnerRows.length !== 1 || prepareWaiterRows.length !== 1) {
      throw new Error("CONCURRENT_PREPARE_RESULT_COUNT_INVALID");
    }

    const prepareResults = [prepareWinnerRows[0], prepareWaiterRows[0]];
    const prepareJobIds = prepareResults.map((result) => result.job_id);
    const prepareProviderKeys = prepareJobIds.map((jobId) => `sdf-initial-confirmation/${jobId}`);
    if (new Set(prepareJobIds).size !== 1) throw new Error("UNSTABLE_JOB_ID");
    if (new Set(prepareProviderKeys).size !== 1) throw new Error("UNSTABLE_PROVIDER_IDENTITY");

    const jobId = prepareJobIds[0];
    const providerIdempotencyKey = prepareProviderKeys[0];
    const semanticSummary = JSON.parse(query(`
      select json_build_object(
        'job_count', count(*)::integer,
        'distinct_job_ids', count(distinct job_id)::integer,
        'shared_confirmation_count', (
          select count(*)::integer
          from public.quote_request_email_jobs
          where quote_request_id = '${quoteRequestId}'
            and kind = 'customer_confirmation'
        )
      )
      from public.sdf_initial_confirmation_email_jobs
      where quote_request_id = '${quoteRequestId}'
    `));
    if (semanticSummary.job_count !== 1) throw new Error("DUPLICATE_SEMANTIC_CONFIRMATION");
    if (semanticSummary.distinct_job_ids !== 1) throw new Error("UNSTABLE_JOB_ID");
    if (semanticSummary.shared_confirmation_count !== 0) throw new Error("SHARED_SDF_JOB_CREATED");

    claimHolder = startHoldingTransaction({
      applicationName: "sdf_initial_claim_winner",
      marker: "CLAIM_HELD",
      sql: `
        select row_to_json(claimed)::text
        from public.claim_sdf_initial_confirmation_email_job_v1('${jobId}') as claimed;
      `,
    });
    await claimHolder.ready;

    claimWaiter = run(`
      set application_name = 'sdf_initial_claim_waiter';
      begin;
      set local role service_role;
      select row_to_json(claimed)::text
      from public.claim_sdf_initial_confirmation_email_job_v1('${jobId}') as claimed;
      commit;
    `);
    await proveBlocked(
      "sdf_initial_claim_waiter",
      "sdf_initial_claim_winner",
      "CONCURRENT_CLAIM_LOCK_WAIT_NOT_PROVEN",
    );

    const claimWinnerResult = await claimHolder.release();
    claimHolder = null;
    const claimWaiterResult = await claimWaiter;
    claimWaiter = null;
    if (claimWinnerResult.code !== 0) {
      throw new Error(`CLAIM_WINNER_FAILED:${JSON.stringify(claimWinnerResult)}`);
    }
    if (claimWaiterResult.code !== 0) {
      throw new Error(`CLAIM_WAITER_FAILED:${JSON.stringify(claimWaiterResult)}`);
    }

    const claimWinnerRows = parseJsonRows(claimWinnerResult.stdout);
    const claimWaiterRows = parseJsonRows(claimWaiterResult.stdout);
    const claimWinners = claimWinnerRows.length + claimWaiterRows.length;
    if (claimWinners !== 1) throw new Error(`INVALID_CLAIM_WINNER_COUNT:${claimWinners}`);

    const winningClaim = claimWinnerRows[0] || claimWaiterRows[0];
    if (winningClaim.job_id !== jobId) throw new Error("CLAIM_JOB_ID_CHANGED");
    if (winningClaim.attempt_count !== 1) throw new Error("CLAIM_ATTEMPT_COUNT_INVALID");
    if (winningClaim.provider_idempotency_key !== providerIdempotencyKey) {
      throw new Error("CLAIM_PROVIDER_IDENTITY_CHANGED");
    }

    const claimSummary = JSON.parse(query(`
      select json_build_object(
        'active_lease_winners', count(*) filter (
          where status = 'processing'
            and delivery_lease_token is not null
            and delivery_lease_expires_at > clock_timestamp()
        )::integer,
        'attempt_count', max(attempt_count)::integer
      )
      from public.sdf_initial_confirmation_email_jobs
      where quote_request_id = '${quoteRequestId}'
    `));
    if (claimSummary.active_lease_winners !== 1) throw new Error("MULTIPLE_ACTIVE_LEASES");
    if (claimSummary.attempt_count !== 1) throw new Error("CLAIM_ATTEMPT_COUNT_INVALID");

    const winnerLeaseValidates = query(`
      set role service_role;
      select public.validate_sdf_initial_confirmation_email_delivery_v1(
        '${jobId}', '${winningClaim.delivery_lease_token}'
      )
    `) === "t";
    const spoofedLeaseValidates = query(`
      set role service_role;
      select public.validate_sdf_initial_confirmation_email_delivery_v1(
        '${jobId}', '${spoofedLeaseToken}'
      )
    `) === "t";
    const spoofedCompletionRejected = query(`
      set role service_role;
      select public.complete_sdf_initial_confirmation_email_job_v1(
        '${jobId}', '${spoofedLeaseToken}', true, false, null, 'must-not-persist'
      ) is null
    `) === "t";
    if (!winnerLeaseValidates) throw new Error("WINNER_LEASE_REJECTED");
    if (spoofedLeaseValidates) throw new Error("SPOOFED_LEASE_ACCEPTED");
    if (!spoofedCompletionRejected) throw new Error("SPOOFED_COMPLETION_ACCEPTED");

    const authorityAfterSpoof = JSON.parse(query(`
      select json_build_object(
        'status', status,
        'delivery_lease_token', delivery_lease_token,
        'attempt_count', attempt_count
      )
      from public.sdf_initial_confirmation_email_jobs
      where job_id = '${jobId}'
    `));
    if (authorityAfterSpoof.status !== "processing"
        || authorityAfterSpoof.delivery_lease_token !== winningClaim.delivery_lease_token
        || authorityAfterSpoof.attempt_count !== 1) {
      throw new Error("SPOOFED_COMPLETION_MUTATED_AUTHORITY");
    }

    query(`
      update public.sdf_initial_confirmation_email_jobs
      set delivery_lease_expires_at = clock_timestamp() - interval '1 second'
      where job_id = '${jobId}'
    `);
    const reclaimedClaim = JSON.parse(query(`
      set role service_role;
      select row_to_json(claimed)::text
      from public.claim_sdf_initial_confirmation_email_job_v1('${jobId}') as claimed
    `));
    if (reclaimedClaim.job_id !== jobId) throw new Error("RECLAIM_JOB_ID_CHANGED");
    if (reclaimedClaim.attempt_count !== 2) throw new Error("RECLAIM_ATTEMPT_COUNT_INVALID");
    if (reclaimedClaim.provider_idempotency_key !== providerIdempotencyKey) {
      throw new Error("RECLAIM_PROVIDER_IDENTITY_CHANGED");
    }

    const oldLeaseValidates = query(`
      set role service_role;
      select public.validate_sdf_initial_confirmation_email_delivery_v1(
        '${jobId}', '${winningClaim.delivery_lease_token}'
      )
    `) === "t";
    const reclaimedLeaseValidates = query(`
      set role service_role;
      select public.validate_sdf_initial_confirmation_email_delivery_v1(
        '${jobId}', '${reclaimedClaim.delivery_lease_token}'
      )
    `) === "t";
    if (oldLeaseValidates) throw new Error("EXPIRED_LEASE_REVALIDATED");
    if (!reclaimedLeaseValidates) throw new Error("RECLAIMED_LEASE_REJECTED");

    const completion = JSON.parse(query(`
      set role service_role;
      select public.complete_sdf_initial_confirmation_email_job_v1(
        '${jobId}', '${reclaimedClaim.delivery_lease_token}', true, false, null,
        'sdf-initial-concurrency-provider-id'
      )::text
    `));
    if (completion.status !== "sent" || completion.job_id !== jobId) {
      throw new Error("SUCCESSFUL_COMPLETION_INVALID");
    }

    const claimsAfterSent = Number(query(`
      set role service_role;
      select count(*)
      from public.claim_sdf_initial_confirmation_email_job_v1('${jobId}')
    `));
    const finalAuthority = JSON.parse(query(`
      select json_build_object(
        'job_id', job_id,
        'status', status,
        'attempt_count', attempt_count,
        'provider_message_id', provider_message_id,
        'lease_cleared', delivery_lease_token is null
          and delivery_lease_expires_at is null
          and locked_at is null
      )
      from public.sdf_initial_confirmation_email_jobs
      where quote_request_id = '${quoteRequestId}'
    `));
    if (claimsAfterSent !== 0) throw new Error("SENT_JOB_RECLAIMED");
    if (finalAuthority.job_id !== jobId || finalAuthority.status !== "sent") {
      throw new Error("FINAL_AUTHORITY_IDENTITY_INVALID");
    }

    const websiteAfter = websiteMailSnapshot();
    const websiteMailstateUnchanged = JSON.stringify(websiteAfter) === JSON.stringify(websiteBefore);
    if (!websiteMailstateUnchanged) throw new Error("WEBSITE_MAILSTATE_MUTATED");

    process.stdout.write(JSON.stringify({
      test_context: "LOCAL_TEST_ONLY",
      prepare_lock_wait_proven: true,
      claim_lock_wait_proven: true,
      prepare_job_ids: prepareJobIds,
      provider_idempotency_key: providerIdempotencyKey,
      ...semanticSummary,
      claim_winners: claimWinners,
      active_lease_winners: claimSummary.active_lease_winners,
      attempt_count_after_concurrent_claim: claimSummary.attempt_count,
      winner_lease_validates: winnerLeaseValidates,
      spoofed_lease_validates: spoofedLeaseValidates,
      spoofed_completion_rejected: spoofedCompletionRejected,
      reclaimed_attempt_count: reclaimedClaim.attempt_count,
      stable_reclaim_job_id: reclaimedClaim.job_id === jobId,
      stable_reclaim_provider_identity: reclaimedClaim.provider_idempotency_key === providerIdempotencyKey,
      old_lease_validates: oldLeaseValidates,
      reclaimed_lease_validates: reclaimedLeaseValidates,
      claims_after_sent: claimsAfterSent,
      final_status: finalAuthority.status,
      website_mailstate_unchanged: websiteMailstateUnchanged,
      legacy_sdf_producer_absent: true,
    }) + "\n");
  } finally {
    if (prepareHolder) await prepareHolder.abort();
    if (claimHolder) await claimHolder.abort();
    if (prepareWaiter) await prepareWaiter;
    if (claimWaiter) await claimWaiter;
    cleanup();
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
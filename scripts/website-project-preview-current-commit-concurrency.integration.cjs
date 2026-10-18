const { readFileSync } = require("node:fs");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");

const container = process.env.PDF_PREVIEW_CONCURRENCY_CONTAINER;
const database = process.env.PDF_PREVIEW_CONCURRENCY_DATABASE;
const quoteRequestId = "eec31000-0000-4000-8000-000000000002";
const workspaceId = "eec31000-0000-4000-8000-000000000005";
const buildId = "eec31000-0000-4000-8000-000000000009";
const authUserId = "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0";
const commitN = "a".repeat(40);
const commitNext = "b".repeat(40);
const fixturePrefix = "eec31000-";
const baseArgs = [
  "exec", "-i", container ?? "", "psql", "-X", "-U", "postgres", "-d",
  database ?? "", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", "-q", "-At",
];

function assertLocalTarget() {
  if (!/^supabase_db_lws_p0_preview_[a-z0-9_]+$/.test(container ?? "")) {
    throw new Error("LOCAL_TEST_ONLY_CONTAINER_REQUIRED");
  }
  if (!/^lws_p0_preview_[a-z0-9_]+$/.test(database ?? "")) {
    throw new Error("LOCAL_TEST_ONLY_DATABASE_REQUIRED");
  }
  const inspect = spawnSync(
    "docker",
    ["inspect", "--format", "{{.Name}}|{{.State.Status}}|{{.State.Health.Status}}", container],
    { encoding: "utf8" },
  );
  if (
    inspect.status !== 0
    || inspect.stdout.trim() !== `/${container}|running|healthy`
  ) {
    throw new Error(`LOCAL_TEST_ONLY_TARGET_INVALID:${inspect.stderr || inspect.stdout}`);
  }
}

function query(sql) {
  const result = spawnSync("docker", [...baseArgs, "-c", sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) ?? "";
}

function run(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn("docker", [...baseArgs, "-c", sql]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => stdout += data);
    child.stderr.on("data", (data) => stderr += data);
    child.once("error", reject);
    child.once("exit", (code) => resolve({ code, stdout, stderr }));
  });
}

function extractSqlState(stderr) {
  const match = stderr.match(/^ERROR:\s+([0-9A-Z]{5}):/m);
  if (!match) throw new Error(`SQLSTATE_NOT_REPORTED:${stderr}`);
  return match[1];
}

function startHoldingSession(sql, marker) {
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
    if (!settled) readyReject(new Error(`HOLDER_READY_TIMEOUT:${marker}:${stderr || stdout}`));
  }, 10000);
  child.stdout.on("data", (data) => {
    stdout += data;
    if (!settled && stdout.includes(marker)) {
      settled = true;
      clearTimeout(timeout);
      readyResolve();
    }
  });
  child.stderr.on("data", (data) => stderr += data);
  const exited = new Promise((resolve) => child.once("exit", (code) => {
    if (!settled) {
      settled = true;
      clearTimeout(timeout);
      readyReject(new Error(`HOLDER_EXITED:${marker}:${code}:${stderr || stdout}`));
    }
    resolve({ code, stdout, stderr });
  }));
  child.stdin.write(`${sql}\n`);
  return {
    ready,
    output: () => ({ stdout, stderr }),
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

function fixtureSql() {
  const source = readFileSync(
    path.join(__dirname, "../supabase/tests/website_project_preview_reopen_current_commit_v1.sql"),
    "utf8",
  );
  const start = source.indexOf("insert into auth.users");
  const endMarker = "set local session_replication_role = origin;";
  const end = source.indexOf(endMarker, start);
  if (start < 0 || end < 0) throw new Error("CONCURRENCY_FIXTURE_SOURCE_INVALID");
  return `
    begin;
    set local session_replication_role = replica;
    ${source.slice(start, end + endMarker.length)}
    commit;
  `;
}

function cleanupFixtures() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from lws_internal.website_project_preview_sessions
      where preview_build_id in (
        select preview_build_id from lws_internal.website_project_preview_builds
        where quote_request_id = '${quoteRequestId}'
      );
    delete from lws_internal.website_project_preview_build_artifacts
      where preview_build_id in (
        select preview_build_id from lws_internal.website_project_preview_builds
        where quote_request_id = '${quoteRequestId}'
      );
    delete from lws_internal.website_project_preview_builds
      where quote_request_id = '${quoteRequestId}';
    delete from lws_internal.website_project_preview_build_leases
      where quote_request_id = '${quoteRequestId}';
    delete from lws_internal.website_project_files_write_leases
      where quote_request_id = '${quoteRequestId}';
    delete from public.website_repository_provisioning_operations
      where website_workspace_id = '${workspaceId}';
    delete from public.website_execution_workspaces
      where website_workspace_id = '${workspaceId}';
    delete from public.website_work_contexts
      where quote_request_id = '${quoteRequestId}';
    delete from public.website_concepts
      where quote_request_id = '${quoteRequestId}';
    delete from public.quote_requests where id = '${quoteRequestId}';
    delete from public.commercial_operators
      where auth_user_id = '${authUserId}';
    delete from auth.users where id = '${authUserId}';
    commit;
  `);
}

function assertZeroResidue() {
  const residue = query(`
    select jsonb_build_object(
      'sessions', (
        select count(*) from lws_internal.website_project_preview_sessions
        where preview_build_id::text like '${fixturePrefix}%'
      ),
      'builds', (
        select count(*) from lws_internal.website_project_preview_builds
        where quote_request_id = '${quoteRequestId}'
      ),
      'artifacts', (
        select count(*) from lws_internal.website_project_preview_build_artifacts
        where preview_build_id::text like '${fixturePrefix}%'
      ),
      'build_leases', (
        select count(*) from lws_internal.website_project_preview_build_leases
        where quote_request_id = '${quoteRequestId}'
      ),
      'write_leases', (
        select count(*) from lws_internal.website_project_files_write_leases
        where quote_request_id = '${quoteRequestId}'
      ),
      'provisioning_operations', (
        select count(*) from public.website_repository_provisioning_operations
        where website_workspace_id = '${workspaceId}'
      ),
      'workspaces', (
        select count(*) from public.website_execution_workspaces
        where quote_request_id = '${quoteRequestId}'
      ),
      'work_contexts', (
        select count(*) from public.website_work_contexts
        where quote_request_id = '${quoteRequestId}'
      ),
      'concepts', (
        select count(*) from public.website_concepts
        where quote_request_id = '${quoteRequestId}'
      ),
      'quotes', (
        select count(*) from public.quote_requests where id = '${quoteRequestId}'
      ),
      'operators', (
        select count(*) from public.commercial_operators
        where auth_user_id = '${authUserId}'
      ),
      'users', (
        select count(*) from auth.users where id = '${authUserId}'
      )
    )::text
  `);
  const parsed = JSON.parse(residue);
  if (Object.values(parsed).some((count) => Number(count) !== 0)) {
    throw new Error(`PREVIEW_CONCURRENCY_RESIDUE:${residue}`);
  }
}

function resetCase() {
  query(`
    begin;
    delete from lws_internal.website_project_preview_sessions
      where preview_build_id = '${buildId}';
    update public.website_execution_workspaces
      set last_commit_sha = '${commitN}', last_commit_at = clock_timestamp()
      where website_workspace_id = '${workspaceId}';
    commit;
  `);
}

function resetSweepCase() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from lws_internal.website_project_preview_sessions
      where preview_build_id = '${buildId}';
    update public.website_execution_workspaces
    set last_commit_sha = '${commitN}', last_commit_at = clock_timestamp()
    where website_workspace_id = '${workspaceId}';
    update lws_internal.website_project_preview_builds
    set commit_sha = '${commitN}',
        build_status = 'PASS',
        built_at = clock_timestamp() - interval '48 hours'
    where preview_build_id = '${buildId}';
    insert into lws_internal.website_project_preview_build_artifacts(
      artifact_id, preview_build_id, relative_path, content_type, sha256, bytes
    ) values (
      'eec31000-0000-4000-8000-000000000010',
      '${buildId}',
      'index.html',
      'text/html',
      repeat('a', 64),
      100
    )
    on conflict (preview_build_id, relative_path) do update
    set content_type = excluded.content_type,
        sha256 = excluded.sha256,
        bytes = excluded.bytes;
    set local session_replication_role = origin;
    commit;
  `);
}

function sweepSnapshot(tokenHash) {
  return JSON.parse(query(`
    select jsonb_build_object(
      'artifact_count', (
        select count(*)
        from lws_internal.website_project_preview_build_artifacts
        where preview_build_id = '${buildId}'
      ),
      'session_count', (
        select count(*)
        from lws_internal.website_project_preview_sessions
        where session_token_hash = '${tokenHash}'
      ),
      'active_session_count', (
        select count(*)
        from lws_internal.website_project_preview_sessions
        where session_token_hash = '${tokenHash}'
          and revoked_at is null
          and expires_at > clock_timestamp()
      ),
      'revoked_session_count', (
        select count(*)
        from lws_internal.website_project_preview_sessions
        where session_token_hash = '${tokenHash}'
          and revoked_at is not null
      )
    )::text
  `));
}

function humanClaims() {
  return `select set_config(
    'request.jwt.claims',
    '{"sub":"${authUserId}","role":"authenticated","aal":"aal2"}',
    true
  );`;
}

async function proveBlocked(waiterName, holderName) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    const proof = query(`
      select jsonb_build_object(
        'holder_pid', holder.pid,
        'waiter_pid', waiter.pid,
        'wait_event_type', waiter.wait_event_type,
        'blocking_pids', pg_blocking_pids(waiter.pid)
      )::text
      from pg_stat_activity as waiter
      join pg_stat_activity as holder
        on holder.pid = any(pg_blocking_pids(waiter.pid))
      where waiter.application_name = '${waiterName}'
        and holder.application_name = '${holderName}'
        and waiter.wait_event_type = 'Lock'
    `);
    if (proof) {
      const parsed = JSON.parse(proof);
      const holderPid = Number(parsed.holder_pid);
      const waiterPid = Number(parsed.waiter_pid);
      if (
        holderPid > 0
        && waiterPid > 0
        && new Set([holderPid, waiterPid]).size === 2
        && parsed.blocking_pids.length === 1
        && Number(parsed.blocking_pids[0]) === holderPid
      ) return parsed;
    }
  }
  throw new Error(`LOCK_WAIT_NOT_PROVEN:${waiterName}:${holderName}`);
}

function snapshot() {
  return JSON.parse(query(`
    select jsonb_build_object(
      'commit_sha', workspace.last_commit_sha,
      'session_count', (
        select count(*) from lws_internal.website_project_preview_sessions
        where preview_build_id = '${buildId}'
      )
    )::text
    from public.website_execution_workspaces as workspace
    where workspace.website_workspace_id = '${workspaceId}'
  `));
}

function markSessionConsumed(tokenHash) {
  query(`
    update lws_internal.website_project_preview_sessions
    set handoff_consumed_at = clock_timestamp()
    where session_token_hash = '${tokenHash}'
  `);
}

function resolveSession(tokenHash) {
  return JSON.parse(query(`
    begin;
    set local role service_role;
    select set_config('request.jwt.claims', '{"role":"service_role"}', true);
    select public.resolve_website_project_preview_session_v1('${tokenHash}')::text;
    commit;
  `));
}

async function issuanceFirst(kind, tokenHash) {
  resetCase();
  const holderName = `lws_preview_${kind}_issuance_holder`;
  const waiterName = `lws_preview_${kind}_update_waiter`;
  const rpc = kind === "reopen"
    ? `public.open_existing_website_project_preview_v1('${quoteRequestId}','${tokenHash}')`
    : `public.create_website_project_preview_session_v1('${buildId}','${tokenHash}')`;
  let holder;
  try {
    holder = startHoldingSession(`
      set application_name = '${holderName}';
      begin;
      set local role authenticated;
      ${humanClaims()}
      select ${rpc}::text;
      select pg_backend_pid(), '${kind.toUpperCase()}_ISSUANCE_HELD';
    `, `${kind.toUpperCase()}_ISSUANCE_HELD`);
    await holder.ready;
    const waiter = run(`
      set application_name = '${waiterName}';
      update public.website_execution_workspaces
      set last_commit_sha = '${commitNext}', last_commit_at = clock_timestamp()
      where website_workspace_id = '${workspaceId}';
    `);
    const lock = await proveBlocked(waiterName, holderName);
    const holderResult = await holder.release();
    holder = null;
    const waiterResult = await waiter;
    if (holderResult.code !== 0 || waiterResult.code !== 0) {
      throw new Error(`${kind.toUpperCase()}_ISSUANCE_FIRST_FAILED:${JSON.stringify({ holderResult, waiterResult })}`);
    }
    const after = snapshot();
    if (after.commit_sha !== commitNext || Number(after.session_count) !== 1) {
      throw new Error(`${kind.toUpperCase()}_ISSUANCE_FIRST_STATE_INVALID:${JSON.stringify(after)}`);
    }
    markSessionConsumed(tokenHash);
    const resolved = resolveSession(tokenHash);
    if (resolved.previewBuildId !== buildId) {
      throw new Error(`${kind.toUpperCase()}_ISSUED_SESSION_NOT_PRESERVED`);
    }
    return { lock, after, resolver: resolved };
  } finally {
    if (holder) await holder.abort();
  }
}

async function updateFirst(kind, tokenHash, expectedSqlState, expectedMessage) {
  resetCase();
  const holderName = `lws_preview_${kind}_update_holder`;
  const waiterName = `lws_preview_${kind}_issuance_waiter`;
  const rpc = kind === "reopen"
    ? `public.open_existing_website_project_preview_v1('${quoteRequestId}','${tokenHash}')`
    : `public.create_website_project_preview_session_v1('${buildId}','${tokenHash}')`;
  let holder;
  try {
    holder = startHoldingSession(`
      set application_name = '${holderName}';
      begin;
      update public.website_execution_workspaces
      set last_commit_sha = '${commitNext}', last_commit_at = clock_timestamp()
      where website_workspace_id = '${workspaceId}';
      select pg_backend_pid(), '${kind.toUpperCase()}_UPDATE_HELD';
    `, `${kind.toUpperCase()}_UPDATE_HELD`);
    await holder.ready;
    const waiter = run(`
      set application_name = '${waiterName}';
      begin;
      set local role authenticated;
      ${humanClaims()}
      select ${rpc}::text;
      commit;
    `);
    const lock = await proveBlocked(waiterName, holderName);
    const holderResult = await holder.release();
    holder = null;
    const waiterResult = await waiter;
    if (
      holderResult.code !== 0
      || waiterResult.code === 0
      || !waiterResult.stderr.includes(expectedMessage)
    ) {
      throw new Error(`${kind.toUpperCase()}_UPDATE_FIRST_RESULT_INVALID:${JSON.stringify({ holderResult, waiterResult })}`);
    }
    const sqlstate = extractSqlState(waiterResult.stderr);
    if (sqlstate !== expectedSqlState) {
      throw new Error(`${kind.toUpperCase()}_UPDATE_FIRST_SQLSTATE_INVALID:${sqlstate}`);
    }
    const after = snapshot();
    if (after.commit_sha !== commitNext || Number(after.session_count) !== 0) {
      throw new Error(`${kind.toUpperCase()}_UPDATE_FIRST_STATE_INVALID:${JSON.stringify(after)}`);
    }
    return {
      lock,
      after,
      sqlstate,
      message: expectedMessage,
    };
  } finally {
    if (holder) await holder.abort();
  }
}

async function artifactSweepFirst(tokenHash) {
  resetSweepCase();
  const holderName = "lws_preview_artifact_sweep_holder";
  const waiterName = "lws_preview_artifact_issuance_waiter";
  let holder;
  try {
    holder = startHoldingSession(`
      set application_name = '${holderName}';
      begin;
      set local role service_role;
      select public.sweep_expired_website_project_preview_artifacts_v1(24)::text;
      select pg_backend_pid(), 'ARTIFACT_SWEEP_HELD';
    `, "ARTIFACT_SWEEP_HELD");
    await holder.ready;
    const waiter = run(`
      set application_name = '${waiterName}';
      begin;
      set local role authenticated;
      ${humanClaims()}
      select public.create_website_project_preview_session_v1(
        '${buildId}',
        '${tokenHash}'
      )::text;
      commit;
    `);
    const lock = await proveBlocked(waiterName, holderName);
    const holderResult = await holder.release();
    holder = null;
    const waiterResult = await waiter;
    if (
      holderResult.code !== 0
      || waiterResult.code === 0
      || !waiterResult.stderr.includes("PROJECT_PREVIEW_BUILD_NOT_READY")
    ) {
      throw new Error(`ARTIFACT_SWEEP_FIRST_RESULT_INVALID:${JSON.stringify({
        holderResult,
        waiterResult,
      })}`);
    }
    const sqlstate = extractSqlState(waiterResult.stderr);
    const after = sweepSnapshot(tokenHash);
    if (
      sqlstate !== "42501"
      || Number(after.artifact_count) !== 0
      || Number(after.session_count) !== 0
      || Number(after.active_session_count) !== 0
    ) {
      throw new Error(`ARTIFACT_SWEEP_FIRST_STATE_INVALID:${JSON.stringify({
        sqlstate,
        after,
      })}`);
    }
    return {
      lock,
      after,
      sqlstate,
      message: "PROJECT_PREVIEW_BUILD_NOT_READY",
    };
  } finally {
    if (holder) await holder.abort();
  }
}

async function artifactIssuanceFirst(tokenHash) {
  resetSweepCase();
  const holderName = "lws_preview_artifact_issuance_holder";
  const waiterName = "lws_preview_artifact_sweep_waiter";
  let holder;
  try {
    holder = startHoldingSession(`
      set application_name = '${holderName}';
      begin;
      set local role authenticated;
      ${humanClaims()}
      select public.create_website_project_preview_session_v1(
        '${buildId}',
        '${tokenHash}'
      )::text;
      select pg_backend_pid(), 'ARTIFACT_ISSUANCE_HELD';
    `, "ARTIFACT_ISSUANCE_HELD");
    await holder.ready;
    const before = sweepSnapshot(tokenHash);
    if (
      Number(before.artifact_count) !== 1
      || Number(before.session_count) !== 0
    ) {
      throw new Error(`ARTIFACT_ISSUANCE_FIRST_PRECOMMIT_INVALID:${JSON.stringify(before)}`);
    }
    const waiter = run(`
      set application_name = '${waiterName}';
      begin;
      set local role service_role;
      select public.sweep_expired_website_project_preview_artifacts_v1(24)::text;
      commit;
    `);
    const lock = await proveBlocked(waiterName, holderName);
    const holderResult = await holder.release();
    holder = null;
    const waiterResult = await waiter;
    if (holderResult.code !== 0 || waiterResult.code !== 0) {
      throw new Error(`ARTIFACT_ISSUANCE_FIRST_RESULT_INVALID:${JSON.stringify({
        holderResult,
        waiterResult,
      })}`);
    }
    const after = sweepSnapshot(tokenHash);
    if (
      Number(after.artifact_count) !== 0
      || Number(after.session_count) !== 1
      || Number(after.active_session_count) !== 0
      || Number(after.revoked_session_count) !== 1
    ) {
      throw new Error(`ARTIFACT_ISSUANCE_FIRST_DANGLING_SESSION:${JSON.stringify(after)}`);
    }
    return { lock, before, after };
  } finally {
    if (holder) await holder.abort();
  }
}

async function artifactReopenSweepFirst(tokenHash) {
  resetSweepCase();
  const holderName = "lws_preview_artifact_reopen_sweep_holder";
  const waiterName = "lws_preview_artifact_reopen_waiter";
  let holder;
  try {
    holder = startHoldingSession(`
      set application_name = '${holderName}';
      begin;
      set local role service_role;
      select public.sweep_expired_website_project_preview_artifacts_v1(24)::text;
      select pg_backend_pid(), 'ARTIFACT_REOPEN_SWEEP_HELD';
    `, "ARTIFACT_REOPEN_SWEEP_HELD");
    await holder.ready;
    const waiter = run(`
      set application_name = '${waiterName}';
      begin;
      set local role authenticated;
      ${humanClaims()}
      select public.open_existing_website_project_preview_v1(
        '${quoteRequestId}',
        '${tokenHash}'
      )::text;
      commit;
    `);
    const lock = await proveBlocked(waiterName, holderName);
    const holderResult = await holder.release();
    holder = null;
    const waiterResult = await waiter;
    const after = sweepSnapshot(tokenHash);
    if (holderResult.code !== 0) {
      throw new Error(`ARTIFACT_REOPEN_SWEEP_FIRST_HOLDER_FAILED:${JSON.stringify({
        holderResult,
        waiterResult,
        after,
      })}`);
    }
    if (waiterResult.code === 0) {
      throw new Error(`ARTIFACT_REOPEN_SWEEP_FIRST_DANGLING_SESSION:${JSON.stringify({
        waiterResult,
        after,
      })}`);
    }
    const sqlstate = extractSqlState(waiterResult.stderr);
    if (
      sqlstate !== "P0001"
      || !waiterResult.stderr.includes("PROJECT_PREVIEW_BUILD_NOT_FOUND")
      || Number(after.artifact_count) !== 0
      || Number(after.session_count) !== 0
      || Number(after.active_session_count) !== 0
    ) {
      throw new Error(`ARTIFACT_REOPEN_SWEEP_FIRST_STATE_INVALID:${JSON.stringify({
        sqlstate,
        waiterResult,
        after,
      })}`);
    }
    return {
      lock,
      after,
      sqlstate,
      message: "PROJECT_PREVIEW_BUILD_NOT_FOUND",
    };
  } finally {
    if (holder) await holder.abort();
  }
}

async function artifactReopenFirst(tokenHash) {
  resetSweepCase();
  const holderName = "lws_preview_artifact_reopen_holder";
  const waiterName = "lws_preview_artifact_reopen_sweeper";
  let holder;
  try {
    holder = startHoldingSession(`
      set application_name = '${holderName}';
      begin;
      set local role authenticated;
      ${humanClaims()}
      select public.open_existing_website_project_preview_v1(
        '${quoteRequestId}',
        '${tokenHash}'
      )::text;
      select pg_backend_pid(), 'ARTIFACT_REOPEN_HELD';
    `, "ARTIFACT_REOPEN_HELD");
    await holder.ready;
    const before = sweepSnapshot(tokenHash);
    if (
      Number(before.artifact_count) !== 1
      || Number(before.session_count) !== 0
    ) {
      throw new Error(`ARTIFACT_REOPEN_FIRST_PRECOMMIT_INVALID:${JSON.stringify(before)}`);
    }
    const waiter = run(`
      set application_name = '${waiterName}';
      begin;
      set local role service_role;
      select public.sweep_expired_website_project_preview_artifacts_v1(24)::text;
      commit;
    `);
    const lock = await proveBlocked(waiterName, holderName);
    const holderResult = await holder.release();
    holder = null;
    const waiterResult = await waiter;
    if (holderResult.code !== 0 || waiterResult.code !== 0) {
      throw new Error(`ARTIFACT_REOPEN_FIRST_RESULT_INVALID:${JSON.stringify({
        holderResult,
        waiterResult,
      })}`);
    }
    const after = sweepSnapshot(tokenHash);
    if (
      Number(after.artifact_count) !== 0
      || Number(after.session_count) !== 1
      || Number(after.active_session_count) !== 0
      || Number(after.revoked_session_count) !== 1
    ) {
      throw new Error(`ARTIFACT_REOPEN_FIRST_STATE_INVALID:${JSON.stringify(after)}`);
    }
    return { lock, before, after };
  } finally {
    if (holder) await holder.abort();
  }
}

async function artifactCleanedHistoryNotRelocked(tokenHash) {
  resetSweepCase();
  const initialSweep = JSON.parse(query(`
    begin;
    set local role service_role;
    select public.sweep_expired_website_project_preview_artifacts_v1(24)::text;
    commit;
  `));
  const afterInitialSweep = sweepSnapshot(tokenHash);
  if (
    Number(initialSweep.orphanedArtifactRowsDeleted) !== 1
    || Number(afterInitialSweep.artifact_count) !== 0
    || Number(afterInitialSweep.active_session_count) !== 0
  ) {
    throw new Error(`ARTIFACT_CLEANED_HISTORY_SETUP_INVALID:${JSON.stringify({
      initialSweep,
      afterInitialSweep,
    })}`);
  }

  query(`
    insert into lws_internal.website_project_preview_sessions (
      preview_build_id, session_token_hash, actor_auth_user_id, expires_at
    ) values (
      '${buildId}',
      '${tokenHash}',
      '${authUserId}',
      clock_timestamp() + interval '30 minutes'
    )
  `);
  const orphanedSessionSweep = JSON.parse(query(`
    begin;
    set local role service_role;
    select public.sweep_expired_website_project_preview_artifacts_v1(24)::text;
    commit;
  `));
  const afterOrphanedSessionSweep = sweepSnapshot(tokenHash);
  if (
    Number(orphanedSessionSweep.expiredSessionsRevoked) !== 1
    || Number(orphanedSessionSweep.orphanedArtifactRowsDeleted) !== 0
    || Number(afterOrphanedSessionSweep.artifact_count) !== 0
    || Number(afterOrphanedSessionSweep.active_session_count) !== 0
    || Number(afterOrphanedSessionSweep.revoked_session_count) !== 1
  ) {
    throw new Error(`ARTIFACT_MISSING_UNREVOKED_SESSION_NOT_CLEANED:${JSON.stringify({
      orphanedSessionSweep,
      afterOrphanedSessionSweep,
    })}`);
  }

  const holderName = "lws_preview_cleaned_history_holder";
  const waiterName = "lws_preview_cleaned_history_sweeper";
  let holder;
  try {
    holder = startHoldingSession(`
      set application_name = '${holderName}';
      begin;
      select preview_build_id
      from lws_internal.website_project_preview_builds
      where preview_build_id = '${buildId}'
      for update;
      select pg_backend_pid(), 'CLEANED_HISTORY_BUILD_HELD';
    `, "CLEANED_HISTORY_BUILD_HELD");
    await holder.ready;
    const waiterResult = await run(`
      set application_name = '${waiterName}';
      begin;
      set local lock_timeout = '500ms';
      set local role service_role;
      select public.sweep_expired_website_project_preview_artifacts_v1(24)::text;
      commit;
    `);
    if (waiterResult.code !== 0) {
      const sqlstate = extractSqlState(waiterResult.stderr);
      throw new Error(`ARTIFACT_CLEANED_HISTORY_RELOCKED:SQLSTATE_${sqlstate}`);
    }
    const holderResult = await holder.release();
    holder = null;
    if (holderResult.code !== 0) {
      throw new Error(`ARTIFACT_CLEANED_HISTORY_HOLDER_FAILED:${JSON.stringify(holderResult)}`);
    }
    const sweepResult = JSON.parse(
      waiterResult.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) ?? "",
    );
    const after = sweepSnapshot(tokenHash);
    if (
      Number(sweepResult.expiredSessionsRevoked) !== 0
      || Number(sweepResult.orphanedArtifactRowsDeleted) !== 0
      || Number(after.artifact_count) !== 0
      || Number(after.active_session_count) !== 0
    ) {
      throw new Error(`ARTIFACT_CLEANED_HISTORY_STATE_INVALID:${JSON.stringify({
        sweepResult,
        after,
      })}`);
    }
    return {
      initialSweep,
      afterInitialSweep,
      orphanedSessionSweep,
      afterOrphanedSessionSweep,
      sweepResult,
      after,
    };
  } finally {
    if (holder) await holder.abort();
  }
}

async function main() {
  assertLocalTarget();
  let runError;
  const evidence = { test_context: "LOCAL_TEST_ONLY", database, cases: {} };
  try {
    cleanupFixtures();
    query(fixtureSql());
    evidence.before = snapshot();
    evidence.cases.reopen_issuance_first = await issuanceFirst("reopen", "1".repeat(64));
    evidence.cases.reopen_update_first = await updateFirst(
      "reopen",
      "2".repeat(64),
      "P0001",
      "PROJECT_PREVIEW_BUILD_NOT_FOUND",
    );
    evidence.cases.create_session_issuance_first = await issuanceFirst(
      "create_session",
      "3".repeat(64),
    );
    evidence.cases.create_session_update_first = await updateFirst(
      "create_session",
      "4".repeat(64),
      "42501",
      "PROJECT_PREVIEW_BUILD_NOT_READY",
    );
    evidence.cases.artifact_sweep_first = await artifactSweepFirst("5".repeat(64));
    evidence.cases.artifact_issuance_first = await artifactIssuanceFirst("6".repeat(64));
    evidence.cases.artifact_cleaned_history_not_relocked =
      await artifactCleanedHistoryNotRelocked("7".repeat(64));
    evidence.cases.artifact_reopen_sweep_first =
      await artifactReopenSweepFirst("8".repeat(64));
    evidence.cases.artifact_reopen_first = await artifactReopenFirst("9".repeat(64));
  } catch (error) {
    runError = error;
  } finally {
    let cleanupError;
    try {
      cleanupFixtures();
      assertZeroResidue();
    } catch (error) {
      cleanupError = error;
    }
    if (runError && cleanupError) {
      throw new AggregateError([runError, cleanupError], "RUN_AND_CLEANUP_FAILED");
    }
    if (runError) throw runError;
    if (cleanupError) throw cleanupError;
  }
  process.stdout.write(`${JSON.stringify(evidence)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});

const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const ownerUserId = "fa100000-0000-4000-8000-000000000001";
const ownerOperatorId = "fa110000-0000-4000-8000-000000000001";
const inboxItemId = "fa120000-0000-4000-8000-000000000001";
const sha256 = "2".repeat(64);

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

function startHoldingProcess() {
  const child = spawn("docker", baseArgs);
  let stdout = "";
  let stderr = "";
  let readyResolve;
  let readyReject;
  let settled = false;
  const ready = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });
  const timeout = setTimeout(() => {
    if (!settled) readyReject(new Error(`FIRST_PROCESS_TIMEOUT:${stderr || stdout}`));
  }, 5000);
  child.stdout.on("data", (data) => {
    stdout += data;
    if (!settled && stdout.includes("FIRST_PROCESS_HELD")) {
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
      readyReject(new Error(`FIRST_PROCESS_EXITED:${code}:${stderr || stdout}`));
    }
    resolve({ code, stdout, stderr });
  }));
  child.stdin.write(`
    set application_name = 'document_inbox_processor_one';
    begin;
    set local role authenticated;
    select set_config('request.jwt.claim.sub','${ownerUserId}',true);
    select public.process_document_inbox_item_v1('${inboxItemId}',1);
    select 'FIRST_PROCESS_HELD';
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

async function proveBlocked() {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const blocked = query(`
      select exists (
        select 1
        from pg_stat_activity waiting
        join pg_stat_activity blocker on blocker.pid = any(pg_blocking_pids(waiting.pid))
        where waiting.application_name = 'document_inbox_processor_two'
          and blocker.application_name = 'document_inbox_processor_one'
          and waiting.wait_event_type = 'Lock'
      )
    `);
    if (blocked === "t") return;
  }
  throw new Error("DOCUMENT_INBOX_PROCESS_LOCK_WAIT_NOT_PROVEN");
}

function cleanup() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from public.document_inbox_events where inbox_item_id = '${inboxItemId}';
    delete from public.document_inbox_items where id = '${inboxItemId}';
    delete from public.business_expense_documents where created_by_operator_id = '${ownerOperatorId}';
    delete from public.supplier_documents where created_by_operator_id = '${ownerOperatorId}';
    delete from public.business_expenses where created_by_operator_id = '${ownerOperatorId}';
    delete from storage.objects where bucket_id = 'supplier-documents' and name = 'documents/${sha256}.pdf';
    delete from public.commercial_operators where operator_id = '${ownerOperatorId}';
    delete from auth.users where id = '${ownerUserId}';
    commit;
    select 'CLEAN';
  `);
}

async function main() {
  let first = null;
  if (query("select current_database()") !== "postgres") throw new Error("LOCAL_TEST_ENVIRONMENT_REQUIRED");
  try {
    cleanup();
    query(`
      insert into auth.users(id,email) values('${ownerUserId}','inbox-concurrency-owner@example.test');
      insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status)
      values('${ownerOperatorId}','${ownerUserId}','Inbox Concurrency Owner','owner','ACTIVE');
      insert into storage.objects(bucket_id,name,metadata)
      values('supplier-documents','documents/${sha256}.pdf',jsonb_build_object('size',202,'mimetype','application/pdf','sha256','${sha256}'));
      insert into public.document_inbox_items(
        id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
        source_type,lifecycle_status,revision,
        confirmed_supplier_name,confirmed_document_type,confirmed_amount_minor,confirmed_currency,
        confirmed_description,confirmed_category,confirmed_expense_date,confirmed_relation_type,
        warnings_acknowledged,record_classification,created_by_operator_id,approved_by_operator_id,approved_at
      ) values (
        '${inboxItemId}','${sha256}','documents/${sha256}.pdf','concurrent.pdf','application/pdf',202,
        'MANUAL_UPLOAD','APPROVED',1,
        'Concurrent Supplier','INVOICE',20200,'EUR',
        'Concurrent processing fixture','other','2026-08-29','INVOICE',
        true,'internal_e2e','${ownerOperatorId}','${ownerOperatorId}',clock_timestamp()
      );
      select 'READY';
    `);

    first = startHoldingProcess();
    await first.ready;
    const secondPromise = run(`
      set application_name = 'document_inbox_processor_two';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claim.sub','${ownerUserId}',true);
      select public.process_document_inbox_item_v1('${inboxItemId}',1);
      commit;
    `);
    await proveBlocked();
    const firstResult = await first.release();
    first = null;
    const secondResult = await secondPromise;
    if (firstResult.code !== 0) throw new Error(`FIRST_PROCESS_FAILED:${JSON.stringify(firstResult)}`);
    if (secondResult.code !== 0) throw new Error(`SECOND_PROCESS_FAILED:${JSON.stringify(secondResult)}`);
    if (!firstResult.stdout.includes('"replayed": false')) throw new Error(`FIRST_PROCESS_NOT_NEW:${firstResult.stdout}`);
    if (!secondResult.stdout.includes('"replayed": true')) throw new Error(`SECOND_PROCESS_NOT_REPLAY:${secondResult.stdout}`);

    const summary = JSON.parse(query(`
      select json_build_object(
        'status',(select lifecycle_status from public.document_inbox_items where id='${inboxItemId}'),
        'expenses',(select count(*) from public.business_expenses where internal_reference='DOCUMENT-INBOX:${inboxItemId}'),
        'documents',(select count(*) from public.supplier_documents where rtrim(sha256)='${sha256}'),
        'links',(select count(*) from public.business_expense_documents where business_expense_id=(select result_business_expense_id from public.document_inbox_items where id='${inboxItemId}')),
        'processed_events',(select count(*) from public.document_inbox_events where inbox_item_id='${inboxItemId}' and event_type='PROCESSED')
      )
    `));
    if (summary.status !== "PROCESSED" || summary.expenses !== 1 || summary.documents !== 1 || summary.links !== 1 || summary.processed_events !== 1) {
      throw new Error(`CONCURRENT_PROCESS_DUPLICATE:${JSON.stringify(summary)}`);
    }
    process.stdout.write(JSON.stringify({
      test_context: "LOCAL_TEST_ONLY",
      lock_wait_proven: true,
      first_process_replayed: false,
      second_process_replayed: true,
      ...summary,
    }) + "\n");
  } finally {
    if (first) await first.abort();
    cleanup();
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
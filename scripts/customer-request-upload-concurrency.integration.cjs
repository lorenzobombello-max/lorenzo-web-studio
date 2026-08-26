const { spawn, spawnSync } = require("node:child_process");

const container = process.env.SUPABASE_DB_CONTAINER || "supabase_db_xcsptvntvrizwhskaphr";
const psqlArgs = ["exec", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c"];
const requestId = "ca920000-0000-4000-8000-000000000001";
const uploadRequestId = "ca930000-0000-4000-8000-000000000001";
const operatorId = "ca910000-0000-4000-8000-000000000001";
const tokenDigest = "9".repeat(64);
const reservationCount = 6;

function query(sql) {
  const result = spawnSync("docker", [...psqlArgs, sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim();
}

function run(sql) {
  return new Promise((resolve) => {
    const child = spawn("docker", [...psqlArgs, sql]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => stdout += data);
    child.stderr.on("data", (data) => stderr += data);
    child.on("exit", (code) => resolve({ code, stdout: stdout.trim(), stderr: stderr.trim() }));
  });
}

function cleanup() {
  query(`set session_replication_role = replica;
    delete from lws_internal.customer_request_upload_operations where upload_request_id = '${uploadRequestId}';
    delete from public.customer_request_uploaded_files where upload_request_id = '${uploadRequestId}';
    delete from public.customer_request_upload_requests where upload_request_id = '${uploadRequestId}';
    delete from public.customer_requests where request_id = '${requestId}';
    set session_replication_role = origin;`);
}

cleanup();
query(`set session_replication_role = replica;
  insert into public.customer_requests(
    request_id, request_reference, quote_request_id, customer_id, project_id, source,
    request_type, title, description, status, priority, submitted_at, submitter_type
  ) values (
    '${requestId}', 'LWS-VRZ-2199-0901', 'ca940000-0000-4000-8000-000000000001',
    'ca950000-0000-4000-8000-000000000001', 'ca960000-0000-4000-8000-000000000001',
    'OPERATOR', 'FILE_DELIVERY', 'Parallel upload proof', 'Local concurrency fixture.',
    'WAITING_CUSTOMER', 'NORMAL', statement_timestamp(), 'OPERATOR'
  );
  insert into public.customer_request_upload_requests(
    upload_request_id, customer_request_id, token_digest, status, expires_at, created_by_operator_id
  ) values ('${uploadRequestId}', '${requestId}', '${tokenDigest}', 'ACTIVE', clock_timestamp() + interval '1 day', '${operatorId}');
  set session_replication_role = origin;`);

Promise.all(Array.from({ length: reservationCount }, (_, index) => run(
  `select public.prepare_customer_request_upload_v1(
    '${tokenDigest}', 'parallel-${index + 1}.pdf', 'application/pdf', 1,
    'ca970000-0000-4000-8000-${String(index + 1).padStart(12, "0")}'
  )->>'state';`
))).then((results) => {
  const failures = results.filter((result) => result.code !== 0);
  if (failures.length) throw new Error(`CONCURRENT_RESERVATION_FAILURE:${JSON.stringify(failures)}`);
  const outcomes = results.map((result) => result.stdout.split(/\r?\n/).filter(Boolean).at(-1)).sort();
  const prepared = outcomes.filter((state) => state === "PREPARED").length;
  const limited = outcomes.filter((state) => state === "LIMIT_EXCEEDED").length;
  const persisted = Number(query(`select count(*) from public.customer_request_uploaded_files where upload_request_id = '${uploadRequestId}' and status = 'PREPARED';`));
  if (prepared !== 5 || limited !== 1 || persisted !== 5) {
    throw new Error(`CONCURRENT_RESERVATION_LIMIT_BYPASS:${JSON.stringify({ outcomes, persisted })}`);
  }
  cleanup();
  process.stdout.write(JSON.stringify({
    test_context: "LOCAL_TEST_ONLY",
    concurrent_reservations: reservationCount,
    prepared,
    limit_exceeded: limited,
    persisted,
  }) + "\n");
}).catch((error) => {
  try { cleanup(); } catch {}
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
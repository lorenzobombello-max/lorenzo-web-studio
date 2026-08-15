const { spawnSync } = require("node:child_process");

const databaseName = process.env.LWS_D3E8_TEST_DATABASE;
if (!databaseName) throw new Error("LWS_D3E8_TEST_DATABASE_REQUIRED");
const container = "supabase_db_xcsptvntvrizwhskaphr";
const psqlArgs = ["exec", container, "psql", "-U", "postgres", "-d", databaseName, "-v", "ON_ERROR_STOP=1", "-At", "-c"];

function query(sql, allowFailure = false) {
  const result = spawnSync("docker", [...psqlArgs, sql], { encoding: "utf8" });
  if (!allowFailure && result.status !== 0) throw new Error(result.stderr || result.stdout);
  return { status: result.status, stdout: result.stdout.trim(), stderr: result.stderr.trim() };
}

function acceptSql(issuanceId, key, name, email) {
  return `select concat_ws('|',acceptance_id,acceptance_payload_sha256,accepted_at,was_created)
    from public.accept_quotation_v1('${issuanceId}',1,repeat('b',64),
    'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',
    '${name}','${email}','D3E8 Test Customer','Bestuurder',true,'${key}',repeat('f',64));`;
}

function capabilitySql(issuanceId, digest, key) {
  return `select concat_ws('|',capability_id,expires_at,was_created)
    from public.create_quotation_acceptance_capability_v1('${issuanceId}','${digest}',null,'${key}',repeat('f',64),'admin:TEST_ONLY_D3E9');`;
}

function race(sqlA, sqlB) {
  const script = `
    const { spawn } = require('node:child_process');
    const args = ${JSON.stringify(psqlArgs.slice(0, -1))};
    const run = (sql) => new Promise((resolve) => {
      const child = spawn('docker', [...args, '-c', sql]);
      let out='', err=''; child.stdout.on('data',d=>out+=d); child.stderr.on('data',d=>err+=d);
      child.on('exit',code=>resolve({code,out:out.trim(),err:err.trim()}));
    });
    Promise.all([run(${JSON.stringify(sqlA)}),run(${JSON.stringify(sqlB)})]).then(x=>process.stdout.write(JSON.stringify(x)));
  `;
  const result = spawnSync(process.execPath, ["-e", script], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr);
  return JSON.parse(result.stdout);
}

const issuance1 = query("select id from public.quote_request_quotation_issuances where approval_id='d3ea5000-0000-4000-8000-000000000001'").stdout;
const capabilityRace = race(
  capabilitySql(issuance1, "7".repeat(64), "d3e99000-0000-4000-8000-000000000201"),
  capabilitySql(issuance1, "8".repeat(64), "d3e99000-0000-4000-8000-000000000202"),
);
const capabilitySuccess = capabilityRace.filter((item) => item.code === 0);
const capabilityFailure = capabilityRace.filter((item) => item.code !== 0);
if (capabilitySuccess.length !== 1 || capabilityFailure.length !== 1
  || !/(ACTIVE_CAPABILITY_EXISTS|CAPABILITY_CONFLICT)/.test(capabilityFailure[0].err)) {
  throw new Error(`CAPABILITY_RACE_INVALID:${JSON.stringify(capabilityRace)}`);
}
const activeCapability = query(`select id from public.quote_request_quotation_acceptance_capabilities where issuance_id='${issuance1}' and status='ACTIVE'`).stdout;
const oldDigest = query(`select rtrim(token_digest) from public.quote_request_quotation_acceptance_capabilities where id='${activeCapability}'`).stdout;
query(`select * from public.revoke_quotation_acceptance_capability_v1('${activeCapability}','TEST_ONLY rotation','admin:TEST_ONLY_D3E9','d3e99000-0000-4000-8000-000000000203',repeat('f',64))`);
if (JSON.parse(query(`select public.resolve_quotation_acceptance_capability_v1('${oldDigest}')`).stdout).state !== "INVALID_OR_EXPIRED_LINK") {
  throw new Error("REVOKED_CAPABILITY_RESOLVED");
}
query(capabilitySql(issuance1, "9".repeat(64), "d3e99000-0000-4000-8000-000000000204"));
if (JSON.parse(query(`select public.resolve_quotation_acceptance_capability_v1('${"9".repeat(64)}')`).stdout).state !== "ACTIVE") {
  throw new Error("REPLACEMENT_CAPABILITY_NOT_ACTIVE");
}
query(`select * from public.revoke_quotation_acceptance_capability_v1((select id from public.quote_request_quotation_acceptance_capabilities where token_digest='${"9".repeat(64)}'),'TEST_ONLY cleanup','admin:TEST_ONLY_D3E9','d3e99000-0000-4000-8000-000000000205',repeat('f',64))`);
const conflict = race(
  acceptSql(issuance1, "d3e88000-0000-4000-8000-000000000201", "Actor A", "a@example.test"),
  acceptSql(issuance1, "d3e88000-0000-4000-8000-000000000202", "Actor B", "b@example.test"),
);
const conflictSuccess = conflict.filter((item) => item.code === 0);
const conflictFailure = conflict.filter((item) => item.code !== 0);
if (conflictSuccess.length !== 1 || conflictFailure.length !== 1 || !conflictFailure[0].err.includes("ACCEPTANCE_CONFLICT")) {
  throw new Error(`CONFLICT_RACE_INVALID:${JSON.stringify(conflict)}`);
}

query(`insert into public.quote_request_quotation_approvals(id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_version,approved_payload,payload_sha256,approved_by,approved_at)
  select 'd3ea5000-0000-4000-8000-000000000002',draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,2,approved_payload,payload_sha256,approved_by,clock_timestamp()
  from public.quote_request_quotation_approvals where id='d3ea5000-0000-4000-8000-000000000001';
  insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac) values('d3ea5000-0000-4000-8000-000000000002','hmac-sha256-v1','v1',repeat('e',64));
  select * from public.prepare_quotation_issuance_v2('d3ea5000-0000-4000-8000-000000000002',2099::smallint,1::smallint,repeat('2',64),'d3ea6000-0000-4000-8000-000000000202',repeat('f',64),'admin:TEST_ONLY');
  select * from public.commit_quotation_issuance_v2((select id from public.quote_request_quotation_issuances where approval_id='d3ea5000-0000-4000-8000-000000000002'),'d3ea7000-0000-4000-8000-000000000202',repeat('2',64),repeat('3',64),'LWS_QUOTATION_NL_BE','1.0.0-technical','3ad2faaaa6a0a06e566f462e1c65c631006019c0d2d462333b8c693eb11154de',1::smallint,repeat('4',64),100,null,null,'admin:TEST_ONLY',repeat('f',64));`);
const issuance2 = query("select id from public.quote_request_quotation_issuances where approval_id='d3ea5000-0000-4000-8000-000000000002'").stdout;
const equivalent = race(
  acceptSql(issuance2, "d3e88000-0000-4000-8000-000000000203", "Same Actor", "same@example.test"),
  acceptSql(issuance2, "d3e88000-0000-4000-8000-000000000204", "Same Actor", "same@example.test"),
);
if (equivalent.some((item) => item.code !== 0)) throw new Error(`EQUIVALENT_RACE_FAILED:${JSON.stringify(equivalent)}`);
const identities = equivalent.map((item) => item.out.split("|")[0]);
if (new Set(identities).size !== 1) throw new Error(`EQUIVALENT_IDENTITIES_DIFFER:${identities}`);
const counts = query("select concat_ws('|',(select count(*) from public.quote_request_quotation_acceptances),(select count(*) from public.quote_request_quotation_acceptance_events),(select count(*) from public.quote_request_quotation_acceptance_operations))").stdout;
if (counts !== "2|2|3") throw new Error(`CONCURRENCY_COUNTS_INVALID:${counts}`);

process.stdout.write(JSON.stringify({
  test_context: "TEST_ONLY",
  conflicting: { success: 1, conflict: 1, error: "ACCEPTANCE_CONFLICT" },
  equivalent: { success: 2, distinct_acceptance_ids: 1 },
  capability_creation: { success: 1, conflict: 1, max_active: 1 },
  capability_revocation: "PASS",
  capability_replacement: "PASS",
  authority_rows: 2,
  events: 2,
  operations: 3,
}) + "\n");

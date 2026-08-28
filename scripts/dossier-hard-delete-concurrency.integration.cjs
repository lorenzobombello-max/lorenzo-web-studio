const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = [
  "exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres",
  "-v", "ON_ERROR_STOP=1", "-At"
];
const ownerUserId = "fb000000-0000-4000-8000-000000000001";
const ownerOperatorId = "fb010000-0000-4000-8000-000000000001";
const issuanceWinsRequestId = "fb020000-0000-4000-8000-000000000001";
const purgeWinsRequestId = "fb020002-0000-4000-8000-000000000002";
const issuanceWinsApprovalId = "fb030000-0000-4000-8000-000000000001";
const purgeWinsApprovalId = "fb030000-0000-4000-8000-000000000002";

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

function startHoldingSession(sql, readyMarker) {
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
    if (!settled) readyReject(new Error(`SESSION_READY_TIMEOUT:${readyMarker}:${stderr || stdout}`));
  }, 5000);
  child.stdout.on("data", (data) => {
    stdout += data;
    if (!settled && stdout.includes(readyMarker)) {
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
      readyReject(new Error(`SESSION_EXITED_BEFORE_READY:${readyMarker}:${code}:${stderr || stdout}`));
    }
    resolve({ code, stdout, stderr });
  }));
  child.stdin.write(`${sql}\n`);
  return {
    ready,
    release: async () => {
      child.stdin.end("commit;\n");
      return await exited;
    },
    abort: async () => {
      if (child.exitCode === null) child.stdin.end("rollback;\n");
      return await exited;
    }
  };
}

async function proveBlocked(applicationName, blockerApplicationName) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const proof = query(`
      select exists (
        select 1
        from pg_stat_activity waiting
        join pg_stat_activity blocker
          on blocker.pid = any(pg_blocking_pids(waiting.pid))
        where waiting.application_name = '${applicationName}'
          and blocker.application_name = '${blockerApplicationName}'
          and waiting.wait_event_type = 'Lock'
      )
    `);
    if (proof === "t") return;
  }
  throw new Error(`LOCK_WAIT_NOT_PROVEN:${applicationName}:${blockerApplicationName}`);
}

function cleanupFixtures() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from public.quote_request_quotation_issuance_operations
    where issuance_id in (
      select id from public.quote_request_quotation_issuances
      where approval_id in ('${issuanceWinsApprovalId}','${purgeWinsApprovalId}')
    );
    delete from public.quote_request_quotation_issuances
    where approval_id in ('${issuanceWinsApprovalId}','${purgeWinsApprovalId}');
    delete from public.quotation_number_counters where year = 9876;
    delete from public.quote_request_quotation_approval_integrity
    where approval_id in ('${issuanceWinsApprovalId}','${purgeWinsApprovalId}');
    delete from public.quote_request_quotation_approvals
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from public.quote_request_quotation_approval_drafts
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from public.quote_request_pricing_snapshot_integrity
    where snapshot_id in (
      select snapshot.id from public.quote_request_pricing_snapshots snapshot
      join public.quote_request_intakes intake on intake.id = snapshot.intake_id
      where intake.quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}')
    );
    delete from public.quote_request_pricing_snapshots
    where intake_id in (
      select id from public.quote_request_intakes
      where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}')
    );
    delete from public.quote_request_intakes
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.dossier_preofficial_quotation_tombstones
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.dossier_purge_tombstones
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.operator_dossier_assignments
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.operator_dossier_states
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from public.quote_requests
    where id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.intake_identity_anchors
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.dossier_identity_anchors
    where quote_request_id in ('${issuanceWinsRequestId}','${purgeWinsRequestId}');
    delete from public.commercial_operators where operator_id = '${ownerOperatorId}';
    delete from auth.users where id = '${ownerUserId}';
    commit;
    select 'CLEAN';
  `);
}

function createFixtures() {
  query(`
    insert into auth.users(id,email)
    values('${ownerUserId}','purge-concurrency-owner@example.test');
    insert into public.commercial_operators(
      operator_id,auth_user_id,display_name,role,status
    ) values('${ownerOperatorId}','${ownerUserId}','Purge Concurrency Owner','owner','ACTIVE');

    create function pg_temp.create_fixture(
      p_quote_request_id uuid,
      p_approval_id uuid,
      p_suffix text
    ) returns void language plpgsql as \$\$
    declare
      v_intake_id uuid := gen_random_uuid();
      v_snapshot_id uuid := gen_random_uuid();
      v_draft_id uuid := gen_random_uuid();
      v_payload jsonb;
    begin
      insert into public.quote_requests(
        id,application_reference,record_classification,request_kind,name,email,
        website_type,budget,timing,description,privacy_consent,status
      ) values(
        p_quote_request_id,'LWS-AAN-2099-' || p_suffix,'production','website',
        'Purge race fixture','purge-race-' || p_suffix || '@example.test',
        'business','EUR 3.200 t/m EUR 6.000','flexible',
        'Local purge race fixture.',true,'approved'
      );
      insert into public.quote_request_intakes(
        id,quote_request_id,status,access_token_hash,access_token_expires_at,
        started_at,submitted_at,confirmation,admin_access_token_hash,
        admin_access_token_expires_at
      ) values(
        v_intake_id,p_quote_request_id,'submitted',repeat(reverse(p_suffix),16),
        clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),true,
        repeat(p_suffix,16),clock_timestamp()+interval '1 day'
      );
      insert into public.quote_request_pricing_snapshots(
        id,intake_id,snapshot_contract_version,config_version,config_hash,
        normalized_evidence,calculation,package_advice,budget_evaluation
      ) values(
        v_snapshot_id,v_intake_id,2,'1.0.0',repeat('1',64),
        '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
        '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":10000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000}]}',
        '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
        '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
      );
      insert into public.quote_request_pricing_snapshot_integrity(
        snapshot_id,algorithm_version,key_id,mac
      ) values(v_snapshot_id,'hmac-sha256-v1','v1',repeat('a',64));
      v_payload := jsonb_build_object(
        'contract_version',1,'source_quote_request_id',p_quote_request_id::text,
        'source_intake_id',v_intake_id::text,
        'pricing_snapshot',jsonb_build_object(
          'snapshot_id',v_snapshot_id::text,'snapshot_contract_version',2,
          'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1',
          'integrity_mac',repeat('a',64)
        ),'currency','EUR',
        'line_items',jsonb_build_array(jsonb_build_object(
          'line_id','website','sequence',1,'product_or_service_code','WEBSITE',
          'description','Websiteontwikkeling','quantity',1,'unit','project',
          'unit_price_minor',10000,'discount_minor',0,'vat_treatment','STANDARD',
          'vat_rate',21,'line_net_amount_minor',10000,'cost_type','ONE_TIME'
        )),
        'totals',jsonb_build_object(
          'one_time_subtotal_minor',10000,'recurring_subtotal_minor',0,
          'discount_total_minor',0,'vat_base_minor',10000,'vat_amount_minor',2100,
          'total_gross_minor',12100
        ),
        'discount',jsonb_build_object(
          'discount_type',null,'discount_value_minor',0,'discount_reason',null,
          'approved_by',null,'approved_at',null
        ),
        'customer_identity',jsonb_build_object(
          'source_quote_request_id',p_quote_request_id::text,
          'source_intake_id',v_intake_id::text,'customer_id',null,
          'legal_name','Race Fixture','contact_name',null,
          'email','purge-race@example.test','address_line_1','Teststraat 1',
          'address_line_2',null,'postal_code','9000','city','Gent','country_code','BE',
          'enterprise_number',null,'vat_number',null,
          'source_fields',jsonb_build_object('legal_name','fixture'),
          'snapshot_sha256',repeat('b',64)
        ),
        'project_scope',jsonb_build_object(
          'project_id',null,'project_title','Race website','project_type','website',
          'scope_summary','Local fixture','requested_languages',jsonb_build_array('nl'),
          'included_page_count',1,'features','[]'::jsonb,'copywriting',null,'seo',null,
          'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,
          'assumptions','[]'::jsonb,'indicative_timing',null,
          'source_intake_id',v_intake_id::text,
          'source_pricing_snapshot_id',v_snapshot_id::text,
          'snapshot_sha256',repeat('c',64)
        ),
        'vat_approval',jsonb_build_object(
          'vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant',
          'vat_approved_by','accountant:test','vat_approved_at','2026-08-15T12:00:00Z'
        ),
        'payment_schedule',jsonb_build_object(
          'schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object(
            'sequence',1,'label','Volledige betaling','percentage',100,
            'amount_minor',null,'trigger','invoice','due_terms_days',30,
            'recurring_cycle',null
          )),'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'
        ),
        'validity',jsonb_build_object(
          'valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30,
          'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'
        ),
        'legal_references',jsonb_build_object(
          'terms_reference','terms-v1','terms_version','1.0.0',
          'terms_sha256',repeat('d',64),'terms_status','APPROVED',
          'agreement_template_reference',null,'agreement_template_version',null,
          'agreement_template_sha256',null
        )
      );
      insert into public.quote_request_quotation_approval_drafts(
        id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,
        approval_payload,payload_fingerprint,idempotency_key,created_by
      ) values(
        v_draft_id,p_quote_request_id,v_intake_id,v_snapshot_id,1,v_payload,
        public.quotation_approval_payload_sha256_v1(v_payload),gen_random_uuid(),
        'test:purge-race'
      );
      insert into public.quote_request_quotation_approvals(
        id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,
        approval_version,approved_payload,payload_sha256,approved_by,approved_at
      ) values(
        p_approval_id,v_draft_id,p_quote_request_id,v_intake_id,v_snapshot_id,1,1,
        v_payload,public.quotation_approval_payload_sha256_v1(v_payload),
        'test:purge-race',clock_timestamp()
      );
      insert into public.quote_request_quotation_approval_integrity(
        approval_id,algorithm_version,key_id,mac
      ) values(p_approval_id,'hmac-sha256-v1','v1',repeat('e',64));
      update lws_internal.operator_dossier_states
      set state='TRASHED',revision=revision+1,state_before_trash='ACTIVE',
          deletion_eligible_at=null,updated_at=clock_timestamp()
      where quote_request_id=p_quote_request_id;
    end;
    \$\$;

    select pg_temp.create_fixture(
      '${issuanceWinsRequestId}','${issuanceWinsApprovalId}','0901'
    );
    select pg_temp.create_fixture(
      '${purgeWinsRequestId}','${purgeWinsApprovalId}','0902'
    );
  `);
}

async function main() {
  let holdingSession = null;
  if (query("select current_database()") !== "postgres") {
    throw new Error("LOCAL_TEST_ENVIRONMENT_REQUIRED");
  }
  try {
    cleanupFixtures();
    createFixtures();

    holdingSession = startHoldingSession(`
      set application_name = 'lws_issuance_winner';
      begin;
      select * from public.prepare_quotation_issuance_v2(
        '${issuanceWinsApprovalId}',9876::smallint,1::smallint,repeat('1',64),
        'fb040000-0000-4000-8000-000000000001',repeat('0901',16),'test:purge-race'
      );
      select 'ISSUANCE_LOCK_HELD';
    `, "ISSUANCE_LOCK_HELD");
    await holdingSession.ready;
    const purgeWaiter = run(`
      set application_name = 'lws_purge_after_issuance';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claim.sub','${ownerUserId}',true);
      select public.purge_dossier_v1(
        '${issuanceWinsRequestId}','Issuance wins race',
        'fb050000-0000-4000-8000-000000000001'
      );
      commit;
    `);
    await proveBlocked("lws_purge_after_issuance", "lws_issuance_winner");
    const issuanceWinner = await holdingSession.release();
    holdingSession = null;
    const purgeLoser = await purgeWaiter;
    if (issuanceWinner.code !== 0) throw new Error(`ISSUANCE_WINNER_FAILED:${JSON.stringify(issuanceWinner)}`);
    if (purgeLoser.code === 0 || !purgeLoser.stderr.includes("OFFICIAL_QUOTATION_EXISTS")) {
      throw new Error(`PURGE_DID_NOT_FAIL_CLOSED:${JSON.stringify(purgeLoser)}`);
    }
    if (query(`select count(*)=1 from public.quote_requests where id='${issuanceWinsRequestId}'`) !== "t"
        || query(`select count(*)=1 from public.quote_request_quotation_issuances where approval_id='${issuanceWinsApprovalId}'`) !== "t") {
      throw new Error("ISSUANCE_WINNER_LEFT_SPLIT_STATE");
    }

    holdingSession = startHoldingSession(`
      set application_name = 'lws_purge_winner';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claim.sub','${ownerUserId}',true);
      select public.purge_dossier_v1(
        '${purgeWinsRequestId}','Purge wins race',
        'fb050000-0000-4000-8000-000000000002'
      );
      select 'PURGE_LOCK_HELD';
    `, "PURGE_LOCK_HELD");
    await holdingSession.ready;
    const issuanceWaiter = run(`
      set application_name = 'lws_issuance_after_purge';
      begin;
      select * from public.prepare_quotation_issuance_v2(
        '${purgeWinsApprovalId}',9876::smallint,1::smallint,repeat('2',64),
        'fb040000-0000-4000-8000-000000000002',repeat('0902',16),'test:purge-race'
      );
      commit;
    `);
    await proveBlocked("lws_issuance_after_purge", "lws_purge_winner");
    const purgeWinner = await holdingSession.release();
    holdingSession = null;
    const issuanceLoser = await issuanceWaiter;
    if (purgeWinner.code !== 0) throw new Error(`PURGE_WINNER_FAILED:${JSON.stringify(purgeWinner)}`);
    if (issuanceLoser.code === 0 || !issuanceLoser.stderr.includes("DOSSIER_PURGED")) {
      throw new Error(`ISSUANCE_DID_NOT_FAIL_CLOSED:${JSON.stringify(issuanceLoser)}`);
    }
    if (query(`select count(*)=0 from public.quote_requests where id='${purgeWinsRequestId}'`) !== "t"
        || query(`select count(*)=1 from lws_internal.dossier_purge_tombstones where quote_request_id='${purgeWinsRequestId}'`) !== "t"
        || query(`select count(*)=0 from public.quote_request_quotation_issuances where approval_id='${purgeWinsApprovalId}'`) !== "t") {
      throw new Error("PURGE_WINNER_LEFT_SPLIT_STATE");
    }

    process.stdout.write(JSON.stringify({
      test_context: "LOCAL_TEST_ONLY",
      issuance_winner_lock_wait_proven: true,
      issuance_winner_result: "OFFICIAL_QUOTATION_EXISTS",
      purge_winner_lock_wait_proven: true,
      purge_winner_result: "DOSSIER_PURGED",
      split_state_observed: false
    }) + "\n");
  } finally {
    if (holdingSession) await holdingSession.abort();
    cleanupFixtures();
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
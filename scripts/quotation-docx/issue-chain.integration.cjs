const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const dbContainer = "supabase_db_xcsptvntvrizwhskaphr";
const databaseName = process.env.LWS_D3E7_TEST_DATABASE || "postgres";
const fixtureFile = path.resolve(__dirname, "../../supabase/tests/quotation_issuance_hash_binding.sql");
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "lws-d3e7-issue-"));
const outputPath = path.join(tempRoot, "synthetic-issue.docx");
const inputPath = path.join(tempRoot, "issue-payload.json");
const evidencePath = path.join(tempRoot, "issue-evidence.json");
const templateSha256 = "3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE";
const templateSha256Lower = templateSha256.toLowerCase();

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function waitForLine(process, prefix) {
  return new Promise((resolve, reject) => {
    let buffer = "";
    const onData = (chunk) => {
      buffer += chunk.toString();
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop();
      for (const line of lines) {
        if (line.startsWith(prefix)) {
          cleanup();
          resolve(line.slice(prefix.length));
        }
      }
    };
    const onExit = (code) => {
      cleanup();
      reject(new Error(`PSQL_EXITED_BEFORE_${prefix}:${code}`));
    };
    const cleanup = () => {
      process.stdout.off("data", onData);
      process.off("exit", onExit);
    };
    process.stdout.on("data", onData);
    process.once("exit", onExit);
  });
}

async function main() {
  const psql = spawn("docker", ["exec", "-i", dbContainer, "psql", "-U", "postgres", "-d", databaseName, "-v", "ON_ERROR_STOP=1", "-At"], {
    stdio: ["pipe", "pipe", "inherit"],
  });
  let rolledBack = false;
  try {
    const fixture = fs.readFileSync(fixtureFile, "utf8");
    const setupStart = fixture.indexOf("create temporary table d3e3a_source");
    const setupEnd = fixture.indexOf("select is((select quotation_number from public.prepare_quotation_issuance_v2");
    if (setupStart < 0 || setupEnd < 0) throw new Error("D3E3A_FIXTURE_BOUNDARY_NOT_FOUND");
    const setup = fixture.slice(setupStart, setupEnd).replace(
      /select is\(\(select count\(\*\)::integer from d3e3a_source\), 0, 'focused suite starts without production approval data'\);/,
      "",
    );
    const payloadLine = waitForLine(psql, "D3E7_PAYLOAD|");
    psql.stdin.write(`begin; set local search_path=public,extensions;\n${setup}\n`);
    psql.stdin.write(`
      select * from public.prepare_quotation_issuance_v2(
        'd3ea5000-0000-4000-8000-000000000001', 2099::smallint, 1::smallint,
        repeat('1',64), 'd3ea6000-0000-4000-8000-000000000099',
        repeat('f',64), 'admin:TEST_ONLY_D3E7'
      );
      select 'D3E7_PAYLOAD|' || encode(convert_to(jsonb_build_object(
        'payload', built.payload,
        'payload_sha256', built.payload_sha256,
        'issuance_input_sha256', rtrim(issuance.issuance_input_sha256),
        'issuance_id', issuance.id
      )::text,'UTF8'),'hex')
      from public.quote_request_quotation_issuances issuance
      cross join lateral public.build_quotation_issue_payload_v1(
        issuance.id,
        jsonb_build_object(
          'template_id','LWS_QUOTATION_NL_BE',
          'template_version','1.0.0-technical',
          'template_sha256','${templateSha256Lower}',
          'authority_status','APPROVED'
        ),
        jsonb_build_object(
          'legal_name','Lorenzo Web Solutions','address_line_1','Teststraat 1',
          'address_line_2',null,'postal_code','9000','city','Gent','country_code','BE',
          'enterprise_number','0123456789','vat_number','BE0123456789',
          'email','seller@example.test','website','https://example.test','contact_name',null
        ), repeat('f',64)
      ) built
      where issuance.approval_id='d3ea5000-0000-4000-8000-000000000001';
    `);

    const encoded = await payloadLine;
    const input = JSON.parse(Buffer.from(encoded, "hex").toString("utf8"));
    if (input.payload.mode !== "ISSUE") throw new Error("ISSUE_PAYLOAD_MODE_INVALID");
    if (!/^LWS-OFF-2099-[0-9]{4}$/.test(input.payload.quotation.quotation_number)) throw new Error("TEST_ONLY_NUMBER_INVALID");
    if (input.payload.template.template_sha256 !== templateSha256Lower) throw new Error("TEMPLATE_HASH_BINDING_INVALID");
    fs.writeFileSync(inputPath, JSON.stringify(input));
    const rendered = spawnSync(process.execPath, [
      path.resolve(__dirname, "issue-render.integration.cjs"),
      inputPath, outputPath, evidencePath,
    ], { encoding: "utf8" });
    if (rendered.status !== 0) throw new Error(`ISSUE_RENDER_VALIDATION_FAILED:${rendered.stderr}`);
    const evidence = JSON.parse(fs.readFileSync(evidencePath, "utf8"));

    const commitLine = waitForLine(psql, "D3E7_COMMIT|");
    psql.stdin.write(`
      select 'D3E7_COMMIT|' || concat_ws('|', status, generation_payload_sha256, was_committed)
      from public.commit_quotation_issuance_v2(
        ${sqlLiteral(input.issuance_id)}::uuid,
        'd3ea7000-0000-4000-8000-000000000099'::uuid,
        ${sqlLiteral(input.issuance_input_sha256)}, ${sqlLiteral(input.payload_sha256)},
        'LWS_QUOTATION_NL_BE','1.0.0-technical',${sqlLiteral(templateSha256Lower)},
        1::smallint,${sqlLiteral(evidence.docx_sha256)},${evidence.docx_bytes},null,null,
        'admin:TEST_ONLY_D3E7',repeat('f',64)
      );
    `);
    const commit = (await commitLine).split("|");
    if (commit[0] !== "ISSUED" || commit[1] !== input.payload_sha256 || commit[2] !== "t") throw new Error(`ISSUE_COMMIT_INVALID:${commit.join("|")}`);

    const replayLine = waitForLine(psql, "D3E7_REPLAY|");
    psql.stdin.write(`
      select 'D3E7_REPLAY|' || concat_ws('|', status, generation_payload_sha256, was_committed)
      from public.commit_quotation_issuance_v2(
        ${sqlLiteral(input.issuance_id)}::uuid,
        'd3ea7000-0000-4000-8000-000000000099'::uuid,
        ${sqlLiteral(input.issuance_input_sha256)}, ${sqlLiteral(input.payload_sha256)},
        'LWS_QUOTATION_NL_BE','1.0.0-technical',${sqlLiteral(templateSha256Lower)},
        1::smallint,${sqlLiteral(evidence.docx_sha256)},${evidence.docx_bytes},null,null,
        'admin:TEST_ONLY_D3E7',repeat('f',64)
      );
    `);
    const replay = (await replayLine).split("|");
    if (replay[0] !== "ISSUED" || replay[1] !== input.payload_sha256 || replay[2] !== "f") throw new Error(`ISSUE_REPLAY_INVALID:${replay.join("|")}`);

    const historicalSetupLine = waitForLine(psql, "D3E8_HISTORICAL_SETUP|");
    psql.stdin.write(`
      insert into public.quote_request_quotation_approvals(
        id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,
        contract_version,approval_version,approved_payload,payload_sha256,
        approved_by,approved_at
      )
      select 'd3ea5000-0000-4000-8000-000000000002',draft_id,quote_request_id,
        intake_id,pricing_snapshot_id,contract_version,2,
        jsonb_set(jsonb_set(approved_payload,'{validity,valid_from}','"2026-06-01"'),
          '{validity,valid_until}','"2026-07-01"'),
        public.quotation_approval_payload_sha256_v1(
          jsonb_set(jsonb_set(approved_payload,'{validity,valid_from}','"2026-06-01"'),
            '{validity,valid_until}','"2026-07-01"')
        ),approved_by,clock_timestamp()
      from public.quote_request_quotation_approvals
      where id='d3ea5000-0000-4000-8000-000000000001';
      insert into public.quote_request_quotation_approval_integrity(
        approval_id,algorithm_version,key_id,mac
      ) values('d3ea5000-0000-4000-8000-000000000002','hmac-sha256-v1','v1',repeat('e',64));
      select * from public.prepare_quotation_issuance_v2(
        'd3ea5000-0000-4000-8000-000000000002',2099::smallint,1::smallint,
        repeat('2',64),'d3ea6000-0000-4000-8000-000000000102',repeat('f',64),'admin:TEST_ONLY_D3E8'
      );
      select * from public.commit_quotation_issuance_v2(
        (select id from public.quote_request_quotation_issuances where approval_id='d3ea5000-0000-4000-8000-000000000002'),
        'd3ea7000-0000-4000-8000-000000000102',repeat('2',64),repeat('3',64),
        'LWS_QUOTATION_NL_BE','1.0.0-technical',${sqlLiteral(templateSha256Lower)},
        1::smallint,repeat('4',64),100,null,null,'admin:TEST_ONLY_D3E8',repeat('f',64)
      );
      select public.retire_quotation_template_v1(
        (select id from public.quotation_template_authorities where template_id='LWS_QUOTATION_NL_BE'),
        'admin:TEST_ONLY_D3E8','Historical acceptance test','D3E8_RETIRE_AFTER_ISSUE'
      );
      select 'D3E8_HISTORICAL_SETUP|PASS';
    `);
    if (await historicalSetupLine !== "PASS") throw new Error("HISTORICAL_SETUP_FAILED");

    const negativeLine = waitForLine(psql, "D3E8_NEGATIVES|");
    psql.stdin.write(`
      do $$begin
        perform * from public.accept_quotation_v1(${sqlLiteral(input.issuance_id)}::uuid,2,repeat('b',64),
          'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical','Test','test@example.test',null,null,true,
          'd3e88000-0000-4000-8000-000000000091',repeat('f',64));
        raise exception 'EXPECTED_VERSION_MISMATCH';
      exception when sqlstate 'P0001' then if sqlerrm<>'QUOTATION_VERSION_MISMATCH' then raise;end if;end$$;
      do $$begin
        perform * from public.accept_quotation_v1(${sqlLiteral(input.issuance_id)}::uuid,1,repeat('0',64),
          'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical','Test','test@example.test',null,null,true,
          'd3e88000-0000-4000-8000-000000000092',repeat('f',64));
        raise exception 'EXPECTED_CUSTOMER_MISMATCH';
      exception when sqlstate 'P0001' then if sqlerrm<>'CUSTOMER_IDENTITY_MISMATCH' then raise;end if;end$$;
      do $$begin
        perform * from public.accept_quotation_v1(${sqlLiteral(input.issuance_id)}::uuid,1,repeat('b',64),
          'UNKNOWN_TERMS','9.9.9','Test','test@example.test',null,null,true,
          'd3e88000-0000-4000-8000-000000000093',repeat('f',64));
        raise exception 'EXPECTED_TERMS_REJECTION';
      exception when sqlstate 'P0001' then if sqlerrm<>'ACCEPTANCE_TERMS_NOT_APPROVED' then raise;end if;end$$;
      do $$begin
        perform * from public.accept_quotation_v1(
          (select id from public.quote_request_quotation_issuances where approval_id='d3ea5000-0000-4000-8000-000000000002'),
          1,repeat('b',64),'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',
          'Expired Actor','expired@example.test',null,null,true,
          'd3e88000-0000-4000-8000-000000000094',repeat('f',64));
        raise exception 'EXPECTED_EXPIRY';
      exception when sqlstate 'P0001' then if sqlerrm<>'QUOTATION_EXPIRED' then raise;end if;end$$;
      select 'D3E8_NEGATIVES|PASS';
    `);
    if (await negativeLine !== "PASS") throw new Error("ACCEPTANCE_NEGATIVES_FAILED");

    const acceptanceLine = waitForLine(psql, "D3E8_ACCEPT|");
    psql.stdin.write(`
      select 'D3E8_ACCEPT|' || concat_ws('|', acceptance_id, issuance_id,
        quotation_number, quotation_version, acceptance_payload_sha256,
        accepted_at, was_created)
      from public.accept_quotation_v1(
        ${sqlLiteral(input.issuance_id)}::uuid, 1, repeat('b',64),
        'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',
        'Test Acceptant','acceptant@example.test','D3E8 Test Customer','Bestuurder',
        true,'d3e88000-0000-4000-8000-000000000099'::uuid,repeat('f',64)
      );
    `);
    const acceptance = (await acceptanceLine).split("|");
    if (acceptance.length !== 7 || acceptance[2] !== input.payload.quotation.quotation_number
      || acceptance[3] !== "1" || !/^[0-9a-f]{64}$/.test(acceptance[4])
      || acceptance[6] !== "t") throw new Error(`ACCEPTANCE_INVALID:${acceptance.join("|")}`);

    const acceptanceReplayLine = waitForLine(psql, "D3E8_ACCEPT_REPLAY|");
    psql.stdin.write(`
      select 'D3E8_ACCEPT_REPLAY|' || concat_ws('|', acceptance_id,
        acceptance_payload_sha256, accepted_at, was_created)
      from public.accept_quotation_v1(
        ${sqlLiteral(input.issuance_id)}::uuid, 1, repeat('b',64),
        'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',
        'Test Acceptant','acceptant@example.test','D3E8 Test Customer','Bestuurder',
        true,'d3e88000-0000-4000-8000-000000000099'::uuid,repeat('f',64)
      );
    `);
    const acceptanceReplay = (await acceptanceReplayLine).split("|");
    if (acceptanceReplay[0] !== acceptance[0] || acceptanceReplay[1] !== acceptance[4]
      || acceptanceReplay[2] !== acceptance[5] || acceptanceReplay[3] !== "f") {
      throw new Error(`ACCEPTANCE_REPLAY_INVALID:${acceptanceReplay.join("|")}`);
    }

    const acceptanceConflictLine = waitForLine(psql, "D3E8_ACCEPT_CONFLICT|");
    psql.stdin.write(`
      do $$begin
        perform * from public.accept_quotation_v1(
          ${sqlLiteral(input.issuance_id)}::uuid, 1, repeat('b',64),
          'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',
          'Other Actor','other@example.test',null,null,true,
          'd3e88000-0000-4000-8000-000000000099'::uuid,repeat('f',64)
        );
        raise exception 'EXPECTED_IDEMPOTENCY_CONFLICT';
      exception when sqlstate 'P0001' then
        if sqlerrm <> 'IDEMPOTENCY_CONFLICT' then raise; end if;
      end$$;
      select 'D3E8_ACCEPT_CONFLICT|PASS';
    `);
    if (await acceptanceConflictLine !== "PASS") throw new Error("ACCEPTANCE_CONFLICT_NOT_CONFIRMED");

    const acceptanceEvidenceLine = waitForLine(psql, "D3E8_ACCEPT_EVIDENCE|");
    psql.stdin.write(`
      select 'D3E8_ACCEPT_EVIDENCE|' || concat_ws('|',
        (select count(*) from public.quote_request_quotation_acceptances),
        (select count(*) from public.quote_request_quotation_acceptance_events),
        (select count(*) from public.quote_request_quotation_acceptance_operations),
        (select rtrim(docx_sha256) from public.quote_request_quotation_acceptances),
        (select rtrim(template_sha256) from public.quote_request_quotation_acceptances),
        (select rtrim(generation_payload_sha256) from public.quote_request_quotation_acceptances)
      );
    `);
    const acceptanceEvidence = (await acceptanceEvidenceLine).split("|");
    if (acceptanceEvidence[0] !== "1" || acceptanceEvidence[1] !== "1"
      || acceptanceEvidence[2] !== "1" || acceptanceEvidence[3] !== evidence.docx_sha256
      || acceptanceEvidence[4] !== templateSha256Lower
      || acceptanceEvidence[5] !== input.payload_sha256) {
      throw new Error(`ACCEPTANCE_EVIDENCE_INVALID:${acceptanceEvidence.join("|")}`);
    }
    const immutabilityLine = waitForLine(psql, "D3E8_IMMUTABILITY|");
    psql.stdin.write(`
      do $$begin
        update public.quote_request_quotation_acceptances set accepting_name='Changed';
        raise exception 'EXPECTED_UPDATE_BLOCK';
      exception when sqlstate '55000' then
        if sqlerrm<>'QUOTATION_ACCEPTANCE_IMMUTABLE' then raise;end if;
      end$$;
      do $$begin
        delete from public.quote_request_quotation_acceptances;
        raise exception 'EXPECTED_DELETE_BLOCK';
      exception when sqlstate '55000' then
        if sqlerrm<>'QUOTATION_ACCEPTANCE_IMMUTABLE' then raise;end if;
      end$$;
      select 'D3E8_IMMUTABILITY|PASS';
      rollback;
      select 'D3E7_ROLLBACK|PASS';
    `);
    if (await immutabilityLine !== "PASS") throw new Error("ACCEPTANCE_IMMUTABILITY_FAILED");
    const rollbackLine = waitForLine(psql, "D3E7_ROLLBACK|");
    if (await rollbackLine !== "PASS") throw new Error("ROLLBACK_NOT_CONFIRMED");
    rolledBack = true;
    psql.stdin.end();
    const exitCode = await new Promise((resolve) => psql.once("exit", resolve));
    if (exitCode !== 0) throw new Error(`PSQL_EXIT:${exitCode}`);

    process.stdout.write(JSON.stringify({
      test_context: "TEST_ONLY",
      quotation_number: input.payload.quotation.quotation_number,
      issuance_input_sha256: input.issuance_input_sha256,
      generation_payload_sha256: input.payload_sha256,
      template_sha256: templateSha256Lower,
      docx_sha256: evidence.docx_sha256,
      docx_bytes: evidence.docx_bytes,
      openxml: "PASS",
      content_extraction: "PASS",
      security_leakage: "PASS",
      deterministic_render: "PASS",
      commit_status: "ISSUED",
      commit_retry: "IDEMPOTENT",
      acceptance_id: acceptance[0],
      acceptance_payload_sha256: acceptance[4],
      accepted_at: acceptance[5],
      acceptance_retry: "IDEMPOTENT",
      acceptance_conflict: "PASS",
      acceptance_artifact_binding: "PASS",
      acceptance_immutability: "PASS",
      acceptance_customer_binding: "PASS",
      acceptance_version_binding: "PASS",
      acceptance_terms_binding: "PASS",
      expiration_rejection: "PASS",
      historical_retired_template_acceptance: "PASS",
      rollback: "PASS",
    }) + "\n");
  } finally {
    if (!rolledBack && !psql.killed) {
      psql.stdin.write("rollback;\n");
      psql.stdin.end();
    }
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

create function pg_temp.fixture_uuid(p_value text)
returns uuid
language sql
immutable
set search_path = pg_catalog
as $$
  select (
    substr(md5(p_value), 1, 8) || '-' || substr(md5(p_value), 9, 4) || '-4' ||
    substr(md5(p_value), 14, 3) || '-8' || substr(md5(p_value), 18, 3) || '-' ||
    substr(md5(p_value), 21, 12)
  )::uuid
$$;

create function pg_temp.set_role_claim(p_role text, p_subject uuid default null, p_aal text default null)
returns void
language sql
set search_path = pg_catalog
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_strip_nulls(jsonb_build_object('role', p_role, 'sub', p_subject, 'aal', p_aal))::text,
    true
  )::text
$$;

create function pg_temp.jsonb_keys(p_value jsonb)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(array_agg(key order by key), array[]::text[])
  from jsonb_object_keys(p_value) as keys(key)
$$;

create function pg_temp.evidence(p_type text, p_target text, p_source_sha text)
returns jsonb
language plpgsql
stable
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_details jsonb;
begin
  v_details := case p_type
    when 'REPOSITORY_ROUTE' then jsonb_build_object(
      'path', p_target, 'object_type', 'tree', 'object_sha', repeat('b', 40)
    )
    when 'REPOSITORY_FILE' then jsonb_build_object(
      'path', p_target, 'object_type', 'blob', 'object_sha', repeat('c', 40)
    )
    when 'TEST_RUN' then jsonb_build_object(
      'suite_id', p_target, 'suite_version', 1, 'run_id', 'task4-run-1'
    )
    when 'CONTENT_MARKER' then jsonb_build_object(
      'path', p_target,
      'marker_key', 'LWS_APPROVED_CONTENT',
      'marker_version', 1,
      'marker_sha256', lws_internal.website_requirements_sha256_hex_v1(
        'LWS_APPROVED_CONTENT_V1:' || p_source_sha
      )
    )
  end;
  return jsonb_build_object(
    'contract_version', 1,
    'evidence_type', p_type,
    'website_work_context_id', pg_temp.fixture_uuid('wrv-context'),
    'website_workspace_id', pg_temp.fixture_uuid('wrv-workspace'),
    'binding_revision', 3,
    'repository_ref', 'heads/main',
    'commit_sha', repeat('a', 40),
    'requirement_source_sha256', p_source_sha,
    'observed_at', to_char(
      current_timestamp at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'details', v_details
  );
end;
$$;

select has_table(
  'public', 'website_requirement_verification_commands',
  'Task 4 verification command ledger exists'
);
select has_function(
  'public', 'get_website_requirement_verification_authority_v1',
  array['uuid', 'uuid', 'uuid', 'bigint'],
  'verification authority RPC has the exact signature'
);
select has_function(
  'public', 'record_website_requirement_verification_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'text', 'integer', 'text', 'jsonb', 'uuid'],
  'verification mutation RPC has the exact signature'
);
select has_function(
  'lws_internal', 'website_requirement_rule_v1', array['text', 'integer'],
  'closed Task 4 rule registry exists'
);
select has_function(
  'lws_internal', 'website_requirement_verification_is_current_v1', array['uuid', 'boolean'],
  'Task 4 currentness evaluator exists'
);

select is(
  lws_internal.website_requirement_rule_v1('website_route_present', 1)->>'evidence_type',
  'REPOSITORY_ROUTE', 'route rule is closed to REPOSITORY_ROUTE'
);
select is(
  lws_internal.website_requirement_rule_v1('website_module_present', 1)->>'evidence_type',
  'REPOSITORY_FILE', 'module rule is closed to REPOSITORY_FILE'
);
select is(
  lws_internal.website_requirement_rule_v1('website_test_suite_passed', 1)->>'evidence_type',
  'TEST_RUN', 'test rule is closed to TEST_RUN'
);
select is(
  lws_internal.website_requirement_rule_v1('approved_content_present', 1)->>'evidence_type',
  'CONTENT_MARKER', 'content rule is closed to CONTENT_MARKER'
);
select is(
  lws_internal.website_requirement_rule_v1('approved_provider_resource', 1),
  null::jsonb, 'generic EXTERNAL rule does not exist'
);
select is(
  lws_internal.website_requirement_evidence_sha256_v1(jsonb_build_object(
    'z', jsonb_build_array(3, jsonb_build_object('b', 2, 'a', 1)),
    'a', chr(101) || chr(769)
  ))::text,
  'ec9197534aec86f1ce287ab12ed5464bc10169978f6e45bb4b0f3bd877ebb24c',
  'SQL and TypeScript canonical JSON normalize strings to the same UTF-8 hash'
);
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.website_requirement_verification_commands'::regclass),
  'verification ledger has forced RLS'
);
select ok(
  not has_table_privilege('public', 'public.website_requirement_verification_commands', 'select')
  and not has_table_privilege('anon', 'public.website_requirement_verification_commands', 'select')
  and not has_table_privilege('authenticated', 'public.website_requirement_verification_commands', 'select')
  and not has_table_privilege('service_role', 'public.website_requirement_verification_commands', 'select'),
  'no runtime role has direct verification-ledger access'
);
select ok(
  has_function_privilege('service_role', 'public.get_website_requirement_verification_authority_v1(uuid,uuid,uuid,bigint)', 'execute')
  and has_function_privilege('service_role', 'public.record_website_requirement_verification_v1(uuid,uuid,uuid,bigint,text,integer,text,jsonb,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_website_requirement_verification_authority_v1(uuid,uuid,uuid,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.record_website_requirement_verification_v1(uuid,uuid,uuid,bigint,text,integer,text,jsonb,uuid)', 'execute'),
  'only service_role can execute Task 4 RPCs'
);

set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values (
  pg_temp.fixture_uuid('wrv-owner-op'), pg_temp.fixture_uuid('wrv-owner-user'),
  'WRV Owner', 'owner', 'ACTIVE', null
);
insert into public.quote_requests(
  id, application_reference, record_classification, request_kind,
  name, company, email, website_type, budget, timing, description,
  privacy_consent, status
) values (
  pg_temp.fixture_uuid('wrv-quote'), 'LWS-AAN-2099-9401', 'production', 'website',
  'WRV Customer', 'WRV Company', 'wrv@example.test', 'business',
  'Meer dan EUR 6.000', 'flexible', 'Synthetic Task 4 fixture.', true, 'approved'
);
insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, commercially_released,
  concept_status, revision, created_by
) values (
  pg_temp.fixture_uuid('wrv-concept'), pg_temp.fixture_uuid('wrv-quote'),
  'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', 1, pg_temp.fixture_uuid('wrv-owner-op')
);
insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values (
  pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-quote'),
  pg_temp.fixture_uuid('wrv-concept'), null, 'PRE_PROJECT', 9
);
insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  workspace_state, repository_provider, repository_owner, repository_name,
  default_branch, preview_branch, last_commit_sha, binding_revision,
  created_by, provisioned_by, provisioned_at, repository_external_id,
  repository_node_id, repository_visibility, repository_state, starter_source,
  starter_version, starter_commit_sha, repository_marker_commit_sha,
  repository_bound_at
) values (
  pg_temp.fixture_uuid('wrv-workspace'), pg_temp.fixture_uuid('wrv-context'), null,
  pg_temp.fixture_uuid('wrv-quote'), 'REPOSITORY_READY', 'GITHUB',
  'lws-fixtures', 'task4-site', 'main', null, repeat('a', 40), 3,
  pg_temp.fixture_uuid('wrv-owner-op'), pg_temp.fixture_uuid('wrv-owner-op'), current_timestamp,
  7000000001, 'R_task4', 'private', 'BOUND', 'lws-fixtures/starter',
  '1.0.0', repeat('9', 40), repeat('8', 40), current_timestamp
);
insert into public.website_repository_provisioning_operations(
  operation_id, website_workspace_id, website_work_context_id, actor_id,
  idempotency_key, request_fingerprint, repository_provider, repository_owner,
  repository_name, starter_source, starter_version, starter_commit_sha,
  state, attempt_count, repository_external_id, repository_node_id,
  claimed_at, updated_at, external_created_at, bound_at
) values (
  pg_temp.fixture_uuid('wrv-repo-operation'), pg_temp.fixture_uuid('wrv-workspace'),
  pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-owner-op'),
  pg_temp.fixture_uuid('wrv-repo-key'), repeat('7', 64), 'GITHUB',
  'lws-fixtures', 'task4-site', 'lws-fixtures/starter', '1.0.0', repeat('9', 40),
  'BOUND', 1, 7000000001, 'R_task4', current_timestamp, current_timestamp,
  current_timestamp, current_timestamp
);
insert into public.website_requirements_boards(
  requirements_board_id, website_work_context_id, quote_request_id,
  sync_state, mapping_version, revision, created_by
) values (
  pg_temp.fixture_uuid('wrv-board'), pg_temp.fixture_uuid('wrv-context'),
  pg_temp.fixture_uuid('wrv-quote'), 'CURRENT', 1, 10, pg_temp.fixture_uuid('wrv-owner-op')
);
insert into public.website_requirements(
  requirement_id, requirements_board_id, website_work_context_id, quote_request_id,
  source_key, source_reference, source_value_sha256, item_number, sort_order,
  title, description, category, linked_page_or_module, status, completion_mode,
  completion_rule_key, completion_rule_version, source_review_state, required,
  started_at, completed_at, completed_by, evidence_summary,
  verification_result, blocked_reason, revision, created_at, updated_at
) values
  (pg_temp.fixture_uuid('wrv-auto'), pg_temp.fixture_uuid('wrv-board'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-quote'),
   'test:release', '{}', repeat('1',64), 1, 1, 'Release test', 'AUTO test fixture', 'TECHNICAL', 'release_smoke',
   'BLOCKED', 'AUTO', 'website_test_suite_passed', 1, 'CURRENT', true,
  current_timestamp, null, null, null, 'UNKNOWN', 'Waiting', 1, current_timestamp, current_timestamp),
  (pg_temp.fixture_uuid('wrv-hybrid'), pg_temp.fixture_uuid('wrv-board'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-quote'),
   'page:about', '{}', repeat('2',64), 2, 2, 'About route', 'HYBRID route fixture', 'PAGE', 'pages/about',
   'ACTIVE', 'HYBRID', 'website_route_present', 1, 'CURRENT', true,
  current_timestamp, null, null, null, 'UNKNOWN', null, 1, current_timestamp, current_timestamp),
  (pg_temp.fixture_uuid('wrv-file'), pg_temp.fixture_uuid('wrv-board'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-quote'),
   'module:forms', '{}', repeat('3',64), 3, 3, 'Forms module', 'HYBRID file fixture', 'FORM', 'src/forms.ts',
   'PENDING', 'HYBRID', 'website_module_present', 1, 'CURRENT', false,
  null, null, null, null, 'UNKNOWN', null, 1, current_timestamp, current_timestamp),
  (pg_temp.fixture_uuid('wrv-content'), pg_temp.fixture_uuid('wrv-board'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-quote'),
   'content:copy', '{}', repeat('4',64), 4, 4, 'Approved content', 'HYBRID marker fixture', 'CONTENT', 'content/about.txt',
   'PENDING', 'HYBRID', 'approved_content_present', 1, 'CURRENT', false,
  null, null, null, null, 'UNKNOWN', null, 1, current_timestamp, current_timestamp),
  (pg_temp.fixture_uuid('wrv-operator'), pg_temp.fixture_uuid('wrv-board'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-quote'),
   'brief:site_direction', '{}', repeat('5',64), 5, 5, 'Human work', 'OPERATOR fixture', 'CONTENT', null,
   'PENDING', 'OPERATOR', null, null, 'CURRENT', false,
  null, null, null, null, 'NOT_APPLICABLE', null, 1, current_timestamp, current_timestamp),
  (pg_temp.fixture_uuid('wrv-external'), pg_temp.fixture_uuid('wrv-board'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-quote'),
   'integration:external', '{}', repeat('6',64), 6, 6, 'External work', 'EXTERNAL fixture', 'INTEGRATION', 'external',
   'PENDING', 'EXTERNAL', 'approved_provider_resource', 1, 'CURRENT', false,
  null, null, null, null, 'UNKNOWN', null, 1, current_timestamp, current_timestamp);
set local session_replication_role = origin;

select pg_temp.set_role_claim('authenticated', pg_temp.fixture_uuid('wrv-owner-user'), 'aal2');
select throws_ok(
  format(
    'select public.get_website_requirement_verification_authority_v1(%L,%L,%L,1)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-auto')
  ),
  '42501', 'TRUSTED_WEBSITE_REQUIREMENTS_VERIFIER_REQUIRED',
  'authenticated owner cannot obtain trusted verification authority'
);

select pg_temp.set_role_claim('service_role');
select is(
  pg_temp.jsonb_keys(public.get_website_requirement_verification_authority_v1(
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'),
    pg_temp.fixture_uuid('wrv-auto'), 1
  )),
  array['completion_mode','contract_version','quote_request_id','requirement_id',
    'requirement_revision','requirements_board_id','rule_key','rule_version',
    'source_review_state','source_value_sha256','verification_target','website_work_context_id','workspace'],
  'authority RPC returns the exact root keys'
);
select is(
  pg_temp.jsonb_keys(public.get_website_requirement_verification_authority_v1(
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'),
    pg_temp.fixture_uuid('wrv-auto'), 1
  )->'workspace'),
  array['binding_revision','last_commit_sha','ref_label','repository_external_id',
    'repository_name','repository_node_id','repository_operation_state',
    'repository_owner','repository_provider','repository_ref','website_workspace_id','workspace_state'],
  'authority workspace DTO has no secret or surplus key'
);
select is(
  public.get_website_requirement_verification_authority_v1(
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'),
    pg_temp.fixture_uuid('wrv-auto'), 1
  )->'verification_target',
  '{"kind":"SUITE_ID","value":"release_smoke"}'::jsonb,
  'verification target derives from the persisted rule target'
);
select throws_ok(
  format(
    'select public.get_website_requirement_verification_authority_v1(%L,%L,%L,1)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrong-context'), pg_temp.fixture_uuid('wrv-auto')
  ),
  'P0001', 'WEBSITE_REQUIREMENT_NOT_FOUND', 'wrong context fails closed'
);
select throws_ok(
  format(
    'select public.get_website_requirement_verification_authority_v1(%L,%L,%L,99)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-auto')
  ),
  '40001', 'CONCURRENT_MODIFICATION', 'stale authority revision is rejected'
);
select throws_ok(
  format(
    'select public.get_website_requirement_verification_authority_v1(%L,%L,%L,1)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-external')
  ),
  '22023', 'UNKNOWN_WEBSITE_REQUIREMENT_RULE', 'EXTERNAL v1 fails closed'
);

create temporary table task4_results(name text primary key, value jsonb);
insert into task4_results values (
  'auto', public.record_website_requirement_verification_v1(
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'),
    pg_temp.fixture_uuid('wrv-auto'), 1, 'website_test_suite_passed', 1, 'PASS',
    pg_temp.evidence('TEST_RUN', 'release_smoke', repeat('1',64)),
    pg_temp.fixture_uuid('wrv-auto-pass-key')
  )
);
select is(
  pg_temp.jsonb_keys((select value from task4_results where name='auto')),
  array['auto_completed','board_revision','contract_version','quote_request_id',
    'replayed','requirement_id','requirement_revision','requirements_board_id',
    'result','rule_key','rule_version','status','verification_id','website_work_context_id'],
  'mutation result has exact closed keys'
);
select is((select value->>'status' from task4_results where name='auto'), 'COMPLETED', 'BLOCKED AUTO PASS completes');
select is((select (value->>'auto_completed')::boolean from task4_results where name='auto'), true, 'AUTO PASS reports auto completion');
select ok(
  (select status='COMPLETED' and blocked_reason is null and started_at is not null
     and completed_by='SYSTEM:website_requirements_verifier'
     and verification_result='PASS' and revision=2
   from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrv-auto')),
  'AUTO PASS preserves started_at and atomically closes BLOCKED state'
);
select ok(
  (select requirement_revision=2 and result='PASS'
     and verified_by='SYSTEM:website_requirements_verifier'
      and expires_at=(evidence_reference->>'observed_at')::timestamptz + interval '24 hours'
   from public.website_requirement_verifications where requirement_id=pg_temp.fixture_uuid('wrv-auto')),
  'verification stores resulting revision and exact trusted identity/freshness'
);
select is(
  (select count(*)::integer from public.website_requirement_events
   where requirement_id=pg_temp.fixture_uuid('wrv-auto')),
  2, 'AUTO transition emits exactly recorded and auto-completed events'
);
select ok(
  not exists (
    select 1 from public.website_requirement_events
    where requirement_id=pg_temp.fixture_uuid('wrv-auto')
      and pg_temp.jsonb_keys(metadata) is distinct from array[
        'auto_completed','board_revision','evidence_sha256','evidence_type',
        'new_revision','new_status','previous_revision','previous_status',
        'requirement_id','requirements_board_id','result','rule_key','rule_version','verification_id'
      ]
  ), 'Task 4 event metadata uses the exact safe schema'
);
select is(
  (public.record_website_requirement_verification_v1(
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'),
    pg_temp.fixture_uuid('wrv-auto'), 1, 'website_test_suite_passed', 1, 'PASS',
    pg_temp.evidence('TEST_RUN', 'release_smoke', repeat('1',64)),
    pg_temp.fixture_uuid('wrv-auto-pass-key')
  )->>'replayed')::boolean,
  true, 'exact replay succeeds before stale revision rejection'
);
select is(
  (select count(*)::integer from public.website_requirement_verifications
   where requirement_id=pg_temp.fixture_uuid('wrv-auto')),
  1, 'replay creates no duplicate verification'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,1,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-auto'),
    'website_test_suite_passed', 'FAIL', pg_temp.evidence('TEST_RUN','release_smoke',repeat('1',64))::text,
    pg_temp.fixture_uuid('wrv-auto-pass-key')
  ),
  'P0001', 'WEBSITE_REQUIREMENT_VERIFICATION_IDEMPOTENCY_CONFLICT',
  'same key with another fingerprint conflicts'
);

insert into task4_results values (
  'hybrid', public.record_website_requirement_verification_v1(
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'),
    pg_temp.fixture_uuid('wrv-hybrid'), 1, 'website_route_present', 1, 'PASS',
    pg_temp.evidence('REPOSITORY_ROUTE', 'pages/about', repeat('2',64)),
    pg_temp.fixture_uuid('wrv-hybrid-pass-key')
  )
);
select is((select value->>'status' from task4_results where name='hybrid'), 'ACTIVE', 'HYBRID PASS does not auto-complete');
select is((select (value->>'auto_completed')::boolean from task4_results where name='hybrid'), false, 'HYBRID PASS reports no auto completion');
select ok(
  lws_internal.website_requirement_current_pass_v1(pg_temp.fixture_uuid('wrv-hybrid')),
  'HYBRID PASS is current for the Task 3 mutation gate'
);

select pg_temp.set_role_claim('authenticated', pg_temp.fixture_uuid('wrv-owner-user'), 'aal2');
select lives_ok(
  format(
    'select public.complete_website_requirement_v1(%L,%L,%L,2,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-hybrid'),
    '{"attestation":"Reviewed against current evidence"}', pg_temp.fixture_uuid('wrv-hybrid-complete-key')
  ),
  'authorized Task 3 human completion consumes current HYBRID PASS'
);
select ok(
  not lws_internal.website_requirement_verification_is_current_v1(pg_temp.fixture_uuid('wrv-hybrid'), false)
  and lws_internal.website_requirement_verification_is_current_v1(pg_temp.fixture_uuid('wrv-hybrid'), true),
  'completed HYBRID bridge is readiness evidence but not a new mutation gate'
);

select pg_temp.set_role_claim('service_role');
insert into task4_results values (
  'file-fail', public.record_website_requirement_verification_v1(
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'),
    pg_temp.fixture_uuid('wrv-file'), 1, 'website_module_present', 1, 'FAIL',
    pg_temp.evidence('REPOSITORY_FILE', 'src/forms.ts', repeat('3',64)),
    pg_temp.fixture_uuid('wrv-file-fail-key')
  )
);
select ok(
  (select status='PENDING' and verification_result='FAIL' and revision=2
   from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrv-file')),
  'FAIL updates evidence and revisions without completion or reopen'
);
insert into task4_results values (
  'content-unknown', public.record_website_requirement_verification_v1(
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'),
    pg_temp.fixture_uuid('wrv-content'), 1, 'approved_content_present', 1, 'UNKNOWN',
    pg_temp.evidence('CONTENT_MARKER', 'content/about.txt', repeat('4',64)),
    pg_temp.fixture_uuid('wrv-content-unknown-key')
  )
);
select ok(
  (select status='PENDING' and verification_result='UNKNOWN' and revision=2
   from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrv-content')),
  'UNKNOWN preserves lifecycle status while refreshing safe evidence'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,1,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-operator'),
    'website_route_present', 'PASS', pg_temp.evidence('REPOSITORY_ROUTE','pages/about',repeat('5',64))::text,
    pg_temp.fixture_uuid('wrv-operator-key')
  ),
  '55000', 'WEBSITE_REQUIREMENT_VERIFICATION_MODE_UNSUPPORTED',
  'OPERATOR verification ingestion is denied without a row'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,1,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-external'),
    'approved_provider_resource', 'PASS', pg_temp.evidence('REPOSITORY_FILE','external',repeat('6',64))::text,
    pg_temp.fixture_uuid('wrv-external-key')
  ),
  '22023', 'UNKNOWN_WEBSITE_REQUIREMENT_RULE', 'EXTERNAL verification remains fail closed'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('f',64)))::text,
    pg_temp.fixture_uuid('wrv-wrong-source-key')
  ),
  '23514', 'WEBSITE_REQUIREMENT_SOURCE_MISMATCH', 'wrong source hash fails closed'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)) || jsonb_build_object('commit_sha',repeat('f',40)))::text,
    pg_temp.fixture_uuid('wrv-wrong-commit-key')
  ),
  '23514', 'WEBSITE_REQUIREMENT_COMMIT_MISMATCH', 'wrong canonical commit fails closed'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)) ||
      jsonb_build_object('website_workspace_id',pg_temp.fixture_uuid('wrong-workspace')))::text,
    pg_temp.fixture_uuid('wrv-wrong-workspace-key')
  ),
  '23514', 'WEBSITE_REQUIREMENT_WORKSPACE_MISMATCH', 'wrong workspace fails closed'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)) ||
      jsonb_build_object('binding_revision',99))::text,
    pg_temp.fixture_uuid('wrv-wrong-binding-key')
  ),
  '23514', 'WEBSITE_REQUIREMENT_BINDING_MISMATCH', 'wrong binding revision fails closed'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)) ||
      jsonb_build_object('repository_ref','heads/develop'))::text,
    pg_temp.fixture_uuid('wrv-wrong-ref-key')
  ),
  '23514', 'WEBSITE_REQUIREMENT_REF_MISMATCH', 'wrong repository ref fails closed'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)) ||
      jsonb_build_object('website_work_context_id',pg_temp.fixture_uuid('wrong-context')))::text,
    pg_temp.fixture_uuid('wrv-wrong-evidence-context-key')
  ),
  '23514', 'WEBSITE_REQUIREMENT_WORKSPACE_MISMATCH', 'wrong evidence context fails closed'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)) ||
      jsonb_build_object('observed_at',to_char(
        current_timestamp at time zone 'UTC' - interval '6 minutes',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      )))::text,
    pg_temp.fixture_uuid('wrv-stale-evidence-key')
  ),
  '22023', 'WEBSITE_REQUIREMENT_VERIFICATION_STALE', 'stale repository evidence is rejected'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)) ||
      jsonb_build_object('observed_at',current_timestamp::text))::text,
    pg_temp.fixture_uuid('wrv-non-rfc3339-key')
  ),
  '22023', 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE',
  'observed_at must use RFC3339 UTC form'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    jsonb_set(pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)),
      '{binding_revision}', '"3"'::jsonb)::text,
    pg_temp.fixture_uuid('wrv-wrong-type-key')
  ),
  '22023', 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE',
  'string-typed binding revision is rejected'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'NOT_APPLICABLE',
    pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64))::text,
    pg_temp.fixture_uuid('wrv-not-applicable-key')
  ),
  '22023', 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_COMMAND',
  'NOT_APPLICABLE can never be inserted as a Task 4 result'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS',
    (pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64)) || '{"surplus":true}'::jsonb)::text,
    pg_temp.fixture_uuid('wrv-surplus-evidence-key')
  ),
  '22023', 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE',
  'surplus evidence keys are rejected'
);
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,99,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS', pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64))::text,
    pg_temp.fixture_uuid('wrv-stale-revision-key')
  ),
  '40001', 'CONCURRENT_MODIFICATION', 'stale requirement revision is rejected'
);
select pg_temp.set_role_claim('authenticated', pg_temp.fixture_uuid('wrv-owner-user'), 'aal2');
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,2,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('wrv-quote'), pg_temp.fixture_uuid('wrv-context'), pg_temp.fixture_uuid('wrv-file'),
    'website_module_present', 'PASS', pg_temp.evidence('REPOSITORY_FILE','src/forms.ts',repeat('3',64))::text,
    pg_temp.fixture_uuid('wrv-owner-self-pass-key')
  ),
  '42501', 'TRUSTED_WEBSITE_REQUIREMENTS_VERIFIER_REQUIRED',
  'owner cannot self-record verification'
);
select pg_temp.set_role_claim('service_role');
select throws_ok(
  $$update public.website_requirement_verifications set result='FAIL'$$,
  '55000', 'WEBSITE_REQUIREMENT_HISTORY_IMMUTABLE', 'verification rows are update-immutable'
);
select throws_ok(
  $$delete from public.website_requirement_verifications$$,
  '55000', 'WEBSITE_REQUIREMENT_HISTORY_IMMUTABLE', 'verification rows are delete-immutable'
);
select is(
  (select project_id from public.website_work_contexts where website_work_context_id=pg_temp.fixture_uuid('wrv-context')),
  null::uuid, 'Task 4 operates with project_id NULL in PRE_PROJECT'
);
select is(
  (select revision from public.website_work_contexts where website_work_context_id=pg_temp.fixture_uuid('wrv-context')),
  9::bigint, 'verification never changes website work-context revision'
);
select is(
  (select count(*)::integer from public.project_requirement_verifications
   where verified_by='SYSTEM:website_requirements_verifier'),
  0, 'commercial verification authority is untouched'
);

select * from finish();
rollback;
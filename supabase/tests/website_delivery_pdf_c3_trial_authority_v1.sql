begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(42);

select has_table(
  'public', 'website_delivery_pdf_c3_trial_fixtures',
  'C3 has one durable internal_e2e trial fixture authority'
);
select has_function(
  'public', 'create_website_delivery_pdf_c3_trial_fixture_v1',
  array['uuid','uuid'],
  'owner fixture creation RPC exists'
);
select has_function(
  'public', 'close_website_delivery_pdf_c3_trial_fixture_v1',
  array['uuid','integer','uuid'],
  'owner fixture close RPC exists'
);
select has_function(
  'public', 'resolve_website_delivery_pdf_c3_test_hold_v1',
  array['uuid','uuid','uuid','integer'],
  'service hold resolver exists'
);
select function_privs_are(
  'public', 'create_website_delivery_pdf_c3_trial_fixture_v1',
  array['uuid','uuid'], 'authenticated', array['EXECUTE'],
  'only authenticated humans can enter guarded fixture creation'
);
select function_privs_are(
  'public', 'close_website_delivery_pdf_c3_trial_fixture_v1',
  array['uuid','integer','uuid'], 'authenticated', array['EXECUTE'],
  'only authenticated humans can enter guarded fixture cleanup'
);
select function_privs_are(
  'public', 'resolve_website_delivery_pdf_c3_test_hold_v1',
  array['uuid','uuid','uuid','integer'], 'service_role', array['EXECUTE'],
  'only service role can resolve the server-side hold'
);
select ok(
  not has_function_privilege('anon', 'public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid,uuid)', 'execute'),
  'anonymous cannot create a C3 fixture'
);
select ok(
  not has_function_privilege('authenticated', 'public.resolve_website_delivery_pdf_c3_test_hold_v1(uuid,uuid,uuid,integer)', 'execute'),
  'human clients cannot resolve or forge a C3 hold'
);
select has_table(
  'public', 'website_delivery_pdf_c3_trial_fixture_events',
  'C3 fixture lifecycle has append-only events'
);
select is(
  (select relrowsecurity and relforcerowsecurity from pg_class
   where oid = 'public.website_delivery_pdf_c3_trial_fixtures'::regclass),
  true,
  'C3 fixtures force RLS'
);
select is(
  (select relrowsecurity and relforcerowsecurity from pg_class
   where oid = 'public.website_delivery_pdf_c3_trial_fixture_events'::regclass),
  true,
  'C3 fixture events force RLS'
);
select table_privs_are(
  'public', 'website_delivery_pdf_c3_trial_fixtures', 'service_role', array[]::text[],
  'service role has no direct C3 fixture table privileges'
);

insert into auth.users(id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'c3-owner@example.test')
on conflict (id) do update set email = excluded.email;
set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values (
  'c3100000-0000-4000-8000-000000000002',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'C3 Owner', 'owner', 'ACTIVE'
) on conflict (auth_user_id) do update
set display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;
set local session_replication_role = origin;
select set_config('request.jwt.claim.sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);
create temporary table c3_run as
select public.create_internal_e2e_run_v1(
  'c3100000-0000-4000-8000-000000000003', repeat('1',64),
  'C3 PDF recovery trial', 30, repeat('2',64), repeat('3',64), repeat('4',64)
) as result;
create temporary table c3_fixture(result jsonb);
grant select on c3_run to authenticated;
grant insert, select on c3_fixture to authenticated;
set local role authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
select throws_ok(
  format(
    'select public.create_website_delivery_pdf_c3_trial_fixture_v1(%L,%L)',
    (select result->>'run_id' from c3_run),
    'c3100000-0000-4000-8000-000000000004'
  ),
  '42501', 'AAL2_REQUIRED',
  'active owner without AAL2 cannot create the C3 fixture'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);
insert into c3_fixture
select public.create_website_delivery_pdf_c3_trial_fixture_v1(
  (select (result->>'run_id')::uuid from c3_run),
  'c3100000-0000-4000-8000-000000000004'
) as result;
reset role;

select is((select result->>'was_created' from c3_fixture), 'true',
  'first owner+AAL2 request creates one fixture');
select is((select result->>'synthetic_scope' from c3_fixture), 'PDF_RECOVERY_ONLY',
  'fixture explicitly limits its evidentiary scope to PDF recovery');
select is((select request.record_classification
  from public.quote_requests as request
  where request.id = (select (result->>'quote_request_id')::uuid from c3_fixture)),
  'internal_e2e', 'fixture remains rooted in immutable internal_e2e classification');
select is((select project.current_state
  from public.commercial_projects as project
  where project.project_id = (select (result->>'project_id')::uuid from c3_fixture)),
  'M2_PAYMENT_RECEIVED', 'fixture starts in the explicitly synthetic M2 state');
select is((select preview.status
  from public.preview_versions as preview
  where preview.preview_version_id = (select (result->>'preview_version_id')::uuid from c3_fixture)),
  'CURRENT', 'fixture owns one CURRENT synthetic preview');
select is((
  select count(*)::integer from public.commercial_project_sites
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
), 1, 'fixture creates exactly one site binding through the guarded site command');
select is((
  select canonical_domain from public.commercial_project_sites
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
), 'c3-test-only.invalid', 'fixture site uses the reserved TEST_ONLY invalid domain');
select is((
  select site.operation || ':' || site.evidence || ':' || operator.auth_user_id::text
  from public.commercial_project_sites as site
  join public.commercial_operators as operator
    on operator.operator_id = site.actor_operator_id
  where site.project_id = (select (result->>'project_id')::uuid from c3_fixture)
), 'INITIAL_BIND:TEST_ONLY:C3:PDF_RECOVERY_ONLY:c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'fixture site preserves guarded command operation, evidence, and owner identity');
create temporary table c3_checklist as select jsonb_build_object(
  'pages','COMPLETED','desktop_browsers','COMPLETED','mobile_tablet','COMPLETED','forms','COMPLETED',
  'links','COMPLETED','technical_seo','COMPLETED','ssl','NOT_APPLICABLE','hosting','COMPLETED',
  'domain','COMPLETED','access_transfer','COMPLETED','backup','COMPLETED') as value;
create temporary table c3_prepare as
select public.prepare_website_delivery_document_v1(
  (select (result->>'project_id')::uuid from c3_fixture), date '2099-10-01',
  (select value from c3_checklist), 'NONE_CONFIRMED', null, date '2099-10-01',
  'Lievegem', null, null, 'c3100000-0000-4000-8000-000000000005', 'TEST_ONLY:C3'
) as result;
select is((select result->>'was_created' from c3_prepare), 'true',
  'real document preparation succeeds for the protected C3 fixture');
select is((select result->'generation_payload'->'project'->>'canonical_url' from c3_prepare),
  'https://c3-test-only.invalid', 'prepared document uses the guarded fixture site binding');
select is((
  select count(*)::integer from public.commercial_obligations
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
) + (
  select count(*)::integer from public.payment_expectations
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
) + (
  select count(*)::integer from public.payment_evidence
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
) + (
  select count(*)::integer from public.payment_reconciliations
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
) + (
  select count(*)::integer from public.commercial_documents
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
), 0, 'fixture creates no obligation, payment, reconciliation, invoice, or commercial-document evidence');
select is((
  select count(*)::integer from public.preview_access
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
) + (
  select count(*)::integer from public.customer_approvals
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
) + (
  select count(*)::integer from public.website_delivery_document_acceptances
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
), 0, 'fixture creates no customer access, approval, or delivery acceptance');
select is(public.create_website_delivery_pdf_c3_trial_fixture_v1(
  (select (result->>'run_id')::uuid from c3_run),
  'c3100000-0000-4000-8000-000000000004'
)->>'was_created', 'false', 'same request replays without duplicate fixture creation');
select is((
  select count(*)::integer from public.commercial_project_sites
  where project_id = (select (result->>'project_id')::uuid from c3_fixture)
), 1, 'fixture replay creates no second site binding');
select is((select count(*)::integer from public.website_delivery_pdf_c3_trial_fixtures), 1,
  'fixture replay leaves exactly one durable marker');
select is((select count(*)::integer from public.website_delivery_pdf_c3_trial_fixture_events), 1,
  'fixture creation records one audit event');

set local session_replication_role = replica;
insert into public.website_delivery_pdf_conversion_tasks(
  task_id, artifact_id, candidate_id, project_id, preview_version_id, document_version,
  source_docx_sha256, generation_payload_sha256, source_drive_file_id, source_sha256,
  statement_version, runtime_template_reference, runtime_template_version,
  runtime_template_sha256, task_idempotency_key, actor
) values (
  'c3100000-0000-4000-8000-000000000010',
  'c3100000-0000-4000-8000-000000000011',
  'c3100000-0000-4000-8000-000000000012',
  (select (result->>'project_id')::uuid from c3_fixture),
  (select (result->>'preview_version_id')::uuid from c3_fixture),
  1, repeat('a',64), repeat('b',64), 'TEST_ONLY:C3', repeat('c',64),
  'OPL-W-01', 'LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v2.docx', 'v2',
  '84f16839f584e6949c9fc6389d72894160e65fbf67746eb3bc0effb0d546706d',
  'c3100000-0000-4000-8000-000000000013', 'TEST_ONLY:C3'
);
insert into public.website_delivery_pdf_conversion_executions(
  execution_id, task_id, workflow_repository, workflow_repository_id,
  workflow_ref_name, workflow_ref, workflow_run_id, workflow_run_attempt,
  claimed_by, claimed_at, expires_at
) values (
  'c3100000-0000-4000-8000-000000000014',
  'c3100000-0000-4000-8000-000000000010',
  'lorenzobombello-max/lorenzo-web-studio', '1320223175', 'main',
  'refs/heads/main', '9000001', 1, 'TEST_ONLY:C3',
  '2026-10-01T12:00:00Z', '2026-10-01T12:15:00Z'
);
set local session_replication_role = origin;

select is(public.resolve_website_delivery_pdf_c3_test_hold_v1(
  (select (result->>'project_id')::uuid from c3_fixture),
  (select (result->>'run_id')::uuid from c3_run),
  'c3100000-0000-4000-8000-000000000010', 1
), '2026-10-01T12:02:00Z'::timestamptz,
  'exact active binding resolves immutable claimed_at plus two minutes');
select is(public.resolve_website_delivery_pdf_c3_test_hold_v1(
  (select (result->>'project_id')::uuid from c3_fixture),
  (select (result->>'run_id')::uuid from c3_run),
  'c3100000-0000-4000-8000-000000000010', 1
), '2026-10-01T12:02:00Z'::timestamptz,
  'repeated resolution cannot extend the fixed deadline');
select is(public.resolve_website_delivery_pdf_c3_test_hold_v1(
  'c3100000-0000-4000-8000-000000000099',
  (select (result->>'run_id')::uuid from c3_run),
  'c3100000-0000-4000-8000-000000000010', 1
), null, 'project ID without the exact configured binding cannot enable the hold');
select is(public.resolve_website_delivery_pdf_c3_test_hold_v1(
  (select (result->>'project_id')::uuid from c3_fixture),
  'c3100000-0000-4000-8000-000000000098',
  'c3100000-0000-4000-8000-000000000010', 1
), null, 'wrong internal_e2e run cannot enable the hold');
select is(public.resolve_website_delivery_pdf_c3_test_hold_v1(
  (select (result->>'project_id')::uuid from c3_fixture),
  (select (result->>'run_id')::uuid from c3_run),
  'c3100000-0000-4000-8000-000000000010', 2
), null, 'attempt 2 never receives the test hold');

create temporary table c3_closed as
select public.close_website_delivery_pdf_c3_trial_fixture_v1(
  (select (result->>'fixture_id')::uuid from c3_fixture), 0,
  'c3100000-0000-4000-8000-000000000020'
) as result;
select is((select result->>'was_closed' from c3_closed), 'true',
  'owner+AAL2 can logically close the owned fixture');
select is((select result->>'status' from c3_closed), 'CLOSED',
  'cleanup records the terminal CLOSED state');
select is(public.resolve_website_delivery_pdf_c3_test_hold_v1(
  (select (result->>'project_id')::uuid from c3_fixture),
  (select (result->>'run_id')::uuid from c3_run),
  'c3100000-0000-4000-8000-000000000010', 1
), null, 'closed fixture immediately loses hold authority');
select is(public.close_website_delivery_pdf_c3_trial_fixture_v1(
  (select (result->>'fixture_id')::uuid from c3_fixture), 0,
  'c3100000-0000-4000-8000-000000000020'
)->>'was_closed', 'false', 'same cleanup request replays without mutation');
select is((select count(*)::integer from public.website_delivery_pdf_c3_trial_fixture_events), 2,
  'logical cleanup appends exactly one CLOSED event');
select throws_ok(
  $$delete from public.website_delivery_pdf_c3_trial_fixtures$$,
  '55000', 'WEBSITE_DELIVERY_PDF_C3_TRIAL_FIXTURE_IMMUTABLE',
  'cleanup cannot delete retained fixture evidence'
);
select throws_ok(
  $$delete from public.website_delivery_pdf_c3_trial_fixture_events$$,
  '55000', 'WEBSITE_DELIVERY_PDF_C3_TRIAL_EVENT_IMMUTABLE',
  'cleanup cannot delete retained fixture events'
);

select * from finish();
rollback;
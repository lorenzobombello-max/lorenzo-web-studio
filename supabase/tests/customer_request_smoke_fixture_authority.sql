begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_column('public', 'customer_requests', 'internal_e2e_run_id', 'Customer Request can bind exclusively to an internal E2E run');
select has_function(
  'public', 'create_customer_request_smoke_fixture_v1', array['uuid','uuid'],
  'run-bound smoke fixture helper exists'
);
select has_function(
  'public', 'create_customer_request_smoke_fixture_v1', array['uuid'],
  'owner-only atomic smoke fixture RPC exists'
);
select ok(
  not has_function_privilege('authenticated', 'public.create_customer_request_smoke_fixture_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.create_customer_request_smoke_fixture_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.create_customer_request_smoke_fixture_v1(uuid,uuid)', 'execute'),
  'run-bound helper is unreachable to runtime roles'
);
select ok(
  has_function_privilege('authenticated', to_regprocedure('public.create_customer_request_smoke_fixture_v1(uuid)'), 'execute')
  and not has_function_privilege('anon', to_regprocedure('public.create_customer_request_smoke_fixture_v1(uuid)'), 'execute')
  and not has_function_privilege('service_role', to_regprocedure('public.create_customer_request_smoke_fixture_v1(uuid)'), 'execute'),
  'only authenticated humans can enter the atomic smoke fixture RPC'
);
select is(
  pg_get_function_arguments(to_regprocedure('public.create_customer_request_smoke_fixture_v1(uuid)')),
  'p_idempotency_key uuid',
  'atomic fixture RPC accepts no customer, project, quote, identity, classification, or request fields'
);

insert into auth.users(id, email) values
  ('d1000000-0000-4000-8000-000000000001', 'smoke-owner@example.test'),
  ('d1000000-0000-4000-8000-000000000002', 'smoke-admin@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('d1100000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001', 'Smoke Owner', 'owner', 'ACTIVE'),
  ('d1100000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000002', 'Smoke Admin', 'admin', 'ACTIVE');

select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000001', true);
create temporary table smoke_run as
select public.create_internal_e2e_run_v1(
  'd1200000-0000-4000-8000-000000000001', repeat('1',64),
  'LWS-SMOKE-TEST-UPLOAD-LINK-20260827', 60,
  repeat('2',64), repeat('3',64), repeat('4',64)
) as result;

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.create_customer_request_smoke_fixture_v1('d1300000-0000-4000-8000-000000000001')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is denied'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.create_customer_request_smoke_fixture_v1('d1300000-0000-4000-8000-000000000002')$$,
  '42501', 'INTERNAL_E2E_OWNER_REQUIRED', 'non-owner human is denied by the backend'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000001', true);

insert into lws_internal.customer_request_reference_counters(reference_year, last_value)
values (extract(year from clock_timestamp() at time zone 'Europe/Brussels')::smallint, 9999);
select throws_ok(
  $$select public.create_customer_request_smoke_fixture_v1('d1300000-0000-4000-8000-000000000099')$$,
  '23514', 'new row for relation "customer_request_reference_counters" violates check constraint "customer_request_reference_counters_value_valid"',
  'request-create failure rolls back the atomic run creation'
);
select is(
  (select count(*)::integer from public.internal_e2e_runs where idempotency_key = 'd1300000-0000-4000-8000-000000000099'),
  0, 'failed atomic create leaves no orphan internal E2E run'
);
delete from lws_internal.customer_request_reference_counters;

create temporary table smoke_request as
select public.create_customer_request_smoke_fixture_v1(
  (select (result->>'run_id')::uuid from smoke_run),
  'd1200000-0000-4000-8000-000000000001'
) as result;

select is((select result->>'status' from smoke_request), 'NEW', 'owner creates one synthetic smoke Customer Request');
select is((select result->>'replayed' from smoke_request), 'false', 'first fixture creation is not a replay');
select ok(
  (select request_reference ~ '^LWS-VRZ-[0-9]{4}-[0-9]{4}$'
   from public.customer_requests where request_id = (select (result->>'request_id')::uuid from smoke_request)),
  'request reference is generated server-side'
);
select is(
  (select row(source, submitter_type, request_type, priority, title)::text
   from public.customer_requests where request_id = (select (result->>'request_id')::uuid from smoke_request)),
  row('OPERATOR','OPERATOR','FILE_DELIVERY','LOW','LWS-SMOKE-TEST-UPLOAD-LINK-20260827')::text,
  'synthetic request identity and classification fields are server-authored'
);
select ok(
  (select internal_e2e_run_id = (select (result->>'run_id')::uuid from smoke_run)
          and quote_request_id = (select (result->>'quote_request_id')::uuid from smoke_run)
          and customer_id is null and project_id is null
   from public.customer_requests where request_id = (select (result->>'request_id')::uuid from smoke_request)),
  'fixture binds only to its authoritative internal E2E context'
);
select is((select count(*)::integer from public.customer_request_events), 1, 'fixture creation appends one CREATED audit event');
select is((select count(*)::integer from public.commercial_customers), 0, 'fixture creates no commercial customer');
select is((select count(*)::integer from public.commercial_projects), 0, 'fixture creates no commercial project');
select is((select count(*)::integer from public.quote_request_quotation_acceptances), 0, 'fixture creates no quotation acceptance');
select is((select count(*)::integer from public.quote_request_email_jobs), 0, 'fixture creates no quotation email job');
select is((select count(*)::integer from public.quote_request_quotation_acceptance_events), 0, 'fixture creates no quotation acceptance event');
select is((select count(*)::integer from public.quote_request_quotation_acceptance_capability_events), 0, 'fixture creates no quotation acceptance capability event');
select is((select count(*)::integer from public.quote_request_quotation_artifact_events), 0, 'fixture creates no quotation artifact event');
select is(
  public.create_customer_request_smoke_fixture_v1(
    (select (result->>'run_id')::uuid from smoke_run),
    'd1200000-0000-4000-8000-000000000001'
  )->>'replayed',
  'true', 'same idempotency key replays without a duplicate dossier'
);
select is((select count(*)::integer from public.customer_requests), 1, 'idempotent replay leaves exactly one Customer Request');

create function pg_temp.attempt_duplicate_smoke_request()
returns void
language plpgsql
as $$
begin
  insert into public.customer_requests(
    request_id, request_reference, quote_request_id, customer_id, project_id,
    internal_e2e_run_id, source, request_type, title, description, status,
    priority, submitted_at, submitter_type
  ) select
    'd1500000-0000-4000-8000-000000000001', 'LWS-VRZ-2099-9999', quote_request_id, null, null,
    internal_e2e_run_id, source, request_type, title, description, status,
    priority, clock_timestamp(), submitter_type
  from public.customer_requests
  where request_id = (select (result->>'request_id')::uuid from smoke_request);
  raise exception using errcode = 'P0001', message = 'DUPLICATE_SMOKE_REQUEST_WAS_ALLOWED';
end;
$$;
select throws_ok(
  $$select pg_temp.attempt_duplicate_smoke_request()$$,
  '23505', 'duplicate key value violates unique constraint "customer_requests_internal_e2e_run_unique"',
  'schema independently enforces one Customer Request per internal E2E run'
);
select is((select count(*)::integer from public.customer_requests), 1, 'different-key duplicate attempt leaves one Customer Request');

select lives_ok($$
  select public.create_customer_request_upload_request_v1(
    (select (result->>'request_id')::uuid from smoke_request), repeat('a',64),
    clock_timestamp() + interval '1 hour', 'd1400000-0000-4000-8000-000000000001'
  )
$$, 'normal Upload Link authority works for the owner-created smoke fixture');
select is(public.resolve_customer_request_upload_capability_v1(repeat('a',64))->>'state', 'ACTIVE', 'fixture Upload Link resolves normally');

create function pg_temp.attempt_premature_smoke_finalize()
returns void
language plpgsql
as $$
begin
  perform public.finalize_internal_e2e_run_v1(
    (select (result->>'run_id')::uuid from smoke_run), 'PASSED', 0,
    'd1400000-0000-4000-8000-000000000099'
  );
  raise exception using errcode = 'P0001', message = 'PREMATURE_SMOKE_FINALIZE_WAS_ALLOWED';
end;
$$;
select throws_ok(
  $$select pg_temp.attempt_premature_smoke_finalize()$$,
  'P0001', 'INTERNAL_E2E_CUSTOMER_REQUEST_CLEANUP_REQUIRED',
  'run cannot finalize while its Customer Request and Upload Link remain active'
);
select is(
  (select status from public.internal_e2e_runs where id = (select (result->>'run_id')::uuid from smoke_run)),
  'ACTIVE', 'denied premature finalize leaves the run active'
);

select lives_ok($$
  select public.revoke_customer_request_upload_request_v1(
    (select upload_request_id from public.customer_request_upload_requests where token_digest = repeat('a',64)),
    'Synthetic smoke lifecycle complete', 'd1400000-0000-4000-8000-000000000002'
  )
$$, 'fixture Upload Link is revoked through normal authority');
select is(public.resolve_customer_request_upload_capability_v1(repeat('a',64))->>'state', 'INVALID_OR_EXPIRED_LINK', 'revoked fixture capability is denied');
select is(
  public.transition_customer_request_v1(
    (select (result->>'request_id')::uuid from smoke_request), 'CANCEL', 0,
    'd1400000-0000-4000-8000-000000000003', '{}'::jsonb
  )->>'status',
  'CANCELLED', 'fixture Customer Request is cancelled through normal lifecycle authority'
);
select is(
  public.finalize_internal_e2e_run_v1(
    (select (result->>'run_id')::uuid from smoke_run), 'PASSED', 0,
    'd1400000-0000-4000-8000-000000000004'
  )->>'status',
  'PASSED', 'fixture run finalizes through the existing internal E2E lifecycle'
);
create temporary table terminal_replay(result jsonb);
create function pg_temp.capture_terminal_replay()
returns void
language plpgsql
as $$
begin
  execute $query$
    insert into terminal_replay(result)
    select public.create_customer_request_smoke_fixture_v1('d1200000-0000-4000-8000-000000000001')
  $query$;
end;
$$;
select lives_ok(
  $$select pg_temp.capture_terminal_replay()$$,
  'same atomic create call remains available after request cancellation and run finalization'
);
select is((select result->>'replayed' from terminal_replay), 'true', 'terminal create replay returns the original fixture result');
select is((select count(*)::integer from public.internal_e2e_runs), 1, 'terminal replay creates no new internal E2E run');
select is((select count(*)::integer from public.customer_requests), 1, 'terminal replay creates no new Customer Request');
select is((select count(*)::integer from public.customer_request_uploaded_files), 0, 'capability-only smoke lifecycle creates no uploaded files');
select ok(
  not has_function_privilege('anon', 'lws_internal.create_customer_request_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.create_customer_request_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.create_customer_request_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,jsonb)', 'execute'),
  'general production Customer Request core remains unreachable to runtime roles'
);
select ok(
  exists (select 1 from pg_trigger where tgname = 'trg_quotation_approval_drafts_deny_internal_e2e' and tgenabled <> 'D')
  and exists (select 1 from pg_trigger where tgname = 'trg_quotation_approvals_deny_internal_e2e' and tgenabled <> 'D'),
  'existing internal E2E quotation guards remain enabled'
);

create temporary table capability_fixture_one as
select public.create_customer_request_smoke_fixture_v1(
  'd1600000-0000-4000-8000-000000000001'
) as result;
create temporary table capability_material_one as
select request.approval_token_hash, intake.access_token_hash, intake.admin_access_token_hash
from capability_fixture_one as fixture
join public.internal_e2e_runs as run on run.id = (fixture.result->>'run_id')::uuid
join public.quote_requests as request on request.id = run.quote_request_id
join public.quote_request_intakes as intake on intake.quote_request_id = request.id;

select isnt(
  (select approval_token_hash from capability_material_one),
  encode(extensions.digest(convert_to('smoke-approval:d1600000-0000-4000-8000-000000000001', 'UTF8'), 'sha256'), 'hex'),
  'caller-known idempotency UUID cannot reproduce approval capability hash'
);
select isnt(
  (select access_token_hash from capability_material_one),
  encode(extensions.digest(convert_to('smoke-intake:d1600000-0000-4000-8000-000000000001', 'UTF8'), 'sha256'), 'hex'),
  'caller-known idempotency UUID cannot reproduce intake capability hash'
);
select ok(
  position('smoke-admin:' in pg_get_functiondef('public.create_customer_request_smoke_fixture_v1(uuid)'::regprocedure)) = 0,
  'atomic fixture authority contains no idempotency-derived admin capability material'
);
select is(
  (select admin_access_token_hash from capability_material_one),
  null,
  'fixture creates no persisted admin intake capability'
);

create temporary table capability_fixture_replay as
select public.create_customer_request_smoke_fixture_v1(
  'd1600000-0000-4000-8000-000000000001'
) as result;
select ok(
  (select first.result->>'run_id' = replay.result->>'run_id'
          and first.result->>'request_id' = replay.result->>'request_id'
          and replay.result->>'replayed' = 'true'
   from capability_fixture_one as first cross join capability_fixture_replay as replay),
  'same-key replay returns the original run and request'
);
select is(
  (select row(request.approval_token_hash, intake.access_token_hash, intake.admin_access_token_hash)::text
   from capability_fixture_one as fixture
   join public.internal_e2e_runs as run on run.id = (fixture.result->>'run_id')::uuid
   join public.quote_requests as request on request.id = run.quote_request_id
   join public.quote_request_intakes as intake on intake.quote_request_id = request.id),
  (select row(approval_token_hash, access_token_hash, admin_access_token_hash)::text from capability_material_one),
  'same-key replay leaves stored capability hashes unchanged'
);

create temporary table capability_fixture_two as
select public.create_customer_request_smoke_fixture_v1(
  'd1600000-0000-4000-8000-000000000002'
) as result;
select ok(
  (select first.approval_token_hash <> request.approval_token_hash
          and first.access_token_hash <> intake.access_token_hash
   from capability_material_one as first
   cross join capability_fixture_two as fixture
   join public.internal_e2e_runs as run on run.id = (fixture.result->>'run_id')::uuid
   join public.quote_requests as request on request.id = run.quote_request_id
   join public.quote_request_intakes as intake on intake.quote_request_id = request.id),
  'different fixtures receive distinct stored approval and intake capability hashes'
);
select ok(
  (select (select count(*) from jsonb_object_keys(fixture.result)) = 6
          and not (result ?| array[
            'approval_token', 'approval_token_hash', 'intake_token', 'access_token_hash',
            'admin_intake_token', 'admin_access_token_hash', 'capability', 'secret'
          ])
   from capability_fixture_one as fixture),
  'operator result contains only fixture metadata and no capability material'
);

select * from finish();
rollback;
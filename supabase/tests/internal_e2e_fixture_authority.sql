begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(42);

select has_column('public', 'quote_requests', 'record_classification', 'root business record has classification');
select has_table('public', 'internal_e2e_runs', 'E2E lifecycle table exists');
select has_table('public', 'internal_e2e_run_events', 'E2E audit table exists');
select has_function('public', 'create_internal_e2e_run_v1', array['uuid','text','text','integer','text','text','text'], 'owner create RPC exists');
select has_function('public', 'finalize_internal_e2e_run_v1', array['uuid','text','integer','uuid'], 'owner finalize RPC exists');
select ok(has_function_privilege('authenticated', 'public.create_internal_e2e_run_v1(uuid,text,text,integer,text,text,text)', 'execute'), 'authenticated human can enter guarded create RPC');
select ok(not has_function_privilege('anon', 'public.create_internal_e2e_run_v1(uuid,text,text,integer,text,text,text)', 'execute'), 'anonymous cannot create E2E records');
select ok(not has_function_privilege('service_role', 'public.create_internal_e2e_run_v1(uuid,text,text,integer,text,text,text)', 'execute'), 'service role cannot bypass owner create authority');
select ok(has_function_privilege('service_role', 'public.get_quote_request_email_classification_v1(uuid)', 'execute'), 'service role can resolve authoritative mail classification');
select ok(not has_function_privilege('authenticated', 'public.get_quote_request_email_classification_v1(uuid)', 'execute'), 'human clients cannot inspect mail policy RPC');

insert into auth.users (id, email) values
  ('b1000000-0000-4000-8000-000000000001', 'e2e-owner@example.test'),
  ('b1000000-0000-4000-8000-000000000002', 'e2e-admin@example.test');
insert into public.commercial_operators (auth_user_id, display_name, role, status) values
  ('b1000000-0000-4000-8000-000000000001', 'E2E Owner', 'owner', 'ACTIVE'),
  ('b1000000-0000-4000-8000-000000000002', 'E2E Admin', 'admin', 'ACTIVE');

select throws_ok(
  $$select public.create_internal_e2e_run_v1('b2000000-0000-4000-8000-000000000001',repeat('1',64),'missing auth',30,repeat('2',64),repeat('3',64),repeat('4',64))$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is denied'
);
select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.create_internal_e2e_run_v1('b2000000-0000-4000-8000-000000000001',repeat('1',64),'admin denied',30,repeat('2',64),repeat('3',64),repeat('4',64))$$,
  '42501', 'INTERNAL_E2E_OWNER_REQUIRED', 'active admin is not an E2E owner'
);

select set_config('request.jwt.claim.sub', 'b1000000-0000-4000-8000-000000000001', true);
create temporary table created_e2e as
select public.create_internal_e2e_run_v1(
  'b2000000-0000-4000-8000-000000000001', repeat('1',64), 'production smoke', 30,
  repeat('2',64), repeat('3',64), repeat('4',64)
) as result;

select is((select result->>'was_created' from created_e2e), 'true', 'first create owns a new fixture');
select is((select record_classification from public.quote_requests where id = (select (result->>'quote_request_id')::uuid from created_e2e)), 'internal_e2e', 'classification is server-authored');
select is((select application_reference from public.quote_requests where id = (select (result->>'quote_request_id')::uuid from created_e2e)), null, 'new E2E fixture has no business reference');
select is((select count(*)::integer from public.internal_e2e_run_events), 1, 'creation writes one audit event');
select is(
  public.create_internal_e2e_run_v1('b2000000-0000-4000-8000-000000000001',repeat('1',64),'production smoke',30,repeat('2',64),repeat('3',64),repeat('4',64))->>'was_created',
  'false', 'same idempotency input replays without duplication'
);
select is((select count(*)::integer from public.internal_e2e_runs), 1, 'replay leaves exactly one run');
select throws_ok(
  $$select public.create_internal_e2e_run_v1('b2000000-0000-4000-8000-000000000001',repeat('9',64),'changed',30,repeat('2',64),repeat('3',64),repeat('4',64))$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'changed replay is rejected'
);
select throws_ok(
  format('update public.quote_requests set record_classification=%L where id=%L', 'production', (select result->>'quote_request_id' from created_e2e)),
  '23514', 'RECORD_CLASSIFICATION_IMMUTABLE', 'classification cannot be rewritten'
);

update public.quote_request_intakes
set status = 'submitted', submitted_at = clock_timestamp(), confirmation = true,
    admin_access_token_hash = repeat('4',64), admin_access_token_expires_at = access_token_expires_at
where quote_request_id = (select (result->>'quote_request_id')::uuid from created_e2e);
select is((select count(*)::integer from public.application_reference_counters), 0, 'E2E submission consumes no production reference');
select is((select application_reference from public.quote_requests where id = (select (result->>'quote_request_id')::uuid from created_e2e)), null, 'E2E submission receives no application reference');
select is(jsonb_array_length(public.list_operator_applications_v1()), 0, 'operator production list excludes submitted E2E fixture');
insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('b4100000-0000-4000-8000-000000000001','Production New','new@example.test','Website','Budget','Timing','New production pagination fixture.',true,'approved'),
  ('b4100000-0000-4000-8000-000000000002','Production Old','old@example.test','Website','Budget','Timing','Old production pagination fixture.',true,'approved');
insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at, started_at, submitted_at, confirmation
) values
  ('b4200000-0000-4000-8000-000000000001','b4100000-0000-4000-8000-000000000001','submitted',repeat('a',64),clock_timestamp()+interval '1 hour',clock_timestamp(),clock_timestamp()+interval '1 minute',true),
  ('b4200000-0000-4000-8000-000000000002','b4100000-0000-4000-8000-000000000002','submitted',repeat('b',64),clock_timestamp()+interval '1 hour',clock_timestamp(),clock_timestamp()-interval '1 minute',true);
select is(jsonb_array_length(public.list_operator_applications_v1()), 2, 'E2E record is removed before production pagination');
select is(public.list_operator_applications_v1(1,1)->0->>'quote_request_id', 'b4100000-0000-4000-8000-000000000002', 'offset applies to the filtered production sequence');
select throws_ok(
  format('select public.get_operator_application_v1(%L,null)', (select result->>'quote_request_id' from created_e2e)),
  'P0001', 'APPLICATION_NOT_FOUND', 'operator detail hides E2E fixture'
);
select throws_ok(
  format('select public.promote_operator_application_v1(%L,%L,null)', 'b2000000-0000-4000-8000-000000000002', (select result->>'quote_request_id' from created_e2e)),
  'P0001', 'INTERNAL_E2E_PROMOTION_DENIED', 'E2E fixture cannot enter project promotion'
);
select throws_ok(
  format(
    'insert into public.quote_request_quotation_approval_drafts(id,quote_request_id,intake_id,pricing_snapshot_id,approval_payload,payload_fingerprint,idempotency_key,created_by) values(%L,%L,%L,%L,%L::jsonb,%L,%L,%L)',
    'b3000000-0000-4000-8000-000000000001',
    (select result->>'quote_request_id' from created_e2e),
    (select result->>'intake_id' from created_e2e),
    'b3000000-0000-4000-8000-000000000002', '{}', repeat('5',64),
    'b3000000-0000-4000-8000-000000000003', 'owner:test'
  ),
  'P0001', 'INTERNAL_E2E_QUOTATION_DENIED', 'E2E fixture cannot create quotation authority'
);

create temporary table finalized_e2e as
select public.finalize_internal_e2e_run_v1(
  (select (result->>'run_id')::uuid from created_e2e), 'PASSED', 0,
  'b2000000-0000-4000-8000-000000000003'
) as result;
select is((select result->>'status' from finalized_e2e), 'PASSED', 'finalize records terminal result');
select is((select result->>'revision' from finalized_e2e), '1', 'finalize advances revision once');
select ok((select access_token_revoked_at is not null and admin_access_token_revoked_at is not null from public.quote_request_intakes where quote_request_id = (select (result->>'quote_request_id')::uuid from created_e2e)), 'finalize revokes both intake capabilities');
select ok((select approval_token_hash is null and approval_token_expires_at is null from public.quote_requests where id = (select (result->>'quote_request_id')::uuid from created_e2e)), 'finalize revokes approval capability');
select is(
  public.finalize_internal_e2e_run_v1((select (result->>'run_id')::uuid from created_e2e),'PASSED',0,'b2000000-0000-4000-8000-000000000003')->>'was_finalized',
  'false', 'finalize replay is side-effect free'
);
select is((select count(*)::integer from public.internal_e2e_run_events), 2, 'lifecycle keeps exactly create and finalize evidence');
select throws_ok(
  $$delete from public.internal_e2e_run_events$$,
  '23514', 'INTERNAL_E2E_RUN_EVENT_IMMUTABLE', 'audit events are append-only'
);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description, privacy_consent,
  status, approval_token_hash, approval_token_expires_at
) values (
  'b4000000-0000-4000-8000-000000000001', 'Normal Production', 'normal@example.test',
  'Website', 'Budget', 'Timing', 'Normal production control fixture.', true,
  'approved', repeat('6',64), clock_timestamp() + interval '1 hour'
);
select is((select record_classification from public.quote_requests where id = 'b4000000-0000-4000-8000-000000000001'), 'production', 'normal insert remains production by default');
select is((select count(*)::integer from public.quote_requests where record_classification = 'production'), 3, 'E2E lifecycle does not rewrite normal records');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at, started_at
) values (
  'b4300000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000001',
  'in_progress', repeat('7',64), clock_timestamp() + interval '1 hour', clock_timestamp()
);
insert into public.internal_e2e_runs (
  id, quote_request_id, idempotency_key, request_fingerprint, run_label,
  created_by_operator_id, created_at, expires_at
) select
  'b4400000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000001',
  'b4400000-0000-4000-8000-000000000002', repeat('8',64), 'invalid production linkage',
  operator_id, clock_timestamp(), clock_timestamp() + interval '1 hour'
from public.commercial_operators
where auth_user_id = 'b1000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.finalize_internal_e2e_run_v1('b4400000-0000-4000-8000-000000000001','FAILED',0,'b4400000-0000-4000-8000-000000000003')$$,
  'P0001', 'INTERNAL_E2E_CLASSIFICATION_REQUIRED', 'production-linked run is rejected by the classification guard'
);
select is(
  (select row(status::text, approval_token_hash, approval_token_expires_at is not null)::text from public.quote_requests where id = 'b4000000-0000-4000-8000-000000000001'),
  row('approved', repeat('6',64), true)::text,
  'rejected production finalize leaves the root record and approval capability unchanged'
);
select is(
  (select row(status::text, access_token_hash, access_token_revoked_at, admin_access_token_revoked_at)::text from public.quote_request_intakes where id = 'b4300000-0000-4000-8000-000000000001'),
  row('in_progress', repeat('7',64), null::timestamptz, null::timestamptz)::text,
  'rejected production finalize leaves intake status and capabilities unchanged'
);
select is(
  (select row(status, revision, finalized_at, (select count(*) from public.internal_e2e_run_events where run_id = internal_e2e_runs.id))::text from public.internal_e2e_runs where id = 'b4400000-0000-4000-8000-000000000001'),
  row('ACTIVE', 0, null::timestamptz, 0::bigint)::text,
  'rejected production finalize leaves lifecycle and audit state unchanged'
);
select is((select count(*)::integer from public.commercial_projects), 0, 'rejected production finalize creates no commercial state');

select * from finish();
rollback;
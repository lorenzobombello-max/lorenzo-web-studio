begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(57);

select has_function(
  'public',
  'execute_operator_dossier_lifecycle_command_v1',
  array['uuid','text','bigint','uuid','text','uuid'],
  'operator dossier lifecycle command RPC exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.execute_operator_dossier_lifecycle_command_v1(uuid,text,bigint,uuid,text,uuid)',
    'execute'
  ),
  'authenticated role can enter guarded dossier lifecycle RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.execute_operator_dossier_lifecycle_command_v1(uuid,text,bigint,uuid,text,uuid)',
    'execute'
  ) and not has_function_privilege(
    'service_role',
    'public.execute_operator_dossier_lifecycle_command_v1(uuid,text,bigint,uuid,text,uuid)',
    'execute'
  ),
  'anonymous and service roles cannot execute dossier lifecycle commands'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.issue_operator_dossier_lifecycle_edge_capability_v1(uuid,uuid,text,bigint,uuid,text)',
    'execute'
  ) and not has_function_privilege(
    'authenticated',
    'public.issue_operator_dossier_lifecycle_edge_capability_v1(uuid,uuid,text,bigint,uuid,text)',
    'execute'
  ),
  'only the Edge service role can issue dossier command capabilities'
);
select ok(
  (select count(*) = 3
   from pg_trigger
   where not tgisinternal
     and tgname in (
       'trg_quotation_draft_dossier_lifecycle_guard',
       'trg_sdf_project_dossier_lifecycle_guard',
       'trg_sdf_quotation_dossier_lifecycle_guard'
     )),
  'all first blocker creator boundaries have the central dossier lifecycle guard'
);

insert into auth.users (id, email) values
  ('f4000000-0000-4000-8000-000000000001', 'dossier-owner@example.test'),
  ('f4000000-0000-4000-8000-000000000002', 'dossier-admin@example.test'),
  ('f4000000-0000-4000-8000-000000000003', 'dossier-operator@example.test'),
  ('f4000000-0000-4000-8000-000000000004', 'dossier-disabled@example.test'),
  ('f4000000-0000-4000-8000-000000000005', 'dossier-revoked@example.test'),
  ('f4000000-0000-4000-8000-000000000006', 'dossier-customer@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('f4010000-0000-4000-8000-000000000001', 'f4000000-0000-4000-8000-000000000001', 'Dossier Owner', 'owner', 'ACTIVE', null),
  ('f4010000-0000-4000-8000-000000000002', 'f4000000-0000-4000-8000-000000000002', 'Dossier Admin', 'admin', 'ACTIVE', null),
  ('f4010000-0000-4000-8000-000000000003', 'f4000000-0000-4000-8000-000000000003', 'Dossier Operator', 'operator', 'ACTIVE', null),
  ('f4010000-0000-4000-8000-000000000004', 'f4000000-0000-4000-8000-000000000004', 'Dossier Disabled', 'admin', 'DISABLED', null),
  ('f4010000-0000-4000-8000-000000000005', 'f4000000-0000-4000-8000-000000000005', 'Dossier Revoked', 'admin', 'REVOKED', clock_timestamp());

create function pg_temp.execute_operator_dossier_lifecycle_command_v1(
  p_quote_request_id uuid,
  p_event_type text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_reason text
)
returns jsonb
language plpgsql
as $$
declare
  v_capability uuid;
begin
  if auth.uid() is null then
    v_capability := gen_random_uuid();
  else
    v_capability := public.issue_operator_dossier_lifecycle_edge_capability_v1(
      auth.uid(), p_quote_request_id, p_event_type, p_expected_revision,
      p_idempotency_key, p_reason
    );
  end if;
  return public.execute_operator_dossier_lifecycle_command_v1(
    p_quote_request_id, p_event_type, p_expected_revision,
    p_idempotency_key, p_reason, v_capability
  );
end;
$$;

insert into public.quote_requests (
  id, application_reference, record_classification, request_kind,
  name, email, website_type, budget, timing, description,
  privacy_consent, status
) values (
  'f4100000-0000-4000-8000-000000000001', 'LWS-AAN-2099-0401', 'production', 'website',
  'Dossier command fixture', 'dossier-command@example.test', 'business', 'Meer dan EUR 6.000',
  'flexible', 'Dossier lifecycle command fixture.', true, 'approved'
), (
  'f4110000-0000-4000-8000-000000000002', 'LWS-AAN-2099-0402', 'production', 'website',
  'Capability misuse fixture', 'capability-misuse@example.test', 'business', 'Meer dan EUR 6.000',
  'flexible', 'Dossier capability misuse fixture.', true, 'approved'
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, submitted_at, confirmation,
  created_at
) values (
  'f4200000-0000-4000-8000-000000000001', 'f4100000-0000-4000-8000-000000000001',
  'submitted', repeat('4',64), '2099-08-30T12:00:00Z', 'CANCELLED', 1,
  clock_timestamp(), clock_timestamp(), true, clock_timestamp()
);

insert into public.quote_requests (
  id, request_kind, sdf_package, created_at, name, email, description,
  privacy_consent, status
) values
  ('d3752349-3489-4c19-bd03-f0cc076b5607', 'slimme_documentenflow', 'groei', '2026-08-18T06:40:00.735922Z', 'Legacy authority fixture', 'legacy-authority@example.test', 'Local authority validation fixture.', true, 'approved'),
  ('0696171e-a315-4c03-b402-ba0b689abfbc', 'slimme_documentenflow', 'start', '2026-08-17T23:52:15.685429Z', 'Blocked legacy fixture', 'blocked-legacy@example.test', 'Local blocker validation fixture.', true, 'approved');

insert into public.sdf_projects(project_id, quote_request_id, created_at)
values('f4300000-0000-4000-8000-000000000001', '0696171e-a315-4c03-b402-ba0b689abfbc', clock_timestamp());

select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('f4100000-0000-4000-8000-000000000001','ARCHIVED',0,'f4400000-0000-4000-8000-000000000001','Archive dossier')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is rejected'
);
select set_config('request.jwt.claim.sub', 'f4000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('f4100000-0000-4000-8000-000000000001','ARCHIVED',0,'f4400000-0000-4000-8000-000000000001','Archive dossier')$$,
  '42501', 'UNKNOWN_OPERATOR', 'customer identity cannot execute dossier lifecycle command'
);
select set_config('request.jwt.claim.sub', 'f4000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('f4100000-0000-4000-8000-000000000001','ARCHIVED',0,'f4400000-0000-4000-8000-000000000001','Archive dossier')$$,
  '42501', 'OPERATOR_DISABLED', 'disabled operator is rejected'
);
select set_config('request.jwt.claim.sub', 'f4000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('f4100000-0000-4000-8000-000000000001','ARCHIVED',0,'f4400000-0000-4000-8000-000000000001','Archive dossier')$$,
  '42501', 'OPERATOR_REVOKED', 'revoked operator is rejected'
);
select set_config('request.jwt.claim.sub', 'f4000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('f4100000-0000-4000-8000-000000000001','ARCHIVED',0,'f4400000-0000-4000-8000-000000000001','Archive dossier')$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'project-scoped operator cannot mutate dossier lifecycle'
);

select set_config('request.jwt.claim.sub', 'f4000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1('f4100000-0000-4000-8000-000000000001','ARCHIVED',0,'f4400000-0000-4000-8000-000000000001','Archive dossier',gen_random_uuid())$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'authenticated actor cannot bypass Edge with a self-chosen capability'
);

create temp table capability_misuse_tokens (
  test_name text primary key,
  capability_token uuid not null
) on commit drop;

insert into capability_misuse_tokens(test_name, capability_token)
select test_name, public.issue_operator_dossier_lifecycle_edge_capability_v1(
  'f4000000-0000-4000-8000-000000000001',
  'f4110000-0000-4000-8000-000000000002',
  'ARCHIVED', 0, idempotency_key, reason
)
from (values
  ('single_use', 'f4400000-0000-4000-8000-000000000101'::uuid, 'Capability single use'),
  ('cross_actor', 'f4400000-0000-4000-8000-000000000102'::uuid, 'Capability cross actor'),
  ('cross_dossier', 'f4400000-0000-4000-8000-000000000103'::uuid, 'Capability cross dossier'),
  ('cross_action', 'f4400000-0000-4000-8000-000000000104'::uuid, 'Capability cross action'),
  ('revision', 'f4400000-0000-4000-8000-000000000105'::uuid, 'Capability revision'),
  ('idempotency', 'f4400000-0000-4000-8000-000000000106'::uuid, 'Capability idempotency'),
  ('reason', 'f4400000-0000-4000-8000-000000000107'::uuid, 'Capability reason'),
  ('expired', 'f4400000-0000-4000-8000-000000000108'::uuid, 'Capability expired')
) as cases(test_name, idempotency_key, reason);

select is(
  public.execute_operator_dossier_lifecycle_command_v1(
    'f4110000-0000-4000-8000-000000000002', 'ARCHIVED', 0,
    'f4400000-0000-4000-8000-000000000101', 'Capability single use',
    (select capability_token from capability_misuse_tokens where test_name = 'single_use')
  )->>'state',
  'ARCHIVED',
  'issued capability executes its exact intent once'
);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1(
    'f4110000-0000-4000-8000-000000000002','ARCHIVED',0,
    'f4400000-0000-4000-8000-000000000101','Capability single use',
    (select capability_token from capability_misuse_tokens where test_name = 'single_use'))$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'successfully consumed capability cannot be replayed'
);
select set_config('request.jwt.claim.sub', 'f4000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1(
    'f4110000-0000-4000-8000-000000000002','ARCHIVED',0,
    'f4400000-0000-4000-8000-000000000102','Capability cross actor',
    (select capability_token from capability_misuse_tokens where test_name = 'cross_actor'))$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'capability rejects cross-actor substitution'
);
select set_config('request.jwt.claim.sub', 'f4000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1(
    'f4100000-0000-4000-8000-000000000001','ARCHIVED',0,
    'f4400000-0000-4000-8000-000000000103','Capability cross dossier',
    (select capability_token from capability_misuse_tokens where test_name = 'cross_dossier'))$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'capability rejects cross-dossier substitution'
);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1(
    'f4110000-0000-4000-8000-000000000002','REACTIVATED',0,
    'f4400000-0000-4000-8000-000000000104','Capability cross action',
    (select capability_token from capability_misuse_tokens where test_name = 'cross_action'))$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'capability rejects cross-action substitution'
);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1(
    'f4110000-0000-4000-8000-000000000002','ARCHIVED',1,
    'f4400000-0000-4000-8000-000000000105','Capability revision',
    (select capability_token from capability_misuse_tokens where test_name = 'revision'))$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'capability rejects expected-revision substitution'
);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1(
    'f4110000-0000-4000-8000-000000000002','ARCHIVED',0,
    'f4400000-0000-4000-8000-000000000199','Capability idempotency',
    (select capability_token from capability_misuse_tokens where test_name = 'idempotency'))$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'capability rejects idempotency-key substitution'
);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1(
    'f4110000-0000-4000-8000-000000000002','ARCHIVED',0,
    'f4400000-0000-4000-8000-000000000107','Changed capability reason',
    (select capability_token from capability_misuse_tokens where test_name = 'reason'))$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'capability rejects reason substitution'
);
update lws_internal.operator_dossier_edge_capabilities
set issued_at = clock_timestamp() - interval '2 minutes',
    expires_at = clock_timestamp() - interval '90 seconds'
where capability_token = (select capability_token from capability_misuse_tokens where test_name = 'expired');
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1(
    'f4110000-0000-4000-8000-000000000002','ARCHIVED',0,
    'f4400000-0000-4000-8000-000000000108','Capability expired',
    (select capability_token from capability_misuse_tokens where test_name = 'expired'))$$,
  '42501', 'EDGE_DOSSIER_CAPABILITY_REQUIRED', 'expired capability is rejected'
);
select ok(
  (select state = 'ARCHIVED' and revision = 1
   from lws_internal.operator_dossier_states
  where quote_request_id = 'f4110000-0000-4000-8000-000000000002'),
  'rejected capability misuse leaves dossier state and revision unchanged'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_state_events
  where quote_request_id = 'f4110000-0000-4000-8000-000000000002'),
  1,
  'rejected capability misuse creates no unauthorized event'
);

select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'f4100000-0000-4000-8000-000000000001', 'ARCHIVED', 0,
    'f4400000-0000-4000-8000-000000000001', '  Archive dossier  '
  )->>'state',
  'ARCHIVED',
  'owner archives an ACTIVE dossier'
);
select is(
  (select access_state from public.quote_request_intakes where id = 'f4200000-0000-4000-8000-000000000001'),
  'CANCELLED',
  'dossier lifecycle is independent from terminal intake cancellation'
);
select set_config('request.jwt.claim.sub', 'f4000000-0000-4000-8000-000000000002', true);
select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'f4100000-0000-4000-8000-000000000001', 'REACTIVATED', 1,
    'f4400000-0000-4000-8000-000000000002', 'Reactivate dossier'
  )->>'state',
  'ACTIVE',
  'admin reactivates an ARCHIVED dossier'
);
select is(
  (select revision from lws_internal.operator_dossier_states where quote_request_id = 'f4100000-0000-4000-8000-000000000001'),
  2::bigint,
  'commands increment dossier revision exactly once'
);

select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'TRASHED', 0,
    'f4400000-0000-4000-8000-000000000003', 'Trash reviewed legacy dossier'
  )->>'state_before_trash',
  'ACTIVE',
  'exact-11 authority permits ACTIVE to TRASHED and records origin'
);
select is(
  (select deletion_eligible_at from lws_internal.operator_dossier_states where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  null::timestamptz,
  'trash command grants no purge eligibility'
);
select throws_ok(
  $$insert into public.sdf_projects(project_id,quote_request_id) values ('f4300000-0000-4000-8000-000000000002','d3752349-3489-4c19-bd03-f0cc076b5607')$$,
  '55000', 'TRASHED_DOSSIER_BLOCKER_CREATION_DENIED', 'SDF project creation is denied after dossier trash'
);
select throws_ok(
  $$insert into public.sdf_quotations(quotation_id,quote_request_id) values ('f4300000-0000-4000-8000-000000000003','d3752349-3489-4c19-bd03-f0cc076b5607')$$,
  '55000', 'TRASHED_DOSSIER_BLOCKER_CREATION_DENIED', 'SDF quotation creation is denied after dossier trash'
);
select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'RESTORED', 1,
    'f4400000-0000-4000-8000-000000000004', 'Restore active dossier'
  )->>'state',
  'ACTIVE',
  'TRASHED restores to prior ACTIVE state'
);
select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'ARCHIVED', 2,
    'f4400000-0000-4000-8000-000000000005', 'Archive reviewed legacy dossier'
  )->>'state',
  'ARCHIVED',
  'ACTIVE transitions to ARCHIVED before second trash path'
);
select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'TRASHED', 3,
    'f4400000-0000-4000-8000-000000000006', 'Trash archived legacy dossier'
  )->>'state_before_trash',
  'ARCHIVED',
  'exact-11 authority permits ARCHIVED to TRASHED and records origin'
);
select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'RESTORED', 4,
    'f4400000-0000-4000-8000-000000000007', 'Restore archived dossier'
  )->>'state',
  'ARCHIVED',
  'TRASHED restores to prior ARCHIVED state'
);
select is(
  (select state_before_trash from lws_internal.operator_dossier_states where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  null::text,
  'restored state clears prior trash origin'
);
select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'RESTORED', 4,
    'f4400000-0000-4000-8000-000000000007', 'Restore archived dossier'
  )->>'replayed',
  'true',
  'same idempotent command replays before stale-state validation'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_state_events where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  5,
  'idempotent replay creates no duplicate dossier event'
);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('d3752349-3489-4c19-bd03-f0cc076b5607','RESTORED',4,'f4400000-0000-4000-8000-000000000007','Changed reason')$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'changed replay is rejected'
);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('d3752349-3489-4c19-bd03-f0cc076b5607','REACTIVATED',4,'f4400000-0000-4000-8000-000000000008','Stale reactivation')$$,
  '40001', 'CONCURRENT_MODIFICATION', 'stale dossier revision is rejected'
);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('d3752349-3489-4c19-bd03-f0cc076b5607','ARCHIVED',5,'f4400000-0000-4000-8000-000000000009','Invalid archive')$$,
  'P0001', 'INVALID_OPERATOR_DOSSIER_TRANSITION', 'invalid self-transition is rejected'
);
select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    'f4100000-0000-4000-8000-000000000001', 'TRASHED', 2,
    'f4400000-0000-4000-8000-000000000010', 'Trash current test dossier'
  )->>'state',
  'TRASHED',
  'current production dossier moves to trash without legacy cleanup authority'
);
select is(
  (select state from lws_internal.operator_dossier_states where quote_request_id = 'f4100000-0000-4000-8000-000000000001'),
  'TRASHED',
  'move-to-trash state remains durable after the command'
);
select is(
  jsonb_array_length(public.list_operator_applications_v2(
    p_actor_auth_user_id => 'f4000000-0000-4000-8000-000000000002',
    p_zone => 'ACTIVE', p_search => 'LWS-AAN-2099-0401', p_limit => 10
  )->'items'),
  0,
  'trashed dossier disappears from the active projection'
);
select is(
  jsonb_array_length(public.list_operator_applications_v2(
    p_actor_auth_user_id => 'f4000000-0000-4000-8000-000000000002',
    p_zone => 'TRASHED', p_search => 'LWS-AAN-2099-0401', p_limit => 10
  )->'items'),
  1,
  'trashed dossier appears in the trash projection'
);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('f4100000-0000-4000-8000-000000000001','RESTORED',2,'f4400000-0000-4000-8000-000000000013','Stale restore')$$,
  '40001', 'CONCURRENT_MODIFICATION', 'stale dossier revision remains fail closed after trash'
);
select is(
  pg_temp.execute_operator_dossier_lifecycle_command_v1(
    '0696171e-a315-4c03-b402-ba0b689abfbc', 'TRASHED', 0,
    'f4400000-0000-4000-8000-000000000011', 'Trash dossier with protected dependency'
  )->>'state',
  'TRASHED',
  'existing protected dependencies do not block reversible trash placement'
);
select is(
  (select state from lws_internal.operator_dossier_states where quote_request_id = '0696171e-a315-4c03-b402-ba0b689abfbc'),
  'TRASHED',
  'dependency-bearing dossier remains durably trashed while purge stays separate'
);
select throws_ok(
  $$select pg_temp.execute_operator_dossier_lifecycle_command_v1('f4100000-0000-4000-8000-000000000099','ARCHIVED',0,'f4400000-0000-4000-8000-000000000012','Missing dossier')$$,
  'P0001', 'DOSSIER_NOT_FOUND', 'unknown dossier is rejected'
);
select is(
  (select actor_operator_id from lws_internal.operator_dossier_state_events where idempotency_key = 'f4400000-0000-4000-8000-000000000007'),
  'f4010000-0000-4000-8000-000000000002'::uuid,
  'immutable event records authenticated operator identity'
);
select ok(
  (select evidence = jsonb_build_object('contract_version', 1, 'expected_revision', 4)
   from lws_internal.operator_dossier_state_events where idempotency_key = 'f4400000-0000-4000-8000-000000000007'),
  'immutable event stores safe revision evidence'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_state_events where deletion_eligible_at is not null),
  0,
  'all dossier lifecycle command events preserve no-purge authority'
);
select throws_ok(
  $$update lws_internal.operator_dossier_state_events set reason = 'tampered' where idempotency_key = 'f4400000-0000-4000-8000-000000000007'$$,
  '55000', 'OPERATOR_DOSSIER_STATE_EVENT_APPEND_ONLY', 'dossier audit event remains append-only'
);
select ok(
  not has_table_privilege('authenticated', 'lws_internal.operator_dossier_states', 'select,insert,update,delete'),
  'authenticated role has no direct dossier state table rights'
);
select ok(
  not has_table_privilege('authenticated', 'lws_internal.operator_dossier_state_events', 'select,insert,update,delete'),
  'authenticated role has no direct dossier event table rights'
);
select is(
  (select count(*)::integer from lws_internal.legacy_test_cleanup_authorities),
  11,
  'dossier lifecycle commands preserve the exact-11 authority set'
);
select is(
  (select reason from lws_internal.operator_dossier_state_events where idempotency_key = 'f4400000-0000-4000-8000-000000000001'),
  'Archive dossier',
  'command normalizes reason before fingerprinting and audit persistence'
);
select lives_ok(
  $$insert into public.sdf_quotations(quotation_id,quote_request_id) values ('f4300000-0000-4000-8000-000000000004','d3752349-3489-4c19-bd03-f0cc076b5607')$$,
  'ARCHIVED dossier remains eligible for protected lifecycle data creation'
);

select * from finish();
rollback;

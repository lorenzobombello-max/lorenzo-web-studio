begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok(
  has_function_privilege('authenticated', 'public.get_operator_application_v1(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_application_v1(uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operator_application_v1(uuid,text)', 'execute'),
  'only authenticated humans can enter the application detail RPC'
);
select ok(
  not has_table_privilege('authenticated', 'lws_internal.operator_dossier_states', 'select')
  and not has_table_privilege('anon', 'lws_internal.operator_dossier_states', 'select')
  and not has_table_privilege('service_role', 'lws_internal.operator_dossier_states', 'select'),
  'dossier state table remains unavailable to runtime roles'
);

insert into auth.users(id, email) values
  ('c6000000-0000-4000-8000-000000000001', 'detail-owner@example.test'),
  ('c6000000-0000-4000-8000-000000000002', 'detail-operator@example.test'),
  ('c6000000-0000-4000-8000-000000000003', 'detail-unknown@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('c6010000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000001', 'Detail Owner', 'owner', 'ACTIVE'),
  ('c6010000-0000-4000-8000-000000000002', 'c6000000-0000-4000-8000-000000000002', 'Detail Operator', 'operator', 'ACTIVE');

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  name, email, description, privacy_consent, status
) values
  ('c6100000-0000-4000-8000-000000000001', 'LWS-AAN-2099-0601', 'production', 'slimme_documentenflow', 'start',
   'Detail First', 'detail-first@example.test', 'Detail lifecycle projection fixture.', true, 'approved'),
  ('c6110000-0000-4000-8000-000000000002', 'LWS-AAN-2099-0602', 'production', 'slimme_documentenflow', 'groei',
   'Detail Second', 'detail-second@example.test', 'Detail binding fixture.', true, 'approved');

update lws_internal.operator_dossier_states
set state = 'ARCHIVED', revision = 1, updated_at = clock_timestamp() + interval '1 second'
where quote_request_id = 'c6100000-0000-4000-8000-000000000001';

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.get_operator_application_v1('c6100000-0000-4000-8000-000000000001', null)$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is rejected'
);
select set_config('request.jwt.claim.sub', 'c6000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.get_operator_application_v1('c6100000-0000-4000-8000-000000000001', null)$$,
  '42501', 'UNKNOWN_OPERATOR', 'unknown operator is rejected'
);
select set_config('request.jwt.claim.sub', 'c6000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.get_operator_application_v1('c6100000-0000-4000-8000-000000000001', null)$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'non-owner operator is rejected'
);
select set_config('request.jwt.claim.sub', 'c6000000-0000-4000-8000-000000000001', true);

select is(
  public.get_operator_application_v1('c6100000-0000-4000-8000-000000000001', null)->'dossier_lifecycle'->>'state',
  'ARCHIVED',
  'detail projects the current authoritative dossier state'
);
select is(
  (public.get_operator_application_v1('c6100000-0000-4000-8000-000000000001', null)->'dossier_lifecycle'->>'revision')::bigint,
  1::bigint,
  'detail projects the current non-default authoritative revision'
);
select is(
  public.get_operator_application_v1('c6110000-0000-4000-8000-000000000002', null)->'dossier_lifecycle',
  jsonb_build_object('state', 'ACTIVE', 'revision', 0),
  'detail binds lifecycle state and revision to the selected quote request'
);
select is(
  public.get_operator_application_by_support_reference_v1('#C6100000')->'dossier_lifecycle',
  jsonb_build_object('state', 'ARCHIVED', 'revision', 1),
  'support-reference detail route inherits the authoritative lifecycle projection'
);
select is(
  public.get_operator_application_v1('c6100000-0000-4000-8000-000000000001', null) - 'dossier_lifecycle',
  public.get_operator_application_v1_pre_dossier_lifecycle_detail('c6100000-0000-4000-8000-000000000001', null),
  'existing application detail fields remain unchanged'
);
select is(
  (select count(*)::integer
   from jsonb_object_keys(public.get_operator_application_v1('c6100000-0000-4000-8000-000000000001', null)->'dossier_lifecycle')),
  2,
  'dossier lifecycle disclosure contains only state and revision'
);
select ok(
  not (public.get_operator_application_v1('c6100000-0000-4000-8000-000000000001', null)::text
    ~* 'state_before_trash|deletion_eligible_at|capability|service_role'),
  'detail response exposes no lifecycle internals, capability data, or service-role data'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'lws_internal.operator_dossier_states'::regclass
      and pg_get_constraintdef(oid) ~ 'revision >= 0'
  ),
  'authoritative storage rejects malformed negative revisions'
);

delete from lws_internal.operator_dossier_states
where quote_request_id = 'c6110000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.get_operator_application_v1('c6110000-0000-4000-8000-000000000002', null)$$,
  'P0001', 'OPERATOR_DOSSIER_STATE_REQUIRED', 'missing dossier state fails closed'
);

select * from finish();
rollback;
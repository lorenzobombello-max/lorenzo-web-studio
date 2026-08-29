begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'list_operator_pending_intakes_v1', array['uuid'],
  'pending-intake list RPC exists'
);
select ok(
  has_function_privilege('service_role', 'public.list_operator_pending_intakes_v1(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.list_operator_pending_intakes_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.list_operator_pending_intakes_v1(uuid)', 'execute'),
  'only service_role can enter the pending-intake transport'
);
select ok(
  not has_table_privilege('authenticated', 'lws_internal.operator_pending_intakes_v1', 'select')
  and not has_table_privilege('service_role', 'lws_internal.operator_pending_intakes_v1', 'select'),
  'pending-intake readmodel has no direct runtime read grant'
);

insert into auth.users (id, email) values
  ('f7100000-0000-4000-8000-000000000001', 'pending-owner@example.test'),
  ('f7100000-0000-4000-8000-000000000002', 'pending-admin@example.test'),
  ('f7100000-0000-4000-8000-000000000003', 'pending-operator@example.test'),
  ('f7100000-0000-4000-8000-000000000004', 'pending-disabled@example.test'),
  ('f7100000-0000-4000-8000-000000000005', 'pending-unknown@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('f7110000-0000-4000-8000-000000000001', 'f7100000-0000-4000-8000-000000000001', 'Pending Owner', 'owner', 'ACTIVE'),
  ('f7110000-0000-4000-8000-000000000002', 'f7100000-0000-4000-8000-000000000002', 'Pending Admin', 'admin', 'ACTIVE'),
  ('f7110000-0000-4000-8000-000000000003', 'f7100000-0000-4000-8000-000000000003', 'Pending Operator', 'operator', 'ACTIVE'),
  ('f7110000-0000-4000-8000-000000000004', 'f7100000-0000-4000-8000-000000000004', 'Pending Disabled', 'admin', 'DISABLED');

insert into public.quote_requests (
  id, application_reference, record_classification, request_kind,
  name, company, email, phone, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('f7200001-0000-4000-8000-000000000001', null, 'production', 'website', 'Invited Prospect', 'Invited BV', 'invited@example.test', '+32000000001', 'Webshop', 'EUR 3.000', 'flexible', 'Pending invited authority fixture.', true, 'approved'),
  ('f7200002-0000-4000-8000-000000000002', null, 'production', 'website', 'Started Prospect', 'Started BV', 'started@example.test', null, 'Website op maat', 'EUR 3.000', 'flexible', 'Pending started authority fixture.', true, 'approved'),
  ('f7200003-0000-4000-8000-000000000003', 'LWS-AAN-2099-0703', 'production', 'website', 'Submitted Customer', 'Submitted BV', 'submitted@example.test', null, 'Website op maat', 'EUR 3.000', 'flexible', 'Submitted exclusion fixture.', true, 'approved'),
  ('f7200004-0000-4000-8000-000000000004', 'LWS-AAN-2099-0704', 'production', 'website', 'Reviewed Customer', 'Reviewed BV', 'reviewed@example.test', null, 'Webshop', 'EUR 3.000', 'flexible', 'Reviewed exclusion fixture.', true, 'approved'),
  ('f7200005-0000-4000-8000-000000000005', null, 'production', 'website', 'Expired Prospect', null, 'expired@example.test', null, 'Website op maat', 'EUR 3.000', 'flexible', 'Expired access fixture.', true, 'approved');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, submitted_at, reviewed_at,
  confirmation, created_at
) values
  ('f7300000-0000-4000-8000-000000000001', 'f7200001-0000-4000-8000-000000000001', 'invited', repeat('1',64), '2099-08-30T12:00:00Z', 'ACTIVE', 0, null, null, null, false, '2099-08-23T12:00:00Z'),
  ('f7300000-0000-4000-8000-000000000002', 'f7200002-0000-4000-8000-000000000002', 'in_progress', repeat('2',64), '2099-08-30T12:00:00Z', 'INTERRUPTED', 1, '2099-08-24T12:00:00Z', null, null, false, '2099-08-23T13:00:00Z'),
  ('f7300000-0000-4000-8000-000000000003', 'f7200003-0000-4000-8000-000000000003', 'submitted', repeat('3',64), '2099-08-30T12:00:00Z', 'ACTIVE', 0, '2099-08-24T12:00:00Z', '2099-08-25T12:00:00Z', null, true, '2099-08-23T14:00:00Z'),
  ('f7300000-0000-4000-8000-000000000004', 'f7200004-0000-4000-8000-000000000004', 'reviewed', repeat('4',64), '2099-08-30T12:00:00Z', 'ACTIVE', 0, '2099-08-24T12:00:00Z', '2099-08-25T12:00:00Z', '2099-08-26T12:00:00Z', true, '2099-08-23T15:00:00Z'),
  ('f7300000-0000-4000-8000-000000000005', 'f7200005-0000-4000-8000-000000000005', 'invited', repeat('5',64), '2020-01-01T00:00:00Z', 'ACTIVE', 0, null, null, null, false, '2019-12-25T00:00:00Z');

select is(
  jsonb_array_length(public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000001')->'items'),
  3,
  'owner sees invited and in-progress intakes only'
);
select is(
  jsonb_array_length(public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000002')->'items'),
  3,
  'ACTIVE admin can read pending intakes'
);
select ok(
  public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000001')->'items'
    @> '[{"quote_request_id":"f7200001-0000-4000-8000-000000000001","intake_status":"invited"}]'::jsonb,
  'invited intake appears in pending list'
);
select ok(
  public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000001')->'items'
    @> '[{"quote_request_id":"f7200002-0000-4000-8000-000000000002","intake_status":"in_progress","effective_access":"INTERRUPTED"}]'::jsonb,
  'in-progress intake appears with authoritative effective access'
);
select ok(
  public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000001')->'items'
    @> '[{"quote_request_id":"f7200005-0000-4000-8000-000000000005","effective_access":"EXPIRED"}]'::jsonb,
  'expired access is derived by the authoritative resolver'
);
select is(
  (select count(*)::integer from lws_internal.operator_pending_intakes_v1 where intake_status in ('submitted', 'reviewed')),
  0,
  'submitted and reviewed intakes never enter pending readmodel'
);
select is(
  (select count(*)::integer from lws_internal.operator_application_readmodel_v2 where quote_request_id in (
    'f7200001-0000-4000-8000-000000000001', 'f7200002-0000-4000-8000-000000000002',
    'f7200005-0000-4000-8000-000000000005'
  )),
  0,
  'pending intakes never enter existing dossier readmodel'
);
select is(
  (select count(*)::integer from lws_internal.operator_application_readmodel_v2 where quote_request_id = 'f7200003-0000-4000-8000-000000000003'),
  1,
  'submitted intake remains present in existing dossier readmodel'
);
select is(
  (select count(distinct quote_request_id)::integer from lws_internal.operator_pending_intakes_v1 where quote_request_id::text like 'f720000%'),
  (select count(*)::integer from lws_internal.operator_pending_intakes_v1 where quote_request_id::text like 'f720000%'),
  'pending readmodel contains no duplicate quote request'
);
select is(
  (select count(*)::integer
   from lws_internal.operator_pending_intakes_v1 as pending
   join lws_internal.operator_application_readmodel_v2 as dossier using (quote_request_id)),
  0,
  'pending and dossier readmodels are mutually exclusive'
);
select throws_ok(
  $$select public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000003')$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'non-owner/admin operator is rejected'
);
select throws_ok(
  $$select public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000004')$$,
  '42501', 'OPERATOR_DISABLED', 'disabled admin is rejected'
);
select throws_ok(
  $$select public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000005')$$,
  '42501', 'UNKNOWN_OPERATOR', 'unknown identity is rejected'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      public.list_operator_pending_intakes_v1('f7100000-0000-4000-8000-000000000001')->'items'
    ) as item,
    lateral jsonb_object_keys(item) as field(key)
    where field.key in (
      'token', 'access_token', 'access_token_hash', 'token_hash',
      'encrypted_payload', 'service_role_key'
    )
  ),
  'pending DTO contains no token or secret fields'
);

update public.quote_request_intakes
set status = 'submitted',
    started_at = '2099-08-24T12:00:00Z',
    submitted_at = '2099-08-25T12:00:00Z',
    confirmation = true
where id = 'f7300000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from lws_internal.operator_pending_intakes_v1 where quote_request_id = 'f7200001-0000-4000-8000-000000000001'),
  0,
  'submitted transition removes intake from pending readmodel'
);
select is(
  (select count(*)::integer from lws_internal.operator_application_readmodel_v2 where quote_request_id = 'f7200001-0000-4000-8000-000000000001'),
  1,
  'same quote request enters existing dossier readmodel after submission'
);
select is(
  (select id from public.quote_request_intakes where quote_request_id = 'f7200001-0000-4000-8000-000000000001'),
  'f7300000-0000-4000-8000-000000000001'::uuid,
  'submission preserves the original intake identity'
);

select * from finish();
rollback;
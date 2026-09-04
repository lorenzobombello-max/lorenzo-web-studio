begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'list_operator_pending_intakes_v1', array['uuid', 'text'],
  'retention-aware pending list exists'
);
select has_function(
  'public', 'count_operator_active_pending_intakes_v1', array['uuid'],
  'active pending count projection exists'
);
select has_function(
  'public', 'execute_operator_pending_intake_retention_v1',
  array['uuid', 'uuid', 'text', 'bigint', 'uuid', 'text'],
  'pending retention command exists'
);
select has_function(
  'public', 'can_permanently_delete_pending_intake_v1',
  array['uuid', 'uuid', 'uuid'],
  'pending delete eligibility authority exists'
);
select has_function(
  'public', 'permanently_delete_pending_intake_v1',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text'],
  'pending permanent delete authority exists'
);
select ok(
  has_function_privilege('service_role', 'public.permanently_delete_pending_intake_v1(uuid,uuid,uuid,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.permanently_delete_pending_intake_v1(uuid,uuid,uuid,uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.permanently_delete_pending_intake_v1(uuid,uuid,uuid,uuid,text)', 'execute'),
  'only service transport can enter pending delete authority'
);
select ok(
  not has_table_privilege('service_role', 'lws_internal.operator_pending_intake_retention', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operator_pending_intake_retention', 'select,insert,update,delete'),
  'no runtime role can mutate retention tables directly'
);

insert into auth.users (id, email) values
  ('fb000000-0000-4000-8000-000000000001', 'workspace-owner@example.test'),
  ('fb000000-0000-4000-8000-000000000002', 'workspace-admin@example.test'),
  ('fb000000-0000-4000-8000-000000000003', 'workspace-operator@example.test'),
  ('fb000000-0000-4000-8000-000000000004', 'workspace-disabled@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('fb010000-0000-4000-8000-000000000001', 'fb000000-0000-4000-8000-000000000001', 'Workspace Owner', 'owner', 'ACTIVE'),
  ('fb010000-0000-4000-8000-000000000002', 'fb000000-0000-4000-8000-000000000002', 'Workspace Admin', 'admin', 'ACTIVE'),
  ('fb010000-0000-4000-8000-000000000003', 'fb000000-0000-4000-8000-000000000003', 'Workspace Operator', 'operator', 'ACTIVE'),
  ('fb010000-0000-4000-8000-000000000004', 'fb000000-0000-4000-8000-000000000004', 'Workspace Disabled', 'admin', 'DISABLED');

insert into public.quote_requests (
  id, application_reference, record_classification, request_kind,
  name, company, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('fb100000-0000-4000-8000-000000000001', null, 'production', 'website', 'Archive Prospect', 'Archive BV', 'archive@example.test', 'Website op maat', 'EUR 3.000', 'flexible', 'Archive fixture.', true, 'approved'),
  ('fb100002-0000-4000-8000-000000000002', null, 'production', 'website', 'Delete Invited', 'Fixture BV', 'delete-invited@example.test', 'Website op maat', 'EUR 3.000', 'flexible', 'Clean delete fixture.', true, 'approved'),
  ('fb100003-0000-4000-8000-000000000003', null, 'production', 'website', 'Delete Started', null, 'delete-started@example.test', 'Webshop', 'EUR 3.000', 'flexible', 'Clean started delete fixture.', true, 'approved'),
  ('fb100004-0000-4000-8000-000000000004', 'LWS-AAN-2099-0904', 'production', 'website', 'Protected Dossier', null, 'protected@example.test', 'Website op maat', 'EUR 3.000', 'flexible', 'Protected fixture.', true, 'approved'),
  ('fb100005-0000-4000-8000-000000000005', 'LWS-AAN-2099-0905', 'production', 'website', 'Submitted Dossier', null, 'submitted@example.test', 'Website op maat', 'EUR 3.000', 'flexible', 'Submitted fixture.', true, 'approved'),
  ('fb100006-0000-4000-8000-000000000006', null, 'production', 'website', 'Isolation Prospect', null, 'isolation@example.test', 'Website op maat', 'EUR 3.000', 'flexible', 'Isolation fixture.', true, 'approved');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, submitted_at, confirmation, created_at
) values
  ('fb200000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', 'invited', repeat('1', 64), '2099-09-30T12:00:00Z', 'ACTIVE', 0, null, null, false, '2099-09-01T12:00:00Z'),
  ('fb200000-0000-4000-8000-000000000002', 'fb100002-0000-4000-8000-000000000002', 'invited', repeat('2', 64), '2099-09-30T12:00:00Z', 'ACTIVE', 0, null, null, false, '2099-09-02T12:00:00Z'),
  ('fb200000-0000-4000-8000-000000000003', 'fb100003-0000-4000-8000-000000000003', 'in_progress', repeat('3', 64), '2099-09-30T12:00:00Z', 'INTERRUPTED', 2, '2099-09-03T12:00:00Z', null, false, '2099-09-03T11:00:00Z'),
  ('fb200000-0000-4000-8000-000000000004', 'fb100004-0000-4000-8000-000000000004', 'invited', repeat('4', 64), '2099-09-30T12:00:00Z', 'ACTIVE', 0, null, null, false, '2099-09-04T12:00:00Z'),
  ('fb200000-0000-4000-8000-000000000005', 'fb100005-0000-4000-8000-000000000005', 'submitted', repeat('5', 64), '2099-09-30T12:00:00Z', 'ACTIVE', 0, '2099-09-05T10:00:00Z', '2099-09-05T12:00:00Z', true, '2099-09-05T09:00:00Z'),
  ('fb200000-0000-4000-8000-000000000006', 'fb100006-0000-4000-8000-000000000006', 'invited', repeat('6', 64), '2099-09-30T12:00:00Z', 'ACTIVE', 0, null, null, false, '2099-09-06T12:00:00Z');

create temp table pending_workspace_before as
select status, access_state, access_token_expires_at, lifecycle_revision
from public.quote_request_intakes
where id = 'fb200000-0000-4000-8000-000000000001';

select set_config(
  'test.pending_support_reference',
  (select support_reference from public.quote_requests where id = 'fb100006-0000-4000-8000-000000000006'),
  true
);
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  (public.list_operator_pending_intakes_v1('fb000000-0000-4000-8000-000000000001', 'ACTIVE')->'items'->0 ? 'retention_state'),
  true,
  'new pending records default to ACTIVE in the readmodel'
);
select is(
  public.list_operator_pending_intakes_v1('fb000000-0000-4000-8000-000000000001', 'ACTIVE')->'items'->0->>'support_reference',
  current_setting('test.pending_support_reference'),
  'Website pending operator projection exposes its own canonical public dossier reference'
);
reset role;

select is(
  public.execute_operator_pending_intake_retention_v1(
    'fb000000-0000-4000-8000-000000000001',
    'fb200000-0000-4000-8000-000000000001', 'ARCHIVED', 0,
    'fb300000-0000-4000-8000-000000000001', 'Workspace cleanup'
  )->>'retention_state',
  'ARCHIVED',
  'owner archives one pending intake'
);

select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  jsonb_array_length(public.list_operator_pending_intakes_v1('fb000000-0000-4000-8000-000000000001', 'ACTIVE')->'items'),
  4,
  'archived intake is excluded from active workspace'
);
select is(
  (public.count_operator_active_pending_intakes_v1('fb000000-0000-4000-8000-000000000001')->>'active_count')::integer,
  4,
  'active counter excludes archived intake'
);
select is(
  jsonb_array_length(public.list_operator_pending_intakes_v1('fb000000-0000-4000-8000-000000000001', 'ARCHIVED')->'items'),
  1,
  'archived intake appears in archived workspace'
);
reset role;

select is(
  (select row(status, access_state, access_token_expires_at, lifecycle_revision)::text
   from public.quote_request_intakes where id = 'fb200000-0000-4000-8000-000000000001'),
  (select row(status, access_state, access_token_expires_at, lifecycle_revision)::text from pending_workspace_before),
  'archive preserves lifecycle, access and expiry'
);
select is(
  public.execute_operator_pending_intake_retention_v1(
    'fb000000-0000-4000-8000-000000000002',
    'fb200000-0000-4000-8000-000000000001', 'RESTORED', 1,
    'fb300000-0000-4000-8000-000000000002', 'Return to active follow-up'
  )->>'retention_state',
  'ACTIVE',
  'ACTIVE admin restores one pending intake'
);
select is(
  (select count(*)::integer from lws_internal.operator_pending_intake_retention_events
   where intake_id = 'fb200000-0000-4000-8000-000000000001'),
  2,
  'archive and restore retain immutable event evidence'
);
select throws_ok(
  $$select public.execute_operator_pending_intake_retention_v1(
    'fb000000-0000-4000-8000-000000000003',
    'fb200000-0000-4000-8000-000000000001', 'ARCHIVED', 2,
    'fb300000-0000-4000-8000-000000000003', 'Unauthorized attempt'
  )$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'non-owner/admin retention is rejected'
);
select throws_ok(
  $$select public.execute_operator_pending_intake_retention_v1(
    'fb000000-0000-4000-8000-000000000004',
    'fb200000-0000-4000-8000-000000000001', 'ARCHIVED', 2,
    'fb300000-0000-4000-8000-000000000004', 'Disabled attempt'
  )$$,
  '42501', 'OPERATOR_DISABLED', 'disabled admin retention is rejected'
);

select is(
  public.can_permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000001',
    'fb200000-0000-4000-8000-000000000002',
    'fb100002-0000-4000-8000-000000000002'
  )->>'can_permanently_delete',
  'true',
  'clean invited intake is delete eligible'
);
select is(
  public.can_permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000001',
    'fb200000-0000-4000-8000-000000000003',
    'fb100003-0000-4000-8000-000000000003'
  )->>'can_permanently_delete',
  'true',
  'clean in-progress intake is delete eligible'
);
select is(
  public.can_permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000001',
    'fb200000-0000-4000-8000-000000000005',
    'fb100005-0000-4000-8000-000000000005'
  )->>'delete_block_reason',
  'INTAKE_SUBMITTED',
  'submitted intake is blocked'
);
select is(
  public.can_permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000002',
    'fb200000-0000-4000-8000-000000000004',
    'fb100004-0000-4000-8000-000000000004'
  )->>'delete_block_reason',
  'COMMERCIAL_FOLLOW_UP_EXISTS',
  'application reference blocks permanent delete'
);
select ok(
  pg_get_functiondef('lws_internal.pending_intake_delete_block_reason_v1(uuid,uuid)'::regprocedure)
    ~ 'quote_request_quotation_approval_drafts'
  and pg_get_functiondef('lws_internal.pending_intake_delete_block_reason_v1(uuid,uuid)'::regprocedure)
    ~ 'quote_request_quotation_business_drafts'
  and pg_get_functiondef('lws_internal.pending_intake_delete_block_reason_v1(uuid,uuid)'::regprocedure)
    ~ 'quote_request_quotation_approvals'
  and pg_get_functiondef('lws_internal.pending_intake_delete_block_reason_v1(uuid,uuid)'::regprocedure)
    ~ 'sdf_projects'
  and pg_get_functiondef('lws_internal.pending_intake_delete_block_reason_v1(uuid,uuid)'::regprocedure)
    ~ 'sdf_quotations'
  and pg_get_functiondef('lws_internal.pending_intake_delete_block_reason_v1(uuid,uuid)'::regprocedure)
    ~ 'sdf_m1_invoice_candidates'
  and pg_get_functiondef('lws_internal.pending_intake_delete_block_reason_v1(uuid,uuid)'::regprocedure)
    ~ 'customer_requests'
  and pg_get_functiondef('lws_internal.pending_intake_delete_block_reason_v1(uuid,uuid)'::regprocedure)
    ~ 'quotation_vat_transaction_classifications',
  'delete authority checks all repository-backed official dependency roots'
);
select ok(
  lower(pg_get_functiondef('public.permanently_delete_pending_intake_v1(uuid,uuid,uuid,uuid,text)'::regprocedure))
    ~ 'pg_advisory_xact_lock.*dossier:'
  and lower(pg_get_functiondef('public.permanently_delete_pending_intake_v1(uuid,uuid,uuid,uuid,text)'::regprocedure))
    ~ 'for update',
  'delete rechecks dependencies behind shared transaction and row locks'
);
select throws_ok(
  $$select public.permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000003',
    'fb200000-0000-4000-8000-000000000002',
    'fb100002-0000-4000-8000-000000000002',
    'fb400000-0000-4000-8000-000000000001', 'Unauthorized delete'
  )$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'unauthorized permanent delete is rejected'
);
select is(
  public.permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000001',
    'fb200000-0000-4000-8000-000000000002',
    'fb100002-0000-4000-8000-000000000002',
    'fb400000-0000-4000-8000-000000000002', 'Delete disposable invited fixture'
  )->>'outcome',
  'deleted',
  'owner deletes clean invited chain'
);
select is(
  public.permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000002',
    'fb200000-0000-4000-8000-000000000003',
    'fb100003-0000-4000-8000-000000000003',
    'fb400000-0000-4000-8000-000000000003', 'Delete disposable started fixture'
  )->>'outcome',
  'deleted',
  'admin deletes clean in-progress chain'
);
select is(
  public.permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000001',
    'fb200000-0000-4000-8000-000000000002',
    'fb100002-0000-4000-8000-000000000002',
    'fb400000-0000-4000-8000-000000000002', 'Delete disposable invited fixture'
  )->>'outcome',
  'already_deleted',
  'same idempotency key safely replays deleted outcome'
);
select ok(
  not exists (select 1 from public.quote_requests where id in (
    'fb100002-0000-4000-8000-000000000002',
    'fb100003-0000-4000-8000-000000000003'
  ))
  and not exists (select 1 from public.quote_request_intakes where id in (
    'fb200000-0000-4000-8000-000000000002',
    'fb200000-0000-4000-8000-000000000003'
  ))
  and exists (select 1 from public.quote_requests where id = 'fb100006-0000-4000-8000-000000000006')
  and exists (select 1 from public.quote_request_intakes where id = 'fb200000-0000-4000-8000-000000000006'),
  'delete removes exact target chains and preserves other pending data'
);
select is(
  (select count(*)::integer from lws_internal.pending_intake_purge_tombstones
   where intake_id in (
     'fb200000-0000-4000-8000-000000000002',
     'fb200000-0000-4000-8000-000000000003'
   )),
  2,
  'each permanent delete retains an immutable tombstone'
);
select throws_ok(
  $$select public.permanently_delete_pending_intake_v1(
    'fb000000-0000-4000-8000-000000000001',
    'fb200000-0000-4000-8000-000000000004',
    'fb100004-0000-4000-8000-000000000004',
    'fb400000-0000-4000-8000-000000000004', 'Protected delete attempt'
  )$$,
  '55000', 'PENDING_INTAKE_DELETE_BLOCKED', 'protected commercial follow-up cannot be deleted'
);
select ok(
  exists (select 1 from public.quote_requests where id = 'fb100004-0000-4000-8000-000000000004')
  and exists (select 1 from public.quote_request_intakes where id = 'fb200000-0000-4000-8000-000000000004'),
  'blocked delete preserves protected business data'
);

select * from finish();
rollback;

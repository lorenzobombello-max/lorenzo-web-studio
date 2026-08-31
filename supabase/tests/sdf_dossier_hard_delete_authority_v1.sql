begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(32);

select has_function(
  'public', 'can_purge_sdf_dossier_v1', array['uuid'],
  'SDF purge eligibility authority exists'
);
select has_function(
  'public', 'purge_sdf_dossier_v1', array['uuid','text','uuid'],
  'SDF purge transaction authority exists'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.purge_sdf_dossier_v1(uuid,text,uuid)', 'execute'
  ) and not has_function_privilege(
    'anon', 'public.purge_sdf_dossier_v1(uuid,text,uuid)', 'execute'
  ) and not has_function_privilege(
    'service_role', 'public.purge_sdf_dossier_v1(uuid,text,uuid)', 'execute'
  ),
  'only authenticated callers can enter SDF purge authority'
);
select ok(
  pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%sdf_quotation_preparation_authorities%',
  'quotation preparation authority remains a hard blocker'
);
select ok(
  pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%sdf_quotation_acceptances%'
  and pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%sdf_accepted_commercial_terms%'
  and pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%sdf_milestone_one_obligations%',
  'acceptance, accepted terms, and commercial obligations remain hard blockers'
);
select ok(
  pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%sdf_m1_invoice_candidates%'
  and pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%sdf_m1_invoice_issuances%',
  'invoice candidate and issuance remain hard blockers'
);
select ok(
  pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%quotation_vat_transaction_classifications%'
  and pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%sdf_quotation_vat_authority_bindings%',
  'VAT and commercial bindings remain hard blockers'
);
select ok(
  pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%commercial_projects%'
  and pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%payment_expectations%'
  and pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%payment_evidence%'
  and pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%payment_reconciliations%',
  'generic projects and all payment layers remain hard blockers'
);
select ok(
  pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%customer_requests%'
  and pg_get_functiondef('lws_internal.sdf_dossier_purge_block_reason_v1(uuid)'::regprocedure)
    like '%document_inbox_customer_request_upload_sources%',
  'customer requests and document upload dependencies remain hard blockers'
);

insert into auth.users (id, email) values
  ('fc000000-0000-4000-8000-000000000001', 'sdf-purge-owner@example.test'),
  ('fc000000-0000-4000-8000-000000000002', 'sdf-purge-admin@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('fc010000-0000-4000-8000-000000000001', 'fc000000-0000-4000-8000-000000000001', 'SDF Purge Owner', 'owner', 'ACTIVE', null),
  ('fc010000-0000-4000-8000-000000000002', 'fc000000-0000-4000-8000-000000000002', 'SDF Purge Admin', 'admin', 'ACTIVE', null);

insert into public.quote_requests (
  id, record_classification, request_kind, sdf_package, name, email,
  website_type, budget, timing, description, privacy_consent, status
) values
  ('fc100001-0000-4000-8000-000000000001', 'production', 'slimme_documentenflow', 'start', 'Technical only', 'technical@example.test', null, null, null, 'Technical purge fixture.', true, 'approved'),
  ('fc100002-0000-4000-8000-000000000002', 'production', 'slimme_documentenflow', 'groei', 'Quotation blocked', 'quotation@example.test', null, null, null, 'Quotation blocker fixture.', true, 'approved'),
  ('fc100003-0000-4000-8000-000000000003', 'production', 'website', null, 'Website control', 'website@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Website isolation fixture.', true, 'approved'),
  ('fc100004-0000-4000-8000-000000000004', 'production', 'slimme_documentenflow', 'start', 'Active control', 'active@example.test', null, null, null, 'Active state fixture.', true, 'approved'),
  ('fc100005-0000-4000-8000-000000000005', 'production', 'slimme_documentenflow', 'start', 'Project blocked', 'project@example.test', null, null, null, 'Project blocker fixture.', true, 'approved'),
  ('fc100006-0000-4000-8000-000000000006', 'production', 'slimme_documentenflow', 'start', 'Customer blocked', 'customer@example.test', null, null, null, 'Customer blocker fixture.', true, 'approved');

insert into public.sdf_qualification_intakes (
  intake_id, quote_request_id, customer_capability_digest,
  customer_capability_encrypted, customer_capability_expires_at
) values (
  'fc200000-0000-4000-8000-000000000001',
  'fc100001-0000-4000-8000-000000000001', repeat('1', 64),
  'v1.abcdefghijklmnop.abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
  clock_timestamp() + interval '1 day'
);
insert into public.sdf_qualification_intake_submissions (
  submission_id, intake_id, submission_sequence, answers, taxonomy_version,
  payload_sha256, confirmation_version, confirmation_sha256
) values (
  'fc210000-0000-4000-8000-000000000001',
  'fc200000-0000-4000-8000-000000000001', 1, '{}'::jsonb,
  'sdf_qualification_intake/1.0.0', repeat('2', 64),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1', repeat('3', 64)
);
insert into public.sdf_qualification_intake_events (
  event_id, intake_id, event_kind, to_status, actor_class, result_snapshot
) values (
  'fc220000-0000-4000-8000-000000000001',
  'fc200000-0000-4000-8000-000000000001', 'INVITED', 'invited',
  'system', '{}'::jsonb
);
insert into public.sdf_qualification_intake_email_jobs (
  job_id, intake_id, kind, template_version, invitation_generation,
  idempotency_key, request_fingerprint
) values (
  'fc230000-0000-4000-8000-000000000001',
  'fc200000-0000-4000-8000-000000000001', 'invitation',
  'SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1', 1,
  'fc230000-0000-4000-8000-000000000002', repeat('4', 64)
);

insert into public.sdf_initial_confirmation_email_jobs (
  job_id, quote_request_id, status, attempt_count, next_attempt_at
) values (
  'fc240000-0000-4000-8000-000000000001',
  'fc100001-0000-4000-8000-000000000001', 'pending', 0, clock_timestamp()
);

insert into public.sdf_quotations (quotation_id, quote_request_id) values (
  'fc300000-0000-4000-8000-000000000001',
  'fc100002-0000-4000-8000-000000000002'
);
insert into public.sdf_projects (project_id, quote_request_id) values (
  'fc310000-0000-4000-8000-000000000001',
  'fc100005-0000-4000-8000-000000000005'
);
set local session_replication_role = replica;
insert into public.customer_requests (
  request_id, request_reference, quote_request_id, source, request_type,
  title, description, status, submitted_at, submitter_type
) values (
  'fc320000-0000-4000-8000-000000000001',
  'LWS-VRZ-2099-9001', 'fc100006-0000-4000-8000-000000000006',
  'OPERATOR', 'OTHER', 'Block purge', 'Commercial dependency fixture.',
  'NEW', clock_timestamp(), 'OPERATOR'
);
set local session_replication_role = origin;

create function pg_temp.trash_sdf_dossier(p_quote_request_id uuid, p_key uuid)
returns void
language plpgsql
as $$
declare
  v_capability uuid;
begin
  v_capability := public.issue_operator_dossier_lifecycle_edge_capability_v1(
    auth.uid(), p_quote_request_id, 'TRASHED', 0, p_key, 'Trash before SDF purge'
  );
  perform public.execute_operator_dossier_lifecycle_command_v1(
    p_quote_request_id, 'TRASHED', 0, p_key, 'Trash before SDF purge', v_capability
  );
end;
$$;

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000001', true);
select pg_temp.trash_sdf_dossier('fc100001-0000-4000-8000-000000000001', 'fc400001-0000-4000-8000-000000000001');
select pg_temp.trash_sdf_dossier('fc100002-0000-4000-8000-000000000002', 'fc400002-0000-4000-8000-000000000002');
select pg_temp.trash_sdf_dossier('fc100003-0000-4000-8000-000000000003', 'fc400003-0000-4000-8000-000000000003');
select pg_temp.trash_sdf_dossier('fc100005-0000-4000-8000-000000000005', 'fc400005-0000-4000-8000-000000000005');
select pg_temp.trash_sdf_dossier('fc100006-0000-4000-8000-000000000006', 'fc400006-0000-4000-8000-000000000006');

select is(
  public.can_purge_sdf_dossier_v1('fc100001-0000-4000-8000-000000000001')->>'can_purge',
  'true', 'trashed technical-only SDF dossier is eligible'
);
select is(
  public.can_purge_sdf_dossier_v1('fc100002-0000-4000-8000-000000000002')->>'reason',
  'SDF_QUOTATION_EXISTS', 'SDF quotation blocks purge with exact reason'
);
select is(
  public.can_purge_sdf_dossier_v1('fc100005-0000-4000-8000-000000000005')->>'reason',
  'PROJECT_EXISTS', 'SDF project blocks purge'
);
select is(
  public.can_purge_sdf_dossier_v1('fc100006-0000-4000-8000-000000000006')->>'reason',
  'CUSTOMER_REQUEST_EXISTS', 'customer request blocks purge'
);
select is(
  public.can_purge_sdf_dossier_v1('fc100003-0000-4000-8000-000000000003')->>'reason',
  'WRONG_PRODUCT_KIND', 'Website dossier is rejected by SDF authority'
);
select is(
  public.can_purge_sdf_dossier_v1('fc100004-0000-4000-8000-000000000004')->>'reason',
  'DOSSIER_NOT_TRASHED', 'active SDF dossier is rejected'
);
select is(
  public.can_purge_sdf_dossier_v1('fc109999-0000-4000-8000-000000000999')->>'reason',
  'DOSSIER_NOT_FOUND', 'unknown dossier is rejected'
);

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.purge_sdf_dossier_v1(
    'fc100001-0000-4000-8000-000000000001', 'Cleanup',
    'fc500000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'OWNER_REQUIRED', 'non-owner cannot purge SDF dossier'
);

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.purge_sdf_dossier_v1(
    'fc100002-0000-4000-8000-000000000002', 'Cleanup',
    'fc500000-0000-4000-8000-000000000002'
  )$$,
  '55000', 'SDF_QUOTATION_EXISTS', 'quotation-blocked dossier cannot purge'
);
select is(
  public.purge_sdf_dossier_v1(
    'fc100001-0000-4000-8000-000000000001', '  Technical cleanup  ',
    'fc500000-0000-4000-8000-000000000001'
  )->>'replayed',
  'false', 'owner purges technical-only SDF dossier once'
);
select is(
  (select count(*)::integer from public.quote_requests
   where id = 'fc100001-0000-4000-8000-000000000001'),
  0, 'SDF dossier root is deleted'
);
select is(
  (select count(*)::integer from public.sdf_qualification_intakes
   where quote_request_id = 'fc100001-0000-4000-8000-000000000001'),
  0, 'qualification intake is deleted child-first'
);
select is(
  (select count(*)::integer from public.sdf_qualification_intake_submissions
   where intake_id = 'fc200000-0000-4000-8000-000000000001'),
  0, 'qualification submissions are deleted'
);
select is(
  (select count(*)::integer from public.sdf_qualification_intake_events
   where intake_id = 'fc200000-0000-4000-8000-000000000001'),
  0, 'qualification events are deleted'
);
select is(
  (select count(*)::integer from public.sdf_qualification_intake_email_jobs
   where intake_id = 'fc200000-0000-4000-8000-000000000001'),
  0, 'qualification email jobs are deleted'
);
select is(
  (select count(*)::integer from public.sdf_initial_confirmation_email_jobs
   where quote_request_id = 'fc100001-0000-4000-8000-000000000001'),
  0, 'initial confirmation jobs are deleted'
);
select is(
  (select count(*)::integer from lws_internal.application_intake_automation_work
   where quote_request_id = 'fc100001-0000-4000-8000-000000000001'),
  0, 'automation work is deleted'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_states
   where quote_request_id = 'fc100001-0000-4000-8000-000000000001'),
  0, 'mutable dossier state is deleted'
);
select ok(
  exists (
    select 1 from lws_internal.dossier_identity_anchors
    where quote_request_id = 'fc100001-0000-4000-8000-000000000001'
  ) and exists (
    select 1 from lws_internal.dossier_purge_tombstones
    where quote_request_id = 'fc100001-0000-4000-8000-000000000001'
      and purge_reason = 'Technical cleanup'
      and request_kind = 'slimme_documentenflow'
  ),
  'identity anchor and normalized immutable tombstone are retained'
);
select is(
  public.purge_sdf_dossier_v1(
    'fc100001-0000-4000-8000-000000000001', 'Technical cleanup',
    'fc500000-0000-4000-8000-000000000001'
  )->>'replayed',
  'true', 'exact replay is deterministic after root deletion'
);
select throws_ok(
  $$select public.purge_sdf_dossier_v1(
    'fc100001-0000-4000-8000-000000000001', 'Changed reason',
    'fc500000-0000-4000-8000-000000000001'
  )$$,
  'P0001', 'DOSSIER_ALREADY_PURGED', 'changed replay is rejected'
);
select is(
  public.can_purge_sdf_dossier_v1('fc100001-0000-4000-8000-000000000001')->>'reason',
  'ALREADY_PURGED', 'eligibility reports already-purged tombstone'
);
select ok(
  public.can_purge_dossier_v1('fc100003-0000-4000-8000-000000000003') ? 'can_purge',
  'Website purge authority remains callable and unchanged'
);

select * from finish();
rollback;
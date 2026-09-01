begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

select has_table('lws_internal', 'intake_reminder_capability_escrow', 'private reminder capability escrow exists');
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'lws_internal.intake_reminder_capability_escrow'::regclass),
  'capability escrow has forced RLS'
);
select ok(
  not has_table_privilege('service_role', 'lws_internal.intake_reminder_capability_escrow', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.intake_reminder_capability_escrow', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'lws_internal.intake_reminder_capability_escrow', 'select,insert,update,delete'),
  'runtime roles have no direct escrow privileges'
);
select ok(
  has_function_privilege('service_role', 'public.get_intake_reminder_capability_v1(uuid,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_intake_reminder_capability_v1(uuid,bigint)', 'execute')
  and not has_function_privilege('anon', 'public.get_intake_reminder_capability_v1(uuid,bigint)', 'execute'),
  'capability retrieval is service-only'
);
select has_function(
  'public', 'prepare_intake_reminder_email_job_v1',
  array['uuid','bigint','text','uuid','timestamptz'],
  'reminder preparation no longer accepts caller-supplied ciphertext'
);
select ok(
  to_regprocedure('public.prepare_intake_reminder_email_job_v1(uuid,bigint,text,uuid,text,timestamptz)') is null,
  'legacy caller-supplied ciphertext preparation signature is absent'
);
select is(
  (select count(*)::integer
   from information_schema.columns
   where table_schema = 'lws_internal'
     and table_name = 'intake_reminder_capability_escrow'
     and column_name ~ '(^|_)token($|_)|plaintext|raw'),
  0,
  'escrow schema exposes no plaintext or token column'
);

insert into auth.users (id, email) values
  ('fc000001-0000-4000-8000-000000000001', 'capability-owner@example.test');
insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values (
  'fc010001-0000-4000-8000-000000000001',
  'fc000001-0000-4000-8000-000000000001',
  'Capability Owner', 'owner', 'ACTIVE'
);

insert into public.quote_requests (
  id, record_classification, request_kind, name, email, website_type,
  budget, timing, description, privacy_consent, status,
  approval_token_hash, approval_token_expires_at,
  budget_category_scheme, budget_category_code
) values
  ('fc100001-0000-4000-8000-000000000001', 'production', 'website', 'Escrow Invitation', 'escrow@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Capability fixture.', true, 'approved', repeat('a',64), clock_timestamp() + interval '1 day', 'budget_guard_v2', 'above_6000'),
  ('fc100002-0000-4000-8000-000000000002', 'production', 'website', 'Legacy Missing', 'legacy@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Legacy fixture.', true, 'approved', null, null, 'budget_guard_v2', 'above_6000'),
  ('fc100003-0000-4000-8000-000000000003', 'production', 'website', 'Cancelled', 'cancelled@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Cancellation fixture.', true, 'approved', null, null, 'budget_guard_v2', 'above_6000'),
  ('fc100004-0000-4000-8000-000000000004', 'production', 'website', 'Reviewed', 'reviewed@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Review fixture.', true, 'approved', null, null, 'budget_guard_v2', 'above_6000'),
  ('fc100005-0000-4000-8000-000000000005', 'production', 'website', 'Deleted', 'deleted@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Delete fixture.', true, 'approved', null, null, 'budget_guard_v2', 'above_6000');

create temp table invitation_created as
select * from public.create_quote_request_intake_invitation(
  repeat('a',64), repeat('b',64),
  'v1.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
);

select is((select outcome from invitation_created), 'invitation_created', 'invitation producer creates intake and delivery job');
select is(
  (select encrypted_capability from lws_internal.intake_reminder_capability_escrow
   where intake_id = (select intake_id from invitation_created) and access_cycle = 0),
  'v1.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
  'invitation transaction escrows the exact ciphertext for cycle zero'
);
select is(
  (select access_token_hash from public.quote_request_intakes
   where id = (select intake_id from invitation_created)),
  repeat('b',64),
  'escrowed capability remains bound to the authoritative access hash'
);

select * from public.create_quote_request_intake_invitation(
  repeat('a',64), repeat('b',64),
  'v1.CCCCCCCCCCCCCCCC.DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'
);
select is(
  (select count(*)::integer from lws_internal.intake_reminder_capability_escrow
   where intake_id = (select intake_id from invitation_created)),
  1,
  'repeated invitation construction is escrow-idempotent'
);
select is(
  (select count(*)::integer from public.claim_quote_request_email_job(
    (select invitation_job_id from invitation_created)
  )),
  1,
  'invitation job can enter the existing delivery pipeline'
);
select is(
  (select job_status from public.complete_quote_request_email_job(
    (select invitation_job_id from invitation_created), true, false, null, 'capability-test-provider-id'
  )),
  'sent',
  'invitation job can complete without sending real email in the SQL fixture'
);
select ok(
  (select encrypted_payload is null from public.quote_request_email_jobs
   where id = (select invitation_job_id from invitation_created))
  and exists(
    select 1 from lws_internal.intake_reminder_capability_escrow
    where intake_id = (select intake_id from invitation_created)
  ),
  'invitation payload cleanup remains intact while private escrow survives'
);
select results_eq(
  $$select outcome, encrypted_capability, access_token_hash
    from public.get_intake_reminder_capability_v1(
      (select intake_id from invitation_created), 0
    )$$,
  $$values (
    'CAPABILITY_AVAILABLE'::text,
    'v1.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'::text,
    repeat('b',64)::text
  )$$,
  'service authority returns ciphertext and its hash binding for the active current cycle'
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, submitted_at, reviewed_at,
  confirmation, created_at
) values
  ('fc200002-0000-4000-8000-000000000002', 'fc100002-0000-4000-8000-000000000002', 'invited', repeat('2',64), clock_timestamp() + interval '3 days', 'ACTIVE', 0, null, null, null, false, clock_timestamp() - interval '1 day'),
  ('fc200003-0000-4000-8000-000000000003', 'fc100003-0000-4000-8000-000000000003', 'invited', repeat('3',64), clock_timestamp() + interval '3 days', 'ACTIVE', 0, null, null, null, false, clock_timestamp() - interval '1 day'),
  ('fc200004-0000-4000-8000-000000000004', 'fc100004-0000-4000-8000-000000000004', 'submitted', repeat('4',64), clock_timestamp() + interval '3 days', 'ACTIVE', 0, clock_timestamp() - interval '2 days', clock_timestamp() - interval '1 day', null, true, clock_timestamp() - interval '3 days'),
  ('fc200005-0000-4000-8000-000000000005', 'fc100005-0000-4000-8000-000000000005', 'invited', repeat('5',64), clock_timestamp() + interval '3 days', 'ACTIVE', 0, null, null, null, false, clock_timestamp() - interval '1 day');

insert into lws_internal.intake_reminder_capability_escrow (
  intake_id, access_cycle, encrypted_capability
) values
  ('fc200003-0000-4000-8000-000000000003', 0, 'v1.EEEEEEEEEEEEEEEE.FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'),
  ('fc200004-0000-4000-8000-000000000004', 0, 'v1.GGGGGGGGGGGGGGGG.HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH'),
  ('fc200005-0000-4000-8000-000000000005', 0, 'v1.IIIIIIIIIIIIIIII.JJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJ');

select is(
  (select outcome from public.get_intake_reminder_capability_v1(
    'fc200002-0000-4000-8000-000000000002', 0
  )),
  'CAPABILITY_UNAVAILABLE',
  'legacy intake without recoverable ciphertext is explicitly unavailable'
);
create temp table legacy_claim as
select * from public.claim_intake_reminder_v1(
  'fc200002-0000-4000-8000-000000000002', 'REMINDER_1'
);
select is(
  (select outcome from public.prepare_intake_reminder_email_job_v1(
    'fc200002-0000-4000-8000-000000000002', 0, 'REMINDER_1',
    (select claim_token from legacy_claim), clock_timestamp()
  )),
  'CAPABILITY_UNAVAILABLE',
  'legacy reminder preparation fails closed with a safe outcome'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where reminder_intake_id = 'fc200002-0000-4000-8000-000000000002'),
  0,
  'missing legacy capability creates no reminder job'
);

select set_config('request.jwt.claim.sub', 'fc000001-0000-4000-8000-000000000001', true);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    (select intake_id from invitation_created), 'INTERRUPTED', 0,
    'fc300001-0000-4000-8000-000000000001', 'Pause capability fixture'
  )->>'effective_access',
  'INTERRUPTED',
  'capability fixture can be interrupted'
);
select ok(
  (select outcome from public.get_intake_reminder_capability_v1(
    (select intake_id from invitation_created), 0
  )) = 'CAPABILITY_UNAVAILABLE'
  and exists(
    select 1 from lws_internal.intake_reminder_capability_escrow
    where intake_id = (select intake_id from invitation_created) and access_cycle = 0
  ),
  'interruption hides retrieval but preserves escrow for resume'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    (select intake_id from invitation_created), 'RESUMED', 1,
    'fc300001-0000-4000-8000-000000000002', 'Resume same capability cycle'
  )->>'effective_access',
  'ACTIVE',
  'resume restores active access'
);
select ok(
  (select outcome from public.get_intake_reminder_capability_v1(
    (select intake_id from invitation_created), 0
  )) = 'CAPABILITY_AVAILABLE'
  and (select count(*) from lws_internal.intake_reminder_capability_escrow
       where intake_id = (select intake_id from invitation_created)) = 1,
  'resume reuses cycle zero without copying or rotating capability'
);

update public.quote_request_intakes
set created_at = clock_timestamp() - interval '8 days',
    access_token_expires_at = clock_timestamp() - interval '1 minute'
where id = (select intake_id from invitation_created);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    (select intake_id from invitation_created), 'REACTIVATED', 2,
    'fc300001-0000-4000-8000-000000000003', 'Start fresh capability cycle'
  )->>'effective_access',
  'ACTIVE',
  'reactivation restores active access without rotating the token'
);
select ok(
  exists(
    select 1 from lws_internal.intake_reminder_capability_escrow
    where intake_id = (select intake_id from invitation_created)
      and access_cycle = 1
      and copied_from_cycle = 0
      and encrypted_capability = 'v1.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
  )
  and (select access_token_hash from public.quote_request_intakes
       where id = (select intake_id from invitation_created)) = repeat('b',64),
  'reactivation carries the same hash-bound ciphertext into the new cycle'
);
select ok(
  (select outcome from public.get_intake_reminder_capability_v1(
    (select intake_id from invitation_created), 0
  )) = 'CAPABILITY_UNAVAILABLE'
  and (select outcome from public.get_intake_reminder_capability_v1(
    (select intake_id from invitation_created), 1
  )) = 'CAPABILITY_AVAILABLE',
  'retrieval exposes only the current reactivated cycle'
);

create temp table reactivated_claim as
select * from public.claim_intake_reminder_v1(
  (select intake_id from invitation_created), 'REMINDER_1',
  clock_timestamp() + interval '10 days 1 minute'
);
create temp table reactivated_job as
select * from public.prepare_intake_reminder_email_job_v1(
  (select intake_id from invitation_created), 1, 'REMINDER_1',
  (select claim_token from reactivated_claim),
  clock_timestamp() + interval '10 days 1 minute'
);
select is((select outcome from reactivated_job), 'prepared', 'reactivated cycle prepares from escrow without caller ciphertext');
select is(
  (select email_job_id from public.prepare_intake_reminder_email_job_v1(
    (select intake_id from invitation_created), 1, 'REMINDER_1',
    (select claim_token from reactivated_claim),
    clock_timestamp() + interval '10 days 1 minute'
  )),
  (select email_job_id from reactivated_job),
  'escrow-backed reminder preparation remains idempotent'
);

update public.quote_request_intakes
set status = 'submitted',
    started_at = clock_timestamp() - interval '1 day',
    submitted_at = clock_timestamp(),
    confirmation = true
where id = (select intake_id from invitation_created);
select is(
  (select count(*)::integer from lws_internal.intake_reminder_capability_escrow
   where intake_id = (select intake_id from invitation_created)),
  0,
  'submission deletes all escrow cycles'
);

update public.quote_request_intakes set access_state = 'CANCELLED'
where id = 'fc200003-0000-4000-8000-000000000003';
select is(
  (select count(*)::integer from lws_internal.intake_reminder_capability_escrow
   where intake_id = 'fc200003-0000-4000-8000-000000000003'),
  0,
  'cancellation deletes capability escrow'
);
update public.quote_request_intakes
set status = 'reviewed', reviewed_at = clock_timestamp()
where id = 'fc200004-0000-4000-8000-000000000004';
select is(
  (select count(*)::integer from lws_internal.intake_reminder_capability_escrow
   where intake_id = 'fc200004-0000-4000-8000-000000000004'),
  0,
  'review completion deletes capability escrow'
);
delete from public.quote_request_intakes
where id = 'fc200005-0000-4000-8000-000000000005';
select is(
  (select count(*)::integer from lws_internal.intake_reminder_capability_escrow
   where intake_id = 'fc200005-0000-4000-8000-000000000005'),
  0,
  'hard deletion cascades to capability escrow'
);

select * from finish();
rollback;
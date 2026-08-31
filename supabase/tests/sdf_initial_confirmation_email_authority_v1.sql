begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;

select no_plan();

select has_table(
  'public',
  'sdf_initial_confirmation_email_jobs',
  'SDF initial-confirmation business authority exists'
);
select columns_are(
  'public',
  'sdf_initial_confirmation_email_jobs',
  array[
    'job_id', 'quote_request_id', 'template_version', 'status',
    'attempt_count', 'max_attempts', 'next_attempt_at', 'locked_at',
    'delivery_lease_token', 'delivery_lease_expires_at', 'sent_at',
    'provider_message_id', 'last_error_code', 'created_at', 'updated_at'
  ],
  'SDF initial-confirmation authority has only the approved columns'
);
select col_is_pk(
  'public',
  'sdf_initial_confirmation_email_jobs',
  'job_id',
  'job_id is the immutable primary identity'
);
select col_is_unique(
  'public',
  'sdf_initial_confirmation_email_jobs',
  'quote_request_id',
  'one SDF request has at most one initial-confirmation authority'
);
select fk_ok(
  'public',
  'sdf_initial_confirmation_email_jobs',
  'quote_request_id',
  'public',
  'quote_requests',
  'id',
  'SDF initial confirmation correlates only to the neutral request root'
);
select is(
  (
    select confdeltype::text
    from pg_constraint
    where conrelid = to_regclass('public.sdf_initial_confirmation_email_jobs')
      and contype = 'f'
      and conname = 'sdf_initial_confirmation_email_jobs_quote_request_id_fkey'
  ),
  'r',
  'SDF request correlation uses ON DELETE RESTRICT'
);
select is(
  (
    select array_agg(
      format('%s:%s:%s', column_name, data_type, is_nullable)
      order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sdf_initial_confirmation_email_jobs'
  ),
  array[
    'job_id:uuid:NO',
    'quote_request_id:uuid:NO',
    'template_version:text:NO',
    'status:text:NO',
    'attempt_count:integer:NO',
    'max_attempts:integer:NO',
    'next_attempt_at:timestamp with time zone:NO',
    'locked_at:timestamp with time zone:YES',
    'delivery_lease_token:uuid:YES',
    'delivery_lease_expires_at:timestamp with time zone:YES',
    'sent_at:timestamp with time zone:YES',
    'provider_message_id:text:YES',
    'last_error_code:text:YES',
    'created_at:timestamp with time zone:NO',
    'updated_at:timestamp with time zone:NO'
  ]::text[],
  'SDF initial-confirmation columns have the approved types and nullability'
);
select is(
  (
    select count(*)::integer
    from pg_constraint
    where conrelid = to_regclass('public.sdf_initial_confirmation_email_jobs')
      and conname in (
        'sdf_initial_confirmation_email_jobs_template_version_check',
        'sdf_initial_confirmation_email_jobs_status_check',
        'sdf_initial_confirmation_email_jobs_attempt_count_check',
        'sdf_initial_confirmation_email_jobs_max_attempts_check',
        'sdf_initial_confirmation_email_jobs_lease_shape_check',
        'sdf_initial_confirmation_email_jobs_sent_at_shape_check',
        'sdf_initial_confirmation_email_jobs_attempts_within_max_check'
      )
  ),
  7,
  'SDF authority owns all approved named shape constraints'
);
select is(
  (
    select pg_get_constraintdef(oid)
    from pg_constraint
    where conrelid = to_regclass('public.sdf_initial_confirmation_email_jobs')
      and conname = 'sdf_initial_confirmation_email_jobs_status_check'
  ),
  'CHECK ((status = ANY (ARRAY[''pending''::text, ''processing''::text, ''retry_wait''::text, ''sent''::text, ''failed''::text])))',
  'SDF status contract is local and exact'
);
select is(
  (
    select pg_get_constraintdef(oid)
    from pg_constraint
    where conrelid = to_regclass('public.sdf_initial_confirmation_email_jobs')
      and conname = 'sdf_initial_confirmation_email_jobs_attempt_count_check'
  ),
  'CHECK (((attempt_count >= 0) AND (attempt_count <= 5)))',
  'SDF attempt count remains between zero and five'
);
select is(
  (
    select pg_get_constraintdef(oid)
    from pg_constraint
    where conrelid = to_regclass('public.sdf_initial_confirmation_email_jobs')
      and conname = 'sdf_initial_confirmation_email_jobs_lease_shape_check'
  ),
  'CHECK ((((status = ''processing''::text) AND (locked_at IS NOT NULL) AND (delivery_lease_token IS NOT NULL) AND (delivery_lease_expires_at IS NOT NULL)) OR ((status <> ''processing''::text) AND (locked_at IS NULL) AND (delivery_lease_token IS NULL) AND (delivery_lease_expires_at IS NULL))))',
  'SDF processing state exclusively owns complete lease data'
);
select is(
  (
    select pg_get_constraintdef(oid)
    from pg_constraint
    where conrelid = to_regclass('public.sdf_initial_confirmation_email_jobs')
      and conname = 'sdf_initial_confirmation_email_jobs_sent_at_shape_check'
  ),
  'CHECK ((((status = ''sent''::text) AND (sent_at IS NOT NULL)) OR ((status <> ''sent''::text) AND (sent_at IS NULL))))',
  'Only sent SDF jobs carry sent_at'
);
select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'sdf_initial_confirmation_email_jobs'
      and indexname = 'sdf_initial_confirmation_email_jobs_due_idx'
      and indexdef like '%(status, next_attempt_at, created_at)%'
      and indexdef like '%WHERE (status = ANY (ARRAY[''pending''::text, ''retry_wait''::text]))%'
  ),
  'SDF due index is local and restricted to pending and retry_wait'
);
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = to_regclass('public.sdf_initial_confirmation_email_jobs')
      and tgname = 'sdf_initial_confirmation_email_jobs_request_guard'
      and not tgisinternal
  ),
  'SDF authority has its product-specific request guard'
);
select ok(
  coalesce((
    select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = to_regclass('public.sdf_initial_confirmation_email_jobs')
  ), false),
  'SDF initial-confirmation state enables and forces RLS'
);
select is(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name = 'sdf_initial_confirmation_email_jobs'
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0,
  'SDF authority grants no direct table privileges'
);
select is(
  (
    select count(*)::integer
    from pg_depend
    where (
      objid = to_regclass('public.sdf_initial_confirmation_email_jobs')
      and refobjid = to_regclass('public.quote_request_email_jobs')
    ) or (
      objid = to_regclass('public.quote_request_email_jobs')
      and refobjid = to_regclass('public.sdf_initial_confirmation_email_jobs')
    )
  ),
  0,
  'SDF initial-confirmation authority has no Website mail-state dependency'
);

select has_function(
  'public',
  'prepare_sdf_initial_confirmation_v2',
  array['bigint', 'uuid'],
  'SDF initial-confirmation prepare authority exists'
);
select has_function(
  'public',
  'claim_sdf_initial_confirmation_email_job_v1',
  array['uuid'],
  'SDF initial-confirmation claim authority exists'
);
select has_function(
  'public',
  'validate_sdf_initial_confirmation_email_delivery_v1',
  array['uuid', 'uuid'],
  'SDF initial-confirmation lease-validation authority exists'
);
select has_function(
  'public',
  'complete_sdf_initial_confirmation_email_job_v1',
  array['uuid', 'uuid', 'boolean', 'boolean', 'text', 'text'],
  'SDF initial-confirmation completion authority exists'
);
select has_function(
  'lws_internal',
  'advance_sdf_automation_from_initial_confirmation_v1',
  array[]::text[],
  'SDF initial-confirmation completion projection trigger exists'
);
select ok(
  coalesce((
    select procedure.prosecdef
      and procedure.proowner = 'postgres'::regrole
      and procedure.proconfig = array['search_path=pg_catalog']::text[]
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'lws_internal'
      and procedure.proname = 'advance_sdf_automation_from_initial_confirmation_v1'
      and procedure.pronargs = 0
  ), false),
  'Projection trigger is SECURITY DEFINER with trusted owner and fixed search_path'
);
select ok(
  coalesce((
    select not has_function_privilege('anon', procedure.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
      and not has_function_privilege('service_role', procedure.oid, 'EXECUTE')
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'lws_internal'
      and procedure.proname = 'advance_sdf_automation_from_initial_confirmation_v1'
      and procedure.pronargs = 0
  ), false),
  'Projection trigger grants no PUBLIC-derived or direct client execution authority'
);
select ok(
  coalesce((
    select pg_get_triggerdef(trigger.oid) like '%AFTER UPDATE OF status, sent_at%'
      and pg_get_triggerdef(trigger.oid) like '%old.status IS DISTINCT FROM new.status%'
      and pg_get_triggerdef(trigger.oid) like '%old.sent_at IS DISTINCT FROM new.sent_at%'
    from pg_trigger as trigger
    where trigger.tgrelid = 'public.sdf_initial_confirmation_email_jobs'::regclass
      and trigger.tgname = 'sdf_initial_confirmation_email_jobs_project_completion'
      and not trigger.tgisinternal
  ), false),
  'Projection trigger is update-only and carries the explicit OLD/NEW transition guard'
);

create temporary table website_created as
select * from public.create_quote_request_idempotent(
  p_idempotency_key => 'fa200000-0000-4000-8000-000000000001',
  p_request_fingerprint => repeat('1', 64),
  p_request_kind => 'website',
  p_sdf_package => null,
  p_name => 'Website preservation',
  p_customer_type => 'individual',
  p_company => null,
  p_enterprise_number => null,
  p_enterprise_validation_status => 'not_checked',
  p_vat_number => null,
  p_vat_validation_status => 'not_checked',
  p_vat_validated_at => null,
  p_billing_address => null,
  p_billing_postal_code => null,
  p_billing_city => null,
  p_billing_country => null,
  p_billing_email => null,
  p_email => 'website-preservation@example.test',
  p_phone => null,
  p_website_type => 'Bedrijfswebsite',
  p_budget => 'EUR 3.000 - EUR 6.000',
  p_timing => 'Binnen 2 tot 3 maanden',
  p_description => 'Website authority preservation fixture.',
  p_privacy_consent => true,
  p_approval_token_hash => repeat('a', 64),
  p_approval_token_expires_at => clock_timestamp() + interval '1 day',
  p_client_ip_hash => repeat('2', 64),
  p_user_agent => 'pgtap-website-preservation'
);

select is(
  (select was_created from website_created),
  true,
  'Website request creation reports a new request'
);
select is(
  (select request_kind from public.quote_requests
   where id = (select request_id from website_created)),
  'website',
  'Website request creation preserves Website identity'
);
select is(
  (select kind::text from public.quote_request_email_jobs
   where id = (select admin_job_id from website_created)),
  'admin_notification',
  'Website request creation uses the existing Website mail authority'
);
select is(
  (select admin_job_status from website_created),
  'pending',
  'Website request creation keeps the existing pending admin job state'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = (select request_id from website_created)
     and kind = 'customer_confirmation'),
  0,
  'Website request creation does not create customer confirmation before approval'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = (select request_id from website_created)
     and template_key = 'SDF_REQUEST_RECEIVED_NL_BE_v1'),
  0,
  'Website request creation creates no SDF initial-mail state in the shared table'
);

create temporary table website_replayed as
select * from public.create_quote_request_idempotent(
  p_idempotency_key => 'fa200000-0000-4000-8000-000000000001',
  p_request_fingerprint => repeat('1', 64),
  p_request_kind => 'website',
  p_sdf_package => null,
  p_name => 'Website preservation',
  p_customer_type => 'individual',
  p_company => null,
  p_enterprise_number => null,
  p_enterprise_validation_status => 'not_checked',
  p_vat_number => null,
  p_vat_validation_status => 'not_checked',
  p_vat_validated_at => null,
  p_billing_address => null,
  p_billing_postal_code => null,
  p_billing_city => null,
  p_billing_country => null,
  p_billing_email => null,
  p_email => 'website-preservation@example.test',
  p_phone => null,
  p_website_type => 'Bedrijfswebsite',
  p_budget => 'EUR 3.000 - EUR 6.000',
  p_timing => 'Binnen 2 tot 3 maanden',
  p_description => 'Website authority preservation fixture.',
  p_privacy_consent => true,
  p_approval_token_hash => repeat('a', 64),
  p_approval_token_expires_at => clock_timestamp() + interval '1 day',
  p_client_ip_hash => repeat('2', 64),
  p_user_agent => 'pgtap-website-preservation'
);

select is((select was_created from website_replayed), false, 'Website request replay remains idempotent');
select is(
  (select request_id from website_replayed),
  (select request_id from website_created),
  'Website request replay returns the existing request'
);
select is(
  (select admin_job_id from website_replayed),
  (select admin_job_id from website_created),
  'Website request replay returns the existing admin mail job'
);

create temporary table website_approved as
select * from public.transition_quote_request_review(repeat('a', 64), 'approved');

select is((select review_status from website_approved), 'approved', 'Website approval remains approved');
select is(
  (select confirmation_job_status from website_approved),
  'pending',
  'Website approval creates the existing pending customer confirmation'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = (select request_id from website_created)
     and kind = 'customer_confirmation'),
  1,
  'Website approval creates exactly one customer confirmation in Website mail authority'
);
select is(
  (select template_key from public.quote_request_email_jobs
   where id = (select confirmation_job_id from website_approved)),
  null::text,
  'Website customer confirmation carries no SDF template authority'
);

create temporary table first_confirmation_claim as
select * from public.claim_quote_request_email_job(
  (select confirmation_job_id from website_approved)
);

select is((select count(*)::integer from first_confirmation_claim), 1, 'Website confirmation can be claimed');
select is((select attempt_count from first_confirmation_claim), 1, 'First Website claim records attempt one');
select is((select kind from first_confirmation_claim), 'customer_confirmation', 'Website claim preserves confirmation kind');

create temporary table retryable_completion as
select * from public.complete_quote_request_email_job(
  (select confirmation_job_id from website_approved),
  false,
  true,
  'RESEND_HTTP_503',
  null
);

select is((select job_status from retryable_completion), 'retry_wait', 'Retryable Website failure enters retry_wait');
select is((select attempt_count from retryable_completion), 1, 'Retryable Website completion preserves attempt one');
select is(
  (select provider_message_id from public.quote_request_email_jobs
   where id = (select confirmation_job_id from website_approved)),
  null::text,
  'Retryable Website failure records no provider success id'
);
select is(
  (select last_error_code from public.quote_request_email_jobs
   where id = (select confirmation_job_id from website_approved)),
  'RESEND_HTTP_503',
  'Retryable Website failure persists its existing error authority'
);

select ok(
  public.requeue_quote_request_email_job(
    (select confirmation_job_id from website_approved),
    'customer_confirmation'
  ),
  'Website confirmation can be requeued through the existing authority'
);

create temporary table second_confirmation_claim as
select * from public.claim_quote_request_email_job(
  (select confirmation_job_id from website_approved)
);

select is((select count(*)::integer from second_confirmation_claim), 1, 'Requeued Website confirmation can be reclaimed');
select is((select attempt_count from second_confirmation_claim), 2, 'Requeued Website confirmation records attempt two');

create temporary table successful_completion as
select * from public.complete_quote_request_email_job(
  (select confirmation_job_id from website_approved),
  true,
  false,
  null,
  'website-preservation-provider-id'
);

select is((select job_status from successful_completion), 'sent', 'Website confirmation completion remains sent');
select is((select attempt_count from successful_completion), 2, 'Website success retains the second attempt count');
select is(
  (select provider_message_id from public.quote_request_email_jobs
   where id = (select confirmation_job_id from website_approved)),
  'website-preservation-provider-id',
  'Website success persists its provider message id'
);
select isnt(
  (select confirmation_sent_at from public.quote_requests
   where id = (select request_id from website_created)),
  null::timestamptz,
  'Website success projects confirmation_sent_at'
);
select isnt(
  public.requeue_quote_request_email_job(
    (select confirmation_job_id from website_approved),
    'customer_confirmation'
  ),
  true,
  'Sent Website confirmation cannot be requeued'
);

select lives_ok(
  $$select * from public.transition_quote_request_review(repeat('a', 64), 'approved')$$,
  'Website approval replay remains idempotent after mail completion'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = (select request_id from website_created)
     and kind = 'customer_confirmation'),
  1,
  'Website approval replay creates no duplicate confirmation'
);
select is(
  (select status::text from public.quote_request_email_jobs
   where id = (select confirmation_job_id from website_approved)),
  'sent',
  'Website approval replay does not regress a sent confirmation'
);

create temporary table website_invitation as
select * from public.create_quote_request_intake_invitation(
  repeat('a', 64),
  repeat('b', 64),
  'v1.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
);

select is((select outcome from website_invitation), 'invitation_created', 'Website intake invitation transition remains available');
select is(
  (select status::text from public.quote_request_intakes
   where id = (select intake_id from website_invitation)),
  'invited',
  'Website intake transition preserves invited status'
);
select is(
  (select invitation_job_status from website_invitation),
  'pending',
  'Website intake transition creates its existing pending invitation job'
);
select is(
  (select kind::text from public.quote_request_email_jobs
   where id = (select invitation_job_id from website_invitation)),
  'intake_invitation',
  'Website intake invitation remains in Website mail authority'
);

create temporary table website_mail_snapshot as
select jsonb_agg(to_jsonb(job) order by job.id) as rows
from public.quote_request_email_jobs as job
where job.quote_request_id = (select request_id from website_created);

create temporary table website_projection_snapshot as
select confirmation_sent_at
from public.quote_requests
where id = (select request_id from website_created);

insert into public.quote_requests (
  id, record_classification, request_kind, sdf_package, name, email,
  description, privacy_consent, status, approval_token_hash,
  approval_token_expires_at
) values (
  'fa250000-0000-4000-8000-000000000001', 'production',
  'slimme_documentenflow', 'start', 'SDF isolation fixture',
  'sdf-isolation@example.test', 'SDF isolation-only fixture.', true,
  'pending', repeat('c', 64), clock_timestamp() + interval '1 day'
);

insert into lws_internal.application_intake_automation_work (
  quote_request_id,
  phase,
  approval_due_at,
  next_attempt_at
)
select
  'fa250000-0000-4000-8000-000000000001',
  'SDF_CONFIRMATION',
  fixture_clock.created_at,
  fixture_clock.created_at
from (select clock_timestamp() as created_at) as fixture_clock
on conflict (quote_request_id) do update
set phase = excluded.phase,
    approval_due_at = excluded.approval_due_at,
    next_attempt_at = excluded.next_attempt_at;

create temporary table sdf_work_claim as
with claim_clock as (
  select clock_timestamp() as claimed_at
), claimed_work as (
  update lws_internal.application_intake_automation_work as work
  set next_attempt_at = claim_clock.claimed_at,
      claim_token = 'fa260000-0000-4000-8000-000000000001',
      claimed_by = 'fa260000-0000-4000-8000-000000000002',
      claimed_at = claim_clock.claimed_at,
      claim_expires_at = claim_clock.claimed_at + interval '10 minutes'
  from claim_clock
  where work.quote_request_id = 'fa250000-0000-4000-8000-000000000001'
    and work.phase = 'SDF_CONFIRMATION'
  returning work.work_id, work.claim_token
)
select * from claimed_work;

select is(
  (select count(*)::integer from sdf_work_claim),
  1,
  'SDF prepare fixture owns one valid SDF_CONFIRMATION work lease'
);

do $test_stub$
begin
  if to_regprocedure('public.prepare_sdf_initial_confirmation_v2(bigint,uuid)') is null then
    execute $create_stub$
      create function public.prepare_sdf_initial_confirmation_v2(bigint, uuid)
      returns table (
        outcome text,
        authority_source text,
        job_id uuid,
        job_status text,
        next_attempt_at timestamptz,
        request_name text,
        request_email text,
        application_reference text,
        created_at timestamptz,
        request_kind text,
        template_version text
      )
      language sql
      as $stub_body$
        select null::text, null::text, null::uuid, null::text,
          null::timestamptz, null::text, null::text, null::text,
          null::timestamptz, null::text, null::text
        where false
      $stub_body$
    $create_stub$;
  end if;

  if to_regprocedure('public.claim_sdf_initial_confirmation_email_job_v1(uuid)') is null then
    execute $create_stub$
      create function public.claim_sdf_initial_confirmation_email_job_v1(uuid)
      returns table (
        job_id uuid,
        quote_request_id uuid,
        request_name text,
        request_email text,
        application_reference text,
        template_version text,
        attempt_count integer,
        provider_idempotency_key text,
        delivery_lease_token uuid,
        delivery_lease_expires_at timestamptz
      )
      language sql
      as $stub_body$
        select null::uuid, null::uuid, null::text, null::text, null::text,
          null::text, null::integer, null::text, null::uuid, null::timestamptz
        where false
      $stub_body$
    $create_stub$;
  end if;

  if to_regprocedure('public.validate_sdf_initial_confirmation_email_delivery_v1(uuid,uuid)') is null then
    execute $create_stub$
      create function public.validate_sdf_initial_confirmation_email_delivery_v1(uuid, uuid)
      returns boolean
      language sql
      stable
      as $stub_body$
        select false
      $stub_body$
    $create_stub$;
  end if;

  if to_regprocedure('public.complete_sdf_initial_confirmation_email_job_v1(uuid,uuid,boolean,boolean,text,text)') is null then
    execute $create_stub$
      create function public.complete_sdf_initial_confirmation_email_job_v1(
        uuid, uuid, boolean, boolean, text, text
      )
      returns jsonb
      language sql
      as $stub_body$
        select null::jsonb
      $stub_body$
    $create_stub$;
  end if;
end;
$test_stub$;

create temporary table sdf_prepared as
select *
from public.prepare_sdf_initial_confirmation_v2(
  (select work_id from sdf_work_claim),
  (select claim_token from sdf_work_claim)
);

select is((select count(*)::integer from sdf_prepared), 1, 'Valid SDF work lease prepares one authority');
select is((select outcome from sdf_prepared), 'due', 'New SDF initial confirmation is immediately due');
select is((select authority_source from sdf_prepared), 'sdf_initial', 'Prepare selects isolated SDF authority');
select is((select job_status from sdf_prepared), 'pending', 'Prepared SDF initial confirmation starts pending');
select is((select request_kind from sdf_prepared), 'slimme_documentenflow', 'Prepare returns only SDF request identity');
select is((select template_version from sdf_prepared), 'SDF_REQUEST_RECEIVED_NL_BE_v1', 'Prepare returns canonical SDF template authority');
select is(
  (select count(*)::integer from public.sdf_initial_confirmation_email_jobs
   where quote_request_id = 'fa250000-0000-4000-8000-000000000001'),
  1,
  'Prepare creates exactly one semantic SDF initial-confirmation job'
);
select is(
  'sdf-initial-confirmation/' || (select job_id::text from sdf_prepared),
  'sdf-initial-confirmation/' || (
    select job_id::text
    from public.sdf_initial_confirmation_email_jobs
    where quote_request_id = 'fa250000-0000-4000-8000-000000000001'
  ),
  'Prepared job has the stable SDF provider-idempotency identity'
);

create temporary table sdf_prepared_replay as
select *
from public.prepare_sdf_initial_confirmation_v2(
  (select work_id from sdf_work_claim),
  (select claim_token from sdf_work_claim)
);

select is((select job_id from sdf_prepared_replay), (select job_id from sdf_prepared), 'Prepare replay preserves immutable job_id');
select is(
  (select count(*)::integer from public.sdf_initial_confirmation_email_jobs
   where quote_request_id = 'fa250000-0000-4000-8000-000000000001'),
  1,
  'Prepare replay preserves one semantic row'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = 'fa250000-0000-4000-8000-000000000001'),
  0,
  'SDF prepare creates no Website mail-authority row'
);

create temporary table sdf_claimed as
select *
from public.claim_sdf_initial_confirmation_email_job_v1(
  (select job_id from sdf_prepared)
);

select is((select count(*)::integer from sdf_claimed), 1, 'Due SDF initial confirmation can be claimed once');
select is((select attempt_count from sdf_claimed), 1, 'SDF claim increments attempt_count exactly once');
select is(
  (select status from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from sdf_prepared)),
  'processing',
  'SDF claim moves its isolated job to processing'
);
select is(
  (select confirmation_sent_at from public.quote_requests
   where id = 'fa250000-0000-4000-8000-000000000001'),
  null::timestamptz,
  'Processing SDF initial confirmation does not project completion'
);
select isnt((select delivery_lease_token from sdf_claimed), null::uuid, 'SDF claim issues a unique mail lease token');
select ok(
  (select delivery_lease_expires_at > clock_timestamp() + interval '9 minutes 50 seconds'
   from sdf_claimed),
  'SDF claim issues the designed ten-minute mail lease'
);
select is(
  (select provider_idempotency_key from sdf_claimed),
  'sdf-initial-confirmation/' || (select job_id::text from sdf_prepared),
  'SDF claim returns the stable provider-idempotency key'
);

create temporary table sdf_second_claim as
select *
from public.claim_sdf_initial_confirmation_email_job_v1(
  (select job_id from sdf_prepared)
);

select is((select count(*)::integer from sdf_second_claim), 0, 'Active SDF processing lease cannot be claimed twice');

select ok(
  public.validate_sdf_initial_confirmation_email_delivery_v1(
    (select job_id from sdf_claimed),
    (select delivery_lease_token from sdf_claimed)
  ),
  'Current SDF mail lease validates immediately before provider I/O'
);
select is(
  public.validate_sdf_initial_confirmation_email_delivery_v1(
    (select job_id from sdf_claimed),
    'fa270000-0000-4000-8000-000000000099'
  ),
  false,
  'Wrong SDF mail lease token fails closed'
);
select is(
  public.validate_sdf_initial_confirmation_email_delivery_v1(
    'fa270000-0000-4000-8000-000000000098',
    (select delivery_lease_token from sdf_claimed)
  ),
  false,
  'Unknown SDF mail job fails lease validation closed'
);

update public.sdf_initial_confirmation_email_jobs
set delivery_lease_expires_at = clock_timestamp() - interval '1 second'
where job_id = (select job_id from sdf_claimed);

select is(
  public.validate_sdf_initial_confirmation_email_delivery_v1(
    (select job_id from sdf_claimed),
    (select delivery_lease_token from sdf_claimed)
  ),
  false,
  'Expired SDF mail lease fails validation closed'
);

create temporary table sdf_reclaimed as
select *
from public.claim_sdf_initial_confirmation_email_job_v1(
  (select job_id from sdf_claimed)
);

select is((select count(*)::integer from sdf_reclaimed), 1, 'Expired SDF processing lease is reclaimed once');
select is((select attempt_count from sdf_reclaimed), 2, 'Stale reclaim increments attempt_count exactly once');
select isnt(
  (select delivery_lease_token from sdf_reclaimed),
  (select delivery_lease_token from sdf_claimed),
  'Stale reclaim replaces the expired lease token'
);
select is(
  (select provider_idempotency_key from sdf_reclaimed),
  (select provider_idempotency_key from sdf_claimed),
  'Stale reclaim preserves the provider-idempotency key'
);
select ok(
  public.validate_sdf_initial_confirmation_email_delivery_v1(
    (select job_id from sdf_reclaimed),
    (select delivery_lease_token from sdf_reclaimed)
  ),
  'Replacement SDF mail lease validates'
);

create temporary table wrong_lease_completion as
select public.complete_sdf_initial_confirmation_email_job_v1(
  (select job_id from sdf_reclaimed),
  'fa270000-0000-4000-8000-000000000097',
  true,
  false,
  null,
  'must-not-persist'
) as result;

select is((select result from wrong_lease_completion), null::jsonb, 'Wrong SDF mail lease cannot complete');
select is(
  (select status from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from sdf_reclaimed)),
  'processing',
  'Wrong completion lease leaves SDF job processing'
);

create temporary table successful_sdf_completion as
select public.complete_sdf_initial_confirmation_email_job_v1(
  (select job_id from sdf_reclaimed),
  (select delivery_lease_token from sdf_reclaimed),
  true,
  false,
  null,
  'sdf-provider-message-id'
) as result;

select is((select result->>'status' from successful_sdf_completion), 'sent', 'Valid SDF mail lease completes successfully');
select is(
  (select status from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from sdf_reclaimed)),
  'sent',
  'Successful SDF completion persists terminal sent state'
);
select isnt(
  (select sent_at from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from sdf_reclaimed)),
  null::timestamptz,
  'Successful SDF completion records sent_at'
);
select is(
  (select provider_message_id from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from sdf_reclaimed)),
  'sdf-provider-message-id',
  'Successful SDF completion records provider evidence'
);
select is(
  (select delivery_lease_token from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from sdf_reclaimed)),
  null::uuid,
  'Successful SDF completion clears its mail lease'
);
select is(
  (select confirmation_sent_at from public.quote_requests
   where id = 'fa250000-0000-4000-8000-000000000001'),
  (select sent_at from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from sdf_reclaimed)),
  'Successful isolated SDF completion projects its durable sent_at exactly'
);
select is(
  (select count(*)::integer
   from lws_internal.application_intake_automation_work
   where quote_request_id = 'fa250000-0000-4000-8000-000000000001'
     and phase = 'SDF_INTAKE'),
  1,
  'Successful isolated SDF completion advances exactly one work row to SDF_INTAKE'
);
select is(
  (select intake_due_at - confirmation_sent_at
   from lws_internal.application_intake_automation_work as work
   join public.quote_requests as request on request.id = work.quote_request_id
   where work.quote_request_id = 'fa250000-0000-4000-8000-000000000001'),
  interval '120 seconds',
  'Existing downstream authority schedules SDF intake 120 seconds after projection'
);
select is(
  public.validate_sdf_initial_confirmation_email_delivery_v1(
    (select job_id from sdf_reclaimed),
    (select delivery_lease_token from sdf_reclaimed)
  ),
  false,
  'Sent SDF job no longer validates for provider delivery'
);
select is(
  public.complete_sdf_initial_confirmation_email_job_v1(
    (select job_id from sdf_reclaimed),
    (select delivery_lease_token from sdf_reclaimed),
    true,
    false,
    null,
    'second-provider-message-id'
  ),
  null::jsonb,
  'SDF completion replay after sent is an idempotent no-op'
);

create temporary table sdf_projection_snapshot as
select request.confirmation_sent_at, work.phase, work.approved_at, work.intake_due_at
from public.quote_requests as request
join lws_internal.application_intake_automation_work as work
  on work.quote_request_id = request.id
where request.id = 'fa250000-0000-4000-8000-000000000001';

update public.sdf_initial_confirmation_email_jobs
set status = status,
    sent_at = sent_at
where job_id = (select job_id from sdf_reclaimed);

select is(
  (select jsonb_build_object(
      'confirmation_sent_at', request.confirmation_sent_at,
      'phase', work.phase,
      'approved_at', work.approved_at,
      'intake_due_at', work.intake_due_at
    )
   from public.quote_requests as request
   join lws_internal.application_intake_automation_work as work
     on work.quote_request_id = request.id
   where request.id = 'fa250000-0000-4000-8000-000000000001'),
  (select jsonb_build_object(
      'confirmation_sent_at', confirmation_sent_at,
      'phase', phase,
      'approved_at', approved_at,
      'intake_due_at', intake_due_at
    ) from sdf_projection_snapshot),
  'Unchanged sent-row replay preserves the projection and downstream lifecycle exactly'
);
select is(
  (select provider_message_id from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from sdf_reclaimed)),
  'sdf-provider-message-id',
  'SDF completion replay preserves original provider evidence'
);
select is(
  (select count(*)::integer
   from public.claim_sdf_initial_confirmation_email_job_v1(
     (select job_id from sdf_reclaimed))),
  0,
  'Sent SDF job cannot be claimed again'
);

insert into public.quote_requests (
  id, record_classification, request_kind, sdf_package, name, email,
  description, privacy_consent, status, approval_token_hash,
  approval_token_expires_at
) values
  ('fa251000-0000-4000-8000-000000000002', 'production', 'slimme_documentenflow', 'start', 'SDF sent fixture', 'sdf-sent@example.test', 'Sent claim fixture.', true, 'pending', repeat('d', 64), clock_timestamp() + interval '1 day'),
  ('fa252000-0000-4000-8000-000000000003', 'production', 'slimme_documentenflow', 'start', 'SDF failed fixture', 'sdf-failed@example.test', 'Failed claim fixture.', true, 'pending', repeat('e', 64), clock_timestamp() + interval '1 day'),
  ('fa253000-0000-4000-8000-000000000004', 'production', 'slimme_documentenflow', 'start', 'SDF non-due fixture', 'sdf-nondue@example.test', 'Non-due claim fixture.', true, 'pending', repeat('f', 64), clock_timestamp() + interval '1 day'),
  ('fa254000-0000-4000-8000-000000000005', 'production', 'slimme_documentenflow', 'start', 'SDF terminal fixture', 'sdf-terminal@example.test', 'Terminal claim fixture.', true, 'pending', repeat('9', 64), clock_timestamp() + interval '1 day');

insert into public.sdf_initial_confirmation_email_jobs (
  quote_request_id,
  status,
  attempt_count,
  next_attempt_at,
  sent_at,
  last_error_code
) values
  ('fa251000-0000-4000-8000-000000000002', 'sent', 1, clock_timestamp(), clock_timestamp(), null),
  ('fa252000-0000-4000-8000-000000000003', 'failed', 5, clock_timestamp(), null, 'TERMINAL_TEST'),
  ('fa253000-0000-4000-8000-000000000004', 'retry_wait', 0, clock_timestamp() + interval '1 hour', null, 'RETRY_TEST'),
  ('fa254000-0000-4000-8000-000000000005', 'retry_wait', 4, clock_timestamp(), null, 'RETRY_TEST');

select is(
  (select count(*)::integer
   from public.claim_sdf_initial_confirmation_email_job_v1(
     (select job_id from public.sdf_initial_confirmation_email_jobs
      where quote_request_id = 'fa251000-0000-4000-8000-000000000002'))),
  0,
  'Sent SDF initial confirmation is not claimable'
);
select is(
  (select count(*)::integer
   from public.claim_sdf_initial_confirmation_email_job_v1(
     (select job_id from public.sdf_initial_confirmation_email_jobs
      where quote_request_id = 'fa252000-0000-4000-8000-000000000003'))),
  0,
  'Failed SDF initial confirmation is not claimable'
);
select is(
  (select count(*)::integer
   from public.claim_sdf_initial_confirmation_email_job_v1(
     (select job_id from public.sdf_initial_confirmation_email_jobs
      where quote_request_id = 'fa253000-0000-4000-8000-000000000004'))),
  0,
  'Non-due retry_wait SDF initial confirmation is not claimable'
);

insert into lws_internal.application_intake_automation_work (
  quote_request_id,
  phase,
  approval_due_at,
  next_attempt_at
)
select request_id, 'SDF_CONFIRMATION', fixture_clock.created_at, fixture_clock.created_at
from (
  values
    ('fa253000-0000-4000-8000-000000000004'::uuid),
    ('fa254000-0000-4000-8000-000000000005'::uuid)
) as fixture(request_id)
cross join (select clock_timestamp() as created_at) as fixture_clock
on conflict (quote_request_id) do update
set phase = excluded.phase,
    approval_due_at = excluded.approval_due_at,
    next_attempt_at = excluded.next_attempt_at;

update public.sdf_initial_confirmation_email_jobs
set next_attempt_at = clock_timestamp()
where quote_request_id = 'fa253000-0000-4000-8000-000000000004';

create temporary table retry_claim as
select *
from public.claim_sdf_initial_confirmation_email_job_v1(
  (select job_id from public.sdf_initial_confirmation_email_jobs
   where quote_request_id = 'fa253000-0000-4000-8000-000000000004')
);

select is((select attempt_count from retry_claim), 1, 'Retry fixture starts provider attempt one');

create temporary table retry_completion_clock as
select clock_timestamp() as completed_at;

create temporary table retry_completion as
select public.complete_sdf_initial_confirmation_email_job_v1(
  (select job_id from retry_claim),
  (select delivery_lease_token from retry_claim),
  false,
  true,
  'RESEND_HTTP_503',
  null
) as result;

select is((select result->>'status' from retry_completion), 'retry_wait', 'Transient SDF failure schedules retry_wait');
select is(
  (select status from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from retry_claim)),
  'retry_wait',
  'Transient SDF failure persists retry_wait in isolated authority'
);
select is(
  (select delivery_lease_token from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from retry_claim)),
  null::uuid,
  'Transient SDF failure clears its mail lease'
);
select is(
  (select confirmation_sent_at from public.quote_requests
   where id = 'fa253000-0000-4000-8000-000000000004'),
  null::timestamptz,
  'retry_wait SDF initial confirmation does not project completion'
);
select is(
  (select last_error_code from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from retry_claim)),
  'RESEND_HTTP_503',
  'Transient SDF failure records bounded error authority'
);
select ok(
  (select job.next_attempt_at between retry_clock.completed_at + interval '29 seconds'
                                  and retry_clock.completed_at + interval '31 seconds'
   from public.sdf_initial_confirmation_email_jobs as job
   cross join retry_completion_clock as retry_clock
   where job.job_id = (select job_id from retry_claim)),
  'Attempt-one SDF retry uses 30-second exponential backoff'
);

update public.sdf_initial_confirmation_email_jobs
set next_attempt_at = clock_timestamp()
where job_id = (select job_id from retry_claim);

create temporary table retry_reclaim as
select *
from public.claim_sdf_initial_confirmation_email_job_v1(
  (select job_id from retry_claim)
);

select is((select job_id from retry_reclaim), (select job_id from retry_claim), 'Retry reclaim preserves stable job_id');
select is((select attempt_count from retry_reclaim), 2, 'Retry reclaim increments to provider attempt two');
select is(
  (select provider_idempotency_key from retry_reclaim),
  (select provider_idempotency_key from retry_claim),
  'Retry reclaim preserves stable provider-idempotency key'
);

create temporary table terminal_claim as
select *
from public.claim_sdf_initial_confirmation_email_job_v1(
  (select job_id from public.sdf_initial_confirmation_email_jobs
   where quote_request_id = 'fa254000-0000-4000-8000-000000000005')
);

select is((select attempt_count from terminal_claim), 5, 'Terminal fixture claims provider attempt five');

create temporary table terminal_completion as
select public.complete_sdf_initial_confirmation_email_job_v1(
  (select job_id from terminal_claim),
  (select delivery_lease_token from terminal_claim),
  false,
  true,
  'RESEND_HTTP_503',
  null
) as result;

select is((select result->>'status' from terminal_completion), 'failed', 'Attempt-five SDF failure becomes terminal failed');
select is(
  (select status from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from terminal_claim)),
  'failed',
  'Terminal SDF failure persists failed state'
);
select is(
  (select delivery_lease_token from public.sdf_initial_confirmation_email_jobs
   where job_id = (select job_id from terminal_claim)),
  null::uuid,
  'Terminal SDF failure clears its mail lease'
);
select is(
  (select phase from lws_internal.application_intake_automation_work
   where quote_request_id = 'fa254000-0000-4000-8000-000000000005'),
  'MANUAL_REVIEW',
  'Terminal SDF failure moves only matching SDF work to MANUAL_REVIEW'
);
select is(
  (select confirmation_sent_at from public.quote_requests
   where id = 'fa254000-0000-4000-8000-000000000005'),
  null::timestamptz,
  'Failed SDF initial confirmation does not project completion'
);

create temporary table invalid_prepare as
select *
from public.prepare_sdf_initial_confirmation_v2(
  (select work_id from sdf_work_claim),
  'fa260000-0000-4000-8000-000000000099'
);

select is((select count(*)::integer from invalid_prepare), 0, 'Wrong work lease fails SDF prepare closed');

create temporary table website_work_claim as
with claim_clock as (
  select clock_timestamp() as claimed_at
), claimed_work as (
  update lws_internal.application_intake_automation_work as work
  set phase = 'SDF_CONFIRMATION',
      next_attempt_at = claim_clock.claimed_at,
      claim_token = 'fa260000-0000-4000-8000-000000000011',
      claimed_by = 'fa260000-0000-4000-8000-000000000012',
      claimed_at = claim_clock.claimed_at,
      claim_expires_at = claim_clock.claimed_at + interval '10 minutes'
  from claim_clock
  where work.quote_request_id = (select request_id from website_created)
  returning work.work_id, work.claim_token
)
select * from claimed_work;

create temporary table website_prepare_rejected as
select *
from public.prepare_sdf_initial_confirmation_v2(
  (select work_id from website_work_claim),
  (select claim_token from website_work_claim)
);

select is((select count(*)::integer from website_prepare_rejected), 0, 'Website request is not valid for SDF prepare authority');

select is(
  (select jsonb_agg(to_jsonb(job) order by job.id)
   from public.quote_request_email_jobs as job
   where job.quote_request_id = (select request_id from website_created)),
  (select rows from website_mail_snapshot),
  'SDF fixture creation leaves Website mail authority byte-identical'
);
select is(
  (select confirmation_sent_at from public.quote_requests
   where id = (select request_id from website_created)),
  (select confirmation_sent_at from website_projection_snapshot),
  'Isolated SDF completion does not project onto the Website request'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = 'fa250000-0000-4000-8000-000000000001'),
  0,
  'SDF fixture creates no mail state during the Task 1 preservation baseline'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = (select request_id from website_created)
     and template_key is not null),
  0,
  'Website mail authority remains free of SDF template state'
);

select * from finish();
rollback;
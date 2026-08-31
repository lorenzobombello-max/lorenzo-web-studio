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

select is(
  (select jsonb_agg(to_jsonb(job) order by job.id)
   from public.quote_request_email_jobs as job
   where job.quote_request_id = (select request_id from website_created)),
  (select rows from website_mail_snapshot),
  'SDF fixture creation leaves Website mail authority byte-identical'
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
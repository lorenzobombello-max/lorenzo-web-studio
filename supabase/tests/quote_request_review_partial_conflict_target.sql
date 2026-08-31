begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;

select plan(9);

select has_function(
  'public', 'transition_quote_request_review', array['text','text'],
  'existing quote request review RPC remains available'
);
select ok(
  pg_get_functiondef('public.transition_quote_request_review(text,text)'::regprocedure)
    ~* 'on conflict \(quote_request_id, kind\)[[:space:]]+where reminder_access_cycle is null[[:space:]]+do nothing',
  'customer confirmation insert targets the partial non-reminder unique index'
);
select ok(
  exists(
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'quote_request_email_jobs'
      and indexname = 'quote_request_email_jobs_request_kind_non_reminder_key'
      and indexdef ilike 'CREATE UNIQUE INDEX%'
      and indexdef ilike '%WHERE (reminder_access_cycle IS NULL)%'
  ),
  'non-reminder email uniqueness remains a partial unique index'
);

insert into public.quote_requests (
  id, record_classification, request_kind, name, email, website_type,
  budget, timing, description, privacy_consent, status,
  approval_token_hash, approval_token_expires_at
) values (
  'fc100000-0000-4000-8000-000000000001', 'production', 'website',
  'Conflict target fixture', 'conflict-target@example.test', 'business',
  'EUR 3.000', 'flexible', 'Partial conflict target regression.', true, 'pending',
  repeat('f', 64), clock_timestamp() + interval '1 day'
);

create temporary table first_approval as
select * from public.transition_quote_request_review(repeat('f', 64), 'approved');

select is(
  (select confirmation_job_status from first_approval),
  'pending',
  'first approval creates a pending customer confirmation job without 42P10'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = 'fc100000-0000-4000-8000-000000000001'
     and kind = 'customer_confirmation'),
  1,
  'first approval creates exactly one customer confirmation job'
);
select lives_ok(
  $$select * from public.transition_quote_request_review(repeat('f', 64), 'approved')$$,
  'approved replay remains idempotent'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where quote_request_id = 'fc100000-0000-4000-8000-000000000001'
     and kind = 'customer_confirmation'),
  1,
  'approved replay creates no duplicate customer confirmation job'
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, confirmation
) values (
  'fc200000-0000-4000-8000-000000000001',
  'fc100000-0000-4000-8000-000000000001',
  'invited', repeat('e', 64), clock_timestamp() + interval '7 days',
  'ACTIVE', 0, false
);

select lives_ok(
  $$insert into public.quote_request_email_jobs (
      quote_request_id, kind, reminder_intake_id, reminder_access_cycle,
      reminder_phase, reminder_claim_token
    ) values
      ('fc100000-0000-4000-8000-000000000001', 'intake_reminder_1',
       'fc200000-0000-4000-8000-000000000001', 0, 'REMINDER_1',
       'fc300000-0000-4000-8000-000000000001'),
      ('fc100000-0000-4000-8000-000000000001', 'intake_reminder_1',
       'fc200000-0000-4000-8000-000000000001', 1, 'REMINDER_1',
       'fc300000-0000-4000-8000-000000000002')$$,
  'reminder jobs remain independently unique by access cycle'
);
select is(
  (select status::text from public.quote_requests
   where id = 'fc100000-0000-4000-8000-000000000001'),
  'approved',
  'approval lifecycle semantics remain unchanged'
);

select * from finish();
rollback;
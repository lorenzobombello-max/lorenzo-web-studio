begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(24);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('27000000-0000-0000-0000-000000000001', 'Atomic draft', 'atomic-draft@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Atomic draft fixture.', true, 'approved'),
  ('27000000-0000-0000-0000-000000000002', 'Atomic submit', 'atomic-submit@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Atomic submit fixture.', true, 'approved'),
  ('27000000-0000-0000-0000-000000000003', 'Legacy failure', 'legacy-failure@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Legacy rollback fixture.', true, 'approved'),
  ('27000000-0000-0000-0000-000000000004', 'Evidence failure', 'evidence-failure@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Evidence rollback fixture.', true, 'approved'),
  ('27000000-0000-0000-0000-000000000005', 'Submitted protected', 'submitted-protected@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Submitted lifecycle fixture.', true, 'approved'),
  ('27000000-0000-0000-0000-000000000006', 'Standalone legacy', 'standalone-legacy@example.test', 'business', 'EUR 1.500 - EUR 3.000', 'flexible', 'Standalone legacy fixture.', true, 'approved'),
  ('27000000-0000-0000-0000-000000000007', 'Standalone bridge', 'standalone-bridge@example.test', 'business', 'EUR 1.500 - EUR 3.000', 'flexible', 'Standalone bridge fixture.', true, 'approved');

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation, primary_language, created_at
) values
  ('27000000-0000-0000-0000-000000000001', repeat('a', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('27000000-0000-0000-0000-000000000002', repeat('b', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('27000000-0000-0000-0000-000000000003', repeat('c', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('27000000-0000-0000-0000-000000000004', repeat('d', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('27000000-0000-0000-0000-000000000005', repeat('e', 64), clock_timestamp() + interval '1 day', 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, 'nl', clock_timestamp() - interval '3 hours'),
  ('27000000-0000-0000-0000-000000000006', repeat('f', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('27000000-0000-0000-0000-000000000007', repeat('0', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp());

create temporary table phase27_draft_result as
select *
from public.update_quote_request_intake_with_evidence(
  repeat('a', 64),
  'save_draft',
  '{"business_description":"Draft legacy data"}'::jsonb,
  '{"primary_language":"nl","additional_languages":["fr"]}'::jsonb
);

select is(
  (select outcome from phase27_draft_result),
  'saved',
  'draft and evidence save atomically'
);
select is(
  (select business_description from public.quote_request_intakes where access_token_hash = repeat('a', 64)),
  'Draft legacy data',
  'atomic draft stores legacy data'
);
select is(
  (select additional_languages from public.quote_request_intakes where access_token_hash = repeat('a', 64)),
  array['fr']::text[],
  'atomic draft stores raw evidence'
);
select is(
  (select status::text from public.quote_request_intakes where access_token_hash = repeat('a', 64)),
  'in_progress',
  'atomic draft preserves legacy lifecycle semantics'
);

create temporary table phase27_submit_result as
select *
from public.update_quote_request_intake_with_evidence(
  repeat('b', 64),
  'submit',
  '{
    "business_description":"Complete submit description",
    "target_audience":"Local businesses",
    "primary_conversion_goal":"Request a quote",
    "website_goals":["generate_leads"],
    "requested_pages":["home"],
    "requested_features":[],
    "design_styles":["modern"],
    "brand_status":"complete",
    "logo_status":"available",
    "content_status":"complete",
    "image_status":"sufficient",
    "domain_status":"has_domain",
    "hosting_status":"has_hosting",
    "maintenance_interest":"no",
    "seo_priority":"basic",
    "priorities":["usability"],
    "confirmation":true,
    "budget_update_category":"EUR 3.200 t/m EUR 6.000"
  }'::jsonb,
  '{
    "primary_language":"nl",
    "page_scope_details":{"gallery":"normal"},
    "budget_update_category":"EUR 3.200 t/m EUR 6.000",
    "budget_update_category_scheme":"budget_guard_v1",
    "budget_update_category_code":"3200_to_6000_inclusive"
  }'::jsonb,
  repeat('9', 64),
  clock_timestamp() + interval '1 day'
);

select is(
  (select outcome from phase27_submit_result),
  'submitted',
  'submit and evidence save atomically without v2 submit'
);
select is(
  (select status::text from public.quote_request_intakes where access_token_hash = repeat('b', 64)),
  'submitted',
  'atomic submit preserves legacy submitted status'
);
select is(
  (select page_scope_details->>'gallery' from public.quote_request_intakes where access_token_hash = repeat('b', 64)),
  'normal',
  'atomic submit stores raw evidence before lifecycle closes'
);
select is(
  (
    select count(*)::integer
    from public.quote_request_email_jobs
    where quote_request_id = '27000000-0000-0000-0000-000000000002'
      and kind = 'intake_submitted_notification'
  ),
  1,
  'atomic submit retains legacy notification job behavior'
);

select throws_matching(
  $$
    select *
    from public.update_quote_request_intake_with_evidence(
      repeat('c', 64),
      'submit',
      '{"business_description":"Incomplete submit"}'::jsonb,
      '{"primary_language":"nl"}'::jsonb,
      repeat('8', 64),
      clock_timestamp() + interval '1 day'
    )
  $$,
  'INCOMPLETE_INTAKE_SUBMISSION',
  'legacy failure aborts the orchestrated operation'
);
select is(
  (select primary_language from public.quote_request_intakes where access_token_hash = repeat('c', 64)),
  null::text,
  'legacy failure rolls back evidence update'
);
select is(
  (select status::text from public.quote_request_intakes where access_token_hash = repeat('c', 64)),
  'invited',
  'legacy failure rolls back evidence lifecycle changes'
);

select throws_matching(
  $$
    select *
    from public.update_quote_request_intake_with_evidence(
      repeat('d', 64),
      'save_draft',
      '{"business_description":"Must not persist"}'::jsonb,
      '{"page_scope_details":{"blog":"normal","unexpected":true}}'::jsonb
    )
  $$,
  'INVALID_PAGE_SCOPE_DETAILS',
  'evidence failure aborts before legacy mutation'
);
select is(
  (select business_description from public.quote_request_intakes where access_token_hash = repeat('d', 64)),
  null::text,
  'evidence failure leaves legacy data unchanged'
);

select is(
  (
    select outcome
    from public.update_quote_request_intake_with_evidence(
      repeat('e', 64),
      'save_draft',
      '{"business_description":"Forbidden submitted edit"}'::jsonb,
      '{"primary_language":"fr"}'::jsonb
    )
  ),
  'not_editable',
  'submitted intake remains protected by bridge lifecycle'
);
select is(
  (select primary_language from public.quote_request_intakes where access_token_hash = repeat('e', 64)),
  'nl',
  'submitted evidence remains immutable through orchestrator'
);

select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots),
  0,
  'orchestrator creates zero pricing snapshots'
);
select ok(
  position(
    'quote_request_pricing_snapshots'
    in pg_get_functiondef(
      'public.update_quote_request_intake_with_evidence(text,text,jsonb,jsonb,text,timestamp with time zone)'::regprocedure
    )
  ) = 0
  and position(
    'update_quote_request_intake_v2'
    in pg_get_functiondef(
      'public.update_quote_request_intake_with_evidence(text,text,jsonb,jsonb,text,timestamp with time zone)'::regprocedure
    )
  ) = 0,
  'orchestrator contains no pricing snapshot or v2 pricing-submit path'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_quote_request_intake_with_evidence(text,text,jsonb,jsonb,text,timestamp with time zone)',
    'execute'
  ),
  'anon cannot execute transactional orchestrator'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_quote_request_intake_with_evidence(text,text,jsonb,jsonb,text,timestamp with time zone)',
    'execute'
  ),
  'authenticated cannot execute transactional orchestrator'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.update_quote_request_intake_with_evidence(text,text,jsonb,jsonb,text,timestamp with time zone)',
    'execute'
  ),
  'service role can execute transactional orchestrator'
);

select is(
  (
    select outcome
    from public.update_quote_request_intake(
      repeat('f', 64),
      'save_draft',
      '{"business_description":"Standalone legacy remains available"}'::jsonb
    )
  ),
  'saved',
  'legacy RPC remains independently functional'
);
select is(
  (select business_description from public.quote_request_intakes where access_token_hash = repeat('f', 64)),
  'Standalone legacy remains available',
  'standalone legacy RPC still stores data'
);
select is(
  (
    select outcome
    from public.update_quote_request_intake_evidence(
      repeat('0', 64),
      '{"primary_language":"nl"}'::jsonb
    )
  ),
  'saved',
  'phase 2.6 bridge remains independently functional'
);
select is(
  (select primary_language from public.quote_request_intakes where access_token_hash = repeat('0', 64)),
  'nl',
  'standalone phase 2.6 bridge still stores evidence'
);

select * from finish();
rollback;

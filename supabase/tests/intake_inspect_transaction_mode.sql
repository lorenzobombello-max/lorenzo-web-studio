begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(22);

select is((select provolatile::text from pg_proc where oid = 'public.inspect_quote_request_intake_details_v2(text)'::regprocedure), 'v', 'v2 requests a read-write PostgREST transaction');
select is((select provolatile::text from pg_proc where oid = 'public.inspect_quote_request_intake_details_v3(text)'::regprocedure), 'v', 'v3 requests a read-write PostgREST transaction');
select is((select provolatile::text from pg_proc where oid = 'public.inspect_quote_request_intake_details_v4(text)'::regprocedure), 'v', 'v4 requests a read-write PostgREST transaction');
select is((select provolatile::text from pg_proc where oid = 'public.inspect_quote_request_intake_details_v5(text)'::regprocedure), 'v', 'v5 requests a read-write PostgREST transaction');
select ok(position('for share' in lower(pg_get_functiondef('public.inspect_quote_request_intake_details(text)'::regprocedure))) > 0, 'customer inspect retains its shared lifecycle lock');
select ok(position('inspect_quote_request_intake_details(p_access_token_hash)' in pg_get_functiondef('public.inspect_quote_request_intake_details_v2(text)'::regprocedure)) > 0, 'v2 retains the lifecycle-enforced authority');
select ok(position('inspect_quote_request_intake_details_v2(p_access_token_hash)' in pg_get_functiondef('public.inspect_quote_request_intake_details_v3(text)'::regprocedure)) > 0, 'v3 retains delegation to v2');
select ok(position('inspect_quote_request_intake_details_v3(p_access_token_hash)' in pg_get_functiondef('public.inspect_quote_request_intake_details_v4(text)'::regprocedure)) > 0, 'v4 retains delegation to v3');
select ok(position('inspect_quote_request_intake_details_v4(p_access_token_hash)' in pg_get_functiondef('public.inspect_quote_request_intake_details_v5(text)'::regprocedure)) > 0, 'v5 retains delegation to v4');
select ok(has_function_privilege('service_role', 'public.inspect_quote_request_intake_details_v5(text)', 'execute'), 'service role retains v5 execute privilege');
select ok(not has_function_privilege('anon', 'public.inspect_quote_request_intake_details_v5(text)', 'execute') and not has_function_privilege('authenticated', 'public.inspect_quote_request_intake_details_v5(text)', 'execute'), 'public roles remain unable to inspect customer intake details');

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  ('f2500000-0000-4000-8000-000000000001', 'Active inspect', 'active-inspect@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Active inspect fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2500001-0000-4000-8000-000000000002', 'Interrupted inspect', 'interrupted-inspect@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Interrupted inspect fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2500002-0000-4000-8000-000000000003', 'Expired inspect', 'expired-inspect@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Expired inspect fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2500003-0000-4000-8000-000000000004', 'Cancelled inspect', 'cancelled-inspect@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Cancelled inspect fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2500004-0000-4000-8000-000000000005', 'Revoked inspect', 'revoked-inspect@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Revoked inspect fixture.', true, 'approved', 'budget_guard_v2', 'above_6000');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_token_revoked_at, access_state, started_at, created_at, draft_revision
) values
  ('f2510000-0000-4000-8000-000000000001', 'f2500000-0000-4000-8000-000000000001', 'invited', repeat('a', 64), clock_timestamp() + interval '1 day', null, 'ACTIVE', null, clock_timestamp(), 7),
  ('f2510000-0000-4000-8000-000000000002', 'f2500001-0000-4000-8000-000000000002', 'in_progress', repeat('b', 64), clock_timestamp() + interval '1 day', null, 'INTERRUPTED', clock_timestamp() - interval '1 hour', clock_timestamp(), 2),
  ('f2510000-0000-4000-8000-000000000003', 'f2500002-0000-4000-8000-000000000003', 'in_progress', repeat('c', 64), clock_timestamp() - interval '1 hour', null, 'ACTIVE', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '2 days', 3),
  ('f2510000-0000-4000-8000-000000000004', 'f2500003-0000-4000-8000-000000000004', 'in_progress', repeat('d', 64), clock_timestamp() + interval '1 day', null, 'CANCELLED', clock_timestamp() - interval '1 hour', clock_timestamp(), 4),
  ('f2510000-0000-4000-8000-000000000005', 'f2500004-0000-4000-8000-000000000005', 'in_progress', repeat('e', 64), clock_timestamp() + interval '1 day', clock_timestamp(), 'CANCELLED', clock_timestamp() - interval '1 hour', clock_timestamp(), 5);

set local role service_role;

select is(current_setting('transaction_read_only'), 'off', 'service-role inspect runs in a transaction that permits the shared lock');
select is((select intake_status from public.inspect_quote_request_intake_details_v5(repeat('a', 64))), 'invited', 'ACTIVE service-role v5 inspect succeeds without SQLSTATE 25006');
select is((select draft_revision from public.inspect_quote_request_intake_details_v5(repeat('a', 64))), 7::bigint, 'v5 preserves the draft revision return contract');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v5(repeat('b', 64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'INTERRUPTED remains denied by lifecycle authority');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v5(repeat('c', 64))$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'EXPIRED remains denied by lifecycle authority');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v5(repeat('d', 64))$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'CANCELLED remains denied by lifecycle authority');
select is((select count(*)::integer from public.inspect_quote_request_intake_details_v5(repeat('e', 64))), 0, 'revoked capability remains indistinguishable from no result');
select is((select count(*)::integer from public.inspect_quote_request_intake_details_v5(repeat('f', 64))), 0, 'unknown capability remains indistinguishable from no result');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v2(repeat('b', 64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'legacy v2 cannot bypass lifecycle authority');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v3(repeat('b', 64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'legacy v3 cannot bypass lifecycle authority');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v4(repeat('b', 64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'legacy v4 cannot bypass lifecycle authority');

reset role;

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = public, extensions;

select plan(45);

select has_schema('lws_internal', 'private limiter schema exists');
select has_table('lws_internal', 'preview_rate_limit_buckets', 'private limiter bucket table exists');
select has_pk('lws_internal', 'preview_rate_limit_buckets', 'bucket table has an atomic conflict key');
select has_index(
  'lws_internal', 'preview_rate_limit_buckets', 'preview_rate_limit_buckets_expiry_idx',
  'expiry cleanup has a supporting index'
);
select ok(not has_schema_privilege('anon', 'lws_internal', 'usage'), 'anon cannot use limiter schema');
select ok(not has_schema_privilege('authenticated', 'lws_internal', 'usage'), 'authenticated cannot use limiter schema');
select ok(not has_table_privilege('anon', 'lws_internal.preview_rate_limit_buckets', 'select'), 'anon cannot read limiter state');
select ok(not has_table_privilege('authenticated', 'lws_internal.preview_rate_limit_buckets', 'insert'), 'authenticated cannot create limiter state');
select ok(not has_table_privilege('service_role', 'lws_internal.preview_rate_limit_buckets', 'select'), 'service role cannot bypass limiter RPC');
select ok(not has_function_privilege('anon', 'public.consume_preview_rate_limit_v1(text,text,integer,integer,integer)', 'execute'), 'anon cannot execute limiter RPC');
select ok(not has_function_privilege('authenticated', 'public.consume_preview_rate_limit_v1(text,text,integer,integer,integer)', 'execute'), 'authenticated cannot execute limiter RPC');
select ok(has_function_privilege('service_role', 'public.consume_preview_rate_limit_v1(text,text,integer,integer,integer)', 'execute'), 'service role can execute limiter RPC');

select is(
  (select allowed from public.consume_preview_rate_limit_v1('preview_global', repeat('a', 64), 60, 2, 0)),
  true,
  'first request is allowed'
);
select is(
  (select remaining from public.consume_preview_rate_limit_v1('preview_global', repeat('a', 64), 60, 2, 0)),
  0,
  'second request consumes the remaining capacity'
);
select is(
  (select allowed from public.consume_preview_rate_limit_v1('preview_global', repeat('a', 64), 60, 2, 0)),
  false,
  'request above the limit is denied atomically'
);
select ok(
  (select retry_after_seconds between 1 and 60
   from public.consume_preview_rate_limit_v1('preview_global', repeat('a', 64), 60, 2, 0)),
  'denied result returns authoritative bounded retry-after'
);
select ok(
  (select reset_at > clock_timestamp()
   from public.consume_preview_rate_limit_v1('preview_global', repeat('a', 64), 60, 2, 0)),
  'window reset is authoritative server time'
);

select is(
  (select allowed from public.consume_preview_rate_limit_v1('preview_capability', repeat('a', 64), 60, 1, 0)),
  true,
  'same key in another namespace has isolated capacity'
);
select is(
  (select allowed from public.consume_preview_rate_limit_v1('preview_capability', repeat('b', 64), 60, 1, 0)),
  true,
  'different valid capabilities have isolated capacity'
);
select is(
  (select allowed from public.consume_preview_rate_limit_v1('preview_capability', repeat('a', 64), 60, 1, 0)),
  false,
  'capability bucket denies independently above its limit'
);

select throws_ok(
  $$select * from public.consume_preview_rate_limit_v1('invalid', repeat('a', 64), 60, 2, 0)$$,
  '22023', 'INVALID_RATE_LIMIT_NAMESPACE', 'unknown namespace is rejected'
);
select throws_ok(
  $$select * from public.consume_preview_rate_limit_v1('preview_global', 'raw-capability', 60, 2, 0)$$,
  '22023', 'INVALID_RATE_LIMIT_KEY', 'raw capability cannot be a storage key'
);
select throws_ok(
  $$select * from public.consume_preview_rate_limit_v1('preview_global', repeat('a', 64), 0, 2, 0)$$,
  '22023', 'INVALID_RATE_LIMIT_WINDOW', 'zero window is rejected'
);
select throws_ok(
  $$select * from public.consume_preview_rate_limit_v1('preview_global', repeat('a', 64), 60, 10001, 0)$$,
  '22023', 'INVALID_RATE_LIMIT_MAX_REQUESTS', 'counter bound cannot exceed table capacity'
);
select throws_ok(
  $$select * from public.consume_preview_rate_limit_v1('preview_global', repeat('a', 64), 60, 2, 101)$$,
  '22023', 'INVALID_RATE_LIMIT_CLEANUP_BATCH', 'cleanup batch is hard bounded'
);

insert into lws_internal.preview_rate_limit_buckets (
  namespace, key_hash, window_started_at, window_expires_at, request_count
) values (
  'preview_global',
  repeat('e', 64),
  to_timestamp(floor(extract(epoch from date_trunc('second', clock_timestamp())) / 60) * 60),
  to_timestamp(floor(extract(epoch from date_trunc('second', clock_timestamp())) / 60) * 60) + interval '60 seconds',
  10000
);
select is(
  (select allowed from public.consume_preview_rate_limit_v1('preview_global', repeat('e', 64), 60, 10000, 0)),
  false,
  'request above the highest configurable maximum is denied'
);

insert into lws_internal.preview_rate_limit_buckets (
  namespace, key_hash, window_started_at, window_expires_at, request_count
)
select
  'preview_capability',
  encode(sha256(('expired-' || value)::bytea), 'hex'),
  date_trunc('second', clock_timestamp() - interval '3 hours'),
  date_trunc('second', clock_timestamp() - interval '2 hours'),
  1
from generate_series(1, 30) as value;

create temporary table cleanup_baseline as
select count(*)::integer as expired_count
from lws_internal.preview_rate_limit_buckets
where window_expires_at < clock_timestamp() - interval '1 hour';

select public.consume_preview_rate_limit_v1('preview_global', repeat('c', 64), 60, 10, 7);
select is(
  (select count(*)::integer from lws_internal.preview_rate_limit_buckets
   where window_expires_at < clock_timestamp() - interval '1 hour'),
  (select expired_count - 7 from cleanup_baseline),
  'opportunistic cleanup deletes exactly the bounded batch'
);

create temporary table concurrent_key as
select encode(gen_random_bytes(32), 'hex') as key_hash;

select is(
  extensions.dblink_connect(
    'preview_rl_1',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres'
  ),
  'OK',
  'first concurrent connection opens'
);
select is(
  extensions.dblink_connect(
    'preview_rl_2',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres'
  ),
  'OK',
  'second concurrent connection opens'
);
select ok(
  extensions.dblink_send_query(
    'preview_rl_1',
    format(
      $$select * from public.consume_preview_rate_limit_v1('preview_global', %L, 60, 10, 0)$$,
      (select key_hash from concurrent_key)
    )
  ) = 1,
  'first concurrent consume starts'
);
select ok(
  extensions.dblink_send_query(
    'preview_rl_2',
    format(
      $$select * from public.consume_preview_rate_limit_v1('preview_global', %L, 60, 10, 0)$$,
      (select key_hash from concurrent_key)
    )
  ) = 1,
  'second concurrent consume starts'
);
create temporary table concurrent_results as
select * from extensions.dblink_get_result('preview_rl_1')
  as result(allowed boolean, remaining integer, reset_at timestamptz, retry_after_seconds integer)
union all
select * from extensions.dblink_get_result('preview_rl_2')
  as result(allowed boolean, remaining integer, reset_at timestamptz, retry_after_seconds integer);
select is(
  (select count(*)::integer from concurrent_results where allowed),
  2,
  'both concurrent requests receive allowed results below the limit'
);
select is(
  (select request_count from lws_internal.preview_rate_limit_buckets
   where namespace = 'preview_global'
     and key_hash = (select concurrent_key.key_hash from concurrent_key)),
  2,
  'concurrent requests atomically increment one bucket without lost updates'
);
select extensions.dblink_disconnect('preview_rl_1');
select extensions.dblink_disconnect('preview_rl_2');
do $$
declare
  cleanup_result text;
begin
  perform extensions.dblink_connect(
    'preview_rl_cleanup',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres'
  );
  select extensions.dblink_exec(
    'preview_rl_cleanup',
    format(
      'delete from lws_internal.preview_rate_limit_buckets where namespace = ''preview_global'' and key_hash = %L',
      (select key_hash from concurrent_key)
    )
  ) into cleanup_result;
  if cleanup_result <> 'DELETE 1' then
    raise exception 'CONCURRENT_FIXTURE_CLEANUP_FAILED';
  end if;
  perform extensions.dblink_disconnect('preview_rl_cleanup');
end;
$$;

select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots),
  0,
  'limiter creates no pricing snapshot'
);
select is(
  (select count(*)::integer from public.quote_request_intakes),
  0,
  'limiter creates or mutates no intake state'
);
select ok(
  has_function_privilege('service_role', 'public.update_quote_request_intake_v4(text,text,jsonb,text,timestamp with time zone,jsonb,jsonb)', 'execute'),
  'submit RPC remains available and independent from preview limiter'
);

select ok(
  not has_function_privilege('anon', 'public.inspect_preview_budget_guard_context_v1(text)', 'execute'),
  'anon cannot inspect preview context'
);
select ok(
  not has_function_privilege('authenticated', 'public.inspect_preview_budget_guard_context_v1(text)', 'execute'),
  'authenticated cannot inspect preview context'
);
select ok(
  has_function_privilege('service_role', 'public.inspect_preview_budget_guard_context_v1(text)', 'execute'),
  'service role can inspect minimal preview context'
);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  ('32d00000-0000-4000-8000-000000000001', 'Preview fixture 1', 'preview1@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Preview fixture', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('32d00000-0000-4000-8000-000000000002', 'Preview fixture 2', 'preview2@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Preview fixture', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('32d00000-0000-4000-8000-000000000003', 'Preview fixture 3', 'preview3@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Preview fixture', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('32d00000-0000-4000-8000-000000000004', 'Preview fixture 4', 'preview4@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Preview fixture', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive');

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  access_token_revoked_at, status, started_at, submitted_at, confirmation,
  created_at, updated_at
) values
  ('32d01000-0000-4000-8000-000000000001', '32d00000-0000-4000-8000-000000000001', repeat('1', 64), clock_timestamp() + interval '1 hour', null, 'invited', null, null, false, clock_timestamp(), clock_timestamp()),
  ('32d01000-0000-4000-8000-000000000002', '32d00000-0000-4000-8000-000000000002', repeat('2', 64), clock_timestamp() + interval '1 hour', null, 'submitted', clock_timestamp(), clock_timestamp(), true, clock_timestamp() - interval '1 minute', clock_timestamp()),
  ('32d01000-0000-4000-8000-000000000003', '32d00000-0000-4000-8000-000000000003', repeat('3', 64), clock_timestamp() - interval '1 hour', null, 'in_progress', clock_timestamp() - interval '90 minutes', null, false, clock_timestamp() - interval '2 hours', clock_timestamp()),
  ('32d01000-0000-4000-8000-000000000004', '32d00000-0000-4000-8000-000000000004', repeat('4', 64), clock_timestamp() + interval '1 hour', clock_timestamp(), 'in_progress', clock_timestamp(), null, false, clock_timestamp() - interval '1 minute', clock_timestamp());

select is(
  (select intake_status from public.inspect_preview_budget_guard_context_v1(repeat('1', 64))),
  'invited',
  'valid invited capability returns preview lifecycle only'
);
select is(
  (select budget_category_code from public.inspect_preview_budget_guard_context_v1(repeat('1', 64))),
  '3200_to_6000_inclusive',
  'valid capability returns authoritative budget provenance'
);
select is(
  (select intake_status from public.inspect_preview_budget_guard_context_v1(repeat('2', 64))),
  'submitted',
  'context exposes submitted lifecycle for handler rejection'
);
select is_empty(
  $$select * from public.inspect_preview_budget_guard_context_v1(repeat('3', 64))$$,
  'expired capability returns no preview context'
);
select is_empty(
  $$select * from public.inspect_preview_budget_guard_context_v1(repeat('4', 64))$$,
  'revoked capability returns no preview context'
);
select ok(
  (select row_to_json(context)::text !~ '(email|name|intake_data|pricing|snapshot|proof)'
   from public.inspect_preview_budget_guard_context_v1(repeat('1', 64)) as context),
  'preview context contains no PII, intake payload, pricing state, snapshot, or proof'
);

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(31);

select has_function(
  'lws_internal',
  'get_sdf_budget_guard_contract_v1',
  array[]::text[],
  'SDF Budget Guard contract authority exists'
);
select has_function(
  'lws_internal',
  'evaluate_sdf_budget_guard_v1',
  array['bigint', 'bigint', 'bigint', 'bigint'],
  'SDF Budget Guard evaluator exists'
);
select is(
  (select provolatile::text from pg_proc where oid = 'lws_internal.get_sdf_budget_guard_contract_v1()'::regprocedure),
  'i',
  'contract authority is immutable'
);
select is(
  (select provolatile::text from pg_proc where oid = 'lws_internal.evaluate_sdf_budget_guard_v1(bigint,bigint,bigint,bigint)'::regprocedure),
  'i',
  'evaluator is immutable'
);
select ok(
  not has_function_privilege('anon', 'lws_internal.get_sdf_budget_guard_contract_v1()', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.get_sdf_budget_guard_contract_v1()', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.get_sdf_budget_guard_contract_v1()', 'execute')
  and not has_function_privilege('anon', 'lws_internal.evaluate_sdf_budget_guard_v1(bigint,bigint,bigint,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.evaluate_sdf_budget_guard_v1(bigint,bigint,bigint,bigint)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.evaluate_sdf_budget_guard_v1(bigint,bigint,bigint,bigint)', 'execute'),
  'contract and evaluator are private'
);
select is(
  lws_internal.get_sdf_budget_guard_contract_v1(),
  '{
    "start":{"package":"start","setup_price":2850,"monthly_price":175,"max_flows":1,"max_document_types":2,"max_pages_per_month":500,"max_users":3},
    "groei":{"package":"groei","setup_price":5700,"monthly_price":299,"max_flows":3,"max_document_types":5,"max_pages_per_month":2500,"max_users":10},
    "pro":{"package":"pro","setup_price":7500,"monthly_price":449,"max_flows":6,"max_document_types":10,"max_pages_per_month":7500,"max_users":25}
  }'::jsonb,
  'contract authority contains the exact frozen package prices and limits'
);

select is(lws_internal.evaluate_sdf_budget_guard_v1(1, 2, 500, 3)->>'package', 'start', 'START exact limits select START');
select is(lws_internal.evaluate_sdf_budget_guard_v1(2, 2, 500, 3)->>'package', 'groei', 'START plus one flow selects GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v1(1, 3, 500, 3)->>'package', 'groei', 'START plus one document type selects GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v1(1, 2, 501, 3)->>'package', 'groei', 'START plus one page selects GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v1(1, 2, 500, 4)->>'package', 'groei', 'START plus one user selects GROEI');

select is(lws_internal.evaluate_sdf_budget_guard_v1(3, 5, 2500, 10)->>'package', 'groei', 'GROEI exact limits select GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v1(4, 5, 2500, 10)->>'package', 'pro', 'GROEI plus one flow selects PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v1(3, 6, 2500, 10)->>'package', 'pro', 'GROEI plus one document type selects PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v1(3, 5, 2501, 10)->>'package', 'pro', 'GROEI plus one page selects PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v1(3, 5, 2500, 11)->>'package', 'pro', 'GROEI plus one user selects PRO');

select is(lws_internal.evaluate_sdf_budget_guard_v1(6, 10, 7500, 25)->>'package', 'pro', 'PRO exact limits select PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v1(7, 10, 7500, 25)->>'package', 'maatwerk', 'PRO plus one flow selects MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v1(6, 11, 7500, 25)->>'package', 'maatwerk', 'PRO plus one document type selects MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v1(6, 10, 7501, 25)->>'package', 'maatwerk', 'PRO plus one page selects MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v1(6, 10, 7500, 26)->>'package', 'maatwerk', 'PRO plus one user selects MAATWERK');

select is(lws_internal.evaluate_sdf_budget_guard_v1(1, 2, 7000, 3)->>'package', 'pro', 'one higher mixed dimension selects the required highest package');
select is(
  lws_internal.evaluate_sdf_budget_guard_v1(6, 10, 7500, 25),
  lws_internal.evaluate_sdf_budget_guard_v1(6, 10, 7500, 25),
  'same normalized capacities produce a deterministic result'
);
select is(
  lws_internal.evaluate_sdf_budget_guard_v1(1, 2, 500, 3),
  '{"package":"start","setup_price":2850,"monthly_price":175,"flows":1,"document_types":2,"pages_per_month":500,"users":3,"classification_reason":"WITHIN_START_LIMITS"}'::jsonb,
  'START result contains authoritative prices, normalized inputs and reason'
);
select is(
  lws_internal.evaluate_sdf_budget_guard_v1(3, 5, 2500, 10)->>'classification_reason',
  'WITHIN_GROEI_LIMITS',
  'GROEI result has a controlled classification reason'
);
select is(
  lws_internal.evaluate_sdf_budget_guard_v1(6, 10, 7500, 25)->>'classification_reason',
  'WITHIN_PRO_LIMITS',
  'PRO result has a controlled classification reason'
);
select is(
  lws_internal.evaluate_sdf_budget_guard_v1(7, 10, 7500, 25),
  '{"package":"maatwerk","setup_price":null,"monthly_price":null,"flows":7,"document_types":10,"pages_per_month":7500,"users":25,"classification_reason":"ABOVE_PRO_LIMITS"}'::jsonb,
  'MAATWERK result has no invented fixed price'
);

select throws_ok(
  $$select lws_internal.evaluate_sdf_budget_guard_v1(null, 2, 500, 3)$$,
  '22023',
  'INVALID_SDF_BUDGET_GUARD_CAPACITY',
  'missing authoritative capacity fails closed'
);
select throws_ok(
  $$select lws_internal.evaluate_sdf_budget_guard_v1(0, 2, 500, 3)$$,
  '22023',
  'INVALID_SDF_BUDGET_GUARD_CAPACITY',
  'zero capacity fails closed'
);
select throws_ok(
  $$select lws_internal.evaluate_sdf_budget_guard_v1(-1, 2, 500, 3)$$,
  '22023',
  'INVALID_SDF_BUDGET_GUARD_CAPACITY',
  'negative capacity fails closed'
);
select is(
  pg_get_function_arguments('lws_internal.evaluate_sdf_budget_guard_v1(bigint,bigint,bigint,bigint)'::regprocedure),
  'p_flows bigint, p_document_types bigint, p_pages_per_month bigint, p_users bigint',
  'client package direction and client prices are not evaluator inputs'
);

select * from finish();
rollback;
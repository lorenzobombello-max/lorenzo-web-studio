begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(6);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values (
  '14120000-0000-4000-8000-000000000001',
  'Contract v2', 'contract-v2@example.test', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible', 'Contract v2 fixture.',
  true, 'approved'
);

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at,
  status, confirmation
) values (
  '14120000-0000-4000-8000-000000000001',
  repeat('1', 64), clock_timestamp() + interval '1 day', 'invited', false
);

select lives_ok(
  $$update public.quote_request_intakes
    set page_scope_details = '{"jobs":"dynamic","jobs_application":"upload"}'::jsonb
    where quote_request_id = '14120000-0000-4000-8000-000000000001'$$,
  'contract v2 accepts closed vacancy evidence'
);

select lives_ok(
  $$update public.quote_request_intakes
    set shop_required = true,
        shop_details = '{
          "approx_product_count":15,
          "categories":true,
          "online_payments":true,
          "shipping":true,
          "pickup":true,
          "pickup_scope":"scheduled",
          "existing_catalog":false,
          "complex_product_count":0,
          "payment_provider_count":1,
          "shipping_scope":"standard",
          "customer_accounts":false,
          "catalog_import":false,
          "erp_api":false
        }'::jsonb
    where quote_request_id = '14120000-0000-4000-8000-000000000001'$$,
  'contract v2 accepts coherent pickup evidence'
);

select throws_ok(
  $$update public.quote_request_intakes
    set shop_details = shop_details || '{"pickup":false,"pickup_scope":"simple"}'::jsonb
    where quote_request_id = '14120000-0000-4000-8000-000000000001'$$,
  '22023',
  'INVALID_PHASE_D_INTAKE_EVIDENCE',
  'contract v2 rejects incoherent pickup evidence'
);

select throws_ok(
  $$update public.quote_request_intakes
    set page_scope_details = '{"jobs":"normal","jobs_application":"invented"}'::jsonb
    where quote_request_id = '14120000-0000-4000-8000-000000000001'$$,
  '22023',
  'INVALID_PHASE_D_INTAKE_EVIDENCE',
  'contract v2 rejects unknown vacancy evidence'
);

select ok(
  pg_get_functiondef(
    'public.is_strict_pricing_snapshot_v3(smallint,text,text,jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure
  ) like '%2026-08-12-v1%2026-08-13-v2%',
  'strict v3 accepts historical and current catalog config versions'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.is_valid_phase_d_intake_evidence(public.quote_request_intakes)',
    'execute'
  ),
  'service role can execute the extended evidence validator'
);

select * from finish();
rollback;

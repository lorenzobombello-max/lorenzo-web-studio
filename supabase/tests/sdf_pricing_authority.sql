begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(9);

select has_function('public','get_sdf_package_pricing_authority_v1',array['text'],'SDF package pricing authority exists');
select is(
  (select provolatile::text from pg_proc where oid='public.get_sdf_package_pricing_authority_v1(text)'::regprocedure),
  'i',
  'SDF package pricing authority is immutable'
);
select ok(
  not has_function_privilege('anon','public.get_sdf_package_pricing_authority_v1(text)','execute')
  and not has_function_privilege('authenticated','public.get_sdf_package_pricing_authority_v1(text)','execute')
  and not has_function_privilege('service_role','public.get_sdf_package_pricing_authority_v1(text)','execute'),
  'SDF package pricing authority is private'
);
select is(
  jsonb_build_array(
    public.get_sdf_package_pricing_authority_v1('start')->'implementation'->>'amount_minor',
    public.get_sdf_package_pricing_authority_v1('start')->'implementation'->>'price_mode',
    public.get_sdf_package_pricing_authority_v1('start')->'recurring'->>'amount_minor',
    public.get_sdf_package_pricing_authority_v1('start')->'recurring'->>'price_mode'
  ),
  '["285000", "fixed", "17500", "fixed"]'::jsonb,
  'START authority exposes fixed implementation and recurring amounts'
);
select is(
  jsonb_build_array(
    public.get_sdf_package_pricing_authority_v1('groei')->'implementation'->>'amount_minor',
    public.get_sdf_package_pricing_authority_v1('groei')->'implementation'->>'price_mode',
    public.get_sdf_package_pricing_authority_v1('groei')->'recurring'->>'amount_minor',
    public.get_sdf_package_pricing_authority_v1('groei')->'recurring'->>'price_mode'
  ),
  '["570000", "fixed", "29900", "fixed"]'::jsonb,
  'GROEI authority exposes fixed implementation and recurring amounts'
);
select is(
  jsonb_build_array(
    public.get_sdf_package_pricing_authority_v1('maatwerk')->'implementation'->>'amount_minor',
    public.get_sdf_package_pricing_authority_v1('maatwerk')->'implementation'->>'price_mode',
    public.get_sdf_package_pricing_authority_v1('maatwerk')->'recurring'->>'amount_minor',
    public.get_sdf_package_pricing_authority_v1('maatwerk')->'recurring'->>'price_mode'
  ),
  '["750000", "starting_at", "44900", "starting_at"]'::jsonb,
  'MAATWERK authority preserves starting-at semantics'
);
select is(public.get_sdf_package_pricing_authority_v1(null),null::jsonb,'missing legacy package yields no pricing authority');
select throws_ok(
  $$select public.get_sdf_package_pricing_authority_v1('onbekend')$$,
  '22023', 'INVALID_SDF_PACKAGE', 'unknown SDF package fails closed'
);
select is(
  jsonb_build_array(
    public.get_sdf_package_pricing_authority_v1('groei')->'recurring'->>'commercial_package_price',
    public.get_sdf_package_pricing_authority_v1('groei')->'recurring'->>'active_recurring_obligation',
    public.get_sdf_package_pricing_authority_v1('groei')->'recurring'->>'billing_period'
  ),
  '["true", "false", "month"]'::jsonb,
  'recurring authority is commercial read-only pricing, not an active obligation'
);

select * from finish();
rollback;
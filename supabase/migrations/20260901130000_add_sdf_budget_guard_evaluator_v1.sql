create function lws_internal.get_sdf_budget_guard_contract_v1()
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'start', jsonb_build_object(
      'package', 'start',
      'setup_price', 2850,
      'monthly_price', 175,
      'max_flows', 1,
      'max_document_types', 2,
      'max_pages_per_month', 500,
      'max_users', 3
    ),
    'groei', jsonb_build_object(
      'package', 'groei',
      'setup_price', 5700,
      'monthly_price', 299,
      'max_flows', 3,
      'max_document_types', 5,
      'max_pages_per_month', 2500,
      'max_users', 10
    ),
    'pro', jsonb_build_object(
      'package', 'pro',
      'setup_price', 7500,
      'monthly_price', 449,
      'max_flows', 6,
      'max_document_types', 10,
      'max_pages_per_month', 7500,
      'max_users', 25
    )
  )
$$;

create function lws_internal.evaluate_sdf_budget_guard_v1(
  p_flows bigint,
  p_document_types bigint,
  p_pages_per_month bigint,
  p_users bigint
)
returns jsonb
language plpgsql
immutable
set search_path = lws_internal, pg_catalog
as $$
declare
  v_contract jsonb := lws_internal.get_sdf_budget_guard_contract_v1();
  v_package text;
  v_reason text;
  v_package_contract jsonb;
begin
  if p_flows is null
     or p_document_types is null
     or p_pages_per_month is null
     or p_users is null
     or p_flows < 1
     or p_document_types < 1
     or p_pages_per_month < 1
     or p_users < 1 then
    raise exception using
      errcode = '22023',
      message = 'INVALID_SDF_BUDGET_GUARD_CAPACITY';
  end if;

  if p_flows <= (v_contract #>> '{start,max_flows}')::bigint
     and p_document_types <= (v_contract #>> '{start,max_document_types}')::bigint
     and p_pages_per_month <= (v_contract #>> '{start,max_pages_per_month}')::bigint
     and p_users <= (v_contract #>> '{start,max_users}')::bigint then
    v_package := 'start';
    v_reason := 'WITHIN_START_LIMITS';
  elsif p_flows <= (v_contract #>> '{groei,max_flows}')::bigint
     and p_document_types <= (v_contract #>> '{groei,max_document_types}')::bigint
     and p_pages_per_month <= (v_contract #>> '{groei,max_pages_per_month}')::bigint
     and p_users <= (v_contract #>> '{groei,max_users}')::bigint then
    v_package := 'groei';
    v_reason := 'WITHIN_GROEI_LIMITS';
  elsif p_flows <= (v_contract #>> '{pro,max_flows}')::bigint
     and p_document_types <= (v_contract #>> '{pro,max_document_types}')::bigint
     and p_pages_per_month <= (v_contract #>> '{pro,max_pages_per_month}')::bigint
     and p_users <= (v_contract #>> '{pro,max_users}')::bigint then
    v_package := 'pro';
    v_reason := 'WITHIN_PRO_LIMITS';
  else
    v_package := 'maatwerk';
    v_reason := 'ABOVE_PRO_LIMITS';
  end if;

  v_package_contract := v_contract -> v_package;

  return jsonb_build_object(
    'package', v_package,
    'setup_price', v_package_contract -> 'setup_price',
    'monthly_price', v_package_contract -> 'monthly_price',
    'flows', p_flows,
    'document_types', p_document_types,
    'pages_per_month', p_pages_per_month,
    'users', p_users,
    'classification_reason', v_reason
  );
end;
$$;

revoke all on function lws_internal.get_sdf_budget_guard_contract_v1()
from public, anon, authenticated, service_role;

revoke all on function lws_internal.evaluate_sdf_budget_guard_v1(bigint, bigint, bigint, bigint)
from public, anon, authenticated, service_role;

comment on function lws_internal.get_sdf_budget_guard_contract_v1() is
  'Private immutable frozen SDF package contract for server-side Budget Guard evaluation.';

comment on function lws_internal.evaluate_sdf_budget_guard_v1(bigint, bigint, bigint, bigint) is
  'Private immutable SDF Budget Guard evaluator over explicit normalized capacities. Client package direction and prices are not inputs.';
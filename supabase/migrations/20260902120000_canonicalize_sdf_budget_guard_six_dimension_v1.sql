create or replace function lws_internal.evaluate_sdf_budget_guard_v2(
  p_flows bigint,
  p_document_types bigint,
  p_pages_per_month bigint,
  p_users bigint,
  p_complexity_level text,
  p_exceptional_scope boolean,
  p_selected_package text
)
returns jsonb
language plpgsql
immutable
set search_path = lws_internal, extensions, pg_catalog
as $$
declare
  v_contract jsonb := lws_internal.get_sdf_budget_guard_contract_v1();
  v_numeric jsonb;
  v_flow_package text;
  v_document_type_package text;
  v_page_package text;
  v_user_package text;
  v_complexity_package text;
  v_exceptional_package text;
  v_minimum_package text;
  v_minimum_rank integer;
  v_selected_rank integer;
  v_scope_facts jsonb;
  v_dimensions jsonb;
  v_reasons jsonb;
  v_fingerprint_payload jsonb;
  v_decision_fingerprint text;
  v_pricing jsonb;
begin
  if p_complexity_level is null then
    raise exception using errcode = '22004', message = 'SDF_COMPLEXITY_LEVEL_REQUIRED';
  end if;
  if p_exceptional_scope is null then
    raise exception using errcode = '22004', message = 'SDF_EXCEPTIONAL_SCOPE_REQUIRED';
  end if;
  if p_complexity_level not in ('standard','expanded','advanced') then
    raise exception using errcode = '22023', message = 'INVALID_SDF_COMPLEXITY_LEVEL';
  end if;
  if p_selected_package is null then
    raise exception using errcode = '22004', message = 'SDF_SELECTED_PACKAGE_REQUIRED';
  end if;
  v_selected_rank := lws_internal.sdf_package_rank_v1(p_selected_package);
  if v_selected_rank is null then
    raise exception using errcode = '22023', message = 'INVALID_SDF_SELECTED_PACKAGE';
  end if;

  v_numeric := lws_internal.evaluate_sdf_budget_guard_v1(
    p_flows,p_document_types,p_pages_per_month,p_users
  );
  v_flow_package := lws_internal.evaluate_sdf_budget_guard_v1(p_flows,1,1,1)->>'package';
  v_document_type_package := lws_internal.evaluate_sdf_budget_guard_v1(1,p_document_types,1,1)->>'package';
  v_page_package := lws_internal.evaluate_sdf_budget_guard_v1(1,1,p_pages_per_month,1)->>'package';
  v_user_package := lws_internal.evaluate_sdf_budget_guard_v1(1,1,1,p_users)->>'package';
  v_complexity_package := case p_complexity_level
    when 'standard' then 'start'
    when 'expanded' then 'groei'
    when 'advanced' then 'pro'
  end;
  v_exceptional_package := case when p_exceptional_scope then 'maatwerk' else 'start' end;

  v_minimum_rank := greatest(
    lws_internal.sdf_package_rank_v1(v_numeric->>'package'),
    lws_internal.sdf_package_rank_v1(v_complexity_package),
    lws_internal.sdf_package_rank_v1(v_exceptional_package)
  );
  v_minimum_package := lws_internal.sdf_package_for_rank_v1(v_minimum_rank);
  if v_selected_rank < v_minimum_rank then
    raise exception using errcode = '23514', message = 'SDF_PACKAGE_DOWNGRADE_DENIED';
  end if;

  v_scope_facts := jsonb_build_object(
    'flow_count',p_flows,
    'document_type_count',p_document_types,
    'normalized_monthly_pages',p_pages_per_month,
    'user_count',p_users,
    'complexity_level',p_complexity_level,
    'exceptional_scope',p_exceptional_scope
  );
  v_dimensions := jsonb_build_object(
    'flows',jsonb_build_object(
      'value',p_flows,'minimum_package',v_flow_package,
      'reason','FLOW_REQUIRES_' || upper(v_flow_package),
      'applicable_threshold',jsonb_build_object(
        'max',case when v_flow_package='maatwerk' then null else (v_contract#>>(array[v_flow_package,'max_flows']))::bigint end,
        'pro_max',(v_contract#>>'{pro,max_flows}')::bigint
      )
    ),
    'document_types',jsonb_build_object(
      'value',p_document_types,'minimum_package',v_document_type_package,
      'reason','DOCUMENT_TYPES_REQUIRE_' || upper(v_document_type_package),
      'applicable_threshold',jsonb_build_object(
        'max',case when v_document_type_package='maatwerk' then null else (v_contract#>>(array[v_document_type_package,'max_document_types']))::bigint end,
        'pro_max',(v_contract#>>'{pro,max_document_types}')::bigint
      )
    ),
    'monthly_pages',jsonb_build_object(
      'value',p_pages_per_month,'minimum_package',v_page_package,
      'reason','MONTHLY_PAGES_REQUIRE_' || upper(v_page_package),
      'applicable_threshold',jsonb_build_object(
        'max',case when v_page_package='maatwerk' then null else (v_contract#>>(array[v_page_package,'max_pages_per_month']))::bigint end,
        'pro_max',(v_contract#>>'{pro,max_pages_per_month}')::bigint
      )
    ),
    'users',jsonb_build_object(
      'value',p_users,'minimum_package',v_user_package,
      'reason','USERS_REQUIRE_' || upper(v_user_package),
      'applicable_threshold',jsonb_build_object(
        'max',case when v_user_package='maatwerk' then null else (v_contract#>>(array[v_user_package,'max_users']))::bigint end,
        'pro_max',(v_contract#>>'{pro,max_users}')::bigint
      )
    ),
    'complexity',jsonb_build_object(
      'value',p_complexity_level,'minimum_package',v_complexity_package,
      'reason','COMPLEXITY_REQUIRES_' || upper(v_complexity_package),
      'applicable_threshold',jsonb_build_object('max_level',p_complexity_level)
    ),
    'exceptional_scope',jsonb_build_object(
      'value',p_exceptional_scope,'minimum_package',v_exceptional_package,
      'reason',case when p_exceptional_scope then 'EXCEPTIONAL_SCOPE_REQUIRES_MAATWERK' else 'EXCEPTIONAL_SCOPE_CLEAR' end,
      'applicable_threshold',jsonb_build_object('required_for_standard_packages',false)
    )
  );
  v_reasons := jsonb_build_array(
    jsonb_build_object('dimension','flows','value',p_flows,'required_package',v_flow_package,'reason',v_dimensions#>>'{flows,reason}'),
    jsonb_build_object('dimension','document_types','value',p_document_types,'required_package',v_document_type_package,'reason',v_dimensions#>>'{document_types,reason}'),
    jsonb_build_object('dimension','normalized_monthly_pages','value',p_pages_per_month,'required_package',v_page_package,'reason',v_dimensions#>>'{monthly_pages,reason}'),
    jsonb_build_object('dimension','users','value',p_users,'required_package',v_user_package,'reason',v_dimensions#>>'{users,reason}'),
    jsonb_build_object('dimension','complexity_level','value',p_complexity_level,'required_package',v_complexity_package,'reason',v_dimensions#>>'{complexity,reason}'),
    jsonb_build_object('dimension','exceptional_scope','value',p_exceptional_scope,'required_package',v_exceptional_package,'reason',v_dimensions#>>'{exceptional_scope,reason}')
  );
  v_fingerprint_payload := jsonb_build_object(
    'decision_contract_version',1,
    'scope_facts',v_scope_facts,
    'dimensions',v_dimensions,
    'minimum_package',v_minimum_package,
    'selected_package',p_selected_package,
    'maatwerk_required',v_minimum_package='maatwerk',
    'reasons',v_reasons
  );
  v_decision_fingerprint := encode(
    extensions.digest(convert_to(v_fingerprint_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_pricing := lws_internal.get_sdf_budget_guard_pricing_authority_v2(p_selected_package);

  return jsonb_build_object(
    'authority_version',2,
    'decision_contract_version',1,
    'scope_facts',v_scope_facts,
    'minimum_package',v_minimum_package,
    'selected_package',p_selected_package,
    'maatwerk_required',v_minimum_package='maatwerk',
    'dimensions',v_dimensions,
    'reasons',v_reasons,
    'decision_fingerprint',v_decision_fingerprint,
    'pricing',v_pricing
  );
end;
$$;

alter table public.sdf_scope_classification_authorities
  add constraint sdf_scope_classification_budget_guard_decision_valid check (
    evaluation_snapshot->>'authority_version'='2'
    and evaluation_snapshot->>'decision_contract_version'='1'
    and evaluation_snapshot->>'minimum_package'=minimum_package
    and evaluation_snapshot->>'selected_package'=selected_package
    and evaluation_snapshot#>>'{scope_facts,complexity_level}'=complexity_level
    and (evaluation_snapshot#>>'{scope_facts,exceptional_scope}')::boolean=exceptional_scope
    and evaluation_snapshot->>'decision_fingerprint' ~ '^[0-9a-f]{64}$'
    and jsonb_array_length(evaluation_snapshot->'reasons')=6
  );

create or replace function lws_internal.get_sdf_preparation_classification_binding_v1(
  p_preparation_authority_id uuid,
  p_submission_sha256 text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_preparation public.sdf_quotation_preparation_authorities%rowtype;
  v_classification public.sdf_scope_classification_authorities%rowtype;
begin
  select * into v_preparation
  from public.sdf_quotation_preparation_authorities
  where authority_id = p_preparation_authority_id;
  if not found or v_preparation.classification_authority_id is null then
    raise exception using errcode = '55000', message = 'SDF_SCOPE_CLASSIFICATION_REQUIRED';
  end if;
  select * into v_classification
  from public.sdf_scope_classification_authorities
  where classification_authority_id = v_preparation.classification_authority_id
    and quote_request_id = v_preparation.quote_request_id
    and qualification_intake_id = v_preparation.qualification_intake_id
    and rtrim(submission_sha256) = p_submission_sha256
    and rtrim(classification_sha256) = rtrim(v_preparation.classification_sha256);
  if not found
     or v_classification.selected_package <> v_preparation.sdf_package
     or v_classification.evaluation_snapshot->>'decision_fingerprint' !~ '^[0-9a-f]{64}$'
     or rtrim(v_classification.classification_sha256) <>
        encode(extensions.digest(convert_to(v_classification.canonical_payload::text,'UTF8'),'sha256'),'hex') then
    raise exception using errcode = '55000', message = 'SDF_SCOPE_CLASSIFICATION_STALE';
  end if;
  return jsonb_build_object(
    'classification_authority_id',v_classification.classification_authority_id,
    'classification_sha256',rtrim(v_classification.classification_sha256),
    'budget_guard_decision_fingerprint',v_classification.evaluation_snapshot->>'decision_fingerprint',
    'scope_facts',v_classification.evaluation_snapshot->'scope_facts',
    'minimum_package',v_classification.minimum_package,
    'selected_package',v_classification.selected_package,
    'complexity_level',v_classification.complexity_level,
    'exceptional_scope',v_classification.exceptional_scope,
    'pricing',lws_internal.get_sdf_budget_guard_pricing_authority_v2(v_classification.selected_package)
  );
end;
$$;

revoke all on function lws_internal.evaluate_sdf_budget_guard_v2(bigint,bigint,bigint,bigint,text,boolean,text)
from public,anon,authenticated,service_role;
revoke all on function lws_internal.get_sdf_preparation_classification_binding_v1(uuid,text)
from public,anon,authenticated,service_role;

comment on function lws_internal.evaluate_sdf_budget_guard_v2(bigint,bigint,bigint,bigint,text,boolean,text) is
  'Canonical private immutable SDF six-dimension package decision with ordered provenance, highest-dimension-wins minimum, downgrade guard, and timestamp-free SHA-256 fingerprint.';
comment on constraint sdf_scope_classification_budget_guard_decision_valid on public.sdf_scope_classification_authorities is
  'Binds every immutable SDF classification authority to one canonical six-dimension Budget Guard decision and fingerprint.';

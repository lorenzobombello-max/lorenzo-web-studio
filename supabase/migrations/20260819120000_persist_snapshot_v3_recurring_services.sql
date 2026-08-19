alter table public.quote_request_pricing_snapshots
  add column recurring_services jsonb;

alter table public.quote_request_pricing_snapshots
  drop constraint quote_request_pricing_snapshots_config_version_valid;

alter table public.quote_request_pricing_snapshots
  add constraint quote_request_pricing_snapshots_config_version_valid
  check (
    config_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'
    or config_version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}-v[1-9][0-9]*$'
  );

create function public.is_valid_pricing_recurring_services_v1(p_value jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_value is null or (
    jsonb_typeof(p_value) = 'array'
    and jsonb_array_length(p_value) between 1 and 2
    and (
      select count(*) = jsonb_array_length(p_value)
      from jsonb_array_elements(p_value) as service(value)
      where jsonb_typeof(service.value) = 'object'
        and service.value ?& array['productId', 'amountMinor', 'unit']
        and (select count(*) from jsonb_object_keys(service.value)) = 3
        and service.value->>'unit' = 'month'
        and (
          (service.value->>'productId' = 'care'
            and service.value->'amountMinor' = '4900'::jsonb)
          or (service.value->>'productId' = 'care_plus'
            and service.value->'amountMinor' = '9900'::jsonb)
        )
    )
    and (
      select count(distinct service.value->>'productId') = jsonb_array_length(p_value)
      from jsonb_array_elements(p_value) as service(value)
    )
  )
$$;

alter table public.quote_request_pricing_snapshots
  add constraint quote_request_pricing_snapshots_recurring_services_valid
  check (public.is_valid_pricing_recurring_services_v1(recurring_services));

do $$
declare
  v_signature constant text :=
    'public.is_strict_pricing_snapshot_v3(smallint,text,text,jsonb,jsonb,jsonb,jsonb,jsonb)';
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(v_signature::regprocedure) into v_definition;

  v_updated := replace(
    v_definition,
    'p_config_version not in (''2.0.0'', ''2026-08-12-v1'', ''2026-08-13-v2'')',
    'p_config_version not in (''2.0.0'', ''2026-08-12-v1'', ''2026-08-13-v2'', ''2026-08-16-v3'')'
  );
  if v_updated = v_definition then
    raise exception 'STRICT_V3_VERSION_ALLOWLIST_FRAGMENT_NOT_FOUND';
  end if;
  v_definition := v_updated;

  v_updated := replace(
    v_definition,
    'p_config_version not in (''2026-08-12-v1'', ''2026-08-13-v2'')',
    'p_config_version not in (''2026-08-12-v1'', ''2026-08-13-v2'', ''2026-08-16-v3'')'
  );
  if v_updated = v_definition then
    raise exception 'STRICT_V3_PROFESSIONAL_VERSION_FRAGMENT_NOT_FOUND';
  end if;
  v_definition := v_updated;

  v_updated := replace(
    v_definition,
    'p_config_version in (''2026-08-12-v1'', ''2026-08-13-v2'')',
    'p_config_version in (''2026-08-12-v1'', ''2026-08-13-v2'', ''2026-08-16-v3'')'
  );
  if v_updated = v_definition then
    raise exception 'STRICT_V3_EXTRA_PAGE_VERSION_FRAGMENT_NOT_FOUND';
  end if;

  execute v_updated;
end;
$$;

create or replace function public.update_quote_request_intake_v5(
  p_access_token_hash text,
  p_action text,
  p_data jsonb,
  p_admin_access_token_hash text default null,
  p_admin_access_token_expires_at timestamptz default null,
  p_budget_guard_snapshot jsonb default null,
  p_pricing_snapshot_integrity jsonb default null
)
returns table (
  outcome text, intake_status text, started_at timestamptz,
  submitted_at timestamptz, updated_at timestamptz,
  notification_job_id uuid, notification_job_status text, pricing_snapshot jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result record;
  v_intake public.quote_request_intakes%rowtype;
  v_request public.quote_requests%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_snapshot_version smallint;
  v_package_id text;
  v_budget_evaluation jsonb;
  v_budget_label text;
  v_budget_scheme text;
  v_budget_code text;
  v_legacy_data jsonb;
  v_recurring_services jsonb;
  v_evidence_keys constant text[] := array[
    'primary_language', 'additional_languages', 'page_scope_details',
    'quote_form_details', 'multilingual_details', 'download_details',
    'content_media_details', 'newsletter_details', 'hosting_maintenance_details',
    'deadline_details', 'seo_details', 'budget_update_category_scheme',
    'budget_update_category_code', 'selected_package_definition_id'
  ];
begin
  if p_budget_guard_snapshot is null or jsonb_typeof(p_budget_guard_snapshot) <> 'object'
     or (p_budget_guard_snapshot->>'snapshotContractVersion') !~ '^\d+$' then
    raise exception using errcode = '22023', message = 'INVALID_PRICING_SNAPSHOT';
  end if;
  v_snapshot_version := (p_budget_guard_snapshot->>'snapshotContractVersion')::smallint;
  if v_snapshot_version = 2 then
    return query select * from public.update_quote_request_intake_v4(
      p_access_token_hash, p_action, p_data, p_admin_access_token_hash,
      p_admin_access_token_expires_at, p_budget_guard_snapshot,
      p_pricing_snapshot_integrity
    );
    return;
  end if;
  v_recurring_services := case when p_budget_guard_snapshot ? 'recurringServices'
    then p_budget_guard_snapshot->'recurringServices' else null end;
  if p_action <> 'submit' or v_snapshot_version <> 3
     or p_data is null or jsonb_typeof(p_data) <> 'object'
     or jsonb_typeof(p_pricing_snapshot_integrity) <> 'object'
     or p_pricing_snapshot_integrity->>'algorithmVersion' <> 'hmac-sha256-v1'
     or p_pricing_snapshot_integrity->>'keyId' !~ '^v[1-9][0-9]*$'
     or p_pricing_snapshot_integrity->>'mac' !~ '^[0-9a-f]{64}$'
     or not (p_budget_guard_snapshot ?& array[
       'snapshotContractVersion', 'pricingConfigVersion', 'pricingConfigHash',
       'normalizedScope', 'calculation', 'packageAdvice', 'budgetEvaluation',
       'packageDefinition'
     ])
     or (select count(*) from jsonb_object_keys(p_budget_guard_snapshot)) <>
       (case when v_recurring_services is null then 8 else 9 end)
     or not public.is_valid_pricing_recurring_services_v1(v_recurring_services)
     or not public.is_strict_pricing_snapshot_v3(
       3::smallint,
       p_budget_guard_snapshot->>'pricingConfigVersion',
       p_budget_guard_snapshot->>'pricingConfigHash',
       p_budget_guard_snapshot->'normalizedScope',
       p_budget_guard_snapshot->'calculation',
       p_budget_guard_snapshot->'packageAdvice',
       p_budget_guard_snapshot->'budgetEvaluation',
       p_budget_guard_snapshot->'packageDefinition'
     ) then
    raise exception using errcode = '22023', message = 'INVALID_PRICING_SNAPSHOT_V3';
  end if;

  v_package_id := p_budget_guard_snapshot->'packageDefinition'->>'id';
  if jsonb_typeof(p_data->'selected_package_definition_id') <> 'string'
     or p_data->>'selected_package_definition_id' is distinct from v_package_id then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_PACKAGE_MISMATCH';
  end if;
  v_legacy_data := p_data - v_evidence_keys;
  select * into v_result from public.update_quote_request_intake(
    p_access_token_hash, p_action, v_legacy_data,
    p_admin_access_token_hash, p_admin_access_token_expires_at
  );

  if v_result.outcome <> 'submitted' then
    select snapshot.* into v_snapshot
    from public.quote_request_pricing_snapshots as snapshot
    inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.access_token_hash = p_access_token_hash;
    return query select v_result.outcome, v_result.intake_status,
      v_result.started_at, v_result.submitted_at, v_result.updated_at,
      v_result.notification_job_id, v_result.notification_job_status,
      case when v_snapshot.id is null then null else jsonb_build_object(
        'snapshotContractVersion', v_snapshot.snapshot_contract_version,
        'pricingConfigVersion', v_snapshot.config_version,
        'pricingConfigHash', v_snapshot.config_hash,
        'normalizedScope', v_snapshot.normalized_evidence,
        'calculation', v_snapshot.calculation,
        'packageAdvice', v_snapshot.package_advice,
        'budgetEvaluation', v_snapshot.budget_evaluation,
        'packageDefinition', v_snapshot.package_definition,
        'createdAt', v_snapshot.created_at
      ) || case when v_snapshot.recurring_services is null then '{}'::jsonb
        else jsonb_build_object('recurringServices', v_snapshot.recurring_services) end end;
    return;
  end if;

  select * into v_intake from public.quote_request_intakes
  where access_token_hash = p_access_token_hash for update;
  update public.quote_request_intakes set
    primary_language = case when p_data ? 'primary_language' then nullif(btrim(p_data->>'primary_language'), '') else v_intake.primary_language end,
    additional_languages = case when not (p_data ? 'additional_languages') then v_intake.additional_languages when p_data->'additional_languages' = 'null'::jsonb then null else array(select jsonb_array_elements_text(p_data->'additional_languages')) end,
    page_scope_details = case when p_data ? 'page_scope_details' then nullif(p_data->'page_scope_details', 'null'::jsonb) else v_intake.page_scope_details end,
    quote_form_details = case when p_data ? 'quote_form_details' then nullif(p_data->'quote_form_details', 'null'::jsonb) else v_intake.quote_form_details end,
    multilingual_details = case when p_data ? 'multilingual_details' then nullif(p_data->'multilingual_details', 'null'::jsonb) else v_intake.multilingual_details end,
    download_details = case when p_data ? 'download_details' then nullif(p_data->'download_details', 'null'::jsonb) else v_intake.download_details end,
    content_media_details = case when p_data ? 'content_media_details' then nullif(p_data->'content_media_details', 'null'::jsonb) else v_intake.content_media_details end,
    newsletter_details = case when p_data ? 'newsletter_details' then nullif(p_data->'newsletter_details', 'null'::jsonb) else v_intake.newsletter_details end,
    hosting_maintenance_details = case when p_data ? 'hosting_maintenance_details' then nullif(p_data->'hosting_maintenance_details', 'null'::jsonb) else v_intake.hosting_maintenance_details end,
    deadline_details = case when p_data ? 'deadline_details' then nullif(p_data->'deadline_details', 'null'::jsonb) else v_intake.deadline_details end,
    seo_details = case when p_data ? 'seo_details' then nullif(p_data->'seo_details', 'null'::jsonb) else v_intake.seo_details end,
    budget_update_category_scheme = case when p_data ? 'budget_update_category_scheme' then nullif(p_data->>'budget_update_category_scheme', '') else v_intake.budget_update_category_scheme end,
    budget_update_category_code = case when p_data ? 'budget_update_category_code' then nullif(p_data->>'budget_update_category_code', '') else v_intake.budget_update_category_code end,
    selected_package_definition_id = v_package_id
  where id = v_intake.id returning * into v_intake;

  select * into v_request from public.quote_requests where id = v_intake.quote_request_id;
  if v_intake.budget_update_category is not null then
    v_budget_label := v_intake.budget_update_category;
    v_budget_scheme := v_intake.budget_update_category_scheme;
    v_budget_code := v_intake.budget_update_category_code;
  else
    v_budget_label := v_request.budget;
    v_budget_scheme := v_request.budget_category_scheme;
    v_budget_code := v_request.budget_category_code;
  end if;
  v_budget_evaluation := p_budget_guard_snapshot->'budgetEvaluation';
  if not public.is_valid_pricing_budget_evaluation_v2(v_budget_evaluation)
     or v_budget_evaluation->>'originalLabel' is distinct from v_budget_label
     or (
       v_budget_evaluation->>'evidenceProvenance' in ('budget_guard_v1', 'budget_guard_v2')
       and (
         v_budget_scheme is distinct from v_budget_evaluation->>'evidenceProvenance'
         or v_budget_code is null
         or v_budget_evaluation->>'categoryScheme' is distinct from v_budget_scheme
         or v_budget_evaluation->>'categoryCode' is distinct from v_budget_code
       )
     )
     or (
       v_budget_evaluation->>'evidenceProvenance' = 'legacy_label'
       and (
         v_budget_scheme is not null or v_budget_code is not null
         or v_budget_evaluation->'categoryScheme' <> 'null'::jsonb
         or v_budget_evaluation->'categoryCode' <> 'null'::jsonb
       )
     ) then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_BUDGET_MISMATCH';
  end if;

  insert into public.quote_request_pricing_snapshots (
    intake_id, snapshot_contract_version, config_version, config_hash,
    normalized_evidence, calculation, package_advice, budget_evaluation,
    package_definition, recurring_services
  ) values (
    v_intake.id, 3, p_budget_guard_snapshot->>'pricingConfigVersion',
    p_budget_guard_snapshot->>'pricingConfigHash',
    p_budget_guard_snapshot->'normalizedScope', p_budget_guard_snapshot->'calculation',
    p_budget_guard_snapshot->'packageAdvice', p_budget_guard_snapshot->'budgetEvaluation',
    p_budget_guard_snapshot->'packageDefinition', v_recurring_services
  ) returning * into v_snapshot;

  insert into public.quote_request_pricing_snapshot_integrity (
    snapshot_id, algorithm_version, key_id, mac
  ) values (
    v_snapshot.id, p_pricing_snapshot_integrity->>'algorithmVersion',
    p_pricing_snapshot_integrity->>'keyId', p_pricing_snapshot_integrity->>'mac'
  );

  return query select v_result.outcome, v_result.intake_status,
    v_intake.started_at, v_intake.submitted_at, v_intake.updated_at,
    v_result.notification_job_id, v_result.notification_job_status,
    jsonb_build_object(
      'snapshotContractVersion', 3,
      'pricingConfigVersion', v_snapshot.config_version,
      'pricingConfigHash', v_snapshot.config_hash,
      'normalizedScope', v_snapshot.normalized_evidence,
      'calculation', v_snapshot.calculation,
      'packageAdvice', v_snapshot.package_advice,
      'budgetEvaluation', v_snapshot.budget_evaluation,
      'packageDefinition', v_snapshot.package_definition,
      'createdAt', v_snapshot.created_at
    ) || case when v_snapshot.recurring_services is null then '{}'::jsonb
      else jsonb_build_object('recurringServices', v_snapshot.recurring_services) end;
end;
$$;

create or replace function public.inspect_quote_request_intake_details_v4(p_access_token_hash text)
returns table (
  intake_id uuid, intake_status text, quote_request_created_at timestamptz,
  name text, company text, email text, phone text, website_type text,
  budget text, timing text, description text, started_at timestamptz,
  submitted_at timestamptz, reviewed_at timestamptz, intake_data jsonb,
  pricing_snapshot jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select legacy.intake_id, legacy.intake_status, legacy.quote_request_created_at,
    legacy.name, legacy.company, legacy.email, legacy.phone, legacy.website_type,
    legacy.budget, legacy.timing, legacy.description, legacy.started_at,
    legacy.submitted_at, legacy.reviewed_at,
    legacy.intake_data || jsonb_build_object(
      'primary_language', intake.primary_language,
      'additional_languages', intake.additional_languages,
      'page_scope_details', intake.page_scope_details,
      'quote_form_details', intake.quote_form_details,
      'multilingual_details', intake.multilingual_details,
      'download_details', intake.download_details,
      'content_media_details', intake.content_media_details,
      'newsletter_details', intake.newsletter_details,
      'hosting_maintenance_details', intake.hosting_maintenance_details,
      'deadline_details', intake.deadline_details,
      'seo_details', intake.seo_details,
      'budget_update_category_scheme', intake.budget_update_category_scheme,
      'budget_update_category_code', intake.budget_update_category_code,
      'selected_package_definition_id', intake.selected_package_definition_id
    ),
    case when legacy.pricing_snapshot is null then null else
      legacy.pricing_snapshot || jsonb_build_object(
        'packageDefinition', snapshot.package_definition
      ) || case when snapshot.recurring_services is null then '{}'::jsonb
        else jsonb_build_object('recurringServices', snapshot.recurring_services) end
    end
  from public.inspect_quote_request_intake_details_v3(p_access_token_hash) as legacy
  join public.quote_request_intakes as intake on intake.id = legacy.intake_id
  left join public.quote_request_pricing_snapshots as snapshot on snapshot.intake_id = legacy.intake_id
$$;

create or replace function public.inspect_customer_pricing_read_v3(p_access_token_hash text)
returns table (
  intake_status text, snapshot_present boolean, snapshot_contract_version smallint,
  calculation_basis text, currency text, vat_basis text,
  known_minimum_minor bigint, contains_from_pricing boolean,
  manual_review_required boolean, manual_reason_count integer,
  budget_contract_version smallint, evidence_provenance text,
  budget_status text, outside_budget_wishes boolean, package_definition jsonb,
  integrity_snapshot jsonb, integrity_context text, integrity_metadata jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select intake.status::text, snapshot.id is not null and validity.ok,
    case when validity.ok then snapshot.snapshot_contract_version end,
    case when validity.ok then snapshot.calculation->>'basis' end,
    case when validity.ok then snapshot.calculation->>'currency' end,
    case when validity.ok then snapshot.calculation->>'vatBasis' end,
    case when validity.ok then (snapshot.calculation->>'knownMinimumMinor')::bigint end,
    case when validity.ok then (snapshot.calculation->>'containsFromPricing')::boolean end,
    case when validity.ok then (snapshot.calculation->>'manualReviewRequired')::boolean end,
    case when validity.ok then jsonb_array_length(snapshot.calculation->'manualReasons') end,
    case when validity.ok then (snapshot.budget_evaluation->>'contractVersion')::smallint end,
    case when validity.ok then snapshot.budget_evaluation->>'evidenceProvenance' end,
    case when validity.ok then snapshot.budget_evaluation->>'status' end,
    case when validity.ok and jsonb_typeof(snapshot.budget_evaluation->'outsideBudgetWishes') = 'boolean' then (snapshot.budget_evaluation->>'outsideBudgetWishes')::boolean end,
    case when validity.ok then snapshot.package_definition end,
    case when validity.ok then jsonb_build_object(
      'snapshotContractVersion', snapshot.snapshot_contract_version,
      'pricingConfigVersion', snapshot.config_version,
      'pricingConfigHash', snapshot.config_hash,
      'normalizedScope', snapshot.normalized_evidence,
      'calculation', snapshot.calculation,
      'packageAdvice', snapshot.package_advice,
      'budgetEvaluation', snapshot.budget_evaluation
    ) || case when snapshot.snapshot_contract_version = 3 then
      jsonb_build_object('packageDefinition', snapshot.package_definition)
      else '{}'::jsonb end || case when snapshot.recurring_services is null then
      '{}'::jsonb else jsonb_build_object('recurringServices', snapshot.recurring_services) end end,
    case when validity.ok then snapshot.intake_id::text end,
    case when validity.ok then jsonb_build_object(
      'algorithmVersion', integrity.algorithm_version,
      'keyId', integrity.key_id, 'mac', integrity.mac
    ) end
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot on snapshot.intake_id = intake.id
  left join public.quote_request_pricing_snapshot_integrity as integrity on integrity.snapshot_id = snapshot.id
  cross join lateral (select (
    case when snapshot.snapshot_contract_version = 2 then public.is_strict_pricing_snapshot_v2(
      snapshot.snapshot_contract_version, snapshot.config_version, snapshot.config_hash,
      snapshot.normalized_evidence, snapshot.calculation, snapshot.package_advice,
      snapshot.budget_evaluation
    ) when snapshot.snapshot_contract_version = 3 then public.is_strict_pricing_snapshot_v3(
      snapshot.snapshot_contract_version, snapshot.config_version, snapshot.config_hash,
      snapshot.normalized_evidence, snapshot.calculation, snapshot.package_advice,
      snapshot.budget_evaluation, snapshot.package_definition
    ) else false end
  ) and integrity.snapshot_id is not null
    and public.is_valid_pricing_recurring_services_v1(snapshot.recurring_services) as ok) as validity
  where p_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.access_token_hash = p_access_token_hash
    and intake.access_token_expires_at > clock_timestamp()
    and intake.access_token_revoked_at is null
    and intake.status in ('submitted', 'reviewed') and intake.submitted_at is not null
  limit 1
$$;

create or replace function public.inspect_admin_pricing_read_v3(p_admin_access_token_hash text)
returns table (
  intake_status text, snapshot_present boolean, snapshot_contract_version smallint,
  snapshot_created_at timestamptz, config_version text, config_hash text,
  normalized_scope jsonb, calculation jsonb, package_advice jsonb,
  budget_evaluation jsonb, package_definition jsonb, integrity_snapshot jsonb,
  integrity_context text, integrity_metadata jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select intake.status::text, snapshot.id is not null and validity.ok,
    case when validity.ok then snapshot.snapshot_contract_version end,
    case when validity.ok then snapshot.created_at end,
    case when validity.ok then snapshot.config_version end,
    case when validity.ok then snapshot.config_hash end,
    case when validity.ok then snapshot.normalized_evidence end,
    case when validity.ok then snapshot.calculation end,
    case when validity.ok then snapshot.package_advice end,
    case when validity.ok and snapshot.snapshot_contract_version in (2, 3) then snapshot.budget_evaluation end,
    case when validity.ok then snapshot.package_definition end,
    case when validity.ok and snapshot.snapshot_contract_version in (2, 3) then jsonb_build_object(
      'snapshotContractVersion', snapshot.snapshot_contract_version,
      'pricingConfigVersion', snapshot.config_version,
      'pricingConfigHash', snapshot.config_hash,
      'normalizedScope', snapshot.normalized_evidence,
      'calculation', snapshot.calculation,
      'packageAdvice', snapshot.package_advice,
      'budgetEvaluation', snapshot.budget_evaluation
    ) || case when snapshot.snapshot_contract_version = 3 then
      jsonb_build_object('packageDefinition', snapshot.package_definition)
      else '{}'::jsonb end || case when snapshot.recurring_services is null then
      '{}'::jsonb else jsonb_build_object('recurringServices', snapshot.recurring_services) end end,
    case when validity.ok and snapshot.snapshot_contract_version in (2, 3) then snapshot.intake_id::text end,
    case when validity.ok and snapshot.snapshot_contract_version in (2, 3) then jsonb_build_object(
      'algorithmVersion', integrity.algorithm_version,
      'keyId', integrity.key_id, 'mac', integrity.mac
    ) end
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot on snapshot.intake_id = intake.id
  left join public.quote_request_pricing_snapshot_integrity as integrity on integrity.snapshot_id = snapshot.id
  cross join lateral (select case
    when snapshot.snapshot_contract_version is null then true
    when snapshot.snapshot_contract_version = 2 then public.is_strict_pricing_snapshot_v2(
      snapshot.snapshot_contract_version, snapshot.config_version, snapshot.config_hash,
      snapshot.normalized_evidence, snapshot.calculation, snapshot.package_advice,
      snapshot.budget_evaluation
    ) and integrity.snapshot_id is not null
      and public.is_valid_pricing_recurring_services_v1(snapshot.recurring_services)
    when snapshot.snapshot_contract_version = 3 then public.is_strict_pricing_snapshot_v3(
      snapshot.snapshot_contract_version, snapshot.config_version, snapshot.config_hash,
      snapshot.normalized_evidence, snapshot.calculation, snapshot.package_advice,
      snapshot.budget_evaluation, snapshot.package_definition
    ) and integrity.snapshot_id is not null
      and public.is_valid_pricing_recurring_services_v1(snapshot.recurring_services)
    else false end as ok) as validity
  where p_admin_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.admin_access_token_hash = p_admin_access_token_hash
    and intake.admin_access_token_expires_at > clock_timestamp()
    and intake.admin_access_token_revoked_at is null
    and intake.status = 'submitted' and intake.submitted_at is not null
  limit 1
$$;

revoke all on function public.is_valid_pricing_recurring_services_v1(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.is_valid_pricing_recurring_services_v1(jsonb) to service_role;

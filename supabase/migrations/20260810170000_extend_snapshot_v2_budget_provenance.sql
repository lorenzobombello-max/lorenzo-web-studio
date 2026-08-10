alter table public.quote_request_pricing_snapshots
  drop constraint quote_request_pricing_snapshots_budget_evaluation_valid;

alter table public.quote_request_pricing_snapshots
  add constraint quote_request_pricing_snapshots_budget_evaluation_valid
    check (
      jsonb_typeof(budget_evaluation) = 'object'
      and (
        (
          snapshot_contract_version is null
          and not (budget_evaluation ? 'contractVersion')
          and budget_evaluation->>'categoryCode' in (
            'below_1800',
            '1800_to_below_3200',
            '3200_to_6000_inclusive',
            'above_6000'
          )
          and budget_evaluation->>'status' in (
            'below_starter_starting_price',
            'known_minimum_exceeds_category_upper_bound',
            'possibly_compatible_with_category',
            'unbounded_category_indeterminate',
            'legacy_category_not_safely_comparable',
            'manual_review_required'
          )
          and (
            not (budget_evaluation ? 'outsideBudgetWishes')
            or jsonb_typeof(budget_evaluation->'outsideBudgetWishes') = 'array'
          )
        )
        or (
          snapshot_contract_version = 2
          and budget_evaluation ?& array[
            'contractVersion', 'evidenceProvenance', 'categoryScheme',
            'categoryCode', 'originalLabel', 'status', 'outsideBudgetWishes'
          ]
          and budget_evaluation <@ jsonb_build_object(
            'contractVersion', budget_evaluation->'contractVersion',
            'evidenceProvenance', budget_evaluation->'evidenceProvenance',
            'categoryScheme', budget_evaluation->'categoryScheme',
            'categoryCode', budget_evaluation->'categoryCode',
            'originalLabel', budget_evaluation->'originalLabel',
            'status', budget_evaluation->'status',
            'outsideBudgetWishes', budget_evaluation->'outsideBudgetWishes'
          )
          and budget_evaluation->'contractVersion' = '2'::jsonb
          and jsonb_typeof(budget_evaluation->'evidenceProvenance') = 'string'
          and budget_evaluation->>'evidenceProvenance' in (
            'budget_guard_v1',
            'legacy_label',
            'missing',
            'ambiguous'
          )
          and budget_evaluation->>'status' in (
            'below_starter_starting_price',
            'known_minimum_exceeds_category_upper_bound',
            'possibly_compatible_with_category',
            'unbounded_category_indeterminate',
            'legacy_category_not_safely_comparable',
            'manual_review_required'
          )
          and jsonb_typeof(budget_evaluation->'outsideBudgetWishes') in ('boolean', 'null')
          and (
            (
              budget_evaluation->>'evidenceProvenance' = 'budget_guard_v1'
              and jsonb_typeof(budget_evaluation->'categoryScheme') = 'string'
              and budget_evaluation->>'categoryScheme' = 'budget_guard_v1'
              and jsonb_typeof(budget_evaluation->'categoryCode') = 'string'
              and budget_evaluation->>'categoryCode' in (
                'below_1800',
                '1800_to_below_3200',
                '3200_to_6000_inclusive',
                'above_6000'
              )
              and jsonb_typeof(budget_evaluation->'originalLabel') = 'string'
              and (
                (budget_evaluation->>'categoryCode' = 'below_1800'
                  and budget_evaluation->>'originalLabel' = 'Minder dan EUR 1.800')
                or (budget_evaluation->>'categoryCode' = '1800_to_below_3200'
                  and budget_evaluation->>'originalLabel' = 'EUR 1.800 tot minder dan EUR 3.200')
                or (budget_evaluation->>'categoryCode' = '3200_to_6000_inclusive'
                  and budget_evaluation->>'originalLabel' = 'EUR 3.200 t/m EUR 6.000')
                or (budget_evaluation->>'categoryCode' = 'above_6000'
                  and budget_evaluation->>'originalLabel' = 'Meer dan EUR 6.000')
              )
              and budget_evaluation->>'status' <> 'legacy_category_not_safely_comparable'
              and (
                (budget_evaluation->>'status' in (
                  'below_starter_starting_price',
                  'known_minimum_exceeds_category_upper_bound'
                ) and budget_evaluation->'outsideBudgetWishes' = 'true'::jsonb)
                or (budget_evaluation->>'status' = 'possibly_compatible_with_category'
                  and budget_evaluation->'outsideBudgetWishes' = 'false'::jsonb)
                or (budget_evaluation->>'status' in (
                  'unbounded_category_indeterminate',
                  'manual_review_required'
                ) and budget_evaluation->'outsideBudgetWishes' = 'null'::jsonb)
              )
            )
            or (
              budget_evaluation->>'evidenceProvenance' = 'legacy_label'
              and budget_evaluation->'categoryScheme' = 'null'::jsonb
              and budget_evaluation->'categoryCode' = 'null'::jsonb
              and jsonb_typeof(budget_evaluation->'originalLabel') = 'string'
              and budget_evaluation->>'originalLabel' in (
                'Tot EUR 1.500',
                'EUR 1.500 - EUR 3.000',
                'EUR 3.000 - EUR 6.000',
                'Meer dan EUR 6.000'
              )
              and budget_evaluation->>'status' in (
                'legacy_category_not_safely_comparable',
                'manual_review_required'
              )
              and budget_evaluation->'outsideBudgetWishes' = 'null'::jsonb
            )
            or (
              budget_evaluation->>'evidenceProvenance' = 'missing'
              and budget_evaluation->'categoryScheme' = 'null'::jsonb
              and budget_evaluation->'categoryCode' = 'null'::jsonb
              and budget_evaluation->'originalLabel' = 'null'::jsonb
              and budget_evaluation->>'status' = 'manual_review_required'
              and budget_evaluation->'outsideBudgetWishes' = 'null'::jsonb
            )
            or (
              budget_evaluation->>'evidenceProvenance' = 'ambiguous'
              and budget_evaluation->'categoryScheme' = 'null'::jsonb
              and budget_evaluation->'categoryCode' = 'null'::jsonb
              and jsonb_typeof(budget_evaluation->'originalLabel') = 'string'
              and btrim(budget_evaluation->>'originalLabel') <> ''
              and budget_evaluation->>'status' = 'manual_review_required'
              and budget_evaluation->'outsideBudgetWishes' = 'null'::jsonb
            )
          )
        )
      )
    );

create or replace function public.update_quote_request_intake_v3(
  p_access_token_hash text,
  p_action text,
  p_data jsonb,
  p_admin_access_token_hash text default null,
  p_admin_access_token_expires_at timestamptz default null,
  p_budget_guard_snapshot jsonb default null
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  submitted_at timestamptz,
  updated_at timestamptz,
  notification_job_id uuid,
  notification_job_status text,
  pricing_snapshot jsonb
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
  v_budget_evaluation jsonb;
  v_budget_label text;
  v_budget_scheme text;
  v_budget_code text;
  v_legacy_data jsonb;
  v_v2_keys constant text[] := array[
    'primary_language', 'additional_languages', 'page_scope_details',
    'quote_form_details', 'multilingual_details', 'download_details',
    'content_media_details', 'newsletter_details', 'hosting_maintenance_details',
    'deadline_details', 'seo_details', 'budget_update_category_scheme',
    'budget_update_category_code'
  ];
  v_snapshot_keys constant text[] := array[
    'snapshotContractVersion', 'pricingConfigVersion', 'pricingConfigHash',
    'normalizedScope', 'calculation', 'packageAdvice', 'budgetEvaluation'
  ];
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_DATA';
  end if;

  if p_action = 'save_draft' then
    return query
      select *
      from public.update_quote_request_intake_v2(
        p_access_token_hash,
        p_action,
        p_data,
        p_admin_access_token_hash,
        p_admin_access_token_expires_at,
        p_budget_guard_snapshot
      );
    return;
  end if;

  if p_action <> 'submit' then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_ACTION';
  end if;

  if p_budget_guard_snapshot is null
     or jsonb_typeof(p_budget_guard_snapshot) <> 'object' then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_REQUIRED_FOR_SUBMIT';
  end if;

  v_legacy_data := p_data - v_v2_keys;

  select *
    into v_result
    from public.update_quote_request_intake(
      p_access_token_hash,
      p_action,
      v_legacy_data,
      p_admin_access_token_hash,
      p_admin_access_token_expires_at
    );

  if v_result.outcome <> 'submitted' then
    select snapshot.*
      into v_snapshot
      from public.quote_request_pricing_snapshots as snapshot
      inner join public.quote_request_intakes as intake
        on intake.id = snapshot.intake_id
      where intake.access_token_hash = p_access_token_hash;

    return query select
      v_result.outcome,
      v_result.intake_status,
      v_result.started_at,
      v_result.submitted_at,
      v_result.updated_at,
      v_result.notification_job_id,
      v_result.notification_job_status,
      case when v_snapshot.id is null then null else jsonb_build_object(
        'snapshotContractVersion', v_snapshot.snapshot_contract_version,
        'pricingConfigVersion', v_snapshot.config_version,
        'pricingConfigHash', v_snapshot.config_hash,
        'normalizedScope', v_snapshot.normalized_evidence,
        'calculation', v_snapshot.calculation,
        'packageAdvice', v_snapshot.package_advice,
        'budgetEvaluation', v_snapshot.budget_evaluation,
        'createdAt', v_snapshot.created_at
      ) end;
    return;
  end if;

  if not (p_budget_guard_snapshot ?& v_snapshot_keys)
     or exists (
       select 1
       from jsonb_object_keys(p_budget_guard_snapshot) as supplied(key)
       where not (supplied.key = any(v_snapshot_keys))
     )
     or p_budget_guard_snapshot->'snapshotContractVersion' <> '2'::jsonb then
    raise exception using errcode = '22023', message = 'INVALID_PRICING_SNAPSHOT_V2';
  end if;

  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for update;

  update public.quote_request_intakes
  set
    primary_language = case when p_data ? 'primary_language' then nullif(btrim(p_data->>'primary_language'), '') else v_intake.primary_language end,
    additional_languages = case
      when not (p_data ? 'additional_languages') then v_intake.additional_languages
      when p_data->'additional_languages' = 'null'::jsonb then null
      else array(select jsonb_array_elements_text(p_data->'additional_languages'))
    end,
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
    budget_update_category_code = case when p_data ? 'budget_update_category_code' then nullif(p_data->>'budget_update_category_code', '') else v_intake.budget_update_category_code end
  where id = v_intake.id
  returning * into v_intake;

  select *
    into v_request
    from public.quote_requests
    where id = v_intake.quote_request_id;

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

  if jsonb_typeof(v_budget_evaluation) is distinct from 'object'
     or v_budget_evaluation->'contractVersion' <> '2'::jsonb
     or (
       v_budget_evaluation->>'evidenceProvenance' in (
         'budget_guard_v1', 'legacy_label', 'ambiguous'
       )
       and v_budget_evaluation->>'originalLabel' is distinct from v_budget_label
     )
     or (
       v_budget_evaluation->>'evidenceProvenance' = 'budget_guard_v1'
       and (
         v_budget_scheme is distinct from 'budget_guard_v1'
         or v_budget_code is null
         or v_budget_evaluation->>'categoryScheme' is distinct from v_budget_scheme
         or v_budget_evaluation->>'categoryCode' is distinct from v_budget_code
       )
     )
     or (
       v_budget_evaluation->>'evidenceProvenance' = 'legacy_label'
       and (
         v_budget_scheme is not null
         or v_budget_code is not null
         or v_budget_evaluation->'categoryScheme' <> 'null'::jsonb
         or v_budget_evaluation->'categoryCode' <> 'null'::jsonb
       )
     )
     or v_budget_evaluation->>'evidenceProvenance' not in (
       'budget_guard_v1', 'legacy_label', 'missing', 'ambiguous'
     ) then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_BUDGET_MISMATCH';
  end if;

  insert into public.quote_request_pricing_snapshots (
    intake_id,
    snapshot_contract_version,
    config_version,
    config_hash,
    normalized_evidence,
    calculation,
    package_advice,
    budget_evaluation
  ) values (
    v_intake.id,
    2,
    p_budget_guard_snapshot->>'pricingConfigVersion',
    p_budget_guard_snapshot->>'pricingConfigHash',
    p_budget_guard_snapshot->'normalizedScope',
    p_budget_guard_snapshot->'calculation',
    p_budget_guard_snapshot->'packageAdvice',
    v_budget_evaluation
  )
  returning * into v_snapshot;

  return query select
    v_result.outcome,
    v_result.intake_status,
    v_intake.started_at,
    v_intake.submitted_at,
    v_intake.updated_at,
    v_result.notification_job_id,
    v_result.notification_job_status,
    jsonb_build_object(
      'snapshotContractVersion', v_snapshot.snapshot_contract_version,
      'pricingConfigVersion', v_snapshot.config_version,
      'pricingConfigHash', v_snapshot.config_hash,
      'normalizedScope', v_snapshot.normalized_evidence,
      'calculation', v_snapshot.calculation,
      'packageAdvice', v_snapshot.package_advice,
      'budgetEvaluation', v_snapshot.budget_evaluation,
      'createdAt', v_snapshot.created_at
    );
end;
$$;

comment on function public.update_quote_request_intake_v3(text, text, jsonb, text, timestamptz, jsonb) is
  'Service-role-only atomic submit boundary for closed pricing snapshot contract v2 with four authoritative budget provenance states. It stores authoritative output but never calculates pricing.';
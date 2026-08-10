create or replace function public.update_quote_request_intake_evidence(
  p_access_token_hash text,
  p_data jsonb
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
  v_value jsonb;
  v_now timestamptz;
  v_has_budget boolean;
  v_budget_label text;
  v_budget_scheme text;
  v_budget_code text;
  v_allowed_keys constant text[] := array[
    'primary_language', 'additional_languages', 'page_scope_details',
    'quote_form_details', 'multilingual_details', 'download_details',
    'content_media_details', 'newsletter_details', 'hosting_maintenance_details',
    'deadline_details', 'seo_details', 'budget_update_category',
    'budget_update_category_scheme', 'budget_update_category_code'
  ];
  v_forbidden_pricing_keys constant text[] := array[
    'knownMinimumMinor', 'appliedRules', 'manualReviewRequired',
    'manualReasons', 'packageAdvice', 'budgetEvaluation',
    'pricingConfigVersion', 'pricingConfigHash', 'pricingSnapshot'
  ];
begin
  if p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;

  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_EVIDENCE';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_data) as supplied(key)
    where supplied.key = any(v_forbidden_pricing_keys)
  ) then
    raise exception using errcode = '22023', message = 'AUTHORITATIVE_PRICING_DATA_NOT_ALLOWED';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_data) as supplied(key)
    where not (supplied.key = any(v_allowed_keys))
  ) then
    raise exception using errcode = '22023', message = 'UNKNOWN_INTAKE_EVIDENCE_FIELD';
  end if;

  if p_data ? 'primary_language'
     and p_data->'primary_language' <> 'null'::jsonb
     and (
       jsonb_typeof(p_data->'primary_language') <> 'string'
       or char_length(btrim(p_data->>'primary_language')) not between 2 and 35
     ) then
    raise exception using errcode = '22023', message = 'INVALID_PRIMARY_LANGUAGE';
  end if;

  if p_data ? 'additional_languages' and p_data->'additional_languages' <> 'null'::jsonb then
    v_value := p_data->'additional_languages';
    if jsonb_typeof(v_value) <> 'array'
       or jsonb_array_length(v_value) > 8
       or exists (
         select 1
         from jsonb_array_elements(v_value) as language(value)
         where jsonb_typeof(language.value) <> 'string'
           or char_length(btrim(language.value #>> '{}')) not between 2 and 35
       ) then
      raise exception using errcode = '22023', message = 'INVALID_ADDITIONAL_LANGUAGES';
    end if;
  end if;

  if p_data ? 'page_scope_details' and p_data->'page_scope_details' <> 'null'::jsonb then
    v_value := p_data->'page_scope_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where not (supplied.key = any(array['reviews', 'blog', 'jobs', 'gallery']))
       )
       or exists (
         select 1 from jsonb_each(v_value) as supplied(key, value)
         where jsonb_typeof(supplied.value) <> 'string'
           or (supplied.value #>> '{}') not in ('normal', 'complex', 'unknown')
       ) then
      raise exception using errcode = '22023', message = 'INVALID_PAGE_SCOPE_DETAILS';
    end if;
  end if;

  if p_data ? 'quote_form_details' and p_data->'quote_form_details' <> 'null'::jsonb then
    v_value := p_data->'quote_form_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where not (supplied.key = any(array[
           'classification', 'file_uploads', 'database_workflow',
           'automated_processing', 'review_approval', 'custom_logic', 'form_count',
           'structure_scope'
         ]))
       )
       or (
         v_value ? 'classification'
         and (
           jsonb_typeof(v_value->'classification') <> 'string'
           or v_value->>'classification' not in ('simple', 'extended', 'complex', 'unknown')
         )
       )
       or (
         v_value ? 'structure_scope'
         and (
           jsonb_typeof(v_value->'structure_scope') <> 'string'
           or v_value->>'structure_scope' not in (
             'basic_single_section',
             'extended_standard_structure',
             'unsure_or_other'
           )
         )
       )
       or exists (
         select 1
         from unnest(array[
           'file_uploads', 'database_workflow', 'automated_processing',
           'review_approval', 'custom_logic'
         ]) as boolean_key(key)
         where v_value ? boolean_key.key
           and jsonb_typeof(v_value->boolean_key.key) <> 'boolean'
       ) then
      raise exception using errcode = '22023', message = 'INVALID_QUOTE_FORM_DETAILS';
    end if;
    if v_value ? 'form_count' and (
      jsonb_typeof(v_value->'form_count') <> 'number'
      or (v_value->>'form_count') !~ '^\d+$'
    ) then
      raise exception using errcode = '22023', message = 'INVALID_QUOTE_FORM_DETAILS';
    end if;
    if v_value ? 'form_count'
       and (v_value->>'form_count')::integer not between 1 and 20 then
      raise exception using errcode = '22023', message = 'INVALID_QUOTE_FORM_DETAILS';
    end if;
  end if;

  if p_data ? 'multilingual_details' and p_data->'multilingual_details' <> 'null'::jsonb then
    v_value := p_data->'multilingual_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where not (supplied.key = any(array[
           'final_translations_supplied', 'same_structure', 'extensive_seo',
           'language_specific_integrations', 'complex_scope'
         ]))
       )
       or exists (
         select 1
         from unnest(array[
           'final_translations_supplied', 'same_structure', 'extensive_seo',
           'language_specific_integrations', 'complex_scope'
         ]) as boolean_key(key)
         where v_value ? boolean_key.key
           and jsonb_typeof(v_value->boolean_key.key) <> 'boolean'
       ) then
      raise exception using errcode = '22023', message = 'INVALID_MULTILINGUAL_DETAILS';
    end if;
  end if;

  if p_data ? 'download_details' and p_data->'download_details' <> 'null'::jsonb then
    v_value := p_data->'download_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where supplied.key <> 'access'
       )
       or (
         v_value ? 'access'
         and (
           jsonb_typeof(v_value->'access') <> 'string'
           or v_value->>'access' not in ('public', 'secured', 'both', 'unknown')
         )
       ) then
      raise exception using errcode = '22023', message = 'INVALID_DOWNLOAD_DETAILS';
    end if;
  end if;

  if p_data ? 'content_media_details' and p_data->'content_media_details' <> 'null'::jsonb then
    v_value := p_data->'content_media_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where not (supplied.key = any(array[
           'copywriting_scope', 'image_work_scope', 'paid_stock_handling'
         ]))
       )
       or (
         v_value ? 'copywriting_scope'
         and (
           jsonb_typeof(v_value->'copywriting_scope') <> 'string'
           or v_value->>'copywriting_scope' not in ('none', 'light', 'substantial', 'unknown')
         )
       )
       or (
         v_value ? 'image_work_scope'
         and (
           jsonb_typeof(v_value->'image_work_scope') <> 'string'
           or v_value->>'image_work_scope' not in ('none', 'standard', 'exceptional', 'unknown')
         )
       )
       or (
         v_value ? 'paid_stock_handling'
         and jsonb_typeof(v_value->'paid_stock_handling') <> 'boolean'
       ) then
      raise exception using errcode = '22023', message = 'INVALID_CONTENT_MEDIA_DETAILS';
    end if;
  end if;

  if p_data ? 'newsletter_details' and p_data->'newsletter_details' <> 'null'::jsonb then
    v_value := p_data->'newsletter_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where supplied.key <> 'scope'
       )
       or (
         v_value ? 'scope'
         and (
           jsonb_typeof(v_value->'scope') <> 'string'
           or v_value->>'scope' not in (
             'simple_existing_service', 'new_service_setup',
             'automation_or_segmentation', 'unknown'
           )
         )
       ) then
      raise exception using errcode = '22023', message = 'INVALID_NEWSLETTER_DETAILS';
    end if;
  end if;

  if p_data ? 'hosting_maintenance_details' and p_data->'hosting_maintenance_details' <> 'null'::jsonb then
    v_value := p_data->'hosting_maintenance_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where not (supplied.key = any(array['hosting_support', 'maintenance_interest']))
       )
       or (
         v_value ? 'hosting_support'
         and (
           jsonb_typeof(v_value->'hosting_support') <> 'string'
           or v_value->>'hosting_support' not in ('yes', 'no', 'advice')
         )
       )
       or (
         v_value ? 'maintenance_interest'
         and (
           jsonb_typeof(v_value->'maintenance_interest') <> 'string'
           or v_value->>'maintenance_interest' not in ('yes', 'no', 'maybe', 'info_requested')
         )
       ) then
      raise exception using errcode = '22023', message = 'INVALID_HOSTING_MAINTENANCE_DETAILS';
    end if;
  end if;

  if p_data ? 'deadline_details' and p_data->'deadline_details' <> 'null'::jsonb then
    v_value := p_data->'deadline_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where not (supplied.key = any(array['commercially_critical', 'hard_deadline']))
       )
       or exists (
         select 1
         from unnest(array['commercially_critical', 'hard_deadline']) as boolean_key(key)
         where v_value ? boolean_key.key
           and jsonb_typeof(v_value->boolean_key.key) <> 'boolean'
       ) then
      raise exception using errcode = '22023', message = 'INVALID_DEADLINE_DETAILS';
    end if;
  end if;

  if p_data ? 'seo_details' and p_data->'seo_details' <> 'null'::jsonb then
    v_value := p_data->'seo_details';
    if jsonb_typeof(v_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_value) as supplied(key)
         where supplied.key <> 'extensive_services'
       )
       or (
         v_value ? 'extensive_services'
         and jsonb_typeof(v_value->'extensive_services') <> 'boolean'
       ) then
      raise exception using errcode = '22023', message = 'INVALID_SEO_DETAILS';
    end if;
  end if;

  v_has_budget := p_data ? 'budget_update_category'
    or p_data ? 'budget_update_category_scheme'
    or p_data ? 'budget_update_category_code';

  if v_has_budget then
    if not (
      p_data ? 'budget_update_category'
      and p_data ? 'budget_update_category_scheme'
      and p_data ? 'budget_update_category_code'
    )
       or jsonb_typeof(p_data->'budget_update_category') <> 'string'
       or jsonb_typeof(p_data->'budget_update_category_scheme') <> 'string'
       or jsonb_typeof(p_data->'budget_update_category_code') <> 'string' then
      raise exception using errcode = '22023', message = 'INCOHERENT_BUDGET_EVIDENCE';
    end if;

    v_budget_label := p_data->>'budget_update_category';
    v_budget_scheme := p_data->>'budget_update_category_scheme';
    v_budget_code := p_data->>'budget_update_category_code';

    if v_budget_scheme <> 'budget_guard_v1'
       or not (
         (v_budget_code = 'below_1800' and v_budget_label = 'Minder dan EUR 1.800')
         or (
           v_budget_code = '1800_to_below_3200'
           and v_budget_label = 'EUR 1.800 tot minder dan EUR 3.200'
         )
         or (
           v_budget_code = '3200_to_6000_inclusive'
           and v_budget_label = 'EUR 3.200 t/m EUR 6.000'
         )
         or (v_budget_code = 'above_6000' and v_budget_label = 'Meer dan EUR 6.000')
       ) then
      raise exception using errcode = '22023', message = 'INCOHERENT_BUDGET_EVIDENCE';
    end if;
  end if;

  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for update;

  if not found
     or v_intake.access_token_expires_at <= clock_timestamp()
     or v_intake.access_token_revoked_at is not null then
    return query select
      'invalid_token'::text, null::text, null::timestamptz, null::timestamptz;
    return;
  end if;

  if v_intake.status not in ('invited', 'in_progress') then
    return query select
      'not_editable'::text,
      v_intake.status::text,
      v_intake.started_at,
      v_intake.updated_at;
    return;
  end if;

  v_now := clock_timestamp();

  update public.quote_request_intakes
  set
    primary_language = case
      when not (p_data ? 'primary_language') then v_intake.primary_language
      when p_data->'primary_language' = 'null'::jsonb then null
      else btrim(p_data->>'primary_language')
    end,
    additional_languages = case
      when not (p_data ? 'additional_languages') then v_intake.additional_languages
      when p_data->'additional_languages' = 'null'::jsonb then null
      else array(
        select btrim(language.value)
        from jsonb_array_elements_text(p_data->'additional_languages') as language(value)
      )
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
    budget_update_category = case when v_has_budget then v_budget_label else v_intake.budget_update_category end,
    budget_update_category_scheme = case when v_has_budget then v_budget_scheme else v_intake.budget_update_category_scheme end,
    budget_update_category_code = case when v_has_budget then v_budget_code else v_intake.budget_update_category_code end,
    started_at = coalesce(v_intake.started_at, v_now),
    status = 'in_progress'::public.quote_request_intake_status
  where id = v_intake.id
  returning * into v_intake;

  return query select
    'saved'::text,
    v_intake.status::text,
    v_intake.started_at,
    v_intake.updated_at;
end;
$$;

comment on function public.update_quote_request_intake_evidence(text, jsonb) is
  'Service-role-only bridge for validated raw Budget Guard evidence. It cannot submit an intake, accept authoritative pricing output, or create a pricing snapshot.';

revoke all
on function public.update_quote_request_intake_evidence(text, jsonb)
from public, anon, authenticated;

grant execute
on function public.update_quote_request_intake_evidence(text, jsonb)
to service_role;
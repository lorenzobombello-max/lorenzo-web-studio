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
  v_result record;
  v_intake public.quote_request_intakes%rowtype;
  v_has_budget boolean;
  v_budget_label text;
  v_budget_scheme text;
  v_budget_code text;
  v_phase_d_keys constant text[] := array[
    'page_scope_details', 'multilingual_details', 'download_details',
    'content_media_details', 'newsletter_details',
    'hosting_maintenance_details', 'seo_details',
    'budget_update_category', 'budget_update_category_scheme',
    'budget_update_category_code'
  ];
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_EVIDENCE';
  end if;

  if p_data ? 'page_scope_details'
     and p_data->'page_scope_details' <> 'null'::jsonb
     and (
       jsonb_typeof(p_data->'page_scope_details') <> 'object'
       or exists (
         select 1 from jsonb_object_keys(p_data->'page_scope_details') supplied(key)
         where supplied.key not in ('reviews', 'blog', 'jobs', 'gallery', 'portfolio', 'search')
       )
       or exists (
         select 1 from jsonb_each(p_data->'page_scope_details') supplied(key, value)
         where jsonb_typeof(supplied.value) <> 'string'
       )
     ) then
    raise exception using errcode = '22023', message = 'INVALID_PAGE_SCOPE_DETAILS';
  end if;

  if p_data ? 'multilingual_details'
     and p_data->'multilingual_details' <> 'null'::jsonb
     and (
       jsonb_typeof(p_data->'multilingual_details') <> 'object'
       or exists (
         select 1 from jsonb_object_keys(p_data->'multilingual_details') supplied(key)
         where supplied.key not in (
           'final_translations_supplied', 'same_structure', 'extensive_seo',
           'translation_required', 'seo_per_language', 'advanced_seo_research',
           'language_specific_integrations', 'complex_scope'
         )
       )
       or exists (
         select 1 from jsonb_each(p_data->'multilingual_details') supplied(key, value)
         where jsonb_typeof(supplied.value) <> 'boolean'
       )
     ) then
    raise exception using errcode = '22023', message = 'INVALID_MULTILINGUAL_DETAILS';
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

    if not (
      (
        v_budget_scheme = 'budget_guard_v1'
        and (
          (v_budget_code = 'below_1800' and v_budget_label = 'Minder dan EUR 1.800')
          or (v_budget_code = '1800_to_below_3200' and v_budget_label = 'EUR 1.800 tot minder dan EUR 3.200')
          or (v_budget_code = '3200_to_6000_inclusive' and v_budget_label = 'EUR 3.200 t/m EUR 6.000')
          or (v_budget_code = 'above_6000' and v_budget_label = 'Meer dan EUR 6.000')
        )
      )
      or (
        v_budget_scheme = 'budget_guard_v2'
        and (
          (v_budget_code = 'below_1800' and v_budget_label = 'Minder dan EUR 1.800')
          or (v_budget_code = '1800_to_below_3500' and v_budget_label = 'EUR 1.800 tot minder dan EUR 3.500')
          or (v_budget_code = '3500_to_6000_inclusive' and v_budget_label = 'EUR 3.500 t/m EUR 6.000')
          or (v_budget_code = 'above_6000' and v_budget_label = 'Meer dan EUR 6.000')
        )
      )
    ) then
      raise exception using errcode = '22023', message = 'INCOHERENT_BUDGET_EVIDENCE';
    end if;
  end if;

  select * into v_result
  from public.update_quote_request_intake_evidence_v1(
    p_access_token_hash,
    p_data - v_phase_d_keys
  );

  if v_result.outcome <> 'saved' then
    return query select
      v_result.outcome, v_result.intake_status,
      v_result.started_at, v_result.updated_at;
    return;
  end if;

  update public.quote_request_intakes
  set
    page_scope_details = case when p_data ? 'page_scope_details' then nullif(p_data->'page_scope_details', 'null'::jsonb) else page_scope_details end,
    multilingual_details = case when p_data ? 'multilingual_details' then nullif(p_data->'multilingual_details', 'null'::jsonb) else multilingual_details end,
    download_details = case when p_data ? 'download_details' then nullif(p_data->'download_details', 'null'::jsonb) else download_details end,
    content_media_details = case when p_data ? 'content_media_details' then nullif(p_data->'content_media_details', 'null'::jsonb) else content_media_details end,
    newsletter_details = case when p_data ? 'newsletter_details' then nullif(p_data->'newsletter_details', 'null'::jsonb) else newsletter_details end,
    hosting_maintenance_details = case when p_data ? 'hosting_maintenance_details' then nullif(p_data->'hosting_maintenance_details', 'null'::jsonb) else hosting_maintenance_details end,
    seo_details = case when p_data ? 'seo_details' then nullif(p_data->'seo_details', 'null'::jsonb) else seo_details end,
    budget_update_category = case when v_has_budget then v_budget_label else budget_update_category end,
    budget_update_category_scheme = case when v_has_budget then v_budget_scheme else budget_update_category_scheme end,
    budget_update_category_code = case when v_has_budget then v_budget_code else budget_update_category_code end
  where access_token_hash = p_access_token_hash
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

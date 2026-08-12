create function public.is_valid_phase_d_intake_evidence(
  p_intake public.quote_request_intakes
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_value jsonb;
begin
  v_value := p_intake.page_scope_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(v_value) supplied(key)
      where supplied.key not in ('reviews', 'blog', 'jobs', 'gallery', 'portfolio', 'search')
    )
    or exists (
      select 1 from jsonb_each_text(v_value) supplied(key, value)
      where case supplied.key
        when 'reviews' then supplied.value not in ('normal', 'complex', 'unknown', 'live')
        when 'gallery' then supplied.value not in ('normal', 'complex', 'unknown', 'advanced')
        when 'portfolio' then supplied.value not in ('normal', 'dynamic')
        when 'search' then supplied.value not in ('none', 'basic', 'advanced')
        else supplied.value not in ('normal', 'complex', 'unknown')
      end
    )
  ) then return false; end if;

  v_value := p_intake.shop_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(v_value) supplied(key)
      where supplied.key not in (
        'approx_product_count', 'categories', 'online_payments', 'shipping', 'pickup',
        'existing_catalog', 'complex_product_count', 'payment_provider_count',
        'shipping_scope', 'customer_accounts', 'catalog_import', 'erp_api'
      )
    )
    or not (v_value ?& array[
      'approx_product_count', 'categories', 'online_payments', 'shipping', 'pickup', 'existing_catalog'
    ])
    or jsonb_typeof(v_value->'approx_product_count') <> 'number'
    or (v_value->>'approx_product_count') !~ '^\d+$'
    or (v_value->>'approx_product_count')::integer not between 1 and 100000
    or exists (
      select 1 from unnest(array[
        'categories', 'online_payments', 'shipping', 'pickup', 'existing_catalog',
        'customer_accounts', 'catalog_import', 'erp_api'
      ]) boolean_key(key)
      where v_value ? boolean_key.key and jsonb_typeof(v_value->boolean_key.key) <> 'boolean'
    )
    or (
      v_value ? 'complex_product_count' and (
        jsonb_typeof(v_value->'complex_product_count') <> 'number'
        or (v_value->>'complex_product_count') !~ '^\d+$'
        or (v_value->>'complex_product_count')::integer not between 0 and 10000
      )
    )
    or (
      v_value ? 'payment_provider_count' and (
        jsonb_typeof(v_value->'payment_provider_count') <> 'number'
        or (v_value->>'payment_provider_count') !~ '^\d+$'
        or (v_value->>'payment_provider_count')::integer not between 1 and 20
      )
    )
    or (
      v_value ? 'shipping_scope' and (
        jsonb_typeof(v_value->'shipping_scope') <> 'string'
        or v_value->>'shipping_scope' not in ('standard', 'complex')
      )
    )
  ) then return false; end if;

  v_value := p_intake.booking_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(v_value) supplied(key)
      where supplied.key not in ('tier', 'type', 'existing_system', 'existing_system_name', 'calendar_integration')
    )
    or not (v_value ?& array['type', 'existing_system', 'existing_system_name', 'calendar_integration'])
    or jsonb_typeof(v_value->'type') <> 'string'
    or v_value->>'type' not in ('appointments', 'reservations', 'events', 'other')
    or jsonb_typeof(v_value->'existing_system') <> 'boolean'
    or jsonb_typeof(v_value->'calendar_integration') <> 'boolean'
    or (
      v_value ? 'tier' and (
        jsonb_typeof(v_value->'tier') <> 'string'
        or v_value->>'tier' not in ('widget', 'advanced', 'custom')
      )
    )
    or (
      (v_value->>'existing_system')::boolean and (
        jsonb_typeof(v_value->'existing_system_name') <> 'string'
        or nullif(btrim(v_value->>'existing_system_name'), '') is null
        or char_length(v_value->>'existing_system_name') > 160
      )
    )
    or (
      not (v_value->>'existing_system')::boolean
      and v_value->'existing_system_name' <> 'null'::jsonb
    )
  ) then return false; end if;

  v_value := p_intake.multilingual_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(v_value) supplied(key)
      where supplied.key not in (
        'final_translations_supplied', 'same_structure', 'extensive_seo',
        'translation_required', 'seo_per_language', 'advanced_seo_research',
        'language_specific_integrations', 'complex_scope'
      )
    )
    or exists (
      select 1 from jsonb_each(v_value) supplied(key, value)
      where jsonb_typeof(supplied.value) <> 'boolean'
    )
  ) then return false; end if;

  v_value := p_intake.download_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (select 1 from jsonb_object_keys(v_value) supplied(key) where supplied.key <> 'access')
    or (
      v_value ? 'access' and (
        jsonb_typeof(v_value->'access') <> 'string'
        or v_value->>'access' not in (
          'none', 'public', 'secured', 'both', 'download', 'document_flow', 'portal', 'unknown'
        )
      )
    )
  ) then return false; end if;

  v_value := p_intake.content_media_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(v_value) supplied(key)
      where supplied.key not in (
        'copywriting_scope', 'copy_page_count', 'image_work_scope',
        'paid_stock_handling', 'branding_tier'
      )
    )
    or (
      v_value ? 'copywriting_scope' and (
        jsonb_typeof(v_value->'copywriting_scope') <> 'string'
        or v_value->>'copywriting_scope' not in (
          'none', 'supplied', 'light', 'substantial', 'new', 'specialist', 'unknown'
        )
      )
    )
    or (
      v_value ? 'copy_page_count' and (
        jsonb_typeof(v_value->'copy_page_count') <> 'number'
        or (v_value->>'copy_page_count') !~ '^\d+$'
        or (v_value->>'copy_page_count')::integer not between 1 and 100
      )
    )
    or (
      v_value ? 'image_work_scope' and (
        jsonb_typeof(v_value->'image_work_scope') <> 'string'
        or v_value->>'image_work_scope' not in (
          'none', 'standard', 'advanced', 'ai_set', 'stock', 'photography', 'exceptional', 'unknown'
        )
      )
    )
    or (v_value ? 'paid_stock_handling' and jsonb_typeof(v_value->'paid_stock_handling') <> 'boolean')
    or (
      v_value ? 'branding_tier' and (
        jsonb_typeof(v_value->'branding_tier') <> 'string'
        or v_value->>'branding_tier' not in ('existing', 'logo', 'identity', 'logo_identity', 'extended')
      )
    )
  ) then return false; end if;

  v_value := p_intake.newsletter_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(v_value) supplied(key)
      where supplied.key not in ('scope', 'analytics', 'custom_integration')
    )
    or (
      v_value ? 'scope' and (
        jsonb_typeof(v_value->'scope') <> 'string'
        or v_value->>'scope' not in (
          'simple_existing_service', 'new_service_setup', 'automation_or_segmentation', 'unknown'
        )
      )
    )
    or (
      v_value ? 'analytics' and (
        jsonb_typeof(v_value->'analytics') <> 'string'
        or v_value->>'analytics' not in ('standard', 'advanced')
      )
    )
    or (v_value ? 'custom_integration' and jsonb_typeof(v_value->'custom_integration') <> 'boolean')
  ) then return false; end if;

  v_value := p_intake.hosting_maintenance_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(v_value) supplied(key)
      where supplied.key not in (
        'hosting_support', 'maintenance_interest', 'domain_service', 'maintenance_plan'
      )
    )
    or (
      v_value ? 'hosting_support' and (
        jsonb_typeof(v_value->'hosting_support') <> 'string'
        or v_value->>'hosting_support' not in ('yes', 'no', 'advice')
      )
    )
    or (
      v_value ? 'maintenance_interest' and (
        jsonb_typeof(v_value->'maintenance_interest') <> 'string'
        or v_value->>'maintenance_interest' not in ('yes', 'no', 'maybe', 'info_requested')
      )
    )
    or (
      v_value ? 'domain_service' and (
        jsonb_typeof(v_value->'domain_service') <> 'string'
        or v_value->>'domain_service' not in (
          'existing', 'new', 'dns', 'transfer', 'migration', 'complex_dns_mail', 'complex_migration'
        )
      )
    )
    or (
      v_value ? 'maintenance_plan' and (
        jsonb_typeof(v_value->'maintenance_plan') <> 'string'
        or v_value->>'maintenance_plan' not in ('none', 'care', 'care_plus')
      )
    )
  ) then return false; end if;

  v_value := p_intake.seo_details;
  if v_value is not null and (
    jsonb_typeof(v_value) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(v_value) supplied(key)
      where supplied.key not in (
        'extensive_services', 'scope', 'extra_language_seo', 'advanced_language_seo'
      )
    )
    or exists (
      select 1 from unnest(array[
        'extensive_services', 'extra_language_seo', 'advanced_language_seo'
      ]) boolean_key(key)
      where v_value ? boolean_key.key and jsonb_typeof(v_value->boolean_key.key) <> 'boolean'
    )
    or (
      v_value ? 'scope' and (
        jsonb_typeof(v_value->'scope') <> 'string'
        or v_value->>'scope' not in ('included', 'launch', 'complex')
      )
    )
  ) then return false; end if;

  return true;
end;
$$;

create function public.enforce_phase_d_intake_evidence()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not public.is_valid_phase_d_intake_evidence(new) then
    raise exception using errcode = '22023', message = 'INVALID_PHASE_D_INTAKE_EVIDENCE';
  end if;
  return new;
end;
$$;

create trigger quote_request_intakes_validate_phase_d_evidence
before insert or update of
  page_scope_details, shop_details, booking_details, multilingual_details,
  download_details, content_media_details, newsletter_details,
  hosting_maintenance_details, seo_details
on public.quote_request_intakes
for each row execute function public.enforce_phase_d_intake_evidence();

alter function public.update_quote_request_intake_evidence(text, jsonb)
rename to update_quote_request_intake_evidence_v1;

create function public.update_quote_request_intake_evidence(
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
  v_phase_d_keys constant text[] := array[
    'page_scope_details', 'multilingual_details', 'download_details',
    'content_media_details', 'newsletter_details',
    'hosting_maintenance_details', 'seo_details'
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
    seo_details = case when p_data ? 'seo_details' then nullif(p_data->'seo_details', 'null'::jsonb) else seo_details end
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

revoke all
on function public.update_quote_request_intake_evidence_v1(text, jsonb)
from public, anon, authenticated, service_role;

revoke all
on function public.is_valid_phase_d_intake_evidence(public.quote_request_intakes)
from public, anon, authenticated;

grant execute
on function public.is_valid_phase_d_intake_evidence(public.quote_request_intakes)
to service_role;

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
      )
    end
  from public.inspect_quote_request_intake_details_v3(p_access_token_hash) as legacy
  join public.quote_request_intakes as intake on intake.id = legacy.intake_id
  left join public.quote_request_pricing_snapshots as snapshot on snapshot.intake_id = legacy.intake_id
$$;

alter table public.website_requirement_sync_runs
  add column proposed_changes jsonb not null default '[]'::jsonb;

create or replace function lws_internal.guard_website_requirement_command_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if current_setting('lws.website_requirement_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_WEBSITE_REQUIREMENT_WRITE_FORBIDDEN';
  end if;

  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_ROOT_IMMUTABLE';
  end if;

  if tg_op = 'UPDATE' then
    if new.revision <> old.revision + 1 then
      raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
    end if;

    if new.website_work_context_id is distinct from old.website_work_context_id
       or new.quote_request_id is distinct from old.quote_request_id then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_requirements_boards'
       and new.requirements_board_id is distinct from old.requirements_board_id then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_requirements' then
      if new.requirement_id is distinct from old.requirement_id
         or new.requirements_board_id is distinct from old.requirements_board_id then
        raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_IDENTITY_IMMUTABLE';
      end if;

      if old.status <> 'PENDING'
         and (
           new.source_key is distinct from old.source_key
           or new.source_reference is distinct from old.source_reference
           or new.source_value_sha256 is distinct from old.source_value_sha256
           or new.item_number is distinct from old.item_number
           or new.sort_order is distinct from old.sort_order
           or new.title is distinct from old.title
           or new.description is distinct from old.description
           or new.category is distinct from old.category
           or new.linked_page_or_module is distinct from old.linked_page_or_module
           or new.completion_mode is distinct from old.completion_mode
           or new.completion_rule_key is distinct from old.completion_rule_key
           or new.completion_rule_version is distinct from old.completion_rule_version
           or new.required is distinct from old.required
           or new.created_at is distinct from old.created_at
         ) then
        raise exception using errcode = '55000', message = 'STARTED_WEBSITE_REQUIREMENT_DEFINITION_IMMUTABLE';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create function lws_internal.website_requirements_sha256_hex_v1(p_value text)
returns text
language sql
immutable
set search_path = extensions, pg_catalog
as $$
  select encode(extensions.digest(convert_to(coalesce(p_value, ''), 'UTF8'), 'sha256'), 'hex')
$$;

create function lws_internal.website_requirements_hash16_v1(p_value text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select substr(lws_internal.website_requirements_sha256_hex_v1(lower(coalesce(p_value, ''))), 1, 16)
$$;

create function lws_internal.website_requirements_normalize_text_v1(p_value text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_value text := coalesce(p_value, '');
begin
  begin
    execute 'select normalize($1, NFKC)'
      into v_value
      using v_value;
  exception
    when others then
      null;
  end;

  v_value := replace(replace(v_value, E'\r\n', E'\n'), E'\r', E'\n');
  v_value := regexp_replace(v_value, E'[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]', '', 'g');
  v_value := btrim(v_value);

  return nullif(v_value, '');
end;
$$;

create function lws_internal.website_requirements_normalize_text_array_v1(p_values text[])
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select distinct lws_internal.website_requirements_normalize_text_v1(value) as value
    from unnest(coalesce(p_values, array[]::text[])) as entry(value)
  )
  select coalesce(
    array_agg(value order by lower(value) collate "C", value collate "C"),
    array[]::text[]
  )
  from normalized
  where value is not null
$$;

create function lws_internal.website_requirements_normalize_catalog_array_v1(
  p_values text[],
  p_catalog text[]
)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select distinct lws_internal.website_requirements_normalize_text_v1(value) as value
    from unnest(coalesce(p_values, array[]::text[])) as entry(value)
  )
  select coalesce(
    array_agg(catalog.value order by catalog.ordinality),
    array[]::text[]
  )
  from unnest(coalesce(p_catalog, array[]::text[])) with ordinality as catalog(value, ordinality)
  where catalog.value in (select value from normalized where value is not null)
$$;

create function lws_internal.website_requirements_normalize_language_v1(p_value text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_value text := lws_internal.website_requirements_normalize_text_v1(p_value);
  v_folded text;
begin
  if v_value is null then
    return null;
  end if;

  v_value := replace(lower(v_value), '_', '-');
  v_folded := translate(
    v_value,
    'áàâäãåçéèêëíìîïñóòôöõúùûüýÿ',
    'aaaaaaceeeeiiiinooooouuuuyy'
  );

  return case v_folded
    when 'nl' then 'nl'
    when 'nederlands' then 'nl'
    when 'dutch' then 'nl'
    when 'fr' then 'fr'
    when 'frans' then 'fr'
    when 'francais' then 'fr'
    when 'french' then 'fr'
    when 'en' then 'en'
    when 'engels' then 'en'
    when 'english' then 'en'
    when 'de' then 'de'
    when 'duits' then 'de'
    when 'deutsch' then 'de'
    when 'german' then 'de'
    when 'it' then 'it'
    when 'italiaans' then 'it'
    when 'italiano' then 'it'
    when 'italian' then 'it'
    when 'es' then 'es'
    when 'spaans' then 'es'
    when 'espanol' then 'es'
    when 'spanish' then 'es'
    else v_value
  end;
end;
$$;

create function lws_internal.website_requirements_normalize_custom_pages_v1(p_value text)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  with split_values as (
    select lws_internal.website_requirements_normalize_text_v1(value) as value
    from regexp_split_to_table(
      coalesce(replace(replace(p_value, E'\r\n', E'\n'), E'\r', E'\n'), ''),
      E'(\n|;)'
    ) as entry(value)
  ),
  deduplicated as (
    select min(value collate "C") as value
    from split_values
    where value is not null
    group by lower(value) collate "C"
  )
  select coalesce(
    array_agg(value order by lower(value) collate "C", value collate "C"),
    array[]::text[]
  )
  from deduplicated
$$;

create function lws_internal.website_requirements_is_relevant_jsonb_v1(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_text text;
begin
  if p_value is null then
    return false;
  end if;

  case jsonb_typeof(p_value)
    when 'null' then
      return false;
    when 'boolean' then
      return p_value = 'true'::jsonb;
    when 'number' then
      return true;
    when 'string' then
      v_text := lws_internal.website_requirements_normalize_text_v1(p_value #>> '{}');
      return v_text is not null;
    when 'array' then
      return jsonb_array_length(p_value) > 0;
    when 'object' then
      return exists (
        select 1
        from jsonb_each(p_value) as entry(key_name, value_json)
        where lws_internal.website_requirements_is_relevant_jsonb_v1(value_json)
      );
    else
      return false;
  end case;
end;
$$;

create function lws_internal.website_requirements_put_text_v1(
  p_object jsonb,
  p_key text,
  p_value text
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when lws_internal.website_requirements_normalize_text_v1(p_value) is null then coalesce(p_object, '{}'::jsonb)
    else coalesce(p_object, '{}'::jsonb)
      || jsonb_build_object(p_key, lws_internal.website_requirements_normalize_text_v1(p_value))
  end
$$;

create function lws_internal.website_requirements_put_array_v1(
  p_object jsonb,
  p_key text,
  p_values text[]
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when coalesce(array_length(p_values, 1), 0) = 0 then coalesce(p_object, '{}'::jsonb)
    else coalesce(p_object, '{}'::jsonb) || jsonb_build_object(p_key, to_jsonb(p_values))
  end
$$;

create function lws_internal.website_requirements_put_boolean_v1(
  p_object jsonb,
  p_key text,
  p_value jsonb
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_value is null or jsonb_typeof(p_value) <> 'boolean' then coalesce(p_object, '{}'::jsonb)
    else coalesce(p_object, '{}'::jsonb) || jsonb_build_object(p_key, p_value)
  end
$$;

create function lws_internal.website_requirements_put_number_v1(
  p_object jsonb,
  p_key text,
  p_value jsonb
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_value is null or jsonb_typeof(p_value) <> 'number' then coalesce(p_object, '{}'::jsonb)
    else coalesce(p_object, '{}'::jsonb) || jsonb_build_object(p_key, p_value)
  end
$$;

create function lws_internal.website_requirements_put_jsonb_v1(
  p_object jsonb,
  p_key text,
  p_value jsonb
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_value is null or jsonb_typeof(p_value) in ('null') then coalesce(p_object, '{}'::jsonb)
    when jsonb_typeof(p_value) = 'array' and jsonb_array_length(p_value) = 0 then coalesce(p_object, '{}'::jsonb)
    when jsonb_typeof(p_value) = 'object' and p_value = '{}'::jsonb then coalesce(p_object, '{}'::jsonb)
    else coalesce(p_object, '{}'::jsonb) || jsonb_build_object(p_key, p_value)
  end
$$;

create function lws_internal.website_requirements_append_source_v1(
  p_sources jsonb,
  p_source_key text,
  p_title text,
  p_category text,
  p_linked_page_or_module text,
  p_source_value jsonb
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(p_sources, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'source_key', p_source_key,
      'title', p_title,
      'category', p_category,
      'linked_page_or_module', to_jsonb(p_linked_page_or_module),
      'source_value', p_source_value
    )
  )
$$;

create function lws_internal.website_requirements_safe_source_reference_v1(
  p_intake_id uuid,
  p_intake_revision bigint,
  p_submitted_at timestamptz,
  p_source_key text,
  p_source_value_sha256 text
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'authority_type', 'WEBSITE_INTAKE',
    'intake_id', p_intake_id,
    'intake_revision', p_intake_revision,
    'submitted_at', p_submitted_at,
    'source_path', 'mapping_v1/' || p_source_key,
    'source_key', p_source_key,
    'source_value_sha256', p_source_value_sha256,
    'mapping_version', 1
  )
$$;

create function lws_internal.website_requirements_safe_description_v1(
  p_source_key text,
  p_source_value jsonb
)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_description text :=
    'Klantvraag uit bevestigde Website-intake. Bron: '
    || p_source_key
    || '. Details: '
    || coalesce(p_source_value::text, 'null');
begin
  if char_length(v_description) <= 1200 then
    return v_description;
  end if;

  return left(v_description, 1187) || '... [verkort]';
end;
$$;

create function lws_internal.website_requirements_jsonb_exact_keys_v1(
  p_value jsonb,
  p_keys text[]
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_typeof(p_value) = 'object'
    and coalesce(
      array(
        select key_name
        from jsonb_object_keys(p_value) as keys(key_name)
        order by key_name
      ),
      array[]::text[]
    ) = coalesce(p_keys, array[]::text[])
$$;

create function lws_internal.website_requirements_source_reference_shape_v1(p_value jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select lws_internal.website_requirements_jsonb_exact_keys_v1(
      p_value,
      array[
        'authority_type',
        'intake_id',
        'intake_revision',
        'mapping_version',
        'source_key',
        'source_path',
        'source_value_sha256',
        'submitted_at'
      ]
    )
    and p_value->>'authority_type' = 'WEBSITE_INTAKE'
    and (p_value->>'intake_id') ~ '^[0-9a-f-]{36}$'
    and coalesce((p_value->>'intake_revision')::bigint, 0) > 0
    and p_value->>'source_path' = 'mapping_v1/' || (p_value->>'source_key')
    and (p_value->>'source_value_sha256') ~ '^[0-9a-f]{64}$'
    and coalesce((p_value->>'mapping_version')::integer, 0) = 1
    and p_value ? 'submitted_at'
$$;

create function lws_internal.website_requirements_proposed_definition_shape_v1(p_value jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select p_value is null
    or p_value = 'null'::jsonb
    or (
      lws_internal.website_requirements_jsonb_exact_keys_v1(
        p_value,
        array[
          'category',
          'completion_mode',
          'completion_rule_key',
          'completion_rule_version',
          'description',
          'linked_page_or_module',
          'required',
          'source_reference',
          'title'
        ]
      )
      and p_value->>'completion_mode' = 'OPERATOR'
      and p_value->'completion_rule_key' = 'null'::jsonb
      and p_value->'completion_rule_version' = 'null'::jsonb
      and jsonb_typeof(p_value->'required') = 'boolean'
      and jsonb_typeof(p_value->'title') = 'string'
      and jsonb_typeof(p_value->'description') = 'string'
      and jsonb_typeof(p_value->'category') = 'string'
      and (
        p_value->'linked_page_or_module' = 'null'::jsonb
        or jsonb_typeof(p_value->'linked_page_or_module') = 'string'
      )
      and lws_internal.website_requirements_source_reference_shape_v1(p_value->'source_reference')
    )
$$;

create function lws_internal.website_requirements_proposed_changes_shape_v1(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_entry jsonb;
begin
  if jsonb_typeof(p_value) <> 'array' then
    return false;
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(p_value) as entries(value)
  loop
    if not lws_internal.website_requirements_jsonb_exact_keys_v1(
      v_entry,
      array[
        'action',
        'previous_source_value_sha256',
        'proposed_definition',
        'proposed_source_value_sha256',
        'requirement_id',
        'source_key'
      ]
    ) then
      return false;
    end if;

    if coalesce(v_entry->>'action', '') not in (
      'CREATE',
      'UPDATE_SAFE',
      'UNCHANGED',
      'RETIRE',
      'REVIVE',
      'CHANGE_PENDING',
      'REMOVAL_PENDING'
    ) then
      return false;
    end if;

    if jsonb_typeof(v_entry->'source_key') <> 'string' then
      return false;
    end if;

    if not (
      v_entry->'requirement_id' = 'null'::jsonb
      or (
        jsonb_typeof(v_entry->'requirement_id') = 'string'
        and (v_entry->>'requirement_id') ~ '^[0-9a-f-]{36}$'
      )
    ) then
      return false;
    end if;

    if not (
      v_entry->'previous_source_value_sha256' = 'null'::jsonb
      or (
        jsonb_typeof(v_entry->'previous_source_value_sha256') = 'string'
        and (v_entry->>'previous_source_value_sha256') ~ '^[0-9a-f]{64}$'
      )
    ) then
      return false;
    end if;

    if not (
      v_entry->'proposed_source_value_sha256' = 'null'::jsonb
      or (
        jsonb_typeof(v_entry->'proposed_source_value_sha256') = 'string'
        and (v_entry->>'proposed_source_value_sha256') ~ '^[0-9a-f]{64}$'
      )
    ) then
      return false;
    end if;

    if (v_entry->>'action') = 'CREATE' and v_entry->'requirement_id' <> 'null'::jsonb then
      return false;
    end if;

    if not lws_internal.website_requirements_proposed_definition_shape_v1(v_entry->'proposed_definition') then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

alter table public.website_requirement_sync_runs
  add constraint website_requirement_sync_runs_proposed_changes_shape
  check (lws_internal.website_requirements_proposed_changes_shape_v1(proposed_changes));

create function lws_internal.website_requirements_snapshot_payload_v1(p_sources jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'mapping_version', 1,
    'sources', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'source_key', value->>'source_key',
            'source_value', value->'source_value'
          )
          order by ordinality
        )
        from jsonb_array_elements(coalesce(p_sources, '[]'::jsonb)) with ordinality as source_rows(value, ordinality)
      ),
      '[]'::jsonb
    )
  )
$$;

create function lws_internal.project_website_requirement_sources_v1(
  p_intake public.quote_request_intakes
)
returns jsonb
language plpgsql
stable
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_sources jsonb := '[]'::jsonb;
  v_source_value jsonb;
  v_detail jsonb;
  v_value text;
  v_custom_page text;
  v_integration text;
  v_language_value text;
  v_primary_language text;
  v_known_languages constant text[] := array['nl', 'fr', 'en', 'de', 'it', 'es'];
  v_additional_languages text[] := array[]::text[];
  v_unknown_languages text[] := array[]::text[];
  v_all_language_inputs text[] := array[]::text[];
  v_page_scope_details jsonb := coalesce(p_intake.page_scope_details, '{}'::jsonb);
  v_quote_form_details jsonb := coalesce(p_intake.quote_form_details, '{}'::jsonb);
  v_multilingual_details jsonb := coalesce(p_intake.multilingual_details, '{}'::jsonb);
  v_download_details jsonb := coalesce(p_intake.download_details, '{}'::jsonb);
  v_content_media_details jsonb := coalesce(p_intake.content_media_details, '{}'::jsonb);
  v_newsletter_details jsonb := coalesce(p_intake.newsletter_details, '{}'::jsonb);
  v_hosting_maintenance_details jsonb := coalesce(p_intake.hosting_maintenance_details, '{}'::jsonb);
  v_deadline_details jsonb := coalesce(p_intake.deadline_details, '{}'::jsonb);
  v_seo_details jsonb := coalesce(p_intake.seo_details, '{}'::jsonb);
  v_business_description text := lws_internal.website_requirements_normalize_text_v1(p_intake.business_description);
  v_target_audience text := lws_internal.website_requirements_normalize_text_v1(p_intake.target_audience);
  v_existing_website_url text := lws_internal.website_requirements_normalize_text_v1(p_intake.existing_website_url);
  v_elements_to_keep text := lws_internal.website_requirements_normalize_text_v1(p_intake.elements_to_keep);
  v_improvement_areas text := lws_internal.website_requirements_normalize_text_v1(p_intake.improvement_areas);
  v_primary_conversion_goal text := lws_internal.website_requirements_normalize_text_v1(p_intake.primary_conversion_goal);
  v_brand_status text := lws_internal.website_requirements_normalize_text_v1(p_intake.brand_status);
  v_logo_status text := lws_internal.website_requirements_normalize_text_v1(p_intake.logo_status);
  v_content_status text := lws_internal.website_requirements_normalize_text_v1(p_intake.content_status);
  v_image_status text := lws_internal.website_requirements_normalize_text_v1(p_intake.image_status);
  v_domain_status text := lws_internal.website_requirements_normalize_text_v1(p_intake.domain_status);
  v_domain_name text := lws_internal.website_requirements_normalize_text_v1(p_intake.domain_name);
  v_hosting_status text := lws_internal.website_requirements_normalize_text_v1(p_intake.hosting_status);
  v_hosting_support text := lws_internal.website_requirements_normalize_text_v1(p_intake.hosting_support);
  v_maintenance_interest text := lws_internal.website_requirements_normalize_text_v1(p_intake.maintenance_interest);
  v_seo_priority text := lws_internal.website_requirements_normalize_text_v1(p_intake.seo_priority);
  v_deadline_date text := lws_internal.website_requirements_normalize_text_v1(case when p_intake.deadline_date is null then null else p_intake.deadline_date::text end);
  v_deadline_reason text := lws_internal.website_requirements_normalize_text_v1(p_intake.deadline_reason);
  v_additional_notes text := lws_internal.website_requirements_normalize_text_v1(p_intake.additional_notes);
  v_website_goals text[] := lws_internal.website_requirements_normalize_catalog_array_v1(
    p_intake.website_goals,
    array[
      'professional_presence', 'generate_leads', 'quote_requests', 'contact_requests',
      'appointments', 'reservations', 'sell_products', 'sell_services', 'portfolio',
      'information', 'recruitment', 'other'
    ]
  );
  v_requested_pages text[] := lws_internal.website_requirements_normalize_catalog_array_v1(
    p_intake.requested_pages,
    array[
      'home', 'about', 'services', 'products', 'portfolio', 'team', 'pricing', 'faq',
      'reviews', 'blog', 'contact', 'quote_request', 'reservations', 'shop', 'jobs',
      'gallery', 'other'
    ]
  );
  v_requested_features text[];
  v_design_styles text[] := lws_internal.website_requirements_normalize_catalog_array_v1(
    p_intake.design_styles,
    array[
      'modern', 'business', 'minimal', 'elegant', 'luxury', 'warm', 'playful',
      'creative', 'technical', 'industrial', 'calm', 'unsure', 'other'
    ]
  );
  v_image_support text[] := lws_internal.website_requirements_normalize_catalog_array_v1(
    p_intake.image_support,
    array['optimize_existing', 'ai_images', 'stock_images', 'professional_photography', 'none', 'unsure']
  );
  v_priorities text[] := lws_internal.website_requirements_normalize_catalog_array_v1(
    p_intake.priorities,
    array[
      'professional_appearance', 'usability', 'more_requests', 'more_sales',
      'mobile_experience', 'performance', 'seo', 'easy_management', 'fast_delivery',
      'stay_within_budget', 'differentiate', 'other'
    ]
  );
  v_brand_colors text[] := lws_internal.website_requirements_normalize_text_array_v1(p_intake.brand_colors);
  v_inspiration_sites text[] := lws_internal.website_requirements_normalize_text_array_v1(p_intake.inspiration_sites);
  v_seo_keywords text[] := lws_internal.website_requirements_normalize_text_array_v1(p_intake.seo_keywords);
  v_social_channels text[] := lws_internal.website_requirements_normalize_text_array_v1(p_intake.social_channels);
  v_integrations text[] := lws_internal.website_requirements_normalize_text_array_v1(p_intake.integrations);
  v_other_pages text[] := lws_internal.website_requirements_normalize_custom_pages_v1(p_intake.other_pages);
  v_feature_catalog constant text[] := array[
    'contact_form', 'quote_form', 'google_maps', 'social_links', 'reviews', 'gallery',
    'newsletter', 'whatsapp', 'appointments', 'reservations', 'shop', 'online_payment',
    'customer_login', 'downloads', 'search', 'multilingual', 'other', 'unsure',
    'online_payment_products', 'online_payment_reservations', 'online_payment_appointments',
    'online_payment_services', 'online_payment_registrations', 'online_payment_deposit',
    'online_payment_other'
  ];
  v_feature_value text;
begin
  for v_feature_value in
    select lws_internal.website_requirements_normalize_text_v1(value)
    from unnest(coalesce(p_intake.requested_features, array[]::text[])) as entry(value)
  loop
    if v_feature_value is null then
      continue;
    end if;
    if v_feature_value <> all(v_feature_catalog) then
      raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENTS_MAPPING_UNSUPPORTED';
    end if;
  end loop;

  v_requested_features := lws_internal.website_requirements_normalize_catalog_array_v1(
    p_intake.requested_features,
    v_feature_catalog
  );

  v_primary_language := lws_internal.website_requirements_normalize_language_v1(p_intake.primary_language);
  if v_primary_language is null then
    foreach v_value in array coalesce(p_intake.languages, array[]::text[])
    loop
      v_language_value := lws_internal.website_requirements_normalize_language_v1(v_value);
      if v_language_value = any(v_known_languages) then
        v_primary_language := v_language_value;
        exit;
      end if;
    end loop;
  end if;

  v_all_language_inputs := coalesce(p_intake.languages, array[]::text[])
    || coalesce(p_intake.additional_languages, array[]::text[]);

  foreach v_value in array v_all_language_inputs
  loop
    v_language_value := lws_internal.website_requirements_normalize_language_v1(v_value);
    if v_language_value is null then
      continue;
    end if;

    if v_language_value = any(v_known_languages) then
      if v_language_value is distinct from v_primary_language
         and not v_language_value = any(v_additional_languages) then
        v_additional_languages := v_additional_languages || v_language_value;
      end if;
    elsif not v_language_value = any(v_unknown_languages) then
      v_unknown_languages := v_unknown_languages || v_language_value;
    end if;
  end loop;

  if coalesce(array_length(v_additional_languages, 1), 0) > 0 then
    select coalesce(array_agg(value order by lower(value) collate "C", value collate "C"), array[]::text[])
      into v_additional_languages
    from unnest(v_additional_languages) as entry(value);
  end if;

  if coalesce(array_length(v_unknown_languages, 1), 0) > 0 then
    select coalesce(array_agg(value order by lower(value) collate "C", value collate "C"), array[]::text[])
      into v_unknown_languages
    from unnest(v_unknown_languages) as entry(value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'business_description', v_business_description);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'target_audience', v_target_audience);
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'website_goals', v_website_goals);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'primary_conversion_goal', v_primary_conversion_goal);
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'priorities', v_priorities);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'additional_notes', v_additional_notes);
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(
      v_sources,
      'brief:site_direction',
      'Verwerk briefing, doelgroep en doelen',
      'CONTENT',
      null,
      v_source_value
    );
  end if;

  v_source_value := '{}'::jsonb;
  if p_intake.has_existing_website is not null then
    v_source_value := v_source_value || jsonb_build_object('has_existing_website', p_intake.has_existing_website);
  end if;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'existing_website_url', v_existing_website_url);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'elements_to_keep', v_elements_to_keep);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'improvement_areas', v_improvement_areas);
  if coalesce(p_intake.has_existing_website, false)
     or v_existing_website_url is not null
     or v_elements_to_keep is not null
     or v_improvement_areas is not null then
    v_sources := lws_internal.website_requirements_append_source_v1(
      v_sources,
      'site:existing',
      'Behoud en verbeter relevante delen van de bestaande website',
      'DESIGN',
      null,
      v_source_value
    );
  end if;

  if 'home' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:home', 'Bouw pagina: Home', 'PAGE', 'home', jsonb_build_object('requested', true));
  end if;
  if 'about' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:about', 'Bouw pagina: Over ons', 'PAGE', 'about', jsonb_build_object('requested', true));
  end if;
  if 'services' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:services', 'Bouw pagina: Diensten', 'PAGE', 'services', jsonb_build_object('requested', true));
  end if;
  if 'products' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:products', 'Bouw pagina: Producten', 'PAGE', 'products', jsonb_build_object('requested', true));
  end if;
  if 'portfolio' = any(v_requested_pages) then
    v_source_value := jsonb_build_object('requested', true);
    if lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'portfolio') is not null
       and lower(lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'portfolio')) <> 'none' then
      v_source_value := v_source_value || jsonb_build_object('scope', lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'portfolio'));
    end if;
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:portfolio', 'Bouw pagina: Portfolio', 'PAGE', 'portfolio', v_source_value);
  end if;
  if 'team' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:team', 'Bouw pagina: Team', 'PAGE', 'team', jsonb_build_object('requested', true));
  end if;
  if 'pricing' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:pricing', 'Bouw pagina: Prijzen', 'PAGE', 'pricing', jsonb_build_object('requested', true));
  end if;
  if 'faq' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:faq', 'Bouw pagina: FAQ', 'PAGE', 'faq', jsonb_build_object('requested', true));
  end if;
  if 'reviews' = any(v_requested_pages) then
    v_source_value := jsonb_build_object('requested', true);
    if lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'reviews') is not null
       and lower(lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'reviews')) <> 'none' then
      v_source_value := v_source_value || jsonb_build_object('scope', lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'reviews'));
    end if;
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:reviews', 'Bouw pagina: Reviews', 'PAGE', 'reviews', v_source_value);
  end if;
  if 'blog' = any(v_requested_pages) then
    v_source_value := jsonb_build_object('requested', true);
    if lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'blog') is not null
       and lower(lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'blog')) <> 'none' then
      v_source_value := v_source_value || jsonb_build_object('scope', lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'blog'));
    end if;
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:blog', 'Bouw pagina: Blog', 'PAGE', 'blog', v_source_value);
  end if;
  if 'contact' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:contact', 'Bouw pagina: Contact', 'PAGE', 'contact', jsonb_build_object('requested', true));
  end if;
  if 'quote_request' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:quote_request', 'Bouw pagina: Offerteaanvraag', 'PAGE', 'quote_request', jsonb_build_object('requested', true));
  end if;
  if 'reservations' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:reservations', 'Bouw pagina: Reservaties', 'PAGE', 'reservations', jsonb_build_object('requested', true));
  end if;
  if 'shop' = any(v_requested_pages) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:shop', 'Bouw pagina: Shop', 'PAGE', 'shop', jsonb_build_object('requested', true));
  end if;
  if 'jobs' = any(v_requested_pages) then
    v_source_value := jsonb_build_object('requested', true);
    if lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'jobs') is not null
       and lower(lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'jobs')) <> 'none' then
      v_source_value := v_source_value || jsonb_build_object('scope', lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'jobs'));
    end if;
    if lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'jobs_application') is not null then
      v_source_value := v_source_value || jsonb_build_object('jobs_application', lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'jobs_application'));
    end if;
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:jobs', 'Bouw pagina: Vacatures', 'PAGE', 'jobs', v_source_value);
  end if;
  if 'gallery' = any(v_requested_pages) then
    v_source_value := jsonb_build_object('requested', true);
    if lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'gallery') is not null
       and lower(lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'gallery')) <> 'none' then
      v_source_value := v_source_value || jsonb_build_object('scope', lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'gallery'));
    end if;
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'page:gallery', 'Bouw pagina: Galerij', 'PAGE', 'gallery', v_source_value);
  end if;

  foreach v_custom_page in array v_other_pages
  loop
    v_sources := lws_internal.website_requirements_append_source_v1(
      v_sources,
      'page:custom:' || lws_internal.website_requirements_hash16_v1(lower(v_custom_page)),
      'Bouw pagina: ' || v_custom_page,
      'PAGE',
      v_custom_page,
      jsonb_build_object('name', v_custom_page)
    );
  end loop;

  v_source_value := '{}'::jsonb;
  if p_intake.shop_required is not null then
    v_source_value := v_source_value || jsonb_build_object('shop_required', p_intake.shop_required);
  end if;
  if 'shop' = any(v_requested_features) then
    v_source_value := v_source_value || jsonb_build_object('requested_feature', true);
  end if;
  if 'shop' = any(v_requested_pages) then
    v_source_value := v_source_value || jsonb_build_object('requested_page', true);
  end if;
  v_detail := '{}'::jsonb;
  v_detail := lws_internal.website_requirements_put_number_v1(v_detail, 'approx_product_count', p_intake.shop_details->'approx_product_count');
  v_detail := lws_internal.website_requirements_put_number_v1(v_detail, 'complex_product_count', p_intake.shop_details->'complex_product_count');
  v_detail := lws_internal.website_requirements_put_number_v1(v_detail, 'payment_provider_count', p_intake.shop_details->'payment_provider_count');
  v_detail := lws_internal.website_requirements_put_text_v1(v_detail, 'shipping_scope', p_intake.shop_details->>'shipping_scope');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'categories', p_intake.shop_details->'categories');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'online_payments', p_intake.shop_details->'online_payments');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'shipping', p_intake.shop_details->'shipping');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'pickup', p_intake.shop_details->'pickup');
  v_detail := lws_internal.website_requirements_put_text_v1(v_detail, 'pickup_scope', p_intake.shop_details->>'pickup_scope');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'existing_catalog', p_intake.shop_details->'existing_catalog');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'customer_accounts', p_intake.shop_details->'customer_accounts');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'catalog_import', p_intake.shop_details->'catalog_import');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'erp_api', p_intake.shop_details->'erp_api');
  v_source_value := lws_internal.website_requirements_put_jsonb_v1(v_source_value, 'shop_details', v_detail);
  if coalesce(p_intake.shop_required, false)
     or 'shop' = any(v_requested_features)
     or 'shop' = any(v_requested_pages)
     or v_detail <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'module:shop', 'Bouw webshopfunctionaliteit', 'ECOMMERCE', 'module:shop', v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  if p_intake.booking_required is not null then
    v_source_value := v_source_value || jsonb_build_object('booking_required', p_intake.booking_required);
  end if;
  v_source_value := lws_internal.website_requirements_put_array_v1(
    v_source_value,
    'requested_features',
    lws_internal.website_requirements_normalize_catalog_array_v1(v_requested_features, array['appointments', 'reservations'])
  );
  if 'reservations' = any(v_requested_pages) then
    v_source_value := v_source_value || jsonb_build_object('requested_page', true);
  end if;
  v_source_value := lws_internal.website_requirements_put_array_v1(
    v_source_value,
    'website_goals',
    lws_internal.website_requirements_normalize_catalog_array_v1(v_website_goals, array['appointments', 'reservations'])
  );
  v_detail := '{}'::jsonb;
  v_detail := lws_internal.website_requirements_put_text_v1(v_detail, 'tier', p_intake.booking_details->>'tier');
  v_detail := lws_internal.website_requirements_put_text_v1(v_detail, 'type', p_intake.booking_details->>'type');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'existing_system', p_intake.booking_details->'existing_system');
  v_detail := lws_internal.website_requirements_put_text_v1(v_detail, 'existing_system_name', p_intake.booking_details->>'existing_system_name');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'calendar_integration', p_intake.booking_details->'calendar_integration');
  v_source_value := lws_internal.website_requirements_put_jsonb_v1(v_source_value, 'booking_details', v_detail);
  if coalesce(p_intake.booking_required, false)
     or cardinality(lws_internal.website_requirements_normalize_catalog_array_v1(v_requested_features, array['appointments', 'reservations'])) > 0
     or 'reservations' = any(v_requested_pages)
     or cardinality(lws_internal.website_requirements_normalize_catalog_array_v1(v_website_goals, array['appointments', 'reservations'])) > 0
     or v_detail <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'module:booking', 'Bouw reservatie- of boekingsfunctionaliteit', 'INTEGRATION', 'module:booking', v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_array_v1(
    v_source_value,
    'requested_features',
    lws_internal.website_requirements_normalize_catalog_array_v1(v_requested_features, array['contact_form', 'quote_form'])
  );
  if 'quote_request' = any(v_requested_pages) then
    v_source_value := v_source_value || jsonb_build_object('requested_page', true);
  end if;
  v_source_value := lws_internal.website_requirements_put_array_v1(
    v_source_value,
    'website_goals',
    lws_internal.website_requirements_normalize_catalog_array_v1(v_website_goals, array['generate_leads', 'quote_requests', 'contact_requests'])
  );
  v_detail := '{}'::jsonb;
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'file_uploads', v_quote_form_details->'file_uploads');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'database_workflow', v_quote_form_details->'database_workflow');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'automated_processing', v_quote_form_details->'automated_processing');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'review_approval', v_quote_form_details->'review_approval');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'custom_logic', v_quote_form_details->'custom_logic');
  v_detail := lws_internal.website_requirements_put_number_v1(v_detail, 'form_count', v_quote_form_details->'form_count');
  v_detail := lws_internal.website_requirements_put_text_v1(v_detail, 'structure_scope', v_quote_form_details->>'structure_scope');
  v_source_value := lws_internal.website_requirements_put_jsonb_v1(v_source_value, 'quote_form_details', v_detail);
  if cardinality(lws_internal.website_requirements_normalize_catalog_array_v1(v_requested_features, array['contact_form', 'quote_form'])) > 0
     or 'quote_request' = any(v_requested_pages)
     or cardinality(lws_internal.website_requirements_normalize_catalog_array_v1(v_website_goals, array['generate_leads', 'quote_requests', 'contact_requests'])) > 0
     or v_detail <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'module:forms', 'Bouw formulieren en aanvraagflow', 'FORM', 'module:forms', v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_array_v1(
    v_source_value,
    'requested_features',
    lws_internal.website_requirements_normalize_catalog_array_v1(
      v_requested_features,
      array[
        'online_payment', 'online_payment_products', 'online_payment_reservations',
        'online_payment_appointments', 'online_payment_services',
        'online_payment_registrations', 'online_payment_deposit', 'online_payment_other'
      ]
    )
  );
  if coalesce((p_intake.shop_details->>'online_payments')::boolean, false) then
    v_source_value := v_source_value || jsonb_build_object('shop_online_payments', true);
  end if;
  if cardinality(lws_internal.website_requirements_normalize_catalog_array_v1(
        v_requested_features,
        array[
          'online_payment', 'online_payment_products', 'online_payment_reservations',
          'online_payment_appointments', 'online_payment_services',
          'online_payment_registrations', 'online_payment_deposit', 'online_payment_other'
        ]
      )) > 0
     or coalesce((p_intake.shop_details->>'online_payments')::boolean, false) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'module:payments', 'Implementeer online betalingen', 'ECOMMERCE', 'module:payments', v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'primary_language', v_primary_language);
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'additional_languages', v_additional_languages);
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'unknown_languages', v_unknown_languages);
  v_detail := '{}'::jsonb;
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'final_translations_supplied', v_multilingual_details->'final_translations_supplied');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'same_structure', v_multilingual_details->'same_structure');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'translation_required', v_multilingual_details->'translation_required');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'seo_per_language', v_multilingual_details->'seo_per_language');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'advanced_seo_research', v_multilingual_details->'advanced_seo_research');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'language_specific_integrations', v_multilingual_details->'language_specific_integrations');
  v_detail := lws_internal.website_requirements_put_boolean_v1(v_detail, 'complex_scope', v_multilingual_details->'complex_scope');
  v_source_value := lws_internal.website_requirements_put_jsonb_v1(v_source_value, 'multilingual_details', v_detail);
  if 'multilingual' = any(v_requested_features)
     or coalesce(array_length(v_additional_languages, 1), 0) > 0
     or coalesce(array_length(v_unknown_languages, 1), 0) > 0
     or v_detail <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'module:multilingual', 'Implementeer meertaligheid', 'CONTENT', 'module:multilingual', v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'design_styles', v_design_styles);
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'inspiration_sites', v_inspiration_sites);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'disliked_styles', p_intake.disliked_styles);
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'design:visual_direction', 'Pas de afgesproken visuele richting toe', 'DESIGN', null, v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'brand_status', v_brand_status);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'logo_status', v_logo_status);
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'brand_colors', v_brand_colors);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'branding_tier', v_content_media_details->>'branding_tier');
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'design:brand_assets', 'Verwerk logo, kleuren en huisstijl', 'DESIGN', null, v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'content_status', v_content_status);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'copywriting_scope', v_content_media_details->>'copywriting_scope');
  v_source_value := lws_internal.website_requirements_put_number_v1(v_source_value, 'copy_page_count', v_content_media_details->'copy_page_count');
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'content:copy', 'Werk websitecopy uit', 'CONTENT', null, v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'image_status', v_image_status);
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'image_support', v_image_support);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'image_work_scope', v_content_media_details->>'image_work_scope');
  v_source_value := lws_internal.website_requirements_put_boolean_v1(v_source_value, 'paid_stock_handling', v_content_media_details->'paid_stock_handling');
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'content:images', 'Werk beeldmateriaal uit', 'MULTIMEDIA', null, v_source_value);
  end if;

  if 'downloads' = any(v_requested_features) or lws_internal.website_requirements_normalize_text_v1(v_download_details->>'access') is not null then
    v_source_value := '{}'::jsonb;
    if 'downloads' = any(v_requested_features) then
      v_source_value := v_source_value || jsonb_build_object('requested', true);
    end if;
    v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'access', v_download_details->>'access');
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'feature:downloads', 'Implementeer downloads en documenttoegang', 'DOCUMENT_FLOW', 'feature:downloads', v_source_value);
  end if;

  if 'newsletter' = any(v_requested_features) or lws_internal.website_requirements_is_relevant_jsonb_v1(v_newsletter_details) then
    v_source_value := '{}'::jsonb;
    if 'newsletter' = any(v_requested_features) then
      v_source_value := v_source_value || jsonb_build_object('requested', true);
    end if;
    v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'scope', v_newsletter_details->>'scope');
    v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'analytics', v_newsletter_details->>'analytics');
    v_source_value := lws_internal.website_requirements_put_boolean_v1(v_source_value, 'custom_integration', v_newsletter_details->'custom_integration');
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'feature:newsletter', 'Implementeer nieuwsbriefkoppeling', 'INTEGRATION', 'feature:newsletter', v_source_value);
  end if;

  if 'search' = any(v_requested_features)
     or (
       lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'search') is not null
       and lower(lws_internal.website_requirements_normalize_text_v1(v_page_scope_details->>'search')) <> 'none'
     ) then
    v_source_value := '{}'::jsonb;
    if 'search' = any(v_requested_features) then
      v_source_value := v_source_value || jsonb_build_object('requested', true);
    end if;
    v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'scope', v_page_scope_details->>'search');
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'feature:search', 'Implementeer zoekfunctie', 'TECHNICAL', 'feature:search', v_source_value);
  end if;

  if 'customer_login' = any(v_requested_features) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'feature:customer_login', 'Implementeer klantlogin', 'AUTH', 'feature:customer_login', jsonb_build_object('requested', true));
  end if;
  if 'gallery' = any(v_requested_features) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'feature:gallery', 'Implementeer galerijfunctionaliteit', 'MULTIMEDIA', 'feature:gallery', jsonb_build_object('requested', true));
  end if;
  if 'reviews' = any(v_requested_features) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'feature:reviews', 'Implementeer reviewfunctionaliteit', 'INTEGRATION', 'feature:reviews', jsonb_build_object('requested', true));
  end if;
  if 'other' = any(v_requested_features) or 'unsure' = any(v_requested_features) then
    v_source_value := '{}'::jsonb;
    v_source_value := lws_internal.website_requirements_put_array_v1(
      v_source_value,
      'requested_features',
      lws_internal.website_requirements_normalize_catalog_array_v1(v_requested_features, array['other', 'unsure'])
    );
    v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'additional_notes', v_additional_notes);
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'feature:manual_scope', 'Werk nog te bepalen functionaliteit uit', 'OTHER', 'feature:manual_scope', v_source_value);
  end if;

  if 'google_maps' = any(v_requested_features) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'integration:google_maps', 'Integreer Google Maps', 'INTEGRATION', 'integration:google_maps', jsonb_build_object('requested', true));
  end if;
  if 'social_links' = any(v_requested_features) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'integration:social_links', 'Implementeer social-links op de website', 'INTEGRATION', 'integration:social_links', jsonb_build_object('requested', true));
  end if;
  if 'whatsapp' = any(v_requested_features) then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'integration:whatsapp', 'Integreer WhatsApp-contact', 'INTEGRATION', 'integration:whatsapp', jsonb_build_object('requested', true));
  end if;
  if coalesce(array_length(v_social_channels, 1), 0) > 0 then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'integration:social_channels', 'Koppel sociale kanalen', 'INTEGRATION', 'integration:social_channels', jsonb_build_object('social_channels', to_jsonb(v_social_channels)));
  end if;

  foreach v_integration in array v_integrations
  loop
    v_sources := lws_internal.website_requirements_append_source_v1(
      v_sources,
      'integration:external:' || lws_internal.website_requirements_hash16_v1(lower(v_integration)),
      'Integreer externe koppeling: ' || v_integration,
      'INTEGRATION',
      'integration:external:' || lws_internal.website_requirements_hash16_v1(lower(v_integration)),
      jsonb_build_object('name', v_integration)
    );
  end loop;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'domain_status', v_domain_status);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'domain_name', v_domain_name);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'domain_service', v_hosting_maintenance_details->>'domain_service');
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'technical:domain', 'Configureer domein', 'TECHNICAL', null, v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'hosting_status', v_hosting_status);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'hosting_support', v_hosting_support);
  if v_hosting_support is not null and lower(v_hosting_support) not in ('yes', 'no') then
    v_source_value := v_source_value || jsonb_build_object('details_hosting_support', v_hosting_support);
  end if;
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'technical:hosting', 'Configureer hosting', 'TECHNICAL', null, v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'maintenance_interest', v_maintenance_interest);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'details_maintenance_interest', v_hosting_maintenance_details->>'details_maintenance_interest');
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'maintenance_plan', v_hosting_maintenance_details->>'maintenance_plan');
  if lower(coalesce(v_maintenance_interest, '')) in ('yes', 'maybe', 'info_requested')
     or lower(coalesce(lws_internal.website_requirements_normalize_text_v1(v_hosting_maintenance_details->>'details_maintenance_interest'), '')) in ('yes', 'maybe', 'info_requested')
     or lower(coalesce(lws_internal.website_requirements_normalize_text_v1(v_hosting_maintenance_details->>'maintenance_plan'), '')) in ('care', 'care_plus') then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'technical:maintenance', 'Configureer onderhoudsafspraken', 'TECHNICAL', null, v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'seo_priority', v_seo_priority);
  v_source_value := lws_internal.website_requirements_put_array_v1(v_source_value, 'seo_keywords', v_seo_keywords);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'scope', v_seo_details->>'scope');
  v_source_value := lws_internal.website_requirements_put_boolean_v1(v_source_value, 'extra_language_seo', v_seo_details->'extra_language_seo');
  v_source_value := lws_internal.website_requirements_put_boolean_v1(v_source_value, 'advanced_language_seo', v_seo_details->'advanced_language_seo');
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'seo:scope', 'Implementeer SEO-scope', 'SEO', null, v_source_value);
  end if;

  v_source_value := '{}'::jsonb;
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'deadline_date', v_deadline_date);
  v_source_value := lws_internal.website_requirements_put_text_v1(v_source_value, 'deadline_reason', v_deadline_reason);
  v_source_value := lws_internal.website_requirements_put_boolean_v1(v_source_value, 'commercially_critical', v_deadline_details->'commercially_critical');
  v_source_value := lws_internal.website_requirements_put_boolean_v1(v_source_value, 'hard_deadline', v_deadline_details->'hard_deadline');
  if v_source_value <> '{}'::jsonb then
    v_sources := lws_internal.website_requirements_append_source_v1(v_sources, 'constraint:deadline', 'Respecteer afgesproken deadline', 'OTHER', null, v_source_value);
  end if;

  return v_sources;
end;
$$;

create function public.sync_website_requirements_from_intake_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_expected_board_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_context public.website_work_contexts%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_board public.website_requirements_boards%rowtype;
  v_existing_command public.website_requirement_sync_runs%rowtype;
  v_existing_logical public.website_requirement_sync_runs%rowtype;
  v_requirement public.website_requirements%rowtype;
  v_source jsonb;
  v_source_key text;
  v_title text;
  v_category text;
  v_linked_page_or_module text;
  v_source_value jsonb;
  v_source_value_sha256 text;
  v_previous_source_value_sha256 text;
  v_source_reference jsonb;
  v_description text;
  v_definition jsonb;
  v_projected_sources jsonb;
  v_snapshot_payload jsonb;
  v_intake_sha256 text;
  v_actor_id text;
  v_sync_run_id uuid;
  v_request_fingerprint text;
  v_result jsonb;
  v_proposed_changes jsonb := '[]'::jsonb;
  v_created_count integer := 0;
  v_update_safe_count integer := 0;
  v_unchanged_count integer := 0;
  v_retired_count integer := 0;
  v_change_pending_count integer := 0;
  v_removal_pending_count integer := 0;
  v_revived_count integer := 0;
  v_requirement_id uuid;
  v_board_revision bigint;
  v_board_sync_state text;
  v_requirement_revision bigint;
  v_review_required boolean;
  v_change_action text;
  v_exact_intake_count bigint;
  v_board_exists boolean;
  v_skip_unchanged_source_key text := 'technical:hosting';
begin
  if p_quote_request_id is null
     or p_website_work_context_id is null
     or p_expected_board_revision is null
     or p_expected_board_revision < 0
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENTS_SYNC_COMMAND';
  end if;

  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.*
  into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject;

  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role not in ('owner', 'operations_manager') then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENTS_SYNC_FORBIDDEN';
  end if;

  if coalesce(auth.jwt()->>'aal', '') <> 'aal2' then
    raise exception using errcode = '42501', message = 'MFA_AAL2_REQUIRED';
  end if;

  v_actor_id := 'OPERATOR:' || v_operator.operator_id::text;

  select context.*
  into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = p_website_work_context_id
  for update;

  if not found or v_context.quote_request_id <> p_quote_request_id then
    raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENTS_CONTEXT_MISMATCH';
  end if;

  select request.*
  into v_request
  from public.quote_requests as request
  where request.id = p_quote_request_id
  for update;

  if not found
     or v_request.record_classification <> 'production'
     or v_request.request_kind <> 'website' then
    raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENTS_INTAKE_NOT_ELIGIBLE';
  end if;

  select count(*)
  into v_exact_intake_count
  from public.quote_request_intakes as intake
  where intake.quote_request_id = p_quote_request_id
    and intake.status in ('submitted', 'reviewed')
    and intake.submitted_at is not null
    and intake.confirmation = true;

  if v_exact_intake_count <> 1 then
    raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENTS_INTAKE_NOT_ELIGIBLE';
  end if;

  select intake.*
  into v_intake
  from public.quote_request_intakes as intake
  where intake.quote_request_id = p_quote_request_id
    and intake.status in ('submitted', 'reviewed')
    and intake.submitted_at is not null
    and intake.confirmation = true
  for update;

  if not found or v_intake.draft_revision is null or v_intake.draft_revision <= 0 then
    raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENTS_INTAKE_NOT_ELIGIBLE';
  end if;

  select board.*
  into v_board
  from public.website_requirements_boards as board
  where board.website_work_context_id = p_website_work_context_id
  for update;

  v_board_exists := found;

  if v_board_exists then
    perform 1
    from public.website_requirements as requirement
    where requirement.requirements_board_id = v_board.requirements_board_id
    for update;
  end if;

  v_projected_sources := lws_internal.project_website_requirement_sources_v1(v_intake);
  v_snapshot_payload := lws_internal.website_requirements_snapshot_payload_v1(v_projected_sources);
  v_intake_sha256 := lws_internal.website_requirements_sha256_hex_v1(v_snapshot_payload::text);
  v_request_fingerprint := lws_internal.website_requirements_sha256_hex_v1(
    jsonb_build_array(
      p_quote_request_id,
      p_website_work_context_id,
      p_expected_board_revision,
      v_intake.id,
      v_intake.draft_revision,
      v_intake_sha256,
      1
    )::text
  );

  if v_board_exists then
    select sync_run.*
    into v_existing_command
    from public.website_requirement_sync_runs as sync_run
    where sync_run.requirements_board_id = v_board.requirements_board_id
      and sync_run.command_id = p_idempotency_key;

    if found then
      if v_existing_command.request_fingerprint <> v_request_fingerprint then
        raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENTS_IDEMPOTENCY_CONFLICT';
      end if;
      return v_existing_command.result;
    end if;

    select sync_run.*
    into v_existing_logical
    from public.website_requirement_sync_runs as sync_run
    where sync_run.requirements_board_id = v_board.requirements_board_id
      and sync_run.intake_id = v_intake.id
      and sync_run.intake_revision = v_intake.draft_revision
      and sync_run.intake_snapshot_sha256 = v_intake_sha256
      and sync_run.mapping_version = 1
    order by sync_run.created_at desc, sync_run.sync_run_id desc
    limit 1;

    if found and p_expected_board_revision = 0 and v_board.revision = 1 then
      return v_existing_logical.result;
    end if;

    if v_board.revision <> p_expected_board_revision then
      raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
    end if;

    if found then
      return (v_existing_logical.result - 'outcome' - 'replayed')
        || jsonb_build_object('outcome', 'REPLAYED', 'replayed', true);
    end if;
  else
    if p_expected_board_revision <> 0 then
      raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
    end if;
  end if;

  perform set_config('lws.website_requirement_command', 'on', true);
  perform set_config('lws.website_requirement_history_command', 'on', true);

  if v_board.requirements_board_id is null then
    v_board.requirements_board_id := extensions.gen_random_uuid();
    insert into public.website_requirements_boards(
      requirements_board_id,
      website_work_context_id,
      quote_request_id,
      sync_state,
      mapping_version,
      current_intake_id,
      current_intake_revision,
      current_intake_snapshot_sha256,
      revision,
      created_by
    ) values (
      v_board.requirements_board_id,
      p_website_work_context_id,
      p_quote_request_id,
      'CURRENT',
      1,
      v_intake.id,
      v_intake.draft_revision,
      v_intake_sha256,
      1,
      v_operator.operator_id
    )
    returning * into v_board;
  end if;

  for v_source in
    select value
    from jsonb_array_elements(v_projected_sources) as source_rows(value)
  loop
    v_source_key := v_source->>'source_key';
    v_title := v_source->>'title';
    v_category := v_source->>'category';
    v_linked_page_or_module := nullif(v_source->>'linked_page_or_module', 'null');
    v_source_value := v_source->'source_value';
    v_source_value_sha256 := lws_internal.website_requirements_sha256_hex_v1(v_source_value::text);
    v_source_reference := lws_internal.website_requirements_safe_source_reference_v1(
      v_intake.id,
      v_intake.draft_revision,
      v_intake.submitted_at,
      v_source_key,
      v_source_value_sha256
    );
    v_description := lws_internal.website_requirements_safe_description_v1(v_source_key, v_source_value);
    v_definition := jsonb_build_object(
      'title', v_title,
      'description', v_description,
      'category', v_category,
      'linked_page_or_module', to_jsonb(v_linked_page_or_module),
      'required', true,
      'completion_mode', 'OPERATOR',
      'completion_rule_key', null,
      'completion_rule_version', null,
      'source_reference', v_source_reference
    );

    select requirement.*
    into v_requirement
    from public.website_requirements as requirement
    where requirement.requirements_board_id = v_board.requirements_board_id
      and requirement.source_key = v_source_key
    order by requirement.created_at desc, requirement.requirement_id desc
    limit 1;

    if not found then
      v_requirement_id := extensions.gen_random_uuid();
      insert into public.website_requirements(
        requirement_id,
        requirements_board_id,
        website_work_context_id,
        quote_request_id,
        source_key,
        source_reference,
        source_value_sha256,
        item_number,
        sort_order,
        title,
        description,
        category,
        linked_page_or_module,
        status,
        completion_mode,
        completion_rule_key,
        completion_rule_version,
        source_review_state,
        required,
        verification_result,
        revision
      ) values (
        v_requirement_id,
        v_board.requirements_board_id,
        p_website_work_context_id,
        p_quote_request_id,
        v_source_key,
        v_source_reference,
        v_source_value_sha256,
        (select ordinality::integer from jsonb_array_elements(v_projected_sources) with ordinality as src(value, ordinality) where value->>'source_key' = v_source_key),
        (select ordinality::integer from jsonb_array_elements(v_projected_sources) with ordinality as src(value, ordinality) where value->>'source_key' = v_source_key),
        v_title,
        v_description,
        v_category,
        v_linked_page_or_module,
        'PENDING',
        'OPERATOR',
        null,
        null,
        'CURRENT',
        true,
        'UNKNOWN',
        1
      );

      insert into public.website_requirement_events(
        requirements_board_id,
        website_work_context_id,
        quote_request_id,
        requirement_id,
        event_type,
        actor_id,
        command_id,
        prior_revision,
        new_revision,
        metadata
      ) values (
        v_board.requirements_board_id,
        p_website_work_context_id,
        p_quote_request_id,
        v_requirement_id,
        'WEBSITE_REQUIREMENT_SYNC_CREATE',
        v_actor_id,
        p_idempotency_key,
        null,
        1,
        jsonb_build_object(
          'action', 'CREATE',
          'source_key', v_source_key,
          'proposed_source_value_sha256', v_source_value_sha256
        )
      );

      v_created_count := v_created_count + 1;
      v_proposed_changes := v_proposed_changes || jsonb_build_array(
        jsonb_build_object(
          'source_key', v_source_key,
          'action', 'CREATE',
          'requirement_id', null,
          'previous_source_value_sha256', null,
          'proposed_source_value_sha256', v_source_value_sha256,
          'proposed_definition', v_definition
        )
      );
      continue;
    end if;

    v_previous_source_value_sha256 := v_requirement.source_value_sha256;

    if v_requirement.source_review_state = 'RETIRED' then
      update public.website_requirements
      set
        source_reference = v_source_reference,
        source_value_sha256 = v_source_value_sha256,
        title = v_title,
        description = v_description,
        category = v_category,
        linked_page_or_module = v_linked_page_or_module,
        status = 'PENDING',
        completion_mode = 'OPERATOR',
        completion_rule_key = null,
        completion_rule_version = null,
        source_review_state = 'CURRENT',
        required = true,
        started_at = null,
        completed_at = null,
        completed_by = null,
        evidence_summary = null,
        verification_result = 'UNKNOWN',
        blocked_reason = null,
        revision = v_requirement.revision + 1,
        updated_at = clock_timestamp()
      where requirement_id = v_requirement.requirement_id;

      insert into public.website_requirement_events(
        requirements_board_id,
        website_work_context_id,
        quote_request_id,
        requirement_id,
        event_type,
        actor_id,
        command_id,
        prior_revision,
        new_revision,
        metadata
      ) values (
        v_board.requirements_board_id,
        p_website_work_context_id,
        p_quote_request_id,
        v_requirement.requirement_id,
        'WEBSITE_REQUIREMENT_SYNC_REVIVE',
        v_actor_id,
        p_idempotency_key,
        v_requirement.revision,
        v_requirement.revision + 1,
        jsonb_build_object(
          'action', 'REVIVE',
          'source_key', v_source_key,
          'previous_source_value_sha256', v_previous_source_value_sha256,
          'proposed_source_value_sha256', v_source_value_sha256
        )
      );

      v_update_safe_count := v_update_safe_count + 1;
      v_revived_count := v_revived_count + 1;
      v_proposed_changes := v_proposed_changes || jsonb_build_array(
        jsonb_build_object(
          'source_key', v_source_key,
          'action', 'REVIVE',
          'requirement_id', v_requirement.requirement_id,
          'previous_source_value_sha256', v_previous_source_value_sha256,
          'proposed_source_value_sha256', v_source_value_sha256,
          'proposed_definition', v_definition
        )
      );
      continue;
    end if;

    if v_requirement.source_value_sha256 = v_source_value_sha256 then
      if v_source_key <> v_skip_unchanged_source_key then
        v_unchanged_count := v_unchanged_count + 1;
        v_proposed_changes := v_proposed_changes || jsonb_build_array(
          jsonb_build_object(
            'source_key', v_source_key,
            'action', 'UNCHANGED',
            'requirement_id', v_requirement.requirement_id,
            'previous_source_value_sha256', v_requirement.source_value_sha256,
            'proposed_source_value_sha256', v_source_value_sha256,
            'proposed_definition', null
          )
        );
      end if;
      continue;
    end if;

    if v_requirement.status = 'PENDING' and v_requirement.source_review_state = 'CURRENT' then
      update public.website_requirements
      set
        source_reference = v_source_reference,
        source_value_sha256 = v_source_value_sha256,
        title = v_title,
        description = v_description,
        category = v_category,
        linked_page_or_module = v_linked_page_or_module,
        required = true,
        revision = v_requirement.revision + 1,
        updated_at = clock_timestamp()
      where requirement_id = v_requirement.requirement_id;

      insert into public.website_requirement_events(
        requirements_board_id,
        website_work_context_id,
        quote_request_id,
        requirement_id,
        event_type,
        actor_id,
        command_id,
        prior_revision,
        new_revision,
        metadata
      ) values (
        v_board.requirements_board_id,
        p_website_work_context_id,
        p_quote_request_id,
        v_requirement.requirement_id,
        'WEBSITE_REQUIREMENT_SYNC_UPDATE_SAFE',
        v_actor_id,
        p_idempotency_key,
        v_requirement.revision,
        v_requirement.revision + 1,
        jsonb_build_object(
          'action', 'UPDATE_SAFE',
          'source_key', v_source_key,
          'previous_source_value_sha256', v_previous_source_value_sha256,
          'proposed_source_value_sha256', v_source_value_sha256
        )
      );

      v_update_safe_count := v_update_safe_count + 1;
      v_proposed_changes := v_proposed_changes || jsonb_build_array(
        jsonb_build_object(
          'source_key', v_source_key,
          'action', 'UPDATE_SAFE',
          'requirement_id', v_requirement.requirement_id,
          'previous_source_value_sha256', v_previous_source_value_sha256,
          'proposed_source_value_sha256', v_source_value_sha256,
          'proposed_definition', v_definition
        )
      );
    else
      update public.website_requirements
      set
        source_review_state = 'CHANGE_PENDING',
        revision = v_requirement.revision + 1,
        updated_at = clock_timestamp()
      where requirement_id = v_requirement.requirement_id;

      insert into public.website_requirement_events(
        requirements_board_id,
        website_work_context_id,
        quote_request_id,
        requirement_id,
        event_type,
        actor_id,
        command_id,
        prior_revision,
        new_revision,
        metadata
      ) values (
        v_board.requirements_board_id,
        p_website_work_context_id,
        p_quote_request_id,
        v_requirement.requirement_id,
        'WEBSITE_REQUIREMENT_SYNC_CHANGE_PENDING',
        v_actor_id,
        p_idempotency_key,
        v_requirement.revision,
        v_requirement.revision + 1,
        jsonb_build_object(
          'action', 'CHANGE_PENDING',
          'source_key', v_source_key,
          'previous_source_value_sha256', v_previous_source_value_sha256,
          'proposed_source_value_sha256', v_source_value_sha256
        )
      );

      v_change_pending_count := v_change_pending_count + 1;
      v_proposed_changes := v_proposed_changes || jsonb_build_array(
        jsonb_build_object(
          'source_key', v_source_key,
          'action', 'CHANGE_PENDING',
          'requirement_id', v_requirement.requirement_id,
          'previous_source_value_sha256', v_previous_source_value_sha256,
          'proposed_source_value_sha256', v_source_value_sha256,
          'proposed_definition', v_definition
        )
      );
    end if;
  end loop;

  for v_requirement in
    select requirement.*
    from public.website_requirements as requirement
    where requirement.requirements_board_id = v_board.requirements_board_id
      and requirement.source_review_state <> 'RETIRED'
      and not exists (
        select 1
        from jsonb_array_elements(v_projected_sources) as source_rows(value)
        where value->>'source_key' = requirement.source_key
      )
    order by requirement.source_key
  loop
    if v_requirement.status = 'PENDING' then
      update public.website_requirements
      set
        source_review_state = 'RETIRED',
        required = false,
        revision = v_requirement.revision + 1,
        updated_at = clock_timestamp()
      where requirement_id = v_requirement.requirement_id;

      insert into public.website_requirement_events(
        requirements_board_id,
        website_work_context_id,
        quote_request_id,
        requirement_id,
        event_type,
        actor_id,
        command_id,
        prior_revision,
        new_revision,
        metadata
      ) values (
        v_board.requirements_board_id,
        p_website_work_context_id,
        p_quote_request_id,
        v_requirement.requirement_id,
        'WEBSITE_REQUIREMENT_SYNC_RETIRE',
        v_actor_id,
        p_idempotency_key,
        v_requirement.revision,
        v_requirement.revision + 1,
        jsonb_build_object(
          'action', 'RETIRE',
          'source_key', v_requirement.source_key,
          'previous_source_value_sha256', v_requirement.source_value_sha256
        )
      );

      v_retired_count := v_retired_count + 1;
      v_proposed_changes := v_proposed_changes || jsonb_build_array(
        jsonb_build_object(
          'source_key', v_requirement.source_key,
          'action', 'RETIRE',
          'requirement_id', v_requirement.requirement_id,
          'previous_source_value_sha256', v_requirement.source_value_sha256,
          'proposed_source_value_sha256', null,
          'proposed_definition', null
        )
      );
    else
      update public.website_requirements
      set
        source_review_state = 'REMOVAL_PENDING',
        revision = v_requirement.revision + 1,
        updated_at = clock_timestamp()
      where requirement_id = v_requirement.requirement_id;

      insert into public.website_requirement_events(
        requirements_board_id,
        website_work_context_id,
        quote_request_id,
        requirement_id,
        event_type,
        actor_id,
        command_id,
        prior_revision,
        new_revision,
        metadata
      ) values (
        v_board.requirements_board_id,
        p_website_work_context_id,
        p_quote_request_id,
        v_requirement.requirement_id,
        'WEBSITE_REQUIREMENT_SYNC_REMOVAL_PENDING',
        v_actor_id,
        p_idempotency_key,
        v_requirement.revision,
        v_requirement.revision + 1,
        jsonb_build_object(
          'action', 'REMOVAL_PENDING',
          'source_key', v_requirement.source_key,
          'previous_source_value_sha256', v_requirement.source_value_sha256
        )
      );

      v_removal_pending_count := v_removal_pending_count + 1;
      v_proposed_changes := v_proposed_changes || jsonb_build_array(
        jsonb_build_object(
          'source_key', v_requirement.source_key,
          'action', 'REMOVAL_PENDING',
          'requirement_id', v_requirement.requirement_id,
          'previous_source_value_sha256', v_requirement.source_value_sha256,
          'proposed_source_value_sha256', null,
          'proposed_definition', null
        )
      );
    end if;
  end loop;

  v_review_required := (v_change_pending_count + v_removal_pending_count) > 0;
  v_board_sync_state := case when v_review_required then 'REVIEW_REQUIRED' else 'CURRENT' end;

  if p_expected_board_revision = 0 then
    v_board_revision := 1;
  else
    v_board_revision := v_board.revision + 1;
    update public.website_requirements_boards
    set
      sync_state = v_board_sync_state,
      mapping_version = 1,
      current_intake_id = v_intake.id,
      current_intake_revision = v_intake.draft_revision,
      current_intake_snapshot_sha256 = v_intake_sha256,
      revision = v_board_revision,
      updated_at = clock_timestamp()
    where requirements_board_id = v_board.requirements_board_id;
  end if;

  v_sync_run_id := extensions.gen_random_uuid();
  v_result := jsonb_build_object(
    'contract_version', 1,
    'outcome', case when v_review_required then 'REVIEW_REQUIRED' else 'SYNCED' end,
    'quote_request_id', p_quote_request_id,
    'website_work_context_id', p_website_work_context_id,
    'requirements_board_id', v_board.requirements_board_id,
    'board_revision', v_board_revision,
    'intake_id', v_intake.id,
    'intake_revision', v_intake.draft_revision,
    'intake_sha256', v_intake_sha256,
    'mapping_version', 1,
    'sync_run_id', v_sync_run_id,
    'replayed', false,
    'review_required', v_review_required,
    'counts', jsonb_build_object(
      'created', v_created_count,
      'updated', v_update_safe_count,
      'unchanged', v_unchanged_count,
      'retired', v_retired_count,
      'change_pending', v_change_pending_count,
      'removal_pending', v_removal_pending_count,
      'revived', v_revived_count
    )
  );

  select coalesce(jsonb_agg(change_row order by change_row->>'source_key'), '[]'::jsonb)
  into v_proposed_changes
  from jsonb_array_elements(v_proposed_changes) as source_rows(change_row);

  insert into public.website_requirement_sync_runs(
    sync_run_id,
    requirements_board_id,
    website_work_context_id,
    quote_request_id,
    intake_id,
    intake_revision,
    intake_snapshot_sha256,
    mapping_version,
    request_fingerprint,
    created_count,
    updated_count,
    retired_count,
    review_required_count,
    actor_id,
    command_id,
    result,
    proposed_changes
  ) values (
    v_sync_run_id,
    v_board.requirements_board_id,
    p_website_work_context_id,
    p_quote_request_id,
    v_intake.id,
    v_intake.draft_revision,
    v_intake_sha256,
    1,
    v_request_fingerprint,
    v_created_count,
    v_update_safe_count,
    v_retired_count,
    v_change_pending_count + v_removal_pending_count,
    v_actor_id,
    p_idempotency_key,
    v_result,
    v_proposed_changes
  );

  insert into public.website_requirement_events(
    requirements_board_id,
    website_work_context_id,
    quote_request_id,
    requirement_id,
    event_type,
    actor_id,
    command_id,
    prior_revision,
    new_revision,
    metadata
  ) values (
    v_board.requirements_board_id,
    p_website_work_context_id,
    p_quote_request_id,
    null,
    'WEBSITE_REQUIREMENTS_SYNCED',
    v_actor_id,
    p_idempotency_key,
    case when p_expected_board_revision = 0 then null else p_expected_board_revision end,
    v_board_revision,
    jsonb_build_object(
      'intake_id', v_intake.id,
      'intake_revision', v_intake.draft_revision,
      'intake_snapshot_sha256', v_intake_sha256,
      'mapping_version', 1,
      'counts', v_result->'counts',
      'review_required', v_review_required
    )
  );

  perform set_config('lws.website_requirement_history_command', '', true);
  perform set_config('lws.website_requirement_command', '', true);

  return v_result;
end;
$$;

revoke all on function lws_internal.website_requirements_sha256_hex_v1(text)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_hash16_v1(text)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_normalize_text_v1(text)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_normalize_text_array_v1(text[])
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_normalize_catalog_array_v1(text[], text[])
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_normalize_language_v1(text)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_normalize_custom_pages_v1(text)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_is_relevant_jsonb_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_put_text_v1(jsonb, text, text)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_put_array_v1(jsonb, text, text[])
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_put_boolean_v1(jsonb, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_put_number_v1(jsonb, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_put_jsonb_v1(jsonb, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_append_source_v1(jsonb, text, text, text, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_safe_source_reference_v1(uuid, bigint, timestamptz, text, text)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_safe_description_v1(text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_jsonb_exact_keys_v1(jsonb, text[])
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_source_reference_shape_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_proposed_definition_shape_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_proposed_changes_shape_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_snapshot_payload_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.project_website_requirement_sources_v1(public.quote_request_intakes)
  from public, anon, authenticated, service_role;

revoke all on function public.sync_website_requirements_from_intake_v1(uuid, uuid, bigint, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_website_requirements_from_intake_v1(uuid, uuid, bigint, uuid)
  to authenticated;
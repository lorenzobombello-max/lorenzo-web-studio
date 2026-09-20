begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = public, lws_internal, extensions;

select no_plan();

create function pg_temp.fixture_uuid(p_value text)
returns uuid
language sql
immutable
set search_path = pg_catalog
as $$
  select (
    substr(md5(p_value), 1, 8) || '-' ||
    substr(md5(p_value), 9, 4) || '-4' ||
    substr(md5(p_value), 14, 3) || '-8' ||
    substr(md5(p_value), 18, 3) || '-' ||
    substr(md5(p_value), 21, 12)
  )::uuid
$$;

create function pg_temp.sha256_hex(p_value text)
returns text
language sql
immutable
set search_path = extensions, pg_catalog
as $$
  select encode(extensions.digest(convert_to(coalesce(p_value, ''), 'UTF8'), 'sha256'), 'hex')
$$;

create function pg_temp.jsonb_sha256(p_value jsonb)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select pg_temp.sha256_hex(coalesce(p_value, 'null'::jsonb)::text)
$$;

create function pg_temp.hash16(p_value text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select substr(pg_temp.sha256_hex(lower(coalesce(p_value, ''))), 1, 16)
$$;

create function pg_temp.normalize_text_contract_v1(p_value text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select nullif(
    btrim(
      replace(
        replace(
          replace(coalesce(p_value, ''), chr(7), ''),
          E'\r\n', E'\n'
        ),
        E'\r', E'\n'
      )
    ),
    ''
  )
$$;

create function pg_temp.normalize_free_text_array_contract_v1(p_values text[])
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select distinct pg_temp.normalize_text_contract_v1(value) as value
    from unnest(coalesce(p_values, array[]::text[])) as entry(value)
  )
  select coalesce(
    jsonb_agg(value order by lower(value) collate "C", value collate "C"),
    '[]'::jsonb
  )
  from normalized
  where value is not null
$$;

create function pg_temp.catalog_array_contract_v1(p_values text[], p_catalog text[])
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(catalog.value order by catalog.ordinality), '[]'::jsonb)
  from unnest(coalesce(p_catalog, array[]::text[])) with ordinality as catalog(value, ordinality)
  where catalog.value = any(coalesce(p_values, array[]::text[]))
$$;

create function pg_temp.normalize_language_contract_v1(p_value text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case replace(lower(coalesce(pg_temp.normalize_text_contract_v1(p_value), '')), '_', '-')
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
    else replace(lower(coalesce(pg_temp.normalize_text_contract_v1(p_value), '')), '_', '-')
  end
$$;

create function pg_temp.safe_source_reference_v1(
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

create function pg_temp.safe_description_v1(p_source_key text, p_source_value jsonb)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_description text := 'Klantvraag uit bevestigde Website-intake. Bron: '
    || p_source_key || '. Details: ' || coalesce(p_source_value::text, 'null');
begin
  if char_length(v_description) <= 1200 then
    return v_description;
  end if;

  return left(v_description, 1187) || '... [verkort]';
end;
$$;

create function pg_temp.jsonb_keys_sorted_v1(p_value jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(key_name order by key_name), '[]'::jsonb)
  from jsonb_object_keys(coalesce(p_value, '{}'::jsonb)) as keys(key_name)
$$;

create function pg_temp.jsonb_array_sorted_v1(p_value jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(value order by value), '[]'::jsonb)
  from jsonb_array_elements_text(coalesce(p_value, '[]'::jsonb)) as entry(value)
$$;

create function pg_temp.request_fingerprint_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_expected_board_revision bigint,
  p_intake_id uuid,
  p_intake_revision bigint,
  p_intake_sha256 text,
  p_mapping_version integer
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select pg_temp.sha256_hex(
    jsonb_build_array(
      p_quote_request_id,
      p_website_work_context_id,
      p_expected_board_revision,
      p_intake_id,
      p_intake_revision,
      p_intake_sha256,
      p_mapping_version
    )::text
  )
$$;

create function pg_temp.set_sync_claims_v1(p_subject uuid, p_aal text)
returns void
language sql
set search_path = pg_catalog
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_subject, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  )::text
$$;

create function pg_temp.call_sync_website_requirements_from_intake_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_expected_board_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_result jsonb;
  v_message text;
  v_detail text;
  v_hint text;
begin
  if to_regprocedure(
    'public.sync_website_requirements_from_intake_v1(uuid,uuid,bigint,uuid)'
  ) is null then
    return jsonb_build_object(
      'missing_contract', true,
      'signature', 'public.sync_website_requirements_from_intake_v1(uuid,uuid,bigint,uuid)',
      'sqlstate', '42883',
      'message', 'undefined_function'
    );
  end if;

  execute 'select public.sync_website_requirements_from_intake_v1($1, $2, $3, $4)'
    into v_result
    using p_quote_request_id, p_website_work_context_id, p_expected_board_revision, p_idempotency_key;

  return v_result;
exception
  when others then
    get stacked diagnostics
      v_message = message_text,
      v_detail = pg_exception_detail,
      v_hint = pg_exception_hint;
    return jsonb_build_object(
      'missing_contract', false,
      'sqlstate', sqlstate,
      'message', v_message,
      'detail', v_detail,
      'hint', v_hint
    );
end;
$$;

create function pg_temp.sync_run_proposed_changes_v1(p_sync_run_id uuid)
returns jsonb
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_result jsonb;
begin
  if p_sync_run_id is null then
    return null;
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'website_requirement_sync_runs'
      and column_name = 'proposed_changes'
  ) then
    return null;
  end if;

  execute
    'select proposed_changes from public.website_requirement_sync_runs where sync_run_id = $1'
    into v_result
    using p_sync_run_id;

  return v_result;
end;
$$;

create function pg_temp.insert_sync_run_fixture_v1(
  p_sync_run_id uuid,
  p_requirements_board_id uuid,
  p_website_work_context_id uuid,
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_intake_revision bigint,
  p_intake_sha256 text,
  p_mapping_version integer,
  p_request_fingerprint text,
  p_actor_id text,
  p_command_id uuid,
  p_result jsonb,
  p_proposed_changes jsonb
)
returns void
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  perform set_config('lws.website_requirement_history_command', 'on', true);

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'website_requirement_sync_runs'
      and column_name = 'proposed_changes'
  ) then
    execute $insert$
      insert into public.website_requirement_sync_runs (
        sync_run_id, requirements_board_id, website_work_context_id, quote_request_id,
        intake_id, intake_revision, intake_snapshot_sha256, mapping_version,
        request_fingerprint, created_count, updated_count, retired_count,
        review_required_count, actor_id, command_id, result, proposed_changes
      ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
    $insert$
    using
      p_sync_run_id,
      p_requirements_board_id,
      p_website_work_context_id,
      p_quote_request_id,
      p_intake_id,
      p_intake_revision,
      p_intake_sha256,
      p_mapping_version,
      p_request_fingerprint,
      coalesce((p_result->'counts'->>'created')::integer, 0),
      coalesce((p_result->'counts'->>'updated')::integer, 0),
      coalesce((p_result->'counts'->>'retired')::integer, 0),
      coalesce((p_result->'counts'->>'change_pending')::integer, 0) + coalesce((p_result->'counts'->>'removal_pending')::integer, 0),
      p_actor_id,
      p_command_id,
      p_result,
      coalesce(p_proposed_changes, '[]'::jsonb);
  else
    insert into public.website_requirement_sync_runs (
      sync_run_id, requirements_board_id, website_work_context_id, quote_request_id,
      intake_id, intake_revision, intake_snapshot_sha256, mapping_version,
      request_fingerprint, created_count, updated_count, retired_count,
      review_required_count, actor_id, command_id, result
    ) values (
      p_sync_run_id, p_requirements_board_id, p_website_work_context_id, p_quote_request_id,
      p_intake_id, p_intake_revision, p_intake_sha256, p_mapping_version,
      p_request_fingerprint,
      coalesce((p_result->'counts'->>'created')::integer, 0),
      coalesce((p_result->'counts'->>'updated')::integer, 0),
      coalesce((p_result->'counts'->>'retired')::integer, 0),
      coalesce((p_result->'counts'->>'change_pending')::integer, 0) + coalesce((p_result->'counts'->>'removal_pending')::integer, 0),
      p_actor_id,
      p_command_id,
      p_result
    );
  end if;

  perform set_config('lws.website_requirement_history_command', '', true);
end;
$$;

select has_function(
  'public',
  'sync_website_requirements_from_intake_v1',
  array['uuid', 'uuid', 'bigint', 'uuid'],
  'Task 2 sync RPC exists with the exact signature'
);
select has_column(
  'public', 'website_requirement_sync_runs', 'proposed_changes',
  'Task 2 adds the immutable proposed_changes column'
);
select col_type_is(
  'public', 'website_requirement_sync_runs', 'proposed_changes', 'jsonb',
  'proposed_changes uses jsonb'
);
select col_not_null(
  'public', 'website_requirement_sync_runs', 'proposed_changes',
  'proposed_changes is required'
);

select ok(
  case when to_regprocedure('public.sync_website_requirements_from_intake_v1(uuid,uuid,bigint,uuid)') is null then false
    else has_function_privilege(
      'authenticated',
      'public.sync_website_requirements_from_intake_v1(uuid,uuid,bigint,uuid)',
      'execute'
    )
      and not has_function_privilege(
        'anon',
        'public.sync_website_requirements_from_intake_v1(uuid,uuid,bigint,uuid)',
        'execute'
      )
      and not has_function_privilege(
        'service_role',
        'public.sync_website_requirements_from_intake_v1(uuid,uuid,bigint,uuid)',
        'execute'
      )
  end,
  'only authenticated humans may execute the Task 2 sync RPC'
);

select is(
  pg_temp.normalize_text_contract_v1('  Premium' || chr(7) || ' websites' || E'\r\n' || 'voor scale-ups  '),
  'Premium websites' || E'\n' || 'voor scale-ups',
  'text normalization trims, strips control characters, and normalizes line endings'
);
select is(
  pg_temp.normalize_free_text_array_contract_v1(array[' Partner Portaal ', 'Case Studies', 'partner portaal']),
  '["Case Studies","Partner Portaal","partner portaal"]'::jsonb,
  'free-text arrays normalize empties and sort deterministically'
);
select is(
  pg_temp.normalize_language_contract_v1(' Frans '),
  'fr',
  'language aliases normalize to canonical codes'
);
select is(
  pg_temp.hash16('Case Studies'),
  substr(pg_temp.sha256_hex('case studies'), 1, 16),
  'dynamic page and integration keys derive from lowercase normalized names'
);

insert into auth.users(id, email) values
  (pg_temp.fixture_uuid('wris-owner-user'), 'wris-owner@example.test'),
  (pg_temp.fixture_uuid('wris-manager-user'), 'wris-manager@example.test'),
  (pg_temp.fixture_uuid('wris-operator-user'), 'wris-operator@example.test'),
  (pg_temp.fixture_uuid('wris-inactive-user'), 'wris-inactive@example.test');

set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values
  (pg_temp.fixture_uuid('wris-owner-operator'), pg_temp.fixture_uuid('wris-owner-user'), 'WRIS Owner', 'owner', 'ACTIVE'),
  (pg_temp.fixture_uuid('wris-manager-operator'), pg_temp.fixture_uuid('wris-manager-user'), 'WRIS Manager', 'operations_manager', 'ACTIVE'),
  (pg_temp.fixture_uuid('wris-operator-operator'), pg_temp.fixture_uuid('wris-operator-user'), 'WRIS Operator', 'operator', 'ACTIVE'),
  (pg_temp.fixture_uuid('wris-inactive-operator'), pg_temp.fixture_uuid('wris-inactive-user'), 'WRIS Disabled', 'owner', 'DISABLED');
set local session_replication_role = origin;

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  created_at, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  (
    pg_temp.fixture_uuid('wris-quote-initial-full'),
    'LWS-AAN-2099-9201', 'production', 'website', null,
    '2099-01-01T09:00:00Z', 'WRIS Initial Full', 'wris-initial@example.test',
    'business', 'Meer dan EUR 6.000', 'flexible',
    'Synthetic Website intake for full source coverage.', true, 'approved'
  ),
  (
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'LWS-AAN-2099-9202', 'production', 'website', null,
    '2099-01-01T09:05:00Z', 'WRIS Resync Delta', 'wris-delta@example.test',
    'business', 'Meer dan EUR 6.000', 'flexible',
    'Synthetic Website intake for resync action coverage.', true, 'approved'
  ),
  (
    pg_temp.fixture_uuid('wris-quote-replay'),
    'LWS-AAN-2099-9203', 'production', 'website', null,
    '2099-01-01T09:10:00Z', 'WRIS Replay', 'wris-replay@example.test',
    'business', 'Meer dan EUR 6.000', 'flexible',
    'Synthetic Website intake for replay coverage.', true, 'approved'
  ),
  (
    pg_temp.fixture_uuid('wris-quote-unknown-feature'),
    'LWS-AAN-2099-9204', 'production', 'website', null,
    '2099-01-01T09:15:00Z', 'WRIS Unknown Feature', 'wris-unknown@example.test',
    'business', 'Meer dan EUR 6.000', 'flexible',
    'Synthetic Website intake with unsupported requested feature.', true, 'approved'
  ),
  (
    pg_temp.fixture_uuid('wris-quote-nonproduction'),
    'LWS-AAN-2099-9205', 'internal_e2e', 'website', null,
    '2099-01-01T09:20:00Z', 'WRIS Internal E2E', 'wris-internal@example.test',
    'business', 'Meer dan EUR 6.000', 'flexible',
    'Synthetic internal-e2e Website intake.', true, 'approved'
  ),
  (
    pg_temp.fixture_uuid('wris-quote-nonwebsite'),
    'LWS-AAN-2099-9206', 'production', 'slimme_documentenflow', 'start',
    '2099-01-01T09:25:00Z', 'WRIS Non Website', 'wris-sdf@example.test',
    null, null, null,
    'Synthetic non-Website dossier.', true, 'approved'
  ),
  (
    pg_temp.fixture_uuid('wris-quote-unsubmitted'),
    'LWS-AAN-2099-9207', 'production', 'website', null,
    '2099-01-01T09:30:00Z', 'WRIS Unsubmitted', 'wris-unsubmitted@example.test',
    'business', 'Meer dan EUR 6.000', 'flexible',
    'Synthetic Website intake still in progress.', true, 'approved'
  ),
  (
    pg_temp.fixture_uuid('wris-quote-unconfirmed'),
    'LWS-AAN-2099-9208', 'production', 'website', null,
    '2099-01-01T09:35:00Z', 'WRIS Unconfirmed', 'wris-unconfirmed@example.test',
    'business', 'Meer dan EUR 6.000', 'flexible',
    'Synthetic Website intake not confirmed.', true, 'approved'
  );

set local session_replication_role = replica;
insert into public.quote_request_intakes(
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  started_at, submitted_at, reviewed_at,
  business_description, target_audience, has_existing_website,
  existing_website_url, elements_to_keep, improvement_areas, website_goals,
  primary_conversion_goal, requested_pages, other_pages, requested_features,
  shop_required, shop_details, booking_required, booking_details, languages,
  design_styles, brand_status, logo_status, brand_colors, inspiration_sites,
  disliked_styles, content_status, image_status, image_support, domain_status,
  domain_name, hosting_status, hosting_support, maintenance_interest,
  seo_priority, seo_keywords, social_channels, integrations, deadline_date,
  deadline_reason, budget_confirmed, budget_update_category, budget_notes,
  priorities, additional_notes, confirmation
) values
  (
    pg_temp.fixture_uuid('wris-intake-initial-full'),
    pg_temp.fixture_uuid('wris-quote-initial-full'),
    'submitted', repeat('1', 64), '2099-01-03T00:00:00Z',
    '2099-01-01T10:00:00Z', '2099-01-01T11:00:00Z', null,
    '  Premium' || chr(7) || ' websites' || E'\r\n' || 'voor scale-ups  ',
    '  SaaS scale-ups in de Benelux  ', true,
    'https://legacy.example.test', 'Kennisbank; FAQ', 'Snellere navigatie',
    array['other', 'generate_leads', 'appointments', 'sell_products', 'portfolio'],
    'Plan een demo',
    array['gallery', 'home', 'jobs', 'services', 'contact', 'blog', 'products', 'shop', 'about', 'faq', 'portfolio', 'pricing', 'team', 'quote_request', 'reservations', 'reviews'],
    ' Partner Portaal ;' || E'\r\n' || 'Case Studies' || E'\n' || 'partner portaal',
    array[
      'online_payment_other', 'search', 'contact_form', 'newsletter', 'multilingual',
      'google_maps', 'reservations', 'shop', 'downloads', 'online_payment', 'reviews',
      'social_links', 'quote_form', 'whatsapp', 'customer_login', 'gallery',
      'appointments', 'other', 'unsure', 'online_payment_deposit',
      'online_payment_products', 'online_payment_reservations',
      'online_payment_appointments', 'online_payment_services',
      'online_payment_registrations'
    ],
    true,
    '{"approx_product_count":48,"complex_product_count":6,"payment_provider_count":2,"shipping_scope":"advanced","categories":true,"online_payments":true,"shipping":true,"pickup":true,"pickup_scope":"scheduled","existing_catalog":true,"customer_accounts":true,"catalog_import":true,"erp_api":true}'::jsonb,
    true,
    '{"tier":"advanced","type":"appointments_and_reservations","existing_system":true,"existing_system_name":"Calendly","calendar_integration":true}'::jsonb,
    array['FRANS', ' Nederlands ', 'svenska'],
    array['technical', 'other', 'modern', 'playful'],
    'partial', 'needs_update', array['#112233', '#abcdef'],
    array['https://example-one.test', 'https://example-two.test'],
    'Te minimalistisch', 'partial', 'partial',
    array['stock_images', 'ai_images', 'optimize_existing'],
    'has_domain', 'example.test', 'has_hosting', 'advice', 'yes',
    'high', array['lead generatie', 'erp koppeling'],
    array['youtube', 'instagram', 'linkedin'],
    array['hubspot', 'HubSpot', 'exact online', 'Exact Online'],
    '2099-03-31', 'Lancering voor Q4-beurs', true, 'Meer dan EUR 6.000',
    'Budget in aparte commerciële stroom bevestigd.',
    array['differentiate', 'seo', 'fast_delivery', 'professional_appearance', 'other'],
    '  Launch vóór Q4' || E'\r\n' || 'met gated downloads.  ',
    true
  ),
  (
    pg_temp.fixture_uuid('wris-intake-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'submitted', repeat('2', 64), '2099-01-03T00:00:00Z',
    '2099-01-01T10:05:00Z', '2099-01-01T11:05:00Z', null,
    'Delta scope voor bestaand traject', 'Bestaande klanten', true,
    'https://delta.example.test', 'Homepage en support', 'Nieuwe CTA en snellere navigatie',
    array['generate_leads'], 'Vraag een intakegesprek', array['home'], null,
    array['contact_form', 'downloads'],
    false, null, false, null, array['nl'],
    array['business', 'modern'], 'complete', 'available', array['#112233'],
    array['https://delta-reference.test'], null,
    'complete', 'sufficient', array['optimize_existing'],
    null, null, 'has_hosting', 'yes', 'no',
    'basic', array['lead generatie'],
    array[]::text[], array[]::text[],
    null, null, true, 'Meer dan EUR 6.000', null,
    array['professional_appearance'], 'Behoud bestaande copy waar mogelijk.',
    true
  ),
  (
    pg_temp.fixture_uuid('wris-intake-replay'),
    pg_temp.fixture_uuid('wris-quote-replay'),
    'submitted', repeat('3', 64), '2099-01-03T00:00:00Z',
    '2099-01-01T10:10:00Z', '2099-01-01T11:10:00Z', null,
    'Replay scope', 'Bestaande klanten', true,
    'https://replay.example.test', 'Homepage', 'Nieuwe CTA',
    array['generate_leads'], 'Vraag een intakegesprek', array['home'], null,
    array['contact_form', 'downloads'],
    false, null, false, null, array['nl'],
    array['modern'], 'complete', 'available', array['#112233'],
    array['https://replay-reference.test'], null,
    'complete', 'sufficient', array['optimize_existing'],
    null, null, 'has_hosting', 'yes', 'no',
    'basic', array['lead generatie'],
    array[]::text[], array[]::text[],
    null, null, true, 'Meer dan EUR 6.000', null,
    array['professional_appearance'], 'Replay baseline.',
    true
  ),
  (
    pg_temp.fixture_uuid('wris-intake-unknown-feature'),
    pg_temp.fixture_uuid('wris-quote-unknown-feature'),
    'submitted', repeat('4', 64), '2099-01-03T00:00:00Z',
    '2099-01-01T10:15:00Z', '2099-01-01T11:15:00Z', null,
    'Unknown feature scope', 'Prospects', false,
    null, null, null, array['generate_leads'], 'Vraag een offerte', array['home'], null,
    array['invented_feature'], false, null, false, null, array['nl'],
    array['modern'], 'complete', 'available', array['#112233'],
    array[]::text[], null,
    'complete', 'sufficient', array['optimize_existing'],
    'has_domain', 'unknown-feature.example.test', 'has_hosting', 'yes', 'no',
    'basic', array[]::text[], array[]::text[], array[]::text[],
    null, null, true, 'Meer dan EUR 6.000', null,
    array['professional_appearance'], 'Unsupported feature contract fixture.',
    true
  ),
  (
    pg_temp.fixture_uuid('wris-intake-nonproduction'),
    pg_temp.fixture_uuid('wris-quote-nonproduction'),
    'submitted', repeat('5', 64), '2099-01-03T00:00:00Z',
    '2099-01-01T10:20:00Z', '2099-01-01T11:20:00Z', null,
    'Internal E2E scope', 'QA', false,
    null, null, null, array['generate_leads'], 'Vraag een demo', array['home'], null,
    array['contact_form'], false, null, false, null, array['nl'],
    array['modern'], 'complete', 'available', array['#112233'],
    array[]::text[], null,
    'complete', 'sufficient', array['optimize_existing'],
    'has_domain', 'internal-e2e.example.test', 'has_hosting', 'yes', 'no',
    'basic', array[]::text[], array[]::text[], array[]::text[],
    null, null, true, 'Meer dan EUR 6.000', null,
    array['professional_appearance'], 'Non-production contract fixture.',
    true
  ),
  (
    pg_temp.fixture_uuid('wris-intake-nonwebsite'),
    pg_temp.fixture_uuid('wris-quote-nonwebsite'),
    'submitted', repeat('6', 64), '2099-01-03T00:00:00Z',
    '2099-01-01T10:25:00Z', '2099-01-01T11:25:00Z', null,
    'SDF scope', 'Backoffice', false,
    null, null, null, array[]::text[], null, array[]::text[], null,
    array[]::text[], false, null, false, null, array['nl'],
    array[]::text[], null, null, array[]::text[], array[]::text[], null,
    null, null, array[]::text[], null, null, null, null, null,
    null, array[]::text[], array[]::text[], array[]::text[],
    null, null, true, null, null, array[]::text[], 'Non-website contract fixture.',
    true
  ),
  (
    pg_temp.fixture_uuid('wris-intake-unsubmitted'),
    pg_temp.fixture_uuid('wris-quote-unsubmitted'),
    'in_progress', repeat('7', 64), '2099-01-03T00:00:00Z',
    '2099-01-01T10:30:00Z', null, null,
    'In progress scope', 'Prospects', false,
    null, null, null, array['generate_leads'], 'Vraag een offerte', array['home'], null,
    array['contact_form'], false, null, false, null, array['nl'],
    array['modern'], 'complete', 'available', array['#112233'],
    array[]::text[], null,
    'complete', 'sufficient', array['optimize_existing'],
    'has_domain', 'in-progress.example.test', 'has_hosting', 'yes', 'no',
    'basic', array[]::text[], array[]::text[], array[]::text[],
    null, null, true, 'Meer dan EUR 6.000', null,
    array['professional_appearance'], 'Unsubmitted contract fixture.',
    false
  ),
  (
    pg_temp.fixture_uuid('wris-intake-unconfirmed'),
    pg_temp.fixture_uuid('wris-quote-unconfirmed'),
    'in_progress', repeat('8', 64), '2099-01-03T00:00:00Z',
    '2099-01-01T10:35:00Z', null, null,
    'Unconfirmed scope', 'Prospects', false,
    null, null, null, array['generate_leads'], 'Vraag een offerte', array['home'], null,
    array['contact_form'], false, null, false, null, array['nl'],
    array['modern'], 'complete', 'available', array['#112233'],
    array[]::text[], null,
    'complete', 'sufficient', array['optimize_existing'],
    'has_domain', 'unconfirmed.example.test', 'has_hosting', 'yes', 'no',
    'basic', array[]::text[], array[]::text[], array[]::text[],
    null, null, true, 'Meer dan EUR 6.000', null,
    array['professional_appearance'], 'Unconfirmed contract fixture.',
    false
  );

update public.quote_request_intakes
set
  primary_language = ' Nederlands ',
  additional_languages = array[' English ', 'FRANS', 'nederlands', 'Svenska', 'frans '],
  page_scope_details = '{"reviews":"complex","blog":"normal","jobs":"complex","jobs_application":"upload","gallery":"complex","search":"sitewide"}'::jsonb,
  quote_form_details = '{"file_uploads":true,"database_workflow":true,"automated_processing":true,"review_approval":true,"custom_logic":true,"form_count":3,"structure_scope":"complex"}'::jsonb,
  multilingual_details = '{"final_translations_supplied":false,"same_structure":true,"translation_required":true,"seo_per_language":true,"advanced_seo_research":true,"language_specific_integrations":true,"complex_scope":true}'::jsonb,
  download_details = '{"access":"private_documents"}'::jsonb,
  content_media_details = '{"copywriting_scope":"new_pages_and_reviews","copy_page_count":8,"image_work_scope":"new_and_edit_existing","paid_stock_handling":true,"branding_tier":"existing"}'::jsonb,
  newsletter_details = '{"scope":"existing_list_and_automation","analytics":"advanced","custom_integration":true}'::jsonb,
  hosting_maintenance_details = '{"maintenance_interest":"yes","details_maintenance_interest":"care_plus_requested","maintenance_plan":"care_plus","domain_service":"transfer_needed"}'::jsonb,
  deadline_details = '{"commercially_critical":true,"hard_deadline":true}'::jsonb,
  seo_details = '{"scope":"advanced","extra_language_seo":true,"advanced_language_seo":true}'::jsonb,
  budget_update_category_scheme = 'budget_guard_v2',
  budget_update_category_code = 'above_6000',
  draft_revision = 7
where id = pg_temp.fixture_uuid('wris-intake-initial-full');

update public.quote_request_intakes
set
  primary_language = 'nl',
  additional_languages = array[]::text[],
  brand_status = null,
  logo_status = null,
  brand_colors = array[]::text[],
  image_status = null,
  image_support = array[]::text[],
  page_scope_details = null,
  quote_form_details = '{"file_uploads":false,"database_workflow":false,"automated_processing":false,"review_approval":true,"custom_logic":false,"form_count":1,"structure_scope":"simple"}'::jsonb,
  multilingual_details = null,
  download_details = '{"access":"private_documents"}'::jsonb,
  content_media_details = '{"copywriting_scope":"existing_with_edits","copy_page_count":3}'::jsonb,
  newsletter_details = null,
  hosting_maintenance_details = '{"maintenance_interest":"no","maintenance_plan":"none"}'::jsonb,
  deadline_details = null,
  seo_details = '{"scope":"basic","extra_language_seo":false,"advanced_language_seo":false}'::jsonb,
  budget_update_category_scheme = 'budget_guard_v2',
  budget_update_category_code = 'above_6000',
  draft_revision = 9
where id = pg_temp.fixture_uuid('wris-intake-resync-delta');

update public.quote_request_intakes
set
  business_description = 'Delta scope voor bestaand traject',
  target_audience = 'Bestaande klanten',
  existing_website_url = 'https://delta.example.test',
  elements_to_keep = 'Homepage en support',
  improvement_areas = 'Nieuwe CTA en snellere navigatie',
  primary_conversion_goal = 'Vraag een intakegesprek',
  primary_language = 'nl',
  additional_languages = array[]::text[],
  design_styles = array['business', 'modern'],
  brand_status = null,
  logo_status = null,
  brand_colors = array[]::text[],
  inspiration_sites = array['https://delta-reference.test'],
  image_status = null,
  image_support = array[]::text[],
  quote_form_details = '{"file_uploads":false,"database_workflow":false,"automated_processing":false,"review_approval":true,"custom_logic":false,"form_count":1,"structure_scope":"simple"}'::jsonb,
  download_details = '{"access":"private_documents"}'::jsonb,
  content_media_details = '{"copywriting_scope":"existing_with_edits","copy_page_count":3}'::jsonb,
  seo_details = '{"scope":"basic","extra_language_seo":false,"advanced_language_seo":false}'::jsonb,
  budget_update_category_scheme = 'budget_guard_v2',
  budget_update_category_code = 'above_6000',
  additional_notes = 'Behoud bestaande copy waar mogelijk.',
  draft_revision = 11
where id = pg_temp.fixture_uuid('wris-intake-replay');

update public.quote_request_intakes
set
  primary_language = 'nl',
  additional_languages = array[]::text[],
  budget_update_category_scheme = 'budget_guard_v2',
  budget_update_category_code = 'above_6000',
  draft_revision = 5
where id in (
  pg_temp.fixture_uuid('wris-intake-unknown-feature'),
  pg_temp.fixture_uuid('wris-intake-nonproduction'),
  pg_temp.fixture_uuid('wris-intake-nonwebsite'),
  pg_temp.fixture_uuid('wris-intake-unsubmitted'),
  pg_temp.fixture_uuid('wris-intake-unconfirmed')
);
set local session_replication_role = origin;

set local session_replication_role = replica;
insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, commercially_released,
  concept_status, promoted_project_id, revision, created_by
) values
  (pg_temp.fixture_uuid('wris-concept-initial-full'), pg_temp.fixture_uuid('wris-quote-initial-full'), 'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1, pg_temp.fixture_uuid('wris-owner-operator')),
  (pg_temp.fixture_uuid('wris-concept-resync-delta'), pg_temp.fixture_uuid('wris-quote-resync-delta'), 'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1, pg_temp.fixture_uuid('wris-owner-operator')),
  (pg_temp.fixture_uuid('wris-concept-replay'), pg_temp.fixture_uuid('wris-quote-replay'), 'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1, pg_temp.fixture_uuid('wris-owner-operator')),
  (pg_temp.fixture_uuid('wris-concept-unknown-feature'), pg_temp.fixture_uuid('wris-quote-unknown-feature'), 'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1, pg_temp.fixture_uuid('wris-owner-operator')),
  (pg_temp.fixture_uuid('wris-concept-nonproduction'), pg_temp.fixture_uuid('wris-quote-nonproduction'), 'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1, pg_temp.fixture_uuid('wris-owner-operator')),
  (pg_temp.fixture_uuid('wris-concept-nonwebsite'), pg_temp.fixture_uuid('wris-quote-nonwebsite'), 'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1, pg_temp.fixture_uuid('wris-owner-operator')),
  (pg_temp.fixture_uuid('wris-concept-unsubmitted'), pg_temp.fixture_uuid('wris-quote-unsubmitted'), 'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1, pg_temp.fixture_uuid('wris-owner-operator')),
  (pg_temp.fixture_uuid('wris-concept-unconfirmed'), pg_temp.fixture_uuid('wris-quote-unconfirmed'), 'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1, pg_temp.fixture_uuid('wris-owner-operator'));

select set_config('lws.website_concept_command', 'on', true);
insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values
  (pg_temp.fixture_uuid('wris-context-initial-full'), pg_temp.fixture_uuid('wris-quote-initial-full'), pg_temp.fixture_uuid('wris-concept-initial-full'), null, 'PRE_PROJECT', 1),
  (pg_temp.fixture_uuid('wris-context-resync-delta'), pg_temp.fixture_uuid('wris-quote-resync-delta'), pg_temp.fixture_uuid('wris-concept-resync-delta'), null, 'PRE_PROJECT', 1),
  (pg_temp.fixture_uuid('wris-context-replay'), pg_temp.fixture_uuid('wris-quote-replay'), pg_temp.fixture_uuid('wris-concept-replay'), null, 'PRE_PROJECT', 1),
  (pg_temp.fixture_uuid('wris-context-unknown-feature'), pg_temp.fixture_uuid('wris-quote-unknown-feature'), pg_temp.fixture_uuid('wris-concept-unknown-feature'), null, 'PRE_PROJECT', 1),
  (pg_temp.fixture_uuid('wris-context-nonproduction'), pg_temp.fixture_uuid('wris-quote-nonproduction'), pg_temp.fixture_uuid('wris-concept-nonproduction'), null, 'PRE_PROJECT', 1),
  (pg_temp.fixture_uuid('wris-context-nonwebsite'), pg_temp.fixture_uuid('wris-quote-nonwebsite'), pg_temp.fixture_uuid('wris-concept-nonwebsite'), null, 'PRE_PROJECT', 1),
  (pg_temp.fixture_uuid('wris-context-unsubmitted'), pg_temp.fixture_uuid('wris-quote-unsubmitted'), pg_temp.fixture_uuid('wris-concept-unsubmitted'), null, 'PRE_PROJECT', 1),
  (pg_temp.fixture_uuid('wris-context-unconfirmed'), pg_temp.fixture_uuid('wris-quote-unconfirmed'), pg_temp.fixture_uuid('wris-concept-unconfirmed'), null, 'PRE_PROJECT', 1);
select set_config('lws.website_concept_command', '', true);
set local session_replication_role = origin;

create temporary table expected_full_sources (
  ordinal integer primary key,
  source_key text not null,
  title text not null,
  category text not null,
  linked_page_or_module text,
  source_value jsonb not null,
  source_value_sha256 text,
  source_reference jsonb,
  description text
);

insert into expected_full_sources(ordinal, source_key, title, category, linked_page_or_module, source_value)
values
  (1, 'brief:site_direction', 'Verwerk briefing, doelgroep en doelen', 'CONTENT', null,
    jsonb_build_object(
      'business_description', 'Premium websites' || E'\n' || 'voor scale-ups',
      'target_audience', 'SaaS scale-ups in de Benelux',
      'website_goals', jsonb_build_array('generate_leads', 'appointments', 'sell_products', 'portfolio', 'other'),
      'primary_conversion_goal', 'Plan een demo',
      'priorities', jsonb_build_array('professional_appearance', 'seo', 'fast_delivery', 'differentiate', 'other'),
      'additional_notes', 'Launch vóór Q4' || E'\n' || 'met gated downloads.'
    )
  ),
  (2, 'site:existing', 'Behoud en verbeter relevante delen van de bestaande website', 'DESIGN', null,
    jsonb_build_object(
      'has_existing_website', true,
      'existing_website_url', 'https://legacy.example.test',
      'elements_to_keep', 'Kennisbank; FAQ',
      'improvement_areas', 'Snellere navigatie'
    )
  ),
  (3, 'page:home', 'Bouw pagina: Home', 'PAGE', 'home', jsonb_build_object('requested', true)),
  (4, 'page:about', 'Bouw pagina: Over ons', 'PAGE', 'about', jsonb_build_object('requested', true)),
  (5, 'page:services', 'Bouw pagina: Diensten', 'PAGE', 'services', jsonb_build_object('requested', true)),
  (6, 'page:products', 'Bouw pagina: Producten', 'PAGE', 'products', jsonb_build_object('requested', true)),
  (7, 'page:portfolio', 'Bouw pagina: Portfolio', 'PAGE', 'portfolio', jsonb_build_object('requested', true)),
  (8, 'page:team', 'Bouw pagina: Team', 'PAGE', 'team', jsonb_build_object('requested', true)),
  (9, 'page:pricing', 'Bouw pagina: Prijzen', 'PAGE', 'pricing', jsonb_build_object('requested', true)),
  (10, 'page:faq', 'Bouw pagina: FAQ', 'PAGE', 'faq', jsonb_build_object('requested', true)),
  (11, 'page:reviews', 'Bouw pagina: Reviews', 'PAGE', 'reviews', jsonb_build_object('requested', true, 'scope', 'complex')),
  (12, 'page:blog', 'Bouw pagina: Blog', 'PAGE', 'blog', jsonb_build_object('requested', true, 'scope', 'normal')),
  (13, 'page:contact', 'Bouw pagina: Contact', 'PAGE', 'contact', jsonb_build_object('requested', true)),
  (14, 'page:quote_request', 'Bouw pagina: Offerteaanvraag', 'PAGE', 'quote_request', jsonb_build_object('requested', true)),
  (15, 'page:reservations', 'Bouw pagina: Reservaties', 'PAGE', 'reservations', jsonb_build_object('requested', true)),
  (16, 'page:shop', 'Bouw pagina: Shop', 'PAGE', 'shop', jsonb_build_object('requested', true)),
  (17, 'page:jobs', 'Bouw pagina: Vacatures', 'PAGE', 'jobs', jsonb_build_object('requested', true, 'scope', 'complex', 'jobs_application', 'upload')),
  (18, 'page:gallery', 'Bouw pagina: Galerij', 'PAGE', 'gallery', jsonb_build_object('requested', true, 'scope', 'complex')),
  (19, 'page:custom:' || pg_temp.hash16('Case Studies'), 'Bouw pagina: Case Studies', 'PAGE', 'Case Studies', jsonb_build_object('name', 'Case Studies')),
  (20, 'page:custom:' || pg_temp.hash16('Partner Portaal'), 'Bouw pagina: Partner Portaal', 'PAGE', 'Partner Portaal', jsonb_build_object('name', 'Partner Portaal')),
  (21, 'module:shop', 'Bouw webshopfunctionaliteit', 'ECOMMERCE', 'module:shop',
    jsonb_build_object(
      'shop_required', true,
      'requested_feature', true,
      'requested_page', true,
      'shop_details', '{"approx_product_count":48,"complex_product_count":6,"payment_provider_count":2,"shipping_scope":"advanced","categories":true,"online_payments":true,"shipping":true,"pickup":true,"pickup_scope":"scheduled","existing_catalog":true,"customer_accounts":true,"catalog_import":true,"erp_api":true}'::jsonb
    )
  ),
  (22, 'module:booking', 'Bouw reservatie- of boekingsfunctionaliteit', 'INTEGRATION', 'module:booking',
    jsonb_build_object(
      'booking_required', true,
      'requested_features', jsonb_build_array('appointments', 'reservations'),
      'requested_page', true,
      'website_goals', jsonb_build_array('appointments'),
      'booking_details', '{"tier":"advanced","type":"appointments_and_reservations","existing_system":true,"existing_system_name":"Calendly","calendar_integration":true}'::jsonb
    )
  ),
  (23, 'module:forms', 'Bouw formulieren en aanvraagflow', 'FORM', 'module:forms',
    jsonb_build_object(
      'requested_features', jsonb_build_array('contact_form', 'quote_form'),
      'requested_page', true,
      'website_goals', jsonb_build_array('generate_leads'),
      'quote_form_details', '{"file_uploads":true,"database_workflow":true,"automated_processing":true,"review_approval":true,"custom_logic":true,"form_count":3,"structure_scope":"complex"}'::jsonb
    )
  ),
  (24, 'module:payments', 'Implementeer online betalingen', 'ECOMMERCE', 'module:payments',
    jsonb_build_object(
      'requested_features', jsonb_build_array(
        'online_payment', 'online_payment_products', 'online_payment_reservations',
        'online_payment_appointments', 'online_payment_services', 'online_payment_registrations',
        'online_payment_deposit', 'online_payment_other'
      ),
      'shop_online_payments', true
    )
  ),
  (25, 'module:multilingual', 'Implementeer meertaligheid', 'CONTENT', 'module:multilingual',
    jsonb_build_object(
      'primary_language', 'nl',
      'additional_languages', jsonb_build_array('en', 'fr'),
      'unknown_languages', jsonb_build_array('svenska'),
      'multilingual_details', '{"final_translations_supplied":false,"same_structure":true,"translation_required":true,"seo_per_language":true,"advanced_seo_research":true,"language_specific_integrations":true,"complex_scope":true}'::jsonb
    )
  ),
  (26, 'design:visual_direction', 'Pas de afgesproken visuele richting toe', 'DESIGN', null,
    jsonb_build_object(
      'design_styles', jsonb_build_array('modern', 'playful', 'technical', 'other'),
      'inspiration_sites', jsonb_build_array('https://example-one.test', 'https://example-two.test'),
      'disliked_styles', 'Te minimalistisch'
    )
  ),
  (27, 'design:brand_assets', 'Verwerk logo, kleuren en huisstijl', 'DESIGN', null,
    jsonb_build_object(
      'brand_status', 'partial',
      'logo_status', 'needs_update',
      'brand_colors', jsonb_build_array('#112233', '#abcdef'),
      'branding_tier', 'existing'
    )
  ),
  (28, 'content:copy', 'Werk websitecopy uit', 'CONTENT', null,
    jsonb_build_object(
      'content_status', 'partial',
      'copywriting_scope', 'new_pages_and_reviews',
      'copy_page_count', 8
    )
  ),
  (29, 'content:images', 'Werk beeldmateriaal uit', 'MULTIMEDIA', null,
    jsonb_build_object(
      'image_status', 'partial',
      'image_support', jsonb_build_array('optimize_existing', 'ai_images', 'stock_images'),
      'image_work_scope', 'new_and_edit_existing',
      'paid_stock_handling', true
    )
  ),
  (30, 'feature:downloads', 'Implementeer downloads en documenttoegang', 'DOCUMENT_FLOW', 'feature:downloads', jsonb_build_object('requested', true, 'access', 'private_documents')),
  (31, 'feature:newsletter', 'Implementeer nieuwsbriefkoppeling', 'INTEGRATION', 'feature:newsletter', jsonb_build_object('requested', true, 'scope', 'existing_list_and_automation', 'analytics', 'advanced', 'custom_integration', true)),
  (32, 'feature:search', 'Implementeer zoekfunctie', 'TECHNICAL', 'feature:search', jsonb_build_object('requested', true, 'scope', 'sitewide')),
  (33, 'feature:customer_login', 'Implementeer klantlogin', 'AUTH', 'feature:customer_login', jsonb_build_object('requested', true)),
  (34, 'feature:gallery', 'Implementeer galerijfunctionaliteit', 'MULTIMEDIA', 'feature:gallery', jsonb_build_object('requested', true)),
  (35, 'feature:reviews', 'Implementeer reviewfunctionaliteit', 'INTEGRATION', 'feature:reviews', jsonb_build_object('requested', true)),
  (36, 'feature:manual_scope', 'Werk nog te bepalen functionaliteit uit', 'OTHER', 'feature:manual_scope', jsonb_build_object('requested_features', jsonb_build_array('other', 'unsure'), 'additional_notes', 'Launch vóór Q4' || E'\n' || 'met gated downloads.')),
  (37, 'integration:google_maps', 'Integreer Google Maps', 'INTEGRATION', 'integration:google_maps', jsonb_build_object('requested', true)),
  (38, 'integration:social_links', 'Implementeer social-links op de website', 'INTEGRATION', 'integration:social_links', jsonb_build_object('requested', true)),
  (39, 'integration:whatsapp', 'Integreer WhatsApp-contact', 'INTEGRATION', 'integration:whatsapp', jsonb_build_object('requested', true)),
  (40, 'integration:social_channels', 'Koppel sociale kanalen', 'INTEGRATION', 'integration:social_channels', jsonb_build_object('social_channels', jsonb_build_array('instagram', 'linkedin', 'youtube'))),
  (41, 'integration:external:' || pg_temp.hash16('exact online'), 'Integreer externe koppeling: Exact Online', 'INTEGRATION', 'integration:external:' || pg_temp.hash16('exact online'), jsonb_build_object('name', 'Exact Online')),
  (42, 'integration:external:' || pg_temp.hash16('hubspot'), 'Integreer externe koppeling: HubSpot', 'INTEGRATION', 'integration:external:' || pg_temp.hash16('hubspot'), jsonb_build_object('name', 'HubSpot')),
  (43, 'technical:domain', 'Configureer domein', 'TECHNICAL', null, jsonb_build_object('domain_status', 'has_domain', 'domain_name', 'example.test', 'domain_service', 'transfer_needed')),
  (44, 'technical:hosting', 'Configureer hosting', 'TECHNICAL', null, jsonb_build_object('hosting_status', 'has_hosting', 'hosting_support', 'advice', 'details_hosting_support', 'advice')),
  (45, 'technical:maintenance', 'Configureer onderhoudsafspraken', 'TECHNICAL', null, jsonb_build_object('maintenance_interest', 'yes', 'details_maintenance_interest', 'care_plus_requested', 'maintenance_plan', 'care_plus')),
  (46, 'seo:scope', 'Implementeer SEO-scope', 'SEO', null, jsonb_build_object('seo_priority', 'high', 'seo_keywords', jsonb_build_array('erp koppeling', 'lead generatie'), 'scope', 'advanced', 'extra_language_seo', true, 'advanced_language_seo', true)),
  (47, 'constraint:deadline', 'Respecteer afgesproken deadline', 'OTHER', null, jsonb_build_object('deadline_date', '2099-03-31', 'deadline_reason', 'Lancering voor Q4-beurs', 'commercially_critical', true, 'hard_deadline', true));

update expected_full_sources
set
  source_value_sha256 = pg_temp.jsonb_sha256(source_value),
  source_reference = pg_temp.safe_source_reference_v1(
    pg_temp.fixture_uuid('wris-intake-initial-full'),
    7,
    '2099-01-01T11:00:00Z'::timestamptz,
    source_key,
    pg_temp.jsonb_sha256(source_value)
  ),
  description = pg_temp.safe_description_v1(source_key, source_value);

create temporary table expected_delta_sources (
  ordinal integer primary key,
  source_key text not null,
  title text not null,
  category text not null,
  linked_page_or_module text,
  source_value jsonb not null,
  source_value_sha256 text,
  source_reference jsonb,
  description text
);

insert into expected_delta_sources(ordinal, source_key, title, category, linked_page_or_module, source_value)
values
  (1, 'brief:site_direction', 'Verwerk briefing, doelgroep en doelen', 'CONTENT', null, jsonb_build_object('business_description', 'Delta scope voor bestaand traject', 'target_audience', 'Bestaande klanten', 'website_goals', jsonb_build_array('generate_leads'), 'primary_conversion_goal', 'Vraag een intakegesprek', 'priorities', jsonb_build_array('professional_appearance'), 'additional_notes', 'Behoud bestaande copy waar mogelijk.')),
  (2, 'site:existing', 'Behoud en verbeter relevante delen van de bestaande website', 'DESIGN', null, jsonb_build_object('has_existing_website', true, 'existing_website_url', 'https://delta.example.test', 'elements_to_keep', 'Homepage en support', 'improvement_areas', 'Nieuwe CTA en snellere navigatie')),
  (3, 'page:home', 'Bouw pagina: Home', 'PAGE', 'home', jsonb_build_object('requested', true)),
  (4, 'module:forms', 'Bouw formulieren en aanvraagflow', 'FORM', 'module:forms', jsonb_build_object('requested_features', jsonb_build_array('contact_form'), 'website_goals', jsonb_build_array('generate_leads'), 'quote_form_details', '{"file_uploads":false,"database_workflow":false,"automated_processing":false,"review_approval":true,"custom_logic":false,"form_count":1,"structure_scope":"simple"}'::jsonb)),
  (5, 'design:visual_direction', 'Pas de afgesproken visuele richting toe', 'DESIGN', null, jsonb_build_object('design_styles', jsonb_build_array('modern', 'business'), 'inspiration_sites', jsonb_build_array('https://delta-reference.test'))),
  (6, 'content:copy', 'Werk websitecopy uit', 'CONTENT', null, jsonb_build_object('content_status', 'complete', 'copywriting_scope', 'existing_with_edits', 'copy_page_count', 3)),
  (7, 'feature:downloads', 'Implementeer downloads en documenttoegang', 'DOCUMENT_FLOW', 'feature:downloads', jsonb_build_object('requested', true, 'access', 'private_documents')),
  (8, 'technical:hosting', 'Configureer hosting', 'TECHNICAL', null, jsonb_build_object('hosting_status', 'has_hosting', 'hosting_support', 'yes')),
  (9, 'seo:scope', 'Implementeer SEO-scope', 'SEO', null, jsonb_build_object('seo_priority', 'basic', 'seo_keywords', jsonb_build_array('lead generatie'), 'scope', 'basic', 'extra_language_seo', false, 'advanced_language_seo', false));

update expected_delta_sources
set
  source_value_sha256 = pg_temp.jsonb_sha256(source_value),
  source_reference = pg_temp.safe_source_reference_v1(
    pg_temp.fixture_uuid('wris-intake-resync-delta'),
    9,
    '2099-01-01T11:05:00Z'::timestamptz,
    source_key,
    pg_temp.jsonb_sha256(source_value)
  ),
  description = pg_temp.safe_description_v1(source_key, source_value);

select set_config('lws.website_requirement_command', 'on', true);
insert into public.website_requirements_boards(
  requirements_board_id, website_work_context_id, quote_request_id, sync_state,
  mapping_version, current_intake_id, current_intake_revision,
  current_intake_snapshot_sha256, revision, created_by
) values
  (
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'CURRENT', 1,
    pg_temp.fixture_uuid('wris-intake-resync-delta'),
    8,
    repeat('a', 64),
    7,
    pg_temp.fixture_uuid('wris-owner-operator')
  ),
  (
    pg_temp.fixture_uuid('wris-board-replay'),
    pg_temp.fixture_uuid('wris-context-replay'),
    pg_temp.fixture_uuid('wris-quote-replay'),
    'CURRENT', 1,
    pg_temp.fixture_uuid('wris-intake-replay'),
    11,
    (select pg_temp.jsonb_sha256(jsonb_build_object('mapping_version', 1, 'sources', jsonb_agg(jsonb_build_object('source_key', source_key, 'source_value', source_value) order by ordinal))) from expected_delta_sources),
    12,
    pg_temp.fixture_uuid('wris-owner-operator')
  );

insert into public.website_requirements(
  requirement_id, requirements_board_id, website_work_context_id, quote_request_id,
  source_key, source_reference, source_value_sha256, item_number, sort_order,
  title, description, category, linked_page_or_module, status,
  completion_mode, completion_rule_key, completion_rule_version,
  source_review_state, required, started_at, completed_at, completed_by,
  evidence_summary, verification_result, blocked_reason, revision
) values
  (
    pg_temp.fixture_uuid('wris-req-brief-unchanged'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'brief:site_direction',
    (select source_reference from expected_delta_sources where source_key = 'brief:site_direction'),
    (select source_value_sha256 from expected_delta_sources where source_key = 'brief:site_direction'),
    1, 1,
    (select title from expected_delta_sources where source_key = 'brief:site_direction'),
    (select description from expected_delta_sources where source_key = 'brief:site_direction'),
    'CONTENT', null,
    'PENDING', 'OPERATOR', null, null,
    'CURRENT', true, null, null, null, null, 'UNKNOWN', null, 1
  ),
  (
    pg_temp.fixture_uuid('wris-req-site-update-safe'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'site:existing',
    pg_temp.safe_source_reference_v1(pg_temp.fixture_uuid('wris-intake-resync-delta'), 8, '2099-01-01T11:05:00Z'::timestamptz, 'site:existing', repeat('1', 64)),
    repeat('1', 64),
    2, 2,
    'Behoud en verbeter relevante delen van de bestaande website',
    'Klantvraag uit bevestigde Website-intake. Bron: site:existing. Details: {"has_existing_website":true,"existing_website_url":"https://delta.example.test","elements_to_keep":"Homepage en support","improvement_areas":"Oude CTA"}',
    'DESIGN', null,
    'PENDING', 'OPERATOR', null, null,
    'CURRENT', true, null, null, null, null, 'UNKNOWN', null, 1
  ),
  (
    pg_temp.fixture_uuid('wris-req-home-unchanged'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'page:home',
    (select source_reference from expected_delta_sources where source_key = 'page:home'),
    (select source_value_sha256 from expected_delta_sources where source_key = 'page:home'),
    3, 3,
    'Bouw pagina: Home',
    (select description from expected_delta_sources where source_key = 'page:home'),
    'PAGE', 'home',
    'PENDING', 'OPERATOR', null, null,
    'CURRENT', true, null, null, null, null, 'UNKNOWN', null, 1
  ),
  (
    pg_temp.fixture_uuid('wris-req-about-retire'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'page:about',
    pg_temp.safe_source_reference_v1(pg_temp.fixture_uuid('wris-intake-resync-delta'), 8, '2099-01-01T11:05:00Z'::timestamptz, 'page:about', repeat('2', 64)),
    repeat('2', 64),
    4, 4,
    'Bouw pagina: Over ons',
    'Klantvraag uit bevestigde Website-intake. Bron: page:about. Details: {"requested":true}',
    'PAGE', 'about',
    'PENDING', 'OPERATOR', null, null,
    'CURRENT', true, null, null, null, null, 'UNKNOWN', null, 1
  ),
  (
    pg_temp.fixture_uuid('wris-req-downloads-revive'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'feature:downloads',
    pg_temp.safe_source_reference_v1(pg_temp.fixture_uuid('wris-intake-resync-delta'), 8, '2099-01-01T11:05:00Z'::timestamptz, 'feature:downloads', repeat('3', 64)),
    repeat('3', 64),
    5, 5,
    'Implementeer downloads en documenttoegang',
    'Klantvraag uit bevestigde Website-intake. Bron: feature:downloads. Details: {"requested":true,"access":"legacy"}',
    'DOCUMENT_FLOW', 'feature:downloads',
    'PENDING', 'OPERATOR', null, null,
    'RETIRED', false, null, null, null, null, 'UNKNOWN', null, 1
  ),
  (
    pg_temp.fixture_uuid('wris-req-design-change-pending'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'design:visual_direction',
    pg_temp.safe_source_reference_v1(pg_temp.fixture_uuid('wris-intake-resync-delta'), 8, '2099-01-01T11:05:00Z'::timestamptz, 'design:visual_direction', repeat('4', 64)),
    repeat('4', 64),
    6, 6,
    'Pas de afgesproken visuele richting toe',
    'Klantvraag uit bevestigde Website-intake. Bron: design:visual_direction. Details: {"design_styles":["modern"],"inspiration_sites":["https://old-reference.test"]}',
    'DESIGN', null,
    'ACTIVE', 'OPERATOR', null, null,
    'CURRENT', true, '2099-01-01T12:00:00Z', null, null,
    '{"state":"work_started"}'::jsonb, 'UNKNOWN', null, 2
  ),
  (
    pg_temp.fixture_uuid('wris-req-search-removal-pending'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'feature:search',
    pg_temp.safe_source_reference_v1(pg_temp.fixture_uuid('wris-intake-resync-delta'), 8, '2099-01-01T11:05:00Z'::timestamptz, 'feature:search', repeat('5', 64)),
    repeat('5', 64),
    7, 7,
    'Implementeer zoekfunctie',
    'Klantvraag uit bevestigde Website-intake. Bron: feature:search. Details: {"requested":true,"scope":"sitewide"}',
    'TECHNICAL', 'feature:search',
    'BLOCKED', 'OPERATOR', null, null,
    'CURRENT', true, '2099-01-01T12:30:00Z', null, null,
    '{"issue":"indexing blocker"}'::jsonb, 'UNKNOWN', 'Wacht op contentmodel', 3
  ),
  (
    pg_temp.fixture_uuid('wris-req-copy-change-pending'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'content:copy',
    pg_temp.safe_source_reference_v1(pg_temp.fixture_uuid('wris-intake-resync-delta'), 8, '2099-01-01T11:05:00Z'::timestamptz, 'content:copy', repeat('6', 64)),
    repeat('6', 64),
    8, 8,
    'Werk websitecopy uit',
    'Klantvraag uit bevestigde Website-intake. Bron: content:copy. Details: {"content_status":"complete","copywriting_scope":"existing","copy_page_count":2}',
    'CONTENT', null,
    'COMPLETED', 'OPERATOR', null, null,
    'CURRENT', true, '2099-01-01T12:45:00Z', '2099-01-01T13:00:00Z',
    'OPERATOR:' || pg_temp.fixture_uuid('wris-owner-operator')::text,
    '{"delivered":"copy-v1"}'::jsonb, 'PASS', null, 4
  ),
  (
    pg_temp.fixture_uuid('wris-req-maintenance-removal-pending'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'technical:maintenance',
    pg_temp.safe_source_reference_v1(pg_temp.fixture_uuid('wris-intake-resync-delta'), 8, '2099-01-01T11:05:00Z'::timestamptz, 'technical:maintenance', repeat('7', 64)),
    repeat('7', 64),
    9, 9,
    'Configureer onderhoudsafspraken',
    'Klantvraag uit bevestigde Website-intake. Bron: technical:maintenance. Details: {"maintenance_interest":"yes","maintenance_plan":"care"}',
    'TECHNICAL', null,
    'COMPLETED', 'OPERATOR', null, null,
    'CURRENT', true, '2099-01-01T12:50:00Z', '2099-01-01T13:10:00Z',
    'OPERATOR:' || pg_temp.fixture_uuid('wris-manager-operator')::text,
    '{"delivered":"maintenance-agreement"}'::jsonb, 'PASS', null, 5
  ),
  (
    pg_temp.fixture_uuid('wris-req-forms-unchanged'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'module:forms',
    (select source_reference from expected_delta_sources where source_key = 'module:forms'),
    (select source_value_sha256 from expected_delta_sources where source_key = 'module:forms'),
    10, 10,
    'Bouw formulieren en aanvraagflow',
    (select description from expected_delta_sources where source_key = 'module:forms'),
    'FORM', 'module:forms',
    'PENDING', 'OPERATOR', null, null,
    'CURRENT', true, null, null, null, null, 'UNKNOWN', null, 1
  ),
  (
    pg_temp.fixture_uuid('wris-req-hosting-unchanged'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'technical:hosting',
    (select source_reference from expected_delta_sources where source_key = 'technical:hosting'),
    (select source_value_sha256 from expected_delta_sources where source_key = 'technical:hosting'),
    11, 11,
    'Configureer hosting',
    (select description from expected_delta_sources where source_key = 'technical:hosting'),
    'TECHNICAL', null,
    'PENDING', 'OPERATOR', null, null,
    'CURRENT', true, null, null, null, null, 'UNKNOWN', null, 1
  ),
  (
    pg_temp.fixture_uuid('wris-req-seo-unchanged'),
    pg_temp.fixture_uuid('wris-board-resync-delta'),
    pg_temp.fixture_uuid('wris-context-resync-delta'),
    pg_temp.fixture_uuid('wris-quote-resync-delta'),
    'seo:scope',
    (select source_reference from expected_delta_sources where source_key = 'seo:scope'),
    (select source_value_sha256 from expected_delta_sources where source_key = 'seo:scope'),
    12, 12,
    'Implementeer SEO-scope',
    (select description from expected_delta_sources where source_key = 'seo:scope'),
    'SEO', null,
    'PENDING', 'OPERATOR', null, null,
    'CURRENT', true, null, null, null, null, 'UNKNOWN', null, 1
  );
select set_config('lws.website_requirement_command', '', true);

select pg_temp.insert_sync_run_fixture_v1(
  pg_temp.fixture_uuid('wris-sync-run-replay'),
  pg_temp.fixture_uuid('wris-board-replay'),
  pg_temp.fixture_uuid('wris-context-replay'),
  pg_temp.fixture_uuid('wris-quote-replay'),
  pg_temp.fixture_uuid('wris-intake-replay'),
  11,
  (select pg_temp.jsonb_sha256(jsonb_build_object('mapping_version', 1, 'sources', jsonb_agg(jsonb_build_object('source_key', source_key, 'source_value', source_value) order by ordinal))) from expected_delta_sources),
  1,
  pg_temp.request_fingerprint_v1(
    pg_temp.fixture_uuid('wris-quote-replay'),
    pg_temp.fixture_uuid('wris-context-replay'),
    11,
    pg_temp.fixture_uuid('wris-intake-replay'),
    11,
    (select pg_temp.jsonb_sha256(jsonb_build_object('mapping_version', 1, 'sources', jsonb_agg(jsonb_build_object('source_key', source_key, 'source_value', source_value) order by ordinal))) from expected_delta_sources),
    1
  ),
  'OPERATOR:' || pg_temp.fixture_uuid('wris-owner-operator')::text,
  pg_temp.fixture_uuid('wris-replay-command'),
  jsonb_build_object(
    'contract_version', 1,
    'outcome', 'SYNCED',
    'quote_request_id', pg_temp.fixture_uuid('wris-quote-replay'),
    'website_work_context_id', pg_temp.fixture_uuid('wris-context-replay'),
    'requirements_board_id', pg_temp.fixture_uuid('wris-board-replay'),
    'board_revision', 12,
    'intake_id', pg_temp.fixture_uuid('wris-intake-replay'),
    'intake_revision', 11,
    'intake_sha256', (select pg_temp.jsonb_sha256(jsonb_build_object('mapping_version', 1, 'sources', jsonb_agg(jsonb_build_object('source_key', source_key, 'source_value', source_value) order by ordinal))) from expected_delta_sources),
    'mapping_version', 1,
    'sync_run_id', pg_temp.fixture_uuid('wris-sync-run-replay'),
    'replayed', false,
    'review_required', false,
    'counts', jsonb_build_object('created', 0, 'updated', 0, 'unchanged', 9, 'retired', 0, 'change_pending', 0, 'removal_pending', 0, 'revived', 0)
  ),
  '[]'::jsonb
);

create temporary table commercial_baseline as
select
  (select count(*) from public.quote_request_quotation_approvals) as quotation_approvals,
  (select count(*) from public.quote_request_quotation_issuances) as quotation_issuances,
  (select count(*) from public.quote_request_quotation_acceptances) as quotation_acceptances,
  (select count(*) from public.commercial_customers) as commercial_customers,
  (select count(*) from public.commercial_projects) as commercial_projects,
  (select count(*) from public.commercial_obligations) as commercial_obligations,
  (select count(*) from public.payment_expectations) as payment_expectations,
  (select count(*) from public.payment_evidence) as payment_evidence,
  (select count(*) from public.payment_reconciliations) as payment_reconciliations;

select ok(
  not exists (
    select 1
    from expected_full_sources
    where source_value::text ~ '(budget_confirmed|budget_update_category|budget_update_category_scheme|budget_update_category_code|budget_notes|selected_package_definition_id|confirmation)'
  ),
  'canonical source values exclude budget and eligibility-only fields'
);
select ok(
  not exists (
    select 1
    from expected_full_sources
    where pg_temp.jsonb_keys_sorted_v1(source_reference) <>
      '["authority_type","intake_id","intake_revision","mapping_version","source_key","source_path","source_value_sha256","submitted_at"]'::jsonb
  ),
  'source references expose only the exact safe provenance keys'
);
select ok(
  not exists (
    select 1
    from expected_full_sources
    where category not in ('PAGE', 'CONTENT', 'DESIGN', 'FORM', 'SEO', 'INTEGRATION', 'AUTH', 'ECOMMERCE', 'DOCUMENT_FLOW', 'MULTIMEDIA', 'TECHNICAL', 'OTHER')
  ),
  'expected sources use only the contracted category set'
);
select is(
  lws_internal.website_requirements_normalize_integration_array_v1(
    array['hubspot', 'HubSpot', 'exact online', 'Exact Online']
  ),
  lws_internal.website_requirements_normalize_integration_array_v1(
    array['Exact Online', 'exact online', 'HubSpot', 'hubspot']
  ),
  'external integration identity and display selection are independent of input order'
);

select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2');

create temporary table initial_sync_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-initial-full'),
  pg_temp.fixture_uuid('wris-context-initial-full'),
  0,
  pg_temp.fixture_uuid('wris-initial-command')
) as result;

select is(
  pg_temp.jsonb_keys_sorted_v1((select result from initial_sync_result)),
  '["board_revision","contract_version","counts","intake_id","intake_revision","intake_sha256","mapping_version","outcome","quote_request_id","replayed","requirements_board_id","review_required","sync_run_id","website_work_context_id"]'::jsonb,
  'initial sync result uses the exact root key set'
);
select is(
  pg_temp.jsonb_keys_sorted_v1((select result->'counts' from initial_sync_result)),
  '["change_pending","created","removal_pending","retired","revived","unchanged","updated"]'::jsonb,
  'initial sync result counts use the exact key set'
);
select is((select result->>'contract_version' from initial_sync_result), '1', 'initial sync returns contract version 1');
select is((select result->>'mapping_version' from initial_sync_result), '1', 'initial sync returns mapping version 1');
select is((select result->>'outcome' from initial_sync_result), 'SYNCED', 'owner AAL2 can perform the initial sync');
select is((select result->>'replayed' from initial_sync_result), 'false', 'initial sync is not a replay');
select is((select result->>'review_required' from initial_sync_result), 'false', 'initial sync starts in current state');
select is((select result->>'quote_request_id' from initial_sync_result), pg_temp.fixture_uuid('wris-quote-initial-full')::text, 'initial sync result echoes the exact quote request id');
select is((select result->>'website_work_context_id' from initial_sync_result), pg_temp.fixture_uuid('wris-context-initial-full')::text, 'initial sync result echoes the exact Website work context id');
select is((select result->>'intake_id' from initial_sync_result), pg_temp.fixture_uuid('wris-intake-initial-full')::text, 'initial sync result echoes the exact intake id');
select is((select result->>'intake_revision' from initial_sync_result), '7', 'initial sync uses draft_revision as intake revision authority');
select is(
  (select result->>'intake_sha256' from initial_sync_result),
  (select pg_temp.jsonb_sha256(jsonb_build_object('mapping_version', 1, 'sources', jsonb_agg(jsonb_build_object('source_key', source_key, 'source_value', source_value) order by ordinal))) from expected_full_sources),
  'initial sync returns the exact canonical intake snapshot hash'
);
select is((select result->>'board_revision' from initial_sync_result), '1', 'initial sync creates board revision 1');
select is((select result->'counts'->>'created' from initial_sync_result), '47', 'initial sync creates every canonical fixed and dynamic requirement source');
select is((select result->'counts'->>'updated' from initial_sync_result), '0', 'initial sync has no updated rows');
select is((select result->'counts'->>'unchanged' from initial_sync_result), '0', 'initial sync has no unchanged rows');
select is((select result->'counts'->>'retired' from initial_sync_result), '0', 'initial sync has no retired rows');
select is((select result->'counts'->>'change_pending' from initial_sync_result), '0', 'initial sync has no change-pending rows');
select is((select result->'counts'->>'removal_pending' from initial_sync_result), '0', 'initial sync has no removal-pending rows');
select is((select result->'counts'->>'revived' from initial_sync_result), '0', 'initial sync has no revived rows');

select is(
  pg_temp.jsonb_array_sorted_v1(
    (select jsonb_agg(source_key order by ordinal) from expected_full_sources)
  ),
  pg_temp.jsonb_array_sorted_v1(
    (select jsonb_agg(source_key order by source_key)
     from expected_full_sources)
  ),
  'the full expected source catalog is deterministic for comparison'
);
select is(
  pg_temp.jsonb_array_sorted_v1(
    (select jsonb_agg(requirement.source_key order by requirement.source_key)
     from public.website_requirements as requirement
     join public.website_requirements_boards as board
       on board.requirements_board_id = requirement.requirements_board_id
     where board.website_work_context_id = pg_temp.fixture_uuid('wris-context-initial-full')
       and requirement.source_review_state <> 'RETIRED')
  ),
  pg_temp.jsonb_array_sorted_v1((select jsonb_agg(source_key order by source_key) from expected_full_sources)),
  'initial sync materializes every fixed source key and dynamic page/integration hash exactly once'
);
select is(
  (select count(*)::text
   from public.website_requirements
   where website_work_context_id = pg_temp.fixture_uuid('wris-context-initial-full')
     and completion_mode = 'OPERATOR'
     and completion_rule_key is null
     and completion_rule_version is null),
  '47',
  'initial sync emits OPERATOR-only requirements with no automation rules'
);
select is(
  (select count(*)::text
   from public.website_requirements
   where website_work_context_id = pg_temp.fixture_uuid('wris-context-initial-full')
     and required = true
     and status = 'PENDING'
     and source_review_state = 'CURRENT'),
  '47',
  'initial sync emits required CURRENT PENDING rows only'
);

select is(
  pg_temp.jsonb_array_sorted_v1(
    pg_temp.sync_run_proposed_changes_v1(
      ((select result->>'sync_run_id' from initial_sync_result))::uuid
    )
  ),
  pg_temp.jsonb_array_sorted_v1(
    (select jsonb_agg(
      jsonb_build_object(
        'source_key', source_key,
        'action', 'CREATE',
        'requirement_id', null,
        'previous_source_value_sha256', null,
        'proposed_source_value_sha256', source_value_sha256,
        'proposed_definition', jsonb_build_object(
          'title', title,
          'description', description,
          'category', category,
          'linked_page_or_module', linked_page_or_module,
          'required', true,
          'completion_mode', 'OPERATOR',
          'completion_rule_key', null,
          'completion_rule_version', null,
          'source_reference', source_reference
        )
      )
    order by source_key) from expected_full_sources)
  ),
  'initial sync persists exact CREATE proposed_changes with safe provenance and no lifecycle fields'
);

create temporary table exact_replay_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-initial-full'),
  pg_temp.fixture_uuid('wris-context-initial-full'),
  0,
  pg_temp.fixture_uuid('wris-initial-command')
) as result;

select is(
  (select result from exact_replay_result),
  (select result from initial_sync_result),
  'exact idempotent replay returns the stored result without side effects'
);

create temporary table owner_aal1_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-initial-full'),
  pg_temp.fixture_uuid('wris-context-initial-full'),
  0,
  pg_temp.fixture_uuid('wris-owner-aal1-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal1')) as ignored;

select is(
  (select result->>'sqlstate' from owner_aal1_result),
  '42501',
  'AAL1 owners are denied'
);

create temporary table operator_denied_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-initial-full'),
  pg_temp.fixture_uuid('wris-context-initial-full'),
  0,
  pg_temp.fixture_uuid('wris-operator-denied-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-operator-user'), 'aal2')) as ignored;

select is(
  (select result->>'sqlstate' from operator_denied_result),
  '42501',
  'operator role is unauthorized for intake sync'
);

create temporary table inactive_denied_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-initial-full'),
  pg_temp.fixture_uuid('wris-context-initial-full'),
  0,
  pg_temp.fixture_uuid('wris-inactive-denied-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-inactive-user'), 'aal2')) as ignored;

select is(
  (select result->>'sqlstate' from inactive_denied_result),
  '42501',
  'inactive management identities are denied'
);

create temporary table manager_initial_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-initial-full'),
  pg_temp.fixture_uuid('wris-context-initial-full'),
  0,
  pg_temp.fixture_uuid('wris-manager-initial-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-manager-user'), 'aal2')) as ignored;

select is(
  (select result->>'outcome' from manager_initial_result),
  'SYNCED',
  'operations_manager AAL2 can perform the initial sync'
);

create temporary table wrong_context_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-initial-full'),
  pg_temp.fixture_uuid('wris-context-resync-delta'),
  0,
  pg_temp.fixture_uuid('wris-wrong-context-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select ok(
  coalesce((select result->>'sqlstate' from wrong_context_result), '') = any(array['22023', '42501']),
  'mismatched quote and Website work context fail closed'
);

create temporary table nonproduction_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-nonproduction'),
  pg_temp.fixture_uuid('wris-context-nonproduction'),
  0,
  pg_temp.fixture_uuid('wris-nonproduction-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select ok(
  coalesce((select result->>'sqlstate' from nonproduction_result), '') = any(array['22023', '42501']),
  'non-production dossiers fail closed'
);

create temporary table nonwebsite_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-nonwebsite'),
  pg_temp.fixture_uuid('wris-context-nonwebsite'),
  0,
  pg_temp.fixture_uuid('wris-nonwebsite-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select ok(
  coalesce((select result->>'sqlstate' from nonwebsite_result), '') = any(array['22023', '42501']),
  'non-Website dossiers fail closed'
);

create temporary table unsubmitted_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-unsubmitted'),
  pg_temp.fixture_uuid('wris-context-unsubmitted'),
  0,
  pg_temp.fixture_uuid('wris-unsubmitted-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select ok(
  coalesce((select result->>'sqlstate' from unsubmitted_result), '') = any(array['22023', '42501']),
  'unsubmitted intakes fail closed'
);

create temporary table unconfirmed_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-unconfirmed'),
  pg_temp.fixture_uuid('wris-context-unconfirmed'),
  0,
  pg_temp.fixture_uuid('wris-unconfirmed-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select ok(
  coalesce((select result->>'sqlstate' from unconfirmed_result), '') = any(array['22023', '42501']),
  'unconfirmed intakes fail closed'
);

create temporary table unknown_feature_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-unknown-feature'),
  pg_temp.fixture_uuid('wris-context-unknown-feature'),
  0,
  pg_temp.fixture_uuid('wris-unknown-feature-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select is(
  (select result->>'message' from unknown_feature_result),
  'WEBSITE_REQUIREMENTS_MAPPING_UNSUPPORTED',
  'unknown requested_features fail closed'
);

create temporary table resync_delta_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-resync-delta'),
  pg_temp.fixture_uuid('wris-context-resync-delta'),
  7,
  pg_temp.fixture_uuid('wris-resync-delta-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select is((select result->>'outcome' from resync_delta_result), 'REVIEW_REQUIRED', 'mixed resync actions yield REVIEW_REQUIRED');
select is((select result->>'review_required' from resync_delta_result), 'true', 'resync marks review_required when preserving in-progress evidence');
select is((select result->>'replayed' from resync_delta_result), 'false', 'state-changing resync is not a replay');
select is((select result->>'board_revision' from resync_delta_result), '8', 'resync increments board revision');
select is((select result->'counts'->>'created' from resync_delta_result), '0', 'resync creates no unexpected rows in the delta fixture');
select is((select result->'counts'->>'updated' from resync_delta_result), '2', 'resync reports update-safe and revive under updated counts');
select is((select result->'counts'->>'unchanged' from resync_delta_result), '4', 'resync reports unchanged sources precisely');
select is((select result->'counts'->>'retired' from resync_delta_result), '1', 'resync retires safe removed pending work');
select is((select result->'counts'->>'change_pending' from resync_delta_result), '2', 'resync reports active/completed source changes as change-pending');
select is((select result->'counts'->>'removal_pending' from resync_delta_result), '2', 'resync preserves blocked/completed removals as removal-pending');
select is((select result->'counts'->>'revived' from resync_delta_result), '1', 'resync revives previously retired requirements');

select is(
  pg_temp.jsonb_array_sorted_v1(
    (select jsonb_agg(change_row->>'action')
     from jsonb_array_elements(
       pg_temp.sync_run_proposed_changes_v1(((select result->>'sync_run_id' from resync_delta_result))::uuid)
     ) as change_row)
  ),
  '["CHANGE_PENDING","CHANGE_PENDING","REMOVAL_PENDING","REMOVAL_PENDING","RETIRE","REVIVE","UNCHANGED","UNCHANGED","UNCHANGED","UNCHANGED","UPDATE_SAFE"]'::jsonb,
  'resync proposed_changes uses only the contracted action set'
);

select is(
  (select source_review_state::text from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-site-update-safe')),
  'CURRENT',
  'update-safe keeps CURRENT source state'
);
select is(
  (select source_review_state::text from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-about-retire')),
  'RETIRED',
  'safe removed pending work retires instead of deleting'
);
select is(
  (select source_review_state::text from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-design-change-pending')),
  'CHANGE_PENDING',
  'ACTIVE definition changes preserve work and enter CHANGE_PENDING'
);
select is(
  (select source_review_state::text from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-search-removal-pending')),
  'REMOVAL_PENDING',
  'BLOCKED removals preserve state and become REMOVAL_PENDING'
);
select is(
  (select source_review_state::text from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-copy-change-pending')),
  'CHANGE_PENDING',
  'COMPLETED definition changes preserve completion and become CHANGE_PENDING'
);
select is(
  (select source_review_state::text from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-maintenance-removal-pending')),
  'REMOVAL_PENDING',
  'COMPLETED removals preserve completion and become REMOVAL_PENDING'
);
select is(
  (select evidence_summary from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-design-change-pending')),
  '{"state":"work_started"}'::jsonb,
  'change-pending ACTIVE rows preserve evidence summary'
);
select is(
  (select blocked_reason from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-search-removal-pending')),
  'Wacht op contentmodel',
  'removal-pending BLOCKED rows preserve blocked reason'
);
select is(
  (select completed_by from public.website_requirements where requirement_id = pg_temp.fixture_uuid('wris-req-copy-change-pending')),
  'OPERATOR:' || pg_temp.fixture_uuid('wris-owner-operator')::text,
  'change-pending COMPLETED rows preserve completion actor'
);

create temporary table exact_stored_replay_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-replay'),
  pg_temp.fixture_uuid('wris-context-replay'),
  11,
  pg_temp.fixture_uuid('wris-replay-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select is(
  (select result from exact_stored_replay_result),
  (select result from public.website_requirement_sync_runs where sync_run_id = pg_temp.fixture_uuid('wris-sync-run-replay')),
  'exact stored replay returns the pre-existing idempotent sync result'
);

create temporary table logical_replay_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-replay'),
  pg_temp.fixture_uuid('wris-context-replay'),
  12,
  pg_temp.fixture_uuid('wris-logical-replay-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select is(
  (select result->>'outcome' from logical_replay_result),
  'REPLAYED',
  'logical replay reuses the stored logical sync without side effects'
);
select is(
  (select result->>'replayed' from logical_replay_result),
  'true',
  'logical replay sets replayed=true'
);

create temporary table replay_conflict_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-replay'),
  pg_temp.fixture_uuid('wris-context-replay'),
  12,
  pg_temp.fixture_uuid('wris-replay-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select is(
  (select result->>'message' from replay_conflict_result),
  'WEBSITE_REQUIREMENTS_IDEMPOTENCY_CONFLICT',
  'same command id with a different fingerprint fails closed'
);

create temporary table stale_revision_result as
select pg_temp.call_sync_website_requirements_from_intake_v1(
  pg_temp.fixture_uuid('wris-quote-resync-delta'),
  pg_temp.fixture_uuid('wris-context-resync-delta'),
  6,
  pg_temp.fixture_uuid('wris-stale-revision-command')
) as result
from (select pg_temp.set_sync_claims_v1(pg_temp.fixture_uuid('wris-owner-user'), 'aal2')) as ignored;

select is(
  (select result->>'message' from stale_revision_result),
  'CONCURRENT_MODIFICATION',
  'stale board revisions fail closed'
);

select ok(
  (select quotation_approvals from commercial_baseline) = (select count(*) from public.quote_request_quotation_approvals)
  and (select quotation_issuances from commercial_baseline) = (select count(*) from public.quote_request_quotation_issuances)
  and (select quotation_acceptances from commercial_baseline) = (select count(*) from public.quote_request_quotation_acceptances)
  and (select commercial_customers from commercial_baseline) = (select count(*) from public.commercial_customers)
  and (select commercial_projects from commercial_baseline) = (select count(*) from public.commercial_projects)
  and (select commercial_obligations from commercial_baseline) = (select count(*) from public.commercial_obligations)
  and (select payment_expectations from commercial_baseline) = (select count(*) from public.payment_expectations)
  and (select payment_evidence from commercial_baseline) = (select count(*) from public.payment_evidence)
  and (select payment_reconciliations from commercial_baseline) = (select count(*) from public.payment_reconciliations),
  'sync produces no commercial side effects'
);

select is(
  extensions.dblink_connect(
    'wris_race_setup',
    'host=' || host(inet_server_addr()) || ' port=' || current_setting('port')
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres application_name=wris_race_setup'
  ),
  'OK',
  'concurrency setup connection opens'
);
select lives_ok(
  $test$select extensions.dblink_exec(
    'wris_race_setup',
    $setup$
      set session_replication_role = replica;
      delete from public.website_requirement_verifications where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_requirement_events where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_requirement_sync_runs where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_requirements where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_requirements_boards where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_work_contexts where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_concepts where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.quote_request_intakes where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.quote_requests where id = 'a2220002-0000-4000-8000-000000000001';
      insert into public.quote_requests(
        id, application_reference, record_classification, request_kind,
        created_at, name, email, website_type, budget, timing, description,
        privacy_consent, status
      ) values (
        'a2220002-0000-4000-8000-000000000001', 'LWS-AAN-2099-9299',
        'production', 'website', '2099-01-01T13:00:00Z',
        'WRIS concurrent sync', 'wris-race@example.test', 'business',
        'Meer dan EUR 6.000', 'flexible',
        'Synthetic concurrent requirements sync fixture.', true, 'approved'
      );
      insert into public.quote_request_intakes(
        id, quote_request_id, status, access_token_hash, access_token_expires_at,
        started_at, submitted_at, business_description, target_audience,
        has_existing_website, website_goals, primary_conversion_goal,
        requested_pages, requested_features, shop_required, booking_required,
        languages, design_styles, brand_colors, inspiration_sites, image_support,
        seo_keywords, social_channels, integrations, budget_confirmed,
        priorities, additional_notes, confirmation, draft_revision
      ) values (
        'a2220002-0000-4000-8000-000000000002',
        'a2220002-0000-4000-8000-000000000001',
        'submitted', repeat('9', 64), '2099-01-03T00:00:00Z',
        '2099-01-01T13:05:00Z', '2099-01-01T13:10:00Z',
        'Concurrent requirements scope', 'Concurrency test', false,
        array['generate_leads'], 'Vraag een offerte', array['home'],
        array['contact_form'], false, false, array['nl'], array['modern'],
        array[]::text[], array[]::text[], array[]::text[], array[]::text[],
        array[]::text[], array[]::text[], true,
        array['professional_appearance'], 'Concurrent sync.', true, 1
      );
      insert into public.website_concepts(
        concept_id, quote_request_id, mode, briefing_status, commercially_released,
        concept_status, promoted_project_id, revision, created_by
      ) values (
        'a2220002-0000-4000-8000-000000000003',
        'a2220002-0000-4000-8000-000000000001',
        'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', null, 1,
        'e409bd5b-1b99-4c55-8192-2a06011aa7f5'
      );
      insert into public.website_work_contexts(
        website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
      ) values (
        'a2220002-0000-4000-8000-000000000004',
        'a2220002-0000-4000-8000-000000000001',
        'a2220002-0000-4000-8000-000000000003', null, 'PRE_PROJECT', 1
      );
      set session_replication_role = origin;
    $setup$
  )$test$,
  'committed concurrency fixture is created outside the pgTAP transaction'
);
select is(
  extensions.dblink_connect(
    'wris_race_a',
    'host=' || host(inet_server_addr()) || ' port=' || current_setting('port')
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres application_name=wris_race_a'
  ),
  'OK',
  'first requirements race connection opens'
);
select is(
  extensions.dblink_connect(
    'wris_race_b',
    'host=' || host(inet_server_addr()) || ' port=' || current_setting('port')
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres application_name=wris_race_b'
  ),
  'OK',
  'second requirements race connection opens'
);
select is(
  extensions.dblink_exec(
    'wris_race_a',
    $$begin;
      select set_config('request.jwt.claims',
        '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
        false);
      set local role authenticated$$
  ),
  'SET',
  'first requirements race transaction and caller context start'
);
create temporary table requirements_race_first_result as
select result
from extensions.dblink(
  'wris_race_a',
  $$select public.sync_website_requirements_from_intake_v1(
    'a2220002-0000-4000-8000-000000000001',
    'a2220002-0000-4000-8000-000000000004',
    0,
    'a2220002-0000-4000-8000-000000000005'
  )$$
) as command(result jsonb);
select is(
  extensions.dblink_exec(
    'wris_race_b',
    $$begin;
      select set_config('request.jwt.claims',
        '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
        false);
      set local role authenticated$$
  ),
  'SET',
  'second requirements race transaction and caller context start'
);
select ok(
  extensions.dblink_send_query(
    'wris_race_b',
    $$select public.sync_website_requirements_from_intake_v1(
      'a2220002-0000-4000-8000-000000000001',
      'a2220002-0000-4000-8000-000000000004',
      0,
      'a2220002-0000-4000-8000-000000000005'
    )$$
  ) = 1,
  'second identical sync starts while the winner holds its lock'
);
select is(extensions.dblink_exec('wris_race_a', 'commit'), 'COMMIT', 'first concurrent sync commits');
create temporary table requirements_race_second_result as
select result
from extensions.dblink_get_result('wris_race_b') as command(result jsonb);
select is(
  (select result from requirements_race_second_result),
  (select result from requirements_race_first_result),
  'concurrent identical sync returns the single stored logical result'
);
select is(
  (select jsonb_build_array(
    (select count(*) from public.website_requirements_boards where quote_request_id = 'a2220002-0000-4000-8000-000000000001'),
    (select count(*) from public.website_requirement_sync_runs where quote_request_id = 'a2220002-0000-4000-8000-000000000001'),
    (select revision from public.website_requirements_boards where quote_request_id = 'a2220002-0000-4000-8000-000000000001')
  )),
  '[1,1,1]'::jsonb,
  'concurrent identical sync creates one board, one logical result, and one revision'
);
select ok(
  (select count(*) > 0
     and count(*) = count(distinct source_key)
   from public.website_requirements
   where quote_request_id = 'a2220002-0000-4000-8000-000000000001'),
  'concurrent identical sync creates each requirement source exactly once'
);
select is(extensions.dblink_disconnect('wris_race_a'), 'OK', 'first requirements race connection closes');
select is(extensions.dblink_disconnect('wris_race_b'), 'OK', 'second requirements race connection closes');
select lives_ok(
  $test$select extensions.dblink_exec(
    'wris_race_setup',
    $cleanup$
      set session_replication_role = replica;
      delete from public.website_requirement_verifications where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_requirement_events where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_requirement_sync_runs where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_requirements where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_requirements_boards where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_work_contexts where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.website_concepts where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.quote_request_intakes where quote_request_id = 'a2220002-0000-4000-8000-000000000001';
      delete from public.quote_requests where id = 'a2220002-0000-4000-8000-000000000001';
      set session_replication_role = origin;
    $cleanup$
  )$test$,
  'committed concurrency fixture is removed'
);
select is(extensions.dblink_disconnect('wris_race_setup'), 'OK', 'concurrency setup connection closes');

select * from finish();
rollback;
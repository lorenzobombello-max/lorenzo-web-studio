alter table public.quote_request_intakes
  add column draft_revision bigint not null default 0;

alter table public.quote_request_intakes
  add constraint quote_request_intakes_draft_revision_nonnegative
    check (draft_revision >= 0);

create function public.inspect_quote_request_intake_details_v5(p_access_token_hash text)
returns table (
  intake_id uuid, intake_status text, quote_request_created_at timestamptz,
  name text, company text, email text, phone text, website_type text,
  budget text, timing text, description text, started_at timestamptz,
  submitted_at timestamptz, reviewed_at timestamptz, intake_data jsonb,
  pricing_snapshot jsonb, draft_revision bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select details.intake_id, details.intake_status, details.quote_request_created_at,
    details.name, details.company, details.email, details.phone, details.website_type,
    details.budget, details.timing, details.description, details.started_at,
    details.submitted_at, details.reviewed_at, details.intake_data,
    details.pricing_snapshot, intake.draft_revision
  from public.inspect_quote_request_intake_details_v4(p_access_token_hash) as details
  join public.quote_request_intakes as intake on intake.id = details.intake_id
$$;

comment on function public.inspect_quote_request_intake_details_v5(text) is
  'Service-role-only customer intake inspection with an atomic draft revision read.';

revoke all
on function public.inspect_quote_request_intake_details_v5(text)
from public, anon, authenticated;

grant execute
on function public.inspect_quote_request_intake_details_v5(text)
to service_role;

create function public.save_quote_request_intake_draft_v2(
  p_access_token_hash text,
  p_expected_revision bigint,
  p_legacy_data jsonb,
  p_evidence_data jsonb
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  updated_at timestamptz,
  draft_revision bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
  v_save_result record;
begin
  if p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;

  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception using errcode = '22023', message = 'INVALID_EXPECTED_REVISION';
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
      'invalid_token'::text, null::text, null::timestamptz,
      null::timestamptz, null::bigint;
    return;
  end if;

  if v_intake.status not in ('invited', 'in_progress') then
    return query select
      'not_editable'::text, v_intake.status::text, v_intake.started_at,
      v_intake.updated_at, v_intake.draft_revision;
    return;
  end if;

  if v_intake.draft_revision <> p_expected_revision then
    return query select
      'stale_revision'::text, v_intake.status::text, v_intake.started_at,
      v_intake.updated_at, v_intake.draft_revision;
    return;
  end if;

  select *
    into v_save_result
    from public.update_quote_request_intake_with_evidence(
      p_access_token_hash,
      'save_draft',
      p_legacy_data,
      p_evidence_data
    );

  if v_save_result.outcome <> 'saved' then
    raise exception using errcode = '40001', message = 'INTAKE_DRAFT_SAVE_ROLLBACK';
  end if;

  update public.quote_request_intakes as intake
  set draft_revision = intake.draft_revision + 1
  where intake.id = v_intake.id
  returning * into v_intake;

  return query select
    'saved'::text, v_intake.status::text, v_intake.started_at,
    v_intake.updated_at, v_intake.draft_revision;
end;
$$;

comment on function public.save_quote_request_intake_draft_v2(text, bigint, jsonb, jsonb) is
  'Service-role-only optimistic-concurrency boundary for validated customer draft saves.';

revoke all
on function public.save_quote_request_intake_draft_v2(text, bigint, jsonb, jsonb)
from public, anon, authenticated;

grant execute
on function public.save_quote_request_intake_draft_v2(text, bigint, jsonb, jsonb)
to service_role;

create function public.reset_quote_request_intake_draft_v1(
  p_access_token_hash text,
  p_expected_revision bigint
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  updated_at timestamptz,
  draft_revision bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  if p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;

  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception using errcode = '22023', message = 'INVALID_EXPECTED_REVISION';
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
      'invalid_token'::text, null::text, null::timestamptz,
      null::timestamptz, null::bigint;
    return;
  end if;

  if v_intake.status not in ('invited', 'in_progress') then
    return query select
      'not_editable'::text, v_intake.status::text, v_intake.started_at,
      v_intake.updated_at, v_intake.draft_revision;
    return;
  end if;

  if v_intake.draft_revision <> p_expected_revision then
    return query select
      'stale_revision'::text, v_intake.status::text, v_intake.started_at,
      v_intake.updated_at, v_intake.draft_revision;
    return;
  end if;

  update public.quote_request_intakes as intake
  set
    business_description = null,
    target_audience = null,
    has_existing_website = null,
    existing_website_url = null,
    elements_to_keep = null,
    improvement_areas = null,
    website_goals = '{}'::text[],
    primary_conversion_goal = null,
    requested_pages = '{}'::text[],
    other_pages = null,
    requested_features = '{}'::text[],
    shop_required = false,
    shop_details = null,
    booking_required = false,
    booking_details = null,
    languages = array['nl']::text[],
    design_styles = '{}'::text[],
    brand_status = null,
    logo_status = null,
    brand_colors = '{}'::text[],
    inspiration_sites = '{}'::text[],
    disliked_styles = null,
    content_status = null,
    image_status = null,
    image_support = '{}'::text[],
    domain_status = null,
    domain_name = null,
    hosting_status = null,
    hosting_support = null,
    maintenance_interest = null,
    seo_priority = null,
    seo_keywords = '{}'::text[],
    social_channels = '{}'::text[],
    integrations = '{}'::text[],
    deadline_date = null,
    deadline_reason = null,
    budget_confirmed = null,
    budget_update_category = null,
    budget_notes = null,
    priorities = '{}'::text[],
    additional_notes = null,
    confirmation = false,
    primary_language = null,
    additional_languages = null,
    page_scope_details = null,
    quote_form_details = null,
    multilingual_details = null,
    download_details = null,
    content_media_details = null,
    newsletter_details = null,
    hosting_maintenance_details = null,
    deadline_details = null,
    seo_details = null,
    budget_update_category_scheme = null,
    budget_update_category_code = null,
    selected_package_definition_id = null,
    draft_revision = intake.draft_revision + 1
  where intake.id = v_intake.id
  returning * into v_intake;

  return query select
    'reset'::text, v_intake.status::text, v_intake.started_at,
    v_intake.updated_at, v_intake.draft_revision;
end;
$$;

comment on function public.reset_quote_request_intake_draft_v1(text, bigint) is
  'Service-role-only atomic draft reset. Preserves intake identity, capability, lifecycle, audit, and submitted pricing records.';

revoke all
on function public.reset_quote_request_intake_draft_v1(text, bigint)
from public, anon, authenticated;

grant execute
on function public.reset_quote_request_intake_draft_v1(text, bigint)
to service_role;

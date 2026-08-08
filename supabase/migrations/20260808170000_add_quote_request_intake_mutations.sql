create or replace function public.update_quote_request_intake(
  p_access_token_hash text,
  p_action text,
  p_data jsonb
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  submitted_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
  v_now timestamptz;
  v_allowed_keys constant text[] := array[
    'business_description', 'target_audience', 'has_existing_website', 'existing_website_url',
    'elements_to_keep', 'improvement_areas', 'website_goals', 'primary_conversion_goal',
    'requested_pages', 'other_pages', 'requested_features', 'shop_required', 'shop_details',
    'booking_required', 'booking_details', 'languages', 'design_styles', 'brand_status',
    'logo_status', 'brand_colors', 'inspiration_sites', 'disliked_styles', 'content_status',
    'image_status', 'image_support', 'domain_status', 'domain_name', 'hosting_status',
    'hosting_support', 'maintenance_interest', 'seo_priority', 'seo_keywords', 'social_channels',
    'integrations', 'deadline_date', 'deadline_reason', 'budget_confirmed',
    'budget_update_category', 'budget_notes', 'priorities', 'additional_notes', 'confirmation'
  ];
begin
  if p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;

  if p_action not in ('save_draft', 'submit') then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_ACTION';
  end if;

  if p_data is null or jsonb_typeof(p_data) <> 'object' or exists (
    select 1
    from jsonb_object_keys(p_data) as supplied(key)
    where not (supplied.key = any(v_allowed_keys))
  ) then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_DATA';
  end if;

  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for update;

  if not found
     or v_intake.access_token_expires_at <= clock_timestamp()
     or v_intake.access_token_revoked_at is not null then
    return query select 'invalid_token'::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz;
    return;
  end if;

  if p_action = 'submit' and v_intake.status = 'submitted' then
    return query select
      'already_submitted'::text,
      v_intake.status::text,
      v_intake.started_at,
      v_intake.submitted_at,
      v_intake.updated_at;
    return;
  end if;

  if v_intake.status not in ('invited', 'in_progress') then
    return query select
      'not_editable'::text,
      v_intake.status::text,
      v_intake.started_at,
      v_intake.submitted_at,
      v_intake.updated_at;
    return;
  end if;

  if p_action = 'submit' and (
    nullif(btrim(p_data->>'business_description'), '') is null
    or nullif(btrim(p_data->>'target_audience'), '') is null
    or nullif(btrim(p_data->>'primary_conversion_goal'), '') is null
    or jsonb_typeof(p_data->'website_goals') <> 'array'
    or jsonb_array_length(p_data->'website_goals') < 1
    or jsonb_typeof(p_data->'requested_pages') <> 'array'
    or jsonb_array_length(p_data->'requested_pages') < 1
    or jsonb_typeof(p_data->'requested_features') <> 'array'
    or jsonb_typeof(p_data->'design_styles') <> 'array'
    or jsonb_array_length(p_data->'design_styles') < 1
    or nullif(btrim(p_data->>'brand_status'), '') is null
    or nullif(btrim(p_data->>'logo_status'), '') is null
    or nullif(btrim(p_data->>'content_status'), '') is null
    or nullif(btrim(p_data->>'image_status'), '') is null
    or nullif(btrim(p_data->>'domain_status'), '') is null
    or nullif(btrim(p_data->>'hosting_status'), '') is null
    or nullif(btrim(p_data->>'maintenance_interest'), '') is null
    or nullif(btrim(p_data->>'seo_priority'), '') is null
    or jsonb_typeof(p_data->'priorities') <> 'array'
    or jsonb_array_length(p_data->'priorities') not between 1 and 3
    or coalesce((p_data->>'confirmation')::boolean, false) is not true
  ) then
    raise exception using errcode = '22023', message = 'INCOMPLETE_INTAKE_SUBMISSION';
  end if;

  v_now := clock_timestamp();

  update public.quote_request_intakes
  set
    business_description = case when p_data ? 'business_description' then p_data->>'business_description' else v_intake.business_description end,
    target_audience = case when p_data ? 'target_audience' then p_data->>'target_audience' else v_intake.target_audience end,
    has_existing_website = case when p_data ? 'has_existing_website' then (p_data->>'has_existing_website')::boolean else v_intake.has_existing_website end,
    existing_website_url = case when p_data ? 'existing_website_url' then p_data->>'existing_website_url' else v_intake.existing_website_url end,
    elements_to_keep = case when p_data ? 'elements_to_keep' then p_data->>'elements_to_keep' else v_intake.elements_to_keep end,
    improvement_areas = case when p_data ? 'improvement_areas' then p_data->>'improvement_areas' else v_intake.improvement_areas end,
    website_goals = case when p_data ? 'website_goals' then array(select jsonb_array_elements_text(p_data->'website_goals')) else v_intake.website_goals end,
    primary_conversion_goal = case when p_data ? 'primary_conversion_goal' then p_data->>'primary_conversion_goal' else v_intake.primary_conversion_goal end,
    requested_pages = case when p_data ? 'requested_pages' then array(select jsonb_array_elements_text(p_data->'requested_pages')) else v_intake.requested_pages end,
    other_pages = case when p_data ? 'other_pages' then p_data->>'other_pages' else v_intake.other_pages end,
    requested_features = case when p_data ? 'requested_features' then array(select jsonb_array_elements_text(p_data->'requested_features')) else v_intake.requested_features end,
    shop_required = case when p_data ? 'shop_required' then (p_data->>'shop_required')::boolean else v_intake.shop_required end,
    shop_details = case when p_data ? 'shop_details' then nullif(p_data->'shop_details', 'null'::jsonb) else v_intake.shop_details end,
    booking_required = case when p_data ? 'booking_required' then (p_data->>'booking_required')::boolean else v_intake.booking_required end,
    booking_details = case when p_data ? 'booking_details' then nullif(p_data->'booking_details', 'null'::jsonb) else v_intake.booking_details end,
    languages = case when p_data ? 'languages' then array(select jsonb_array_elements_text(p_data->'languages')) else v_intake.languages end,
    design_styles = case when p_data ? 'design_styles' then array(select jsonb_array_elements_text(p_data->'design_styles')) else v_intake.design_styles end,
    brand_status = case when p_data ? 'brand_status' then p_data->>'brand_status' else v_intake.brand_status end,
    logo_status = case when p_data ? 'logo_status' then p_data->>'logo_status' else v_intake.logo_status end,
    brand_colors = case when p_data ? 'brand_colors' then array(select jsonb_array_elements_text(p_data->'brand_colors')) else v_intake.brand_colors end,
    inspiration_sites = case when p_data ? 'inspiration_sites' then array(select jsonb_array_elements_text(p_data->'inspiration_sites')) else v_intake.inspiration_sites end,
    disliked_styles = case when p_data ? 'disliked_styles' then p_data->>'disliked_styles' else v_intake.disliked_styles end,
    content_status = case when p_data ? 'content_status' then p_data->>'content_status' else v_intake.content_status end,
    image_status = case when p_data ? 'image_status' then p_data->>'image_status' else v_intake.image_status end,
    image_support = case when p_data ? 'image_support' then array(select jsonb_array_elements_text(p_data->'image_support')) else v_intake.image_support end,
    domain_status = case when p_data ? 'domain_status' then p_data->>'domain_status' else v_intake.domain_status end,
    domain_name = case when p_data ? 'domain_name' then p_data->>'domain_name' else v_intake.domain_name end,
    hosting_status = case when p_data ? 'hosting_status' then p_data->>'hosting_status' else v_intake.hosting_status end,
    hosting_support = case when p_data ? 'hosting_support' then p_data->>'hosting_support' else v_intake.hosting_support end,
    maintenance_interest = case when p_data ? 'maintenance_interest' then p_data->>'maintenance_interest' else v_intake.maintenance_interest end,
    seo_priority = case when p_data ? 'seo_priority' then p_data->>'seo_priority' else v_intake.seo_priority end,
    seo_keywords = case when p_data ? 'seo_keywords' then array(select jsonb_array_elements_text(p_data->'seo_keywords')) else v_intake.seo_keywords end,
    social_channels = case when p_data ? 'social_channels' then array(select jsonb_array_elements_text(p_data->'social_channels')) else v_intake.social_channels end,
    integrations = case when p_data ? 'integrations' then array(select jsonb_array_elements_text(p_data->'integrations')) else v_intake.integrations end,
    deadline_date = case when p_data ? 'deadline_date' then (p_data->>'deadline_date')::date else v_intake.deadline_date end,
    deadline_reason = case when p_data ? 'deadline_reason' then p_data->>'deadline_reason' else v_intake.deadline_reason end,
    budget_confirmed = case when p_data ? 'budget_confirmed' then (p_data->>'budget_confirmed')::boolean else v_intake.budget_confirmed end,
    budget_update_category = case when p_data ? 'budget_update_category' then p_data->>'budget_update_category' else v_intake.budget_update_category end,
    budget_notes = case when p_data ? 'budget_notes' then p_data->>'budget_notes' else v_intake.budget_notes end,
    priorities = case when p_data ? 'priorities' then array(select jsonb_array_elements_text(p_data->'priorities')) else v_intake.priorities end,
    additional_notes = case when p_data ? 'additional_notes' then p_data->>'additional_notes' else v_intake.additional_notes end,
    confirmation = case when p_data ? 'confirmation' then (p_data->>'confirmation')::boolean else v_intake.confirmation end,
    started_at = coalesce(v_intake.started_at, v_now),
    submitted_at = case when p_action = 'submit' then v_now else v_intake.submitted_at end,
    status = case when p_action = 'submit' then 'submitted'::public.quote_request_intake_status else 'in_progress'::public.quote_request_intake_status end
  where id = v_intake.id
  returning * into v_intake;

  return query select
    case when p_action = 'submit' then 'submitted'::text else 'saved'::text end,
    v_intake.status::text,
    v_intake.started_at,
    v_intake.submitted_at,
    v_intake.updated_at;
end;
$$;

revoke all
on function public.update_quote_request_intake(text, text, jsonb)
from public, anon, authenticated;

grant execute
on function public.update_quote_request_intake(text, text, jsonb)
to service_role;
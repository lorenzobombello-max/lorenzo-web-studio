create or replace function public.inspect_quote_request_intake_details(p_access_token_hash text)
returns table (
  intake_id uuid,
  intake_status text,
  quote_request_created_at timestamptz,
  name text,
  company text,
  email text,
  phone text,
  website_type text,
  budget text,
  timing text,
  description text,
  started_at timestamptz,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  intake_data jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intake.id,
    intake.status::text,
    request.created_at,
    request.name,
    request.company,
    request.email,
    request.phone,
    request.website_type,
    request.budget,
    request.timing,
    request.description,
    intake.started_at,
    intake.submitted_at,
    intake.reviewed_at,
    jsonb_build_object(
      'business_description', intake.business_description,
      'target_audience', intake.target_audience,
      'has_existing_website', intake.has_existing_website,
      'existing_website_url', intake.existing_website_url,
      'elements_to_keep', intake.elements_to_keep,
      'improvement_areas', intake.improvement_areas,
      'website_goals', intake.website_goals,
      'primary_conversion_goal', intake.primary_conversion_goal,
      'requested_pages', intake.requested_pages,
      'other_pages', intake.other_pages,
      'requested_features', intake.requested_features,
      'shop_required', intake.shop_required,
      'shop_details', intake.shop_details,
      'booking_required', intake.booking_required,
      'booking_details', intake.booking_details,
      'languages', intake.languages,
      'design_styles', intake.design_styles,
      'brand_status', intake.brand_status,
      'logo_status', intake.logo_status,
      'brand_colors', intake.brand_colors,
      'inspiration_sites', intake.inspiration_sites,
      'disliked_styles', intake.disliked_styles,
      'content_status', intake.content_status,
      'image_status', intake.image_status,
      'image_support', intake.image_support,
      'domain_status', intake.domain_status,
      'domain_name', intake.domain_name,
      'hosting_status', intake.hosting_status,
      'hosting_support', intake.hosting_support,
      'maintenance_interest', intake.maintenance_interest,
      'seo_priority', intake.seo_priority,
      'seo_keywords', intake.seo_keywords,
      'social_channels', intake.social_channels,
      'integrations', intake.integrations,
      'deadline_date', intake.deadline_date,
      'deadline_reason', intake.deadline_reason,
      'budget_confirmed', intake.budget_confirmed,
      'budget_update_category', intake.budget_update_category,
      'budget_notes', intake.budget_notes,
      'priorities', intake.priorities,
      'additional_notes', intake.additional_notes,
      'confirmation', intake.confirmation
    )
  from public.quote_request_intakes as intake
  inner join public.quote_requests as request
    on request.id = intake.quote_request_id
  where intake.access_token_hash = p_access_token_hash
    and intake.access_token_expires_at > clock_timestamp()
    and intake.access_token_revoked_at is null
  limit 1
$$;

revoke all
on function public.inspect_quote_request_intake_details(text)
from public, anon, authenticated;

grant execute
on function public.inspect_quote_request_intake_details(text)
to service_role;
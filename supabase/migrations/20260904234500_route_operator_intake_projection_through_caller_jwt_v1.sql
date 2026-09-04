create function public.get_operator_submitted_application_intake_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid() <> p_actor_auth_user_id then
    raise exception using errcode = '42501', message = 'OPERATOR_IDENTITY_MISMATCH';
  end if;

  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);

  select jsonb_build_object(
    'id', intake.id,
    'quote_request_id', intake.quote_request_id,
    'status', intake.status,
    'submitted_at', intake.submitted_at,
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
    'primary_language', intake.primary_language,
    'additional_languages', intake.additional_languages,
    'page_scope_details', intake.page_scope_details,
    'quote_form_details', intake.quote_form_details,
    'multilingual_details', intake.multilingual_details,
    'download_details', intake.download_details,
    'newsletter_details', intake.newsletter_details
  ) || jsonb_build_object(
    'integrations', intake.integrations,
    'social_channels', intake.social_channels,
    'seo_priority', intake.seo_priority,
    'seo_details', intake.seo_details,
    'brand_status', intake.brand_status,
    'logo_status', intake.logo_status,
    'brand_colors', intake.brand_colors,
    'design_styles', intake.design_styles,
    'inspiration_sites', intake.inspiration_sites,
    'disliked_styles', intake.disliked_styles,
    'content_status', intake.content_status,
    'image_status', intake.image_status,
    'image_support', intake.image_support,
    'content_media_details', intake.content_media_details,
    'domain_status', intake.domain_status,
    'domain_name', intake.domain_name,
    'hosting_status', intake.hosting_status,
    'maintenance_interest', intake.maintenance_interest,
    'hosting_support', intake.hosting_support,
    'hosting_maintenance_details', intake.hosting_maintenance_details,
    'deadline_date', intake.deadline_date,
    'deadline_reason', intake.deadline_reason,
    'deadline_details', intake.deadline_details,
    'priorities', intake.priorities,
    'budget_notes', intake.budget_notes,
    'additional_notes', intake.additional_notes
  )
  into v_result
  from public.quote_request_intakes as intake
  inner join public.quote_requests as request on request.id = intake.quote_request_id
  where intake.quote_request_id = p_quote_request_id
    and intake.status in ('submitted', 'reviewed')
    and request.record_classification in ('production', 'internal_e2e')
    and request.request_kind = 'website';

  return v_result;
end;
$$;

revoke all on function public.get_operator_submitted_application_intake_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_submitted_application_intake_v1(uuid, uuid)
to authenticated;

comment on function public.get_operator_submitted_application_intake_v1(uuid, uuid) is
  'Authenticated owner/admin submitted Website intake projection bound to the caller Auth UUID.';
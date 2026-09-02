create function public.get_operator_dossier_substance_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_request public.quote_requests%rowtype;
  v_website_intake public.quote_request_intakes%rowtype;
  v_sdf_intake public.sdf_qualification_intakes%rowtype;
  v_sdf_answers jsonb;
  v_intake jsonb;
  v_customer_request_count integer;
  v_uploaded_document_count integer;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id
    and record_classification = 'production';
  if not found then
    raise exception using errcode = 'P0001', message = 'DOSSIER_SUBSTANCE_NOT_FOUND';
  end if;

  if v_request.request_kind = 'website' then
    select * into v_website_intake
    from public.quote_request_intakes
    where quote_request_id = v_request.id;
    if not found then
      raise exception using errcode = 'P0001', message = 'DOSSIER_INTAKE_NOT_FOUND';
    end if;

    v_intake := jsonb_build_object(
      'intake_id', v_website_intake.id,
      'status', v_website_intake.status,
      'invitation_state', case when v_website_intake.status = 'invited' then 'INVITED' else 'ACTIVATED' end,
      'invited_at', v_website_intake.created_at,
      'started_at', v_website_intake.started_at,
      'submitted_at', v_website_intake.submitted_at,
      'structured_answers', jsonb_build_object(
        'business_description', v_website_intake.business_description,
        'target_audience', v_website_intake.target_audience,
        'has_existing_website', v_website_intake.has_existing_website,
        'existing_website_url', v_website_intake.existing_website_url,
        'elements_to_keep', v_website_intake.elements_to_keep,
        'improvement_areas', v_website_intake.improvement_areas,
        'website_goals', v_website_intake.website_goals,
        'primary_conversion_goal', v_website_intake.primary_conversion_goal,
        'requested_pages', v_website_intake.requested_pages,
        'other_pages', v_website_intake.other_pages,
        'requested_features', v_website_intake.requested_features,
        'shop_required', v_website_intake.shop_required,
        'shop_details', case when v_website_intake.shop_details is null then null else jsonb_build_object(
          'approx_product_count', v_website_intake.shop_details -> 'approx_product_count',
          'complex_product_count', v_website_intake.shop_details -> 'complex_product_count',
          'payment_provider_count', v_website_intake.shop_details -> 'payment_provider_count',
          'shipping_scope', v_website_intake.shop_details -> 'shipping_scope',
          'categories', v_website_intake.shop_details -> 'categories',
          'online_payments', v_website_intake.shop_details -> 'online_payments',
          'shipping', v_website_intake.shop_details -> 'shipping',
          'pickup', v_website_intake.shop_details -> 'pickup',
          'pickup_scope', v_website_intake.shop_details -> 'pickup_scope',
          'existing_catalog', v_website_intake.shop_details -> 'existing_catalog',
          'customer_accounts', v_website_intake.shop_details -> 'customer_accounts',
          'catalog_import', v_website_intake.shop_details -> 'catalog_import',
          'erp_api', v_website_intake.shop_details -> 'erp_api'
        ) end,
        'booking_required', v_website_intake.booking_required,
        'booking_details', case when v_website_intake.booking_details is null then null else jsonb_build_object(
          'tier', v_website_intake.booking_details -> 'tier',
          'type', v_website_intake.booking_details -> 'type',
          'existing_system', v_website_intake.booking_details -> 'existing_system',
          'existing_system_name', v_website_intake.booking_details -> 'existing_system_name',
          'calendar_integration', v_website_intake.booking_details -> 'calendar_integration'
        ) end,
        'languages', v_website_intake.languages,
        'primary_language', v_website_intake.primary_language,
        'additional_languages', v_website_intake.additional_languages,
        'page_scope_details', case when v_website_intake.page_scope_details is null then null else jsonb_build_object(
          'portfolio', v_website_intake.page_scope_details -> 'portfolio',
          'reviews', v_website_intake.page_scope_details -> 'reviews',
          'blog', v_website_intake.page_scope_details -> 'blog',
          'jobs', v_website_intake.page_scope_details -> 'jobs',
          'gallery', v_website_intake.page_scope_details -> 'gallery',
          'jobs_application', v_website_intake.page_scope_details -> 'jobs_application',
          'search', v_website_intake.page_scope_details -> 'search'
        ) end,
        'quote_form_details', case when v_website_intake.quote_form_details is null then null else jsonb_build_object(
          'file_uploads', v_website_intake.quote_form_details -> 'file_uploads',
          'database_workflow', v_website_intake.quote_form_details -> 'database_workflow',
          'automated_processing', v_website_intake.quote_form_details -> 'automated_processing',
          'review_approval', v_website_intake.quote_form_details -> 'review_approval',
          'custom_logic', v_website_intake.quote_form_details -> 'custom_logic',
          'form_count', v_website_intake.quote_form_details -> 'form_count',
          'structure_scope', v_website_intake.quote_form_details -> 'structure_scope'
        ) end,
        'multilingual_details', case when v_website_intake.multilingual_details is null then null else jsonb_build_object(
          'final_translations_supplied', v_website_intake.multilingual_details -> 'final_translations_supplied',
          'same_structure', v_website_intake.multilingual_details -> 'same_structure',
          'translation_required', v_website_intake.multilingual_details -> 'translation_required',
          'seo_per_language', v_website_intake.multilingual_details -> 'seo_per_language',
          'advanced_seo_research', v_website_intake.multilingual_details -> 'advanced_seo_research',
          'language_specific_integrations', v_website_intake.multilingual_details -> 'language_specific_integrations',
          'complex_scope', v_website_intake.multilingual_details -> 'complex_scope'
        ) end,
        'download_details', case when v_website_intake.download_details is null then null else jsonb_build_object(
          'access', v_website_intake.download_details -> 'access'
        ) end,
        'newsletter_details', case when v_website_intake.newsletter_details is null then null else jsonb_build_object(
          'scope', v_website_intake.newsletter_details -> 'scope',
          'analytics', v_website_intake.newsletter_details -> 'analytics',
          'custom_integration', v_website_intake.newsletter_details -> 'custom_integration'
        ) end,
        'content_media_details', case when v_website_intake.content_media_details is null then null else jsonb_build_object(
          'copywriting_scope', v_website_intake.content_media_details -> 'copywriting_scope',
          'copy_page_count', v_website_intake.content_media_details -> 'copy_page_count',
          'image_work_scope', v_website_intake.content_media_details -> 'image_work_scope',
          'paid_stock_handling', v_website_intake.content_media_details -> 'paid_stock_handling',
          'branding_tier', v_website_intake.content_media_details -> 'branding_tier'
        ) end,
        'hosting_maintenance_details', case when v_website_intake.hosting_maintenance_details is null then null else jsonb_build_object(
          'hosting_support', v_website_intake.hosting_maintenance_details -> 'hosting_support',
          'maintenance_interest', v_website_intake.hosting_maintenance_details -> 'maintenance_interest',
          'domain_service', v_website_intake.hosting_maintenance_details -> 'domain_service',
          'maintenance_plan', v_website_intake.hosting_maintenance_details -> 'maintenance_plan'
        ) end,
        'deadline_details', case when v_website_intake.deadline_details is null then null else jsonb_build_object(
          'commercially_critical', v_website_intake.deadline_details -> 'commercially_critical',
          'hard_deadline', v_website_intake.deadline_details -> 'hard_deadline'
        ) end,
        'seo_details', case when v_website_intake.seo_details is null then null else jsonb_build_object(
          'scope', v_website_intake.seo_details -> 'scope',
          'extra_language_seo', v_website_intake.seo_details -> 'extra_language_seo',
          'advanced_language_seo', v_website_intake.seo_details -> 'advanced_language_seo'
        ) end
      ) || jsonb_build_object(
        'design_styles', v_website_intake.design_styles,
        'brand_status', v_website_intake.brand_status,
        'logo_status', v_website_intake.logo_status,
        'brand_colors', v_website_intake.brand_colors,
        'inspiration_sites', v_website_intake.inspiration_sites,
        'disliked_styles', v_website_intake.disliked_styles,
        'content_status', v_website_intake.content_status,
        'image_status', v_website_intake.image_status,
        'image_support', v_website_intake.image_support,
        'domain_status', v_website_intake.domain_status,
        'domain_name', v_website_intake.domain_name,
        'hosting_status', v_website_intake.hosting_status,
        'hosting_support', v_website_intake.hosting_support,
        'maintenance_interest', v_website_intake.maintenance_interest,
        'seo_priority', v_website_intake.seo_priority,
        'seo_keywords', v_website_intake.seo_keywords,
        'social_channels', v_website_intake.social_channels,
        'integrations', v_website_intake.integrations,
        'deadline_date', v_website_intake.deadline_date,
        'deadline_reason', v_website_intake.deadline_reason,
        'budget_confirmed', v_website_intake.budget_confirmed,
        'budget_update_category', v_website_intake.budget_update_category,
        'budget_notes', v_website_intake.budget_notes,
        'priorities', v_website_intake.priorities,
        'additional_notes', v_website_intake.additional_notes,
        'confirmation', v_website_intake.confirmation
      )
    );
  elsif v_request.request_kind = 'slimme_documentenflow' then
    select * into v_sdf_intake
    from public.sdf_qualification_intakes
    where quote_request_id = v_request.id;
    if not found then
      raise exception using errcode = 'P0001', message = 'DOSSIER_INTAKE_NOT_FOUND';
    end if;

    select submission.answers into v_sdf_answers
    from public.sdf_qualification_intake_submissions as submission
    where submission.intake_id = v_sdf_intake.intake_id
    order by submission.submission_sequence desc
    limit 1;
    v_sdf_answers := coalesce(v_sdf_answers, v_sdf_intake.draft_answers, '{}'::jsonb);

    v_intake := jsonb_build_object(
      'intake_id', v_sdf_intake.intake_id,
      'status', v_sdf_intake.status,
      'invitation_state', case when v_sdf_intake.status = 'invited' then 'INVITED' else 'ACTIVATED' end,
      'invited_at', v_sdf_intake.invited_at,
      'started_at', case when v_sdf_intake.status = 'invited' then null else v_sdf_intake.updated_at end,
      'submitted_at', v_sdf_intake.submitted_at,
      'structured_answers', jsonb_build_object(
        'documentPurpose', jsonb_build_object(
          'categories', coalesce(v_sdf_answers #> '{documentPurpose,categories}', '[]'::jsonb),
          'otherDescription', v_sdf_answers #> '{documentPurpose,otherDescription}'
        ),
        'workflowCapabilities', coalesce(v_sdf_answers -> 'workflowCapabilities', '[]'::jsonb),
        'businessRequirements', jsonb_build_object(
          'currentWorkflow', v_sdf_answers #> '{businessRequirements,currentWorkflow}',
          'desiredWorkflow', v_sdf_answers #> '{businessRequirements,desiredWorkflow}',
          'volumeBand', v_sdf_answers #> '{businessRequirements,volumeBand}',
          'frequency', v_sdf_answers #> '{businessRequirements,frequency}',
          'relevantDocumentTypes', coalesce(v_sdf_answers #> '{businessRequirements,relevantDocumentTypes}', '[]'::jsonb),
          'rolesUsers', coalesce(v_sdf_answers #> '{businessRequirements,rolesUsers}', '[]'::jsonb)
        ),
        'sampleDocumentMetadata', jsonb_build_object(
          'available', v_sdf_answers #> '{sampleDocumentMetadata,available}',
          'requestedByLws', v_sdf_answers #> '{sampleDocumentMetadata,requestedByLws}',
          'uploadRequiredLater', v_sdf_answers #> '{sampleDocumentMetadata,uploadRequiredLater}'
        ),
        'commercialQualification', jsonb_build_object(
          'packageDirection', v_sdf_answers #> '{commercialQualification,packageDirection}',
          'customComplexity', v_sdf_answers #> '{commercialQualification,customComplexity}',
          'documentVolumes', coalesce((
            select jsonb_agg(jsonb_build_object(
              'documentType', volume -> 'documentType',
              'documentCount', volume -> 'documentCount',
              'period', volume -> 'period',
              'averagePagesPerDocument', volume -> 'averagePagesPerDocument'
            ))
            from jsonb_array_elements(case
              when jsonb_typeof(v_sdf_answers #> '{commercialQualification,documentVolumes}') = 'array'
                then v_sdf_answers #> '{commercialQualification,documentVolumes}'
              else '[]'::jsonb
            end) as volume
          ), '[]'::jsonb),
          'flowCount', v_sdf_answers #> '{commercialQualification,flowCount}',
          'userCount', v_sdf_answers #> '{commercialQualification,userCount}'
        )
      )
    );
  else
    raise exception using errcode = 'P0001', message = 'DOSSIER_PRODUCT_NOT_SUPPORTED';
  end if;

  select count(*)::integer into v_customer_request_count
  from public.customer_requests
  where quote_request_id = v_request.id;

  select count(*)::integer into v_uploaded_document_count
  from public.customer_request_uploaded_files as uploaded
  join public.customer_requests as customer_request
    on customer_request.request_id = uploaded.customer_request_id
  where customer_request.quote_request_id = v_request.id;

  return jsonb_build_object(
    'quote_request_id', v_request.id,
    'request_kind', v_request.request_kind,
    'request', jsonb_build_object(
      'reference', coalesce(v_request.application_reference, v_request.support_reference),
      'original_text', v_request.description,
      'requested_service', case
        when v_request.request_kind = 'website' then v_request.website_type
        else 'Slimme Documentenflow - ' || v_request.sdf_package
      end,
      'requested_at', v_request.created_at
    ),
    'customer', jsonb_build_object(
      'name', v_request.name,
      'company', v_request.company,
      'email', v_request.email,
      'phone', v_request.phone
    ),
    'intake', v_intake,
    'documents', jsonb_build_object(
      'customer_request_count', v_customer_request_count,
      'uploaded_document_count', v_uploaded_document_count
    )
  );
end;
$$;

revoke all on function public.get_operator_dossier_substance_v1(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.get_operator_dossier_substance_v1(uuid, uuid)
to service_role;

comment on function public.get_operator_dossier_substance_v1(uuid, uuid) is
  'Record-bound, active owner/admin Operator projection of original request text, allowlisted intake answers, customer identity, and linked document counts. No capabilities or raw audit metadata.';
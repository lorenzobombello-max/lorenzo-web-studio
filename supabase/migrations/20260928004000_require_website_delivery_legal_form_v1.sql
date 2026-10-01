create or replace function public.prepare_website_delivery_document_v1(
  p_project_id uuid,
  p_delivery_date date,
  p_checklist jsonb,
  p_remarks_state text,
  p_remarks_text text,
  p_contractor_signature_date date,
  p_contractor_signature_place text,
  p_customer_signature_date date,
  p_customer_signature_place text,
  p_idempotency_key uuid,
  p_actor text
)
returns jsonb
language plpgsql
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_project public.commercial_projects%rowtype;
  v_customer public.commercial_customers%rowtype;
  v_acceptance public.quote_request_quotation_acceptances%rowtype;
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_request public.quote_requests%rowtype;
  v_preview public.preview_versions%rowtype;
  v_customer_approval public.customer_approvals%rowtype;
  v_site public.commercial_project_sites%rowtype;
  v_statement lws_internal.customer_approval_statement_authorities%rowtype;
  v_existing public.website_delivery_document_candidates%rowtype;
  v_candidate public.website_delivery_document_candidates%rowtype;
  v_customer_payload jsonb;
  v_project_payload jsonb;
  v_payload jsonb;
  v_payload_sha256 text;
  v_version integer;
begin
  if p_project_id is null or p_delivery_date is null or p_idempotency_key is null
     or nullif(btrim(p_actor), '') is null
     or p_contractor_signature_date is null or p_customer_signature_date is null
     or nullif(btrim(p_contractor_signature_place), '') is null
     or nullif(btrim(p_customer_signature_place), '') is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_INPUT_INVALID';
  end if;
  if jsonb_typeof(p_checklist) is distinct from 'object'
     or (select count(*) from jsonb_object_keys(p_checklist)) <> 11
     or exists (
       select 1 from jsonb_each_text(p_checklist) item
       where item.key not in (
         'pages', 'desktop_browsers', 'mobile_tablet', 'forms', 'links',
         'technical_seo', 'ssl', 'hosting', 'domain', 'access_transfer', 'backup'
       ) or item.value not in ('COMPLETED', 'NOT_APPLICABLE')
     ) then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_CHECKLIST_INVALID';
  end if;
  if (p_remarks_state = 'NONE_CONFIRMED' and nullif(btrim(p_remarks_text), '') is not null)
     or (p_remarks_state = 'RECORDED' and nullif(btrim(p_remarks_text), '') is null)
     or p_remarks_state not in ('NONE_CONFIRMED', 'RECORDED') then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_REMARKS_INVALID';
  end if;

  select * into v_project from public.commercial_projects
  where project_id = p_project_id for update;
  if not found then raise exception using errcode = '23503', message = 'PROJECT_NOT_FOUND'; end if;
  if v_project.current_state <> 'FINAL_APPROVAL_RECORDED' then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_STATE_INVALID';
  end if;
  select * into strict v_customer from public.commercial_customers
  where customer_id = v_project.customer_id and acceptance_id = v_project.acceptance_id;
  select * into strict v_acceptance from public.quote_request_quotation_acceptances
  where id = v_project.acceptance_id and issuance_id = v_project.quotation_issuance_id;
  select * into strict v_issuance from public.quote_request_quotation_issuances
  where id = v_project.quotation_issuance_id;
  select * into strict v_approval from public.quote_request_quotation_approvals
  where id = v_issuance.approval_id;
  select * into strict v_request from public.quote_requests
  where id = v_approval.quote_request_id and request_kind = 'website';
  select * into strict v_preview from public.preview_versions
  where project_id = p_project_id and status = 'CURRENT';
  select * into strict v_customer_approval from public.customer_approvals
  where project_id = p_project_id and preview_version_id = v_preview.preview_version_id
    and status = 'CURRENT';
  select * into strict v_site from public.commercial_project_sites
  where project_id = p_project_id
  order by site_revision desc limit 1;
  select * into strict v_statement from lws_internal.customer_approval_statement_authorities
  where document_type = 'WEBSITE_DELIVERY_ACCEPTANCE' and status = 'CURRENT';
  if v_customer_approval.statement_version <> v_statement.authority_id
     or v_customer_approval.statement_sha256 <> v_statement.source_sha256 then
    raise exception using errcode = '23514', message = 'WEBSITE_DELIVERY_APPROVAL_AUTHORITY_MISMATCH';
  end if;

  v_customer_payload := v_approval.approved_payload->'customer_identity';
  v_project_payload := v_approval.approved_payload->'project_scope';
  if nullif(btrim(v_customer_payload->>'legal_name'), '') is null
     or nullif(btrim(v_customer_payload->>'legal_form'), '') is null
     or nullif(btrim(v_customer_payload->>'email'), '') is null
     or nullif(btrim(v_acceptance.accepting_name), '') is null
     or nullif(btrim(v_acceptance.accepting_role), '') is null
     or nullif(btrim(v_project_payload->>'project_title'), '') is null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_SOURCE_DATA_INCOMPLETE';
  end if;

  v_payload := jsonb_build_object(
    'authority', jsonb_build_object(
      'source_drive_file_id', v_statement.source_drive_id,
      'source_sha256', rtrim(v_statement.source_sha256),
      'statement_version', v_statement.authority_id
    ),
    'lineage', jsonb_build_object(
      'project_id', v_project.project_id,
      'customer_id', v_customer.customer_id,
      'preview_version_id', v_preview.preview_version_id,
      'preview_version', v_preview.version_number,
      'preview_content_reference', v_preview.content_reference,
      'preview_content_sha256', rtrim(v_preview.content_sha256)
    ),
    'customer', jsonb_build_object(
      'legal_name', btrim(v_customer_payload->>'legal_name'),
      'legal_form', btrim(v_customer_payload->>'legal_form'),
      'enterprise_number', coalesce(nullif(btrim(v_customer_payload->>'enterprise_number'), ''), 'Niet van toepassing'),
      'vat_number', coalesce(nullif(btrim(v_customer_payload->>'vat_number'), ''), 'Niet van toepassing'),
      'address', concat_ws(', ',
        nullif(btrim(concat_ws(' ', v_customer_payload->>'address_line_1', v_customer_payload->>'address_line_2')), ''),
        nullif(btrim(concat_ws(' ', v_customer_payload->>'postal_code', v_customer_payload->>'city')), ''),
        case v_customer_payload->>'country_code' when 'BE' then 'België' else v_customer_payload->>'country_code' end
      ),
      'representative_name', btrim(v_acceptance.accepting_name),
      'representative_role', btrim(v_acceptance.accepting_role),
      'email', btrim(v_customer_payload->>'email')
    ),
    'project', jsonb_build_object(
      'reference', v_request.application_reference,
      'title', btrim(v_project_payload->>'project_title'),
      'canonical_url', v_site.canonical_url,
      'delivery_date', to_char(p_delivery_date, 'DD/MM/YYYY')
    ),
    'checklist', p_checklist,
    'remarks', case p_remarks_state
      when 'NONE_CONFIRMED' then jsonb_build_object('state', p_remarks_state)
      else jsonb_build_object('state', p_remarks_state, 'text', btrim(p_remarks_text))
    end,
    'signatures', jsonb_build_object(
      'contractor_date', to_char(p_contractor_signature_date, 'DD/MM/YYYY'),
      'contractor_place', btrim(p_contractor_signature_place),
      'customer_name', btrim(v_acceptance.accepting_name),
      'customer_role', btrim(v_acceptance.accepting_role),
      'customer_date', to_char(p_customer_signature_date, 'DD/MM/YYYY'),
      'customer_place', btrim(p_customer_signature_place)
    )
  );
  if nullif(v_payload->'customer'->>'address', '') is null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_SOURCE_DATA_INCOMPLETE';
  end if;
  v_payload_sha256 := encode(extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_existing from public.website_delivery_document_candidates
  where preparation_idempotency_key = p_idempotency_key;
  if found then
    if v_existing.project_id <> p_project_id or v_existing.generation_payload_sha256 <> v_payload_sha256 then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'candidate_id', v_existing.candidate_id, 'document_version', v_existing.document_version,
      'generation_payload', v_existing.generation_payload,
      'generation_payload_sha256', rtrim(v_existing.generation_payload_sha256), 'was_created', false
    );
  end if;
  select * into v_existing from public.website_delivery_document_candidates
  where project_id = p_project_id and generation_payload_sha256 = v_payload_sha256;
  if found then
    return jsonb_build_object(
      'candidate_id', v_existing.candidate_id, 'document_version', v_existing.document_version,
      'generation_payload', v_existing.generation_payload,
      'generation_payload_sha256', rtrim(v_existing.generation_payload_sha256), 'was_created', false
    );
  end if;
  select coalesce(max(document_version), 0) + 1 into v_version
  from public.website_delivery_document_candidates where project_id = p_project_id;
  insert into public.website_delivery_document_candidates(
    project_id, customer_id, preview_version_id, preview_version,
    preview_content_reference, preview_content_sha256, source_drive_file_id,
    source_sha256, statement_version, document_version, generation_payload,
    generation_payload_sha256, preparation_idempotency_key, created_by
  ) values (
    p_project_id, v_customer.customer_id, v_preview.preview_version_id, v_preview.version_number,
    v_preview.content_reference, v_preview.content_sha256, v_statement.source_drive_id,
    v_statement.source_sha256, v_statement.authority_id, v_version, v_payload,
    v_payload_sha256, p_idempotency_key, btrim(p_actor)
  ) returning * into v_candidate;
  return jsonb_build_object(
    'candidate_id', v_candidate.candidate_id, 'document_version', v_candidate.document_version,
    'generation_payload', v_candidate.generation_payload,
    'generation_payload_sha256', rtrim(v_candidate.generation_payload_sha256), 'was_created', true
  );
end;
$$;

comment on function public.prepare_website_delivery_document_v1(uuid,date,jsonb,text,text,date,text,date,text,uuid,text) is
  'Prepares immutable OPL-W-01 input and requires an explicitly stored customer legal form; no derivation or missing-value default is permitted.';

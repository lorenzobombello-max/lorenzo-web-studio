-- W2.4.1-P3 repair (forward-only): prepare the OPL-W-01 delivery document before customer acceptance.
--
-- Source basis (read-only, unchanged):
--   * 01_Websiteontwikkelingsovereenkomst art. 6: the website is delivered when it is made available for
--     control "zoals vastgelegd in het document 'Opleverdocument'"; functional test, corrections and final
--     control follow; formal, active acceptance is required afterwards.
--   * 07_Opleverdocument (OPL-W-01): confirms delivery by the Opdrachtnemer; §4 is the Opdrachtgever's
--     acceptance declaration; Ondertekening has Naam/Functie/Datum/Plaats/Handtekening per party.
--   * package-1 spec: names, roles, dates and places only from validated records or explicit operator input.
-- Conclusion: the document is prepared while acceptance is possible (M2_PAYMENT_RECEIVED) for the CURRENT
-- preview and only while no customer approval exists for it. The customer's signature date and place belong
-- to the customer's own signing and stay empty; the acceptance moment is registered separately.

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
  if p_customer_signature_date is not null or p_customer_signature_place is not null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_CUSTOMER_SIGNATURE_BEFORE_ACCEPTANCE';
  end if;
  if p_project_id is null or p_delivery_date is null or p_idempotency_key is null
     or nullif(btrim(p_actor), '') is null
     or p_contractor_signature_date is null
     or nullif(btrim(p_contractor_signature_place), '') is null then
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
  if v_project.current_state <> 'M2_PAYMENT_RECEIVED' then
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
  select * into v_preview from public.preview_versions
  where project_id = p_project_id and status = 'CURRENT';
  if not found then raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PREVIEW_REQUIRED'; end if;
  if exists (
    select 1 from public.customer_approvals
    where project_id = p_project_id and preview_version_id = v_preview.preview_version_id
      and status = 'CURRENT'
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ALREADY_ACCEPTED';
  end if;
  select * into strict v_site from public.commercial_project_sites
  where project_id = p_project_id
  order by site_revision desc limit 1;
  select * into strict v_statement from lws_internal.customer_approval_statement_authorities
  where document_type = 'WEBSITE_DELIVERY_ACCEPTANCE' and status = 'CURRENT';

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
    -- No customer_date/customer_place: those belong to the customer's own signing, after this document.
    'signatures', jsonb_build_object(
      'contractor_date', to_char(p_contractor_signature_date, 'DD/MM/YYYY'),
      'contractor_place', btrim(p_contractor_signature_place),
      'customer_name', btrim(v_acceptance.accepting_name),
      'customer_role', btrim(v_acceptance.accepting_role)
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
  'Prepares immutable OPL-W-01 input for the CURRENT preview in M2_PAYMENT_RECEIVED before customer acceptance; customer signature date/place must stay empty.';

-- One definition of the current document for operator reads, customer reads and acceptance.
create or replace function public.resolve_website_delivery_document_view_v1(
  p_project_id uuid,
  p_preview_version_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_view public.website_delivery_document_view_derivatives%rowtype;
begin
  if p_project_id is null or p_preview_version_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_VIEW_INPUT_INVALID';
  end if;
  v_view := lws_internal.current_website_delivery_document_view_v1(p_project_id, p_preview_version_id);
  if v_view.view_derivative_id is null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'view_derivative_id', v_view.view_derivative_id,
    'artifact_id', v_view.artifact_id,
    'project_id', v_view.project_id,
    'preview_version_id', v_view.preview_version_id,
    'document_version', v_view.document_version,
    'source_docx_sha256', rtrim(v_view.source_docx_sha256),
    'storage_bucket_id', v_view.storage_bucket_id,
    'storage_object_path', v_view.storage_object_path,
    'content_type', v_view.content_type,
    'pdf_sha256', rtrim(v_view.pdf_sha256),
    'pdf_bytes', v_view.pdf_bytes
  );
end;
$$;

create or replace function public.resolve_customer_website_delivery_document_view_v1(
  p_session_digest char(64),
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_session public.preview_sessions%rowtype;
  v_access public.preview_access%rowtype;
  v_view public.website_delivery_document_view_derivatives%rowtype;
begin
  if p_project_id is null or btrim(p_session_digest::text) !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;

  select session.* into v_session
  from public.preview_sessions session
  join public.preview_access access
    on access.preview_access_id = session.preview_access_id
   and access.project_id = session.project_id
  join public.preview_versions preview
    on preview.preview_version_id = access.preview_version_id
   and preview.project_id = access.project_id
  where session.session_digest = p_session_digest
    and session.project_id = p_project_id
    and session.revoked_at is null
    and session.expires_at > clock_timestamp()
    and access.status = 'ACTIVE'
    and access.revoked_at is null
    and access.expires_at > clock_timestamp()
    and preview.status = 'CURRENT';
  if not found then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;
  select * into strict v_access from public.preview_access
  where preview_access_id = v_session.preview_access_id;

  v_view := lws_internal.current_website_delivery_document_view_v1(p_project_id, v_access.preview_version_id);
  if v_view.view_derivative_id is null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'preview_session_id', v_session.preview_session_id,
    'view_derivative_id', v_view.view_derivative_id,
    'artifact_id', v_view.artifact_id,
    'project_id', v_view.project_id,
    'preview_version_id', v_view.preview_version_id,
    'document_version', v_view.document_version,
    'source_docx_sha256', rtrim(v_view.source_docx_sha256),
    'storage_bucket_id', v_view.storage_bucket_id,
    'storage_object_path', v_view.storage_object_path,
    'content_type', v_view.content_type,
    'pdf_sha256', rtrim(v_view.pdf_sha256),
    'pdf_bytes', v_view.pdf_bytes
  );
end;
$$;

-- Integrity by constraint: the accepted receipt belongs to the same session and view, and the linked
-- approval to the same project, preview and access.
alter table public.website_delivery_document_access_receipts
  add constraint website_delivery_receipt_session_view_unique
  unique (access_receipt_id, preview_session_id, view_derivative_id);
alter table public.customer_approvals
  add constraint customer_approval_binding_unique
  unique (approval_id, project_id, preview_version_id, preview_access_id);
alter table public.website_delivery_document_acceptances
  add constraint website_delivery_acceptance_receipt_binding
  foreign key (access_receipt_id, preview_session_id, view_derivative_id)
  references public.website_delivery_document_access_receipts (access_receipt_id, preview_session_id, view_derivative_id),
  add constraint website_delivery_acceptance_approval_binding
  foreign key (customer_approval_id, project_id, preview_version_id, preview_access_id)
  references public.customer_approvals (approval_id, project_id, preview_version_id, preview_access_id);

create or replace function public.execute_customer_commercial_command_v1(
  p_session_digest char(64),
  p_project_id uuid,
  p_command_type text,
  p_expected_state text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_session public.preview_sessions%rowtype;
  v_access public.preview_access%rowtype;
  v_version public.preview_versions%rowtype;
  v_authority lws_internal.customer_approval_statement_authorities%rowtype;
  v_view public.website_delivery_document_view_derivatives%rowtype;
  v_receipt public.website_delivery_document_access_receipts%rowtype;
  v_approval public.customer_approvals%rowtype;
  v_acceptance public.website_delivery_document_acceptances%rowtype;
  v_safe_payload jsonb;
  v_result jsonb;
begin
  if p_command_type not in ('submit_customer_feedback', 'submit_customer_approval') then
    raise exception using errcode = '42501', message = 'CUSTOMER_COMMAND_DENIED';
  end if;

  select * into v_session
  from public.preview_sessions
  where session_digest = p_session_digest
    and project_id = p_project_id
    and revoked_at is null
    and expires_at > clock_timestamp();
  if not found then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;

  select * into v_access
  from public.preview_access
  where preview_access_id = v_session.preview_access_id
    and project_id = p_project_id
    and status = 'ACTIVE'
    and revoked_at is null
    and expires_at > clock_timestamp();
  if not found then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;

  v_safe_payload := (coalesce(p_payload, '{}'::jsonb) - 'preview_access_id')
    || jsonb_build_object('preview_access_id', v_access.preview_access_id);

  if p_command_type = 'submit_customer_approval' then
    -- Lost-response retry: the stored acceptance of this key is authoritative; rebuild the exact payload.
    select * into v_acceptance
    from public.website_delivery_document_acceptances
    where command_idempotency_key = p_idempotency_key;
    if found then
      if v_acceptance.project_id is distinct from p_project_id
         or v_acceptance.preview_access_id is distinct from v_access.preview_access_id then
        raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
      end if;
      v_result := lws_internal.execute_commercial_command_core_v1(
        'CUSTOMER:' || v_access.preview_access_id::text,
        p_project_id, p_command_type, p_expected_state, p_expected_revision, p_idempotency_key,
        (v_safe_payload
          - 'preview_version_id' - 'statement_version' - 'statement_sha256'
          - 'viewed_document_version' - 'viewed_pdf_sha256'
          - 'delivery_view_derivative_id' - 'delivery_document_version' - 'delivery_pdf_sha256')
        || jsonb_build_object(
          'preview_version_id', v_acceptance.preview_version_id,
          'statement_version', v_acceptance.statement_version,
          'statement_sha256', v_acceptance.statement_sha256,
          'delivery_view_derivative_id', v_acceptance.view_derivative_id,
          'delivery_document_version', v_acceptance.document_version,
          'delivery_pdf_sha256', rtrim(v_acceptance.pdf_sha256)
        )
      );
      return v_result || jsonb_build_object(
        'accepted_document_version', v_acceptance.document_version,
        'accepted_pdf_sha256', rtrim(v_acceptance.pdf_sha256),
        'accepted_at', v_acceptance.accepted_at
      );
    end if;

    -- Serialize with lifecycle commands (preview supersession runs under the same project lock).
    perform 1 from public.commercial_projects where project_id = p_project_id for update;

    select * into v_version
    from public.preview_versions
    where preview_version_id = v_access.preview_version_id
      and project_id = p_project_id
      and status = 'CURRENT';
    if not found then
      raise exception using errcode = 'P0001', message = 'PREVIEW_VERSION_MISMATCH';
    end if;

    if exists (
      select 1 from public.website_delivery_document_acceptances
      where project_id = p_project_id and preview_version_id = v_version.preview_version_id
    ) then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ALREADY_ACCEPTED';
    end if;

    if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)->'viewed_document_version') is distinct from 'number'
       or coalesce(p_payload->>'viewed_pdf_sha256', '') !~ '^[0-9a-f]{64}$' then
      raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_ACCEPTANCE_INPUT_INVALID';
    end if;

    v_view := lws_internal.current_website_delivery_document_view_v1(
      p_project_id, v_version.preview_version_id
    );
    if v_view.view_derivative_id is null then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_NOT_FOUND';
    end if;
    if v_view.document_version::text is distinct from (p_payload->>'viewed_document_version')
       or rtrim(v_view.pdf_sha256) is distinct from (p_payload->>'viewed_pdf_sha256') then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_DOCUMENT_VERSION_CHANGED';
    end if;

    select receipt.* into v_receipt
    from public.website_delivery_document_access_receipts receipt
    where receipt.viewer_kind = 'CUSTOMER'
      and receipt.preview_session_id = v_session.preview_session_id
      and receipt.view_derivative_id = v_view.view_derivative_id
      and receipt.served_pdf_sha256 = v_view.pdf_sha256
      and receipt.served_pdf_bytes = v_view.pdf_bytes
    order by receipt.served_at, receipt.access_receipt_id
    limit 1;
    if not found then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_EVIDENCE_REQUIRED';
    end if;

    select * into strict v_authority
    from lws_internal.customer_approval_statement_authorities
    where document_type = 'WEBSITE_DELIVERY_ACCEPTANCE'
      and status = 'CURRENT';

    v_safe_payload := (v_safe_payload
      - 'preview_version_id' - 'statement_version' - 'statement_sha256'
      - 'viewed_document_version' - 'viewed_pdf_sha256'
      - 'delivery_view_derivative_id' - 'delivery_document_version' - 'delivery_pdf_sha256')
      || jsonb_build_object(
        'preview_version_id', v_version.preview_version_id,
        'statement_version', v_authority.authority_id,
        'statement_sha256', v_authority.source_sha256,
        'delivery_view_derivative_id', v_view.view_derivative_id,
        'delivery_document_version', v_view.document_version,
        'delivery_pdf_sha256', rtrim(v_view.pdf_sha256)
      );
  end if;

  v_result := lws_internal.execute_commercial_command_core_v1(
    'CUSTOMER:' || v_access.preview_access_id::text,
    p_project_id,
    p_command_type,
    p_expected_state,
    p_expected_revision,
    p_idempotency_key,
    v_safe_payload
  );

  if p_command_type = 'submit_customer_approval' then
    select * into strict v_approval
    from public.customer_approvals
    where project_id = p_project_id
      and preview_version_id = v_version.preview_version_id
      and preview_access_id = v_access.preview_access_id
      and status = 'CURRENT';
    insert into public.website_delivery_document_acceptances(
      customer_approval_id, project_id, preview_access_id, preview_session_id,
      preview_version_id, view_derivative_id, artifact_id, document_version,
      source_docx_sha256, pdf_sha256, pdf_bytes, access_receipt_id,
      statement_version, statement_sha256, command_idempotency_key
    ) values (
      v_approval.approval_id, p_project_id, v_access.preview_access_id, v_session.preview_session_id,
      v_version.preview_version_id, v_view.view_derivative_id, v_view.artifact_id, v_view.document_version,
      v_view.source_docx_sha256, v_view.pdf_sha256, v_view.pdf_bytes, v_receipt.access_receipt_id,
      v_authority.authority_id, v_authority.source_sha256, p_idempotency_key
    ) returning * into v_acceptance;

    v_result := v_result || jsonb_build_object(
      'accepted_document_version', v_acceptance.document_version,
      'accepted_pdf_sha256', rtrim(v_acceptance.pdf_sha256),
      'accepted_at', v_acceptance.accepted_at
    );
  end if;

  return v_result;
end
$$;

revoke all on function public.execute_customer_commercial_command_v1(char,uuid,text,text,bigint,uuid,jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.execute_customer_commercial_command_v1(char,uuid,text,text,bigint,uuid,jsonb)
to service_role;

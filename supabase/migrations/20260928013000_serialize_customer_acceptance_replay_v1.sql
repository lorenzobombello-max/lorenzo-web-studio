-- W2.4.1-P3: a concurrent duplicate acceptance request (same idempotency key) waited on the
-- project lock after its replay lookup and was refused as WEBSITE_DELIVERY_ALREADY_ACCEPTED.
-- The lock now precedes the replay lookup. No other behaviour changes; grants are re-applied.

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
    -- Serialize with lifecycle commands and with a concurrent request of the same key: the replay
    -- lookup below runs only after the project lock, so a queued duplicate sees the committed
    -- acceptance and returns the stored result instead of WEBSITE_DELIVERY_ALREADY_ACCEPTED.
    perform 1 from public.commercial_projects where project_id = p_project_id for update;

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


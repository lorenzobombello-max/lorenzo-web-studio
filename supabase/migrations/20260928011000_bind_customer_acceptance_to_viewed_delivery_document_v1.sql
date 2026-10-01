-- W2.4.1-P3: bind the existing explicit customer approval command to the exact registered
-- OPL-W-01 delivery document that this customer session was served before accepting.
-- Forward-only. The OPL-W-01 statement authority and §4 text are unchanged. A receipt proves
-- server-side delivery of exact bytes to the session, not human reading or a signature.

create table public.website_delivery_document_acceptances (
  acceptance_id uuid primary key default gen_random_uuid(),
  customer_approval_id uuid not null unique references public.customer_approvals(approval_id),
  project_id uuid not null references public.commercial_projects(project_id),
  preview_access_id uuid not null references public.preview_access(preview_access_id),
  preview_session_id uuid not null references public.preview_sessions(preview_session_id),
  preview_version_id uuid not null,
  view_derivative_id uuid not null,
  artifact_id uuid not null,
  document_version integer not null check (document_version > 0),
  source_docx_sha256 char(64) not null check (source_docx_sha256 ~ '^[0-9a-f]{64}$'),
  pdf_sha256 char(64) not null check (pdf_sha256 ~ '^[0-9a-f]{64}$'),
  pdf_bytes bigint not null check (pdf_bytes > 0),
  access_receipt_id uuid not null references public.website_delivery_document_access_receipts(access_receipt_id),
  statement_version text not null,
  statement_sha256 char(64) not null check (statement_sha256 ~ '^[0-9a-f]{64}$'),
  command_idempotency_key uuid not null unique,
  accepted_at timestamptz not null default clock_timestamp(),
  constraint website_delivery_acceptance_view_binding foreign key(
    view_derivative_id, artifact_id, project_id, preview_version_id,
    document_version, source_docx_sha256, pdf_sha256, pdf_bytes
  ) references public.website_delivery_document_view_derivatives(
    view_derivative_id, artifact_id, project_id, preview_version_id,
    document_version, source_docx_sha256, pdf_sha256, pdf_bytes
  ),
  constraint website_delivery_acceptance_one_per_preview unique(project_id, preview_version_id)
);

create trigger trg_website_delivery_acceptances_immutable
before update or delete on public.website_delivery_document_acceptances
for each row execute function public.prevent_website_delivery_document_mutation_v1();

alter table public.website_delivery_document_acceptances enable row level security;
alter table public.website_delivery_document_acceptances force row level security;
revoke all on table public.website_delivery_document_acceptances
from public, anon, authenticated, service_role;

-- The acceptable document is the view of the project's latest registered artifact, and only
-- when that artifact belongs to the CURRENT preview version. Otherwise nothing is acceptable.
create function lws_internal.current_website_delivery_document_view_v1(
  p_project_id uuid,
  p_preview_version_id uuid
)
returns public.website_delivery_document_view_derivatives
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select derivative.*
  from public.website_delivery_document_artifacts artifact
  join public.website_delivery_document_view_derivatives derivative
    on derivative.artifact_id = artifact.artifact_id
  where artifact.project_id = p_project_id
    and artifact.preview_version_id = p_preview_version_id
    and artifact.document_version = (
      select max(latest.document_version)
      from public.website_delivery_document_artifacts latest
      where latest.project_id = p_project_id
    )
$$;

revoke all on function lws_internal.current_website_delivery_document_view_v1(uuid,uuid)
from public, anon, authenticated, service_role;

create or replace function public.resolve_customer_approval_context_v1(
  p_session_digest char(64),
  p_project_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_session public.preview_sessions%rowtype;
  v_access public.preview_access%rowtype;
  v_version public.preview_versions%rowtype;
  v_project public.commercial_projects%rowtype;
  v_authority lws_internal.customer_approval_statement_authorities%rowtype;
  v_approval_event public.workflow_events%rowtype;
  v_view public.website_delivery_document_view_derivatives%rowtype;
  v_acceptance public.website_delivery_document_acceptances%rowtype;
  v_viewed boolean := false;
  v_replay_available boolean := false;
  v_expected_state text;
  v_expected_revision bigint;
begin
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

  select * into v_version
  from public.preview_versions
  where preview_version_id = v_access.preview_version_id
    and project_id = p_project_id
    and status = 'CURRENT';
  if not found then
    raise exception using errcode = 'P0001', message = 'PREVIEW_VERSION_MISMATCH';
  end if;

  select * into strict v_project
  from public.commercial_projects
  where project_id = p_project_id;

  select * into strict v_authority
  from lws_internal.customer_approval_statement_authorities
  where document_type = 'WEBSITE_DELIVERY_ACCEPTANCE'
    and status = 'CURRENT';

  select event.* into v_approval_event
  from public.workflow_events as event
  join public.audit_events as audit
    on audit.project_id = event.project_id
   and audit.command_id = event.command_id
   and audit.event_type = 'SUBMIT_CUSTOMER_APPROVAL'
   and audit.actor = 'CUSTOMER:' || v_access.preview_access_id::text
  where event.project_id = p_project_id
    and event.previous_state = 'M2_PAYMENT_RECEIVED'
    and event.new_state = 'FINAL_APPROVAL_RECORDED'
  order by event.project_revision desc
  limit 1;

  if found then
    v_replay_available := true;
    v_expected_state := v_approval_event.previous_state;
    v_expected_revision := v_approval_event.project_revision - 1;
  else
    v_expected_state := v_project.current_state;
    v_expected_revision := v_project.revision;
  end if;

  v_view := lws_internal.current_website_delivery_document_view_v1(
    p_project_id, v_version.preview_version_id
  );
  if v_view.view_derivative_id is not null then
    select exists(
      select 1
      from public.website_delivery_document_access_receipts receipt
      where receipt.viewer_kind = 'CUSTOMER'
        and receipt.preview_session_id = v_session.preview_session_id
        and receipt.view_derivative_id = v_view.view_derivative_id
        and receipt.served_pdf_sha256 = v_view.pdf_sha256
        and receipt.served_pdf_bytes = v_view.pdf_bytes
    ) into v_viewed;
  end if;

  select * into v_acceptance
  from public.website_delivery_document_acceptances
  where project_id = p_project_id
    and preview_version_id = v_version.preview_version_id;

  return jsonb_build_object(
    'project_id', v_project.project_id,
    'current_state', v_project.current_state,
    'revision', v_project.revision,
    'preview_access_id', v_access.preview_access_id,
    'preview_version_id', v_version.preview_version_id,
    'preview_version_number', v_version.version_number,
    'preview_content_reference', v_version.content_reference,
    'preview_content_sha256', v_version.content_sha256,
    'statement_version', v_authority.authority_id,
    'statement_sha256', v_authority.source_sha256,
    'statement_text', v_authority.statement_text,
    'statement_section', v_authority.section_reference,
    'source_filename', v_authority.source_filename,
    'source_drive_id', v_authority.source_drive_id,
    'source_byte_length', v_authority.source_byte_length,
    'approval_replay_available', v_replay_available,
    'approval_expected_state', v_expected_state,
    'approval_expected_revision', v_expected_revision,
    'session_expires_at', v_session.expires_at,
    'delivery_document', case when v_view.view_derivative_id is null then null else jsonb_build_object(
      'view_derivative_id', v_view.view_derivative_id,
      'document_version', v_view.document_version,
      'pdf_sha256', rtrim(v_view.pdf_sha256),
      'source_docx_sha256', rtrim(v_view.source_docx_sha256),
      'pdf_bytes', v_view.pdf_bytes
    ) end,
    'delivery_document_viewed', v_viewed,
    'acceptance', case when v_acceptance.acceptance_id is null then null else jsonb_build_object(
      'accepted_at', v_acceptance.accepted_at,
      'document_version', v_acceptance.document_version,
      'pdf_sha256', rtrim(v_acceptance.pdf_sha256),
      'statement_version', v_acceptance.statement_version
    ) end
  );
end
$$;

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

    -- Only server-derived values reach the command core and its idempotency fingerprint.
    v_safe_payload := (v_safe_payload
      - 'preview_version_id'
      - 'statement_version'
      - 'statement_sha256'
      - 'viewed_document_version'
      - 'viewed_pdf_sha256'
      - 'delivery_view_derivative_id'
      - 'delivery_document_version'
      - 'delivery_pdf_sha256')
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
    select * into v_acceptance
    from public.website_delivery_document_acceptances
    where command_idempotency_key = p_idempotency_key;
    if not found then
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
    elsif v_acceptance.view_derivative_id is distinct from v_view.view_derivative_id
       or v_acceptance.project_id is distinct from p_project_id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;

    v_result := v_result || jsonb_build_object(
      'accepted_document_version', v_acceptance.document_version,
      'accepted_pdf_sha256', rtrim(v_acceptance.pdf_sha256),
      'accepted_at', v_acceptance.accepted_at
    );
  end if;

  return v_result;
end
$$;

revoke all on function public.resolve_customer_approval_context_v1(char,uuid)
from public, anon, authenticated, service_role;
grant execute on function public.resolve_customer_approval_context_v1(char,uuid)
to service_role;

revoke all on function public.execute_customer_commercial_command_v1(char,uuid,text,text,bigint,uuid,jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.execute_customer_commercial_command_v1(char,uuid,text,text,bigint,uuid,jsonb)
to service_role;

comment on table public.website_delivery_document_acceptances is
  'Immutable evidence that an explicit customer approval was bound to the exact registered OPL-W-01 delivery-document view served to the same customer session. Not proof of identity, reading or a digital signature.';
comment on function public.execute_customer_commercial_command_v1(char,uuid,text,text,bigint,uuid,jsonb) is
  'Customer command gateway; approval requires the CURRENT registered delivery-document view and a view receipt of the same session, re-checked at registration.';

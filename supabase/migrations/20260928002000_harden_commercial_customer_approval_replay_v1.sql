-- Complete official source provenance and project exact approval replay inputs.

alter table lws_internal.customer_approval_statement_authorities
add column source_byte_length bigint;

update lws_internal.customer_approval_statement_authorities
set source_byte_length = 169278
where authority_id = 'OPL-W-01'
  and source_drive_id = '1dx4vXk6VNbykqY2S2cKmK9TeQBMBfDKP'
  and source_sha256 = '57a39bab36303b133c6acb41f857aeb4cad6de25811e127e7444f590fda4697b';

alter table lws_internal.customer_approval_statement_authorities
alter column source_byte_length set not null,
add constraint customer_approval_statement_source_byte_length_positive
check (source_byte_length > 0);

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
    'session_expires_at', v_session.expires_at
  );
end
$$;

comment on function public.resolve_customer_approval_context_v1(char,uuid) is
  'Service-role projection of the active customer session, CURRENT preview, exact replay inputs, lifecycle state, and complete official OPL-W-01 source authority.';
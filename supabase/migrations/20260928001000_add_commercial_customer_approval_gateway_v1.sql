-- Forward-only customer approval authority and context projection.
-- OPL-W-01 is the existing CURRENT authority; the hash pins the official DOCX bytes.

create table lws_internal.customer_approval_statement_authorities (
  authority_id text primary key,
  document_type text not null check (document_type = 'WEBSITE_DELIVERY_ACCEPTANCE'),
  source_drive_id text not null,
  source_filename text not null,
  source_sha256 char(64) not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  section_reference text not null,
  statement_text text not null,
  status text not null check (status in ('CURRENT', 'SUPERSEDED')),
  created_at timestamptz not null default clock_timestamp()
);

create unique index customer_approval_one_current_statement
on lws_internal.customer_approval_statement_authorities(document_type)
where status = 'CURRENT';

insert into lws_internal.customer_approval_statement_authorities(
  authority_id,
  document_type,
  source_drive_id,
  source_filename,
  source_sha256,
  section_reference,
  statement_text,
  status
) values (
  'OPL-W-01',
  'WEBSITE_DELIVERY_ACCEPTANCE',
  '1dx4vXk6VNbykqY2S2cKmK9TeQBMBfDKP',
  '07_Opleverdocument.docx',
  '57a39bab36303b133c6acb41f857aeb4cad6de25811e127e7444f590fda4697b',
  '§4 Aanvaarding',
  'De Opdrachtgever verklaart de hierboven beschreven website te hebben gecontroleerd en, onder voorbehoud van de eventuele opmerkingen vermeld in punt 3, te aanvaarden conform artikel 6 van de Websiteontwikkelingsovereenkomst (functionele test van 10 werkdagen, gevolgd door een finale controle van 5 werkdagen; formele, actieve acceptatie is vereist — er geldt geen stilzwijgende aanvaarding). Dit document vormt de formele bevestiging van die aanvaarding.',
  'CURRENT'
);

alter table lws_internal.customer_approval_statement_authorities enable row level security;
alter table lws_internal.customer_approval_statement_authorities force row level security;
revoke all on table lws_internal.customer_approval_statement_authorities
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
    'session_expires_at', v_session.expires_at
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
  v_safe_payload jsonb;
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
    select * into v_version
    from public.preview_versions
    where preview_version_id = v_access.preview_version_id
      and project_id = p_project_id
      and status = 'CURRENT';
    if not found then
      raise exception using errcode = 'P0001', message = 'PREVIEW_VERSION_MISMATCH';
    end if;

    select * into strict v_authority
    from lws_internal.customer_approval_statement_authorities
    where document_type = 'WEBSITE_DELIVERY_ACCEPTANCE'
      and status = 'CURRENT';

    v_safe_payload := (v_safe_payload
      - 'preview_version_id'
      - 'statement_version'
      - 'statement_sha256')
      || jsonb_build_object(
        'preview_version_id', v_version.preview_version_id,
        'statement_version', v_authority.authority_id,
        'statement_sha256', v_authority.source_sha256
      );
  end if;

  return lws_internal.execute_commercial_command_core_v1(
    'CUSTOMER:' || v_access.preview_access_id::text,
    p_project_id,
    p_command_type,
    p_expected_state,
    p_expected_revision,
    p_idempotency_key,
    v_safe_payload
  );
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

comment on function public.resolve_customer_approval_context_v1(char,uuid) is
  'Service-role projection of the active customer session, CURRENT preview, lifecycle state, and official OPL-W-01 statement authority.';
comment on function public.execute_customer_commercial_command_v1(char,uuid,text,text,bigint,uuid,jsonb) is
  'Existing customer command gateway hardened so approval evidence is server-owned and bound to CURRENT OPL-W-01 and preview authority.';

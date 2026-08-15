create table public.quotation_template_authorities (
  id uuid primary key default gen_random_uuid(),
  template_id text not null,
  template_version text not null,
  document_type text not null check (document_type = 'QUOTATION'),
  locale text not null check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  template_sha256 char(64) not null check (template_sha256 ~ '^[0-9A-F]{64}$'),
  technical_master_filename text not null check (nullif(btrim(technical_master_filename), '') is not null),
  renderer_contract_version smallint not null check (renderer_contract_version = 1),
  renderer_version text not null check (nullif(btrim(renderer_version), '') is not null),
  generation_contract_version smallint not null check (generation_contract_version = 1),
  semantic_contract_version smallint not null check (semantic_contract_version = 1),
  status text not null check (status in ('CANDIDATE', 'APPROVED', 'RETIRED')),
  approved_at timestamptz,
  approved_by text,
  approval_reference text,
  retired_at timestamptz,
  retired_by text,
  retirement_reason text,
  supersedes_template_id uuid references public.quotation_template_authorities(id),
  created_at timestamptz not null default clock_timestamp(),
  created_by text not null check (nullif(btrim(created_by), '') is not null),

  constraint quotation_template_authority_version_unique unique (template_id, template_version),
  constraint quotation_template_authority_state_valid check (
    (status = 'CANDIDATE'
      and approved_at is null and approved_by is null and approval_reference is null
      and retired_at is null and retired_by is null and retirement_reason is null)
    or (status = 'APPROVED'
      and approved_at is not null and nullif(btrim(approved_by), '') is not null
      and nullif(btrim(approval_reference), '') is not null
      and retired_at is null and retired_by is null and retirement_reason is null)
    or (status = 'RETIRED'
      and approved_at is not null and nullif(btrim(approved_by), '') is not null
      and nullif(btrim(approval_reference), '') is not null
      and retired_at is not null and nullif(btrim(retired_by), '') is not null
      and nullif(btrim(retirement_reason), '') is not null)
  )
);

create unique index quotation_template_authority_one_approved_per_contract
on public.quotation_template_authorities (
  document_type, locale, currency, renderer_contract_version,
  generation_contract_version, semantic_contract_version
)
where status = 'APPROVED';

create table public.quotation_template_authority_events (
  id bigint generated always as identity primary key,
  template_authority_id uuid not null references public.quotation_template_authorities(id),
  event_type text not null check (event_type in ('REGISTERED', 'APPROVED', 'RETIRED')),
  actor text not null check (nullif(btrim(actor), '') is not null),
  event_reference text not null check (nullif(btrim(event_reference), '') is not null),
  event_at timestamptz not null default clock_timestamp(),
  evidence jsonb not null,
  constraint quotation_template_authority_event_evidence_valid check (
    jsonb_typeof(evidence) = 'object'
    and not (evidence ?| array['capability_token', 'service_role_key', 'hmac_secret'])
  )
);

create function public.guard_quotation_template_authority_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_transition text := current_setting('lws.quotation_template_transition', true);
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'QUOTATION_TEMPLATE_AUTHORITY_IMMUTABLE';
  end if;
  if v_transition = 'APPROVE'
     and old.status = 'CANDIDATE' and new.status = 'APPROVED'
     and old.id = new.id and old.template_id = new.template_id
     and old.template_version = new.template_version
     and old.document_type = new.document_type and old.locale = new.locale
     and old.currency = new.currency and old.template_sha256 = new.template_sha256
     and old.technical_master_filename = new.technical_master_filename
     and old.renderer_contract_version = new.renderer_contract_version
     and old.renderer_version = new.renderer_version
     and old.generation_contract_version = new.generation_contract_version
     and old.semantic_contract_version = new.semantic_contract_version
     and old.supersedes_template_id is not distinct from new.supersedes_template_id
     and old.created_at = new.created_at and old.created_by = new.created_by then
    return new;
  end if;
  if v_transition = 'RETIRE'
     and old.status = 'APPROVED' and new.status = 'RETIRED'
     and old.id = new.id and old.template_id = new.template_id
     and old.template_version = new.template_version
     and old.document_type = new.document_type and old.locale = new.locale
     and old.currency = new.currency and old.template_sha256 = new.template_sha256
     and old.technical_master_filename = new.technical_master_filename
     and old.renderer_contract_version = new.renderer_contract_version
     and old.renderer_version = new.renderer_version
     and old.generation_contract_version = new.generation_contract_version
     and old.semantic_contract_version = new.semantic_contract_version
     and old.approved_at = new.approved_at and old.approved_by = new.approved_by
     and old.approval_reference = new.approval_reference
     and old.supersedes_template_id is not distinct from new.supersedes_template_id
     and old.created_at = new.created_at and old.created_by = new.created_by then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_TEMPLATE_AUTHORITY_IMMUTABLE';
end;
$$;

create function public.prevent_quotation_template_authority_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'QUOTATION_TEMPLATE_AUTHORITY_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_quotation_template_authority_guard
before update or delete on public.quotation_template_authorities
for each row execute function public.guard_quotation_template_authority_mutation();
create trigger trg_quotation_template_authority_events_immutable
before update or delete on public.quotation_template_authority_events
for each row execute function public.prevent_quotation_template_authority_event_mutation();

create function public.register_quotation_template_candidate_v1(
  p_template_id text,
  p_template_version text,
  p_document_type text,
  p_locale text,
  p_currency text,
  p_template_sha256 text,
  p_technical_master_filename text,
  p_renderer_contract_version smallint,
  p_renderer_version text,
  p_generation_contract_version smallint,
  p_semantic_contract_version smallint,
  p_created_by text,
  p_event_reference text,
  p_supersedes_template_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_document_type <> 'QUOTATION' or p_locale !~ '^[a-z]{2}(-[A-Z]{2})?$'
     or p_currency !~ '^[A-Z]{3}$' or p_template_sha256 !~ '^[0-9A-F]{64}$'
     or p_renderer_contract_version <> 1 or p_generation_contract_version <> 1
     or p_semantic_contract_version <> 1
     or nullif(btrim(p_template_id), '') is null
     or nullif(btrim(p_template_version), '') is null
     or nullif(btrim(p_technical_master_filename), '') is null
     or nullif(btrim(p_renderer_version), '') is null
     or nullif(btrim(p_created_by), '') is null
     or nullif(btrim(p_event_reference), '') is null then
    raise exception using errcode = '22023', message = 'TEMPLATE_AUTHORITY_INPUT_INVALID';
  end if;
  begin
    insert into public.quotation_template_authorities (
      template_id, template_version, document_type, locale, currency,
      template_sha256, technical_master_filename, renderer_contract_version,
      renderer_version, generation_contract_version, semantic_contract_version,
      status, supersedes_template_id, created_by
    ) values (
      p_template_id, p_template_version, p_document_type, p_locale, p_currency,
      p_template_sha256, p_technical_master_filename, p_renderer_contract_version,
      p_renderer_version, p_generation_contract_version, p_semantic_contract_version,
      'CANDIDATE', p_supersedes_template_id, p_created_by
    ) returning id into v_id;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'TEMPLATE_VERSION_CONFLICT';
  end;
  insert into public.quotation_template_authority_events (
    template_authority_id, event_type, actor, event_reference, evidence
  ) values (
    v_id, 'REGISTERED', p_created_by, p_event_reference,
    jsonb_build_object('templateSha256', p_template_sha256, 'status', 'CANDIDATE')
  );
  return v_id;
end;
$$;

create function public.approve_quotation_template_v1(
  p_template_authority_id uuid,
  p_approved_by text,
  p_approval_reference text
)
returns public.quotation_template_authorities
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template public.quotation_template_authorities%rowtype;
begin
  if nullif(btrim(p_approved_by), '') is null
     or nullif(btrim(p_approval_reference), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;
  select * into v_template from public.quotation_template_authorities
  where id = p_template_authority_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'TEMPLATE_NOT_FOUND'; end if;
  if v_template.status <> 'CANDIDATE' then
    raise exception using errcode = 'P0001', message = 'TEMPLATE_STATE_CONFLICT';
  end if;
  perform set_config('lws.quotation_template_transition', 'APPROVE', true);
  begin
    update public.quotation_template_authorities
    set status = 'APPROVED', approved_at = clock_timestamp(),
        approved_by = p_approved_by, approval_reference = p_approval_reference
    where id = p_template_authority_id returning * into v_template;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'TEMPLATE_AUTHORITY_AMBIGUOUS';
  end;
  perform set_config('lws.quotation_template_transition', '', true);
  insert into public.quotation_template_authority_events (
    template_authority_id, event_type, actor, event_reference, evidence
  ) values (
    v_template.id, 'APPROVED', p_approved_by, p_approval_reference,
    jsonb_build_object('templateSha256', rtrim(v_template.template_sha256), 'status', 'APPROVED')
  );
  return v_template;
end;
$$;

create function public.retire_quotation_template_v1(
  p_template_authority_id uuid,
  p_retired_by text,
  p_retirement_reason text,
  p_event_reference text
)
returns public.quotation_template_authorities
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template public.quotation_template_authorities%rowtype;
begin
  if nullif(btrim(p_retired_by), '') is null
     or nullif(btrim(p_retirement_reason), '') is null
     or nullif(btrim(p_event_reference), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;
  select * into v_template from public.quotation_template_authorities
  where id = p_template_authority_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'TEMPLATE_NOT_FOUND'; end if;
  if v_template.status <> 'APPROVED' then
    raise exception using errcode = 'P0001', message = 'TEMPLATE_STATE_CONFLICT';
  end if;
  perform set_config('lws.quotation_template_transition', 'RETIRE', true);
  update public.quotation_template_authorities
  set status = 'RETIRED', retired_at = clock_timestamp(),
      retired_by = p_retired_by, retirement_reason = p_retirement_reason
  where id = p_template_authority_id returning * into v_template;
  perform set_config('lws.quotation_template_transition', '', true);
  insert into public.quotation_template_authority_events (
    template_authority_id, event_type, actor, event_reference, evidence
  ) values (
    v_template.id, 'RETIRED', p_retired_by, p_event_reference,
    jsonb_build_object('templateSha256', rtrim(v_template.template_sha256), 'status', 'RETIRED', 'reason', p_retirement_reason)
  );
  return v_template;
end;
$$;

create function public.resolve_approved_quotation_template_v1(
  p_document_type text,
  p_locale text,
  p_currency text,
  p_renderer_contract_version smallint,
  p_generation_contract_version smallint,
  p_semantic_contract_version smallint
)
returns public.quotation_template_authorities
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_template public.quotation_template_authorities%rowtype;
begin
  select count(*) into v_count
  from public.quotation_template_authorities
  where document_type = p_document_type and locale = p_locale and currency = p_currency
    and renderer_contract_version = p_renderer_contract_version
    and generation_contract_version = p_generation_contract_version
    and semantic_contract_version = p_semantic_contract_version
    and status = 'APPROVED';
  if v_count = 0 then raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED'; end if;
  if v_count <> 1 then raise exception using errcode = 'P0001', message = 'TEMPLATE_AUTHORITY_AMBIGUOUS'; end if;
  select * into strict v_template
  from public.quotation_template_authorities
  where document_type = p_document_type and locale = p_locale and currency = p_currency
    and renderer_contract_version = p_renderer_contract_version
    and generation_contract_version = p_generation_contract_version
    and semantic_contract_version = p_semantic_contract_version
    and status = 'APPROVED';
  return v_template;
end;
$$;

create function public.is_approved_quotation_template_identity_v1(p_template jsonb)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_valid_quotation_generation_template_v1(p_template, true)
    and exists (
      select 1 from public.quotation_template_authorities
      where template_id = p_template->>'template_id'
        and template_version = p_template->>'template_version'
        and rtrim(template_sha256) = upper(p_template->>'template_sha256')
        and document_type = 'QUOTATION' and locale = 'nl-BE' and currency = 'EUR'
        and renderer_contract_version = 1 and generation_contract_version = 1
        and semantic_contract_version = 1 and status = 'APPROVED'
    )
$$;

alter function public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text)
rename to build_quotation_issue_payload_v1_unchecked_d3e4;
revoke all on function public.build_quotation_issue_payload_v1_unchecked_d3e4(uuid,jsonb,jsonb,text)
from public, anon, authenticated, service_role;

create function public.build_quotation_issue_payload_v1(
  p_issuance_id uuid,
  p_template jsonb,
  p_seller jsonb,
  p_admin_access_token_hash text
)
returns table(payload jsonb, payload_sha256 text, contract_version smallint, mode text, approval_id uuid, issuance_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template public.quotation_template_authorities%rowtype;
begin
  if not exists (
    select 1 from public.quote_request_quotation_issuances
    where id = p_issuance_id
  ) then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
  end if;
  select * into v_template
  from public.quotation_template_authorities
  where template_id = p_template->>'template_id'
    and template_version = p_template->>'template_version'
    and rtrim(template_sha256) = upper(p_template->>'template_sha256')
    and document_type = 'QUOTATION' and locale = 'nl-BE' and currency = 'EUR'
    and renderer_contract_version = 1 and generation_contract_version = 1
    and semantic_contract_version = 1 and status = 'APPROVED'
  for share;
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
  end if;
  if not public.is_approved_quotation_template_identity_v1(p_template) then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
  end if;
  return query select * from public.build_quotation_issue_payload_v1_unchecked_d3e4(
    p_issuance_id, p_template, p_seller, p_admin_access_token_hash
  );
end;
$$;

alter function public.commit_quotation_issuance_v2(uuid,uuid,text,text,text,text,text,smallint,text,bigint,text,bigint,text,text)
rename to commit_quotation_issuance_v2_unchecked_d3e3a;
revoke all on function public.commit_quotation_issuance_v2_unchecked_d3e3a(uuid,uuid,text,text,text,text,text,smallint,text,bigint,text,bigint,text,text)
from public, anon, authenticated, service_role;

create function public.commit_quotation_issuance_v2(
  p_issuance_id uuid,
  p_commit_idempotency_key uuid,
  p_issuance_input_sha256 text,
  p_generation_payload_sha256 text,
  p_template_id text,
  p_template_version text,
  p_template_sha256 text,
  p_generation_contract_version smallint,
  p_docx_sha256 text,
  p_docx_bytes bigint,
  p_pdf_sha256 text,
  p_pdf_bytes bigint,
  p_issued_by text,
  p_admin_access_token_hash text
)
returns table (
  issuance_id uuid, quotation_number text, quotation_version integer,
  status text, generation_payload_sha256 text, issued_at timestamptz,
  was_committed boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_identity jsonb;
  v_template public.quotation_template_authorities%rowtype;
begin
  if p_admin_access_token_hash is null
     or p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_issued_by), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;
  if p_issuance_input_sha256 is null
     or p_issuance_input_sha256 !~ '^[0-9a-f]{64}$'
     or p_generation_payload_sha256 is null
     or p_generation_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'GENERATION_PAYLOAD_HASH_MISMATCH';
  end if;
  if nullif(btrim(p_template_id), '') is null
     or nullif(btrim(p_template_version), '') is null
     or p_template_sha256 is null
     or p_template_sha256 !~ '^[0-9a-fA-F]{64}$'
     or p_generation_contract_version <> 1 then
    raise exception using errcode = '22023', message = 'TEMPLATE_IDENTITY_INVALID';
  end if;
  if p_docx_sha256 is null or p_docx_sha256 !~ '^[0-9a-f]{64}$'
     or (p_pdf_sha256 is not null and p_pdf_sha256 !~ '^[0-9a-f]{64}$') then
    raise exception using errcode = '22023', message = 'ARTIFACT_HASH_INVALID';
  end if;
  if p_docx_bytes is null or p_docx_bytes <= 0
     or (p_pdf_sha256 is null) <> (p_pdf_bytes is null)
     or (p_pdf_bytes is not null and p_pdf_bytes <= 0) then
    raise exception using errcode = '22023', message = 'ARTIFACT_BYTES_INVALID';
  end if;
  v_identity := jsonb_build_object(
    'template_id', p_template_id, 'template_version', p_template_version,
    'template_sha256', lower(p_template_sha256), 'authority_status', 'APPROVED'
  );
  if not public.is_approved_quotation_template_identity_v1(v_identity)
     or p_generation_contract_version <> 1 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
  end if;
  select * into strict v_template
  from public.quotation_template_authorities as authority
  where authority.template_id = p_template_id
    and authority.template_version = p_template_version
    and rtrim(authority.template_sha256) = upper(p_template_sha256)
    and authority.document_type = 'QUOTATION'
    and authority.locale = 'nl-BE' and authority.currency = 'EUR'
    and authority.renderer_contract_version = 1
    and authority.generation_contract_version = p_generation_contract_version
    and authority.semantic_contract_version = 1
    and authority.status = 'APPROVED'
  for share;
  return query select * from public.commit_quotation_issuance_v2_unchecked_d3e3a(
    p_issuance_id, p_commit_idempotency_key, p_issuance_input_sha256,
    p_generation_payload_sha256, p_template_id, p_template_version,
    lower(p_template_sha256), p_generation_contract_version,
    p_docx_sha256, p_docx_bytes, p_pdf_sha256, p_pdf_bytes,
    p_issued_by, p_admin_access_token_hash
  );
end;
$$;

alter table public.quotation_template_authorities enable row level security;
alter table public.quotation_template_authority_events enable row level security;
revoke all privileges on table public.quotation_template_authorities from public, anon, authenticated, service_role;
revoke all privileges on table public.quotation_template_authority_events from public, anon, authenticated, service_role;

revoke all on function public.guard_quotation_template_authority_mutation() from public,anon,authenticated,service_role;
revoke all on function public.prevent_quotation_template_authority_event_mutation() from public,anon,authenticated,service_role;
revoke all on function public.register_quotation_template_candidate_v1(text,text,text,text,text,text,text,smallint,text,smallint,smallint,text,text,uuid) from public,anon,authenticated;
revoke all on function public.approve_quotation_template_v1(uuid,text,text) from public,anon,authenticated;
revoke all on function public.retire_quotation_template_v1(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.resolve_approved_quotation_template_v1(text,text,text,smallint,smallint,smallint) from public,anon,authenticated;
revoke all on function public.is_approved_quotation_template_identity_v1(jsonb) from public,anon,authenticated;
revoke all on function public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function public.commit_quotation_issuance_v2(uuid,uuid,text,text,text,text,text,smallint,text,bigint,text,bigint,text,text) from public,anon,authenticated;

grant execute on function public.register_quotation_template_candidate_v1(text,text,text,text,text,text,text,smallint,text,smallint,smallint,text,text,uuid) to service_role;
grant execute on function public.approve_quotation_template_v1(uuid,text,text) to service_role;
grant execute on function public.retire_quotation_template_v1(uuid,text,text,text) to service_role;
grant execute on function public.resolve_approved_quotation_template_v1(text,text,text,smallint,smallint,smallint) to service_role;
grant execute on function public.is_approved_quotation_template_identity_v1(jsonb) to service_role;
grant execute on function public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text) to service_role;
grant execute on function public.commit_quotation_issuance_v2(uuid,uuid,text,text,text,text,text,smallint,text,bigint,text,bigint,text,text) to service_role;

select public.register_quotation_template_candidate_v1(
  'LWS_QUOTATION_NL_BE', '1.0.0-technical', 'QUOTATION', 'nl-BE', 'EUR',
  '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE',
  'assets/docs/quotation/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx',
  1::smallint, 'quotation-docx-v1', 1::smallint, 1::smallint,
  'checkpoint:D3E7', 'LWS_D3E7_CANDIDATE_REGISTRATION', null
);
select public.approve_quotation_template_v1(
  (select id from public.quotation_template_authorities
    where template_id = 'LWS_QUOTATION_NL_BE' and template_version = '1.0.0-technical'),
  'checkpoint:D3E7', 'LWS_D3E7_QUOTATION_TEMPLATE_AUTHORITY_APPROVAL'
);

comment on table public.quotation_template_authorities is
  'Immutable-version quotation template authority. Visual byte changes require a new candidate version and approval.';
comment on function public.resolve_approved_quotation_template_v1(text,text,text,smallint,smallint,smallint) is
  'Fails closed unless exactly one APPROVED template matches the governed document/locale/contract identity.';

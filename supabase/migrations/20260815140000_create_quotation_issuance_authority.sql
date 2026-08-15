create table public.quotation_number_counters (
  year smallint primary key check (year between 2000 and 9999),
  next_sequence integer not null check (next_sequence >= 1 and next_sequence <= 10000),
  updated_at timestamptz not null default clock_timestamp()
);

create table public.quote_request_quotation_issuances (
  id uuid primary key default gen_random_uuid(),
  quotation_number text not null,
  quotation_version integer not null default 1 check (quotation_version >= 1),
  status text not null check (status in ('PREPARED', 'ISSUED', 'VOID', 'SUPERSEDED')),
  approval_id uuid not null references public.quote_request_quotation_approvals(id),
  issued_at timestamptz,
  issued_by text,
  template_id text,
  template_version text,
  template_sha256 char(64),
  generation_contract_version smallint not null check (generation_contract_version = 1),
  generation_payload_sha256 char(64) not null,
  docx_sha256 char(64),
  docx_bytes bigint,
  pdf_sha256 char(64),
  pdf_bytes bigint,
  prepare_idempotency_key uuid not null unique,
  prepare_fingerprint char(64) not null,
  commit_idempotency_key uuid unique,
  commit_fingerprint char(64),
  void_idempotency_key uuid unique,
  void_fingerprint char(64),
  voided_at timestamptz,
  voided_by text,
  void_reason text,
  supersedes_issuance_id uuid references public.quote_request_quotation_issuances(id),
  superseded_by_issuance_id uuid references public.quote_request_quotation_issuances(id),
  revision_reason text,
  created_at timestamptz not null default clock_timestamp(),

  constraint quote_request_quotation_issuances_number_version_unique
    unique (quotation_number, quotation_version),
  constraint quote_request_quotation_issuances_approval_unique unique (approval_id),
  constraint quote_request_quotation_issuances_number_format
    check (quotation_number ~ '^LWS-OFF-[0-9]{4}-[0-9]{4}$'),
  constraint quote_request_quotation_issuances_hashes_valid check (
    generation_payload_sha256 ~ '^[0-9a-f]{64}$'
    and prepare_fingerprint ~ '^[0-9a-f]{64}$'
    and (template_sha256 is null or template_sha256 ~ '^[0-9a-f]{64}$')
    and (docx_sha256 is null or docx_sha256 ~ '^[0-9a-f]{64}$')
    and (pdf_sha256 is null or pdf_sha256 ~ '^[0-9a-f]{64}$')
    and (commit_fingerprint is null or commit_fingerprint ~ '^[0-9a-f]{64}$')
    and (void_fingerprint is null or void_fingerprint ~ '^[0-9a-f]{64}$')
  ),
  constraint quote_request_quotation_issuances_artifact_sizes_valid check (
    (docx_bytes is null or docx_bytes > 0)
    and (pdf_bytes is null or pdf_bytes > 0)
  ),
  constraint quote_request_quotation_issuances_state_valid check (
    (status = 'PREPARED'
      and issued_at is null and issued_by is null
      and template_id is null and template_version is null and template_sha256 is null
      and docx_sha256 is null and docx_bytes is null
      and pdf_sha256 is null and pdf_bytes is null
      and commit_idempotency_key is null and commit_fingerprint is null
      and void_idempotency_key is null and void_fingerprint is null
      and voided_at is null and voided_by is null and void_reason is null
      and supersedes_issuance_id is null and superseded_by_issuance_id is null
      and revision_reason is null)
    or (status = 'ISSUED'
      and issued_at is not null and nullif(btrim(issued_by), '') is not null
      and nullif(btrim(template_id), '') is not null
      and nullif(btrim(template_version), '') is not null
      and template_sha256 is not null
      and docx_sha256 is not null and docx_bytes > 0
      and commit_idempotency_key is not null and commit_fingerprint is not null
      and void_idempotency_key is null and void_fingerprint is null
      and voided_at is null and voided_by is null and void_reason is null
      and supersedes_issuance_id is null and superseded_by_issuance_id is null
      and revision_reason is null)
    or (status = 'VOID'
      and issued_at is null and issued_by is null
      and template_id is null and template_version is null and template_sha256 is null
      and docx_sha256 is null and docx_bytes is null
      and pdf_sha256 is null and pdf_bytes is null
      and commit_idempotency_key is null and commit_fingerprint is null
      and void_idempotency_key is not null and void_fingerprint is not null
      and voided_at is not null and nullif(btrim(voided_by), '') is not null
      and nullif(btrim(void_reason), '') is not null
      and supersedes_issuance_id is null and superseded_by_issuance_id is null
      and revision_reason is null)
    or (status = 'SUPERSEDED'
      and issued_at is not null and nullif(btrim(issued_by), '') is not null
      and template_sha256 is not null
      and docx_sha256 is not null and docx_bytes > 0
      and superseded_by_issuance_id is not null
      and superseded_by_issuance_id <> id)
  )
);

create table public.quote_request_quotation_issuance_operations (
  idempotency_key uuid primary key,
  operation_type text not null check (operation_type in ('PREPARE', 'COMMIT', 'VOID')),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  issuance_id uuid not null references public.quote_request_quotation_issuances(id),
  created_at timestamptz not null default clock_timestamp()
);

create function public.is_valid_quotation_approval_for_issuance_v1(p_approval_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.quote_request_quotation_approvals as approval
    join public.quote_request_quotation_approval_integrity as integrity
      on integrity.approval_id = approval.id
    where approval.id = p_approval_id
      and approval.contract_version = 1
      and approval.payload_sha256 = public.quotation_approval_payload_sha256_v1(approval.approved_payload)
      and public.is_valid_quotation_approval_payload_v1(approval.approved_payload, true)
      and integrity.algorithm_version = 'hmac-sha256-v1'
      and integrity.key_id ~ '^v[1-9][0-9]*$'
      and integrity.mac ~ '^[0-9a-f]{64}$'
      and public.is_current_pricing_snapshot_integrity_valid(
        approval.intake_id,
        approval.pricing_snapshot_id,
        approval.approved_payload->'pricing_snapshot'
      )
  )
$$;

create function public.prepare_quotation_issuance_v1(
  p_approval_id uuid,
  p_issue_year smallint,
  p_generation_contract_version smallint,
  p_generation_payload_sha256 text,
  p_idempotency_key uuid,
  p_admin_access_token_hash text,
  p_prepared_by text
)
returns table (
  issuance_id uuid,
  quotation_number text,
  quotation_version integer,
  status text,
  generation_contract_version smallint,
  generation_payload_sha256 text,
  was_created boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_operation public.quote_request_quotation_issuance_operations%rowtype;
  v_fingerprint text;
  v_sequence integer;
begin
  if p_issue_year not between 2000 and 9999
     or p_generation_contract_version <> 1
     or p_generation_payload_sha256 is null
     or p_generation_payload_sha256 !~ '^[0-9a-f]{64}$'
     or p_admin_access_token_hash is null
     or p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_prepared_by), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'approvalId', p_approval_id,
    'generationContractVersion', p_generation_contract_version,
    'generationPayloadSha256', p_generation_payload_sha256,
    'issueYear', p_issue_year
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_approval
  from public.quote_request_quotation_approvals
  where id = p_approval_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'APPROVAL_NOT_FOUND';
  end if;

  select * into strict v_intake
  from public.quote_request_intakes
  where id = v_approval.intake_id
  for update;

  if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null
     or v_intake.status not in ('submitted', 'reviewed') then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  if not public.is_valid_quotation_approval_for_issuance_v1(p_approval_id) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_INTEGRITY_INVALID';
  end if;

  select * into v_operation
  from public.quote_request_quotation_issuance_operations
  where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'PREPARE'
       or v_operation.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_issuance
    from public.quote_request_quotation_issuances
    where id = v_operation.issuance_id;
    return query select v_issuance.id, v_issuance.quotation_number,
      v_issuance.quotation_version, v_issuance.status,
      v_issuance.generation_contract_version,
      rtrim(v_issuance.generation_payload_sha256), false;
    return;
  end if;

  select * into v_issuance
  from public.quote_request_quotation_issuances
  where approval_id = p_approval_id;

  if found then
    if v_issuance.prepare_fingerprint = v_fingerprint then
      return query select v_issuance.id, v_issuance.quotation_number,
        v_issuance.quotation_version, v_issuance.status,
        v_issuance.generation_contract_version,
        rtrim(v_issuance.generation_payload_sha256), false;
      return;
    end if;
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  insert into public.quotation_number_counters as counter (year, next_sequence)
  values (p_issue_year, 2)
  on conflict (year) do update
    set next_sequence = counter.next_sequence + 1,
        updated_at = clock_timestamp()
    where counter.next_sequence <= 9999
  returning next_sequence - 1 into v_sequence;

  if v_sequence is null or v_sequence not between 1 and 9999 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_NUMBER_CONFLICT';
  end if;

  begin
    insert into public.quote_request_quotation_issuances (
      quotation_number, quotation_version, status, approval_id,
      generation_contract_version, generation_payload_sha256,
      prepare_idempotency_key, prepare_fingerprint
    ) values (
      'LWS-OFF-' || p_issue_year::text || '-' || lpad(v_sequence::text, 4, '0'),
      1, 'PREPARED', p_approval_id, p_generation_contract_version,
      p_generation_payload_sha256, p_idempotency_key, v_fingerprint
    ) returning * into v_issuance;
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'CONCURRENT_ISSUANCE_CONFLICT';
  end;

  insert into public.quote_request_quotation_issuance_operations (
    idempotency_key, operation_type, request_fingerprint, issuance_id
  ) values (p_idempotency_key, 'PREPARE', v_fingerprint, v_issuance.id);

  return query select v_issuance.id, v_issuance.quotation_number,
    v_issuance.quotation_version, v_issuance.status,
    v_issuance.generation_contract_version,
    rtrim(v_issuance.generation_payload_sha256), true;
end;
$$;

create function public.commit_quotation_issuance_v1(
  p_issuance_id uuid,
  p_commit_idempotency_key uuid,
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
  issuance_id uuid,
  quotation_number text,
  quotation_version integer,
  status text,
  issued_at timestamptz,
  was_committed boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_operation public.quote_request_quotation_issuance_operations%rowtype;
  v_fingerprint text;
begin
  if p_admin_access_token_hash is null
     or p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_issued_by), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;
  if nullif(btrim(p_template_id), '') is null
     or nullif(btrim(p_template_version), '') is null
     or p_template_sha256 is null
     or p_template_sha256 !~ '^[0-9a-f]{64}$'
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

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'docxBytes', p_docx_bytes,
    'docxSha256', p_docx_sha256,
    'generationContractVersion', p_generation_contract_version,
    'generationPayloadSha256', p_generation_payload_sha256,
    'issuanceId', p_issuance_id,
    'pdfBytes', p_pdf_bytes,
    'pdfSha256', p_pdf_sha256,
    'templateId', p_template_id,
    'templateSha256', p_template_sha256,
    'templateVersion', p_template_version
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_issuance
  from public.quote_request_quotation_issuances
  where id = p_issuance_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
  end if;

  select * into strict v_approval
  from public.quote_request_quotation_approvals where id = v_issuance.approval_id;
  select * into strict v_intake
  from public.quote_request_intakes where id = v_approval.intake_id for update;
  if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null
     or v_intake.status not in ('submitted', 'reviewed') then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;
  if not public.is_valid_quotation_approval_for_issuance_v1(v_issuance.approval_id) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_INTEGRITY_INVALID';
  end if;

  select * into v_operation
  from public.quote_request_quotation_issuance_operations
  where idempotency_key = p_commit_idempotency_key;
  if found then
    if v_operation.operation_type <> 'COMMIT'
       or v_operation.request_fingerprint <> v_fingerprint
       or v_operation.issuance_id <> p_issuance_id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return query select v_issuance.id, v_issuance.quotation_number,
      v_issuance.quotation_version, v_issuance.status, v_issuance.issued_at, false;
    return;
  end if;

  if v_issuance.status = 'VOID' then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_VOID';
  end if;
  if v_issuance.status <> 'PREPARED' then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_ALREADY_COMPLETED';
  end if;
  if rtrim(v_issuance.generation_payload_sha256) <> p_generation_payload_sha256
     or v_issuance.generation_contract_version <> p_generation_contract_version then
    raise exception using errcode = 'P0001', message = 'GENERATION_PAYLOAD_HASH_MISMATCH';
  end if;

  perform set_config('lws.quotation_issuance_transition', 'COMMIT', true);
  update public.quote_request_quotation_issuances
  set status = 'ISSUED', issued_at = clock_timestamp(), issued_by = p_issued_by,
      template_id = p_template_id, template_version = p_template_version,
      template_sha256 = p_template_sha256,
      docx_sha256 = p_docx_sha256, docx_bytes = p_docx_bytes,
      pdf_sha256 = p_pdf_sha256, pdf_bytes = p_pdf_bytes,
      commit_idempotency_key = p_commit_idempotency_key,
      commit_fingerprint = v_fingerprint
  where id = p_issuance_id
  returning * into v_issuance;
  perform set_config('lws.quotation_issuance_transition', '', true);

  insert into public.quote_request_quotation_issuance_operations (
    idempotency_key, operation_type, request_fingerprint, issuance_id
  ) values (p_commit_idempotency_key, 'COMMIT', v_fingerprint, v_issuance.id);

  return query select v_issuance.id, v_issuance.quotation_number,
    v_issuance.quotation_version, v_issuance.status, v_issuance.issued_at, true;
end;
$$;

create function public.void_quotation_issuance_v1(
  p_issuance_id uuid,
  p_reason text,
  p_actor text,
  p_idempotency_key uuid,
  p_admin_access_token_hash text
)
returns table (
  issuance_id uuid,
  quotation_number text,
  status text,
  voided_at timestamptz,
  was_voided boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_operation public.quote_request_quotation_issuance_operations%rowtype;
  v_fingerprint text;
begin
  if p_admin_access_token_hash is null
     or p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '22023', message = 'ISSUANCE_STATE_CONFLICT';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'actor', p_actor, 'issuanceId', p_issuance_id, 'reason', p_reason
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_issuance
  from public.quote_request_quotation_issuances
  where id = p_issuance_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
  end if;

  select * into strict v_approval
  from public.quote_request_quotation_approvals where id = v_issuance.approval_id;
  select * into strict v_intake
  from public.quote_request_intakes where id = v_approval.intake_id for update;
  if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null
     or v_intake.status not in ('submitted', 'reviewed') then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  select * into v_operation
  from public.quote_request_quotation_issuance_operations
  where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'VOID'
       or v_operation.request_fingerprint <> v_fingerprint
       or v_operation.issuance_id <> p_issuance_id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return query select v_issuance.id, v_issuance.quotation_number,
      v_issuance.status, v_issuance.voided_at, false;
    return;
  end if;

  if v_issuance.status <> 'PREPARED' then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_STATE_CONFLICT';
  end if;

  perform set_config('lws.quotation_issuance_transition', 'VOID', true);
  update public.quote_request_quotation_issuances
  set status = 'VOID', voided_at = clock_timestamp(), voided_by = p_actor,
      void_reason = p_reason, void_idempotency_key = p_idempotency_key,
      void_fingerprint = v_fingerprint
  where id = p_issuance_id
  returning * into v_issuance;
  perform set_config('lws.quotation_issuance_transition', '', true);

  insert into public.quote_request_quotation_issuance_operations (
    idempotency_key, operation_type, request_fingerprint, issuance_id
  ) values (p_idempotency_key, 'VOID', v_fingerprint, v_issuance.id);

  return query select v_issuance.id, v_issuance.quotation_number,
    v_issuance.status, v_issuance.voided_at, true;
end;
$$;

create function public.guard_quotation_issuance_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_transition text := current_setting('lws.quotation_issuance_transition', true);
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'QUOTATION_ISSUANCE_IMMUTABLE';
  end if;
  if v_transition = 'COMMIT'
     and old.status = 'PREPARED' and new.status = 'ISSUED'
     and old.id = new.id and old.quotation_number = new.quotation_number
     and old.quotation_version = new.quotation_version
     and old.approval_id = new.approval_id
     and old.generation_contract_version = new.generation_contract_version
     and old.generation_payload_sha256 = new.generation_payload_sha256
     and old.prepare_idempotency_key = new.prepare_idempotency_key
     and old.prepare_fingerprint = new.prepare_fingerprint
     and old.created_at = new.created_at then
    return new;
  end if;
  if v_transition = 'VOID'
     and old.status = 'PREPARED' and new.status = 'VOID'
     and old.id = new.id and old.quotation_number = new.quotation_number
     and old.quotation_version = new.quotation_version
     and old.approval_id = new.approval_id
     and old.generation_contract_version = new.generation_contract_version
     and old.generation_payload_sha256 = new.generation_payload_sha256
     and old.prepare_idempotency_key = new.prepare_idempotency_key
     and old.prepare_fingerprint = new.prepare_fingerprint
     and old.created_at = new.created_at then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_ISSUANCE_IMMUTABLE';
end;
$$;

create trigger trg_quotation_issuances_guard
before update or delete on public.quote_request_quotation_issuances
for each row execute function public.guard_quotation_issuance_mutation();

create function public.prevent_quotation_issuance_authority_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'QUOTATION_ISSUANCE_AUTHORITY_IMMUTABLE';
end;
$$;

create trigger trg_quotation_issuance_operations_immutable
before update or delete on public.quote_request_quotation_issuance_operations
for each row execute function public.prevent_quotation_issuance_authority_mutation();

alter table public.quotation_number_counters enable row level security;
alter table public.quote_request_quotation_issuances enable row level security;
alter table public.quote_request_quotation_issuance_operations enable row level security;

revoke all privileges on table public.quotation_number_counters
from public, anon, authenticated, service_role;
revoke all privileges on table public.quote_request_quotation_issuances
from public, anon, authenticated, service_role;
revoke all privileges on table public.quote_request_quotation_issuance_operations
from public, anon, authenticated, service_role;

revoke all on function public.is_valid_quotation_approval_for_issuance_v1(uuid)
from public, anon, authenticated;
revoke all on function public.prepare_quotation_issuance_v1(uuid, smallint, smallint, text, uuid, text, text)
from public, anon, authenticated;
revoke all on function public.commit_quotation_issuance_v1(uuid, uuid, text, text, text, text, smallint, text, bigint, text, bigint, text, text)
from public, anon, authenticated;
revoke all on function public.void_quotation_issuance_v1(uuid, text, text, uuid, text)
from public, anon, authenticated;
revoke all on function public.guard_quotation_issuance_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.prevent_quotation_issuance_authority_mutation()
from public, anon, authenticated, service_role;

grant execute on function public.is_valid_quotation_approval_for_issuance_v1(uuid)
to service_role;
grant execute on function public.prepare_quotation_issuance_v1(uuid, smallint, smallint, text, uuid, text, text)
to service_role;
grant execute on function public.commit_quotation_issuance_v1(uuid, uuid, text, text, text, text, smallint, text, bigint, text, bigint, text, text)
to service_role;
grant execute on function public.void_quotation_issuance_v1(uuid, text, text, uuid, text)
to service_role;

comment on table public.quote_request_quotation_issuances is
  'D3E3 metadata registry only. Artifact generation, validation, storage, publication, acceptance, and supersession operations are outside this checkpoint.';
comment on function public.is_valid_quotation_approval_for_issuance_v1(uuid) is
  'Validates immutable approval/root/pricing evidence using the D3E2 SQL trust pattern. Cryptographic HMAC verification remains mandatory at the trusted Edge boundary because signing secrets never enter SQL.';
comment on function public.commit_quotation_issuance_v1(uuid, uuid, text, text, text, text, smallint, text, bigint, text, bigint, text, text) is
  'Registers trusted artifact evidence only. DOCX is mandatory; PDF is optional until a production quotation contract mandates it.';

alter table public.quote_request_quotation_issuances
  add column issuance_input_sha256 char(64);

alter table public.quote_request_quotation_issuances
  alter column generation_payload_sha256 drop not null;

alter table public.quote_request_quotation_issuances
  disable trigger trg_quotation_issuances_guard;

update public.quote_request_quotation_issuances
set issuance_input_sha256 = generation_payload_sha256
where issuance_input_sha256 is null;

update public.quote_request_quotation_issuances
set generation_payload_sha256 = null
where status in ('PREPARED', 'VOID');

alter table public.quote_request_quotation_issuances
  enable trigger trg_quotation_issuances_guard;

alter table public.quote_request_quotation_issuances
  alter column issuance_input_sha256 set not null;

alter table public.quote_request_quotation_issuances
  drop constraint quote_request_quotation_issuances_hashes_valid,
  drop constraint quote_request_quotation_issuances_state_valid;

alter table public.quote_request_quotation_issuances
  add constraint quote_request_quotation_issuances_hashes_valid check (
    issuance_input_sha256 ~ '^[0-9a-f]{64}$'
    and (generation_payload_sha256 is null
      or generation_payload_sha256 ~ '^[0-9a-f]{64}$')
    and prepare_fingerprint ~ '^[0-9a-f]{64}$'
    and (template_sha256 is null or template_sha256 ~ '^[0-9a-f]{64}$')
    and (docx_sha256 is null or docx_sha256 ~ '^[0-9a-f]{64}$')
    and (pdf_sha256 is null or pdf_sha256 ~ '^[0-9a-f]{64}$')
    and (commit_fingerprint is null or commit_fingerprint ~ '^[0-9a-f]{64}$')
    and (void_fingerprint is null or void_fingerprint ~ '^[0-9a-f]{64}$')
  ),
  add constraint quote_request_quotation_issuances_state_valid check (
    (status = 'PREPARED'
      and generation_payload_sha256 is null
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
      and generation_payload_sha256 is not null
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
      and generation_payload_sha256 is null
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
      and generation_payload_sha256 is not null
      and issued_at is not null and nullif(btrim(issued_by), '') is not null
      and template_sha256 is not null
      and docx_sha256 is not null and docx_bytes > 0
      and superseded_by_issuance_id is not null
      and superseded_by_issuance_id <> id)
  );

create function public.prepare_quotation_issuance_v2(
  p_approval_id uuid,
  p_issue_year smallint,
  p_generation_contract_version smallint,
  p_issuance_input_sha256 text,
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
  issuance_input_sha256 text,
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
     or p_issuance_input_sha256 is null
     or p_issuance_input_sha256 !~ '^[0-9a-f]{64}$'
     or p_admin_access_token_hash is null
     or p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_prepared_by), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'approvalId', p_approval_id,
    'generationContractVersion', p_generation_contract_version,
    'issuanceInputSha256', p_issuance_input_sha256,
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
      rtrim(v_issuance.issuance_input_sha256),
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
        rtrim(v_issuance.issuance_input_sha256),
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
      generation_contract_version, issuance_input_sha256,
      generation_payload_sha256, prepare_idempotency_key, prepare_fingerprint
    ) values (
      'LWS-OFF-' || p_issue_year::text || '-' || lpad(v_sequence::text, 4, '0'),
      1, 'PREPARED', p_approval_id, p_generation_contract_version,
      p_issuance_input_sha256, null, p_idempotency_key, v_fingerprint
    ) returning * into v_issuance;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'CONCURRENT_ISSUANCE_CONFLICT';
  end;

  insert into public.quote_request_quotation_issuance_operations (
    idempotency_key, operation_type, request_fingerprint, issuance_id
  ) values (p_idempotency_key, 'PREPARE', v_fingerprint, v_issuance.id);

  return query select v_issuance.id, v_issuance.quotation_number,
    v_issuance.quotation_version, v_issuance.status,
    v_issuance.generation_contract_version,
    rtrim(v_issuance.issuance_input_sha256),
    rtrim(v_issuance.generation_payload_sha256), true;
end;
$$;

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
  issuance_id uuid,
  quotation_number text,
  quotation_version integer,
  status text,
  generation_payload_sha256 text,
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
  if p_issuance_input_sha256 is null
     or p_issuance_input_sha256 !~ '^[0-9a-f]{64}$'
     or p_generation_payload_sha256 is null
     or p_generation_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'GENERATION_PAYLOAD_HASH_MISMATCH';
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
    'docxBytes', p_docx_bytes, 'docxSha256', p_docx_sha256,
    'generationContractVersion', p_generation_contract_version,
    'generationPayloadSha256', p_generation_payload_sha256,
    'issuanceId', p_issuance_id, 'issuanceInputSha256', p_issuance_input_sha256,
    'pdfBytes', p_pdf_bytes, 'pdfSha256', p_pdf_sha256,
    'templateId', p_template_id, 'templateSha256', p_template_sha256,
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
      v_issuance.quotation_version, v_issuance.status,
      rtrim(v_issuance.generation_payload_sha256), v_issuance.issued_at, false;
    return;
  end if;

  if v_issuance.status = 'VOID' then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_VOID';
  end if;
  if v_issuance.status <> 'PREPARED' then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_ALREADY_COMPLETED';
  end if;
  if rtrim(v_issuance.issuance_input_sha256) <> p_issuance_input_sha256
     or v_issuance.generation_contract_version <> p_generation_contract_version then
    raise exception using errcode = 'P0001', message = 'PREPARATION_INPUT_HASH_MISMATCH';
  end if;

  perform set_config('lws.quotation_issuance_transition', 'COMMIT_V2', true);
  update public.quote_request_quotation_issuances
  set status = 'ISSUED', generation_payload_sha256 = p_generation_payload_sha256,
      issued_at = clock_timestamp(), issued_by = p_issued_by,
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
    v_issuance.quotation_version, v_issuance.status,
    rtrim(v_issuance.generation_payload_sha256), v_issuance.issued_at, true;
end;
$$;

create or replace function public.prepare_quotation_issuance_v1(
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
language sql
security definer
set search_path = public
as $$
  select result.issuance_id, result.quotation_number,
    result.quotation_version, result.status,
    result.generation_contract_version,
    result.issuance_input_sha256 as generation_payload_sha256,
    result.was_created
  from public.prepare_quotation_issuance_v2(
    p_approval_id, p_issue_year, p_generation_contract_version,
    p_generation_payload_sha256, p_idempotency_key,
    p_admin_access_token_hash, p_prepared_by
  ) as result
$$;

create or replace function public.commit_quotation_issuance_v1(
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
begin
  return query
  select result.issuance_id, result.quotation_number,
    result.quotation_version, result.status,
    result.issued_at, result.was_committed
  from public.commit_quotation_issuance_v2(
    p_issuance_id, p_commit_idempotency_key,
    p_generation_payload_sha256, p_generation_payload_sha256,
    p_template_id, p_template_version, p_template_sha256,
    p_generation_contract_version, p_docx_sha256, p_docx_bytes,
    p_pdf_sha256, p_pdf_bytes, p_issued_by, p_admin_access_token_hash
  ) as result;
exception
  when sqlstate 'P0001' then
    if sqlerrm = 'PREPARATION_INPUT_HASH_MISMATCH' then
      raise exception using errcode = 'P0001', message = 'GENERATION_PAYLOAD_HASH_MISMATCH';
    end if;
    raise;
end;
$$;

create or replace function public.guard_quotation_issuance_mutation()
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
  if v_transition in ('COMMIT', 'COMMIT_V2')
     and old.status = 'PREPARED' and new.status = 'ISSUED'
     and old.id = new.id and old.quotation_number = new.quotation_number
     and old.quotation_version = new.quotation_version
     and old.approval_id = new.approval_id
     and old.generation_contract_version = new.generation_contract_version
     and old.issuance_input_sha256 = new.issuance_input_sha256
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
     and old.issuance_input_sha256 = new.issuance_input_sha256
     and old.generation_payload_sha256 is not distinct from new.generation_payload_sha256
     and old.prepare_idempotency_key = new.prepare_idempotency_key
     and old.prepare_fingerprint = new.prepare_fingerprint
     and old.created_at = new.created_at then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_ISSUANCE_IMMUTABLE';
end;
$$;

revoke all on function public.prepare_quotation_issuance_v2(uuid, smallint, smallint, text, uuid, text, text)
from public, anon, authenticated;
revoke all on function public.commit_quotation_issuance_v2(uuid, uuid, text, text, text, text, text, smallint, text, bigint, text, bigint, text, text)
from public, anon, authenticated;
grant execute on function public.prepare_quotation_issuance_v2(uuid, smallint, smallint, text, uuid, text, text)
to service_role;
grant execute on function public.commit_quotation_issuance_v2(uuid, uuid, text, text, text, text, text, smallint, text, bigint, text, bigint, text, text)
to service_role;

comment on column public.quote_request_quotation_issuances.issuance_input_sha256 is
  'Hash of immutable pre-number authority inputs. It excludes issuance identity and is fixed at PREPARED allocation.';
comment on column public.quote_request_quotation_issuances.generation_payload_sha256 is
  'Hash of the definitive canonical ISSUE generation payload. It is absent in PREPARED/VOID and frozen only during PREPARED to ISSUED commit.';
comment on function public.prepare_quotation_issuance_v2(uuid, smallint, smallint, text, uuid, text, text) is
  'Allocates PREPARED identity from an immutable issuance-input hash; no final generation payload exists yet.';
comment on function public.commit_quotation_issuance_v2(uuid, uuid, text, text, text, text, text, smallint, text, bigint, text, bigint, text, text) is
  'Binds the definitive post-allocation canonical generation payload hash and trusted artifact evidence atomically.';
comment on function public.prepare_quotation_issuance_v1(uuid, smallint, smallint, text, uuid, text, text) is
  'Compatibility wrapper: the historical generation_payload_sha256 argument is interpreted as the immutable issuance-input hash. New callers must use v2.';
comment on function public.commit_quotation_issuance_v1(uuid, uuid, text, text, text, text, smallint, text, bigint, text, bigint, text, text) is
  'Compatibility wrapper: the historical hash is used as both preparation input and final payload hash. New callers must use v2.';

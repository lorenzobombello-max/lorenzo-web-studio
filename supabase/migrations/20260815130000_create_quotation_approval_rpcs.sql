create table public.quote_request_quotation_approval_operations (
  idempotency_key uuid primary key,
  operation_type text not null
    check (operation_type in ('UPSERT_DRAFT', 'APPROVE')),
  request_fingerprint text not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  draft_id uuid references public.quote_request_quotation_approval_drafts(id),
  approval_id uuid references public.quote_request_quotation_approvals(id),
  draft_updated_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),

  constraint quote_request_quotation_approval_operations_result_valid
    check (
      (operation_type = 'UPSERT_DRAFT' and draft_id is not null
        and approval_id is null and draft_updated_at is not null)
      or (operation_type = 'APPROVE' and draft_id is not null
        and approval_id is not null and draft_updated_at is null)
    )
);

create function public.is_current_pricing_snapshot_integrity_valid(
  p_intake_id uuid,
  p_pricing_snapshot_id uuid,
  p_payload_reference jsonb
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.quote_request_pricing_snapshots as snapshot
    join public.quote_request_pricing_snapshot_integrity as integrity
      on integrity.snapshot_id = snapshot.id
    where snapshot.id = p_pricing_snapshot_id
      and snapshot.intake_id = p_intake_id
      and p_payload_reference->>'snapshot_id' = snapshot.id::text
      and (p_payload_reference->>'snapshot_contract_version')::smallint
        is not distinct from snapshot.snapshot_contract_version
      and p_payload_reference->>'integrity_algorithm_version' = integrity.algorithm_version
      and p_payload_reference->>'integrity_key_id' = integrity.key_id
      and p_payload_reference->>'integrity_mac' = integrity.mac
      and case snapshot.snapshot_contract_version
        when 2 then public.is_strict_pricing_snapshot_v2(
          snapshot.snapshot_contract_version,
          snapshot.config_version,
          snapshot.config_hash,
          snapshot.normalized_evidence,
          snapshot.calculation,
          snapshot.package_advice,
          snapshot.budget_evaluation
        )
        when 3 then public.is_strict_pricing_snapshot_v3(
          snapshot.snapshot_contract_version,
          snapshot.config_version,
          snapshot.config_hash,
          snapshot.normalized_evidence,
          snapshot.calculation,
          snapshot.package_advice,
          snapshot.budget_evaluation,
          snapshot.package_definition
        )
        else false
      end
  )
$$;

create function public.quotation_approval_integrity_root_v1(
  p_approval_id uuid,
  p_payload_sha256 text,
  p_contract_version smallint,
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_pricing_snapshot_id uuid
)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'approvalId', p_approval_id,
    'contractVersion', p_contract_version,
    'intakeId', p_intake_id,
    'integrityRootVersion', 1,
    'payloadSha256', p_payload_sha256,
    'pricingSnapshotId', p_pricing_snapshot_id,
    'quoteRequestId', p_quote_request_id
  )
$$;

create function public.upsert_quotation_approval_draft_v1(
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_pricing_snapshot_id uuid,
  p_approval_payload jsonb,
  p_idempotency_key uuid,
  p_admin_access_token_hash text,
  p_created_by text
)
returns table (
  draft_id uuid,
  payload_fingerprint text,
  was_created boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
  v_draft public.quote_request_quotation_approval_drafts%rowtype;
  v_operation public.quote_request_quotation_approval_operations%rowtype;
  v_fingerprint text;
  v_created boolean := false;
begin
  if p_admin_access_token_hash is null
     or p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_created_by), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  select * into v_intake
  from public.quote_request_intakes
  where id = p_intake_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INTAKE_NOT_FOUND';
  end if;
  if v_intake.quote_request_id is distinct from p_quote_request_id then
    raise exception using errcode = 'P0001', message = 'QUOTE_REQUEST_NOT_FOUND';
  end if;
  if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null
     or v_intake.status not in ('submitted', 'reviewed') then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  if not exists (
    select 1 from public.quote_request_pricing_snapshots
    where id = p_pricing_snapshot_id
  ) then
    raise exception using errcode = 'P0001', message = 'PRICING_SNAPSHOT_NOT_FOUND';
  end if;
  if not public.is_current_pricing_snapshot_integrity_valid(
    p_intake_id, p_pricing_snapshot_id, p_approval_payload->'pricing_snapshot'
  ) then
    if exists (
      select 1 from public.quote_request_pricing_snapshots
      where id = p_pricing_snapshot_id and intake_id <> p_intake_id
    ) then
      raise exception using errcode = 'P0001', message = 'PRICING_SNAPSHOT_MISMATCH';
    end if;
    raise exception using errcode = 'P0001', message = 'PRICING_INTEGRITY_INVALID';
  end if;
  if not public.is_valid_quotation_approval_payload_v1(p_approval_payload, false) then
    raise exception using errcode = '22023', message = 'DRAFT_VALIDATION_FAILED';
  end if;

  v_fingerprint := public.quotation_approval_payload_sha256_v1(p_approval_payload);
  select * into v_operation
  from public.quote_request_quotation_approval_operations
  where idempotency_key = p_idempotency_key;

  if found then
    if v_operation.operation_type <> 'UPSERT_DRAFT'
       or v_operation.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_draft
    from public.quote_request_quotation_approval_drafts
    where id = v_operation.draft_id;
    return query select v_draft.id, v_operation.request_fingerprint,
      false, v_operation.draft_updated_at;
    return;
  end if;

  select * into v_draft
  from public.quote_request_quotation_approval_drafts
  where intake_id = p_intake_id
  for update;

  if found then
    update public.quote_request_quotation_approval_drafts
    set quote_request_id = p_quote_request_id,
        pricing_snapshot_id = p_pricing_snapshot_id,
        contract_version = 1,
        approval_payload = p_approval_payload,
        payload_fingerprint = v_fingerprint,
        idempotency_key = p_idempotency_key,
        created_by = p_created_by
    where id = v_draft.id
    returning * into v_draft;
  else
    insert into public.quote_request_quotation_approval_drafts (
      quote_request_id, intake_id, pricing_snapshot_id, contract_version,
      approval_payload, payload_fingerprint, idempotency_key, created_by
    ) values (
      p_quote_request_id, p_intake_id, p_pricing_snapshot_id, 1,
      p_approval_payload, v_fingerprint, p_idempotency_key, p_created_by
    ) returning * into v_draft;
    v_created := true;
  end if;

  insert into public.quote_request_quotation_approval_operations (
    idempotency_key, operation_type, request_fingerprint, draft_id,
    draft_updated_at
  ) values (
    p_idempotency_key, 'UPSERT_DRAFT', v_fingerprint, v_draft.id,
    v_draft.updated_at
  );

  return query select v_draft.id, v_draft.payload_fingerprint, v_created, v_draft.updated_at;
end;
$$;

create function public.approve_quotation_commercial_envelope_v1(
  p_draft_id uuid,
  p_approval_id uuid,
  p_approved_payload jsonb,
  p_idempotency_key uuid,
  p_admin_access_token_hash text,
  p_approved_by text,
  p_integrity jsonb
)
returns table (
  approval_id uuid,
  approval_version integer,
  payload_sha256 text,
  approved_at timestamptz,
  was_created boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_draft public.quote_request_quotation_approval_drafts%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_operation public.quote_request_quotation_approval_operations%rowtype;
  v_payload_sha256 text;
  v_request_fingerprint text;
  v_version integer;
begin
  if p_admin_access_token_hash is null
     or p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_approved_by), '') is null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  select * into v_draft
  from public.quote_request_quotation_approval_drafts
  where id = p_draft_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'DRAFT_NOT_FOUND';
  end if;

  select * into strict v_intake
  from public.quote_request_intakes
  where id = v_draft.intake_id
  for update;

  if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null
     or v_intake.status not in ('submitted', 'reviewed') then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  if not public.is_current_pricing_snapshot_integrity_valid(
    v_draft.intake_id,
    v_draft.pricing_snapshot_id,
    p_approved_payload->'pricing_snapshot'
  ) then
    raise exception using errcode = 'P0001', message = 'PRICING_INTEGRITY_INVALID';
  end if;

  if not public.is_valid_quotation_vat_approval_v1(p_approved_payload->'vat_approval', true) then
    raise exception using errcode = '22023', message = 'VAT_APPROVAL_MISSING';
  end if;
  if not public.is_valid_quotation_payment_schedule_v1(
    p_approved_payload->'payment_schedule',
    (p_approved_payload->'totals'->>'one_time_subtotal_minor')::bigint,
    true
  ) then
    raise exception using errcode = '22023', message = 'PAYMENT_SCHEDULE_UNAPPROVED';
  end if;
  if not public.is_valid_quotation_validity_v1(p_approved_payload->'validity', true) then
    raise exception using errcode = '22023', message = 'VALIDITY_UNAPPROVED';
  end if;
  if not public.is_valid_quotation_legal_references_v1(
    p_approved_payload->'legal_references', true
  ) then
    raise exception using errcode = '22023', message = 'LEGAL_REFERENCE_UNAPPROVED';
  end if;
  if not public.is_valid_quotation_identity_v1(p_approved_payload->'customer_identity')
     or not public.is_valid_quotation_scope_v1(p_approved_payload->'project_scope') then
    raise exception using errcode = '22023', message = 'IDENTITY_SNAPSHOT_INVALID';
  end if;
  if not public.is_valid_quotation_approval_payload_v1(p_approved_payload, true) then
    raise exception using errcode = '22023', message = 'APPROVAL_VALIDATION_FAILED';
  end if;

  v_payload_sha256 := public.quotation_approval_payload_sha256_v1(p_approved_payload);
  v_request_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'approvalId', p_approval_id,
      'draftId', p_draft_id,
      'payloadSha256', v_payload_sha256
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  select * into v_operation
  from public.quote_request_quotation_approval_operations
  where idempotency_key = p_idempotency_key;

  if found then
    if v_operation.operation_type <> 'APPROVE'
       or v_operation.request_fingerprint <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_approval
    from public.quote_request_quotation_approvals
    where id = v_operation.approval_id;
    return query select v_approval.id, v_approval.approval_version,
      v_approval.payload_sha256, v_approval.approved_at, false;
    return;
  end if;

  if v_payload_sha256 <> v_draft.payload_fingerprint then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  if not public.jsonb_has_exact_keys(p_integrity, array[
    'algorithmVersion', 'keyId', 'mac', 'root'
  ])
    or p_integrity->>'algorithmVersion' <> 'hmac-sha256-v1'
    or p_integrity->>'keyId' !~ '^v[1-9][0-9]*$'
    or not public.is_sha256_jsonb(p_integrity->'mac')
    or p_integrity->'root' <> public.quotation_approval_integrity_root_v1(
      p_approval_id, v_payload_sha256, v_draft.contract_version,
      v_draft.quote_request_id, v_draft.intake_id, v_draft.pricing_snapshot_id
    ) then
    raise exception using errcode = 'P0001', message = 'PRICING_INTEGRITY_INVALID';
  end if;

  select coalesce(max(approval.approval_version), 0) + 1 into v_version
  from public.quote_request_quotation_approvals as approval
  where approval.intake_id = v_draft.intake_id;

  begin
    insert into public.quote_request_quotation_approvals (
      id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
      contract_version, approval_version, approved_payload, payload_sha256,
      approved_by, approved_at
    ) values (
      p_approval_id, v_draft.id, v_draft.quote_request_id, v_draft.intake_id,
      v_draft.pricing_snapshot_id, v_draft.contract_version, v_version,
      p_approved_payload, v_payload_sha256, p_approved_by, clock_timestamp()
    ) returning * into v_approval;
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end;

  insert into public.quote_request_quotation_approval_integrity (
    approval_id, algorithm_version, key_id, mac
  ) values (
    v_approval.id, p_integrity->>'algorithmVersion',
    p_integrity->>'keyId', p_integrity->>'mac'
  );

  insert into public.quote_request_quotation_approval_operations (
    idempotency_key, operation_type, request_fingerprint, draft_id, approval_id
  ) values (
    p_idempotency_key, 'APPROVE', v_request_fingerprint,
    v_draft.id, v_approval.id
  );

  return query select v_approval.id, v_approval.approval_version,
    v_approval.payload_sha256, v_approval.approved_at, true;
end;
$$;

comment on function public.upsert_quotation_approval_draft_v1(uuid, uuid, uuid, jsonb, uuid, text, text) is
  'Mutable draft updates require a new idempotency key. Every prior key remains an immutable replay handle for its original result fingerprint and timestamp.';

comment on function public.approve_quotation_commercial_envelope_v1(uuid, uuid, jsonb, uuid, text, text, jsonb) is
  'Registers an Edge-produced HMAC proof atomically with the immutable approval. SQL validates exact root binding and proof shape; cryptographic MAC verification remains mandatory in trusted Edge consumers because signing secrets never enter SQL.';

create function public.prevent_quotation_approval_operation_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'QUOTATION_APPROVAL_OPERATION_IMMUTABLE';
end;
$$;

create trigger trg_quotation_approval_operations_immutable
before update or delete on public.quote_request_quotation_approval_operations
for each row execute function public.prevent_quotation_approval_operation_mutation();

alter table public.quote_request_quotation_approval_operations enable row level security;

revoke all privileges on table public.quote_request_quotation_approval_operations
from public, anon, authenticated, service_role;

revoke all on function public.is_current_pricing_snapshot_integrity_valid(uuid, uuid, jsonb)
from public, anon, authenticated;
revoke all on function public.quotation_approval_integrity_root_v1(uuid, text, smallint, uuid, uuid, uuid)
from public, anon, authenticated;
revoke all on function public.upsert_quotation_approval_draft_v1(uuid, uuid, uuid, jsonb, uuid, text, text)
from public, anon, authenticated;
revoke all on function public.approve_quotation_commercial_envelope_v1(uuid, uuid, jsonb, uuid, text, text, jsonb)
from public, anon, authenticated;
revoke all on function public.prevent_quotation_approval_operation_mutation()
from public, anon, authenticated, service_role;

grant execute on function public.is_current_pricing_snapshot_integrity_valid(uuid, uuid, jsonb)
to service_role;
grant execute on function public.quotation_approval_integrity_root_v1(uuid, text, smallint, uuid, uuid, uuid)
to service_role;
grant execute on function public.upsert_quotation_approval_draft_v1(uuid, uuid, uuid, jsonb, uuid, text, text)
to service_role;
grant execute on function public.approve_quotation_commercial_envelope_v1(uuid, uuid, jsonb, uuid, text, text, jsonb)
to service_role;
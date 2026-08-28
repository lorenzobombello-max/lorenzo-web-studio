create table public.quote_request_quotation_business_approval_promotions (
  business_draft_id uuid primary key references public.quote_request_quotation_business_drafts(business_draft_id),
  approval_id uuid not null unique references public.quote_request_quotation_approvals(id)
);

create table public.quote_request_quotation_business_approval_promotion_operations (
  idempotency_key uuid primary key,
  operation_type text not null check (operation_type = 'PROMOTE_BUSINESS_DRAFT'),
  operator_id uuid not null references public.commercial_operators(operator_id),
  business_draft_id uuid not null references public.quote_request_quotation_business_drafts(business_draft_id),
  expected_revision bigint not null check (expected_revision > 0),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  approval_id uuid not null references public.quote_request_quotation_approvals(id),
  result_payload jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);

create function public.prevent_quotation_business_approval_promotion_mutation_v1()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'QUOTATION_BUSINESS_APPROVAL_PROMOTION_IMMUTABLE';
end;
$$;

create trigger trg_quotation_business_approval_promotions_immutable
before update or delete on public.quote_request_quotation_business_approval_promotions
for each row execute function public.prevent_quotation_business_approval_promotion_mutation_v1();

create trigger trg_quotation_business_approval_promotion_operations_immutable
before update or delete on public.quote_request_quotation_business_approval_promotion_operations
for each row execute function public.prevent_quotation_business_approval_promotion_mutation_v1();

create function public.resolve_quotation_business_approval_promotion_context_v1(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_draft public.quote_request_quotation_approval_drafts%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_integrity public.quote_request_quotation_approval_integrity%rowtype;
  v_candidate_count integer;
  v_payload_sha256 text;
begin
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_BUSINESS_SCOPE_DENIED';
  end if;

  select * into v_business
  from public.quote_request_quotation_business_drafts
  where intake_id = p_intake_id
  order by business_revision desc
  limit 1;
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_BUSINESS_DRAFT_NOT_FOUND';
  end if;
  if p_expected_revision is distinct from v_business.business_revision then
    raise exception using errcode = 'P0001', message = 'STALE_BUSINESS_REVISION';
  end if;

  v_payload_sha256 := public.quotation_approval_payload_sha256_v1(v_business.canonical_payload);
  if rtrim(v_business.canonical_payload_sha256) <> v_payload_sha256 then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  select * into v_draft
  from public.quote_request_quotation_approval_drafts
  where id = v_business.approval_draft_id;
  if not found
     or v_draft.intake_id is distinct from v_business.intake_id
     or v_draft.quote_request_id is distinct from v_business.quote_request_id
     or v_draft.pricing_snapshot_id is distinct from v_business.pricing_snapshot_id
     or v_draft.contract_version <> 1
     or v_draft.approval_payload is distinct from v_business.canonical_payload
     or v_draft.payload_fingerprint <> v_payload_sha256 then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  select count(*)::integer into v_candidate_count
  from public.quote_request_quotation_approvals as approval
  where approval.draft_id = v_business.approval_draft_id
    and approval.intake_id = v_business.intake_id
    and approval.quote_request_id = v_business.quote_request_id
    and approval.pricing_snapshot_id = v_business.pricing_snapshot_id
    and approval.contract_version = 1
    and approval.approved_payload = v_business.canonical_payload
    and approval.payload_sha256 = v_payload_sha256;

  if v_candidate_count > 1 then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  if v_candidate_count = 1 then
    select approval.* into strict v_approval
    from public.quote_request_quotation_approvals as approval
    where approval.draft_id = v_business.approval_draft_id
      and approval.intake_id = v_business.intake_id
      and approval.quote_request_id = v_business.quote_request_id
      and approval.pricing_snapshot_id = v_business.pricing_snapshot_id
      and approval.contract_version = 1
      and approval.approved_payload = v_business.canonical_payload
      and approval.payload_sha256 = v_payload_sha256;

    select * into v_integrity
    from public.quote_request_quotation_approval_integrity
    where approval_id = v_approval.id;
    if not found
       or v_integrity.algorithm_version <> 'hmac-sha256-v1'
       or v_integrity.key_id !~ '^v[1-9][0-9]*$'
       or v_integrity.mac !~ '^[0-9a-f]{64}$' then
      raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
    end if;

    return jsonb_build_object(
      'mode', 'ADOPT',
      'business_draft_id', v_business.business_draft_id,
      'business_revision', v_business.business_revision,
      'approval_draft_id', v_business.approval_draft_id,
      'approval_id', v_approval.id,
      'quote_request_id', v_business.quote_request_id,
      'intake_id', v_business.intake_id,
      'pricing_snapshot_id', v_business.pricing_snapshot_id,
      'contract_version', 1,
      'payload_sha256', v_payload_sha256,
      'integrity', jsonb_build_object(
        'algorithmVersion', v_integrity.algorithm_version,
        'keyId', v_integrity.key_id,
        'mac', v_integrity.mac,
        'root', public.quotation_approval_integrity_root_v1(
          v_approval.id, v_payload_sha256, 1::smallint,
          v_business.quote_request_id, v_business.intake_id,
          v_business.pricing_snapshot_id
        )
      )
    );
  end if;

  return jsonb_build_object(
    'mode', 'CREATE',
    'business_draft_id', v_business.business_draft_id,
    'business_revision', v_business.business_revision,
    'approval_draft_id', v_business.approval_draft_id,
    'quote_request_id', v_business.quote_request_id,
    'intake_id', v_business.intake_id,
    'pricing_snapshot_id', v_business.pricing_snapshot_id,
    'contract_version', 1,
    'payload_sha256', v_payload_sha256
  );
end;
$$;

create function public.promote_quotation_business_draft_to_approval_v1(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_approval_id uuid,
  p_integrity jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_context jsonb;
  v_operator public.commercial_operators%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_operation public.quote_request_quotation_business_approval_promotion_operations%rowtype;
  v_promotion public.quote_request_quotation_business_approval_promotions%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_approval_result record;
  v_fingerprint text;
  v_result jsonb;
  v_mode text;
begin
  if p_actor_auth_user_id is null or p_intake_id is null
     or p_expected_revision is null or p_expected_revision < 1
     or p_idempotency_key is null or p_approval_id is null
     or p_integrity is null then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST';
  end if;

  v_context := public.resolve_quotation_business_approval_promotion_context_v1(
    p_actor_auth_user_id, p_intake_id, p_expected_revision
  );

  perform pg_catalog.pg_advisory_xact_lock(
    17001,
    pg_catalog.hashtext(v_context->>'business_draft_id')
  );
  perform pg_catalog.pg_advisory_xact_lock(
    17002,
    pg_catalog.hashtext(p_idempotency_key::text)
  );

  v_context := public.resolve_quotation_business_approval_promotion_context_v1(
    p_actor_auth_user_id, p_intake_id, p_expected_revision
  );
  v_mode := v_context->>'mode';

  select * into strict v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id
    and status = 'ACTIVE' and role in ('owner', 'admin');
  select * into strict v_business
  from public.quote_request_quotation_business_drafts
  where business_draft_id = (v_context->>'business_draft_id')::uuid;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'businessDraftId', v_business.business_draft_id,
    'businessRevision', v_business.business_revision,
    'canonicalPayloadSha256', rtrim(v_business.canonical_payload_sha256),
    'operationType', 'PROMOTE_BUSINESS_DRAFT',
    'operatorId', v_operator.operator_id
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_operation
  from public.quote_request_quotation_business_approval_promotion_operations
  where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_operation.result_payload || jsonb_build_object('was_created', false);
  end if;

  select * into v_promotion
  from public.quote_request_quotation_business_approval_promotions
  where business_draft_id = v_business.business_draft_id;
  if found then
    select * into strict v_approval
    from public.quote_request_quotation_approvals
    where id = v_promotion.approval_id;
    v_result := jsonb_build_object(
      'business_draft_id', v_business.business_draft_id,
      'business_revision', v_business.business_revision,
      'approval_id', v_approval.id,
      'approval_version', v_approval.approval_version,
      'status', 'APPROVED',
      'approved_at', v_approval.approved_at,
      'was_created', false
    );
    insert into public.quote_request_quotation_business_approval_promotion_operations (
      idempotency_key, operation_type, operator_id, business_draft_id,
      expected_revision, request_fingerprint, approval_id, result_payload
    ) values (
      p_idempotency_key, 'PROMOTE_BUSINESS_DRAFT', v_operator.operator_id,
      v_business.business_draft_id, p_expected_revision, v_fingerprint,
      v_approval.id, v_result
    );
    return v_result;
  end if;

  if not public.jsonb_has_exact_keys(p_integrity, array['algorithmVersion', 'keyId', 'mac', 'root'])
     or p_integrity->'root' <> public.quotation_approval_integrity_root_v1(
      p_approval_id, rtrim(v_business.canonical_payload_sha256), 1::smallint,
       v_business.quote_request_id, v_business.intake_id,
       v_business.pricing_snapshot_id
     ) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  if v_mode = 'ADOPT' then
    if p_approval_id is distinct from (v_context->>'approval_id')::uuid
       or p_integrity is distinct from v_context->'integrity' then
      raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
    end if;
    select * into strict v_approval
    from public.quote_request_quotation_approvals
    where id = p_approval_id;
  elsif v_mode = 'CREATE' then
    select * into strict v_intake
    from public.quote_request_intakes
    where id = v_business.intake_id;
    select * into strict v_approval_result
    from public.approve_quotation_commercial_envelope_v1(
      v_business.approval_draft_id,
      p_approval_id,
      v_business.canonical_payload,
      p_idempotency_key,
      v_intake.admin_access_token_hash,
      'OPERATOR:' || v_operator.operator_id::text,
      p_integrity
    );
    select * into strict v_approval
    from public.quote_request_quotation_approvals
    where id = v_approval_result.approval_id;
  else
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  insert into public.quote_request_quotation_business_approval_promotions (
    business_draft_id, approval_id
  ) values (v_business.business_draft_id, v_approval.id);

  v_result := jsonb_build_object(
    'business_draft_id', v_business.business_draft_id,
    'business_revision', v_business.business_revision,
    'approval_id', v_approval.id,
    'approval_version', v_approval.approval_version,
    'status', 'APPROVED',
    'approved_at', v_approval.approved_at,
    'was_created', v_mode = 'CREATE'
  );

  insert into public.quote_request_quotation_business_approval_promotion_operations (
    idempotency_key, operation_type, operator_id, business_draft_id,
    expected_revision, request_fingerprint, approval_id, result_payload
  ) values (
    p_idempotency_key, 'PROMOTE_BUSINESS_DRAFT', v_operator.operator_id,
    v_business.business_draft_id, p_expected_revision, v_fingerprint,
    v_approval.id, v_result
  );
  return v_result;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
end;
$$;

alter table public.quote_request_quotation_business_approval_promotions enable row level security;
alter table public.quote_request_quotation_business_approval_promotions force row level security;
alter table public.quote_request_quotation_business_approval_promotion_operations enable row level security;
alter table public.quote_request_quotation_business_approval_promotion_operations force row level security;

revoke all privileges on table public.quote_request_quotation_business_approval_promotions
from public, anon, authenticated, service_role;
revoke all privileges on table public.quote_request_quotation_business_approval_promotion_operations
from public, anon, authenticated, service_role;
revoke all on function public.prevent_quotation_business_approval_promotion_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.resolve_quotation_business_approval_promotion_context_v1(uuid, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.promote_quotation_business_draft_to_approval_v1(uuid, uuid, bigint, uuid, uuid, jsonb)
from public, anon, authenticated, service_role;

grant execute on function public.resolve_quotation_business_approval_promotion_context_v1(uuid, uuid, bigint)
to service_role;
grant execute on function public.promote_quotation_business_draft_to_approval_v1(uuid, uuid, bigint, uuid, uuid, jsonb)
to service_role;

comment on function public.resolve_quotation_business_approval_promotion_context_v1(uuid, uuid, bigint) is
  'Service-only resolver for latest immutable quotation business revision and exact legacy approval integrity context.';
comment on function public.promote_quotation_business_draft_to_approval_v1(uuid, uuid, bigint, uuid, uuid, jsonb) is
  'Atomically binds one latest immutable business revision to one existing canonical quotation approval, creating through the existing approval authority only when no exact legacy approval exists.';

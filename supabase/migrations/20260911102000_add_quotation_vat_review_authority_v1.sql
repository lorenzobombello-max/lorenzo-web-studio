create table public.quotation_vat_review_requests (
  review_request_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null
    references public.quote_requests(id) on delete restrict,
  intake_id uuid not null
    references public.quote_request_intakes(id) on delete restrict,
  context_sha256 char(64) not null check (context_sha256 ~ '^[0-9a-f]{64}$'),
  classification_policy_id uuid
    references public.quotation_vat_classification_policies(classification_policy_id)
    on delete restrict,
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  reason text not null check (
    reason = btrim(reason) and char_length(reason) between 1 and 2000
  ),
  status text not null check (status = 'REVIEW_REQUIRED'),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result_payload jsonb not null check (jsonb_typeof(result_payload) = 'object'),
  requested_at timestamptz not null
);

create table public.quotation_vat_review_events (
  review_event_id bigint generated always as identity primary key,
  review_request_id uuid not null
    references public.quotation_vat_review_requests(review_request_id) on delete restrict,
  quote_request_id uuid not null
    references public.quote_requests(id) on delete restrict,
  intake_id uuid not null
    references public.quote_request_intakes(id) on delete restrict,
  context_sha256 char(64) not null check (context_sha256 ~ '^[0-9a-f]{64}$'),
  classification_policy_id uuid
    references public.quotation_vat_classification_policies(classification_policy_id)
    on delete restrict,
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  reason text not null check (
    reason = btrim(reason) and char_length(reason) between 1 and 2000
  ),
  status text not null check (status = 'REVIEW_REQUIRED'),
  event_type text not null check (event_type = 'REVIEW_REQUESTED'),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  occurred_at timestamptz not null,
  unique (review_request_id, event_type)
);

create function lws_internal.guard_quotation_vat_review_request_immutable_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'QUOTATION_VAT_REVIEW_IMMUTABLE';
end;
$$;

create function lws_internal.guard_quotation_vat_review_event_immutable_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'QUOTATION_VAT_REVIEW_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_quotation_vat_review_requests_immutable
before update or delete on public.quotation_vat_review_requests
for each row execute function
  lws_internal.guard_quotation_vat_review_request_immutable_v1();

create trigger trg_quotation_vat_review_events_immutable
before update or delete on public.quotation_vat_review_events
for each row execute function
  lws_internal.guard_quotation_vat_review_event_immutable_v1();

create function public.request_quotation_vat_review_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, lws_internal, auth, extensions
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_existing public.quotation_vat_review_requests%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_context_sha256 text;
  v_jurisdiction text;
  v_policy_id uuid;
  v_policy_count integer;
  v_request_fingerprint text;
  v_review_request_id uuid := gen_random_uuid();
  v_requested_at timestamptz := clock_timestamp();
  v_evaluation_date date := (clock_timestamp() at time zone 'Europe/Brussels')::date;
  v_result jsonb;
  v_action_is_critical boolean;
begin
  if p_actor_auth_user_id is null
     or p_quote_request_id is null
     or p_intake_id is null
     or p_idempotency_key is null
     or char_length(v_reason) not between 1 and 2000 then
    raise exception using
      errcode = '22023',
      message = 'QUOTATION_VAT_REVIEW_INPUT_INVALID';
  end if;

  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid() <> p_actor_auth_user_id then
    raise exception using
      errcode = '42501',
      message = 'OPERATOR_IDENTITY_MISMATCH';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role not in ('owner', 'admin') then
    raise exception using
      errcode = '42501',
      message = 'QUOTATION_VAT_REVIEW_FORBIDDEN';
  end if;

  select exists (
    select 1
    from lws_internal.security_action_policy
    where action_code = 'request_quotation_vat_review_v1'
      and risk_level = 'CRITICAL'
  ) into v_action_is_critical;
  if v_action_is_critical then
    perform lws_internal.assert_operator_aal2_v1();
  end if;

  v_request_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'actor_auth_user_id', p_actor_auth_user_id,
      'authority_version', 1,
      'intake_id', p_intake_id,
      'quote_request_id', p_quote_request_id,
      'reason', v_reason
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );
  select * into v_existing
  from public.quotation_vat_review_requests
  where idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint) <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_quote_request_id::text, 0)
  );
  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id;
  if not found then
    raise exception using
      errcode = '23503',
      message = 'QUOTATION_VAT_REVIEW_REQUEST_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from public.quote_request_intakes
    where id = p_intake_id
      and quote_request_id = p_quote_request_id
      and status in ('submitted', 'reviewed')
  ) then
    raise exception using
      errcode = '23514',
      message = 'QUOTATION_VAT_REVIEW_INTAKE_MISMATCH';
  end if;

  v_context_sha256 := public.quotation_vat_context_sha256_v1(
    p_quote_request_id
  );
  v_jurisdiction := case
    when lower(btrim(coalesce(v_request.billing_country, ''))) in (
      'be', 'belgie', 'belgië', 'belgium'
    ) then 'BE'
    else upper(btrim(coalesce(v_request.billing_country, '')))
  end;

  select count(*)::integer, min(policy.classification_policy_id::text)::uuid
  into v_policy_count, v_policy_id
  from public.quotation_vat_classification_policies as policy
  where policy.status = 'APPROVED'
    and policy.customer_type = v_request.customer_type
    and policy.jurisdiction = v_jurisdiction
    and policy.effective_from <= v_evaluation_date
    and (policy.effective_until is null or policy.effective_until >= v_evaluation_date);
  if v_policy_count <> 1 then
    v_policy_id := null;
  end if;

  perform lws_internal.assert_quotation_vat_context_current_v1(
    p_quote_request_id,
    v_context_sha256
  );

  v_result := jsonb_build_object(
    'review_request_id', v_review_request_id,
    'quote_request_id', p_quote_request_id,
    'intake_id', p_intake_id,
    'context_sha256', v_context_sha256,
    'classification_policy_id', v_policy_id,
    'actor_operator_id', v_operator.operator_id,
    'reason', v_reason,
    'status', 'REVIEW_REQUIRED',
    'requested_at', v_requested_at,
    'replayed', false
  );

  insert into public.quotation_vat_review_requests (
    review_request_id, quote_request_id, intake_id, context_sha256,
    classification_policy_id, actor_operator_id, reason, status,
    idempotency_key, request_fingerprint, result_payload, requested_at
  ) values (
    v_review_request_id, p_quote_request_id, p_intake_id, v_context_sha256,
    v_policy_id, v_operator.operator_id, v_reason, 'REVIEW_REQUIRED',
    p_idempotency_key, v_request_fingerprint, v_result, v_requested_at
  );

  insert into public.quotation_vat_review_events (
    review_request_id, quote_request_id, intake_id, context_sha256,
    classification_policy_id, actor_operator_id, reason, status, event_type,
    idempotency_key, request_fingerprint, occurred_at
  ) values (
    v_review_request_id, p_quote_request_id, p_intake_id, v_context_sha256,
    v_policy_id, v_operator.operator_id, v_reason, 'REVIEW_REQUIRED',
    'REVIEW_REQUESTED', p_idempotency_key, v_request_fingerprint,
    v_requested_at
  );

  return v_result;
end;
$$;

alter table public.quotation_vat_review_requests enable row level security;
alter table public.quotation_vat_review_requests force row level security;
alter table public.quotation_vat_review_events enable row level security;
alter table public.quotation_vat_review_events force row level security;

revoke all privileges on table public.quotation_vat_review_requests
from public, anon, authenticated, service_role;
revoke all privileges on table public.quotation_vat_review_events
from public, anon, authenticated, service_role;
revoke all privileges on sequence public.quotation_vat_review_events_review_event_id_seq
from public, anon, authenticated, service_role;

revoke all on function lws_internal.guard_quotation_vat_review_request_immutable_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_quotation_vat_review_event_immutable_v1()
from public, anon, authenticated, service_role;
revoke all on function public.request_quotation_vat_review_v1(
  uuid, uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.request_quotation_vat_review_v1(
  uuid, uuid, uuid, text, uuid
) to authenticated;

comment on function public.request_quotation_vat_review_v1(
  uuid, uuid, uuid, text, uuid
) is
  'Appends an immutable human VAT review request without approving or recording any VAT classification.';

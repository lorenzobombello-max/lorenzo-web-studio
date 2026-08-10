create schema if not exists lws_internal;

revoke all on schema lws_internal from public, anon, authenticated;

grant usage on schema lws_internal to service_role;

create table lws_internal.preview_rate_limit_buckets (
  namespace text not null,
  key_hash text not null,
  window_started_at timestamptz not null,
  window_expires_at timestamptz not null,
  request_count integer not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint preview_rate_limit_buckets_pk
    primary key (namespace, key_hash, window_started_at),
  constraint preview_rate_limit_buckets_namespace_check
    check (namespace in ('preview_global', 'preview_capability')),
  constraint preview_rate_limit_buckets_key_hash_check
    check (key_hash ~ '^[0-9a-f]{64}$'),
  constraint preview_rate_limit_buckets_window_check
    check (
      window_started_at = date_trunc('second', window_started_at)
      and window_expires_at = date_trunc('second', window_expires_at)
      and window_expires_at > window_started_at
      and window_expires_at <= window_started_at + interval '1 hour'
    ),
  constraint preview_rate_limit_buckets_count_check
    check (request_count between 1 and 10001),
  constraint preview_rate_limit_buckets_timestamps_check
    check (updated_at >= created_at)
);

create index preview_rate_limit_buckets_expiry_idx
on lws_internal.preview_rate_limit_buckets (window_expires_at);

revoke all privileges
on table lws_internal.preview_rate_limit_buckets
from public, anon, authenticated, service_role;

create function public.consume_preview_rate_limit_v1(
  p_namespace text,
  p_key_hash text,
  p_window_seconds integer,
  p_max_requests integer,
  p_cleanup_batch integer default 25
)
returns table (
  allowed boolean,
  remaining integer,
  reset_at timestamptz,
  retry_after_seconds integer
)
language plpgsql
volatile
security definer
set search_path = lws_internal, pg_catalog
as $$
declare
  v_now timestamptz := date_trunc('second', clock_timestamp());
  v_window_started_at timestamptz;
  v_window_expires_at timestamptz;
  v_request_count integer;
begin
  if p_namespace is null
     or p_namespace not in ('preview_global', 'preview_capability') then
    raise exception using errcode = '22023', message = 'INVALID_RATE_LIMIT_NAMESPACE';
  end if;
  if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_RATE_LIMIT_KEY';
  end if;
  if p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 3600 then
    raise exception using errcode = '22023', message = 'INVALID_RATE_LIMIT_WINDOW';
  end if;
  if p_max_requests is null or p_max_requests < 1 or p_max_requests > 10000 then
    raise exception using errcode = '22023', message = 'INVALID_RATE_LIMIT_MAX_REQUESTS';
  end if;
  if p_cleanup_batch is null or p_cleanup_batch < 0 or p_cleanup_batch > 100 then
    raise exception using errcode = '22023', message = 'INVALID_RATE_LIMIT_CLEANUP_BATCH';
  end if;

  v_window_started_at := to_timestamp(
    floor(extract(epoch from v_now) / p_window_seconds) * p_window_seconds
  );
  v_window_expires_at := v_window_started_at + make_interval(secs => p_window_seconds);

  insert into lws_internal.preview_rate_limit_buckets as bucket (
    namespace,
    key_hash,
    window_started_at,
    window_expires_at,
    request_count,
    created_at,
    updated_at
  ) values (
    p_namespace,
    p_key_hash,
    v_window_started_at,
    v_window_expires_at,
    1,
    v_now,
    v_now
  )
  on conflict (namespace, key_hash, window_started_at) do update
  set request_count = least(bucket.request_count + 1, 10001),
      updated_at = greatest(bucket.created_at, v_now)
  returning request_count into v_request_count;

  if p_cleanup_batch > 0 then
    delete from lws_internal.preview_rate_limit_buckets
    where (namespace, key_hash, window_started_at) in (
      select expired.namespace, expired.key_hash, expired.window_started_at
      from lws_internal.preview_rate_limit_buckets as expired
      where expired.window_expires_at < v_now - interval '1 hour'
      order by expired.window_expires_at
      limit p_cleanup_batch
      for update skip locked
    );
  end if;

  return query select
    v_request_count <= p_max_requests,
    greatest(p_max_requests - v_request_count, 0),
    v_window_expires_at,
    case
      when v_request_count <= p_max_requests then 0
      else greatest(1, ceil(extract(epoch from v_window_expires_at - v_now))::integer)
    end;
end;
$$;

revoke all
on function public.consume_preview_rate_limit_v1(text, text, integer, integer, integer)
from public, anon, authenticated;

grant execute
on function public.consume_preview_rate_limit_v1(text, text, integer, integer, integer)
to service_role;

comment on table lws_internal.preview_rate_limit_buckets is
  'Short-lived infrastructure-only abuse-control state. Contains no raw capabilities, intake payloads, pricing data, snapshots, or lifecycle state.';

comment on function public.consume_preview_rate_limit_v1(text, text, integer, integer, integer) is
  'Service-role-only atomic fixed-window limiter with bounded opportunistic cleanup.';

create function public.inspect_preview_budget_guard_context_v1(
  p_access_token_hash text
)
returns table (
  intake_status text,
  budget_label text,
  budget_category_scheme text,
  budget_category_code text
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select
    intake.status::text,
    request.budget,
    request.budget_category_scheme,
    request.budget_category_code
  from public.quote_request_intakes as intake
  inner join public.quote_requests as request
    on request.id = intake.quote_request_id
  where p_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.access_token_hash = p_access_token_hash
    and intake.access_token_expires_at > clock_timestamp()
    and intake.access_token_revoked_at is null
  limit 1
$$;

revoke all
on function public.inspect_preview_budget_guard_context_v1(text)
from public, anon, authenticated;

grant execute
on function public.inspect_preview_budget_guard_context_v1(text)
to service_role;

comment on function public.inspect_preview_budget_guard_context_v1(text) is
  'Service-role-only preview capability and lifecycle read. Returns no PII, intake payload, pricing state, snapshot, or proof.';

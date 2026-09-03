create table if not exists lws_internal.operator_dossier_seen_states (
  quote_request_id uuid not null references public.quote_requests(id) on delete cascade,
  operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  first_seen_at timestamptz not null,
  seen_at timestamptz not null,
  primary key (quote_request_id, operator_id),
  constraint operator_dossier_seen_states_time_order_check
    check (seen_at >= first_seen_at)
);

alter table lws_internal.operator_dossier_seen_states enable row level security;
alter table lws_internal.operator_dossier_seen_states force row level security;

create index if not exists operator_dossier_seen_states_operator_idx
  on lws_internal.operator_dossier_seen_states (operator_id, seen_at desc, quote_request_id);

revoke all on table lws_internal.operator_dossier_seen_states
from public, anon, authenticated, service_role;

create or replace function lws_internal.project_operator_dossier_seen_v1(
  p_result jsonb,
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_operator_id uuid;
  v_items jsonb;
begin
  select operator_id into v_operator_id
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;

  select coalesce(jsonb_agg(
    listed.item || jsonb_build_object('seen_at', seen.seen_at)
    order by listed.ordinality
  ), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(p_result->'items') with ordinality as listed(item, ordinality)
  left join lws_internal.operator_dossier_seen_states as seen
    on seen.quote_request_id = (listed.item->>'quote_request_id')::uuid
   and seen.operator_id = v_operator_id;

  return jsonb_set(p_result, '{items}', v_items, false);
end;
$$;

alter function public.list_operator_applications_v2(
  uuid, text, text, integer, text, text, text, timestamptz, uuid, integer
) rename to list_operator_applications_v2_pre_dos_r1_current_seen;

create function public.list_operator_applications_v2(
  p_actor_auth_user_id uuid,
  p_zone text default 'ACTIVE',
  p_operational_status text default null,
  p_year integer default null,
  p_quarter text default null,
  p_request_kind text default null,
  p_search text default null,
  p_cursor_date timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns jsonb
language sql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
  select lws_internal.project_operator_dossier_seen_v1(
    public.list_operator_applications_v2_pre_dos_r1_current_seen(
      p_actor_auth_user_id, p_zone, p_operational_status, p_year, p_quarter,
      p_request_kind, p_search, p_cursor_date, p_cursor_id, p_limit
    ),
    p_actor_auth_user_id
  );
$$;

alter function public.list_operator_pending_intakes_v1(uuid, text)
  rename to list_operator_pending_intakes_v1_pre_dos_r1_current_seen;

create function public.list_operator_pending_intakes_v1(
  p_actor_auth_user_id uuid,
  p_retention_state text default 'ACTIVE'
)
returns jsonb
language sql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
  select lws_internal.project_operator_dossier_seen_v1(
    public.list_operator_pending_intakes_v1_pre_dos_r1_current_seen(
      p_actor_auth_user_id, p_retention_state
    ),
    p_actor_auth_user_id
  );
$$;

alter function public.list_operator_pending_sdf_intakes_v1(uuid)
  rename to list_operator_pending_sdf_intakes_v1_pre_dos_r1_current_seen;

create function public.list_operator_pending_sdf_intakes_v1(
  p_actor_auth_user_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
  select lws_internal.project_operator_dossier_seen_v1(
    public.list_operator_pending_sdf_intakes_v1_pre_dos_r1_current_seen(p_actor_auth_user_id),
    p_actor_auth_user_id
  );
$$;

create or replace function public.mark_operator_dossier_seen_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_operator_id uuid;
  v_seen lws_internal.operator_dossier_seen_states%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);

  select operator_id into v_operator_id
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;

  if p_quote_request_id is null or not exists (
    select 1
    from public.quote_requests as request
    join lws_internal.operator_dossier_states as state
      on state.quote_request_id = request.id
    where request.id = p_quote_request_id
      and request.record_classification = 'production'
  ) then
    raise exception using errcode = 'P0001', message = 'DOSSIER_NOT_FOUND';
  end if;

  insert into lws_internal.operator_dossier_seen_states (
    quote_request_id, operator_id, first_seen_at, seen_at
  ) values (
    p_quote_request_id, v_operator_id, v_now, v_now
  )
  on conflict (quote_request_id, operator_id) do update
    set seen_at = excluded.seen_at
  returning * into v_seen;

  return jsonb_build_object(
    'quote_request_id', v_seen.quote_request_id,
    'seen_at', v_seen.seen_at
  );
end;
$$;

revoke all on function lws_internal.project_operator_dossier_seen_v1(jsonb, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_operator_applications_v2_pre_dos_r1_current_seen(
  uuid, text, text, integer, text, text, text, timestamptz, uuid, integer
) from public, anon, authenticated, service_role;
revoke all on function public.list_operator_pending_intakes_v1_pre_dos_r1_current_seen(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.list_operator_pending_sdf_intakes_v1_pre_dos_r1_current_seen(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_operator_applications_v2(
  uuid, text, text, integer, text, text, text, timestamptz, uuid, integer
) from public, anon, authenticated, service_role;
revoke all on function public.list_operator_pending_intakes_v1(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.list_operator_pending_sdf_intakes_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.mark_operator_dossier_seen_v1(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.list_operator_applications_v2(
  uuid, text, text, integer, text, text, text, timestamptz, uuid, integer
) to service_role;
grant execute on function public.list_operator_pending_intakes_v1(uuid, text)
to service_role;
grant execute on function public.list_operator_pending_sdf_intakes_v1(uuid)
to service_role;
grant execute on function public.mark_operator_dossier_seen_v1(uuid, uuid)
to service_role;

comment on table lws_internal.operator_dossier_seen_states is
  'Per-operator Dossiers seen state, written only after an authoritative detail open succeeds.';
comment on function public.mark_operator_dossier_seen_v1(uuid, uuid) is
  'Service-only Dossiers transport that binds seen state to a server-derived human actor.';
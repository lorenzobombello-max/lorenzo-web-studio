create or replace function public.list_operator_applications_v2(
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
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid() <> p_actor_auth_user_id then
    raise exception using errcode = '42501', message = 'OPERATOR_IDENTITY_MISMATCH';
  end if;
  return lws_internal.project_operator_dossier_seen_v1(
    public.list_operator_applications_v2_pre_dos_r1_current_seen(
      p_actor_auth_user_id,
      p_zone,
      p_operational_status,
      p_year,
      p_quarter,
      p_request_kind,
      p_search,
      p_cursor_date,
      p_cursor_id,
      p_limit
    ),
    p_actor_auth_user_id
  );
end;
$$;

revoke all on function public.list_operator_applications_v2(
  uuid, text, text, integer, text, text, text, timestamptz, uuid, integer
) from public, anon, authenticated, service_role;
grant execute on function public.list_operator_applications_v2(
  uuid, text, text, integer, text, text, text, timestamptz, uuid, integer
) to authenticated;

comment on function public.list_operator_applications_v2(
  uuid, text, text, integer, text, text, text, timestamptz, uuid, integer
) is 'Authenticated read-only dossier-list projection bound to the caller Auth UUID.';
create function lws_internal.assert_operator_aal2_v1()
returns void
language plpgsql
stable
security definer
set search_path = auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_aal text := coalesce(auth.jwt() ->> 'aal', '');
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if v_subject not in (
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'::uuid,
    'bd2ab636-0d42-4069-88a9-60bd97f2b335'::uuid
  ) then
    raise exception using errcode = '42501', message = 'MFA_OPERATOR_NOT_ELIGIBLE';
  end if;
  if v_aal <> 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2_REQUIRED';
  end if;
end;
$$;

revoke all on function lws_internal.assert_operator_aal2_v1() from public, anon, authenticated, service_role;

alter function public.purge_dossier_v1(uuid, text, uuid)
  rename to purge_dossier_pre_mfa_impl_v1;
revoke all on function public.purge_dossier_pre_mfa_impl_v1(uuid, text, uuid)
  from public, anon, authenticated, service_role;

create function public.purge_dossier_v1(
  p_quote_request_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  perform lws_internal.assert_operator_aal2_v1();
  return public.purge_dossier_pre_mfa_impl_v1(p_quote_request_id, p_reason, p_idempotency_key);
end;
$$;

alter function public.purge_sdf_dossier_v1(uuid, text, uuid)
  rename to purge_sdf_dossier_pre_mfa_impl_v1;
revoke all on function public.purge_sdf_dossier_pre_mfa_impl_v1(uuid, text, uuid)
  from public, anon, authenticated, service_role;

create function public.purge_sdf_dossier_v1(
  p_quote_request_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  perform lws_internal.assert_operator_aal2_v1();
  return public.purge_sdf_dossier_pre_mfa_impl_v1(p_quote_request_id, p_reason, p_idempotency_key);
end;
$$;

alter function public.appoint_operations_manager_v1(uuid, text)
  rename to appoint_operations_manager_pre_mfa_impl_v1;
revoke all on function public.appoint_operations_manager_pre_mfa_impl_v1(uuid, text)
  from public, anon, authenticated, service_role;

create function public.appoint_operations_manager_v1(
  p_operator_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  perform lws_internal.assert_operator_aal2_v1();
  return public.appoint_operations_manager_pre_mfa_impl_v1(p_operator_id, p_reason);
end;
$$;

alter function public.revoke_operations_manager_v1(uuid, text, text)
  rename to revoke_operations_manager_pre_mfa_impl_v1;
revoke all on function public.revoke_operations_manager_pre_mfa_impl_v1(uuid, text, text)
  from public, anon, authenticated, service_role;

create function public.revoke_operations_manager_v1(
  p_operator_id uuid,
  p_reason text,
  p_fallback_role text default 'operator'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  perform lws_internal.assert_operator_aal2_v1();
  return public.revoke_operations_manager_pre_mfa_impl_v1(p_operator_id, p_reason, p_fallback_role);
end;
$$;

alter function public.revoke_operator_workspace_v1(uuid, bigint, uuid, uuid)
  rename to revoke_operator_workspace_pre_mfa_impl_v1;
revoke all on function public.revoke_operator_workspace_pre_mfa_impl_v1(uuid, bigint, uuid, uuid)
  from public, anon, authenticated, service_role;

create function public.revoke_operator_workspace_v1(
  p_workspace_id uuid,
  p_epoch bigint,
  p_master_window_id uuid,
  p_renewal_token uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  perform lws_internal.assert_operator_aal2_v1();
  return public.revoke_operator_workspace_pre_mfa_impl_v1(
    p_workspace_id,
    p_epoch,
    p_master_window_id,
    p_renewal_token
  );
end;
$$;

revoke all on function public.purge_dossier_v1(uuid, text, uuid) from public, anon, service_role;
revoke all on function public.purge_sdf_dossier_v1(uuid, text, uuid) from public, anon, service_role;
revoke all on function public.appoint_operations_manager_v1(uuid, text) from public, anon, service_role;
revoke all on function public.revoke_operations_manager_v1(uuid, text, text) from public, anon, service_role;
revoke all on function public.revoke_operator_workspace_v1(uuid, bigint, uuid, uuid) from public, anon, service_role;
grant execute on function public.purge_dossier_v1(uuid, text, uuid) to authenticated;
grant execute on function public.purge_sdf_dossier_v1(uuid, text, uuid) to authenticated;
grant execute on function public.appoint_operations_manager_v1(uuid, text) to authenticated;
grant execute on function public.revoke_operations_manager_v1(uuid, text, text) to authenticated;
grant execute on function public.revoke_operator_workspace_v1(uuid, bigint, uuid, uuid) to authenticated;

create function lws_internal.guard_operator_auth_uuid_binding_aal2_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, auth, pg_catalog
as $$
begin
  perform lws_internal.assert_operator_aal2_v1();
  return new;
end;
$$;

revoke all on function lws_internal.guard_operator_auth_uuid_binding_aal2_v1()
  from public, anon, authenticated, service_role;

create trigger trg_commercial_operator_auth_uuid_binding_aal2
before insert or update of auth_user_id on public.commercial_operators
for each row execute function lws_internal.guard_operator_auth_uuid_binding_aal2_v1();

create trigger trg_operator_profile_auth_uuid_binding_aal2
before insert or update of auth_user_id on public.operator_profile_definitions
for each row execute function lws_internal.guard_operator_auth_uuid_binding_aal2_v1();

comment on function lws_internal.assert_operator_aal2_v1() is
  'Requires an AAL2 human JWT for the immutable OP-01 or OP-02 Auth UUID; role authority remains enforced by the called operation.';
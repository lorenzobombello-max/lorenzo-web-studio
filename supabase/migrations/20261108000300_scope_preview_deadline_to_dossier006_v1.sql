-- Scheduled cleanup is authorized only for dossier006. General worker RPCs remain unchanged.
create function lws_internal.is_preview_deadline_dossier006_v1(p_lease_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog
as $$
  select exists (
    select 1 from lws_internal.website_project_preview_build_leases
    where preview_lease_id = p_lease_id
      and quote_request_id = '7458c346-dfc9-40f3-ad0e-cb94a16636bf'
      and website_work_context_id = 'a88b1e87-9271-4ad1-99cc-b385b7982a8b'
      and website_workspace_id = 'fa057e1f-d03d-47cf-a595-317447734298'
  );
$$;
revoke all on function lws_internal.is_preview_deadline_dossier006_v1(uuid) from public, anon, authenticated, service_role;

create function public.expire_website_project_preview_dispatches_dossier006_v1()
returns integer language plpgsql security definer set search_path = pg_catalog
as $$
declare item record; expired_count integer := 0; outcome jsonb;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  perform lws_internal.lock_preview_lifecycle_v1();
  for item in select preview_lease_id from lws_internal.website_project_preview_dispatches
    where finished_at is null and expires_at <= clock_timestamp()
      and lws_internal.is_preview_deadline_dossier006_v1(preview_lease_id)
    order by expires_at limit 100
  loop
    outcome := lws_internal.fail_preview_dispatch_v1(item.preview_lease_id,'DEADLINE_EXCEEDED');
    if outcome->>'transitioned' = 'true' and outcome->>'reason' = 'DEADLINE_EXCEEDED' then
      expired_count := expired_count + 1;
    end if;
  end loop;
  return expired_count;
end $$;

create function public.get_website_project_preview_cleanup_candidates_dossier006_v1()
returns jsonb language plpgsql stable security definer set search_path = pg_catalog
as $$
declare result jsonb;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(authorized_build_id),'[]'::jsonb) into result from (
    select authorized_build_id from lws_internal.website_project_preview_dispatches
    where state='FAILED' and finished_at < clock_timestamp()-interval '2 minutes'
      and (cleanup_checked_at is null or cleanup_checked_at < clock_timestamp()-interval '2 minutes')
      and lws_internal.is_preview_deadline_dossier006_v1(preview_lease_id)
    order by coalesce(cleanup_checked_at,finished_at),authorized_build_id limit 100
  ) pending;
  return result;
end $$;

create function public.get_website_project_preview_failed_storage_paths_dossier006_v1(p_build_id uuid)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog
as $$
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  if not exists(select 1 from lws_internal.website_project_preview_dispatches
    where authorized_build_id=p_build_id and lws_internal.is_preview_deadline_dossier006_v1(preview_lease_id)) then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_CLEANUP_AUTHORITY_INVALID';
  end if;
  return public.get_website_project_preview_failed_storage_paths_v1(p_build_id);
end $$;

create function public.record_website_project_preview_cleanup_checked_dossier006_v1(p_build_id uuid)
returns boolean language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  perform lws_internal.lock_preview_lifecycle_v1();
  update lws_internal.website_project_preview_dispatches set cleanup_checked_at=clock_timestamp()
    where authorized_build_id=p_build_id and state='FAILED'
      and lws_internal.is_preview_deadline_dossier006_v1(preview_lease_id);
  return found;
end $$;

revoke all on function public.expire_website_project_preview_dispatches_dossier006_v1(),
  public.get_website_project_preview_cleanup_candidates_dossier006_v1(),
  public.get_website_project_preview_failed_storage_paths_dossier006_v1(uuid),
  public.record_website_project_preview_cleanup_checked_dossier006_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.expire_website_project_preview_dispatches_dossier006_v1(),
  public.get_website_project_preview_cleanup_candidates_dossier006_v1(),
  public.get_website_project_preview_failed_storage_paths_dossier006_v1(uuid),
  public.record_website_project_preview_cleanup_checked_dossier006_v1(uuid) to service_role;

-- Executed locally by scripts/website-project-preview-repair-local.cjs all.
-- Requires three fresh, isolated OWNER preview leases in distinct workspaces.
-- psql variables: lease_id, build_id, actor_id, workflow_sha, unmanaged_lease_id, expiry_lease_id.
-- All leases belong to actor_id. No other pending expired dispatches. Never use production fixtures.
\set ON_ERROR_STOP on
begin;
select set_config('test.preview_lease', :'lease_id', true),
       set_config('test.preview_build', :'build_id', true),
       set_config('test.preview_actor', :'actor_id', true),
       set_config('test.preview_workflow', :'workflow_sha', true),
       set_config('test.preview_unmanaged_lease', :'unmanaged_lease_id', true),
       set_config('test.preview_expiry_lease', :'expiry_lease_id', true);
insert into lws_internal.website_project_preview_workflow_revisions(workflow_sha,enabled)
  values(:'workflow_sha',true) on conflict(workflow_sha) do update set enabled=true;
do $$
declare
  lease uuid:=current_setting('test.preview_lease')::uuid;
  build uuid:=current_setting('test.preview_build')::uuid;
  actor uuid:=current_setting('test.preview_actor')::uuid;
  revision text:=current_setting('test.preview_workflow');
  unmanaged uuid:=current_setting('test.preview_unmanaged_lease')::uuid;
  expiry_lease uuid:=current_setting('test.preview_expiry_lease')::uuid;
  original_expiry timestamptz;
  result jsonb;
begin
  if lease=unmanaged or lease=expiry_lease or unmanaged=expiry_lease
    or (select count(*) from lws_internal.website_project_preview_build_leases
      where preview_lease_id in (lease,unmanaged,expiry_lease) and actor_auth_user_id=actor
        and released_at is null and expires_at > clock_timestamp()) <> 3
    or exists(select 1 from lws_internal.website_project_preview_dispatches
      where preview_lease_id in (lease,unmanaged,expiry_lease)
        or (finished_at is null and expires_at <= clock_timestamp())) then
    raise exception 'FRESH_ISOLATED_FIXTURES_REQUIRED';
  end if;
  if has_table_privilege('authenticated','lws_internal.website_project_preview_dispatches','INSERT')
    or has_function_privilege('authenticated','public.claim_website_project_preview_run_v1(uuid,uuid,bigint,integer,text)','EXECUTE') then
    raise exception 'DISPATCH_ACL_TEST_FAILED';
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'aal','aal1')::text,true);
  begin
    perform public.claim_website_project_preview_dispatch_v1(lease,revision);
    raise exception 'AAL1_ACCEPTED';
  exception when insufficient_privilege then null;
  end;
  perform public.release_website_project_preview_build_v1(unmanaged);
  perform public.release_website_project_preview_build_v1(unmanaged);
  if not exists(select 1 from lws_internal.website_project_preview_build_leases l
    join lws_internal.website_project_files_write_leases s on s.lease_id=l.source_write_lease_id
    where l.preview_lease_id=unmanaged and l.released_at is not null and s.released_at is not null) then
    raise exception 'UNMANAGED_RELEASE_CHANGED';
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'aal','aal2')::text,true);
  result:=public.claim_website_project_preview_dispatch_v1(lease,revision);
  if result->>'dispatchAllowed' is distinct from 'true' or (result->>'buildId')::uuid is distinct from build then
    raise exception 'FIRST_DISPATCH_NOT_CLAIMED';
  end if;
  result:=public.claim_website_project_preview_dispatch_v1(lease,revision);
  if result->>'dispatchAllowed' is distinct from 'false' then raise exception 'DUPLICATE_DISPATCH_ACCEPTED'; end if;
  begin
    perform public.release_website_project_preview_build_v1(lease);
    raise exception 'MANAGED_RELEASE_ACCEPTED';
  exception when insufficient_privilege then
    if sqlerrm <> 'PROJECT_PREVIEW_MANAGED_RELEASE_FORBIDDEN' then raise; end if;
  end;
  if exists(select 1 from lws_internal.website_project_preview_build_leases l
    join lws_internal.website_project_files_write_leases s on s.lease_id=l.source_write_lease_id
    where l.preview_lease_id=lease and (l.released_at is not null or s.released_at is not null)) then
    raise exception 'MANAGED_RELEASE_MUTATED_LEASE';
  end if;
  begin
    perform public.finalize_website_project_preview_build_v2(lease,result->>'commitSha','FAILED','FAILED','[]'::jsonb);
    raise exception 'LEGACY_FINALIZER_ACCEPTED';
  exception when insufficient_privilege then
    if sqlerrm <> 'PROJECT_PREVIEW_MANAGED_FINALIZER_REQUIRED' then raise; end if;
  end;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  begin
    perform public.claim_website_project_preview_run_v1(lease,build,987654321,2,revision);
    raise exception 'RERUN_ACCEPTED';
  exception when insufficient_privilege then null;
  end;
  select expires_at into strict original_expiry from lws_internal.website_project_preview_build_leases
    where preview_lease_id=lease;
  update lws_internal.website_project_preview_build_leases
    set expires_at=clock_timestamp()-interval '1 second' where preview_lease_id=lease;
  begin
    perform public.claim_website_project_preview_run_v1(lease,build,987654321,1,revision);
    raise exception 'EXPIRED_RUN_AUTHORIZED';
  exception when insufficient_privilege then
    if sqlerrm <> 'PROJECT_PREVIEW_LEASE_INVALID' then raise; end if;
  end;
  if exists(select 1 from lws_internal.website_project_preview_dispatches
    where preview_lease_id=lease and (workflow_run_id is not null or source_claimed_at is not null)) then
    raise exception 'EXPIRED_RUN_MUTATED_AUTHORITY';
  end if;
  update lws_internal.website_project_preview_build_leases set expires_at=original_expiry where preview_lease_id=lease;
  perform public.claim_website_project_preview_run_v1(lease,build,987654321,1,revision);
  begin
    perform public.claim_website_project_preview_run_v1(lease,build,987654322,1,revision);
    raise exception 'SECOND_RUN_ACCEPTED';
  exception when insufficient_privilege then null;
  end;
  result:=public.finish_website_project_preview_failure_v1(lease,build,987654321,'BUILD_FAILED',revision);
  if result->>'state' is distinct from 'FAILED' then raise exception 'FAILURE_NOT_TERMINAL'; end if;
  result:=public.finish_website_project_preview_failure_v1(lease,build,987654321,'CANCELLED',revision);
  if result->>'reason' is distinct from 'BUILD_FAILED' then raise exception 'TERMINAL_REASON_OVERWRITTEN'; end if;
  if (select count(*) from lws_internal.website_project_preview_builds where lease_id=lease) <> 1 then
    raise exception 'TERMINAL_BUILD_CARDINALITY_INVALID';
  end if;
  if exists(select 1 from lws_internal.website_project_preview_build_leases l
    join lws_internal.website_project_files_write_leases s on s.lease_id=l.source_write_lease_id
    where l.preview_lease_id=lease and (l.released_at is null or s.released_at is null)) then
    raise exception 'LEASE_NOT_RELEASED';
  end if;
  result:=lws_internal.fail_preview_dispatch_v1(lease,'DEADLINE_EXCEEDED');
  if result->>'transitioned' is distinct from 'false' or result->>'reason' is distinct from 'BUILD_FAILED' then
    raise exception 'TERMINAL_REPLAY_COUNTED_AS_TRANSITION';
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'aal','aal2')::text,true);
  perform public.claim_website_project_preview_dispatch_v1(expiry_lease,revision);
  update lws_internal.website_project_preview_build_leases
    set expires_at=clock_timestamp()-interval '1 second' where preview_lease_id=expiry_lease;
  update lws_internal.website_project_preview_dispatches
    set expires_at=clock_timestamp()-interval '1 second' where preview_lease_id=expiry_lease;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  if public.expire_website_project_preview_dispatches_v1() <> 1 then
    raise exception 'NEW_EXPIRY_NOT_COUNTED_ONCE';
  end if;
  if public.expire_website_project_preview_dispatches_v1() <> 0 then
    raise exception 'TERMINAL_EXPIRY_COUNTED_TWICE';
  end if;
  if not exists(select 1 from lws_internal.website_project_preview_dispatches d
    join lws_internal.website_project_preview_build_leases l using(preview_lease_id)
    join lws_internal.website_project_files_write_leases s on s.lease_id=l.source_write_lease_id
    where d.preview_lease_id=expiry_lease and d.state='FAILED' and d.reason='DEADLINE_EXCEEDED'
      and d.finished_at is not null and l.released_at is not null and s.released_at is not null) then
    raise exception 'EXPIRY_NOT_TERMINAL';
  end if;
end $$;
rollback;

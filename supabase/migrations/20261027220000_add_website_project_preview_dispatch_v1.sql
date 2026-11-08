-- Local draft only. Deployment and scheduler activation require separate approval.
create table lws_internal.website_project_preview_workflow_revisions (
  workflow_sha text primary key check (workflow_sha ~ '^[0-9a-f]{40}$'),
  enabled boolean not null default false
);
alter table lws_internal.website_project_preview_workflow_revisions enable row level security;
alter table lws_internal.website_project_preview_workflow_revisions force row level security;
revoke all on lws_internal.website_project_preview_workflow_revisions from public,anon,authenticated,service_role;

create table lws_internal.website_project_preview_dispatches (
  preview_lease_id uuid primary key references lws_internal.website_project_preview_build_leases,
  authorized_build_id uuid not null,
  actor_auth_user_id uuid not null,
  workflow_sha text not null check (workflow_sha ~ '^[0-9a-f]{40}$'),
  state text not null check (state in
    ('ATTEMPTED','ACCEPTED','UNKNOWN','RUNNING','PASS','PASS_WITH_WARNINGS','FAILED')),
  reason text,
  workflow_run_id bigint unique check (workflow_run_id > 0),
  source_claimed_at timestamptz,
  attempted_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  finished_at timestamptz,
  cleanup_checked_at timestamptz,
  constraint preview_dispatch_build_unique unique (authorized_build_id)
);
alter table lws_internal.website_project_preview_dispatches enable row level security;
alter table lws_internal.website_project_preview_dispatches force row level security;
revoke all on lws_internal.website_project_preview_dispatches from public, anon, authenticated, service_role;

create function lws_internal.lock_preview_lifecycle_v1()
returns void language plpgsql security definer set search_path=pg_catalog as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('website-project-preview-lifecycle:v1',0));
end $$;
revoke all on function lws_internal.lock_preview_lifecycle_v1() from public,anon,authenticated,service_role;

create function lws_internal.lock_preview_leases_v1(p_lease_id uuid)
returns lws_internal.website_project_preview_build_leases
language plpgsql security definer set search_path=public,lws_internal,pg_catalog as $$
declare l lws_internal.website_project_preview_build_leases%rowtype;
begin
  perform lws_internal.lock_preview_lifecycle_v1();
  select * into l from lws_internal.website_project_preview_build_leases where preview_lease_id=p_lease_id;
  if not found then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_LEASE_INVALID';
  end if;
  perform 1 from lws_internal.website_project_files_write_leases where lease_id=l.source_write_lease_id for update;
  select * into strict l from lws_internal.website_project_preview_build_leases where preview_lease_id=p_lease_id for update;
  return l;
end $$;
revoke all on function lws_internal.lock_preview_leases_v1(uuid) from public,anon,authenticated,service_role;

-- Call only with both lease rows already locked; this check itself never waits.
create function lws_internal.assert_preview_lease_current_v1(p_lease_id uuid)
returns void language plpgsql security definer set search_path=public,lws_internal,pg_catalog as $$
declare l lws_internal.website_project_preview_build_leases%rowtype;
begin
  select * into l from lws_internal.website_project_preview_build_leases where preview_lease_id=p_lease_id;
  if not found or l.released_at is not null or l.expires_at <= clock_timestamp() then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_LEASE_INVALID';
  end if;
end $$;
revoke all on function lws_internal.assert_preview_lease_current_v1(uuid) from public,anon,authenticated,service_role;

alter function public.acquire_website_project_preview_build_v1(uuid,text,uuid) set schema lws_internal;
alter function lws_internal.acquire_website_project_preview_build_v1(uuid,text,uuid)
  rename to acquire_preview_pre_dispatch_v1;
revoke all on function lws_internal.acquire_preview_pre_dispatch_v1(uuid,text,uuid) from public,anon,authenticated,service_role;
create function public.acquire_website_project_preview_build_v1(
  p_quote_request_id uuid,p_expected_commit_sha text,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path=public,lws_internal,auth,pg_catalog as $$
declare a jsonb;
begin
  perform lws_internal.lock_preview_lifecycle_v1();
  a:=lws_internal.acquire_preview_pre_dispatch_v1(p_quote_request_id,p_expected_commit_sha,p_idempotency_key);
  perform lws_internal.assert_preview_lease_current_v1((a->>'leaseId')::uuid);
  return a;
end $$;
revoke all on function public.acquire_website_project_preview_build_v1(uuid,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.acquire_website_project_preview_build_v1(uuid,text,uuid) to authenticated;

alter function public.release_website_project_preview_build_v1(uuid) set schema lws_internal;
alter function lws_internal.release_website_project_preview_build_v1(uuid)
  rename to release_preview_pre_dispatch_v1;
revoke all on function lws_internal.release_preview_pre_dispatch_v1(uuid) from public,anon,authenticated,service_role;
create function public.release_website_project_preview_build_v1(p_lease_id uuid)
returns void language plpgsql security definer set search_path=public,lws_internal,auth,pg_catalog as $$
begin
  perform lws_internal.lock_preview_leases_v1(p_lease_id);
  if exists(select 1 from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id) then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_MANAGED_RELEASE_FORBIDDEN';
  end if;
  perform lws_internal.release_preview_pre_dispatch_v1(p_lease_id);
end $$;
revoke all on function public.release_website_project_preview_build_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.release_website_project_preview_build_v1(uuid) to authenticated;

create function lws_internal.assert_preview_dispatch_binding_v1(p_lease_id uuid)
returns jsonb language plpgsql security definer
set search_path = public, lws_internal, auth, pg_catalog as $$
declare
  l lws_internal.website_project_preview_build_leases%rowtype;
  s lws_internal.website_project_files_write_leases%rowtype;
  c public.website_work_contexts%rowtype;
  w public.website_execution_workspaces%rowtype;
  o public.website_repository_provisioning_operations%rowtype;
begin
  perform lws_internal.lock_preview_lifecycle_v1();
  select * into l from lws_internal.website_project_preview_build_leases where preview_lease_id=p_lease_id;
  if not found or l.released_at is not null or l.expires_at <= clock_timestamp() then
    raise exception using errcode='42501', message='PROJECT_PREVIEW_LEASE_INVALID';
  end if;
  select * into strict s from lws_internal.website_project_files_write_leases where lease_id=l.source_write_lease_id;
  perform 1 from public.commercial_operators where auth_user_id=l.actor_auth_user_id
    and operator_id=s.actor_operator_id and role='owner' and status='ACTIVE' and revoked_at is null for share;
  if not found then
    raise exception using errcode='42501', message='WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;
  select * into c from public.website_work_contexts where website_work_context_id=l.website_work_context_id
    and quote_request_id=l.quote_request_id for share;
  if not found then
    raise exception using errcode='42501', message='REPOSITORY_BINDING_STALE';
  end if;
  select * into w from public.website_execution_workspaces where website_workspace_id=l.website_workspace_id for share;
  if not found then
    raise exception using errcode='42501', message='REPOSITORY_BINDING_STALE';
  end if;
  select * into o from public.website_repository_provisioning_operations
    where operation_id=lws_internal.get_website_repository_canonical_durable_operation_id_v1(
      w.website_workspace_id,l.website_work_context_id) for share;
  if not found then
    raise exception using errcode='42501', message='REPOSITORY_BINDING_STALE';
  end if;
  l:=lws_internal.lock_preview_leases_v1(p_lease_id);
  select * into strict s from lws_internal.website_project_files_write_leases where lease_id=l.source_write_lease_id;
  perform lws_internal.assert_preview_lease_current_v1(p_lease_id);
  if w.workspace_state is distinct from 'REPOSITORY_READY'
    or c.project_id is distinct from w.project_id
    or w.repository_state is distinct from 'BOUND' or w.repository_visibility is distinct from 'private'
    or w.last_commit_sha is distinct from l.expected_commit_sha
    or row(w.binding_revision,w.repository_provider,w.repository_owner,w.repository_name,
      w.repository_external_id,w.repository_node_id,w.default_branch,w.website_work_context_id,w.quote_request_id)
      is distinct from row(s.binding_revision,s.repository_provider,s.repository_owner,s.repository_name,
      s.repository_external_id,s.repository_node_id,s.default_branch,l.website_work_context_id,l.quote_request_id)
    or s.expected_commit_sha is distinct from l.expected_commit_sha
    or s.actor_auth_user_id is distinct from l.actor_auth_user_id
    or s.write_path is distinct from 'index.html' or s.finalized_at is not null
    or s.repository_ref is distinct from 'heads/' || w.default_branch
    or w.repository_bound_at is null or w.repository_marker_commit_sha is null then
    raise exception using errcode='42501', message='REPOSITORY_BINDING_STALE';
  end if;
  if o.operation_id is distinct from s.marker_operation_id or o.state is distinct from 'BOUND'
    or row(o.repository_provider,o.repository_owner,o.repository_name,o.repository_external_id,o.repository_node_id)
      is distinct from row(s.repository_provider,s.repository_owner,s.repository_name,s.repository_external_id,s.repository_node_id) then
    raise exception using errcode='42501', message='REPOSITORY_BINDING_STALE';
  end if;
  return jsonb_build_object('leaseId',p_lease_id,'buildId',l.authorized_build_id,
    'repositoryOwner',s.repository_owner,'repositoryName',s.repository_name,
    'repositoryId',s.repository_external_id::text,'commitSha',l.expected_commit_sha,
    'actorId',l.actor_auth_user_id,'expiresAt',l.expires_at);
end $$;
revoke all on function lws_internal.assert_preview_dispatch_binding_v1(uuid) from public,anon,authenticated,service_role;

create function public.claim_website_project_preview_dispatch_v1(p_lease_id uuid,p_workflow_sha text)
returns jsonb language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare a jsonb; inserted_count integer; d lws_internal.website_project_preview_dispatches%rowtype;
begin
  if auth.uid() is null or coalesce(auth.jwt()->>'role','') <> 'authenticated' then
    raise exception using errcode='42501', message='HUMAN_JWT_REQUIRED';
  end if;
  perform lws_internal.assert_operator_aal2_v1();
  a := lws_internal.assert_preview_dispatch_binding_v1(p_lease_id);
  if (a->>'actorId')::uuid is distinct from auth.uid() then
    raise exception using errcode='42501', message='PROJECT_PREVIEW_LEASE_INVALID';
  end if;
  if p_workflow_sha is null or p_workflow_sha !~ '^[0-9a-f]{40}$' then
    raise exception using errcode='22023', message='PROJECT_PREVIEW_WORKFLOW_INVALID';
  end if;
  perform 1 from lws_internal.website_project_preview_workflow_revisions
    where workflow_sha=p_workflow_sha and enabled for share;
  if not found then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKFLOW_NOT_APPROVED';
  end if;
  perform lws_internal.assert_preview_lease_current_v1(p_lease_id);
  insert into lws_internal.website_project_preview_dispatches(
    preview_lease_id,authorized_build_id,actor_auth_user_id,workflow_sha,state,expires_at)
    values(p_lease_id,(a->>'buildId')::uuid,auth.uid(),p_workflow_sha,'ATTEMPTED',(a->>'expiresAt')::timestamptz)
    on conflict (preview_lease_id) do nothing;
  get diagnostics inserted_count = row_count;
  select * into strict d from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id;
  return a || jsonb_build_object('dispatchAllowed',inserted_count=1,'state',d.state,
    'workflowSha',d.workflow_sha,'reason',d.reason);
end $$;

create function lws_internal.fail_preview_dispatch_v1(p_lease_id uuid,p_reason text)
returns jsonb language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare d lws_internal.website_project_preview_dispatches%rowtype;
  l lws_internal.website_project_preview_build_leases%rowtype; b uuid;
begin
  l:=lws_internal.lock_preview_leases_v1(p_lease_id);
  select * into d from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id for update;
  if not found then raise exception using errcode='42501',message='PROJECT_PREVIEW_DISPATCH_INVALID'; end if;
  if d.finished_at is not null then return jsonb_build_object('transitioned',false,'state',d.state,'reason',d.reason); end if;
  if exists(select 1 from lws_internal.website_project_preview_builds where lease_id=p_lease_id) then
    raise exception using errcode='55000',message='PROJECT_PREVIEW_TERMINAL_CONFLICT';
  end if;
  insert into lws_internal.website_project_preview_builds(
    lease_id,actor_auth_user_id,quote_request_id,website_work_context_id,website_workspace_id,
    commit_sha,artifact_path,artifact_sha256,artifact_bytes,build_status)
    values(p_lease_id,l.actor_auth_user_id,l.quote_request_id,l.website_work_context_id,
      l.website_workspace_id,l.expected_commit_sha,'FAILED',repeat('0',64),0,'FAILED')
    returning preview_build_id into b;
  update lws_internal.website_project_preview_dispatches set state='FAILED',reason=p_reason,finished_at=clock_timestamp()
    where preview_lease_id=p_lease_id;
  update lws_internal.website_project_preview_build_leases set released_at=coalesce(released_at,clock_timestamp())
    where preview_lease_id=p_lease_id;
  update lws_internal.website_project_files_write_leases set released_at=coalesce(released_at,clock_timestamp())
    where lease_id=l.source_write_lease_id and finalized_at is null;
  update lws_internal.website_project_preview_upload_sessions set status='ABORTED',aborted_at=clock_timestamp()
    where preview_lease_id=p_lease_id and status='OPEN';
  return jsonb_build_object('transitioned',true,'state','FAILED','reason',p_reason,'previewBuildId',b);
end $$;
revoke all on function lws_internal.fail_preview_dispatch_v1(uuid,text) from public,anon,authenticated,service_role;

create function public.record_website_project_preview_dispatch_v1(p_lease_id uuid,p_outcome text)
returns jsonb language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare d lws_internal.website_project_preview_dispatches%rowtype;
begin
  if auth.uid() is null or coalesce(auth.jwt()->>'role','') <> 'authenticated' then
    raise exception using errcode='42501',message='HUMAN_JWT_REQUIRED';
  end if;
  perform lws_internal.assert_operator_aal2_v1();
  perform lws_internal.lock_preview_leases_v1(p_lease_id);
  select * into d from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id for update;
  if not found or d.actor_auth_user_id is distinct from auth.uid() then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_DISPATCH_INVALID';
  end if;
  if p_outcome is null or p_outcome not in ('ACCEPTED','UNKNOWN','REJECTED') then
    raise exception using errcode='22023',message='PROJECT_PREVIEW_DISPATCH_OUTCOME_INVALID';
  end if;
  if d.state <> 'ATTEMPTED' then return jsonb_build_object('state',d.state,'reason',d.reason); end if;
  if p_outcome='REJECTED' then return lws_internal.fail_preview_dispatch_v1(p_lease_id,'DISPATCH_REJECTED') - 'transitioned'; end if;
  update lws_internal.website_project_preview_dispatches set state=p_outcome,
    reason=case when p_outcome='UNKNOWN' then 'DISPATCH_UNKNOWN' else null end where preview_lease_id=p_lease_id;
  return jsonb_build_object('state',p_outcome);
end $$;

create function public.claim_website_project_preview_run_v1(
  p_lease_id uuid,p_build_id uuid,p_workflow_run_id bigint,p_run_attempt integer,p_workflow_sha text)
returns jsonb language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare a jsonb; d lws_internal.website_project_preview_dispatches%rowtype;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  if p_run_attempt is distinct from 1 or p_workflow_run_id is null or p_workflow_run_id <= 0 then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_RUN_INVALID';
  end if;
  a:=lws_internal.assert_preview_dispatch_binding_v1(p_lease_id);
  select * into d from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id for update;
  if not found or d.authorized_build_id is distinct from p_build_id or d.workflow_sha is distinct from p_workflow_sha
    or d.finished_at is not null or d.source_claimed_at is not null
    or d.workflow_run_id is not null then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_RUN_ALREADY_CLAIMED';
  end if;
  perform lws_internal.assert_preview_lease_current_v1(p_lease_id);
  update lws_internal.website_project_preview_dispatches set workflow_run_id=p_workflow_run_id,
    source_claimed_at=clock_timestamp(),state='RUNNING',reason=null where preview_lease_id=p_lease_id;
  return a || jsonb_build_object('runId',p_workflow_run_id::text,'workflowSha',d.workflow_sha);
end $$;

create function public.assert_website_project_preview_run_v1(p_lease_id uuid,p_build_id uuid,p_workflow_run_id bigint)
returns jsonb language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare a jsonb; d lws_internal.website_project_preview_dispatches%rowtype;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  a:=lws_internal.assert_preview_dispatch_binding_v1(p_lease_id);
  select * into d from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id;
  if not found or d.authorized_build_id is distinct from p_build_id or d.workflow_run_id is distinct from p_workflow_run_id
    or d.source_claimed_at is null or d.state <> 'RUNNING' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_RUN_INVALID';
  end if;
  return a || jsonb_build_object('runId',p_workflow_run_id::text,'workflowSha',d.workflow_sha);
end $$;

create function public.finish_website_project_preview_failure_v1(
  p_lease_id uuid,p_build_id uuid,p_workflow_run_id bigint,p_reason text,p_workflow_sha text)
returns jsonb language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare d lws_internal.website_project_preview_dispatches%rowtype;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  if p_reason is null or p_reason not in ('FETCH_FAILED','BUILD_FAILED','UPLOAD_FAILED',
    'WORKFLOW_FAILED','CANCELLED','TIMED_OUT','FINALIZATION_MISSING') then
    raise exception using errcode='22023',message='PROJECT_PREVIEW_FAILURE_INVALID';
  end if;
  perform lws_internal.lock_preview_leases_v1(p_lease_id);
  select * into d from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id for update;
  if not found or d.authorized_build_id is distinct from p_build_id or d.workflow_sha is distinct from p_workflow_sha
    or p_workflow_run_id is null or p_workflow_run_id <= 0
    or (d.workflow_run_id is not null and d.workflow_run_id <> p_workflow_run_id) then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_RUN_INVALID';
  end if;
  if d.workflow_run_id is null then
    update lws_internal.website_project_preview_dispatches set workflow_run_id=p_workflow_run_id where preview_lease_id=p_lease_id;
  end if;
  return lws_internal.fail_preview_dispatch_v1(p_lease_id,p_reason) - 'transitioned';
end $$;

create function public.expire_website_project_preview_dispatches_v1()
returns integer language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare item record; expired_count integer:=0; outcome jsonb;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  perform lws_internal.lock_preview_lifecycle_v1();
  for item in select preview_lease_id from lws_internal.website_project_preview_dispatches
    where finished_at is null and expires_at <= clock_timestamp() order by expires_at limit 100
  loop
    outcome:=lws_internal.fail_preview_dispatch_v1(item.preview_lease_id,'DEADLINE_EXCEEDED');
    if outcome->>'transitioned' = 'true' and outcome->>'reason' = 'DEADLINE_EXCEEDED' then
      expired_count:=expired_count+1;
    end if;
  end loop;
  return expired_count;
end $$;

alter function public.resolve_website_project_preview_artifact_authority_v1(uuid,uuid,bigint) set schema lws_internal;
alter function lws_internal.resolve_website_project_preview_artifact_authority_v1(uuid,uuid,bigint)
  rename to resolve_preview_pre_dispatch_v1;
revoke all on function lws_internal.resolve_preview_pre_dispatch_v1(uuid,uuid,bigint) from public,anon,authenticated,service_role;
create function public.resolve_website_project_preview_artifact_authority_v1(p_lease_id uuid,p_build_id uuid,p_workflow_run_id bigint)
returns jsonb language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare a jsonb; d lws_internal.website_project_preview_dispatches%rowtype;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  a:=lws_internal.resolve_preview_pre_dispatch_v1(p_lease_id,p_build_id,p_workflow_run_id);
  perform lws_internal.assert_preview_dispatch_binding_v1(p_lease_id);
  select * into d from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id;
  if not found or d.authorized_build_id is distinct from p_build_id or d.finished_at is not null
    or (d.workflow_run_id is not null and d.workflow_run_id is distinct from p_workflow_run_id) then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_RUN_INVALID';
  end if;
  return a || jsonb_build_object('workflowSha',d.workflow_sha);
end $$;

alter function public.finalize_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint) set schema lws_internal;
alter function lws_internal.finalize_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint)
  rename to finalize_preview_upload_pre_dispatch_v1;
revoke all on function lws_internal.finalize_preview_upload_pre_dispatch_v1(text,uuid,uuid,bigint,text,bigint)
  from public,anon,authenticated,service_role;
create function public.finalize_website_project_preview_upload_session_v1(
  p_session_token_hash text,p_lease_id uuid,p_build_id uuid,p_repository_external_id bigint,p_commit_sha text,p_workflow_run_id bigint)
returns jsonb language plpgsql security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare a jsonb; result jsonb;
begin
  a:=public.assert_website_project_preview_run_v1(p_lease_id,p_build_id,p_workflow_run_id);
  if a->>'commitSha' is distinct from p_commit_sha or (a->>'repositoryId')::bigint is distinct from p_repository_external_id then
    raise exception using errcode='42501',message='REPOSITORY_BINDING_STALE';
  end if;
  result:=lws_internal.finalize_preview_upload_pre_dispatch_v1(
    p_session_token_hash,p_lease_id,p_build_id,p_repository_external_id,p_commit_sha,p_workflow_run_id);
  update lws_internal.website_project_preview_dispatches set state=result->>'buildStatus',reason=null,finished_at=clock_timestamp()
    where preview_lease_id=p_lease_id;
  update lws_internal.website_project_files_write_leases set released_at=coalesce(released_at,clock_timestamp())
    where lease_id=(select source_write_lease_id from lws_internal.website_project_preview_build_leases where preview_lease_id=p_lease_id)
      and finalized_at is null;
  return result;
end $$;

alter function public.get_website_project_preview_build_status_v1(uuid) set schema lws_internal;
alter function lws_internal.get_website_project_preview_build_status_v1(uuid) rename to get_preview_status_pre_dispatch_v1;
revoke all on function lws_internal.get_preview_status_pre_dispatch_v1(uuid) from public,anon,authenticated,service_role;
create function public.get_website_project_preview_build_status_v1(p_lease_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare result jsonb; d lws_internal.website_project_preview_dispatches%rowtype;
begin
  result:=lws_internal.get_preview_status_pre_dispatch_v1(p_lease_id);
  select * into d from lws_internal.website_project_preview_dispatches
    where preview_lease_id=p_lease_id and actor_auth_user_id=auth.uid();
  if not found then return result; end if;
  if d.finished_at is not null then return result || jsonb_build_object('reason',d.reason); end if;
  if d.expires_at <= clock_timestamp() then
    return result || jsonb_build_object('buildStatus','FAILED','reason','DEADLINE_EXCEEDED');
  end if;
  return result || jsonb_build_object('buildStatus',
    case d.state when 'ACCEPTED' then 'BUILD_QUEUED' when 'RUNNING' then 'BUILD_IN_PROGRESS'
      else 'DISPATCH_UNKNOWN' end,'reason',d.reason);
end $$;
revoke all on function public.get_website_project_preview_build_status_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_website_project_preview_build_status_v1(uuid) to authenticated;

create function lws_internal.assert_preview_legacy_finalizer_v1(p_lease_id uuid)
returns void language plpgsql security definer set search_path=public,lws_internal,pg_catalog as $$
begin
  perform lws_internal.lock_preview_leases_v1(p_lease_id);
  if exists(select 1 from lws_internal.website_project_preview_dispatches where preview_lease_id=p_lease_id) then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_MANAGED_FINALIZER_REQUIRED';
  end if;
end $$;
revoke all on function lws_internal.assert_preview_legacy_finalizer_v1(uuid) from public,anon,authenticated,service_role;

alter function public.finalize_website_project_preview_build_v1(uuid,text,text,text,bigint,text) set schema lws_internal;
alter function lws_internal.finalize_website_project_preview_build_v1(uuid,text,text,text,bigint,text)
  rename to finalize_preview_legacy_single_v1;
revoke all on function lws_internal.finalize_preview_legacy_single_v1(uuid,text,text,text,bigint,text)
  from public,anon,authenticated,service_role;
create function public.finalize_website_project_preview_build_v1(
  p_lease_id uuid,p_expected_commit_sha text,p_artifact_path text,p_artifact_sha256 text,p_artifact_bytes bigint,p_build_status text)
returns void language plpgsql security definer set search_path=public,lws_internal,auth,pg_catalog as $$
begin
  perform lws_internal.assert_preview_legacy_finalizer_v1(p_lease_id);
  perform lws_internal.finalize_preview_legacy_single_v1(
    p_lease_id,p_expected_commit_sha,p_artifact_path,p_artifact_sha256,p_artifact_bytes,p_build_status);
end $$;
revoke all on function public.finalize_website_project_preview_build_v1(uuid,text,text,text,bigint,text)
  from public,anon,authenticated,service_role;
grant execute on function public.finalize_website_project_preview_build_v1(uuid,text,text,text,bigint,text) to authenticated;

alter function public.finalize_website_project_preview_build_v2(uuid,text,text,text,jsonb) set schema lws_internal;
alter function lws_internal.finalize_website_project_preview_build_v2(uuid,text,text,text,jsonb)
  rename to finalize_preview_legacy_multi_v2;
revoke all on function lws_internal.finalize_preview_legacy_multi_v2(uuid,text,text,text,jsonb)
  from public,anon,authenticated,service_role;
create function public.finalize_website_project_preview_build_v2(
  p_lease_id uuid,p_expected_commit_sha text,p_build_status text,p_primary_relative_path text,p_manifest jsonb)
returns jsonb language plpgsql security definer set search_path=public,lws_internal,auth,pg_catalog as $$
begin
  perform lws_internal.assert_preview_legacy_finalizer_v1(p_lease_id);
  return lws_internal.finalize_preview_legacy_multi_v2(
    p_lease_id,p_expected_commit_sha,p_build_status,p_primary_relative_path,p_manifest);
end $$;
revoke all on function public.finalize_website_project_preview_build_v2(uuid,text,text,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.finalize_website_project_preview_build_v2(uuid,text,text,text,jsonb) to authenticated;

create function public.get_website_project_preview_dispatch_completion_v1(p_lease_id uuid,p_build_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,lws_internal,auth,pg_catalog as $$
declare result jsonb;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  select jsonb_build_object('leaseId',d.preview_lease_id,'buildId',d.authorized_build_id,
    'workflowSha',d.workflow_sha,'runId',d.workflow_run_id::text,'state',d.state,
    'repositoryId',s.repository_external_id::text,'repository',s.repository_owner || '/' || s.repository_name,
    'commitSha',l.expected_commit_sha) into result
    from lws_internal.website_project_preview_dispatches d
    join lws_internal.website_project_preview_build_leases l on l.preview_lease_id=d.preview_lease_id
    join lws_internal.website_project_files_write_leases s on s.lease_id=l.source_write_lease_id
    where d.preview_lease_id=p_lease_id and d.authorized_build_id=p_build_id;
  if result is null then raise exception using errcode='42501',message='PROJECT_PREVIEW_DISPATCH_INVALID'; end if;
  return result;
end $$;

create function public.get_website_project_preview_failed_storage_paths_v1(p_build_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,lws_internal,auth,pg_catalog as $$
declare result jsonb;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(distinct d.authorized_build_id::text || '/' || f.relative_path),'[]'::jsonb) into result
    from lws_internal.website_project_preview_dispatches d
    join lws_internal.website_project_preview_upload_sessions s on s.preview_lease_id=d.preview_lease_id
    join lws_internal.website_project_preview_upload_files f on f.session_token_hash=s.session_token_hash
    where d.authorized_build_id=p_build_id and d.state='FAILED';
  return result;
end $$;
revoke all on function public.get_website_project_preview_dispatch_completion_v1(uuid,uuid),
  public.get_website_project_preview_failed_storage_paths_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_website_project_preview_dispatch_completion_v1(uuid,uuid),
  public.get_website_project_preview_failed_storage_paths_v1(uuid) to service_role;

create function public.get_website_project_preview_cleanup_candidates_v1()
returns jsonb language plpgsql stable security definer set search_path=public,lws_internal,auth,pg_catalog as $$
declare result jsonb;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(authorized_build_id),'[]'::jsonb) into result from (
    select authorized_build_id from lws_internal.website_project_preview_dispatches
    where state='FAILED' and finished_at < clock_timestamp()-interval '2 minutes'
      and (cleanup_checked_at is null or cleanup_checked_at < clock_timestamp()-interval '2 minutes')
    order by coalesce(cleanup_checked_at,finished_at),authorized_build_id limit 100
  ) pending;
  return result;
end $$;
create function public.record_website_project_preview_cleanup_checked_v1(p_build_id uuid)
returns boolean language plpgsql security definer set search_path=public,lws_internal,auth,pg_catalog as $$
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='PROJECT_PREVIEW_WORKER_FORBIDDEN';
  end if;
  perform lws_internal.lock_preview_lifecycle_v1();
  update lws_internal.website_project_preview_dispatches set cleanup_checked_at=clock_timestamp()
    where authorized_build_id=p_build_id and state='FAILED';
  return found;
end $$;
revoke all on function public.get_website_project_preview_cleanup_candidates_v1(),
  public.record_website_project_preview_cleanup_checked_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_website_project_preview_cleanup_candidates_v1(),
  public.record_website_project_preview_cleanup_checked_v1(uuid) to service_role;

revoke all on function public.claim_website_project_preview_dispatch_v1(uuid,text),
  public.record_website_project_preview_dispatch_v1(uuid,text),
  public.claim_website_project_preview_run_v1(uuid,uuid,bigint,integer,text),
  public.assert_website_project_preview_run_v1(uuid,uuid,bigint),
  public.finish_website_project_preview_failure_v1(uuid,uuid,bigint,text,text),
  public.expire_website_project_preview_dispatches_v1(),
  public.resolve_website_project_preview_artifact_authority_v1(uuid,uuid,bigint),
  public.finalize_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint)
  from public,anon,authenticated,service_role;
grant execute on function public.claim_website_project_preview_dispatch_v1(uuid,text),
  public.record_website_project_preview_dispatch_v1(uuid,text) to authenticated;
grant execute on function public.claim_website_project_preview_run_v1(uuid,uuid,bigint,integer,text),
  public.assert_website_project_preview_run_v1(uuid,uuid,bigint),
  public.finish_website_project_preview_failure_v1(uuid,uuid,bigint,text,text),
  public.expire_website_project_preview_dispatches_v1(),
  public.resolve_website_project_preview_artifact_authority_v1(uuid,uuid,bigint),
  public.finalize_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint) to service_role;

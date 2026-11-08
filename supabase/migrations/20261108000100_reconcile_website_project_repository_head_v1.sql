-- No customer data is changed by installation. Only the server-verified 006 path is enabled.
create table lws_internal.website_project_head_reconciliations (
  read_lease_id uuid primary key references lws_internal.website_project_files_read_leases,
  previous_commit_sha text,
  verified_commit_sha text not null check (verified_commit_sha ~ '^[0-9a-f]{40}$'),
  reconciled_at timestamptz not null default clock_timestamp()
);
alter table lws_internal.website_project_head_reconciliations enable row level security;
alter table lws_internal.website_project_head_reconciliations force row level security;
revoke all on lws_internal.website_project_head_reconciliations from public,anon,authenticated,service_role;

create function public.reconcile_website_project_repository_head_v1(
  p_lease_id uuid, p_expected_commit_sha text, p_verified_commit_sha text
) returns jsonb language plpgsql volatile security definer
set search_path = public,lws_internal,auth,pg_catalog as $$
declare
  h lws_internal.website_project_files_read_leases%rowtype;
  l lws_internal.website_project_files_read_leases%rowtype;
  o public.commercial_operators%rowtype;
  c public.website_work_contexts%rowtype;
  w public.website_execution_workspaces%rowtype;
  p public.website_repository_provisioning_operations%rowtype;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'PROJECT_HEAD_RECONCILIATION_FORBIDDEN' using errcode='42501';
  end if;
  if p_verified_commit_sha is null or p_verified_commit_sha !~ '^[0-9a-f]{40}$'
     or p_expected_commit_sha is null or p_expected_commit_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'PROJECT_HEAD_COMMIT_INVALID';
  end if;
  perform lws_internal.lock_preview_lifecycle_v1();
  select * into h from lws_internal.website_project_files_read_leases where lease_id=p_lease_id;
  if not found or h.quote_request_id <> '7458c346-dfc9-40f3-ad0e-cb94a16636bf'
    or h.website_work_context_id <> 'a88b1e87-9271-4ad1-99cc-b385b7982a8b'
    or h.website_workspace_id <> 'fa057e1f-d03d-47cf-a595-317447734298'
    or h.marker_operation_id <> '33202312-6e10-4d3a-bba9-c05868105331'
    or h.repository_external_id <> 1378797607
    or h.repository_node_id <> 'R_kgDOUi7IJw'
    or h.repository_owner <> 'lorenzo-web-solutions'
    or h.repository_name <> 'lws-web-a88b1e8792714ad199ccb385b7982a8b' then
    raise exception 'PROJECT_HEAD_RECONCILIATION_NOT_ENABLED';
  end if;
  -- The read authority was acquired by OWNER+AAL2. Recheck its actor under the
  -- same operator -> context -> workspace -> operation -> lease lock order.
  select * into o from public.commercial_operators where auth_user_id=h.actor_auth_user_id for update;
  if not found or o.operator_id is distinct from h.actor_operator_id
    or o.status <> 'ACTIVE' or o.role <> 'owner' or o.revoked_at is not null then
    raise exception 'WEBSITE_REPOSITORY_OWNER_REQUIRED' using errcode='42501';
  end if;
  select * into c from public.website_work_contexts
    where website_work_context_id=h.website_work_context_id and quote_request_id=h.quote_request_id for update;
  if not found then raise exception 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH'; end if;
  select * into w from public.website_execution_workspaces
    where website_workspace_id=h.website_workspace_id and website_work_context_id=c.website_work_context_id
      and quote_request_id=h.quote_request_id and project_id is not distinct from c.project_id for update;
  if not found then raise exception 'WEBSITE_WORKSPACE_NOT_FOUND'; end if;
  select * into p from public.website_repository_provisioning_operations
    where operation_id=lws_internal.get_website_repository_canonical_durable_operation_id_v1(
      w.website_workspace_id,c.website_work_context_id) for update;
  if not found or p.state is distinct from 'BOUND' or p.operation_id is distinct from h.marker_operation_id
    or row(p.repository_provider,p.repository_owner,p.repository_name,p.repository_external_id,p.repository_node_id)
       is distinct from row(w.repository_provider,w.repository_owner,w.repository_name,w.repository_external_id,w.repository_node_id)
    then raise exception 'REPOSITORY_BINDING_STALE'; end if;
  select * into l from lws_internal.website_project_files_read_leases where lease_id=p_lease_id for update;
  if not found or l is distinct from h or l.released_at is not null or l.expires_at <= clock_timestamp() then
    raise exception 'PROJECT_FILES_LEASE_EXPIRED';
  end if;
  if w.workspace_state is distinct from 'REPOSITORY_READY'
    or w.repository_state is distinct from 'BOUND' or w.repository_visibility is distinct from 'private'
    or w.repository_bound_at is null or w.repository_marker_commit_sha is null
    or row(w.binding_revision,w.repository_provider,w.repository_owner,w.repository_name,
           w.repository_external_id,w.repository_node_id,w.default_branch)
       is distinct from row(l.binding_revision,l.repository_provider,l.repository_owner,l.repository_name,
           l.repository_external_id,l.repository_node_id,l.default_branch)
    or l.repository_ref is distinct from 'heads/' || w.default_branch
    or l.ref_label is distinct from w.default_branch then
    raise exception 'REPOSITORY_BINDING_STALE';
  end if;
  if w.last_commit_sha is distinct from p_expected_commit_sha then raise exception 'PROJECT_FILES_STALE_REVISION'; end if;
  if exists(select 1 from lws_internal.website_project_files_write_leases
      where website_workspace_id=w.website_workspace_id and released_at is null
        and finalized_at is null and expires_at > clock_timestamp())
    or exists(select 1 from lws_internal.website_project_preview_build_leases
      where website_workspace_id=w.website_workspace_id and released_at is null and expires_at > clock_timestamp())
    or exists(select 1 from lws_internal.website_project_preview_dispatches d
      join lws_internal.website_project_preview_build_leases b on b.preview_lease_id=d.preview_lease_id
      where b.website_workspace_id=w.website_workspace_id and d.finished_at is null) then
    raise exception 'PROJECT_HEAD_RECONCILIATION_BUSY';
  end if;
  insert into lws_internal.website_project_head_reconciliations(read_lease_id,previous_commit_sha,verified_commit_sha)
    values(l.lease_id,w.last_commit_sha,p_verified_commit_sha);
  update public.website_execution_workspaces set last_commit_sha=p_verified_commit_sha
    where website_workspace_id=w.website_workspace_id;
  update lws_internal.website_project_files_read_leases set released_at=clock_timestamp() where lease_id=l.lease_id;
  return jsonb_build_object('commitSha',p_verified_commit_sha);
end;
$$;
revoke all on function public.reconcile_website_project_repository_head_v1(uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.reconcile_website_project_repository_head_v1(uuid,text,text) to service_role;

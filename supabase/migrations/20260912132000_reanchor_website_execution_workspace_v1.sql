do $$
begin
  if exists (
    select 1
    from public.website_work_contexts as context
    join public.commercial_projects as project
      on project.project_id = context.project_id
    where context.phase <> 'OFFICIAL_PROJECT'
       or context.quote_request_id is distinct from
          lws_internal.resolve_website_project_quote_request_v1(project.project_id)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  if exists (
    select 1
    from public.commercial_projects as project
    join public.quote_request_quotation_acceptances as acceptance
      on acceptance.id = project.acceptance_id
     and acceptance.issuance_id = project.quotation_issuance_id
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = project.quotation_issuance_id
     and issuance.status = 'ISSUED'
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    join public.quote_requests as request
      on request.id = approval.quote_request_id
     and request.record_classification = 'production'
     and request.request_kind = 'website'
    join public.website_work_contexts as context
      on context.quote_request_id = request.id
    where context.project_id is distinct from project.project_id
       or context.phase <> 'OFFICIAL_PROJECT'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  if exists (
    select 1
    from public.website_execution_workspaces as workspace
    where workspace.quote_request_id is distinct from
          lws_internal.resolve_website_project_quote_request_v1(workspace.project_id)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORKSPACE_BINDING_MISMATCH';
  end if;
end;
$$;

select set_config('lws.website_concept_command', 'on', true);

insert into public.website_work_contexts(
  quote_request_id,
  concept_id,
  project_id,
  phase,
  revision
)
select
  approval.quote_request_id,
  null,
  project.project_id,
  'OFFICIAL_PROJECT',
  1
from public.commercial_projects as project
join public.quote_request_quotation_acceptances as acceptance
  on acceptance.id = project.acceptance_id
 and acceptance.issuance_id = project.quotation_issuance_id
join public.quote_request_quotation_issuances as issuance
  on issuance.id = project.quotation_issuance_id
 and issuance.status = 'ISSUED'
join public.quote_request_quotation_approvals as approval
  on approval.id = issuance.approval_id
join public.quote_requests as request
  on request.id = approval.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'website'
left join public.website_work_contexts as context
  on context.quote_request_id = approval.quote_request_id
where context.website_work_context_id is null
order by project.project_id;

set constraints all immediate;
set constraints all deferred;
select set_config('lws.website_concept_command', '', true);

alter table public.website_execution_workspaces
  add column website_work_context_id uuid;

update public.website_execution_workspaces as workspace
set website_work_context_id = context.website_work_context_id
from public.website_work_contexts as context
where context.project_id = workspace.project_id
  and context.quote_request_id = workspace.quote_request_id
  and context.phase = 'OFFICIAL_PROJECT';

do $$
begin
  if exists (
    select 1
    from public.website_execution_workspaces
    where website_work_context_id is null
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORKSPACE_BINDING_MISMATCH';
  end if;
end;
$$;

alter table public.website_execution_workspaces
  alter column project_id drop not null,
  alter column website_work_context_id set not null,
  add constraint website_execution_workspace_context_unique
    unique (website_work_context_id),
  add constraint website_execution_workspace_context_fk
    foreign key (website_work_context_id)
    references public.website_work_contexts(website_work_context_id);

create function lws_internal.guard_website_execution_workspace_context_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_context public.website_work_contexts%rowtype;
  v_previous_command_setting text;
begin
  if tg_op = 'UPDATE'
     and new.website_work_context_id is distinct from old.website_work_context_id then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORKSPACE_BINDING_MISMATCH';
  end if;

  if tg_op = 'INSERT' and new.website_work_context_id is null then
    if new.project_id is null
       or lws_internal.resolve_website_project_quote_request_v1(new.project_id)
          is distinct from new.quote_request_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORKSPACE_BINDING_MISMATCH';
    end if;

    select *
    into v_context
    from public.website_work_contexts as context
    where context.project_id = new.project_id
      and context.quote_request_id = new.quote_request_id
      and context.phase = 'OFFICIAL_PROJECT';

    if not found then
      v_previous_command_setting :=
        current_setting('lws.website_concept_command', true);
      perform set_config('lws.website_concept_command', 'on', true);
      insert into public.website_work_contexts(
        quote_request_id, concept_id, project_id, phase, revision
      ) values (
        new.quote_request_id, null, new.project_id, 'OFFICIAL_PROJECT', 1
      )
      returning * into v_context;
      perform set_config(
        'lws.website_concept_command',
        coalesce(v_previous_command_setting, ''),
        true
      );
    end if;

    new.website_work_context_id := v_context.website_work_context_id;
  end if;

  select *
  into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = new.website_work_context_id;

  if not found
     or v_context.quote_request_id is distinct from new.quote_request_id
     or v_context.project_id is distinct from new.project_id
     or (v_context.phase = 'PRE_PROJECT' and new.project_id is not null)
     or (v_context.phase = 'OFFICIAL_PROJECT' and new.project_id is null) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORKSPACE_BINDING_MISMATCH';
  end if;

  return new;
end;
$$;

create trigger trg_website_execution_workspace_context_guard
before insert or update on public.website_execution_workspaces
for each row execute function
  lws_internal.guard_website_execution_workspace_context_v1();

create function public.get_website_execution_workspace_v2(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_work jsonb;
  v_context public.website_work_contexts%rowtype;
  v_legacy jsonb;
  v_workspace jsonb;
begin
  if p_quote_request_id is null then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_WORKSPACE_LOCATOR_REQUIRED';
  end if;

  v_work := public.get_operator_website_work_v1(p_quote_request_id);

  if v_work->>'state' not in ('PRE_PROJECT', 'OFFICIAL_PROJECT')
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
     or nullif(v_work->>'website_work_context_id', '') is null then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  select *
  into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id =
        (v_work->>'website_work_context_id')::uuid
    and context.quote_request_id = p_quote_request_id;

  if not found
     or v_context.phase is distinct from v_work->>'mode'
     or v_context.concept_id is distinct from
        nullif(v_work->>'concept_id', '')::uuid
     or v_context.project_id is distinct from
        nullif(v_work->>'project_id', '')::uuid then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  if v_context.phase = 'PRE_PROJECT' then
    select jsonb_build_object(
      'website_workspace_id', workspace.website_workspace_id,
      'website_work_context_id', workspace.website_work_context_id,
      'project_id', workspace.project_id,
      'quote_request_id', workspace.quote_request_id,
      'repository_provider', workspace.repository_provider,
      'repository_owner', workspace.repository_owner,
      'repository_name', workspace.repository_name,
      'default_branch', workspace.default_branch,
      'preview_branch', workspace.preview_branch,
      'preview_url', workspace.preview_url,
      'last_commit_sha', workspace.last_commit_sha,
      'last_commit_at', workspace.last_commit_at,
      'last_build_result', workspace.last_build_result,
      'last_build_at', workspace.last_build_at,
      'binding_revision', workspace.binding_revision,
      'created_at', workspace.created_at,
      'updated_at', workspace.updated_at
    )
    into v_workspace
    from public.website_execution_workspaces as workspace
    where workspace.website_work_context_id = v_context.website_work_context_id;

    return jsonb_build_object(
      'contract_version', 2,
      'mode', 'PRE_PROJECT',
      'quote_request_id', p_quote_request_id,
      'concept_id', v_context.concept_id,
      'project_id', null,
      'website_work_context_id', v_context.website_work_context_id,
      'context_revision', v_context.revision,
      'briefing_status', v_work->>'briefing_status',
      'commercially_released', false,
      'project', null,
      'start_gate', null,
      'workspace', v_workspace,
      'requirements', jsonb_build_object(
        'state', 'NOT_AVAILABLE',
        'message', 'Requirements volgen na intake-sync.'
      )
    );
  end if;

  v_legacy := public.get_website_execution_workspace_v1(
    p_quote_request_id,
    v_context.project_id
  );
  v_workspace := case
    when v_legacy->'workspace' = 'null'::jsonb then null
    else (v_legacy->'workspace') || jsonb_build_object(
      'website_work_context_id', v_context.website_work_context_id
    )
  end;

  return v_legacy || jsonb_build_object(
    'contract_version', 2,
    'mode', 'OFFICIAL_PROJECT',
    'quote_request_id', p_quote_request_id,
    'concept_id', v_context.concept_id,
    'project_id', v_context.project_id,
    'website_work_context_id', v_context.website_work_context_id,
    'context_revision', v_context.revision,
    'briefing_status', v_work->>'briefing_status',
    'commercially_released', (v_work->>'commercially_released')::boolean,
    'workspace', v_workspace,
    'requirements', jsonb_build_object(
      'state', 'PROJECT_BOUND',
      'message', null
    )
  );
end;
$$;

revoke all on function
  lws_internal.guard_website_execution_workspace_context_v1(),
  public.get_website_execution_workspace_v2(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_website_execution_workspace_v2(uuid)
to authenticated;

comment on column public.website_execution_workspaces.website_work_context_id is
  'Stable Website work-context authority; legacy project and request locators are checked projections.';
comment on function public.get_website_execution_workspace_v2(uuid) is
  'Context-bound Website Execution projection for PRE_PROJECT and OFFICIAL_PROJECT work.';

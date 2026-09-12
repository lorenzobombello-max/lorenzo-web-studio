begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(12);

select has_table(
  'public',
  'website_execution_workspaces',
  'Website Workspace technical reference table exists'
);
select has_function(
  'public',
  'get_website_execution_workspace_v1',
  array['uuid', 'uuid'],
  'Website Workspace read projection exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_website_execution_workspace_v1(uuid,uuid)',
    'execute'
  ),
  'authenticated humans can enter the guarded read projection'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_website_execution_workspace_v1(uuid,uuid)',
    'execute'
  ),
  'anonymous callers cannot inspect Website Workspace metadata'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.get_website_execution_workspace_v1(uuid,uuid)',
    'execute'
  ),
  'service role cannot bypass the human projection boundary'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.website_execution_workspaces'::regclass),
  'Website Workspace metadata has RLS enabled'
);
select ok(
  (select relforcerowsecurity from pg_class where oid = 'public.website_execution_workspaces'::regclass),
  'Website Workspace metadata forces RLS'
);
select ok(
  not has_table_privilege('authenticated', 'public.website_execution_workspaces', 'select'),
  'authenticated callers cannot read the metadata table directly'
);
select hasnt_column(
  'public',
  'website_execution_workspaces',
  'production_url',
  'technical metadata does not duplicate production URL authority'
);
select matches(
  pg_get_functiondef('public.get_website_execution_workspace_v1(uuid,uuid)'::regprocedure),
  'get_operator_project_start_gate_v1',
  'projection reuses the existing project authorization and dossier gate'
);
select matches(
  pg_get_functiondef('public.get_website_execution_workspace_v1(uuid,uuid)'::regprocedure),
  'get_commercial_project_view_v2',
  'projection reuses the existing project site authority'
);
select matches(
  pg_get_functiondef('public.get_website_execution_workspace_v1(uuid,uuid)'::regprocedure),
  'PROJECT_WORK_STARTED',
  'projection requires the immutable project-start fact'
);

select * from finish();
rollback;
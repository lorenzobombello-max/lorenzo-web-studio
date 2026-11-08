-- The isolated runner supplies the existing preview-reopen fixture transaction.
select ok(
  has_function_privilege('authenticated', 'public.get_website_execution_workspace_v7(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_website_execution_workspace_v7(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.get_website_execution_workspace_v7(uuid)', 'execute'),
  'projection retains authenticated-only execution'
);
set local role authenticated;
select public.get_website_execution_workspace_v7(
  'eec31000-0000-4000-8000-000000000002') as projection \gset
reset role;
select is(:'projection'::jsonb->>'contract_version', '7', 'versioned projection');
select is(:'projection'::jsonb->'preview_artifact'->>'build_status', 'PASS',
  'existing PASS artifact is visible');
select is(:'projection'::jsonb - 'contract_version' - 'preview_artifact',
  public.get_website_execution_workspace_v6('eec31000-0000-4000-8000-000000000002') - 'contract_version',
  'all previous workspace and permission fields remain unchanged');

update lws_internal.website_project_preview_builds set build_status = 'PASS_WITH_WARNINGS'
where preview_build_id = 'eec31000-0000-4000-8000-000000000009';
select is(public.get_website_execution_workspace_v7('eec31000-0000-4000-8000-000000000002')
  ->'preview_artifact'->>'build_status', 'PASS_WITH_WARNINGS',
  'existing warning status is preserved without a new build');

update public.website_execution_workspaces set last_commit_sha = repeat('b', 40)
where website_workspace_id = 'eec31000-0000-4000-8000-000000000005';
select is(public.get_website_execution_workspace_v7('eec31000-0000-4000-8000-000000000002')
  ->'preview_artifact', 'null'::jsonb, 'stale commit artifact is not presented as current');
update public.website_execution_workspaces set last_commit_sha = repeat('a', 40)
where website_workspace_id = 'eec31000-0000-4000-8000-000000000005';

update lws_internal.website_project_files_write_leases set binding_revision = binding_revision + 1
where lease_id = 'eec31000-0000-4000-8000-000000000007';
select is(public.get_website_execution_workspace_v7('eec31000-0000-4000-8000-000000000002')
  ->'preview_artifact', 'null'::jsonb, 'different repository binding is rejected');
update lws_internal.website_project_files_write_leases set binding_revision = binding_revision - 1
where lease_id = 'eec31000-0000-4000-8000-000000000007';

delete from lws_internal.website_project_preview_build_artifacts
where preview_build_id = 'eec31000-0000-4000-8000-000000000009';
select is(public.get_website_execution_workspace_v7('eec31000-0000-4000-8000-000000000002')
  ->'preview_artifact', 'null'::jsonb, 'removed artifact is not reported available');
select is((select count(*)::integer from lws_internal.website_project_preview_sessions), 0,
  'status reads do not open preview sessions');
select is((select count(*)::integer from lws_internal.website_project_preview_build_leases
  where quote_request_id = 'eec31000-0000-4000-8000-000000000002'), 1,
  'status reads do not acquire another build lease');
select finish();
rollback;

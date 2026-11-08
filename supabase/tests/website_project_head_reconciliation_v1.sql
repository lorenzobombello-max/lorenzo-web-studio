\set ON_ERROR_STOP on
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
select ok(not has_function_privilege('authenticated','public.reconcile_website_project_repository_head_v1(uuid,text,text)','execute'),
  'caller cannot supply verified proof');
select ok(has_function_privilege('service_role','public.reconcile_website_project_repository_head_v1(uuid,text,text)','execute'),
  'only server finalizes');
select set_config('request.jwt.claims','{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',true);
select throws_ok($$select public.acquire_website_project_files_read_v1('7458c346-dfc9-40f3-ad0e-cb94a16636bf','DIRECTORY')$$,
  '42501','AAL2_REQUIRED','read authority requires AAL2');
select set_config('request.jwt.claims','{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',true);
select public.acquire_website_project_files_read_v1('7458c346-dfc9-40f3-ad0e-cb94a16636bf','DIRECTORY')->>'leaseId' as read_id \gset
select set_config('test.read_id', :'read_id',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($$select public.reconcile_website_project_repository_head_v1(current_setting('test.read_id')::uuid,repeat('c',40),repeat('b',40))$$,
  'P0001','PROJECT_FILES_STALE_REVISION','stale CAS rejected');
update public.website_execution_workspaces set binding_revision=binding_revision+1 where website_workspace_id='fa057e1f-d03d-47cf-a595-317447734298';
select throws_ok($$select public.reconcile_website_project_repository_head_v1(current_setting('test.read_id')::uuid,repeat('a',40),repeat('b',40))$$,
  'P0001','REPOSITORY_BINDING_STALE','changed binding rejected');
update public.website_execution_workspaces set binding_revision=binding_revision-1 where website_workspace_id='fa057e1f-d03d-47cf-a595-317447734298';
update public.commercial_operators set status='REVOKED',revoked_at=clock_timestamp() where auth_user_id='c9bcd3ef-1e7e-4889-8a12-db827f1b97b0';
select throws_ok($$select public.reconcile_website_project_repository_head_v1(current_setting('test.read_id')::uuid,repeat('a',40),repeat('b',40))$$,
  '42501','WEBSITE_REPOSITORY_OWNER_REQUIRED','revoked owner rejected');
update public.commercial_operators set status='ACTIVE',revoked_at=null where auth_user_id='c9bcd3ef-1e7e-4889-8a12-db827f1b97b0';
select is(public.reconcile_website_project_repository_head_v1(:'read_id',repeat('a',40),repeat('b',40))->>'commitSha',repeat('b',40),'verified head reconciled');
select is((select last_commit_sha from public.website_execution_workspaces where website_workspace_id='fa057e1f-d03d-47cf-a595-317447734298'),repeat('b',40),'workspace projection updated');
select is((select count(*)::integer from lws_internal.website_project_head_reconciliations where read_lease_id=:'read_id'),1,'audit retained');
select throws_ok($$select public.reconcile_website_project_repository_head_v1(current_setting('test.read_id')::uuid,repeat('b',40),repeat('c',40))$$,
  'P0001','PROJECT_FILES_LEASE_EXPIRED','consumed authority cannot replay');
select set_config('request.jwt.claims','{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',true);
select public.acquire_website_project_preview_build_v1('7458c346-dfc9-40f3-ad0e-cb94a16636bf',repeat('b',40),gen_random_uuid())->>'leaseId' as preview_id \gset
select is((select expected_commit_sha from lws_internal.website_project_preview_build_leases where preview_lease_id=:'preview_id'),repeat('b',40),'actual preview acquire pins verified head');
select public.acquire_website_project_files_read_v1('7458c346-dfc9-40f3-ad0e-cb94a16636bf','DIRECTORY')->>'leaseId' as read_id \gset
select set_config('test.read_id', :'read_id',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($$select public.reconcile_website_project_repository_head_v1(current_setting('test.read_id')::uuid,repeat('b',40),repeat('c',40))$$,
  'P0001','PROJECT_HEAD_RECONCILIATION_BUSY','active preview/write blocks reconciliation');
select set_config('request.jwt.claims','{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',true);
insert into lws_internal.website_project_preview_workflow_revisions(workflow_sha,enabled) values(repeat('f',40),true);
select public.claim_website_project_preview_dispatch_v1(:'preview_id',repeat('f',40));
select public.record_website_project_preview_dispatch_v1(:'preview_id','UNKNOWN');
update lws_internal.website_project_preview_build_leases set expires_at=clock_timestamp()-interval '1 second' where preview_lease_id=:'preview_id';
update lws_internal.website_project_files_write_leases set released_at=clock_timestamp()
  where lease_id=(select source_write_lease_id from lws_internal.website_project_preview_build_leases where preview_lease_id=:'preview_id');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($$select public.reconcile_website_project_repository_head_v1(current_setting('test.read_id')::uuid,repeat('b',40),repeat('c',40))$$,
  'P0001','PROJECT_HEAD_RECONCILIATION_BUSY','unresolved UNKNOWN dispatch blocks even after preview expiry');
update lws_internal.website_project_files_read_leases set acquired_at=statement_timestamp()-interval '16 seconds',expires_at=statement_timestamp()-interval '1 second'
  where lease_id=:'read_id';
select throws_ok($$select public.reconcile_website_project_repository_head_v1(current_setting('test.read_id')::uuid,repeat('b',40),repeat('c',40))$$,
  'P0001','PROJECT_FILES_LEASE_EXPIRED','expired read authority rejected');
select * from finish();
rollback;

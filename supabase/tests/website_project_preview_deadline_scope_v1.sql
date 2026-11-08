-- Isolated runner fixtures only. All changes roll back.
begin;
create extension if not exists pgtap with schema extensions;
set local session_replication_role=replica;
set local search_path=public,extensions;
select no_plan();
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update lws_internal.website_project_preview_build_leases
set quote_request_id='7458c346-dfc9-40f3-ad0e-cb94a16636bf',
    website_work_context_id='a88b1e87-9271-4ad1-99cc-b385b7982a8b',
    website_workspace_id='fa057e1f-d03d-47cf-a595-317447734298'
where preview_lease_id='eec31001-0000-4000-8000-000000000008';
insert into lws_internal.website_project_preview_dispatches
  (preview_lease_id,authorized_build_id,actor_auth_user_id,workflow_sha,state,expires_at)
select preview_lease_id,authorized_build_id,actor_auth_user_id,repeat('f',40),'ATTEMPTED',clock_timestamp()-interval '1 minute'
from lws_internal.website_project_preview_build_leases
where preview_lease_id in ('eec31001-0000-4000-8000-000000000008','eec31002-0000-4000-8000-000000000008');
insert into lws_internal.website_project_preview_upload_sessions
  (session_token_hash,preview_lease_id,build_id,repository_external_id,commit_sha,workflow_run_id,primary_relative_path,build_status,expires_at)
select repeat(case when preview_lease_id::text like 'eec31001%' then 'a' else 'b' end,64),
  preview_lease_id,authorized_build_id,1,repeat('a',40),
  case when preview_lease_id::text like 'eec31001%' then 1 else 2 end,
  'index.html','PASS',clock_timestamp()+interval '10 minutes'
from lws_internal.website_project_preview_dispatches;
insert into lws_internal.website_project_preview_upload_files
  (session_token_hash,relative_path,content_type,sha256,bytes,state)
select session_token_hash,'index.html','text/html',repeat('c',64),12,'RECEIVED'
from lws_internal.website_project_preview_upload_sessions;
create temporary table untouched as
select 'lease' as kind,to_jsonb(l) as evidence from lws_internal.website_project_preview_build_leases l where preview_lease_id::text like 'eec31002%'
union all select 'source',to_jsonb(s) from lws_internal.website_project_files_write_leases s where lease_id::text like 'eec31002%'
union all select 'dispatch',to_jsonb(d) from lws_internal.website_project_preview_dispatches d where preview_lease_id::text like 'eec31002%'
union all select 'upload',to_jsonb(s) from lws_internal.website_project_preview_upload_sessions s where preview_lease_id::text like 'eec31002%'
union all select 'file',to_jsonb(f) from lws_internal.website_project_preview_upload_files f where session_token_hash=repeat('b',64);
select is(public.expire_website_project_preview_dispatches_dossier006_v1(),1,'only dossier006 expires');
select is(public.expire_website_project_preview_dispatches_dossier006_v1(),0,'no repeated transition');
update lws_internal.website_project_preview_dispatches set finished_at=clock_timestamp()-interval '3 minutes'
where preview_lease_id::text like 'eec31001%';
select is(public.get_website_project_preview_cleanup_candidates_dossier006_v1(),
  '["eec31001-0000-4000-8000-000000000009"]'::jsonb,'only dossier006 cleanup candidate');
select is(public.get_website_project_preview_failed_storage_paths_dossier006_v1('eec31001-0000-4000-8000-000000000009'),
  '["eec31001-0000-4000-8000-000000000009/index.html"]'::jsonb,'only authorized storage path');
select throws_ok($$select public.get_website_project_preview_failed_storage_paths_dossier006_v1('eec31002-0000-4000-8000-000000000009')$$,
  '42501','PROJECT_PREVIEW_CLEANUP_AUTHORITY_INVALID','other dossier paths denied');
select ok(not public.record_website_project_preview_cleanup_checked_dossier006_v1('eec31002-0000-4000-8000-000000000009'),'other dossier record denied');
select ok(public.record_website_project_preview_cleanup_checked_dossier006_v1('eec31001-0000-4000-8000-000000000009'),'dossier006 cleanup recorded');
select results_eq($$
select 'lease' as kind,to_jsonb(l) as evidence from lws_internal.website_project_preview_build_leases l where preview_lease_id::text like 'eec31002%'
union all select 'source',to_jsonb(s) from lws_internal.website_project_files_write_leases s where lease_id::text like 'eec31002%'
union all select 'dispatch',to_jsonb(d) from lws_internal.website_project_preview_dispatches d where preview_lease_id::text like 'eec31002%'
union all select 'upload',to_jsonb(s) from lws_internal.website_project_preview_upload_sessions s where preview_lease_id::text like 'eec31002%'
union all select 'file',to_jsonb(f) from lws_internal.website_project_preview_upload_files f where session_token_hash=repeat('b',64)
$$,$$select * from untouched$$,'other dossier lease/source/dispatch/upload/file evidence unchanged');
select ok(not exists(select 1 from lws_internal.website_project_preview_builds where lease_id::text like 'eec31002%'),'no other dossier terminal artifact inserted');
-- A failed non006 dispatch must also be invisible, not merely an active one.
update lws_internal.website_project_preview_dispatches set state='FAILED',finished_at=clock_timestamp()-interval '3 minutes'
where preview_lease_id::text like 'eec31002%';
update untouched set evidence=(select to_jsonb(d) from lws_internal.website_project_preview_dispatches d where preview_lease_id::text like 'eec31002%')
where kind='dispatch';
select is(public.get_website_project_preview_cleanup_candidates_dossier006_v1(),'[]'::jsonb,'failed non006 dispatch is not a candidate');
select throws_ok($$select public.get_website_project_preview_failed_storage_paths_dossier006_v1('eec31002-0000-4000-8000-000000000009')$$,
  '42501','PROJECT_PREVIEW_CLEANUP_AUTHORITY_INVALID','failed non006 storage paths denied');
select ok(not public.record_website_project_preview_cleanup_checked_dossier006_v1('eec31002-0000-4000-8000-000000000009'),'failed non006 cleanup record denied');
select is((select to_jsonb(d) from lws_internal.website_project_preview_dispatches d where preview_lease_id::text like 'eec31002%'),
  (select evidence from untouched where kind='dispatch'),'failed other dossier evidence unchanged');
select ok(not has_function_privilege('authenticated','public.expire_website_project_preview_dispatches_dossier006_v1()','execute')
  and not has_function_privilege('anon','public.get_website_project_preview_failed_storage_paths_dossier006_v1(uuid)','execute'),
  'scoped authority remains service only');
select * from finish();
rollback;

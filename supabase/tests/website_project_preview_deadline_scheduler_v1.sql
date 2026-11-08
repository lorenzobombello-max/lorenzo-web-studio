begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
select has_function('public', 'invoke_website_project_preview_deadline_v1', array[]::text[]);
select ok(not has_function_privilege('anon', 'public.invoke_website_project_preview_deadline_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public.schedule_website_project_preview_deadline_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.schedule_website_project_preview_deadline_v1()', 'execute'),
  'only database administrator can invoke or register the scheduler');
delete from vault.secrets where name = 'website_project_preview_deadline_secret';
select throws_ok($$select public.invoke_website_project_preview_deadline_v1()$$,
  'P0001', 'PREVIEW_DEADLINE_VAULT_CONFIG_INVALID', 'missing secret fails closed');
select throws_ok($$select public.schedule_website_project_preview_deadline_v1()$$,
  'P0001', 'PREVIEW_DEADLINE_VAULT_CONFIG_INVALID', 'missing secret cannot activate schedule');
select vault.create_secret(repeat('x', 64), 'website_project_preview_deadline_secret');
create temporary table other_jobs as select jobid,jobname,schedule,command,active from cron.job;
select lives_ok($$select public.schedule_website_project_preview_deadline_v1()$$, 'trusted configuration schedules recovery');
select lives_ok($$select public.schedule_website_project_preview_deadline_v1()$$, 'repeat registration is idempotent');
select is((select count(*) from cron.job where jobname = 'website-project-preview-deadline-v1'), 1::bigint, 'exactly one job');
select is((select schedule from cron.job where jobname = 'website-project-preview-deadline-v1'), '* * * * *', 'minute recovery schedule');
select ok(not exists(select * from other_jobs except select jobid,jobname,schedule,command,active from cron.job),
  'other schedules unchanged');
select lives_ok($$select public.invoke_website_project_preview_deadline_v1()$$, 'queues trusted bounded request');
select ok(exists(select 1 from net.http_request_queue
  where url = 'https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/website-project-preview-completion/deadline'
  and headers->>'x-lws-automation-secret' = repeat('x', 64)
  and timeout_milliseconds = 10000), 'fixed production endpoint and bounded request');
select lives_ok($$select public.unschedule_website_project_preview_deadline_v1()$$, 'can stop only recovery schedule');
select is((select count(*) from cron.job where jobname = 'website-project-preview-deadline-v1'), 0::bigint, 'schedule removed');
select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

select has_function(
  'public', 'invoke_intake_reminder_worker_v1', array[]::text[],
  'reminder worker invocation authority exists'
);
select has_function(
  'public', 'schedule_intake_reminder_worker_cron_v1', array[]::text[],
  'reminder scheduler registration authority exists'
);
select has_function(
  'public', 'unschedule_intake_reminder_worker_cron_v1', array[]::text[],
  'reminder scheduler removal authority exists'
);
select ok(
  has_function_privilege('service_role', 'public.invoke_intake_reminder_worker_v1()', 'execute')
  and has_function_privilege('service_role', 'public.schedule_intake_reminder_worker_cron_v1()', 'execute')
  and has_function_privilege('service_role', 'public.unschedule_intake_reminder_worker_cron_v1()', 'execute')
  and not has_function_privilege('anon', 'public.invoke_intake_reminder_worker_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public.invoke_intake_reminder_worker_v1()', 'execute'),
  'scheduler entry points are restricted to service role'
);

delete from vault.secrets
where name in ('intake_reminder_worker_url', 'intake_reminder_automation_secret');

create temp table request_queue_before as
select count(*)::bigint as value from net.http_request_queue;

select vault.create_secret(
  'https://scheduler.invalid/functions/v1/intake-reminder-worker',
  'intake_reminder_worker_url'
);
select throws_ok(
  $$select public.invoke_intake_reminder_worker_v1()$$,
  'P0001',
  'INTAKE_REMINDER_AUTOMATION_VAULT_CONFIG_INVALID',
  'missing Vault config fails closed'
);
select is(
  (select count(*) from net.http_request_queue),
  (select value from request_queue_before),
  'missing Vault config creates no HTTP request'
);

delete from vault.secrets where name = 'intake_reminder_worker_url';
select vault.create_secret(
  encode(gen_random_bytes(32), 'hex'),
  'intake_reminder_automation_secret'
);
select throws_ok(
  $$select public.invoke_intake_reminder_worker_v1()$$,
  'P0001',
  'INTAKE_REMINDER_AUTOMATION_VAULT_CONFIG_INVALID',
  'missing worker URL fails closed'
);
select is(
  (select count(*) from net.http_request_queue),
  (select value from request_queue_before),
  'missing worker URL creates no HTTP request'
);

select vault.create_secret(
  'https://scheduler.invalid/functions/v1/intake-reminder-worker',
  'intake_reminder_worker_url'
);

select cron.schedule(
  'application-intake-automation-v1',
  '3 * * * *',
  'select 1;'
);
create temp table existing_scheduler_before as
select jobid, schedule, command
from cron.job
where jobname = 'application-intake-automation-v1';

select lives_ok(
  $$select public.schedule_intake_reminder_worker_cron_v1()$$,
  'valid Vault authority registers the reminder cron job'
);
select is(
  (select count(*)::integer from cron.job where jobname = 'intake-reminder-worker-v1'),
  1,
  'reminder cron job is registered exactly once'
);
select is(
  (select schedule from cron.job where jobname = 'intake-reminder-worker-v1'),
  '7 * * * *',
  'reminder cron runs once per hour at minute seven'
);
select is(
  (select btrim(command) from cron.job where jobname = 'intake-reminder-worker-v1'),
  'select public.invoke_intake_reminder_worker_v1();',
  'cron delegates only to the guarded worker invoker'
);

select lives_ok(
  $$select public.schedule_intake_reminder_worker_cron_v1()$$,
  'repeated registration succeeds'
);
select is(
  (select count(*)::integer from cron.job where jobname = 'intake-reminder-worker-v1'),
  1,
  'repeated registration cannot duplicate the reminder cron job'
);
select results_eq(
  $$select jobid, schedule, command from cron.job where jobname = 'application-intake-automation-v1'$$,
  $$select jobid, schedule, command from existing_scheduler_before$$,
  'existing application scheduler is unchanged'
);

select ok(
  pg_get_functiondef('public.invoke_intake_reminder_worker_v1()'::regprocedure)
    like '%vault.decrypted_secrets%intake_reminder_worker_url%'
  and pg_get_functiondef('public.invoke_intake_reminder_worker_v1()'::regprocedure)
    like '%vault.decrypted_secrets%intake_reminder_automation_secret%',
  'worker URL and authentication secret come from dedicated Vault authority'
);
select ok(
  pg_get_functiondef('public.invoke_intake_reminder_worker_v1()'::regprocedure)
    !~ 'https://[[:alnum:]]'
  and pg_get_functiondef('public.invoke_intake_reminder_worker_v1()'::regprocedure)
    not like '%scheduler.invalid%',
  'scheduler invoker persists no concrete URL or local configuration value'
);
select ok(
  pg_get_functiondef('public.invoke_intake_reminder_worker_v1()'::regprocedure)
    like '%/functions/v1/intake-reminder-worker%'
  and pg_get_functiondef('public.invoke_intake_reminder_worker_v1()'::regprocedure)
    like '%x-lws-automation-secret%'
  and pg_get_functiondef('public.invoke_intake_reminder_worker_v1()'::regprocedure)
    like '%' || quote_literal('dry_run') || '%false%',
  'worker invocation uses the required endpoint, custom header, and normal-mode body'
);
select ok(
  pg_get_functiondef('public.invoke_intake_reminder_worker_v1()'::regprocedure)
    !~* 'recipient|email|phone|encrypted|html|customer',
  'scheduler request contains no customer PII or delivery payload'
);
select ok(
  has_function_privilege('service_role', 'public.list_intake_reminder_candidates_v1(text,timestamptz,integer)', 'execute')
  and has_function_privilege('service_role', 'public.claim_intake_reminder_v1(uuid,text,timestamptz)', 'execute')
  and has_function_privilege('service_role', 'public.prepare_intake_reminder_email_job_v1(uuid,bigint,text,uuid,timestamptz)', 'execute'),
  'existing reminder authority remains available and unchanged'
);
select is(
  (select count(*) from net.http_request_queue),
  (select value from request_queue_before),
  'scheduler contract tests make no worker HTTP invocation'
);

select * from finish();
rollback;
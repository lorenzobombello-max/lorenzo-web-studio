create extension if not exists pg_cron;
create extension if not exists pg_net;
create extension if not exists supabase_vault;

create function public.invoke_intake_reminder_worker_v1()
returns bigint
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_worker_url text;
  v_worker_secret text;
  v_worker_url_count bigint;
  v_worker_secret_count bigint;
  v_request_id bigint;
begin
  select count(*), min(decrypted_secret)
  into v_worker_url_count, v_worker_url
  from vault.decrypted_secrets
  where name = 'intake_reminder_worker_url';

  select count(*), min(decrypted_secret)
  into v_worker_secret_count, v_worker_secret
  from vault.decrypted_secrets
  where name = 'intake_reminder_automation_secret';

  if v_worker_url_count <> 1
     or v_worker_secret_count <> 1
     or v_worker_url is null
     or btrim(v_worker_url) = ''
     or v_worker_url !~ '^https://[^[:space:]]+/functions/v1/intake-reminder-worker/?$'
     or v_worker_secret is null
     or btrim(v_worker_secret) = ''
     or octet_length(v_worker_secret) < 32 then
    raise exception using
      errcode = 'P0001',
      message = 'INTAKE_REMINDER_AUTOMATION_VAULT_CONFIG_INVALID';
  end if;

  select net.http_post(
    url := v_worker_url,
    body := pg_catalog.jsonb_build_object('dry_run', false),
    headers := pg_catalog.jsonb_build_object(
      'content-type', 'application/json',
      'x-lws-automation-secret', v_worker_secret
    ),
    timeout_milliseconds := 5000
  ) into v_request_id;

  return v_request_id;
end;
$$;

create function public.schedule_intake_reminder_worker_cron_v1()
returns bigint
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_worker_url text;
  v_worker_secret text;
  v_worker_url_count bigint;
  v_worker_secret_count bigint;
  v_existing_job_id bigint;
  v_scheduled_job_id bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(17003, 8);

  select count(*), min(decrypted_secret)
  into v_worker_url_count, v_worker_url
  from vault.decrypted_secrets
  where name = 'intake_reminder_worker_url';

  select count(*), min(decrypted_secret)
  into v_worker_secret_count, v_worker_secret
  from vault.decrypted_secrets
  where name = 'intake_reminder_automation_secret';

  if v_worker_url_count <> 1
     or v_worker_secret_count <> 1
     or v_worker_url is null
     or btrim(v_worker_url) = ''
     or v_worker_url !~ '^https://[^[:space:]]+/functions/v1/intake-reminder-worker/?$'
     or v_worker_secret is null
     or btrim(v_worker_secret) = ''
     or octet_length(v_worker_secret) < 32 then
    raise exception using
      errcode = 'P0001',
      message = 'INTAKE_REMINDER_AUTOMATION_VAULT_CONFIG_INVALID';
  end if;

  for v_existing_job_id in
    select jobid
    from cron.job
    where jobname = 'intake-reminder-worker-v1'
  loop
    perform cron.unschedule(v_existing_job_id);
  end loop;

  select cron.schedule(
    'intake-reminder-worker-v1',
    '7 * * * *',
    $command$select public.invoke_intake_reminder_worker_v1();$command$
  ) into v_scheduled_job_id;

  return v_scheduled_job_id;
end;
$$;

create function public.unschedule_intake_reminder_worker_cron_v1()
returns integer
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_existing_job_id bigint;
  v_removed_count integer := 0;
begin
  perform pg_catalog.pg_advisory_xact_lock(17003, 8);

  for v_existing_job_id in
    select jobid
    from cron.job
    where jobname = 'intake-reminder-worker-v1'
  loop
    perform cron.unschedule(v_existing_job_id);
    v_removed_count := v_removed_count + 1;
  end loop;

  return v_removed_count;
end;
$$;

revoke all on function public.invoke_intake_reminder_worker_v1()
  from public, anon, authenticated, service_role;
revoke all on function public.schedule_intake_reminder_worker_cron_v1()
  from public, anon, authenticated, service_role;
revoke all on function public.unschedule_intake_reminder_worker_cron_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.invoke_intake_reminder_worker_v1() to service_role;
grant execute on function public.schedule_intake_reminder_worker_cron_v1() to service_role;
grant execute on function public.unschedule_intake_reminder_worker_cron_v1() to service_role;
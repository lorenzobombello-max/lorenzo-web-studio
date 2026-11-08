-- Uses the existing pg_cron / pg_net / Vault scheduler. Activation is an
-- explicit release operation after the matching Edge secret is provisioned.
create function public.invoke_website_project_preview_deadline_v1()
returns bigint language plpgsql volatile security definer set search_path = pg_catalog
as $$
declare
  v_secret text;
  v_count bigint;
  v_request_id bigint;
begin
  select count(*), min(decrypted_secret) into v_count, v_secret
  from vault.decrypted_secrets where name = 'website_project_preview_deadline_secret';
  if v_count <> 1 or v_secret is null or octet_length(v_secret) < 32 or octet_length(v_secret) > 256 then
    raise exception using errcode = 'P0001', message = 'PREVIEW_DEADLINE_VAULT_CONFIG_INVALID';
  end if;
  select net.http_post(
    url := 'https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/website-project-preview-completion/deadline',
    body := '{}'::jsonb,
    headers := jsonb_build_object('content-type', 'application/json', 'x-lws-automation-secret', v_secret),
    timeout_milliseconds := 10000
  ) into v_request_id;
  return v_request_id;
end;
$$;

create function public.schedule_website_project_preview_deadline_v1()
returns bigint language plpgsql volatile security definer set search_path = pg_catalog
as $$
declare
  v_secret text;
  v_count bigint;
  v_job_id bigint;
begin
  perform pg_advisory_xact_lock(17003, 9);
  select count(*), min(decrypted_secret) into v_count, v_secret
  from vault.decrypted_secrets where name = 'website_project_preview_deadline_secret';
  if v_count <> 1 or v_secret is null or octet_length(v_secret) < 32 or octet_length(v_secret) > 256 then
    raise exception using errcode = 'P0001', message = 'PREVIEW_DEADLINE_VAULT_CONFIG_INVALID';
  end if;
  select cron.schedule('website-project-preview-deadline-v1', '* * * * *',
    'select public.invoke_website_project_preview_deadline_v1();') into v_job_id;
  return v_job_id;
end;
$$;

create function public.unschedule_website_project_preview_deadline_v1()
returns integer language plpgsql volatile security definer set search_path = pg_catalog
as $$
declare
  v_job_id bigint;
  v_count integer := 0;
begin
  perform pg_advisory_xact_lock(17003, 9);
  for v_job_id in select jobid from cron.job where jobname = 'website-project-preview-deadline-v1' loop
    perform cron.unschedule(v_job_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.invoke_website_project_preview_deadline_v1() from public, anon, authenticated, service_role;
revoke all on function public.schedule_website_project_preview_deadline_v1() from public, anon, authenticated, service_role;
revoke all on function public.unschedule_website_project_preview_deadline_v1() from public, anon, authenticated, service_role;

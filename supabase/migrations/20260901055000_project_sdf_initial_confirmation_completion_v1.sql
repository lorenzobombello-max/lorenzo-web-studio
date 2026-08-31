create function lws_internal.advance_sdf_automation_from_initial_confirmation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.status = 'sent'
     and new.sent_at is not null
     and (
       old.status is distinct from new.status
       or old.sent_at is distinct from new.sent_at
     ) then
    update public.quote_requests
    set confirmation_sent_at = coalesce(confirmation_sent_at, new.sent_at)
    where id = new.quote_request_id
      and request_kind = 'slimme_documentenflow'
      and record_classification = 'production';
  end if;

  return new;
end;
$$;

alter function lws_internal.advance_sdf_automation_from_initial_confirmation_v1()
owner to postgres;

revoke execute on function lws_internal.advance_sdf_automation_from_initial_confirmation_v1()
from public, anon, authenticated, service_role;

create trigger sdf_initial_confirmation_email_jobs_project_completion
after update of status, sent_at
on public.sdf_initial_confirmation_email_jobs
for each row
when (
  new.status = 'sent'
  and new.sent_at is not null
  and (
    old.status is distinct from new.status
    or old.sent_at is distinct from new.sent_at
  )
)
execute function lws_internal.advance_sdf_automation_from_initial_confirmation_v1();
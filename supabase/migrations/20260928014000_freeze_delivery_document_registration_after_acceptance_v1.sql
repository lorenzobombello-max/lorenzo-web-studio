-- W2.4.1-P3 review finding I-1: a candidate prepared before acceptance could still be registered as a
-- newer artifact (and PDF view) after acceptance, after which the shared current-document helper hid
-- the accepted document or served a never-accepted one. Registration is now refused once the project
-- has an acceptance, serialized with the acceptance command through the same project row lock.
-- Review finding M-e: the accepting session must belong to the accepting access by constraint.

create function lws_internal.guard_website_delivery_registration_after_acceptance_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  perform 1 from public.commercial_projects where project_id = new.project_id for update;
  if exists (
    select 1 from public.website_delivery_document_acceptances where project_id = new.project_id
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ALREADY_ACCEPTED';
  end if;
  return new;
end;
$$;

revoke all on function lws_internal.guard_website_delivery_registration_after_acceptance_v1()
from public, anon, authenticated, service_role;

create trigger trg_website_delivery_artifact_after_acceptance
before insert on public.website_delivery_document_artifacts
for each row execute function lws_internal.guard_website_delivery_registration_after_acceptance_v1();

create trigger trg_website_delivery_view_after_acceptance
before insert on public.website_delivery_document_view_derivatives
for each row execute function lws_internal.guard_website_delivery_registration_after_acceptance_v1();

alter table public.preview_sessions
  add constraint preview_session_access_binding_unique unique (preview_session_id, preview_access_id);

alter table public.website_delivery_document_acceptances
  add constraint website_delivery_acceptance_session_access_binding
  foreign key (preview_session_id, preview_access_id)
  references public.preview_sessions (preview_session_id, preview_access_id);

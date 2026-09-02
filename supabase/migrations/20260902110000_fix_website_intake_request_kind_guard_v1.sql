create or replace function public.guard_website_intake_kind_v1()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_request_kind text;
begin
  select request_kind into v_request_kind
  from public.quote_requests
  where id = new.quote_request_id;

  if v_request_kind = 'slimme_documentenflow'
     and current_setting('lws.sdf_generic_intake_adapter', true) is distinct from 'CREATE' then
    raise exception using errcode = '42501', message = 'REQUEST_KIND_INTAKE_NOT_ALLOWED';
  end if;
  return new;
end;
$$;

revoke execute on function public.guard_website_intake_kind_v1()
from public, anon, authenticated, service_role;

comment on function public.guard_website_intake_kind_v1() is
  'Fail-closed boundary preventing SDF requests from entering Website intake except through the controlled SDF generic-intake adapter.';
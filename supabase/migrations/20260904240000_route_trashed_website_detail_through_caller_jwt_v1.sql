create function public.get_operator_trashed_website_intake_detail_caller_v1(
  p_support_reference text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  return public.get_operator_trashed_website_intake_detail_v1(
    v_subject,
    p_support_reference
  );
end;
$$;

revoke all on function public.get_operator_trashed_website_intake_detail_caller_v1(text)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_trashed_website_intake_detail_caller_v1(text)
to authenticated;

comment on function public.get_operator_trashed_website_intake_detail_caller_v1(text) is
  'Authenticated caller-JWT wrapper for the unchanged service-only TRASHED Website intake detail authority.';
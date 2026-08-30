create function public.list_owner_recruitment_vacancies_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_actor public.commercial_operators%rowtype;
  v_result jsonb;
begin
  select * into v_actor
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_actor.status <> 'ACTIVE' or v_actor.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', vacancy.id,
        'title', vacancy.title,
        'slug', vacancy.slug,
        'department', vacancy.department,
        'location', vacancy.location,
        'employment_type', vacancy.employment_type,
        'summary', vacancy.summary,
        'description', vacancy.description,
        'requirements', vacancy.requirements,
        'status', vacancy.status,
        'published_at', vacancy.published_at,
        'closed_at', vacancy.closed_at,
        'created_at', vacancy.created_at,
        'updated_at', vacancy.updated_at
      ) order by vacancy.created_at desc, vacancy.id
    ),
    '[]'::jsonb
  ) into v_result
  from public.recruitment_vacancies as vacancy;

  return v_result;
end;
$$;

revoke all on function public.list_owner_recruitment_vacancies_v1()
from public, anon, authenticated, service_role;
grant execute on function public.list_owner_recruitment_vacancies_v1()
to authenticated;

comment on function public.list_owner_recruitment_vacancies_v1() is
  'Caller-JWT owner-only vacancy management projection across draft, published, and closed states.';
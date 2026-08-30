create table public.recruitment_vacancies (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 160),
  slug text not null,
  department text not null check (char_length(btrim(department)) between 1 and 120),
  location text not null check (char_length(btrim(location)) between 1 and 160),
  employment_type text not null check (char_length(btrim(employment_type)) between 1 and 80),
  summary text not null check (char_length(btrim(summary)) between 1 and 500),
  description text not null check (nullif(btrim(description), '') is not null),
  requirements text not null check (nullif(btrim(requirements), '') is not null),
  status text not null default 'DRAFT' check (status in ('DRAFT', 'PUBLISHED', 'CLOSED')),
  published_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint recruitment_vacancies_slug_key unique (slug),
  constraint recruitment_vacancies_slug_format check (
    slug = btrim(slug)
    and char_length(slug) between 1 and 120
    and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
  ),
  constraint recruitment_vacancies_publication_timestamps check (
    (status = 'DRAFT' and published_at is null and closed_at is null)
    or (status = 'PUBLISHED' and published_at is not null and closed_at is null)
    or (status = 'CLOSED' and published_at is not null and closed_at is not null)
  )
);

alter table public.recruitment_vacancies enable row level security;
alter table public.recruitment_vacancies force row level security;

revoke all privileges on table public.recruitment_vacancies
from public, anon, authenticated, service_role;

comment on table public.recruitment_vacancies is
  'Owner-managed vacancy authority exposed publicly only through the published-vacancy RPC projection.';

create function public.set_recruitment_vacancies_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger trg_recruitment_vacancies_set_updated_at
before update on public.recruitment_vacancies
for each row execute function public.set_recruitment_vacancies_updated_at();

revoke all on function public.set_recruitment_vacancies_updated_at()
from public, anon, authenticated, service_role;

create function public.create_recruitment_vacancy_v1(
  p_title text,
  p_slug text,
  p_department text,
  p_location text,
  p_employment_type text,
  p_summary text,
  p_description text,
  p_requirements text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_actor public.commercial_operators%rowtype;
  v_vacancy public.recruitment_vacancies%rowtype;
begin
  select * into v_actor
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_actor.status <> 'ACTIVE' or v_actor.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;

  insert into public.recruitment_vacancies (
    title, slug, department, location, employment_type,
    summary, description, requirements
  ) values (
    btrim(p_title), btrim(p_slug), btrim(p_department), btrim(p_location),
    btrim(p_employment_type), btrim(p_summary), btrim(p_description), btrim(p_requirements)
  )
  returning * into v_vacancy;

  return jsonb_build_object(
    'id', v_vacancy.id,
    'slug', v_vacancy.slug,
    'status', v_vacancy.status
  );
end;
$$;

create function public.update_recruitment_vacancy_v1(
  p_vacancy_id uuid,
  p_title text,
  p_department text,
  p_location text,
  p_employment_type text,
  p_summary text,
  p_description text,
  p_requirements text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_actor public.commercial_operators%rowtype;
  v_vacancy public.recruitment_vacancies%rowtype;
begin
  select * into v_actor
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_actor.status <> 'ACTIVE' or v_actor.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;

  update public.recruitment_vacancies
  set title = btrim(p_title),
      department = btrim(p_department),
      location = btrim(p_location),
      employment_type = btrim(p_employment_type),
      summary = btrim(p_summary),
      description = btrim(p_description),
      requirements = btrim(p_requirements)
  where id = p_vacancy_id
  returning * into v_vacancy;
  if not found then
    raise exception using errcode = 'P0002', message = 'RECRUITMENT_VACANCY_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'id', v_vacancy.id,
    'slug', v_vacancy.slug,
    'status', v_vacancy.status
  );
end;
$$;

create function public.set_recruitment_vacancy_status_v1(
  p_vacancy_id uuid,
  p_status text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_actor public.commercial_operators%rowtype;
  v_vacancy public.recruitment_vacancies%rowtype;
  v_changed_at timestamptz := clock_timestamp();
begin
  select * into v_actor
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_actor.status <> 'ACTIVE' or v_actor.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;
  if p_status is null or p_status not in ('DRAFT', 'PUBLISHED', 'CLOSED') then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_VACANCY_STATUS';
  end if;

  select * into v_vacancy
  from public.recruitment_vacancies
  where id = p_vacancy_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'RECRUITMENT_VACANCY_NOT_FOUND';
  end if;
  if p_status = 'DRAFT' and v_vacancy.status <> 'DRAFT' then
    raise exception using errcode = '22023', message = 'RECRUITMENT_VACANCY_DRAFT_REVERSION_DENIED';
  end if;
  if p_status = 'CLOSED' and v_vacancy.published_at is null then
    raise exception using errcode = '22023', message = 'RECRUITMENT_VACANCY_MUST_BE_PUBLISHED_BEFORE_CLOSE';
  end if;

  update public.recruitment_vacancies
  set status = p_status,
      published_at = case
        when p_status = 'DRAFT' then null
        when p_status = 'PUBLISHED' then coalesce(published_at, v_changed_at)
        else published_at
      end,
      closed_at = case when p_status = 'CLOSED' then v_changed_at else null end
  where id = p_vacancy_id
  returning * into v_vacancy;

  return jsonb_build_object(
    'id', v_vacancy.id,
    'slug', v_vacancy.slug,
    'status', v_vacancy.status,
    'published_at', v_vacancy.published_at,
    'closed_at', v_vacancy.closed_at
  );
end;
$$;

create function public.list_public_recruitment_vacancies_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'title', vacancy.title,
        'slug', vacancy.slug,
        'department', vacancy.department,
        'location', vacancy.location,
        'employment_type', vacancy.employment_type,
        'summary', vacancy.summary,
        'description', vacancy.description,
        'requirements', vacancy.requirements,
        'published_at', vacancy.published_at
      ) order by vacancy.published_at desc, vacancy.slug
    ),
    '[]'::jsonb
  )
  from public.recruitment_vacancies as vacancy
  where vacancy.status = 'PUBLISHED';
$$;

revoke all on function public.create_recruitment_vacancy_v1(text, text, text, text, text, text, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.update_recruitment_vacancy_v1(uuid, text, text, text, text, text, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.set_recruitment_vacancy_status_v1(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.list_public_recruitment_vacancies_v1()
from public, anon, authenticated, service_role;

grant execute on function public.create_recruitment_vacancy_v1(text, text, text, text, text, text, text, text)
to authenticated;
grant execute on function public.update_recruitment_vacancy_v1(uuid, text, text, text, text, text, text, text)
to authenticated;
grant execute on function public.set_recruitment_vacancy_status_v1(uuid, text)
to authenticated;
grant execute on function public.list_public_recruitment_vacancies_v1()
to anon, authenticated;

comment on function public.list_public_recruitment_vacancies_v1() is
  'Public projection containing only active published vacancy content and no internal identifiers.';
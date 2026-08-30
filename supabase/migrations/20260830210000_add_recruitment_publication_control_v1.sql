create table public.recruitment_publication_settings (
  singleton boolean primary key default true,
  enabled boolean not null default true,
  updated_at timestamptz not null default clock_timestamp(),
  constraint recruitment_publication_settings_singleton check (singleton)
);

insert into public.recruitment_publication_settings (singleton, enabled)
values (true, true);

alter table public.recruitment_publication_settings enable row level security;
alter table public.recruitment_publication_settings force row level security;

revoke all privileges on table public.recruitment_publication_settings
from public, anon, authenticated, service_role;

comment on table public.recruitment_publication_settings is
  'Private singleton authority controlling all public recruitment visibility.';

create function public.set_recruitment_publication_settings_updated_at_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger trg_recruitment_publication_settings_updated_at
before update on public.recruitment_publication_settings
for each row execute function public.set_recruitment_publication_settings_updated_at_v1();

revoke all on function public.set_recruitment_publication_settings_updated_at_v1()
from public, anon, authenticated, service_role;

create function public.get_public_recruitment_publication_state_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select jsonb_build_object('enabled', settings.enabled)
  from public.recruitment_publication_settings as settings
  where settings.singleton;
$$;

create function public.set_recruitment_publication_enabled_v1(p_enabled boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_actor public.commercial_operators%rowtype;
  v_enabled boolean;
begin
  if p_enabled is null then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_PUBLICATION_STATE';
  end if;

  select * into v_actor
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_actor.status <> 'ACTIVE' or v_actor.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;

  update public.recruitment_publication_settings
  set enabled = p_enabled
  where singleton
  returning enabled into v_enabled;

  if not found then
    raise exception using errcode = 'P0002', message = 'RECRUITMENT_PUBLICATION_STATE_NOT_FOUND';
  end if;

  return jsonb_build_object('enabled', v_enabled);
end;
$$;

create or replace function public.list_public_recruitment_vacancies_v1()
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
  where vacancy.status = 'PUBLISHED'
    and exists (
      select 1
      from public.recruitment_publication_settings as settings
      where settings.singleton and settings.enabled
    );
$$;

revoke all on function public.get_public_recruitment_publication_state_v1()
from public, anon, authenticated, service_role;
grant execute on function public.get_public_recruitment_publication_state_v1()
to anon, authenticated;

revoke all on function public.set_recruitment_publication_enabled_v1(boolean)
from public, anon, authenticated, service_role;
grant execute on function public.set_recruitment_publication_enabled_v1(boolean)
to authenticated;

comment on function public.get_public_recruitment_publication_state_v1() is
  'Returns only the central public recruitment enabled state.';
comment on function public.set_recruitment_publication_enabled_v1(boolean) is
  'Allows only an active owner to change central public recruitment visibility.';
comment on function public.list_public_recruitment_vacancies_v1() is
  'Public projection available only when central recruitment publication is enabled and vacancy status is PUBLISHED.';
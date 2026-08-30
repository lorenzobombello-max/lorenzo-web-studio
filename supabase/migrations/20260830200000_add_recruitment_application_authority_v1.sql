insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'recruitment-cvs',
  'recruitment-cvs',
  false,
  10485760,
  array[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]::text[]
);

create table public.recruitment_applications (
  id uuid primary key,
  vacancy_id uuid not null references public.recruitment_vacancies(id) on delete restrict,
  first_name text not null,
  last_name text not null,
  email text not null,
  phone text,
  motivation text not null,
  cv_storage_path text not null unique,
  cv_mime_type text not null,
  cv_byte_count bigint not null,
  cv_sha256 char(64) not null,
  status text not null default 'SUBMITTED',
  submitted_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint recruitment_applications_first_name_valid check (
    first_name = btrim(first_name) and length(first_name) between 1 and 100
  ),
  constraint recruitment_applications_last_name_valid check (
    last_name = btrim(last_name) and length(last_name) between 1 and 100
  ),
  constraint recruitment_applications_email_valid check (
    email = lower(btrim(email))
    and length(email) between 3 and 254
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint recruitment_applications_phone_valid check (
    phone is null or (phone = btrim(phone) and length(phone) between 1 and 40)
  ),
  constraint recruitment_applications_motivation_valid check (
    motivation = btrim(motivation) and length(motivation) between 1 and 5000
  ),
  constraint recruitment_applications_cv_mime_valid check (
    cv_mime_type in (
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    )
  ),
  constraint recruitment_applications_cv_byte_count_valid check (
    cv_byte_count between 1 and 10485760
  ),
  constraint recruitment_applications_cv_sha256_valid check (
    cv_sha256 ~ '^[0-9a-f]{64}$'
  ),
  constraint recruitment_applications_cv_path_valid check (
    cv_storage_path = 'applications/' || id::text || '/cv.' || case cv_mime_type
      when 'application/pdf' then 'pdf'
      when 'application/msword' then 'doc'
      when 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then 'docx'
    end
  ),
  constraint recruitment_applications_status_valid check (status = 'SUBMITTED')
);

alter table public.recruitment_applications enable row level security;
alter table public.recruitment_applications force row level security;

revoke all privileges on table public.recruitment_applications
from public, anon, authenticated, service_role;

comment on table public.recruitment_applications is
  'Private candidate applications created only after server-side CV validation and restricted to RPC authority.';

create function public.set_recruitment_applications_updated_at_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = clock_timestamp();
  return new;
end;
$$;

create trigger trg_recruitment_applications_set_updated_at
before update on public.recruitment_applications
for each row execute function public.set_recruitment_applications_updated_at_v1();

revoke all on function public.set_recruitment_applications_updated_at_v1()
from public, anon, authenticated, service_role;

create function public.finalize_recruitment_application_v1(
  p_application_id uuid,
  p_vacancy_id uuid,
  p_first_name text,
  p_last_name text,
  p_email text,
  p_phone text,
  p_motivation text,
  p_cv_storage_path text,
  p_cv_mime_type text,
  p_cv_byte_count bigint,
  p_cv_sha256 text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, storage, auth, pg_catalog
as $$
declare
  v_vacancy public.recruitment_vacancies%rowtype;
  v_first_name text := btrim(p_first_name);
  v_last_name text := btrim(p_last_name);
  v_email text := lower(btrim(p_email));
  v_phone text := nullif(btrim(p_phone), '');
  v_motivation text := btrim(p_motivation);
  v_mime_type text := lower(btrim(p_cv_mime_type));
  v_sha256 text := btrim(p_cv_sha256);
  v_extension text;
  v_expected_path text;
  v_storage_metadata jsonb;
  v_application public.recruitment_applications%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_APPLICATION_SERVICE_REQUIRED';
  end if;
  if p_application_id is null then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_APPLICATION_ID';
  end if;
  if v_first_name is null or length(v_first_name) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_FIRST_NAME';
  end if;
  if v_last_name is null or length(v_last_name) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_LAST_NAME';
  end if;
  if v_email is null or length(v_email) not between 3 and 254
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_EMAIL';
  end if;
  if v_phone is not null and length(v_phone) > 40 then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_PHONE';
  end if;
  if v_motivation is null or length(v_motivation) not between 1 and 5000 then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_MOTIVATION';
  end if;
  if v_mime_type not in (
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_CV_MIME_TYPE';
  end if;
  if p_cv_byte_count is null or p_cv_byte_count not between 1 and 10485760 then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_CV_BYTE_COUNT';
  end if;
  if v_sha256 is null or v_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_CV_SHA256';
  end if;

  select * into v_vacancy
  from public.recruitment_vacancies
  where id = p_vacancy_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'RECRUITMENT_VACANCY_NOT_FOUND';
  end if;
  if v_vacancy.status <> 'PUBLISHED' then
    raise exception using errcode = '22023', message = 'RECRUITMENT_VACANCY_NOT_OPEN';
  end if;

  v_extension := case v_mime_type
    when 'application/pdf' then 'pdf'
    when 'application/msword' then 'doc'
    when 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then 'docx'
  end;
  v_expected_path := 'applications/' || p_application_id::text || '/cv.' || v_extension;
  if p_cv_storage_path is distinct from v_expected_path then
    raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_CV_STORAGE_PATH';
  end if;

  select object.metadata into v_storage_metadata
  from storage.objects as object
  where object.bucket_id = 'recruitment-cvs'
    and object.name = v_expected_path;
  if not found
     or coalesce(v_storage_metadata->>'mimetype', '') <> v_mime_type
     or coalesce(v_storage_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_storage_metadata->>'size')::bigint <> p_cv_byte_count
     or coalesce(v_storage_metadata->>'sha256', '') <> v_sha256 then
    raise exception using errcode = 'P0001', message = 'RECRUITMENT_CV_OBJECT_MISMATCH';
  end if;

  insert into public.recruitment_applications (
    id, vacancy_id, first_name, last_name, email, phone, motivation,
    cv_storage_path, cv_mime_type, cv_byte_count, cv_sha256
  ) values (
    p_application_id, p_vacancy_id, v_first_name, v_last_name, v_email,
    v_phone, v_motivation, v_expected_path, v_mime_type,
    p_cv_byte_count, v_sha256
  ) returning * into v_application;

  return jsonb_build_object(
    'id', v_application.id,
    'status', v_application.status,
    'submitted_at', v_application.submitted_at
  );
end;
$$;

create function public.list_owner_recruitment_applications_v1()
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', application.id,
    'vacancy_id', application.vacancy_id,
    'first_name', application.first_name,
    'last_name', application.last_name,
    'email', application.email,
    'phone', application.phone,
    'motivation', application.motivation,
    'cv_storage_path', application.cv_storage_path,
    'status', application.status,
    'submitted_at', application.submitted_at,
    'created_at', application.created_at,
    'updated_at', application.updated_at
  ) order by application.submitted_at desc, application.id), '[]'::jsonb)
  into v_result
  from public.recruitment_applications as application;
  return v_result;
end;
$$;

revoke all on function public.finalize_recruitment_application_v1(uuid, uuid, text, text, text, text, text, text, text, bigint, text)
from public, anon, authenticated, service_role;
grant execute on function public.finalize_recruitment_application_v1(uuid, uuid, text, text, text, text, text, text, text, bigint, text)
to service_role;

revoke all on function public.list_owner_recruitment_applications_v1()
from public, anon, authenticated, service_role;
grant execute on function public.list_owner_recruitment_applications_v1()
to authenticated;

comment on function public.finalize_recruitment_application_v1(uuid, uuid, text, text, text, text, text, text, text, bigint, text) is
  'Service-only application finalizer requiring a validated private CV object and a currently published vacancy.';
comment on function public.list_owner_recruitment_applications_v1() is
  'Caller-JWT owner-only private recruitment application projection; CV retrieval remains separate and deferred.';
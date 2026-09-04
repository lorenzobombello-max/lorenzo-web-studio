alter table public.recruitment_applications
  alter column vacancy_id drop not null,
  add column application_type text not null default 'VACANCY',
  add column interest_area text,
  add column experience_skills text,
  add column portfolio_url text,
  add column availability text,
  add column privacy_consented_at timestamptz,
  add column workflow_status text not null default 'OPEN',
  add column linked_test_profile text,
  add column linked_test_candidate_id uuid references public.recruitment_test_candidates(candidate_id) on delete set null,
  add constraint recruitment_applications_type_valid check (application_type in ('VACANCY', 'OPEN_SOLLICITATIE')),
  add constraint recruitment_applications_source_valid check (
    (application_type = 'VACANCY' and vacancy_id is not null)
    or (application_type = 'OPEN_SOLLICITATIE' and vacancy_id is null)
  ),
  add constraint recruitment_applications_interest_valid check (
    interest_area is null or interest_area in ('Webdesign', 'Development', 'Security', 'SEO', 'Content', 'Administratie', 'Sales', 'HR', 'Finance', 'Anders')
  ),
  add constraint recruitment_applications_experience_valid check (
    experience_skills is null or (experience_skills = btrim(experience_skills) and length(experience_skills) between 1 and 5000)
  ),
  add constraint recruitment_applications_portfolio_valid check (
    portfolio_url is null or (portfolio_url = btrim(portfolio_url) and length(portfolio_url) between 1 and 500 and portfolio_url ~ '^https://')
  ),
  add constraint recruitment_applications_availability_valid check (
    availability is null or (availability = btrim(availability) and length(availability) between 1 and 1000)
  ),
  add constraint recruitment_applications_open_fields_valid check (
    application_type <> 'OPEN_SOLLICITATIE'
    or (interest_area is not null and experience_skills is not null and availability is not null and privacy_consented_at is not null)
  ),
  add constraint recruitment_applications_workflow_valid check (workflow_status in ('OPEN', 'BEWAARD', 'AFGEWEZEN', 'UITGENODIGD')),
  add constraint recruitment_applications_profile_valid check (
    linked_test_profile is null or linked_test_profile in ('Webdesign', 'Development', 'Security', 'SEO', 'Content')
  );

create function public.finalize_recruitment_open_application_v1(
  p_application_id uuid,
  p_first_name text,
  p_last_name text,
  p_email text,
  p_phone text,
  p_motivation text,
  p_interest_area text,
  p_experience_skills text,
  p_portfolio_url text,
  p_availability text,
  p_privacy_consent boolean,
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
  v_first_name text := btrim(p_first_name);
  v_last_name text := btrim(p_last_name);
  v_email text := lower(btrim(p_email));
  v_phone text := nullif(btrim(p_phone), '');
  v_motivation text := btrim(p_motivation);
  v_interest_area text := btrim(p_interest_area);
  v_experience_skills text := btrim(p_experience_skills);
  v_portfolio_url text := nullif(btrim(p_portfolio_url), '');
  v_availability text := btrim(p_availability);
  v_mime_type text := lower(btrim(p_cv_mime_type));
  v_sha256 text := btrim(p_cv_sha256);
  v_extension text;
  v_expected_path text;
  v_storage_metadata jsonb;
  v_storage_user_metadata jsonb;
  v_application public.recruitment_applications%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_APPLICATION_SERVICE_REQUIRED';
  end if;
  if p_application_id is null then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_APPLICATION_ID'; end if;
  if v_first_name is null or length(v_first_name) not between 1 and 100 then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_FIRST_NAME'; end if;
  if v_last_name is null or length(v_last_name) not between 1 and 100 then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_LAST_NAME'; end if;
  if v_email is null or length(v_email) not between 3 and 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_EMAIL'; end if;
  if v_phone is not null and length(v_phone) > 40 then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_PHONE'; end if;
  if v_motivation is null or length(v_motivation) not between 1 and 5000 then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_MOTIVATION'; end if;
  if v_interest_area not in ('Webdesign', 'Development', 'Security', 'SEO', 'Content', 'Administratie', 'Sales', 'HR', 'Finance', 'Anders') then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_INTEREST_AREA'; end if;
  if v_experience_skills is null or length(v_experience_skills) not between 1 and 5000 then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_EXPERIENCE'; end if;
  if v_portfolio_url is not null and (length(v_portfolio_url) > 500 or v_portfolio_url !~ '^https://') then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_PORTFOLIO_URL'; end if;
  if v_availability is null or length(v_availability) not between 1 and 1000 then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_AVAILABILITY'; end if;
  if p_privacy_consent is distinct from true then raise exception using errcode = '22023', message = 'RECRUITMENT_PRIVACY_CONSENT_REQUIRED'; end if;
  if v_mime_type not in ('application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_CV_MIME_TYPE'; end if;
  if p_cv_byte_count is null or p_cv_byte_count not between 1 and 10485760 then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_CV_BYTE_COUNT'; end if;
  if v_sha256 is null or v_sha256 !~ '^[0-9a-f]{64}$' then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_CV_SHA256'; end if;

  v_extension := case v_mime_type when 'application/pdf' then 'pdf' when 'application/msword' then 'doc' else 'docx' end;
  v_expected_path := 'applications/' || p_application_id::text || '/cv.' || v_extension;
  if p_cv_storage_path is distinct from v_expected_path then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_CV_STORAGE_PATH'; end if;
  select object.metadata, object.user_metadata into v_storage_metadata, v_storage_user_metadata from storage.objects as object
  where object.bucket_id = 'recruitment-cvs' and object.name = v_expected_path;
  if not found or coalesce(v_storage_metadata->>'mimetype', '') <> v_mime_type
     or coalesce(v_storage_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_storage_metadata->>'size')::bigint <> p_cv_byte_count
    or coalesce(v_storage_user_metadata->>'sha256', v_storage_metadata->>'sha256', '') <> v_sha256 then
    raise exception using errcode = 'P0001', message = 'RECRUITMENT_CV_OBJECT_MISMATCH';
  end if;

  insert into public.recruitment_applications (
    id, vacancy_id, application_type, first_name, last_name, email, phone, motivation,
    interest_area, experience_skills, portfolio_url, availability, privacy_consented_at,
    cv_storage_path, cv_mime_type, cv_byte_count, cv_sha256
  ) values (
    p_application_id, null, 'OPEN_SOLLICITATIE', v_first_name, v_last_name, v_email, v_phone, v_motivation,
    v_interest_area, v_experience_skills, v_portfolio_url, v_availability, clock_timestamp(),
    v_expected_path, v_mime_type, p_cv_byte_count, v_sha256
  ) returning * into v_application;
  return jsonb_build_object('id', v_application.id, 'status', v_application.status, 'submitted_at', v_application.submitted_at);
end;
$$;

create function public.list_owner_recruitment_open_applications_v1()
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
  select * into v_actor from public.commercial_operators where auth_user_id = auth.uid();
  if not found or v_actor.status <> 'ACTIVE' or v_actor.role <> 'owner' then raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', application.id, 'application_type', application.application_type,
    'first_name', application.first_name, 'last_name', application.last_name,
    'email', application.email, 'phone', application.phone, 'motivation', application.motivation,
    'interest_area', application.interest_area, 'experience_skills', application.experience_skills,
    'portfolio_url', application.portfolio_url, 'availability', application.availability,
    'cv_storage_path', application.cv_storage_path, 'workflow_status', application.workflow_status,
    'linked_test_profile', application.linked_test_profile,
    'linked_test_candidate_id', application.linked_test_candidate_id,
    'submitted_at', application.submitted_at, 'updated_at', application.updated_at
  ) order by application.submitted_at desc, application.id), '[]'::jsonb)
  into v_result from public.recruitment_applications as application
  where application.application_type = 'OPEN_SOLLICITATIE';
  return v_result;
end;
$$;

create function public.update_owner_recruitment_open_application_v1(
  p_application_id uuid,
  p_workflow_status text,
  p_linked_test_profile text default null,
  p_linked_test_candidate_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_actor public.commercial_operators%rowtype;
  v_application public.recruitment_applications%rowtype;
  v_status text := upper(btrim(p_workflow_status));
  v_profile text := nullif(btrim(p_linked_test_profile), '');
begin
  select * into v_actor from public.commercial_operators where auth_user_id = auth.uid();
  if not found or v_actor.status <> 'ACTIVE' or v_actor.role <> 'owner' then raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED'; end if;
  if v_status not in ('OPEN', 'BEWAARD', 'AFGEWEZEN', 'UITGENODIGD') then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_APPLICATION_STATUS'; end if;
  if v_profile is not null and v_profile not in ('Webdesign', 'Development', 'Security', 'SEO', 'Content') then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_TEST_PROFILE'; end if;
  if p_linked_test_candidate_id is not null and not exists (
    select 1 from public.recruitment_test_candidates candidate
    where candidate.candidate_id = p_linked_test_candidate_id and candidate.email = (select email from public.recruitment_applications where id = p_application_id)
  ) then raise exception using errcode = '22023', message = 'INVALID_RECRUITMENT_TEST_CANDIDATE'; end if;
  update public.recruitment_applications set
    workflow_status = v_status,
    linked_test_profile = coalesce(v_profile, linked_test_profile),
    linked_test_candidate_id = coalesce(p_linked_test_candidate_id, linked_test_candidate_id)
  where id = p_application_id and application_type = 'OPEN_SOLLICITATIE'
  returning * into v_application;
  if not found then raise exception using errcode = 'P0002', message = 'RECRUITMENT_OPEN_APPLICATION_NOT_FOUND'; end if;
  return jsonb_build_object(
    'id', v_application.id, 'workflow_status', v_application.workflow_status,
    'linked_test_profile', v_application.linked_test_profile,
    'linked_test_candidate_id', v_application.linked_test_candidate_id,
    'updated_at', v_application.updated_at
  );
end;
$$;

create policy recruitment_cvs_owner_read_v1 on storage.objects
for select to authenticated
using (
  bucket_id = 'recruitment-cvs'
  and exists (
    select 1 from public.commercial_operators operator
    where operator.auth_user_id = auth.uid() and operator.status = 'ACTIVE' and operator.role = 'owner'
  )
);

revoke all on function public.finalize_recruitment_open_application_v1(uuid, text, text, text, text, text, text, text, text, text, boolean, text, text, bigint, text) from public, anon, authenticated, service_role;
grant execute on function public.finalize_recruitment_open_application_v1(uuid, text, text, text, text, text, text, text, text, text, boolean, text, text, bigint, text) to service_role;
revoke all on function public.list_owner_recruitment_open_applications_v1() from public, anon, authenticated, service_role;
grant execute on function public.list_owner_recruitment_open_applications_v1() to authenticated;
revoke all on function public.update_owner_recruitment_open_application_v1(uuid, text, text, uuid) from public, anon, authenticated, service_role;
grant execute on function public.update_owner_recruitment_open_application_v1(uuid, text, text, uuid) to authenticated;

comment on function public.finalize_recruitment_open_application_v1(uuid, text, text, text, text, text, text, text, text, text, boolean, text, text, bigint, text) is
  'Service-only open application finalizer with validated private CV evidence and explicit privacy consent.';
comment on function public.list_owner_recruitment_open_applications_v1() is
  'Owner-only projection for spontaneous Recruitment applications; no HR or contract authority.';
comment on function public.update_owner_recruitment_open_application_v1(uuid, text, text, uuid) is
  'Owner-only Recruitment disposition and optional existing test-candidate linkage; no hiring authority.';
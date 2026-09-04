create table public.recruitment_test_catalog (
  test_id uuid primary key default gen_random_uuid(),
  test_code text not null unique check (test_code ~ '^TEST-[A-Z0-9-]{2,32}$'),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  test_profile text not null check (char_length(btrim(test_profile)) between 1 and 120),
  instructions text not null check (char_length(btrim(instructions)) between 1 and 2000),
  questions jsonb not null check (jsonb_typeof(questions) = 'array' and jsonb_array_length(questions) between 1 and 20),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'ARCHIVED')),
  created_at timestamptz not null default clock_timestamp()
);

create table public.recruitment_test_candidates (
  candidate_id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  email text not null check (email = lower(btrim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  test_profile text not null check (char_length(btrim(test_profile)) between 1 and 120),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'ARCHIVED')),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table public.recruitment_test_assignments (
  assignment_id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.recruitment_test_candidates(candidate_id) on delete restrict,
  test_id uuid not null references public.recruitment_test_catalog(test_id) on delete restrict,
  capability_digest bytea not null unique check (octet_length(capability_digest) = 32),
  status text not null check (status in ('GEPLAND', 'BESCHIKBAAR', 'BEZIG', 'INGEDIEND', 'BEOORDEELD')),
  draft_answers jsonb not null default '{}'::jsonb check (jsonb_typeof(draft_answers) = 'object'),
  submitted_answers jsonb check (submitted_answers is null or jsonb_typeof(submitted_answers) = 'object'),
  review_notes text,
  assigned_by_operator_id uuid not null references public.commercial_operators(operator_id),
  planned_at timestamptz not null default clock_timestamp(),
  available_at timestamptz,
  started_at timestamptz,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  unique (candidate_id, test_id),
  constraint recruitment_test_assignment_status_shape check (
    (status = 'GEPLAND' and available_at is null and started_at is null and submitted_at is null and reviewed_at is null and submitted_answers is null)
    or (status = 'BESCHIKBAAR' and available_at is not null and started_at is null and submitted_at is null and reviewed_at is null and submitted_answers is null)
    or (status = 'BEZIG' and available_at is not null and started_at is not null and submitted_at is null and reviewed_at is null and submitted_answers is null)
    or (status = 'INGEDIEND' and available_at is not null and started_at is not null and submitted_at is not null and reviewed_at is null and submitted_answers is not null)
    or (status = 'BEOORDEELD' and available_at is not null and started_at is not null and submitted_at is not null and reviewed_at is not null and submitted_answers is not null)
  )
);

create table public.recruitment_test_history (
  history_id bigint generated always as identity primary key,
  assignment_id uuid not null references public.recruitment_test_assignments(assignment_id) on delete restrict,
  from_status text,
  to_status text not null check (to_status in ('GEPLAND', 'BESCHIKBAAR', 'BEZIG', 'INGEDIEND', 'BEOORDEELD')),
  actor_type text not null check (actor_type in ('OWNER', 'CANDIDATE')),
  occurred_at timestamptz not null default clock_timestamp()
);

create function public.prevent_recruitment_test_history_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'RECRUITMENT_TEST_HISTORY_APPEND_ONLY';
end;
$$;

create trigger trg_recruitment_test_history_append_only
before update or delete on public.recruitment_test_history
for each row execute function public.prevent_recruitment_test_history_mutation_v1();

alter table public.recruitment_test_catalog enable row level security;
alter table public.recruitment_test_catalog force row level security;
alter table public.recruitment_test_candidates enable row level security;
alter table public.recruitment_test_candidates force row level security;
alter table public.recruitment_test_assignments enable row level security;
alter table public.recruitment_test_assignments force row level security;
alter table public.recruitment_test_history enable row level security;
alter table public.recruitment_test_history force row level security;

revoke all on table public.recruitment_test_catalog from public, anon, authenticated, service_role;
revoke all on table public.recruitment_test_candidates from public, anon, authenticated, service_role;
revoke all on table public.recruitment_test_assignments from public, anon, authenticated, service_role;
revoke all on table public.recruitment_test_history from public, anon, authenticated, service_role;
revoke all on sequence public.recruitment_test_history_history_id_seq from public, anon, authenticated, service_role;

insert into public.recruitment_test_catalog (test_code, title, test_profile, instructions, questions)
values
  (
    'TEST-COMMUNICATIE',
    'Klantgerichte communicatie',
    'Communicatie',
    'Beantwoord beide praktijksituaties helder en professioneel. Gebruik geen echte klant- of productiegegevens.',
    '[{"id":"response","label":"Schrijf een antwoord aan een klant die om een duidelijke statusupdate vraagt.","type":"textarea"},{"id":"reflection","label":"Welke drie principes heb je in je antwoord toegepast?","type":"textarea"}]'::jsonb
  ),
  (
    'TEST-PRIORITEITEN',
    'Prioriteiten en operations',
    'HR & Operations',
    'Beschrijf je aanpak op basis van de fictieve situatie. Gebruik geen echte medewerker- of productiegegevens.',
    '[{"id":"plan","label":"Drie taken komen tegelijk binnen. Beschrijf je prioritering en eerste acties.","type":"textarea"},{"id":"escalation","label":"Wanneer en hoe escaleer je?","type":"textarea"}]'::jsonb
  );

create function public.list_owner_recruitment_tests_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_owner public.commercial_operators%rowtype;
begin
  select * into v_owner from public.commercial_operators
  where auth_user_id = auth.uid() and status = 'ACTIVE';
  if not found or v_owner.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'test_id', test_id,
      'test_code', test_code,
      'title', title,
      'test_profile', test_profile,
      'instructions', instructions,
      'questions', questions,
      'status', status
    ) order by title)
    from public.recruitment_test_catalog
    where status = 'ACTIVE'
  ), '[]'::jsonb);
end;
$$;

create function public.create_recruitment_test_candidate_v1(
  p_name text,
  p_email text,
  p_test_profile text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_owner public.commercial_operators%rowtype;
  v_candidate public.recruitment_test_candidates%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_profile text := btrim(coalesce(p_test_profile, ''));
begin
  select * into v_owner from public.commercial_operators
  where auth_user_id = auth.uid() and status = 'ACTIVE';
  if not found or v_owner.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;
  if char_length(v_name) not between 1 and 120
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or char_length(v_profile) not between 1 and 120 then
    raise exception using errcode = '22023', message = 'RECRUITMENT_CANDIDATE_INVALID';
  end if;

  insert into public.recruitment_test_candidates (name, email, test_profile, created_by_operator_id)
  values (v_name, v_email, v_profile, v_owner.operator_id)
  returning * into v_candidate;

  return jsonb_build_object(
    'candidate_id', v_candidate.candidate_id,
    'name', v_candidate.name,
    'email', v_candidate.email,
    'test_profile', v_candidate.test_profile,
    'status', v_candidate.status,
    'created_at', v_candidate.created_at
  );
end;
$$;

create function public.assign_recruitment_candidate_test_v1(
  p_candidate_id uuid,
  p_test_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, extensions, pg_catalog
as $$
declare
  v_owner public.commercial_operators%rowtype;
  v_candidate public.recruitment_test_candidates%rowtype;
  v_test public.recruitment_test_catalog%rowtype;
  v_assignment public.recruitment_test_assignments%rowtype;
  v_token text := encode(gen_random_bytes(32), 'hex');
begin
  select * into v_owner from public.commercial_operators
  where auth_user_id = auth.uid() and status = 'ACTIVE';
  if not found or v_owner.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;
  select * into v_candidate from public.recruitment_test_candidates
  where candidate_id = p_candidate_id and status = 'ACTIVE';
  if not found then raise exception using errcode = '23503', message = 'RECRUITMENT_CANDIDATE_NOT_FOUND'; end if;
  select * into v_test from public.recruitment_test_catalog
  where test_id = p_test_id and status = 'ACTIVE';
  if not found then raise exception using errcode = '23503', message = 'RECRUITMENT_TEST_NOT_FOUND'; end if;

  insert into public.recruitment_test_assignments (
    candidate_id, test_id, capability_digest, status, assigned_by_operator_id
  ) values (
    v_candidate.candidate_id, v_test.test_id, digest(v_token, 'sha256'), 'GEPLAND', v_owner.operator_id
  ) returning * into v_assignment;
  insert into public.recruitment_test_history (assignment_id, from_status, to_status, actor_type)
  values (v_assignment.assignment_id, null, 'GEPLAND', 'OWNER');
  update public.recruitment_test_assignments
  set status = 'BESCHIKBAAR', available_at = clock_timestamp(), updated_at = clock_timestamp()
  where assignment_id = v_assignment.assignment_id
  returning * into v_assignment;
  insert into public.recruitment_test_history (assignment_id, from_status, to_status, actor_type)
  values (v_assignment.assignment_id, 'GEPLAND', 'BESCHIKBAAR', 'OWNER');

  return jsonb_build_object(
    'assignment_id', v_assignment.assignment_id,
    'candidate_id', v_candidate.candidate_id,
    'test_id', v_test.test_id,
    'status', v_assignment.status,
    'access_token', v_token
  );
end;
$$;

create function public.list_owner_recruitment_candidate_tests_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_owner public.commercial_operators%rowtype;
begin
  select * into v_owner from public.commercial_operators
  where auth_user_id = auth.uid() and status = 'ACTIVE';
  if not found or v_owner.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'candidate_id', candidate.candidate_id,
      'name', candidate.name,
      'email', candidate.email,
      'test_profile', candidate.test_profile,
      'candidate_status', candidate.status,
      'assignment_id', assignment.assignment_id,
      'test_id', test.test_id,
      'test_code', test.test_code,
      'test_title', test.title,
      'assignment_status', assignment.status,
      'draft_answers', assignment.draft_answers,
      'submitted_answers', assignment.submitted_answers,
      'review_notes', assignment.review_notes,
      'planned_at', assignment.planned_at,
      'available_at', assignment.available_at,
      'started_at', assignment.started_at,
      'submitted_at', assignment.submitted_at,
      'reviewed_at', assignment.reviewed_at,
      'history', coalesce((
        select jsonb_agg(jsonb_build_object(
          'from_status', history.from_status,
          'to_status', history.to_status,
          'actor_type', history.actor_type,
          'occurred_at', history.occurred_at
        ) order by history.history_id)
        from public.recruitment_test_history as history
        where history.assignment_id = assignment.assignment_id
      ), '[]'::jsonb)
    ) order by candidate.created_at desc)
    from public.recruitment_test_candidates as candidate
    left join public.recruitment_test_assignments as assignment on assignment.candidate_id = candidate.candidate_id
    left join public.recruitment_test_catalog as test on test.test_id = assignment.test_id
  ), '[]'::jsonb);
end;
$$;

create function public.review_recruitment_candidate_test_v1(
  p_assignment_id uuid,
  p_review_notes text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_owner public.commercial_operators%rowtype;
  v_assignment public.recruitment_test_assignments%rowtype;
  v_notes text := btrim(coalesce(p_review_notes, ''));
begin
  select * into v_owner from public.commercial_operators
  where auth_user_id = auth.uid() and status = 'ACTIVE';
  if not found or v_owner.role <> 'owner' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED';
  end if;
  if char_length(v_notes) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'RECRUITMENT_REVIEW_INVALID';
  end if;
  select * into v_assignment from public.recruitment_test_assignments
  where assignment_id = p_assignment_id for update;
  if not found then raise exception using errcode = '23503', message = 'RECRUITMENT_ASSIGNMENT_NOT_FOUND'; end if;
  if v_assignment.status <> 'INGEDIEND' then
    raise exception using errcode = '55000', message = 'RECRUITMENT_ASSIGNMENT_NOT_SUBMITTED';
  end if;

  update public.recruitment_test_assignments
  set status = 'BEOORDEELD', review_notes = v_notes, reviewed_at = clock_timestamp(), updated_at = clock_timestamp()
  where assignment_id = v_assignment.assignment_id
  returning * into v_assignment;
  insert into public.recruitment_test_history (assignment_id, from_status, to_status, actor_type)
  values (v_assignment.assignment_id, 'INGEDIEND', 'BEOORDEELD', 'OWNER');

  return jsonb_build_object('assignment_id', v_assignment.assignment_id, 'status', v_assignment.status, 'reviewed_at', v_assignment.reviewed_at);
end;
$$;

create function public.get_recruitment_candidate_test_v1(p_access_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_assignment public.recruitment_test_assignments%rowtype;
  v_candidate public.recruitment_test_candidates%rowtype;
  v_test public.recruitment_test_catalog%rowtype;
  v_token text := btrim(coalesce(p_access_token, ''));
  v_previous_status text;
begin
  if v_token !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '42501', message = 'RECRUITMENT_CANDIDATE_ACCESS_DENIED';
  end if;
  select * into v_assignment from public.recruitment_test_assignments
  where capability_digest = digest(v_token, 'sha256') for update;
  if not found then raise exception using errcode = '42501', message = 'RECRUITMENT_CANDIDATE_ACCESS_DENIED'; end if;
  if v_assignment.status = 'GEPLAND' then raise exception using errcode = '42501', message = 'RECRUITMENT_TEST_NOT_AVAILABLE'; end if;

  if v_assignment.status = 'BESCHIKBAAR' then
    v_previous_status := v_assignment.status;
    update public.recruitment_test_assignments
    set status = 'BEZIG', started_at = clock_timestamp(), updated_at = clock_timestamp()
    where assignment_id = v_assignment.assignment_id
    returning * into v_assignment;
    insert into public.recruitment_test_history (assignment_id, from_status, to_status, actor_type)
    values (v_assignment.assignment_id, v_previous_status, 'BEZIG', 'CANDIDATE');
  end if;

  select * into v_candidate from public.recruitment_test_candidates where candidate_id = v_assignment.candidate_id;
  select * into v_test from public.recruitment_test_catalog where test_id = v_assignment.test_id;
  return jsonb_build_object(
    'assignment_id', v_assignment.assignment_id,
    'candidate_id', v_candidate.candidate_id,
    'candidate_name', v_candidate.name,
    'test_profile', v_candidate.test_profile,
    'test_code', v_test.test_code,
    'test_title', v_test.title,
    'instructions', v_test.instructions,
    'questions', v_test.questions,
    'status', v_assignment.status,
    'draft_answers', v_assignment.draft_answers,
    'submitted_answers', v_assignment.submitted_answers,
    'started_at', v_assignment.started_at,
    'submitted_at', v_assignment.submitted_at
  );
end;
$$;

create function public.save_recruitment_candidate_test_v1(p_access_token text, p_answers jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_assignment public.recruitment_test_assignments%rowtype;
  v_token text := btrim(coalesce(p_access_token, ''));
begin
  if v_token !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_answers) <> 'object' or pg_column_size(p_answers) > 65536 then
    raise exception using errcode = '22023', message = 'RECRUITMENT_TEST_SAVE_INVALID';
  end if;
  select * into v_assignment from public.recruitment_test_assignments
  where capability_digest = digest(v_token, 'sha256') for update;
  if not found then raise exception using errcode = '42501', message = 'RECRUITMENT_CANDIDATE_ACCESS_DENIED'; end if;
  if v_assignment.status <> 'BEZIG' then raise exception using errcode = '55000', message = 'RECRUITMENT_TEST_NOT_EDITABLE'; end if;

  update public.recruitment_test_assignments
  set draft_answers = p_answers, updated_at = clock_timestamp()
  where assignment_id = v_assignment.assignment_id
  returning * into v_assignment;
  return jsonb_build_object('assignment_id', v_assignment.assignment_id, 'status', v_assignment.status, 'saved_at', v_assignment.updated_at);
end;
$$;

create function public.submit_recruitment_candidate_test_v1(p_access_token text, p_answers jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_assignment public.recruitment_test_assignments%rowtype;
  v_test public.recruitment_test_catalog%rowtype;
  v_token text := btrim(coalesce(p_access_token, ''));
begin
  if v_token !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_answers) <> 'object' or pg_column_size(p_answers) > 65536 then
    raise exception using errcode = '22023', message = 'RECRUITMENT_TEST_SUBMISSION_INVALID';
  end if;
  select * into v_assignment from public.recruitment_test_assignments
  where capability_digest = digest(v_token, 'sha256') for update;
  if not found then raise exception using errcode = '42501', message = 'RECRUITMENT_CANDIDATE_ACCESS_DENIED'; end if;
  if v_assignment.status <> 'BEZIG' then raise exception using errcode = '55000', message = 'RECRUITMENT_TEST_NOT_EDITABLE'; end if;
  select * into v_test from public.recruitment_test_catalog where test_id = v_assignment.test_id;
  if exists (
    select 1 from jsonb_array_elements(v_test.questions) as question
    where nullif(btrim(p_answers ->> (question ->> 'id')), '') is null
  ) then
    raise exception using errcode = '22023', message = 'RECRUITMENT_TEST_ANSWERS_INCOMPLETE';
  end if;

  update public.recruitment_test_assignments
  set status = 'INGEDIEND', draft_answers = p_answers, submitted_answers = p_answers,
      submitted_at = clock_timestamp(), updated_at = clock_timestamp()
  where assignment_id = v_assignment.assignment_id
  returning * into v_assignment;
  insert into public.recruitment_test_history (assignment_id, from_status, to_status, actor_type)
  values (v_assignment.assignment_id, 'BEZIG', 'INGEDIEND', 'CANDIDATE');
  return jsonb_build_object('assignment_id', v_assignment.assignment_id, 'status', v_assignment.status, 'submitted_at', v_assignment.submitted_at);
end;
$$;

revoke all on function public.list_owner_recruitment_tests_v1() from public, anon, service_role;
revoke all on function public.create_recruitment_test_candidate_v1(text, text, text) from public, anon, service_role;
revoke all on function public.assign_recruitment_candidate_test_v1(uuid, uuid) from public, anon, service_role;
revoke all on function public.list_owner_recruitment_candidate_tests_v1() from public, anon, service_role;
revoke all on function public.review_recruitment_candidate_test_v1(uuid, text) from public, anon, service_role;
grant execute on function public.list_owner_recruitment_tests_v1() to authenticated;
grant execute on function public.create_recruitment_test_candidate_v1(text, text, text) to authenticated;
grant execute on function public.assign_recruitment_candidate_test_v1(uuid, uuid) to authenticated;
grant execute on function public.list_owner_recruitment_candidate_tests_v1() to authenticated;
grant execute on function public.review_recruitment_candidate_test_v1(uuid, text) to authenticated;

revoke all on function public.get_recruitment_candidate_test_v1(text) from public, service_role;
revoke all on function public.save_recruitment_candidate_test_v1(text, jsonb) from public, service_role;
revoke all on function public.submit_recruitment_candidate_test_v1(text, jsonb) from public, service_role;
grant execute on function public.get_recruitment_candidate_test_v1(text) to anon, authenticated;
grant execute on function public.save_recruitment_candidate_test_v1(text, jsonb) to anon, authenticated;
grant execute on function public.submit_recruitment_candidate_test_v1(text, jsonb) to anon, authenticated;

comment on table public.recruitment_test_assignments is
  'Capability-isolated candidate test assignments. Raw access tokens are never stored.';
comment on table public.recruitment_test_history is
  'Append-only Recruitment test status history; direct table access is denied to all API roles.';
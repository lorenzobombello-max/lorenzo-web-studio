alter table public.recruitment_test_assignments
  add column invitation_sent_at timestamptz;

create table public.recruitment_test_assignment_items (
  assignment_id uuid not null references public.recruitment_test_assignments(assignment_id) on delete restrict,
  test_id uuid not null references public.recruitment_test_catalog(test_id) on delete restrict,
  position smallint not null check (position between 1 and 5),
  primary key (assignment_id, test_id),
  unique (assignment_id, position)
);

create table public.recruitment_candidate_invitation_email_jobs (
  job_id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique references public.recruitment_test_assignments(assignment_id) on delete restrict,
  encrypted_capability text not null check (encrypted_capability ~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{107}$'),
  template_version text not null check (template_version = 'RECRUITMENT_CANDIDATE_INVITATION_NL_BE_v1'),
  status text not null default 'pending' check (status in ('pending','processing','sent','retry_wait','failed')),
  attempt_count smallint not null default 0 check (attempt_count between 0 and 10),
  next_attempt_at timestamptz not null default clock_timestamp(),
  delivery_lease_token uuid,
  delivery_lease_expires_at timestamptz,
  provider_message_id text,
  last_error_code text,
  created_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  constraint recruitment_invitation_job_state_shape check (
    (status = 'processing' and delivery_lease_token is not null and delivery_lease_expires_at is not null)
    or (status <> 'processing' and delivery_lease_token is null and delivery_lease_expires_at is null)
  )
);

alter table public.recruitment_test_assignment_items enable row level security;
alter table public.recruitment_test_assignment_items force row level security;
alter table public.recruitment_candidate_invitation_email_jobs enable row level security;
alter table public.recruitment_candidate_invitation_email_jobs force row level security;
revoke all on table public.recruitment_test_assignment_items from public, anon, authenticated, service_role;
revoke all on table public.recruitment_candidate_invitation_email_jobs from public, anon, authenticated, service_role;

create function public.prevent_recruitment_test_assignment_item_mutation_v2()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception using errcode = '55000', message = 'RECRUITMENT_TEST_SELECTION_IMMUTABLE';
end;
$$;

create trigger trg_recruitment_test_assignment_items_immutable
before update or delete on public.recruitment_test_assignment_items
for each row execute function public.prevent_recruitment_test_assignment_item_mutation_v2();

insert into public.recruitment_test_catalog (test_code, title, test_profile, instructions, questions)
values
  ('TEST-WEB-VISUEEL','Visuele hiërarchie','Webdesign','Werk vanuit de fictieve briefing en motiveer uw keuzes.','[{"id":"approach","label":"Beschrijf de visuele hiërarchie voor een zakelijke homepage.","type":"textarea"}]'),
  ('TEST-WEB-UX','Gebruikersroute','Webdesign','Werk vanuit de fictieve briefing en motiveer uw keuzes.','[{"id":"approach","label":"Ontwerp de stappen van bezoeker naar contactaanvraag.","type":"textarea"}]'),
  ('TEST-WEB-RESP','Responsive ontwerp','Webdesign','Werk vanuit de fictieve briefing en motiveer uw keuzes.','[{"id":"approach","label":"Leg uit hoe u dit ontwerp voor mobiel laat werken.","type":"textarea"}]'),
  ('TEST-WEB-ACC','Toegankelijk ontwerp','Webdesign','Werk vanuit de fictieve briefing en motiveer uw keuzes.','[{"id":"approach","label":"Welke toegankelijkheidskeuzes past u toe en waarom?","type":"textarea"}]'),
  ('TEST-WEB-SYSTEM','Design system','Webdesign','Werk vanuit de fictieve briefing en motiveer uw keuzes.','[{"id":"approach","label":"Schets de componenten en tokens van een klein design system.","type":"textarea"}]'),
  ('TEST-DEV-API','API-integratie','Development','Beschrijf een veilige en onderhoudbare technische aanpak.','[{"id":"approach","label":"Hoe bouwt en test u een robuuste API-integratie?","type":"textarea"}]'),
  ('TEST-DEV-DATA','Datamodellering','Development','Beschrijf een veilige en onderhoudbare technische aanpak.','[{"id":"approach","label":"Modelleer kandidaten, opdrachten en resultaten met integriteitsregels.","type":"textarea"}]'),
  ('TEST-DEV-DEBUG','Probleemanalyse','Development','Beschrijf een veilige en onderhoudbare technische aanpak.','[{"id":"approach","label":"Beschrijf uw aanpak voor een moeilijk reproduceerbare fout.","type":"textarea"}]'),
  ('TEST-DEV-TEST','Teststrategie','Development','Beschrijf een veilige en onderhoudbare technische aanpak.','[{"id":"approach","label":"Welke testlagen kiest u voor een kritieke workflow?","type":"textarea"}]'),
  ('TEST-DEV-PERF','Performance','Development','Beschrijf een veilige en onderhoudbare technische aanpak.','[{"id":"approach","label":"Hoe onderzoekt en verhelpt u een trage webapplicatie?","type":"textarea"}]'),
  ('TEST-SEC-THREAT','Threat modeling','Security','Gebruik uitsluitend fictieve gegevens en beschrijf verdedigingsmaatregelen.','[{"id":"approach","label":"Maak een beknopt dreigingsmodel voor een kandidaatportaal.","type":"textarea"}]'),
  ('TEST-SEC-AUTH','Authenticatie','Security','Gebruik uitsluitend fictieve gegevens en beschrijf verdedigingsmaatregelen.','[{"id":"approach","label":"Beoordeel een passwordless authenticatiestroom en de risico’s.","type":"textarea"}]'),
  ('TEST-SEC-INC','Incidentrespons','Security','Gebruik uitsluitend fictieve gegevens en beschrijf verdedigingsmaatregelen.','[{"id":"approach","label":"Wat zijn uw eerste acties bij een vermoedelijk datalek?","type":"textarea"}]'),
  ('TEST-SEC-REVIEW','Code review','Security','Gebruik uitsluitend fictieve gegevens en beschrijf verdedigingsmaatregelen.','[{"id":"approach","label":"Welke kwetsbaarheden zoekt u in een uploadfunctie?","type":"textarea"}]'),
  ('TEST-SEC-SECRETS','Secretsbeheer','Security','Gebruik uitsluitend fictieve gegevens en beschrijf verdedigingsmaatregelen.','[{"id":"approach","label":"Ontwerp veilig secretsbeheer voor lokaal, CI en productie.","type":"textarea"}]'),
  ('TEST-SEO-TECH','Technische SEO','SEO','Analyseer de fictieve situatie en maak uw prioriteiten concreet.','[{"id":"approach","label":"Welke technische controles voert u eerst uit bij dalend organisch verkeer?","type":"textarea"}]'),
  ('TEST-SEO-INTENT','Zoekintentie','SEO','Analyseer de fictieve situatie en maak uw prioriteiten concreet.','[{"id":"approach","label":"Vertaal drie zoekintenties naar passende landingspagina’s.","type":"textarea"}]'),
  ('TEST-SEO-LOCAL','Lokale vindbaarheid','SEO','Analyseer de fictieve situatie en maak uw prioriteiten concreet.','[{"id":"approach","label":"Maak een actieplan voor lokale vindbaarheid van een dienstverlener.","type":"textarea"}]'),
  ('TEST-SEO-MEASURE','SEO-meting','SEO','Analyseer de fictieve situatie en maak uw prioriteiten concreet.','[{"id":"approach","label":"Welke KPI’s en controles gebruikt u om SEO-impact te meten?","type":"textarea"}]'),
  ('TEST-SEO-CONTENT','Contentoptimalisatie','SEO','Analyseer de fictieve situatie en maak uw prioriteiten concreet.','[{"id":"approach","label":"Verbeter de structuur van een inhoudelijk zwakke dienstenpagina.","type":"textarea"}]'),
  ('TEST-CONT-BRIEF','Contentbriefing','Content','Schrijf of motiveer op basis van een volledig fictieve context.','[{"id":"approach","label":"Maak een bruikbare briefing voor een nieuwe dienstenpagina.","type":"textarea"}]'),
  ('TEST-CONT-TONE','Tone of voice','Content','Schrijf of motiveer op basis van een volledig fictieve context.','[{"id":"approach","label":"Herschrijf een formele boodschap in een heldere menselijke toon.","type":"textarea"}]'),
  ('TEST-CONT-EDIT','Redactie','Content','Schrijf of motiveer op basis van een volledig fictieve context.','[{"id":"approach","label":"Beschrijf uw redactieronde voor juistheid, structuur en stijl.","type":"textarea"}]'),
  ('TEST-CONT-CTA','Conversietekst','Content','Schrijf of motiveer op basis van een volledig fictieve context.','[{"id":"approach","label":"Schrijf en motiveer een CTA voor een zakelijke dienstenpagina.","type":"textarea"}]'),
  ('TEST-CONT-PLAN','Contentplanning','Content','Schrijf of motiveer op basis van een volledig fictieve context.','[{"id":"approach","label":"Maak een beknopt contentplan voor vier weken.","type":"textarea"}]');

create function public.create_recruitment_candidate_invitation_v2(
  p_owner_auth_user_id uuid,
  p_name text,
  p_email text,
  p_test_profile text,
  p_capability_digest text,
  p_encrypted_capability text
)
returns jsonb language plpgsql volatile security definer
set search_path = public, auth, extensions, pg_catalog as $$
declare
  v_owner public.commercial_operators%rowtype;
  v_candidate public.recruitment_test_candidates%rowtype;
  v_assignment public.recruitment_test_assignments%rowtype;
  v_job public.recruitment_candidate_invitation_email_jobs%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_profile text := btrim(coalesce(p_test_profile, ''));
  v_salt bytea := gen_random_bytes(32);
  v_count integer := 4 + (get_byte(gen_random_bytes(1), 0) % 2);
  v_test_ids uuid[];
begin
  select * into v_owner from public.commercial_operators
  where auth_user_id = p_owner_auth_user_id and status = 'ACTIVE' and role = 'owner';
  if not found then raise exception using errcode = '42501', message = 'RECRUITMENT_OWNER_REQUIRED'; end if;
  if char_length(v_name) not between 1 and 120
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or v_profile not in ('Webdesign','Development','Security','SEO','Content')
    or p_capability_digest !~ '^[0-9a-f]{64}$'
    or p_encrypted_capability !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{107}$' then
    raise exception using errcode = '22023', message = 'RECRUITMENT_INVITATION_INVALID';
  end if;

  select array_agg(chosen.test_id order by chosen.rank) into v_test_ids
  from (
    select test_id, row_number() over (order by digest(uuid_send(test_id) || v_salt, 'sha256')) as rank
    from public.recruitment_test_catalog
    where status = 'ACTIVE' and test_profile = v_profile
    order by digest(uuid_send(test_id) || v_salt, 'sha256')
    limit v_count
  ) chosen;
  if coalesce(array_length(v_test_ids, 1), 0) <> v_count then
    raise exception using errcode = '55000', message = 'RECRUITMENT_TEST_BANK_INSUFFICIENT';
  end if;

  insert into public.recruitment_test_candidates (name, email, test_profile, created_by_operator_id)
  values (v_name, v_email, v_profile, v_owner.operator_id) returning * into v_candidate;
  insert into public.recruitment_test_assignments (
    candidate_id, test_id, capability_digest, status, assigned_by_operator_id
  ) values (
    v_candidate.candidate_id, v_test_ids[1], decode(p_capability_digest,'hex'), 'GEPLAND', v_owner.operator_id
  ) returning * into v_assignment;
  insert into public.recruitment_test_assignment_items (assignment_id, test_id, position)
  select v_assignment.assignment_id, selected.test_id, selected.position::smallint
  from unnest(v_test_ids) with ordinality selected(test_id, position);
  insert into public.recruitment_test_history (assignment_id, from_status, to_status, actor_type)
  values (v_assignment.assignment_id, null, 'GEPLAND', 'OWNER');
  update public.recruitment_test_assignments
  set status = 'BESCHIKBAAR', available_at = clock_timestamp(), updated_at = clock_timestamp()
  where assignment_id = v_assignment.assignment_id returning * into v_assignment;
  insert into public.recruitment_test_history (assignment_id, from_status, to_status, actor_type)
  values (v_assignment.assignment_id, 'GEPLAND', 'BESCHIKBAAR', 'OWNER');
  insert into public.recruitment_candidate_invitation_email_jobs (
    assignment_id, encrypted_capability, template_version
  ) values (
    v_assignment.assignment_id, p_encrypted_capability, 'RECRUITMENT_CANDIDATE_INVITATION_NL_BE_v1'
  ) returning * into v_job;

  return jsonb_build_object(
    'candidate_id', v_candidate.candidate_id,
    'assignment_id', v_assignment.assignment_id,
    'job_id', v_job.job_id,
    'selection_count', v_count,
    'status', v_assignment.status
  );
end;
$$;

create function public.claim_recruitment_candidate_invitation_email_v2(p_job_id uuid)
returns jsonb language plpgsql volatile security definer
set search_path = public, pg_catalog as $$
declare
  v_job public.recruitment_candidate_invitation_email_jobs%rowtype;
begin
  select * into v_job from public.recruitment_candidate_invitation_email_jobs
  where job_id = p_job_id for update;
  if not found then raise exception using errcode = '23503', message = 'RECRUITMENT_INVITATION_JOB_NOT_FOUND'; end if;
  if v_job.status = 'sent' then return jsonb_build_object('outcome','already_sent'); end if;
  if v_job.status = 'processing' and v_job.delivery_lease_expires_at > clock_timestamp() then
    return jsonb_build_object('outcome','processing');
  end if;
  if v_job.status = 'failed' or v_job.attempt_count >= 10 or v_job.next_attempt_at > clock_timestamp() then
    return jsonb_build_object('outcome',v_job.status);
  end if;
  update public.recruitment_candidate_invitation_email_jobs
  set status = 'processing', attempt_count = attempt_count + 1,
      delivery_lease_token = gen_random_uuid(), delivery_lease_expires_at = clock_timestamp() + interval '5 minutes'
  where job_id = v_job.job_id returning * into v_job;
  return (
    select jsonb_build_object(
      'outcome','claimed', 'job_id',v_job.job_id, 'assignment_id',assignment.assignment_id,
      'candidate_name',candidate.name, 'candidate_email',candidate.email,
      'test_profile',candidate.test_profile, 'selection_count',count(item.test_id),
      'capability_digest',encode(assignment.capability_digest,'hex'),
      'encrypted_capability',v_job.encrypted_capability,
      'delivery_lease_token',v_job.delivery_lease_token,
      'attempt_count',v_job.attempt_count,
      'template_version',v_job.template_version
    )
    from public.recruitment_test_assignments assignment
    join public.recruitment_test_candidates candidate using (candidate_id)
    join public.recruitment_test_assignment_items item using (assignment_id)
    where assignment.assignment_id = v_job.assignment_id
    group by assignment.assignment_id, candidate.candidate_id
  );
end;
$$;

create function public.complete_recruitment_candidate_invitation_email_v2(
  p_job_id uuid,
  p_delivery_lease_token uuid,
  p_succeeded boolean,
  p_retryable boolean,
  p_error_code text,
  p_provider_message_id text
)
returns jsonb language plpgsql volatile security definer
set search_path = public, pg_catalog as $$
declare
  v_job public.recruitment_candidate_invitation_email_jobs%rowtype;
  v_status text;
begin
  select * into v_job from public.recruitment_candidate_invitation_email_jobs
  where job_id = p_job_id for update;
  if not found or v_job.status <> 'processing' or v_job.delivery_lease_token <> p_delivery_lease_token
    or v_job.delivery_lease_expires_at <= clock_timestamp() then
    raise exception using errcode = '55000', message = 'RECRUITMENT_INVITATION_LEASE_INVALID';
  end if;
  v_status := case when p_succeeded then 'sent' when p_retryable and v_job.attempt_count < 10 then 'retry_wait' else 'failed' end;
  update public.recruitment_candidate_invitation_email_jobs
  set status = v_status, delivery_lease_token = null, delivery_lease_expires_at = null,
      next_attempt_at = case when v_status = 'retry_wait' then clock_timestamp() + make_interval(secs => least(3600, 30 * power(2, v_job.attempt_count - 1)::integer)) else next_attempt_at end,
      provider_message_id = case when p_succeeded then nullif(btrim(p_provider_message_id),'') else null end,
      last_error_code = case when p_succeeded then null else nullif(btrim(p_error_code),'') end,
      sent_at = case when p_succeeded then clock_timestamp() else null end
  where job_id = v_job.job_id returning * into v_job;
  if p_succeeded then
    update public.recruitment_test_assignments set invitation_sent_at = v_job.sent_at
    where assignment_id = v_job.assignment_id and invitation_sent_at is null;
  end if;
  return jsonb_build_object('job_id',v_job.job_id,'status',v_job.status,'attempt_count',v_job.attempt_count,'sent_at',v_job.sent_at);
end;
$$;

create or replace function public.list_owner_recruitment_candidate_tests_v1()
returns jsonb language plpgsql stable security definer
set search_path = public, auth, pg_catalog as $$
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
      'candidate_id',candidate.candidate_id, 'name',candidate.name, 'email',candidate.email,
      'test_profile',candidate.test_profile, 'candidate_status',candidate.status,
      'assignment_id',assignment.assignment_id, 'assignment_status',assignment.status,
      'selected_tests',coalesce((
        select jsonb_agg(jsonb_build_object('test_id',test.test_id,'test_code',test.test_code,'title',test.title,'position',item.position) order by item.position)
        from public.recruitment_test_assignment_items item
        join public.recruitment_test_catalog test using (test_id)
        where item.assignment_id = assignment.assignment_id
      ),'[]'::jsonb),
      'invitation_status',job.status, 'invitation_sent_at',assignment.invitation_sent_at,
      'draft_answers',assignment.draft_answers, 'submitted_answers',assignment.submitted_answers,
      'review_notes',assignment.review_notes, 'planned_at',assignment.planned_at,
      'available_at',assignment.available_at, 'started_at',assignment.started_at,
      'submitted_at',assignment.submitted_at, 'reviewed_at',assignment.reviewed_at,
      'history',coalesce((
        select jsonb_agg(jsonb_build_object('from_status',history.from_status,'to_status',history.to_status,'actor_type',history.actor_type,'occurred_at',history.occurred_at) order by history.history_id)
        from public.recruitment_test_history history where history.assignment_id = assignment.assignment_id
      ),'[]'::jsonb)
    ) order by candidate.created_at desc)
    from public.recruitment_test_candidates candidate
    left join public.recruitment_test_assignments assignment using (candidate_id)
    left join public.recruitment_candidate_invitation_email_jobs job using (assignment_id)
  ),'[]'::jsonb);
end;
$$;

create or replace function public.get_recruitment_candidate_test_v1(p_access_token text)
returns jsonb language plpgsql volatile security definer
set search_path = public, extensions, pg_catalog as $$
declare
  v_assignment public.recruitment_test_assignments%rowtype;
  v_candidate public.recruitment_test_candidates%rowtype;
  v_token text := btrim(coalesce(p_access_token, ''));
begin
  if v_token !~ '^[0-9a-f]{64}$' then raise exception using errcode = '42501', message = 'RECRUITMENT_CANDIDATE_ACCESS_DENIED'; end if;
  select * into v_assignment from public.recruitment_test_assignments
  where capability_digest = digest(v_token, 'sha256') for update;
  if not found then raise exception using errcode = '42501', message = 'RECRUITMENT_CANDIDATE_ACCESS_DENIED'; end if;
  if v_assignment.status = 'GEPLAND' then raise exception using errcode = '42501', message = 'RECRUITMENT_TEST_NOT_AVAILABLE'; end if;
  if v_assignment.status = 'BESCHIKBAAR' then
    update public.recruitment_test_assignments
    set status = 'BEZIG', started_at = clock_timestamp(), updated_at = clock_timestamp()
    where assignment_id = v_assignment.assignment_id returning * into v_assignment;
    insert into public.recruitment_test_history (assignment_id,from_status,to_status,actor_type)
    values (v_assignment.assignment_id,'BESCHIKBAAR','BEZIG','CANDIDATE');
  end if;
  select * into v_candidate from public.recruitment_test_candidates where candidate_id = v_assignment.candidate_id;
  return jsonb_build_object(
    'assignment_id',v_assignment.assignment_id, 'candidate_id',v_candidate.candidate_id,
    'candidate_name',v_candidate.name, 'test_profile',v_candidate.test_profile,
    'tests',coalesce((
      select jsonb_agg(jsonb_build_object(
        'test_code',test.test_code, 'title',test.title, 'instructions',test.instructions,
        'questions',test.questions
      ) order by item.position)
      from public.recruitment_test_assignment_items item
      join public.recruitment_test_catalog test using (test_id)
      where item.assignment_id = v_assignment.assignment_id
    ),'[]'::jsonb),
    'status',v_assignment.status, 'draft_answers',v_assignment.draft_answers,
    'submitted_answers',v_assignment.submitted_answers,
    'started_at',v_assignment.started_at, 'submitted_at',v_assignment.submitted_at
  );
end;
$$;

create or replace function public.submit_recruitment_candidate_test_v1(p_access_token text,p_answers jsonb)
returns jsonb language plpgsql volatile security definer
set search_path = public, extensions, pg_catalog as $$
declare
  v_assignment public.recruitment_test_assignments%rowtype;
  v_token text := btrim(coalesce(p_access_token, ''));
begin
  if v_token !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_answers) <> 'object' or pg_column_size(p_answers) > 262144 then
    raise exception using errcode = '22023', message = 'RECRUITMENT_TEST_SUBMISSION_INVALID';
  end if;
  select * into v_assignment from public.recruitment_test_assignments
  where capability_digest = digest(v_token,'sha256') for update;
  if not found then raise exception using errcode = '42501', message = 'RECRUITMENT_CANDIDATE_ACCESS_DENIED'; end if;
  if v_assignment.status <> 'BEZIG' then raise exception using errcode = '55000', message = 'RECRUITMENT_TEST_NOT_EDITABLE'; end if;
  if exists (
    select 1 from public.recruitment_test_assignment_items item
    join public.recruitment_test_catalog test using (test_id)
    cross join lateral jsonb_array_elements(test.questions) question
    where item.assignment_id = v_assignment.assignment_id
      and nullif(btrim(p_answers ->> (test.test_code || '__' || (question ->> 'id'))),'') is null
  ) then raise exception using errcode = '22023', message = 'RECRUITMENT_TEST_ANSWERS_INCOMPLETE'; end if;
  update public.recruitment_test_assignments
  set status='INGEDIEND',draft_answers=p_answers,submitted_answers=p_answers,
      submitted_at=clock_timestamp(),updated_at=clock_timestamp()
  where assignment_id=v_assignment.assignment_id returning * into v_assignment;
  insert into public.recruitment_test_history (assignment_id,from_status,to_status,actor_type)
  values (v_assignment.assignment_id,'BEZIG','INGEDIEND','CANDIDATE');
  return jsonb_build_object('assignment_id',v_assignment.assignment_id,'status',v_assignment.status,'submitted_at',v_assignment.submitted_at);
end;
$$;

create or replace function public.save_recruitment_candidate_test_v1(p_access_token text,p_answers jsonb)
returns jsonb language plpgsql volatile security definer
set search_path = public, extensions, pg_catalog as $$
declare
  v_assignment public.recruitment_test_assignments%rowtype;
  v_token text := btrim(coalesce(p_access_token, ''));
begin
  if v_token !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_answers) <> 'object' or pg_column_size(p_answers) > 262144 then
    raise exception using errcode = '22023', message = 'RECRUITMENT_TEST_SAVE_INVALID';
  end if;
  select * into v_assignment from public.recruitment_test_assignments
  where capability_digest = digest(v_token,'sha256') for update;
  if not found then raise exception using errcode = '42501', message = 'RECRUITMENT_CANDIDATE_ACCESS_DENIED'; end if;
  if v_assignment.status <> 'BEZIG' then raise exception using errcode = '55000', message = 'RECRUITMENT_TEST_NOT_EDITABLE'; end if;
  update public.recruitment_test_assignments set draft_answers=p_answers,updated_at=clock_timestamp()
  where assignment_id=v_assignment.assignment_id returning * into v_assignment;
  return jsonb_build_object('assignment_id',v_assignment.assignment_id,'status',v_assignment.status,'saved_at',v_assignment.updated_at);
end;
$$;

revoke all on function public.create_recruitment_candidate_invitation_v2(uuid,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.claim_recruitment_candidate_invitation_email_v2(uuid) from public, anon, authenticated;
revoke all on function public.complete_recruitment_candidate_invitation_email_v2(uuid,uuid,boolean,boolean,text,text) from public, anon, authenticated;
grant execute on function public.create_recruitment_candidate_invitation_v2(uuid,text,text,text,text,text) to service_role;
grant execute on function public.claim_recruitment_candidate_invitation_email_v2(uuid) to service_role;
grant execute on function public.complete_recruitment_candidate_invitation_email_v2(uuid,uuid,boolean,boolean,text,text) to service_role;
revoke execute on function public.create_recruitment_test_candidate_v1(text,text,text) from authenticated;
revoke execute on function public.assign_recruitment_candidate_test_v1(uuid,uuid) from authenticated;

comment on table public.recruitment_test_assignment_items is
  'Immutable server-selected test set. Candidates and operators cannot add, remove, reorder, or replace selected tests.';
comment on table public.recruitment_candidate_invitation_email_jobs is
  'Lease-based Recruitment invitation delivery authority. Contains only encrypted capability escrow; raw tokens are never persisted.';
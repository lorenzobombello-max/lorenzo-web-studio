alter table public.quote_requests
  add column support_reference text
  generated always as ('#' || upper(left(id::text, 8))) stored;

alter table public.quote_requests
  add constraint quote_requests_support_reference_format_valid
  check (support_reference ~ '^#[0-9A-F]{8}$');

do $$
begin
  if exists (
    select 1
    from public.quote_requests
    group by support_reference
    having count(*) > 1
  ) then
    raise exception using errcode = '23505', message = 'AMBIGUOUS_LEGACY_SUPPORT_REFERENCE';
  end if;
end;
$$;

alter table public.quote_requests
  add constraint quote_requests_support_reference_unique unique (support_reference);

create function public.normalize_quote_request_support_reference_v1(
  p_support_reference text
)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_reference text := upper(btrim(p_support_reference));
begin
  if v_reference ~ '^[0-9A-F]{8}$' then
    v_reference := '#' || v_reference;
  end if;
  if v_reference !~ '^#[0-9A-F]{8}$' then
    raise exception using errcode = '22023', message = 'INVALID_SUPPORT_REFERENCE';
  end if;
  return v_reference;
end;
$$;

create table public.commercial_project_sites (
  site_id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.commercial_projects(project_id),
  site_revision bigint not null check (site_revision > 0),
  previous_site_id uuid,
  operation text not null check (operation in ('INITIAL_BIND', 'ROTATION')),
  canonical_domain text not null,
  canonical_url text generated always as ('https://' || canonical_domain) stored,
  expected_revision bigint not null check (expected_revision >= 0),
  idempotency_key uuid not null,
  evidence text not null check (char_length(btrim(evidence)) between 1 and 500),
  actor_operator_id uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  constraint commercial_project_sites_project_site_unique unique (project_id, site_id),
  constraint commercial_project_sites_previous_same_project foreign key (project_id, previous_site_id)
    references public.commercial_project_sites(project_id, site_id),
  constraint commercial_project_sites_revision_unique unique (project_id, site_revision),
  constraint commercial_project_sites_idempotency_unique unique (project_id, idempotency_key),
  constraint commercial_project_sites_version_shape check (
    (site_revision = 1 and previous_site_id is null and operation = 'INITIAL_BIND' and expected_revision = 0)
    or (site_revision > 1 and previous_site_id is not null and operation = 'ROTATION' and expected_revision = site_revision - 1)
  ),
  constraint commercial_project_sites_domain_canonical check (
    canonical_domain = lower(canonical_domain)
    and canonical_domain ~ '^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'
  )
);

create function public.prevent_commercial_project_site_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'PROJECT_SITE_BINDING_IMMUTABLE';
end;
$$;

create trigger trg_commercial_project_sites_immutable
before update or delete on public.commercial_project_sites
for each row execute function public.prevent_commercial_project_site_mutation();

alter table public.commercial_project_sites enable row level security;
alter table public.commercial_project_sites force row level security;

create function public.execute_operator_project_site_command_v1(
  p_project_id uuid,
  p_operation text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_canonical_domain text,
  p_evidence text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_auth record;
  v_project public.commercial_projects%rowtype;
  v_current public.commercial_project_sites%rowtype;
  v_existing public.commercial_project_sites%rowtype;
  v_created public.commercial_project_sites%rowtype;
  v_domain text := btrim(p_canonical_domain);
  v_evidence text := btrim(p_evidence);
begin
  if p_operation not in ('INITIAL_BIND', 'ROTATION')
     or p_expected_revision is null or p_expected_revision < 0
     or p_idempotency_key is null
     or v_domain is null
     or v_domain <> lower(v_domain)
     or v_domain !~ '^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'
     or v_evidence is null
     or char_length(v_evidence) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_PROJECT_SITE_COMMAND';
  end if;

  select * into strict v_auth
  from public.resolve_commercial_operator_authorization_v1(p_project_id, 'READ_PROJECT', false);
  if v_auth.operator_role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'PROJECT_SITE_OWNER_ADMIN_REQUIRED';
  end if;

  select * into v_project
  from public.commercial_projects
  where project_id = p_project_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'PROJECT_NOT_FOUND';
  end if;

  select * into v_existing
  from public.commercial_project_sites
  where project_id = p_project_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation <> p_operation
       or v_existing.expected_revision <> p_expected_revision
       or v_existing.canonical_domain <> v_domain
       or v_existing.evidence <> v_evidence
       or v_existing.actor_operator_id <> v_auth.operator_id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'site_id', v_existing.site_id,
      'project_id', v_existing.project_id,
      'site_revision', v_existing.site_revision,
      'canonical_domain', v_existing.canonical_domain,
      'canonical_url', v_existing.canonical_url,
      'operation', v_existing.operation,
      'created_at', v_existing.created_at
    );
  end if;

  select * into v_current
  from public.commercial_project_sites
  where project_id = p_project_id
  order by site_revision desc
  limit 1;

  if p_operation = 'INITIAL_BIND' and v_current.site_id is not null then
    raise exception using errcode = 'P0001', message = 'PROJECT_SITE_ALREADY_BOUND';
  end if;
  if p_operation = 'ROTATION' and v_current.site_id is null then
    raise exception using errcode = 'P0001', message = 'PROJECT_SITE_NOT_BOUND';
  end if;
  if p_expected_revision <> coalesce(v_current.site_revision, 0) then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  insert into public.commercial_project_sites(
    project_id, site_revision, previous_site_id, operation, canonical_domain,
    expected_revision, idempotency_key, evidence, actor_operator_id
  ) values (
    p_project_id, p_expected_revision + 1, v_current.site_id, p_operation, v_domain,
    p_expected_revision, p_idempotency_key, v_evidence, v_auth.operator_id
  ) returning * into v_created;

  return jsonb_build_object(
    'site_id', v_created.site_id,
    'project_id', v_created.project_id,
    'site_revision', v_created.site_revision,
    'canonical_domain', v_created.canonical_domain,
    'canonical_url', v_created.canonical_url,
    'operation', v_created.operation,
    'created_at', v_created.created_at
  );
end;
$$;

alter function public.list_operator_applications_v1(integer, integer)
  rename to list_operator_applications_v1_pre_support_reference;

create function public.list_operator_applications_v1(
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
  select coalesce(jsonb_agg(
    application.value || jsonb_build_object('support_reference', request.support_reference)
    order by application.ordinality
  ), '[]'::jsonb)
  from jsonb_array_elements(
    public.list_operator_applications_v1_pre_support_reference(p_limit, p_offset)
  ) with ordinality as application(value, ordinality)
  join public.quote_requests as request
    on request.id = (application.value->>'quote_request_id')::uuid
$$;

alter function public.get_operator_application_v1(uuid, text)
  rename to get_operator_application_v1_pre_support_site;

alter function public.get_commercial_project_view_v2(uuid)
  rename to get_commercial_project_view_v2_pre_project_site;

create function public.get_commercial_project_view_v2(p_project_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
  select public.get_commercial_project_view_v2_pre_project_site(p_project_id)
    || jsonb_build_object('site', (
      select jsonb_build_object(
        'site_id', site.site_id,
        'project_id', site.project_id,
        'site_revision', site.site_revision,
        'canonical_domain', site.canonical_domain,
        'canonical_url', site.canonical_url,
        'created_at', site.created_at
      )
      from public.commercial_project_sites as site
      where site.project_id = p_project_id
      order by site.site_revision desc
      limit 1
    ))
$$;

create function public.get_operator_application_v1(
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_result jsonb;
  v_support_reference text;
  v_site public.commercial_project_sites%rowtype;
begin
  v_result := public.get_operator_application_v1_pre_support_site(
    p_quote_request_id,
    p_application_reference
  );

  select request.support_reference into strict v_support_reference
  from public.quote_requests as request
  where request.id = (v_result->>'quote_request_id')::uuid;

  if v_result->>'request_kind' = 'website'
     and nullif(v_result->'project'->>'project_id', '') is not null then
    select site.* into v_site
    from public.commercial_project_sites as site
    where site.project_id = (v_result->'project'->>'project_id')::uuid
    order by site.site_revision desc
    limit 1;
  end if;

  return v_result || jsonb_build_object(
    'support_reference', v_support_reference,
    'project_site', case when v_site.site_id is null then null else jsonb_build_object(
      'site_id', v_site.site_id,
      'project_id', v_site.project_id,
      'site_revision', v_site.site_revision,
      'canonical_domain', v_site.canonical_domain,
      'canonical_url', v_site.canonical_url,
      'created_at', v_site.created_at
    ) end
  );
end;
$$;

create function public.get_operator_application_by_support_reference_v1(
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
  v_operator public.commercial_operators%rowtype;
  v_reference text;
  v_quote_request_id uuid;
  v_match_count integer;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;

  v_reference := public.normalize_quote_request_support_reference_v1(p_support_reference);
  select count(*), min(request.id::text)::uuid
  into v_match_count, v_quote_request_id
  from public.quote_requests as request
  where request.support_reference = v_reference;

  if v_match_count = 0 then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_FOUND';
  end if;
  if v_match_count > 1 then
    raise exception using errcode = 'P0001', message = 'AMBIGUOUS_SUPPORT_REFERENCE';
  end if;
  return public.get_operator_application_v1(v_quote_request_id, null);
end;
$$;

revoke all privileges on table public.commercial_project_sites
from public, anon, authenticated, service_role;
revoke all on function public.prevent_commercial_project_site_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.execute_operator_project_site_command_v1(uuid, text, bigint, uuid, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.normalize_quote_request_support_reference_v1(text)
from public, anon, authenticated, service_role;
revoke all on function public.list_operator_applications_v1_pre_support_reference(integer, integer)
from public, anon, authenticated, service_role;
revoke all on function public.list_operator_applications_v1(integer, integer)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_v1_pre_support_site(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_commercial_project_view_v2_pre_project_site(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_commercial_project_view_v2(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_v1(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_by_support_reference_v1(text)
from public, anon, authenticated, service_role;

grant execute on function public.list_operator_applications_v1(integer, integer)
to authenticated;
grant execute on function public.get_operator_application_v1(uuid, text)
to authenticated;
grant execute on function public.get_commercial_project_view_v2(uuid)
to authenticated;
grant execute on function public.get_operator_application_by_support_reference_v1(text)
to authenticated;
grant execute on function public.execute_operator_project_site_command_v1(uuid, text, bigint, uuid, text, text)
to authenticated;

comment on column public.quote_requests.support_reference is
  'Persistent customer/support locator preserving the legacy uppercase first-eight UUID reference. It is not authorization authority.';
comment on table public.commercial_project_sites is
  'Private append-only project-site version history. Intake website and domain fields remain separate request evidence.';
comment on function public.execute_operator_project_site_command_v1(uuid, text, bigint, uuid, text, text) is
  'Owner/admin-only initial bind and controlled rotation command with idempotency and optimistic concurrency.';
comment on function public.get_operator_application_by_support_reference_v1(text) is
  'Owner/admin-only exact support-reference lookup. Ambiguous legacy prefixes fail closed.';
comment on function public.get_commercial_project_view_v2(uuid) is
  'Server-authorized project dossier read model with its exact immutable project-site binding.';
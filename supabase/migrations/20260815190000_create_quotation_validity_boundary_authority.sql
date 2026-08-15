create table public.quotation_validity_boundary_authorities (
  authority_version smallint primary key check (authority_version = 1),
  validity_timezone text not null check (validity_timezone = 'Europe/Brussels'),
  valid_until_semantics text not null
    check (valid_until_semantics = 'INCLUSIVE_CALENDAR_DATE'),
  acceptance_deadline_rule text not null
    check (acceptance_deadline_rule = 'NEXT_LOCAL_DAY_00_00_EXCLUSIVE'),
  created_at timestamptz not null default clock_timestamp(),
  created_by text not null check (nullif(btrim(created_by), '') is not null)
);

insert into public.quotation_validity_boundary_authorities (
  authority_version, validity_timezone, valid_until_semantics,
  acceptance_deadline_rule, created_by
) values (
  1, 'Europe/Brussels', 'INCLUSIVE_CALENDAR_DATE',
  'NEXT_LOCAL_DAY_00_00_EXCLUSIVE', 'checkpoint:D3E8A'
);

create function public.prevent_quotation_validity_authority_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000',
    message = 'QUOTATION_VALIDITY_AUTHORITY_IMMUTABLE';
end;
$$;

create trigger trg_quotation_validity_authority_immutable
before update or delete on public.quotation_validity_boundary_authorities
for each row execute function public.prevent_quotation_validity_authority_mutation();

create function public.quotation_validity_boundary_authority_v1()
returns public.quotation_validity_boundary_authorities
language sql
stable
security definer
set search_path = public
as $$
  select authority
  from public.quotation_validity_boundary_authorities as authority
  where authority.authority_version = 1
$$;

create function public.quotation_acceptance_deadline_v1(p_valid_until date)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_timezone text;
begin
  if p_valid_until is null then
    raise exception using errcode = '22023', message = 'VALID_UNTIL_INVALID';
  end if;
  select authority.validity_timezone into strict v_timezone
  from public.quotation_validity_boundary_authorities as authority
  where authority.authority_version = 1;
  return (p_valid_until + 1)::timestamp at time zone v_timezone;
end;
$$;

create function public.is_quotation_within_validity_at_v1(
  p_valid_until date,
  p_server_now timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_server_now is null then
    raise exception using errcode = '22023', message = 'SERVER_TIME_INVALID';
  end if;
  return p_server_now < public.quotation_acceptance_deadline_v1(p_valid_until);
end;
$$;

create function public.quotation_issuance_acceptance_deadline_v1(
  p_issuance_id uuid
)
returns table (
  valid_until date,
  validity_timezone text,
  acceptance_deadline_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_valid_until date;
begin
  select (approval.approved_payload->'validity'->>'valid_until')::date
  into v_valid_until
  from public.quote_request_quotation_issuances as issuance
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  where issuance.id = p_issuance_id
    and issuance.status = 'ISSUED';
  if not found then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_ELIGIBLE';
  end if;
  return query
  select v_valid_until, authority.validity_timezone,
    public.quotation_acceptance_deadline_v1(v_valid_until)
  from public.quotation_validity_boundary_authorities as authority
  where authority.authority_version = 1;
end;
$$;

create function public.is_quotation_within_validity_v1(p_issuance_id uuid)
returns boolean
language sql
volatile
security definer
set search_path = public
as $$
  select clock_timestamp() < deadline.acceptance_deadline_at
  from public.quotation_issuance_acceptance_deadline_v1(p_issuance_id) as deadline
$$;

alter table public.quotation_validity_boundary_authorities enable row level security;
revoke all privileges on table public.quotation_validity_boundary_authorities
from public, anon, authenticated, service_role;

revoke all on function public.prevent_quotation_validity_authority_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.quotation_validity_boundary_authority_v1()
from public, anon, authenticated;
revoke all on function public.quotation_acceptance_deadline_v1(date)
from public, anon, authenticated;
revoke all on function public.is_quotation_within_validity_at_v1(date,timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.quotation_issuance_acceptance_deadline_v1(uuid)
from public, anon, authenticated;
revoke all on function public.is_quotation_within_validity_v1(uuid)
from public, anon, authenticated;

grant execute on function public.quotation_validity_boundary_authority_v1()
to service_role;
grant execute on function public.quotation_acceptance_deadline_v1(date)
to service_role;
grant execute on function public.quotation_issuance_acceptance_deadline_v1(uuid)
to service_role;
grant execute on function public.is_quotation_within_validity_v1(uuid)
to service_role;

comment on table public.quotation_validity_boundary_authorities is
  'Versioned immutable business authority: valid_until is an inclusive Europe/Brussels calendar date; acceptance expires at next local midnight. valid_from remains document/contract metadata and is not an acceptance eligibility gate in v1.';
comment on function public.quotation_acceptance_deadline_v1(date) is
  'Derives the exclusive TIMESTAMPTZ acceptance deadline from the v1 calendar date and immutable Europe/Brussels timezone authority. Callers cannot supply timezone or cutoff.';
comment on function public.is_quotation_within_validity_at_v1(date,timestamptz) is
  'Database-owner test helper only. It accepts an injected clock for deterministic boundary tests and is revoked from service_role, authenticated, and anon. Production acceptance must call is_quotation_within_validity_v1(uuid).';
comment on function public.is_quotation_within_validity_v1(uuid) is
  'Production eligibility helper, deliberately VOLATILE because it uses database-controlled clock_timestamp at execution. Only ISSUED quotations resolve. valid_from remains a document/contract date and is not an acceptance gate in v1.';
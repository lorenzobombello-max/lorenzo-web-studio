create table public.change_request_template_authorities (
  id uuid primary key default gen_random_uuid(),
  template_id text not null,
  template_version text not null,
  document_type text not null check (document_type = 'CHANGE_REQUEST'),
  product_families text[] not null check (
    product_families = array['WEBSITE','SLIMME_DOCUMENTENFLOW']::text[]
  ),
  canonical_filename text not null check (nullif(btrim(canonical_filename), '') is not null),
  repository_asset_path text not null check (nullif(btrim(repository_asset_path), '') is not null),
  template_sha256 char(64) not null check (template_sha256 ~ '^[0-9A-F]{64}$'),
  status text not null check (status in ('CURRENT', 'SUPERSEDED')),
  authority_reference text not null check (nullif(btrim(authority_reference), '') is not null),
  created_at timestamptz not null default clock_timestamp(),
  created_by text not null check (nullif(btrim(created_by), '') is not null),
  constraint change_request_template_authority_version_unique
    unique (template_id, template_version)
);

create unique index change_request_template_authority_one_current
on public.change_request_template_authorities (document_type)
where status = 'CURRENT';

create function public.prevent_change_request_template_authority_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'CHANGE_REQUEST_TEMPLATE_AUTHORITY_IMMUTABLE';
end;
$$;

create trigger trg_change_request_template_authority_immutable
before update or delete on public.change_request_template_authorities
for each row execute function public.prevent_change_request_template_authority_mutation();

create function public.resolve_current_change_request_template_v1(
  p_document_type text
)
returns public.change_request_template_authorities
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_template public.change_request_template_authorities%rowtype;
begin
  select count(*) into v_count
  from public.change_request_template_authorities
  where document_type = p_document_type
    and status = 'CURRENT';

  if v_count <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'CHANGE_REQUEST_TEMPLATE_NOT_CURRENT';
  end if;

  select * into strict v_template
  from public.change_request_template_authorities
  where document_type = p_document_type
    and status = 'CURRENT';

  return v_template;
end;
$$;

alter table public.change_request_template_authorities enable row level security;
alter table public.change_request_template_authorities force row level security;

revoke all privileges on table public.change_request_template_authorities
from public, anon, authenticated, service_role;
revoke all on function public.prevent_change_request_template_authority_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.resolve_current_change_request_template_v1(text)
from public, anon, authenticated;

grant execute on function public.resolve_current_change_request_template_v1(text)
to service_role;

insert into public.change_request_template_authorities (
  template_id,
  template_version,
  document_type,
  product_families,
  canonical_filename,
  repository_asset_path,
  template_sha256,
  status,
  authority_reference,
  created_by
) values (
  'LWS_CHANGE_REQUEST_NL_BE',
  'v2',
  'CHANGE_REQUEST',
  array['WEBSITE','SLIMME_DOCUMENTENFLOW']::text[],
  '08_Wijzigingsverzoek_ChangeRequest_v2.docx',
  'assets/docs/change-request/08_Wijzigingsverzoek_ChangeRequest_v2.docx',
  '671C2BD8512F7C222271464B2269C65826680CC822D8B4DCE8A0DEA9A6DC9271',
  'CURRENT',
  'LWS_COMMERCIAL_AUTHORITY_INDEX.md#CR-01',
  'checkpoint:CHANGE_REQUEST_V2_TEMPLATE_AUTHORITY'
);

comment on table public.change_request_template_authorities is
  'Immutable identity authority for the existing CURRENT/CANONICAL Change Request v2 template; no document generation or business lifecycle mutation.';
comment on function public.resolve_current_change_request_template_v1(text) is
  'Fails closed unless exactly one CURRENT Change Request template matches the requested document type.';
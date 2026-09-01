alter table public.document_inbox_customer_request_upload_sources
  add constraint document_inbox_upload_source_requirement_binding_unique
  unique (uploaded_file_id, quote_request_id, document_inbox_item_id);

create table public.sdf_document_requirements (
  requirement_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  document_type text not null check (document_type in (
    'quotation', 'invoice', 'order_confirmation', 'work_order',
    'delivery_note', 'contract', 'customer_document', 'supplier_document',
    'internal_administrative_document', 'multiple_document_types',
    'other_custom', 'unknown_qualification_required'
  )),
  required_count integer not null check (required_count > 0),
  requirement_status text not null default 'REQUIRED' check (requirement_status = 'REQUIRED'),
  source text not null default 'OPERATOR' check (source = 'OPERATOR'),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (requirement_id, quote_request_id),
  unique (quote_request_id, document_type)
);

create table public.sdf_document_requirement_evidence (
  evidence_id uuid primary key default gen_random_uuid(),
  requirement_id uuid not null,
  quote_request_id uuid not null,
  uploaded_file_id uuid not null,
  document_inbox_item_id uuid not null,
  bound_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  bound_at timestamptz not null default clock_timestamp(),
  unique (uploaded_file_id),
  unique (requirement_id, uploaded_file_id),
  foreign key (requirement_id, quote_request_id)
    references public.sdf_document_requirements(requirement_id, quote_request_id) on delete restrict,
  foreign key (uploaded_file_id, quote_request_id, document_inbox_item_id)
    references public.document_inbox_customer_request_upload_sources(
      uploaded_file_id, quote_request_id, document_inbox_item_id
    ) on delete restrict
);

create index sdf_document_requirements_dossier_idx
on public.sdf_document_requirements(quote_request_id, document_type, requirement_id);

create index sdf_document_requirement_evidence_requirement_idx
on public.sdf_document_requirement_evidence(requirement_id, evidence_id);

alter table public.sdf_document_requirements enable row level security;
alter table public.sdf_document_requirements force row level security;
alter table public.sdf_document_requirement_evidence enable row level security;
alter table public.sdf_document_requirement_evidence force row level security;

revoke all on table public.sdf_document_requirements,
  public.sdf_document_requirement_evidence
from public, anon, authenticated, service_role;

create function lws_internal.reject_sdf_document_requirement_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'SDF_DOCUMENT_REQUIREMENT_HISTORY_IMMUTABLE';
end;
$$;

create trigger trg_sdf_document_requirements_immutable
before update or delete on public.sdf_document_requirements
for each row execute function lws_internal.reject_sdf_document_requirement_mutation_v1();

create trigger trg_sdf_document_requirement_evidence_immutable
before update or delete on public.sdf_document_requirement_evidence
for each row execute function lws_internal.reject_sdf_document_requirement_mutation_v1();

create function lws_internal.get_sdf_document_requirements_v1(p_quote_request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'requirements', coalesce(jsonb_agg(
      jsonb_build_object(
        'requirement_id', requirement.requirement_id,
        'document_type', requirement.document_type,
        'required_count', requirement.required_count,
        'valid_evidence_count', requirement.valid_evidence_count,
        'status', case
          when requirement.valid_evidence_count >= requirement.required_count then 'SATISFIED'
          else 'REQUIRED'
        end
      ) order by requirement.document_type, requirement.requirement_id
    ), '[]'::jsonb)
  )
  from (
    select
      required.requirement_id,
      required.document_type,
      required.required_count,
      count(evidence.evidence_id) filter (
        where uploaded.status = 'ACCEPTED'
          and inbox.lifecycle_status in ('RECEIVED', 'REVIEW_REQUIRED', 'APPROVED', 'PROCESSED')
      )::integer as valid_evidence_count
    from public.sdf_document_requirements required
    left join public.sdf_document_requirement_evidence evidence
      on evidence.requirement_id = required.requirement_id
     and evidence.quote_request_id = required.quote_request_id
    left join public.customer_request_uploaded_files uploaded
      on uploaded.uploaded_file_id = evidence.uploaded_file_id
    left join public.document_inbox_items inbox
      on inbox.id = evidence.document_inbox_item_id
    where required.quote_request_id = p_quote_request_id
    group by required.requirement_id, required.document_type, required.required_count
  ) requirement
$$;

create function public.create_sdf_document_requirement_v1(
  p_quote_request_id uuid,
  p_document_type text,
  p_required_count integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_requirement public.sdf_document_requirements%rowtype;
begin
  v_operator := lws_internal.assert_sdf_owner_v1();
  if p_quote_request_id is null
     or p_document_type is null
     or p_document_type not in (
       'quotation', 'invoice', 'order_confirmation', 'work_order',
       'delivery_note', 'contract', 'customer_document', 'supplier_document',
       'internal_administrative_document', 'multiple_document_types',
       'other_custom', 'unknown_qualification_required'
     )
     or p_required_count is null
     or p_required_count <= 0 then
    raise exception using errcode = '22023', message = 'INVALID_SDF_DOCUMENT_REQUIREMENT';
  end if;

  if not exists (
    select 1
    from public.quote_requests
    where id = p_quote_request_id
      and request_kind = 'slimme_documentenflow'
      and record_classification = 'production'
  ) then
    raise exception using errcode = '23514', message = 'SDF_PRODUCTION_DOSSIER_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_quote_request_id::text || ':' || p_document_type, 0));
  if exists (
    select 1 from public.sdf_document_requirements
    where quote_request_id = p_quote_request_id and document_type = p_document_type
  ) then
    raise exception using errcode = '23505', message = 'SDF_DOCUMENT_REQUIREMENT_EXISTS';
  end if;

  insert into public.sdf_document_requirements(
    quote_request_id, document_type, required_count, created_by_operator_id
  ) values (
    p_quote_request_id, p_document_type, p_required_count, v_operator.operator_id
  ) returning * into v_requirement;

  return jsonb_build_object(
    'requirement_id', v_requirement.requirement_id,
    'quote_request_id', v_requirement.quote_request_id,
    'document_type', v_requirement.document_type,
    'required_count', v_requirement.required_count,
    'status', v_requirement.requirement_status,
    'source', v_requirement.source
  );
end;
$$;

create function public.bind_sdf_document_requirement_evidence_v1(
  p_requirement_id uuid,
  p_uploaded_file_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_requirement public.sdf_document_requirements%rowtype;
  v_source public.document_inbox_customer_request_upload_sources%rowtype;
  v_uploaded public.customer_request_uploaded_files%rowtype;
  v_inbox public.document_inbox_items%rowtype;
  v_existing public.sdf_document_requirement_evidence%rowtype;
  v_evidence public.sdf_document_requirement_evidence%rowtype;
  v_state jsonb;
begin
  v_operator := lws_internal.assert_sdf_owner_v1();
  if p_requirement_id is null or p_uploaded_file_id is null then
    raise exception using errcode = '22023', message = 'INVALID_SDF_DOCUMENT_REQUIREMENT_EVIDENCE';
  end if;

  select * into v_requirement
  from public.sdf_document_requirements
  where requirement_id = p_requirement_id
  for share;
  if not found then
    raise exception using errcode = 'P0002', message = 'SDF_DOCUMENT_REQUIREMENT_NOT_FOUND';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_uploaded_file_id::text, 0));
  select * into v_existing
  from public.sdf_document_requirement_evidence
  where uploaded_file_id = p_uploaded_file_id;
  if found then
    if v_existing.requirement_id <> p_requirement_id then
      raise exception using errcode = '23505', message = 'SDF_DOCUMENT_EVIDENCE_ALREADY_BOUND';
    end if;
    select value into v_state
    from jsonb_array_elements(
      lws_internal.get_sdf_document_requirements_v1(v_requirement.quote_request_id)->'requirements'
    ) value
    where value->>'requirement_id' = p_requirement_id::text;
    return v_state || jsonb_build_object('evidence_id', v_existing.evidence_id, 'replayed', true);
  end if;

  select * into v_source
  from public.document_inbox_customer_request_upload_sources
  where uploaded_file_id = p_uploaded_file_id
  for share;
  if not found then
    raise exception using errcode = 'P0002', message = 'SDF_DOCUMENT_EVIDENCE_NOT_FOUND';
  end if;
  if v_source.quote_request_id <> v_requirement.quote_request_id then
    raise exception using errcode = '23514', message = 'SDF_DOCUMENT_EVIDENCE_DOSSIER_MISMATCH';
  end if;

  select * into strict v_uploaded
  from public.customer_request_uploaded_files
  where uploaded_file_id = v_source.uploaded_file_id
  for share;
  select * into strict v_inbox
  from public.document_inbox_items
  where id = v_source.document_inbox_item_id
  for share;
  if v_uploaded.status <> 'ACCEPTED'
     or v_inbox.lifecycle_status not in ('RECEIVED', 'REVIEW_REQUIRED', 'APPROVED', 'PROCESSED') then
    raise exception using errcode = '55000', message = 'SDF_DOCUMENT_EVIDENCE_NOT_VALID';
  end if;

  insert into public.sdf_document_requirement_evidence(
    requirement_id, quote_request_id, uploaded_file_id,
    document_inbox_item_id, bound_by_operator_id
  ) values (
    v_requirement.requirement_id, v_requirement.quote_request_id,
    v_source.uploaded_file_id, v_source.document_inbox_item_id, v_operator.operator_id
  ) returning * into v_evidence;

  select value into strict v_state
  from jsonb_array_elements(
    lws_internal.get_sdf_document_requirements_v1(v_requirement.quote_request_id)->'requirements'
  ) value
  where value->>'requirement_id' = p_requirement_id::text;
  return v_state || jsonb_build_object('evidence_id', v_evidence.evidence_id, 'replayed', false);
end;
$$;

revoke all on function lws_internal.reject_sdf_document_requirement_mutation_v1(),
  lws_internal.get_sdf_document_requirements_v1(uuid)
from public, anon, authenticated, service_role;

revoke all on function public.create_sdf_document_requirement_v1(uuid, text, integer),
  public.bind_sdf_document_requirement_evidence_v1(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.create_sdf_document_requirement_v1(uuid, text, integer),
  public.bind_sdf_document_requirement_evidence_v1(uuid, uuid)
to authenticated;

comment on table public.sdf_document_requirements is
  'Immutable owner-authored required-document items for one production SDF quote_request_id; no qualification field is promoted automatically.';
comment on table public.sdf_document_requirement_evidence is
  'Immutable binding from one accepted customer upload and its Inbox provenance to one requirement in the same SDF dossier.';
comment on function lws_internal.get_sdf_document_requirements_v1(uuid) is
  'Private deterministic per-requirement state. SATISFIED requires required_count unique accepted uploads with non-rejected Inbox provenance.';

create function lws_internal.sdf_package_rank_v1(p_package text)
returns integer
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select case p_package
    when 'start' then 1
    when 'groei' then 2
    when 'pro' then 3
    when 'maatwerk' then 4
    else null
  end
$$;

create function lws_internal.sdf_package_for_rank_v1(p_rank integer)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select case p_rank
    when 1 then 'start'
    when 2 then 'groei'
    when 3 then 'pro'
    when 4 then 'maatwerk'
    else null
  end
$$;

create function lws_internal.evaluate_sdf_budget_guard_v2(
  p_flows bigint,
  p_document_types bigint,
  p_pages_per_month bigint,
  p_users bigint,
  p_complexity_level text,
  p_exceptional_scope boolean,
  p_selected_package text
)
returns jsonb
language plpgsql
immutable
set search_path = lws_internal, pg_catalog
as $$
declare
  v_numeric jsonb;
  v_complexity_package text;
  v_minimum_package text;
  v_minimum_rank integer;
  v_selected_rank integer;
  v_pricing jsonb;
begin
  if p_complexity_level is null then
    raise exception using errcode = '22004', message = 'SDF_COMPLEXITY_LEVEL_REQUIRED';
  end if;
  if p_exceptional_scope is null then
    raise exception using errcode = '22004', message = 'SDF_EXCEPTIONAL_SCOPE_REQUIRED';
  end if;
  if p_complexity_level not in ('standard','expanded','advanced') then
    raise exception using errcode = '22023', message = 'INVALID_SDF_COMPLEXITY_LEVEL';
  end if;
  if p_selected_package is null then
    raise exception using errcode = '22004', message = 'SDF_SELECTED_PACKAGE_REQUIRED';
  end if;
  v_selected_rank := lws_internal.sdf_package_rank_v1(p_selected_package);
  if v_selected_rank is null then
    raise exception using errcode = '22023', message = 'INVALID_SDF_SELECTED_PACKAGE';
  end if;

  v_numeric := lws_internal.evaluate_sdf_budget_guard_v1(
    p_flows,p_document_types,p_pages_per_month,p_users
  );
  v_complexity_package := case p_complexity_level
    when 'standard' then 'start'
    when 'expanded' then 'groei'
    when 'advanced' then 'pro'
  end;
  v_minimum_rank := greatest(
    lws_internal.sdf_package_rank_v1(v_numeric->>'package'),
    lws_internal.sdf_package_rank_v1(v_complexity_package),
    case when p_exceptional_scope then 4 else 1 end
  );
  v_minimum_package := lws_internal.sdf_package_for_rank_v1(v_minimum_rank);
  if v_selected_rank < v_minimum_rank then
    raise exception using errcode = '23514', message = 'SDF_PACKAGE_DOWNGRADE_DENIED';
  end if;
  v_pricing := lws_internal.get_sdf_budget_guard_pricing_authority_v2(p_selected_package);

  return jsonb_build_object(
    'authority_version',2,
    'minimum_package',v_minimum_package,
    'selected_package',p_selected_package,
    'maatwerk_required',v_minimum_package='maatwerk',
    'dimensions',jsonb_build_object(
      'flows',jsonb_build_object('value',p_flows,'minimum_package',lws_internal.evaluate_sdf_budget_guard_v1(p_flows,1,1,1)->>'package'),
      'document_types',jsonb_build_object('value',p_document_types,'minimum_package',lws_internal.evaluate_sdf_budget_guard_v1(1,p_document_types,1,1)->>'package'),
      'monthly_pages',jsonb_build_object('value',p_pages_per_month,'minimum_package',lws_internal.evaluate_sdf_budget_guard_v1(1,1,p_pages_per_month,1)->>'package'),
      'users',jsonb_build_object('value',p_users,'minimum_package',lws_internal.evaluate_sdf_budget_guard_v1(1,1,1,p_users)->>'package'),
      'complexity',jsonb_build_object('value',p_complexity_level,'minimum_package',v_complexity_package),
      'exceptional_scope',jsonb_build_object('value',p_exceptional_scope,'minimum_package',case when p_exceptional_scope then 'maatwerk' else 'start' end)
    ),
    'pricing',v_pricing
  );
end;
$$;

create table public.sdf_scope_classification_authorities (
  classification_authority_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique references public.quote_requests(id) on delete restrict,
  qualification_intake_id uuid not null unique references public.sdf_qualification_intakes(intake_id) on delete restrict,
  submission_id uuid not null unique references public.sdf_qualification_intake_submissions(submission_id) on delete restrict,
  submission_sha256 char(64) not null check (submission_sha256 ~ '^[0-9a-f]{64}$'),
  complexity_level text not null check (complexity_level in ('standard','expanded','advanced')),
  exceptional_scope boolean not null,
  minimum_package text not null check (minimum_package in ('start','groei','pro','maatwerk')),
  selected_package text not null check (selected_package in ('start','groei','pro','maatwerk')),
  evaluation_snapshot jsonb not null,
  confirmed_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  confirmer_role text not null check (confirmer_role in ('owner','admin')),
  confirmed_at timestamptz not null,
  canonical_payload jsonb not null,
  classification_sha256 char(64) not null check (classification_sha256 ~ '^[0-9a-f]{64}$'),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint sdf_scope_classification_payload_valid check (
    public.jsonb_has_exact_keys(canonical_payload,array[
      'authority_version','quote_request_id','qualification_intake_id','submission_id',
      'submission_sha256','complexity_level','exceptional_scope','minimum_package',
      'selected_package','evaluation','confirmed_by_operator_id','confirmer_role','confirmed_at'
    ])
    and canonical_payload->>'authority_version'='1'
    and canonical_payload->>'quote_request_id'=quote_request_id::text
    and canonical_payload->>'qualification_intake_id'=qualification_intake_id::text
    and canonical_payload->>'submission_id'=submission_id::text
    and canonical_payload->>'submission_sha256'=rtrim(submission_sha256)
    and canonical_payload->>'complexity_level'=complexity_level
    and (canonical_payload->>'exceptional_scope')::boolean=exceptional_scope
    and canonical_payload->>'minimum_package'=minimum_package
    and canonical_payload->>'selected_package'=selected_package
    and canonical_payload->'evaluation'=evaluation_snapshot
    and canonical_payload->>'confirmed_by_operator_id'=confirmed_by_operator_id::text
    and canonical_payload->>'confirmer_role'=confirmer_role
    and (canonical_payload->>'confirmed_at')::timestamptz=confirmed_at
    and classification_sha256=encode(extensions.digest(convert_to(canonical_payload::text,'UTF8'),'sha256'),'hex')
  )
);

alter table public.sdf_quotation_preparation_authorities
  add column classification_authority_id uuid unique
    references public.sdf_scope_classification_authorities(classification_authority_id) on delete restrict,
  add column classification_sha256 char(64)
    check (classification_sha256 is null or classification_sha256 ~ '^[0-9a-f]{64}$'),
  add constraint sdf_quotation_preparation_classification_binding_complete check (
    (classification_authority_id is null) = (classification_sha256 is null)
  );

create function public.guard_sdf_scope_classification_authority_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'SDF_SCOPE_CLASSIFICATION_IMMUTABLE';
end;
$$;

create trigger trg_sdf_scope_classification_authorities_immutable
before update or delete on public.sdf_scope_classification_authorities
for each row execute function public.guard_sdf_scope_classification_authority_v1();

alter table public.sdf_scope_classification_authorities enable row level security;
alter table public.sdf_scope_classification_authorities force row level security;

create function public.confirm_sdf_scope_classification_v1(
  p_quote_request_id uuid,
  p_submission_id uuid,
  p_complexity_level text,
  p_exceptional_scope boolean,
  p_selected_package text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake public.sdf_qualification_intakes%rowtype;
  v_submission public.sdf_qualification_intake_submissions%rowtype;
  v_existing public.sdf_scope_classification_authorities%rowtype;
  v_capacities jsonb;
  v_evaluation jsonb;
  v_submission_hash text;
  v_fingerprint text;
  v_canonical jsonb;
  v_hash text;
  v_now timestamptz := clock_timestamp();
begin
  if p_complexity_level is null then
    raise exception using errcode = '22004', message = 'SDF_COMPLEXITY_LEVEL_REQUIRED';
  end if;
  if p_exceptional_scope is null then
    raise exception using errcode = '22004', message = 'SDF_EXCEPTIONAL_SCOPE_REQUIRED';
  end if;
  if p_complexity_level not in ('standard','expanded','advanced') then
    raise exception using errcode = '22023', message = 'INVALID_SDF_COMPLEXITY_LEVEL';
  end if;
  if p_quote_request_id is null or p_submission_id is null or p_selected_package is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_SCOPE_CLASSIFICATION_INPUT_INVALID';
  end if;
  if v_subject is null then
    raise exception using errcode = '42501', message = 'SDF_SCOPE_CLASSIFICATION_AUTHORITY_DENIED';
  end if;
  select * into v_operator from public.commercial_operators where auth_user_id=v_subject;
  if not found or v_operator.status<>'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_SCOPE_CLASSIFICATION_AUTHORITY_DENIED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_quote_request_id::text,0));
  select * into v_request from public.quote_requests where id=p_quote_request_id for update;
  if not found or v_request.request_kind<>'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_REQUEST_KIND_REQUIRED';
  end if;
  select intake.* into v_intake
  from public.sdf_qualification_intakes intake
  where intake.quote_request_id=p_quote_request_id and intake.status='qualification_complete';
  if not found then
    raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_COMPLETE_REQUIRED';
  end if;
  select * into v_submission
  from public.sdf_qualification_intake_submissions
  where submission_id=p_submission_id
    and intake_id=v_intake.intake_id
    and submission_sequence=v_intake.latest_submission_sequence
    and taxonomy_version='sdf_qualification_intake/3.0.0';
  if not found then
    raise exception using errcode = '55000', message = 'SDF_V3_SUBMISSION_REQUIRED';
  end if;
  v_submission_hash:=encode(extensions.digest(convert_to(v_submission.answers::text,'UTF8'),'sha256'),'hex');
  if v_submission_hash<>rtrim(v_submission.payload_sha256) then
    raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_INTEGRITY_MISMATCH';
  end if;
  v_capacities:=lws_internal.get_sdf_budget_guard_capacity_input_v1(v_submission.answers);
  v_evaluation:=lws_internal.evaluate_sdf_budget_guard_v2(
    (v_capacities->>'flow_count')::bigint,
    (v_capacities->>'document_type_count')::bigint,
    (v_capacities->>'pages_per_month')::bigint,
    (v_capacities->>'user_count')::bigint,
    p_complexity_level,p_exceptional_scope,p_selected_package
  );
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'authorityVersion',1,'quoteRequestId',p_quote_request_id,'submissionId',p_submission_id,
    'submissionSha256',v_submission_hash,'complexityLevel',p_complexity_level,
    'exceptionalScope',p_exceptional_scope,'selectedPackage',p_selected_package,
    'confirmedByOperatorId',v_operator.operator_id,'confirmerRole',v_operator.role
  )::text,'UTF8'),'sha256'),'hex');

  select * into v_existing from public.sdf_scope_classification_authorities where idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint)<>v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'classification_authority_id',v_existing.classification_authority_id,
      'complexity_level',v_existing.complexity_level,'exceptional_scope',v_existing.exceptional_scope,
      'minimum_package',v_existing.minimum_package,'selected_package',v_existing.selected_package,
      'classification_sha256',rtrim(v_existing.classification_sha256),'replayed',true
    );
  end if;
  if exists(select 1 from public.sdf_scope_classification_authorities where quote_request_id=p_quote_request_id) then
    raise exception using errcode = '55000', message = 'SDF_SCOPE_CLASSIFICATION_REAPPROVAL_REQUIRED';
  end if;
  v_canonical:=jsonb_build_object(
    'authority_version',1,'quote_request_id',p_quote_request_id,
    'qualification_intake_id',v_intake.intake_id,'submission_id',v_submission.submission_id,
    'submission_sha256',v_submission_hash,'complexity_level',p_complexity_level,
    'exceptional_scope',p_exceptional_scope,'minimum_package',v_evaluation->>'minimum_package',
    'selected_package',p_selected_package,'evaluation',v_evaluation,
    'confirmed_by_operator_id',v_operator.operator_id,'confirmer_role',v_operator.role,
    'confirmed_at',to_char(v_now at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
  v_hash:=encode(extensions.digest(convert_to(v_canonical::text,'UTF8'),'sha256'),'hex');
  insert into public.sdf_scope_classification_authorities(
    quote_request_id,qualification_intake_id,submission_id,submission_sha256,
    complexity_level,exceptional_scope,minimum_package,selected_package,evaluation_snapshot,
    confirmed_by_operator_id,confirmer_role,confirmed_at,canonical_payload,
    classification_sha256,idempotency_key,request_fingerprint
  ) values (
    p_quote_request_id,v_intake.intake_id,v_submission.submission_id,v_submission_hash,
    p_complexity_level,p_exceptional_scope,v_evaluation->>'minimum_package',p_selected_package,v_evaluation,
    v_operator.operator_id,v_operator.role,v_now,v_canonical,v_hash,p_idempotency_key,v_fingerprint
  ) returning * into v_existing;
  return jsonb_build_object(
    'classification_authority_id',v_existing.classification_authority_id,
    'complexity_level',v_existing.complexity_level,'exceptional_scope',v_existing.exceptional_scope,
    'minimum_package',v_existing.minimum_package,'selected_package',v_existing.selected_package,
    'classification_sha256',rtrim(v_existing.classification_sha256),'replayed',false
  );
end;
$$;

create or replace function public.authorize_sdf_quotation_preparation_v1(
  p_quote_request_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake public.sdf_qualification_intakes%rowtype;
  v_submission public.sdf_qualification_intake_submissions%rowtype;
  v_completion public.sdf_qualification_intake_events%rowtype;
  v_classification public.sdf_scope_classification_authorities%rowtype;
  v_existing public.sdf_quotation_preparation_authorities%rowtype;
  v_quotation_id uuid;
  v_document_completeness jsonb;
  v_package text;
  v_pricing jsonb;
  v_pricing_hash char(64);
  v_submission_hash char(64);
  v_document_evidence_hash char(64);
  v_fingerprint char(64);
begin
  v_operator := lws_internal.assert_sdf_owner_v1();
  select * into v_request from public.quote_requests where id = p_quote_request_id for update;
  if not found or v_request.request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_REQUEST_KIND_REQUIRED';
  end if;
  if v_request.status = 'rejected'
     or exists(select 1 from lws_internal.operator_dossier_states where quote_request_id = p_quote_request_id and state = 'TRASHED') then
    raise exception using errcode = '55000', message = 'SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE';
  end if;
  select * into v_intake from public.sdf_qualification_intakes where quote_request_id = p_quote_request_id for update;
  if not found or v_intake.status <> 'qualification_complete' then
    raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_COMPLETE_REQUIRED';
  end if;
  select * into strict v_submission from public.sdf_qualification_intake_submissions
  where intake_id = v_intake.intake_id and submission_sequence = v_intake.latest_submission_sequence;
  select * into strict v_completion from public.sdf_qualification_intake_events
  where intake_id = v_intake.intake_id and event_kind = 'QUALIFICATION_COMPLETE'
    and submission_sequence = v_submission.submission_sequence
  order by occurred_at desc limit 1;
  v_submission_hash := encode(extensions.digest(convert_to(v_submission.answers::text,'UTF8'),'sha256'),'hex');
  if v_submission_hash <> v_submission.payload_sha256 or v_submission.taxonomy_version <> v_intake.taxonomy_version then
    raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_INTEGRITY_MISMATCH';
  end if;

  if v_submission.taxonomy_version = 'sdf_qualification_intake/3.0.0' then
    select * into v_classification
    from public.sdf_scope_classification_authorities
    where quote_request_id = p_quote_request_id
      and qualification_intake_id = v_intake.intake_id
      and submission_id = v_submission.submission_id
      and rtrim(submission_sha256) = v_submission_hash;
    if not found then
      raise exception using errcode = '55000', message = 'SDF_SCOPE_CLASSIFICATION_REQUIRED';
    end if;
    v_package := v_classification.selected_package;
    v_pricing := lws_internal.get_sdf_budget_guard_pricing_authority_v2(v_package);
    v_document_completeness := lws_internal.evaluate_sdf_document_completeness_v1(p_quote_request_id);
    v_document_evidence_hash := v_document_completeness->>'evidence_sha256';
  else
    if v_request.sdf_package is null then
      raise exception using errcode = '55000', message = 'SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE';
    end if;
    v_package := v_request.sdf_package;
    v_pricing := public.get_sdf_package_pricing_authority_v1(v_package);
    v_document_evidence_hash := null;
  end if;

  v_pricing_hash := encode(extensions.digest(convert_to(v_pricing::text,'UTF8'),'sha256'),'hex');
  v_fingerprint := encode(extensions.digest(convert_to(
    case when v_submission.taxonomy_version = 'sdf_qualification_intake/3.0.0' then
      jsonb_build_object(
        'v',4,'request',p_quote_request_id,'intake',v_intake.intake_id,
        'taxonomy',v_submission.taxonomy_version,'submission',v_submission.payload_sha256,
        'completion',v_completion.event_id,'classificationAuthorityId',v_classification.classification_authority_id,
        'classificationSha256',rtrim(v_classification.classification_sha256),
        'package',v_package,'pricing',v_pricing_hash,'document_evidence',v_document_evidence_hash
      )
    else
      jsonb_build_object(
        'v',1,'request',p_quote_request_id,'intake',v_intake.intake_id,
        'submission',v_submission.payload_sha256,'completion',v_completion.event_id,
        'package',v_package,'pricing',v_pricing_hash
      )
    end::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_quotation_preparation_authorities where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'authority_id',v_existing.authority_id,'quotation_id',v_existing.quotation_id,
      'status','QUOTATION_PREPARATION_ELIGIBLE','sdf_package',v_existing.sdf_package,
      'classification_authority_id',v_existing.classification_authority_id,
      'classification_sha256',rtrim(v_existing.classification_sha256),
      'document_evidence_sha256',rtrim(v_existing.document_evidence_sha256),'replayed',true
    );
  end if;
  if v_submission.taxonomy_version = 'sdf_qualification_intake/3.0.0'
     and (v_document_completeness->>'is_complete')::boolean is distinct from true then
    raise exception using errcode = '55000', message = 'SDF_DOCUMENT_COMPLETENESS_REQUIRED';
  end if;
  if exists(select 1 from public.sdf_quotations where quote_request_id = p_quote_request_id)
     or exists(select 1 from public.sdf_quotation_preparation_authorities where quote_request_id = p_quote_request_id) then
    raise exception using errcode = '55000', message = 'SDF_QUOTATION_PREPARATION_CONFLICT';
  end if;
  insert into public.sdf_quotations(quote_request_id) values(p_quote_request_id) returning quotation_id into v_quotation_id;
  insert into public.sdf_quotation_preparation_authorities(
    quote_request_id,quotation_id,qualification_intake_id,taxonomy_version,
    submission_sequence,submission_sha256,completion_event_id,sdf_package,
    pricing_authority_version,pricing_authority_sha256,document_evidence_sha256,
    classification_authority_id,classification_sha256,actor_operator_id,actor_role,
    idempotency_key,request_fingerprint
  ) values (
    p_quote_request_id,v_quotation_id,v_intake.intake_id,v_submission.taxonomy_version,
    v_submission.submission_sequence,v_submission.payload_sha256,v_completion.event_id,v_package,
    (v_pricing->>'authority_version')::integer,v_pricing_hash,v_document_evidence_hash,
    v_classification.classification_authority_id,v_classification.classification_sha256,
    v_operator.operator_id,'owner',p_idempotency_key,v_fingerprint
  ) returning * into v_existing;
  return jsonb_build_object(
    'authority_id',v_existing.authority_id,'quotation_id',v_existing.quotation_id,
    'status','QUOTATION_PREPARATION_ELIGIBLE','sdf_package',v_existing.sdf_package,
    'classification_authority_id',v_existing.classification_authority_id,
    'classification_sha256',rtrim(v_existing.classification_sha256),
    'document_evidence_sha256',rtrim(v_existing.document_evidence_sha256),'replayed',false
  );
end;
$$;

create function lws_internal.get_sdf_preparation_classification_binding_v1(
  p_preparation_authority_id uuid,
  p_submission_sha256 text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_preparation public.sdf_quotation_preparation_authorities%rowtype;
  v_classification public.sdf_scope_classification_authorities%rowtype;
begin
  select * into v_preparation
  from public.sdf_quotation_preparation_authorities
  where authority_id = p_preparation_authority_id;
  if not found or v_preparation.classification_authority_id is null then
    raise exception using errcode = '55000', message = 'SDF_SCOPE_CLASSIFICATION_REQUIRED';
  end if;
  select * into v_classification
  from public.sdf_scope_classification_authorities
  where classification_authority_id = v_preparation.classification_authority_id
    and quote_request_id = v_preparation.quote_request_id
    and qualification_intake_id = v_preparation.qualification_intake_id
    and rtrim(submission_sha256) = p_submission_sha256
    and rtrim(classification_sha256) = rtrim(v_preparation.classification_sha256);
  if not found
     or v_classification.selected_package <> v_preparation.sdf_package
     or rtrim(v_classification.classification_sha256) <>
        encode(extensions.digest(convert_to(v_classification.canonical_payload::text,'UTF8'),'sha256'),'hex') then
    raise exception using errcode = '55000', message = 'SDF_SCOPE_CLASSIFICATION_STALE';
  end if;
  return jsonb_build_object(
    'classification_authority_id',v_classification.classification_authority_id,
    'classification_sha256',rtrim(v_classification.classification_sha256),
    'minimum_package',v_classification.minimum_package,
    'selected_package',v_classification.selected_package,
    'complexity_level',v_classification.complexity_level,
    'exceptional_scope',v_classification.exceptional_scope,
    'pricing',lws_internal.get_sdf_budget_guard_pricing_authority_v2(v_classification.selected_package)
  );
end;
$$;

do $$
declare
  v_signature text;
  v_definition text;
  v_rewritten text;
  v_old text := $old$  v_binding := lws_internal.get_sdf_budget_guard_quotation_binding_v1(v_submission.answers);
  v_package := v_binding->>'package';
  v_pricing := v_binding->'pricing';$old$;
  v_new text := $new$  v_binding := lws_internal.get_sdf_preparation_classification_binding_v1(
    p_preparation_authority_id, v_submission_hash
  );
  v_package := v_binding->>'selected_package';
  v_pricing := v_binding->'pricing';$new$;
begin
  foreach v_signature in array array[
    'public.authorize_sdf_quotation_commercial_decision_v1(uuid,uuid,uuid,uuid,jsonb,uuid)',
    'public.authorize_sdf_quotation_commercial_decision_v1(uuid,uuid,uuid,uuid,bigint,bigint,jsonb,uuid)'
  ] loop
    v_definition := pg_get_functiondef(v_signature::regprocedure);
    v_rewritten := replace(v_definition,v_old,v_new);
    if v_rewritten = v_definition then
      raise exception using errcode = '55000', message = 'SDF_COMMERCIAL_CLASSIFICATION_CALLSITE_DRIFT';
    end if;
    execute v_rewritten;
  end loop;
end;
$$;

revoke all on function lws_internal.sdf_package_rank_v1(text) from public,anon,authenticated,service_role;
revoke all on function lws_internal.sdf_package_for_rank_v1(integer) from public,anon,authenticated,service_role;
revoke all on function lws_internal.evaluate_sdf_budget_guard_v2(bigint,bigint,bigint,bigint,text,boolean,text) from public,anon,authenticated,service_role;
revoke all on function lws_internal.get_sdf_preparation_classification_binding_v1(uuid,text) from public,anon,authenticated,service_role;
revoke all on table public.sdf_scope_classification_authorities from public,anon,authenticated,service_role;
revoke all on function public.guard_sdf_scope_classification_authority_v1() from public,anon,authenticated,service_role;
revoke all on function public.confirm_sdf_scope_classification_v1(uuid,uuid,text,boolean,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.confirm_sdf_scope_classification_v1(uuid,uuid,text,boolean,text,uuid) to authenticated;

comment on function lws_internal.evaluate_sdf_budget_guard_v2(bigint,bigint,bigint,bigint,text,boolean,text) is
  'Private immutable six-dimension SDF Budget Guard. Reuses numeric v1, adds confirmed complexity and exceptional scope, and permits upgrades while rejecting downgrades.';
comment on table public.sdf_scope_classification_authorities is
  'Immutable owner/admin SDF commercial classification binding explicit complexity and exceptional-scope decisions to one canonical V3 submission and deterministic Budget Guard evaluation.';
comment on function public.confirm_sdf_scope_classification_v1(uuid,uuid,text,boolean,text,uuid) is
  'Owner/admin-only confirmation of SDF complexity, exceptional scope, and selected package. Customer and ordinary operator authority are denied; missing values fail closed.';
comment on column public.sdf_quotation_preparation_authorities.classification_authority_id is
  'Immutable V3 quotation-preparation binding to the confirmed complexity and exceptional-scope authority; null only for historical taxonomy preparations.';
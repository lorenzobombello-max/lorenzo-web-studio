alter table public.sdf_qualification_intakes
  drop constraint sdf_qualification_intakes_taxonomy_version_check,
  add constraint sdf_qualification_intakes_taxonomy_version_check
    check (taxonomy_version in ('sdf_qualification_intake/1.0.0', 'sdf_qualification_intake/2.0.0', 'sdf_qualification_intake/3.0.0'));

alter table public.sdf_qualification_intakes
  alter column taxonomy_version set default 'sdf_qualification_intake/3.0.0';

alter table public.sdf_qualification_intake_submissions
  drop constraint sdf_qualification_intake_submissions_taxonomy_version_check,
  add constraint sdf_qualification_intake_submissions_taxonomy_version_check
    check (taxonomy_version in ('sdf_qualification_intake/1.0.0', 'sdf_qualification_intake/2.0.0', 'sdf_qualification_intake/3.0.0'));

create function lws_internal.sdf_payload_valid_v3(p_answers jsonb, p_require_complete boolean)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_commercial jsonb;
  v_commercial_keys text[];
  v_v2_answers jsonb;
  v_flow_count numeric;
  v_user_count numeric;
begin
  if jsonb_typeof(p_answers) <> 'object' then return false; end if;
  v_commercial := p_answers->'commercialQualification';
  if jsonb_typeof(v_commercial) <> 'object' then return false; end if;

  select coalesce(array_agg(key order by key), '{}')
  into v_commercial_keys
  from jsonb_object_keys(v_commercial) key;
  if v_commercial_keys <> array['customComplexity','documentVolumes','flowCount','packageDirection','userCount']::text[] then return false; end if;

  if jsonb_typeof(v_commercial->'flowCount') not in ('number', 'null')
    or jsonb_typeof(v_commercial->'userCount') not in ('number', 'null') then return false; end if;

  v_v2_answers := jsonb_set(
    p_answers,
    '{commercialQualification}',
    v_commercial - 'flowCount' - 'userCount'
  );
  if not lws_internal.sdf_payload_valid_v2(v_v2_answers, p_require_complete) then return false; end if;

  if jsonb_typeof(v_commercial->'flowCount') = 'number' then
    v_flow_count := (v_commercial->>'flowCount')::numeric;
    if v_flow_count <> trunc(v_flow_count) or v_flow_count not between 1 and 9007199254740991 then return false; end if;
  elsif p_require_complete then return false;
  end if;

  if jsonb_typeof(v_commercial->'userCount') = 'number' then
    v_user_count := (v_commercial->>'userCount')::numeric;
    if v_user_count <> trunc(v_user_count) or v_user_count not between 1 and 9007199254740991 then return false; end if;
  elsif p_require_complete then return false;
  end if;

  return true;
exception when others then return false;
end;
$$;

create function lws_internal.canonicalize_sdf_payload_v3(p_answers jsonb)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_commercial jsonb;
  v_result jsonb;
begin
  if not lws_internal.sdf_payload_valid_v3(p_answers, false) then
    raise exception using errcode = '22023', message = 'INVALID_SDF_QUALIFICATION_PAYLOAD_V3';
  end if;

  v_commercial := p_answers->'commercialQualification';
  v_result := lws_internal.canonicalize_sdf_payload_v2(
    jsonb_set(p_answers, '{commercialQualification}', v_commercial - 'flowCount' - 'userCount')
  );
  v_result := jsonb_set(v_result, '{commercialQualification,flowCount}', v_commercial->'flowCount');
  v_result := jsonb_set(v_result, '{commercialQualification,userCount}', v_commercial->'userCount');
  return v_result;
end;
$$;

create function lws_internal.get_sdf_budget_guard_capacity_input_v1(p_answers jsonb)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_answers jsonb;
  v_pages_per_year numeric;
begin
  if not lws_internal.sdf_payload_valid_v3(p_answers, true) then
    raise exception using errcode = '22023', message = 'INVALID_SDF_BUDGET_GUARD_CAPACITY_INPUT';
  end if;

  v_answers := lws_internal.canonicalize_sdf_payload_v3(p_answers);
  select sum(
    (volume->>'documentCount')::numeric
    * (volume->>'averagePagesPerDocument')::numeric
    * case volume->>'period'
        when 'weekly' then 52
        when 'monthly' then 12
        when 'quarterly' then 4
        when 'yearly' then 1
      end
  )
  into v_pages_per_year
  from jsonb_array_elements(v_answers#>'{commercialQualification,documentVolumes}') volume;

  return jsonb_build_object(
    'flow_count', (v_answers#>>'{commercialQualification,flowCount}')::bigint,
    'document_type_count', jsonb_array_length(v_answers#>'{commercialQualification,documentVolumes}'),
    'pages_per_month', ceil(v_pages_per_year / 12)::bigint,
    'user_count', (v_answers#>>'{commercialQualification,userCount}')::bigint
  );
end;
$$;

create function lws_internal.sdf_payload_taxonomy_version_v3(p_answers jsonb, p_require_complete boolean)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when lws_internal.sdf_payload_valid_v1(p_answers, p_require_complete) then 'sdf_qualification_intake/1.0.0'
    when lws_internal.sdf_payload_valid_v2(p_answers, p_require_complete) then 'sdf_qualification_intake/2.0.0'
    when lws_internal.sdf_payload_valid_v3(p_answers, p_require_complete) then 'sdf_qualification_intake/3.0.0'
    else null
  end
$$;

create or replace function public.save_sdf_qualification_intake_draft_v1(p_customer_capability_digest text,p_expected_revision bigint,p_answers jsonb)
returns jsonb language plpgsql volatile security definer set search_path=public,pg_catalog as $$
declare v_intake public.sdf_qualification_intakes%rowtype; v_new_status public.sdf_qualification_intake_status; v_taxonomy_version text; v_answers jsonb;
begin
  select * into v_intake from public.sdf_qualification_intakes where customer_capability_digest=p_customer_capability_digest and customer_capability_revoked_at is null and customer_capability_expires_at>clock_timestamp() for update;
  if not found then raise exception using errcode='42501', message='SDF_INTAKE_ACCESS_DENIED'; end if;
  if v_intake.status not in ('invited','in_progress','changes_requested') then raise exception using errcode='55000', message='SDF_INTAKE_TRANSITION_NOT_ALLOWED'; end if;
  if p_expected_revision <> v_intake.draft_revision then raise exception using errcode='40001', message='SDF_INTAKE_REVISION_CONFLICT'; end if;
  v_taxonomy_version := lws_internal.sdf_payload_taxonomy_version_v3(p_answers,false);
  if v_taxonomy_version is null then raise exception using errcode='22023', message='INVALID_SDF_QUALIFICATION_PAYLOAD'; end if;
  v_answers := case
    when v_taxonomy_version='sdf_qualification_intake/3.0.0' then lws_internal.canonicalize_sdf_payload_v3(p_answers)
    when v_taxonomy_version='sdf_qualification_intake/2.0.0' then lws_internal.canonicalize_sdf_payload_v2(p_answers)
    else p_answers
  end;
  if v_answers=v_intake.draft_answers and v_taxonomy_version=v_intake.taxonomy_version then return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_intake.status,'draft_revision',v_intake.draft_revision,'taxonomy_version',v_intake.taxonomy_version,'replayed',true); end if;
  v_new_status := 'in_progress';
  update public.sdf_qualification_intakes set draft_answers=v_answers,draft_revision=draft_revision+1,status=v_new_status,taxonomy_version=v_taxonomy_version,updated_at=clock_timestamp() where intake_id=v_intake.intake_id returning * into v_intake;
  insert into public.sdf_qualification_intake_events(intake_id,event_kind,from_status,to_status,actor_class) values(v_intake.intake_id,'DRAFT_SAVED',v_intake.status,v_new_status,'customer');
  return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_intake.status,'draft_revision',v_intake.draft_revision,'taxonomy_version',v_intake.taxonomy_version,'replayed',false);
end;
$$;

create or replace function public.submit_sdf_qualification_intake_v1(p_customer_capability_digest text,p_expected_revision bigint,p_confirmation_accepted boolean,p_confirmation_version text,p_confirmation_sha256 text,p_idempotency_key uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,extensions,pg_catalog as $$
declare v_intake public.sdf_qualification_intakes%rowtype; v_event public.sdf_qualification_intake_events%rowtype; v_sequence integer; v_hash char(64); v_fingerprint char(64); v_taxonomy_version text; v_answers jsonb;
begin
  select * into v_intake from public.sdf_qualification_intakes where customer_capability_digest=p_customer_capability_digest and customer_capability_revoked_at is null and customer_capability_expires_at>clock_timestamp() for update;
  if not found then raise exception using errcode='42501', message='SDF_INTAKE_ACCESS_DENIED'; end if;
  v_taxonomy_version := lws_internal.sdf_payload_taxonomy_version_v3(v_intake.draft_answers,true);
  v_answers := case
    when v_taxonomy_version='sdf_qualification_intake/3.0.0' then lws_internal.canonicalize_sdf_payload_v3(v_intake.draft_answers)
    when v_taxonomy_version='sdf_qualification_intake/2.0.0' then lws_internal.canonicalize_sdf_payload_v2(v_intake.draft_answers)
    else v_intake.draft_answers
  end;
  v_hash := encode(extensions.digest(convert_to(v_answers::text,'UTF8'),'sha256'),'hex');
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object('v',1,'intake',v_intake.intake_id,'revision',p_expected_revision,'payload',v_hash,'confirmation',p_confirmation_sha256)::text,'UTF8'),'sha256'),'hex');
  select * into v_event from public.sdf_qualification_intake_events where intake_id=v_intake.intake_id and idempotency_key=p_idempotency_key;
  if found then if v_event.request_fingerprint<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if; return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_event.to_status,'submission_sequence',v_event.submission_sequence,'replayed',true); end if;
  if v_intake.status not in ('invited','in_progress','changes_requested') then raise exception using errcode='55000',message='SDF_INTAKE_TRANSITION_NOT_ALLOWED'; end if;
  if p_expected_revision<>v_intake.draft_revision then raise exception using errcode='40001',message='SDF_INTAKE_REVISION_CONFLICT'; end if;
  if p_confirmation_accepted is not true
    or p_confirmation_version<>'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1'
    or p_confirmation_sha256<>encode(extensions.digest(convert_to('Ik bevestig dat de ingevulde informatie naar best vermogen volledig en correct is. Ik begrijp dat deze kwalificatie geen offerte, prijsbevestiging of aanvaarding van een opdracht vormt.','UTF8'),'sha256'),'hex')
    or v_taxonomy_version is null then raise exception using errcode='22023',message='INVALID_SDF_QUALIFICATION_SUBMISSION'; end if;
  v_sequence:=v_intake.latest_submission_sequence+1;
  insert into public.sdf_qualification_intake_submissions(intake_id,submission_sequence,answers,taxonomy_version,payload_sha256,confirmation_version,confirmation_sha256) values(v_intake.intake_id,v_sequence,v_answers,v_taxonomy_version,v_hash,p_confirmation_version,p_confirmation_sha256);
  update public.sdf_qualification_intakes set status='submitted',latest_submission_sequence=v_sequence,submitted_at=clock_timestamp(),internal_capability_expires_at=clock_timestamp()+interval '30 days',taxonomy_version=v_taxonomy_version,draft_answers=v_answers,updated_at=clock_timestamp() where intake_id=v_intake.intake_id;
  insert into public.sdf_qualification_intake_events(intake_id,event_kind,from_status,to_status,actor_class,submission_sequence,idempotency_key,request_fingerprint) values(v_intake.intake_id,'SUBMITTED',v_intake.status,'submitted','customer',v_sequence,p_idempotency_key,v_fingerprint);
  insert into public.sdf_qualification_intake_email_jobs(intake_id,kind,template_version,submission_sequence,idempotency_key,request_fingerprint) values(v_intake.intake_id,'submitted','SDF_QUALIFICATION_SUBMITTED_INTERNAL_NL_BE_v1',v_sequence,p_idempotency_key,v_fingerprint);
  return jsonb_build_object('intake_id',v_intake.intake_id,'status','submitted','submission_sequence',v_sequence,'taxonomy_version',v_taxonomy_version,'payload_sha256',v_hash,'replayed',false);
end;
$$;

revoke all on function lws_internal.sdf_payload_valid_v3(jsonb,boolean) from public,anon,authenticated,service_role;
revoke all on function lws_internal.canonicalize_sdf_payload_v3(jsonb) from public,anon,authenticated,service_role;
revoke all on function lws_internal.get_sdf_budget_guard_capacity_input_v1(jsonb) from public,anon,authenticated,service_role;
revoke all on function lws_internal.sdf_payload_taxonomy_version_v3(jsonb,boolean) from public,anon,authenticated,service_role;

comment on function lws_internal.get_sdf_budget_guard_capacity_input_v1(jsonb) is
  'Private immutable extractor for authoritative normalized SDF Budget Guard capacities. Monthly pages are annualized by period and rounded up.';
alter table public.sdf_qualification_intakes
  drop constraint sdf_qualification_intakes_taxonomy_version_check,
  add constraint sdf_qualification_intakes_taxonomy_version_check
    check (taxonomy_version in ('sdf_qualification_intake/1.0.0', 'sdf_qualification_intake/2.0.0'));

alter table public.sdf_qualification_intakes
  alter column taxonomy_version set default 'sdf_qualification_intake/2.0.0';

alter table public.sdf_qualification_intake_submissions
  drop constraint sdf_qualification_intake_submissions_taxonomy_version_check,
  add constraint sdf_qualification_intake_submissions_taxonomy_version_check
    check (taxonomy_version in ('sdf_qualification_intake/1.0.0', 'sdf_qualification_intake/2.0.0'));

alter table public.sdf_quotation_preparation_authorities
  drop constraint sdf_quotation_preparation_authorities_taxonomy_version_check,
  add constraint sdf_quotation_preparation_authorities_taxonomy_version_check
    check (taxonomy_version in ('sdf_qualification_intake/1.0.0', 'sdf_qualification_intake/2.0.0'));

create function lws_internal.sdf_payload_valid_v2(p_answers jsonb, p_require_complete boolean)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_keys text[];
  v_commercial_keys text[];
  v_commercial jsonb;
  v_direction text;
  v_custom_complexity text;
  v_categories jsonb;
  v_volumes jsonb;
  v_volume jsonb;
  v_volume_keys text[];
  v_document_type text;
  v_document_count numeric;
  v_average_pages numeric;
  v_period text;
begin
  if jsonb_typeof(p_answers) <> 'object' then return false; end if;
  select coalesce(array_agg(key order by key), '{}') into v_keys from jsonb_object_keys(p_answers) key;
  if v_keys <> array['businessRequirements','commercialQualification','documentPurpose','sampleDocumentMetadata','workflowCapabilities']::text[] then return false; end if;
  if not lws_internal.sdf_payload_valid_v1(p_answers - 'commercialQualification', p_require_complete) then return false; end if;

  v_commercial := p_answers->'commercialQualification';
  if jsonb_typeof(v_commercial) <> 'object' then return false; end if;
  select coalesce(array_agg(key order by key), '{}') into v_commercial_keys from jsonb_object_keys(v_commercial) key;
  if v_commercial_keys <> array['customComplexity','documentVolumes','packageDirection']::text[] then return false; end if;

  if jsonb_typeof(v_commercial->'packageDirection') <> 'string'
    or jsonb_typeof(v_commercial->'customComplexity') <> 'string'
    or jsonb_typeof(v_commercial->'documentVolumes') <> 'array' then return false; end if;

  v_direction := v_commercial->>'packageDirection';
  v_custom_complexity := btrim(v_commercial->>'customComplexity');
  v_categories := p_answers#>'{documentPurpose,categories}';
  v_volumes := v_commercial->'documentVolumes';

  if v_direction not in ('', 'start', 'groei', 'pro', 'maatwerk', 'advice_requested')
    or char_length(v_custom_complexity) > 2000
    or jsonb_array_length(v_volumes) > 12 then return false; end if;
  if v_direction <> 'maatwerk' and v_custom_complexity <> '' then return false; end if;
  if p_require_complete and (v_direction = '' or (v_direction = 'maatwerk' and v_custom_complexity = '')) then return false; end if;

  for v_volume in select value from jsonb_array_elements(v_volumes) value loop
    if jsonb_typeof(v_volume) <> 'object' then return false; end if;
    select coalesce(array_agg(key order by key), '{}') into v_volume_keys from jsonb_object_keys(v_volume) key;
    if v_volume_keys <> array['averagePagesPerDocument','documentCount','documentType','period']::text[] then return false; end if;
    if jsonb_typeof(v_volume->'documentType') <> 'string'
      or jsonb_typeof(v_volume->'period') <> 'string'
      or jsonb_typeof(v_volume->'documentCount') not in ('number', 'null')
      or jsonb_typeof(v_volume->'averagePagesPerDocument') not in ('number', 'null') then return false; end if;

    v_document_type := v_volume->>'documentType';
    v_period := v_volume->>'period';
    if v_document_type not in ('quotation','invoice','order_confirmation','work_order','delivery_note','contract','customer_document','supplier_document','internal_administrative_document','multiple_document_types','other_custom','unknown_qualification_required')
      or not (v_categories ? v_document_type)
      or v_period not in ('', 'weekly', 'monthly', 'quarterly', 'yearly') then return false; end if;

    if jsonb_typeof(v_volume->'documentCount') = 'number' then
      v_document_count := (v_volume->>'documentCount')::numeric;
      if v_document_count <> trunc(v_document_count) or v_document_count not between 1 and 1000000 then return false; end if;
    elsif p_require_complete then return false;
    end if;

    if jsonb_typeof(v_volume->'averagePagesPerDocument') = 'number' then
      v_average_pages := (v_volume->>'averagePagesPerDocument')::numeric;
      if v_average_pages <> trunc(v_average_pages) or v_average_pages not between 1 and 1000 then return false; end if;
    elsif p_require_complete then return false;
    end if;

    if p_require_complete and v_period = '' then return false; end if;
  end loop;

  if (select count(*) from jsonb_array_elements(v_volumes)) <>
    (select count(distinct value->>'documentType') from jsonb_array_elements(v_volumes) value) then return false; end if;

  if p_require_complete and (
    jsonb_array_length(v_volumes) <> jsonb_array_length(v_categories)
    or exists (
      select 1 from jsonb_array_elements_text(v_categories) category
      where not exists (
        select 1 from jsonb_array_elements(v_volumes) volume
        where volume->>'documentType' = category
      )
    )
  ) then return false; end if;

  return true;
exception when others then return false;
end;
$$;

create function lws_internal.canonicalize_sdf_payload_v2(p_answers jsonb)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_result jsonb;
begin
  if not lws_internal.sdf_payload_valid_v2(p_answers, false) then
    raise exception using errcode = '22023', message = 'INVALID_SDF_QUALIFICATION_PAYLOAD_V2';
  end if;

  v_result := jsonb_set(
    p_answers,
    '{documentPurpose,categories}',
    (select coalesce(jsonb_agg(value order by value), '[]'::jsonb) from jsonb_array_elements_text(p_answers#>'{documentPurpose,categories}') value)
  );
  v_result := jsonb_set(
    v_result,
    '{workflowCapabilities}',
    (select coalesce(jsonb_agg(value order by value), '[]'::jsonb) from jsonb_array_elements_text(v_result->'workflowCapabilities') value)
  );
  v_result := jsonb_set(
    v_result,
    '{businessRequirements,relevantDocumentTypes}',
    (select coalesce(jsonb_agg(value order by value), '[]'::jsonb) from jsonb_array_elements_text(v_result#>'{businessRequirements,relevantDocumentTypes}') value)
  );
  v_result := jsonb_set(
    v_result,
    '{businessRequirements,rolesUsers}',
    (select coalesce(jsonb_agg(value order by value), '[]'::jsonb) from jsonb_array_elements_text(v_result#>'{businessRequirements,rolesUsers}') value)
  );
  v_result := jsonb_set(
    v_result,
    '{commercialQualification,customComplexity}',
    to_jsonb(btrim(v_result#>>'{commercialQualification,customComplexity}'))
  );
  v_result := jsonb_set(
    v_result,
    '{commercialQualification,documentVolumes}',
    (
      select coalesce(jsonb_agg(jsonb_build_object(
        'documentType', value->>'documentType',
        'documentCount', value->'documentCount',
        'period', value->>'period',
        'averagePagesPerDocument', value->'averagePagesPerDocument'
      ) order by value->>'documentType'), '[]'::jsonb)
      from jsonb_array_elements(v_result#>'{commercialQualification,documentVolumes}') value
    )
  );
  return v_result;
end;
$$;

create function lws_internal.sdf_payload_taxonomy_version_v2(p_answers jsonb, p_require_complete boolean)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when lws_internal.sdf_payload_valid_v1(p_answers, p_require_complete) then 'sdf_qualification_intake/1.0.0'
    when lws_internal.sdf_payload_valid_v2(p_answers, p_require_complete) then 'sdf_qualification_intake/2.0.0'
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
  v_taxonomy_version := lws_internal.sdf_payload_taxonomy_version_v2(p_answers,false);
  if v_taxonomy_version is null then raise exception using errcode='22023', message='INVALID_SDF_QUALIFICATION_PAYLOAD'; end if;
  v_answers := case when v_taxonomy_version='sdf_qualification_intake/2.0.0' then lws_internal.canonicalize_sdf_payload_v2(p_answers) else p_answers end;
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
  v_taxonomy_version := lws_internal.sdf_payload_taxonomy_version_v2(v_intake.draft_answers,true);
  v_answers := case when v_taxonomy_version='sdf_qualification_intake/2.0.0' then lws_internal.canonicalize_sdf_payload_v2(v_intake.draft_answers) else v_intake.draft_answers end;
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

revoke all on function lws_internal.sdf_payload_valid_v2(jsonb,boolean) from public,anon,authenticated,service_role;
revoke all on function lws_internal.canonicalize_sdf_payload_v2(jsonb) from public,anon,authenticated,service_role;
revoke all on function lws_internal.sdf_payload_taxonomy_version_v2(jsonb,boolean) from public,anon,authenticated,service_role;

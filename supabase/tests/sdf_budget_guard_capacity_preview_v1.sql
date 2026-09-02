begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(29);

create function pg_temp.preview_payload(p_flows bigint,p_document_types integer,p_pages_per_month bigint,p_users bigint,p_complete boolean default true)
returns jsonb language sql immutable as $$
  with available(document_type,position) as (
    select * from unnest(array['quotation','invoice','order_confirmation','work_order','delivery_note','contract','customer_document','supplier_document','internal_administrative_document','multiple_document_types','other_custom','unknown_qualification_required']) with ordinality
  ), selected as (
    select document_type,position from available where position<=p_document_types
  )
  select jsonb_build_object(
    'documentPurpose',jsonb_build_object('categories',(select jsonb_agg(document_type order by position) from selected)) || case when p_document_types>=11 then jsonb_build_object('otherDescription','Ander documenttype') else '{}'::jsonb end,
    'workflowCapabilities',jsonb_build_array('receive'),
    'businessRequirements',jsonb_build_object('currentWorkflow','A','desiredWorkflow','B','volumeBand','50_to_249','frequency','monthly','relevantDocumentTypes',jsonb_build_array('Documenten'),'rolesUsers',jsonb_build_array('Gebruikers')),
    'sampleDocumentMetadata',jsonb_build_object('available',false,'requestedByLws',false,'uploadRequiredLater',false),
    'commercialQualification',jsonb_build_object(
      'packageDirection','advice_requested','customComplexity','',
      'documentVolumes',(select jsonb_agg(jsonb_build_object('documentType',document_type,'documentCount',case when position=1 then p_pages_per_month-(p_document_types-1) else 1 end,'period','monthly','averagePagesPerDocument',case when p_complete then 1 else null end) order by position) from selected),
      'flowCount',case when p_complete then to_jsonb(p_flows) else 'null'::jsonb end,
      'userCount',to_jsonb(p_users)
    )
  )
$$;

insert into public.quote_requests(id,application_reference,request_kind,sdf_package,name,email,website_type,budget,timing,description,privacy_consent,status)
values
  ('3a100001-0000-4000-8000-000000000001','LWS-AAN-2099-9901','slimme_documentenflow',null,'Preview SDF','preview-sdf@example.test',null,null,null,'Capacity preview fixture.',true,'approved'),
  ('3a100002-0000-4000-8000-000000000002','LWS-AAN-2099-9902','website',null,'Preview Website','preview-website@example.test','Andere','Meer dan EUR 6.000','Flexibel / nog te bepalen','Product isolation fixture.',true,'approved');

insert into public.sdf_qualification_intakes(intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,customer_capability_encrypted,customer_capability_expires_at,draft_answers,draft_revision)
values
  ('3a200001-0000-4000-8000-000000000001','3a100001-0000-4000-8000-000000000001','in_progress','sdf_qualification_intake/3.0.0',repeat('a',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',clock_timestamp()+interval '1 day',pg_temp.preview_payload(1,2,500,3),1),
  ('3a200002-0000-4000-8000-000000000002','3a100002-0000-4000-8000-000000000002','in_progress','sdf_qualification_intake/3.0.0',repeat('b',64),'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',clock_timestamp()+interval '1 day',pg_temp.preview_payload(1,2,500,3),1);

select has_function('public','evaluate_sdf_budget_guard_capacity_preview_v1',array['text'],'capacity preview RPC exists');
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','start','1 flow / 2 docs / 500 pages / 3 users gives START preview');

update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(2,2,500,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','groei','2 flows gives GROEI');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,3,500,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','groei','3 document types gives GROEI');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,2,501,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','groei','501 normalized pages gives GROEI');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,2,500,4) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','groei','4 users gives GROEI');

update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(4,2,500,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','pro','4 flows gives PRO');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,6,500,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','pro','6 document types gives PRO');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,2,2501,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','pro','2501 normalized pages gives PRO');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,2,500,11) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','pro','11 users gives PRO');

update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(7,2,500,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','maatwerk','7 flows gives MAATWERK');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,11,500,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','maatwerk','11 document types gives MAATWERK');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,2,7501,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','maatwerk','7501 normalized pages gives MAATWERK');
update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,2,500,26) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','maatwerk','26 users gives MAATWERK');

update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(2,2,7000,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','pro','highest numeric dimension wins');
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64)),public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64)),'same server facts produce the same preview');

update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(1,2,500,3,false) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'preview_status','INCOMPLETE','incomplete facts return INCOMPLETE');
select ok((public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->'minimum_capacity_package')='null'::jsonb,'incomplete preview has no package default');

select throws_ok($$select public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('b',64))$$,'23514','SDF_REQUEST_KIND_REQUIRED','Website request is rejected');
select throws_ok($$select public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('c',64))$$,'42501','SDF_INTAKE_ACCESS_DENIED','unknown capability is rejected');

update public.sdf_qualification_intakes set draft_answers=pg_temp.preview_payload(2,2,500,3) where intake_id='3a200001-0000-4000-8000-000000000001';
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'minimum_capacity_package','groei','server result ignores saved advice intent as a package class');
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))#>>'{normalized_capacity,pages_per_month}','500','normalized volume is recomputed from saved raw volumes');
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'preview_kind','CAPACITY_ONLY','result is explicitly capacity-only');
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->>'final_decision_pending','true','final six-dimensional decision remains pending');
select is(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->'pending_authorities','["complexity_level","exceptional_scope"]'::jsonb,'owner/admin dimensions remain pending');
select is(jsonb_array_length(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))->'reasons'),4,'preview returns four server-derived dimension reasons');
select is((select array_agg(key order by key) from jsonb_object_keys(public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))) key),array['final_decision_pending','maatwerk_required_by_capacity','minimum_capacity_package','normalized_capacity','pending_authorities','preview_kind','preview_status','reasons']::text[],'preview output has an exact safe allowlist');
select ok(not (public.evaluate_sdf_budget_guard_capacity_preview_v1(repeat('a',64))::text ~ '(intake_id|quote_request_id|fingerprint|sha256|owner_id)'),'preview exposes no internal IDs or commercial hashes');
select ok(has_function_privilege('anon','public.evaluate_sdf_budget_guard_capacity_preview_v1(text)','execute') and has_function_privilege('service_role','public.evaluate_sdf_budget_guard_capacity_preview_v1(text)','execute'),'Edge roles can execute only the capability-bound public RPC');

select * from finish();
rollback;
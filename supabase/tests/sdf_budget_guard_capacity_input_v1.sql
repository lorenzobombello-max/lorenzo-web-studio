begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(24);

create temporary table sdf_v3_fixture(payload jsonb not null);
insert into sdf_v3_fixture(payload) values (
  '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive","review"],"businessRequirements":{"currentWorkflow":"Handmatige ontvangst","desiredWorkflow":"Gecontroleerde digitale flow","volumeBand":"50_to_249","frequency":"monthly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},"commercialQualification":{"packageDirection":"start","customComplexity":"","documentVolumes":[{"documentType":"invoice","documentCount":120,"period":"monthly","averagePagesPerDocument":2}],"flowCount":1,"userCount":3}}'::jsonb
);

select has_function('lws_internal','sdf_payload_valid_v3',array['jsonb','boolean'],'V3 exact-schema validator exists');
select has_function('lws_internal','canonicalize_sdf_payload_v3',array['jsonb'],'V3 canonicalizer exists');
select has_function('lws_internal','get_sdf_budget_guard_capacity_input_v1',array['jsonb'],'capacity extractor exists');
select is(
  (select provolatile::text from pg_proc where oid='lws_internal.get_sdf_budget_guard_capacity_input_v1(jsonb)'::regprocedure),
  'i',
  'capacity extractor is immutable'
);
select ok(
  not has_function_privilege('anon','lws_internal.get_sdf_budget_guard_capacity_input_v1(jsonb)','execute')
  and not has_function_privilege('authenticated','lws_internal.get_sdf_budget_guard_capacity_input_v1(jsonb)','execute')
  and not has_function_privilege('service_role','lws_internal.get_sdf_budget_guard_capacity_input_v1(jsonb)','execute'),
  'capacity extractor is private'
);

select ok(lws_internal.sdf_payload_valid_v3(payload,true),'valid submitted V3 capacities pass') from sdf_v3_fixture;
select is(
  lws_internal.get_sdf_budget_guard_capacity_input_v1(payload),
  '{"flow_count":1,"document_type_count":1,"pages_per_month":240,"user_count":3}'::jsonb,
  'canonical capacities contain four authoritative integers'
) from sdf_v3_fixture;
select is(
  lws_internal.get_sdf_budget_guard_capacity_input_v1(
    jsonb_set(jsonb_set(payload,'{commercialQualification,documentVolumes,0,documentCount}','1'),'{commercialQualification,documentVolumes,0,period}','"weekly"')
  )->>'pages_per_month',
  '9',
  'weekly pages are annualized and rounded up per month'
) from sdf_v3_fixture;

select isnt(lws_internal.sdf_payload_valid_v3(payload #- '{commercialQualification,flowCount}',true),true,'missing flow count fails closed') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(payload #- '{commercialQualification,userCount}',true),true,'missing user count fails closed') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,documentVolumes}','[]'),true),true,'missing document type capacity fails closed') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,documentVolumes,0,averagePagesPerDocument}','null'),true),true,'missing page capacity fails closed') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,flowCount}','0'),true),true,'zero flow count is rejected') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,userCount}','-1'),true),true,'negative user count is rejected') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,flowCount}','1.5'),true),true,'non-integer flow count is rejected') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,userCount}','2.5'),true),true,'non-integer user count is rejected') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,flowCount}','9007199254740992'),true),true,'unsafe flow count overflow is rejected') from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,userCount}','9007199254740992'),true),true,'unsafe user count overflow is rejected') from sdf_v3_fixture;
select ok(
  lws_internal.sdf_payload_valid_v3(jsonb_set(jsonb_set(payload,'{commercialQualification,flowCount}','6'),'{commercialQualification,userCount}','25'),true),
  'client START direction does not invalidate PRO-level capacities'
) from sdf_v3_fixture;
select is(
  lws_internal.canonicalize_sdf_payload_v3(jsonb_set(jsonb_set(payload,'{commercialQualification,flowCount}','6'),'{commercialQualification,userCount}','25'))#>>'{commercialQualification,packageDirection}',
  'start',
  'client package direction remains context only'
) from sdf_v3_fixture;
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(payload,'{commercialQualification,priceMinor}','1000'),true),true,'client price fields remain rejected') from sdf_v3_fixture;
select ok(lws_internal.sdf_payload_valid_v2(payload #- '{commercialQualification,flowCount}' #- '{commercialQualification,userCount}',true),'existing V2 payload remains valid') from sdf_v3_fixture;
select is(lws_internal.sdf_payload_taxonomy_version_v3(payload,true),'sdf_qualification_intake/3.0.0','complete capacity payload dispatches to V3') from sdf_v3_fixture;

select is(
  (
    with document_types(value, position) as (
      select * from unnest(array['quotation','invoice','order_confirmation','work_order','delivery_note','contract','customer_document','supplier_document','internal_administrative_document','multiple_document_types']) with ordinality
    ), binding_payload as (
      select jsonb_set(
        jsonb_set(
          jsonb_set(payload,'{documentPurpose,categories}',(select jsonb_agg(value order by position) from document_types)),
          '{commercialQualification,documentVolumes}',
          (select jsonb_agg(jsonb_build_object('documentType',value,'documentCount',case when position=1 then 7491 else 1 end,'period','monthly','averagePagesPerDocument',1) order by position) from document_types)
        ),
        '{commercialQualification,flowCount}',
        '6'
      ) as payload
      from sdf_v3_fixture
    ), capacities as (
      select lws_internal.get_sdf_budget_guard_capacity_input_v1(payload) as value from binding_payload
    )
    select jsonb_build_array(
      lws_internal.evaluate_sdf_budget_guard_v1(
        (value->>'flow_count')::bigint,
        (value->>'document_type_count')::bigint,
        (value->>'pages_per_month')::bigint,
        (value->>'user_count')::bigint
      )->>'package',
      lws_internal.evaluate_sdf_budget_guard_v1(
        7,
        (value->>'document_type_count')::bigint,
        (value->>'pages_per_month')::bigint,
        (value->>'user_count')::bigint
      )->>'package'
    )
    from capacities
  ),
  '["pro","maatwerk"]'::jsonb,
  'canonical 6/10/7500/25 and 7/10/7500/25 capacities bind to PRO and MAATWERK'
);

select * from finish();
rollback;
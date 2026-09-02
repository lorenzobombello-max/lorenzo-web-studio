begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(43);

select has_table('public','sdf_scope_classification_authorities','SDF scope classification authority exists');
select has_function('lws_internal','evaluate_sdf_budget_guard_v2',array['bigint','bigint','bigint','bigint','text','boolean','text'],'six-dimension evaluator exists');
select has_function('public','confirm_sdf_scope_classification_v1',array['uuid','uuid','text','boolean','text','uuid'],'owner/admin confirmation RPC exists');
select has_column('public','sdf_quotation_preparation_authorities','classification_authority_id','V3 preparation stores classification authority identity');
select has_column('public','sdf_quotation_preparation_authorities','classification_sha256','V3 preparation stores classification SHA-256');
select has_function('lws_internal','get_sdf_preparation_classification_binding_v1',array['uuid','text'],'commercial decisions revalidate preparation classification');

select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start')->>'minimum_package','start','standard contributes START');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'expanded',false,'groei')->>'minimum_package','groei','expanded contributes GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'advanced',false,'pro')->>'minimum_package','pro','advanced contributes PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',true,'maatwerk')->>'minimum_package','maatwerk','exceptional scope requires MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',true,'maatwerk')->>'selected_package','maatwerk','standard plus exceptional scope selects MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'advanced',false,'pro')->>'selected_package','pro','advanced without exceptional scope selects PRO');

select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,null,false,'start')$$,'22004','SDF_COMPLEXITY_LEVEL_REQUIRED','missing complexity fails closed');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',null,'start')$$,'22004','SDF_EXCEPTIONAL_SCOPE_REQUIRED','missing exceptional scope fails closed');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'complex',false,'start')$$,'22023','INVALID_SDF_COMPLEXITY_LEVEL','invalid complexity is rejected');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(3,5,2500,10,'standard',false,'start')$$,'23514','SDF_PACKAGE_DOWNGRADE_DENIED','GROEI to START downgrade is rejected');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(6,10,7500,25,'standard',false,'groei')$$,'23514','SDF_PACKAGE_DOWNGRADE_DENIED','PRO to GROEI downgrade is rejected');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',true,'pro')$$,'23514','SDF_PACKAGE_DOWNGRADE_DENIED','MAATWERK to PRO downgrade is rejected');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'groei')->>'selected_package','groei','START to GROEI upgrade is allowed');
select is(lws_internal.evaluate_sdf_budget_guard_v2(3,5,2500,10,'expanded',false,'pro')->>'selected_package','pro','GROEI to PRO upgrade is allowed');
select is(lws_internal.evaluate_sdf_budget_guard_v2(7,10,7500,25,'standard',false,'maatwerk')#>>'{pricing,implementation,amount_minor}',null,'MAATWERK classification carries no fixed implementation fallback');
select is(lws_internal.evaluate_sdf_budget_guard_v2(7,10,7500,25,'standard',false,'maatwerk')#>>'{pricing,recurring,amount_minor}',null,'MAATWERK classification carries no fixed recurring fallback');

insert into auth.users(id,email) values
  ('ca100000-0000-4000-8000-000000000001','scope-owner@example.test'),
  ('ca100000-0000-4000-8000-000000000002','scope-admin@example.test'),
  ('ca100000-0000-4000-8000-000000000003','scope-operator@example.test'),
  ('ca100000-0000-4000-8000-000000000004','scope-customer@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  ('ca110000-0000-4000-8000-000000000001','ca100000-0000-4000-8000-000000000001','Scope Owner','owner','ACTIVE'),
  ('ca110000-0000-4000-8000-000000000002','ca100000-0000-4000-8000-000000000002','Scope Admin','admin','ACTIVE'),
  ('ca110000-0000-4000-8000-000000000003','ca100000-0000-4000-8000-000000000003','Scope Operator','operator','ACTIVE');

create function pg_temp.scope_answers()
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select '{
    "documentPurpose":{"categories":["invoice","quotation"]},
    "workflowCapabilities":["receive"],
    "businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"50_to_249","frequency":"monthly","relevantDocumentTypes":["Documenten"],"rolesUsers":["Gebruikers"]},
    "sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},
    "commercialQualification":{"packageDirection":"advice_requested","customComplexity":"","documentVolumes":[{"documentType":"invoice","documentCount":499,"period":"monthly","averagePagesPerDocument":1},{"documentType":"quotation","documentCount":1,"period":"monthly","averagePagesPerDocument":1}],"flowCount":1,"userCount":3}
  }'::jsonb
$$;

create temporary table scope_cases(tag integer primary key,quote_request_id uuid,intake_id uuid,submission_id uuid);
insert into scope_cases values
  (1,'ca200001-0000-4000-8000-000000000001','ca300000-0000-4000-8000-000000000001','ca400000-0000-4000-8000-000000000001'),
  (2,'ca200002-0000-4000-8000-000000000002','ca300000-0000-4000-8000-000000000002','ca400000-0000-4000-8000-000000000002'),
  (3,'ca200003-0000-4000-8000-000000000003','ca300000-0000-4000-8000-000000000003','ca400000-0000-4000-8000-000000000003'),
  (4,'ca200004-0000-4000-8000-000000000004','ca300000-0000-4000-8000-000000000004','ca400000-0000-4000-8000-000000000004');
insert into public.quote_requests(id,application_reference,request_kind,sdf_package,name,email,website_type,budget,timing,description,privacy_consent,status)
select quote_request_id,'LWS-AAN-2099-980'||tag,case when tag=4 then 'website' else 'slimme_documentenflow' end,null,'Scope case '||tag,'scope-'||tag||'@example.test',
  case when tag=4 then 'Andere' end,case when tag=4 then 'Meer dan EUR 6.000' end,case when tag=4 then 'Flexibel / nog te bepalen' end,
  'Synthetic scope classification fixture.',true,'approved' from scope_cases;
insert into public.sdf_qualification_intakes(intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,customer_capability_encrypted,customer_capability_expires_at,draft_answers,draft_revision,latest_submission_sequence)
select intake_id,quote_request_id,'qualification_complete','sdf_qualification_intake/3.0.0',repeat(tag::text,64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',clock_timestamp()+interval '1 day',pg_temp.scope_answers(),1,1 from scope_cases where tag<>4;
insert into public.sdf_qualification_intake_submissions(submission_id,intake_id,submission_sequence,answers,taxonomy_version,payload_sha256,confirmation_version,confirmation_sha256)
select submission_id,intake_id,1,pg_temp.scope_answers(),'sdf_qualification_intake/3.0.0',encode(extensions.digest(convert_to(pg_temp.scope_answers()::text,'UTF8'),'sha256'),'hex'),'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat(tag::text,64) from scope_cases where tag<>4;

select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-000000000004',true);
select throws_ok($$select public.confirm_sdf_scope_classification_v1('ca200001-0000-4000-8000-000000000001','ca400000-0000-4000-8000-000000000001','standard',false,'start','ca500000-0000-4000-8000-000000000001')$$,'42501','SDF_SCOPE_CLASSIFICATION_AUTHORITY_DENIED','customer cannot confirm classification');
select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-000000000003',true);
select throws_ok($$select public.confirm_sdf_scope_classification_v1('ca200001-0000-4000-8000-000000000001','ca400000-0000-4000-8000-000000000001','standard',false,'start','ca500000-0000-4000-8000-000000000002')$$,'42501','SDF_SCOPE_CLASSIFICATION_AUTHORITY_DENIED','ordinary operator cannot confirm classification');
select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-000000000001',true);
create temporary table owner_result as select public.confirm_sdf_scope_classification_v1('ca200001-0000-4000-8000-000000000001','ca400000-0000-4000-8000-000000000001','expanded',false,'pro','ca500000-0000-4000-8000-000000000003') value;
select is((select value->>'selected_package' from owner_result),'pro','owner confirmation allows an upgrade');
select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-000000000002',true);
select is(public.confirm_sdf_scope_classification_v1('ca200002-0000-4000-8000-000000000002','ca400000-0000-4000-8000-000000000002','advanced',false,'pro','ca500000-0000-4000-8000-000000000004')->>'complexity_level','advanced','admin confirmation is authorized');

select ok((select canonical_payload ? 'complexity_level' and classification_sha256=encode(extensions.digest(convert_to(canonical_payload::text,'UTF8'),'sha256'),'hex') from public.sdf_scope_classification_authorities where quote_request_id='ca200001-0000-4000-8000-000000000001'),'commercial fingerprint includes complexity');
select ok((select canonical_payload ? 'exceptional_scope' and canonical_payload->'exceptional_scope'='false'::jsonb from public.sdf_scope_classification_authorities where quote_request_id='ca200001-0000-4000-8000-000000000001'),'commercial fingerprint includes exceptional scope');
select is((select evaluation_snapshot from public.sdf_scope_classification_authorities where quote_request_id='ca200001-0000-4000-8000-000000000001'),lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'expanded',false,'pro'),'classification ledger stores the exact canonical six-dimension decision');
select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-000000000001',true);
select is(public.confirm_sdf_scope_classification_v1('ca200001-0000-4000-8000-000000000001','ca400000-0000-4000-8000-000000000001','expanded',false,'pro','ca500000-0000-4000-8000-000000000003')->>'replayed','true','same classification command replays idempotently');
select is((select count(*) from public.sdf_scope_classification_authorities where quote_request_id='ca200001-0000-4000-8000-000000000001'),1::bigint,'idempotent replay creates no second classification decision');
select throws_ok($$select public.confirm_sdf_scope_classification_v1('ca200001-0000-4000-8000-000000000001','ca400000-0000-4000-8000-000000000001','expanded',false,'maatwerk','ca500000-0000-4000-8000-000000000003')$$,'P0001','IDEMPOTENCY_CONFLICT','changed package cannot reuse a classification idempotency key');
select throws_ok($$update public.sdf_scope_classification_authorities set evaluation_snapshot=jsonb_set(evaluation_snapshot,'{decision_fingerprint}','"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"') where quote_request_id='ca200001-0000-4000-8000-000000000001'$$,'55000','SDF_SCOPE_CLASSIFICATION_IMMUTABLE','canonical decision fingerprint cannot be forged after confirmation');
select throws_ok($$update public.sdf_scope_classification_authorities set complexity_level='advanced' where quote_request_id='ca200001-0000-4000-8000-000000000001'$$,'55000','SDF_SCOPE_CLASSIFICATION_IMMUTABLE','changed complexity requires reapproval');
select throws_ok($$update public.sdf_scope_classification_authorities set exceptional_scope=true where quote_request_id='ca200001-0000-4000-8000-000000000001'$$,'55000','SDF_SCOPE_CLASSIFICATION_IMMUTABLE','changed exceptional scope requires reapproval');
select throws_ok($$select public.confirm_sdf_scope_classification_v1('ca200004-0000-4000-8000-000000000004','ca400000-0000-4000-8000-000000000004','standard',false,'start','ca500000-0000-4000-8000-000000000005')$$,'23514','SDF_REQUEST_KIND_REQUIRED','Website cannot use SDF classification route');
select throws_ok($$select public.confirm_sdf_scope_classification_v1('ca200003-0000-4000-8000-000000000003','ca400000-0000-4000-8000-000000000003',null,false,'start','ca500000-0000-4000-8000-000000000006')$$,'22004','SDF_COMPLEXITY_LEVEL_REQUIRED','confirmation rejects missing complexity');
select throws_ok($$select public.confirm_sdf_scope_classification_v1('ca200003-0000-4000-8000-000000000003','ca400000-0000-4000-8000-000000000003','standard',null,'start','ca500000-0000-4000-8000-000000000007')$$,'22004','SDF_EXCEPTIONAL_SCOPE_REQUIRED','confirmation rejects missing exceptional scope');
select throws_ok($$select public.confirm_sdf_scope_classification_v1('ca200003-0000-4000-8000-000000000003','ca400000-0000-4000-8000-000000000003','normal',false,'start','ca500000-0000-4000-8000-000000000008')$$,'22023','INVALID_SDF_COMPLEXITY_LEVEL','confirmation rejects invalid complexity');

insert into public.sdf_qualification_intake_events(event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence)
select ('ca60000'||tag||'-0000-4000-8000-00000000000'||tag)::uuid,intake_id,'QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1
from scope_cases where tag<>4;
insert into public.quote_requests(id,application_reference,request_kind,sdf_package,name,email,description,privacy_consent,status)
values('ca200005-0000-4000-8000-000000000005','LWS-AAN-2099-9805','slimme_documentenflow',null,'Unclassified scope','scope-5@example.test','Unclassified V3 fixture.',true,'approved');
insert into public.sdf_qualification_intakes(intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,customer_capability_encrypted,customer_capability_expires_at,draft_answers,draft_revision,latest_submission_sequence)
values('ca300005-0000-4000-8000-000000000005','ca200005-0000-4000-8000-000000000005','qualification_complete','sdf_qualification_intake/3.0.0',repeat('6',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',clock_timestamp()+interval '1 day',pg_temp.scope_answers(),1,1);
insert into public.sdf_qualification_intake_submissions(submission_id,intake_id,submission_sequence,answers,taxonomy_version,payload_sha256,confirmation_version,confirmation_sha256)
select 'ca400005-0000-4000-8000-000000000005',intake_id,1,draft_answers,'sdf_qualification_intake/3.0.0',encode(extensions.digest(convert_to(draft_answers::text,'UTF8'),'sha256'),'hex'),'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('5',64) from public.sdf_qualification_intakes where intake_id='ca300005-0000-4000-8000-000000000005';
insert into public.sdf_qualification_intake_events(event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence)
values('ca600005-0000-4000-8000-000000000005','ca300005-0000-4000-8000-000000000005','QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1);

select set_config('request.jwt.claim.sub','ca100000-0000-4000-8000-000000000001',true);
select throws_ok($$select public.authorize_sdf_quotation_preparation_v1('ca200005-0000-4000-8000-000000000005','ca700005-0000-4000-8000-000000000005')$$,'55000','SDF_SCOPE_CLASSIFICATION_REQUIRED','V3 preparation fails closed without confirmed classification');
select throws_ok($$select public.authorize_sdf_quotation_preparation_v1('ca200001-0000-4000-8000-000000000001','ca700001-0000-4000-8000-000000000001')$$,'55000','SDF_DOCUMENT_COMPLETENESS_REQUIRED','confirmed classification is consumed before document completeness');

insert into public.sdf_quotations(quotation_id,quote_request_id)
values('ca800001-0000-4000-8000-000000000001','ca200001-0000-4000-8000-000000000001');
insert into public.sdf_quotation_preparation_authorities(
  authority_id,quote_request_id,quotation_id,qualification_intake_id,taxonomy_version,
  submission_sequence,submission_sha256,completion_event_id,sdf_package,
  pricing_authority_version,pricing_authority_sha256,actor_operator_id,actor_role,
  idempotency_key,request_fingerprint,classification_authority_id,classification_sha256
)
select
  'ca810001-0000-4000-8000-000000000001',classification.quote_request_id,
  'ca800001-0000-4000-8000-000000000001',classification.qualification_intake_id,
  'sdf_qualification_intake/3.0.0',1,classification.submission_sha256,
  'ca600001-0000-4000-8000-000000000001',classification.selected_package,
  2,repeat('8',64),classification.confirmed_by_operator_id,'owner',
  'ca820001-0000-4000-8000-000000000001',repeat('9',64),
  classification.classification_authority_id,classification.classification_sha256
from public.sdf_scope_classification_authorities classification
where classification.quote_request_id='ca200001-0000-4000-8000-000000000001';
select is(lws_internal.get_sdf_preparation_classification_binding_v1('ca810001-0000-4000-8000-000000000001',(select rtrim(submission_sha256) from public.sdf_scope_classification_authorities where quote_request_id='ca200001-0000-4000-8000-000000000001'))->>'budget_guard_decision_fingerprint',(select evaluation_snapshot->>'decision_fingerprint' from public.sdf_scope_classification_authorities where quote_request_id='ca200001-0000-4000-8000-000000000001'),'preparation binding carries the canonical Budget Guard decision fingerprint');
select throws_ok($$select lws_internal.get_sdf_preparation_classification_binding_v1('ca810001-0000-4000-8000-000000000001',repeat('f',64))$$,'55000','SDF_SCOPE_CLASSIFICATION_STALE','preparation binding rejects a stale submission fingerprint');

select * from finish();
rollback;
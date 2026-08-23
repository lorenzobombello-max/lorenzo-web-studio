begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(47);

select has_column('public','quote_requests','support_reference','support reference is persisted on the application authority');
select has_table('public','commercial_project_sites','project site binding authority exists');
select has_function('public','get_operator_application_by_support_reference_v1',array['text'],'support lookup RPC exists');
select has_function('public','execute_operator_project_site_command_v1',array['uuid','text','bigint','uuid','text','text'],'guarded site command RPC exists');
select ok(has_function_privilege('authenticated','public.get_operator_application_by_support_reference_v1(text)','execute'),'authenticated role can enter guarded support lookup');
select ok(has_function_privilege('authenticated','public.execute_operator_project_site_command_v1(uuid,text,bigint,uuid,text,text)','execute'),'authenticated role can enter guarded site command');
select ok(not has_function_privilege('anon','public.get_operator_application_by_support_reference_v1(text)','execute'),'anonymous role cannot resolve support references');
select ok(not has_function_privilege('anon','public.execute_operator_project_site_command_v1(uuid,text,bigint,uuid,text,text)','execute'),'anonymous role cannot enter site commands');
select ok(not has_table_privilege('authenticated','public.commercial_project_sites','select'),'authenticated role cannot bypass the guarded dossier read');
select ok(not has_table_privilege('service_role','public.commercial_project_sites','insert'),'service role has no direct site write authority');

insert into auth.users(id,email) values
  ('b1000000-0000-4000-8000-000000000001','support-owner@example.test'),
  ('b1000000-0000-4000-8000-000000000002','support-operator@example.test');
insert into public.commercial_operators(auth_user_id,display_name,role,status) values
  ('b1000000-0000-4000-8000-000000000001','Support Owner','owner','ACTIVE'),
  ('b1000000-0000-4000-8000-000000000002','Support Operator','operator','ACTIVE');

insert into public.quote_requests(id,application_reference,request_kind,created_at,name,email,website_type,budget,timing,description,privacy_consent,status) values
  ('f98b2f08-0000-4000-8000-000000000001','LWS-AAN-2099-7001','website',clock_timestamp(),'Support Customer','support@example.test','business','Meer dan EUR 6.000','flexible','Support fixture',true,'approved'),
  ('c98b2f08-0000-4000-8000-000000000001','LWS-AAN-2099-7002','website',clock_timestamp(),'Second Project Customer','second@example.test','business','Meer dan EUR 6.000','flexible','Second fixture',true,'approved');
insert into public.quote_request_intakes(id,quote_request_id,access_token_hash,access_token_expires_at,status,started_at,submitted_at,confirmation) values
  ('b1200000-0000-4000-8000-000000000001','f98b2f08-0000-4000-8000-000000000001',repeat('1',64),clock_timestamp()+interval '7 days','submitted',clock_timestamp(),clock_timestamp(),true),
  ('b1200000-0000-4000-8000-000000000002','c98b2f08-0000-4000-8000-000000000001',repeat('2',64),clock_timestamp()+interval '7 days','submitted',clock_timestamp(),clock_timestamp(),true);

select is((select support_reference from public.quote_requests where id='f98b2f08-0000-4000-8000-000000000001'),'#F98B2F08','legacy UUID prefix is preserved exactly');
select is(public.normalize_quote_request_support_reference_v1('f98b2f08'),'#F98B2F08','lookup accepts a reference without hash');
select is(public.normalize_quote_request_support_reference_v1('#f98b2f08'),'#F98B2F08','lookup normalizes hash and case');
select throws_ok($$select public.normalize_quote_request_support_reference_v1('#NOT-VALID')$$,'22023','INVALID_SUPPORT_REFERENCE','invalid support reference is rejected');

select throws_ok($$select public.get_operator_application_by_support_reference_v1('#F98B2F08')$$,'42501','HUMAN_JWT_REQUIRED','support lookup requires a human JWT');
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
select throws_ok($$select public.get_operator_application_by_support_reference_v1('#F98B2F08')$$,'42501','APPLICATION_SCOPE_DENIED','project-scoped operator cannot inspect pre-project applications');
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
select is(public.get_operator_application_by_support_reference_v1('#F98B2F08')->>'quote_request_id','f98b2f08-0000-4000-8000-000000000001','support reference resolves the exact application');
select is(public.get_operator_application_by_support_reference_v1('f98b2f08')->>'application_reference','LWS-AAN-2099-7001','support lookup preserves the separate internal reference');
select is(public.get_operator_application_v1(null,'LWS-AAN-2099-7001')->>'support_reference','#F98B2F08','existing application lookup exposes the support reference');
select is((select value->>'support_reference' from jsonb_array_elements(public.list_operator_applications_v1()) as value where value->>'quote_request_id'='f98b2f08-0000-4000-8000-000000000001'),'#F98B2F08','application list exposes the persisted support reference');
select throws_ok($$select public.get_operator_application_by_support_reference_v1('#00000000')$$,'P0001','APPLICATION_NOT_FOUND','unknown support reference fails closed');

select throws_ok(
  $$insert into public.quote_requests(id,application_reference,request_kind,created_at,name,email,website_type,budget,timing,description,privacy_consent,status) values ('f98b2f08-0000-4000-8000-000000000002','LWS-AAN-2099-7003','website',clock_timestamp(),'Ambiguous Customer','ambiguous@example.test','business','Meer dan EUR 6.000','flexible','Ambiguous fixture',true,'approved')$$,
  '23505',null,'legacy prefix collisions fail closed without renumbering'
);

create temporary table support_approval_payload as
select jsonb_build_object(
  'contract_version',1,
  'source_quote_request_id','f98b2f08-0000-4000-8000-000000000001',
  'source_intake_id','b1200000-0000-4000-8000-000000000001',
  'pricing_snapshot',jsonb_build_object('snapshot_id','d1300000-0000-4000-8000-000000000001','snapshot_contract_version',2,'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1','integrity_mac',repeat('a',64)),
  'currency','EUR',
  'line_items',jsonb_build_array(jsonb_build_object('line_id','website','sequence',1,'product_or_service_code','WEBSITE','description','Websiteontwikkeling','quantity',1,'unit','project','unit_price_minor',10000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',10000,'cost_type','ONE_TIME')),
  'totals',jsonb_build_object('one_time_subtotal_minor',10000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',10000,'vat_amount_minor',2100,'total_gross_minor',12100),
  'discount',jsonb_build_object('discount_type',null,'discount_value_minor',0,'discount_reason',null,'approved_by',null,'approved_at',null),
  'customer_identity',jsonb_build_object('source_quote_request_id','f98b2f08-0000-4000-8000-000000000001','source_intake_id','b1200000-0000-4000-8000-000000000001','customer_id',null,'legal_name','Support Customer','contact_name','Support Customer','email','support@example.test','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null,'source_fields',jsonb_build_object('legal_name','fixture'),'snapshot_sha256',repeat('b',64)),
  'project_scope',jsonb_build_object('project_id',null,'project_title','Support website','project_type','website','scope_summary','Support fixture scope','requested_languages',jsonb_build_array('nl'),'included_page_count',1,'features','[]'::jsonb,'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null,'source_intake_id','b1200000-0000-4000-8000-000000000001','source_pricing_snapshot_id','d1300000-0000-4000-8000-000000000001','snapshot_sha256',repeat('c',64)),
  'vat_approval',jsonb_build_object('vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant','vat_approved_by','accountant:test','vat_approved_at','2026-08-15T12:00:00Z'),
  'payment_schedule',jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledige betaling','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null)),'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
  'validity',jsonb_build_object('valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30,'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
  'legal_references',jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','terms_sha256',repeat('d',64),'terms_status','APPROVED','agreement_template_reference',null,'agreement_template_version',null,'agreement_template_sha256',null)
) as payload;

insert into public.quote_request_pricing_snapshots(id,intake_id,snapshot_contract_version,config_version,config_hash,normalized_evidence,calculation,package_advice,budget_evaluation) values (
  'd1300000-0000-4000-8000-000000000001','b1200000-0000-4000-8000-000000000001',2,'1.0.0',repeat('1',64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":10000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000}]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
);
insert into public.quote_request_pricing_snapshot_integrity(snapshot_id,algorithm_version,key_id,mac)
values('d1300000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('a',64));
insert into public.quote_request_quotation_approval_drafts(id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_payload,payload_fingerprint,idempotency_key,created_by)
select 'd1400000-0000-4000-8000-000000000001','f98b2f08-0000-4000-8000-000000000001','b1200000-0000-4000-8000-000000000001','d1300000-0000-4000-8000-000000000001',1,payload,public.quotation_approval_payload_sha256_v1(payload),'d1400000-0000-4000-8000-000000000002','admin:test' from support_approval_payload;
insert into public.quote_request_quotation_approvals(id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_version,approved_payload,payload_sha256,approved_by,approved_at)
select 'd1500000-0000-4000-8000-000000000001','d1400000-0000-4000-8000-000000000001','f98b2f08-0000-4000-8000-000000000001','b1200000-0000-4000-8000-000000000001','d1300000-0000-4000-8000-000000000001',1,1,payload,public.quotation_approval_payload_sha256_v1(payload),'admin:test',clock_timestamp() from support_approval_payload;
insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac)
values('d1500000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('e',64));
insert into public.quote_request_quotation_issuances(id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,template_id,template_version,template_sha256,generation_contract_version,issuance_input_sha256,generation_payload_sha256,docx_sha256,docx_bytes,prepare_idempotency_key,prepare_fingerprint,commit_idempotency_key,commit_fingerprint) values (
  'd1600000-0000-4000-8000-000000000001','LWS-OFF-2099-7001',1,'ISSUED','d1500000-0000-4000-8000-000000000001',clock_timestamp(),'admin:test','LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,repeat('4',64),repeat('5',64),repeat('6',64),12345,'d1600000-0000-4000-8000-000000000002',repeat('7',64),'d1600000-0000-4000-8000-000000000003',repeat('8',64)
);
create temporary table support_acceptance_payload as
select jsonb_build_object(
  'acceptance_contract_version',1,'issuance_id','d1600000-0000-4000-8000-000000000001','quotation_number','LWS-OFF-2099-7001','quotation_version',1,
  'customer_identity_sha256',repeat('b',64),'generation_payload_sha256',repeat('5',64),
  'template',jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',repeat('3',64)),
  'docx',jsonb_build_object('sha256',repeat('6',64),'bytes',12345),
  'acceptance_terms',jsonb_build_object('terms_id','LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','terms_version','1.0.0-technical','terms_sha256',repeat('9',64)),
  'actor',jsonb_build_object('name','Support Acceptant','email','support@example.test','organization','Support Customer','role','Bestuurder'),
  'authority_declaration',true,'accepted_at','2026-08-20T12:00:00.000000Z'
) as payload;
insert into public.quote_request_quotation_acceptances(id,issuance_id,quotation_number,quotation_version,customer_identity_sha256,customer_legal_name,generation_payload_sha256,template_id,template_version,template_sha256,docx_sha256,docx_bytes,acceptance_contract_version,acceptance_terms_id,acceptance_terms_version,acceptance_terms_sha256,accepting_name,accepting_email,accepting_organization,accepting_role,authority_declaration,acceptance_payload,acceptance_payload_sha256,semantic_request_fingerprint,accepted_at,created_at)
select 'd1700000-0000-4000-8000-000000000001','d1600000-0000-4000-8000-000000000001','LWS-OFF-2099-7001',1,repeat('b',64),'Support Customer',repeat('5',64),'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),repeat('6',64),12345,1,'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',repeat('9',64),'Support Acceptant','support@example.test','Support Customer','Bestuurder',true,payload,public.quotation_acceptance_payload_sha256_v1(payload),repeat('f',64),'2026-08-20T12:00:00Z','2026-08-20T12:00:00Z'
from support_acceptance_payload;

insert into public.commercial_customers(customer_id,acceptance_id,identity_sha256)
values ('b1700000-0000-4000-8000-000000000001','d1700000-0000-4000-8000-000000000001',repeat('a',64));
insert into public.commercial_projects(project_id,customer_id,quotation_issuance_id,acceptance_id,accepted_total_minor,currency,m1_minor,m2_minor,m3_minor,current_state,revision)
values ('b1800000-0000-4000-8000-000000000001','b1700000-0000-4000-8000-000000000001','d1600000-0000-4000-8000-000000000001','d1700000-0000-4000-8000-000000000001',10000,'EUR',4000,4000,2000,'QUOTE_ACCEPTED',1);

create temporary table support_approval_payload_two as
select jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(
  payload,
  '{source_quote_request_id}',to_jsonb('c98b2f08-0000-4000-8000-000000000001'::text)),
  '{source_intake_id}',to_jsonb('b1200000-0000-4000-8000-000000000002'::text)),
  '{pricing_snapshot,snapshot_id}',to_jsonb('e1300000-0000-4000-8000-000000000001'::text)),
  '{customer_identity,source_quote_request_id}',to_jsonb('c98b2f08-0000-4000-8000-000000000001'::text)),
  '{customer_identity,source_intake_id}',to_jsonb('b1200000-0000-4000-8000-000000000002'::text)),
  '{project_scope,source_intake_id}',to_jsonb('b1200000-0000-4000-8000-000000000002'::text))
  #>> '{}' as payload
from support_approval_payload;
update support_approval_payload_two
set payload = jsonb_set(payload::jsonb,'{project_scope,source_pricing_snapshot_id}',to_jsonb('e1300000-0000-4000-8000-000000000001'::text))::text;

insert into public.quote_request_pricing_snapshots(id,intake_id,snapshot_contract_version,config_version,config_hash,normalized_evidence,calculation,package_advice,budget_evaluation)
select 'e1300000-0000-4000-8000-000000000001','b1200000-0000-4000-8000-000000000002',snapshot_contract_version,config_version,config_hash,normalized_evidence,calculation,package_advice,budget_evaluation
from public.quote_request_pricing_snapshots where id='d1300000-0000-4000-8000-000000000001';
insert into public.quote_request_pricing_snapshot_integrity(snapshot_id,algorithm_version,key_id,mac)
values('e1300000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('b',64));
insert into public.quote_request_quotation_approval_drafts(id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_payload,payload_fingerprint,idempotency_key,created_by)
select 'e1400000-0000-4000-8000-000000000001','c98b2f08-0000-4000-8000-000000000001','b1200000-0000-4000-8000-000000000002','e1300000-0000-4000-8000-000000000001',1,payload::jsonb,public.quotation_approval_payload_sha256_v1(payload::jsonb),'e1400000-0000-4000-8000-000000000002','admin:test' from support_approval_payload_two;
insert into public.quote_request_quotation_approvals(id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_version,approved_payload,payload_sha256,approved_by,approved_at)
select 'e1500000-0000-4000-8000-000000000001','e1400000-0000-4000-8000-000000000001','c98b2f08-0000-4000-8000-000000000001','b1200000-0000-4000-8000-000000000002','e1300000-0000-4000-8000-000000000001',1,1,payload::jsonb,public.quotation_approval_payload_sha256_v1(payload::jsonb),'admin:test',clock_timestamp() from support_approval_payload_two;
insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac)
values('e1500000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('f',64));
insert into public.quote_request_quotation_issuances(id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,template_id,template_version,template_sha256,generation_contract_version,issuance_input_sha256,generation_payload_sha256,docx_sha256,docx_bytes,prepare_idempotency_key,prepare_fingerprint,commit_idempotency_key,commit_fingerprint) values (
  'e1600000-0000-4000-8000-000000000001','LWS-OFF-2099-7002',1,'ISSUED','e1500000-0000-4000-8000-000000000001',clock_timestamp(),'admin:test','LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,repeat('4',64),repeat('7',64),repeat('8',64),12345,'e1600000-0000-4000-8000-000000000002',repeat('9',64),'e1600000-0000-4000-8000-000000000003',repeat('0',64)
);
create temporary table support_acceptance_payload_two as
select jsonb_set(jsonb_set(payload,'{issuance_id}',to_jsonb('e1600000-0000-4000-8000-000000000001'::text)),'{quotation_number}',to_jsonb('LWS-OFF-2099-7002'::text)) as payload
from support_acceptance_payload;
insert into public.quote_request_quotation_acceptances(id,issuance_id,quotation_number,quotation_version,customer_identity_sha256,customer_legal_name,generation_payload_sha256,template_id,template_version,template_sha256,docx_sha256,docx_bytes,acceptance_contract_version,acceptance_terms_id,acceptance_terms_version,acceptance_terms_sha256,accepting_name,accepting_email,accepting_organization,accepting_role,authority_declaration,acceptance_payload,acceptance_payload_sha256,semantic_request_fingerprint,accepted_at,created_at)
select 'e1700000-0000-4000-8000-000000000001','e1600000-0000-4000-8000-000000000001','LWS-OFF-2099-7002',1,repeat('b',64),'Support Customer',repeat('7',64),'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),repeat('8',64),12345,1,'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',repeat('9',64),'Support Acceptant','support@example.test','Support Customer','Bestuurder',true,payload,public.quotation_acceptance_payload_sha256_v1(payload),repeat('e',64),'2026-08-21T12:00:00Z','2026-08-21T12:00:00Z'
from support_acceptance_payload_two;
insert into public.commercial_projects(project_id,customer_id,quotation_issuance_id,acceptance_id,accepted_total_minor,currency,m1_minor,m2_minor,m3_minor,current_state,revision)
values ('b1800000-0000-4000-8000-000000000002','b1700000-0000-4000-8000-000000000001','e1600000-0000-4000-8000-000000000001','e1700000-0000-4000-8000-000000000001',10000,'EUR',4000,4000,2000,'QUOTE_ACCEPTED',1);

select is(
  public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000001','INITIAL_BIND',0,'b1900000-0000-4000-8000-000000000001','preview.project-one.example','Approved initial preview binding')->>'site_revision',
  '1','owner can create the initial project-site binding'
);
select is((select canonical_url from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001' and site_revision=1),'https://preview.project-one.example','canonical URL derives from the validated initial domain');
select is(
  public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000002','INITIAL_BIND',0,'b1900000-0000-4000-8000-000000000008','project-two.example','Approved second project binding')->>'site_revision',
  '1','same customer can bind an independent second project site'
);
select is(
  public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000001','INITIAL_BIND',0,'b1900000-0000-4000-8000-000000000001','preview.project-one.example','Approved initial preview binding')->>'site_id',
  (select site_id::text from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001' and site_revision=1),
  'identical initial-bind retry returns the original immutable version'
);
select throws_ok(
  $$select public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000001','INITIAL_BIND',0,'b1900000-0000-4000-8000-000000000001','changed.example','Changed evidence')$$,
  'P0001','IDEMPOTENCY_CONFLICT','idempotency key cannot be reused with changed evidence'
);
select throws_ok(
  $$select public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000001','INITIAL_BIND',0,'b1900000-0000-4000-8000-000000000002','duplicate.example','Duplicate bind')$$,
  'P0001','PROJECT_SITE_ALREADY_BOUND','second initial bind is rejected'
);

insert into public.commercial_operator_project_grants(operator_id,project_id,access_level)
select operator_id,'b1800000-0000-4000-8000-000000000001','operator'
from public.commercial_operators where auth_user_id='b1000000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000001','ROTATION',1,'b1900000-0000-4000-8000-000000000003','project-one.example','Unauthorized live rotation')$$,
  '42501','PROJECT_SITE_OWNER_ADMIN_REQUIRED','project-scoped operator cannot rotate a site'
);
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);

select is(
  public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000001','ROTATION',1,'b1900000-0000-4000-8000-000000000004','project-one.example','Approved production domain rotation')->>'site_revision',
  '2','owner can append a controlled domain rotation'
);
select is((select count(*)::integer from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001'),2,'rotation retains both immutable site versions');
select is((select canonical_domain from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001' and site_revision=1),'preview.project-one.example','rotation preserves the previous domain as evidence');
select is((select previous_site_id::text from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001' and site_revision=2),(select site_id::text from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001' and site_revision=1),'rotation links to the previous version in the same project');
select is(public.get_commercial_project_view_v2('b1800000-0000-4000-8000-000000000001')->'site'->>'canonical_domain','project-one.example','authorized project read exposes only the current site version');
select is(public.get_commercial_project_view_v2('b1800000-0000-4000-8000-000000000001')->'site'->>'site_revision','2','authorized project read exposes the current concurrency revision');
select is(public.get_commercial_project_view_v2('b1800000-0000-4000-8000-000000000002')->'site'->>'canonical_domain','project-two.example','rotation of one project leaves the same customer second project isolated');
select throws_ok(
  $$select public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000001','ROTATION',1,'b1900000-0000-4000-8000-000000000005','stale.example','Stale rotation')$$,
  '40001','CONCURRENT_MODIFICATION','stale site revision is rejected'
);
select throws_ok(
  $$select public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000001','ROTATION',2,'b1900000-0000-4000-8000-000000000006','https://unsafe.example/path','Unsafe rotation')$$,
  '22023','INVALID_PROJECT_SITE_COMMAND','unsafe rotation domain is rejected before persistence'
);
select throws_ok(
  $$select public.execute_operator_project_site_command_v1('b1800000-0000-4000-8000-000000000099','INITIAL_BIND',0,'b1900000-0000-4000-8000-000000000007','other.example','Unknown project bind')$$,
  '23503','PROJECT_NOT_FOUND','site command cannot target an unknown project'
);
select throws_ok($$update public.commercial_project_sites set canonical_domain='changed.example' where project_id='b1800000-0000-4000-8000-000000000001'$$,'55000','PROJECT_SITE_BINDING_IMMUTABLE','site versions cannot be overwritten');
select throws_ok($$delete from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001'$$,'55000','PROJECT_SITE_BINDING_IMMUTABLE','site history cannot be deleted');
select is((select count(*)::integer from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001' and actor_operator_id=(select operator_id from public.commercial_operators where auth_user_id='b1000000-0000-4000-8000-000000000001')),2,'every site version records the authorized operator identity');
select is((select count(*)::integer from public.commercial_project_sites where project_id='b1800000-0000-4000-8000-000000000001' and nullif(btrim(evidence),'') is not null),2,'every site version retains explicit operator evidence');
select is((
  select count(*)::integer from pg_constraint
  where conrelid='public.commercial_project_sites'::regclass
    and conname='commercial_project_sites_previous_same_project'
),1,'history linkage has a database-enforced same-project foreign key');
select is((select count(*)::integer from public.quote_request_intakes where quote_request_id='f98b2f08-0000-4000-8000-000000000001' and existing_website_url is null and domain_name is null),1,'site binding does not reinterpret intake website evidence');
select is((select count(*)::integer from public.commercial_projects where customer_id='b1700000-0000-4000-8000-000000000001'),2,'one canonical customer can own multiple independently bound projects');
select is((
  select count(*)::integer
  from pg_constraint as constraint_record
  join pg_class as relation on relation.oid = constraint_record.conrelid
  join pg_namespace as namespace on namespace.oid = relation.relnamespace
  where namespace.nspname = 'public'
    and relation.relname = 'commercial_projects'
    and constraint_record.contype = 'u'
    and constraint_record.conkey = array[(select attnum from pg_attribute where attrelid=relation.oid and attname='customer_id')]::smallint[]
),0,'customer identity remains non-unique so one customer can own multiple projects and sites');

select * from finish();
rollback;
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(42);

select has_column('public', 'quote_request_quotation_issuances', 'issuance_input_sha256', 'preparation input hash has a distinct column');
select has_column('public', 'quote_request_quotation_issuances', 'generation_payload_sha256', 'final generation hash remains explicit');
select has_function('public', 'prepare_quotation_issuance_v2', array['uuid','smallint','smallint','text','uuid','text','text'], 'unambiguous v2 prepare RPC exists');
select has_function('public', 'commit_quotation_issuance_v2', array['uuid','uuid','text','text','text','text','text','smallint','text','bigint','text','bigint','text','text'], 'unambiguous v2 commit RPC exists');
select ok(not has_function_privilege('anon', 'public.prepare_quotation_issuance_v2(uuid,smallint,smallint,text,uuid,text,text)', 'execute'), 'anon cannot prepare through v2');
select ok(not has_function_privilege('authenticated', 'public.commit_quotation_issuance_v2(uuid,uuid,text,text,text,text,text,smallint,text,bigint,text,bigint,text,text)', 'execute'), 'authenticated cannot commit through v2');
select ok(has_function_privilege('service_role', 'public.prepare_quotation_issuance_v2(uuid,smallint,smallint,text,uuid,text,text)', 'execute'), 'service role can prepare through v2');
select ok(has_function_privilege('service_role', 'public.commit_quotation_issuance_v2(uuid,uuid,text,text,text,text,text,smallint,text,bigint,text,bigint,text,text)', 'execute'), 'service role can commit through v2');

create temporary table d3e3a_source as
select approval.id as approval_id, approval.intake_id,
  intake.admin_access_token_hash
from public.quote_request_quotation_approvals as approval
join public.quote_request_intakes as intake on intake.id = approval.intake_id
limit 0;

select is((select count(*)::integer from d3e3a_source), 0, 'focused suite starts without production approval data');

-- The focused contract checks use local synthetic rows and bypass no immutable source guards.
insert into public.quote_requests (id,name,email,website_type,budget,timing,description,privacy_consent,status)
values ('d3ea0000-0000-4000-8000-000000000001','D3E3A','d3e3a@example.test','business','EUR 3.200 t/m EUR 6.000','flexible','D3E3A fixture',true,'approved');
insert into public.quote_request_intakes (
  id,quote_request_id,access_token_hash,access_token_expires_at,status,
  started_at,submitted_at,confirmation,admin_access_token_hash,admin_access_token_expires_at
) values (
  'd3ea1000-0000-4000-8000-000000000001','d3ea0000-0000-4000-8000-000000000001',
  repeat('1',64),clock_timestamp()+interval '1 day','submitted',clock_timestamp(),
  clock_timestamp(),true,repeat('f',64),clock_timestamp()+interval '1 day'
);

create temporary table d3e3a_approval_payload as
select jsonb_build_object(
  'contract_version',1,
  'source_quote_request_id','d3ea0000-0000-4000-8000-000000000001',
  'source_intake_id','d3ea1000-0000-4000-8000-000000000001',
  'pricing_snapshot',jsonb_build_object('snapshot_id','d3ea2000-0000-4000-8000-000000000001','snapshot_contract_version',2,'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1','integrity_mac',repeat('a',64)),
  'currency','EUR',
  'line_items',jsonb_build_array(jsonb_build_object('line_id','website','sequence',1,'product_or_service_code','WEBSITE','description','Websiteontwikkeling','quantity',1,'unit','project','unit_price_minor',100000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',100000,'cost_type','ONE_TIME')),
  'totals',jsonb_build_object('one_time_subtotal_minor',100000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',100000,'vat_amount_minor',21000,'total_gross_minor',121000),
  'discount',jsonb_build_object('discount_type',null,'discount_value_minor',0,'discount_reason',null,'approved_by',null,'approved_at',null),
  'customer_identity',jsonb_build_object('source_quote_request_id','d3ea0000-0000-4000-8000-000000000001','source_intake_id','d3ea1000-0000-4000-8000-000000000001','customer_id',null,'legal_name','D3E3A Customer','contact_name',null,'email','d3e3a@example.test','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null,'source_fields',jsonb_build_object('legal_name','fixture'),'snapshot_sha256',repeat('b',64)),
  'project_scope',jsonb_build_object('project_id',null,'project_title','D3E3A website','project_type','website','scope_summary','Fictieve scope','requested_languages',jsonb_build_array('nl'),'included_page_count',5,'features',jsonb_build_array('contact_form'),'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null,'source_intake_id','d3ea1000-0000-4000-8000-000000000001','source_pricing_snapshot_id','d3ea2000-0000-4000-8000-000000000001','snapshot_sha256',repeat('c',64)),
  'vat_approval',jsonb_build_object('vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant','vat_approved_by','accountant:test','vat_approved_at','2026-08-15T12:00:00Z'),
  'payment_schedule',jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledige betaling','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null)),'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
  'validity',jsonb_build_object('valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30,'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
  'legal_references',jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','terms_sha256',repeat('d',64),'terms_status','APPROVED','agreement_template_reference',null,'agreement_template_version',null,'agreement_template_sha256',null)
) as payload;

insert into public.quote_request_pricing_snapshots (
  id,intake_id,snapshot_contract_version,config_version,config_hash,
  normalized_evidence,calculation,package_advice,budget_evaluation
) values (
  'd3ea2000-0000-4000-8000-000000000001','d3ea1000-0000-4000-8000-000000000001',2,'1.0.0',repeat('1',64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
);
insert into public.quote_request_pricing_snapshot_integrity(snapshot_id,algorithm_version,key_id,mac)
values('d3ea2000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('a',64));
insert into public.quote_request_quotation_approval_drafts(id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_payload,payload_fingerprint,idempotency_key,created_by)
select 'd3ea3000-0000-4000-8000-000000000001','d3ea0000-0000-4000-8000-000000000001','d3ea1000-0000-4000-8000-000000000001','d3ea2000-0000-4000-8000-000000000001',1,payload,public.quotation_approval_payload_sha256_v1(payload),'d3ea4000-0000-4000-8000-000000000001','admin:test' from d3e3a_approval_payload;
insert into public.quote_request_quotation_approvals(id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_version,approved_payload,payload_sha256,approved_by,approved_at)
select 'd3ea5000-0000-4000-8000-000000000001','d3ea3000-0000-4000-8000-000000000001','d3ea0000-0000-4000-8000-000000000001','d3ea1000-0000-4000-8000-000000000001','d3ea2000-0000-4000-8000-000000000001',1,1,payload,public.quotation_approval_payload_sha256_v1(payload),'admin:test',clock_timestamp() from d3e3a_approval_payload;
insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac)
values('d3ea5000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('e',64));

select is((select quotation_number from public.prepare_quotation_issuance_v2('d3ea5000-0000-4000-8000-000000000001',2030::smallint,1::smallint,repeat('1',64),'d3ea6000-0000-4000-8000-000000000001',repeat('f',64),'admin:test')),'LWS-OFF-2030-0001','v2 prepare allocates identity from preparation input');
select is((select issuance_input_sha256::text from public.quote_request_quotation_issuances),repeat('1',64),'PREPARED stores preparation input hash');
select is((select generation_payload_sha256::text from public.quote_request_quotation_issuances),null,'PREPARED has no final generation payload hash');
select is((select was_created from public.prepare_quotation_issuance_v2('d3ea5000-0000-4000-8000-000000000001',2030::smallint,1::smallint,repeat('1',64),'d3ea6000-0000-4000-8000-000000000001',repeat('f',64),'admin:test')),false,'v2 prepare retry is deterministic');
select throws_ok($$select * from public.prepare_quotation_issuance_v2('d3ea5000-0000-4000-8000-000000000001',2030::smallint,1::smallint,repeat('2',64),'d3ea6000-0000-4000-8000-000000000001',repeat('f',64),'admin:test')$$,'P0001','IDEMPOTENCY_CONFLICT','conflicting preparation input is rejected');
select throws_ok($$select * from public.prepare_quotation_issuance_v2('d3ea5000-0000-4000-8000-000000000001',2031::smallint,1::smallint,repeat('1',64),'d3ea6000-0000-4000-8000-000000000001',repeat('f',64),'admin:test')$$,'P0001','IDEMPOTENCY_CONFLICT','same prepare key with different issue year is rejected');
select throws_ok($$select * from public.commit_quotation_issuance_v2((select id from public.quote_request_quotation_issuances),'d3ea7000-0000-4000-8000-000000000001',repeat('1',64),'bad','LWS_QUOTATION_NL_BE','1.0.0-technical','3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE',1::smallint,repeat('4',64),100,null,null,'admin:test',repeat('f',64))$$,'22023','GENERATION_PAYLOAD_HASH_MISMATCH','malformed final generation hash is rejected');
select is((select status from public.commit_quotation_issuance_v2((select id from public.quote_request_quotation_issuances),'d3ea7000-0000-4000-8000-000000000001',repeat('1',64),repeat('2',64),'LWS_QUOTATION_NL_BE','1.0.0-technical','3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE',1::smallint,repeat('4',64),100,null,null,'admin:test',repeat('f',64))),'ISSUED','v2 commit freezes definitive generation hash');
select is((select generation_payload_sha256::text from public.quote_request_quotation_issuances),repeat('2',64),'ISSUED stores definitive generation hash');
select isnt((select issuance_input_sha256::text from public.quote_request_quotation_issuances),(select generation_payload_sha256::text from public.quote_request_quotation_issuances),'preparation and generation hashes have distinct semantics');
select is((select was_committed from public.commit_quotation_issuance_v2((select id from public.quote_request_quotation_issuances),'d3ea7000-0000-4000-8000-000000000001',repeat('1',64),repeat('2',64),'LWS_QUOTATION_NL_BE','1.0.0-technical','3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE',1::smallint,repeat('4',64),100,null,null,'admin:test',repeat('f',64))),false,'v2 commit retry is stable');
select throws_ok($$update public.quote_request_quotation_issuances set generation_payload_sha256=repeat('9',64)$$,'55000','QUOTATION_ISSUANCE_IMMUTABLE','final generation hash is immutable after issue');

insert into public.quote_request_quotation_approvals(id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_version,approved_payload,payload_sha256,approved_by,approved_at)
select 'd3ea5000-0000-4000-8000-000000000002',draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,2,approved_payload,payload_sha256,approved_by,clock_timestamp() from public.quote_request_quotation_approvals where id='d3ea5000-0000-4000-8000-000000000001';
insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac)
values('d3ea5000-0000-4000-8000-000000000002','hmac-sha256-v1','v1',repeat('e',64));
select is((select status from public.prepare_quotation_issuance_v2('d3ea5000-0000-4000-8000-000000000002',2030::smallint,1::smallint,repeat('5',64),'d3ea6000-0000-4000-8000-000000000002',repeat('f',64),'admin:test')),'PREPARED','second v2 issuance prepares without final hash');
select is((select status from public.void_quotation_issuance_v1((select id from public.quote_request_quotation_issuances where approval_id='d3ea5000-0000-4000-8000-000000000002'),'Generation unavailable','admin:test','d3ea8000-0000-4000-8000-000000000001',repeat('f',64))),'VOID','PREPARED v2 issuance may become VOID');
select is((select generation_payload_sha256::text from public.quote_request_quotation_issuances where status='VOID'),null,'VOID retains no final generation hash');
select throws_ok($$select * from public.commit_quotation_issuance_v2((select id from public.quote_request_quotation_issuances where status='VOID'),'d3ea7000-0000-4000-8000-000000000002',repeat('5',64),repeat('6',64),'LWS_QUOTATION_NL_BE','1.0.0-technical','3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE',1::smallint,repeat('4',64),100,null,null,'admin:test',repeat('f',64))$$,'P0001','ISSUANCE_VOID','VOID can never gain a final generation hash');
select is((select next_sequence from public.quotation_number_counters where year=2030),3,'VOID number remains permanently consumed');
select is((select count(*)::integer from public.quote_request_quotation_issuances),2,'v2 retries create no duplicate issuance');
select is((select count(*)::integer from public.quote_request_quotation_issuance_operations),4,'v2 operation ledger records successful operations only');
select is((select count(*)::integer from public.quote_request_quotation_issuances where status='PREPARED'),0,'focused lifecycle leaves no ambiguous PREPARED row');

create temporary table d3e10_delivery as
select * from public.prepare_issued_quotation_delivery_with_capability_v1(
  (select id from public.quote_request_quotation_issuances where status='ISSUED'),repeat('9',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',clock_timestamp()+interval '3 days',
  'd3e10000-0000-4000-8000-000000000001','d3e10000-0000-4000-8000-000000000002',repeat('f',64),'admin:test');
select is((select recipient_email from d3e10_delivery),'d3e3a@example.test','delivery recipient comes from approval snapshot');
select is((select client_name from d3e10_delivery),'D3E3A Customer','delivery client name comes from approval snapshot');
select is((select stored_token_digest from d3e10_delivery),repeat('9',64),'delivery stores only capability digest authority');
select ok((select encrypted_token like 'v1.%' from d3e10_delivery),'delivery job stores retry ciphertext');
select is((select capability_id from public.prepare_issued_quotation_delivery_with_capability_v1(
  (select id from public.quote_request_quotation_issuances where status='ISSUED'),repeat('8',64),
  'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',clock_timestamp()+interval '2 days',
  'd3e10000-0000-4000-8000-000000000001','d3e10000-0000-4000-8000-000000000002',repeat('f',64),'admin:test')),
  (select capability_id from d3e10_delivery),'delivery replay retains original capability');
select is((select count(*)::integer from public.quote_request_quotation_acceptance_capabilities),1,'delivery replay creates no second capability');

create temporary table d3e10_acceptance as select public.submit_quotation_acceptance_capability_v1(
  repeat('9',64),'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical','D3E10 Acceptant','acceptant@example.test','D3E10 BV','Bestuurder',true,'d3e10000-0000-4000-8000-000000000003') as result;
select is((select result->>'state' from d3e10_acceptance),'ACCEPTED','capability acceptance succeeds before confirmations');
select is((select recipient_email from public.prepare_quotation_acceptance_confirmation_v1(
  (select id from public.quote_request_quotation_acceptances),'ACCEPTANCE_CONFIRMATION_CUSTOMER','ACCEPTANCE_CONFIRMATION_CUSTOMER_NL_BE_v1','d3e10000-0000-4000-8000-000000000004','service:quotation-acceptance',null)),
  'd3e3a@example.test','customer confirmation recipient comes from approval snapshot');
select is((select recipient_email from public.prepare_quotation_acceptance_confirmation_v1(
  (select id from public.quote_request_quotation_acceptances),'ACCEPTANCE_CONFIRMATION_INTERNAL','ACCEPTANCE_CONFIRMATION_INTERNAL_NL_BE_v1','d3e10000-0000-4000-8000-000000000005','service:quotation-acceptance','internal@example.test')),
  'internal@example.test','internal confirmation uses explicit trusted recipient');
select is((select count(*)::integer from public.quote_request_email_jobs where kind in('quotation_delivery','quotation_acceptance_customer','quotation_acceptance_internal')),3,'lifecycle creates three distinct email jobs');
select is((select count(*)::integer from public.quote_request_quotation_acceptances),1,'confirmation preparation cannot duplicate or roll back acceptance');
select is((
  (select count(*) from public.sdf_m1_invoice_candidates where quote_request_id='d3ea0000-0000-4000-8000-000000000001')
  + (select count(*) from public.sdf_m1_invoice_issuances as issuance
     join public.sdf_m1_invoice_candidates as candidate on candidate.candidate_id=issuance.candidate_id
     where candidate.quote_request_id='d3ea0000-0000-4000-8000-000000000001')
)::integer,0,'delivery and confirmation lifecycle creates no invoice authority');
select throws_ok($$update public.quote_request_quotation_email_orchestrations set recipient_email='changed@example.test'$$,'55000','QUOTATION_EMAIL_ORCHESTRATION_IMMUTABLE','delivery evidence is immutable');

select * from finish();
rollback;

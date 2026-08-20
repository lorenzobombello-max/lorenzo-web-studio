begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(54);

select has_function('public','list_operator_applications_v1',array['integer','integer'],'application list RPC exists');
select has_function('public','get_operator_application_v1',array['uuid','text'],'application detail RPC exists');
select has_function('public','promote_operator_application_v1',array['uuid','uuid','text'],'application promotion RPC exists');
select ok(has_function_privilege('authenticated','public.list_operator_applications_v1(integer,integer)','execute'),'authenticated role can enter the guarded list RPC');
select ok(not has_function_privilege('anon','public.list_operator_applications_v1(integer,integer)','execute'),'anonymous role cannot list applications');
select ok(not has_function_privilege('service_role','public.list_operator_applications_v1(integer,integer)','execute'),'service role cannot list applications directly');
select ok(has_function_privilege('authenticated','public.get_operator_application_v1(uuid,text)','execute'),'authenticated role can enter the guarded detail RPC');
select ok(not has_function_privilege('anon','public.get_operator_application_v1(uuid,text)','execute'),'anonymous role cannot inspect application details');
select ok(not has_function_privilege('service_role','public.get_operator_application_v1(uuid,text)','execute'),'service role cannot inspect application details directly');
select ok(not has_function_privilege('service_role','public.promote_operator_application_v1(uuid,uuid,text)','execute'),'service role cannot impersonate a human promotion caller');

insert into auth.users (id, email) values
  ('a1000000-0000-4000-8000-000000000001','owner@example.test'),
  ('a1000000-0000-4000-8000-000000000002','admin@example.test'),
  ('a1000000-0000-4000-8000-000000000003','operator@example.test'),
  ('a1000000-0000-4000-8000-000000000004','disabled@example.test'),
  ('a1000000-0000-4000-8000-000000000005','unknown@example.test');

insert into public.commercial_operators (auth_user_id, display_name, role, status) values
  ('a1000000-0000-4000-8000-000000000001','Test Owner','owner','ACTIVE'),
  ('a1000000-0000-4000-8000-000000000002','Test Admin','admin','ACTIVE'),
  ('a1000000-0000-4000-8000-000000000003','Test Operator','operator','ACTIVE'),
  ('a1000000-0000-4000-8000-000000000004','Disabled Operator','admin','DISABLED');

insert into public.quote_requests (
  id, application_reference, request_kind, name, company, email, website_type, budget, timing,
  description, privacy_consent, status
) values
  ('a1100000-0000-4000-8000-000000000001','LWS-AAN-2099-0001','website','Accepted Application','Accepted BV','accepted@example.test','business','Meer dan EUR 6.000','flexible','Accepted operator handoff fixture',true,'approved'),
  ('a1100000-0000-4000-8000-000000000002','LWS-AAN-2099-0002','website','Pending Application',null,'pending@example.test','business','Meer dan EUR 6.000','flexible','Unaccepted operator handoff fixture',true,'approved'),
  ('a1100000-0000-4000-8000-000000000003',null,'slimme_documentenflow','Documentenflow Application','Documentenflow BV','documentenflow@example.test',null,null,null,'Documentenflow application without website fields',true,'approved');

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, confirmation
) values
  ('a1200000-0000-4000-8000-000000000001','a1100000-0000-4000-8000-000000000001',repeat('1',64),clock_timestamp()+interval '1 day','submitted',clock_timestamp(),clock_timestamp(),true),
  ('a1200000-0000-4000-8000-000000000002','a1100000-0000-4000-8000-000000000002',repeat('2',64),clock_timestamp()+interval '1 day','submitted',clock_timestamp(),clock_timestamp(),true);

alter table public.quote_request_intakes disable trigger trg_quote_request_intake_kind_guard;
insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, confirmation
) values (
  'a1200000-0000-4000-8000-000000000003','a1100000-0000-4000-8000-000000000003',repeat('3',64),clock_timestamp()+interval '1 day','submitted',clock_timestamp(),clock_timestamp(),true
);
alter table public.quote_request_intakes enable trigger trg_quote_request_intake_kind_guard;

create temporary table handoff_approval_payload as
select jsonb_build_object(
  'contract_version',1,
  'source_quote_request_id','a1100000-0000-4000-8000-000000000001',
  'source_intake_id','a1200000-0000-4000-8000-000000000001',
  'pricing_snapshot',jsonb_build_object('snapshot_id','a1300000-0000-4000-8000-000000000001','snapshot_contract_version',2,'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1','integrity_mac',repeat('a',64)),
  'currency','EUR',
  'line_items',jsonb_build_array(jsonb_build_object('line_id','website','sequence',1,'product_or_service_code','WEBSITE','description','Websiteontwikkeling','quantity',1,'unit','project','unit_price_minor',350000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',350000,'cost_type','ONE_TIME')),
  'totals',jsonb_build_object('one_time_subtotal_minor',350000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',350000,'vat_amount_minor',73500,'total_gross_minor',423500),
  'discount',jsonb_build_object('discount_type',null,'discount_value_minor',0,'discount_reason',null,'approved_by',null,'approved_at',null),
  'customer_identity',jsonb_build_object('source_quote_request_id','a1100000-0000-4000-8000-000000000001','source_intake_id','a1200000-0000-4000-8000-000000000001','customer_id',null,'legal_name','Accepted BV','contact_name','Accepted Application','email','accepted@example.test','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null,'source_fields',jsonb_build_object('legal_name','fixture'),'snapshot_sha256',repeat('b',64)),
  'project_scope',jsonb_build_object('project_id',null,'project_title','Accepted website','project_type','website','scope_summary','Fictieve scope','requested_languages',jsonb_build_array('nl'),'included_page_count',5,'features',jsonb_build_array('contact_form'),'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null,'source_intake_id','a1200000-0000-4000-8000-000000000001','source_pricing_snapshot_id','a1300000-0000-4000-8000-000000000001','snapshot_sha256',repeat('c',64)),
  'vat_approval',jsonb_build_object('vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant','vat_approved_by','accountant:test','vat_approved_at','2026-08-15T12:00:00Z'),
  'payment_schedule',jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledige betaling','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null)),'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
  'validity',jsonb_build_object('valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30,'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
  'legal_references',jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','terms_sha256',repeat('d',64),'terms_status','APPROVED','agreement_template_reference',null,'agreement_template_version',null,'agreement_template_sha256',null)
) as payload;

insert into public.quote_request_pricing_snapshots (
  id,intake_id,snapshot_contract_version,config_version,config_hash,
  normalized_evidence,calculation,package_advice,budget_evaluation
) values (
  'a1300000-0000-4000-8000-000000000001','a1200000-0000-4000-8000-000000000001',2,'1.0.0',repeat('1',64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
);
insert into public.quote_request_pricing_snapshot_integrity(snapshot_id,algorithm_version,key_id,mac)
values('a1300000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('a',64));
insert into public.quote_request_quotation_approval_drafts(id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_payload,payload_fingerprint,idempotency_key,created_by)
select 'a1400000-0000-4000-8000-000000000001','a1100000-0000-4000-8000-000000000001','a1200000-0000-4000-8000-000000000001','a1300000-0000-4000-8000-000000000001',1,payload,public.quotation_approval_payload_sha256_v1(payload),'a1400000-0000-4000-8000-000000000002','admin:test' from handoff_approval_payload;
insert into public.quote_request_quotation_approvals(id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_version,approved_payload,payload_sha256,approved_by,approved_at)
select 'a1500000-0000-4000-8000-000000000001','a1400000-0000-4000-8000-000000000001','a1100000-0000-4000-8000-000000000001','a1200000-0000-4000-8000-000000000001','a1300000-0000-4000-8000-000000000001',1,1,payload,public.quotation_approval_payload_sha256_v1(payload),'admin:test',clock_timestamp() from handoff_approval_payload;
insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac)
values('a1500000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('e',64));

insert into public.quote_request_quotation_issuances (
  id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,
  template_id,template_version,template_sha256,generation_contract_version,
  issuance_input_sha256,generation_payload_sha256,docx_sha256,docx_bytes,
  prepare_idempotency_key,prepare_fingerprint,commit_idempotency_key,commit_fingerprint
) values (
  'a1600000-0000-4000-8000-000000000001','LWS-OFF-2099-0001',1,'ISSUED','a1500000-0000-4000-8000-000000000001',clock_timestamp(),'admin:test',
  'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,
  repeat('4',64),repeat('5',64),repeat('6',64),12345,
  'a1600000-0000-4000-8000-000000000002',repeat('7',64),'a1600000-0000-4000-8000-000000000003',repeat('8',64)
);

create temporary table handoff_acceptance_payload as
select jsonb_build_object(
  'acceptance_contract_version',1,'issuance_id','a1600000-0000-4000-8000-000000000001',
  'quotation_number','LWS-OFF-2099-0001','quotation_version',1,
  'customer_identity_sha256',repeat('b',64),'generation_payload_sha256',repeat('5',64),
  'template',jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',repeat('3',64)),
  'docx',jsonb_build_object('sha256',repeat('6',64),'bytes',12345),
  'acceptance_terms',jsonb_build_object('terms_id','LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','terms_version','1.0.0-technical','terms_sha256',repeat('9',64)),
  'actor',jsonb_build_object('name','Test Acceptant','email','acceptant@example.test','organization','Accepted BV','role','Bestuurder'),
  'authority_declaration',true,'accepted_at','2026-08-20T12:00:00.000000Z'
) as payload;

insert into public.quote_request_quotation_acceptances (
  id,issuance_id,quotation_number,quotation_version,customer_identity_sha256,customer_legal_name,
  generation_payload_sha256,template_id,template_version,template_sha256,docx_sha256,docx_bytes,
  acceptance_contract_version,acceptance_terms_id,acceptance_terms_version,acceptance_terms_sha256,
  accepting_name,accepting_email,accepting_organization,accepting_role,authority_declaration,
  acceptance_payload,acceptance_payload_sha256,semantic_request_fingerprint,accepted_at,created_at
)
select
  'a1700000-0000-4000-8000-000000000001','a1600000-0000-4000-8000-000000000001','LWS-OFF-2099-0001',1,repeat('b',64),'Accepted BV',
  repeat('5',64),'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),repeat('6',64),12345,
  1,'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',repeat('9',64),
  'Test Acceptant','acceptant@example.test','Accepted BV','Bestuurder',true,
  payload,public.quotation_acceptance_payload_sha256_v1(payload),repeat('f',64),
  '2026-08-20T12:00:00Z','2026-08-20T12:00:00Z'
from handoff_acceptance_payload;

create temporary table immutable_evidence_before as
select acceptance_payload_sha256::text as acceptance_hash,
  (select payload_sha256 from public.quote_request_quotation_approvals where id='a1500000-0000-4000-8000-000000000001') as approval_hash
from public.quote_request_quotation_acceptances
where id='a1700000-0000-4000-8000-000000000001';

\if :{?HANDOFF_FIXTURE_ONLY}
commit;
\quit
\endif

select throws_ok($$select public.list_operator_applications_v1()$$,'42501','HUMAN_JWT_REQUIRED','missing human JWT is rejected');
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000005',true);
select throws_ok($$select public.list_operator_applications_v1()$$,'42501','UNKNOWN_OPERATOR','unknown human is rejected');
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000004',true);
select throws_ok($$select public.list_operator_applications_v1()$$,'42501','OPERATOR_DISABLED','disabled operator is rejected');
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',true);
select throws_ok($$select public.list_operator_applications_v1()$$,'42501','APPLICATION_SCOPE_DENIED','project-scoped operator cannot inspect pre-project applications');

select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
select is(jsonb_array_length(public.list_operator_applications_v1()),3,'owner sees current and legacy submitted applications');
select is((select value->>'request_kind' from jsonb_array_elements(public.list_operator_applications_v1()) where value->>'quote_request_id'='a1100000-0000-4000-8000-000000000001'),'website','application list exposes the stored website request kind');
select is((select value->>'request_kind' from jsonb_array_elements(public.list_operator_applications_v1()) where value->>'quote_request_id'='a1100000-0000-4000-8000-000000000003'),'slimme_documentenflow','application list exposes the stored Documentenflow request kind');
select is(public.get_operator_application_v1(null,'LWS-AAN-2099-0001')->>'name','Accepted Application','owner resolves detail by application reference');
select is(public.get_operator_application_v1(null,'LWS-AAN-2099-0001')->>'request_kind','website','application detail exposes the same stored website request kind');
select is(public.get_operator_application_v1('a1100000-0000-4000-8000-000000000003',null)->>'request_kind','slimme_documentenflow','application detail exposes the same stored Documentenflow request kind');
select is(jsonb_build_array(
  public.get_operator_application_v1('a1100000-0000-4000-8000-000000000003',null)->'website_type',
  public.get_operator_application_v1('a1100000-0000-4000-8000-000000000003',null)->'budget',
  public.get_operator_application_v1('a1100000-0000-4000-8000-000000000003',null)->'timing'
),'[null, null, null]'::jsonb,'Documentenflow detail does not fabricate website fields');
select is(public.get_operator_application_v1('a1100000-0000-4000-8000-000000000002',null)->'acceptance','null'::jsonb,'unaccepted detail has no fabricated acceptance');
select is(public.get_operator_application_v1(null,'LWS-AAN-2099-0001')->'project','null'::jsonb,'accepted but unpromoted dossier has no fabricated project');
select is(public.get_operator_application_v1(null,'LWS-AAN-2099-0001')->'pricing'->>'known_minimum_minor','180000','application dossier uses the persisted pricing minimum');
select is(public.get_operator_application_v1(null,'LWS-AAN-2099-0001')->'quotation'->>'issuance_status','ISSUED','application dossier exposes authoritative quotation issuance state');
select is(public.get_operator_application_v1(null,'LWS-AAN-2099-0001')->'quotation'->>'binary_archive_available','false','quotation metadata does not pretend a binary archive exists');
select is(public.get_operator_application_v1('a1100000-0000-4000-8000-000000000002',null)->'pricing','null'::jsonb,'application without pricing has an explicit empty pricing state');
select is(public.get_operator_application_v1('a1100000-0000-4000-8000-000000000002',null)->'quotation','null'::jsonb,'application without quotation evidence has an explicit empty quotation state');
select is(public.get_operator_application_v1('a1100000-0000-4000-8000-000000000003',null)->'application_reference','null'::jsonb,'legacy UUID lookup does not fabricate an application reference');
select throws_ok($$select public.get_operator_application_v1(null,'bad')$$,'22023','INVALID_APPLICATION_REFERENCE','malformed human locator is rejected');
select throws_ok($$select public.get_operator_application_v1(null,null)$$,'22023','EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED','missing locator is rejected');
select throws_ok($$select public.get_operator_application_v1('a1100000-0000-4000-8000-000000000001','LWS-AAN-2099-0001')$$,'22023','EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED','ambiguous locator is rejected');
select throws_ok($$select public.promote_operator_application_v1('a1800000-0000-4000-8000-000000000001','a1100000-0000-4000-8000-000000000002',null)$$,'P0001','APPLICATION_NOT_ACCEPTED','unaccepted application cannot be promoted');

select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
select is(jsonb_array_length(public.list_operator_applications_v1()),3,'admin has the same global application visibility');

create temporary table first_promotion as
select public.promote_operator_application_v1(
  'a1800000-0000-4000-8000-000000000002',null,'LWS-AAN-2099-0001'
) as result;
select is((select result->>'was_created' from first_promotion),'true','first promotion creates the commercial project');
select is((select result->>'accepted_total_minor' from first_promotion),'350000','promotion derives the accepted total from approval evidence');
select is((select count(*)::integer from public.commercial_projects),1,'promotion creates exactly one project');
select is((select count(*)::integer from public.commercial_customers),1,'promotion creates exactly one customer record');
select is(
  public.promote_operator_application_v1('a1800000-0000-4000-8000-000000000003','a1100000-0000-4000-8000-000000000001',null)->>'project_id',
  (select result->>'project_id' from first_promotion),
  'repeated promotion with another idempotency key returns the same project'
);
select is((select count(*)::integer from public.commercial_projects),1,'repeated promotion creates no duplicate project');
select ok(public.get_operator_application_v1(null,'LWS-AAN-2099-0001')->'project'->>'created_at' is not null,'promoted application dossier exposes project creation time');
select is(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->>'current_state','QUOTE_ACCEPTED','project dossier exposes the authoritative commercial state');
select is(jsonb_array_length(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->'obligations'),0,'project dossier does not fabricate obligations before milestone preparation');
select is(((public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->>'m1_minor')::bigint+(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->>'m2_minor')::bigint+(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->>'m3_minor')::bigint)::text,'350000','encoded milestone summary reconciles to the accepted project total');
select is(concat_ws('/',public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->>'m1_minor',public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->>'m2_minor',public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->>'m3_minor'),'140000/140000/70000','project contract exposes the authoritative 40/40/20 split without payment evidence');
select is(jsonb_array_length(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->'documents'),0,'project dossier has an honest empty commercial-document state');
select is(jsonb_array_length(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->'recurring_services'),0,'project dossier has an honest empty recurring-service state');
select is(jsonb_array_length(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->'timeline'),2,'project dossier combines workflow and audit creation events');
select ok((select bool_and(previous_time >= occurred_at) from (select occurred_at,lag(occurred_at) over (order by ordinal) as previous_time from jsonb_array_elements(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->'timeline') with ordinality as event(value,ordinal) cross join lateral (select (event.value->>'occurred_at')::timestamptz as occurred_at) parsed) ordered where previous_time is not null),'project timeline is newest first');

select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000003',true);
select throws_ok(format('select public.get_commercial_project_view_v2(%L)',(select result->>'project_id' from first_promotion)),'42501','PROJECT_SCOPE_DENIED','project-scoped operator cannot enumerate an ungranted project');
insert into public.commercial_operator_project_grants(operator_id,project_id,access_level,granted_by)
select scoped.operator_id,(first.result->>'project_id')::uuid,'read_only',admin.operator_id
from public.commercial_operators as scoped
cross join first_promotion as first
cross join public.commercial_operators as admin
where scoped.auth_user_id='a1000000-0000-4000-8000-000000000003'
  and admin.auth_user_id='a1000000-0000-4000-8000-000000000002';
select is(public.get_commercial_project_view_v2((select (result->>'project_id')::uuid from first_promotion))->>'project_id',(select result->>'project_id' from first_promotion),'active project grant authorizes only the granted dossier');
update public.commercial_operator_project_grants set revoked_at=clock_timestamp();
select throws_ok(format('select public.get_commercial_project_view_v2(%L)',(select result->>'project_id' from first_promotion)),'42501','PROJECT_SCOPE_DENIED','revoked project grant denies dossier access');
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
select throws_ok($$select public.get_commercial_project_view_v2('a1900000-0000-4000-8000-000000000001')$$,'23503','PROJECT_NOT_FOUND','arbitrary project UUID enumeration fails closed');
select is(
  (select row(acceptance_payload_sha256::text,(select payload_sha256 from public.quote_request_quotation_approvals where id='a1500000-0000-4000-8000-000000000001'))::text from public.quote_request_quotation_acceptances where id='a1700000-0000-4000-8000-000000000001'),
  (select row(acceptance_hash,approval_hash)::text from immutable_evidence_before),
  'promotion leaves immutable acceptance and approval evidence unchanged'
);

select * from finish();
rollback;
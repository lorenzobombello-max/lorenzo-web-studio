begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(56);

create function pg_temp.legacy_authority_snapshot(p_quote_request_id uuid)
returns text
language sql
stable
as $$
  select row(
    quote_request_id,
    support_reference,
    application_reference,
    request_kind,
    dossier_created_at,
    authoritative_browse_at,
    identity_evidence_sha256
  )::text
  from lws_internal.legacy_test_cleanup_authorities
  where quote_request_id = p_quote_request_id
$$;

create function pg_temp.expected_legacy_authority_snapshot(
  p_quote_request_id uuid,
  p_support_reference text,
  p_application_reference text,
  p_request_kind text,
  p_dossier_created_at timestamptz,
  p_authoritative_browse_at timestamptz
)
returns text
language sql
immutable
as $$
  select row(
    p_quote_request_id,
    p_support_reference,
    p_application_reference,
    p_request_kind,
    p_dossier_created_at,
    p_authoritative_browse_at,
    lws_internal.legacy_test_cleanup_identity_sha256_v1(
      p_quote_request_id,
      p_support_reference,
      p_application_reference,
      p_request_kind,
      p_dossier_created_at,
      p_authoritative_browse_at,
      'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY',
      'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23',
      '20260823190000_add_legacy_test_cleanup_authority'
    )
  )::text
$$;

select has_table('lws_internal', 'legacy_test_cleanup_authorities', 'legacy cleanup authority exists');
select has_table('lws_internal', 'legacy_test_cleanup_consumptions', 'legacy cleanup consumption evidence exists');
select has_function('lws_internal', 'assert_legacy_test_cleanup_candidate_v1', array['uuid'], 'candidate assertion exists without a delete command');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities), 11, 'authority contains exactly eleven migration-owned rows');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_consumptions), 0, 'migration consumes no authority');
select is((select count(distinct quote_request_id)::integer from lws_internal.legacy_test_cleanup_authorities), 11, 'all authority UUIDs are unique');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities where request_kind = 'website'), 9, 'nine Website identities are frozen');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities where request_kind = 'slimme_documentenflow'), 2, 'two SDF identities are frozen');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities where application_reference is not null), 2, 'only the two assigned application references are frozen');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities where rtrim(identity_evidence_sha256) ~ '^[0-9a-f]{64}$'), 11, 'all frozen identities have deterministic evidence hashes');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities where identity_evidence_sha256 is distinct from lws_internal.legacy_test_cleanup_identity_sha256_v1(quote_request_id,support_reference,application_reference,request_kind,dossier_created_at,authoritative_browse_at,authority_reason,source_checkpoint,source_migration)), 0, 'stored evidence hashes reproduce from frozen identity fields');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities where quote_request_id in (
  'a3e6cfbc-a575-4c8a-a9ca-1f091aba5414','f98b2f08-e816-4ca5-85eb-5f05fa5045c6','388e8887-8b20-4300-b1e8-183718fe6b57','620b3fa5-2e6b-4439-9d22-741b8541fbdf','d3752349-3489-4c19-bd03-f0cc076b5607','741de441-04f7-41e9-88fe-da92d699e37c','0696171e-a315-4c03-b402-ba0b689abfbc','5c9a89e7-9af1-4ed0-990d-6ebe268fa871','a4e6cbb0-583e-4d0b-86dc-d0c7a5de9d8f','8c7ed4d4-7ff4-4e9c-9f6e-7fd314c1c2b4','19877689-7c72-4ad4-9a7c-7b9459b22ea1'
)), 11, 'authority contains exactly the reviewed UUID set');
select is(pg_temp.legacy_authority_snapshot('a3e6cfbc-a575-4c8a-a9ca-1f091aba5414'),pg_temp.expected_legacy_authority_snapshot('a3e6cfbc-a575-4c8a-a9ca-1f091aba5414','#A3E6CFBC','LWS-AAN-2026-0002','website','2026-08-23T04:11:32.587019Z','2026-08-23T07:39:10.676440Z'),'authority snapshot 1/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('f98b2f08-e816-4ca5-85eb-5f05fa5045c6'),pg_temp.expected_legacy_authority_snapshot('f98b2f08-e816-4ca5-85eb-5f05fa5045c6','#F98B2F08','LWS-AAN-2026-0001','website','2026-08-23T04:46:03.906006Z','2026-08-23T06:38:13.263818Z'),'authority snapshot 2/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('388e8887-8b20-4300-b1e8-183718fe6b57'),pg_temp.expected_legacy_authority_snapshot('388e8887-8b20-4300-b1e8-183718fe6b57','#388E8887',null,'website','2026-08-18T04:38:02.741551Z','2026-08-18T09:21:18.906106Z'),'authority snapshot 3/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('620b3fa5-2e6b-4439-9d22-741b8541fbdf'),pg_temp.expected_legacy_authority_snapshot('620b3fa5-2e6b-4439-9d22-741b8541fbdf','#620B3FA5',null,'website','2026-08-18T06:41:37.328379Z','2026-08-18T06:51:23.983507Z'),'authority snapshot 4/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('d3752349-3489-4c19-bd03-f0cc076b5607'),pg_temp.expected_legacy_authority_snapshot('d3752349-3489-4c19-bd03-f0cc076b5607','#D3752349',null,'slimme_documentenflow','2026-08-18T06:40:00.735922Z','2026-08-18T06:40:00.735922Z'),'authority snapshot 5/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('741de441-04f7-41e9-88fe-da92d699e37c'),pg_temp.expected_legacy_authority_snapshot('741de441-04f7-41e9-88fe-da92d699e37c','#741DE441',null,'website','2026-08-18T00:20:01.917620Z','2026-08-18T02:57:54.766587Z'),'authority snapshot 6/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('0696171e-a315-4c03-b402-ba0b689abfbc'),pg_temp.expected_legacy_authority_snapshot('0696171e-a315-4c03-b402-ba0b689abfbc','#0696171E',null,'slimme_documentenflow','2026-08-17T23:52:15.685429Z','2026-08-17T23:52:15.685429Z'),'authority snapshot 7/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('5c9a89e7-9af1-4ed0-990d-6ebe268fa871'),pg_temp.expected_legacy_authority_snapshot('5c9a89e7-9af1-4ed0-990d-6ebe268fa871','#5C9A89E7',null,'website','2026-08-09T21:55:51.188608Z','2026-08-09T22:09:30.213079Z'),'authority snapshot 8/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('a4e6cbb0-583e-4d0b-86dc-d0c7a5de9d8f'),pg_temp.expected_legacy_authority_snapshot('a4e6cbb0-583e-4d0b-86dc-d0c7a5de9d8f','#A4E6CBB0',null,'website','2026-08-09T01:12:16.064983Z','2026-08-09T11:42:36.394692Z'),'authority snapshot 9/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('8c7ed4d4-7ff4-4e9c-9f6e-7fd314c1c2b4'),pg_temp.expected_legacy_authority_snapshot('8c7ed4d4-7ff4-4e9c-9f6e-7fd314c1c2b4','#8C7ED4D4',null,'website','2026-08-08T19:40:16.615872Z','2026-08-08T19:59:40.566391Z'),'authority snapshot 10/11 is exact, including evidence hash');
select is(pg_temp.legacy_authority_snapshot('19877689-7c72-4ad4-9a7c-7b9459b22ea1'),pg_temp.expected_legacy_authority_snapshot('19877689-7c72-4ad4-9a7c-7b9459b22ea1','#19877689',null,'website','2026-08-08T14:54:51.783217Z','2026-08-08T15:55:13.497810Z'),'authority snapshot 11/11 is exact, including evidence hash');

select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='lws_internal.legacy_test_cleanup_authorities'::regclass), 'authority has RLS and FORCE RLS');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='lws_internal.legacy_test_cleanup_consumptions'::regclass), 'consumption evidence has RLS and FORCE RLS');
select ok(not has_table_privilege('anon','lws_internal.legacy_test_cleanup_authorities','select,insert,update,delete'), 'anon has no authority table rights');
select ok(not has_table_privilege('authenticated','lws_internal.legacy_test_cleanup_authorities','select,insert,update,delete'), 'authenticated has no authority table rights');
select ok(not has_table_privilege('service_role','lws_internal.legacy_test_cleanup_authorities','select,insert,update,delete'), 'service role has no authority table rights');
select ok(not has_table_privilege('anon','lws_internal.legacy_test_cleanup_consumptions','select,insert,update,delete'), 'anon has no consumption table rights');
select ok(not has_table_privilege('authenticated','lws_internal.legacy_test_cleanup_consumptions','select,insert,update,delete'), 'authenticated has no consumption table rights');
select ok(not has_table_privilege('service_role','lws_internal.legacy_test_cleanup_consumptions','select,insert,update,delete'), 'service role has no consumption table rights');

select throws_ok($$update lws_internal.legacy_test_cleanup_authorities set authority_reason=authority_reason where quote_request_id='d3752349-3489-4c19-bd03-f0cc076b5607'$$,'55000','LEGACY_TEST_CLEANUP_AUTHORITY_IMMUTABLE','authority update is denied');
select throws_ok($$delete from lws_internal.legacy_test_cleanup_authorities where quote_request_id='d3752349-3489-4c19-bd03-f0cc076b5607'$$,'55000','LEGACY_TEST_CLEANUP_AUTHORITY_IMMUTABLE','authority delete is denied');
select throws_ok($$insert into lws_internal.legacy_test_cleanup_authorities(quote_request_id,support_reference,request_kind,dossier_created_at,authoritative_browse_at,authority_reason,source_checkpoint,source_migration) select quote_request_id,support_reference,request_kind,dossier_created_at,authoritative_browse_at,authority_reason,source_checkpoint,source_migration from lws_internal.legacy_test_cleanup_authorities where quote_request_id='d3752349-3489-4c19-bd03-f0cc076b5607'$$,'23505','duplicate key value violates unique constraint "legacy_test_cleanup_authorities_pkey"','duplicate authority UUID is denied');

select throws_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('c0000000-0000-4000-8000-000000000001')$$,'42501','LEGACY_TEST_CLEANUP_AUTHORITY_REQUIRED','unknown UUID is denied');

insert into public.quote_requests(id,request_kind,created_at,name,email,website_type,budget,timing,description,privacy_consent,status)
values('a4e6cbb0-583e-4d0b-86dc-d0c7a5de9d8f','website','2026-08-09T01:12:16.064984Z','Identity mismatch fixture','identity-mismatch@example.test','business','Budget','Timing','Local mismatch validation fixture.',true,'approved');
insert into public.quote_request_intakes(id,quote_request_id,status,access_token_hash,access_token_expires_at,started_at,submitted_at,confirmation)
values('c4000000-0000-4000-8000-000000000001','a4e6cbb0-583e-4d0b-86dc-d0c7a5de9d8f','submitted',repeat('1',64),clock_timestamp()+interval '1 hour','2026-08-09T01:12:16.064984Z','2026-08-09T11:42:36.394692Z',true);
select throws_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('a4e6cbb0-583e-4d0b-86dc-d0c7a5de9d8f')$$,'23514','LEGACY_TEST_CLEANUP_IDENTITY_MISMATCH','identity mismatch is rejected fail closed');

create function pg_temp.create_legacy_website_blocker_fixture(
  p_quote_request_id uuid,
  p_created_at timestamptz,
  p_submitted_at timestamptz,
  p_quotation_sequence integer,
  p_level text
)
returns table(issuance_id uuid, acceptance_id uuid, project_id uuid)
language plpgsql
as $$
declare
  v_intake_id uuid := gen_random_uuid();
  v_snapshot_id uuid := gen_random_uuid();
  v_draft_id uuid := gen_random_uuid();
  v_approval_id uuid := gen_random_uuid();
  v_issuance_id uuid := gen_random_uuid();
  v_acceptance_id uuid := gen_random_uuid();
  v_customer_id uuid := gen_random_uuid();
  v_project_id uuid := gen_random_uuid();
  v_obligation_id uuid := gen_random_uuid();
  v_payment_evidence_id uuid := gen_random_uuid();
  v_quotation_number text := 'LWS-OFF-2099-' || lpad(p_quotation_sequence::text, 4, '0');
  v_approval_payload jsonb;
  v_acceptance_payload jsonb;
begin
  insert into public.quote_requests(id,request_kind,created_at,name,email,website_type,budget,timing,description,privacy_consent,status)
  values(p_quote_request_id,'website',p_created_at,'Legacy blocker fixture','legacy-blocker@example.test','business','Budget','Timing','Local blocker branch fixture.',true,'approved');
  insert into public.quote_request_intakes(id,quote_request_id,status,access_token_hash,access_token_expires_at,started_at,submitted_at,confirmation)
  values(v_intake_id,p_quote_request_id,'submitted',encode(extensions.digest(convert_to(v_intake_id::text,'UTF8'),'sha256'),'hex'),clock_timestamp()+interval '1 hour',p_created_at,p_submitted_at,true);
  insert into public.quote_request_pricing_snapshots(id,intake_id,snapshot_contract_version,config_version,config_hash,normalized_evidence,calculation,package_advice,budget_evaluation)
  values(v_snapshot_id,v_intake_id,2,'1.0.0',repeat('1',64),
    '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
    '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":10000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000}]}',
    '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
    '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}');
  insert into public.quote_request_pricing_snapshot_integrity(snapshot_id,algorithm_version,key_id,mac)
  values(v_snapshot_id,'hmac-sha256-v1','v1',repeat('a',64));

  v_approval_payload := jsonb_build_object(
    'contract_version',1,'source_quote_request_id',p_quote_request_id::text,'source_intake_id',v_intake_id::text,
    'pricing_snapshot',jsonb_build_object('snapshot_id',v_snapshot_id::text,'snapshot_contract_version',2,'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1','integrity_mac',repeat('a',64)),
    'currency','EUR','line_items',jsonb_build_array(jsonb_build_object('line_id','website','sequence',1,'product_or_service_code','WEBSITE','description','Websiteontwikkeling','quantity',1,'unit','project','unit_price_minor',10000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',10000,'cost_type','ONE_TIME')),
    'totals',jsonb_build_object('one_time_subtotal_minor',10000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',10000,'vat_amount_minor',2100,'total_gross_minor',12100),
    'discount',jsonb_build_object('discount_type',null,'discount_value_minor',0,'discount_reason',null,'approved_by',null,'approved_at',null),
    'customer_identity',jsonb_build_object('source_quote_request_id',p_quote_request_id::text,'source_intake_id',v_intake_id::text,'customer_id',null,'legal_name','Legacy Fixture','contact_name','Legacy Fixture','email','legacy-blocker@example.test','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null,'source_fields',jsonb_build_object('legal_name','fixture'),'snapshot_sha256',repeat('b',64)),
    'project_scope',jsonb_build_object('project_id',null,'project_title','Legacy fixture','project_type','website','scope_summary','Local blocker fixture','requested_languages',jsonb_build_array('nl'),'included_page_count',1,'features','[]'::jsonb,'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null,'source_intake_id',v_intake_id::text,'source_pricing_snapshot_id',v_snapshot_id::text,'snapshot_sha256',repeat('c',64)),
    'vat_approval',jsonb_build_object('vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant','vat_approved_by','accountant:test','vat_approved_at','2026-08-15T12:00:00Z'),
    'payment_schedule',jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledige betaling','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null)),'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
    'validity',jsonb_build_object('valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30,'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
    'legal_references',jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','terms_sha256',repeat('d',64),'terms_status','APPROVED','agreement_template_reference',null,'agreement_template_version',null,'agreement_template_sha256',null));
  insert into public.quote_request_quotation_approval_drafts(id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_payload,payload_fingerprint,idempotency_key,created_by)
  values(v_draft_id,p_quote_request_id,v_intake_id,v_snapshot_id,1,v_approval_payload,public.quotation_approval_payload_sha256_v1(v_approval_payload),gen_random_uuid(),'test:legacy-authority');
  insert into public.quote_request_quotation_approvals(id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_version,approved_payload,payload_sha256,approved_by,approved_at)
  values(v_approval_id,v_draft_id,p_quote_request_id,v_intake_id,v_snapshot_id,1,1,v_approval_payload,public.quotation_approval_payload_sha256_v1(v_approval_payload),'test:legacy-authority',clock_timestamp());
  insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac)
  values(v_approval_id,'hmac-sha256-v1','v1',repeat('e',64));
  insert into public.quote_request_quotation_issuances(id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,template_id,template_version,template_sha256,generation_contract_version,issuance_input_sha256,generation_payload_sha256,docx_sha256,docx_bytes,prepare_idempotency_key,prepare_fingerprint,commit_idempotency_key,commit_fingerprint)
  values(v_issuance_id,v_quotation_number,1,'ISSUED',v_approval_id,clock_timestamp(),'test:legacy-authority','LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,repeat('4',64),repeat('5',64),repeat('6',64),12345,gen_random_uuid(),repeat('7',64),gen_random_uuid(),repeat('8',64));
  v_acceptance_payload := jsonb_build_object('acceptance_contract_version',1,'issuance_id',v_issuance_id::text,'quotation_number',v_quotation_number,'quotation_version',1,'customer_identity_sha256',repeat('b',64),'generation_payload_sha256',repeat('5',64),'template',jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',repeat('3',64)),'docx',jsonb_build_object('sha256',repeat('6',64),'bytes',12345),'acceptance_terms',jsonb_build_object('terms_id','LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','terms_version','1.0.0-technical','terms_sha256',repeat('9',64)),'actor',jsonb_build_object('name','Legacy Acceptant','email','legacy-blocker@example.test','organization','Legacy Fixture','role','Bestuurder'),'authority_declaration',true,'accepted_at','2026-08-20T12:00:00.000000Z');
  insert into public.quote_request_quotation_acceptances(id,issuance_id,quotation_number,quotation_version,customer_identity_sha256,customer_legal_name,generation_payload_sha256,template_id,template_version,template_sha256,docx_sha256,docx_bytes,acceptance_contract_version,acceptance_terms_id,acceptance_terms_version,acceptance_terms_sha256,accepting_name,accepting_email,accepting_organization,accepting_role,authority_declaration,acceptance_payload,acceptance_payload_sha256,semantic_request_fingerprint,accepted_at,created_at)
  values(v_acceptance_id,v_issuance_id,v_quotation_number,1,repeat('b',64),'Legacy Fixture',repeat('5',64),'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),repeat('6',64),12345,1,'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',repeat('9',64),'Legacy Acceptant','legacy-blocker@example.test','Legacy Fixture','Bestuurder',true,v_acceptance_payload,public.quotation_acceptance_payload_sha256_v1(v_acceptance_payload),repeat('f',64),'2026-08-20T12:00:00Z','2026-08-20T12:00:00Z');

  if p_level in ('commercial','payment','document') then
    insert into public.commercial_customers(customer_id,acceptance_id,identity_sha256) values(v_customer_id,v_acceptance_id,repeat('a',64));
    insert into public.commercial_projects(project_id,customer_id,quotation_issuance_id,acceptance_id,accepted_total_minor,currency,m1_minor,m2_minor,m3_minor,current_state,revision)
    values(v_project_id,v_customer_id,v_issuance_id,v_acceptance_id,10000,'EUR',4000,4000,2000,'QUOTE_ACCEPTED',1);
  end if;
  if p_level = 'payment' then
    insert into public.commercial_obligations(obligation_id,project_id,obligation_type,milestone,amount_minor,expected_reference,status)
    values(v_obligation_id,v_project_id,'PROJECT_MILESTONE',1,4000,'LEGACY-PAYMENT-' || p_quotation_sequence,'OPEN');
    insert into public.payment_expectations(project_id,obligation_id,expected_amount_minor,expected_reference)
    values(v_project_id,v_obligation_id,4000,'LEGACY-PAYMENT-' || p_quotation_sequence);
    insert into public.payment_evidence(payment_evidence_id,project_id,obligation_id,received_amount_minor,transaction_date,transaction_reference,evidence_reference,bank_account_fingerprint,verified_by,verified_at)
    values(v_payment_evidence_id,v_project_id,v_obligation_id,4000,'2026-08-20','LEGACY-TX-' || p_quotation_sequence,'LEGACY-EVIDENCE-' || p_quotation_sequence,repeat('1',64),'test:legacy-authority',clock_timestamp());
    insert into public.payment_reconciliations(payment_evidence_id,project_id,obligation_id,match_status,decided_by)
    values(v_payment_evidence_id,v_project_id,v_obligation_id,'MATCHED','SERVER_COMMAND_LAYER');
  end if;
  if p_level = 'document' then
    insert into public.commercial_documents(project_id,document_type,workflow_state,template_id,template_version,commercial_reference,status)
    values(v_project_id,'QUOTATION','ARCHIVED','legacy-test','1','LEGACY-DOC-' || p_quotation_sequence,'NON_PRODUCTION_WORKING');
    insert into public.quote_request_quotation_artifacts(issuance_id,artifact_type,storage_bucket_id,storage_object_path,content_type,sha256,byte_count,registration_idempotency_key,registration_fingerprint,created_by)
    values(v_issuance_id,'DOCX','quotation-artifacts','issuances/' || v_issuance_id || '/docx/' || repeat('c',64) || '.docx','application/vnd.openxmlformats-officedocument.wordprocessingml.document',repeat('c',64),150,gen_random_uuid(),repeat('d',64),'test:legacy-authority');
  end if;
  return query select v_issuance_id,v_acceptance_id,v_project_id;
end;
$$;

create temporary table legacy_blocker_fixtures(level text primary key, issuance_id uuid, acceptance_id uuid, project_id uuid);
insert into legacy_blocker_fixtures select 'quotation',fixture.* from pg_temp.create_legacy_website_blocker_fixture('388e8887-8b20-4300-b1e8-183718fe6b57','2026-08-18T04:38:02.741551Z','2026-08-18T09:21:18.906106Z',8101,'quotation') fixture;
select is((select count(*)::integer from public.quote_request_quotation_acceptances where id=(select acceptance_id from legacy_blocker_fixtures where level='quotation')),1,'quotation fixture has issuance and acceptance authority');
select throws_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('388e8887-8b20-4300-b1e8-183718fe6b57')$$,'55000','LEGACY_TEST_CLEANUP_QUOTATION_BLOCKER_PRESENT','quotation authority is rejected fail closed');

insert into legacy_blocker_fixtures select 'commercial',fixture.* from pg_temp.create_legacy_website_blocker_fixture('620b3fa5-2e6b-4439-9d22-741b8541fbdf','2026-08-18T06:41:37.328379Z','2026-08-18T06:51:23.983507Z',8102,'commercial') fixture;
select is((select count(*)::integer from public.commercial_projects where project_id=(select project_id from legacy_blocker_fixtures where level='commercial')),1,'commercial fixture has customer and project authority');
select throws_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('620b3fa5-2e6b-4439-9d22-741b8541fbdf')$$,'55000','LEGACY_TEST_CLEANUP_QUOTATION_BLOCKER_PRESENT','dossier with commercial authority is rejected fail closed');

insert into legacy_blocker_fixtures select 'payment',fixture.* from pg_temp.create_legacy_website_blocker_fixture('741de441-04f7-41e9-88fe-da92d699e37c','2026-08-18T00:20:01.917620Z','2026-08-18T02:57:54.766587Z',8103,'payment') fixture;
select is((select count(*)::integer from public.payment_expectations where project_id=(select project_id from legacy_blocker_fixtures where level='payment'))+(select count(*)::integer from public.payment_evidence where project_id=(select project_id from legacy_blocker_fixtures where level='payment'))+(select count(*)::integer from public.payment_reconciliations where project_id=(select project_id from legacy_blocker_fixtures where level='payment')),3,'payment fixture has expectation, evidence, and reconciliation authority');
select throws_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('741de441-04f7-41e9-88fe-da92d699e37c')$$,'55000','LEGACY_TEST_CLEANUP_QUOTATION_BLOCKER_PRESENT','dossier with payment authority is rejected fail closed');

insert into legacy_blocker_fixtures select 'document',fixture.* from pg_temp.create_legacy_website_blocker_fixture('5c9a89e7-9af1-4ed0-990d-6ebe268fa871','2026-08-09T21:55:51.188608Z','2026-08-09T22:09:30.213079Z',8104,'document') fixture;
select is((select count(*)::integer from public.commercial_documents where project_id=(select project_id from legacy_blocker_fixtures where level='document'))+(select count(*)::integer from public.quote_request_quotation_artifacts where issuance_id=(select issuance_id from legacy_blocker_fixtures where level='document')),2,'document fixture has production document and artifact authority');
select throws_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('5c9a89e7-9af1-4ed0-990d-6ebe268fa871')$$,'55000','LEGACY_TEST_CLEANUP_QUOTATION_BLOCKER_PRESENT','dossier with document authority is rejected fail closed');

insert into public.quote_requests(id,request_kind,sdf_package,created_at,name,email,description,privacy_consent,status)
values('d3752349-3489-4c19-bd03-f0cc076b5607','slimme_documentenflow','groei','2026-08-18T06:40:00.735922Z','Legacy authority fixture','legacy-authority@example.test','Local authority validation fixture.',true,'approved');
select is((select record_classification from public.quote_requests where id='d3752349-3489-4c19-bd03-f0cc076b5607'),'production','legacy authority preserves production classification');
select lives_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('d3752349-3489-4c19-bd03-f0cc076b5607')$$,'matching blocker-free legacy identity is eligible at the authority layer');

insert into public.quote_requests(id,record_classification,request_kind,sdf_package,created_at,name,email,description,privacy_consent,status)
values('c0000000-0000-4000-8000-000000000002','internal_e2e','slimme_documentenflow','start',clock_timestamp(),'Independent E2E fixture','internal-e2e@invalid.local','Separate trust model fixture.',true,'approved');
select is((select record_classification from public.quote_requests where id='c0000000-0000-4000-8000-000000000002'),'internal_e2e','internal E2E classification remains unchanged');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities where quote_request_id='c0000000-0000-4000-8000-000000000002'),0,'internal E2E fixture receives no legacy authority');
select has_table('public','internal_e2e_runs','existing internal E2E run authority remains present');
select has_table('public','internal_e2e_run_events','existing internal E2E event authority remains present');

insert into auth.users(id,email) values('c1000000-0000-4000-8000-000000000001','legacy-cleanup-owner@example.test');
insert into public.commercial_operators(auth_user_id,display_name,role,status)
values('c1000000-0000-4000-8000-000000000001','Legacy Cleanup Owner','owner','ACTIVE');
insert into lws_internal.legacy_test_cleanup_consumptions(authority_quote_request_id,cleanup_operation_id,consumed_at,authorized_operator_id,result,previous_identity_evidence_sha256,result_evidence_sha256)
select authority.quote_request_id,'c2000000-0000-4000-8000-000000000001',clock_timestamp(),operator.operator_id,'COMPLETED',authority.identity_evidence_sha256,repeat('a',64)
from lws_internal.legacy_test_cleanup_authorities authority
cross join public.commercial_operators operator
where authority.quote_request_id='d3752349-3489-4c19-bd03-f0cc076b5607'
  and operator.auth_user_id='c1000000-0000-4000-8000-000000000001';
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_consumptions),1,'consumption evidence can be appended only by migration/server authority');
select throws_ok($$update lws_internal.legacy_test_cleanup_consumptions set result=result$$,'55000','LEGACY_TEST_CLEANUP_CONSUMPTION_APPEND_ONLY','consumption update is denied');
select throws_ok($$delete from lws_internal.legacy_test_cleanup_consumptions$$,'55000','LEGACY_TEST_CLEANUP_CONSUMPTION_APPEND_ONLY','consumption delete is denied');
select throws_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('d3752349-3489-4c19-bd03-f0cc076b5607')$$,'55000','LEGACY_TEST_CLEANUP_AUTHORITY_CONSUMED','consumed UUID is denied');

insert into public.quote_requests(id,request_kind,sdf_package,created_at,name,email,description,privacy_consent,status)
values('0696171e-a315-4c03-b402-ba0b689abfbc','slimme_documentenflow','start','2026-08-17T23:52:15.685429Z','Blocked legacy fixture','blocked-legacy@example.test','Local blocker validation fixture.',true,'approved');
insert into public.sdf_projects(project_id,quote_request_id,created_at)
values('c3000000-0000-4000-8000-000000000001','0696171e-a315-4c03-b402-ba0b689abfbc',clock_timestamp());
select is((select count(*)::integer from public.sdf_projects where quote_request_id='0696171e-a315-4c03-b402-ba0b689abfbc'),1,'SDF fixture has project authority');
select throws_ok($$select lws_internal.assert_legacy_test_cleanup_candidate_v1('0696171e-a315-4c03-b402-ba0b689abfbc')$$,'55000','LEGACY_TEST_CLEANUP_SDF_BLOCKER_PRESENT','migration candidate assertion fails closed for a simulated SDF project binding');

select * from finish();
rollback;
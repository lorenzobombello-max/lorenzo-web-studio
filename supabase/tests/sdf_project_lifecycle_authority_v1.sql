begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public','sdf_project_lifecycle_events','SDF lifecycle has immutable event authority');
select has_table('public','sdf_project_phase_acceptance_capabilities','SDF phase acceptance has scoped customer capabilities');
select has_table('public','sdf_project_phase_acceptance_capability_operations','SDF phase capability operations preserve idempotency history');
select has_function(
  'public','prepare_sdf_project_phase_acceptance_v1',
  array['uuid','text','text','text','text','timestamp with time zone','uuid'],
  'owner-only phase acceptance preparation RPC exists'
);
select has_function(
  'public','resolve_sdf_project_phase_acceptance_v1',array['text'],
  'customer-safe phase acceptance resolver exists'
);
select has_function(
  'public','submit_sdf_project_phase_acceptance_v1',
  array['text','text','text','text','text','boolean','uuid'],
  'active customer signature submission RPC exists'
);
select has_function(
  'public','revoke_sdf_project_phase_acceptance_v1',array['uuid','text','uuid'],
  'owner-only phase acceptance revocation RPC exists'
);
select has_function(
  'public','activate_sdf_project_operationally_v1',array['uuid','text','text','uuid'],
  'owner-only operational activation RPC exists'
);
select has_function(
  'public','get_sdf_project_lifecycle_v1',array['uuid'],
  'canonical SDF lifecycle projection exists'
);

insert into auth.users(id,email) values
  ('a1000000-0000-4000-8000-000000000001','lifecycle-owner@example.test'),
  ('a1000000-0000-4000-8000-000000000002','lifecycle-operator@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  ('a1100000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Lifecycle Owner','owner','ACTIVE'),
  ('a1100000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','Lifecycle Operator','operator','ACTIVE');

insert into public.quote_requests(
  id,application_reference,request_kind,sdf_package,name,company,email,customer_type,
  enterprise_number,enterprise_validation_status,vat_number,vat_validation_status,vat_validated_at,
  billing_address,billing_postal_code,billing_city,billing_country,billing_email,
  description,privacy_consent,status
) values
  (
    'a2000000-0000-4000-8000-000000000001','LWS-AAN-2099-9101','slimme_documentenflow','start',
    'Lifecycle Customer','Lifecycle BV','lifecycle@example.test','business',
    '0123456789','format_valid_not_externally_verified','BE0123456789','valid','2099-01-01T08:00:00Z',
    'Klantstraat 1','9000','Gent','BE','billing@example.test',
    'SDF lifecycle started fixture.',true,'approved'
  ),
  (
    'a2000001-0000-4000-8000-000000000002','LWS-AAN-2099-9102','slimme_documentenflow','start',
    'Unstarted Customer','Unstarted BV','unstarted@example.test','business',
    '0987654321','format_valid_not_externally_verified','BE0987654321','valid','2099-01-01T08:00:00Z',
    'Teststraat 2','9000','Gent','BE','unstarted@example.test',
    'SDF lifecycle unstarted fixture.',true,'approved'
  );
insert into public.quote_requests(
  id,request_kind,name,email,website_type,budget,timing,description,privacy_consent,status
) values (
  'a2000002-0000-4000-8000-000000000003','website','Website Customer','website-lifecycle@example.test',
  'business','Meer dan EUR 6.000','flexible','Website lifecycle isolation fixture.',true,'approved'
);

insert into public.sdf_projects(project_id,quote_request_id) values
  ('a3000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001'),
  ('a3000000-0000-4000-8000-000000000002','a2000001-0000-4000-8000-000000000002');
set local session_replication_role = replica;
insert into public.sdf_projects(project_id,quote_request_id) values
  ('a3000000-0000-4000-8000-000000000003','a2000002-0000-4000-8000-000000000003');
set local session_replication_role = origin;

insert into public.sdf_quotations(quotation_id,quote_request_id,created_at) values (
  'a4000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','2099-01-01T09:00:00Z'
);
insert into public.sdf_quotation_documents(
  quotation_id,quotation_date,valid_until,prepared_at,document_reference,document_sha256
) values (
  'a4000000-0000-4000-8000-000000000001','2099-01-01','2099-02-01','2099-01-01T10:00:00Z',
  'sdf/lifecycle/quotation.docx',repeat('1',64)
);
insert into public.sdf_quotation_acceptances(
  quotation_id,accepted_at,document_reference,document_sha256
) values (
  'a4000000-0000-4000-8000-000000000001','2099-01-02T10:00:00Z',
  'sdf/lifecycle/accepted.docx',repeat('2',64)
);
insert into public.sdf_accepted_commercial_terms(
  accepted_terms_id,quotation_id,quote_request_id,sdf_package,accepted_implementation_amount_minor,
  currency,vat_basis,pricing_authority_version,creation_idempotency_key,creation_fingerprint,
  created_by_operator_id
) values (
  'a4100000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001','start',285000,'EUR','exclusive',1,
  'a4200000-0000-4000-8000-000000000001',repeat('3',64),'a1100000-0000-4000-8000-000000000001'
);
insert into public.sdf_milestone_one_obligations(
  obligation_id,quotation_id,accepted_terms_id,milestone_identity,percentage_basis_points,
  amount_minor,currency,vat_basis,obligation_state,obligation_origin
) values (
  'a4300000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001',
  'a4100000-0000-4000-8000-000000000001','M1',4000,114000,'EUR','exclusive','EXPECTED','QUOTATION_ACCEPTANCE'
);
insert into public.sdf_invoice_template_authorities(
  template_authority_id,document_type,milestone_identity,template_id,template_version,
  document_reference,document_sha256,registration_idempotency_key,registration_fingerprint,
  created_by_operator_id
) values (
  'a4400000-0000-4000-8000-000000000001','INVOICE','M1','LWS_GENERIC_INVOICE_MASTER','lifecycle-test',
  '03_Algemene_sjablonen/02_Factuursjabloon.docx',
  '52dc454bec5d0e09fc9f4b85a1f1877b65f7d3aea166ed195da598cb7b4536d6',
  'a4500000-0000-4000-8000-000000000001',repeat('4',64),'a1100000-0000-4000-8000-000000000001'
);
insert into public.sdf_m1_invoice_candidates(
  candidate_id,obligation_id,quotation_id,accepted_terms_id,quote_request_id,application_reference,
  template_authority_id,candidate_state,milestone_identity,percentage_basis_points,currency,
  net_amount_minor,accepted_price_basis,seller_snapshot,customer_snapshot,bank_snapshot,
  template_snapshot,candidate_payload_sha256,creation_idempotency_key,creation_fingerprint,
  prepared_by_operator_id
) values (
  'a4600000-0000-4000-8000-000000000001','a4300000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','a4100000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001','LWS-AAN-2099-9101',
  'a4400000-0000-4000-8000-000000000001','PREPARED','M1',4000,'EUR',114000,'exclusive',
  '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
  jsonb_build_object(
    'document_reference','03_Algemene_sjablonen/02_Factuursjabloon.docx',
    'document_sha256','52dc454bec5d0e09fc9f4b85a1f1877b65f7d3aea166ed195da598cb7b4536d6'
  ),repeat('5',64),'a4700000-0000-4000-8000-000000000001',repeat('6',64),
  'a1100000-0000-4000-8000-000000000001'
);
insert into public.sdf_m1_invoice_issuances(
  issuance_id,candidate_id,invoice_number,issue_year,sequence,issuance_state,
  vat_decision_authority_id,vat_authority_version,vat_authority_sha256,vat_treatment,
  rate_semantics,vat_rate_basis_points,invoice_literal,net_amount_minor,vat_amount_minor,
  gross_amount_minor,issuance_payload_sha256,docx_sha256,docx_bytes,pdf_sha256,pdf_bytes,
  issuance_idempotency_key,issuance_fingerprint,issued_by_operator_id
) values (
  'a4800000-0000-4000-8000-000000000001','a4600000-0000-4000-8000-000000000001',
  'LWS-2099-9101',2099,9101,'ISSUED','b1030000-0000-4000-8000-000000000001','1.0.0',
  repeat('7',64),'EXEMPT','NOT_APPLICABLE',0,'Bijzondere vrijstellingsregeling van belasting',
  114000,0,114000,repeat('8',64),repeat('9',64),4096,repeat('a',64),2048,
  'a4900000-0000-4000-8000-000000000001',repeat('b',64),'a1100000-0000-4000-8000-000000000001'
);
insert into public.sdf_m1_project_start_authorities(
  start_authority_id,project_id,quote_request_id,issuance_id,candidate_id,authority_state,
  required_amount_minor,received_amount_minor,currency,candidate_payload_sha256,
  issuance_payload_sha256,creation_idempotency_key,creation_fingerprint,authorized_by_operator_id
) values (
  'a5000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000001',
  'a4600000-0000-4000-8000-000000000001','START_ALLOWED',114000,114000,'EUR',repeat('5',64),
  repeat('8',64),'a5100000-0000-4000-8000-000000000001',repeat('c',64),
  'a1100000-0000-4000-8000-000000000001'
);

select to_regprocedure('public.get_sdf_project_lifecycle_v1(uuid)') is not null as lifecycle_implemented \gset
\if :lifecycle_implemented

select ok(
  (select bool_and(relrowsecurity and relforcerowsecurity)
   from pg_class where oid in (
     'public.sdf_project_lifecycle_events'::regclass,
     'public.sdf_project_phase_acceptance_capabilities'::regclass,
     'public.sdf_project_phase_acceptance_capability_operations'::regclass
   )),
  'all lifecycle authority tables have forced RLS'
);
select ok(
  not has_table_privilege('authenticated','public.sdf_project_lifecycle_events','select')
  and not has_table_privilege('authenticated','public.sdf_project_lifecycle_events','insert')
  and not has_table_privilege('service_role','public.sdf_project_lifecycle_events','insert'),
  'runtime roles cannot read or mutate private lifecycle history directly'
);
select ok(
  has_function_privilege('authenticated','public.prepare_sdf_project_phase_acceptance_v1(uuid,text,text,text,text,timestamptz,uuid)','execute')
  and has_function_privilege('authenticated','public.activate_sdf_project_operationally_v1(uuid,text,text,uuid)','execute')
  and has_function_privilege('authenticated','public.get_sdf_project_lifecycle_v1(uuid)','execute')
  and not has_function_privilege('anon','public.prepare_sdf_project_phase_acceptance_v1(uuid,text,text,text,text,timestamptz,uuid)','execute')
  and not has_function_privilege('authenticated','public.submit_sdf_project_phase_acceptance_v1(text,text,text,text,text,boolean,uuid)','execute')
  and has_function_privilege('service_role','public.submit_sdf_project_phase_acceptance_v1(text,text,text,text,text,boolean,uuid)','execute')
  and not has_function_privilege('anon','public.submit_sdf_project_phase_acceptance_v1(text,text,text,text,text,boolean,uuid)','execute'),
  'owner commands and customer capability orchestration have separate execute surfaces'
);
select ok(
  not exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name in (
        'sdf_project_lifecycle_events','sdf_project_phase_acceptance_capabilities',
        'sdf_project_phase_acceptance_capability_operations'
      )
      and column_name in (
        'amount_minor','price_minor','invoice_number','invoice_id','payment_state',
        'recurring_amount_minor','recurring_obligation_id'
      )
  ),
  'lifecycle authority contains no billing, payment, or recurring fields'
);

select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
select is(
  public.get_sdf_project_lifecycle_v1('a3000000-0000-4000-8000-000000000001')->>'current_state',
  'PROJECT_STARTED',
  'existing M1 START_ALLOWED authority projects PROJECT_STARTED without a duplicate event'
);
select is(
  (select count(*)::integer from public.sdf_project_lifecycle_events
   where project_id='a3000000-0000-4000-8000-000000000001'),
  0,
  'PROJECT_STARTED is not recreated as an independent lifecycle event'
);
select throws_ok(
  $$select public.prepare_sdf_project_phase_acceptance_v1(
    'a3000000-0000-4000-8000-000000000002','PHASE_A_CONFIRMED',
    'sdf/delivery/a/acceptance.docx',repeat('d',64),repeat('1',64),
    clock_timestamp()+interval '10 days','a6000000-0000-4000-8000-000000000001'
  )$$,
  '55000','SDF_PROJECT_NOT_STARTED',
  'Phase A cannot be prepared before existing PROJECT_STARTED authority'
);
select throws_ok(
  $$select public.prepare_sdf_project_phase_acceptance_v1(
    'a3000000-0000-4000-8000-000000000001','PHASE_B_CONFIRMED',
    'sdf/delivery/b/acceptance.docx',repeat('e',64),repeat('2',64),
    clock_timestamp()+interval '5 days','a6000000-0000-4000-8000-000000000002'
  )$$,
  '55000','SDF_LIFECYCLE_INVALID_TRANSITION',
  'Phase B cannot be prepared before canonical Phase A'
);
select throws_ok(
  $$select public.activate_sdf_project_operationally_v1(
    'a3000000-0000-4000-8000-000000000001',
    'sdf/operations/activation.json',repeat('f',64),
    'a6000000-0000-4000-8000-000000000003'
  )$$,
  '55000','SDF_LIFECYCLE_INVALID_TRANSITION',
  'operational activation cannot occur before canonical Phase B'
);
select throws_ok(
  $$select public.prepare_sdf_project_phase_acceptance_v1(
    'a3000000-0000-4000-8000-000000000003','PHASE_A_CONFIRMED',
    'sdf/delivery/website/acceptance.docx',repeat('1',64),repeat('3',64),
    clock_timestamp()+interval '10 days','a6000000-0000-4000-8000-000000000004'
  )$$,
  '23514','SDF_REQUEST_KIND_REQUIRED',
  'Website request kind cannot enter SDF lifecycle authority'
);
select throws_ok(
  $$select public.prepare_sdf_project_phase_acceptance_v1(
    'a3000000-0000-4000-8000-000000000099','PHASE_A_CONFIRMED',
    'sdf/delivery/missing/acceptance.docx',repeat('1',64),repeat('4',64),
    clock_timestamp()+interval '10 days','a6000000-0000-4000-8000-000000000005'
  )$$,
  '23503','SDF_PROJECT_REQUIRED',
  'unknown or wrong project linkage fails closed'
);

select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.get_sdf_project_lifecycle_v1('a3000000-0000-4000-8000-000000000001')$$,
  '42501','SDF_LIFECYCLE_AUTHORITY_DENIED',
  'ordinary Operator cannot read private lifecycle data'
);
select throws_ok(
  $$select public.prepare_sdf_project_phase_acceptance_v1(
    'a3000000-0000-4000-8000-000000000001','PHASE_A_CONFIRMED',
    'sdf/delivery/a/acceptance.docx',repeat('d',64),repeat('5',64),
    clock_timestamp()+interval '10 days','a6000000-0000-4000-8000-000000000006'
  )$$,
  '42501','SDF_LIFECYCLE_AUTHORITY_DENIED',
  'ordinary Operator cannot prepare lifecycle acceptance authority'
);
select throws_ok(
  $$select public.activate_sdf_project_operationally_v1(
    'a3000000-0000-4000-8000-000000000001',
    'sdf/operations/denied.json',repeat('f',64),
    'a6000000-0000-4000-8000-000000000099'
  )$$,
  '42501','SDF_LIFECYCLE_AUTHORITY_DENIED',
  'ordinary Operator cannot create operational lifecycle authority'
);
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);

select lives_ok(
  $$select public.prepare_sdf_project_phase_acceptance_v1(
    'a3000000-0000-4000-8000-000000000001','PHASE_A_CONFIRMED',
    'sdf/delivery/a/acceptance.docx',repeat('d',64),repeat('6',64),
    '2099-01-20T00:00:00Z','a6000000-0000-4000-8000-000000000007'
  )$$,
  'owner prepares exact Phase A customer acceptance capability'
);
select is(
  public.resolve_sdf_project_phase_acceptance_v1(repeat('6',64))->>'state','ACTIVE',
  'customer resolves active scoped Phase A capability'
);
select throws_ok(
  $$select public.submit_sdf_project_phase_acceptance_v1(
    repeat('6',64),'Customer Signer','customer@example.test','Lifecycle BV','Director',false,
    'a6100000-0000-4000-8000-000000000099'
  )$$,
  '22023','SDF_PHASE_ACCEPTANCE_SIGNATURE_INVALID',
  'Phase A cannot use tacit acceptance without an active customer declaration'
);

set local session_replication_role = replica;
update public.sdf_project_phase_acceptance_capabilities
set project_id='a3000000-0000-4000-8000-000000000002'
where token_digest=repeat('6',64);
set local session_replication_role = origin;
select throws_ok(
  $$select public.submit_sdf_project_phase_acceptance_v1(
    repeat('6',64),'Customer Signer','customer@example.test','Lifecycle BV','Director',true,
    'a6100000-0000-4000-8000-000000000001'
  )$$,
  '23514','SDF_PROJECT_LINKAGE_MISMATCH',
  'tampered capability project linkage is rejected before event insertion'
);
set local session_replication_role = replica;
update public.sdf_project_phase_acceptance_capabilities
set project_id='a3000000-0000-4000-8000-000000000001'
where token_digest=repeat('6',64);
update public.sdf_quotation_acceptances
set document_sha256=repeat('0',64)
where quotation_id='a4000000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.submit_sdf_project_phase_acceptance_v1(
    repeat('6',64),'Customer Signer','customer@example.test','Lifecycle BV','Director',true,
    'a6100000-0000-4000-8000-000000000002'
  )$$,
  '55000','SDF_PROJECT_LINKAGE_STALE',
  'stale immutable commercial linkage is rejected before event insertion'
);
set local session_replication_role = replica;
update public.sdf_quotation_acceptances
set document_sha256=repeat('2',64)
where quotation_id='a4000000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

select lives_ok(
  $$select public.submit_sdf_project_phase_acceptance_v1(
    repeat('6',64),'Customer Signer','customer@example.test','Lifecycle BV','Director',true,
    'a6100000-0000-4000-8000-000000000003'
  )$$,
  'active customer signature confirms Phase A'
);
select is(
  public.get_sdf_project_lifecycle_v1('a3000000-0000-4000-8000-000000000001')->>'current_state',
  'PHASE_A_CONFIRMED','canonical lifecycle advances to Phase A'
);
select is(
  (public.submit_sdf_project_phase_acceptance_v1(
    repeat('6',64),'Customer Signer','customer@example.test','Lifecycle BV','Director',true,
    'a6100000-0000-4000-8000-000000000003'
  )->>'was_created')::boolean,
  false,'identical Phase A retry returns canonical event'
);
select throws_ok(
  $$select public.submit_sdf_project_phase_acceptance_v1(
    repeat('6',64),'Changed Signer','customer@example.test','Lifecycle BV','Director',true,
    'a6100000-0000-4000-8000-000000000003'
  )$$,
  'P0001','IDEMPOTENCY_CONFLICT','changed Phase A replay is rejected'
);

select lives_ok(
  $$select public.prepare_sdf_project_phase_acceptance_v1(
    'a3000000-0000-4000-8000-000000000001','PHASE_B_CONFIRMED',
    'sdf/delivery/b/acceptance.docx',repeat('e',64),repeat('7',64),
    '2099-01-25T00:00:00Z','a6000000-0000-4000-8000-000000000008'
  )$$,
  'owner prepares Phase B only after canonical Phase A'
);
select lives_ok(
  $$select public.submit_sdf_project_phase_acceptance_v1(
    repeat('7',64),'Customer Signer','customer@example.test','Lifecycle BV','Director',true,
    'a6100000-0000-4000-8000-000000000004'
  )$$,
  'active customer signature confirms Phase B'
);
select is(
  public.get_sdf_project_lifecycle_v1('a3000000-0000-4000-8000-000000000001')->>'current_state',
  'PHASE_B_CONFIRMED','canonical lifecycle advances to Phase B'
);
select is(
  (public.submit_sdf_project_phase_acceptance_v1(
    repeat('7',64),'Customer Signer','customer@example.test','Lifecycle BV','Director',true,
    'a6100000-0000-4000-8000-000000000004'
  )->>'was_created')::boolean,
  false,'identical Phase B retry returns canonical event'
);
select throws_ok(
  $$select public.submit_sdf_project_phase_acceptance_v1(
    repeat('7',64),'Customer Signer','changed@example.test','Lifecycle BV','Director',true,
    'a6100000-0000-4000-8000-000000000004'
  )$$,
  'P0001','IDEMPOTENCY_CONFLICT','changed Phase B replay is rejected'
);

select lives_ok(
  $$select public.activate_sdf_project_operationally_v1(
    'a3000000-0000-4000-8000-000000000001',
    'sdf/operations/activation.json',repeat('f',64),
    'a6200000-0000-4000-8000-000000000001'
  )$$,
  'owner activates operations only after canonical Phase B'
);
select is(
  public.get_sdf_project_lifecycle_v1('a3000000-0000-4000-8000-000000000001')->>'current_state',
  'OPERATIONAL_ACTIVATED','canonical lifecycle advances to operational activation'
);
select is(
  (public.activate_sdf_project_operationally_v1(
    'a3000000-0000-4000-8000-000000000001',
    'sdf/operations/activation.json',repeat('f',64),
    'a6200000-0000-4000-8000-000000000001'
  )->>'was_created')::boolean,
  false,'identical operational activation retry returns canonical event'
);
select throws_ok(
  $$select public.activate_sdf_project_operationally_v1(
    'a3000000-0000-4000-8000-000000000001',
    'sdf/operations/activation.json',repeat('0',64),
    'a6200000-0000-4000-8000-000000000001'
  )$$,
  'P0001','IDEMPOTENCY_CONFLICT','changed operational activation replay is rejected'
);
select results_eq(
  $$select previous_state,new_state,actor_type
    from public.sdf_project_lifecycle_events
    order by case new_state
      when 'PHASE_A_CONFIRMED' then 1
      when 'PHASE_B_CONFIRMED' then 2
      when 'OPERATIONAL_ACTIVATED' then 3 end$$,
  $$values
    ('PROJECT_STARTED'::text,'PHASE_A_CONFIRMED'::text,'CUSTOMER'::text),
    ('PHASE_A_CONFIRMED'::text,'PHASE_B_CONFIRMED'::text,'CUSTOMER'::text),
    ('PHASE_B_CONFIRMED'::text,'OPERATIONAL_ACTIVATED'::text,'OWNER'::text)$$,
  'canonical history preserves strict order and authoritative actor types'
);
select ok(
  (select bool_and(
    quote_request_id='a2000000-0000-4000-8000-000000000001'
    and request_kind='slimme_documentenflow'
    and accepted_terms_id='a4100000-0000-4000-8000-000000000001'
    and quotation_id='a4000000-0000-4000-8000-000000000001'
    and start_authority_id='a5000000-0000-4000-8000-000000000001'
    and project_linkage_sha256 ~ '^[0-9a-f]{64}$'
    and evidence_sha256 ~ '^[0-9a-f]{64}$'
    and occurred_at=created_at
    and idempotency_key is not null
    and request_fingerprint ~ '^[0-9a-f]{64}$'
    and jsonb_typeof(audit_metadata)='object'
  ) from public.sdf_project_lifecycle_events),
  'every lifecycle event freezes complete safe project, commercial, evidence, actor, and idempotency provenance'
);
select throws_ok(
  $$update public.sdf_project_lifecycle_events set audit_metadata='{}'::jsonb$$,
  '55000','SDF_PROJECT_LIFECYCLE_IMMUTABLE','lifecycle events reject UPDATE'
);
select throws_ok(
  $$delete from public.sdf_project_lifecycle_events$$,
  '55000','SDF_PROJECT_LIFECYCLE_IMMUTABLE','lifecycle events reject DELETE'
);
select is((select count(*)::integer from public.sdf_project_lifecycle_events),3,'exactly Phase A, Phase B, and operational events exist');
select is((select count(*)::integer from public.sdf_m1_invoice_issuances),1,'lifecycle creates no invoice issuance');
select is((select count(*)::integer from public.sdf_m1_payment_receipts),0,'lifecycle creates no payment mutation');
select is((select count(*)::integer from public.recurring_services),0,'lifecycle creates no recurring obligation');

\else
select fail('lifecycle behavior remains RED until schema and RPC implementation exists');
\endif

select * from finish();
rollback;
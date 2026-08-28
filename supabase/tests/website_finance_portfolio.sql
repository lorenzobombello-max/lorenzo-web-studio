begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(33);

select has_function(
  'public', 'get_website_finance_portfolio_v1', array[]::text[],
  'Website finance portfolio RPC exists'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.get_website_finance_portfolio_v1()'::regprocedure
      and prosecdef
      and provolatile = 's'
      and proconfig = array['search_path=public, auth, pg_catalog']
  ),
  'portfolio is stable SECURITY DEFINER with a fixed safe search_path'
);
select ok(
  has_function_privilege('authenticated', 'public.get_website_finance_portfolio_v1()', 'execute')
  and not has_function_privilege('anon', 'public.get_website_finance_portfolio_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.get_website_finance_portfolio_v1()', 'execute')
  and not has_function_privilege('public', 'public.get_website_finance_portfolio_v1()', 'execute'),
  'only authenticated receives entrypoint execute privilege'
);
select ok(
  not has_table_privilege('authenticated', 'public.commercial_projects', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.payment_evidence', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.payment_reconciliations', 'select,insert,update,delete'),
  'browser roles retain no direct finance table privileges'
);
select ok(
  (select prosrc !~* '\m(insert|update|delete|merge|truncate)\M'
   from pg_proc where oid = 'public.get_website_finance_portfolio_v1()'::regprocedure),
  'portfolio runtime contains no mutation statement'
);

insert into auth.users(id, email) values
  ('f2000000-0000-4000-8000-000000000001', 'finance-owner@example.test'),
  ('f2000000-0000-4000-8000-000000000002', 'finance-admin@example.test'),
  ('f2000000-0000-4000-8000-000000000003', 'finance-operator@example.test'),
  ('f2000000-0000-4000-8000-000000000004', 'finance-unknown@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f2010000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001', 'Finance Owner', 'owner', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000002', 'Finance Admin', 'admin', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000003', 'f2000000-0000-4000-8000-000000000003', 'Finance Operator', 'operator', 'ACTIVE');

insert into public.quote_requests (
  id, application_reference, request_kind, sdf_package, created_at, name, company, email,
  website_type, budget, timing, description, privacy_consent, status
) values
  ('f2100000-0000-4000-8000-000000000001', 'LWS-AAN-2099-0101', 'website', null,
   '2099-01-01T09:00:00Z', 'Finance Website', 'Finance Website BV', 'website@example.test',
   'business', 'Meer dan EUR 6.000', 'flexible', 'Website finance portfolio fixture.', true, 'approved'),
  ('f2110000-0000-4000-8000-000000000002', 'LWS-AAN-2099-0102', 'slimme_documentenflow', 'start',
   '2099-01-01T10:00:00Z', 'Finance SDF', 'Finance SDF BV', 'sdf@example.test',
   null, null, null, 'SDF exclusion fixture.', true, 'approved');

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select is(jsonb_array_length(public.get_website_finance_portfolio_v1()->'projects'), 0, 'SDF-only state yields an empty Website portfolio');
select is(public.get_website_finance_portfolio_v1()->'currency_totals', '[]'::jsonb, 'empty portfolio has safe empty currency totals');
select ok(
  not (public.get_website_finance_portfolio_v1()->>'invoice_projection_available')::boolean
  and not (public.get_website_finance_portfolio_v1()->>'outstanding_projection_available')::boolean
  and not (public.get_website_finance_portfolio_v1()->>'overdue_projection_available')::boolean
  and not (public.get_website_finance_portfolio_v1()->>'upcoming_projection_available')::boolean
  and not (public.get_website_finance_portfolio_v1()->>'recurring_amount_projection_available')::boolean,
  'unavailable commercial projections fail closed instead of reporting zero'
);
select ok(
  not (public.get_website_finance_portfolio_v1()->>'bank_actuals_projection_available')::boolean
  and public.get_website_finance_portfolio_v1()->'bank_actuals' = 'null'::jsonb,
  'bank actuals remain explicitly separate and unavailable'
);

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, confirmation
) values (
  'f2200000-0000-4000-8000-000000000001', 'f2100000-0000-4000-8000-000000000001',
  repeat('1',64), '2099-01-03T00:00:00Z', 'submitted',
  '2099-01-01T12:00:00Z', '2099-01-01T12:00:00Z', true
);

create temporary table finance_approval_payload as
select jsonb_build_object(
  'contract_version',1,
  'source_quote_request_id','f2100000-0000-4000-8000-000000000001',
  'source_intake_id','f2200000-0000-4000-8000-000000000001',
  'pricing_snapshot',jsonb_build_object('snapshot_id','f2300000-0000-4000-8000-000000000001','snapshot_contract_version',2,'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1','integrity_mac',repeat('a',64)),
  'currency','EUR',
  'line_items',jsonb_build_array(jsonb_build_object('line_id','website','sequence',1,'product_or_service_code','WEBSITE','description','Websiteontwikkeling','quantity',1,'unit','project','unit_price_minor',350000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',350000,'cost_type','ONE_TIME')),
  'totals',jsonb_build_object('one_time_subtotal_minor',350000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',350000,'vat_amount_minor',73500,'total_gross_minor',423500),
  'discount',jsonb_build_object('discount_type',null,'discount_value_minor',0,'discount_reason',null,'approved_by',null,'approved_at',null),
  'customer_identity',jsonb_build_object('source_quote_request_id','f2100000-0000-4000-8000-000000000001','source_intake_id','f2200000-0000-4000-8000-000000000001','customer_id',null,'legal_name','Finance Website BV','contact_name','Finance Website','email','website@example.test','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null,'source_fields',jsonb_build_object('legal_name','fixture'),'snapshot_sha256',repeat('b',64)),
  'project_scope',jsonb_build_object('project_id',null,'project_title','Finance website','project_type','website','scope_summary','Finance fixture scope','requested_languages',jsonb_build_array('nl'),'included_page_count',5,'features',jsonb_build_array('contact_form'),'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null,'source_intake_id','f2200000-0000-4000-8000-000000000001','source_pricing_snapshot_id','f2300000-0000-4000-8000-000000000001','snapshot_sha256',repeat('c',64)),
  'vat_approval',jsonb_build_object('vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant','vat_approved_by','accountant:test','vat_approved_at','2026-08-15T12:00:00Z'),
  'payment_schedule',jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledige betaling','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null)),'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
  'validity',jsonb_build_object('valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30,'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
  'legal_references',jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','terms_sha256',repeat('d',64),'terms_status','APPROVED','agreement_template_reference',null,'agreement_template_version',null,'agreement_template_sha256',null)
) as payload;

insert into public.quote_request_pricing_snapshots (
  id,intake_id,snapshot_contract_version,config_version,config_hash,
  normalized_evidence,calculation,package_advice,budget_evaluation
) values (
  'f2300000-0000-4000-8000-000000000001','f2200000-0000-4000-8000-000000000001',2,'1.0.0',repeat('1',64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
);
insert into public.quote_request_pricing_snapshot_integrity(snapshot_id,algorithm_version,key_id,mac)
values('f2300000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('a',64));
insert into public.quote_request_quotation_approval_drafts(id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_payload,payload_fingerprint,idempotency_key,created_by)
select 'f2400000-0000-4000-8000-000000000001','f2100000-0000-4000-8000-000000000001','f2200000-0000-4000-8000-000000000001','f2300000-0000-4000-8000-000000000001',1,payload,public.quotation_approval_payload_sha256_v1(payload),'f2400000-0000-4000-8000-000000000002','finance:test' from finance_approval_payload;
insert into public.quote_request_quotation_approvals(id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,approval_version,approved_payload,payload_sha256,approved_by,approved_at)
select 'f2500000-0000-4000-8000-000000000001','f2400000-0000-4000-8000-000000000001','f2100000-0000-4000-8000-000000000001','f2200000-0000-4000-8000-000000000001','f2300000-0000-4000-8000-000000000001',1,1,payload,public.quotation_approval_payload_sha256_v1(payload),'finance:test',clock_timestamp() from finance_approval_payload;
insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac)
values('f2500000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('e',64));
insert into public.quote_request_quotation_issuances (
  id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,
  template_id,template_version,template_sha256,generation_contract_version,
  issuance_input_sha256,generation_payload_sha256,docx_sha256,docx_bytes,
  prepare_idempotency_key,prepare_fingerprint,commit_idempotency_key,commit_fingerprint
) values (
  'f2600000-0000-4000-8000-000000000001','LWS-OFF-2099-0101',1,'ISSUED','f2500000-0000-4000-8000-000000000001',clock_timestamp(),'finance:test',
  'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,
  repeat('4',64),repeat('5',64),repeat('6',64),12345,
  'f2600000-0000-4000-8000-000000000002',repeat('7',64),'f2600000-0000-4000-8000-000000000003',repeat('8',64)
);

create temporary table finance_acceptance_payload as
select jsonb_build_object(
  'acceptance_contract_version',1,'issuance_id','f2600000-0000-4000-8000-000000000001',
  'quotation_number','LWS-OFF-2099-0101','quotation_version',1,
  'customer_identity_sha256',repeat('b',64),'generation_payload_sha256',repeat('5',64),
  'template',jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',repeat('3',64)),
  'docx',jsonb_build_object('sha256',repeat('6',64),'bytes',12345),
  'acceptance_terms',jsonb_build_object('terms_id','LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','terms_version','1.0.0-technical','terms_sha256',repeat('9',64)),
  'actor',jsonb_build_object('name','Finance Acceptant','email','acceptant@example.test','organization','Finance Website BV','role','Bestuurder'),
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
  'f2700000-0000-4000-8000-000000000001','f2600000-0000-4000-8000-000000000001','LWS-OFF-2099-0101',1,repeat('b',64),'Finance Website BV',
  repeat('5',64),'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),repeat('6',64),12345,
  1,'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical',repeat('9',64),
  'Finance Acceptant','acceptant@example.test','Finance Website BV','Bestuurder',true,
  payload,public.quotation_acceptance_payload_sha256_v1(payload),repeat('f',64),
  '2026-08-20T12:00:00Z','2026-08-20T12:00:00Z'
from finance_acceptance_payload;

create temporary table finance_project as
select public.promote_operator_application_v1(
  'f2800000-0000-4000-8000-000000000001',
  'f2100000-0000-4000-8000-000000000001', null
) as result;

select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'prepare_milestone_1',
  'QUOTE_ACCEPTED', 1, 'f2800000-0000-4000-8000-000000000002', '{}'::jsonb
);

create temporary table finance_m1_evidence as
select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'record_payment_evidence',
  'M1_PAYMENT_PENDING', 2, 'f2800000-0000-4000-8000-000000000003',
  jsonb_build_object('expected_reference','LWS-MILESTONE-'||(select result->>'project_id' from finance_project)||'-M1','received_amount_minor',140000,'transaction_date','2026-08-22','transaction_reference','F2-M1','evidence_reference','finance-f2/m1','bank_iban','BE42 7380 5510 8954')
) as result;
select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'reconcile_payment',
  'M1_PAYMENT_PENDING', 2, 'f2800000-0000-4000-8000-000000000004',
  jsonb_build_object('payment_evidence_id',(select result->>'entity_id' from finance_m1_evidence))
);
select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'confirm_payment',
  'M1_PAYMENT_PENDING', 2, 'f2800000-0000-4000-8000-000000000005', jsonb_build_object('milestone',1)
);

create temporary table finance_m1_duplicate as
select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'record_payment_evidence',
  'M1_PAYMENT_RECEIVED', 3, 'f2800000-0000-4000-8000-000000000006',
  jsonb_build_object('expected_reference','LWS-MILESTONE-'||(select result->>'project_id' from finance_project)||'-M1','received_amount_minor',140000,'transaction_date','2026-08-23','transaction_reference','F2-M1-DUP','evidence_reference','finance-f2/m1-duplicate','bank_iban','BE42 7380 5510 8954')
) as result;
select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'reconcile_payment',
  'M1_PAYMENT_RECEIVED', 3, 'f2800000-0000-4000-8000-000000000007',
  jsonb_build_object('payment_evidence_id',(select result->>'entity_id' from finance_m1_duplicate))
);

create temporary table finance_m2_evidence as
select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'record_payment_evidence',
  'M1_PAYMENT_RECEIVED', 3, 'f2800000-0000-4000-8000-000000000008',
  jsonb_build_object('expected_reference','LWS-MILESTONE-'||(select result->>'project_id' from finance_project)||'-M2','received_amount_minor',140000,'transaction_date','2026-08-24','transaction_reference','F2-M2','evidence_reference','finance-f2/m2','bank_iban','BE42 7380 5510 8954')
) as result;
select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'reconcile_payment',
  'M1_PAYMENT_RECEIVED', 3, 'f2800000-0000-4000-8000-000000000009',
  jsonb_build_object('payment_evidence_id',(select result->>'entity_id' from finance_m2_evidence))
);

select public.execute_commercial_command_v2(
  (select (result->>'project_id')::uuid from finance_project), 'record_payment_evidence',
  'M1_PAYMENT_RECEIVED', 3, 'f2800000-0000-4000-8000-000000000010',
  jsonb_build_object('expected_reference','LWS-MILESTONE-'||(select result->>'project_id' from finance_project)||'-M3','received_amount_minor',70000,'transaction_date','2026-08-25','transaction_reference','F2-M3','evidence_reference','finance-f2/m3','bank_iban','BE42 7380 5510 8954')
);

select is(jsonb_array_length(public.get_website_finance_portfolio_v1()->'projects'), 1, 'portfolio includes exactly one Website project and excludes SDF');
select is(public.get_website_finance_portfolio_v1()->'projects'->0->>'request_kind', 'website', 'classification comes from authoritative request_kind');
select is(public.get_website_finance_portfolio_v1()->'projects'->0->>'application_reference', 'LWS-AAN-2099-0101', 'portfolio exposes the authoritative application reference');
select is((public.get_website_finance_portfolio_v1()->'projects'->0->>'accepted_total_minor')::bigint, 350000::bigint, 'project commitment is preserved');
select is(
  (public.get_website_finance_portfolio_v1()->'projects'->0->>'m1_minor')::bigint
  + (public.get_website_finance_portfolio_v1()->'projects'->0->>'m2_minor')::bigint
  + (public.get_website_finance_portfolio_v1()->'projects'->0->>'m3_minor')::bigint,
  350000::bigint, 'milestone commitments reconcile to accepted total'
);
select is((public.get_website_finance_portfolio_v1()->'projects'->0->>'expected_minor')::bigint, 350000::bigint, 'expected total sums each project expectation once');
select is((public.get_website_finance_portfolio_v1()->'projects'->0->>'confirmed_received_minor')::bigint, 140000::bigint, 'only confirmed M1 is received');
select is(
  public.get_website_finance_portfolio_v1()->'currency_totals'->0,
  '{"currency":"EUR","total_commitment_minor":350000,"total_expected_minor":350000,"total_confirmed_received_minor":140000}'::jsonb,
  'currency aggregate keeps commitment expected and confirmed received separate'
);
select is(public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->0->>'payment_status', 'CONFIRMED', 'M1 is confirmed');
select is(public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->1->>'payment_status', 'MATCHED_AWAITING_CONFIRMATION', 'M2 MATCHED without confirmation is not received');
select is(public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->2->>'payment_status', 'EVIDENCE_RECORDED', 'M3 evidence alone is not received');
select is((public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->1->>'confirmed_received_minor')::bigint, 0::bigint, 'MATCHED without confirmation contributes zero confirmed cash');
select is((public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->2->>'confirmed_received_minor')::bigint, 0::bigint, 'evidence alone contributes zero confirmed cash');
select is((public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->0->>'confirmed_received_minor')::bigint, 140000::bigint, 'duplicate M1 evidence cannot double count confirmed receipt');
select is(
  (select sum((milestone.value->>'confirmed_received_minor')::bigint)::bigint
   from jsonb_array_elements(public.get_website_finance_portfolio_v1()->'projects'->0->'milestones') as milestone(value)),
  (public.get_website_finance_portfolio_v1()->'projects'->0->>'confirmed_received_minor')::bigint,
  'milestone confirmed receipts reconcile exactly to the project confirmed total'
);
select ok(
  public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->0->'payment_confirmation_date' <> 'null'::jsonb
  and public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->1->'reconciliation_date' <> 'null'::jsonb
  and public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->2->'transaction_date' <> 'null'::jsonb,
  'dates retain explicit payment confirmation reconciliation and transaction meanings'
);
select ok(
  public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->1->'payment_confirmation_date' = 'null'::jsonb
  and public.get_website_finance_portfolio_v1()->'projects'->0->'milestones'->2->'reconciliation_date' = 'null'::jsonb,
  'missing confirmation and reconciliation dates remain null rather than fabricated'
);
select is(jsonb_array_length(public.get_website_finance_portfolio_v1()->'currency_totals'), 1, 'currency totals are grouped rather than blindly mixed');
select ok(
  (select pg_get_constraintdef(oid) like '%currency = %EUR%'
   from pg_constraint
   where conrelid='public.commercial_projects'::regclass
     and conname='commercial_projects_currency_check'),
  'current project authority constrains portfolio money to EUR'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000002', true);
select throws_ok($$select public.get_website_finance_portfolio_v1()$$, '42501', 'WEBSITE_FINANCE_PORTFOLIO_OWNER_REQUIRED', 'active admin is denied');
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000003', true);
select throws_ok($$select public.get_website_finance_portfolio_v1()$$, '42501', 'WEBSITE_FINANCE_PORTFOLIO_OWNER_REQUIRED', 'project-scoped operator is denied the global portfolio');
select throws_ok(
  format('select public.get_commercial_project_view_v2(%L)', (select result->>'project_id' from finance_project)),
  '42501', 'PROJECT_SCOPE_DENIED', 'existing per-project isolation remains closed without a grant'
);
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000004', true);
select throws_ok($$select public.get_website_finance_portfolio_v1()$$, '42501', 'UNKNOWN_OPERATOR', 'unknown human is denied');
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select public.get_website_finance_portfolio_v1()$$, '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is denied');

select * from finish();
rollback;
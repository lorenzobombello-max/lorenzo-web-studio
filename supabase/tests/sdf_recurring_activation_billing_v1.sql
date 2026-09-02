begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public','sdf_recurring_activation_obligations','recurring activation obligation authority exists');
select has_table('public','sdf_recurring_invoice_candidates','recurring invoice candidate authority exists');
select has_table('public','sdf_recurring_invoice_issuances','recurring invoice issuance authority exists');
select has_function(
  'public','create_sdf_recurring_activation_obligation_v1',array['uuid','uuid'],
  'OPERATIONAL_ACTIVATED creates the first recurring EXPECTED obligation'
);
select has_function(
  'public','prepare_sdf_recurring_invoice_candidate_v1',array['uuid','uuid'],
  'recurring EXPECTED obligation prepares an invoice candidate'
);
select has_function(
  'public','issue_sdf_recurring_invoice_v1',
  array['uuid','smallint','uuid','text','bigint','text','bigint'],
  'recurring candidate issues through the existing invoice authority'
);

select to_regprocedure('public.create_sdf_recurring_activation_obligation_v1(uuid,uuid)') is not null
  and to_regprocedure('public.prepare_sdf_recurring_invoice_candidate_v1(uuid,uuid)') is not null
  and to_regprocedure('public.issue_sdf_recurring_invoice_v1(uuid,smallint,uuid,text,bigint,text,bigint)') is not null
  as recurring_implemented \gset

\if :recurring_implemented

create temporary table recurring_cases(
  tag integer primary key,
  sdf_package text not null,
  expected_recurring bigint,
  request_kind text not null,
  project_id uuid not null,
  quote_request_id uuid not null,
  quotation_id uuid not null,
  accepted_terms_id uuid not null,
  commercial_decision_id uuid not null,
  phase_b_event_id uuid not null,
  activation_event_id uuid
);

insert into auth.users(id,email) values
  ('c1000000-0000-4000-8000-000000000001','recurring-owner@example.test'),
  ('c1000000-0000-4000-8000-000000000002','recurring-operator@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  ('c1100000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','Recurring Owner','owner','ACTIVE'),
  ('c1100000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002','Recurring Operator','operator','ACTIVE');

create function pg_temp.payment_schedule(p_amount bigint)
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object(
    'schedule_id','recurring-fixture',
    'milestones',jsonb_build_array(jsonb_build_object(
      'sequence',1,'label','Synthetic implementation payment','percentage',null,
      'amount_minor',p_amount,'trigger','invoice','due_terms_days',30,'recurring_cycle',null
    )),
    'approved_by','OPERATOR:c1100000-0000-4000-8000-000000000001',
    'approved_at','2098-01-01T00:00:00.000000Z'
  )
$$;

set local session_replication_role = replica;
do $$
declare
  v_tag integer;
  v_package text;
  v_kind text;
  v_implementation bigint;
  v_recurring bigint;
  v_decision_recurring bigint;
  v_request uuid;
  v_project uuid;
  v_quotation uuid;
  v_terms uuid;
  v_decision uuid;
  v_preparation uuid;
  v_phase_b uuid;
  v_activation uuid;
  v_schedule jsonb;
  v_payload jsonb;
  v_decision_sha text;
  v_project_sha text;
begin
  for v_tag in 1..9 loop
    v_package := case v_tag when 1 then 'start' when 2 then 'groei' when 3 then 'pro' when 4 then 'maatwerk' when 5 then 'maatwerk' else 'start' end;
    v_kind := case when v_tag=8 then 'website' else 'slimme_documentenflow' end;
    v_implementation := case v_package when 'start' then 285000 when 'groei' then 570000 when 'pro' then 750000 else 910000 end;
    v_recurring := case v_package when 'start' then 17500 when 'groei' then 29900 when 'pro' then 44900 else 53700 end;
    v_decision_recurring := case when v_tag=9 then 17600 else v_recurring end;
    v_request := gen_random_uuid();
    v_project := gen_random_uuid();
    v_quotation := gen_random_uuid();
    v_terms := gen_random_uuid();
    v_decision := gen_random_uuid();
    v_preparation := gen_random_uuid();
    v_phase_b := gen_random_uuid();
    v_activation := case when v_tag=6 then null else gen_random_uuid() end;
    v_project_sha := encode(digest(convert_to(format('recurring-project-%s',v_tag),'UTF8'),'sha256'),'hex');
    v_schedule := pg_temp.payment_schedule(v_implementation);
    v_payload := jsonb_build_object(
      'authority_version',1,'quote_request_id',v_request,
      'preparation_authority_id',v_preparation,'quotation_id',v_quotation,
      'submission_sha256',repeat('1',64),'pricing_authority_version',1,
      'pricing_authority_sha256',repeat('2',64),'document_evidence_sha256',repeat('3',64),
      'sdf_package',v_package,'implementation_amount_minor',v_implementation,
      'recurring_amount_minor',v_decision_recurring,'currency','EUR',
      'vat_decision_authority_id',gen_random_uuid(),'vat_resolution_date','2098-01-01',
      'vat_context_sha256',repeat('4',64),'vat_classification_id',gen_random_uuid(),
      'vat_turnover_snapshot_id',gen_random_uuid(),'terms_authority_id',gen_random_uuid(),
      'payment_schedule',v_schedule
    );
    v_decision_sha := encode(digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');

    if v_kind='slimme_documentenflow' then
      insert into public.quote_requests(
        id,application_reference,request_kind,sdf_package,name,company,email,customer_type,
        enterprise_number,enterprise_validation_status,vat_number,vat_validation_status,
        vat_validated_at,billing_address,billing_postal_code,billing_city,billing_country,
        billing_email,description,privacy_consent,status
      ) values (
        v_request,format('LWS-AAN-2097-%s',lpad(v_tag::text,4,'0')),v_kind,v_package,
        format('Recurring Customer %s',v_tag),format('Recurring BV %s',v_tag),
        format('recurring-%s@example.test',v_tag),'business',lpad(v_tag::text,10,'0'),
        'format_valid_not_externally_verified',format('BE%s',lpad(v_tag::text,10,'0')),
        'valid','2097-01-01T00:00:00Z','Teststraat 1','9000','Gent','BE',
        format('invoice-%s@example.test',v_tag),'Synthetic recurring fixture.',true,'approved'
      );
    else
      insert into public.quote_requests(
        id,request_kind,name,email,website_type,budget,timing,description,privacy_consent,status
      ) values (
        v_request,'website','Website Recurring Customer','website-recurring@example.test',
        'business','Meer dan EUR 6.000','flexible','Synthetic Website fixture.',true,'approved'
      );
    end if;

    insert into public.sdf_projects(project_id,quote_request_id) values(v_project,v_request);
    insert into public.sdf_quotation_commercial_decisions(
      decision_id,quote_request_id,preparation_authority_id,quotation_id,
      vat_decision_authority_id,vat_resolution_date,vat_context_sha256,
      vat_classification_id,vat_turnover_snapshot_id,terms_authority_id,sdf_package,
      pricing_authority_version,pricing_authority_sha256,submission_sha256,
      document_evidence_sha256,payment_schedule,canonical_payload,decision_sha256,
      actor_operator_id,actor_role,decided_at,idempotency_key,request_fingerprint
    ) values (
      v_decision,v_request,v_preparation,v_quotation,
      (v_payload->>'vat_decision_authority_id')::uuid,'2098-01-01',repeat('4',64),
      (v_payload->>'vat_classification_id')::uuid,(v_payload->>'vat_turnover_snapshot_id')::uuid,
      (v_payload->>'terms_authority_id')::uuid,v_package,1,repeat('2',64),repeat('1',64),
      repeat('3',64),v_schedule,v_payload,v_decision_sha,
      'c1100000-0000-4000-8000-000000000001','owner','2098-01-01T00:00:00Z',
      gen_random_uuid(),encode(digest(convert_to(format('decision-%s',v_tag),'UTF8'),'sha256'),'hex')
    );
    insert into public.sdf_accepted_commercial_terms(
      accepted_terms_id,quotation_id,quote_request_id,sdf_package,
      accepted_implementation_amount_minor,currency,vat_basis,pricing_authority_version,
      creation_idempotency_key,creation_fingerprint,created_by_operator_id,created_at,
      accepted_recurring_amount_minor,pricing_mode,commercial_decision_id,commercial_decision_sha256
    ) values (
      v_terms,v_quotation,v_request,v_package,v_implementation,'EUR','exclusive',1,
      gen_random_uuid(),encode(digest(convert_to(format('terms-%s',v_tag),'UTF8'),'sha256'),'hex'),
      'c1100000-0000-4000-8000-000000000001','2098-01-02T00:00:00Z',
      case when v_tag=5 or v_package<>'maatwerk' then null else v_recurring end,
      case when v_package='maatwerk' then 'manual' else null end,
      case when v_package='maatwerk' then v_decision else null end,
      case when v_package='maatwerk' then v_decision_sha else null end
    );
    insert into public.sdf_project_lifecycle_events(
      lifecycle_event_id,project_id,quote_request_id,request_kind,accepted_terms_id,quotation_id,
      project_linkage_sha256,previous_state,new_state,start_authority_id,predecessor_event_id,
      capability_id,actor_type,actor_operator_id,actor_identity,occurred_at,evidence_reference,
      evidence_sha256,idempotency_key,request_fingerprint,audit_metadata,created_at
    ) values (
      v_phase_b,v_project,v_request,'slimme_documentenflow',v_terms,v_quotation,v_project_sha,
      'PHASE_A_CONFIRMED','PHASE_B_CONFIRMED',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
      'CUSTOMER',null,jsonb_build_object('signer','Synthetic Customer'),
      format('2098-03-%s 10:00:00Z',lpad(v_tag::text,2,'0'))::timestamptz,
      format('sdf/recurring/%s/phase-b.pdf',v_tag),repeat('5',64),gen_random_uuid(),repeat('6',64),
      '{}'::jsonb,format('2098-03-%s 10:00:00Z',lpad(v_tag::text,2,'0'))::timestamptz
    );
    if v_activation is not null then
      insert into public.sdf_project_lifecycle_events(
        lifecycle_event_id,project_id,quote_request_id,request_kind,accepted_terms_id,quotation_id,
        project_linkage_sha256,previous_state,new_state,start_authority_id,predecessor_event_id,
        capability_id,actor_type,actor_operator_id,actor_identity,occurred_at,evidence_reference,
        evidence_sha256,idempotency_key,request_fingerprint,audit_metadata,created_at
      ) values (
        v_activation,case when v_tag=7 then gen_random_uuid() else v_project end,v_request,
        'slimme_documentenflow',v_terms,v_quotation,v_project_sha,'PHASE_B_CONFIRMED',
        'OPERATIONAL_ACTIVATED',gen_random_uuid(),v_phase_b,null,'OWNER',
        'c1100000-0000-4000-8000-000000000001',jsonb_build_object('role','owner'),
        format('2098-04-%s 10:00:00Z',lpad(v_tag::text,2,'0'))::timestamptz,
        format('sdf/recurring/%s/operational.pdf',v_tag),repeat('7',64),gen_random_uuid(),
        encode(digest(convert_to(format('activation-%s',v_tag),'UTF8'),'sha256'),'hex'),
        jsonb_build_object('activationMode','OWNER_CONFIRMED'),
        format('2098-04-%s 10:00:00Z',lpad(v_tag::text,2,'0'))::timestamptz
      );
    end if;
    insert into recurring_cases values(
      v_tag,v_package,v_recurring,v_kind,v_project,v_request,v_quotation,v_terms,
      v_decision,v_phase_b,v_activation
    );
  end loop;
end;
$$;

insert into public.sdf_quotation_vat_authority_bindings(
  quotation_id,quote_request_id,vat_decision_authority_id,vat_authority_version,
  vat_authority_sha256,vat_treatment,rate_semantics,invoice_literal,context_sha256,
  classification_id,turnover_snapshot_id,bound_by_operator_id,bound_at
)
select quotation_id,quote_request_id,
  (select vat_decision_authority_id from public.quotation_vat_decision_authorities
   where authority_family='LWS_OUTGOING_VAT' and status='APPROVED'),
  'LWS_OUTGOING_VAT/1.0.0',repeat('8',64),
  'EXEMPT','NOT_APPLICABLE','Bijzondere vrijstellingsregeling van belasting',repeat('9',64),
  gen_random_uuid(),gen_random_uuid(),'c1100000-0000-4000-8000-000000000001','2098-01-01T00:00:00Z'
from recurring_cases;
set local session_replication_role = origin;

select ok(
  (select bool_and(relrowsecurity and relforcerowsecurity)
   from pg_class where oid in (
     'public.sdf_recurring_activation_obligations'::regclass,
     'public.sdf_recurring_invoice_candidates'::regclass,
     'public.sdf_recurring_invoice_issuances'::regclass
   )),
  'all recurring authority tables have forced RLS'
);
select ok(
  not has_table_privilege('authenticated','public.sdf_recurring_activation_obligations','insert')
  and not has_table_privilege('service_role','public.sdf_recurring_invoice_issuances','insert'),
  'runtime roles cannot directly mutate recurring authority'
);

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000001',true);
create temporary table recurring_created(tag integer primary key,obligation_id uuid not null);
insert into recurring_created
select tag,(public.create_sdf_recurring_activation_obligation_v1(
  activation_event_id,
  case when tag=1 then 'c4000000-0000-4000-8000-000000000001'::uuid else gen_random_uuid() end
)->>'obligation_id')::uuid
from recurring_cases where tag in (1,2,3,4);

select is((select amount_minor from public.sdf_recurring_activation_obligations where obligation_id=(select obligation_id from recurring_created where tag=1)),17500::bigint,'START activation creates recurring EXPECTED 17500');
select is((select amount_minor from public.sdf_recurring_activation_obligations where obligation_id=(select obligation_id from recurring_created where tag=2)),29900::bigint,'GROEI activation creates recurring EXPECTED 29900');
select is((select amount_minor from public.sdf_recurring_activation_obligations where obligation_id=(select obligation_id from recurring_created where tag=3)),44900::bigint,'PRO activation creates recurring EXPECTED 44900');
select is((select amount_minor from public.sdf_recurring_activation_obligations where obligation_id=(select obligation_id from recurring_created where tag=4)),53700::bigint,'MAATWERK activation reads exact accepted recurring amount 53700');
select throws_ok(
  format($sql$select public.create_sdf_recurring_activation_obligation_v1(%L,%L)$sql$,
    (select activation_event_id from recurring_cases where tag=5),gen_random_uuid()),
  '23514','SDF_MAATWERK_RECURRING_AMOUNT_REQUIRED','missing accepted MAATWERK recurring amount fails closed'
);
select throws_ok(
  format($sql$select public.create_sdf_recurring_activation_obligation_v1(%L,%L)$sql$,
    (select phase_b_event_id from recurring_cases where tag=6),gen_random_uuid()),
  '23503','SDF_OPERATIONAL_ACTIVATION_REQUIRED','Phase B alone creates no recurring obligation'
);
select is((select count(*)::integer from public.sdf_recurring_activation_obligations where sdf_project_id=(select project_id from recurring_cases where tag=6)),0,'before operational activation no recurring obligation exists');

select is(
  (public.create_sdf_recurring_activation_obligation_v1(
    (select activation_event_id from recurring_cases where tag=1),
    'c4000000-0000-4000-8000-000000000001'
  )->>'obligation_id')::uuid,
  (select obligation_id from recurring_created where tag=1),
  'duplicate activation processing returns the one canonical obligation'
);
select is(
  (public.create_sdf_recurring_activation_obligation_v1(
    (select activation_event_id from recurring_cases where tag=1),
    'c4000000-0000-4000-8000-000000000001'
  )->>'was_created')::boolean,
  false,
  'same recurring retry is idempotent'
);
select throws_ok(
  format($sql$select public.create_sdf_recurring_activation_obligation_v1(%L,'c4000000-0000-4000-8000-000000000001')$sql$,
    (select activation_event_id from recurring_cases where tag=2)),
  'P0001','IDEMPOTENCY_CONFLICT','changed recurring replay conflicts'
);
select throws_ok(
  format($sql$select public.create_sdf_recurring_activation_obligation_v1(%L,%L)$sql$,
    (select activation_event_id from recurring_cases where tag=7),gen_random_uuid()),
  '23514','SDF_RECURRING_PROJECT_LINKAGE_MISMATCH','wrong project linkage is rejected'
);
select throws_ok(
  format($sql$select public.create_sdf_recurring_activation_obligation_v1(%L,%L)$sql$,
    (select activation_event_id from recurring_cases where tag=8),gen_random_uuid()),
  '23514','SDF_FINANCIAL_AUTHORITY_REQUIRES_SDF','Website request cannot enter the SDF recurring route'
);
select throws_ok(
  format($sql$select public.create_sdf_recurring_activation_obligation_v1(%L,%L)$sql$,
    (select activation_event_id from recurring_cases where tag=9),gen_random_uuid()),
  '55000','SDF_RECURRING_COMMERCIAL_SNAPSHOT_STALE','stale fixed-package commercial amount is rejected'
);

create temporary table recurring_candidate as
select public.prepare_sdf_recurring_invoice_candidate_v1(
  (select obligation_id from recurring_created where tag=1),gen_random_uuid()
) result;
select is((select obligation_state from public.sdf_recurring_activation_obligations where obligation_id=(select obligation_id from recurring_created where tag=1)),'EXPECTED','candidate preparation leaves recurring obligation EXPECTED');
select is((select result->>'invoice_number' from recurring_candidate),null,'recurring candidate allocates no invoice number');
select matches(
  (select invoice_description from public.sdf_recurring_invoice_candidates where candidate_id=(select (result->>'candidate_id')::uuid from recurring_candidate)),
  '^Slimme Documentenflow — recurrente dienstverlening activation anchor .* — pakket START$',
  'description uses only the activation anchor and package without invented calendar boundaries'
);

create temporary table recurring_issuance as
select public.issue_sdf_recurring_invoice_v1(
  (select (result->>'candidate_id')::uuid from recurring_candidate),
  extract(year from clock_timestamp() at time zone 'Europe/Brussels')::smallint,
  gen_random_uuid(),repeat('a',64),1000,repeat('b',64),900
) result;
select is((select issuance_state from public.sdf_recurring_invoice_issuances where issuance_id=(select (result->>'issuance_id')::uuid from recurring_issuance)),'INVOICED','recurring issuance records INVOICED separately from EXPECTED');
select is((select obligation_state from public.sdf_recurring_activation_obligations where obligation_id=(select obligation_id from recurring_created where tag=1)),'EXPECTED','invoice issuance does not rewrite the EXPECTED obligation');
select ok(
  not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='sdf_recurring_invoice_issuances'
      and column_name in ('received_at','reconciled_at','payment_receipt_id')
  ),
  'recurring INVOICED authority contains no RECEIVED or RECONCILED state'
);
select is((select count(*)::integer from public.sdf_m1_payment_receipts),0,'recurring issuance creates no payment receipt');

select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000002',true);
select throws_ok(
  format($sql$select public.create_sdf_recurring_activation_obligation_v1(%L,%L)$sql$,
    (select activation_event_id from recurring_cases where tag=5),gen_random_uuid()),
  '42501','SDF_INVOICE_AUTHORITY_DENIED','ordinary operator cannot create recurring financial authority'
);
select throws_ok($$update public.sdf_recurring_activation_obligations set amount_minor=1$$,'55000','SDF_INVOICE_FOUNDATION_IMMUTABLE','recurring obligations reject mutation');
select is((select count(*)::integer from public.recurring_services),0,'recurring slice creates no scheduler-backed recurring service');

\endif

select * from finish();
rollback;
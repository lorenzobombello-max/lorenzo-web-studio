begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public','sdf_post_start_milestone_obligations','M2/M3 share one post-start obligation authority');
select has_table('public','sdf_post_start_invoice_candidates','M2/M3 share one post-start candidate authority');
select has_table('public','sdf_post_start_invoice_issuances','M2/M3 share one post-start issuance authority');
select has_function(
  'public','create_sdf_post_start_milestone_obligation_v1',array['uuid','uuid'],
  'lifecycle event creates a canonical M2/M3 EXPECTED obligation'
);
select has_function(
  'public','prepare_sdf_post_start_invoice_candidate_v1',array['uuid','uuid'],
  'post-start obligation prepares an invoice candidate'
);
select has_function(
  'public','issue_sdf_post_start_invoice_v1',
  array['uuid','smallint','uuid','text','bigint','text','bigint'],
  'post-start candidate issues through artifact-aware invoice authority'
);

select to_regprocedure('public.create_sdf_post_start_milestone_obligation_v1(uuid,uuid)') is not null
  and to_regprocedure('public.prepare_sdf_post_start_invoice_candidate_v1(uuid,uuid)') is not null
  and to_regprocedure('public.issue_sdf_post_start_invoice_v1(uuid,smallint,uuid,text,bigint,text,bigint)') is not null
  as m2_m3_implemented \gset

\if :m2_m3_implemented

create temporary table billing_cases (
  tag integer primary key,
  sdf_package text not null,
  implementation_amount bigint,
  request_kind text not null,
  project_id uuid not null,
  quote_request_id uuid not null,
  quotation_id uuid not null,
  accepted_terms_id uuid,
  phase_a_event_id uuid,
  phase_b_event_id uuid
);

insert into auth.users(id,email) values
  ('b1000000-0000-4000-8000-000000000001','m2m3-owner@example.test'),
  ('b1000000-0000-4000-8000-000000000002','m2m3-operator@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  ('b1100000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','M2 M3 Owner','owner','ACTIVE'),
  ('b1100000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000002','M2 M3 Operator','operator','ACTIVE');

set local session_replication_role = replica;
do $$
declare
  v_tag integer;
  v_package text;
  v_amount bigint;
  v_kind text;
  v_project uuid;
  v_request uuid;
  v_quotation uuid;
  v_terms uuid;
  v_phase_a uuid;
  v_phase_b uuid;
  v_has_a boolean;
  v_has_b boolean;
begin
  for v_tag in 1..13 loop
    v_package := case
      when v_tag in (1,5,9,10,12) then 'start'
      when v_tag in (2,6) then 'groei'
      when v_tag in (3,7) then 'pro'
      else 'maatwerk' end;
    v_amount := case v_package
      when 'start' then 285000 when 'groei' then 570000
      when 'pro' then 750000 else 1000000 end;
    v_kind := case when v_tag=11 then 'website' else 'slimme_documentenflow' end;
    v_project := gen_random_uuid();
    v_request := gen_random_uuid();
    v_quotation := gen_random_uuid();
    v_terms := case when v_tag=13 then gen_random_uuid() else gen_random_uuid() end;
    v_phase_a := gen_random_uuid();
    v_phase_b := gen_random_uuid();
    v_has_a := v_tag <> 9;
    v_has_b := v_tag in (5,6,7,8,13);

    if v_kind='slimme_documentenflow' then
      insert into public.quote_requests(
        id,application_reference,request_kind,sdf_package,name,company,email,customer_type,
        enterprise_number,enterprise_validation_status,vat_number,vat_validation_status,vat_validated_at,
        billing_address,billing_postal_code,billing_city,billing_country,billing_email,
        description,privacy_consent,status
      ) values (
        v_request,format('LWS-AAN-2098-%s',lpad(v_tag::text,4,'0')),v_kind,v_package,
        format('Billing Customer %s',v_tag),format('Billing BV %s',v_tag),
        format('billing-%s@example.test',v_tag),'business',lpad(v_tag::text,10,'0'),
        'format_valid_not_externally_verified',format('BE%s',lpad(v_tag::text,10,'0')),
        'valid','2098-01-01T08:00:00Z','Teststraat 1','9000','Gent','BE',
        format('invoice-%s@example.test',v_tag),'Synthetic M2/M3 fixture.',true,'approved'
      );
    else
      insert into public.quote_requests(
        id,request_kind,name,email,website_type,budget,timing,description,privacy_consent,status
      ) values (
        v_request,'website','Website Billing Customer','website-billing@example.test',
        'business','Meer dan EUR 6.000','flexible','Synthetic Website isolation fixture.',true,'approved'
      );
    end if;

    insert into public.sdf_projects(project_id,quote_request_id) values (v_project,v_request);
    if v_tag<>13 then
      insert into public.sdf_accepted_commercial_terms(
        accepted_terms_id,quotation_id,quote_request_id,sdf_package,accepted_implementation_amount_minor,
        currency,vat_basis,pricing_authority_version,creation_idempotency_key,creation_fingerprint,
        created_by_operator_id
      ) values (
        v_terms,v_quotation,v_request,v_package,v_amount,'EUR','exclusive',1,gen_random_uuid(),
        encode(digest(convert_to(format('terms-%s',v_tag),'UTF8'),'sha256'),'hex'),
        'b1100000-0000-4000-8000-000000000001'
      );
    end if;

    if v_has_a then
      insert into public.sdf_project_lifecycle_events(
        lifecycle_event_id,project_id,quote_request_id,request_kind,accepted_terms_id,quotation_id,
        project_linkage_sha256,previous_state,new_state,start_authority_id,predecessor_event_id,
        capability_id,actor_type,actor_operator_id,actor_identity,occurred_at,evidence_reference,
        evidence_sha256,idempotency_key,request_fingerprint,audit_metadata,created_at
      ) values (
        v_phase_a,case when v_tag=10 then gen_random_uuid() else v_project end,v_request,
        'slimme_documentenflow',v_terms,v_quotation,
        encode(digest(convert_to(format('project-%s',v_tag),'UTF8'),'sha256'),'hex'),
        'PROJECT_STARTED','PHASE_A_CONFIRMED',gen_random_uuid(),null,gen_random_uuid(),'CUSTOMER',null,
        jsonb_build_object('signer','Synthetic Customer'),
        format('2098-02-%s 10:00:00Z',lpad(v_tag::text,2,'0'))::timestamptz,
        format('sdf/delivery/%s/phase-a.pdf',v_tag),
        encode(digest(convert_to(format('phase-a-%s',v_tag),'UTF8'),'sha256'),'hex'),
        gen_random_uuid(),encode(digest(convert_to(format('event-a-%s',v_tag),'UTF8'),'sha256'),'hex'),
        '{}'::jsonb,format('2098-02-%s 10:00:00Z',lpad(v_tag::text,2,'0'))::timestamptz
      );
    end if;
    if v_has_b then
      insert into public.sdf_project_lifecycle_events(
        lifecycle_event_id,project_id,quote_request_id,request_kind,accepted_terms_id,quotation_id,
        project_linkage_sha256,previous_state,new_state,start_authority_id,predecessor_event_id,
        capability_id,actor_type,actor_operator_id,actor_identity,occurred_at,evidence_reference,
        evidence_sha256,idempotency_key,request_fingerprint,audit_metadata,created_at
      ) values (
        v_phase_b,v_project,v_request,'slimme_documentenflow',v_terms,v_quotation,
        encode(digest(convert_to(format('project-%s',v_tag),'UTF8'),'sha256'),'hex'),
        'PHASE_A_CONFIRMED','PHASE_B_CONFIRMED',gen_random_uuid(),v_phase_a,gen_random_uuid(),
        'CUSTOMER',null,jsonb_build_object('signer','Synthetic Customer'),
        format('2098-03-%s 10:00:00Z',lpad(v_tag::text,2,'0'))::timestamptz,
        format('sdf/delivery/%s/phase-b.pdf',v_tag),
        encode(digest(convert_to(format('phase-b-%s',v_tag),'UTF8'),'sha256'),'hex'),
        gen_random_uuid(),encode(digest(convert_to(format('event-b-%s',v_tag),'UTF8'),'sha256'),'hex'),
        '{}'::jsonb,format('2098-03-%s 10:00:00Z',lpad(v_tag::text,2,'0'))::timestamptz
      );
    end if;
    insert into billing_cases values (
      v_tag,v_package,v_amount,v_kind,v_project,v_request,v_quotation,v_terms,
      case when v_has_a then v_phase_a end,case when v_has_b then v_phase_b end
    );
  end loop;
end;
$$;
set local session_replication_role = origin;

select ok(
  (select bool_and(relrowsecurity and relforcerowsecurity)
   from pg_class where oid in (
     'public.sdf_post_start_milestone_obligations'::regclass,
     'public.sdf_post_start_invoice_candidates'::regclass,
     'public.sdf_post_start_invoice_issuances'::regclass
   )),
  'all post-start billing authority tables have forced RLS'
);
select ok(
  not has_table_privilege('authenticated','public.sdf_post_start_milestone_obligations','select')
  and not has_table_privilege('authenticated','public.sdf_post_start_milestone_obligations','insert')
  and not has_table_privilege('service_role','public.sdf_post_start_invoice_issuances','insert'),
  'runtime roles cannot directly read or mutate post-start billing authority'
);
select ok(
  not exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name in ('sdf_post_start_milestone_obligations','sdf_post_start_invoice_candidates','sdf_post_start_invoice_issuances')
      and column_name like '%recurring%'
  ),
  'M2/M3 authority contains no recurring billing fields'
);

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
create temporary table created_obligations(tag integer primary key, obligation_id uuid not null);
insert into created_obligations
select tag,(public.create_sdf_post_start_milestone_obligation_v1(
  case when tag<=4 or tag=12 then phase_a_event_id else phase_b_event_id end,
  gen_random_uuid()
)->>'obligation_id')::uuid
from billing_cases where tag in (1,2,3,4,5,6,7,8,12);

select is((select amount_minor from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=1)),114000::bigint,'START Phase A creates M2 EXPECTED 114000');
select is((select amount_minor from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=2)),228000::bigint,'GROEI Phase A creates M2 EXPECTED 228000');
select is((select amount_minor from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=3)),300000::bigint,'PRO Phase A creates M2 EXPECTED 300000');
select is((select amount_minor from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=4)),400000::bigint,'MAATWERK Phase A creates exact 40 percent M2');
select is((select amount_minor from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=5)),57000::bigint,'START Phase B creates M3 EXPECTED 57000');
select is((select amount_minor from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=6)),114000::bigint,'GROEI Phase B creates M3 EXPECTED 114000');
select is((select amount_minor from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=7)),150000::bigint,'PRO Phase B creates M3 EXPECTED 150000');
select is((select amount_minor from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=8)),200000::bigint,'MAATWERK Phase B creates exact 20 percent M3');

select throws_ok(
  format('select public.create_sdf_post_start_milestone_obligation_v1(%L,%L)',
    (select phase_a_event_id from billing_cases where tag=13),gen_random_uuid()),
  '23503','SDF_ACCEPTED_TERMS_REQUIRED','missing MAATWERK amount authority fails M2 closed'
);
select throws_ok(
  format('select public.create_sdf_post_start_milestone_obligation_v1(%L,%L)',
    (select phase_b_event_id from billing_cases where tag=13),gen_random_uuid()),
  '23503','SDF_ACCEPTED_TERMS_REQUIRED','missing MAATWERK amount authority fails M3 closed'
);
select throws_ok(
  format('select public.create_sdf_post_start_milestone_obligation_v1(%L,%L)',gen_random_uuid(),gen_random_uuid()),
  '23503','SDF_LIFECYCLE_EVENT_REQUIRED','no Phase A or Phase B means no post-start obligation'
);
select is(
  (select count(*)::integer from public.sdf_post_start_milestone_obligations
   where sdf_project_id=(select project_id from billing_cases where tag=9)),
  0,'no Phase A creates no M2 obligation'
);
select is(
  (select count(*)::integer from public.sdf_post_start_milestone_obligations
   where sdf_project_id=(select project_id from billing_cases where tag=4) and milestone_identity='M3'),
  0,'no Phase B creates no M3 obligation'
);
select is(
  (public.create_sdf_post_start_milestone_obligation_v1(
    (select phase_a_event_id from billing_cases where tag=1),gen_random_uuid()
  )->>'was_created')::boolean,false,
  'duplicate canonical Phase A creates one canonical M2 obligation'
);
select is(
  (select count(*)::integer from public.sdf_post_start_milestone_obligations
   where sdf_project_id=(select project_id from billing_cases where tag=1) and milestone_identity='M2'),
  1,'duplicate Phase A leaves one M2 obligation row'
);
select throws_ok(
  format('select public.create_sdf_post_start_milestone_obligation_v1(%L,%L)',
    (select phase_a_event_id from billing_cases where tag=2),
    (select creation_idempotency_key from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=1))),
  'P0001','IDEMPOTENCY_CONFLICT','changed Phase A replay is rejected'
);
select is(
  (public.create_sdf_post_start_milestone_obligation_v1(
    (select phase_b_event_id from billing_cases where tag=5),gen_random_uuid()
  )->>'was_created')::boolean,false,
  'duplicate canonical Phase B creates one canonical M3 obligation'
);
select throws_ok(
  format('select public.create_sdf_post_start_milestone_obligation_v1(%L,%L)',
    (select phase_b_event_id from billing_cases where tag=6),
    (select creation_idempotency_key from public.sdf_post_start_milestone_obligations where obligation_id=(select obligation_id from created_obligations where tag=5))),
  'P0001','IDEMPOTENCY_CONFLICT','changed Phase B replay is rejected'
);
select throws_ok(
  format('select public.create_sdf_post_start_milestone_obligation_v1(%L,%L)',
    (select phase_a_event_id from billing_cases where tag=10),gen_random_uuid()),
  '23514','SDF_LIFECYCLE_PROJECT_LINKAGE_MISMATCH','wrong project linkage is rejected'
);
select throws_ok(
  format('select public.create_sdf_post_start_milestone_obligation_v1(%L,%L)',
    (select phase_a_event_id from billing_cases where tag=11),gen_random_uuid()),
  '23514','SDF_FINANCIAL_AUTHORITY_REQUIRES_SDF','Website request kind is rejected'
);

set local session_replication_role = replica;
update public.sdf_accepted_commercial_terms
set accepted_implementation_amount_minor=accepted_implementation_amount_minor+5
where accepted_terms_id=(select accepted_terms_id from billing_cases where tag=12);
set local session_replication_role = origin;
select throws_ok(
  format('select public.prepare_sdf_post_start_invoice_candidate_v1(%L,%L)',
    (select obligation_id from created_obligations where tag=12),gen_random_uuid()),
  '55000','SDF_POST_START_COMMERCIAL_SNAPSHOT_STALE','stale commercial snapshot is rejected before candidate preparation'
);

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
select throws_ok(
  format('select public.create_sdf_post_start_milestone_obligation_v1(%L,%L)',
    (select phase_a_event_id from billing_cases where tag=2),gen_random_uuid()),
  '42501','SDF_INVOICE_AUTHORITY_DENIED','ordinary operator cannot mutate M2/M3 financial authority'
);
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);

create temporary table prepared_candidates(tag integer primary key,candidate_id uuid not null);
insert into prepared_candidates values
  (1,(public.prepare_sdf_post_start_invoice_candidate_v1((select obligation_id from created_obligations where tag=1),gen_random_uuid())->>'candidate_id')::uuid),
  (5,(public.prepare_sdf_post_start_invoice_candidate_v1((select obligation_id from created_obligations where tag=5),gen_random_uuid())->>'candidate_id')::uuid);
select is(
  (public.prepare_sdf_post_start_invoice_candidate_v1(
    (select obligation_id from created_obligations where tag=1),gen_random_uuid()
  )->>'was_created')::boolean,false,
  'M2 candidate exact canonical replay returns one candidate'
);
select throws_ok(
  format('select public.prepare_sdf_post_start_invoice_candidate_v1(%L,%L)',
    (select obligation_id from created_obligations where tag=5),
    (select creation_idempotency_key from public.sdf_post_start_invoice_candidates where candidate_id=(select candidate_id from prepared_candidates where tag=1))),
  'P0001','IDEMPOTENCY_CONFLICT','changed candidate replay is rejected'
);

set local session_replication_role = replica;
insert into public.sdf_quotation_vat_authority_bindings(
  quotation_id,quote_request_id,vat_decision_authority_id,vat_authority_version,vat_authority_sha256,
  vat_treatment,rate_semantics,invoice_literal,context_sha256,classification_id,turnover_snapshot_id,
  bound_by_operator_id
)
select quotation_id,quote_request_id,
  (select vat_decision_authority_id from public.quotation_vat_decision_authorities where status='APPROVED' limit 1),
  '1.0.0',repeat('a',64),'EXEMPT','NOT_APPLICABLE',
  'Bijzondere vrijstellingsregeling van belasting',repeat('b',64),gen_random_uuid(),gen_random_uuid(),
  'b1100000-0000-4000-8000-000000000001'
from billing_cases where tag in (1,5);
set local session_replication_role = origin;

create temporary table issued_invoices(tag integer primary key,issuance_id uuid not null);
insert into issued_invoices values
  (1,(public.issue_sdf_post_start_invoice_v1(
    (select candidate_id from prepared_candidates where tag=1),
    extract(year from clock_timestamp() at time zone 'Europe/Brussels')::smallint,
    gen_random_uuid(),repeat('c',64),4096,repeat('d',64),2048
  )->>'issuance_id')::uuid),
  (5,(public.issue_sdf_post_start_invoice_v1(
    (select candidate_id from prepared_candidates where tag=5),
    extract(year from clock_timestamp() at time zone 'Europe/Brussels')::smallint,
    gen_random_uuid(),repeat('e',64),4096,repeat('f',64),2048
  )->>'issuance_id')::uuid);

select is(
  (public.issue_sdf_post_start_invoice_v1(
    (select candidate_id from prepared_candidates where tag=1),
    extract(year from clock_timestamp() at time zone 'Europe/Brussels')::smallint,
    gen_random_uuid(),repeat('c',64),4096,repeat('d',64),2048
  )->>'was_created')::boolean,false,
  'M2 issuance exact canonical replay returns one issuance'
);
select throws_ok(
  format('select public.issue_sdf_post_start_invoice_v1(%L::uuid,%s::smallint,%L::uuid,%L::text,%s::bigint,%L::text,%s::bigint)',
    (select candidate_id from prepared_candidates where tag=1),
    extract(year from clock_timestamp() at time zone 'Europe/Brussels')::smallint,
    (select issuance_idempotency_key from public.sdf_post_start_invoice_issuances where issuance_id=(select issuance_id from issued_invoices where tag=1)),
    repeat('0',64),4096,repeat('d',64),2048),
  'P0001','IDEMPOTENCY_CONFLICT','changed M2 issuance replay is rejected'
);

select ok(
  (select issuance_state='ISSUED' and milestone_identity='M2'
   from public.sdf_post_start_invoice_issuances where issuance_id=(select issuance_id from issued_invoices where tag=1))
  and not exists(
    select 1 from information_schema.columns where table_schema='public'
      and table_name='sdf_post_start_invoice_issuances' and column_name in ('payment_state','received_at','reconciled_at')
  ),
  'M2 INVOICED is not RECEIVED or RECONCILED'
);
select ok(
  (select issuance_state='ISSUED' and milestone_identity='M3'
   from public.sdf_post_start_invoice_issuances where issuance_id=(select issuance_id from issued_invoices where tag=5))
  and not exists(
    select 1 from information_schema.columns where table_schema='public'
      and table_name='sdf_post_start_invoice_issuances' and column_name in ('payment_state','received_at','reconciled_at')
  ),
  'M3 INVOICED is not RECEIVED or RECONCILED'
);
select ok(
  (select bool_and(
    request_kind='slimme_documentenflow'
    and milestone_identity in ('M2','M3')
    and percentage_basis_points in (4000,2000)
    and commercial_snapshot_sha256 ~ '^[0-9a-f]{64}$'
    and lifecycle_evidence_sha256 ~ '^[0-9a-f]{64}$'
    and invoice_master_sha256='52dc454bec5d0e09fc9f4b85a1f1877b65f7d3aea166ed195da598cb7b4536d6'
  ) from public.sdf_post_start_invoice_issuances),
  'M2/M3 issuances preserve commercial, lifecycle, milestone, and invoice-master provenance'
);
select is(
  (select count(*)::integer from public.sdf_post_start_milestone_obligations where request_kind<>'slimme_documentenflow'),
  0,'cross-product fallback creates no obligations'
);
select throws_ok(
  $$update public.sdf_post_start_milestone_obligations set amount_minor=1$$,
  '55000','SDF_INVOICE_FOUNDATION_IMMUTABLE','post-start financial authority rejects UPDATE'
);
select throws_ok(
  $$delete from public.sdf_post_start_invoice_issuances$$,
  '55000','SDF_INVOICE_FOUNDATION_IMMUTABLE','post-start issuance authority rejects DELETE'
);

\else
select fail('RED: M2/M3 lifecycle billing implementation is absent');
\endif

select * from finish();
rollback;
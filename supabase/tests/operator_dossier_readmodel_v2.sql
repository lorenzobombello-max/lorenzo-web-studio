begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'list_operator_applications_v2',
  array['uuid','text','text','integer','text','text','text','timestamp with time zone','uuid','integer'],
  'v2 dossier list RPC exists'
);
select has_function(
  'public', 'get_operator_dossier_facets_v2', array['uuid','text','text','text','text'],
  'v2 dossier facets RPC exists'
);
select ok(
  not has_function_privilege('authenticated', 'public.list_operator_applications_v2(uuid,text,text,integer,text,text,text,timestamp with time zone,uuid,integer)', 'execute')
  and not has_function_privilege('anon', 'public.list_operator_applications_v2(uuid,text,text,integer,text,text,text,timestamp with time zone,uuid,integer)', 'execute')
  and has_function_privilege('service_role', 'public.list_operator_applications_v2(uuid,text,text,integer,text,text,text,timestamp with time zone,uuid,integer)', 'execute'),
  'only service_role can enter the v2 list transport'
);
select ok(
  not has_function_privilege('authenticated', 'public.get_operator_dossier_facets_v2(uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_dossier_facets_v2(uuid,text,text,text,text)', 'execute')
  and has_function_privilege('service_role', 'public.get_operator_dossier_facets_v2(uuid,text,text,text,text)', 'execute'),
  'only service_role can enter the v2 facets transport'
);
select ok(
  has_function_privilege('authenticated', 'public.authorize_operator_application_reader_v2()', 'execute')
  and not has_function_privilege('anon', 'public.authorize_operator_application_reader_v2()', 'execute')
  and not has_function_privilege('service_role', 'public.authorize_operator_application_reader_v2()', 'execute'),
  'only authenticated can enter the authority-only preflight'
);
select ok(
  not has_table_privilege('authenticated', 'lws_internal.operator_application_readmodel_v2', 'select')
  and not has_table_privilege('service_role', 'lws_internal.operator_application_readmodel_v2', 'select'),
  'private v2 readmodel has no direct runtime read grant'
);

select is(
  lws_internal.resolve_operator_operational_status_v2('website','submitted','CANCELLED','DELIVERED',true),
  'CANCELLED',
  'CANCELLED precedes project and acceptance authority'
);
select is(
  lws_internal.resolve_operator_operational_status_v2('website','submitted','ACTIVE','PROJECT_RELEASED',true),
  'PROJECT_RELEASED',
  'canonical project state precedes acceptance and intake status'
);
select is(
  lws_internal.resolve_operator_operational_status_v2('website','submitted','ACTIVE',null,true),
  'QUOTE_ACCEPTED',
  'accepted quotation precedes intake status'
);
select is(
  lws_internal.resolve_operator_operational_status_v2('website','reviewed','ACTIVE',null,false),
  'REVIEWED',
  'reviewed intake projects REVIEWED'
);
select is(
  lws_internal.resolve_operator_operational_status_v2('website','submitted','ACTIVE',null,false),
  'SUBMITTED',
  'submitted intake projects SUBMITTED'
);
select throws_ok(
  $$select lws_internal.resolve_operator_operational_status_v2('slimme_documentenflow',null,null,null,false)$$,
  '22023', 'INVALID_SDF_OPERATIONAL_AUTHORITY',
  'SDF without workflow authority fails closed'
);
select is(
  lws_internal.resolve_operator_operational_status_v2('website','submitted','ACTIVE','UNKNOWN_STATE',false),
  'UNKNOWN_STATE',
  'present project state remains the canonical operational authority'
);

insert into auth.users(id,email) values
  ('b2000000-0000-4000-8000-000000000001','v2-owner@example.test'),
  ('b2000000-0000-4000-8000-000000000002','v2-operator@example.test'),
  ('b2000000-0000-4000-8000-000000000003','v2-unknown@example.test'),
  ('b2000000-0000-4000-8000-000000000004','v2-disabled@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  ('b2010000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','V2 Owner','owner','ACTIVE'),
  ('b2010000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000002','V2 Operator','operator','ACTIVE'),
  ('b2010000-0000-4000-8000-000000000004','b2000000-0000-4000-8000-000000000004','V2 Disabled','admin','DISABLED');

create function pg_temp.v2_list(
  p_zone text default 'ACTIVE', p_operational_status text default null,
  p_year integer default null, p_quarter text default null,
  p_request_kind text default null, p_search text default null,
  p_cursor_date timestamptz default null, p_cursor_id uuid default null,
  p_limit integer default 50
) returns jsonb language sql stable as $$
  select public.list_operator_applications_v2(
    'b2000000-0000-4000-8000-000000000001', p_zone, p_operational_status,
    p_year, p_quarter, p_request_kind, p_search, p_cursor_date, p_cursor_id, p_limit
  );
$$;

create function pg_temp.v2_facets(
  p_zone text default 'ACTIVE', p_operational_status text default null,
  p_request_kind text default null, p_search text default null
) returns jsonb language sql stable as $$
  select public.get_operator_dossier_facets_v2(
    'b2000000-0000-4000-8000-000000000001', p_zone,
    p_operational_status, p_request_kind, p_search
  );
$$;

insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,created_at,
  name,company,email,description,privacy_consent,status
) values
  ('b2100000-0000-4000-8000-000000000001','LWS-AAN-2098-0001','production','slimme_documentenflow','start','2098-02-15T10:00:00Z','Alpha Archive','Zenith Archive BV','alpha@example.test','Phase 2B Q1 SDF fixture.',true,'approved'),
  ('b2110000-0000-4000-8000-000000000002','LWS-AAN-2098-0002','production','slimme_documentenflow','groei','2098-05-15T10:00:00Z','Bravo Archived','Bravo Company','bravo@example.test','Phase 2B Q2 SDF fixture.',true,'approved'),
  ('b2120000-0000-4000-8000-000000000003','LWS-AAN-2098-0003','production','slimme_documentenflow','maatwerk','2098-08-15T10:00:00Z','Charlie Trashed','Hidden Company','charlie@example.test','Phase 2B Q3 trash fixture.',true,'approved'),
  ('b2130000-0000-4000-8000-000000000004','LWS-AAN-2098-0004','production','slimme_documentenflow','start','2098-11-15T10:00:00Z','Delta Active','Acme Organization','delta@example.test','Phase 2B Q4 SDF fixture.',true,'approved'),
  ('b2140000-0000-4000-8000-000000000005','LWS-AAN-2097-0001','production','slimme_documentenflow','start','2097-12-15T10:00:00Z','Earlier Year','Historic Company','earlier@example.test','Phase 2B prior-year fixture.',true,'approved');

insert into public.sdf_qualification_intakes(
  quote_request_id, status, customer_capability_digest,
  customer_capability_encrypted, customer_capability_expires_at, submitted_at
)
select
  request.id,
  'submitted',
  encode(extensions.digest(convert_to(request.id::text, 'UTF8'), 'sha256'), 'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  '2100-01-01T00:00:00Z'::timestamptz,
  request.created_at
from public.quote_requests request
where request.id in (
  'b2100000-0000-4000-8000-000000000001',
  'b2110000-0000-4000-8000-000000000002',
  'b2120000-0000-4000-8000-000000000003',
  'b2130000-0000-4000-8000-000000000004',
  'b2140000-0000-4000-8000-000000000005'
);

insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,created_at,name,company,email,
  website_type,budget,timing,description,privacy_consent,status
) values
  ('b2200000-0000-4000-8000-000000000001','LWS-AAN-2098-0011','production','website','2098-01-01T09:00:00Z','Lorenzo Submitted','LWS Studio','submitted@example.test','business','EUR 3.000','flexible','Phase 2B submitted Website fixture.',true,'approved'),
  ('b2210000-0000-4000-8000-000000000002','LWS-AAN-2098-0012','production','website','2098-04-01T09:00:00Z','Reviewed Customer','Review Company','reviewed@example.test','business','EUR 3.000','flexible','Phase 2B reviewed Website fixture.',true,'approved'),
  ('b2220000-0000-4000-8000-000000000003','LWS-AAN-2098-0013','production','website','2098-07-01T09:00:00Z','Cancelled Customer','Cancel Company','cancelled@example.test','business','EUR 3.000','flexible','Phase 2B cancelled Website fixture.',true,'approved');

insert into public.quote_request_intakes(
  id,quote_request_id,access_token_hash,access_token_expires_at,status,
  started_at,submitted_at,reviewed_at,confirmation
) values
  ('b2300000-0000-4000-8000-000000000001','b2200000-0000-4000-8000-000000000001',repeat('1',64),'2099-01-01T00:00:00Z','submitted','2098-02-01T10:00:00Z','2098-02-15T10:00:00Z',null,true),
  ('b2310000-0000-4000-8000-000000000002','b2210000-0000-4000-8000-000000000002',repeat('2',64),'2099-01-01T00:00:00Z','reviewed','2098-05-01T10:00:00Z','2098-05-15T10:00:00Z','2098-05-16T10:00:00Z',true),
  ('b2320000-0000-4000-8000-000000000003','b2220000-0000-4000-8000-000000000003',repeat('3',64),'2099-01-01T00:00:00Z','submitted','2098-08-01T10:00:00Z','2098-08-15T10:00:00Z',null,true);

update lws_internal.operator_dossier_states
set state='ARCHIVED',revision=1,updated_at=clock_timestamp()+interval '1 second'
where quote_request_id='b2110000-0000-4000-8000-000000000002';
update lws_internal.operator_dossier_states
set state='TRASHED',revision=1,state_before_trash='ACTIVE',
  deletion_eligible_at=null,updated_at=clock_timestamp()+interval '1 second'
where quote_request_id='b2120000-0000-4000-8000-000000000003';

select throws_ok(
  $$select public.authorize_operator_application_reader_v2()$$,
  '42501','HUMAN_JWT_REQUIRED','missing human JWT is rejected'
);
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000003',true);
select throws_ok(
  $$select public.authorize_operator_application_reader_v2()$$,
  '42501','UNKNOWN_OPERATOR','unknown human is rejected'
);
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.authorize_operator_application_reader_v2()$$,
  '42501','APPLICATION_SCOPE_DENIED','project-scoped operator cannot inspect global facets'
);
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
select throws_ok(
  $$select public.authorize_operator_application_reader_v2()$$,
  '42501','OPERATOR_DISABLED','inactive operator fails the authority-only preflight'
);
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select lives_ok(
  $$select public.authorize_operator_application_reader_v2()$$,
  'active owner passes the authority-only preflight'
);
select throws_ok(
  $$select public.list_operator_applications_v2('b2000000-0000-4000-8000-000000000003')$$,
  '42501','UNKNOWN_OPERATOR','DB transport revalidates the supplied human actor'
);
select throws_ok(
  $$select public.list_operator_applications_v2('b2000000-0000-4000-8000-000000000004')$$,
  '42501','OPERATOR_DISABLED','DB transport rejects an inactive supplied human actor'
);

select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'b2320000-0000-4000-8000-000000000003','CANCELLED',0,
    'b2400000-0000-4000-8000-000000000001','Phase 2B cancellation fixture.'
  )->>'effective_access',
  'CANCELLED',
  'cancelled fixture uses existing lifecycle command authority'
);

select is(jsonb_array_length(pg_temp.v2_list()->'items'),6,'default ACTIVE scope returns only active dossiers');
select is(pg_temp.v2_list()->'items'->0->>'zone','ACTIVE','list projects canonical zone');
select ok(
  (pg_temp.v2_list()->'items'->0) ?& array[
    'quote_request_id','application_reference','support_reference','name','organization',
    'request_kind','zone','operational_status','dossier_date'
  ],
  'list item exposes the exact minimum v2 response contract'
);
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ARCHIVED')->'items'),1,'ARCHIVED scope is isolated');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'TRASHED')->'items'),1,'TRASHED scope is explicit');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED')->'items'),7,'ACTIVE_ARCHIVED excludes trash');

select is(jsonb_array_length(pg_temp.v2_list(p_search=>'b2110000-0000-4000-8000-000000000002')->'items'),1,'exact UUID finds archived dossier outside default ACTIVE navigation');
select is(jsonb_array_length(pg_temp.v2_list(p_search=>'lws-aan-2098-0002')->'items'),1,'application reference exact search is case-insensitive');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_search=>'LWS-AAN-2098-')->'items'),6,'application reference prefix search is server-side');
select is(jsonb_array_length(pg_temp.v2_list(p_search=>'#B2100000')->'items'),1,'supportreference with hash resolves exactly');
select is(jsonb_array_length(pg_temp.v2_list(p_search=>'b2100000')->'items'),1,'supportreference without hash resolves exactly');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_search=>'  LoReNzO  ')->'items'),1,'normalized name prefix search trims and ignores case');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_search=>'ACME')->'items'),1,'normalized company prefix search is server-side');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_search=>'Unknown customer')->'items'),0,'unknown search returns zero items');
select is(jsonb_array_length(pg_temp.v2_list(p_search=>'b2120000-0000-4000-8000-000000000003')->'items'),0,'exact identifier does not leak trash in ordinary scope');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'TRASHED',p_search=>'b2120000-0000-4000-8000-000000000003')->'items'),1,'exact identifier finds trash only in explicit TRASHED scope');
select is(pg_temp.v2_list(p_search=>'b2110000-0000-4000-8000-000000000002')->'next_position','null'::jsonb,'exact identifier result has no raw continuation position');
select is(jsonb_array_length(pg_temp.v2_list(p_search=>'b2110000-0000-4000-8000-000000000002',p_year=>2097,p_quarter=>'Q4')->'items'),1,'exact identifier mode ignores year and quarter without leaking trash');

select is(jsonb_array_length(pg_temp.v2_list(p_operational_status=>'SUBMITTED')->'items'),4,'SUBMITTED status filter uses server projection');
select is(jsonb_array_length(pg_temp.v2_list(p_operational_status=>'REVIEWED')->'items'),1,'REVIEWED status filter uses intake authority');
select is(jsonb_array_length(pg_temp.v2_list(p_operational_status=>'CANCELLED')->'items'),1,'CANCELLED status filter overrides submitted intake state');
select is(
  pg_temp.v2_list(p_search=>'b2220000-0000-4000-8000-000000000003')->'items'->0->>'operational_status',
  'CANCELLED',
  'list projects authoritative CANCELLED precedence'
);
select is(jsonb_array_length(pg_temp.v2_list(p_request_kind=>'website')->'items'),3,'request kind filters Website dossiers');
select is(jsonb_array_length(pg_temp.v2_list(p_request_kind=>'slimme_documentenflow')->'items'),3,'request kind filters active SDF dossiers');
select is(jsonb_array_length(pg_temp.v2_list(p_year=>2097)->'items'),1,'year filter uses canonical dossier date');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_year=>2098,p_quarter=>'Q1')->'items'),2,'Q1 uses half-open UTC boundary');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_year=>2098,p_quarter=>'Q2')->'items'),2,'Q2 uses half-open UTC boundary');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_year=>2098,p_quarter=>'Q3')->'items'),1,'Q3 excludes trashed fixture from ordinary scope');
select is(jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_year=>2098,p_quarter=>'Q4')->'items'),1,'Q4 uses next-year exclusive boundary');
select is(jsonb_array_length(pg_temp.v2_list(p_year=>2098,p_quarter=>'Q1',p_request_kind=>'website',p_operational_status=>'SUBMITTED')->'items'),1,'combined filters compose server-side');

select throws_ok($$select pg_temp.v2_list(p_zone=>'UNKNOWN')$$,'22023','INVALID_OPERATOR_ZONE','unknown zone fails closed');
select throws_ok($$select pg_temp.v2_list(p_quarter=>'Q1')$$,'22023','INVALID_OPERATOR_QUARTER','quarter without year fails closed');
select throws_ok($$select pg_temp.v2_list(p_operational_status=>'UNKNOWN')$$,'22023','INVALID_OPERATOR_OPERATIONAL_STATUS_FILTER','unknown status fails closed');
select throws_ok($$select pg_temp.v2_list(p_request_kind=>'unknown')$$,'22023','INVALID_OPERATOR_REQUEST_KIND_FILTER','unknown request kind fails closed');
select throws_ok($$select pg_temp.v2_list(p_limit=>0)$$,'22023','INVALID_OPERATOR_PAGE_LIMIT','zero limit is rejected');
select throws_ok($$select pg_temp.v2_list(p_limit=>101)$$,'22023','INVALID_OPERATOR_PAGE_LIMIT','limit above 100 is rejected');
select throws_ok($$select pg_temp.v2_list(p_search=>repeat('x',141))$$,'22023','INVALID_OPERATOR_SEARCH','search above 140 characters is rejected');

insert into public.quote_requests(
  id,record_classification,request_kind,sdf_package,created_at,name,email,description,privacy_consent,status
) values
  ('b2500000-0000-4000-8000-000000000001','production','slimme_documentenflow','start','2098-12-01T12:00:00Z','Tie Fixture One','tie-one@example.test','Phase 2B tie fixture one.',true,'approved'),
  ('b2510000-0000-4000-8000-000000000002','production','slimme_documentenflow','start','2098-12-01T12:00:00Z','Tie Fixture Two','tie-two@example.test','Phase 2B tie fixture two.',true,'approved');

insert into public.sdf_qualification_intakes(
  quote_request_id, status, customer_capability_digest,
  customer_capability_encrypted, customer_capability_expires_at, submitted_at
)
select
  request.id,
  'submitted',
  encode(extensions.digest(convert_to(request.id::text, 'UTF8'), 'sha256'), 'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  '2100-01-01T00:00:00Z'::timestamptz,
  request.created_at
from public.quote_requests request
where request.id in (
  'b2500000-0000-4000-8000-000000000001',
  'b2510000-0000-4000-8000-000000000002'
);

select is(
  (select string_agg(value->>'quote_request_id',',' order by ordinal)
  from jsonb_array_elements(pg_temp.v2_list(p_search=>'Tie Fixture',p_limit=>100)->'items')
        with ordinality as item(value,ordinal)),
  'b2510000-0000-4000-8000-000000000002,b2500000-0000-4000-8000-000000000001',
  'equal dossier dates use descending root UUID tie-break'
);

create temporary table v2_first_page as
select pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_limit=>1) as response;
select is(jsonb_array_length((select response->'items' from v2_first_page)),1,'limit one returns one item');
select ok((select response->'next_position' is not null from v2_first_page),'first bounded page returns a raw continuation position');
select ok((select response ?& array['items','has_more','next_position'] and not response ? 'next_cursor' from v2_first_page),'DB response exposes only raw pagination metadata');
select throws_ok($$select pg_temp.v2_list(p_cursor_date=>'2098-01-01T00:00:00Z')$$,'22023','INVALID_OPERATOR_CURSOR_POSITION','partial raw position fails closed');

with recursive pages(page_number,response) as (
  select 1, pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_limit=>1)
  union all
  select page_number + 1,
         pg_temp.v2_list(
           p_zone=>'ACTIVE_ARCHIVED',
           p_cursor_date=>(response->'next_position'->>'dossier_date')::timestamptz,
           p_cursor_id=>(response->'next_position'->>'quote_request_id')::uuid,
           p_limit=>1
         )
  from pages
  where (response->>'has_more')::boolean and page_number < 20
), identities as (
  select item.value->>'quote_request_id' as quote_request_id
  from pages
  cross join lateral jsonb_array_elements(response->'items') as item(value)
)
select is(
  (select count(*)::integer from identities),
  jsonb_array_length(pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_limit=>100)->'items'),
  'keyset walk has no missing rows'
);
with recursive pages(page_number,response) as (
  select 1, pg_temp.v2_list(p_zone=>'ACTIVE_ARCHIVED',p_limit=>1)
  union all
  select page_number + 1,
         pg_temp.v2_list(
           p_zone=>'ACTIVE_ARCHIVED',
           p_cursor_date=>(response->'next_position'->>'dossier_date')::timestamptz,
           p_cursor_id=>(response->'next_position'->>'quote_request_id')::uuid,
           p_limit=>1
         )
  from pages
  where (response->>'has_more')::boolean and page_number < 20
), identities as (
  select item.value->>'quote_request_id' as quote_request_id
  from pages cross join lateral jsonb_array_elements(response->'items') as item(value)
)
select is((select count(*)::integer from identities),(select count(distinct quote_request_id)::integer from identities),'keyset walk has no duplicate rows');

select is(pg_temp.v2_facets(p_zone=>'ACTIVE_ARCHIVED')->'years'->0->>'year','2098','facets return newest available year first');
select is(pg_temp.v2_facets(p_zone=>'ACTIVE_ARCHIVED')->'years'->1->>'year','2097','facets derive older available year dynamically');
select is((pg_temp.v2_facets(p_zone=>'ACTIVE_ARCHIVED')->'years'->0->>'count')::integer,8,'facet year total reflects active and archived data');
select is((pg_temp.v2_facets(p_zone=>'ACTIVE_ARCHIVED')->'years'->0->'quarters'->0->>'count')::integer,2,'facet Q1 count is correct');
select is((pg_temp.v2_facets(p_zone=>'ACTIVE_ARCHIVED')->'years'->0->'quarters'->1->>'count')::integer,2,'facet Q2 count is correct');
select is((pg_temp.v2_facets(p_zone=>'ACTIVE_ARCHIVED')->'years'->0->'quarters'->2->>'count')::integer,1,'facet Q3 count is correct');
select is((pg_temp.v2_facets(p_zone=>'ACTIVE_ARCHIVED')->'years'->0->'quarters'->3->>'count')::integer,3,'facet Q4 count includes equal-date fixtures');
select is((pg_temp.v2_facets(p_zone=>'ACTIVE_ARCHIVED',p_search=>'Tie Fixture')->'years'->0->>'count')::integer,2,'search affects facet counts');
select is(jsonb_array_length(pg_temp.v2_facets(p_search=>'Charlie')->'years'),0,'ordinary facets do not leak trash');
select is((pg_temp.v2_facets(p_zone=>'TRASHED')->'years'->0->>'count')::integer,1,'trash facets require explicit scope');

select has_index('lws_internal','operator_dossier_states','operator_dossier_states_zone_root_idx','zone/root index exists');
select has_index('public','quote_request_intakes','quote_request_intakes_dossier_date_root_idx','Website date/root index exists');
select has_index('public','quote_requests','quote_requests_sdf_dossier_date_root_idx','SDF date/root index exists');
select has_index('public','quote_request_intakes','quote_request_intakes_access_dossier_date_root_idx','lifecycle/date/root index exists');
select has_index('public','quote_requests','quote_requests_operator_name_prefix_idx','normalized name prefix index exists');
select has_index('public','quote_requests','quote_requests_operator_company_prefix_idx','normalized company prefix index exists');
select ok(
  position('OFFSET' in upper(pg_get_functiondef(
    'lws_internal.list_operator_applications_v2_core(uuid,text,text,integer,text,text,text,timestamp with time zone,uuid,integer)'::regprocedure
  ))) = 0,
  'v2 list implementation contains no OFFSET pagination'
);

insert into public.quote_requests(
  id,record_classification,request_kind,sdf_package,created_at,name,company,email,description,privacy_consent,status
)
select
  gen_random_uuid(),'production','slimme_documentenflow','start',
  '2096-01-01T00:00:00Z'::timestamptz + (series || ' minutes')::interval,
  case when series % 1000 = 0 then 'Performance Target ' || series else 'Synthetic Dossier ' || series end,
  'Synthetic Company',
  'synthetic-' || series || '@example.test',
  'Local synthetic Phase 2B performance fixture ' || series || '.',
  true,'approved'
from generate_series(1,10000) as series;
insert into public.sdf_qualification_intakes(
  quote_request_id, status, customer_capability_digest,
  customer_capability_encrypted, customer_capability_expires_at, submitted_at
)
select
  request.id,
  'submitted',
  encode(extensions.digest(convert_to(request.id::text, 'UTF8'), 'sha256'), 'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  '2100-01-01T00:00:00Z'::timestamptz,
  request.created_at
from public.quote_requests request
where request.created_at >= '2096-01-01T00:00:00Z'::timestamptz
  and request.created_at < '2097-01-01T00:00:00Z'::timestamptz
  and request.request_kind='slimme_documentenflow';
analyze public.quote_requests;
analyze public.sdf_qualification_intakes;
analyze lws_internal.operator_dossier_states;

select is(jsonb_array_length(pg_temp.v2_list(p_year=>2096)->'items'),50,'10k dataset keeps default page bounded to 50');
select is(jsonb_array_length(pg_temp.v2_list(p_year=>2096,p_limit=>100)->'items'),100,'10k dataset honors maximum page bound 100');
select ok(pg_temp.v2_list(p_year=>2096,p_limit=>100)->'next_position' is not null,'10k dataset returns a raw continuation position');
select is(jsonb_array_length(pg_temp.v2_list(p_year=>2096,p_search=>'PERFORMANCE TARGET',p_limit=>100)->'items'),10,'10k name prefix search executes server-side and returns only matches');
select is(jsonb_array_length(pg_temp.v2_list(p_year=>2096,p_request_kind=>'website')->'items'),0,'10k request-kind filter executes server-side');

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid='lws_internal.operator_dossier_states'::regclass),
  'Phase-1 dossier state RLS and FORCE RLS remain enabled'
);
select is((select enum_range(null::public.quote_request_intake_status)::text),'{invited,in_progress,submitted,reviewed}','CANCELLED remains outside intake progress enum');
select has_function('public','list_operator_applications_v1',array['integer','integer'],'v1 list RPC remains available');
select has_function('public','resolve_quote_request_intake_effective_access_v1',array['text','timestamptz','timestamptz'],'existing CANCELLED resolver remains available');
select ok(exists(select 1 from pg_constraint where conrelid='public.quote_requests'::regclass and conname='quote_requests_application_reference_unique'),'application numbering uniqueness remains constrained');
select ok(exists(select 1 from pg_constraint where conrelid='public.quote_request_quotation_issuances'::regclass and conname='quote_request_quotation_issuances_number_version_unique'),'quotation numbering uniqueness remains constrained');
select ok(exists(select 1 from pg_constraint where conrelid='public.commercial_projects'::regclass and conname='commercial_project_money_coherent'),'40/40/rest money coherence remains constrained');

select * from finish();
rollback;
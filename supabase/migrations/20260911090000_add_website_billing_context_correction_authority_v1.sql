begin;

alter table public.quote_requests
  drop constraint quote_requests_business_fields_check;

alter table public.quote_requests
  add constraint quote_requests_business_fields_check
  check (
    customer_type is null
    or (
      customer_type = 'individual'
      and company is null
      and enterprise_number is null
      and vat_number is null
    )
    or (
      customer_type = 'business'
      and company is not null
      and enterprise_number is not null
      and billing_address is not null
      and billing_postal_code is not null
      and billing_city is not null
      and billing_country is not null
    )
  );

create function lws_internal.is_iso_3166_1_alpha2_v1(p_value text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select upper(coalesce(p_value,'')) = any(array[
    'AD','AE','AF','AG','AI','AL','AM','AO','AQ','AR','AS','AT','AU','AW','AX','AZ',
    'BA','BB','BD','BE','BF','BG','BH','BI','BJ','BL','BM','BN','BO','BQ','BR','BS','BT','BV','BW','BY','BZ',
    'CA','CC','CD','CF','CG','CH','CI','CK','CL','CM','CN','CO','CR','CU','CV','CW','CX','CY','CZ',
    'DE','DJ','DK','DM','DO','DZ','EC','EE','EG','EH','ER','ES','ET','FI','FJ','FK','FM','FO','FR',
    'GA','GB','GD','GE','GF','GG','GH','GI','GL','GM','GN','GP','GQ','GR','GS','GT','GU','GW','GY',
    'HK','HM','HN','HR','HT','HU','ID','IE','IL','IM','IN','IO','IQ','IR','IS','IT','JE','JM','JO','JP',
    'KE','KG','KH','KI','KM','KN','KP','KR','KW','KY','KZ','LA','LB','LC','LI','LK','LR','LS','LT','LU','LV','LY',
    'MA','MC','MD','ME','MF','MG','MH','MK','ML','MM','MN','MO','MP','MQ','MR','MS','MT','MU','MV','MW','MX','MY','MZ',
    'NA','NC','NE','NF','NG','NI','NL','NO','NP','NR','NU','NZ','OM','PA','PE','PF','PG','PH','PK','PL','PM','PN','PR','PS','PT','PW','PY',
    'QA','RE','RO','RS','RU','RW','SA','SB','SC','SD','SE','SG','SH','SI','SJ','SK','SL','SM','SN','SO','SR','SS','ST','SV','SX','SY','SZ',
    'TC','TD','TF','TG','TH','TJ','TK','TL','TM','TN','TO','TR','TT','TV','TW','TZ',
    'UA','UG','UM','US','UY','UZ','VA','VC','VE','VG','VI','VN','VU','WF','WS','YE','YT','ZA','ZM','ZW'
  ]::text[])
$$;

create table public.website_quote_request_billing_context_events (
  event_id bigint generated always as identity primary key,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  intake_id uuid not null references public.quote_request_intakes(id) on delete restrict,
  event_type text not null check (
    event_type = 'WEBSITE_QUOTE_REQUEST_BILLING_CONTEXT_CORRECTED'
  ),
  actor_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  actor text not null check (actor ~ '^OPERATOR:[0-9a-f-]{36}$'),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  previous_context_sha256 char(64) not null check (previous_context_sha256 ~ '^[0-9a-f]{64}$'),
  corrected_context_sha256 char(64) not null check (corrected_context_sha256 ~ '^[0-9a-f]{64}$'),
  changed_fields text[] not null check (cardinality(changed_fields) > 0),
  result_payload jsonb not null,
  occurred_at timestamptz not null
);

create function public.guard_website_billing_context_event_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode='55000',message='WEBSITE_BILLING_CONTEXT_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_website_quote_request_billing_context_events_immutable
before update or delete on public.website_quote_request_billing_context_events
for each row execute function public.guard_website_billing_context_event_v1();

create function public.correct_website_quote_request_billing_context_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_billing_context jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, auth, extensions
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_existing public.website_quote_request_billing_context_events%rowtype;
  v_address text;
  v_postal_code text;
  v_city text;
  v_country text;
  v_email text;
  v_actor text;
  v_fingerprint text;
  v_previous_sha text;
  v_corrected_sha text;
  v_changed_fields text[]:=array[]::text[];
  v_result jsonb;
  v_now timestamptz:=clock_timestamp();
begin
  if p_actor_auth_user_id is null or p_quote_request_id is null
     or p_intake_id is null or p_idempotency_key is null
     or not public.jsonb_has_exact_keys(p_billing_context,array[
       'billing_address','billing_postal_code','billing_city',
       'billing_country','billing_email'
     ]) then
    raise exception using errcode='22023',message='WEBSITE_BILLING_CONTEXT_INPUT_INVALID';
  end if;
  if auth.uid() is null then
    raise exception using errcode='42501',message='HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid()<>p_actor_auth_user_id then
    raise exception using errcode='42501',message='OPERATOR_IDENTITY_MISMATCH';
  end if;
  perform lws_internal.assert_operator_aal2_v1();
  select * into v_operator
  from public.commercial_operators
  where auth_user_id=p_actor_auth_user_id;
  if not found or v_operator.status<>'ACTIVE' or v_operator.role<>'owner' then
    raise exception using errcode='42501',message='WEBSITE_BILLING_CONTEXT_FORBIDDEN';
  end if;

  v_address:=nullif(btrim(p_billing_context->>'billing_address'),'');
  v_postal_code:=nullif(btrim(p_billing_context->>'billing_postal_code'),'');
  v_city:=nullif(btrim(p_billing_context->>'billing_city'),'');
  v_country:=upper(nullif(btrim(p_billing_context->>'billing_country'),''));
  v_email:=lower(nullif(btrim(p_billing_context->>'billing_email'),''));
  if not lws_internal.is_iso_3166_1_alpha2_v1(v_country)
     or (v_address is not null and length(v_address) not between 2 and 200)
     or (v_postal_code is not null and length(v_postal_code) not between 2 and 20)
     or (v_city is not null and length(v_city) not between 2 and 120)
     or (v_email is not null and (
       length(v_email) not between 5 and 254
       or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     )) then
    raise exception using errcode='22023',message='WEBSITE_BILLING_CONTEXT_INPUT_INVALID';
  end if;

  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'authorityVersion',1,'actorAuthUserId',p_actor_auth_user_id,
    'quoteRequestId',p_quote_request_id,'intakeId',p_intake_id,
    'billingAddress',v_address,'billingPostalCode',v_postal_code,
    'billingCity',v_city,'billingCountry',v_country,'billingEmail',v_email
  )::text,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  select * into v_existing
  from public.website_quote_request_billing_context_events
  where idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint)<>v_fingerprint then
      raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed',true);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_quote_request_id::text,0));
  select * into v_request
  from public.quote_requests
  where id=p_quote_request_id
  for update;
  if not found then
    raise exception using errcode='23503',message='WEBSITE_BILLING_CONTEXT_REQUEST_NOT_FOUND';
  end if;
  if v_request.request_kind<>'website'
     or v_request.record_classification not in ('production','internal_e2e') then
    raise exception using errcode='23514',message='WEBSITE_BILLING_CONTEXT_DOMAIN_MISMATCH';
  end if;
  select * into v_intake
  from public.quote_request_intakes
  where id=p_intake_id and quote_request_id=p_quote_request_id
  for update;
  if not found or v_intake.status not in ('submitted','reviewed') then
    raise exception using errcode='23514',message='WEBSITE_BILLING_CONTEXT_INTAKE_NOT_READY';
  end if;
  if exists(
    select 1 from public.quote_request_quotation_business_drafts
    where quote_request_id=p_quote_request_id
  ) then
    raise exception using errcode='55000',message='WEBSITE_BILLING_CONTEXT_IMMUTABLE';
  end if;

  v_previous_sha:=encode(extensions.digest(convert_to(jsonb_build_object(
    'billing_address',v_request.billing_address,
    'billing_postal_code',v_request.billing_postal_code,
    'billing_city',v_request.billing_city,
    'billing_country',v_request.billing_country,
    'billing_email',v_request.billing_email,
    'enterprise_number',v_request.enterprise_number,
    'vat_number',v_request.vat_number
  )::text,'UTF8'),'sha256'),'hex');
  if v_request.billing_address is distinct from v_address then v_changed_fields:=array_append(v_changed_fields,'billing_address'); end if;
  if v_request.billing_postal_code is distinct from v_postal_code then v_changed_fields:=array_append(v_changed_fields,'billing_postal_code'); end if;
  if v_request.billing_city is distinct from v_city then v_changed_fields:=array_append(v_changed_fields,'billing_city'); end if;
  if upper(v_request.billing_country) is distinct from v_country then v_changed_fields:=array_append(v_changed_fields,'billing_country'); end if;
  if lower(v_request.billing_email) is distinct from v_email then v_changed_fields:=array_append(v_changed_fields,'billing_email'); end if;
  if cardinality(v_changed_fields)=0 then
    raise exception using errcode='23514',message='WEBSITE_BILLING_CONTEXT_UNCHANGED';
  end if;

  update public.quote_requests
  set billing_address=v_address,
      billing_postal_code=v_postal_code,
      billing_city=v_city,
      billing_country=v_country,
      billing_email=v_email
  where id=p_quote_request_id
  returning * into v_request;

  v_corrected_sha:=encode(extensions.digest(convert_to(jsonb_build_object(
    'billing_address',v_request.billing_address,
    'billing_postal_code',v_request.billing_postal_code,
    'billing_city',v_request.billing_city,
    'billing_country',v_request.billing_country,
    'billing_email',v_request.billing_email,
    'enterprise_number',v_request.enterprise_number,
    'vat_number',v_request.vat_number
  )::text,'UTF8'),'sha256'),'hex');
  v_result:=jsonb_build_object(
    'quote_request_id',p_quote_request_id,'intake_id',p_intake_id,
    'billing_address',v_request.billing_address,
    'billing_postal_code',v_request.billing_postal_code,
    'billing_city',v_request.billing_city,
    'billing_country',v_request.billing_country,
    'billing_email',v_request.billing_email,
    'changed_fields',to_jsonb(v_changed_fields),
    'corrected_at',v_now,'replayed',false
  );
  v_actor:='OPERATOR:'||v_operator.operator_id::text;
  insert into public.website_quote_request_billing_context_events(
    quote_request_id,intake_id,event_type,actor_operator_id,actor,
    idempotency_key,request_fingerprint,previous_context_sha256,
    corrected_context_sha256,changed_fields,result_payload,occurred_at
  ) values(
    p_quote_request_id,p_intake_id,'WEBSITE_QUOTE_REQUEST_BILLING_CONTEXT_CORRECTED',
    v_operator.operator_id,v_actor,p_idempotency_key,v_fingerprint,
    v_previous_sha,v_corrected_sha,v_changed_fields,v_result,v_now
  );
  return v_result;
end;
$$;

alter table public.website_quote_request_billing_context_events enable row level security;
alter table public.website_quote_request_billing_context_events force row level security;
revoke all privileges on table public.website_quote_request_billing_context_events from public,anon,authenticated,service_role;
revoke all on function public.guard_website_billing_context_event_v1() from public,anon,authenticated,service_role;
revoke all on function public.correct_website_quote_request_billing_context_v1(uuid,uuid,uuid,jsonb,uuid) from public,anon,authenticated,service_role;
revoke all on function lws_internal.is_iso_3166_1_alpha2_v1(text) from public,anon,authenticated,service_role;
grant execute on function public.correct_website_quote_request_billing_context_v1(uuid,uuid,uuid,jsonb,uuid) to authenticated;

comment on table public.website_quote_request_billing_context_events is
  'Immutable audit and idempotency evidence for pre-quotation Website billing context corrections.';
comment on function public.correct_website_quote_request_billing_context_v1(uuid,uuid,uuid,jsonb,uuid) is
  'Owner-only AAL2 authority for correcting canonical Website billing contact fields before a quotation draft exists.';

commit;
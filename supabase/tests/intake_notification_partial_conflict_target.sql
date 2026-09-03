begin;

create extension if not exists pgtap with schema extensions;
select plan(2);

select has_function(
  'public',
  'update_quote_request_intake_phase2b_predecessor',
  array['text', 'text', 'jsonb', 'text', 'timestamp with time zone'],
  'The guarded intake predecessor remains available'
);

select matches(
  pg_get_functiondef('public.update_quote_request_intake_phase2b_predecessor(text,text,jsonb,text,timestamp with time zone)'::regprocedure),
  'on conflict \(quote_request_id, kind\) where reminder_access_cycle is null do nothing',
  'Intake submission targets the non-reminder partial unique index'
);

select * from finish();
rollback;
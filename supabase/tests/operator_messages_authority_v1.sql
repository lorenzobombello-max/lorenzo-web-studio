begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'operator_messages', 'canonical operator messages persist server-side');
select columns_are(
  'public', 'operator_messages',
  array['id','sender_operator_id','message_scope','body','created_at'],
  'canonical message stores no recipient-specific read state'
);
select has_table('public', 'operator_message_recipients', 'normalized recipient relations exist');
select columns_are(
  'public', 'operator_message_recipients',
  array['message_id','recipient_operator_id','read_at'],
  'each recipient relation owns its read state'
);
select col_is_pk('public', 'operator_messages', 'id', 'message ID is stable and unique');
select col_has_default('public', 'operator_messages', 'id', 'message ID is server generated');
select col_has_default('public', 'operator_messages', 'created_at', 'creation time is server generated');
select has_function('public', 'send_operator_message_v1', array['text','uuid','text'], 'scope-aware send authority exists');
select has_function('public', 'list_operator_messages_v1', array['text','integer'], 'mailbox list authority exists');
select has_function('public', 'mark_operator_message_read_v1', array['uuid'], 'recipient read authority exists');
select has_function('public', 'is_current_active_operator_v1', array['uuid'], 'bounded Realtime recipient predicate exists');
select ok(
  to_regprocedure('public.send_operator_message_v1(text,uuid[],text)') is null,
  'send authority accepts no client-forged recipient array'
);
select ok(
  not has_table_privilege('anon', 'public.operator_messages', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.operator_messages', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.operator_messages', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.operator_message_recipients', 'select,insert,update,delete')
  and has_table_privilege('authenticated', 'public.operator_message_recipients', 'select')
  and not has_table_privilege('authenticated', 'public.operator_message_recipients', 'insert,update,delete')
  and not has_table_privilege('service_role', 'public.operator_message_recipients', 'select,insert,update,delete'),
  'Realtime grants authenticated read-only delivery visibility while message content and every mutation remain closed'
);
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'operator_message_recipients'
      and policyname = 'operator_message_recipients_realtime_select_v1'
      and roles = array['authenticated']::name[]
      and cmd = 'SELECT'
  ),
  'recipient delivery Realtime visibility has one authenticated SELECT policy'
);
select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'operator_message_recipients'
  )
  and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'operator_messages'
  ),
  'Realtime publishes delivery invalidations without publishing message content'
);
select ok(
  has_function_privilege('authenticated', 'public.send_operator_message_v1(text,uuid,text)', 'execute')
  and has_function_privilege('authenticated', 'public.list_operator_messages_v1(text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.mark_operator_message_read_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.send_operator_message_v1(text,uuid,text)', 'execute'),
  'only authenticated humans can enter message RPCs'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.operator_messages'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.operator_message_recipients'::regclass),
  'both authority tables have forced RLS'
);
select has_index('public', 'operator_messages', 'operator_messages_sender_created_idx', 'sender chronology is indexed');
select has_index('public', 'operator_message_recipients', 'operator_message_recipients_inbox_idx', 'recipient inbox is indexed');
select has_index('public', 'operator_message_recipients', 'operator_message_recipients_unread_idx', 'unread retrieval is indexed');

insert into auth.users(id, email) values
  ('f2000000-0000-4000-8000-000000000001', 'message-owner@example.test'),
  ('f2000000-0000-4000-8000-000000000002', 'message-recipient-a@example.test'),
  ('f2000000-0000-4000-8000-000000000003', 'message-recipient-b@example.test'),
  ('f2000000-0000-4000-8000-000000000004', 'message-disabled@example.test'),
  ('f2000000-0000-4000-8000-000000000005', 'message-nonowner@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f2010000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001', 'Message Owner', 'owner', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000002', 'Message Recipient A', 'operator', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000003', 'f2000000-0000-4000-8000-000000000003', 'Message Recipient B', 'reviewer', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000004', 'f2000000-0000-4000-8000-000000000004', 'Message Disabled', 'operator', 'DISABLED'),
  ('f2010000-0000-4000-8000-000000000005', 'f2000000-0000-4000-8000-000000000005', 'Message Nonowner', 'operations_manager', 'ACTIVE');

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.send_operator_message_v1('PERSONAL', 'f2010000-0000-4000-8000-000000000002', 'Offline-safe bericht')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated send is denied'
);
select throws_ok(
  $$select public.list_operator_messages_v1('received', 50)$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated list is denied'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.send_operator_message_v1('ALL', null, 'Niet toegestane broadcast')$$,
  '42501', 'OWNER_MESSAGE_SENDER_REQUIRED', 'non-owner cannot broadcast'
);
select throws_ok(
  $$select public.send_operator_message_v1('PERSONAL', 'f2010000-0000-4000-8000-000000000001', 'Niet toegestaan')$$,
  '42501', 'OWNER_MESSAGE_SENDER_REQUIRED', 'current V1 policy does not grant broad personal-send authority'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.send_operator_message_v1('ALL', 'f2010000-0000-4000-8000-000000000002', 'Forged broadcast set')$$,
  '22023', 'BROADCAST_RECIPIENT_FORBIDDEN', 'client cannot forge recipients for ALL scope'
);
select throws_ok(
  $$select public.send_operator_message_v1('PERSONAL', null, 'Ontbrekende ontvanger')$$,
  '22023', 'PERSONAL_RECIPIENT_REQUIRED', 'personal scope requires exactly one recipient'
);
select throws_ok(
  $$select public.send_operator_message_v1('PERSONAL', 'f2010000-0000-4000-8000-000000000099', 'Onbekende ontvanger')$$,
  '23503', 'MESSAGE_RECIPIENT_NOT_FOUND', 'nonexistent personal recipient is denied'
);
select throws_ok(
  $$select public.send_operator_message_v1('PERSONAL', 'f2010000-0000-4000-8000-000000000004', 'Inactieve ontvanger')$$,
  '42501', 'MESSAGE_RECIPIENT_NOT_ACTIVE', 'inactive personal recipient is denied'
);
select throws_ok(
  $$select public.send_operator_message_v1('PERSONAL', 'f2010000-0000-4000-8000-000000000001', 'Bericht aan mezelf')$$,
  '22023', 'MESSAGE_RECIPIENT_MUST_DIFFER', 'personal sender and recipient must differ'
);
select throws_ok(
  $$select public.send_operator_message_v1('PERSONAL', 'f2010000-0000-4000-8000-000000000002', '   ')$$,
  '22023', 'INVALID_MESSAGE_BODY', 'whitespace-only body is denied'
);
select throws_ok(
  $$select public.send_operator_message_v1('PERSONAL', 'f2010000-0000-4000-8000-000000000002', repeat('x', 4001))$$,
  '22023', 'INVALID_MESSAGE_BODY', 'body beyond 4000 characters is denied'
);

create temporary table message_fixture(kind text primary key, id uuid, sent jsonb);
insert into message_fixture(kind, id, sent)
select 'personal', (result->>'id')::uuid, result
from (select public.send_operator_message_v1(
  'PERSONAL', 'f2010000-0000-4000-8000-000000000002',
  '  Blijvend persoonlijk bericht voor latere login.  '
) result) sent;
insert into message_fixture(kind, id, sent)
select 'all', (result->>'id')::uuid, result
from (select public.send_operator_message_v1(
  'ALL', null, 'Blijvende broadcast voor iedere actieve ontvanger.'
) result) sent;

select is((select sent->>'sender_operator_id' from message_fixture where kind = 'personal'), 'f2010000-0000-4000-8000-000000000001', 'sender identity is derived from authenticated owner');
select is((select sent->>'message_scope' from message_fixture where kind = 'personal'), 'PERSONAL', 'personal scope is canonical');
select is((select sent->>'recipient_count' from message_fixture where kind = 'personal'), '1', 'personal message creates one recipient relation');
select is((select count(*)::integer from public.operator_message_recipients where message_id = (select id from message_fixture where kind = 'personal')), 1, 'personal recipient cardinality is exactly one');
select is(
  (select (sent->>'recipient_count')::integer from message_fixture where kind = 'all'),
  (select count(*)::integer from public.commercial_operators where status = 'ACTIVE' and operator_id <> 'f2010000-0000-4000-8000-000000000001'),
  'ALL resolves every other ACTIVE operator server-side'
);
select is(
  (select count(*)::integer from public.operator_message_recipients where message_id = (select id from message_fixture where kind = 'all')),
  (select count(*)::integer from public.commercial_operators where status = 'ACTIVE' and operator_id <> 'f2010000-0000-4000-8000-000000000001'),
  'broadcast has one relation per eligible active recipient'
);
select ok(not exists(
  select 1 from public.operator_message_recipients
  where message_id = (select id from message_fixture where kind = 'all')
    and recipient_operator_id in ('f2010000-0000-4000-8000-000000000001','f2010000-0000-4000-8000-000000000004')
), 'broadcast excludes sender and inactive identities');
select is((select count(*)::integer from public.operator_messages where id in (select id from message_fixture)), 2, 'personal and broadcast each retain one canonical message body');

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  (select count(*)::integer from public.operator_message_recipients),
  2,
  'Realtime recipient sees only their own personal and broadcast delivery rows'
);
select throws_ok(
  $$select count(*) from public.operator_messages$$,
  '42501', null, 'Realtime recipient cannot read canonical message content directly'
);
reset role;
select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select is(jsonb_array_length(public.list_operator_messages_v1('sent', 50)), 2, 'sender sees each canonical message once in sent items');
select is(
  (public.list_operator_messages_v1('sent', 50)->0->>'recipient_count')::integer,
  (select count(*)::integer from public.commercial_operators where status = 'ACTIVE' and operator_id <> 'f2010000-0000-4000-8000-000000000001'),
  'sent projection reports broadcast recipient cardinality without duplicating body'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000003', true);
select is(jsonb_array_length(public.list_operator_messages_v1('received', 50)), 1, 'operator B sees broadcast but not operator A personal message');
select is(public.list_operator_messages_v1('received', 50)->0->>'message_scope', 'ALL', 'received broadcast retains explicit scope');
select throws_ok(
  format('select public.mark_operator_message_read_v1(%L)', (select id from message_fixture where kind = 'personal')),
  '42501', 'OPERATOR_MESSAGE_NOT_AVAILABLE', 'unrelated operator cannot mark guessed personal message read'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000001', true);
select throws_ok(
  format('select public.mark_operator_message_read_v1(%L)', (select id from message_fixture where kind = 'all')),
  '42501', 'OPERATOR_MESSAGE_NOT_AVAILABLE', 'broadcast sender cannot alter recipient read states'
);

select set_config('request.jwt.claim.sub', 'f2000000-0000-4000-8000-000000000002', true);
select is(jsonb_array_length(public.list_operator_messages_v1('received', 50)), 2, 'offline operator A retrieves personal and broadcast deliveries on later login');
select is((select count(*)::integer from public.operator_message_recipients where recipient_operator_id = 'f2010000-0000-4000-8000-000000000002' and read_at is null), 2, 'offline deliveries remain unread');
create temporary table read_fixture(read_at timestamptz);
insert into read_fixture select (public.mark_operator_message_read_v1((select id from message_fixture where kind = 'all'))->>'read_at')::timestamptz;
select ok((select read_at is not null from read_fixture), 'operator A marks only their broadcast relation read');
select ok((select read_at is null from public.operator_message_recipients where message_id = (select id from message_fixture where kind = 'all') and recipient_operator_id = 'f2010000-0000-4000-8000-000000000003'), 'operator B independent broadcast relation remains unread');
select is((public.mark_operator_message_read_v1((select id from message_fixture where kind = 'all'))->>'read_at')::timestamptz, (select read_at from read_fixture), 'repeated mark-read is idempotent');

select throws_ok(
  format('update public.operator_messages set body = %L where id = %L', 'Gewijzigd', (select id from message_fixture where kind = 'personal')),
  '55000', 'OPERATOR_MESSAGE_IMMUTABLE', 'canonical message body is immutable'
);
select throws_ok(
  format('update public.operator_messages set message_scope = %L where id = %L', 'ALL', (select id from message_fixture where kind = 'personal')),
  '55000', 'OPERATOR_MESSAGE_IMMUTABLE', 'message scope is immutable'
);
select throws_ok(
  format('delete from public.operator_message_recipients where message_id = %L', (select id from message_fixture where kind = 'all')),
  '55000', 'OPERATOR_MESSAGE_RECIPIENT_DELETE_NOT_ALLOWED', 'recipient set cannot be deleted after send'
);
select throws_ok(
  format('delete from public.operator_messages where id = %L', (select id from message_fixture where kind = 'personal')),
  '55000', 'OPERATOR_MESSAGE_DELETE_NOT_ALLOWED', 'canonical messages cannot be deleted'
);
select ok(
  pg_get_functiondef('public.send_operator_message_v1(text,uuid,text)'::regprocedure) !~* '(online|heartbeat|last_seen|presence)',
  'personal and ALL persistence have no online or presence dependency'
);

select * from finish();
rollback;

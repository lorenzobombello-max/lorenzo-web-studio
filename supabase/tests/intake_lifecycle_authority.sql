begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(32);

select has_column('public', 'quote_request_intakes', 'access_state', 'intake has persistent access state');
select has_column('public', 'quote_request_intakes', 'lifecycle_revision', 'intake has lifecycle concurrency revision');
select has_table('public', 'quote_request_intake_lifecycle_events', 'intake lifecycle event authority exists');
select has_function('public', 'resolve_quote_request_intake_effective_access_v1', array['text','timestamptz','timestamptz'], 'canonical effective access resolver exists');

insert into auth.users (id, email) values
  ('e2300000-0000-4000-8000-000000000001', 'lifecycle-owner@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values (
  'e2310000-0000-4000-8000-000000000001',
  'e2300000-0000-4000-8000-000000000001',
  'Lifecycle Owner', 'owner', 'ACTIVE'
);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, approval_token_hash, approval_token_expires_at,
  budget_category_scheme, budget_category_code
) values
  (
    'e2320000-0000-4000-8000-000000000001', 'Legacy constructor',
    'legacy-lifecycle@example.test', 'business', 'Meer dan EUR 6.000',
    'flexible', 'Legacy lifecycle constructor fixture.', true, 'approved',
    repeat('a', 64), clock_timestamp() + interval '1 day',
    'budget_guard_v2', 'above_6000'
  ),
  (
    'e2320001-0000-4000-8000-000000000002', 'Invitation constructor',
    'invitation-lifecycle@example.test', 'business', 'Meer dan EUR 6.000',
    'flexible', 'Invitation lifecycle constructor fixture.', true, 'approved',
    repeat('b', 64), clock_timestamp() + interval '1 day',
    'budget_guard_v2', 'above_6000'
  ),
  (
    'e2320002-0000-4000-8000-000000000003', 'Existing revoked semantics',
    'revoked-lifecycle@example.test', 'business', 'Meer dan EUR 6.000',
    'flexible', 'Existing revoked lifecycle fixture.', true, 'approved',
    repeat('c', 64), clock_timestamp() + interval '1 day',
    'budget_guard_v2', 'above_6000'
  );

create temporary table legacy_created as
select * from public.create_quote_request_intake(repeat('a', 64), repeat('d', 64));

create temporary table invitation_created as
select * from public.create_quote_request_intake_invitation(
  repeat('b', 64), repeat('e', 64),
  'v1.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_token_revoked_at, started_at, created_at, draft_revision
) values (
  'e2330000-0000-4000-8000-000000000003',
  'e2320002-0000-4000-8000-000000000003',
  'in_progress', repeat('f', 64), clock_timestamp() + interval '1 day',
  clock_timestamp() - interval '1 minute', clock_timestamp() - interval '1 hour',
  clock_timestamp() - interval '2 hours', 9
);

select is(
  (select access_state from public.quote_request_intakes where access_token_hash = repeat('d', 64)),
  'ACTIVE', 'new intake defaults to ACTIVE'
);
select is(
  (select lifecycle_revision from public.quote_request_intakes where access_token_hash = repeat('d', 64)),
  0::bigint, 'lifecycle revision starts at zero'
);
select is(
  (select access_token_expires_at - created_at from public.quote_request_intakes where access_token_hash = repeat('d', 64)),
  interval '7 days', 'legacy constructor uses seven-day expiry'
);
select is(
  (select access_token_expires_at - created_at from public.quote_request_intakes where access_token_hash = repeat('e', 64)),
  interval '7 days', 'invitation constructor uses seven-day expiry'
);
select is(
  (select access_token_expires_at - created_at from public.quote_request_intakes where access_token_hash = repeat('d', 64)),
  (select access_token_expires_at - created_at from public.quote_request_intakes where access_token_hash = repeat('e', 64)),
  'both constructors share one expiry contract'
);
select is(
  (select count(*)::integer from public.quote_request_intakes where access_token_hash in (repeat('d', 64), repeat('e', 64)) and status = 'invited'),
  2, 'constructors preserve invited progress status'
);
select is(
  (select count(*)::integer from public.quote_request_intakes where access_token_hash in (repeat('d', 64), repeat('e', 64)) and access_token_revoked_at is null),
  2, 'constructors preserve existing non-revoked semantics'
);

select is(
  public.resolve_quote_request_intake_effective_access_v1('CANCELLED', timestamptz '2026-01-01 00:00:00+00', timestamptz '2026-01-02 00:00:00+00'),
  'CANCELLED', 'cancelled takes priority over expiry'
);
select is(
  public.resolve_quote_request_intake_effective_access_v1('ACTIVE', timestamptz '2026-01-01 00:00:00+00', timestamptz '2026-01-02 00:00:00+00'),
  'EXPIRED', 'expiry takes priority over active'
);
select is(
  public.resolve_quote_request_intake_effective_access_v1('INTERRUPTED', timestamptz '2026-01-01 00:00:00+00', timestamptz '2026-01-02 00:00:00+00'),
  'EXPIRED', 'expiry takes priority over interruption'
);
select is(
  public.resolve_quote_request_intake_effective_access_v1('INTERRUPTED', timestamptz '2026-01-03 00:00:00+00', timestamptz '2026-01-02 00:00:00+00'),
  'INTERRUPTED', 'interrupted takes priority over active'
);
select is(
  public.resolve_quote_request_intake_effective_access_v1('ACTIVE', timestamptz '2026-01-03 00:00:00+00', timestamptz '2026-01-02 00:00:00+00'),
  'ACTIVE', 'unexpired active intake resolves active'
);

select is(
  (select enum_range(null::public.quote_request_intake_status)::text),
  '{invited,in_progress,submitted,reviewed}', 'progress status contract is unchanged'
);
select is(
  (select draft_revision from public.quote_request_intakes where access_token_hash = repeat('f', 64)),
  9::bigint, 'existing draft revision remains independent'
);
select ok(
  (select access_token_revoked_at is not null and access_state = 'ACTIVE' and lifecycle_revision = 0
   from public.quote_request_intakes where access_token_hash = repeat('f', 64)),
  'existing revoked timestamp is preserved without rewriting lifecycle state'
);

insert into public.quote_request_intake_lifecycle_events (
  intake_id, event_type, previous_access_state, new_access_state,
  previous_expires_at, new_expires_at, actor_operator_id, reason,
  occurred_at, idempotency_key, request_fingerprint, evidence
) select
  intake.id, 'INTERRUPTED', 'ACTIVE', 'INTERRUPTED',
  intake.access_token_expires_at, intake.access_token_expires_at,
  'e2310000-0000-4000-8000-000000000001', 'Customer requested a temporary hold.',
  intake.created_at + interval '1 hour',
  'e2340000-0000-4000-8000-000000000001', repeat('1', 64),
  '{"source":"operator"}'::jsonb
from public.quote_request_intakes as intake
where intake.access_token_hash = repeat('d', 64);

select is(
  (select count(*)::integer from public.quote_request_intake_lifecycle_events),
  1, 'valid lifecycle evidence is recorded once'
);
select throws_ok(
  $$update public.quote_request_intake_lifecycle_events set reason = 'Changed'$$,
  '55000', 'INTAKE_LIFECYCLE_EVENT_IMMUTABLE', 'event updates are rejected'
);
select throws_ok(
  $$delete from public.quote_request_intake_lifecycle_events$$,
  '55000', 'INTAKE_LIFECYCLE_EVENT_IMMUTABLE', 'event deletes are rejected'
);
select throws_ok(
  $$insert into public.quote_request_intake_lifecycle_events (
      intake_id, event_type, previous_access_state, new_access_state,
      previous_expires_at, new_expires_at, actor_operator_id, reason,
      occurred_at, idempotency_key, request_fingerprint, evidence
    ) select intake.id, 'INTERRUPTED', 'ACTIVE', 'INTERRUPTED',
      intake.access_token_expires_at, intake.access_token_expires_at,
      'e2310000-0000-4000-8000-000000000001', 'Duplicate operation.',
      intake.created_at + interval '2 hours',
      'e2340000-0000-4000-8000-000000000001', repeat('2', 64), '{}'::jsonb
    from public.quote_request_intakes intake where intake.access_token_hash = repeat('d', 64)$$,
  '23505', null, 'duplicate lifecycle idempotency key is rejected'
);
select throws_ok(
  $$insert into public.quote_request_intake_lifecycle_events (
      intake_id, event_type, previous_access_state, new_access_state,
      previous_expires_at, new_expires_at, actor_operator_id, reason,
      occurred_at, idempotency_key, request_fingerprint, evidence
    ) select intake.id, 'RESUMED', 'ACTIVE', 'ACTIVE',
      intake.access_token_expires_at, intake.access_token_expires_at,
      'e2310000-0000-4000-8000-000000000001', 'Invalid transition.',
      intake.created_at + interval '2 hours',
      'e2340000-0000-4000-8000-000000000002', repeat('3', 64), '{}'::jsonb
    from public.quote_request_intakes intake where intake.access_token_hash = repeat('d', 64)$$,
  '23514', null, 'invalid lifecycle transition evidence is rejected'
);
select throws_ok(
  $$insert into public.quote_request_intake_lifecycle_events (
      intake_id, event_type, previous_access_state, new_access_state,
      previous_expires_at, new_expires_at, actor_operator_id, reason,
      occurred_at, idempotency_key, request_fingerprint, evidence
    ) select intake.id, 'INTERRUPTED', 'ACTIVE', 'INTERRUPTED',
      intake.access_token_expires_at, intake.access_token_expires_at,
      'e2310000-0000-4000-8000-000000000001', 'Unsafe evidence.',
      intake.created_at + interval '2 hours',
      'e2340000-0000-4000-8000-000000000003', repeat('4', 64),
      '{"access_token_hash":"forbidden"}'::jsonb
    from public.quote_request_intakes intake where intake.access_token_hash = repeat('d', 64)$$,
  '23514', null, 'token material is forbidden from lifecycle evidence'
);

select ok(
  not has_table_privilege('anon', 'public.quote_request_intakes', 'update')
  and not has_table_privilege('authenticated', 'public.quote_request_intakes', 'update'),
  'customer roles cannot mutate intake lifecycle columns'
);
select ok(
  not has_table_privilege('anon', 'public.quote_request_intake_lifecycle_events', 'insert')
  and not has_table_privilege('authenticated', 'public.quote_request_intake_lifecycle_events', 'insert')
  and not has_table_privilege('service_role', 'public.quote_request_intake_lifecycle_events', 'insert'),
  'lifecycle event inserts require a future guarded authority function'
);
select ok(
  not has_table_privilege('anon', 'public.quote_request_intake_lifecycle_events', 'select')
  and not has_table_privilege('authenticated', 'public.quote_request_intake_lifecycle_events', 'select'),
  'lifecycle evidence is not publicly readable'
);
select ok(
  has_function_privilege('service_role', 'public.resolve_quote_request_intake_effective_access_v1(text,timestamptz,timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.resolve_quote_request_intake_effective_access_v1(text,timestamptz,timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.resolve_quote_request_intake_effective_access_v1(text,timestamptz,timestamptz)', 'execute'),
  'effective resolver is service-role-only'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.quote_request_intake_lifecycle_events'::regclass),
  'lifecycle event authority has forced RLS'
);
select ok(
  position('quote_request_intake_default_expires_at_v1' in pg_get_functiondef('public.create_quote_request_intake(text,text)'::regprocedure)) > 0
  and position('quote_request_intake_default_expires_at_v1' in pg_get_functiondef('public.create_quote_request_intake_invitation(text,text,text)'::regprocedure)) > 0,
  'both constructors call the shared expiry authority'
);
select ok(
  position('14 days' in pg_get_functiondef('public.create_quote_request_intake(text,text)'::regprocedure)) = 0
  and position('14 days' in pg_get_functiondef('public.create_quote_request_intake_invitation(text,text,text)'::regprocedure)) = 0,
  'active constructor definitions contain no fourteen-day fallback'
);

select * from finish();
rollback;
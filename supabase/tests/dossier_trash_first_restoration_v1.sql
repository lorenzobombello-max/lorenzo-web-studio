begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(21);

select function_returns(
  'lws_internal', 'enforce_dossier_trash_before_purge_v1', array[]::text[], 'trigger',
  'hard-delete guard is installed'
);

select trigger_is(
  'lws_internal', 'operator_dossier_states',
  'trg_enforce_dossier_trash_before_purge_v1',
  'lws_internal', 'enforce_dossier_trash_before_purge_v1',
  'dossier state owns the trash-before-purge guard'
);

select ok(
  position('v_state.state <> ''TRASHED''' in pg_get_functiondef('public.can_purge_dossier_v1(uuid)'::regprocedure)::text) > 0,
  'Website purge eligibility requires TRASHED'
);

select ok(
  position('not in (''ACTIVE'', ''TRASHED'')' in pg_get_functiondef('public.can_purge_dossier_v1(uuid)'::regprocedure)::text) = 0,
  'Website purge eligibility has no direct-active allowance'
);

select ok(
  position('v_state.state <> ''TRASHED''' in pg_get_functiondef('public.can_purge_sdf_dossier_v1(uuid)'::regprocedure)::text) > 0,
  'SDF purge eligibility requires TRASHED'
);

select ok(
  position('not in (''ACTIVE'', ''TRASHED'')' in pg_get_functiondef('public.can_purge_sdf_dossier_v1(uuid)'::regprocedure)::text) = 0,
  'SDF purge eligibility has no direct-active allowance'
);

select ok(
  position('DOSSIER_NOT_TRASHED' in pg_get_functiondef('lws_internal.enforce_dossier_trash_before_purge_v1()'::regprocedure)::text) > 0,
  'hard-delete guard fails with explicit lifecycle authority error'
);

select ok(
  position('lws.sdf_dossier_purge_authority' in pg_get_functiondef('lws_internal.enforce_dossier_trash_before_purge_v1()'::regprocedure)::text) > 0,
  'hard-delete guard covers the separate SDF purge authority'
);

select ok(
  position('dossier_state.state <> ''TRASHED''' in pg_get_viewdef('lws_internal.operator_pending_intakes_v1'::regclass, true)::text) > 0,
  'trashed Website applications leave Pending'
);

select ok(
  position('dossier_state.state <> ''TRASHED''' in pg_get_viewdef('lws_internal.operator_pending_sdf_intakes_v1'::regclass, true)::text) > 0,
  'trashed SDF applications leave Pending'
);

select ok(
  position('''invited''' in pg_get_viewdef('lws_internal.operator_application_readmodel_v2'::regclass, true)::text) > 0,
  'Trash readmodel includes pending intake statuses'
);

select ok(
  position('''dossier_state'', pending.dossier_state' in pg_get_functiondef('public.list_operator_pending_intakes_v1_pre_dos_r1_current_seen(uuid,text)'::regprocedure)::text) > 0,
  'Website Pending DTO exposes canonical dossier state'
);

select ok(
  position('''dossier_revision'', pending.dossier_revision' in pg_get_functiondef('public.list_operator_pending_intakes_v1_pre_dos_r1_current_seen(uuid,text)'::regprocedure)::text) > 0,
  'Website Pending DTO exposes canonical dossier revision'
);

insert into auth.users (id, email) values
  ('a7100000-0000-4000-8000-000000000001', 'trash-first-owner@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values (
  'a7110000-0000-4000-8000-000000000001',
  'a7100000-0000-4000-8000-000000000001',
  'Trash first owner', 'owner', 'ACTIVE'
);

insert into public.quote_requests (
  id, record_classification, request_kind, name, email, website_type,
  budget, timing, description, privacy_consent, status
) values (
  'a7120000-0000-4000-8000-000000000001', 'production', 'website',
  'Trash first fixture', 'trash-first-fixture@example.test', 'business',
  'Meer dan EUR 6.000', 'flexible', 'Trash-first lifecycle fixture.', true, 'approved'
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, confirmation, created_at
) values (
  'a7130000-0000-4000-8000-000000000001',
  'a7120000-0000-4000-8000-000000000001',
  'invited', repeat('7', 64), '2099-09-03T12:00:00Z',
  'ACTIVE', 0, false, clock_timestamp()
);

create function pg_temp.transition_dossier(
  p_event_type text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_reason text
)
returns jsonb
language plpgsql
as $$
declare
  v_capability uuid;
begin
  v_capability := public.issue_operator_dossier_lifecycle_edge_capability_v1(
    auth.uid(), 'a7120000-0000-4000-8000-000000000001', p_event_type,
    p_expected_revision, p_idempotency_key, p_reason
  );
  return public.execute_operator_dossier_lifecycle_command_v1(
    'a7120000-0000-4000-8000-000000000001', p_event_type,
    p_expected_revision, p_idempotency_key, p_reason, v_capability
  );
end;
$$;

select is(
  (select count(*)::integer from lws_internal.operator_pending_intakes_v1
   where quote_request_id = 'a7120000-0000-4000-8000-000000000001'),
  1,
  'invited Website application starts in Pending'
);

select set_config('request.jwt.claim.sub', 'a7100000-0000-4000-8000-000000000001', true);
select is(
  pg_temp.transition_dossier(
    'TRASHED', 0, 'a7140000-0000-4000-8000-000000000001', 'Niet verder opvolgen'
  )->>'state',
  'TRASHED',
  'Pending application transitions through canonical dossier lifecycle'
);

select is(
  (select count(*)::integer from lws_internal.operator_pending_intakes_v1
   where quote_request_id = 'a7120000-0000-4000-8000-000000000001'),
  0,
  'trashed application leaves Pending immediately'
);

select is(
  (select zone::text from lws_internal.operator_application_readmodel_v2
   where quote_request_id = 'a7120000-0000-4000-8000-000000000001'),
  'TRASHED',
  'trashed incomplete application enters the Trash readmodel'
);

select is(
  public.can_purge_dossier_v1('a7120000-0000-4000-8000-000000000001')->>'can_purge',
  'true',
  'owner receives purge eligibility only after Trash transition'
);

select is(
  pg_temp.transition_dossier(
    'RESTORED', 1, 'a7140000-0000-4000-8000-000000000002', 'Opvolging hervatten'
  )->>'state',
  'ACTIVE',
  'trashed Pending application can be restored revision-bound'
);

select is(
  (select count(*)::integer from lws_internal.operator_application_readmodel_v2
   where quote_request_id = 'a7120000-0000-4000-8000-000000000001'),
  0,
  'restored incomplete application leaves the Trash readmodel'
);

select is(
  (select count(*)::integer from lws_internal.operator_pending_intakes_v1
   where quote_request_id = 'a7120000-0000-4000-8000-000000000001'),
  1,
  'restored incomplete application returns to Pending'
);

select * from finish();
rollback;
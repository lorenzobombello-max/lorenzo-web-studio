begin;

select plan(10);

-- GIT-001 migration-sequence transient-risk closure regression.
--
-- These assertions guard the technical quiescence barrier design:
--   20260920130000 (production head, claim already reachable)
--   -> 20260920135900 (deny: revokes authenticated EXECUTE on claim)
--   -> 20260920140000 (guard logic; CREATE OR REPLACE preserves revoked ACL)
--   -> 20260920150000 (adds recovery-authority/finalize with NO grants)
--   -> 20260920231950 (lineage hardening; restores the exact final matrix)
--
-- On a fully migrated database (the state pgTAP always runs against), the
-- end state must exactly match the intended, non-broadened privilege
-- matrix: authenticated may claim/read-authority, service_role alone may
-- finalize, and no anon/PUBLIC/service_role-on-claim/authenticated-on-
-- finalize leakage exists. If a future migration accidentally reorders or
-- drops a revoke/grant statement, these assertions fail closed.

select ok(
  has_function_privilege(
    'authenticated',
    'public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text)',
    'execute'
  ),
  'final state: authenticated retains EXECUTE on claim_production_website_repository_provisioning_v1'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text)',
    'execute'
  ),
  'final state: claim_production_website_repository_provisioning_v1 grants nothing to anon or service_role'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_production_website_repository_recovery_authority_v1(uuid,uuid,uuid)',
    'execute'
  ),
  'final state: authenticated retains EXECUTE on get_production_website_repository_recovery_authority_v1'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_production_website_repository_recovery_authority_v1(uuid,uuid,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_production_website_repository_recovery_authority_v1(uuid,uuid,uuid)',
    'execute'
  ),
  'final state: get_production_website_repository_recovery_authority_v1 grants nothing to anon or service_role'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.finalize_production_website_repository_recovery_v1(uuid,uuid,jsonb,uuid,text)',
    'execute'
  ),
  'final state: service_role retains EXECUTE on finalize_production_website_repository_recovery_v1'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.finalize_production_website_repository_recovery_v1(uuid,uuid,jsonb,uuid,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.finalize_production_website_repository_recovery_v1(uuid,uuid,jsonb,uuid,text)',
    'execute'
  ),
  'final state: finalize_production_website_repository_recovery_v1 grants nothing to anon or authenticated'
);

-- Simulate the mid-promotion quiescence boundary (deny applied, hardening
-- not yet complete) inside this rolled-back test transaction and prove the
-- sensitive surface is technically unreachable, not merely conventionally
-- discouraged.
revoke execute on function
  public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text),
  public.get_production_website_repository_recovery_authority_v1(uuid,uuid,uuid)
from authenticated;
revoke execute on function
  public.finalize_production_website_repository_recovery_v1(uuid,uuid,jsonb,uuid,text)
from service_role;

-- Privilege checks apply to the *current* database role, not the calling
-- test session's owner, so these must actually run `as` authenticated /
-- service_role, not merely as the superuser test runner.
set local role authenticated;
select throws_ok(
  $$select public.claim_production_website_repository_provisioning_v1(
    gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
    'x', '1.0.0', repeat('a', 40))$$,
  '42501',
  'permission denied for function claim_production_website_repository_provisioning_v1',
  'quiesced boundary: claim is technically denied, not merely policy-discouraged'
);
select throws_ok(
  $$select public.get_production_website_repository_recovery_authority_v1(
    gen_random_uuid(), gen_random_uuid(), gen_random_uuid())$$,
  '42501',
  'permission denied for function get_production_website_repository_recovery_authority_v1',
  'quiesced boundary: recovery authority read is technically denied'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.finalize_production_website_repository_recovery_v1(
    gen_random_uuid(), gen_random_uuid(), '{}'::jsonb, gen_random_uuid(), 'aal2')$$,
  '42501',
  'permission denied for function finalize_production_website_repository_recovery_v1',
  'quiesced boundary: finalize is technically denied'
);
reset role;

-- Restore grants within this same rolled-back test transaction so any
-- later test file in the same run session sees the true committed state
-- (defense in depth; the outer `rollback;` already guarantees this).
grant execute on function
  public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text),
  public.get_production_website_repository_recovery_authority_v1(uuid,uuid,uuid)
to authenticated;
grant execute on function
  public.finalize_production_website_repository_recovery_v1(uuid,uuid,jsonb,uuid,text)
to service_role;

select ok(
  has_function_privilege(
    'authenticated',
    'public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text)',
    'execute'
  ),
  'restored: authenticated regains EXECUTE on claim_production_website_repository_provisioning_v1'
);

select * from finish();

rollback;

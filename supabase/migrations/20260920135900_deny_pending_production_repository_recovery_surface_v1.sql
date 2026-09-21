-- GIT-001 migration-sequence transient-risk closure: technical quiescence
-- barrier.
--
-- This migration is intentionally sequenced immediately after the current
-- production migration head (20260920130000) and strictly before the
-- pending, not-yet-production-applied sequence
-- 20260920140000 -> 20260920150000 -> 20260920231950.
--
-- Supabase applies pending migration files sequentially, each executed as
-- its own atomic unit; there is no transaction wrapping the entire pending
-- set. If a production `db push` stops after 20260920140000 or
-- 20260920150000 succeeds but before 20260920231950 (the lineage-hardening
-- migration) completes, production would otherwise be left, for an
-- unbounded period, with the pre-hardening "vulnerable latest-operation"
-- claim implementation installed and reachable by ordinary authenticated
-- callers.
--
-- public.claim_production_website_repository_provisioning_v1 is the only
-- production-repository entry point that already exists at the current
-- production head; it is the sole path capable of creating a fresh
-- provisioning operation (the CREATE_REPOSITORY-capable path). Revoking its
-- EXECUTE grant from `authenticated` here, before 20260920140000 is ever
-- applied, guarantees no externally reachable caller can invoke a fresh
-- PRE_PROJECT claim at any point during the pending promotion sequence,
-- regardless of which file the sequence stops on.
--
-- public.get_production_website_repository_recovery_authority_v1 and
-- public.finalize_production_website_repository_recovery_v1 do not exist
-- yet at this point (they are first created by 20260920150000), so they
-- require no action here; 20260920150000 has been adjusted to not grant
-- EXECUTE on them at creation time, deferring that grant to
-- 20260920231950's existing trailing revoke/grant block, which restores
-- the complete, non-broadened privilege matrix once the canonical
-- durable-identity resolver is installed. No separate "re-enable"
-- migration is required.
--
-- This migration is forward-safe/idempotent: revoking an already-revoked
-- privilege is a no-op, so replaying it (e.g. via `migration up`
-- re-application semantics) is always safe.

revoke execute on function public.claim_production_website_repository_provisioning_v1(
  uuid, uuid, uuid, uuid, text, text, text
) from authenticated;

comment on function public.claim_production_website_repository_provisioning_v1(
  uuid, uuid, uuid, uuid, text, text, text
) is 'OWNER+AAL2 production PRE_PROJECT claim authority; EXECUTE temporarily revoked from authenticated by 20260920135900 pending lineage hardening in 20260920231950, which restores it.';

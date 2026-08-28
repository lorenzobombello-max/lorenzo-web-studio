create function public.get_pricing_snapshot_integrity_for_operator_v1(
  p_snapshot_id uuid
)
returns table (
  algorithm_version text,
  key_id text,
  mac text
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select
    integrity.algorithm_version,
    integrity.key_id,
    integrity.mac
  from public.quote_request_pricing_snapshot_integrity as integrity
  where integrity.snapshot_id = p_snapshot_id
$$;

revoke all on function public.get_pricing_snapshot_integrity_for_operator_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_pricing_snapshot_integrity_for_operator_v1(uuid)
to service_role;
begin;

revoke execute on function public.list_operator_pending_sdf_intakes_v1(uuid) from authenticated;
grant execute on function public.list_operator_pending_sdf_intakes_v1(uuid) to service_role;

commit;
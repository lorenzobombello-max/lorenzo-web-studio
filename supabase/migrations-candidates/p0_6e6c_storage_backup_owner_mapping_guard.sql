-- LOCAL_CANDIDATE_NOT_PRODUCTION_ACTIVATABLE. DO NOT APPLY.
-- Remove the executable guard only in a separately reviewed activation artifact.

begin;

do $lws_backup_owner_mapping_activation_guard$
begin
  raise exception 'LWS_BACKUP_OWNER_MAPPING_GUARD_NOT_PRODUCTION_ACTIVATABLE';
end;
$lws_backup_owner_mapping_activation_guard$;

alter table public.commercial_operators
  add constraint commercial_operators_backup_identity_not_active_owner_v1
  check (
    auth_user_id <> 'e7a62396-efac-4402-b9a9-c161bc29a051'::uuid
    or status <> 'ACTIVE'
    or role <> 'owner'
  ) not valid;

alter table public.commercial_operators
  validate constraint commercial_operators_backup_identity_not_active_owner_v1;

commit;

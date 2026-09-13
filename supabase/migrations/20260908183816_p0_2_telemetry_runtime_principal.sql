-- LOCAL_INERT_RUNTIME_PRINCIPAL_CANDIDATE_NOT_ACTIVATABLE. DO NOT APPLY.
-- The unconditional guard keeps all role membership and privilege changes inert.

begin;


do $lws_p0_2_telemetry_runtime_roles$
declare
  runtime_oid oid;
begin
  select oid
    into runtime_oid
    from pg_catalog.pg_roles
   where rolname = 'p0_2_telemetry_runtime';

  if runtime_oid is null then
    execute 'create role p0_2_telemetry_runtime login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls';
  else
    if exists (
      select 1
      from pg_catalog.pg_roles
       where oid = runtime_oid
         and (
           not rolcanlogin
           or not rolinherit
           or rolsuper
           or rolcreatedb
           or rolcreaterole
           or rolreplication
           or rolbypassrls
         )
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_ROLE_ATTRIBUTES';
    end if;

    if (
      select count(*)
        from pg_catalog.pg_auth_members membership
       where membership.member = runtime_oid
    ) <> 4
    or (
      select count(*)
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles granted_role on granted_role.oid = membership.roleid
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.member = runtime_oid
         and granted_role.rolname = any (array[
           'p0_2_telemetry_checkpoint_controller',
           'p0_2_telemetry_lifecycle_controller',
           'p0_2_telemetry_runtime_writer',
           'p0_2_telemetry_report_reader'
         ]::name[])
         and grantor_role.rolname = 'postgres'
         and membership.inherit_option
         and not membership.set_option
         and not membership.admin_option
    ) <> 4
    or (
      select count(*)
        from pg_catalog.pg_auth_members membership
       where membership.roleid = runtime_oid
    ) <> 1
    or (
      select count(*)
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.roleid = runtime_oid
         and member_role.rolname = 'postgres'
         and grantor_role.rolname = 'supabase_admin'
         and not membership.inherit_option
         and not membership.set_option
         and membership.admin_option
    ) <> 1
  then
      raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_MEMBERSHIP';
    end if;

    if exists (
      select 1
        from pg_catalog.pg_proc routine
        cross join lateral pg_catalog.aclexplode(routine.proacl) privilege
       where privilege.grantee = runtime_oid
    ) or exists (
      select 1
        from pg_catalog.pg_class relation
        cross join lateral pg_catalog.aclexplode(relation.relacl) privilege
       where privilege.grantee = runtime_oid
    ) or exists (
      select 1
        from pg_catalog.pg_namespace namespace
        cross join lateral pg_catalog.aclexplode(namespace.nspacl) privilege
       where privilege.grantee = runtime_oid
    ) or exists (
      select 1
        from pg_catalog.pg_database database_entry
        cross join lateral pg_catalog.aclexplode(database_entry.datacl) privilege
       where privilege.grantee = runtime_oid
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_DIRECT_PRIVILEGE';
    end if;

    if exists (
      select 1
        from pg_catalog.pg_proc routine
       where routine.proowner = runtime_oid
    ) or exists (
      select 1
        from pg_catalog.pg_class relation
       where relation.relowner = runtime_oid
    ) or exists (
      select 1
        from pg_catalog.pg_namespace namespace
       where namespace.nspowner = runtime_oid
    ) or exists (
      select 1
        from pg_catalog.pg_database database_entry
       where database_entry.datdba = runtime_oid
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_OWNERSHIP';
    end if;

    if exists (
      select 1
        from pg_catalog.pg_default_acl default_acl
        cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) privilege
       where privilege.grantee = runtime_oid
         and default_acl.defaclobjtype in ('f', 'r', 'S', 'n', 'T')
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_DEFAULT_ACL';
    end if;
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_roles
     where rolname = 'p0_2_telemetry_checkpoint_controller'
  ) then
    execute 'create role p0_2_telemetry_checkpoint_controller nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls';
  end if;
  if not exists (
    select 1
      from pg_catalog.pg_roles
     where rolname = 'p0_2_telemetry_lifecycle_controller'
  ) then
    execute 'create role p0_2_telemetry_lifecycle_controller nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls';
  end if;
  if not exists (
    select 1
      from pg_catalog.pg_roles
     where rolname = 'p0_2_telemetry_runtime_writer'
  ) then
    execute 'create role p0_2_telemetry_runtime_writer nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls';
  end if;
  if not exists (
    select 1
      from pg_catalog.pg_roles
     where rolname = 'p0_2_telemetry_report_reader'
  ) then
    execute 'create role p0_2_telemetry_report_reader nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls';
  end if;
end;
$lws_p0_2_telemetry_runtime_roles$;

alter role p0_2_telemetry_checkpoint_controller
  with nologin noinherit nocreatedb nocreaterole noreplication nobypassrls;
alter role p0_2_telemetry_lifecycle_controller
  with nologin noinherit nocreatedb nocreaterole noreplication nobypassrls;
alter role p0_2_telemetry_runtime_writer
  with nologin noinherit nocreatedb nocreaterole noreplication nobypassrls;
alter role p0_2_telemetry_report_reader
  with nologin noinherit nocreatedb nocreaterole noreplication nobypassrls;

do $lws_p0_2_validate_capability_roles$
declare
  capability record;
begin
  for capability in
    select expected.role_name, expected.function_signatures, roles.oid
      from (values
        (
          'p0_2_telemetry_checkpoint_controller'::name,
          array[
            'p0_2_aggregate_telemetry.create_p0_2_telemetry_activation_checkpoint_v1(text, integer)',
            'p0_2_aggregate_telemetry.read_p0_2_telemetry_activation_checkpoint_v1()',
            'p0_2_aggregate_telemetry.transition_p0_2_telemetry_activation_checkpoint_v1(text, text, bigint, timestamp with time zone, timestamp with time zone, bigint, text)',
            'p0_2_aggregate_telemetry.invalidate_p0_2_telemetry_activation_checkpoint_v1(text, bigint, bigint, text, boolean)',
            'p0_2_aggregate_telemetry.acquire_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer)',
            'p0_2_aggregate_telemetry.renew_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer)',
            'p0_2_aggregate_telemetry.release_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text)',
            'p0_2_aggregate_telemetry.claim_p0_2_telemetry_heartbeat_bucket_v1(text, bigint, bigint, text, integer)'
          ]::text[]
        ),
        (
          'p0_2_telemetry_lifecycle_controller'::name,
          array[
            'p0_2_aggregate_telemetry.cover_p0_2_aggregate_telemetry_minute_v1(timestamp with time zone, integer, bigint, bigint, text)',
            'p0_2_aggregate_telemetry.create_p0_2_aggregate_telemetry_window_v1(bigint, bigint, text)',
            'p0_2_aggregate_telemetry.seal_p0_2_aggregate_telemetry_window_v1(timestamp with time zone, bigint, bigint, text)'
          ]::text[]
        ),
        (
          'p0_2_telemetry_runtime_writer'::name,
          array[
            'p0_2_aggregate_telemetry.increment_p0_2_aggregate_telemetry_counter_v1(timestamp with time zone, text, integer, bigint, bigint, text)'
          ]::text[]
        ),
        (
          'p0_2_telemetry_report_reader'::name,
          array[
            'p0_2_aggregate_telemetry.read_p0_2_aggregate_telemetry_report_v1(timestamp with time zone, bigint, bigint, text)'
          ]::text[]
        )
      ) as expected(role_name, function_signatures)
      join pg_catalog.pg_roles roles on roles.rolname = expected.role_name
  loop
    if exists (
      select 1
        from pg_catalog.pg_roles role_state
       where role_state.oid = capability.oid
         and (
           role_state.rolcanlogin
           or role_state.rolinherit
           or role_state.rolsuper
           or role_state.rolcreatedb
           or role_state.rolcreaterole
           or role_state.rolreplication
           or role_state.rolbypassrls
         )
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_CAPABILITY_ROLE_ATTRIBUTES: %', capability.role_name;
    end if;

    if exists (
      select 1
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.member = capability.oid
          or (
            membership.roleid = capability.oid
            and not (
              (
                member_role.rolname = 'p0_2_telemetry_runtime'
                and grantor_role.rolname = 'postgres'
                and membership.inherit_option
                and not membership.set_option
                and not membership.admin_option
              )
              or (
                member_role.rolname = 'postgres'
                and grantor_role.rolname = 'supabase_admin'
                and not membership.inherit_option
                and not membership.set_option
                and membership.admin_option
              )
            )
          )
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_CAPABILITY_MEMBERSHIP: %', capability.role_name;
    end if;

    if exists (
      select 1
        from (
          select
            privilege.privilege_type,
            privilege.is_grantable,
            routine.oid as function_oid
          from pg_catalog.pg_proc routine
          cross join lateral pg_catalog.aclexplode(routine.proacl) privilege
          where privilege.grantee = capability.oid
        ) privilege
       where privilege.privilege_type <> 'EXECUTE'
          or privilege.is_grantable
          or not exists (
            select 1
              from unnest(capability.function_signatures) as expected_signature(signature)
             where pg_catalog.to_regprocedure(expected_signature.signature) = privilege.function_oid
          )
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_FUNCTION_EXECUTE: %', capability.role_name;
    end if;

    if exists (
      select 1
        from pg_catalog.pg_class relation
        cross join lateral pg_catalog.aclexplode(relation.relacl) privilege
       where privilege.grantee = capability.oid
         and relation.relkind in ('r', 'p', 'v', 'm', 'f')
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_TABLE_PRIVILEGE: %', capability.role_name;
    end if;

    if exists (
      select 1
        from pg_catalog.pg_class relation
        cross join lateral pg_catalog.aclexplode(relation.relacl) privilege
       where privilege.grantee = capability.oid
         and relation.relkind = 'S'
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_SEQUENCE_PRIVILEGE: %', capability.role_name;
    end if;

    if exists (
      select 1
        from pg_catalog.pg_namespace namespace
        cross join lateral pg_catalog.aclexplode(namespace.nspacl) privilege
       where privilege.grantee = capability.oid
         and (
           namespace.nspname <> 'p0_2_aggregate_telemetry'
           or privilege.privilege_type <> 'USAGE'
           or privilege.is_grantable
         )
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_SCHEMA_PRIVILEGE: %', capability.role_name;
    end if;

    if exists (
      select 1
        from pg_catalog.pg_database database_entry
        cross join lateral pg_catalog.aclexplode(database_entry.datacl) privilege
       where privilege.grantee = capability.oid
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_DATABASE_PRIVILEGE: %', capability.role_name;
    end if;

    if exists (
      select 1
        from pg_catalog.pg_proc routine
       where routine.proowner = capability.oid
    ) or exists (
      select 1
        from pg_catalog.pg_class relation
       where relation.relowner = capability.oid
    ) or exists (
      select 1
        from pg_catalog.pg_namespace namespace
       where namespace.nspowner = capability.oid
    ) or exists (
      select 1
        from pg_catalog.pg_database database_entry
       where database_entry.datdba = capability.oid
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_CAPABILITY_OWNERSHIP: %', capability.role_name;
    end if;

    if exists (
      select 1
        from pg_catalog.pg_default_acl default_acl
        cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) privilege
       where privilege.grantee = capability.oid
         and default_acl.defaclobjtype in ('f', 'r', 'S', 'n', 'T')
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_CAPABILITY_DEFAULT_ACL: %', capability.role_name;
    end if;
  end loop;

  perform 'LWS_P0_2_CAPABILITY_ROLES_VALIDATED';
end;
$lws_p0_2_validate_capability_roles$;

do $lws_p0_2_private_owner_preflight$
declare
  private_owner_oid oid;
begin
  select oid into private_owner_oid from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_private_owner';

  if private_owner_oid is null
    or (
      select count(*)
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.roleid = private_owner_oid
    ) <> 1
    or not exists (
      select 1
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.roleid = private_owner_oid
         and member_role.rolname = 'postgres'
         and grantor_role.rolname = 'supabase_admin'
         and membership.admin_option
         and not membership.inherit_option
         and not membership.set_option
    ) then
    raise exception 'LWS_P0_2_UNEXPECTED_PRIVATE_OWNER_MEMBERSHIP';
  end if;
end;
$lws_p0_2_private_owner_preflight$;

grant p0_2_telemetry_private_owner to postgres
  with admin false, inherit false, set true
  granted by postgres;
set local role p0_2_telemetry_private_owner;
revoke all on schema p0_2_aggregate_telemetry
  from public, anon, authenticated, p0_2_telemetry_runtime;
revoke create on schema p0_2_aggregate_telemetry
  from p0_2_telemetry_checkpoint_controller,
       p0_2_telemetry_lifecycle_controller,
       p0_2_telemetry_runtime_writer,
       p0_2_telemetry_report_reader;
grant usage on schema p0_2_aggregate_telemetry to p0_2_telemetry_checkpoint_controller;
grant usage on schema p0_2_aggregate_telemetry to p0_2_telemetry_lifecycle_controller;
grant usage on schema p0_2_aggregate_telemetry to p0_2_telemetry_runtime_writer;
grant usage on schema p0_2_aggregate_telemetry to p0_2_telemetry_report_reader;

revoke all on table
  p0_2_aggregate_telemetry.activation_checkpoint,
  p0_2_aggregate_telemetry.windows
  from public, anon, authenticated;
revoke all on table
  p0_2_aggregate_telemetry.activation_checkpoint,
  p0_2_aggregate_telemetry.windows
  from p0_2_telemetry_runtime,
       p0_2_telemetry_checkpoint_controller,
       p0_2_telemetry_lifecycle_controller,
       p0_2_telemetry_runtime_writer,
       p0_2_telemetry_report_reader;

revoke execute on function p0_2_aggregate_telemetry.create_p0_2_telemetry_activation_checkpoint_v1(text, integer) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.read_p0_2_telemetry_activation_checkpoint_v1() from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.transition_p0_2_telemetry_activation_checkpoint_v1(text, text, bigint, timestamptz, timestamptz, bigint, text) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.invalidate_p0_2_telemetry_activation_checkpoint_v1(text, bigint, bigint, text, boolean) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.acquire_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.renew_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.release_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.claim_p0_2_telemetry_heartbeat_bucket_v1(text, bigint, bigint, text, integer) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.increment_p0_2_aggregate_telemetry_counter_v1(timestamptz, text, integer, bigint, bigint, text) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.cover_p0_2_aggregate_telemetry_minute_v1(timestamptz, integer, bigint, bigint, text) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.create_p0_2_aggregate_telemetry_window_v1(bigint, bigint, text) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.seal_p0_2_aggregate_telemetry_window_v1(timestamptz, bigint, bigint, text) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;
revoke execute on function p0_2_aggregate_telemetry.read_p0_2_aggregate_telemetry_report_v1(timestamptz, bigint, bigint, text) from public, anon, authenticated, p0_2_telemetry_runtime, p0_2_telemetry_checkpoint_controller, p0_2_telemetry_lifecycle_controller, p0_2_telemetry_runtime_writer, p0_2_telemetry_report_reader;

grant execute on function p0_2_aggregate_telemetry.create_p0_2_telemetry_activation_checkpoint_v1(text, integer) to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.read_p0_2_telemetry_activation_checkpoint_v1() to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.transition_p0_2_telemetry_activation_checkpoint_v1(text, text, bigint, timestamptz, timestamptz, bigint, text) to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.invalidate_p0_2_telemetry_activation_checkpoint_v1(text, bigint, bigint, text, boolean) to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.acquire_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer) to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.renew_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer) to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.release_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text) to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.claim_p0_2_telemetry_heartbeat_bucket_v1(text, bigint, bigint, text, integer) to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.increment_p0_2_aggregate_telemetry_counter_v1(timestamptz, text, integer, bigint, bigint, text) to p0_2_telemetry_runtime_writer;
grant execute on function p0_2_aggregate_telemetry.cover_p0_2_aggregate_telemetry_minute_v1(timestamptz, integer, bigint, bigint, text) to p0_2_telemetry_lifecycle_controller;
grant execute on function p0_2_aggregate_telemetry.create_p0_2_aggregate_telemetry_window_v1(bigint, bigint, text) to p0_2_telemetry_lifecycle_controller;
grant execute on function p0_2_aggregate_telemetry.seal_p0_2_aggregate_telemetry_window_v1(timestamptz, bigint, bigint, text) to p0_2_telemetry_lifecycle_controller;
grant execute on function p0_2_aggregate_telemetry.read_p0_2_aggregate_telemetry_report_v1(timestamptz, bigint, bigint, text) to p0_2_telemetry_report_reader;
reset role;
revoke p0_2_telemetry_private_owner from postgres granted by postgres;

do $lws_p0_2_private_owner_restored$
declare
  private_owner_oid oid;
begin
  select oid into strict private_owner_oid from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_private_owner';

  if (
      select count(*)
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.roleid = private_owner_oid
    ) <> 1
    or not exists (
      select 1
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.roleid = private_owner_oid
         and member_role.rolname = 'postgres'
         and grantor_role.rolname = 'supabase_admin'
         and membership.admin_option
         and not membership.inherit_option
         and not membership.set_option
    ) then
    raise exception 'LWS_P0_2_PRIVATE_OWNER_MEMBERSHIP_NOT_RESTORED';
  end if;
end;
$lws_p0_2_private_owner_restored$;


grant p0_2_telemetry_checkpoint_controller to p0_2_telemetry_runtime with inherit true, set false;
grant p0_2_telemetry_lifecycle_controller to p0_2_telemetry_runtime with inherit true, set false;
grant p0_2_telemetry_runtime_writer to p0_2_telemetry_runtime with inherit true, set false;
grant p0_2_telemetry_report_reader to p0_2_telemetry_runtime with inherit true, set false;

do $lws_p0_2_final_validation$
declare
  runtime_oid oid;
  private_owner_oid oid;
  capability record;
begin
  select oid into strict runtime_oid from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_runtime';

  if exists (
    select 1 from pg_catalog.pg_roles
     where oid = runtime_oid
       and (
         not rolcanlogin or not rolinherit or rolsuper or rolcreatedb
         or rolcreaterole or rolreplication or rolbypassrls
       )
  ) then
    raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_ROLE_ATTRIBUTES';
  end if;

  if (
      select count(*)
        from pg_catalog.pg_auth_members membership
       where membership.member = runtime_oid
    ) <> 4
    or (
      select count(*)
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles granted_role on granted_role.oid = membership.roleid
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.member = runtime_oid
         and granted_role.rolname = any (array[
           'p0_2_telemetry_checkpoint_controller',
           'p0_2_telemetry_lifecycle_controller',
           'p0_2_telemetry_runtime_writer',
           'p0_2_telemetry_report_reader'
         ]::name[])
         and grantor_role.rolname = 'postgres'
         and membership.inherit_option
         and not membership.set_option
         and not membership.admin_option
    ) <> 4
    or (
      select count(*)
        from pg_catalog.pg_auth_members membership
       where membership.roleid = runtime_oid
    ) <> 1
    or (
      select count(*)
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.roleid = runtime_oid
         and member_role.rolname = 'postgres'
         and grantor_role.rolname = 'supabase_admin'
         and not membership.inherit_option
         and not membership.set_option
         and membership.admin_option
    ) <> 1
  then
    raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_MEMBERSHIP';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc routine
    cross join lateral pg_catalog.aclexplode(routine.proacl) privilege
    where privilege.grantee = runtime_oid
  ) or exists (
    select 1 from pg_catalog.pg_class relation
    cross join lateral pg_catalog.aclexplode(relation.relacl) privilege
    where privilege.grantee = runtime_oid
  ) or exists (
    select 1 from pg_catalog.pg_namespace namespace
    cross join lateral pg_catalog.aclexplode(namespace.nspacl) privilege
    where privilege.grantee = runtime_oid
  ) or exists (
    select 1 from pg_catalog.pg_database database_entry
    cross join lateral pg_catalog.aclexplode(database_entry.datacl) privilege
    where privilege.grantee = runtime_oid
  ) then
    raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_DIRECT_PRIVILEGE';
  end if;

  if exists (select 1 from pg_catalog.pg_proc where proowner = runtime_oid)
    or exists (select 1 from pg_catalog.pg_class where relowner = runtime_oid)
    or exists (select 1 from pg_catalog.pg_namespace where nspowner = runtime_oid)
    or exists (select 1 from pg_catalog.pg_database where datdba = runtime_oid)
  then
    raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_OWNERSHIP';
  end if;

  if exists (
    select 1 from pg_catalog.pg_default_acl default_acl
    cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) privilege
    where privilege.grantee = runtime_oid
      and default_acl.defaclobjtype in ('f', 'r', 'S', 'n', 'T')
  ) then
    raise exception 'LWS_P0_2_UNEXPECTED_RUNTIME_DEFAULT_ACL';
  end if;

  for capability in
    select roles.oid, roles.rolname
      from pg_catalog.pg_roles roles
     where roles.rolname = any (array[
       'p0_2_telemetry_checkpoint_controller',
       'p0_2_telemetry_lifecycle_controller',
       'p0_2_telemetry_runtime_writer',
       'p0_2_telemetry_report_reader'
     ]::name[])
  loop
    if capability.rolname is null or exists (
      select 1 from pg_catalog.pg_roles role_state
       where role_state.oid = capability.oid
         and (
           role_state.rolcanlogin or role_state.rolinherit or role_state.rolsuper
           or role_state.rolcreatedb or role_state.rolcreaterole
           or role_state.rolreplication or role_state.rolbypassrls
         )
    ) then
      raise exception 'LWS_P0_2_UNEXPECTED_CAPABILITY_ROLE_ATTRIBUTES: %', capability.rolname;
    end if;

    if (select count(*) from pg_catalog.pg_auth_members where roleid = capability.oid) <> 2
      or exists (select 1 from pg_catalog.pg_auth_members where member = capability.oid)
      or not exists (
        select 1
          from pg_catalog.pg_auth_members membership
          join pg_catalog.pg_roles member_role on member_role.oid = membership.member
          join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
         where membership.roleid = capability.oid
           and member_role.rolname = 'p0_2_telemetry_runtime'
           and grantor_role.rolname = 'postgres'
           and membership.inherit_option
           and not membership.set_option
           and not membership.admin_option
      )
      or not exists (
        select 1
          from pg_catalog.pg_auth_members membership
          join pg_catalog.pg_roles member_role on member_role.oid = membership.member
          join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
         where membership.roleid = capability.oid
           and member_role.rolname = 'postgres'
           and grantor_role.rolname = 'supabase_admin'
           and not membership.inherit_option
           and not membership.set_option
           and membership.admin_option
      )
    then
      raise exception 'LWS_P0_2_UNEXPECTED_CAPABILITY_MEMBERSHIP: %', capability.rolname;
    end if;
  end loop;

  if (
    select count(*) from pg_catalog.pg_roles
     where rolname = any (array[
       'p0_2_telemetry_checkpoint_controller',
       'p0_2_telemetry_lifecycle_controller',
       'p0_2_telemetry_runtime_writer',
       'p0_2_telemetry_report_reader'
     ]::name[])
  ) <> 4 then
    raise exception 'LWS_P0_2_CAPABILITY_ROLE_MISSING';
  end if;

  select oid into strict private_owner_oid from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_private_owner';
  if (
      select count(*)
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.roleid = private_owner_oid
    ) <> 1
    or not exists (
      select 1
        from pg_catalog.pg_auth_members membership
        join pg_catalog.pg_roles member_role on member_role.oid = membership.member
        join pg_catalog.pg_roles grantor_role on grantor_role.oid = membership.grantor
       where membership.roleid = private_owner_oid
         and member_role.rolname = 'postgres'
         and grantor_role.rolname = 'supabase_admin'
         and membership.admin_option
         and not membership.inherit_option
         and not membership.set_option
    ) then
    raise exception 'LWS_P0_2_PRIVATE_OWNER_MEMBERSHIP_NOT_RESTORED';
  end if;

  perform 'LWS_P0_2_FINAL_VALIDATION_PASSED';
end;
$lws_p0_2_final_validation$;
commit;
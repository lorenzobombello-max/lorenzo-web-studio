create function lws_internal.get_website_repository_canonical_durable_operation_id_v1(
	p_website_workspace_id uuid,
	p_website_work_context_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
	v_operation_id uuid;
	v_identity_count bigint;
begin
	select count(distinct (
		operation.repository_external_id,
		operation.repository_node_id,
		operation.repository_owner,
		operation.repository_name
	))
	into v_identity_count
	from public.website_repository_provisioning_operations as operation
	where (
			operation.website_workspace_id = p_website_workspace_id
			or operation.website_work_context_id = p_website_work_context_id
		)
		and (
			operation.repository_external_id is not null
			or operation.repository_node_id is not null
			or operation.external_created_at is not null
		);

	if v_identity_count > 1 then
		raise exception using
			errcode = 'P0001',
			message = 'PRODUCTION_REPOSITORY_RECOVERY_RECONCILIATION_REQUIRED';
	end if;

	select operation.operation_id
	into v_operation_id
	from public.website_repository_provisioning_operations as operation
	where (
			operation.website_workspace_id = p_website_workspace_id
			or operation.website_work_context_id = p_website_work_context_id
		)
		and (
			operation.repository_external_id is not null
			or operation.repository_node_id is not null
			or operation.external_created_at is not null
		)
	order by operation.external_created_at, operation.claimed_at, operation.operation_id
	limit 1;

	return v_operation_id;
end;
$$;

revoke all on function
	lws_internal.get_website_repository_canonical_durable_operation_id_v1(uuid, uuid)
from public, anon, authenticated, service_role;

create or replace function public.claim_production_website_repository_provisioning_v1(
	p_quote_request_id uuid,
	p_website_workspace_id uuid,
	p_website_work_context_id uuid,
	p_idempotency_key uuid,
	p_starter_source text,
	p_starter_version text,
	p_starter_commit_sha text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
	v_work jsonb;
	v_operator public.commercial_operators%rowtype;
	v_request public.quote_requests%rowtype;
	v_workspace public.website_execution_workspaces%rowtype;
begin
	if p_quote_request_id is null
		 or p_website_workspace_id is null
		 or p_website_work_context_id is null then
		raise exception using errcode = '22023', message = 'INVALID_PRODUCTION_REPOSITORY_CLAIM';
	end if;

	v_operator := lws_internal.require_website_repository_owner_v1();

	select request.* into v_request
	from public.quote_requests as request
	where request.id = p_quote_request_id
	for key share;

	v_work := public.get_operator_website_work_v1(p_quote_request_id);

	select workspace.* into v_workspace
	from public.website_execution_workspaces as workspace
	where workspace.website_workspace_id = p_website_workspace_id
		and workspace.website_work_context_id = p_website_work_context_id
		and workspace.quote_request_id = p_quote_request_id
	for update;

	if v_request.id is null
		 or v_request.record_classification <> 'production'
		 or v_request.request_kind <> 'website'
		 or not found
		 or v_work->>'state' <> 'PRE_PROJECT'
		 or v_work->>'mode' <> 'PRE_PROJECT'
		 or (v_work->>'website_work_context_id')::uuid <> p_website_work_context_id
		 or nullif(v_work->>'project_id', '') is not null
		 or (v_work->>'commercially_released')::boolean
		 or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
		 or v_workspace.project_id is not null
		 or v_workspace.workspace_state not in (
			 'PENDING_REPOSITORY', 'REPOSITORY_FAILED', 'REPOSITORY_PROVISIONING',
			 'REPOSITORY_READY'
		 ) then
		raise exception using errcode = '42501', message = 'PRODUCTION_REPOSITORY_CONTEXT_DENIED';
	end if;

	if exists (
		select 1
		from public.website_repository_provisioning_operations as operation
		where operation.actor_id = v_operator.operator_id
			and operation.idempotency_key = p_idempotency_key
	) then
		return public.claim_website_repository_provisioning_v1(
			p_website_workspace_id,
			p_website_work_context_id,
			p_idempotency_key,
			p_starter_source,
			p_starter_version,
			p_starter_commit_sha
		);
	end if;

	if exists (
		select 1
		from public.website_repository_provisioning_operations as operation
		where (
				operation.website_workspace_id = p_website_workspace_id
				or operation.website_work_context_id = p_website_work_context_id
			)
			and (
				operation.repository_external_id is not null
				or operation.repository_node_id is not null
				or operation.external_created_at is not null
			)
	) then
		raise exception using
			errcode = 'P0001',
			message = 'PRODUCTION_REPOSITORY_RECOVERY_REQUIRED';
	end if;

	return public.claim_website_repository_provisioning_v1(
		p_website_workspace_id,
		p_website_work_context_id,
		p_idempotency_key,
		p_starter_source,
		p_starter_version,
		p_starter_commit_sha
	);
end;
$$;

create or replace function public.get_production_website_repository_recovery_authority_v1(
	p_quote_request_id uuid,
	p_website_work_context_id uuid,
	p_website_workspace_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
	v_operator public.commercial_operators%rowtype;
	v_operation public.website_repository_provisioning_operations%rowtype;
	v_context public.website_work_contexts%rowtype;
	v_workspace public.website_execution_workspaces%rowtype;
	v_request public.quote_requests%rowtype;
	v_concept public.website_concepts%rowtype;
	v_operation_id uuid;
begin
	if p_quote_request_id is null
		 or p_website_work_context_id is null
		 or p_website_workspace_id is null then
		raise exception using
			errcode = '22023', message = 'PRODUCTION_REPOSITORY_RECOVERY_IDENTITY_REQUIRED';
	end if;

	v_operator := lws_internal.require_website_repository_owner_v1();

	select context.* into v_context
	from public.website_work_contexts as context
	where context.website_work_context_id = p_website_work_context_id
		and context.quote_request_id = p_quote_request_id;

	select workspace.* into v_workspace
	from public.website_execution_workspaces as workspace
	where workspace.website_workspace_id = p_website_workspace_id
		and workspace.website_work_context_id = p_website_work_context_id
		and workspace.quote_request_id = p_quote_request_id;

	select request.* into v_request
	from public.quote_requests as request
	where request.id = p_quote_request_id;

	select concept.* into v_concept
	from public.website_concepts as concept
	where concept.concept_id = v_context.concept_id
		and concept.quote_request_id = p_quote_request_id;

	if v_context.website_work_context_id is null
		 or v_workspace.website_workspace_id is null
		 or v_request.id is null
		 or v_concept.concept_id is null
		 or v_context.phase <> 'PRE_PROJECT'
		 or v_context.project_id is not null
		 or v_workspace.project_id is not null
		 or v_request.record_classification <> 'production'
		 or v_request.request_kind <> 'website'
		 or v_concept.mode <> 'PRE_PROJECT'
		 or v_concept.commercially_released <> false
		 or v_concept.promoted_project_id is not null
		 or v_workspace.workspace_state <> 'REPOSITORY_FAILED'
		 or v_workspace.repository_external_id is not null
		 or v_workspace.repository_node_id is not null
		 or v_workspace.repository_state is not null
		 or v_workspace.repository_bound_at is not null then
		raise exception using
			errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_MISMATCH';
	end if;

	v_operation_id :=
		lws_internal.get_website_repository_canonical_durable_operation_id_v1(
			p_website_workspace_id,
			p_website_work_context_id
		);

	select operation.* into v_operation
	from public.website_repository_provisioning_operations as operation
	where operation.operation_id = v_operation_id;

	if not found
		 or v_operation.actor_id is distinct from v_operator.operator_id
		 or v_operation.state <> 'TERMINAL_FAILED'
		 or v_operation.failure_code <> 'REPOSITORY_PROVIDER_FAILED'
		 or v_operation.external_created_at is null
		 or v_operation.repository_provider <> 'GITHUB'
		 or v_operation.repository_external_id is null
		 or v_operation.repository_node_id is null
		 or v_operation.repository_owner is null
		 or v_operation.repository_name is null
		 or v_operation.bound_at is not null
		 or v_operation.quarantined_at is not null
		 or v_operation.quarantine_evidence_sha256 is not null then
		raise exception using
			errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_MISMATCH';
	end if;

	return jsonb_build_object(
		'operation_id', v_operation.operation_id,
		'website_work_context_id', v_operation.website_work_context_id,
		'website_workspace_id', v_operation.website_workspace_id,
		'repository_external_id', v_operation.repository_external_id::text,
		'repository_node_id', v_operation.repository_node_id,
		'repository_owner', v_operation.repository_owner,
		'repository_name', v_operation.repository_name,
		'starter_source', v_operation.starter_source,
		'starter_version', v_operation.starter_version,
		'starter_commit_sha', v_operation.starter_commit_sha
	);
end;
$$;

alter function public.finalize_production_website_repository_recovery_v1(
	uuid, uuid, jsonb, uuid, text
) set schema lws_internal;
alter function lws_internal.finalize_production_website_repository_recovery_v1(
	uuid, uuid, jsonb, uuid, text
) rename to finalize_prod_repo_recovery_legacy_v1;

revoke all on function
	lws_internal.finalize_prod_repo_recovery_legacy_v1(
		uuid, uuid, jsonb, uuid, text
	)
from public, anon, authenticated, service_role;

-- Locking-boundary hardening: the canonical-operation identity used to
-- authorize a bind must be revalidated AFTER this function has taken the
-- same operation+workspace row locks that
-- claim_production_website_repository_provisioning_v1 takes, not before.
-- A plain (unlocked) canonical pre-check in the thin public wrapper below
-- is retained purely as a fast, lock-free rejection path for the common
-- case; it is NOT the enforcement boundary. The re-check inserted into
-- this function's body (immediately after the `operation ... for update`
-- and `workspace ... for update` locks are both held, and after the
-- workspace/context/request/concept authority validation succeeds) is the
-- actual authoritative boundary: any concurrent
-- claim_production_website_repository_provisioning_v1 call against the
-- same workspace blocks on the workspace row lock until this transaction
-- commits or rolls back, so no new identity can appear in, or be removed
-- from, the lineage between the canonical resolution below and the
-- mutation that follows later in this same function body. Lock order here
-- (operation row, then workspace row) matches the order already used
-- earlier in this same function, so no lock-order inversion is introduced
-- and no new deadlock risk exists versus the unmodified control flow.
create or replace function lws_internal.finalize_prod_repo_recovery_legacy_v1(
  p_quote_request_id uuid,
  p_operation_id uuid,
  p_verification jsonb,
  p_actor_auth_user_id uuid,
  p_actor_aal text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_context public.website_work_contexts%rowtype;
  v_request public.quote_requests%rowtype;
  v_concept public.website_concepts%rowtype;
  v_external_id bigint;
  v_marker_sha text;
  v_previous_state text;
  v_canonical_operation_id uuid;
begin
  if p_quote_request_id is null
     or p_operation_id is null
     or p_actor_auth_user_id is null
     or jsonb_typeof(p_verification) <> 'object'
     or not p_verification ?& array[
       'operation_id','website_workspace_id','website_work_context_id',
       'repository_external_id','repository_node_id','repository_owner',
       'repository_name','repository_visibility','default_branch',
       'starter_source','starter_version','starter_commit_sha',
       'repository_marker_commit_sha'
     ]
     or exists (
       select 1 from jsonb_object_keys(p_verification) as supplied(key)
       where supplied.key <> all(array[
         'operation_id','website_workspace_id','website_work_context_id',
         'repository_external_id','repository_node_id','repository_owner',
         'repository_name','repository_visibility','default_branch',
         'starter_source','starter_version','starter_commit_sha',
         'repository_marker_commit_sha'
       ])
     )
     or exists (
       select 1 from jsonb_each(p_verification) as supplied(key,value)
       where jsonb_typeof(supplied.value) <> 'string'
     )
     or p_verification->>'repository_external_id' !~ '^[1-9][0-9]{0,15}$'
     or p_verification->>'repository_node_id' !~ '^[A-Za-z0-9_-]{6,255}$'
     or p_verification->>'repository_visibility' <> 'private'
     or p_verification->>'default_branch' <> 'main'
     or p_verification->>'repository_marker_commit_sha' !~
       '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' then
    raise exception using
      errcode = '22023', message = 'INVALID_PRODUCTION_REPOSITORY_RECOVERY_BINDING';
  end if;

  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  end if;
  if p_actor_aal is distinct from 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2_REQUIRED';
  end if;

  select operator.* into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = p_actor_auth_user_id
    and operator.status = 'ACTIVE'
    and operator.role = 'owner'
    and operator.revoked_at is null;
  if not found then
    raise exception using errcode = '42501', message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = p_operation_id
  for update;
  if not found or v_operation.actor_id is distinct from v_operator.operator_id then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_OPERATION_DENIED';
  end if;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = v_operation.website_workspace_id
    and workspace.quote_request_id = p_quote_request_id
  for update;
  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = v_operation.website_work_context_id;
  select request.* into v_request
  from public.quote_requests as request
  where request.id = p_quote_request_id;
  select concept.* into v_concept
  from public.website_concepts as concept
  where concept.concept_id = v_context.concept_id
    and concept.quote_request_id = p_quote_request_id;

  if v_workspace.website_workspace_id is null
     or v_context.website_work_context_id is null
     or v_request.id is null
     or v_concept.concept_id is null
     or v_workspace.website_work_context_id is distinct from v_context.website_work_context_id
     or v_workspace.quote_request_id is distinct from v_context.quote_request_id
     or v_context.phase <> 'PRE_PROJECT'
     or v_context.project_id is not null
     or v_workspace.project_id is not null
     or v_request.record_classification <> 'production'
     or v_request.request_kind <> 'website'
     or v_concept.mode <> 'PRE_PROJECT'
     or v_concept.commercially_released <> false
     or v_concept.promoted_project_id is not null then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_MISMATCH';
  end if;

  -- Authoritative locking-boundary re-check (see comment above this
  -- function). Both the operation row and the workspace row are already
  -- held FOR UPDATE at this point, so this resolution cannot be
  -- invalidated by a concurrent claim/finalize before the mutation below.
  v_canonical_operation_id :=
    lws_internal.get_website_repository_canonical_durable_operation_id_v1(
      v_operation.website_workspace_id,
      v_operation.website_work_context_id
    );
  if v_canonical_operation_id is distinct from p_operation_id then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_OPERATION_DENIED';
  end if;

  v_external_id := (p_verification->>'repository_external_id')::bigint;
  v_marker_sha := p_verification->>'repository_marker_commit_sha';
  if p_verification->>'operation_id' is distinct from v_operation.operation_id::text
     or p_verification->>'website_workspace_id' is distinct from v_operation.website_workspace_id::text
     or p_verification->>'website_work_context_id' is distinct from v_operation.website_work_context_id::text
     or v_external_id is distinct from v_operation.repository_external_id
     or p_verification->>'repository_node_id' is distinct from v_operation.repository_node_id
     or p_verification->>'repository_owner' is distinct from v_operation.repository_owner
     or p_verification->>'repository_name' is distinct from v_operation.repository_name
     or p_verification->>'starter_source' is distinct from v_operation.starter_source
     or p_verification->>'starter_version' is distinct from v_operation.starter_version
     or p_verification->>'starter_commit_sha' is distinct from v_operation.starter_commit_sha then
    raise exception using
      errcode = 'P0001', message = 'PRODUCTION_REPOSITORY_RECOVERY_BINDING_MISMATCH';
  end if;

  if v_operation.state = 'BOUND' then
    if v_workspace.workspace_state <> 'REPOSITORY_READY'
       or v_workspace.repository_state <> 'BOUND'
       or v_workspace.repository_external_id is distinct from v_external_id
       or v_workspace.repository_node_id is distinct from p_verification->>'repository_node_id'
       or v_workspace.repository_marker_commit_sha is distinct from v_marker_sha
       or v_workspace.last_commit_sha is distinct from v_marker_sha then
      raise exception using
        errcode = 'P0001', message = 'PRODUCTION_REPOSITORY_RECOVERY_BINDING_MISMATCH';
    end if;
    return lws_internal.website_repository_operation_result_v1(v_operation, 'REPLAY');
  end if;

  if v_operation.state <> 'TERMINAL_FAILED'
     or v_operation.failure_code <> 'REPOSITORY_PROVIDER_FAILED'
     or v_operation.external_created_at is null
     or v_operation.repository_external_id is null
     or v_operation.repository_node_id is null
     or v_operation.bound_at is not null
     or v_operation.quarantined_at is not null
     or v_operation.quarantine_evidence_sha256 is not null
     or v_workspace.workspace_state <> 'REPOSITORY_FAILED'
     or v_workspace.repository_external_id is not null
     or v_workspace.repository_node_id is not null
     or v_workspace.repository_state is not null
     or v_workspace.repository_bound_at is not null then
    raise exception using
      errcode = 'P0001', message = 'PRODUCTION_REPOSITORY_RECOVERY_TRANSITION_INVALID';
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  v_previous_state := v_operation.state;
  update public.website_execution_workspaces
  set workspace_state = 'REPOSITORY_READY',
      repository_owner = v_operation.repository_owner,
      repository_name = v_operation.repository_name,
      repository_external_id = v_operation.repository_external_id,
      repository_node_id = v_operation.repository_node_id,
      repository_visibility = 'private',
      repository_state = 'BOUND',
      default_branch = 'main',
      starter_source = v_operation.starter_source,
      starter_version = v_operation.starter_version,
      starter_commit_sha = v_operation.starter_commit_sha,
      repository_marker_commit_sha = v_marker_sha,
      repository_bound_at = clock_timestamp(),
      last_commit_sha = v_marker_sha,
      last_commit_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where website_workspace_id = v_operation.website_workspace_id;

  update public.website_repository_provisioning_operations
  set state = 'BOUND', failure_code = null, retry_at = null,
      retry_action = null, provider_retry_after_at = null,
      bound_at = clock_timestamp(), updated_at = clock_timestamp()
  where operation_id = p_operation_id
  returning * into v_operation;

  insert into public.website_repository_provisioning_events(
    operation_id, website_workspace_id, website_work_context_id, actor_id,
    request_fingerprint, event_type, previous_state, new_state,
    repository_provider, repository_owner, repository_name,
    repository_external_id, starter_source, starter_version,
    starter_commit_sha, attempt_number, result_code
  ) values (
    v_operation.operation_id, v_operation.website_workspace_id,
    v_operation.website_work_context_id, v_operator.operator_id,
    v_operation.request_fingerprint, 'REPOSITORY_BOUND', v_previous_state,
    'BOUND', v_operation.repository_provider, v_operation.repository_owner,
    v_operation.repository_name, v_operation.repository_external_id,
    v_operation.starter_source, v_operation.starter_version,
    v_operation.starter_commit_sha, v_operation.attempt_count, 'BOUND'
  );
  perform set_config('lws.website_repository_command', '', true);
  return lws_internal.website_repository_operation_result_v1(v_operation, 'BOUND');
exception when others then
  perform set_config('lws.website_repository_command', '', true);
  raise;
end;
$$;

-- Thin public entrypoint. Performs an unlocked, lock-free canonical
-- pre-check purely to give callers a fast, informative rejection before
-- any row lock is taken; it is advisory only. The authoritative,
-- race-safe re-check lives inside
-- lws_internal.finalize_prod_repo_recovery_legacy_v1 above, executed only
-- after that function holds the operation and workspace row locks (see
-- the comment on that function for the full argument).
create function public.finalize_production_website_repository_recovery_v1(
  p_quote_request_id uuid,
  p_operation_id uuid,
  p_verification jsonb,
  p_actor_auth_user_id uuid,
  p_actor_aal text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_canonical_operation_id uuid;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  end if;

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = p_operation_id;

  if not found then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_OPERATION_DENIED';
  end if;

  v_canonical_operation_id :=
    lws_internal.get_website_repository_canonical_durable_operation_id_v1(
      v_operation.website_workspace_id,
      v_operation.website_work_context_id
    );

  if v_canonical_operation_id is distinct from p_operation_id then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_OPERATION_DENIED';
  end if;

  return lws_internal.finalize_prod_repo_recovery_legacy_v1(
    p_quote_request_id,
    p_operation_id,
    p_verification,
    p_actor_auth_user_id,
    p_actor_aal
  );
end;
$$;

alter function public.get_website_execution_workspace_v3(uuid)
	set schema lws_internal;
alter function lws_internal.get_website_execution_workspace_v3(uuid)
	rename to get_website_execution_workspace_v3_legacy_lineage_v1;

revoke all on function
	lws_internal.get_website_execution_workspace_v3_legacy_lineage_v1(uuid)
from public, anon, authenticated, service_role;

create function public.get_website_execution_workspace_v3(
	p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
	v_result jsonb;
	v_workspace public.website_execution_workspaces%rowtype;
	v_operation public.website_repository_provisioning_operations%rowtype;
	v_operation_id uuid;
	v_operation_state text;
	v_failure_category text;
	v_recovery_guidance text;
	v_binding_verified boolean := false;
	v_owner_eligible boolean := false;
	v_workspace_result jsonb;
begin
	v_result := lws_internal.get_website_execution_workspace_v3_legacy_lineage_v1(
		p_quote_request_id
	);

	if v_result->'workspace' is null
		 or not exists (
			 select 1 from public.quote_requests as request
			 where request.id = p_quote_request_id
				 and request.record_classification = 'production'
				 and request.request_kind = 'website'
		 ) then
		return v_result;
	end if;

	select workspace.* into v_workspace
	from public.website_execution_workspaces as workspace
	where workspace.quote_request_id = p_quote_request_id;

	v_operation_id :=
		lws_internal.get_website_repository_canonical_durable_operation_id_v1(
			v_workspace.website_workspace_id,
			v_workspace.website_work_context_id
		);

	if v_operation_id is null then
		return v_result;
	end if;

	select operation.* into v_operation
	from public.website_repository_provisioning_operations as operation
	where operation.operation_id = v_operation_id;

	v_operation_state := case
		when v_operation.state = 'BOUND' then 'COMPLETE'
		else v_operation.state
	end;
	v_failure_category := case
		when v_operation_state = 'QUARANTINED' then 'QUARANTINED'
		when v_operation_state = 'BLOCKED' then 'BLOCKED'
		when v_operation_state = 'TERMINAL_FAILED' then 'TERMINAL'
		when v_operation_state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED') then 'RETRYABLE'
		else null
	end;
	v_recovery_guidance := case
		when v_operation_state = 'QUARANTINED' then 'RECONCILIATION_REQUIRED'
		when v_operation_state in ('BLOCKED', 'TERMINAL_FAILED') then 'CONTACT_OWNER'
		when v_operation_state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED') then 'REFRESH_LATER'
		when v_operation_state = 'COMPLETE' then null
		else 'WAIT'
	end;
	v_binding_verified :=
		coalesce(
			(v_result #>> '{workspace,capabilities,project_files_read}')::boolean,
			false
		)
		and v_workspace.workspace_state = 'REPOSITORY_READY'
		and v_workspace.repository_state = 'BOUND'
		and v_workspace.binding_revision >= 1
		and v_workspace.default_branch is not null
		and v_operation.state = 'BOUND'
		and v_operation.repository_provider is not distinct from v_workspace.repository_provider
		and v_operation.repository_owner is not distinct from v_workspace.repository_owner
		and v_operation.repository_name is not distinct from v_workspace.repository_name
		and v_operation.repository_external_id is not distinct from v_workspace.repository_external_id
		and v_operation.repository_node_id is not distinct from v_workspace.repository_node_id;

	select exists (
		select 1 from public.commercial_operators as operator
		where operator.auth_user_id = auth.uid()
			and operator.status = 'ACTIVE'
			and operator.role = 'owner'
			and operator.revoked_at is null
	) into v_owner_eligible;

	v_workspace_result := (v_result->'workspace') || jsonb_build_object(
		'repository_operation_state', v_operation_state,
		'repository_failure_category', v_failure_category,
		'repository_recovery_guidance', v_recovery_guidance,
		'capabilities', coalesce(v_result #> '{workspace,capabilities}', '{}'::jsonb) ||
			jsonb_build_object('project_files_read', v_binding_verified and v_owner_eligible)
	);

	return (v_result - 'workspace') || jsonb_build_object(
		'contract_version', 3,
		'workspace', v_workspace_result
	);
end;
$$;

create or replace function public.get_website_execution_workspace_v5(
	p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
	v_v4 jsonb;
	v_workspace public.website_execution_workspaces%rowtype;
	v_operation public.website_repository_provisioning_operations%rowtype;
	v_operation_id uuid;
	v_retry_allowed boolean := false;
	v_recovery_required boolean := false;
begin
	v_v4 := public.get_website_execution_workspace_v4(p_quote_request_id);

	select workspace.* into v_workspace
	from public.website_execution_workspaces as workspace
	join public.quote_requests as request on request.id = workspace.quote_request_id
	where workspace.quote_request_id = p_quote_request_id
		and request.record_classification = 'production'
		and request.request_kind = 'website';

	if found and not (
		v_workspace.workspace_state = 'REPOSITORY_READY'
		and v_workspace.repository_state = 'BOUND'
	) then
		v_operation_id :=
			lws_internal.get_website_repository_canonical_durable_operation_id_v1(
				v_workspace.website_workspace_id,
				v_workspace.website_work_context_id
			);

		if v_operation_id is not null then
			select operation.* into v_operation
			from public.website_repository_provisioning_operations as operation
			where operation.operation_id = v_operation_id;
			v_recovery_required := v_operation.state = 'TERMINAL_FAILED';
		else
			select operation.* into v_operation
			from public.website_repository_provisioning_operations as operation
			where operation.website_workspace_id = v_workspace.website_workspace_id
				and operation.website_work_context_id = v_workspace.website_work_context_id
			order by operation.updated_at desc, operation.operation_id desc
			limit 1;
			v_retry_allowed := found and v_operation.state = 'TERMINAL_FAILED';
		end if;
	end if;

	return jsonb_set(
		jsonb_set(
			jsonb_set(v_v4, '{contract_version}', '5'::jsonb),
			'{workspace,capabilities}',
			coalesce(v_v4 #> '{workspace,capabilities}', '{}'::jsonb) ||
				jsonb_build_object(
					'repository_retry_allowed', v_retry_allowed,
					'repository_recovery_required', v_recovery_required
				),
			false
		),
		'{workspace,repository_recovery_operation_id}',
		case when v_recovery_required then to_jsonb(v_operation.operation_id::text)
			else 'null'::jsonb end,
		true
	);
end;
$$;

revoke all on function
	public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text),
	public.get_production_website_repository_recovery_authority_v1(uuid,uuid,uuid),
	public.finalize_production_website_repository_recovery_v1(uuid,uuid,jsonb,uuid,text),
	public.get_website_execution_workspace_v3(uuid),
	public.get_website_execution_workspace_v5(uuid)
from public, anon, authenticated, service_role;

grant execute on function
	public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text),
	public.get_production_website_repository_recovery_authority_v1(uuid,uuid,uuid),
	public.get_website_execution_workspace_v3(uuid),
	public.get_website_execution_workspace_v5(uuid)
to authenticated;

grant execute on function
	public.finalize_production_website_repository_recovery_v1(uuid,uuid,jsonb,uuid,text)
to service_role;

comment on function lws_internal.get_website_repository_canonical_durable_operation_id_v1(
	uuid, uuid
) is 'Returns the sole durable repository operation in a workspace lineage and fails closed when repository identities conflict.';
comment on function public.claim_production_website_repository_provisioning_v1(
	uuid, uuid, uuid, uuid, text, text, text
) is 'OWNER+AAL2 production claim authority; exact idempotent replay is preserved while any durable lineage identity forbids fresh create.';
comment on function public.get_production_website_repository_recovery_authority_v1(
	uuid, uuid, uuid
) is 'Read-only OWNER+AAL2 authority for the canonical durable production repository operation across complete lineage.';
comment on function public.finalize_production_website_repository_recovery_v1(
	uuid, uuid, jsonb, uuid, text
) is 'Service-only finalizer constrained to the canonical durable recovery operation; creates no repository.';
comment on function public.get_website_execution_workspace_v3(uuid) is
	'Workspace projection where canonical durable or bound production repository identity dominates later identity-free history.';
comment on function public.get_website_execution_workspace_v5(uuid) is
	'Workspace projection with lineage-wide recovery detection, ambiguity closure, and mutually exclusive retry/recovery capabilities.';

-- Project Files READ/WRITE timestamp-shadowing closure: both gates
-- previously resolved repository authority via
-- `order by updated_at desc, operation_id desc limit 1`, which lets a
-- later-touched TERMINAL_FAILED historical operation (identity-free or
-- not) shadow the canonical BOUND operation purely because its
-- updated_at happens to be newer. Both gates below instead resolve the
-- deterministic canonical durable operation for the workspace/context
-- lineage (fails closed on conflicting durable identities), then verify
-- that operation is BOUND and matches the workspace's live binding before
-- issuing a lease. READ and WRITE use identical binding semantics.
create or replace function public.acquire_website_project_files_read_v1(
  p_quote_request_id uuid,
  p_read_kind text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_now timestamptz;
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_work jsonb;
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_canonical_operation_id uuid;
  v_rate_limit integer;
  v_rate_count bigint;
  v_active_leases bigint;
  v_lease lws_internal.website_project_files_read_leases%rowtype;
begin
  if p_quote_request_id is null then
    raise exception using
      errcode = '22023', message = 'QUOTE_REQUEST_ID_REQUIRED';
  end if;
  if p_read_kind is null or p_read_kind not in ('DIRECTORY', 'FILE') then
    raise exception using
      errcode = '22023', message = 'PROJECT_FILES_READ_KIND_INVALID';
  end if;
  if v_subject is null
     or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.*
  into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject
  for update;

  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role <> 'owner'
     or v_operator.revoked_at is not null then
    raise exception using
      errcode = '42501', message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;

  perform lws_internal.assert_operator_aal2_v1();
  v_work := public.get_operator_website_work_v1(p_quote_request_id);

  if v_work->>'state' not in ('PRE_PROJECT', 'OFFICIAL_PROJECT')
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
     or nullif(v_work->>'website_work_context_id', '') is null then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  select context.*
  into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id =
        (v_work->>'website_work_context_id')::uuid
    and context.quote_request_id = p_quote_request_id
  for update;

  if not found
     or v_context.phase is distinct from v_work->>'mode'
     or v_context.concept_id is distinct from
        nullif(v_work->>'concept_id', '')::uuid
     or v_context.project_id is distinct from
        nullif(v_work->>'project_id', '')::uuid then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  select workspace.*
  into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = v_context.website_work_context_id
    and workspace.quote_request_id = p_quote_request_id
    and workspace.project_id is not distinct from v_context.project_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_FOUND';
  end if;
  if v_workspace.workspace_state <> 'REPOSITORY_READY' then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_NOT_READY';
  end if;
  if v_workspace.repository_provider <> 'GITHUB'
     or v_workspace.repository_owner is null
     or v_workspace.repository_name is null
     or v_workspace.repository_external_id is null
     or v_workspace.repository_node_id is null
     or v_workspace.repository_state <> 'BOUND'
     or v_workspace.repository_visibility <> 'private'
     or v_workspace.repository_marker_commit_sha is null
     or v_workspace.repository_bound_at is null
     or v_workspace.binding_revision < 1
     or v_workspace.default_branch is null then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_BINDING_MISSING';
  end if;

  v_canonical_operation_id :=
    lws_internal.get_website_repository_canonical_durable_operation_id_v1(
      v_workspace.website_workspace_id,
      v_context.website_work_context_id
    );

  select operation.*
  into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = v_canonical_operation_id
  for update;

  if not found
     or v_operation.state <> 'BOUND'
     or v_operation.repository_provider is distinct from
        v_workspace.repository_provider
     or v_operation.repository_owner is distinct from
        v_workspace.repository_owner
     or v_operation.repository_name is distinct from
        v_workspace.repository_name
     or v_operation.repository_external_id is distinct from
        v_workspace.repository_external_id
     or v_operation.repository_node_id is distinct from
        v_workspace.repository_node_id then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_BINDING_STALE';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('website-project-files:' || v_subject::text, 0)
  );
  v_now := clock_timestamp();

  delete from lws_internal.website_project_files_read_acquisitions
  where acquired_at <= v_now - interval '5 minutes';

  select count(*)
  into v_active_leases
  from lws_internal.website_project_files_read_leases as lease
  where lease.actor_auth_user_id = v_subject
    and lease.released_at is null
    and lease.expires_at > v_now;

  if v_active_leases >= 4 then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_CONCURRENCY_LIMITED';
  end if;

  v_rate_limit := case p_read_kind when 'DIRECTORY' then 30 else 10 end;
  select count(*)
  into v_rate_count
  from lws_internal.website_project_files_read_acquisitions as acquisition
  where acquisition.actor_auth_user_id = v_subject
    and acquisition.website_work_context_id = v_context.website_work_context_id
    and acquisition.read_kind = p_read_kind
    and acquisition.acquired_at > v_now - interval '60 seconds'
    and acquisition.acquired_at <= v_now;

  if v_rate_count >= v_rate_limit then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_RATE_LIMITED';
  end if;

  insert into lws_internal.website_project_files_read_acquisitions(
    actor_operator_id, actor_auth_user_id, website_work_context_id,
    read_kind, acquired_at
  ) values (
    v_operator.operator_id, v_subject, v_context.website_work_context_id,
    p_read_kind, v_now
  );

  insert into lws_internal.website_project_files_read_leases(
    actor_operator_id, actor_auth_user_id, quote_request_id,
    website_work_context_id, website_workspace_id, read_kind,
    binding_revision, repository_provider, repository_owner,
    repository_name, repository_external_id, repository_node_id,
    default_branch, repository_ref, ref_label, marker_operation_id,
    acquired_at, expires_at
  ) values (
    v_operator.operator_id, v_subject, p_quote_request_id,
    v_context.website_work_context_id, v_workspace.website_workspace_id,
    p_read_kind, v_workspace.binding_revision,
    v_workspace.repository_provider, v_workspace.repository_owner,
    v_workspace.repository_name, v_workspace.repository_external_id,
    v_workspace.repository_node_id, v_workspace.default_branch,
    'heads/' || v_workspace.default_branch, v_workspace.default_branch,
    v_operation.operation_id, v_now, v_now + interval '15 seconds'
  ) returning * into v_lease;

  return jsonb_build_object(
    'leaseId', v_lease.lease_id,
    'actorAuthUserId', v_lease.actor_auth_user_id,
    'quoteRequestId', v_lease.quote_request_id,
    'websiteWorkContextId', v_lease.website_work_context_id,
    'websiteWorkspaceId', v_lease.website_workspace_id,
    'bindingRevision', v_lease.binding_revision,
    'repositoryProvider', v_lease.repository_provider,
    'repositoryOwner', v_lease.repository_owner,
    'repositoryName', v_lease.repository_name,
    'repositoryExternalId', v_lease.repository_external_id::text,
    'repositoryNodeId', v_lease.repository_node_id,
    'defaultBranch', v_lease.default_branch,
    'repositoryRef', v_lease.repository_ref,
    'refLabel', v_lease.ref_label,
    'markerOperationId', v_lease.marker_operation_id,
    'expiresAt', v_lease.expires_at
  );
end;
$$;

comment on function public.acquire_website_project_files_read_v1(uuid, text) is
  'Caller-JWT ACTIVE OWNER+AAL2 project-file read authority acquisition bound to the lineage-wide canonical durable operation.';

create or replace function public.acquire_website_project_files_write_v1(
  p_quote_request_id uuid,
  p_path text,
  p_expected_commit_sha text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_now timestamptz;
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_work jsonb;
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_canonical_operation_id uuid;
  v_rate_count bigint;
  v_active_leases bigint;
  v_existing lws_internal.website_project_files_write_leases%rowtype;
  v_lease lws_internal.website_project_files_write_leases%rowtype;
begin
  if p_quote_request_id is null then
    raise exception using
      errcode = '22023', message = 'QUOTE_REQUEST_ID_REQUIRED';
  end if;
  if p_path is null or btrim(p_path) = '' then
    raise exception using
      errcode = '22023', message = 'INVALID_PROJECT_PATH';
  end if;
  if p_expected_commit_sha is null
     or p_expected_commit_sha !~ '^[0-9a-f]{40}$' then
    raise exception using
      errcode = '22023', message = 'PROJECT_FILES_STALE_REVISION';
  end if;
  if p_idempotency_key is null then
    raise exception using
      errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if v_subject is null
     or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.*
  into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject
  for update;

  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role <> 'owner'
     or v_operator.revoked_at is not null then
    raise exception using
      errcode = '42501', message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;

  perform lws_internal.assert_operator_aal2_v1();
  v_work := public.get_operator_website_work_v1(p_quote_request_id);

  if v_work->>'state' not in ('PRE_PROJECT', 'OFFICIAL_PROJECT')
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
     or nullif(v_work->>'website_work_context_id', '') is null then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  select context.*
  into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id =
        (v_work->>'website_work_context_id')::uuid
    and context.quote_request_id = p_quote_request_id
  for update;

  if not found
     or v_context.phase is distinct from v_work->>'mode'
     or v_context.concept_id is distinct from
        nullif(v_work->>'concept_id', '')::uuid
     or v_context.project_id is distinct from
        nullif(v_work->>'project_id', '')::uuid then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  select workspace.*
  into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = v_context.website_work_context_id
    and workspace.quote_request_id = p_quote_request_id
    and workspace.project_id is not distinct from v_context.project_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_FOUND';
  end if;
  if v_workspace.workspace_state <> 'REPOSITORY_READY' then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_NOT_READY';
  end if;
  if v_workspace.repository_provider <> 'GITHUB'
     or v_workspace.repository_owner is null
     or v_workspace.repository_name is null
     or v_workspace.repository_external_id is null
     or v_workspace.repository_node_id is null
     or v_workspace.repository_state <> 'BOUND'
     or v_workspace.repository_visibility <> 'private'
     or v_workspace.repository_marker_commit_sha is null
     or v_workspace.repository_bound_at is null
     or v_workspace.binding_revision < 1
     or v_workspace.default_branch is null then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_BINDING_MISSING';
  end if;

  v_canonical_operation_id :=
    lws_internal.get_website_repository_canonical_durable_operation_id_v1(
      v_workspace.website_workspace_id,
      v_context.website_work_context_id
    );

  select operation.*
  into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = v_canonical_operation_id
  for update;

  if not found
     or v_operation.state <> 'BOUND'
     or v_operation.repository_provider is distinct from
        v_workspace.repository_provider
     or v_operation.repository_owner is distinct from
        v_workspace.repository_owner
     or v_operation.repository_name is distinct from
        v_workspace.repository_name
     or v_operation.repository_external_id is distinct from
        v_workspace.repository_external_id
     or v_operation.repository_node_id is distinct from
        v_workspace.repository_node_id then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_BINDING_STALE';
  end if;

  if v_workspace.last_commit_sha is not null
     and v_workspace.last_commit_sha <> p_expected_commit_sha then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('website-project-files-write:' || v_subject::text, 0)
  );
  v_now := clock_timestamp();

  delete from lws_internal.website_project_files_write_acquisitions
  where acquired_at <= v_now - interval '5 minutes';

  select lease.*
  into v_existing
  from lws_internal.website_project_files_write_leases as lease
  where lease.actor_auth_user_id = v_subject
    and lease.website_work_context_id = v_context.website_work_context_id
    and lease.idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.quote_request_id <> p_quote_request_id
       or v_existing.write_path <> p_path
       or v_existing.expected_commit_sha <> p_expected_commit_sha
       or v_existing.website_workspace_id <> v_workspace.website_workspace_id
       or v_existing.binding_revision <> v_workspace.binding_revision
       or v_existing.repository_provider <> v_workspace.repository_provider
       or v_existing.repository_owner <> v_workspace.repository_owner
       or v_existing.repository_name <> v_workspace.repository_name
       or v_existing.repository_external_id <> v_workspace.repository_external_id
       or v_existing.repository_node_id <> v_workspace.repository_node_id
       or v_existing.marker_operation_id <> v_operation.operation_id then
      raise exception using
        errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
    end if;
    if v_existing.released_at is null and v_existing.expires_at > v_now then
      return jsonb_build_object(
        'leaseId', v_existing.lease_id,
        'actorAuthUserId', v_existing.actor_auth_user_id,
        'quoteRequestId', v_existing.quote_request_id,
        'websiteWorkContextId', v_existing.website_work_context_id,
        'websiteWorkspaceId', v_existing.website_workspace_id,
        'bindingRevision', v_existing.binding_revision,
        'repositoryProvider', v_existing.repository_provider,
        'repositoryOwner', v_existing.repository_owner,
        'repositoryName', v_existing.repository_name,
        'repositoryExternalId', v_existing.repository_external_id::text,
        'repositoryNodeId', v_existing.repository_node_id,
        'defaultBranch', v_existing.default_branch,
        'repositoryRef', v_existing.repository_ref,
        'refLabel', v_existing.ref_label,
        'markerOperationId', v_existing.marker_operation_id,
        'expiresAt', v_existing.expires_at
      );
    end if;
    if v_existing.finalized_at is not null then
      return jsonb_build_object(
        'leaseId', v_existing.lease_id,
        'actorAuthUserId', v_existing.actor_auth_user_id,
        'quoteRequestId', v_existing.quote_request_id,
        'websiteWorkContextId', v_existing.website_work_context_id,
        'websiteWorkspaceId', v_existing.website_workspace_id,
        'bindingRevision', v_existing.binding_revision,
        'repositoryProvider', v_existing.repository_provider,
        'repositoryOwner', v_existing.repository_owner,
        'repositoryName', v_existing.repository_name,
        'repositoryExternalId', v_existing.repository_external_id::text,
        'repositoryNodeId', v_existing.repository_node_id,
        'defaultBranch', v_existing.default_branch,
        'repositoryRef', v_existing.repository_ref,
        'refLabel', v_existing.ref_label,
        'markerOperationId', v_existing.marker_operation_id,
        'expiresAt', v_existing.expires_at
      );
    end if;
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
  end if;

  select count(*)
  into v_active_leases
  from lws_internal.website_project_files_write_leases as lease
  where lease.actor_auth_user_id = v_subject
    and lease.released_at is null
    and lease.expires_at > v_now;

  if v_active_leases >= 2 then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_CONCURRENCY_LIMITED';
  end if;

  select count(*)
  into v_rate_count
  from lws_internal.website_project_files_write_acquisitions as acquisition
  where acquisition.actor_auth_user_id = v_subject
    and acquisition.website_work_context_id = v_context.website_work_context_id
    and acquisition.acquired_at > v_now - interval '60 seconds'
    and acquisition.acquired_at <= v_now;

  if v_rate_count >= 10 then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_RATE_LIMITED';
  end if;

  insert into lws_internal.website_project_files_write_acquisitions(
    actor_operator_id,
    actor_auth_user_id,
    quote_request_id,
    website_work_context_id,
    write_path,
    expected_commit_sha,
    idempotency_key,
    acquired_at
  ) values (
    v_operator.operator_id,
    v_subject,
    p_quote_request_id,
    v_context.website_work_context_id,
    p_path,
    p_expected_commit_sha,
    p_idempotency_key,
    v_now
  );

  insert into lws_internal.website_project_files_write_leases(
    actor_operator_id,
    actor_auth_user_id,
    quote_request_id,
    website_work_context_id,
    website_workspace_id,
    binding_revision,
    repository_provider,
    repository_owner,
    repository_name,
    repository_external_id,
    repository_node_id,
    default_branch,
    repository_ref,
    ref_label,
    marker_operation_id,
    write_path,
    expected_commit_sha,
    idempotency_key,
    acquired_at,
    expires_at
  ) values (
    v_operator.operator_id,
    v_subject,
    p_quote_request_id,
    v_context.website_work_context_id,
    v_workspace.website_workspace_id,
    v_workspace.binding_revision,
    v_workspace.repository_provider,
    v_workspace.repository_owner,
    v_workspace.repository_name,
    v_workspace.repository_external_id,
    v_workspace.repository_node_id,
    v_workspace.default_branch,
    'heads/' || v_workspace.default_branch,
    v_workspace.default_branch,
    v_operation.operation_id,
    p_path,
    p_expected_commit_sha,
    p_idempotency_key,
    v_now,
    v_now + interval '30 seconds'
  ) returning * into v_lease;

  return jsonb_build_object(
    'leaseId', v_lease.lease_id,
    'actorAuthUserId', v_lease.actor_auth_user_id,
    'quoteRequestId', v_lease.quote_request_id,
    'websiteWorkContextId', v_lease.website_work_context_id,
    'websiteWorkspaceId', v_lease.website_workspace_id,
    'bindingRevision', v_lease.binding_revision,
    'repositoryProvider', v_lease.repository_provider,
    'repositoryOwner', v_lease.repository_owner,
    'repositoryName', v_lease.repository_name,
    'repositoryExternalId', v_lease.repository_external_id::text,
    'repositoryNodeId', v_lease.repository_node_id,
    'defaultBranch', v_lease.default_branch,
    'repositoryRef', v_lease.repository_ref,
    'refLabel', v_lease.ref_label,
    'markerOperationId', v_lease.marker_operation_id,
    'expiresAt', v_lease.expires_at
  );
end;
$$;

comment on function public.acquire_website_project_files_write_v1(
  uuid, text, text, uuid
) is 'Caller-JWT ACTIVE OWNER+AAL2 project-file write authority acquisition bound to the lineage-wide canonical durable operation.';

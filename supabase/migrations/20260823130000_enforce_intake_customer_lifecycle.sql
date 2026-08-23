create function public.enforce_quote_request_intake_lifecycle_access_v1(
  p_access_state text,
  p_access_token_expires_at timestamptz,
  p_server_now timestamptz
)
returns void
language plpgsql
stable
set search_path = public, pg_catalog
as $$
declare
  v_effective_access text;
begin
  v_effective_access := public.resolve_quote_request_intake_effective_access_v1(
    p_access_state,
    p_access_token_expires_at,
    p_server_now
  );

  if v_effective_access = 'ACTIVE' then
    return;
  end if;

  raise exception using
    errcode = 'P0001',
    message = case v_effective_access
      when 'INTERRUPTED' then 'INTAKE_ACCESS_INTERRUPTED'
      when 'EXPIRED' then 'INTAKE_ACCESS_EXPIRED'
      when 'CANCELLED' then 'INTAKE_ACCESS_CANCELLED'
    end;
end;
$$;

create function public.inspect_quote_request_intake_customer_access_v1(
  p_access_token_hash text
)
returns table (effective_access text)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select public.resolve_quote_request_intake_effective_access_v1(
    intake.access_state,
    intake.access_token_expires_at,
    clock_timestamp()
  )
  from public.quote_request_intakes as intake
  where p_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.access_token_hash = p_access_token_hash
    and intake.access_token_revoked_at is null
  limit 1
$$;

alter function public.inspect_quote_request_intake(text)
  rename to inspect_quote_request_intake_phase2b_predecessor;

create function public.inspect_quote_request_intake(p_access_token_hash text)
returns table (
  intake_id uuid,
  intake_status text,
  quote_request_created_at timestamptz,
  name text,
  company text,
  email text,
  phone text,
  website_type text,
  budget text,
  timing text,
  description text,
  started_at timestamptz,
  submitted_at timestamptz,
  reviewed_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for share;

  if not found or v_intake.access_token_revoked_at is not null then
    return query
      select * from public.inspect_quote_request_intake_phase2b_predecessor(
        p_access_token_hash
      );
    return;
  end if;

  perform public.enforce_quote_request_intake_lifecycle_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    clock_timestamp()
  );

  return query
    select * from public.inspect_quote_request_intake_phase2b_predecessor(
      p_access_token_hash
    );
end;
$$;

alter function public.inspect_quote_request_intake_details(text)
  rename to inspect_quote_request_intake_details_phase2b_predecessor;

create function public.inspect_quote_request_intake_details(p_access_token_hash text)
returns table (
  intake_id uuid,
  intake_status text,
  quote_request_created_at timestamptz,
  name text,
  company text,
  email text,
  phone text,
  website_type text,
  budget text,
  timing text,
  description text,
  started_at timestamptz,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  intake_data jsonb
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for share;

  if not found or v_intake.access_token_revoked_at is not null then
    return query
      select * from public.inspect_quote_request_intake_details_phase2b_predecessor(
        p_access_token_hash
      );
    return;
  end if;

  perform public.enforce_quote_request_intake_lifecycle_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    clock_timestamp()
  );

  return query
    select * from public.inspect_quote_request_intake_details_phase2b_predecessor(
      p_access_token_hash
    );
end;
$$;

alter function public.update_quote_request_intake(text, text, jsonb, text, timestamptz)
  rename to update_quote_request_intake_phase2b_predecessor;

create function public.update_quote_request_intake(
  p_access_token_hash text,
  p_action text,
  p_data jsonb,
  p_admin_access_token_hash text default null,
  p_admin_access_token_expires_at timestamptz default null
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  submitted_at timestamptz,
  updated_at timestamptz,
  notification_job_id uuid,
  notification_job_status text
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for update;

  if not found or v_intake.access_token_revoked_at is not null then
    return query
      select * from public.update_quote_request_intake_phase2b_predecessor(
        p_access_token_hash,
        p_action,
        p_data,
        p_admin_access_token_hash,
        p_admin_access_token_expires_at
      );
    return;
  end if;

  perform public.enforce_quote_request_intake_lifecycle_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    clock_timestamp()
  );

  return query
    select * from public.update_quote_request_intake_phase2b_predecessor(
      p_access_token_hash,
      p_action,
      p_data,
      p_admin_access_token_hash,
      p_admin_access_token_expires_at
    );
end;
$$;

alter function public.save_quote_request_intake_draft_v2(text, bigint, jsonb, jsonb)
  rename to save_quote_request_intake_draft_v2_phase2b_predecessor;

create function public.save_quote_request_intake_draft_v2(
  p_access_token_hash text,
  p_expected_revision bigint,
  p_legacy_data jsonb,
  p_evidence_data jsonb
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  updated_at timestamptz,
  draft_revision bigint
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for update;

  if not found or v_intake.access_token_revoked_at is not null then
    return query
      select * from public.save_quote_request_intake_draft_v2_phase2b_predecessor(
        p_access_token_hash,
        p_expected_revision,
        p_legacy_data,
        p_evidence_data
      );
    return;
  end if;

  perform public.enforce_quote_request_intake_lifecycle_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    clock_timestamp()
  );

  return query
    select * from public.save_quote_request_intake_draft_v2_phase2b_predecessor(
      p_access_token_hash,
      p_expected_revision,
      p_legacy_data,
      p_evidence_data
    );
end;
$$;

alter function public.reset_quote_request_intake_draft_v1(text, bigint)
  rename to reset_quote_request_intake_draft_v1_phase2b_predecessor;

create function public.reset_quote_request_intake_draft_v1(
  p_access_token_hash text,
  p_expected_revision bigint
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  updated_at timestamptz,
  draft_revision bigint
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for update;

  if not found or v_intake.access_token_revoked_at is not null then
    return query
      select * from public.reset_quote_request_intake_draft_v1_phase2b_predecessor(
        p_access_token_hash,
        p_expected_revision
      );
    return;
  end if;

  perform public.enforce_quote_request_intake_lifecycle_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    clock_timestamp()
  );

  return query
    select * from public.reset_quote_request_intake_draft_v1_phase2b_predecessor(
      p_access_token_hash,
      p_expected_revision
    );
end;
$$;

alter function public.inspect_preview_budget_guard_context_v1(text)
  rename to inspect_preview_budget_guard_context_v1_phase2b_predecessor;

create function public.inspect_preview_budget_guard_context_v1(
  p_access_token_hash text
)
returns table (
  intake_status text,
  budget_label text,
  budget_category_scheme text,
  budget_category_code text
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for share;

  if not found or v_intake.access_token_revoked_at is not null then
    return query
      select * from public.inspect_preview_budget_guard_context_v1_phase2b_predecessor(
        p_access_token_hash
      );
    return;
  end if;

  perform public.enforce_quote_request_intake_lifecycle_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    clock_timestamp()
  );

  return query
    select * from public.inspect_preview_budget_guard_context_v1_phase2b_predecessor(
      p_access_token_hash
    );
end;
$$;

alter function public.inspect_customer_pricing_read_v3(text)
  rename to inspect_customer_pricing_read_v3_phase2b_predecessor;

alter function public.inspect_customer_pricing_read_v2(text)
  rename to inspect_customer_pricing_read_v2_phase2b_predecessor;

create function public.inspect_customer_pricing_read_v2(p_access_token_hash text)
returns table (
  intake_status text,
  snapshot_present boolean,
  snapshot_contract_version smallint,
  calculation_basis text,
  currency text,
  vat_basis text,
  known_minimum_minor bigint,
  contains_from_pricing boolean,
  manual_review_required boolean,
  manual_reason_count integer,
  budget_contract_version smallint,
  evidence_provenance text,
  budget_status text,
  outside_budget_wishes boolean,
  integrity_snapshot jsonb,
  integrity_context text,
  integrity_metadata jsonb
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for share;

  if not found or v_intake.access_token_revoked_at is not null then
    return query
      select * from public.inspect_customer_pricing_read_v2_phase2b_predecessor(
        p_access_token_hash
      );
    return;
  end if;

  perform public.enforce_quote_request_intake_lifecycle_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    clock_timestamp()
  );

  return query
    select * from public.inspect_customer_pricing_read_v2_phase2b_predecessor(
      p_access_token_hash
    );
end;
$$;

create function public.inspect_customer_pricing_read_v3(p_access_token_hash text)
returns table (
  intake_status text,
  snapshot_present boolean,
  snapshot_contract_version smallint,
  calculation_basis text,
  currency text,
  vat_basis text,
  known_minimum_minor bigint,
  contains_from_pricing boolean,
  manual_review_required boolean,
  manual_reason_count integer,
  budget_contract_version smallint,
  evidence_provenance text,
  budget_status text,
  outside_budget_wishes boolean,
  package_definition jsonb,
  integrity_snapshot jsonb,
  integrity_context text,
  integrity_metadata jsonb
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
begin
  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for share;

  if not found or v_intake.access_token_revoked_at is not null then
    return query
      select * from public.inspect_customer_pricing_read_v3_phase2b_predecessor(
        p_access_token_hash
      );
    return;
  end if;

  perform public.enforce_quote_request_intake_lifecycle_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    clock_timestamp()
  );

  return query
    select * from public.inspect_customer_pricing_read_v3_phase2b_predecessor(
      p_access_token_hash
    );
end;
$$;

revoke all
on function public.enforce_quote_request_intake_lifecycle_access_v1(text, timestamptz, timestamptz)
from public, anon, authenticated, service_role;

revoke all
on function public.inspect_quote_request_intake_customer_access_v1(text)
from public, anon, authenticated;

grant execute
on function public.inspect_quote_request_intake_customer_access_v1(text)
to service_role;

revoke all on function public.inspect_quote_request_intake_details_phase2b_predecessor(text)
from public, anon, authenticated, service_role;
revoke all on function public.inspect_quote_request_intake_phase2b_predecessor(text)
from public, anon, authenticated, service_role;
revoke all on function public.update_quote_request_intake_phase2b_predecessor(text, text, jsonb, text, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.save_quote_request_intake_draft_v2_phase2b_predecessor(text, bigint, jsonb, jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.reset_quote_request_intake_draft_v1_phase2b_predecessor(text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.inspect_preview_budget_guard_context_v1_phase2b_predecessor(text)
from public, anon, authenticated, service_role;
revoke all on function public.inspect_customer_pricing_read_v3_phase2b_predecessor(text)
from public, anon, authenticated, service_role;
revoke all on function public.inspect_customer_pricing_read_v2_phase2b_predecessor(text)
from public, anon, authenticated, service_role;

revoke all on function public.inspect_quote_request_intake_details(text)
from public, anon, authenticated;
revoke all on function public.inspect_quote_request_intake(text)
from public, anon, authenticated;
revoke all on function public.update_quote_request_intake(text, text, jsonb, text, timestamptz)
from public, anon, authenticated;
revoke all on function public.save_quote_request_intake_draft_v2(text, bigint, jsonb, jsonb)
from public, anon, authenticated;
revoke all on function public.reset_quote_request_intake_draft_v1(text, bigint)
from public, anon, authenticated;
revoke all on function public.inspect_preview_budget_guard_context_v1(text)
from public, anon, authenticated;
revoke all on function public.inspect_customer_pricing_read_v3(text)
from public, anon, authenticated;
revoke all on function public.inspect_customer_pricing_read_v2(text)
from public, anon, authenticated;

grant execute on function public.inspect_quote_request_intake_details(text) to service_role;
grant execute on function public.inspect_quote_request_intake(text) to service_role;
grant execute on function public.update_quote_request_intake(text, text, jsonb, text, timestamptz) to service_role;
grant execute on function public.save_quote_request_intake_draft_v2(text, bigint, jsonb, jsonb) to service_role;
grant execute on function public.reset_quote_request_intake_draft_v1(text, bigint) to service_role;
grant execute on function public.inspect_preview_budget_guard_context_v1(text) to service_role;
grant execute on function public.inspect_customer_pricing_read_v3(text) to service_role;
grant execute on function public.inspect_customer_pricing_read_v2(text) to service_role;

comment on function public.enforce_quote_request_intake_lifecycle_access_v1(text, timestamptz, timestamptz) is
  'Maps the canonical Phase-1 effective access result to the Phase-2B customer denial codes.';

comment on function public.inspect_quote_request_intake_customer_access_v1(text) is
  'Service-role-only customer lifecycle preflight. Unknown and revoked capabilities return no row.';
create function public.update_quote_request_intake_with_evidence(
  p_access_token_hash text,
  p_action text,
  p_legacy_data jsonb,
  p_evidence_data jsonb,
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
set search_path = public
as $$
declare
  v_evidence_result record;
  v_legacy_result record;
begin
  if p_action not in ('save_draft', 'submit') then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_ACTION';
  end if;

  select *
    into v_evidence_result
    from public.update_quote_request_intake_evidence(
      p_access_token_hash,
      p_evidence_data
    );

  if v_evidence_result.outcome <> 'saved' then
    return query select
      v_evidence_result.outcome,
      v_evidence_result.intake_status,
      v_evidence_result.started_at,
      null::timestamptz,
      v_evidence_result.updated_at,
      null::uuid,
      null::text;
    return;
  end if;

  select *
    into v_legacy_result
    from public.update_quote_request_intake(
      p_access_token_hash,
      p_action,
      p_legacy_data,
      p_admin_access_token_hash,
      p_admin_access_token_expires_at
    );

  if v_legacy_result.outcome not in ('saved', 'submitted') then
    raise exception using
      errcode = '40001',
      message = 'INTAKE_EVIDENCE_ORCHESTRATION_ROLLBACK';
  end if;

  return query select
    v_legacy_result.outcome,
    v_legacy_result.intake_status,
    v_legacy_result.started_at,
    v_legacy_result.submitted_at,
    v_legacy_result.updated_at,
    v_legacy_result.notification_job_id,
    v_legacy_result.notification_job_status;
end;
$$;

comment on function public.update_quote_request_intake_with_evidence(text, text, jsonb, jsonb, text, timestamptz) is
  'Service-role-only transactional boundary for legacy intake mutation plus validated raw Budget Guard evidence. It does not execute pricing or create pricing snapshots.';

revoke all
on function public.update_quote_request_intake_with_evidence(text, text, jsonb, jsonb, text, timestamptz)
from public, anon, authenticated;

grant execute
on function public.update_quote_request_intake_with_evidence(text, text, jsonb, jsonb, text, timestamptz)
to service_role;
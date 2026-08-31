create function public.resolve_sdf_support_reference_v1(
  p_quote_request_id uuid default null,
  p_intake_id uuid default null
)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_support_reference text;
begin
  if (p_quote_request_id is null) = (p_intake_id is null) then
    raise exception using errcode = '22023', message = 'EXACTLY_ONE_SDF_IDENTIFIER_REQUIRED';
  end if;

  select request.support_reference into v_support_reference
  from public.quote_requests as request
  left join public.sdf_qualification_intakes as intake
    on intake.quote_request_id = request.id
  where request.request_kind = 'slimme_documentenflow'
    and (
      request.id = p_quote_request_id
      or intake.intake_id = p_intake_id
    );

  return v_support_reference;
end;
$$;

revoke all on function public.resolve_sdf_support_reference_v1(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.resolve_sdf_support_reference_v1(uuid, uuid)
to service_role;

create or replace function public.inspect_sdf_qualification_intake_v1(
  p_customer_capability_digest text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intake public.sdf_qualification_intakes%rowtype;
  v_support_reference text;
begin
  select * into v_intake
  from public.sdf_qualification_intakes
  where customer_capability_digest = p_customer_capability_digest
    and customer_capability_revoked_at is null
    and customer_capability_expires_at > clock_timestamp();

  if not found then
    raise exception using errcode = '42501', message = 'SDF_INTAKE_ACCESS_DENIED';
  end if;

  select request.support_reference into strict v_support_reference
  from public.quote_requests as request
  where request.id = v_intake.quote_request_id
    and request.request_kind = 'slimme_documentenflow';

  return jsonb_build_object(
    'intake_id', v_intake.intake_id,
    'support_reference', v_support_reference,
    'status', v_intake.status,
    'taxonomy_version', v_intake.taxonomy_version,
    'draft', v_intake.draft_answers,
    'draft_revision', v_intake.draft_revision,
    'expires_at', v_intake.customer_capability_expires_at
  );
end;
$$;

create function public.get_website_agreement_registration_status_v1(
  p_quote_request_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_authorization record;
  v_bound_quote_request_id uuid;
  v_request_kind text;
  v_candidate public.website_commercial_document_candidates%rowtype;
  v_artifact public.website_commercial_document_render_artifacts%rowtype;
begin
  if p_quote_request_id is null or p_project_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_STATUS_INPUT_INVALID';
  end if;

  select * into strict v_authorization
  from public.resolve_commercial_operator_authorization_v1(
    p_project_id,
    'READ_PROJECT',
    false
  );

  select approval.quote_request_id, request.request_kind
  into strict v_bound_quote_request_id, v_request_kind
  from public.commercial_projects as project
  join public.quote_request_quotation_issuances as issuance
    on issuance.id = project.quotation_issuance_id
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  join public.quote_requests as request
    on request.id = approval.quote_request_id
  where project.project_id = p_project_id;

  if v_bound_quote_request_id <> p_quote_request_id then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_PROJECT_BINDING_MISMATCH';
  end if;
  if v_request_kind <> 'website' then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_PRODUCT_FAMILY_INVALID';
  end if;

  select * into v_candidate
  from public.website_commercial_document_candidates
  where project_id = p_project_id and document_kind = 'AGREEMENT';

  if found then
    if v_candidate.quote_request_id <> p_quote_request_id
       or v_candidate.candidate_status <> 'PREPARED_LOCAL_CONCEPT'
       or v_candidate.agreement_status <> 'UNSIGNED_CONCEPT'
       or v_candidate.issuance_status <> 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED' then
      raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_REGISTRATION_INCONSISTENT';
    end if;

    select * into v_artifact
    from public.website_commercial_document_render_artifacts
    where candidate_id = v_candidate.candidate_id;
    if found and (
      v_artifact.document_kind <> 'AGREEMENT'
      or v_artifact.generation_payload_sha256 <> v_candidate.generation_payload_sha256
      or v_artifact.render_status <> 'LOCAL_RENDER_ONLY'
      or v_artifact.issuance_status <> 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
    ) then
      raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_REGISTRATION_INCONSISTENT';
    end if;
  end if;

  return jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'project_id', p_project_id,
    'candidate_id', v_candidate.candidate_id,
    'candidate_status', v_candidate.candidate_status,
    'agreement_status', v_candidate.agreement_status,
    'candidate_issuance_status', v_candidate.issuance_status,
    'artifact_id', v_artifact.artifact_id,
    'render_status', v_artifact.render_status,
    'render_issuance_status', v_artifact.issuance_status
  );
end;
$$;

revoke all on function public.get_website_agreement_registration_status_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_website_agreement_registration_status_v1(uuid, uuid)
to authenticated;

comment on function public.get_website_agreement_registration_status_v1(uuid, uuid) is
  'Read-only operator projection of stored Website agreement candidate and local render registration status.';
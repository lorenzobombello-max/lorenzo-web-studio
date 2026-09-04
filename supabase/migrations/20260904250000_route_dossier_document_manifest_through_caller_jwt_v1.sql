create function public.get_operator_dossier_document_manifest_authenticated_v1(
  p_quote_request_id uuid
)
returns table (
  document_id uuid,
  source_type text,
  document_type text,
  artifact_type text,
  title text,
  filename text,
  status text,
  created_at timestamptz,
  accepted_at timestamptz,
  source_record_id uuid,
  version text,
  sha256 text,
  quote_request_id uuid,
  customer_id uuid,
  project_id uuid,
  can_open boolean,
  can_download boolean
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  return query
  select *
  from public.get_operator_dossier_document_manifest_v1(
    v_subject,
    p_quote_request_id
  );
end;
$$;

revoke all on function public.get_operator_dossier_document_manifest_authenticated_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_dossier_document_manifest_authenticated_v1(uuid)
to authenticated;

comment on function public.get_operator_dossier_document_manifest_authenticated_v1(uuid) is
  'Authenticated caller-JWT wrapper for the unchanged service-only dossier document manifest authority.';
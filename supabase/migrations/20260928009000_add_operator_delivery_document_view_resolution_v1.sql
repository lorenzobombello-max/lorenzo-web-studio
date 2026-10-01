create function public.resolve_current_website_delivery_document_view_v1(
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_preview_version_id uuid;
begin
  if p_project_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_VIEW_INPUT_INVALID';
  end if;
  select preview_version_id into v_preview_version_id
  from public.preview_versions
  where project_id = p_project_id and status = 'CURRENT';
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_NOT_FOUND';
  end if;
  return public.resolve_website_delivery_document_view_v1(
    p_project_id,
    v_preview_version_id
  );
end;
$$;

revoke all on function public.resolve_current_website_delivery_document_view_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.resolve_current_website_delivery_document_view_v1(uuid)
to service_role;

comment on function public.resolve_current_website_delivery_document_view_v1(uuid) is
  'Service-only resolution of the newest registered delivery-document PDF bound to the project CURRENT preview; never falls back to superseded previews.';
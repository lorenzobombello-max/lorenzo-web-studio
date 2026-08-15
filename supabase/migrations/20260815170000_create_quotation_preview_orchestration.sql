create function public.is_valid_quotation_preview_package_v1(p_package jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_package, array[
    'preview_contract_version', 'preview_id', 'created_at', 'mode',
    'is_authoritative', 'source_identity', 'template', 'generation_payload',
    'generation_payload_sha256', 'display_markers', 'locale',
    'requested_output', 'renderer_handoff'
  ])
    and p_package->'preview_contract_version' = '1'::jsonb
    and p_package->>'mode' = 'PREVIEW'
    and p_package->'is_authoritative' = 'false'::jsonb
    and (p_package->>'preview_id')
      ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and public.is_iso_utc_timestamp(p_package->'created_at')
    and public.jsonb_has_exact_keys(p_package->'source_identity', array[
      'source_type', 'approval_id'
    ])
    and p_package->'source_identity'->>'source_type' = 'IMMUTABLE_APPROVAL'
    and (p_package->'source_identity'->>'approval_id')
      ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and public.is_valid_quotation_generation_template_v1(
      p_package->'template', false
    )
    and p_package->'template'->>'authority_status' = 'CANDIDATE'
    and public.is_valid_quotation_generation_payload_v1(
      p_package->'generation_payload'
    )
    and p_package->'generation_payload'->>'mode' = 'PREVIEW'
    and p_package->'generation_payload'->'template' = p_package->'template'
    and p_package->'generation_payload'->'quotation'->>'approval_id'
      = p_package->'source_identity'->>'approval_id'
    and p_package->'generation_payload'->'quotation'->'quotation_number'
      = 'null'::jsonb
    and p_package->'generation_payload'->'quotation'->'issuance_id'
      = 'null'::jsonb
    and public.is_sha256_jsonb(p_package->'generation_payload_sha256')
    and p_package->>'generation_payload_sha256'
      = public.quotation_generation_payload_sha256_v1(
        p_package->'generation_payload'
      )
    and public.jsonb_has_exact_keys(p_package->'display_markers', array[
      'primary', 'secondary'
    ])
    and p_package->'display_markers'->>'primary'
      = 'CONCEPT — NIET GELDIG ALS OFFERTE'
    and p_package->'display_markers'->>'secondary'
      = 'Geen officieel offertenummer toegekend.'
    and p_package->'locale' = p_package->'generation_payload'->'locale'
    and p_package->'locale' = jsonb_build_object(
      'document_language', 'nl',
      'document_locale', 'nl-BE',
      'currency', 'EUR'
    )
    and p_package->>'requested_output' = 'DOCX'
    and public.jsonb_has_exact_keys(p_package->'renderer_handoff', array[
      'package_kind', 'companion_required', 'target'
    ])
    and p_package->'renderer_handoff' = jsonb_build_object(
      'package_kind', 'PREVIEW_PACKAGE',
      'companion_required', 'TECHNICAL_QUOTATION_TEMPLATE',
      'target', 'DOCX_RENDERER'
    )
$$;

create function public.canonicalize_quotation_preview_package_v1(p_package jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  if not public.is_valid_quotation_preview_package_v1(p_package) then
    raise exception using errcode = '22023', message = 'INVALID_QUOTATION_PREVIEW_PACKAGE_V1';
  end if;
  return p_package::text;
end;
$$;

create function public.quotation_preview_package_sha256_v1(p_package jsonb)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(extensions.digest(convert_to(
    public.canonicalize_quotation_preview_package_v1(p_package), 'UTF8'
  ), 'sha256'), 'hex')
$$;

create function public.quotation_preview_id_v1(p_generation_payload_sha256 text)
returns uuid
language plpgsql
immutable
set search_path = public
as $$
declare
  v_hex text;
begin
  if p_generation_payload_sha256 is null
     or p_generation_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'PREVIEW_FINGERPRINT_INVALID';
  end if;
  v_hex := encode(extensions.digest(convert_to(
    'quotation-preview-v1:' || p_generation_payload_sha256, 'UTF8'
  ), 'sha256'), 'hex');
  return (
    substr(v_hex, 1, 8) || '-' || substr(v_hex, 9, 4) || '-5'
    || substr(v_hex, 14, 3) || '-8' || substr(v_hex, 18, 3) || '-'
    || substr(v_hex, 21, 12)
  )::uuid;
end;
$$;

create function public.build_quotation_preview_package_v1(
  p_approval_id uuid,
  p_template_candidate jsonb,
  p_seller jsonb,
  p_document_locale text,
  p_requested_output text,
  p_admin_access_token_hash text
)
returns table (
  preview_package jsonb,
  preview_id uuid,
  generation_payload_sha256 text,
  preview_package_sha256 text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_generation record;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_package jsonb;
  v_preview_id uuid;
begin
  if p_document_locale <> 'nl-BE' then
    raise exception using errcode = '22023', message = 'UNSUPPORTED_PREVIEW_LOCALE';
  end if;
  if p_requested_output <> 'DOCX' then
    raise exception using errcode = '22023', message = 'UNSUPPORTED_PREVIEW_OUTPUT';
  end if;
  if not public.is_valid_quotation_generation_template_v1(
    p_template_candidate, false
  ) then
    raise exception using errcode = '22023', message = 'TEMPLATE_IDENTITY_INVALID';
  end if;
  if p_template_candidate->>'authority_status' <> 'CANDIDATE' then
    raise exception using errcode = 'P0001', message = 'PREVIEW_TEMPLATE_NOT_CANDIDATE';
  end if;

  select * into v_generation
  from public.build_quotation_preview_payload_v1(
    p_approval_id, p_template_candidate, p_seller,
    p_admin_access_token_hash
  );

  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = p_approval_id;

  if v_generation.mode <> 'PREVIEW'
     or v_generation.payload->'quotation'->'quotation_number' <> 'null'::jsonb
     or v_generation.payload->'quotation'->'issuance_id' <> 'null'::jsonb
     or not public.is_valid_quotation_generation_payload_v1(
       v_generation.payload
     )
     or v_generation.payload_sha256
       <> public.quotation_generation_payload_sha256_v1(
         v_generation.payload
       ) then
    raise exception using errcode = 'P0001', message = 'PREVIEW_PAYLOAD_INVALID';
  end if;

  v_preview_id := public.quotation_preview_id_v1(
    v_generation.payload_sha256
  );
  v_package := jsonb_build_object(
    'preview_contract_version', 1,
    'preview_id', v_preview_id,
    'created_at', to_char(v_approval.approved_at at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'mode', 'PREVIEW',
    'is_authoritative', false,
    'source_identity', jsonb_build_object(
      'source_type', 'IMMUTABLE_APPROVAL',
      'approval_id', v_approval.id
    ),
    'template', p_template_candidate,
    'generation_payload', v_generation.payload,
    'generation_payload_sha256', v_generation.payload_sha256,
    'display_markers', jsonb_build_object(
      'primary', 'CONCEPT — NIET GELDIG ALS OFFERTE',
      'secondary', 'Geen officieel offertenummer toegekend.'
    ),
    'locale', v_generation.payload->'locale',
    'requested_output', 'DOCX',
    'renderer_handoff', jsonb_build_object(
      'package_kind', 'PREVIEW_PACKAGE',
      'companion_required', 'TECHNICAL_QUOTATION_TEMPLATE',
      'target', 'DOCX_RENDERER'
    )
  );

  if not public.is_valid_quotation_preview_package_v1(v_package) then
    raise exception using errcode = '22023', message = 'INVALID_QUOTATION_PREVIEW_PACKAGE_V1';
  end if;

  return query select v_package, v_preview_id,
    v_generation.payload_sha256,
    public.quotation_preview_package_sha256_v1(v_package);
end;
$$;

revoke all on function public.is_valid_quotation_preview_package_v1(jsonb)
from public, anon, authenticated;
revoke all on function public.canonicalize_quotation_preview_package_v1(jsonb)
from public, anon, authenticated;
revoke all on function public.quotation_preview_package_sha256_v1(jsonb)
from public, anon, authenticated;
revoke all on function public.quotation_preview_id_v1(text)
from public, anon, authenticated;
revoke all on function public.build_quotation_preview_package_v1(uuid,jsonb,jsonb,text,text,text)
from public, anon, authenticated;

grant execute on function public.is_valid_quotation_preview_package_v1(jsonb)
to service_role;
grant execute on function public.canonicalize_quotation_preview_package_v1(jsonb)
to service_role;
grant execute on function public.quotation_preview_package_sha256_v1(jsonb)
to service_role;
grant execute on function public.quotation_preview_id_v1(text)
to service_role;
grant execute on function public.build_quotation_preview_package_v1(uuid,jsonb,jsonb,text,text,text)
to service_role;

comment on function public.build_quotation_preview_package_v1(uuid,jsonb,jsonb,text,text,text) is
  'Stateless trusted PREVIEW orchestration from immutable approval only. It allocates no quotation number, creates no issuance, and writes no business state.';
comment on function public.quotation_preview_id_v1(text) is
  'Deterministic non-authoritative preview UUID derived from the canonical D3E4 PREVIEW payload hash; it has no accounting or legal significance.';

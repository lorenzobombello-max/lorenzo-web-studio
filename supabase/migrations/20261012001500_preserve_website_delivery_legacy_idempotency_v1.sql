-- Preserve idempotent replay for candidates created before the support-reference fallback.
-- Existing candidate rows remain immutable; only the function's replay comparison changes.

do $migration$
declare
  v_function regprocedure :=
    'public.prepare_website_delivery_document_v1(uuid,date,jsonb,text,text,date,text,date,text,uuid,text)'::regprocedure;
  v_definition text;
  v_repaired text;
  v_owner oid;
  v_acl aclitem[];
  v_security_definer boolean;
  v_config text[];
  v_anchor text := $anchor$
  if found then
    if v_existing.project_id <> p_project_id or v_existing.generation_payload_sha256 <> v_payload_sha256 then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'candidate_id', v_existing.candidate_id, 'document_version', v_existing.document_version,
      'generation_payload', v_existing.generation_payload,
      'generation_payload_sha256', rtrim(v_existing.generation_payload_sha256), 'was_created', false
    );
  end if;
$anchor$;
  v_replacement text := $replacement$
  if found then
    if v_existing.project_id <> p_project_id then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_IDEMPOTENCY_CONFLICT';
    end if;
    if v_existing.generation_payload_sha256 = v_payload_sha256 then
      return jsonb_build_object(
        'candidate_id', v_existing.candidate_id, 'document_version', v_existing.document_version,
        'generation_payload', v_existing.generation_payload,
        'generation_payload_sha256', rtrim(v_existing.generation_payload_sha256), 'was_created', false
      );
    end if;
    if nullif(btrim(v_request.application_reference), '') is null then
      declare
        v_legacy_payload jsonb := jsonb_set(
          v_payload,
          '{project,reference}',
          coalesce(to_jsonb(v_request.application_reference), 'null'::jsonb),
          false
        );
        v_legacy_payload_sha256 text := encode(
          extensions.digest(convert_to(v_legacy_payload::text, 'UTF8'), 'sha256'),
          'hex'
        );
      begin
        if v_existing.generation_payload = v_legacy_payload
           and rtrim(v_existing.generation_payload_sha256) = v_legacy_payload_sha256 then
          return jsonb_build_object(
            'candidate_id', v_existing.candidate_id, 'document_version', v_existing.document_version,
            'generation_payload', v_existing.generation_payload,
            'generation_payload_sha256', rtrim(v_existing.generation_payload_sha256), 'was_created', false
          );
        end if;
      end;
    end if;
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_IDEMPOTENCY_CONFLICT';
  end if;
$replacement$;
begin
  select pg_get_functiondef(v_function), proowner, proacl, prosecdef, proconfig
  into v_definition, v_owner, v_acl, v_security_definer, v_config
  from pg_proc
  where oid = v_function;

  if (
    length(v_definition) - length(replace(v_definition, v_anchor, ''))
  ) <> length(v_anchor) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_LEGACY_IDEMPOTENCY_SOURCE_MISMATCH';
  end if;

  v_repaired := replace(v_definition, v_anchor, v_replacement);
  execute v_repaired;

  if not exists (
    select 1
    from pg_proc
    where oid = v_function
      and proowner = v_owner
      and proacl is not distinct from v_acl
      and prosecdef = v_security_definer
      and proconfig is not distinct from v_config
      and prosrc like '%v_legacy_payload_sha256%'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_LEGACY_IDEMPOTENCY_POSTVERIFY_FAILED';
  end if;
end;
$migration$;

comment on function public.prepare_website_delivery_document_v1(
  uuid,date,jsonb,text,text,date,text,date,text,uuid,text
) is
  'Prepares immutable OPL-W-01 input for the CURRENT preview and preserves exact replay of pre-fallback candidates without rewriting their payload identity.';

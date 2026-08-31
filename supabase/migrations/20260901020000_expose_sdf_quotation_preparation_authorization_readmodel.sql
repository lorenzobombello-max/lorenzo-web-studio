create or replace function public.inspect_sdf_qualification_intake_for_operator_v1(p_quote_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,lws_internal,pg_catalog as $$
declare v_operator public.commercial_operators%rowtype; v_result jsonb;
begin
  v_operator:=lws_internal.assert_sdf_owner_v1();
  select jsonb_build_object(
    'quote_request_id',r.id,
    'name',r.name,
    'company',r.company,
    'email',r.email,
    'sdf_package',r.sdf_package,
    'intake_id',i.intake_id,
    'status',i.status,
    'taxonomy_version',i.taxonomy_version,
    'draft_revision',i.draft_revision,
    'latest_submission_sequence',i.latest_submission_sequence,
    'latest_submission',s.answers,
    'latest_submission_sha256',s.payload_sha256,
    'quotation_preparation_authorized',exists(
      select 1
      from public.sdf_quotation_preparation_authorities authority
      where authority.qualification_intake_id=i.intake_id
    )
  ) into v_result
  from public.quote_requests r
  join public.sdf_qualification_intakes i on i.quote_request_id=r.id
  left join public.sdf_qualification_intake_submissions s
    on s.intake_id=i.intake_id and s.submission_sequence=i.latest_submission_sequence
  where r.id=p_quote_request_id and r.request_kind='slimme_documentenflow';
  if v_result is null then raise exception using errcode='P0002',message='SDF_QUALIFICATION_INTAKE_NOT_FOUND'; end if;
  return v_result;
end;
$$;
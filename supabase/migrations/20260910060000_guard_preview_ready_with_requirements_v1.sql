create or replace function lws_internal.execute_commercial_command_core_v1(
  p_audit_actor text,p_project_id uuid,p_command_type text,p_expected_state text,p_expected_revision bigint,p_idempotency_key uuid,p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=lws_internal,public,extensions,pg_catalog as $$
declare v_project public.commercial_projects%rowtype;v_old public.idempotency_ledger%rowtype;v_fp text;v_state text;v_result jsonb;v_evidence public.payment_evidence%rowtype;v_expect public.payment_expectations%rowtype;v_match text;v_milestone int;v_access public.preview_access%rowtype;v_feedback public.customer_feedback%rowtype;v_revision public.project_revisions%rowtype;v_version public.preview_versions%rowtype;v_id uuid;v_changes_state boolean:=false;v_requirements_readiness jsonb;
begin
  if nullif(btrim(p_audit_actor),'') is null or p_payload ?| array['resulting_state','current_state','match_status','fiscal_production_enabled'] then raise exception using errcode='42501',message='DIRECT_STATE_WRITE_FORBIDDEN';end if;
  v_fp:=lws_internal.commercial_fingerprint_v1(jsonb_build_object('actor',p_audit_actor,'project',p_project_id,'command',p_command_type,'state',p_expected_state,'revision',p_expected_revision,'payload',p_payload));
  select * into v_old from public.idempotency_ledger where actor_id=p_audit_actor and project_id=p_project_id and command_type=p_command_type and idempotency_key=p_idempotency_key;
  if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;return v_old.result_payload;end if;
  select * into v_project from public.commercial_projects where project_id=p_project_id for update;if not found then raise exception using errcode='23503',message='PROJECT_NOT_FOUND';end if;
  if v_project.current_state<>p_expected_state or v_project.revision<>p_expected_revision then raise exception using errcode='40001',message='CONCURRENT_MODIFICATION';end if;
  v_state:=v_project.current_state;
  if p_command_type='prepare_milestone_1' then
    if v_state<>'QUOTE_ACCEPTED' then raise exception using errcode='P0001',message='INVALID_STATE';end if;
    insert into public.commercial_obligations(project_id,obligation_type,milestone,amount_minor,expected_reference,status) values
      (p_project_id,'PROJECT_MILESTONE',1,v_project.m1_minor,'LWS-MILESTONE-'||p_project_id::text||'-M1','OPEN'),
      (p_project_id,'PROJECT_MILESTONE',2,v_project.m2_minor,'LWS-MILESTONE-'||p_project_id::text||'-M2','OPEN'),
      (p_project_id,'PROJECT_MILESTONE',3,v_project.m3_minor,'LWS-MILESTONE-'||p_project_id::text||'-M3','OPEN');
    insert into public.payment_expectations(project_id,obligation_id,expected_amount_minor,expected_reference)
      select project_id,obligation_id,amount_minor,expected_reference from public.commercial_obligations where project_id=p_project_id;
    v_state:='M1_PAYMENT_PENDING';v_changes_state:=true;
  elsif p_command_type='record_payment_evidence' then
    if p_payload->>'bank_iban'='BE34 1500 3429 84' then raise exception using errcode='23514',message='FORBIDDEN_OLD_IBAN';end if;
    if p_payload->>'bank_iban'<>'BE42 7380 5510 8954' then raise exception using errcode='23514',message='UNAPPROVED_BANK';end if;
    select * into v_expect from public.payment_expectations where project_id=p_project_id and expected_reference=p_payload->>'expected_reference';if not found then raise exception using errcode='23503',message='EXPECTATION_NOT_FOUND';end if;
    insert into public.payment_evidence(project_id,obligation_id,received_amount_minor,transaction_date,transaction_reference,evidence_reference,bank_account_fingerprint,verified_by,verified_at)
    values(p_project_id,v_expect.obligation_id,(p_payload->>'received_amount_minor')::bigint,(p_payload->>'transaction_date')::date,p_payload->>'transaction_reference',p_payload->>'evidence_reference',lws_internal.commercial_fingerprint_v1(to_jsonb(p_payload->>'bank_iban')),p_audit_actor,clock_timestamp()) returning * into v_evidence;
  elsif p_command_type='reconcile_payment' then
    select * into v_evidence from public.payment_evidence where payment_evidence_id=(p_payload->>'payment_evidence_id')::uuid and project_id=p_project_id;if not found then raise exception using errcode='23503',message='PAYMENT_EVIDENCE_NOT_FOUND';end if;
    select * into strict v_expect from public.payment_expectations where obligation_id=v_evidence.obligation_id;
    if exists(select 1 from public.payment_reconciliations where payment_evidence_id=v_evidence.payment_evidence_id) then v_match:='DUPLICATE_EVIDENCE';
    elsif v_evidence.received_amount_minor<v_expect.expected_amount_minor then v_match:='PARTIAL';
    elsif v_evidence.received_amount_minor>v_expect.expected_amount_minor then v_match:='OVERPAYMENT';else v_match:='MATCHED';end if;
    insert into public.payment_reconciliations(payment_evidence_id,project_id,obligation_id,match_status,decided_by) values(v_evidence.payment_evidence_id,p_project_id,v_evidence.obligation_id,v_match,'SERVER_COMMAND_LAYER');
  elsif p_command_type='confirm_payment' then
    v_milestone:=(p_payload->>'milestone')::int;
    select pe.* into v_expect from public.payment_expectations pe join public.commercial_obligations co using(obligation_id) where pe.project_id=p_project_id and co.milestone=v_milestone;
    if not found or not exists(select 1 from public.payment_reconciliations where obligation_id=v_expect.obligation_id and match_status='MATCHED') then raise exception using errcode='P0001',message='PAYMENT_NOT_MATCHED';end if;
    if v_milestone=1 and v_state='M1_PAYMENT_PENDING' then v_state:='M1_PAYMENT_RECEIVED';elsif v_milestone=2 and v_state='PREVIEW_READY' then v_state:='M2_PAYMENT_RECEIVED';elsif v_milestone=3 and v_state='FINAL_APPROVAL_RECORDED' then v_state:='FULL_PAYMENT_RECEIVED';else raise exception using errcode='P0001',message='INVALID_STATE';end if;v_changes_state:=true;
  elsif p_command_type='release_project' then if v_state<>'M1_PAYMENT_RECEIVED' then raise exception using errcode='P0001',message='PAYMENT_NOT_MATCHED';end if;v_state:='PROJECT_RELEASED';v_changes_state:=true;
  elsif p_command_type='record_preview_ready' then
    if v_state<>'PROJECT_RELEASED' then raise exception using errcode='P0001',message='INVALID_STATE';end if;
    v_requirements_readiness:=lws_internal.evaluate_project_requirements_readiness_v1(p_project_id);
    if v_requirements_readiness->>'readiness'<>'READY'
       or coalesce((v_requirements_readiness->>'ready_for_preview')::boolean,false) is not true then
      raise exception using errcode='P0001',message='PROJECT_REQUIREMENTS_NOT_READY';
    end if;
    insert into public.preview_versions(project_id,version_number,content_reference,content_sha256,status) values(p_project_id,1,p_payload->>'content_reference',p_payload->>'content_sha256','CURRENT') returning * into v_version;v_state:='PREVIEW_READY';v_changes_state:=true;
  elsif p_command_type='activate_preview_access' then
    if (p_payload->>'token_digest') !~ '^[0-9a-f]{64}$' or (p_payload->>'expires_at')::timestamptz<=clock_timestamp() then raise exception using errcode='22023',message='INVALID_PREVIEW_CREDENTIAL';end if;
    select * into v_version from public.preview_versions where project_id=p_project_id and status='CURRENT';
    insert into public.preview_access(project_id,preview_version_id,token_digest,status,expires_at,created_by) values(p_project_id,v_version.preview_version_id,p_payload->>'token_digest','ACTIVE',(p_payload->>'expires_at')::timestamptz,p_audit_actor) returning * into v_access;
  elsif p_command_type='revoke_preview_access' then perform set_config('lws.commercial_command','on',true);update public.preview_access set status='REVOKED',revoked_at=clock_timestamp(),revision=revision+1 where preview_access_id=(p_payload->>'preview_access_id')::uuid and project_id=p_project_id and status='ACTIVE' returning * into v_access;if not found then raise exception using errcode='P0001',message='ACCESS_NOT_ACTIVE';end if;update public.preview_sessions set revoked_at=clock_timestamp() where preview_access_id=v_access.preview_access_id and revoked_at is null;perform set_config('lws.commercial_command','',true);
  elsif p_command_type='submit_customer_feedback' then
    select * into v_access from public.preview_access where preview_access_id=(p_payload->>'preview_access_id')::uuid and project_id=p_project_id and status='ACTIVE' and expires_at>clock_timestamp();if not found then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
    insert into public.customer_feedback(project_id,preview_access_id,feedback_type,subject,customer_message,page_reference,status) values(p_project_id,v_access.preview_access_id,p_payload->>'feedback_type',p_payload->>'subject',p_payload->>'message',p_payload->>'page_reference','NEW') returning * into v_feedback;
  elsif p_command_type='classify_feedback' then
    perform set_config('lws.commercial_command','on',true);update public.customer_feedback set status=p_payload->>'status',revision=revision+1 where feedback_id=(p_payload->>'feedback_id')::uuid and project_id=p_project_id returning * into v_feedback;perform set_config('lws.commercial_command','',true);if not found then raise exception using errcode='23503',message='FEEDBACK_NOT_FOUND';end if;
  elsif p_command_type='create_revision' then
    select * into v_feedback from public.customer_feedback where feedback_id=(p_payload->>'feedback_id')::uuid and project_id=p_project_id and status='REVIEWED';if not found then raise exception using errcode='P0001',message='INCLUDED_CLASSIFICATION_REQUIRED';end if;
    insert into public.project_revisions(project_id,feedback_id,revision_number,classification,status,evidence_reference) values(p_project_id,v_feedback.feedback_id,coalesce((select max(revision_number)+1 from public.project_revisions where project_id=p_project_id),1),'INCLUDED_REVISION','OPEN',p_payload->>'evidence_reference') returning * into v_revision;
  elsif p_command_type='mark_revision_ready' then
    perform set_config('lws.commercial_command','on',true);update public.project_revisions set status='READY_FOR_PREVIEW',revision=revision+1 where revision_id=(p_payload->>'revision_id')::uuid and project_id=p_project_id and status in('OPEN','IN_PROGRESS') returning * into v_revision;perform set_config('lws.commercial_command','',true);if not found then raise exception using errcode='P0001',message='INVALID_REVISION_STATE';end if;
  elsif p_command_type='create_preview_version' then
    select * into v_revision from public.project_revisions where revision_id=(p_payload->>'revision_id')::uuid and project_id=p_project_id and status='READY_FOR_PREVIEW';if not found then raise exception using errcode='P0001',message='REVISION_NOT_READY';end if;
    perform set_config('lws.commercial_command','on',true);update public.preview_versions set status='SUPERSEDED' where project_id=p_project_id and status='CURRENT';update public.customer_approvals set status='SUPERSEDED' where project_id=p_project_id and status='CURRENT';perform set_config('lws.commercial_command','',true);
    insert into public.preview_versions(project_id,revision_id,version_number,content_reference,content_sha256,status) values(p_project_id,v_revision.revision_id,coalesce((select max(version_number)+1 from public.preview_versions where project_id=p_project_id),1),p_payload->>'content_reference',p_payload->>'content_sha256','CURRENT') returning * into v_version;
  elsif p_command_type='submit_customer_approval' then
    select * into v_access from public.preview_access where preview_access_id=(p_payload->>'preview_access_id')::uuid and project_id=p_project_id and status='ACTIVE' and expires_at>clock_timestamp();if not found then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
    select * into v_version from public.preview_versions where preview_version_id=(p_payload->>'preview_version_id')::uuid and project_id=p_project_id and status='CURRENT';if not found or v_access.preview_version_id<>v_version.preview_version_id then raise exception using errcode='P0001',message='PREVIEW_VERSION_MISMATCH';end if;
    insert into public.customer_approvals(project_id,preview_access_id,preview_version_id,statement_version,statement_sha256,status) values(p_project_id,v_access.preview_access_id,v_version.preview_version_id,p_payload->>'statement_version',p_payload->>'statement_sha256','CURRENT');
    if v_state='M2_PAYMENT_RECEIVED' then v_state:='FINAL_APPROVAL_RECORDED';v_changes_state:=true;end if;
  elsif p_command_type='require_change_order' then
    select * into v_feedback from public.customer_feedback where feedback_id=(p_payload->>'feedback_id')::uuid and project_id=p_project_id;if not found then raise exception using errcode='23503',message='FEEDBACK_NOT_FOUND';end if;
    insert into public.change_orders(project_id,original_quotation_issuance_id,feedback_id,change_request_reference,separate_amount_minor,status) values(p_project_id,v_project.quotation_issuance_id,v_feedback.feedback_id,p_payload->>'change_request_reference',null,'CHANGE_ORDER_REQUIRED');
  elsif p_command_type='authorize_final_transfer' then if v_state<>'FULL_PAYMENT_RECEIVED' then raise exception using errcode='P0001',message='PAYMENT_NOT_MATCHED';end if;v_state:='FINAL_TRANSFER_AUTHORIZED';v_changes_state:=true;
  elsif p_command_type='record_delivery' then if v_state<>'FINAL_TRANSFER_AUTHORIZED' then raise exception using errcode='P0001',message='TRANSFER_NOT_AUTHORIZED';end if;v_state:='DELIVERED';v_changes_state:=true;
  elsif p_command_type='archive_project' then if v_state<>'DELIVERED' then raise exception using errcode='P0001',message='INVALID_STATE';end if;v_state:='ARCHIVED';v_changes_state:=true;
  elsif p_command_type in('invoice_production','vat_production','peppol_production','credit_note_production','fiscal_numbering_activation') then raise exception using errcode='42501',message='FISCAL_PRODUCTION_BLOCKED';
  else raise exception using errcode='22023',message='UNKNOWN_COMMAND';end if;
  if v_changes_state then perform set_config('lws.commercial_command','on',true);update public.commercial_projects set current_state=v_state,revision=revision+1,updated_at=clock_timestamp() where project_id=p_project_id returning * into v_project;perform set_config('lws.commercial_command','',true);insert into public.workflow_events(project_id,previous_state,new_state,project_revision,command_id) values(p_project_id,p_expected_state,v_state,v_project.revision,p_idempotency_key);end if;
  insert into public.audit_events(project_id,event_type,actor,command_id,metadata) values(p_project_id,upper(p_command_type),p_audit_actor,p_idempotency_key,jsonb_build_object('state',v_state));
  v_result:=jsonb_build_object('project_id',p_project_id,'resulting_state',v_state,'revision',(select revision from public.commercial_projects where project_id=p_project_id),'command_type',p_command_type,'match_status',v_match,'entity_id',coalesce(v_evidence.payment_evidence_id,v_access.preview_access_id,v_feedback.feedback_id,v_revision.revision_id,v_version.preview_version_id));
  insert into public.idempotency_ledger(actor_id,project_id,command_type,idempotency_key,request_fingerprint,result_reference,result_payload) values(p_audit_actor,p_project_id,p_command_type,p_idempotency_key,v_fp,p_idempotency_key::text,v_result);
  return v_result;
end $$;

comment on function lws_internal.execute_commercial_command_core_v1(
  text, uuid, text, text, bigint, uuid, jsonb
) is 'Existing commercial command core with fail-closed project requirements readiness before preview creation.';
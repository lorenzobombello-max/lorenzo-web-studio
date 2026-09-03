begin;

do $$
declare
  v_signature constant regprocedure := 'public.update_quote_request_intake_phase2b_predecessor(text,text,jsonb,text,timestamp with time zone)'::regprocedure;
  v_definition text := pg_get_functiondef(v_signature);
  v_old_target constant text := 'on conflict (quote_request_id, kind) do nothing';
  v_new_target constant text := 'on conflict (quote_request_id, kind) where reminder_access_cycle is null do nothing';
begin
  if v_definition not like '%' || v_old_target || '%'
     or v_definition like '%' || v_new_target || '%'
     or length(v_definition) - length(replace(v_definition, v_old_target, '')) <> length(v_old_target) then
    raise exception using errcode = 'P0001', message = 'INTAKE_NOTIFICATION_CONFLICT_TARGET_DRIFT';
  end if;

  execute replace(v_definition, v_old_target, v_new_target);
end;
$$;

commit;
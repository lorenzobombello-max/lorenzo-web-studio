create or replace function public.require_document_inbox_owner_v1()
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role <> 'owner' then raise exception using errcode = '42501', message = 'DOCUMENT_INBOX_OWNER_REQUIRED'; end if;
  return v_operator.operator_id;
end;
$$;
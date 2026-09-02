create function public.list_operator_message_recipients_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_sender public.commercial_operators%rowtype;
  v_recipients jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select * into v_sender
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_sender.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_NOT_ACTIVE'; end if;
  if v_sender.role <> 'owner' then raise exception using errcode = '42501', message = 'OWNER_MESSAGE_SENDER_REQUIRED'; end if;

  select coalesce(jsonb_agg(projected.recipient order by projected.sort_name, projected.operator_id), '[]'::jsonb)
  into v_recipients
  from (
    select
      operator.operator_id,
      lower(operator.display_name) as sort_name,
      jsonb_build_object(
        'operator_id', operator.operator_id,
        'display_name', operator.display_name
      ) as recipient
    from public.commercial_operators as operator
    where operator.status = 'ACTIVE'
      and operator.operator_id <> v_sender.operator_id
  ) as projected;

  return v_recipients;
end;
$$;

revoke all on function public.list_operator_message_recipients_v1()
from public, anon, authenticated, service_role;

grant execute on function public.list_operator_message_recipients_v1() to authenticated;

comment on function public.list_operator_message_recipients_v1() is
  'Owner-authorized minimal PERSONAL message recipient roster. Excludes caller and inactive operators server-side without presence filtering.';
grant select on table public.operator_message_recipients to authenticated;

create function public.is_current_active_operator_v1(p_operator_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
  select exists (
    select 1
    from public.commercial_operators as operator
    where operator.auth_user_id = auth.uid()
      and operator.operator_id = p_operator_id
      and operator.status = 'ACTIVE'
  );
$$;

revoke all on function public.is_current_active_operator_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.is_current_active_operator_v1(uuid) to authenticated;

create policy operator_message_recipients_realtime_select_v1
on public.operator_message_recipients
for select
to authenticated
using (public.is_current_active_operator_v1(recipient_operator_id));

alter publication supabase_realtime add table public.operator_message_recipients;

comment on policy operator_message_recipients_realtime_select_v1 on public.operator_message_recipients is
  'Realtime invalidation only: active Operators can observe only their own delivery rows; message content remains RPC-projected.';

comment on function public.is_current_active_operator_v1(uuid) is
  'Bounded RLS predicate: true only when the UUID is the current authenticated ACTIVE Operator.';
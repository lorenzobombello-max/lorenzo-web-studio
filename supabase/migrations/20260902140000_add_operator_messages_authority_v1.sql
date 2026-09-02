create table public.operator_messages (
  id uuid primary key default gen_random_uuid(),
  sender_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  message_scope text not null check (message_scope in ('PERSONAL', 'ALL')),
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  created_at timestamptz not null default clock_timestamp()
);

create table public.operator_message_recipients (
  message_id uuid not null references public.operator_messages(id) on delete restrict,
  recipient_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  read_at timestamptz,
  primary key(message_id, recipient_operator_id)
);

create index operator_messages_sender_created_idx
  on public.operator_messages(sender_operator_id, created_at desc, id desc);
create index operator_message_recipients_inbox_idx
  on public.operator_message_recipients(recipient_operator_id, message_id);
create index operator_message_recipients_unread_idx
  on public.operator_message_recipients(recipient_operator_id, message_id)
  where read_at is null;

alter table public.operator_messages enable row level security;
alter table public.operator_messages force row level security;
alter table public.operator_message_recipients enable row level security;
alter table public.operator_message_recipients force row level security;

revoke all on table public.operator_messages from public, anon, authenticated, service_role;
revoke all on table public.operator_message_recipients from public, anon, authenticated, service_role;

create function lws_internal.guard_operator_message_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'OPERATOR_MESSAGE_DELETE_NOT_ALLOWED';
  end if;
  if new.id is distinct from old.id
    or new.sender_operator_id is distinct from old.sender_operator_id
    or new.message_scope is distinct from old.message_scope
    or new.body is distinct from old.body
    or new.created_at is distinct from old.created_at then
    raise exception using errcode = '55000', message = 'OPERATOR_MESSAGE_IMMUTABLE';
  end if;
  return new;
end;
$$;

create function lws_internal.guard_operator_message_recipient_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'OPERATOR_MESSAGE_RECIPIENT_DELETE_NOT_ALLOWED';
  end if;
  if new.message_id is distinct from old.message_id
    or new.recipient_operator_id is distinct from old.recipient_operator_id then
    raise exception using errcode = '55000', message = 'OPERATOR_MESSAGE_RECIPIENT_IMMUTABLE';
  end if;
  if old.read_at is not null and new.read_at is distinct from old.read_at then
    raise exception using errcode = '55000', message = 'OPERATOR_MESSAGE_READ_STATE_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger trg_operator_messages_immutable
before update or delete on public.operator_messages
for each row execute function lws_internal.guard_operator_message_mutation_v1();

create trigger trg_operator_message_recipients_immutable
before update or delete on public.operator_message_recipients
for each row execute function lws_internal.guard_operator_message_recipient_mutation_v1();

create function public.send_operator_message_v1(
  p_message_scope text,
  p_recipient_operator_id uuid,
  p_body text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_sender public.commercial_operators%rowtype;
  v_recipient public.commercial_operators%rowtype;
  v_scope text := upper(btrim(coalesce(p_message_scope, '')));
  v_body text := btrim(coalesce(p_body, ''));
  v_message public.operator_messages%rowtype;
  v_recipient_count integer;
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
  if v_scope not in ('PERSONAL', 'ALL') then
    raise exception using errcode = '22023', message = 'INVALID_MESSAGE_SCOPE';
  end if;
  if char_length(v_body) not between 1 and 4000 then
    raise exception using errcode = '22023', message = 'INVALID_MESSAGE_BODY';
  end if;

  if v_scope = 'PERSONAL' then
    if p_recipient_operator_id is null then
      raise exception using errcode = '22023', message = 'PERSONAL_RECIPIENT_REQUIRED';
    end if;
    select * into v_recipient
    from public.commercial_operators
    where operator_id = p_recipient_operator_id;
    if not found then raise exception using errcode = '23503', message = 'MESSAGE_RECIPIENT_NOT_FOUND'; end if;
    if v_recipient.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'MESSAGE_RECIPIENT_NOT_ACTIVE'; end if;
    if v_recipient.operator_id = v_sender.operator_id then
      raise exception using errcode = '22023', message = 'MESSAGE_RECIPIENT_MUST_DIFFER';
    end if;
  elsif p_recipient_operator_id is not null then
    raise exception using errcode = '22023', message = 'BROADCAST_RECIPIENT_FORBIDDEN';
  end if;

  insert into public.operator_messages(sender_operator_id, message_scope, body)
  values(v_sender.operator_id, v_scope, v_body)
  returning * into v_message;

  if v_scope = 'PERSONAL' then
    insert into public.operator_message_recipients(message_id, recipient_operator_id)
    values(v_message.id, v_recipient.operator_id);
  else
    insert into public.operator_message_recipients(message_id, recipient_operator_id)
    select v_message.id, operator.operator_id
    from public.commercial_operators as operator
    where operator.status = 'ACTIVE'
      and operator.operator_id <> v_sender.operator_id;
  end if;

  select count(*)::integer into v_recipient_count
  from public.operator_message_recipients
  where message_id = v_message.id;
  if v_recipient_count = 0 then
    raise exception using errcode = '55000', message = 'MESSAGE_RECIPIENT_SET_EMPTY';
  end if;

  return jsonb_build_object(
    'id', v_message.id,
    'sender_operator_id', v_sender.operator_id,
    'sender_display_name', v_sender.display_name,
    'message_scope', v_message.message_scope,
    'body', v_message.body,
    'created_at', v_message.created_at,
    'recipient_count', v_recipient_count
  );
end;
$$;

create function public.list_operator_messages_v1(
  p_mailbox text default 'received',
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_mailbox text := lower(btrim(coalesce(p_mailbox, '')));
  v_messages jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_NOT_ACTIVE'; end if;
  if v_mailbox not in ('received', 'sent') then
    raise exception using errcode = '22023', message = 'INVALID_MESSAGE_MAILBOX';
  end if;
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'INVALID_MESSAGE_LIMIT';
  end if;

  if v_mailbox = 'received' then
    select coalesce(jsonb_agg(projected.payload order by projected.created_at desc, projected.id desc), '[]'::jsonb)
    into v_messages
    from (
      select message.id, message.created_at, jsonb_build_object(
        'id', message.id,
        'sender_operator_id', sender.operator_id,
        'sender_display_name', sender.display_name,
        'message_scope', message.message_scope,
        'body', message.body,
        'created_at', message.created_at,
        'read_at', delivery.read_at,
        'recipient_count', (select count(*) from public.operator_message_recipients as all_deliveries where all_deliveries.message_id = message.id)
      ) as payload
      from public.operator_message_recipients as delivery
      join public.operator_messages as message on message.id = delivery.message_id
      join public.commercial_operators as sender on sender.operator_id = message.sender_operator_id
      where delivery.recipient_operator_id = v_operator.operator_id
      order by message.created_at desc, message.id desc
      limit p_limit
    ) as projected;
  else
    select coalesce(jsonb_agg(projected.payload order by projected.created_at desc, projected.id desc), '[]'::jsonb)
    into v_messages
    from (
      select message.id, message.created_at, jsonb_build_object(
        'id', message.id,
        'sender_operator_id', sender.operator_id,
        'sender_display_name', sender.display_name,
        'message_scope', message.message_scope,
        'body', message.body,
        'created_at', message.created_at,
        'recipient_count', (select count(*) from public.operator_message_recipients as deliveries where deliveries.message_id = message.id),
        'recipients', coalesce((
          select jsonb_agg(jsonb_build_object(
            'operator_id', recipient.operator_id,
            'display_name', recipient.display_name,
            'read_at', delivery.read_at
          ) order by recipient.display_name, recipient.operator_id)
          from public.operator_message_recipients as delivery
          join public.commercial_operators as recipient on recipient.operator_id = delivery.recipient_operator_id
          where delivery.message_id = message.id
        ), '[]'::jsonb)
      ) as payload
      from public.operator_messages as message
      join public.commercial_operators as sender on sender.operator_id = message.sender_operator_id
      where message.sender_operator_id = v_operator.operator_id
      order by message.created_at desc, message.id desc
      limit p_limit
    ) as projected;
  end if;

  return v_messages;
end;
$$;

create function public.mark_operator_message_read_v1(p_message_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_message public.operator_messages%rowtype;
  v_read_at timestamptz;
  v_sender_name text;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_NOT_ACTIVE'; end if;

  update public.operator_message_recipients
  set read_at = coalesce(read_at, clock_timestamp())
  where message_id = p_message_id
    and recipient_operator_id = v_operator.operator_id
  returning read_at into v_read_at;
  if not found then
    raise exception using errcode = '42501', message = 'OPERATOR_MESSAGE_NOT_AVAILABLE';
  end if;

  select * into v_message from public.operator_messages where id = p_message_id;
  select display_name into v_sender_name
  from public.commercial_operators where operator_id = v_message.sender_operator_id;
  return jsonb_build_object(
    'id', v_message.id,
    'sender_operator_id', v_message.sender_operator_id,
    'sender_display_name', v_sender_name,
    'message_scope', v_message.message_scope,
    'body', v_message.body,
    'created_at', v_message.created_at,
    'read_at', v_read_at
  );
end;
$$;

revoke all on function lws_internal.guard_operator_message_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_operator_message_recipient_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.send_operator_message_v1(text, uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.list_operator_messages_v1(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.mark_operator_message_read_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.send_operator_message_v1(text, uuid, text) to authenticated;
grant execute on function public.list_operator_messages_v1(text, integer) to authenticated;
grant execute on function public.mark_operator_message_read_v1(uuid) to authenticated;

comment on table public.operator_messages is
  'Private retained canonical internal operator messages with PERSONAL or server-resolved ALL scope.';
comment on table public.operator_message_recipients is
  'Private immutable recipient deliveries with independent per-recipient read state.';
comment on function public.send_operator_message_v1(text, uuid, text) is
  'Owner-only V1 send authority. Sender and ALL recipient set derive exclusively from server authority.';
comment on function public.list_operator_messages_v1(text, integer) is
  'Authenticated sender/recipient-only canonical message mailbox projection.';
comment on function public.mark_operator_message_read_v1(uuid) is
  'Recipient-only idempotent per-delivery read authority without message-existence disclosure.';

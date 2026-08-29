create table public.business_expense_documents (
  id uuid primary key default gen_random_uuid(),
  business_expense_id uuid not null,
  supplier_document_id uuid not null,
  relation_type text not null,
  record_classification text not null,
  created_by_operator_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint business_expense_documents_expense_fk
    foreign key (business_expense_id)
    references public.business_expenses(id)
    on delete restrict,
  constraint business_expense_documents_document_fk
    foreign key (supplier_document_id)
    references public.supplier_documents(id)
    on delete restrict,
  constraint business_expense_documents_creator_fk
    foreign key (created_by_operator_id)
    references public.commercial_operators(operator_id)
    on delete restrict,
  constraint business_expense_documents_relation_type_valid check (
    relation_type in ('INVOICE', 'CREDIT_NOTE', 'RECEIPT', 'CONTRACT', 'OTHER')
  ),
  constraint business_expense_documents_classification_valid check (
    record_classification in ('production', 'internal_e2e')
  ),
  constraint business_expense_documents_pair_unique unique (
    business_expense_id, supplier_document_id
  )
);

create function public.prevent_business_expense_document_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'BUSINESS_EXPENSE_DOCUMENT_IMMUTABLE';
end;
$$;

create trigger trg_business_expense_documents_immutable
before update or delete on public.business_expense_documents
for each row execute function public.prevent_business_expense_document_mutation_v1();

alter table public.business_expense_documents enable row level security;

create function public.link_business_expense_document_v1(
  p_business_expense_id uuid,
  p_supplier_document_id uuid,
  p_relation_type text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_expense public.business_expenses%rowtype;
  v_document public.supplier_documents%rowtype;
  v_relation_type text := upper(btrim(p_relation_type));
  v_link_id uuid;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select *
  into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_operator.status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'BUSINESS_EXPENSE_DOCUMENT_OWNER_REQUIRED';
  end if;

  if p_business_expense_id is null then
    raise exception using errcode = '22023', message = 'BUSINESS_EXPENSE_REQUIRED';
  end if;
  if p_supplier_document_id is null then
    raise exception using errcode = '22023', message = 'SUPPLIER_DOCUMENT_REQUIRED';
  end if;
  if v_relation_type is null or v_relation_type not in (
    'INVOICE', 'CREDIT_NOTE', 'RECEIPT', 'CONTRACT', 'OTHER'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_EXPENSE_DOCUMENT_RELATION_TYPE';
  end if;

  select *
  into v_expense
  from public.business_expenses
  where id = p_business_expense_id
  for share;

  if not found then
    raise exception using errcode = 'P0001', message = 'BUSINESS_EXPENSE_NOT_FOUND';
  end if;

  select *
  into v_document
  from public.supplier_documents
  where id = p_supplier_document_id
  for share;

  if not found then
    raise exception using errcode = 'P0001', message = 'SUPPLIER_DOCUMENT_NOT_FOUND';
  end if;

  if v_expense.record_classification <> v_document.record_classification then
    raise exception using errcode = 'P0001', message = 'EXPENSE_DOCUMENT_CLASSIFICATION_MISMATCH';
  end if;

  begin
    insert into public.business_expense_documents (
      business_expense_id,
      supplier_document_id,
      relation_type,
      record_classification,
      created_by_operator_id
    ) values (
      v_expense.id,
      v_document.id,
      v_relation_type,
      v_expense.record_classification,
      v_operator.operator_id
    )
    returning id into v_link_id;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'BUSINESS_EXPENSE_DOCUMENT_ALREADY_LINKED';
  end;

  return v_link_id;
end;
$$;

revoke all on table public.business_expense_documents
from public, anon, authenticated, service_role;

revoke all on function public.prevent_business_expense_document_mutation_v1()
from public, anon, authenticated, service_role;

revoke all on function public.link_business_expense_document_v1(uuid, uuid, text)
from public, anon, authenticated, service_role;

grant execute on function public.link_business_expense_document_v1(uuid, uuid, text)
to authenticated;

comment on table public.business_expense_documents is
  'Immutable N:M evidence links between standalone business-expense and supplier-document authorities. Links do not allocate amounts or create payment, VAT, banking or supplier-matching authority.';

comment on column public.business_expense_documents.relation_type is
  'Controlled reason the document evidences the expense; never a payment state, VAT treatment or amount allocation.';

comment on column public.business_expense_documents.record_classification is
  'Classification copied from equal-classification expense and document authorities at immutable link creation.';

comment on function public.link_business_expense_document_v1(uuid, uuid, text) is
  'Owner-only immutable link creation boundary for existing same-classification business expenses and supplier documents.';
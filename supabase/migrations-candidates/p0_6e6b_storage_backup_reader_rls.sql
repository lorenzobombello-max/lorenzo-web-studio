-- P0-6E.6B INERT RLS CANDIDATE. DESIGN_ONLY_NOT_ACTIVATABLE. DO NOT APPLY.
-- Materialization requires a verified dedicated Auth user UUID and all activation gates.
-- Replace the deliberately invalid identity token only in a separately reviewed activation artifact.

begin;

do $p0_6e6b_activation_guard$
begin
  raise exception 'P0_6E6B_DESIGN_ONLY_NOT_ACTIVATABLE';
end;
$p0_6e6b_activation_guard$;

create policy lws_storage_backup_reader_select_v1 on storage.objects
for select to authenticated
using (
  auth.uid() = '<EXACT_DEDICATED_BACKUP_AUTH_UUID_REQUIRED>'::uuid
  and bucket_id in (
    'customer-request-quarantine',
    'quotation-artifacts',
    'recruitment-cvs',
    'supplier-documents'
  )
);

commit;

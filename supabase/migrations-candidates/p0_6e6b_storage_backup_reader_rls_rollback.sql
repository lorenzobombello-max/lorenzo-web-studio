-- P0-6E.6B INERT ROLLBACK CANDIDATE. REVIEW ONLY. DO NOT APPLY.
-- This rollback removes only the exact policy introduced by P0-6E.6B.

begin;

drop policy if exists lws_storage_backup_reader_select_v1 on storage.objects;

commit;

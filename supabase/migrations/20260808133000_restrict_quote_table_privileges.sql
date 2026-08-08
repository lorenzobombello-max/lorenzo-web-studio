revoke all privileges
on table public.quote_request_email_jobs
from public, anon, authenticated;

revoke insert, update, delete, truncate, references, trigger, maintain
on table public.quote_request_email_jobs
from service_role;

revoke all privileges
on table public.quote_requests
from public, anon, authenticated;

revoke delete, truncate, references, trigger, maintain
on table public.quote_requests
from service_role;

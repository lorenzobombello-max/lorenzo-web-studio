create type public.quote_request_intake_status as enum (
  'invited',
  'in_progress',
  'submitted',
  'reviewed'
);

create table public.quote_request_intakes (
  id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null,
  status public.quote_request_intake_status not null default 'invited',

  access_token_hash text not null,
  access_token_expires_at timestamptz not null,
  access_token_revoked_at timestamptz,

  started_at timestamptz,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  business_description text,
  target_audience text,
  has_existing_website boolean,
  existing_website_url text,
  elements_to_keep text,
  improvement_areas text,
  website_goals text[] not null default '{}'::text[],
  primary_conversion_goal text,

  requested_pages text[] not null default '{}'::text[],
  other_pages text,
  requested_features text[] not null default '{}'::text[],
  shop_required boolean not null default false,
  shop_details jsonb,
  booking_required boolean not null default false,
  booking_details jsonb,
  languages text[] not null default array['nl']::text[],

  design_styles text[] not null default '{}'::text[],
  brand_status text,
  logo_status text,
  brand_colors text[] not null default '{}'::text[],
  inspiration_sites text[] not null default '{}'::text[],
  disliked_styles text,

  content_status text,
  image_status text,
  image_support text[] not null default '{}'::text[],

  domain_status text,
  domain_name text,
  hosting_status text,
  hosting_support text,

  maintenance_interest text,
  seo_priority text,
  seo_keywords text[] not null default '{}'::text[],
  social_channels text[] not null default '{}'::text[],
  integrations text[] not null default '{}'::text[],

  deadline_date date,
  deadline_reason text,
  budget_confirmed boolean,
  budget_update_category text,
  budget_notes text,

  priorities text[] not null default '{}'::text[],
  additional_notes text,
  confirmation boolean not null default false,

  constraint quote_request_intakes_quote_request_key unique (quote_request_id),
  constraint quote_request_intakes_quote_request_fkey
    foreign key (quote_request_id)
    references public.quote_requests (id)
    on delete cascade,
  constraint quote_request_intakes_access_token_hash_key unique (access_token_hash),
  constraint quote_request_intakes_access_token_hash_not_blank
    check (char_length(btrim(access_token_hash)) >= 32),
  constraint quote_request_intakes_access_token_expiry_after_creation
    check (access_token_expires_at > created_at),
  constraint quote_request_intakes_submitted_state_valid
    check (
      status <> 'submitted'
      or (started_at is not null and submitted_at is not null and confirmation = true)
    ),
  constraint quote_request_intakes_reviewed_state_valid
    check (
      status <> 'reviewed'
      or (
        started_at is not null
        and submitted_at is not null
        and reviewed_at is not null
        and confirmation = true
      )
    ),
  constraint quote_request_intakes_in_progress_state_valid
    check (status <> 'in_progress' or started_at is not null),
  constraint quote_request_intakes_shop_details_object
    check (shop_details is null or jsonb_typeof(shop_details) = 'object'),
  constraint quote_request_intakes_shop_details_when_required
    check (shop_required = true or shop_details is null),
  constraint quote_request_intakes_booking_details_object
    check (booking_details is null or jsonb_typeof(booking_details) = 'object'),
  constraint quote_request_intakes_booking_details_when_required
    check (booking_required = true or booking_details is null),
  constraint quote_request_intakes_existing_website_url_valid
    check (has_existing_website is distinct from false or existing_website_url is null),
  constraint quote_request_intakes_brand_status_valid
    check (brand_status is null or brand_status in ('complete', 'partial', 'none', 'unknown')),
  constraint quote_request_intakes_logo_status_valid
    check (logo_status is null or logo_status in ('available', 'needs_update', 'needed', 'unknown')),
  constraint quote_request_intakes_content_status_valid
    check (content_status is null or content_status in ('complete', 'partial', 'none', 'needs_help')),
  constraint quote_request_intakes_image_status_valid
    check (image_status is null or image_status in ('sufficient', 'partial', 'none')),
  constraint quote_request_intakes_domain_status_valid
    check (domain_status is null or domain_status in ('has_domain', 'no_domain', 'unknown')),
  constraint quote_request_intakes_hosting_status_valid
    check (hosting_status is null or hosting_status in ('has_hosting', 'no_hosting', 'unknown')),
  constraint quote_request_intakes_hosting_support_valid
    check (hosting_support is null or hosting_support in ('yes', 'no', 'advice')),
  constraint quote_request_intakes_maintenance_interest_valid
    check (maintenance_interest is null or maintenance_interest in ('yes', 'no', 'maybe', 'info_requested')),
  constraint quote_request_intakes_seo_priority_valid
    check (seo_priority is null or seo_priority in ('high', 'basic', 'low', 'unsure')),
  constraint quote_request_intakes_budget_update_category_valid
    check (
      budget_update_category is null
      or budget_update_category in (
        'Tot EUR 1.500',
        'EUR 1.500 - EUR 3.000',
        'EUR 3.000 - EUR 6.000',
        'Meer dan EUR 6.000'
      )
    )
);

create index idx_quote_request_intakes_status
  on public.quote_request_intakes (status, updated_at desc);

create index idx_quote_request_intakes_access_token_expires_at
  on public.quote_request_intakes (access_token_expires_at);

create trigger trg_quote_request_intakes_set_updated_at
before update on public.quote_request_intakes
for each row
execute function public.set_quote_requests_updated_at();

alter table public.quote_request_intakes enable row level security;

revoke all privileges
on table public.quote_request_intakes
from public, anon, authenticated;

grant select, insert, update
on table public.quote_request_intakes
to service_role;

revoke delete, truncate, references, trigger, maintain
on table public.quote_request_intakes
from service_role;

create table if not exists public.samantha_key_subscription_access (
  original_transaction_id text primary key,
  product_id text not null,
  status text not null default 'unknown',
  expires_at timestamptz,
  environment text,
  last_transaction_id text,
  token_requests integer not null default 0,
  last_token_request_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists samantha_key_subscription_access_status_idx
  on public.samantha_key_subscription_access(status, expires_at);

alter table public.samantha_key_subscription_access enable row level security;

drop policy if exists "No direct client access" on public.samantha_key_subscription_access;
create policy "No direct client access"
  on public.samantha_key_subscription_access
  for all
  using (false)
  with check (false);

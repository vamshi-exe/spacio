-- Tiles AI — Supabase schema
-- Run this once in: Supabase Dashboard → SQL Editor → New query → Run.
-- It is safe to re-run (idempotent).

-- ── PROFILES ────────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  full_name    text,
  plan         text not null default 'Free',
  renders_left integer not null default 50,
  created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert with check (auth.uid() = id);

-- Auto-create a profile row whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── PROJECTS ────────────────────────────────────────────────────────────────
create table if not exists public.projects (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  name             text not null,
  surface          text not null,
  room_image_url   text,
  tile_image_url   text,
  result_image_url text,
  notes            text default '',
  created_at       timestamptz not null default now()
);

alter table public.projects enable row level security;

drop policy if exists "projects_select_own" on public.projects;
create policy "projects_select_own"
  on public.projects for select using (auth.uid() = user_id);

drop policy if exists "projects_insert_own" on public.projects;
create policy "projects_insert_own"
  on public.projects for insert with check (auth.uid() = user_id);

drop policy if exists "projects_delete_own" on public.projects;
create policy "projects_delete_own"
  on public.projects for delete using (auth.uid() = user_id);

create index if not exists projects_user_created_idx
  on public.projects (user_id, created_at desc);

-- ── RENDER CREDITS ──────────────────────────────────────────────────────────
-- Purchased top-up renders. Consumed only after the monthly quota is spent,
-- and carried forward across billing cycles until used. (Safe to re-run.)
alter table public.profiles
  add column if not exists topup_renders_left integer not null default 0;

-- Included monthly renders per SPACIO plan (BYOD 300, Standard 300, Pro 400).
-- Mirrors lib/models/subscription_plan.dart. Unknown / 'Free' → 50 (trial).
create or replace function public.plan_included_renders(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'SPACIO BYOD'     then 300
    when 'SPACIO Standard' then 300
    when 'SPACIO Pro'      then 400
    else 50
  end;
$$;

-- Reset the caller's monthly included renders to their plan allowance. Call
-- this from your billing-cycle webhook / scheduled job at the start of each
-- cycle. Top-up renders are intentionally left untouched (they carry forward).
create or replace function public.reset_monthly_renders()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  new_left integer;
begin
  update public.profiles
    set renders_left = public.plan_included_renders(plan)
    where id = auth.uid()
    returning renders_left into new_left;
  return coalesce(new_left, 0);
end;
$$;

-- ── MERCHANT TYPE & SUBSCRIPTIONS ────────────────────────────────────────────
-- Two merchant types:
--   'device' (Type 1) — bought a SPACIO tablet; subscription is PRELOADED, set
--                       by admin/provisioning. They never pay in-app.
--   'byod'   (Type 2) — install on their own device; they PURCHASE the BYOD
--                       subscription monthly (manual renewal).
-- Self-signups default to 'byod'; admin sets 'device' + plan when shipping a unit.
alter table public.profiles
  add column if not exists merchant_type text not null default 'byod';

-- When the current subscription lapses. NULL = none / preloaded (device type
-- is treated as always-active in the app).
alter table public.profiles
  add column if not exists subscription_active_until timestamptz;

-- One row per BYOD subscription payment (manual monthly).
create table if not exists public.subscription_payments (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users (id) on delete cascade,
  plan                text not null,
  amount_inr          integer not null,
  razorpay_payment_id text,
  razorpay_order_id   text,
  period_start        timestamptz not null,
  period_end          timestamptz not null,
  created_at          timestamptz not null default now()
);

alter table public.subscription_payments enable row level security;

drop policy if exists "subpay_select_own" on public.subscription_payments;
create policy "subpay_select_own"
  on public.subscription_payments for select using (auth.uid() = user_id);

create index if not exists subpay_user_created_idx
  on public.subscription_payments (user_id, created_at desc);

-- Activate / renew a BYOD subscription for one month after a successful payment.
-- Extends from the later of now() or the current expiry (early renewals stack),
-- sets the plan, and resets the monthly render allowance for the new cycle.
-- Top-up renders are left untouched. Returns the new expiry.
--
-- NOTE: In production verify the Razorpay signature server-side before calling.
create or replace function public.activate_byod_subscription(
  p_plan       text,
  p_amount     integer,
  p_payment_id text default null,
  p_order_id   text default null
)
returns timestamptz
language plpgsql
security definer set search_path = public
as $$
declare
  current_until timestamptz;
  new_until     timestamptz;
begin
  select subscription_active_until into current_until
    from public.profiles where id = auth.uid();

  new_until := greatest(coalesce(current_until, now()), now())
               + interval '30 days';

  insert into public.subscription_payments
    (user_id, plan, amount_inr, razorpay_payment_id, razorpay_order_id,
     period_start, period_end)
  values
    (auth.uid(), p_plan, p_amount, p_payment_id, p_order_id, now(), new_until);

  update public.profiles
    set plan = p_plan,
        subscription_active_until = new_until,
        renders_left = public.plan_included_renders(p_plan)
    where id = auth.uid();

  return new_until;
end;
$$;

-- Spend one credit atomically: monthly included renders first, then top-up.
-- Returns the total remaining (monthly + top-up).
create or replace function public.consume_render()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  remaining integer;
begin
  update public.profiles
    set
      renders_left = case
        when renders_left > 0 then renders_left - 1
        else renders_left
      end,
      topup_renders_left = case
        when renders_left <= 0 and topup_renders_left > 0
          then topup_renders_left - 1
        else topup_renders_left
      end
    where id = auth.uid()
    returning renders_left + topup_renders_left into remaining;
  return coalesce(remaining, 0);
end;
$$;

-- ── RENDER TOP-UPS (purchases) ──────────────────────────────────────────────
create table if not exists public.topup_purchases (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users (id) on delete cascade,
  pack_id             text not null,
  renders             integer not null,
  amount_inr          integer not null,
  razorpay_payment_id text,
  razorpay_order_id   text,
  created_at          timestamptz not null default now()
);

alter table public.topup_purchases enable row level security;

drop policy if exists "topup_select_own" on public.topup_purchases;
create policy "topup_select_own"
  on public.topup_purchases for select using (auth.uid() = user_id);

drop policy if exists "topup_insert_own" on public.topup_purchases;
create policy "topup_insert_own"
  on public.topup_purchases for insert with check (auth.uid() = user_id);

create index if not exists topup_user_created_idx
  on public.topup_purchases (user_id, created_at desc);

-- Record a successful top-up purchase and credit the renders atomically.
-- Returns the user's new top-up balance.
--
-- NOTE: In production call this only AFTER verifying the Razorpay payment
-- signature server-side (Edge Function) with the key secret. Crediting on the
-- client success callback alone is not tamper-proof.
create or replace function public.add_topup_renders(
  p_pack       text,
  p_renders    integer,
  p_amount     integer,
  p_payment_id text default null,
  p_order_id   text default null
)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  new_balance integer;
begin
  insert into public.topup_purchases
    (user_id, pack_id, renders, amount_inr, razorpay_payment_id, razorpay_order_id)
  values
    (auth.uid(), p_pack, p_renders, p_amount, p_payment_id, p_order_id);

  update public.profiles
    set topup_renders_left = topup_renders_left + p_renders
    where id = auth.uid()
    returning topup_renders_left into new_balance;

  return coalesce(new_balance, 0);
end;
$$;

-- ── CLIENTS (CRM) ───────────────────────────────────────────────────────────
create table if not exists public.clients (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null,
  phone      text,
  email      text,
  company    text,
  notes      text default '',
  created_at timestamptz not null default now()
);

alter table public.clients enable row level security;

drop policy if exists "clients_select_own" on public.clients;
create policy "clients_select_own"
  on public.clients for select using (auth.uid() = user_id);

drop policy if exists "clients_insert_own" on public.clients;
create policy "clients_insert_own"
  on public.clients for insert with check (auth.uid() = user_id);

drop policy if exists "clients_update_own" on public.clients;
create policy "clients_update_own"
  on public.clients for update using (auth.uid() = user_id);

drop policy if exists "clients_delete_own" on public.clients;
create policy "clients_delete_own"
  on public.clients for delete using (auth.uid() = user_id);

create index if not exists clients_user_created_idx
  on public.clients (user_id, created_at desc);

-- Link a visualization to the client it was created for (added after both
-- tables exist; safe to re-run).
alter table public.projects
  add column if not exists client_id uuid references public.clients (id)
  on delete set null;

create index if not exists projects_client_idx
  on public.projects (client_id);

-- ── CATALOGUE (merchant products) ────────────────────────────────────────────
-- Tiles & marbles a merchant pre-loads so a rep can pick a product on the tile
-- screen without photographing it. `category` is 'tiles' | 'marbles'. `tags`
-- are free-form highlight labels (e.g. 'Hot Selling', 'Top Picks').
create table if not exists public.catalogue_items (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  category       text not null default 'tiles',
  name           text not null,
  image_url      text,
  width          numeric,
  height         numeric,
  size_unit      text not null default 'mm',
  price_per_sqft numeric,
  gst_percent    numeric not null default 18,
  tags           text[] not null default '{}',
  created_at     timestamptz not null default now()
);

alter table public.catalogue_items enable row level security;

drop policy if exists "catalogue_select_own" on public.catalogue_items;
create policy "catalogue_select_own"
  on public.catalogue_items for select using (auth.uid() = user_id);

drop policy if exists "catalogue_insert_own" on public.catalogue_items;
create policy "catalogue_insert_own"
  on public.catalogue_items for insert with check (auth.uid() = user_id);

drop policy if exists "catalogue_update_own" on public.catalogue_items;
create policy "catalogue_update_own"
  on public.catalogue_items for update using (auth.uid() = user_id);

drop policy if exists "catalogue_delete_own" on public.catalogue_items;
create policy "catalogue_delete_own"
  on public.catalogue_items for delete using (auth.uid() = user_id);

create index if not exists catalogue_user_created_idx
  on public.catalogue_items (user_id, created_at desc);

-- ── WHATSAPP SENDS (log) ────────────────────────────────────────────────────
-- One row per quotation sent to a client over WhatsApp. Written by the
-- send-whatsapp-quotation Edge Function (service role). Users can read their own.
create table if not exists public.whatsapp_sends (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users (id) on delete cascade,
  to_phone            text not null,
  client_name         text,
  pdf_url             text,
  summary             text,
  status              text not null default 'sent',
  provider_message_id text,
  error               text,
  created_at          timestamptz not null default now()
);

alter table public.whatsapp_sends enable row level security;

drop policy if exists "whatsapp_select_own" on public.whatsapp_sends;
create policy "whatsapp_select_own"
  on public.whatsapp_sends for select using (auth.uid() = user_id);

create index if not exists whatsapp_user_created_idx
  on public.whatsapp_sends (user_id, created_at desc);

-- ── EMAIL SENDS (log) ───────────────────────────────────────────────────────
-- One row per quotation emailed to a client. Written by the
-- send-quotation-email Edge Function (service role). Users can read their own.
create table if not exists public.email_sends (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users (id) on delete cascade,
  to_email            text not null,
  client_name         text,
  pdf_url             text,
  summary             text,
  status              text not null default 'sent',
  provider_message_id text,
  error               text,
  created_at          timestamptz not null default now()
);

alter table public.email_sends enable row level security;

drop policy if exists "email_select_own" on public.email_sends;
create policy "email_select_own"
  on public.email_sends for select using (auth.uid() = user_id);

create index if not exists email_user_created_idx
  on public.email_sends (user_id, created_at desc);

-- ── PROJECT QUOTATION DATA ──────────────────────────────────────────────────
-- Tile & estimate details saved with each visualization so the quotation PDF
-- can be regenerated (download / email) later from the project detail screen.
-- Older rows keep NULLs; the app falls back to manual entry. (Safe to re-run.)
alter table public.projects
  add column if not exists tile_name      text default '',
  add column if not exists tile_width     numeric,
  add column if not exists tile_height    numeric,
  add column if not exists size_unit      text default 'mm',
  add column if not exists price_per_sqft numeric,
  add column if not exists cartage_fee    numeric,
  add column if not exists gst_percent    numeric default 18,
  add column if not exists area_sqft      numeric;

-- ── ADMIN (merchant management) ──────────────────────────────────────────────
-- The admin dashboard (separate web app) manages merchants across accounts.
-- Admins are identified by an email allowlist; RLS grants allowlisted users
-- read/write on every profile while normal merchants stay limited to their own.

-- Store each merchant's email on their profile so the dashboard can list &
-- search without touching auth.users. Kept in sync by the signup trigger below.
alter table public.profiles
  add column if not exists email text;

-- Backfill emails for existing accounts (safe to re-run).
update public.profiles p
  set email = u.email
  from auth.users u
  where u.id = p.id and p.email is distinct from u.email;

-- Recreate the signup trigger to also capture the email.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Allowlist of admin emails. Add a row per admin (see admin/README.md).
create table if not exists public.admin_emails (
  email      text primary key,
  created_at timestamptz not null default now()
);

alter table public.admin_emails enable row level security;

-- Seed the initial admin. Edit this address / add rows for more admins.
insert into public.admin_emails (email)
  values ('vamshi.vadnala@ensowebworks.com')
  on conflict (email) do nothing;

-- True when the current request's email is on the allowlist. SECURITY DEFINER
-- so it can read admin_emails regardless of that table's own policies, and so
-- it is safe to call from the RLS policies below without recursion.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.admin_emails
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- Only admins can read the allowlist (used by the dashboard).
drop policy if exists "admin_emails_select_admin" on public.admin_emails;
create policy "admin_emails_select_admin"
  on public.admin_emails for select using (public.is_admin());

-- Admins can read & update every merchant profile. These are additive to the
-- existing own-row policies, which remain in force for normal merchants.
drop policy if exists "profiles_select_admin" on public.profiles;
create policy "profiles_select_admin"
  on public.profiles for select using (public.is_admin());

drop policy if exists "profiles_update_admin" on public.profiles;
create policy "profiles_update_admin"
  on public.profiles for update using (public.is_admin());

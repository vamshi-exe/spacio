# SPACIO Admin Dashboard

A standalone web dashboard for managing merchants (the app's `profiles`). It is a
zero-build static site — plain HTML/CSS/JS that talks directly to Supabase using
the project's **public** anon key. All access is enforced server-side by Row
Level Security plus an **admin email allowlist**, so opening this page grants no
data to anyone who isn't an allowlisted admin.

## What it does

- **View & search** every merchant (name, email, plan, type, render balance,
  subscription status).
- **Set plan & type** — change `plan` and `merchant_type` (`byod` vs `device`).
- **Manage subscription** — set / extend (+30d, +1yr) / clear
  `subscription_active_until`.
- **Adjust render credits** — edit monthly (`renders_left`) and top-up
  (`topup_renders_left`) balances, with an optional "reset to plan allowance".

## 1. Apply the database changes

Run the project schema once (idempotent) in **Supabase → SQL Editor**:

- File: [`../supabase/schema.sql`](../supabase/schema.sql)

The new **ADMIN** section adds an `email` column to `profiles` (backfilled), the
`public.admin_emails` allowlist, an `is_admin()` helper, and admin RLS policies
so allowlisted users can read/update every profile.

## 2. Add your admin email(s)

The schema seeds one admin address. Add or change admins any time:

```sql
insert into public.admin_emails (email) values ('you@company.com')
  on conflict (email) do nothing;
```

An admin must also be a normal Supabase **Auth user** (sign up in the mobile app
or via the Supabase dashboard) — the allowlist only grants elevated access to an
account that already exists.

## 3. Run it

It's a static folder — serve it with anything:

```bash
# from the repo root
cd admin
python3 -m http.server 5173
#   → open http://localhost:5173
```

or `npx serve` / VS Code "Live Server". Sign in with an allowlisted admin email
and password.

## 4. Deploy (optional)

Upload the `admin/` folder to any static host — Netlify, Vercel, Cloudflare
Pages, GitHub Pages, or Supabase Storage. No build step, no environment
variables: [`config.js`](config.js) holds the public Supabase URL + anon key.

## Security notes

- The anon key is safe to publish — it's the same one shipped in the mobile app
  ([`lib/config/app_config.dart`](../lib/config/app_config.dart)). Security comes
  from RLS + `admin_emails`, not from hiding the key.
- To revoke an admin, delete their row from `public.admin_emails`.
- Admins can currently **view and edit** merchants (no create/delete). Deleting a
  merchant should still be done via Supabase Auth so the `auth.users` row and its
  cascade are handled correctly.

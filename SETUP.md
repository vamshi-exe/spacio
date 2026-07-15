# Backend setup (Supabase + Cloudinary)

The app runs without keys — it shows an in-app setup screen until you complete
the steps below. All keys live in a gitignored `.env` file at the project root:

```sh
cp .env.example .env   # then fill in the values below
```

Once the four Supabase/Cloudinary values in `.env` are filled, restart the app
(full restart, not hot-reload — `.env` is a bundled asset) and the login screen
appears.

## 1. Supabase

1. Create a project at https://supabase.com.
2. **SQL Editor → New query** → paste `supabase/schema.sql` → **Run**.
   This creates the `profiles`, `projects` and `clients` (CRM) tables,
   row-level security policies, the new-user trigger, and the
   `consume_render()` function. Re-run it any time you pull schema changes —
   it's idempotent.
3. **Project Settings → API** → copy the **Project URL** and the
   **anon / public key**.
4. (Optional, for fast testing) **Authentication → Providers → Email** →
   turn **Confirm email** off so sign-up logs you straight in. Leave it on for
   production.

Paste into `.env`:

```sh
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
```

## 2. Cloudinary

1. Create an account at https://cloudinary.com — note your **Cloud name**
   (Dashboard).
2. **Settings → Upload → Upload presets → Add upload preset**. Set
   **Signing Mode = Unsigned** and save. Copy the preset name.

Paste into `.env`:

```sh
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_UPLOAD_PRESET=your-unsigned-preset
```

## How data flows

- **Auth**: email/password via Supabase. A `profiles` row (plan + render
  credits) is created automatically on sign-up.
- **Generate**: room photo → tile photo → OpenAI render. On success the three
  images upload to Cloudinary and a `projects` row is saved; one render credit
  is spent via `consume_render()`.
- **Dashboard**: greeting, today/this-week counts, renders left, and recent
  projects are all read live from Supabase (pull-to-refresh supported).

## ⚠️ Security note

`.env` is bundled as a Flutter asset, so everything in it (including
`OPENAI_API_KEY`) still ships inside the app binary — it only keeps keys out
of source control. Before any real release, move generation behind a server
(e.g. a Supabase Edge Function) so the OpenAI key never reaches the client.

Server-side secrets (e.g. the Razorpay **key secret**) belong in
`supabase/.env` — never in the root `.env` — and are pushed with
`supabase secrets set --env-file supabase/.env`.

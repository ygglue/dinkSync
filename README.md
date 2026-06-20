# dinkSync

A pickleball social app + CRM. Players find a court, pay entry, and get matched
into a 4-player doubles game by skill. Court owners list courts, pay a
subscription, manage staff, and track revenue.

See [`PLAN.md`](./PLAN.md) for the full architecture, scope, and build phases.

## Status

**Phase 0 — Foundation (complete)**

This phase delivers the foundation everything else builds on:
- Supabase schema (12 tables) + Row Level Security
- `pg_cron` + `pgjwt` extensions enabled
- Flutter app scaffolded with auth (email + password, Google OAuth) and a profile screen
- The seam for payments (`PaymentService` interface + `MockPaymentService`)

The Phase 0 demo proves: a user can sign in, read/write their own profile, and
**RLS blocks them from reading anyone else's** — even though the anon key ships
in the client.

## Prerequisites

- Flutter 3.44+ (includes Dart 3.12+)
- Supabase CLI 2.x (`npm i -g supabase`)
- Docker (for local Supabase stack)

## Project layout

```
dinkSync/
├── app/                      # Flutter app
│   └── lib/
│       ├── main.dart
│       ├── app/              # router, theme
│       ├── config/           # app_config (env)
│       ├── data/             # supabase client
│       ├── features/         # auth, profile, ... (owner/player/etc later)
│       └── services/         # payment_service (interface + mock)
├── supabase/
│   ├── migrations/           # 0000_extensions → 0002_rls_policies, ...
│   ├── seed.sql              # dev seed (1 court, 1 owner, 1 staff, 4 players)
│   └── config.toml
└── PLAN.md
```

## Phase 0 setup

### 1. Backend (local Supabase)

```bash
cd supabase
supabase start          # pulls + starts the local stack (Docker)
supabase db reset       # runs all migrations + seed.sql
```

OTP emails sent during local dev are caught by **Inbucket** at
http://127.0.0.1:54324 — open it to read the 6-digit codes.

Grab your local keys for the app:

```bash
supabase status
# copy "API URL"  -> SUPABASE_URL
# copy "anon key" -> SUPABASE_ANON_KEY
```

### 2. App

```bash
cd app
cp .env.example .env
# fill in SUPABASE_URL + SUPABASE_ANON_KEY from `supabase status`
flutter pub get
flutter run
```

### 3. Linking a hosted project (optional, later)

```bash
cd supabase
supabase link --project-ref <your-project-ref>
supabase db push
```

## Phase 0 demo (proves auth + RLS)

1. Launch the app → you land on **/auth**.
2. **Sign up:** enter email + new password → "Create account". You're
   immediately signed in; a `profiles` row is auto-created by a trigger.
3. **Or:** click "Continue with Google" → OAuth pop-up → pick your account
   → signed in with name + avatar populated from your Google profile.
4. You're redirected to **/profile**. Edit display name / avatar → "Save".
5. Note the **RLS probe** banner: "cannot see other users' rows ✓".
6. "Sign out" → you're bounced back to /auth. Sign back in with the same
   email+password or with Google to confirm the round-trip.

## Verify it compiles

```bash
cd app
flutter analyze      # should be clean
```

## What's next

Per `PLAN.md`, **Phase 1** is owner + court setup: owner onboarding, dashboard
(empty states), staff management, and the admin view of all courts.

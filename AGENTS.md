# AGENTS.md — dinkSync Project Handoff

> Everything a new agent (or returning session) needs to pick up this project
> and work on it productively. Read this file first, then PLAN.md for the full
> architecture rationale.

---

## 1. What is dinkSync?

A pickleball social app + CRM with 4 user roles: **Admin** (platform operator),
**Court Owner** (lists courts, subscribes, manages staff/revenue), **Court Staff**
(accepts payments, operates the queue), and **Player** (finds courts, pays entry,
gets matched into 4-player doubles games by MMR skill rating).

The core loop: Player opens app → picks a court → pays entry → chooses solo or
invites a partner → matchmaking groups 4 players by MMR → group queues for an
open court slot → match is played → score entered → Elo MMR updates.

**Domain:** Pickleball (doubles = 4 players per match). "Dink" = a pickleball shot.

---

## 2. Environment & Tooling

| Tool | Version | Location |
|---|---|---|
| Flutter | 3.44.2 (Dart 3.12.2) | `C:\Users\Eli\flutter\bin\flutter` |
| Supabase CLI | 2.107.0 | npm global (`npm i -g supabase`) |
| Node | v25.8.0 | system PATH |
| Git | 2.53.0 | system PATH |
| Docker | required for `supabase start` | must be running |

**IMPORTANT:** Flutter is NOT on the system PATH visible to bash. Use the full
path: `C:\Users\Eli\flutter\bin\flutter` or `/c/Users/Eli/flutter/bin/flutter`.

### Quick setup for a new agent

```bash
# 1. Verify tooling
flutter --version          # if not found, use: /c/Users/Eli/flutter/bin/flutter
supabase --version
node --version

# 2a. Hosted Supabase (RECOMMENDED — no Docker required)
#     Create a project at https://supabase.com/dashboard, then copy:
#       - Project URL       (Settings → API)
#       - anon public key   (Settings → API)
#     Disable "Confirm email" in Auth → Sign In/Up → Email
#     (this lets OTP password reset work without a confirmation step).
#     Push the schema:
cd supabase
supabase login
supabase link --project-ref <your-project-ref>
supabase db push            # applies all migrations in order

# 2b. Local Supabase (ALTERNATIVE — requires Docker Desktop)
#     cd supabase
#     supabase start         # starts Postgres, Auth, Realtime, Storage, Studio, Inbucket
#     supabase db reset      # applies all migrations + seed.sql
#     supabase status        # copy API URL + anon key
#     # OTP emails are caught at http://127.0.0.1:54324 (Inbucket)

# 3. Configure app
cd ../app
cp .env.example .env        # fill in SUPABASE_URL + SUPABASE_ANON_KEY
# ⚠ .env is BUNDLED into web builds at build time — hot reload won't
#   pick up changes; you need a full restart (R or stop+rebuild).
# ⚠ .env is NOT in Flutter's default .gitignore — add it before git init.

# 4. Run the app
flutter pub get             # or /c/Users/Eli/flutter/bin/flutter pub get
flutter run -d chrome       # web (recommended) or any connected device

# 5. Verify
flutter analyze             # should be clean
flutter test                # 3+ passing tests (theme + config)
```

---

## 3. Stack Decisions (LOCKED — do not change without explicit user approval)

| Decision | Choice | Rationale |
|---|---|---|
| **Mobile framework** | Flutter | Cross-platform iOS + Android |
| **Backend** | Pure Supabase | Postgres + Auth + Realtime + Storage + Edge Functions |
| **Data access** | `supabase_flutter` + RLS | Client talks to Postgres directly; Postgres enforces security |
| **Server logic** | Postgres RPC (plpgsql) via thin Edge Functions | NOT a custom API server; NOT Drizzle ORM |
| **Matchmaking** | `pg_cron` sweep (~5s) | Background job forms groups + assigns slots |
| **MMR system** | Simple Elo | `profiles.mmr` int, default 1000, K=32 |
| **Auth** | Supabase Auth (email + password, Google OAuth; Apple OAuth deferred) | JWT; RLS ties rows to `auth.uid()` |
| **Realtime** | Supabase Realtime | Postgres changes broadcast on channels |
| **State management** | Riverpod | `flutter_riverpod: ^2.6.1` |
| **Routing** | GoRouter | `go_router: ^14.6.0` |
| **Payments** | `PaymentService` interface → `MockPaymentService` | Abstract seam; swap to real provider when region is decided |
| **Push notifications** | FCM via `firebase_messaging` | For Phase 4 |
| **Maps** | `google_maps_flutter` | For Phase 1+ |

**Explicitly NOT in the stack:** Drizzle ORM, custom Node/Bun API server,
Socket.io, Prisma, Firebase, Express, Django, SQLalchemy. These were all
considered and rejected.

---

## 4. Project Structure

```
dinkSync/
├── AGENTS.md                  ← THIS FILE
├── PLAN.md                    ← Full architecture plan (read for design rationale)
├── README.md                  ← Setup instructions + Phase 0 demo steps
├── .gitignore
│
├── app/                       ← Flutter app
│   ├── .env                   ← Secrets (gitignored). Copy from .env.example
│   ├── .env.example           ← Template for env vars
│   ├── pubspec.yaml           ← Dependencies
│   ├── analysis_options.yaml  ← Lint rules (flutter_lints)
│   ├── lib/
│   │   ├── main.dart              ← Entry: load .env, init Supabase, run app
│   │   ├── app/
│   │   │   ├── router.dart        ← GoRouter: /auth, /profile, auth-aware redirect
│   │   │   └── theme.dart         ← Material 3 court-green theme (seed #2E7D32)
│   │   ├── config/
│   │   │   └── app_config.dart    ← .env loader, AppConfigError
│   │   ├── data/
│   │   │   └── supabase_client.dart ← Supabase init, global `supabase` getter,
│   │   │                               authStateProvider, isSignedInProvider
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   │   ├── auth_repository.dart  ← AuthRepository (sendOtp, verifyOtp, signOut — PLANNED: signIn/SignUpWithPassword, signInWithGoogle)
│   │   │   │   └── auth_screen.dart      ← Email+OTP two-step UI — PLANNED: Sign In / Sign Up tabs, email+password, "Continue with Google"
│   │   │   └── profile/
│   │   │       └── profile_screen.dart   ← Profile CRUD + RLS probe banner
│   │   └── services/
│   │       └── payment_service.dart ← PaymentService interface + MockPaymentService
│   └── test/
│       └── widget_test.dart       ← Smoke tests (theme builds, AppConfigError)
│
├── supabase/                  ← Supabase project (CLI-managed)
│   ├── config.toml             ← Local stack config (Postgres 17, ports, auth settings)
│   ├── seed.sql                ← Dev seed: 1 court, 1 owner, 1 staff, 4 players, 2 slots
│   └── migrations/
│       ├── 0000_extensions.sql      ← pg_cron + pgjwt
│       ├── 0001_init_schema.sql      ← All 12 tables, indexes, triggers
│       ├── 0002_rls_policies.sql     ← RLS per table + helper functions
│       └── 0002b_seed_helpers.sql   ← _seed_user() for dev seeding
│
└── docs/
    └── DECISIONS.md            ← ADR-style log (ADR-001 auth, ADR-002 passkeys, ADR-003 hosted Supabase)
```

---

## 5. Database Schema (12 tables)

All IDs are `uuid` with `gen_random_uuid()` default. Money is `integer` cents +
ISO 4217 `currency` code (never floats). Timestamps are `timestamptz`.

### Tables

| Table | Purpose | Key fields |
|---|---|---|
| `profiles` | 1:1 with `auth.users` | `id` (PK → auth.users), `display_name`, `avatar_url`, `mmr` (default 1000), `is_platform_admin` |
| `courts` | Physical venue | `owner_profile_id` (FK → profiles), `name`, `lat`/`lng`, `entry_fee_cents`, `currency`, `num_courts`, `status` (active/suspended/offboarded) |
| `court_members` | Owner + staff per court | Composite PK `(court_id, profile_id)`, `role` (owner/staff), `can_accept_payment`, `added_by` |
| `subscriptions` | Owner pays admin | `court_id`, `plan` (monthly/yearly), `status` (active/past_due/canceled), `amount_cents`, `provider` (mock/stripe/gcash/maya/offline) |
| `matchmaking_requests` | Player wants a game | `court_id`, `profile_id`, `party_size_wanted` (1=solo, 2=with partner), `partner_profile_id`, `status` (open/matched/expired/canceled), `mmr_at_request` |
| `match_groups` | Formed group of 4 | `court_id`, `status` (forming/queued/assigned/playing/done), `slot_label` |
| `match_group_members` | Who's in a group | Composite PK `(match_group_id, profile_id)`, `is_initiator`, `is_invited_partner` |
| `court_slots` | Physical court surface | `court_id`, `label` ("Court 1"), `status` (open/occupied/closed), `current_group_id` |
| `queue_entries` | Group waiting for slot | `match_group_id` (PK), `court_id`, `position`, `enqueued_at` |
| `matches` | Played game | `match_group_id`, `court_id`, `played_at`, `status` (pending_confirm/completed/disputed), `winning_team` (1/2) |
| `match_results` | Per-player outcome | Composite PK `(match_id, profile_id)`, `team` (1/2), `result` (win/loss), `mmr_before`, `mmr_after` |
| `payments` | Every money event | `payer_profile_id`, `payee_court_id`, `kind` (entry/subscription), `amount_cents`, `currency`, `status` (pending/paid/failed/refunded), `provider` (mock/stripe/gcash/maya/offline), `collected_by_member_id` |

### Auto-triggers
- `handle_new_user()`: fires on `auth.users` insert → auto-creates `profiles` row
  with email prefix as default display name.
- `touch_updated_at()`: fires on update of `profiles`, `courts`, `court_slots`
  → sets `updated_at = now()`.

### Seed data (from `seed.sql`)
- **Owner:** `owner@dinksync.dev` (uuid `1111...`) — owns "Demo Pickleball Club" in NYC
- **Staff:** `staff@dinksync.dev` (uuid `2222...`) — payment-enabled staff member
- **Players:** `p1-4@dinksync.dev` (uuids `a1111...` to `a4444...`) — MMRs 1050, 1030, 980, 1010
- **Court:** 1 court with 2 open slots ("Court 1", "Court 2"), entry fee $10.00 USD

### RLS (Row Level Security)

RLS is enabled on all 12 tables. Key patterns:

- **Helper functions** (`is_court_member`, `is_court_owner`, `is_platform_admin`)
  keep policies readable.
- **Client reads:** `profiles` (everyone), `courts` (everyone), `court_slots` (everyone).
- **Owner-scoped reads:** `court_members`, `subscriptions` (owner + admin).
- **Participant reads:** `matchmaking_requests`, `match_groups`, `match_group_members`,
  `queue_entries`, `matches`, `match_results` (self + court members + admin).
- **Client writes (limited):** `profiles` (self), `courts` (owner), `court_members`
  (owner), `matchmaking_requests` (self — cancel only), `payments` (payer).
- **RPC-only writes:** `subscriptions`, `match_groups`, `match_group_members`,
  `queue_entries`, `matches`, `match_results` — no client insert/update/delete
  policies. These use the service-role key in Edge Functions.

---

## 6. Flutter App Architecture

### Conventions
- **Feature-based structure:** `lib/features/{feature_name}/` with screen +
  repository per feature.
- **Supabase client is a global singleton:** accessed via `supabase` getter from
  `data/supabase_client.dart`. Do NOT create multiple client instances.
- **State management:** Riverpod. Auth state via `authStateProvider` stream.
  Services via `Provider`/`AsyncNotifierProvider`.
- **Routing:** GoRouter with auth-aware redirect. The `_AuthListenable` class
  bridges Supabase auth state changes to GoRouter's `refreshListenable`.
- **Error handling in screens:** catch `AuthException` (from
  `package:supabase_flutter/supabase_flutter.dart`) for auth errors; generic
  `catch` for network issues. Show error as inline `Text`, never use `print`.
- **Env vars:** loaded once at startup via `AppConfig.load()` in `main.dart`.
  The `.env` file is gitignored.

### Current routes

| Path | Screen | Auth required |
|---|---|---|
| `/auth` | `AuthScreen` | No (redirects away if signed in) — Sign In / Sign Up tabs, email+password, "Continue with Google" |
| `/profile` | `ProfileScreen` | Yes (redirects to /auth if not signed in) |

### Major decisions

For significant architectural choices, see [`docs/DECISIONS.md`](docs/DECISIONS.md)
(ADR-style log). Currently captured: auth model (ADR-001), Passkey SDK on web
(ADR-002), hosted Supabase for dev (ADR-003). When you make a non-trivial
choice, add an entry.

### Payment seam

`PaymentService` is the abstract interface. `MockPaymentService` is the default
implementation (auto-succeeds, writes a `paid` row). To swap to a real provider,
implement `PaymentService` and change `paymentServiceProvider` in
`lib/services/payment_service.dart` — nowhere else.

### Known gotchas (bugs hit during Phase 0 build — avoid these)

1. **`dotenv.maybeGet`** takes no type parameter. Use `dotenv.maybeGet('KEY')`,
   NOT `dotenv.maybeGet<String>('KEY')`.
2. **`supabase_flutter` deprecated `anonKey`**. Use `publishableKey` in
   `Supabase.initialize()`. The actual key value is the same anon/public key.
3. **`AuthException`** is transitively exported by `supabase_flutter` → `supabase`
   → `gotrue`, but you must import `package:supabase_flutter/supabase_flutter.dart`
   in the file that catches it (it's not in scope from transitive imports alone).
4. **`const` constructor on `AppConfig`** won't work because `String` fields
   from runtime `dotenv` aren't compile-time constants. Remove `const`.
5. **Passkeys Web SDK required on web** for `supabase_flutter` >= 2.5. Add
   `<script src="https://github.com/corbado/flutter-passkeys/releases/download/2.4.0/bundle.js"></script>`
   in `<head>` of `web/index.html` BEFORE the `flutter_bootstrap.js` tag.
   Without it, `Supabase.initialize()` throws "Passkeys Web SDK not loaded"
   and the app shows a blank page.
6. **`config.toml` key renames in newer CLI versions.** The v2.107.0 CLI
   renamed `refresh_token_rotation_enabled` → `enable_refresh_token_rotation`.
   If you see `failed to parse config, 'auth' has invalid keys: <key>`, check
   the CLI release for the current schema and rename accordingly.
7. **`.env` is bundled at build time on Flutter web.** Changing `.env` while
   `flutter run` is already active does NOT take effect on hot reload (`r`).
   You need a full restart (`R`) or stop + rebuild. Same for `web/index.html`
   changes — no hot reload, requires full restart.
8. **`.env` is NOT in Flutter's default `.gitignore`.** Add `.env` to
   `app/.gitignore` before the first `git init` — secrets will otherwise be
   committed on day one. (`.env.example` should stay tracked as the template.)

---

## 7. Migration Management

The **Supabase CLI** is the sole migration tool. No Drizzle, no custom runners.

| Command | What it does |
|---|---|
| `supabase db reset` | Drops + recreates local Postgres, applies all `migrations/*.sql`
  in alphabetical order, runs `seed.sql`. |
| `supabase db push` | Calculates diff between local migration files and linked
  remote project, applies new ones. |
| `supabase start` | Starts local Docker stack (Postgres, Auth, Realtime, Storage,
  Studio, Inbucket). |
| `supabase status` | Shows local service URLs + keys. |
| `supabase link --project-ref <ref>` | Links to a hosted Supabase project. |
| `supabase migration new <name>` | Creates a new timestamped migration file. |

Migration files are plain `.sql` in `supabase/migrations/`, numbered
alphabetically. The CLI tracks applied migrations in an internal
`schema_migrations` table.

**Business logic lives in RPC functions** (plpgsql) called from thin Edge
Functions, NOT in client Dart code. Edge Functions are ~10-line wrappers:
parse input → call one RPC with service-role key → return JSON.

---

## 8. What's Built (Phase 0 — auth rewrite still pending)

- [x] Supabase schema (12 tables) + RLS + extensions
- [x] Dev seed data (1 court, 6 users, 2 slots)
- [x] Flutter app: auth (email+OTP — current; rewrite to email+password + Google OAuth is the next task, see §9 and ADR-001), profile (CRUD + RLS probe), theme, router
- [x] `PaymentService` interface + `MockPaymentService`
- [x] `flutter analyze` clean, `flutter test` passing (3/3)

---

## 9. What's Next (Phase 1 — Owner + Court Setup)

Per `PLAN.md` §9. The next phase adds:

- **Owner onboarding:** create court, set entry fee + number of courts
- **Owner dashboard:** today's revenue, players today, active queue (empty states)
- **Staff management:** owner adds staff by username/email, grants `can_accept_payment`
- **Admin view:** list all courts, subscription status
- **RPC stub:** add `0003_matchmaking_rpc.sql` with a function that returns void (not yet created — current migrations stop at `0002b`)
- **Auth model finalized:** email+password + Google OAuth for sign-in. Email+OTP retained for password reset only. Apple OAuth deferred until an Apple Developer account ($99/yr) is obtained. New migration `0004_oauth_metadata.sql` updates `handle_new_user()` to populate `display_name` / `avatar_url` from OAuth profile data when available.
- **Router expansion:** add `/owner/*`, `/staff/*`, `/admin/*` routes with role-based guards

Read `PLAN.md` sections 4, 8, and 9 for the full Phase 1 spec before starting.

---

## 10. Open Decisions (from PLAN.md §10)

These are deferred choices that don't block Phase 1 but will matter later:

1. **Match entry model** — per-match pay (MVP default) vs. day-pass/session
2. **Score entry** — player enters + opponent confirms (MVP default) vs. staff enters
3. **Partner invite** — share-link/QR (MVP default) vs. friend-list
4. **Court slots** — free-form "next available" (MVP default) vs. fixed time windows
5. **Payment region/provider** — drives the real `PaymentService` impl (most important
   for Phase 3)
6. **Auth model** — Email+password + Google OAuth for sign-in. OTP retained for
   password reset only. Apple OAuth deferred until Apple Developer account is
   obtained. **See [ADR-001](docs/DECISIONS.md#adr-001-auth-model).** The
   `auth_repository.dart` / `auth_screen.dart` rewrite is a Phase 0 extension
   before Phase 1 starts.

---

## 11. Non-Goals (deferred — do not implement without user approval)

Tournaments, leagues, ladders. Future time-slot scheduling. Social feed,
following, DMs. Real payment provider wiring. Owner bank payouts.
Glicko-2 / uncertainty-based matchmaking. Friends list / social graph.

---

## 12. Risks to Watch

- **Matchmaking under load:** greedy + MMR band is simple; may feel slow or unfair
  with few players. Tunable constants in the sweep function.
- **Cold-start:** a court with <4 active players can't form matches. Mitigate with
  live queue depth visibility.
- **Offline payment abuse:** staff marking cash payments is trust-based. Audit log
  via `collected_by_member_id`.
- **Realtime fan-out:** broadcasting every queue change to every player at a court
  could get noisy. Filter channels by court.
- **Seed `_seed_user` writes to `auth.users`:** uses hardcoded `instance_id`. Works
  on fresh local reset but may break across Supabase version upgrades.

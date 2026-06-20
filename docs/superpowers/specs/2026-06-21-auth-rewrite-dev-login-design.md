# Auth Rewrite + Dev Login — Design

**Date:** 2026-06-21
**Status:** Approved (pending spec review)
**Related:** [ADR-001 Auth Model](../../DECISIONS.md#adr-001-auth-model), [ADR-003 Hosted Supabase for Dev](../../DECISIONS.md#adr-003-hosted-supabase-for-dev), [AGENTS.md §8/§9](../../../AGENTS.md)

---

## 1. Goal

Two coupled deliverables:

1. **Auth rewrite** — replace email+OTP as the primary sign-in with **email+password**
   plus **"Continue with Google"** (web), per ADR-001. OTP is retained only as the
   password-reset mechanism.
2. **Dev login** — a debug-only, one-tap way to sign in as any of five seeded
   identities (2 players, 1 owner, 1 staff, 1 admin) so feature work in later
   phases isn't gated on real auth.

The dev login is the immediate unblocker for building "main functionality"
(Phase 1+); the full auth rewrite lands alongside it.

## 2. Non-goals (deferred)

- Native (iOS/Android) Google sign-in — web-only for now.
- Apple OAuth — deferred until an Apple Developer account exists.
- Password-strength rules / email verification gating (dev keeps confirmation off).
- Role-based routing (`/owner/*`, `/staff/*`, `/admin/*`) — that's Phase 1.

---

## 3. Database & seed layer

### 3.1 `0004_oauth_metadata.sql` (new migration)

`create or replace` the `handle_new_user()` trigger function so that on a new
`auth.users` insert it populates `profiles.display_name` and `profiles.avatar_url`
from `raw_user_meta_data` when present:

- `display_name` ← `full_name` → `name` → email prefix (current fallback).
- `avatar_url` ← `avatar_url` → `picture` → null.

This makes Google sign-in auto-fill the profile. Behavior is unchanged for
email+password signups (they have no OAuth metadata, so the email-prefix
fallback still applies).

### 3.2 `0005_dev_seed_auth.sql` (new migration)

`create or replace` the `_seed_user()` helper so seeded users receive a **real
bcrypt password** instead of the current empty string:

- Ensure `pgcrypto` is available (`create extension if not exists pgcrypto`).
- Set `encrypted_password = crypt('<DEV_PASSWORD>', gen_salt('bf'))`.
- `<DEV_PASSWORD>` is a fixed dev-only constant (e.g. `dinkdev123`), defined once
  in this migration and mirrored by the Flutter constant in §6.
- Everything else about `_seed_user` is unchanged (`email_confirmed_at = now()`,
  identities row, profile upsert, `is_admin` param).

This is what lets the dev-login button call `signInWithPassword` against the
seeded accounts.

### 3.3 `seed.sql` (updated)

- Add a sixth seeded user: `admin@dinksync.dev`, uuid
  `99999999-9999-9999-9999-999999999999`, `is_platform_admin = true`, mmr 1000.
- Existing users (owner, staff, p1–p4) keep their UUIDs and roles. p3/p4 remain
  seeded (matchmaking needs four players) but are not surfaced as dev-login
  buttons.

### 3.4 Applying the seed to the hosted dev DB

Per ADR-003 the dev environment is a **hosted** Supabase project, and
`supabase db push` does **not** run `seed.sql` (only local `supabase db reset`
does). To get the password-bearing seed users into hosted dev:

1. `supabase db push` — applies migrations `0004` and `0005`.
2. Apply the seed manually, either:
   - paste `supabase/seed.sql` into the dashboard SQL editor, or
   - `psql "<dev db connection string>" -f supabase/seed.sql`.

`seed.sql` is idempotent (fixed UUIDs + `on conflict`), so re-applying is safe.
This step will be documented in AGENTS.md §2.

> **Production note:** seed data (including the dev password) must never be
> applied to a production project. It only reaches a DB when `seed.sql` is run
> explicitly, so the production migration chain stays clean.

---

## 4. Auth repository (`app/lib/features/auth/auth_repository.dart`)

Rewrite to expose:

| Method | Supabase call | Purpose |
|---|---|---|
| `signInWithPassword(email, password)` | `signInWithPassword` | Primary sign-in; also used by dev login |
| `signUpWithPassword(email, password)` | `signUp` | New account |
| `signInWithGoogle()` | `signInWithOAuth(OAuthProvider.google)` | Web redirect OAuth |
| `sendPasswordResetOtp(email)` | `resetPasswordForEmail` | Step 1 of reset — emails a recovery code |
| `verifyPasswordResetOtp(email, token)` | `verifyOTP(type: recovery)` | Step 2 — creates a recovery session |
| `updatePassword(newPassword)` | `updateUser(UserAttributes(password:))` | Step 3 — sets the new password |
| `signOut()` | `signOut` | Unchanged |
| `currentUser` / `currentEmail` | getters | Unchanged |

The old `sendOtp`/`verifyOtp` are removed as a sign-in path; their behavior now
lives in the reset methods above.

---

## 5. Auth screen (`app/lib/features/auth/auth_screen.dart`)

Rewrite the UI:

- **Sign In / Sign Up tabs** (e.g. `TabBar` or a segmented toggle).
- Email + password fields (password obscured, show/hide toggle).
- Primary button: "Sign in" / "Create account" per tab.
- **"Continue with Google"** button (calls `signInWithGoogle`).
- **"Forgot password?"** link → an in-app reset flow:
  1. enter email → send code,
  2. enter 6-digit code,
  3. set new password → on success, signed in / returned to sign-in.
- Error handling matches the current screen: catch `AuthException` → inline
  `Text`; generic `catch` → friendly connection message. No `print`.

The reset flow can be a nested step within `AuthScreen` (state machine like the
current `_codeSent` flag) rather than a separate route, to avoid router changes.

## 6. Dev login (debug-only)

- New file `app/lib/features/auth/dev_accounts.dart`:
  - `const kDevPassword = 'dinkdev123';` (must match §3.2).
  - A `const` list of `(label, email)` entries:
    `Player 1 → p1@dinksync.dev`, `Player 2 → p2@dinksync.dev`,
    `Owner → owner@dinksync.dev`, `Staff → staff@dinksync.dev`,
    `Admin → admin@dinksync.dev`.
- In `auth_screen.dart`, below the normal login, render a panel wrapped in
  `if (kDebugMode) { ... }` so it is **tree-shaken out of release builds** (the
  password constant included). The panel is a `Wrap`/`Row` of five buttons; each
  calls `signInWithPassword(entry.email, kDevPassword)`. A small "DEV ONLY"
  label clarifies intent.

## 7. Router & config

- **No structural router change.** The existing auth-aware redirect
  (signed-out → `/auth`, signed-in → `/profile`) still applies. Role-based
  routes are Phase 1.
- **`web/index.html`** — verify the existing passkeys `bundle.js` script is the
  only requirement; Google web OAuth uses Supabase's redirect flow and needs no
  extra script. Provider client ID/secret are configured in the Supabase
  dashboard (Auth → Providers → Google), not in the app.
- **`.env.example`** — unchanged (`SUPABASE_URL` + `SUPABASE_ANON_KEY` only).

## 8. Testing

- Existing smoke tests (theme builds, `AppConfigError`) must keep passing.
- Add a widget test asserting the dev-login panel renders in debug (it will,
  since tests run in debug) — e.g. the five role buttons are present.
- `flutter analyze` clean.
- Manual verification: each dev-login button signs in and lands on `/profile`;
  Google button initiates the redirect; the reset flow completes end to end
  against the hosted dev project.

## 9. Documentation updates

- **AGENTS.md** — update §2 (add the "apply seed to hosted dev" step), and
  refresh §8/§9 once auth is no longer "email+OTP" (mark the rewrite done).
- **README.md:16** already claims password+Google auth; it becomes accurate once
  this ships (no change needed, or note it was aspirational).
- **DECISIONS.md** — ADR-001 already covers the auth model; add a short note or
  ADR for the dev-login mechanism (seeded bcrypt password, `kDebugMode` gate) if
  warranted.

## 10. Risks / notes

- **Shared dev password in the seed + app.** Acceptable because seeded accounts
  only exist in dev DBs and the app-side constant is compiled out of release.
  The risk is someone running `seed.sql` against production — mitigated by it
  never auto-running on `db push`.
- **`web/index.html` / `.env` changes need a full restart**, not hot reload
  (existing gotcha #7).
- **Google OAuth dashboard setup** (~30 min, per ADR-001) is a prerequisite for
  testing the Google button but does not block the password + dev-login work.

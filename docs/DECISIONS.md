# DECISIONS.md — Architecture Decision Records (ADR)

> A running log of significant technical decisions made during dinkSync's
> development. Each entry captures the context, decision, and consequences.

---

## ADR-001: Auth Model
**Date:** 2026-06-21
**Status:** Accepted

### Context
Phase 0 used email+OTP exclusively for sign-in. For the MVP, we need a faster,
more familiar auth flow. OTP has friction (email round-trip) and requires
Inbucket for local dev password reset testing.

### Decision
**Use email+password + Google OAuth for signing in.**
- Email+OTP is dropped as a primary sign-in method but remains the underlying
  mechanism for Supabase's password reset flow.
- Apple OAuth is deferred until an Apple Developer account ($99/yr) is obtained.
- Email confirmation is disabled for dev convenience; to be re-enabled before
  production.
- New migration `0004_oauth_metadata.sql` updates the `handle_new_user()`
  trigger to prefer OAuth `full_name` / `avatar_url` from `raw_user_meta_data`
  when available, falling back to the current email-prefix behavior.

### Consequences
- **Positive:** Faster sign-in. OAuth profile data (name, avatar) populates
  the `profiles` table automatically. Familiar UX — everyone knows email+password
  and "Continue with Google."
- **Negative:** Requires Google Cloud Console OAuth setup (~30 min). Password
  reset UI is now needed (forgot-password flow). Apple OAuth remains unshipped
  until the Apple Developer account is set up.
- **Web:** Passkey Web SDK (`bundle.js` from corbado/flutter-passkeys) must
  be loaded in `web/index.html` for `supabase_flutter >= 2.5` on web.

---

## ADR-002: Passkey SDK on Web
**Date:** 2026-06-21
**Status:** Accepted

### Context
`supabase_flutter ^2.8.0` auto-initializes passkey support on web platforms.
The initialization requires a `bundle.js` from corbado's `flutter_passkeys`
package to be loaded in the HTML page. Without it, `Supabase.initialize()`
throws "Passkeys Web SDK not loaded", preventing the app from rendering.

### Decision
**Load the passkey SDK from the corbado GitHub release URL in the `<head>` of
`web/index.html`, before the `flutter_bootstrap.js` tag:**
```html
<script src="https://github.com/corbado/flutter-passkeys/releases/download/2.4.0/bundle.js"></script>
```
For MVP/dev, this is acceptable. For production, we will self-host the bundle
and add a Subresource Integrity (SRI) hash.

### Consequences
- **Positive:** App runs on web without error. SDK is loaded and ready for
  future passkey features (MFA, passwordless login).
- **Negative:** External runtime dependency on a GitHub release URL. No SRI
  hash for now (tamper risk is low for dev/MVP). Must be pinned or self-hosted
  before production.
- **Note:** `web/index.html` changes require a full Flutter restart (not hot
  reload) to take effect.

---

## ADR-003: Hosted Supabase for Dev
**Date:** 2026-06-21
**Status:** Accepted

### Context
Docker Desktop was not installed on the development machine. The local
Supabase stack (`supabase start`) requires Docker. The project needs a database
and auth backend to function during Phase 0 development.

### Decision
**Use a hosted Supabase project (`dinksync-dev`) for development** instead of
a local Docker stack. Migrations are applied via the Supabase CLI
(`supabase db push`).

### Consequences
- **Positive:** No Docker required. Works from any machine with just the
  Supabase CLI. Migrations apply directly to the hosted DB.
- **Negative:** Requires an active internet connection. Cannot run fully
  offline.
- **Secrets hygiene:** The `anon key` and `Project URL` are placed in `.env`
  (gitignored — reminder: Flutter's default `.gitignore` does NOT exclude
  `.env`; we added it manually in `app/.gitignore`). The `.env.example` is a
  clean placeholder template kept in version control.
- **CLI config:** The `config.toml` had a deprecated key
  (`refresh_token_rotation_enabled`) renamed in CLI v2.107.0 to
  `enable_refresh_token_rotation`. Fixed with a one-line rename.

---

## ADR-004: Debug-Only Dev Login
**Date:** 2026-06-21
**Status:** Accepted

### Context
Iterating on role-specific features (player, owner, staff, admin) requires
repeatedly signing in as each role. Real auth (email+password / Google) adds
friction to that loop.

### Decision
**Add a one-tap dev login, gated behind `kDebugMode`.** Seeded users
(`*@dinksync.dev`) are given a shared bcrypt password (`dinkdev123`) in
`0005_dev_seed_auth.sql`; a debug-only panel calls `signInWithPassword` with
that password. The panel and the password constant are tree-shaken out of
release builds by the `if (kDebugMode)` guard.

### Consequences
- **Positive:** Instant role switching in dev. Uses the real password auth path.
- **Negative:** A shared dev password lives in the seed + a Dart constant.
  Acceptable: seeded accounts only exist in dev DBs (`seed.sql` never auto-runs
  on `db push`), and the constant is compiled out of release builds.
- **Guardrail:** never run `seed.sql` against a production project.

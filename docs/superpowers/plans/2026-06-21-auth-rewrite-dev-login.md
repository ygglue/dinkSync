# Auth Rewrite + Dev Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace email+OTP sign-in with email+password + Google (web) OAuth, and add a debug-only one-tap dev login for five seeded identities (2 players, owner, staff, admin).

**Architecture:** Supabase Auth via `supabase_flutter`. Seeded dev users get a real bcrypt password so a `signInWithPassword` button can log in as them. The dev-login panel is gated behind `kDebugMode` so it (and the dev password constant) is tree-shaken out of release builds. Password reset is an in-app 3-step OTP-recovery flow. No router changes.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12.2, `flutter_riverpod ^2.6.1`, `go_router ^14.6.0`, `supabase_flutter ^2.8.0`, Supabase CLI 2.107.0, Postgres 17 (`pgcrypto`).

## Global Constraints

- Flutter binary is NOT on PATH: use `/c/Users/Eli/flutter/bin/flutter` (or `C:\Users\Eli\flutter\bin\flutter`).
- Dev backend is a **hosted** Supabase project (ADR-003). `supabase db push` applies migrations; it does **NOT** run `seed.sql` — the seed is applied manually.
- Dev password constant must match in two places: SQL migration `0005` and Dart `dev_accounts.dart`. Value: `dinkdev123`.
- Money is integer cents; UUIDs fixed for seed idempotency; timestamps `timestamptz`. (Unchanged here.)
- Error handling in screens: catch `AuthException` from `package:supabase_flutter/supabase_flutter.dart` → inline `Text`; generic `catch` → friendly message. Never use `print`.
- `web/index.html` and `.env` changes require a full Flutter restart (`R` / rebuild), not hot reload.
- `flutter analyze` must stay clean; existing tests must keep passing.
- Supabase singleton accessed via the `supabase` getter from `data/supabase_client.dart` — never construct a second client.

---

### Task 1: Initialize git repository

The project is not yet a git repo, but every task below ends in a commit. This task establishes version control. `.gitignore` already exists and correctly excludes `.env`, build artifacts, `nul`, and `flutter_*.log`.

**Files:**
- Modify: none (repo metadata only)

- [ ] **Step 1: Confirm not already a repo**

Run: `git -C /c/Users/Eli/Documents/coding_projects/dinkSync rev-parse --is-inside-work-tree 2>&1 || echo "not a repo"`
Expected: prints `not a repo` (or `false`).

- [ ] **Step 2: Verify `.env` is ignored before first commit**

Read `.gitignore` and confirm it contains `app/.env` (it does, line 3). This is critical — secrets must not enter history.

- [ ] **Step 3: Initialize and make the initial commit**

```bash
cd /c/Users/Eli/Documents/coding_projects/dinkSync
git init
git add -A
git status --short | grep -i '\.env$' && echo "STOP: .env is staged" || echo "ok: .env not staged"
```
Expected: the last line prints `ok: .env not staged`. If it prints `STOP`, do not commit — fix `.gitignore` first.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: initialize git repository"
```
Expected: a commit is created; `git log --oneline` shows one entry.

---

### Task 2: Migration `0004_oauth_metadata.sql` — OAuth-aware profile creation

**Files:**
- Create: `supabase/migrations/0004_oauth_metadata.sql`

**Interfaces:**
- Produces: an updated `public.handle_new_user()` trigger function that fills
  `display_name` and `avatar_url` from `raw_user_meta_data` (Google fields)
  with the existing email-prefix fallback for `display_name`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0004_oauth_metadata.sql`:

```sql
-- 0004_oauth_metadata.sql
-- Make profile auto-creation OAuth-aware (ADR-001). On a new auth.users insert,
-- prefer OAuth-provided name/avatar from raw_user_meta_data; fall back to the
-- email prefix for display_name (unchanged behavior for email+password signups).

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      new.raw_user_meta_data->>'display_name',
      split_part(new.email, '@', 1)
    ),
    coalesce(
      new.raw_user_meta_data->>'avatar_url',
      new.raw_user_meta_data->>'picture'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
```

- [ ] **Step 2: Apply to the hosted dev DB**

Run:
```bash
cd /c/Users/Eli/Documents/coding_projects/dinkSync/supabase
supabase db push
```
Expected: CLI reports `0004_oauth_metadata.sql` applied (or "Applying migration 0004..."). If nothing new applies, confirm the file is named with the `0004_` prefix.

- [ ] **Step 3: Verify the function updated**

In the Supabase dashboard SQL editor (or `psql`), run:
```sql
select pg_get_functiondef('public.handle_new_user()'::regprocedure) ilike '%avatar_url%' as has_avatar;
```
Expected: `has_avatar = true`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0004_oauth_metadata.sql
git commit -m "feat(db): OAuth-aware handle_new_user trigger"
```

---

### Task 3: Migration `0005_dev_seed_auth.sql` — passwords for seeded users

**Files:**
- Create: `supabase/migrations/0005_dev_seed_auth.sql`

**Interfaces:**
- Produces: an updated `public._seed_user(uid, email_addr, name, mmr, is_admin)`
  helper (same signature) that now sets a bcrypt `encrypted_password` from the
  fixed dev password `dinkdev123`, enabling `signInWithPassword`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0005_dev_seed_auth.sql`. The signature is unchanged so `seed.sql`'s existing calls keep working; only the body changes to set a password. The dev password `dinkdev123` is hardcoded here (dev-only).

```sql
-- 0005_dev_seed_auth.sql
-- Give seeded dev users a real bcrypt password so the debug-only "dev login"
-- can sign in via signInWithPassword. Dev-only: seed.sql is never auto-applied
-- to production (db push does not run it). Password: 'dinkdev123'.

create extension if not exists pgcrypto;

create or replace function public._seed_user(
  uid        uuid,
  email_addr text,
  name       text,
  mmr        int,
  is_admin   boolean
) returns void
language plpgsql
security definer set search_path = auth, public
as $$
begin
  -- auth.users (now with a bcrypt password instead of an empty string)
  insert into auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  values (
    uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    email_addr,
    crypt('dinkdev123', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', name)
  )
  on conflict (id) do update
    set encrypted_password = excluded.encrypted_password,
        email_confirmed_at = excluded.email_confirmed_at;

  -- identities (required for the auth flow to consider the user valid)
  insert into auth.identities (id, user_id, provider, identity_data, created_at, updated_at)
  values (
    gen_random_uuid(),
    uid,
    'email',
    jsonb_build_object('sub', uid::text, 'email', email_addr),
    now(),
    now()
  )
  on conflict do nothing;

  -- profile
  insert into public.profiles (id, display_name, mmr, is_platform_admin)
  values (uid, name, mmr, is_admin)
  on conflict (id) do update
    set display_name = excluded.display_name,
        mmr = excluded.mmr,
        is_platform_admin = excluded.is_platform_admin;
end;
$$;
```

> Note: the `on conflict (id) do update` on `auth.users` lets re-running the seed
> repair passwords for users created before this migration.

- [ ] **Step 2: Apply to the hosted dev DB**

Run:
```bash
cd /c/Users/Eli/Documents/coding_projects/dinkSync/supabase
supabase db push
```
Expected: `0005_dev_seed_auth.sql` applied.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0005_dev_seed_auth.sql
git commit -m "feat(db): seeded dev users get a bcrypt password"
```

---

### Task 4: Add admin seed user + re-apply seed to hosted dev

**Files:**
- Modify: `supabase/seed.sql`

**Interfaces:**
- Consumes: `public._seed_user(...)` from Task 3.
- Produces: a seeded `admin@dinksync.dev` user (uuid `9999…`, `is_platform_admin = true`)
  plus the existing owner/staff/p1–p4, all now password-enabled.

- [ ] **Step 1: Add the admin declaration and seed call**

In `supabase/seed.sql`, add the admin id to the `declare` block (after `p4_id`, before `court_id`):

```sql
  admin_id   uuid := '99999999-9999-9999-9999-999999999999';
```

Then add this `_seed_user` call immediately after the `p4_id` call (line 32 area):

```sql
  perform public._seed_user(admin_id, 'admin@dinksync.dev', 'Platform Admin', 1000, true);
```

- [ ] **Step 2: Apply the seed to the hosted dev DB**

`db push` does NOT run `seed.sql`. Apply it manually — paste the contents of
`supabase/seed.sql` into the Supabase dashboard SQL editor and run, **or**:
```bash
psql "<dev db connection string from dashboard > Settings > Database>" -f /c/Users/Eli/Documents/coding_projects/dinkSync/supabase/seed.sql
```
Expected: runs without error (idempotent; safe to re-run).

- [ ] **Step 3: Verify all seven dev users exist with passwords and correct roles**

In the SQL editor run:
```sql
select u.email,
       (u.encrypted_password <> '') as has_pw,
       p.is_platform_admin
from auth.users u
join public.profiles p on p.id = u.id
where u.email like '%@dinksync.dev'
order by u.email;
```
Expected: 7 rows (owner, staff, admin, p1–p4), every `has_pw = true`, and
`admin@dinksync.dev` is the only row with `is_platform_admin = true`.

- [ ] **Step 4: Verify the dev password actually authenticates**

In the SQL editor:
```sql
select email
from auth.users
where email = 'owner@dinksync.dev'
  and encrypted_password = crypt('dinkdev123', encrypted_password);
```
Expected: one row returned (confirms `dinkdev123` matches the stored hash).

- [ ] **Step 5: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat(db): seed platform admin user"
```

---

### Task 5: Dev account registry (`dev_accounts.dart`)

**Files:**
- Create: `app/lib/features/auth/dev_accounts.dart`
- Test: `app/test/dev_accounts_test.dart`

**Interfaces:**
- Produces:
  - `const String kDevPassword` = `'dinkdev123'`.
  - `class DevAccount { final String label; final String email; const DevAccount(...); }`
  - `const List<DevAccount> kDevAccounts` with 5 entries (Player 1/2, Owner, Staff, Admin).

- [ ] **Step 1: Write the failing test**

Create `app/test/dev_accounts_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/auth/dev_accounts.dart';

void main() {
  group('dev_accounts', () {
    test('exposes exactly the five expected dev identities', () {
      final emails = kDevAccounts.map((a) => a.email).toList();
      expect(emails, [
        'p1@dinksync.dev',
        'p2@dinksync.dev',
        'owner@dinksync.dev',
        'staff@dinksync.dev',
        'admin@dinksync.dev',
      ]);
    });

    test('every account has a non-empty label', () {
      expect(kDevAccounts.every((a) => a.label.isNotEmpty), isTrue);
    });

    test('dev password matches the seed migration constant', () {
      expect(kDevPassword, 'dinkdev123');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/dev_accounts_test.dart` (from `app/`)
Expected: FAIL — `dev_accounts.dart` does not exist / `kDevAccounts` undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/features/auth/dev_accounts.dart`:

```dart
/// DEV ONLY. These identities exist solely in dev/seeded databases and are used
/// by the debug-only dev-login panel. This file is referenced only from code
/// wrapped in `if (kDebugMode)`, so it is tree-shaken out of release builds.
///
/// [kDevPassword] MUST match the password set in
/// `supabase/migrations/0005_dev_seed_auth.sql`.
library;

const String kDevPassword = 'dinkdev123';

class DevAccount {
  const DevAccount(this.label, this.email);
  final String label;
  final String email;
}

const List<DevAccount> kDevAccounts = [
  DevAccount('Player 1', 'p1@dinksync.dev'),
  DevAccount('Player 2', 'p2@dinksync.dev'),
  DevAccount('Owner', 'owner@dinksync.dev'),
  DevAccount('Staff', 'staff@dinksync.dev'),
  DevAccount('Admin', 'admin@dinksync.dev'),
];
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/dev_accounts_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/auth/dev_accounts.dart app/test/dev_accounts_test.dart
git commit -m "feat(auth): dev account registry"
```

---

### Task 6: Auth repository rewrite (`auth_repository.dart`)

**Files:**
- Modify: `app/lib/features/auth/auth_repository.dart` (full rewrite)

**Interfaces:**
- Consumes: `supabase` getter from `data/supabase_client.dart`.
- Produces (on `AuthRepository`):
  - `Future<void> signInWithPassword({required String email, required String password})`
  - `Future<void> signUpWithPassword({required String email, required String password})`
  - `Future<bool> signInWithGoogle()` (returns the `signInWithOAuth` bool result)
  - `Future<void> sendPasswordResetOtp(String email)`
  - `Future<void> verifyPasswordResetOtp({required String email, required String token})`
  - `Future<void> updatePassword(String newPassword)`
  - `Future<void> signOut()`
  - `User? get currentUser` / `String? get currentEmail`
  - `final authRepositoryProvider` (unchanged provider).

This task has no standalone unit test — every method is a thin pass-through to
the Supabase client, which requires a live backend (covered by manual
verification in Task 10 and the dev-login path in Task 7/8). Correctness gate
here is `flutter analyze`.

- [ ] **Step 1: Rewrite the repository**

Replace the entire contents of `app/lib/features/auth/auth_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

/// Thin wrapper around Supabase Auth. Centralizes auth calls so widgets stay
/// free of supabase-specific code.
///
/// Primary sign-in is email+password and Google OAuth (web). Email OTP is
/// retained only as the password-reset mechanism (recovery type).
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  /// Sign in an existing user. Throws [AuthException] on bad credentials.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Create a new account. Throws [AuthException] if the email is taken.
  Future<void> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
    );
  }

  /// Start the Google OAuth redirect flow (web). Returns the launch result.
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(OAuthProvider.google);
  }

  /// Step 1 of password reset: email the user a recovery code.
  Future<void> sendPasswordResetOtp(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  /// Step 2 of password reset: exchange the recovery code for a session.
  /// Throws [AuthException] on a wrong/expired code.
  Future<void> verifyPasswordResetOtp({
    required String email,
    required String token,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.recovery,
    );
  }

  /// Step 3 of password reset: set the new password on the recovered session.
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;
  String? get currentEmail => _client.auth.currentUser?.email;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(supabase);
});
```

- [ ] **Step 2: Verify it analyzes cleanly**

Run: `/c/Users/Eli/flutter/bin/flutter analyze lib/features/auth/auth_repository.dart` (from `app/`)
Expected: `No issues found!`

- [ ] **Step 3: Confirm no remaining references to removed methods**

Run: `grep -rn "sendOtp\|verifyOtp\b" /c/Users/Eli/Documents/coding_projects/dinkSync/app/lib`
Expected: no matches (the only caller, `auth_screen.dart`, is rewritten in Task 7). If matches appear outside `auth_screen.dart`, update them.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/auth/auth_repository.dart
git commit -m "feat(auth): email+password, Google, and reset in AuthRepository"
```

---

### Task 7: Auth screen rewrite — tabs, password, Google, reset, dev login

**Files:**
- Modify: `app/lib/features/auth/auth_screen.dart` (full rewrite)

**Interfaces:**
- Consumes: `authRepositoryProvider` (Task 6), `kDevAccounts` / `kDevPassword` (Task 5).
- Produces: a `ConsumerStatefulWidget` `AuthScreen` with a sign-in/sign-up form,
  a Google button, a forgot-password sub-flow, and a `kDebugMode`-gated dev panel.

The screen is one cohesive file, rewritten as a single deliverable so there are
no broken intermediate compile states. After this task the dev login works end
to end (it depends only on Task 4's seed + Task 6's `signInWithPassword`).

- [ ] **Step 1: Rewrite the screen**

Replace the entire contents of `app/lib/features/auth/auth_screen.dart`:

```dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'auth_repository.dart';
import 'dev_accounts.dart';

/// Auth entry point. Email+password (Sign In / Sign Up tabs) plus
/// "Continue with Google" and a forgot-password flow. In debug builds a
/// dev-login panel offers one-tap sign-in as seeded identities.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

enum _Mode { signIn, signUp }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      // On success the auth-state listener redirects to /profile.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
        if (_mode == _Mode.signIn) {
          await _repo.signInWithPassword(
            email: _emailCtl.text,
            password: _passwordCtl.text,
          );
        } else {
          await _repo.signUpWithPassword(
            email: _emailCtl.text,
            password: _passwordCtl.text,
          );
        }
      });

  Future<void> _google() => _run(() => _repo.signInWithGoogle());

  Future<void> _devLogin(DevAccount account) =>
      _run(() => _repo.signInWithPassword(
            email: account.email,
            password: kDevPassword,
          ));

  Future<void> _openResetFlow() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PasswordResetSheet(repo: _repo),
    );
    if (mounted) {
      setState(() => _notice = 'If the email exists, a reset code was sent.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignIn = _mode == _Mode.signIn;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.sports_tennis,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'dinkSync',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.signIn, label: Text('Sign In')),
                    ButtonSegment(value: _Mode.signUp, label: Text('Sign Up')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                            _mode = s.first;
                            _error = null;
                            _notice = null;
                          }),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _emailCtl,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const ['email'],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _passwordCtl,
                  enabled: !_busy,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),

                if (isSignIn)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : _openResetFlow,
                      child: const Text('Forgot password?'),
                    ),
                  )
                else
                  const SizedBox(height: 12),

                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 4),
                  Text(_notice!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 12),

                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isSignIn ? 'Sign in' : 'Create account'),
                ),
                const SizedBox(height: 8),

                OutlinedButton.icon(
                  onPressed: _busy ? null : _google,
                  icon: const Icon(Icons.login),
                  label: const Text('Continue with Google'),
                ),

                if (kDebugMode) _DevLoginPanel(busy: _busy, onPick: _devLogin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// DEV ONLY. Compiled out of release builds via the `if (kDebugMode)` guard at
/// its single call site.
class _DevLoginPanel extends StatelessWidget {
  const _DevLoginPanel({required this.busy, required this.onPick});

  final bool busy;
  final Future<void> Function(DevAccount) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('DEV ONLY',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final account in kDevAccounts)
                OutlinedButton(
                  onPressed: busy ? null : () => onPick(account),
                  child: Text(account.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet password reset: send code -> enter code -> set new password.
class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({required this.repo});
  final AuthRepository repo;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

enum _ResetStep { enterEmail, enterCode }

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  final _emailCtl = TextEditingController();
  final _codeCtl = TextEditingController();
  final _newPwCtl = TextEditingController();

  _ResetStep _step = _ResetStep.enterEmail;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtl.dispose();
    _codeCtl.dispose();
    _newPwCtl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action,
      {VoidCallback? onSuccess}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && onSuccess != null) onSuccess();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendCode() => _run(
        () => widget.repo.sendPasswordResetOtp(_emailCtl.text),
        onSuccess: () => setState(() => _step = _ResetStep.enterCode),
      );

  void _finish() => _run(() async {
        await widget.repo.verifyPasswordResetOtp(
          email: _emailCtl.text,
          token: _codeCtl.text,
        );
        await widget.repo.updatePassword(_newPwCtl.text);
      }, onSuccess: () => Navigator.of(context).pop());

  @override
  Widget build(BuildContext context) {
    final onEmail = _step == _ResetStep.enterEmail;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset password',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (onEmail)
            TextField(
              controller: _emailCtl,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            )
          else ...[
            TextField(
              controller: _codeCtl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '6-digit code',
                prefixIcon: Icon(Icons.password),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPwCtl,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : (onEmail ? _sendCode : _finish),
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(onEmail ? 'Send code' : 'Set new password'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it analyzes cleanly**

Run: `/c/Users/Eli/flutter/bin/flutter analyze lib/features/auth/auth_screen.dart` (from `app/`)
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/auth/auth_screen.dart
git commit -m "feat(auth): password/Google auth screen with reset + dev login"
```

---

### Task 8: Widget test — auth screen renders form + dev panel

**Files:**
- Create: `app/test/auth_screen_test.dart`

Tests run in debug, so `kDebugMode` is true and the dev panel renders. The screen
reads `authRepositoryProvider` only on interaction (via `ref.read`), so building
it does not require a live Supabase client.

**Interfaces:**
- Consumes: `AuthScreen` (Task 7), `kDevAccounts` (Task 5).

- [ ] **Step 1: Write the failing test**

Create `app/test/auth_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/auth/auth_screen.dart';
import 'package:dinksync/features/auth/dev_accounts.dart';

Widget _host() => const ProviderScope(
      child: MaterialApp(home: AuthScreen()),
    );

void main() {
  group('AuthScreen', () {
    testWidgets('shows Sign In / Sign Up toggle and Google button',
        (tester) async {
      await tester.pumpWidget(_host());
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('renders a dev-login button for every dev account in debug',
        (tester) async {
      await tester.pumpWidget(_host());
      expect(find.text('DEV ONLY'), findsOneWidget);
      for (final account in kDevAccounts) {
        expect(find.widgetWithText(OutlinedButton, account.label),
            findsOneWidget);
      }
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails (then passes)**

Run: `/c/Users/Eli/flutter/bin/flutter test test/auth_screen_test.dart` (from `app/`)
Expected: PASS once Task 7 is in place. (If Task 7 were missing it would fail to compile.) If a button label collides (e.g. "Sign In" appears in both the segment and elsewhere), tighten the finder to `find.widgetWithText(ButtonSegment, ...)`.

- [ ] **Step 3: Run the full test suite**

Run: `/c/Users/Eli/flutter/bin/flutter test` (from `app/`)
Expected: all tests pass (existing theme/config smoke tests + `dev_accounts_test` + `auth_screen_test`).

- [ ] **Step 4: Commit**

```bash
git add app/test/auth_screen_test.dart
git commit -m "test(auth): auth screen form + dev login panel render"
```

---

### Task 9: Documentation updates

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/DECISIONS.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update AGENTS.md setup steps**

In `AGENTS.md` section 2, under the hosted-Supabase setup block (after `supabase db push`), add a step noting the seed must be applied manually for dev identities + dev login:

```markdown
#     Apply dev seed (db push does NOT run seed.sql):
#       paste supabase/seed.sql into the dashboard SQL editor, or
#       psql "<dev db connection string>" -f supabase/seed.sql
#     This creates 7 dev users (owner, staff, admin, p1-p4), all with the
#     dev password 'dinkdev123', enabling the debug-only dev-login buttons.
```

- [ ] **Step 2: Mark the auth rewrite done in AGENTS.md**

In `AGENTS.md` section 8, change the auth bullet from the email+OTP "rewrite pending" wording to reflect the shipped state:

```markdown
- [x] Flutter app: auth (email+password + Google OAuth web, OTP retained for
  password reset; debug-only dev login for 5 seeded roles), profile (CRUD + RLS
  probe), theme, router
```

Also remove the "auth rewrite still pending" note from the section 8 heading and the corresponding Phase-0-extension wording in section 9 (the rewrite is no longer "next").

- [ ] **Step 3: Add an ADR for the dev-login mechanism**

Append to `docs/DECISIONS.md`:

```markdown

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
```

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/DECISIONS.md
git commit -m "docs: dev-login + auth rewrite (AGENTS, ADR-004)"
```

---

### Task 10: Google OAuth config + manual end-to-end verification

**Files:** none (dashboard config + manual QA).

This task is the human-in-the-loop verification gate. The dev login and
email+password paths can be verified immediately; Google requires dashboard
setup first.

- [ ] **Step 1: Configure the Google provider (Supabase dashboard)**

In the Supabase dashboard for the dev project: Authentication → Providers →
Google → enable, and paste a Google Cloud OAuth **Web** client ID + secret
(create one at console.cloud.google.com if needed; authorized redirect URI is
the value shown in the Supabase Google provider panel, typically
`https://<project-ref>.supabase.co/auth/v1/callback`). Also confirm
Authentication → Providers → Email has "Confirm email" **disabled** for dev
(ADR-001).

- [ ] **Step 2: Run the app**

Run (from `app/`): `/c/Users/Eli/flutter/bin/flutter run -d chrome`
Expected: the auth screen loads (no blank page — confirms the passkeys script in
`web/index.html` is present).

- [ ] **Step 3: Verify dev login for all five roles**

Tap each dev button (Player 1, Player 2, Owner, Staff, Admin) in turn; after
each, confirm the app lands on `/profile` showing that identity, then sign out.
Expected: all five sign in successfully.

- [ ] **Step 4: Verify email+password**

Sign up a fresh email+password account, confirm it lands on `/profile`; sign
out; sign back in with the same credentials.
Expected: both succeed.

- [ ] **Step 5: Verify Google + password reset**

Tap "Continue with Google" → complete the redirect → lands on `/profile` with
Google name/avatar populated (confirms Task 2). Then use "Forgot password?" on a
password account: enter email → enter the emailed code → set a new password →
confirm sign-in with the new password.
Expected: both flows complete. Note: the OTP-recovery flow needs the Supabase
**Reset Password** email template (Authentication → Email Templates) to include
the code token `{{ .Token }}` — the default template only contains a magic link.
If the email has no 6-digit code, add `{{ .Token }}` to that template.

- [ ] **Step 6: Final analyze + test sweep**

Run (from `app/`): `/c/Users/Eli/flutter/bin/flutter analyze && /c/Users/Eli/flutter/bin/flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 7: Commit any doc tweaks from QA findings**

```bash
git add -A
git commit -m "chore: auth rewrite + dev login verified" || echo "nothing to commit"
```

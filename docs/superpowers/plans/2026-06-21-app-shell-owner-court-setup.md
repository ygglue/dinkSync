# App Shell + Owner Court Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a navigation shell with a persisted Play/Court-Management mode switch, and an owner flow to create a court, subscribe (mock payment), and view a management dashboard.

**Architecture:** `go_router` with a `StatefulShellRoute` Play shell (bottom nav) plus a Management screen; a persisted `appModeProvider` and a derived `capabilitiesProvider` decide the launch destination and the mode-dropdown visibility. Court creation and subscription go through two `security definer` RPCs (clients can't insert the owner membership row, slots, or subscriptions directly). A court is only publicly visible once subscribed (`status='active'`), enforced by a tightened `courts_select` RLS policy.

**Tech Stack:** Flutter (Dart 3.12), Riverpod, go_router, supabase_flutter, shared_preferences, google_fonts; Supabase Postgres (plpgsql RPCs + RLS).

**Spec:** [docs/superpowers/specs/2026-06-21-app-shell-owner-court-setup-design.md](../specs/2026-06-21-app-shell-owner-court-setup-design.md)

## Global Constraints

- Flutter binary is NOT on PATH. Use `/c/Users/Eli/flutter/bin/flutter` for all `flutter`/`dart` commands.
- All UI follows the `dinksync-ui` skill: import `kRadius` (24) and `kBrandGreen` from `app/lib/app/theme.dart`; drive colors from `Theme.of(context).colorScheme` (only `kBrandGreen` is a literal, for filled CTAs); use `withValues(alpha:)`, never `withOpacity`.
- Currency is `PHP`. Subscription prices live server-side: monthly = `99900`, yearly = `999000` centavos. Money is integer minor units.
- Tests must NOT require a live Supabase or network. Test pure logic + widgets with provider overrides; RPC round-trips are verified manually (repo convention).
- After every task: `/c/Users/Eli/flutter/bin/flutter analyze` is clean and `/c/Users/Eli/flutter/bin/flutter test` passes before committing.
- Migration `0003` stays reserved for matchmaking; this slice uses `0008`.
- Run all `flutter`/`git` commands from the `app/` directory unless a path says otherwise (migration files live under `supabase/`).

---

### Task 1: Migration 0008 — RPCs + court visibility policy

**Files:**
- Create: `supabase/migrations/0008_owner_court_setup.sql`

**Interfaces:**
- Produces (Postgres):
  - `create_court(p_name text, p_entry_fee_cents int, p_currency text, p_num_courts int, p_address text) returns uuid`
  - `subscribe_court(p_court_id uuid, p_plan text) returns void`
  - Replaced policy `courts_select` (active courts public; owner/staff/admin see own/all).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0008_owner_court_setup.sql`:

```sql
-- 0008_owner_court_setup.sql
-- Owner court setup: create_court + subscribe_court RPCs, and tighten court
-- visibility so only subscribed (active) courts are publicly discoverable.
-- Clients cannot insert the owner's own court_members row (is_court_owner
-- chicken-and-egg), court_slots (no insert policy), or subscriptions
-- (RPC-only) -- hence security definer functions. Dev/Phase-1 helper.

-- ---------------------------------------------------------------------------
-- create_court: venue (suspended) + owner membership + N slots, atomically.
-- ---------------------------------------------------------------------------
create or replace function public.create_court(
  p_name           text,
  p_entry_fee_cents int,
  p_currency       text,
  p_num_courts     int,
  p_address        text
) returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  uid          uuid := auth.uid();
  new_court_id uuid;
  i            int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'court name is required';
  end if;
  if p_num_courts is null or p_num_courts < 1 then
    raise exception 'num_courts must be >= 1';
  end if;

  insert into public.courts
    (owner_profile_id, name, entry_fee_cents, currency, num_courts, address, status)
  values
    (uid, btrim(p_name), greatest(coalesce(p_entry_fee_cents, 0), 0),
     coalesce(nullif(p_currency, ''), 'PHP'), p_num_courts,
     nullif(btrim(coalesce(p_address, '')), ''), 'suspended')
  returning id into new_court_id;

  insert into public.court_members (court_id, profile_id, role, can_accept_payment, added_by)
  values (new_court_id, uid, 'owner', true, uid);

  for i in 1..p_num_courts loop
    insert into public.court_slots (court_id, label, status)
    values (new_court_id, 'Court ' || i, 'open');
  end loop;

  return new_court_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- subscribe_court: record a (mock) payment + activate the subscription and
-- the court. Prices are authoritative here; the client only sends the plan.
-- ---------------------------------------------------------------------------
create or replace function public.subscribe_court(
  p_court_id uuid,
  p_plan     text
) returns void
language plpgsql
security definer set search_path = public
as $$
declare
  uid      uuid := auth.uid();
  v_amount int;
  v_end    timestamptz;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (
    select 1 from public.courts c
    where c.id = p_court_id and c.owner_profile_id = uid
  ) then
    raise exception 'not the court owner';
  end if;

  if p_plan = 'monthly' then
    v_amount := 99900;
    v_end    := now() + interval '1 month';
  elsif p_plan = 'yearly' then
    v_amount := 999000;
    v_end    := now() + interval '1 year';
  else
    raise exception 'invalid plan: %', p_plan;
  end if;

  insert into public.payments
    (payer_profile_id, payee_court_id, kind, amount_cents, currency, status, provider)
  values
    (uid, p_court_id, 'subscription', v_amount, 'PHP', 'paid', 'mock');

  -- subscriptions has no unique constraint on court_id, so update-or-insert.
  update public.subscriptions
     set plan = p_plan, status = 'active', amount_cents = v_amount,
         currency = 'PHP', provider = 'mock', current_period_end = v_end
   where court_id = p_court_id;
  if not found then
    insert into public.subscriptions
      (court_id, plan, status, amount_cents, currency, provider, current_period_end)
    values
      (p_court_id, p_plan, 'active', v_amount, 'PHP', 'mock', v_end);
  end if;

  update public.courts set status = 'active' where id = p_court_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tighten court visibility: subscribed (active) => publicly visible; owner/
-- staff see their own at any status; admin sees all.
-- ---------------------------------------------------------------------------
drop policy "courts_select" on public.courts;
create policy "courts_select"
  on public.courts for select
  using (
    status = 'active'
    or public.is_court_member(id)
    or public.is_platform_admin()
  );
```

- [ ] **Step 2: Apply the migration**

Run (from `supabase/`):
```bash
supabase db push
```
Expected: applies `0008_owner_court_setup.sql` with no error.

- [ ] **Step 3: Manually verify the RPCs + policy**

In the Supabase SQL editor (or psql), as an authenticated dev user (or by impersonating one), confirm:
- `select public.create_court('Test Venue', 1000, 'PHP', 2, 'Cebu');` returns a uuid; a `courts` row exists with `status='suspended'`, a `court_members` owner row exists, and 2 `court_slots` ("Court 1", "Court 2") exist.
- A second user's `select * from public.courts where id = '<that id>'` returns **0 rows** (suspended, not a member).
- `select public.subscribe_court('<that id>', 'monthly');` then the court `status='active'`, one `subscriptions` row (`active`, amount 99900), one `payments` row (`subscription`, `paid`, 99900). The second user can now see the court.
Document the result in the commit message.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0008_owner_court_setup.sql
git commit -m "feat(db): create_court + subscribe_court RPCs; gate court visibility on active subscription (0008)"
```

---

### Task 2: Persisted app mode (`appModeProvider`)

**Files:**
- Create: `app/lib/data/app_mode.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/pubspec.yaml`
- Test: `app/test/app_mode_test.dart`

**Interfaces:**
- Produces:
  - `enum AppMode { play, management }`
  - `final sharedPreferencesProvider = Provider<SharedPreferences>` (overridden in `main`)
  - `class AppModeController extends StateNotifier<AppMode>` with `Future<void> set(AppMode)`
  - `final appModeProvider = StateNotifierProvider<AppModeController, AppMode>`

- [ ] **Step 1: Add the dependency**

In `app/pubspec.yaml`, under `dependencies:` (after `google_fonts`):
```yaml
  # Local persistence (remembers Play/Management mode)
  shared_preferences: ^2.3.2
```
Run:
```bash
/c/Users/Eli/flutter/bin/flutter pub get
```
Expected: resolves `shared_preferences`.

- [ ] **Step 2: Write the failing test**

Create `app/test/app_mode_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dinksync/data/app_mode.dart';

void main() {
  group('AppModeController', () {
    test('defaults to play when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(AppModeController(prefs).state, AppMode.play);
    });

    test('set persists and reloads as management', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppModeController(prefs);

      await controller.set(AppMode.management);

      expect(controller.state, AppMode.management);
      expect(AppModeController(prefs).state, AppMode.management);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/app_mode_test.dart`
Expected: FAIL — `app_mode.dart` / `AppModeController` not found.

- [ ] **Step 4: Implement**

Create `app/lib/data/app_mode.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which experience the user is currently in. Only meaningful for users with a
/// management role; players are always effectively [AppMode.play].
enum AppMode { play, management }

const _modeKey = 'app_mode';

/// Holds the current [AppMode] and persists changes to [SharedPreferences] so
/// the choice survives app restarts.
class AppModeController extends StateNotifier<AppMode> {
  AppModeController(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static AppMode _read(SharedPreferences p) =>
      p.getString(_modeKey) == 'management' ? AppMode.management : AppMode.play;

  Future<void> set(AppMode mode) async {
    state = mode;
    await _prefs.setString(
      _modeKey,
      mode == AppMode.management ? 'management' : 'play',
    );
  }
}

/// Overridden in `main()` with the loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final appModeProvider =
    StateNotifierProvider<AppModeController, AppMode>((ref) {
  return AppModeController(ref.watch(sharedPreferencesProvider));
});
```

- [ ] **Step 5: Run test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/app_mode_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Wire SharedPreferences into `main`**

In `app/lib/main.dart`, replace the imports block and `main()`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'config/app_config.dart';
import 'data/app_mode.dart';
import 'data/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env + initialize Supabase. Fails loudly if .env is unconfigured.
  final config = await AppConfig.load();
  await initSupabase(config);
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const DinkSyncApp(),
    ),
  );
}
```
(Leave `DinkSyncApp` as-is for now; Task 9 converts it to use `routerProvider`.)

- [ ] **Step 7: Verify analyze + full test suite**

Run: `/c/Users/Eli/flutter/bin/flutter analyze && /c/Users/Eli/flutter/bin/flutter test`
Expected: analyze clean; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/app_mode.dart lib/main.dart test/app_mode_test.dart
git commit -m "feat(shell): persisted Play/Management app mode"
```

---

### Task 3: Capabilities (`capabilitiesProvider`)

**Files:**
- Create: `app/lib/data/capabilities.dart`
- Test: `app/test/capabilities_test.dart`

**Interfaces:**
- Consumes: global `supabase` from `data/supabase_client.dart`.
- Produces:
  - `class Capabilities { final bool isAdmin; final bool isManager; ... Capabilities.from({required bool isAdmin, required List<String> memberRoles}); }`
  - `final capabilitiesProvider = FutureProvider<Capabilities>`

- [ ] **Step 1: Write the failing test**

Create `app/test/capabilities_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/data/capabilities.dart';

void main() {
  group('Capabilities.from', () {
    test('no roles, not admin -> player only', () {
      final c = Capabilities.from(isAdmin: false, memberRoles: const []);
      expect(c.isAdmin, false);
      expect(c.isManager, false);
    });

    test('any court_members role -> manager', () {
      expect(
        Capabilities.from(isAdmin: false, memberRoles: const ['staff']).isManager,
        true,
      );
      expect(
        Capabilities.from(isAdmin: false, memberRoles: const ['owner']).isManager,
        true,
      );
    });

    test('admin flag is carried through', () {
      expect(
        Capabilities.from(isAdmin: true, memberRoles: const []).isAdmin,
        true,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/capabilities_test.dart`
Expected: FAIL — `capabilities.dart` not found.

- [ ] **Step 3: Implement**

Create `app/lib/data/capabilities.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase_client.dart';

/// What a signed-in user is allowed to do. Roles are derived, not a single
/// column: admin from profiles.is_platform_admin, manager from any
/// court_members row (owner or staff).
class Capabilities {
  const Capabilities({required this.isAdmin, required this.isManager});
  const Capabilities.none() : isAdmin = false, isManager = false;

  final bool isAdmin;
  final bool isManager;

  factory Capabilities.from({
    required bool isAdmin,
    required List<String> memberRoles,
  }) {
    return Capabilities(isAdmin: isAdmin, isManager: memberRoles.isNotEmpty);
  }
}

/// Reads the current user's capabilities once. Invalidate after creating a
/// court so the mode dropdown appears.
final capabilitiesProvider = FutureProvider<Capabilities>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const Capabilities.none();

  final profile = await supabase
      .from('profiles')
      .select('is_platform_admin')
      .eq('id', uid)
      .maybeSingle();

  final members =
      await supabase.from('court_members').select('role').eq('profile_id', uid);

  final roles = (members as List)
      .map((m) => (m as Map<String, dynamic>)['role'] as String)
      .toList();

  return Capabilities.from(
    isAdmin: (profile?['is_platform_admin'] as bool?) ?? false,
    memberRoles: roles,
  );
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/capabilities_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/capabilities.dart test/capabilities_test.dart
git commit -m "feat(shell): derive user capabilities (admin/manager)"
```

---

### Task 4: Court repository, models, helpers

**Files:**
- Create: `app/lib/features/owner/court_repository.dart`
- Test: `app/test/court_repository_test.dart`

**Interfaces:**
- Consumes: global `supabase`.
- Produces:
  - `class Court { final String id, name, status, currency; final int entryFeeCents, numCourts; final String? address; bool get isActive; factory Court.fromMap(Map<String,dynamic>); }`
  - `enum SubscriptionPlan { monthly, yearly }`, `int planPriceCents(SubscriptionPlan)`, `String planName(SubscriptionPlan)`
  - `int? parseAmountToMinor(String)`
  - `abstract class CourtRepository { Future<Court?> myCourt(); Future<String> createCourt({required String name, required int entryFeeCents, required String currency, required int numCourts, String? address}); Future<void> subscribeCourt({required String courtId, required SubscriptionPlan plan}); Future<void> updateCourt({required String courtId, required String name, required int entryFeeCents, String? address}); }`
  - `final courtRepositoryProvider = Provider<CourtRepository>`
  - `final ownerCourtProvider = FutureProvider<Court?>`

- [ ] **Step 1: Write the failing test**

Create `app/test/court_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/owner/court_repository.dart';

void main() {
  group('parseAmountToMinor', () {
    test('whole pesos -> centavos', () {
      expect(parseAmountToMinor('999'), 99900);
    });
    test('decimal pesos -> centavos (rounded)', () {
      expect(parseAmountToMinor('12.50'), 1250);
      expect(parseAmountToMinor('12.505'), 1251);
    });
    test('blank or invalid or negative -> null', () {
      expect(parseAmountToMinor(''), null);
      expect(parseAmountToMinor('abc'), null);
      expect(parseAmountToMinor('-5'), null);
    });
  });

  group('plan pricing', () {
    test('canonical centavo prices', () {
      expect(planPriceCents(SubscriptionPlan.monthly), 99900);
      expect(planPriceCents(SubscriptionPlan.yearly), 999000);
    });
    test('plan db names', () {
      expect(planName(SubscriptionPlan.monthly), 'monthly');
      expect(planName(SubscriptionPlan.yearly), 'yearly');
    });
  });

  group('Court.fromMap', () {
    test('maps fields and isActive', () {
      final c = Court.fromMap(const {
        'id': 'c1',
        'name': 'Cebu Dinks',
        'status': 'active',
        'entry_fee_cents': 5000,
        'currency': 'PHP',
        'num_courts': 3,
        'address': 'Cebu City',
      });
      expect(c.id, 'c1');
      expect(c.name, 'Cebu Dinks');
      expect(c.isActive, true);
      expect(c.entryFeeCents, 5000);
      expect(c.numCourts, 3);
      expect(c.address, 'Cebu City');
    });
    test('suspended is not active; null address ok', () {
      final c = Court.fromMap(const {
        'id': 'c2',
        'name': 'X',
        'status': 'suspended',
        'entry_fee_cents': 0,
        'currency': 'PHP',
        'num_courts': 1,
        'address': null,
      });
      expect(c.isActive, false);
      expect(c.address, null);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_repository_test.dart`
Expected: FAIL — `court_repository.dart` not found.

- [ ] **Step 3: Implement**

Create `app/lib/features/owner/court_repository.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

/// A court venue owned/managed by the current user.
class Court {
  const Court({
    required this.id,
    required this.name,
    required this.status,
    required this.entryFeeCents,
    required this.currency,
    required this.numCourts,
    this.address,
  });

  final String id;
  final String name;
  final String status; // active | suspended | offboarded
  final int entryFeeCents;
  final String currency;
  final int numCourts;
  final String? address;

  bool get isActive => status == 'active';

  factory Court.fromMap(Map<String, dynamic> m) => Court(
        id: m['id'] as String,
        name: m['name'] as String,
        status: m['status'] as String,
        entryFeeCents: m['entry_fee_cents'] as int,
        currency: m['currency'] as String,
        numCourts: m['num_courts'] as int,
        address: m['address'] as String?,
      );
}

enum SubscriptionPlan { monthly, yearly }

/// Canonical centavo prices (mirror the server-side values in 0008).
int planPriceCents(SubscriptionPlan p) =>
    p == SubscriptionPlan.monthly ? 99900 : 999000;

String planName(SubscriptionPlan p) =>
    p == SubscriptionPlan.monthly ? 'monthly' : 'yearly';

/// Parse a user-entered major-unit amount ("999", "12.50") into integer minor
/// units (centavos). Returns null for blank/invalid/negative input.
int? parseAmountToMinor(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

abstract class CourtRepository {
  Future<Court?> myCourt();
  Future<String> createCourt({
    required String name,
    required int entryFeeCents,
    required String currency,
    required int numCourts,
    String? address,
  });
  Future<void> subscribeCourt({
    required String courtId,
    required SubscriptionPlan plan,
  });
  Future<void> updateCourt({
    required String courtId,
    required String name,
    required int entryFeeCents,
    String? address,
  });
}

class SupabaseCourtRepository implements CourtRepository {
  SupabaseCourtRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<Court?> myCourt() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final rows = await _db
        .from('courts')
        .select()
        .eq('owner_profile_id', uid)
        .limit(1);
    final list = rows as List;
    return list.isEmpty
        ? null
        : Court.fromMap(list.first as Map<String, dynamic>);
  }

  @override
  Future<String> createCourt({
    required String name,
    required int entryFeeCents,
    required String currency,
    required int numCourts,
    String? address,
  }) async {
    final id = await _db.rpc('create_court', params: {
      'p_name': name,
      'p_entry_fee_cents': entryFeeCents,
      'p_currency': currency,
      'p_num_courts': numCourts,
      'p_address': address,
    });
    return id as String;
  }

  @override
  Future<void> subscribeCourt({
    required String courtId,
    required SubscriptionPlan plan,
  }) async {
    await _db.rpc('subscribe_court', params: {
      'p_court_id': courtId,
      'p_plan': planName(plan),
    });
  }

  @override
  Future<void> updateCourt({
    required String courtId,
    required String name,
    required int entryFeeCents,
    String? address,
  }) async {
    await _db.from('courts').update({
      'name': name,
      'entry_fee_cents': entryFeeCents,
      'address': address,
    }).eq('id', courtId);
  }
}

final courtRepositoryProvider = Provider<CourtRepository>(
  (ref) => SupabaseCourtRepository(supabase),
);

final ownerCourtProvider = FutureProvider<Court?>(
  (ref) => ref.watch(courtRepositoryProvider).myCourt(),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_repository_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/owner/court_repository.dart test/court_repository_test.dart
git commit -m "feat(owner): court model, repository, pricing + amount helpers"
```

---

### Task 5: Court onboarding screen

**Files:**
- Create: `app/lib/features/owner/court_onboarding_screen.dart`
- Test: `app/test/court_onboarding_screen_test.dart`

**Interfaces:**
- Consumes: `courtRepositoryProvider`, `Court*`/`parseAmountToMinor` from Task 4; `kBrandGreen`/`kRadius` from theme.
- Produces: `class CourtOnboardingScreen extends ConsumerStatefulWidget`. On success calls `onCreated(String courtId)` (constructor callback) so the router can navigate; in tests this is asserted.

- [ ] **Step 1: Write the failing test**

Create `app/test/court_onboarding_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/owner/court_onboarding_screen.dart';
import 'package:dinksync/features/owner/court_repository.dart';

class _FakeRepo implements CourtRepository {
  int createCalls = 0;
  Map<String, Object?>? lastArgs;

  @override
  Future<String> createCourt({
    required String name,
    required int entryFeeCents,
    required String currency,
    required int numCourts,
    String? address,
  }) async {
    createCalls++;
    lastArgs = {
      'name': name,
      'entryFeeCents': entryFeeCents,
      'numCourts': numCourts,
    };
    return 'new-court-id';
  }

  @override
  Future<Court?> myCourt() async => null;
  @override
  Future<void> subscribeCourt(
          {required String courtId, required SubscriptionPlan plan}) async {}
  @override
  Future<void> updateCourt(
      {required String courtId,
      required String name,
      required int entryFeeCents,
      String? address}) async {}
}

Widget _host(_FakeRepo repo, {void Function(String)? onCreated}) {
  return ProviderScope(
    overrides: [courtRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: CourtOnboardingScreen(onCreated: onCreated ?? (_) {}),
    ),
  );
}

void main() {
  testWidgets('blank name blocks submit and shows error', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));

    await tester.tap(find.text('Create court'));
    await tester.pump();

    expect(repo.createCalls, 0);
    expect(find.text('Court name is required'), findsOneWidget);
  });

  testWidgets('valid form calls createCourt and onCreated', (tester) async {
    final repo = _FakeRepo();
    String? created;
    await tester.pumpWidget(_host(repo, onCreated: (id) => created = id));

    await tester.enterText(find.bySemanticsLabel('Court name'), 'Cebu Dinks');
    await tester.enterText(
        find.bySemanticsLabel('Entry fee (PHP)'), '50');
    await tester.tap(find.text('Create court'));
    await tester.pumpAndSettle();

    expect(repo.createCalls, 1);
    expect(repo.lastArgs!['name'], 'Cebu Dinks');
    expect(repo.lastArgs!['entryFeeCents'], 5000);
    expect(repo.lastArgs!['numCourts'], 1);
    expect(created, 'new-court-id');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_onboarding_screen_test.dart`
Expected: FAIL — `court_onboarding_screen.dart` not found.

- [ ] **Step 3: Implement**

Create `app/lib/features/owner/court_onboarding_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'court_repository.dart';

/// Step 1 of becoming a host: enter venue details. Creating the court does NOT
/// publish it — the subscription step (next) does. On success, [onCreated] is
/// called with the new court id so the router can route to the subscription page.
class CourtOnboardingScreen extends ConsumerStatefulWidget {
  const CourtOnboardingScreen({super.key, required this.onCreated});

  final void Function(String courtId) onCreated;

  @override
  ConsumerState<CourtOnboardingScreen> createState() =>
      _CourtOnboardingScreenState();
}

class _CourtOnboardingScreenState extends ConsumerState<CourtOnboardingScreen> {
  final _nameCtl = TextEditingController();
  final _feeCtl = TextEditingController(text: '0');
  final _slotsCtl = TextEditingController(text: '1');
  final _addressCtl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtl.dispose();
    _feeCtl.dispose();
    _slotsCtl.dispose();
    _addressCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Court name is required');
      return;
    }
    final fee = parseAmountToMinor(_feeCtl.text) ?? 0;
    final slots = int.tryParse(_slotsCtl.text.trim()) ?? 0;
    if (slots < 1) {
      setState(() => _error = 'Number of courts must be at least 1');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(courtRepositoryProvider).createCourt(
            name: name,
            entryFeeCents: fee,
            currency: 'PHP',
            numCourts: slots,
            address: _addressCtl.text.trim().isEmpty
                ? null
                : _addressCtl.text.trim(),
          );
      if (mounted) widget.onCreated(id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not create court. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your court')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tell us about your venue. You can edit these later.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Court name',
                prefixIcon: Icon(Icons.stadium_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _feeCtl,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Entry fee (PHP)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _slotsCtl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of courts (playing surfaces)',
                prefixIcon: Icon(Icons.grid_view_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create court'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_onboarding_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/owner/court_onboarding_screen.dart test/court_onboarding_screen_test.dart
git commit -m "feat(owner): court onboarding form"
```

---

### Task 6: Subscription screen

**Files:**
- Create: `app/lib/features/owner/subscription_screen.dart`
- Test: `app/test/subscription_screen_test.dart`

**Interfaces:**
- Consumes: `courtRepositoryProvider`, `SubscriptionPlan`, `planPriceCents` (Task 4).
- Produces: `class SubscriptionScreen extends ConsumerStatefulWidget` with `final String courtId; final void Function() onSubscribed;`. Defaults the selected plan to monthly.

- [ ] **Step 1: Write the failing test**

Create `app/test/subscription_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/owner/subscription_screen.dart';
import 'package:dinksync/features/owner/court_repository.dart';

class _FakeRepo implements CourtRepository {
  SubscriptionPlan? subscribedPlan;
  String? subscribedCourt;

  @override
  Future<void> subscribeCourt(
      {required String courtId, required SubscriptionPlan plan}) async {
    subscribedCourt = courtId;
    subscribedPlan = plan;
  }

  @override
  Future<Court?> myCourt() async => null;
  @override
  Future<String> createCourt(
          {required String name,
          required int entryFeeCents,
          required String currency,
          required int numCourts,
          String? address}) async =>
      'x';
  @override
  Future<void> updateCourt(
      {required String courtId,
      required String name,
      required int entryFeeCents,
      String? address}) async {}
}

Widget _host(_FakeRepo repo, {void Function()? onSubscribed}) {
  return ProviderScope(
    overrides: [courtRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: SubscriptionScreen(
        courtId: 'court-1',
        onSubscribed: onSubscribed ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('defaults to monthly and subscribes', (tester) async {
    final repo = _FakeRepo();
    var done = false;
    await tester.pumpWidget(_host(repo, onSubscribed: () => done = true));

    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    expect(repo.subscribedCourt, 'court-1');
    expect(repo.subscribedPlan, SubscriptionPlan.monthly);
    expect(done, true);
  });

  testWidgets('selecting yearly subscribes yearly', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));

    await tester.tap(find.text('Yearly'));
    await tester.pump();
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    expect(repo.subscribedPlan, SubscriptionPlan.yearly);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/subscription_screen_test.dart`
Expected: FAIL — `subscription_screen.dart` not found.

- [ ] **Step 3: Implement**

Create `app/lib/features/owner/subscription_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'court_repository.dart';

/// Step 2 of becoming a host: subscribe to publish the court. Uses the mock
/// payment path (the RPC records a paid payment + activates the court).
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.courtId,
    required this.onSubscribed,
  });

  final String courtId;
  final void Function() onSubscribed;

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  SubscriptionPlan _plan = SubscriptionPlan.monthly;
  bool _busy = false;
  String? _error;

  String _peso(int centavos) => '₱${(centavos / 100).toStringAsFixed(0)}';

  Future<void> _subscribe() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(courtRepositoryProvider).subscribeCourt(
            courtId: widget.courtId,
            plan: _plan,
          );
      if (mounted) widget.onSubscribed();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Subscription failed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _planTile(SubscriptionPlan plan, String title, String sub) {
    final selected = _plan == plan;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: _busy ? null : () => setState(() => _plan = plan),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(
            color: selected ? kBrandGreen : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? kBrandGreen : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(sub,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Subscribe to publish')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A subscription keeps your court listed and bookable. Players '
              "can't see it until you subscribe.",
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _planTile(
              SubscriptionPlan.monthly,
              'Monthly',
              '${_peso(planPriceCents(SubscriptionPlan.monthly))} / month',
            ),
            const SizedBox(height: 12),
            _planTile(
              SubscriptionPlan.yearly,
              'Yearly',
              '${_peso(planPriceCents(SubscriptionPlan.yearly))} / year — 2 months free',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _subscribe,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Subscribe'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/subscription_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/owner/subscription_screen.dart test/subscription_screen_test.dart
git commit -m "feat(owner): subscription screen (mock pay, monthly/yearly)"
```

---

### Task 7: Management screen + dashboard

**Files:**
- Create: `app/lib/features/owner/owner_dashboard_screen.dart`
- Test: `app/test/owner_dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `Court` (Task 4), `kBrandGreen`/`kRadius`.
- Produces: `class OwnerDashboard extends StatelessWidget` with `final Court court; final VoidCallback onSubscribe;` — a pure presentational widget (no provider reads) so it's trivially testable. (The routing-level `ManagementScreen` that chooses onboarding vs dashboard is built in Task 9.)

- [ ] **Step 1: Write the failing test**

Create `app/test/owner_dashboard_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/owner/court_repository.dart';
import 'package:dinksync/features/owner/owner_dashboard_screen.dart';

const _active = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 5000,
  currency: 'PHP',
  numCourts: 3,
);

const _suspended = Court(
  id: 'c2',
  name: 'Manila Smash',
  status: 'suspended',
  entryFeeCents: 0,
  currency: 'PHP',
  numCourts: 1,
);

Widget _host(Court court, {VoidCallback? onSubscribe}) => MaterialApp(
      home: OwnerDashboard(court: court, onSubscribe: onSubscribe ?? () {}),
    );

void main() {
  testWidgets('active court: no suspended banner, shows metric cards',
      (tester) async {
    await tester.pumpWidget(_host(_active));

    expect(find.text('Cebu Dinks'), findsOneWidget);
    expect(find.textContaining('hidden from players'), findsNothing);
    expect(find.text("Today's revenue"), findsOneWidget);
    expect(find.text('Players today'), findsOneWidget);
    expect(find.text('Active queue'), findsOneWidget);
  });

  testWidgets('suspended court: shows banner, tapping calls onSubscribe',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(_suspended, onSubscribe: () => tapped = true));

    expect(find.textContaining('hidden from players'), findsOneWidget);

    await tester.tap(find.text('Subscribe'));
    await tester.pump();
    expect(tapped, true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/owner_dashboard_screen_test.dart`
Expected: FAIL — `owner_dashboard_screen.dart` not found.

- [ ] **Step 3: Implement**

Create `app/lib/features/owner/owner_dashboard_screen.dart`:
```dart
import 'package:flutter/material.dart';

import 'court_repository.dart';

/// Presentational management dashboard for a single court. Metric cards are
/// empty states until the player loop feeds real data. A suspended court shows
/// a "subscribe to publish" banner.
class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({
    super.key,
    required this.court,
    required this.onSubscribe,
  });

  final Court court;
  final VoidCallback onSubscribe;

  String get _fee => '₱${(court.entryFeeCents / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(court.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Entry fee $_fee · ${court.numCourts} '
          '${court.numCourts == 1 ? 'court' : 'courts'}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (!court.isActive)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subscription inactive — your court is hidden from players.',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: onSubscribe,
                  child: const Text('Subscribe'),
                ),
              ],
            ),
          ),
        if (!court.isActive) const SizedBox(height: 20),
        const _MetricCard(
          icon: Icons.payments_outlined,
          title: "Today's revenue",
          empty: 'No revenue yet',
        ),
        const SizedBox(height: 12),
        const _MetricCard(
          icon: Icons.groups_outlined,
          title: 'Players today',
          empty: 'No players yet',
        ),
        const SizedBox(height: 12),
        const _MetricCard(
          icon: Icons.timer_outlined,
          title: 'Active queue',
          empty: 'Queue is empty',
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.empty,
  });

  final IconData icon;
  final String title;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text(empty,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/owner_dashboard_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/owner/owner_dashboard_screen.dart test/owner_dashboard_screen_test.dart
git commit -m "feat(owner): management dashboard with empty states + suspended banner"
```

---

### Task 8: Shell — mode dropdown + placeholder tabs

**Files:**
- Create: `app/lib/features/shell/mode_dropdown.dart`
- Create: `app/lib/features/shell/placeholder_tab.dart`
- Test: `app/test/mode_dropdown_test.dart`

**Interfaces:**
- Consumes: `capabilitiesProvider` (Task 3), `appModeProvider` (Task 2).
- Produces:
  - `class ModeDropdown extends ConsumerWidget` — renders nothing unless `capabilities.isManager`; shows current mode; on change calls `appModeProvider.notifier.set(...)` and `onChanged(AppMode)` (callback so the router navigates).
  - `class PlaceholderTab extends StatelessWidget { final String title; final IconData icon; final String message; }`

- [ ] **Step 1: Write the failing test**

Create `app/test/mode_dropdown_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dinksync/data/app_mode.dart';
import 'package:dinksync/data/capabilities.dart';
import 'package:dinksync/features/shell/mode_dropdown.dart';

Future<Widget> _host({required bool isManager}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWith(
        (ref) async =>
            Capabilities(isAdmin: false, isManager: isManager),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: ModeDropdown(onChanged: (_) {})),
      ),
    ),
  );
}

void main() {
  testWidgets('hidden for non-managers', (tester) async {
    await tester.pumpWidget(await _host(isManager: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mode-dropdown')), findsNothing);
  });

  testWidgets('shown for managers', (tester) async {
    await tester.pumpWidget(await _host(isManager: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mode-dropdown')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/mode_dropdown_test.dart`
Expected: FAIL — `mode_dropdown.dart` not found.

- [ ] **Step 3: Implement the placeholder tab**

Create `app/lib/features/shell/placeholder_tab.dart`:
```dart
import 'package:flutter/material.dart';

/// A simple centered empty state for tabs not yet built (Play, Social).
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement the mode dropdown**

Create `app/lib/features/shell/mode_dropdown.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// Top-bar Play/Management switch. Renders nothing unless the user is a
/// manager. Persists the selection and calls [onChanged] so the caller can
/// navigate to the matching shell.
class ModeDropdown extends ConsumerWidget {
  const ModeDropdown({super.key, required this.onChanged});

  final void Function(AppMode) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider).valueOrNull;
    if (caps == null || !caps.isManager) return const SizedBox.shrink();

    final mode = ref.watch(appModeProvider);
    return DropdownButtonHideUnderline(
      key: const Key('mode-dropdown'),
      child: DropdownButton<AppMode>(
        value: mode,
        onChanged: (m) {
          if (m == null) return;
          ref.read(appModeProvider.notifier).set(m);
          onChanged(m);
        },
        items: const [
          DropdownMenuItem(value: AppMode.play, child: Text('Play')),
          DropdownMenuItem(
              value: AppMode.management, child: Text('Court Management')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/mode_dropdown_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/shell/mode_dropdown.dart lib/features/shell/placeholder_tab.dart test/mode_dropdown_test.dart
git commit -m "feat(shell): mode dropdown + placeholder tabs"
```

---

### Task 9: Router wiring, launch decider, management screen, profile entry

**Files:**
- Create: `app/lib/features/shell/play_shell.dart`
- Create: `app/lib/features/shell/launch_screen.dart`
- Create: `app/lib/features/owner/management_screen.dart`
- Modify: `app/lib/app/router.dart` (full rewrite)
- Modify: `app/lib/main.dart` (use `routerProvider`)
- Modify: `app/lib/features/profile/profile_screen.dart` (add "Own a court?" entry)
- Test: `app/test/router_logic_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 2–8.
- Produces:
  - `String launchTarget({required bool isManager, required AppMode mode})` → `/manage` or `/play` (pure, tested).
  - `final routerProvider = Provider<GoRouter>`.
  - Routes: `/auth`, `/` (launch decider), Play `StatefulShellRoute` (`/play`, `/social`, `/profile`), `/manage`, `/manage/subscribe`.

- [ ] **Step 1: Write the failing test**

Create `app/test/router_logic_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/data/app_mode.dart';
import 'package:dinksync/app/router.dart';

void main() {
  group('launchTarget', () {
    test('manager who last used management -> /manage', () {
      expect(
        launchTarget(isManager: true, mode: AppMode.management),
        '/manage',
      );
    });
    test('manager in play mode -> /play', () {
      expect(launchTarget(isManager: true, mode: AppMode.play), '/play');
    });
    test('non-manager always -> /play', () {
      expect(launchTarget(isManager: false, mode: AppMode.management), '/play');
      expect(launchTarget(isManager: false, mode: AppMode.play), '/play');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/router_logic_test.dart`
Expected: FAIL — `launchTarget` not defined.

- [ ] **Step 3: Implement the launch screen**

Create `app/lib/features/shell/launch_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// Transient '/' screen: once capabilities resolve, routes to the right shell
/// based on the persisted mode. Shows a spinner while loading.
class LaunchScreen extends ConsumerWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final mode = ref.watch(appModeProvider);

    return caps.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/play');
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
      data: (c) {
        final target = launchTarget(isManager: c.isManager, mode: mode);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go(target);
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
```

- [ ] **Step 4: Implement the play shell**

Create `app/lib/features/shell/play_shell.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_mode.dart';
import 'mode_dropdown.dart';

/// Bottom-nav scaffold for Play mode. Wraps the Play/Social/Profile branches.
class PlayShell extends StatelessWidget {
  const PlayShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('dinkSync'),
        actions: [
          ModeDropdown(
            onChanged: (m) {
              if (m == AppMode.management) context.go('/manage');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.sports_tennis_outlined),
              selectedIcon: Icon(Icons.sports_tennis),
              label: 'Play'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Social'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Implement the management screen**

Create `app/lib/features/owner/management_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_mode.dart';
import '../shell/mode_dropdown.dart';
import 'court_onboarding_screen.dart';
import 'court_repository.dart';
import 'owner_dashboard_screen.dart';

/// Court Management mode entry. Shows onboarding if the user owns no court,
/// otherwise the dashboard. Reachable by any signed-in user (first-time hosts).
class ManagementScreen extends ConsumerWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(ownerCourtProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Court Management'),
        actions: [
          ModeDropdown(
            onChanged: (m) {
              if (m == AppMode.play) context.go('/play');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: courtAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorRetry(
          onRetry: () => ref.invalidate(ownerCourtProvider),
        ),
        data: (court) {
          if (court == null) {
            return CourtOnboardingScreen(
              onCreated: (_) {
                ref.invalidate(ownerCourtProvider);
                ref.invalidate(capabilitiesProviderRefresh);
                context.go('/manage/subscribe');
              },
            );
          }
          if (!court.isActive) {
            // Allow jumping straight to subscribe from a suspended court.
            return OwnerDashboard(
              court: court,
              onSubscribe: () => context.go('/manage/subscribe'),
            );
          }
          return OwnerDashboard(court: court, onSubscribe: () {});
        },
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load your court.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
```
Note: `capabilitiesProviderRefresh` does not exist — use `ref.invalidate(capabilitiesProvider)` instead. Replace the line `ref.invalidate(capabilitiesProviderRefresh);` with `ref.invalidate(capabilitiesProvider);` and add the import `import '../../data/capabilities.dart';` at the top.

- [ ] **Step 6: Rewrite the router**

Replace the entire contents of `app/lib/app/router.dart`:
```dart
import 'dart:async' show StreamSubscription;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_mode.dart';
import '../data/supabase_client.dart';
import '../features/auth/auth_screen.dart';
import '../features/owner/court_repository.dart';
import '../features/owner/management_screen.dart';
import '../features/owner/subscription_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/launch_screen.dart';
import '../features/shell/placeholder_tab.dart';
import '../features/shell/play_shell.dart';

/// Where a signed-in user should land on launch, given their role + last mode.
String launchTarget({required bool isManager, required AppMode mode}) {
  if (isManager && mode == AppMode.management) return '/manage';
  return '/play';
}

final _shellKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(),
    redirect: (context, state) {
      final signedIn = supabase.auth.currentSession != null;
      final onAuth = state.matchedLocation == '/auth';
      if (!signedIn && !onAuth) return '/auth';
      if (signedIn && onAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (c, s) => const AuthScreen()),
      GoRoute(path: '/', builder: (c, s) => const LaunchScreen()),
      GoRoute(path: '/manage', builder: (c, s) => const ManagementScreen()),
      GoRoute(
        path: '/manage/subscribe',
        builder: (c, s) => _SubscribeRoute(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (c, s, navShell) => PlayShell(navigationShell: navShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/play',
              builder: (c, s) => const PlaceholderTab(
                title: 'Find a game',
                icon: Icons.sports_tennis,
                message: 'Court discovery and matchmaking are coming soon.',
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/social',
              builder: (c, s) => const PlaceholderTab(
                title: 'Social',
                icon: Icons.groups,
                message: 'Friends and activity are coming soon.',
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (c, s) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
});

/// Resolves the owner's current court id, then shows the subscription screen.
class _SubscribeRoute extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(ownerCourtProvider);
    return courtAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          const Scaffold(body: Center(child: Text('Could not load court.'))),
      data: (court) {
        if (court == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/manage');
          });
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return SubscriptionScreen(
          courtId: court.id,
          onSubscribed: () {
            ref.invalidate(ownerCourtProvider);
            context.go('/manage');
          },
        );
      },
    );
  }
}

/// Bridges Supabase auth changes to GoRouter's redirect.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable() {
    _sub = supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```
(The `_shellKey` is unused if not referenced; remove it if `flutter analyze` flags it.)

- [ ] **Step 7: Use `routerProvider` in `main.dart`**

In `app/lib/main.dart`, change `DinkSyncApp` to a `ConsumerWidget`:
```dart
class DinkSyncApp extends ConsumerWidget {
  const DinkSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'dinkSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
```

- [ ] **Step 8: Add the "Own a court?" entry to the Profile screen**

In `app/lib/features/profile/profile_screen.dart`, add `import 'package:go_router/go_router.dart';` to the imports, then insert this just after the "Sign out" `OutlinedButton.icon(...)` (before the `const SizedBox(height: 28)` that precedes the RLS card):
```dart
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/manage'),
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Own a court? Set it up'),
                  ),
```

- [ ] **Step 9: Run logic test + analyze + full suite**

Run:
```bash
/c/Users/Eli/flutter/bin/flutter test test/router_logic_test.dart
/c/Users/Eli/flutter/bin/flutter analyze
/c/Users/Eli/flutter/bin/flutter test
```
Expected: `launchTarget` tests PASS; analyze clean (remove `_shellKey` if flagged); full suite passes.

- [ ] **Step 10: Manual smoke (web)**

Run from `app/`:
```bash
/c/Users/Eli/flutter/bin/flutter run -d web-server --web-port=8080
```
Verify: sign in as a player (dev login) → lands on `/play` with bottom nav (Play/Social/Profile), no mode dropdown. Profile tab → "Own a court? Set it up" → onboarding → create → subscribe (mock) → dashboard becomes active; mode dropdown now appears and persists across restart. Switch to Play and back.

- [ ] **Step 11: Commit**

```bash
git add lib/app/router.dart lib/main.dart lib/features/shell/launch_screen.dart lib/features/shell/play_shell.dart lib/features/owner/management_screen.dart lib/features/profile/profile_screen.dart test/router_logic_test.dart
git commit -m "feat(shell): wire two-shell router, launch decider, management screen, host entry"
```

---

### Task 10: Edit-court screen

**Files:**
- Create: `app/lib/features/owner/court_edit_screen.dart`
- Modify: `app/lib/features/owner/owner_dashboard_screen.dart` (add optional `onEdit` + edit button)
- Modify: `app/lib/features/owner/management_screen.dart` (pass `onEdit`)
- Modify: `app/lib/app/router.dart` (add `/manage/edit` route)
- Test: `app/test/court_edit_screen_test.dart`

**Interfaces:**
- Consumes: `Court`, `courtRepositoryProvider.updateCourt`, `parseAmountToMinor` (Task 4); `ownerCourtProvider` (Task 4).
- Produces: `class CourtEditScreen extends ConsumerStatefulWidget { final Court court; final void Function() onSaved; }`. `OwnerDashboard` gains an optional `final VoidCallback? onEdit;` (an edit button shows only when non-null — keeps Task 7's test valid).

- [ ] **Step 1: Write the failing test**

Create `app/test/court_edit_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/owner/court_edit_screen.dart';
import 'package:dinksync/features/owner/court_repository.dart';
import 'package:dinksync/features/owner/owner_dashboard_screen.dart';

const _court = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 5000,
  currency: 'PHP',
  numCourts: 3,
  address: 'Cebu City',
);

class _FakeRepo implements CourtRepository {
  int updateCalls = 0;
  Map<String, Object?>? lastArgs;

  @override
  Future<void> updateCourt({
    required String courtId,
    required String name,
    required int entryFeeCents,
    String? address,
  }) async {
    updateCalls++;
    lastArgs = {'courtId': courtId, 'name': name, 'entryFeeCents': entryFeeCents};
  }

  @override
  Future<Court?> myCourt() async => null;
  @override
  Future<String> createCourt(
          {required String name,
          required int entryFeeCents,
          required String currency,
          required int numCourts,
          String? address}) async =>
      'x';
  @override
  Future<void> subscribeCourt(
      {required String courtId, required SubscriptionPlan plan}) async {}
}

Widget _editHost(_FakeRepo repo, {void Function()? onSaved}) => ProviderScope(
      overrides: [courtRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: CourtEditScreen(court: _court, onSaved: onSaved ?? () {}),
      ),
    );

void main() {
  testWidgets('prefills, saves changes, calls onSaved', (tester) async {
    final repo = _FakeRepo();
    var saved = false;
    await tester.pumpWidget(_editHost(repo, onSaved: () => saved = true));

    expect(find.text('Cebu Dinks'), findsOneWidget); // prefilled name

    await tester.enterText(
        find.bySemanticsLabel('Court name'), 'Cebu Dinks 2');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(repo.updateCalls, 1);
    expect(repo.lastArgs!['courtId'], 'c1');
    expect(repo.lastArgs!['name'], 'Cebu Dinks 2');
    expect(repo.lastArgs!['entryFeeCents'], 5000);
    expect(saved, true);
  });

  testWidgets('blank name blocks save', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_editHost(repo));

    await tester.enterText(find.bySemanticsLabel('Court name'), '');
    await tester.tap(find.text('Save changes'));
    await tester.pump();

    expect(repo.updateCalls, 0);
    expect(find.text('Court name is required'), findsOneWidget);
  });

  testWidgets('dashboard shows edit button only when onEdit provided',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: OwnerDashboard(
        court: _court,
        onSubscribe: () {},
        onEdit: () => tapped = true,
      ),
    ));

    final editBtn = find.byKey(const Key('edit-court-button'));
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pump();
    expect(tapped, true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_edit_screen_test.dart`
Expected: FAIL — `court_edit_screen.dart` not found / `onEdit` not a parameter.

- [ ] **Step 3: Implement the edit screen**

Create `app/lib/features/owner/court_edit_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'court_repository.dart';

/// Edit a court's name, entry fee, and address (not slot count — that touches
/// court_slots). Uses the direct `updateCourt` path (allowed by courts_update_owner).
class CourtEditScreen extends ConsumerStatefulWidget {
  const CourtEditScreen({super.key, required this.court, required this.onSaved});

  final Court court;
  final void Function() onSaved;

  @override
  ConsumerState<CourtEditScreen> createState() => _CourtEditScreenState();
}

class _CourtEditScreenState extends ConsumerState<CourtEditScreen> {
  late final TextEditingController _nameCtl =
      TextEditingController(text: widget.court.name);
  late final TextEditingController _feeCtl = TextEditingController(
      text: (widget.court.entryFeeCents / 100).toStringAsFixed(0));
  late final TextEditingController _addressCtl =
      TextEditingController(text: widget.court.address ?? '');

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtl.dispose();
    _feeCtl.dispose();
    _addressCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Court name is required');
      return;
    }
    final fee = parseAmountToMinor(_feeCtl.text) ?? 0;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(courtRepositoryProvider).updateCourt(
            courtId: widget.court.id,
            name: name,
            entryFeeCents: fee,
            address: _addressCtl.text.trim().isEmpty
                ? null
                : _addressCtl.text.trim(),
          );
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit court')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Court name',
                prefixIcon: Icon(Icons.stadium_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _feeCtl,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Entry fee (PHP)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the optional edit button to `OwnerDashboard`**

In `app/lib/features/owner/owner_dashboard_screen.dart`, add the field to the constructor — change:
```dart
  const OwnerDashboard({
    super.key,
    required this.court,
    required this.onSubscribe,
  });

  final Court court;
  final VoidCallback onSubscribe;
```
to:
```dart
  const OwnerDashboard({
    super.key,
    required this.court,
    required this.onSubscribe,
    this.onEdit,
  });

  final Court court;
  final VoidCallback onSubscribe;
  final VoidCallback? onEdit;
```
Then replace the header line:
```dart
        Text(court.name, style: theme.textTheme.headlineSmall),
```
with:
```dart
        Row(
          children: [
            Expanded(
              child: Text(court.name, style: theme.textTheme.headlineSmall),
            ),
            if (onEdit != null)
              IconButton(
                key: const Key('edit-court-button'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit court',
              ),
          ],
        ),
```

- [ ] **Step 5: Wire the route + management screen**

In `app/lib/app/router.dart`, add an import:
```dart
import '../features/owner/court_edit_screen.dart';
```
Add a route after the `/manage/subscribe` `GoRoute`:
```dart
      GoRoute(
        path: '/manage/edit',
        builder: (c, s) => _EditRoute(),
      ),
```
Add this widget next to `_SubscribeRoute` (same file):
```dart
/// Resolves the owner's current court, then shows the edit screen.
class _EditRoute extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(ownerCourtProvider);
    return courtAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          const Scaffold(body: Center(child: Text('Could not load court.'))),
      data: (court) {
        if (court == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/manage');
          });
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return CourtEditScreen(
          court: court,
          onSaved: () {
            ref.invalidate(ownerCourtProvider);
            context.go('/manage');
          },
        );
      },
    );
  }
}
```
In `app/lib/features/owner/management_screen.dart`, pass `onEdit` on both `OwnerDashboard` usages — change each `return OwnerDashboard(court: court, onSubscribe: ...)` to include `onEdit: () => context.go('/manage/edit'),`. For the active branch:
```dart
          return OwnerDashboard(
            court: court,
            onEdit: () => context.go('/manage/edit'),
            onSubscribe: () {},
          );
```
and for the suspended branch:
```dart
            return OwnerDashboard(
              court: court,
              onEdit: () => context.go('/manage/edit'),
              onSubscribe: () => context.go('/manage/subscribe'),
            );
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_edit_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Analyze + full suite**

Run: `/c/Users/Eli/flutter/bin/flutter analyze && /c/Users/Eli/flutter/bin/flutter test`
Expected: analyze clean; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/features/owner/court_edit_screen.dart lib/features/owner/owner_dashboard_screen.dart lib/features/owner/management_screen.dart lib/app/router.dart test/court_edit_screen_test.dart
git commit -m "feat(owner): edit-court screen (name/fee/address)"
```

---

## Self-Review

**Spec coverage:**
- Role/mode model → Tasks 2 (mode), 3 (capabilities), 8 (dropdown). ✓
- Two shells + persisted mode + redirect/guards → Task 9. ✓
- First-time host entry → Task 9 step 8. ✓
- Onboarding (name/fee/#courts/address, PHP) → Task 5. ✓
- Subscription (monthly/yearly, mock pay) → Task 6. ✓
- Dashboard (empty states, suspended banner) → Task 7. ✓
- `create_court` + `subscribe_court` RPCs + visibility policy → Task 1. ✓
- Edit-court action → Task 10 (edit screen + dashboard button + `/manage/edit` route). ✓
- Tests (mode persistence, capabilities, onboarding, subscription, dashboard, launch) → Tasks 2,3,5,6,7,9. ✓
- `shared_preferences` dependency → Task 2. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. The one forward-reference (`capabilitiesProviderRefresh`) is explicitly corrected in Task 9 Step 5.

**Type consistency:** `CourtRepository` method signatures match across Tasks 4–10; `Court`/`SubscriptionPlan`/`AppMode`/`Capabilities` names consistent; `launchTarget`, `ownerCourtProvider`, `courtRepositoryProvider`, `appModeProvider`, `capabilitiesProvider` used consistently. `OwnerDashboard.onEdit` is optional, so Task 7's test (no `onEdit`) stays valid while Task 10 adds the button.

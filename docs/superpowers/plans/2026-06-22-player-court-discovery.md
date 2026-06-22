# Player Court Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players browse a searchable list of active courts and open a court detail page showing venue info plus live court availability.

**Architecture:** Extract the shared `Court` model to `data/court.dart`, add a player-scoped `DiscoveryRepository` + Riverpod providers, and two screens (`CourtListScreen` at `/play`, `CourtDetailScreen` pushed full-screen at `/play/court/:id`). Pure client-side feature against existing tables — no migration.

**Tech Stack:** Flutter 3.44 / Dart 3.12, Riverpod (FutureProvider / family), go_router (StatefulShellRoute + root-navigator push), Supabase Postgres reads.

## Global Constraints

- Flutter binary is not on PATH; run it as `/c/Users/Eli/flutter/bin/flutter` from the `app/` directory.
- All literal colors come from the theme; the only allowed hard-coded color is `kBrandGreen` (filled CTAs / selected). Rounded corners use `kRadius` (both from `app/lib/app/theme.dart`).
- Currency display goes through `formatFee(cents, currency)` — never hard-code a currency symbol.
- Availability: `totalCount` = slots with status `open` or `occupied` (excludes `closed`); `openCount` = slots with status `open`.
- Branch root screens under a shell (e.g. `CourtListScreen`) are body-only (no `Scaffold`/`AppBar`); the shell supplies those. Full-screen pushed screens (e.g. `CourtDetailScreen`) own their `Scaffold`/`AppBar`.
- Tests use `flutter_test` with `ProviderScope` overrides and hand-written fakes (mirror `app/test/subscription_screen_test.dart`).
- Package import prefix is `package:dinksync/...`.

---

## File Structure

- `app/lib/data/court.dart` *(new)* — `Court` model (moved) + `formatFee` helper.
- `app/lib/features/owner/court_repository.dart` *(modify)* — remove `Court`, import + re-export it from `data/court.dart`.
- `app/lib/features/discovery/discovery_repository.dart` *(new)* — `CourtAvailability`, `DiscoveryRepository` (abstract + Supabase impl), providers.
- `app/lib/features/discovery/court_list_screen.dart` *(new)* — `/play` body.
- `app/lib/features/discovery/court_detail_screen.dart` *(new)* — detail page.
- `app/lib/app/router.dart` *(modify)* — `/play` → `CourtListScreen`; add `/play/court/:id`.
- `app/test/court_model_test.dart` *(new)* — `formatFee` + `CourtAvailability`/`fromMap` checks.
- `app/test/discovery_repository_test.dart` *(new)* — repo availability math via injected rows.
- `app/test/court_list_screen_test.dart` *(new)*.
- `app/test/court_detail_screen_test.dart` *(new)*.

---

### Task 1: Extract shared `Court` model + `formatFee`

Move `Court` to a shared file so the player module does not import the owner module, and add the fee formatter.

**Files:**
- Create: `app/lib/data/court.dart`
- Modify: `app/lib/features/owner/court_repository.dart`
- Test: `app/test/court_model_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class Court { const Court({required String id, required String name, required String status, required int entryFeeCents, required String currency, required int numCourts, String? address}); bool get isActive; factory Court.fromMap(Map<String, dynamic>); }`
  - `String formatFee(int cents, String currency)`
  - `court_repository.dart` re-exports `Court` (so `import '.../court_repository.dart'` still resolves `Court`).

- [ ] **Step 1: Write the failing test**

Create `app/test/court_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/data/court.dart';

void main() {
  group('formatFee', () {
    test('PHP uses peso symbol', () => expect(formatFee(15000, 'PHP'), '₱150'));
    test('USD uses dollar symbol', () => expect(formatFee(1000, 'USD'), r'$10'));
    test('unknown currency falls back to code prefix',
        () => expect(formatFee(15000, 'EUR'), 'EUR 150'));
  });

  group('Court.fromMap', () {
    test('parses a row', () {
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
      expect(c.isActive, true);
      expect(c.address, 'Cebu City');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_model_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:dinksync/data/court.dart'`.

- [ ] **Step 3: Create the shared model file**

Create `app/lib/data/court.dart`:

```dart
/// A court venue. Shared by the owner (management) and discovery (player)
/// features, so it lives in `data/` rather than inside either feature.
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

/// Formats a minor-unit amount with a currency symbol. Known symbols map
/// explicitly (PHP -> ₱, USD -> $); anything else falls back to the 3-letter
/// code as a prefix (e.g. "EUR 150").
String formatFee(int cents, String currency) {
  const symbols = {'PHP': '₱', 'USD': r'$'};
  final symbol = symbols[currency];
  final major = (cents / 100).toStringAsFixed(0);
  return symbol != null ? '$symbol$major' : '$currency $major';
}
```

- [ ] **Step 4: Remove `Court` from the owner repo and re-export it**

In `app/lib/features/owner/court_repository.dart`, delete the entire `Court`
class (the doc comment + `class Court { ... }`, currently lines 6–37) and add,
directly under the existing imports at the top of the file:

```dart
import '../../data/court.dart';

// Court moved to data/court.dart; re-exported so existing importers
// (`import '.../court_repository.dart'`) keep resolving `Court`.
export '../../data/court.dart' show Court;
```

Leave `SubscriptionPlan`, `planPriceCents`, `planName`, `parseAmountToMinor`,
`CourtRepository`, `SupabaseCourtRepository`, and the providers unchanged.

- [ ] **Step 5: Run tests to verify they pass**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_model_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Verify nothing else broke**

Run: `/c/Users/Eli/flutter/bin/flutter analyze`
Expected: `No issues found!` (owner screens still see `Court` via the re-export).

Run: `/c/Users/Eli/flutter/bin/flutter test`
Expected: all existing tests still PASS.

- [ ] **Step 7: Commit**

```bash
git add app/lib/data/court.dart app/lib/features/owner/court_repository.dart app/test/court_model_test.dart
git commit -m "refactor(court): extract shared Court model + formatFee to data/"
```

---

### Task 2: `DiscoveryRepository` + `CourtAvailability` + providers

The player-scoped data layer: list active courts, fetch one by id, compute slot availability.

**Files:**
- Create: `app/lib/features/discovery/discovery_repository.dart`
- Test: `app/test/discovery_repository_test.dart`

**Interfaces:**
- Consumes: `Court` from `package:dinksync/data/court.dart`; `supabase` from `package:dinksync/data/supabase_client.dart`.
- Produces:
  - `class CourtAvailability { const CourtAvailability({required int openCount, required int totalCount}); final int openCount; final int totalCount; factory CourtAvailability.fromSlotRows(List<Map<String, dynamic>> rows); }`
  - `abstract class DiscoveryRepository { Future<List<Court>> listActiveCourts(); Future<Court?> courtById(String id); Future<CourtAvailability> availability(String courtId); }`
  - `final discoveryRepositoryProvider = Provider<DiscoveryRepository>(...)`
  - `final activeCourtsProvider = FutureProvider<List<Court>>(...)`
  - `final courtByIdProvider = FutureProvider.family<Court?, String>(...)`
  - `final courtAvailabilityProvider = FutureProvider.family<CourtAvailability, String>(...)`

- [ ] **Step 1: Write the failing test**

Create `app/test/discovery_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/discovery/discovery_repository.dart';

void main() {
  group('CourtAvailability.fromSlotRows', () {
    test('counts open and in-service (excludes closed)', () {
      final a = CourtAvailability.fromSlotRows(const [
        {'status': 'open'},
        {'status': 'open'},
        {'status': 'occupied'},
        {'status': 'closed'},
      ]);
      expect(a.openCount, 2);
      expect(a.totalCount, 3);
    });

    test('no slots -> zeroes', () {
      final a = CourtAvailability.fromSlotRows(const []);
      expect(a.openCount, 0);
      expect(a.totalCount, 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/discovery_repository_test.dart`
Expected: FAIL — URI `package:dinksync/features/discovery/discovery_repository.dart` doesn't exist.

- [ ] **Step 3: Write the repository**

Create `app/lib/features/discovery/discovery_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/court.dart';
import '../../data/supabase_client.dart';

/// Live court availability for a venue, derived from its `court_slots`.
class CourtAvailability {
  const CourtAvailability({required this.openCount, required this.totalCount});

  final int openCount; // slots with status 'open'
  final int totalCount; // in-service slots: 'open' or 'occupied'

  /// Builds availability from `court_slots` rows (each having a `status`).
  /// `closed` slots are out of service and excluded from [totalCount].
  factory CourtAvailability.fromSlotRows(List<Map<String, dynamic>> rows) {
    var open = 0;
    var total = 0;
    for (final r in rows) {
      final status = r['status'] as String?;
      if (status == 'open') {
        open++;
        total++;
      } else if (status == 'occupied') {
        total++;
      }
    }
    return CourtAvailability(openCount: open, totalCount: total);
  }
}

/// Player-facing reads of public court data.
abstract class DiscoveryRepository {
  Future<List<Court>> listActiveCourts();
  Future<Court?> courtById(String id);
  Future<CourtAvailability> availability(String courtId);
}

class SupabaseDiscoveryRepository implements DiscoveryRepository {
  SupabaseDiscoveryRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<List<Court>> listActiveCourts() async {
    final rows = await _db
        .from('courts')
        .select()
        .eq('status', 'active')
        .order('name');
    return (rows as List)
        .map((r) => Court.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Court?> courtById(String id) async {
    final rows = await _db.from('courts').select().eq('id', id).limit(1);
    return rows.isEmpty ? null : Court.fromMap(rows.first);
  }

  @override
  Future<CourtAvailability> availability(String courtId) async {
    final rows =
        await _db.from('court_slots').select('status').eq('court_id', courtId);
    return CourtAvailability.fromSlotRows(
        (rows as List).cast<Map<String, dynamic>>());
  }
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => SupabaseDiscoveryRepository(supabase),
);

/// All active courts, fetched once. Name search filters this list client-side.
final activeCourtsProvider = FutureProvider<List<Court>>(
  (ref) => ref.watch(discoveryRepositoryProvider).listActiveCourts(),
);

final courtByIdProvider = FutureProvider.family<Court?, String>(
  (ref, id) => ref.watch(discoveryRepositoryProvider).courtById(id),
);

final courtAvailabilityProvider =
    FutureProvider.family<CourtAvailability, String>(
  (ref, id) => ref.watch(discoveryRepositoryProvider).availability(id),
);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/c/Users/Eli/flutter/bin/flutter test test/discovery_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Verify analyze is clean**

Run: `/c/Users/Eli/flutter/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/discovery/discovery_repository.dart app/test/discovery_repository_test.dart
git commit -m "feat(discovery): court discovery repository + availability + providers"
```

---

### Task 3: `CourtListScreen` (`/play` body)

Searchable list of active courts; replaces the "Find a game" placeholder.

**Files:**
- Create: `app/lib/features/discovery/court_list_screen.dart`
- Test: `app/test/court_list_screen_test.dart`

**Interfaces:**
- Consumes: `activeCourtsProvider`, `discoveryRepositoryProvider` (test overrides), `Court`, `formatFee`.
- Produces: `class CourtListScreen extends ConsumerStatefulWidget { const CourtListScreen({super.key}); }` (body-only — no `Scaffold`). Navigates via `context.push('/play/court/<id>')`.

- [ ] **Step 1: Write the failing test**

Create `app/test/court_list_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/discovery/court_list_screen.dart';
import 'package:dinksync/features/discovery/discovery_repository.dart';

class _FakeRepo implements DiscoveryRepository {
  _FakeRepo(this.courts);
  final List<Court> courts;

  @override
  Future<List<Court>> listActiveCourts() async => courts;
  @override
  Future<Court?> courtById(String id) async {
    for (final c in courts) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<CourtAvailability> availability(String courtId) async =>
      const CourtAvailability(openCount: 0, totalCount: 0);
}

const _courts = [
  Court(
      id: 'c1',
      name: 'Cebu Dinks',
      status: 'active',
      entryFeeCents: 15000,
      currency: 'PHP',
      numCourts: 3,
      address: 'Cebu City'),
  Court(
      id: 'c2',
      name: 'Manila Smash',
      status: 'active',
      entryFeeCents: 0,
      currency: 'PHP',
      numCourts: 1),
];

Widget _host(List<Court> courts) => ProviderScope(
      overrides: [
        discoveryRepositoryProvider.overrideWithValue(_FakeRepo(courts)),
      ],
      child: const MaterialApp(home: Scaffold(body: CourtListScreen())),
    );

void main() {
  testWidgets('lists courts with name and fee', (tester) async {
    await tester.pumpWidget(_host(_courts));
    await tester.pumpAndSettle();

    expect(find.text('Cebu Dinks'), findsOneWidget);
    expect(find.text('Manila Smash'), findsOneWidget);
    expect(find.text('₱150'), findsOneWidget);
  });

  testWidgets('search filters by name (case-insensitive)', (tester) async {
    await tester.pumpWidget(_host(_courts));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'manila');
    await tester.pump();

    expect(find.text('Manila Smash'), findsOneWidget);
    expect(find.text('Cebu Dinks'), findsNothing);
  });

  testWidgets('no courts at all shows empty message', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();

    expect(find.text('No courts available yet.'), findsOneWidget);
  });

  testWidgets('search with no match shows no-match message', (tester) async {
    await tester.pumpWidget(_host(_courts));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.textContaining('No courts match'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_list_screen_test.dart`
Expected: FAIL — URI `.../court_list_screen.dart` doesn't exist.

- [ ] **Step 3: Write the screen**

Create `app/lib/features/discovery/court_list_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/court.dart';
import 'discovery_repository.dart';

/// Body of the Play shell's first tab: a searchable list of active courts.
/// Body-only — the Play shell supplies the app bar and bottom nav.
class CourtListScreen extends ConsumerStatefulWidget {
  const CourtListScreen({super.key});

  @override
  ConsumerState<CourtListScreen> createState() => _CourtListScreenState();
}

class _CourtListScreenState extends ConsumerState<CourtListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final courtsAsync = ref.watch(activeCourtsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search courts by name',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: courtsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _ErrorRetry(
              onRetry: () => ref.invalidate(activeCourtsProvider),
            ),
            data: (courts) {
              if (courts.isEmpty) {
                return const _Empty(message: 'No courts available yet.');
              }
              final q = _query.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? courts
                  : courts
                      .where((c) => c.name.toLowerCase().contains(q))
                      .toList();
              if (filtered.isEmpty) {
                return _Empty(message: 'No courts match "${_query.trim()}".');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _CourtCard(court: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court});

  final Court court;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: () => context.push('/play/court/${court.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(court.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      court.address ?? 'Address not set',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatFee(court.entryFeeCents, court.currency),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
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
          const Text('Could not load courts.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_list_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Verify analyze is clean**

Run: `/c/Users/Eli/flutter/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/discovery/court_list_screen.dart app/test/court_list_screen_test.dart
git commit -m "feat(discovery): searchable court list screen"
```

---

### Task 4: `CourtDetailScreen` (full-screen pushed page)

Venue info + live availability + disabled "Join queue — coming soon" CTA.

**Files:**
- Create: `app/lib/features/discovery/court_detail_screen.dart`
- Test: `app/test/court_detail_screen_test.dart`

**Interfaces:**
- Consumes: `courtByIdProvider`, `courtAvailabilityProvider`, `discoveryRepositoryProvider` (test overrides), `Court`, `formatFee`, `CourtAvailability`.
- Produces: `class CourtDetailScreen extends ConsumerWidget { const CourtDetailScreen({super.key, required String courtId}); }` (owns its `Scaffold`/`AppBar`).

- [ ] **Step 1: Write the failing test**

Create `app/test/court_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/discovery/court_detail_screen.dart';
import 'package:dinksync/features/discovery/discovery_repository.dart';

class _FakeRepo implements DiscoveryRepository {
  _FakeRepo(this.court, this.avail);
  final Court court;
  final CourtAvailability avail;

  @override
  Future<List<Court>> listActiveCourts() async => [court];
  @override
  Future<Court?> courtById(String id) async => id == court.id ? court : null;
  @override
  Future<CourtAvailability> availability(String courtId) async => avail;
}

const _court = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 15000,
  currency: 'PHP',
  numCourts: 3,
  address: 'Cebu City',
);

Widget _host(DiscoveryRepository repo) => ProviderScope(
      overrides: [discoveryRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: CourtDetailScreen(courtId: 'c1')),
    );

void main() {
  testWidgets('renders venue info, availability, and disabled CTA',
      (tester) async {
    final repo = _FakeRepo(
        _court, const CourtAvailability(openCount: 2, totalCount: 3));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('Cebu Dinks'), findsWidgets); // app bar + body
    expect(find.text('Cebu City'), findsOneWidget);
    expect(find.text('Entry fee ₱150'), findsOneWidget);
    expect(find.text('2 of 3 courts open'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull); // disabled
    expect(find.text('Join queue — coming soon'), findsOneWidget);
  });

  testWidgets('no in-service courts shows "No courts in service"',
      (tester) async {
    final repo = _FakeRepo(
        _court, const CourtAvailability(openCount: 0, totalCount: 0));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('No courts in service'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_detail_screen_test.dart`
Expected: FAIL — URI `.../court_detail_screen.dart` doesn't exist.

- [ ] **Step 3: Write the screen**

Create `app/lib/features/discovery/court_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/court.dart';
import 'discovery_repository.dart';

/// Full-screen court detail: venue info + live availability + a placeholder
/// join CTA. Pushed on the root navigator, so it owns its Scaffold/AppBar.
class CourtDetailScreen extends ConsumerWidget {
  const CourtDetailScreen({super.key, required this.courtId});

  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(courtByIdProvider(courtId));
    return Scaffold(
      appBar: AppBar(
        title: Text(courtAsync.valueOrNull?.name ?? 'Court'),
      ),
      body: courtAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load this court.')),
        data: (court) {
          if (court == null) {
            return const Center(child: Text('Could not load this court.'));
          }
          return _Body(courtId: courtId, court: court);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.courtId, required this.court});

  final String courtId;
  final Court court;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final availAsync = ref.watch(courtAvailabilityProvider(courtId));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(court.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.location_on_outlined,
          text: court.address ?? 'Address not set',
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.payments_outlined,
          text: 'Entry fee ${formatFee(court.entryFeeCents, court.currency)}',
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.grid_view_outlined,
          text: '${court.numCourts} '
              '${court.numCourts == 1 ? 'court' : 'courts'}',
        ),
        const SizedBox(height: 8),
        availAsync.when(
          loading: () => const _InfoRow(
            icon: Icons.sports_tennis,
            text: 'Checking availability…',
          ),
          error: (_, _) => const _InfoRow(
            icon: Icons.sports_tennis,
            text: 'Availability unavailable',
          ),
          data: (a) => _InfoRow(
            icon: Icons.sports_tennis,
            text: a.totalCount == 0
                ? 'No courts in service'
                : '${a.openCount} of ${a.totalCount} courts open',
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: null, // queueing not built yet
          child: const Text('Join queue — coming soon'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/c/Users/Eli/flutter/bin/flutter test test/court_detail_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Verify analyze is clean**

Run: `/c/Users/Eli/flutter/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/discovery/court_detail_screen.dart app/test/court_detail_screen_test.dart
git commit -m "feat(discovery): court detail screen with live availability"
```

---

### Task 5: Wire screens into the router

Replace the Play placeholder with the list and register the detail route.

**Files:**
- Modify: `app/lib/app/router.dart`

**Interfaces:**
- Consumes: `CourtListScreen`, `CourtDetailScreen`, existing `_rootNavigatorKey`.
- Produces: `/play` builds `CourtListScreen`; `/play/court/:id` pushed full-screen builds `CourtDetailScreen`.

- [ ] **Step 1: Add imports**

In `app/lib/app/router.dart`, add to the import block (with the other feature imports):

```dart
import '../features/discovery/court_list_screen.dart';
import '../features/discovery/court_detail_screen.dart';
```

- [ ] **Step 2: Replace the Play tab placeholder**

Find the first Play branch (currently the `/play` `GoRoute` whose builder is a
`PlaceholderTab(title: 'Find a game', ...)`) and replace that whole `GoRoute`
with:

```dart
GoRoute(path: '/play', builder: (c, s) => const CourtListScreen()),
```

Leave the `/social` and `/profile` branches unchanged.

- [ ] **Step 3: Register the detail route**

In the "Full-screen sub-pages pushed over the shells" group (next to
`/manage/edit`), add:

```dart
GoRoute(
  path: '/play/court/:id',
  parentNavigatorKey: _rootNavigatorKey,
  builder: (c, s) => CourtDetailScreen(courtId: s.pathParameters['id']!),
),
```

- [ ] **Step 4: Verify analyze is clean**

Run: `/c/Users/Eli/flutter/bin/flutter analyze`
Expected: `No issues found!` (the `PlaceholderTab` import may now be unused — if analyze reports it as unused, remove the `placeholder_tab.dart` import only if no other route uses it; the `/social` and `/manage/staff` routes still use `PlaceholderTab`, so the import stays).

- [ ] **Step 5: Run the full test suite**

Run: `/c/Users/Eli/flutter/bin/flutter test`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/app/router.dart
git commit -m "feat(discovery): route /play to court list + /play/court/:id detail"
```

---

## Self-Review

**Spec coverage:**
- Shared `Court` extraction + re-export → Task 1. ✓
- `formatFee` (PHP/USD/fallback) → Task 1. ✓
- `DiscoveryRepository` (list/byId/availability) + providers → Task 2. ✓
- `CourtAvailability` semantics (open vs in-service, closed excluded) → Task 2 (`fromSlotRows`). ✓
- `CourtListScreen` with search + loading/empty/no-match/error states → Task 3. ✓
- `CourtDetailScreen` with info + availability + disabled CTA + graceful availability failure → Task 4. ✓
- Routing (`/play` body, `/play/court/:id` root push) → Task 5. ✓
- Testing (repo + both screens, ProviderScope + fakes) → Tasks 1–4. ✓
- No migration needed → confirmed in spec; no DB task. ✓

**Placeholder scan:** No TBD/TODO/"handle errors"; every code step is complete. The single `onPressed: null` is intentional (disabled CTA), documented inline.

**Type consistency:** `Court` fields and `Court.fromMap` identical between Task 1 and the moved original. `CourtAvailability({openCount, totalCount})` + `fromSlotRows` used identically in Tasks 2/3/4. Provider names (`activeCourtsProvider`, `courtByIdProvider`, `courtAvailabilityProvider`, `discoveryRepositoryProvider`) consistent across tasks. `formatFee(int, String)` signature consistent. `CourtListScreen` body-only and `CourtDetailScreen({required courtId})` match the router usage in Task 5.

**Note on Dart lint:** unused-parameter placeholders in error callbacks use `(_, _)` (wildcard) to satisfy the analyzer config used elsewhere in this codebase (see `management_screen.dart` / `subscription_screen.dart`).

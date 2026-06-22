# Game Lobby + Court Booking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `/play` with a game lobby that lets players select a court, see player slots, and book a private court slot on a visual hour-block timeline.

**Architecture:** `LobbyScreen` becomes the `/play` shell body; the court picker and booking screen are full-screen routes pushed over the shell using `parentNavigatorKey: _rootNavigatorKey`. Data flows via a new `BookingRepository` backed by Supabase with two `FutureProvider.family` providers.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12, Riverpod, go_router, Supabase Postgres (migrations + RPC), `flutter test` from `app/` dir.

## Global Constraints

- **No new packages** — no `intl`, no `collection`. Manual weekday array for dates; manual null-guard instead of `firstOrNull`.
- `withValues(alpha:)` — never `withOpacity()`.
- `kBrandGreen = Color(0xFF2E7D32)`, `kRadius = 24.0` (from `app/lib/app/theme.dart`).
- `formatFee(int cents, String currency)` is in `app/lib/data/court.dart` — reuse it.
- Wildcard params `(_, _, _)` are valid in Dart 3.12.
- Shell-tab bodies are **body-only** — no `Scaffold`, no `AppBar`. Full-screen pushed routes own their `Scaffold`.
- Full-screen routes pushed over the shell use `parentNavigatorKey: _rootNavigatorKey`.
- `context.push<Court>('/play/courts')` returns `Future<Court?>` — await in `async` method.
- Test commands run from `app/` directory: `flutter test` or `flutter test test/<file>.dart`.
- Weekday labels: `const _weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];` — index with `date.weekday - 1`.

---

### Task 1: DB Migration — custom bookings

**Files:**
- Create: `supabase/migrations/0010_custom_bookings.sql`

**Interfaces:**
- Produces: `courts.custom_fee_cents` column; `payments.kind` values `'entry'|'subscription'|'custom'`; `custom_bookings` table with RLS; `book_custom_slot(p_court_slot_id, p_starts_at, p_ends_at)` RPC returning `uuid`.

- [ ] **Step 1: Create the migration file**

Create `supabase/migrations/0010_custom_bookings.sql` with the exact content below:

```sql
-- 0010_custom_bookings.sql
-- Adds per-court custom booking fee, extends payments.kind, creates custom_bookings
-- table with RLS, and the book_custom_slot RPC.

-- 1. Per-court custom booking fee (cents per hour). Nullable = feature disabled.
alter table public.courts
  add column custom_fee_cents integer check (custom_fee_cents > 0);

-- 2. Extend payments.kind to include 'custom'.
alter table public.payments
  drop constraint if exists payments_kind_check;
alter table public.payments
  add constraint payments_kind_check
    check (kind in ('entry','subscription','custom'));

-- 3. Custom bookings table.
create table public.custom_bookings (
  id                uuid primary key default gen_random_uuid(),
  court_id          uuid not null references public.courts (id) on delete cascade,
  court_slot_id     uuid not null references public.court_slots (id) on delete cascade,
  booker_profile_id uuid not null references public.profiles (id) on delete cascade,
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  status            text not null default 'confirmed'
                      check (status in ('confirmed','canceled','completed')),
  amount_cents      integer not null check (amount_cents >= 0),
  currency          text    not null check (length(currency) = 3),
  payment_id        uuid    references public.payments (id) on delete set null,
  created_at        timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index custom_bookings_slot_idx
  on public.custom_bookings (court_slot_id, starts_at)
  where status = 'confirmed';

create index custom_bookings_booker_idx
  on public.custom_bookings (booker_profile_id);

alter table public.custom_bookings enable row level security;

-- Players see their own bookings; court members + platform admins see all for their court.
create policy custom_bookings_select on public.custom_bookings for select
  using (
    booker_profile_id = auth.uid()
    or exists (
      select 1 from public.court_members cm
      where cm.court_id = custom_bookings.court_id
        and cm.profile_id = auth.uid()
    )
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.is_platform_admin
    )
  );

-- All writes go through the RPC (security definer).

-- 4. book_custom_slot RPC.
create or replace function public.book_custom_slot(
  p_court_slot_id uuid,
  p_starts_at     timestamptz,
  p_ends_at       timestamptz
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_court         courts%rowtype;
  v_slot          court_slots%rowtype;
  v_payment_id    uuid;
  v_booking_id    uuid;
  v_hours         int;
  v_amount        int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_slot from court_slots where id = p_court_slot_id;
  if not found then
    raise exception 'slot not found';
  end if;
  select * into v_court from courts where id = v_slot.court_id;

  if v_court.custom_fee_cents is null then
    raise exception 'custom_bookings_disabled';
  end if;

  -- Overlap check against confirmed bookings on this slot.
  if exists (
    select 1 from custom_bookings
    where court_slot_id = p_court_slot_id
      and status = 'confirmed'
      and starts_at < p_ends_at
      and ends_at   > p_starts_at
  ) then
    raise exception 'slot_not_available';
  end if;

  v_hours  := extract(epoch from (p_ends_at - p_starts_at))::int / 3600;
  v_amount := v_court.custom_fee_cents * v_hours;

  insert into payments (payer_profile_id, payee_court_id, kind, amount_cents,
                        currency, status, provider)
  values (auth.uid(), v_court.id, 'custom', v_amount,
          v_court.currency, 'paid', 'mock')
  returning id into v_payment_id;

  insert into custom_bookings (court_id, court_slot_id, booker_profile_id,
                               starts_at, ends_at, amount_cents, currency, payment_id)
  values (v_court.id, p_court_slot_id, auth.uid(),
          p_starts_at, p_ends_at, v_amount, v_court.currency, v_payment_id)
  returning id into v_booking_id;

  return v_booking_id;
end;
$$;
```

- [ ] **Step 2: Apply locally**

```bash
supabase db reset
# or, if dev DB is already running:
supabase db push --local
```

Expected: migration applies without errors. `\d public.custom_bookings` shows the table.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0010_custom_bookings.sql
git commit -m "feat(db): custom_bookings table + book_custom_slot RPC (0010)"
```

---

### Task 2: Court model — add `customFeeCents`

**Files:**
- Modify: `app/lib/data/court.dart`
- Test: `app/test/court_repository_test.dart`

**Interfaces:**
- Consumes: existing `Court` class with `id, name, status, entryFeeCents, currency, numCourts, address?, imageUrl?`.
- Produces: `Court.customFeeCents` (`int?`, nullable, mapped from `'custom_fee_cents'`). All existing callers compile unchanged because the field is optional.

- [ ] **Step 1: Write the failing test**

Open `app/test/court_repository_test.dart`. Add this test inside `main()`:

```dart
test('Court.fromMap maps custom_fee_cents', () {
  final c = Court.fromMap({
    'id': 'x1',
    'name': 'Test',
    'status': 'active',
    'entry_fee_cents': 10000,
    'currency': 'PHP',
    'num_courts': 2,
    'address': null,
    'image_url': null,
    'custom_fee_cents': 50000,
  });
  expect(c.customFeeCents, 50000);
});

test('Court.fromMap custom_fee_cents null when absent', () {
  final c = Court.fromMap({
    'id': 'x2',
    'name': 'Test2',
    'status': 'active',
    'entry_fee_cents': 0,
    'currency': 'PHP',
    'num_courts': 1,
    'address': null,
    'image_url': null,
    'custom_fee_cents': null,
  });
  expect(c.customFeeCents, isNull);
});
```

- [ ] **Step 2: Run to verify failure**

```bash
# from app/
flutter test test/court_repository_test.dart
```

Expected: compile error — `customFeeCents` does not exist on `Court`.

- [ ] **Step 3: Add the field to `Court`**

In `app/lib/data/court.dart`, make these changes:

Constructor — add `this.customFeeCents` after `this.imageUrl`:
```dart
const Court({
  required this.id,
  required this.name,
  required this.status,
  required this.entryFeeCents,
  required this.currency,
  required this.numCourts,
  this.address,
  this.imageUrl,
  this.customFeeCents,   // ← add
});
```

Field declaration — add after `imageUrl`:
```dart
final String? imageUrl;
final int? customFeeCents;   // ← add; null = custom bookings disabled
```

`fromMap` — add inside the factory:
```dart
customFeeCents: m['custom_fee_cents'] as int?,   // ← add
```

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/court_repository_test.dart
```

Expected: all tests pass (including the two new ones + existing ones).

- [ ] **Step 5: Full suite green**

```bash
flutter test
```

Expected: all 47+ tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/data/court.dart app/test/court_repository_test.dart
git commit -m "feat(court): add customFeeCents field for private slot booking"
```

---

### Task 3: Booking repository

**Files:**
- Create: `app/lib/features/lobby/booking_repository.dart`
- Create: `app/test/booking_repository_test.dart`

**Interfaces:**
- Consumes: `app/lib/data/supabase_client.dart` (`supabase` getter), `supabase_flutter` `SupabaseClient`.
- Produces (used by Tasks 6 and 7):
  - `class CourtSlot { final String id, label; }`
  - `class CustomBooking { final DateTime startsAt, endsAt; }`
  - `class CourtBookingQuery { final String slotId; final DateTime date; == and hashCode }`
  - `abstract class BookingRepository { Future<List<CourtSlot>> courtSlots(String courtId); Future<List<CustomBooking>> bookingsForSlot(CourtBookingQuery q); Future<void> bookSlot({required String slotId, required DateTime startsAt, required DateTime endsAt}); }`
  - `final bookingRepositoryProvider = Provider<BookingRepository>(...)`
  - `final courtSlotsProvider = FutureProvider.family<List<CourtSlot>, String>(...)`
  - `final courtBookingsProvider = FutureProvider.family<List<CustomBooking>, CourtBookingQuery>(...)`
  - `final currentUserDisplayNameProvider = FutureProvider<String>(...)`

- [ ] **Step 1: Write the failing tests**

Create `app/test/booking_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/lobby/booking_repository.dart';

void main() {
  group('CourtBookingQuery equality', () {
    final day = DateTime(2026, 6, 22);

    test('equal when slotId and date match', () {
      final a = CourtBookingQuery(slotId: 'slot-1', date: day);
      final b = CourtBookingQuery(slotId: 'slot-1', date: day);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when slotId differs', () {
      final a = CourtBookingQuery(slotId: 'slot-1', date: day);
      final b = CourtBookingQuery(slotId: 'slot-2', date: day);
      expect(a, isNot(equals(b)));
    });

    test('not equal when date differs', () {
      final a = CourtBookingQuery(slotId: 'slot-1', date: DateTime(2026, 6, 22));
      final b = CourtBookingQuery(slotId: 'slot-1', date: DateTime(2026, 6, 23));
      expect(a, isNot(equals(b)));
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/booking_repository_test.dart
```

Expected: compile error — `booking_repository.dart` does not exist.

- [ ] **Step 3: Create the repository**

Create `app/lib/features/lobby/booking_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

class CourtSlot {
  const CourtSlot({required this.id, required this.label});
  final String id;
  final String label;
}

class CustomBooking {
  const CustomBooking({required this.startsAt, required this.endsAt});
  final DateTime startsAt;
  final DateTime endsAt;
}

/// Used as a Riverpod family arg — must implement == and hashCode.
class CourtBookingQuery {
  const CourtBookingQuery({required this.slotId, required this.date});
  final String slotId;
  final DateTime date; // date-only (year/month/day); time part ignored

  @override
  bool operator ==(Object other) =>
      other is CourtBookingQuery &&
      slotId == other.slotId &&
      date == other.date;

  @override
  int get hashCode => Object.hash(slotId, date);
}

abstract class BookingRepository {
  Future<List<CourtSlot>> courtSlots(String courtId);
  Future<List<CustomBooking>> bookingsForSlot(CourtBookingQuery query);
  Future<void> bookSlot({
    required String slotId,
    required DateTime startsAt,
    required DateTime endsAt,
  });
}

class SupabaseBookingRepository implements BookingRepository {
  const SupabaseBookingRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<List<CourtSlot>> courtSlots(String courtId) async {
    final rows = await _db
        .from('court_slots')
        .select('id, label')
        .eq('court_id', courtId)
        .order('label');
    return rows
        .map((r) => CourtSlot(id: r['id'] as String, label: r['label'] as String))
        .toList();
  }

  @override
  Future<List<CustomBooking>> bookingsForSlot(CourtBookingQuery query) async {
    final d = query.date;
    final nextDay = d.add(const Duration(days: 1));
    final rows = await _db
        .from('custom_bookings')
        .select('starts_at, ends_at')
        .eq('court_slot_id', query.slotId)
        .eq('status', 'confirmed')
        .gte('starts_at', d.toUtc().toIso8601String())
        .lt('starts_at', nextDay.toUtc().toIso8601String());
    return rows
        .map((r) => CustomBooking(
              startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
              endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
            ))
        .toList();
  }

  @override
  Future<void> bookSlot({
    required String slotId,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    await _db.rpc('book_custom_slot', params: {
      'p_court_slot_id': slotId,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
    });
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => SupabaseBookingRepository(supabase),
);

final courtSlotsProvider =
    FutureProvider.family<List<CourtSlot>, String>((ref, courtId) {
  return ref.watch(bookingRepositoryProvider).courtSlots(courtId);
});

final courtBookingsProvider =
    FutureProvider.family<List<CustomBooking>, CourtBookingQuery>((ref, query) {
  return ref.watch(bookingRepositoryProvider).bookingsForSlot(query);
});

final currentUserDisplayNameProvider = FutureProvider<String>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return 'Player';
  final rows = await supabase
      .from('profiles')
      .select('display_name')
      .eq('id', uid)
      .limit(1);
  if (rows.isEmpty) return 'Player';
  return (rows.first['display_name'] as String?) ?? 'Player';
});
```

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/booking_repository_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 5: Full suite green**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/lobby/booking_repository.dart app/test/booking_repository_test.dart
git commit -m "feat(lobby): BookingRepository, providers, CourtBookingQuery"
```

---

### Task 4: CourtListScreen — picker mode

**Files:**
- Modify: `app/lib/features/discovery/court_list_screen.dart`
- Modify: `app/test/court_list_screen_test.dart`

**Interfaces:**
- Consumes: existing `CourtListScreen` (body-only `ConsumerStatefulWidget`).
- Produces: `CourtListScreen({this.onSelect})` — when `onSelect != null`, card tap calls `onSelect!(court)` instead of pushing to detail; an info `IconButton` appears in the image top-right corner and pushes to detail.

- [ ] **Step 1: Write the failing picker-mode tests**

Add these tests to `app/test/court_list_screen_test.dart`. Add the counter helper at the top of `main()`:

```dart
// Add to the existing _courts const and _host helper at the top of the file.
// The existing _courts and _host stay unchanged.

// New helper for picker mode:
Widget _pickerHost(List<Court> courts, void Function(Court) onSelect) =>
    ProviderScope(
      overrides: [
        discoveryRepositoryProvider.overrideWithValue(_FakeRepo(courts)),
      ],
      child: MaterialApp(
        home: Scaffold(body: CourtListScreen(onSelect: onSelect)),
      ),
    );
```

Then add these tests inside `main()`:

```dart
testWidgets('picker mode: tapping card calls onSelect, not navigation',
    (tester) async {
  Court? selected;
  await tester.pumpWidget(_pickerHost(_courts, (c) => selected = c));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Cebu Dinks'));
  await tester.pump();

  expect(selected?.id, 'c1');
});

testWidgets('picker mode: info button is shown on each card', (tester) async {
  await tester.pumpWidget(_pickerHost(_courts, (_) {}));
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
});

testWidgets('normal mode: info button is NOT shown', (tester) async {
  await tester.pumpWidget(_host(_courts));
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.info_outline), findsNothing);
});
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/court_list_screen_test.dart
```

Expected: compile error — `CourtListScreen` has no `onSelect` parameter.

- [ ] **Step 3: Update `CourtListScreen`**

In `app/lib/features/discovery/court_list_screen.dart`, make the following changes:

**Widget declaration** — add `onSelect`:
```dart
class CourtListScreen extends ConsumerStatefulWidget {
  const CourtListScreen({super.key, this.onSelect});
  final void Function(Court court)? onSelect;
```

**`_CourtListScreenState`** — access `onSelect` from `widget.onSelect`. Update the `itemBuilder` call:
```dart
itemBuilder: (context, i) =>
    _CourtCard(court: filtered[i], onSelect: widget.onSelect),
```

**`_CourtCard`** — add `onSelect` param and picker-mode rendering:
```dart
class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court, this.onSelect});

  final Court court;
  final void Function(Court)? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(kRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect != null
            ? () => onSelect!(court)
            : () => context.push('/play/court/${court.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _CourtImage(imageUrl: court.imageUrl),
                ),
                if (onSelect != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(100),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(100),
                        onTap: () => context.push('/play/court/${court.id}'),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.info_outline,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(court.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          court.address ?? 'Address not set',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatFee(court.entryFeeCents, court.currency),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/court_list_screen_test.dart
```

Expected: all 7 tests pass (4 existing + 3 new).

- [ ] **Step 5: Full suite green**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/discovery/court_list_screen.dart app/test/court_list_screen_test.dart
git commit -m "feat(discovery): CourtListScreen picker mode with onSelect + info button"
```

---

### Task 5: CourtPickerScreen

**Files:**
- Create: `app/lib/features/discovery/court_picker_screen.dart`

**Interfaces:**
- Consumes: `CourtListScreen({onSelect})` from Task 4; `Court` from `app/lib/data/court.dart`; `context.pop(court)`.
- Produces: `class CourtPickerScreen extends StatelessWidget` — full-screen `Scaffold` with AppBar `'Select a court'`, body is `CourtListScreen(onSelect: (court) => context.pop(court))`. No test file (behaviour fully covered by Task 4's picker-mode tests).

- [ ] **Step 1: Create the file**

Create `app/lib/features/discovery/court_picker_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/court.dart';
import 'court_list_screen.dart';

class CourtPickerScreen extends StatelessWidget {
  const CourtPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select a court')),
      body: CourtListScreen(
        onSelect: (Court court) => context.pop(court),
      ),
    );
  }
}
```

- [ ] **Step 2: Compile check**

```bash
flutter analyze lib/features/discovery/court_picker_screen.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/discovery/court_picker_screen.dart
git commit -m "feat(discovery): CourtPickerScreen wrapper for picker mode"
```

---

### Task 6: LobbyScreen

**Files:**
- Create: `app/lib/features/lobby/lobby_screen.dart`
- Create: `app/test/lobby_screen_test.dart`

**Interfaces:**
- Consumes:
  - `currentUserDisplayNameProvider` from `booking_repository.dart` (Task 3)
  - `Court` from `app/lib/data/court.dart` (Task 2 — `customFeeCents` field)
  - `kBrandGreen`, `kRadius` from `app/lib/app/theme.dart`
  - `context.push<Court>('/play/courts')` → returns `Future<Court?>`
  - `context.push('/play/custom', extra: court)` — navigates to booking
- Produces: `class LobbyScreen extends ConsumerStatefulWidget` — body-only (no Scaffold/AppBar).

- [ ] **Step 1: Write the failing tests**

Create `app/test/lobby_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/lobby/booking_repository.dart';
import 'package:dinksync/features/lobby/lobby_screen.dart';

const _courtNoFee = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 15000,
  currency: 'PHP',
  numCourts: 2,
);

const _courtWithFee = Court(
  id: 'c2',
  name: 'Manila Smash',
  status: 'active',
  entryFeeCents: 10000,
  currency: 'PHP',
  numCourts: 1,
  customFeeCents: 50000,
);

Widget _host({Court? preselected}) => ProviderScope(
      overrides: [
        currentUserDisplayNameProvider
            .overrideWith((ref) async => 'Test Player'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LobbyScreen(initialCourt: preselected),
        ),
      ),
    );

void main() {
  testWidgets('shows "Select a court" placeholder when no court selected',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('Select a court'), findsOneWidget);
  });

  testWidgets('"Book a Court" disabled when no court selected', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('"Book a Court" disabled when court has no customFeeCents',
      (tester) async {
    await tester.pumpWidget(_host(preselected: _courtNoFee));
    await tester.pumpAndSettle();

    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('"Book a Court" enabled when court has customFeeCents',
      (tester) async {
    await tester.pumpWidget(_host(preselected: _courtWithFee));
    await tester.pumpAndSettle();

    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('shows selected court name in selector', (tester) async {
    await tester.pumpWidget(_host(preselected: _courtWithFee));
    await tester.pumpAndSettle();
    expect(find.text('Manila Smash'), findsOneWidget);
  });

  testWidgets('shows display name in You slot', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('Test Player'), findsOneWidget);
  });

  testWidgets('"Find Match" button is always disabled', (tester) async {
    await tester.pumpWidget(_host(preselected: _courtWithFee));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/lobby_screen_test.dart
```

Expected: compile error — `LobbyScreen` does not exist.

- [ ] **Step 3: Create `LobbyScreen`**

Create `app/lib/features/lobby/lobby_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/court.dart';
import 'booking_repository.dart';

/// Body of the Play shell's first tab: the game lobby.
/// Body-only — PlayShell supplies the AppBar and floating nav.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, this.initialCourt});
  final Court? initialCourt;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  Court? _selectedCourt;

  @override
  void initState() {
    super.initState();
    _selectedCourt = widget.initialCourt;
  }

  Future<void> _pickCourt() async {
    final court = await context.push<Court>('/play/courts');
    if (court != null && mounted) setState(() => _selectedCourt = court);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nameAsync = ref.watch(currentUserDisplayNameProvider);
    final displayName = nameAsync.valueOrNull ?? 'Player';
    final canBook =
        _selectedCourt != null && _selectedCourt!.customFeeCents != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Court selector
          Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(kRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(kRadius),
              onTap: _pickCourt,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.stadium_outlined,
                      color: _selectedCourt != null
                          ? kBrandGreen
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedCourt?.name ?? 'Select a court',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _selectedCourt != null
                              ? null
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Player slots
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PlayerSlot(displayName: displayName)),
                const SizedBox(width: 12),
                const Expanded(child: _PartnerSlot()),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Action row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: null,
                  child: const Text('Find Match'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: canBook
                      ? () => context.push('/play/custom',
                          extra: _selectedCourt)
                      : null,
                  child: const Text('Book a Court'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerSlot extends StatelessWidget {
  const _PlayerSlot({required this.displayName});
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primary.withValues(alpha: 0.1),
            child: Text(
              initial,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: kBrandGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            displayName,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'You',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PartnerSlot extends StatelessWidget {
  const _PartnerSlot();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: scheme.outlineVariant,
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_add_outlined,
              size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(
            'Invite partner',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Coming soon',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/lobby_screen_test.dart
```

Expected: 7 tests pass.

- [ ] **Step 5: Full suite green**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/lobby/lobby_screen.dart app/test/lobby_screen_test.dart
git commit -m "feat(lobby): LobbyScreen with court selector, player slots, action row"
```

---

### Task 7: CourtBookingScreen

**Files:**
- Create: `app/lib/features/lobby/court_booking_screen.dart`
- Create: `app/test/court_booking_screen_test.dart`

**Interfaces:**
- Consumes:
  - `bookingRepositoryProvider` (Task 3)
  - `courtSlotsProvider` (Task 3) — `FutureProvider.family<List<CourtSlot>, String>`
  - `courtBookingsProvider` (Task 3) — `FutureProvider.family<List<CustomBooking>, CourtBookingQuery>`
  - `CourtSlot`, `CustomBooking`, `CourtBookingQuery` (Task 3)
  - `Court` with `customFeeCents`, `currency` (Task 2)
  - `formatFee(int cents, String currency)` from `app/lib/data/court.dart`
  - `kBrandGreen`, `kRadius` from theme
- Produces: `class CourtBookingScreen extends ConsumerStatefulWidget { const CourtBookingScreen({super.key, required this.court}); final Court court; }`

- [ ] **Step 1: Write the failing tests**

Create `app/test/court_booking_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/lobby/booking_repository.dart';
import 'package:dinksync/features/lobby/court_booking_screen.dart';

const _court = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 15000,
  currency: 'PHP',
  numCourts: 1,
  customFeeCents: 50000,
);

const _slot = CourtSlot(id: 'slot-1', label: 'Court 1');

class _FakeBookingRepo implements BookingRepository {
  _FakeBookingRepo({this.slots = const [], this.bookings = const []});
  final List<CourtSlot> slots;
  final List<CustomBooking> bookings;

  @override
  Future<List<CourtSlot>> courtSlots(String courtId) async => slots;

  @override
  Future<List<CustomBooking>> bookingsForSlot(CourtBookingQuery query) async =>
      bookings;

  @override
  Future<void> bookSlot({
    required String slotId,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {}
}

Widget _host({List<CustomBooking> bookings = const []}) => ProviderScope(
      overrides: [
        bookingRepositoryProvider.overrideWithValue(
          _FakeBookingRepo(slots: const [_slot], bookings: bookings),
        ),
      ],
      child: const MaterialApp(
        home: CourtBookingScreen(court: _court),
      ),
    );

void main() {
  testWidgets('day strip shows today label', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final todayLabel = '${weekdays[now.weekday - 1]} ${now.day}';
    expect(find.text(todayLabel), findsOneWidget);
  });

  testWidgets('Confirm booking button is disabled with no selection',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('tapping an available block selects start + end',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('08:00'));
    await tester.pump();

    expect(find.textContaining('08:00–09:00'), findsOneWidget);
  });

  testWidgets('tapping second block extends range', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('08:00'));
    await tester.pump();
    await tester.tap(find.text('10:00'));
    await tester.pump();

    expect(find.textContaining('08:00–11:00'), findsOneWidget);
  });

  testWidgets('summary shows fee for selected range', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('08:00'));
    await tester.pump();
    await tester.tap(find.text('10:00'));
    await tester.pump();

    // 3 hours × ₱500 = ₱1500
    expect(find.textContaining('₱1500'), findsOneWidget);
  });

  testWidgets('booked block shows Booked label', (tester) async {
    final now = DateTime.now();
    final booking = CustomBooking(
      startsAt: DateTime(now.year, now.month, now.day, 10),
      endsAt: DateTime(now.year, now.month, now.day, 11),
    );
    await tester.pumpWidget(_host(bookings: [booking]));
    await tester.pumpAndSettle();

    expect(find.text('Booked'), findsOneWidget);
  });

  testWidgets('Confirm button enabled after selection', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('09:00'));
    await tester.pump();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/court_booking_screen_test.dart
```

Expected: compile error — `CourtBookingScreen` does not exist.

- [ ] **Step 3: Create `CourtBookingScreen`**

Create `app/lib/features/lobby/court_booking_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/court.dart';
import 'booking_repository.dart';

class CourtBookingScreen extends ConsumerStatefulWidget {
  const CourtBookingScreen({super.key, required this.court});
  final Court court;

  @override
  ConsumerState<CourtBookingScreen> createState() => _CourtBookingScreenState();
}

class _CourtBookingScreenState extends ConsumerState<CourtBookingScreen> {
  late DateTime _selectedDay;
  String? _selectedSlotId;
  int? _startHour;
  int? _endHour;
  bool _booking = false;
  String? _error;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  String _dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day}';
  String _hourStr(int h) => '${h.toString().padLeft(2, '0')}:00';

  void _tapHour(int hour) {
    setState(() {
      if (_startHour == null) {
        _startHour = hour;
        _endHour = hour + 1;
      } else if (hour == _startHour) {
        _startHour = null;
        _endHour = null;
      } else if (hour < _startHour!) {
        _startHour = hour;
      } else {
        _endHour = hour + 1;
      }
    });
  }

  bool _isBooked(int hour, List<CustomBooking> bookings) {
    for (final b in bookings) {
      final start = b.startsAt.hour;
      final end = b.endsAt.hour;
      if (start <= hour && hour < end) return true;
    }
    return false;
  }

  Future<void> _confirmBooking(String slotId) async {
    setState(() {
      _booking = true;
      _error = null;
    });
    try {
      final starts = DateTime(
          _selectedDay.year, _selectedDay.month, _selectedDay.day, _startHour!);
      final ends = DateTime(
          _selectedDay.year, _selectedDay.month, _selectedDay.day, _endHour!);
      await ref.read(bookingRepositoryProvider).bookSlot(
            slotId: slotId,
            startsAt: starts,
            endsAt: ends,
          );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.pop();
        final slots = ref.read(courtSlotsProvider(widget.court.id)).valueOrNull;
        final label = slots != null
            ? (slots.where((s) => s.id == slotId).isNotEmpty
                ? slots.firstWhere((s) => s.id == slotId).label
                : 'your court')
            : 'your court';
        messenger.showSnackBar(
          SnackBar(content: Text('Booked! See you on $label.')),
        );
      }
    } catch (e) {
      final msg = e.toString();
      setState(() {
        _error = msg.contains('slot_not_available')
            ? 'That time is no longer available. Please choose another slot.'
            : 'Booking failed. Please try again.';
        if (msg.contains('slot_not_available')) {
          _startHour = null;
          _endHour = null;
          ref.invalidate(courtBookingsProvider);
        }
      });
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final court = widget.court;
    final slotsAsync = ref.watch(courtSlotsProvider(court.id));

    // Auto-select first slot.
    final slots = slotsAsync.valueOrNull ?? [];
    final effectiveSlotId = _selectedSlotId ??
        (slots.isNotEmpty ? slots.first.id : null);

    final bookingsAsync = effectiveSlotId != null
        ? ref.watch(courtBookingsProvider(
            CourtBookingQuery(slotId: effectiveSlotId, date: _selectedDay)))
        : null;
    final bookings = bookingsAsync?.valueOrNull ?? [];

    final hasSelection = _startHour != null && _endHour != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Book a Court')),
      body: Column(
        children: [
          // Day strip
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 8,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final day = DateTime.now().add(Duration(days: i));
                final dayDate = DateTime(day.year, day.month, day.day);
                final isSelected = dayDate == _selectedDay;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedDay = dayDate;
                    _startHour = null;
                    _endHour = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? kBrandGreen
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      _dayLabel(day),
                      style: TextStyle(
                        color: isSelected ? Colors.white : scheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Slot tabs (only when >1 slot)
          if (slots.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: slots.map((slot) {
                  final selected = slot.id == effectiveSlotId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(slot.label),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _selectedSlotId = slot.id;
                        _startHour = null;
                        _endHour = null;
                      }),
                    ),
                  );
                }).toList(),
              ),
            ),
          // Timeline
          Expanded(
            child: effectiveSlotId == null
                ? const Center(child: Text('No slots available.'))
                : ListView.builder(
                    itemCount: 16, // hours 06–21
                    itemBuilder: (context, i) {
                      final hour = 6 + i;
                      final booked = _isBooked(hour, bookings);
                      final selected = hasSelection &&
                          hour >= _startHour! &&
                          hour < _endHour!;
                      return _HourBlock(
                        hour: hour,
                        isBooked: booked,
                        isSelected: selected,
                        onTap: booked ? null : () => _tapHour(hour),
                      );
                    },
                  ),
          ),
          // Error
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!,
                  style: TextStyle(color: scheme.error),
                  textAlign: TextAlign.center),
            ),
          // Booking summary + confirm
          if (hasSelection && effectiveSlotId != null) ...[
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                _buildSummary(slots, effectiveSlotId, court),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: FilledButton(
              onPressed: (hasSelection && effectiveSlotId != null && !_booking)
                  ? () => _confirmBooking(effectiveSlotId)
                  : null,
              child: _booking
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirm booking'),
            ),
          ),
        ],
      ),
    );
  }

  String _buildSummary(
      List<CourtSlot> slots, String slotId, Court court) {
    final slotLabel = slots.isNotEmpty &&
            slots.where((s) => s.id == slotId).isNotEmpty
        ? slots.firstWhere((s) => s.id == slotId).label
        : 'Court';
    final hours = _endHour! - _startHour!;
    final total = court.customFeeCents! * hours;
    final feeStr = formatFee(total, court.currency);
    final dayLabel = _dayLabel(_selectedDay);
    return '$slotLabel · $dayLabel · ${_hourStr(_startHour!)}–${_hourStr(_endHour!)} · $feeStr';
  }
}

class _HourBlock extends StatelessWidget {
  const _HourBlock({
    required this.hour,
    required this.isBooked,
    required this.isSelected,
    required this.onTap,
  });

  final int hour;
  final bool isBooked;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = '${hour.toString().padLeft(2, '0')}:00';

    Color bg;
    if (isSelected) {
      bg = kBrandGreen.withValues(alpha: 0.15);
    } else if (isBooked) {
      bg = scheme.surfaceContainerHighest;
    } else {
      bg = scheme.surface;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            if (isBooked)
              Text(
                'Booked',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            if (isSelected && !isBooked)
              Icon(Icons.check_circle_outline,
                  size: 16, color: kBrandGreen.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/court_booking_screen_test.dart
```

Expected: 7 tests pass.

- [ ] **Step 5: Full suite green**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/lobby/court_booking_screen.dart app/test/court_booking_screen_test.dart
git commit -m "feat(lobby): CourtBookingScreen — day strip, hour timeline, range selection, confirm"
```

---

### Task 8: Router wiring

**Files:**
- Modify: `app/lib/app/router.dart`

**Interfaces:**
- Consumes: `LobbyScreen` (Task 6), `CourtPickerScreen` (Task 5), `CourtBookingScreen` (Task 7), `Court` (Task 2).
- Produces: `/play` → `LobbyScreen`; `/play/courts` (root nav) → `CourtPickerScreen`; `/play/custom` (root nav) → `CourtBookingScreen(court: s.extra as Court)`.

- [ ] **Step 1: Update imports in `router.dart`**

In `app/lib/app/router.dart`, replace the import of `court_list_screen.dart` with the three new feature imports and remove the now-unused direct import:

```dart
// Remove:
import '../features/discovery/court_list_screen.dart';

// Add:
import '../features/discovery/court_picker_screen.dart';
import '../features/lobby/court_booking_screen.dart';
import '../features/lobby/lobby_screen.dart';
```

Keep `court.dart` import — add it:
```dart
import '../data/court.dart';
```

- [ ] **Step 2: Update the `/play` branch route**

Find:
```dart
StatefulShellBranch(routes: [
  GoRoute(path: '/play', builder: (c, s) => const CourtListScreen()),
]),
```

Replace with:
```dart
StatefulShellBranch(routes: [
  GoRoute(path: '/play', builder: (c, s) => const LobbyScreen()),
]),
```

- [ ] **Step 3: Add the two new full-screen routes**

After the existing `/play/court/:id` route (around line 115), add:

```dart
GoRoute(
  path: '/play/courts',
  parentNavigatorKey: _rootNavigatorKey,
  builder: (c, s) => const CourtPickerScreen(),
),
GoRoute(
  path: '/play/custom',
  parentNavigatorKey: _rootNavigatorKey,
  builder: (c, s) => CourtBookingScreen(court: s.extra as Court),
),
```

- [ ] **Step 4: Compile check**

```bash
flutter analyze lib/app/router.dart
```

Expected: no errors.

- [ ] **Step 5: Full suite green**

```bash
flutter test
```

Expected: all tests pass (47+ tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/app/router.dart
git commit -m "feat(router): wire LobbyScreen to /play; add /play/courts and /play/custom routes"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| `courts.custom_fee_cents` column | Task 1 |
| `payments.kind` extended to `'custom'` | Task 1 |
| `custom_bookings` table + RLS | Task 1 |
| `book_custom_slot` RPC | Task 1 |
| `Court.customFeeCents` field + `fromMap` | Task 2 |
| `CourtSlot`, `CustomBooking`, `CourtBookingQuery` models | Task 3 |
| `courtSlotsProvider`, `courtBookingsProvider` | Task 3 |
| `currentUserDisplayNameProvider` | Task 3 |
| `CourtListScreen` picker mode (`onSelect` + info button) | Task 4 |
| `CourtPickerScreen` wrapper | Task 5 |
| `LobbyScreen` — court selector, player slots, action row | Task 6 |
| "Book a Court" disabled when no court / no fee | Task 6 |
| `CourtBookingScreen` — day strip, slot tabs, timeline | Task 7 |
| Range selection (tap start + tap end) | Task 7 |
| Booking summary with fee | Task 7 |
| `book_custom_slot` RPC call + error handling | Task 7 |
| Router: `/play` → Lobby, `/play/courts`, `/play/custom` | Task 8 |
| Full-screen routes via `parentNavigatorKey` | Task 8 |

**Placeholder scan:** None found — all steps include complete code.

**Type consistency:**
- `CourtBookingQuery` used in Task 3 (definition) and Task 7 (usage) — match confirmed.
- `bookingRepositoryProvider` — `Provider<BookingRepository>` in Task 3, overridden in Task 7 tests — consistent.
- `courtSlotsProvider(court.id)` — `FutureProvider.family<List<CourtSlot>, String>` in Task 3, watched in Task 7 — consistent.
- `currentUserDisplayNameProvider` — `FutureProvider<String>` in Task 3, overridden in Task 6 tests — consistent.
- `LobbyScreen({this.initialCourt})` — defined in Task 6, referenced in Task 6 tests — consistent. Note: the router (Task 8) instantiates `const LobbyScreen()` with no argument (default null), which is correct for the normal play entry point.
- `CourtBookingScreen({required this.court})` — defined in Task 7, router passes `s.extra as Court` in Task 8 — consistent.

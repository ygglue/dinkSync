# Player Court Discovery — Design

**Date:** 2026-06-22
**Status:** Approved (design)

## Goal

Give players a way to find courts: a searchable list of active venues, and a
court detail page showing venue info plus live court availability. This is the
first player-facing feature and the seam the queue/matchmaking loop will plug
into.

## Scope

**In scope**

- A courts **list** (replaces the "Find a game" placeholder at `/play`):
  all active courts, sorted by name, with client-side name search.
- A court **detail** page: venue info + live slot availability + a disabled
  "Join queue — coming soon" CTA.
- Shared `Court` model extraction; a new `discovery` feature module.

**Out of scope (deferred)**

- Location / distance / map view (lat/lng columns exist; revisit later).
- The actual join-queue action (the CTA is a disabled placeholder).
- Per-row availability badges on the list (availability shows on detail only).

## Database / RLS

No migration is required. Existing policies already permit the reads:

- `courts_select` allows reading active courts (`using (true)` pre-0008;
  `status='active' OR member OR admin` post-0008 — either way active courts
  are readable by players).
- `court_slots_select` is `using (true)` — any client can read slot status.

This feature is therefore pure client-side code against existing tables.

## Architecture

### Shared model extraction

Move the `Court` model out of `features/owner/court_repository.dart` into a
shared location so the player module does not depend on the owner module.

- **Create** `app/lib/data/court.dart` — holds `Court` (unchanged fields and
  `fromMap`/`isActive`).
- **Modify** `app/lib/features/owner/court_repository.dart` — delete the
  `Court` class, add `import '../../data/court.dart';`, re-export so existing
  importers keep working: `export '../../data/court.dart' show Court;`.

`SubscriptionPlan`, `planPriceCents`, `planName`, `parseAmountToMinor` stay in
`court_repository.dart` (owner-scoped, not needed by discovery).

### New module: `features/discovery/`

```
app/lib/features/discovery/
  discovery_repository.dart   # repo + CourtAvailability + providers
  court_list_screen.dart      # /play
  court_detail_screen.dart    # /play/court/:id
```

Fee formatting helper lives in `app/lib/data/court.dart` (next to the model):

```dart
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

## Components

### `CourtAvailability`

```dart
class CourtAvailability {
  const CourtAvailability({required this.openCount, required this.totalCount});
  final int openCount;   // slots with status 'open'
  final int totalCount;  // in-service slots: status 'open' or 'occupied'
}
```

Semantics: `closed` slots are out of service and excluded from `totalCount`.
Display string: `"$openCount of $totalCount courts open"`. When `totalCount`
is 0, display `"No courts in service"`.

### `DiscoveryRepository`

Abstract interface + Supabase implementation, mirroring `CourtRepository`.

```dart
abstract class DiscoveryRepository {
  Future<List<Court>> listActiveCourts();
  Future<Court?> courtById(String id);
  Future<CourtAvailability> availability(String courtId);
}
```

Supabase implementation:

- `listActiveCourts()`:
  `from('courts').select().eq('status','active').order('name')`, map rows to
  `Court`.
- `courtById(id)`:
  `from('courts').select().eq('id', id).limit(1)`; null if empty.
- `availability(courtId)`:
  `from('court_slots').select('status').eq('court_id', courtId)`; count
  `open` into `openCount`, count `open` + `occupied` into `totalCount`.

### Providers (in `discovery_repository.dart`)

```dart
final discoveryRepositoryProvider =
    Provider<DiscoveryRepository>((ref) => SupabaseDiscoveryRepository(supabase));

// Fetched once; search filters this list client-side in the widget.
final activeCourtsProvider =
    FutureProvider<List<Court>>((ref) => ref.watch(discoveryRepositoryProvider).listActiveCourts());

final courtByIdProvider = FutureProvider.family<Court?, String>(
    (ref, id) => ref.watch(discoveryRepositoryProvider).courtById(id));

final courtAvailabilityProvider = FutureProvider.family<CourtAvailability, String>(
    (ref, id) => ref.watch(discoveryRepositoryProvider).availability(id));
```

### `CourtListScreen` (`/play`)

- Body (no Scaffold app bar of its own beyond the Play shell's; the Play shell
  provides the top bar). A `TextField` (search by name) pinned at the top, then
  the list.
- Watches `activeCourtsProvider`. Filters the resolved list client-side:
  case-insensitive `name.contains(query)`.
- States:
  - loading → centered `CircularProgressIndicator`.
  - error → retry (invalidate `activeCourtsProvider`), same pattern as
    `ManagementHome`'s `_ErrorRetry`.
  - empty (no active courts at all) → "No courts available yet."
  - empty after filter (query matches nothing) → "No courts match \"<query>\"."
- Each court → a tappable card (`InkWell`, `kRadius`) showing name, address
  (or "Address not set"), and `formatFee(entryFeeCents, currency)`. Tapping
  navigates `context.push('/play/court/<id>')`.

### `CourtDetailScreen` (`/play/court/:id`)

- Own `Scaffold` + `AppBar(title: court name)` — pushed within the Play branch,
  so a back button appears automatically and the bottom nav stays visible.
- Watches `courtByIdProvider(id)` for venue info and
  `courtAvailabilityProvider(id)` for live availability.
- Renders: name (headline), address, entry fee (`formatFee`), number of courts;
  an availability line that resolves independently
  ("2 of 3 courts open" / "No courts in service" / a small inline spinner while
  loading); and a disabled `FilledButton` labelled "Join queue — coming soon".
- States: court loading → spinner; court error or null → "Could not load this
  court." with a back affordance (the app bar back button suffices).

## Routing

Add `court/:id` as a sub-route of the existing `/play` branch in
`app/lib/app/router.dart`:

```dart
StatefulShellBranch(routes: [
  GoRoute(
    path: '/play',
    builder: (c, s) => const CourtListScreen(),
    routes: [
      GoRoute(
        path: 'court/:id',
        builder: (c, s) => CourtDetailScreen(courtId: s.pathParameters['id']!),
      ),
    ],
  ),
]),
```

This replaces the current "Find a game" `PlaceholderTab`. Because the detail
route is nested in the branch (not pushed on the root navigator), the Play
bottom nav remains visible and the back button is automatic.

## Error Handling

- All Supabase reads surface through `FutureProvider` AsyncValue; UI handles
  loading/error/data explicitly.
- List error offers a retry that invalidates `activeCourtsProvider`.
- Availability failure on the detail page degrades gracefully: show
  "Availability unavailable" rather than failing the whole page (the venue info
  comes from a separate provider).

## Testing

Follow the existing pattern: `ProviderScope` with provider overrides and a hand
-written fake repository (see `subscription_screen_test.dart`,
`owner_dashboard_screen_test.dart`).

**Repository / pure logic**

- `formatFee`: PHP → `₱150`, USD → `$10`, unknown → `EUR 150`.
- `CourtAvailability` semantics via a fake: a court with slots
  `[open, open, occupied, closed]` → `openCount=2`, `totalCount=3`.

**`CourtListScreen` widget tests** (override `discoveryRepositoryProvider` /
`activeCourtsProvider` with a fake):

- renders a list of courts from the provider.
- typing in search filters the list (case-insensitive).
- empty provider → "No courts available yet."
- search with no matches → "No courts match ...".

**`CourtDetailScreen` widget tests:**

- renders name, address, fee, number of courts.
- availability line shows "2 of 3 courts open" from a fake.
- the "Join queue — coming soon" button is present and disabled.

## File Summary

- **Create** `app/lib/data/court.dart` — `Court` model + `formatFee`.
- **Create** `app/lib/features/discovery/discovery_repository.dart` —
  `DiscoveryRepository`, `SupabaseDiscoveryRepository`, `CourtAvailability`,
  providers.
- **Create** `app/lib/features/discovery/court_list_screen.dart`.
- **Create** `app/lib/features/discovery/court_detail_screen.dart`.
- **Modify** `app/lib/features/owner/court_repository.dart` — remove `Court`,
  import + re-export it from `data/court.dart`.
- **Modify** `app/lib/app/router.dart` — `/play` → `CourtListScreen`, add
  nested `court/:id` route.
- **Create** tests for the repository helpers and both screens.

# Player Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any signed-in user view another player's public profile (rank, MMR, win/loss, recent matches, member-since) and find players via search, without exposing private profile fields.

**Architecture:** A new Supabase migration adds three plain (non-materialized) security-definer views exposing only public columns, so the self-only RLS on `profiles` stays intact. The Flutter app gains a pure-Dart rank helper, a `PlayerProfileRepository` (abstract + Supabase impl + Riverpod providers) mirroring the existing `DiscoveryRepository` pattern, a read-only profile screen at `/play/player/:id`, and a Social tab that replaces the placeholder with player search.

**Tech Stack:** Flutter 3.44 / Dart 3.12, Riverpod (`FutureProvider.family`), go_router, Supabase Postgres views + grants, supabase_flutter, phosphoricons_flutter.

**Spec:** `docs/superpowers/specs/2026-06-24-player-profiles-design.md`

## Global Constraints

- **Colors from `Theme.of(context).colorScheme`** — no hardcoded hex except the existing green gradient header constants reused from `profile_screen.dart`. (dinksync-ui skill.)
- **Fonts via the theme** (`theme.textTheme.*`) — never call `GoogleFonts` in a screen. Plus Jakarta Sans headlines / Inter body.
- **24px radius** (`kRadius` from `app/lib/app/theme.dart`) for boxes; pills/avatars fully round.
- **Money/IDs:** UUID PKs; this sub-project does not touch money.
- **Views are plain views** — never `create table` or `materialized view`; they store no rows. The base tables remain the single source of truth.
- **Security-definer views are intentional** — do NOT switch them to `security_invoker` (that re-breaks public reads). Expose only the listed columns.
- **Repository pattern:** abstract interface + `Supabase…Repository` impl + `Provider` for the repo + `FutureProvider`(`.family`) for reads, mirroring `app/lib/features/discovery/discovery_repository.dart`.
- `flutter analyze` clean and `flutter test` green before completion.

---

### Task 1: Public-data migration (three views)

**Files:**
- Create: `supabase/migrations/0014_public_profiles.sql`

**Interfaces:**
- Produces: views `public_profiles(id, display_name, avatar_url, mmr, created_at)`, `public_player_stats(profile_id, wins, losses)`, `public_recent_matches(profile_id, match_id, played_at, result, team, winning_team)`, each `grant select … to authenticated`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0014_public_profiles.sql`:

```sql
-- 0014_public_profiles.sql
-- Public, read-only views for social features. The profiles table RLS stays
-- self-only (see 0012); these views expose ONLY safe columns and bypass that
-- RLS by virtue of being security-definer (default) views.
--
-- These are PLAIN views (saved queries) — NOT tables, NOT materialized views.
-- They store no rows and cannot drift; profiles/match_results/matches remain
-- the single source of truth. Do not convert them to materialized views.
--
-- The Supabase advisor will flag these as "Security Definer View". That is
-- intended here: switching to security_invoker would respect the self-only RLS
-- and re-break public reads.

-- Public profile fields (no is_platform_admin, no updated_at).
create view public.public_profiles as
  select id, display_name, avatar_url, mmr, created_at
  from public.profiles;

grant select on public.public_profiles to authenticated;

-- Per-player win/loss totals. Empty until Find Match writes match_results.
create view public.public_player_stats as
  select
    p.id as profile_id,
    count(*) filter (where mr.result = 'win')  as wins,
    count(*) filter (where mr.result = 'loss') as losses
  from public.profiles p
  left join public.match_results mr on mr.profile_id = p.id
  group by p.id;

grant select on public.public_player_stats to authenticated;

-- Per-player completed matches, newest-first applied by the client.
-- Empty until Find Match writes matches/match_results.
create view public.public_recent_matches as
  select
    mr.profile_id,
    m.id          as match_id,
    m.played_at,
    mr.result,
    mr.team,
    m.winning_team
  from public.match_results mr
  join public.matches m on m.id = mr.match_id
  where m.status = 'completed';

grant select on public.public_recent_matches to authenticated;
```

- [ ] **Step 2: Verify the migration applies**

Run (local Supabase, if available): `supabase db reset` (or the project's migration command).
Expected: all migrations apply with no error; `\d+ public.public_profiles` lists exactly the 5 columns.

If no local Supabase is available, verify by SQL review only and note that in the task report. Do NOT apply to the remote project as part of this task.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0014_public_profiles.sql
git commit -m "feat(db): public_profiles/stats/recent_matches views for social"
```

---

### Task 2: Rank helper (pure Dart + tests)

**Files:**
- Create: `app/lib/features/profile/rank.dart`
- Test: `app/test/rank_test.dart`

**Interfaces:**
- Produces: `enum PlayerRank { bronze, silver, gold, platinum, diamond }`, `PlayerRank rankForMmr(int mmr)`, and `extension PlayerRankX on PlayerRank { String get label; }`.

- [ ] **Step 1: Write the failing test**

Create `app/test/rank_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/profile/rank.dart';

void main() {
  group('rankForMmr', () {
    test('boundaries map to the correct tier', () {
      expect(rankForMmr(899), PlayerRank.bronze);
      expect(rankForMmr(900), PlayerRank.silver);
      expect(rankForMmr(1199), PlayerRank.silver);
      expect(rankForMmr(1200), PlayerRank.gold);
      expect(rankForMmr(1499), PlayerRank.gold);
      expect(rankForMmr(1500), PlayerRank.platinum);
      expect(rankForMmr(1799), PlayerRank.platinum);
      expect(rankForMmr(1800), PlayerRank.diamond);
    });

    test('extremes', () {
      expect(rankForMmr(0), PlayerRank.bronze);
      expect(rankForMmr(99999), PlayerRank.diamond);
    });

    test('starting MMR (1000) is Silver', () {
      expect(rankForMmr(1000), PlayerRank.silver);
    });

    test('labels are human-readable', () {
      expect(PlayerRank.bronze.label, 'Bronze');
      expect(PlayerRank.diamond.label, 'Diamond');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/rank_test.dart`
Expected: FAIL — `rank.dart` / `rankForMmr` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/features/profile/rank.dart`:

```dart
/// A player's skill tier, derived from MMR. Starting MMR (1000) is Silver.
enum PlayerRank { bronze, silver, gold, platinum, diamond }

/// Maps an MMR value to its [PlayerRank]. Thresholds are inclusive lower bounds.
PlayerRank rankForMmr(int mmr) {
  if (mmr < 900) return PlayerRank.bronze;
  if (mmr < 1200) return PlayerRank.silver;
  if (mmr < 1500) return PlayerRank.gold;
  if (mmr < 1800) return PlayerRank.platinum;
  return PlayerRank.diamond;
}

extension PlayerRankX on PlayerRank {
  String get label => switch (this) {
        PlayerRank.bronze => 'Bronze',
        PlayerRank.silver => 'Silver',
        PlayerRank.gold => 'Gold',
        PlayerRank.platinum => 'Platinum',
        PlayerRank.diamond => 'Diamond',
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/rank_test.dart`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/profile/rank.dart app/test/rank_test.dart
git commit -m "feat(profile): MMR-to-rank helper with tests"
```

---

### Task 3: Player profile repository (models, parsing, providers + tests)

**Files:**
- Create: `app/lib/features/profile/player_profile_repository.dart`
- Test: `app/test/player_profile_repository_test.dart`

**Interfaces:**
- Consumes: `supabase` from `app/lib/data/supabase_client.dart`.
- Produces:
  - `class PublicProfile { final String id; final String displayName; final String? avatarUrl; final int mmr; final DateTime createdAt; factory PublicProfile.fromMap(Map<String,dynamic>); }`
  - `class PlayerStats { final int wins; final int losses; const PlayerStats({...}); factory PlayerStats.fromMap(Map<String,dynamic>?); double? get winRate; int get total; }`
  - `class RecentMatch { final String matchId; final DateTime playedAt; final String result; final int team; final int? winningTeam; factory RecentMatch.fromMap(Map<String,dynamic>); }`
  - `abstract class PlayerProfileRepository` with `fetchProfile`, `fetchStats`, `fetchRecentMatches`, `searchPlayers`.
  - `playerProfileRepositoryProvider`, `playerProfileProvider(id)`, `playerStatsProvider(id)`, `playerRecentMatchesProvider(id)`, `playerSearchProvider(query)`.

- [ ] **Step 1: Write the failing test**

Create `app/test/player_profile_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/profile/player_profile_repository.dart';

void main() {
  group('PublicProfile.fromMap', () {
    test('parses a row with avatar', () {
      final p = PublicProfile.fromMap(const {
        'id': 'u1',
        'display_name': 'Ada',
        'avatar_url': 'https://x/a.png',
        'mmr': 1200,
        'created_at': '2026-01-02T03:04:05Z',
      });
      expect(p.id, 'u1');
      expect(p.displayName, 'Ada');
      expect(p.avatarUrl, 'https://x/a.png');
      expect(p.mmr, 1200);
      expect(p.createdAt.toUtc().year, 2026);
    });

    test('null avatar and missing mmr default', () {
      final p = PublicProfile.fromMap(const {
        'id': 'u2',
        'display_name': 'Bo',
        'avatar_url': null,
        'mmr': null,
        'created_at': '2026-01-02T03:04:05Z',
      });
      expect(p.avatarUrl, isNull);
      expect(p.mmr, 1000); // default starting MMR
    });
  });

  group('PlayerStats', () {
    test('fromMap parses counts', () {
      final s = PlayerStats.fromMap(const {'wins': 3, 'losses': 1});
      expect(s.wins, 3);
      expect(s.losses, 1);
      expect(s.total, 4);
      expect(s.winRate, closeTo(0.75, 1e-9));
    });

    test('null map -> zeroes', () {
      final s = PlayerStats.fromMap(null);
      expect(s.wins, 0);
      expect(s.losses, 0);
    });

    test('zero games -> winRate is null (no division by zero)', () {
      const s = PlayerStats(wins: 0, losses: 0);
      expect(s.total, 0);
      expect(s.winRate, isNull);
    });
  });

  group('RecentMatch.fromMap', () {
    test('parses a row', () {
      final m = RecentMatch.fromMap(const {
        'match_id': 'm1',
        'played_at': '2026-02-03T10:00:00Z',
        'result': 'win',
        'team': 1,
        'winning_team': 1,
      });
      expect(m.matchId, 'm1');
      expect(m.result, 'win');
      expect(m.team, 1);
      expect(m.winningTeam, 1);
      expect(m.playedAt.toUtc().month, 2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/player_profile_repository_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/features/profile/player_profile_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

/// Public, read-only view of another player (from the public_profiles view).
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    required this.mmr,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final int mmr;
  final DateTime createdAt;

  factory PublicProfile.fromMap(Map<String, dynamic> m) => PublicProfile(
        id: m['id'] as String,
        displayName: (m['display_name'] as String?) ?? 'Player',
        avatarUrl: m['avatar_url'] as String?,
        mmr: (m['mmr'] as int?) ?? 1000,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

/// Aggregate win/loss record (from public_player_stats).
class PlayerStats {
  const PlayerStats({required this.wins, required this.losses});

  final int wins;
  final int losses;

  int get total => wins + losses;

  /// Fraction of games won, or null when no games have been played.
  double? get winRate => total == 0 ? null : wins / total;

  factory PlayerStats.fromMap(Map<String, dynamic>? m) => PlayerStats(
        wins: (m?['wins'] as int?) ?? 0,
        losses: (m?['losses'] as int?) ?? 0,
      );
}

/// One completed match for a player (from public_recent_matches).
class RecentMatch {
  const RecentMatch({
    required this.matchId,
    required this.playedAt,
    required this.result,
    required this.team,
    this.winningTeam,
  });

  final String matchId;
  final DateTime playedAt;
  final String result; // 'win' | 'loss'
  final int team;
  final int? winningTeam;

  factory RecentMatch.fromMap(Map<String, dynamic> m) => RecentMatch(
        matchId: m['match_id'] as String,
        playedAt: DateTime.parse(m['played_at'] as String).toLocal(),
        result: m['result'] as String,
        team: m['team'] as int,
        winningTeam: m['winning_team'] as int?,
      );
}

abstract class PlayerProfileRepository {
  Future<PublicProfile?> fetchProfile(String id);
  Future<PlayerStats> fetchStats(String id);
  Future<List<RecentMatch>> fetchRecentMatches(String id);
  Future<List<PublicProfile>> searchPlayers(String query);
}

class SupabasePlayerProfileRepository implements PlayerProfileRepository {
  SupabasePlayerProfileRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<PublicProfile?> fetchProfile(String id) async {
    final rows =
        await _db.from('public_profiles').select().eq('id', id).limit(1);
    return rows.isEmpty ? null : PublicProfile.fromMap(rows.first);
  }

  @override
  Future<PlayerStats> fetchStats(String id) async {
    final rows = await _db
        .from('public_player_stats')
        .select('wins, losses')
        .eq('profile_id', id)
        .limit(1);
    return PlayerStats.fromMap(rows.isEmpty ? null : rows.first);
  }

  @override
  Future<List<RecentMatch>> fetchRecentMatches(String id) async {
    final rows = await _db
        .from('public_recent_matches')
        .select('match_id, played_at, result, team, winning_team')
        .eq('profile_id', id)
        .order('played_at', ascending: false)
        .limit(10);
    return rows.map(RecentMatch.fromMap).toList();
  }

  @override
  Future<List<PublicProfile>> searchPlayers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final me = _db.auth.currentUser?.id;
    var builder = _db
        .from('public_profiles')
        .select()
        .ilike('display_name', '%$q%');
    if (me != null) builder = builder.neq('id', me);
    final rows = await builder.order('display_name').limit(20);
    return rows.map(PublicProfile.fromMap).toList();
  }
}

final playerProfileRepositoryProvider = Provider<PlayerProfileRepository>(
  (ref) => SupabasePlayerProfileRepository(supabase),
);

final playerProfileProvider =
    FutureProvider.family<PublicProfile?, String>((ref, id) {
  return ref.watch(playerProfileRepositoryProvider).fetchProfile(id);
});

final playerStatsProvider =
    FutureProvider.family<PlayerStats, String>((ref, id) {
  return ref.watch(playerProfileRepositoryProvider).fetchStats(id);
});

final playerRecentMatchesProvider =
    FutureProvider.family<List<RecentMatch>, String>((ref, id) {
  return ref.watch(playerProfileRepositoryProvider).fetchRecentMatches(id);
});

final playerSearchProvider =
    FutureProvider.family<List<PublicProfile>, String>((ref, query) {
  return ref.watch(playerProfileRepositoryProvider).searchPlayers(query);
});
```

> Note for the implementer: the exact `PostgrestFilterBuilder` typing for the
> conditional `.neq` in `searchPlayers` may need a small adjustment (e.g.
> assigning to `var` then chaining, or applying `.neq` before `.select` depending
> on the installed supabase_flutter version). Keep the behavior: filter by
> `ilike`, exclude the current user, order by name, limit 20. Confirm it compiles.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/player_profile_repository_test.dart`
Expected: PASS (parsing + winRate cases).

- [ ] **Step 5: Run analyzer**

Run: `cd app && flutter analyze lib/features/profile/player_profile_repository.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/profile/player_profile_repository.dart app/test/player_profile_repository_test.dart
git commit -m "feat(profile): player profile repository + providers with tests"
```

---

### Task 4: Public player profile screen + route

**Files:**
- Create: `app/lib/features/profile/player_profile_screen.dart`
- Modify: `app/lib/app/router.dart` (add `/play/player/:id` route)

**Interfaces:**
- Consumes: `playerProfileProvider`, `playerStatsProvider`, `playerRecentMatchesProvider` (Task 3); `rankForMmr` + `PlayerRankX.label` (Task 2); `supabase` for the "is this me?" check.
- Produces: `class PlayerProfileScreen extends ConsumerWidget` with `const PlayerProfileScreen({required String profileId})`; route `'/play/player/:id'`.

- [ ] **Step 1: Add the route**

In `app/lib/app/router.dart`, add an import:

```dart
import '../features/profile/player_profile_screen.dart';
```

And add this route alongside the other full-screen sub-pages (near `/play/court/:id`, around line 122):

```dart
GoRoute(
  path: '/play/player/:id',
  parentNavigatorKey: _rootNavigatorKey,
  builder: (c, s) => PlayerProfileScreen(profileId: s.pathParameters['id']!),
),
```

- [ ] **Step 2: Write the screen**

Create `app/lib/features/profile/player_profile_screen.dart`. Reuse the trading-card look from `profile_screen.dart` (green gradient header constants `Color(0xFF2E7D32)` → `Color(0xFF43A047)`, 100px circular avatar, initials fallback). Read-only. Structure:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/theme.dart';
import '../../data/supabase_client.dart';
import 'player_profile_repository.dart';
import 'rank.dart';

class PlayerProfileScreen extends ConsumerWidget {
  const PlayerProfileScreen({super.key, required this.profileId});

  final String profileId;

  static const _darkGreen = Color(0xFF2E7D32);
  static const _midGreen = Color(0xFF43A047);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profileAsync = ref.watch(playerProfileProvider(profileId));
    final isMe = supabase.auth.currentUser?.id == profileId;

    return Scaffold(
      appBar: AppBar(),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text("Couldn't load player",
              style: TextStyle(color: scheme.error)),
        ),
        data: (p) {
          if (p == null) {
            return const Center(child: Text('Player not found.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(playerProfileProvider(profileId));
              ref.invalidate(playerStatsProvider(profileId));
              ref.invalidate(playerRecentMatchesProvider(profileId));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                _ProfileCard(profile: p, darkGreen: _darkGreen, midGreen: _midGreen),
                const SizedBox(height: 24),
                _StatsRow(profileId: profileId),
                const SizedBox(height: 24),
                _RecentMatches(profileId: profileId),
                if (isMe) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/profile'),
                    icon: Icon(PhosphorIconsFill.pencilSimple),
                    label: const Text('Edit profile'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
```

Then implement the private widgets in the same file:

- `_ProfileCard` — bordered rounded-`kRadius` container with the green gradient header (avatar: `Image.network(p.avatarUrl!)` with initials fallback, else initials), then a body showing `p.displayName` (titleLarge w700), a **rank badge** (`rankForMmr(p.mmr).label`) + `'${p.mmr} MMR'`, and **Member since** `_memberSince(p.createdAt)`.
- `_StatsRow` — `ConsumerWidget` watching `playerStatsProvider(profileId)`; renders three cells (Wins / Losses / Win-rate) using the same visual style as `_CardStat` in `profile_screen.dart`. Win-rate shows `'—'` when `winRate == null`, else `'${(winRate*100).round()}%'`. While loading/error, show placeholder dashes.
- `_RecentMatches` — `ConsumerWidget` watching `playerRecentMatchesProvider(profileId)`; section title "Recent matches" then either the list (each: result chip win/loss colored `scheme.primary`/`scheme.error`, date) or a centered empty state "No matches yet" when the list is empty.
- A top-level helper `String _memberSince(DateTime d)` returning e.g. `'Member since Jan 2026'` using a const month-abbreviation list (mirror the `_months` pattern in `schedule_screen.dart`).

Use `theme.textTheme.*` for all text and `scheme.*` for all colors. Initials = first char of `displayName` (uppercased), '?' if empty.

- [ ] **Step 3: Run the analyzer**

Run: `cd app && flutter analyze lib/features/profile/player_profile_screen.dart lib/app/router.dart`
Expected: No issues.

- [ ] **Step 4: Smoke-test compile via existing suite**

Run: `cd app && flutter test test/router_logic_test.dart`
Expected: PASS (route addition doesn't break router construction).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/profile/player_profile_screen.dart app/lib/app/router.dart
git commit -m "feat(profile): read-only public player profile screen + route"
```

---

### Task 5: Social tab with player search

**Files:**
- Create: `app/lib/features/social/social_screen.dart`
- Modify: `app/lib/app/router.dart` (swap the `/social` `PlaceholderTab` for `SocialScreen`)

**Interfaces:**
- Consumes: `playerSearchProvider(query)` (Task 3); `rankForMmr` + `.label` (Task 2); navigates to `/play/player/:id` (Task 4).
- Produces: `class SocialScreen extends ConsumerStatefulWidget`.

- [ ] **Step 1: Write the screen**

Create `app/lib/features/social/social_screen.dart`. A debounced search field driving `playerSearchProvider`. Body-only is fine, but it needs its own scaffold content (the Play shell supplies the AppBar). Structure:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/theme.dart';
import '../profile/player_profile_repository.dart';
import '../profile/rank.dart';

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 92),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctl,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search players',
              prefixIcon: Icon(PhosphorIconsFill.magnifyingGlass),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _results(context, ref, scheme, theme)),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, WidgetRef ref, ColorScheme scheme,
      ThemeData theme) {
    if (_query.isEmpty) {
      return _Hint(
        icon: PhosphorIconsFill.usersThree,
        text: 'Search for players by name',
      );
    }
    final async = ref.watch(playerSearchProvider(_query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Hint(
        icon: PhosphorIconsFill.warning,
        text: 'Search failed. Try again.',
      ),
      data: (players) {
        if (players.isEmpty) {
          return _Hint(
            icon: PhosphorIconsFill.smileyBlank,
            text: 'No players found',
          );
        }
        return ListView.separated(
          itemCount: players.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _PlayerRow(player: players[i]),
        );
      },
    );
  }
}
```

Then implement private widgets in the same file:
- `_PlayerRow({required PublicProfile player})` — a `Material`/`InkWell` rounded-`kRadius` tile (mirror the lobby court-selector tile): leading circular avatar (network or initials over `scheme.surfaceContainerHighest`), title `player.displayName`, subtitle rank chip `rankForMmr(player.mmr).label` + `'${player.mmr} MMR'`, trailing caret. `onTap: () => context.push('/play/player/${player.id}')`.
- `_Hint({required IconData icon, required String text})` — centered muted icon + text empty/placeholder state (mirror the schedule empty state).

All colors `scheme.*`, text `theme.textTheme.*`.

- [ ] **Step 2: Swap the route**

In `app/lib/app/router.dart`:
- Add import: `import '../features/social/social_screen.dart';`
- Replace the `/social` branch builder (currently a `PlaceholderTab`) with:

```dart
GoRoute(
  path: '/social',
  builder: (c, s) => const SocialScreen(),
),
```

Leave the `PhosphorIconsFill` import in place only if still used elsewhere in the file; if the analyzer reports it unused after removing the `PlaceholderTab`, remove that import too. (`PlaceholderTab` import may also become unused — remove it if so.)

- [ ] **Step 3: Run the analyzer**

Run: `cd app && flutter analyze lib/features/social/social_screen.dart lib/app/router.dart`
Expected: No issues (including no unused-import warnings).

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test`
Expected: All tests green (existing + new rank/repository tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/social/social_screen.dart app/lib/app/router.dart
git commit -m "feat(social): player search tab replacing placeholder"
```

---

## Final verification

- [ ] `cd app && flutter analyze` — clean across the project.
- [ ] `cd app && flutter test` — all green.
- [ ] Manual (human, if possible): `flutter run`, open Social tab, search a name, tap a result, confirm the profile renders with rank/MMR/member-since, empty "No matches yet", and that your own profile shows the "Edit profile" button. Verify dark mode.

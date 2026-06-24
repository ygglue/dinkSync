# Player Profiles — Design Spec

**Date:** 2026-06-24
**Status:** Approved (design); pending implementation plan
**Sub-project:** 1 of 5 in the Find Match + Social initiative

## Context

dinkSync is a Flutter (3.44 / Dart 3.12) pickleball app backed by Supabase.
This is the first sub-project in a five-part initiative:

1. **Player Profiles** ← this spec (foundation)
2. Find Match (singles + doubles, court-anchored queue, score entry, Elo, fees)
3. Friends / Following
4. In-app Chat (per-match room)
5. Match History Feed

Player Profiles is the foundation: it removes the self-only RLS wall on
`profiles` and gives every later feature a public profile screen, a player
repository, and a rank helper to reuse.

### Why this is needed now

The `profiles` table RLS is currently **self-only** (migration `0012_fix_profiles_rls.sql`).
Its own comment states that social features require a separate mechanism exposing
only public fields. Until that exists, no feature can read another player's name,
avatar, or MMR.

## Goal

Let a signed-in user view any other player's public profile (rank, MMR, win/loss
record, recent matches, member-since) and find players via search — without
exposing private profile fields.

## Architecture

A new Supabase migration adds three **security-definer views** that expose only
public columns; the base `profiles` table policy stays self-only. The Flutter app
gains a player-profile repository (with Riverpod providers), a read-only profile
screen reachable at `/play/player/:id`, and a Social tab that replaces the current
placeholder with player search. Rank is derived from MMR by a pure Dart helper.

## Tech Stack

- Flutter / Dart, Riverpod (`FutureProvider.family`), go_router
- Supabase Postgres (views + grants), supabase_flutter client
- phosphoricons_flutter, Plus Jakarta Sans / Inter (per dinksync-ui skill)

---

## Backend

A single new migration (next number in sequence, e.g. `0014_public_profiles.sql`).

> **No redundancy:** these are **plain views** (saved queries), not tables and
> **not materialized views**. They store no rows and cannot drift — the base
> tables (`profiles`, `match_results`, `matches`) remain the single source of
> truth. Do not convert any of them to a materialized view or a copy table.

### View: `public_profiles`

```sql
create view public.public_profiles as
  select id, display_name, avatar_url, mmr, created_at
  from public.profiles;

grant select on public.public_profiles to authenticated;
```

Security-definer (default) so it bypasses the self-only RLS on `profiles` while
exposing **only** the listed columns. `is_platform_admin`, `updated_at` never leak.

### View: `public_player_stats`

Aggregates `match_results` per player. Returns zero rows / zero counts today
(table empty until Find Match), correct automatically afterward.

```sql
create view public.public_player_stats as
  select
    p.id as profile_id,
    count(*) filter (where mr.result = 'win')  as wins,
    count(*) filter (where mr.result = 'loss') as losses
  from public.profiles p
  left join public.match_results mr on mr.profile_id = p.id
  group by p.id;

grant select on public.public_player_stats to authenticated;
```

### View: `public_recent_matches`

Last games per player, joining `matches` + `match_results`. Empty today; reserves
the query. The app applies its own `.limit(10).order(played_at desc)`.

```sql
create view public.public_recent_matches as
  select
    mr.profile_id,
    m.id as match_id,
    m.played_at,
    mr.result,
    mr.team,
    m.winning_team
  from public.match_results mr
  join public.matches m on m.id = mr.match_id
  where m.status = 'completed';

grant select on public.public_recent_matches to authenticated;
```

> Decision: build all three views now. They are cheap, forward-compatible, and
> let the profile UI be finished in one pass. Stats/recent return empty until
> Find Match writes rows.

> **Implementation note:** Supabase's advisor will flag these as
> "Security Definer View" — that is **expected and intended** here. Do NOT switch
> them to `security_invoker`; that would respect the self-only RLS on `profiles`
> and re-break public reads. Exposing only the safe columns via a definer view is
> the deliberate mechanism. (If the project prefers, the views may be owned by a
> dedicated low-privilege role, but the definer behavior must remain.)

---

## Rank tiers (pure Dart helper)

A `rank.dart` helper maps MMR → tier. Starting MMR is 1000 (Silver).

| Tier | MMR range |
|---|---|
| Bronze | < 900 |
| Silver | 900–1199 |
| Gold | 1200–1499 |
| Platinum | 1500–1799 |
| Diamond | 1800+ |

`PlayerRank rankForMmr(int mmr)` returns the tier name (and optionally a color /
icon for the badge). Boundary values are unit-tested.

---

## Data layer — `player_profile_repository.dart`

Models:

- `PublicProfile { id, displayName, avatarUrl?, mmr, createdAt }`
- `PlayerStats { wins, losses }` with a computed `winRate` getter that returns
  `null` (not a division) when `wins + losses == 0`.
- `RecentMatch { matchId, playedAt, result, team, winningTeam }`

Repository methods (against the three views):

- `Future<PublicProfile?> fetchProfile(String id)`
- `Future<PlayerStats> fetchStats(String id)`
- `Future<List<RecentMatch>> fetchRecentMatches(String id)` — limit 10, newest first
- `Future<List<PublicProfile>> searchPlayers(String query)` — `ilike` on
  `display_name`, excludes the current user, capped (e.g. 20 results)

Riverpod providers: `playerProfileProvider(id)`, `playerStatsProvider(id)`,
`playerRecentMatchesProvider(id)` as `FutureProvider.family`, plus a search
provider for the Social tab.

---

## Screens

### `player_profile_screen.dart` — route `/play/player/:id`

Read-only, pushed over the Play shell with a back button. Reuses the trading-card
aesthetic from the existing `_PlayerCard` in `profile_screen.dart`:

- Green gradient header + circular avatar (network photo or initials)
- Display name + **rank badge + MMR**
- Stat row: **Wins / Losses / Win-rate** (win-rate shows "—" when no games)
- **Member since** (formatted `created_at`)
- **Recent matches** list with a clean "No matches yet" empty state
- If the viewed id **is the current user**, show an "Edit profile" button routing
  to the Profile tab instead of any edit controls (this screen is never editable).

### `social_screen.dart` — replaces the `/social` placeholder

- Debounced search field (`ilike` on display name)
- Results list: avatar + name + rank chip → tap → `/play/player/:id`
- Excludes the current user
- Loading, empty ("Search for players"), and no-results states

---

## Navigation & error handling

- New route `GoRoute('/play/player/:id')` over the root navigator with a back
  button (mirrors existing `/play/court/:id`).
- Loading spinner, error frame ("Couldn't load player"), and empty states
  throughout.
- All colors from `Theme.of(context).colorScheme`; 24px radius; fonts via theme —
  per the dinksync-ui skill. No hardcoded hex except where the existing card
  header already does (green gradient constants).

---

## Testing

- **Rank helper**: boundary values (899/900, 1199/1200, 1499/1500, 1799/1800,
  and extremes) map to the correct tier.
- **Win-rate math**: zero games → `null`/"—" (no division by zero); typical
  cases compute the right percentage.
- **Repository parsing**: `PublicProfile` / `PlayerStats` / `RecentMatch` parse
  correctly from representative Supabase JSON rows, including null `avatar_url`.

`flutter analyze` clean and `flutter test` green before the sub-project is done.

---

## Out of scope (later sub-projects)

- Writing matches/results (Find Match)
- Friends / following actions on the profile (sub-project 3)
- Chat entry from a profile (sub-project 4)
- The network activity feed (sub-project 5)

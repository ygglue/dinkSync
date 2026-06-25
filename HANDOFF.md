# Handoff — feat/find-match

**Branch:** `feat/find-match` (off `main`)

## What's done

- **Matchmaking RPCs** (`0015`): `assign_free_slots`, `form_groups_for_court`, `matchmake_sweep` — pg_cron runs sweep every minute
- **MMR fallback** (`0016`): if < 4 players fit in the MMR band, falls back to the 4 oldest open requests
- **Realtime publications** (`0017`): `matchmaking_requests`, `match_groups`, `match_group_members`, `court_slots`, `queue_entries` added to `supabase_realtime`
- **Flutter**: `MatchmakingNotifier` (idle → searching → matched), `_SearchingCard` with live queue count + cancel, `_MatchFoundSheet` bottom sheet

## To apply migrations on a new device

```bash
cd supabase && supabase db push
```

Or paste each `supabase/migrations/001{5,6,7}_*.sql` into the Supabase SQL editor in order.

## Manual Realtime toggle (if db push doesn't cover it)

Dashboard → Database → Replication → supabase_realtime → enable:
`matchmaking_requests`, `match_groups`, `match_group_members`, `court_slots`, `queue_entries`

## What's next

- **Score entry + Elo update** — player enters result, opponent confirms, MMR recalculates (`enter_score()` RPC)
- **Staff slot management** — staff opens/closes slots, calls next group manually
- **Match history** — show past matches + MMR delta on profile

# Design — App Shell + Owner Court Setup (Phase 1, slice 1)

**Date:** 2026-06-21
**Status:** Approved (brainstorming) — pending implementation plan
**Branch (suggested):** `feature/app-shell-owner-flow`

## 1. Goal

Give dinkSync a real navigation shell and the first management feature: a court
owner can set up a venue, subscribe (mock payment), and see a management
dashboard. Players keep a Play-mode home. Users who manage a court switch between
**Play** and **Court Management** via a persisted top-bar mode dropdown.

This is the first slice of Phase 1 ("Owner + Court Setup"). It deliberately
defers staff management, the platform-admin view, and the player core loop.

## 2. Scope

**In scope**
- Role/capability detection + a persisted Play/Management mode switcher.
- Two navigation shells (Play with bottom nav; Management) wired in `go_router`.
- Owner court onboarding (create venue) → subscription (mock) → dashboard.
- `0008` migration: `create_court` + `subscribe_court` RPCs + tightened `courts`
  visibility (only subscribed/`active` courts are publicly discoverable).
- Empty-state management dashboard + minimal edit-court.
- Tests consistent with the repo (pure-logic/widget; no live Supabase).

**Out of scope (deferred)**
- Staff management screen (DB already supports staff).
- Platform-admin court list / subscription oversight.
- Player core loop (find courts, pay entry, matchmaking, scoring).
- Google Maps picker / geocoding (lat/lng stay optional, captured as free-text address).
- Real payment provider (region/provider undecided — AGENTS §10.5).
- Multi-court ownership (one venue per owner for now; data model already allows more).

## 3. Role & mode model

Roles are not a single column; they are derived:
- **Admin** — `profiles.is_platform_admin`.
- **Manager** — owns or staffs ≥1 court (`court_members` rows for the user).
- **Player** — everyone (baseline).

A user can be several at once (an owner is also a player).

**New providers (`lib/data/` or `lib/features/shell/`):**
- `capabilitiesProvider` (FutureProvider) → `{ isAdmin, isManager }`, read once
  after sign-in from `profiles` + `court_members`. Drives mode-dropdown visibility.
- `appModeProvider` (StateNotifier, persisted via `shared_preferences`) →
  `AppMode.play | AppMode.management`. Defaults to `play` on first run. Only
  meaningful when `isManager`.

The mode dropdown renders in the top app bar of **both** shells, but **only when
`isManager`**. Flipping it persists the choice and navigates to the other shell.

## 4. Navigation architecture

`go_router` with two shells (chosen approach: two shells + persisted mode):

- **Play shell** — `StatefulShellRoute` with a bottom nav:
  - `/play` — Play tab (empty-state placeholder for now).
  - `/social` — Social tab (empty-state placeholder for now).
  - `/profile` — existing `ProfileScreen`, plus a **"Own a court? Set it up"**
    entry point (first-time host path; see below).
- **Management shell** — `/manage`:
  - No venue owned → **court onboarding**.
  - Venue owned, `suspended` → dashboard with "Subscription inactive — Subscribe" banner.
  - Venue owned, `active` → full dashboard.

**Redirect / guards** (extends the current `redirect` in `router.dart`):
- Signed-out → `/auth`; signed-in on `/auth` → home.
- On launch: if `isManager && mode == management` → `/manage`, else `/play`
  (the default Play-shell tab).
- `/manage` is reachable by **any signed-in user** (so a non-manager can create
  their first court). The dashboard content gates on whether a venue exists; the
  *dropdown* gates on `isManager`.

**First-time host flow:** a player (not yet a manager) taps "Own a court? Set it
up" on the Profile tab → `/manage` → onboarding. After `create_court` succeeds,
`capabilitiesProvider` is invalidated → `isManager` becomes true → dropdown
appears and mode is set to `management`.

The existing `_AuthListenable` stays; the router also reacts to auth changes as today.

## 5. Owner flow

### 5.1 Court onboarding (`features/owner/court_onboarding_screen.dart`)
Form fields:
- **Name** (required, non-empty).
- **Entry fee** — entered in dollars, stored as integer cents (`entry_fee_cents`).
- **Number of courts/slots** — integer, default 1, must be > 0.
- **Address** — optional free-text (`courts.address`); lat/lng left null.
- Currency defaults to `PHP` (Philippines-first; the DB column still defaults to
  `USD`, so the form/RPC passes `PHP` explicitly).

Submit → `create_court` RPC → on success, route to the Subscription page for the
new court. Styled per the `dinksync-ui` skill (24px rounded, kBrandGreen CTA,
tonal inputs). Busy state disables the form; failures show inline error.

Onboarding is a **two-step gate**: creating the court (status `suspended`) does
**not** publish it. The court is **hidden from discovery until an active
subscription exists** (see 5.2 and §6). If the owner abandons before subscribing,
the court stays `suspended`/hidden and they resume from the dashboard banner.

### 5.2 Subscription (`features/owner/subscription_screen.dart`)
- Two plans: **Monthly** and **Yearly**, in **PHP**, with startup-friendly
  placeholder prices: `monthly = 99900` centavos (₱999.00) and
  `yearly = 999000` centavos (₱9,990.00, ~2 months free) — adjustable.
- "Subscribe" → `MockPaymentService` (auto-succeeds) → `subscribe_court` RPC →
  court becomes `active` → **now discoverable** → dashboard.
- Reachable from a `suspended` dashboard banner (reactivation uses the same page).
- This step is what publishes the court; without it the venue is invisible to players.

### 5.3 Management dashboard (`features/owner/owner_dashboard_screen.dart`)
- Header: court name + status chip; entry-fee and #-slots summary.
- If `suspended`: prominent "Subscription inactive — your court is hidden from
  players. Subscribe to publish it" banner → 5.2.
- Three **empty-state** metric cards: **Today's revenue**, **Players today**,
  **Active queue** (real data lands with the player loop; for now they render
  zero/empty states and tolerate restricted/empty reads).
- **Edit court** (secondary action): edit name / entry fee / address only, via a
  direct `courts` update (allowed by `courts_update_owner`). Changing slot count
  is deferred (touches `court_slots`).

### 5.4 Repository (`features/owner/court_repository.dart`)
- `ownerCourtProvider` (FutureProvider) → owner's venue or `null`
  (`courts where owner_profile_id = uid`; `courts_select` is public).
- `createCourt({name, entryFeeCents, currency, numCourts, address})` →
  `supabase.rpc('create_court', …)`; invalidates `ownerCourtProvider` +
  `capabilitiesProvider`.
- `subscribeCourt({courtId, plan})` → runs `MockPaymentService`, then
  `supabase.rpc('subscribe_court', …)`; invalidates `ownerCourtProvider`.
- `updateCourt(...)` → direct `courts` update for the edit action.

## 6. Database changes — migration `0008_owner_court_setup.sql`

Two `plpgsql security definer` functions (set `search_path` explicitly, verify
`auth.uid()` inside — same pattern as existing helpers/seed) **plus a tightened
`courts` visibility policy**. `0003` remains reserved for matchmaking.

**`create_court(p_name text, p_entry_fee_cents int, p_currency text, p_num_courts int, p_address text)`**
- Asserts `auth.uid()` is not null.
- Inserts `courts` with `owner_profile_id = auth.uid()`, `status = 'suspended'`.
- Inserts the owner's `court_members` row (`role = 'owner'`, `can_accept_payment = true`).
- Inserts `p_num_courts` `court_slots` labelled "Court 1" … "Court N" (`status = 'open'`).
- Returns the new court id (or row). Atomic.
- Rationale: client cannot insert the first owner `court_members` row
  (`is_court_owner` chicken-and-egg) nor `court_slots` (no insert policy).

**`subscribe_court(p_court_id uuid, p_plan text)`**
- Asserts caller owns `p_court_id` (`courts.owner_profile_id = auth.uid()`).
- Validates `p_plan ∈ ('monthly','yearly')`; derives `amount_cents` and currency
  (`PHP`) from a **canonical server-side price map** (client never sends the price).
- Inserts a `payments` row (`kind = 'subscription'`, `status = 'paid'`,
  `provider = 'mock'`, `payer_profile_id = auth.uid()`, `payee_court_id = p_court_id`,
  the derived amount).
- Upserts the `subscriptions` row (`plan`, `status = 'active'`, `amount_cents`,
  `provider = 'mock'`).
- Updates `courts.status = 'active'`.
- Returns success. Atomic.
- Rationale: `subscriptions` writes are RPC-only by policy; pricing is
  authoritative server-side so the client can't set its own amount.

Placeholder prices (`monthly = 99900`, `yearly = 999000` centavos = ₱999 / ₱9,990,
currency `PHP`) live in the RPC and are adjustable later. The client sends only
the chosen plan.

**Tighten `courts` visibility (replace `courts_select`)** — a court must have an
active subscription (i.e. `status = 'active'`) to be discoverable:

```sql
drop policy "courts_select" on public.courts;
create policy "courts_select" on public.courts for select
  using (
    status = 'active'                 -- public sees only published courts
    or public.is_court_member(id)     -- owner/staff see their own (any status)
    or public.is_platform_admin()     -- admin sees all
  );
```

This enforces "subscribed ⇒ visible" at the database, before the player
discovery screen exists. `ownerCourtProvider` still works because the owner is a
`court_member` of their own (even `suspended`) court.

## 7. Error handling & edge cases

- Onboarding submit: spinner + disabled form while busy; RPC failure → inline
  error, no navigation. Validation as in 5.1.
- Subscription: mock payment can't really fail, but the RPC can — show inline
  error, leave court `suspended`, allow retry.
- `ownerCourtProvider` / `capabilitiesProvider` load error → screen shows an
  error state with Retry.
- `shared_preferences` unavailable / first run → default `AppMode.play`.
- Non-manager lands on `/manage` with no court → onboarding (expected, not error).
- User becomes a manager mid-session (just created a court) → invalidate
  `capabilitiesProvider` so the dropdown appears and mode flips to management.
- Suspended court (unpaid or later canceled) → dashboard banner + subscribe path.

## 8. Testing (no live Supabase, per repo convention)

- `appModeProvider` persistence — set → read-back with
  `SharedPreferences.setMockInitialValues`.
- `capabilitiesProvider` derivation — admin/manager from sample inputs.
- Onboarding widget — empty name blocks submit; busy disables the button;
  dollars→cents conversion is correct.
- Subscription widget — plan selection + subscribe enabled/disabled states.
- Dashboard widget — renders empty-state cards; shows the suspended banner when
  `status == 'suspended'`.
- `create_court` / `subscribe_court` param-building unit tests.
- Live RPC round-trips verified manually (consistent with current approach),
  including the visibility rule: a `suspended` court is hidden from a
  non-member, visible to its owner, and becomes visible after `subscribe_court`.

## 9. Dependencies & file layout

**New dependency:** `shared_preferences` (mode persistence).

```
app/lib/
  app/router.dart                         (edit: shells, routes, redirect/guards)
  data/
    capabilities_provider.dart            (new)
    app_mode_provider.dart                (new; shared_preferences-backed)
  features/
    shell/
      play_shell.dart                     (new; StatefulShellRoute scaffold + bottom nav)
      mode_dropdown.dart                  (new; top-bar Play/Management switch)
      placeholder_tab.dart                (new; Play/Social empty states)
    owner/
      court_repository.dart               (new)
      court_onboarding_screen.dart        (new)
      subscription_screen.dart            (new)
      owner_dashboard_screen.dart         (new)
    profile/profile_screen.dart           (edit: "Own a court? Set it up" entry)
supabase/migrations/0008_owner_court_setup.sql  (new: RPCs + courts visibility policy)
app/test/…                                (new tests per §8)
```

## 10. Open items / future

- Real payment provider + subscription lifecycle (renewals, past_due automation).
- Staff management screen; platform-admin court/subscription oversight.
- Player core loop (consumes the courts/slots created here).
- Multi-court ownership + a court picker.
- Map-based location + discovery.

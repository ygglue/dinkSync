# dinkSync — MVP Plan

> A pickleball social app + CRM. Players find a court, pay entry, and get
> matched into a 4-player doubles game by skill. Court owners list courts,
> pay a subscription, manage staff, and track revenue. Admins run the
> platform.

---

## 0. Stack decisions (locked)

| Layer | Choice | Notes |
|---|---|---|
| Mobile | **Flutter** | iOS + Android from one codebase |
| Backend | **Pure Supabase** | Postgres + Auth + Realtime + Storage + Edge Functions |
| Data access | **`supabase_flutter` + RLS** | Client talks to Postgres directly; Postgres enforces security |
| Server logic | **Postgres RPC (plpgsql)** called from thin Edge Functions | Matchmaking, payments, queue assignment — anything that can't be a single authorized query |
| Matchmaking trigger | **`pg_cron` sweep (~5s)** | Background job forms groups + assigns slots; players just wait |
| MMR | **Simple Elo** | `profiles.mmr` int, default 1000, K=32 |
| Auth | **Supabase Auth** | Email + password + Google OAuth (Apple deferred until Apple Developer account obtained); JWT, RLS ties rows to `auth.uid()` |
| Realtime | **Supabase Realtime** | Postgres changes broadcast on channels (queue position, group formed, slot assigned) |
| State (Flutter) | **Riverpod** | Light for this scope |
| Maps | `google_maps_flutter` | Court discovery by location |
| Payments | **`PaymentService` interface → Mock for MVP** | Swap to real provider (Stripe Connect / GCash / etc.) once launch region is decided |
| Push | **FCM** via `firebase_messaging` | "You're on Court 2" must work in background |
| File storage | **Supabase Storage** | Avatars, court photos |

**Explicitly NOT in the stack:** Drizzle, a custom API server, Socket.io. We stay
fully in Supabase's sweet spot — no servers to run, no realtime to build, RLS
does the security work. We trade Drizzle's TS query ergonomics for this
simplicity (a deliberate, accepted trade).

---

## 1. Scope

### In scope (the MVP)
- Player finds a court, pays entry, gets matched into a 4-player game.
- Player can invite one partner or go solo; the system fills the rest by MMR.
- Formed groups of 4 queue for the next available court slot.
- Owner lists a court, sets entry fee + number of courts, pays subscription.
- Owner manages staff (grant `can_accept_payment`), sees revenue + player list.
- Staff takes payments (incl. offline cash/e-wallet) and operates the queue.
- Admin sees all courts, subscriptions, and platform revenue.

### Out of scope (defer)
- Tournaments / leagues / ladders
- Future time-slot scheduling (MVP is "show up, match up, play")
- Social feed / following / DMs beyond the match invite
- Real payment provider wiring (stubbed for MVP)
- Owner payouts to their bank (we track balance; manual for MVP)
- Glicko-2 / uncertainty-based matchmaking (Elo first)
- Friends list / social graph

---

## 2. The core loop

```
Player opens app → picks a court (by location/name) → pays entry
  → "Bring a partner?" [Invite] or [Solo]
  → matchmaking runs (cron sweep) → 4 players formed into a Group
  → Group waits in court queue → slot opens → "Court 2, you're up"
  → match played → result entered → MMR updates (Elo)
```

Everything else (owner dashboards, staff tools, subscriptions) is plumbing
around this loop. **If the loop doesn't feel great, nothing else matters.**

---

## 3. Data model (Postgres)

All money stored as integer cents + ISO currency code. Timestamps are
`timestamptz`. IDs are `uuid` PKs (default `gen_random_uuid()`).

```sql
-- 1:1 with auth.users
profiles
  id              uuid  PK  = auth.users.id
  display_name    text
  avatar_url      text
  mmr             int   default 1000      -- Elo
  is_platform_admin bool default false
  created_at      timestamptz

-- a physical venue an owner runs
courts
  id              uuid  PK
  owner_profile_id uuid  FK profiles    -- denormalized owner (for RLS speed)
  name            text
  lat             numeric(9,6)
  lng             numeric(9,6)
  address         text
  entry_fee_cents int
  currency        text                  -- ISO 4217
  num_courts      int
  status          text  default 'active' -- active | suspended | offboarded
  created_at      timestamptz

-- owner + staff of a court (role + capabilities)
court_members
  court_id          uuid  FK courts
  profile_id        uuid  FK profiles
  role              text              -- owner | staff
  can_accept_payment bool
  added_by          uuid  FK profiles
  PK (court_id, profile_id)

-- owner pays admin to keep court on the app
subscriptions
  id                uuid  PK
  court_id          uuid  FK courts
  plan              text              -- monthly | yearly
  status            text              -- active | past_due | canceled
  current_period_end timestamptz
  amount_cents      int
  currency          text
  provider          text              -- mock | stripe | gcash | ...
  provider_sub_id   text
  created_at        timestamptz

-- a player wanting a game (the matchmaking input)
matchmaking_requests
  id                uuid  PK
  court_id          uuid  FK courts
  profile_id        uuid  FK profiles   -- initiator
  party_size_wanted smallint            -- 1 (solo) | 2 (with partner)
  partner_profile_id uuid  FK profiles  -- nullable; set if inviting
  status            text  default 'open'-- open | matched | expired | canceled
  mmr_at_request    int                 -- snapshot for band calc
  created_at        timestamptz

-- the formed group of 4
match_groups
  id          uuid  PK
  court_id    uuid  FK courts
  status      text                  -- forming | queued | assigned | playing | done
  slot_label  text                  -- denormalized "Court 2" for display
  created_at  timestamptz

match_group_members
  match_group_id  uuid  FK match_groups
  profile_id      uuid  FK profiles
  is_initiator    bool
  is_invited_partner bool
  PK (match_group_id, profile_id)

-- a physical court surface + its current state
court_slots
  id              uuid  PK
  court_id        uuid  FK courts
  label           text              -- "Court 1", "Court 2"
  status          text  default 'open'  -- open | occupied | closed
  current_group_id uuid  FK match_groups  -- nullable
  updated_at      timestamptz

-- a group waiting for a slot at a court
queue_entries
  match_group_id uuid  PK  FK match_groups
  court_id       uuid  FK courts
  position       int               -- 1-based, recomputed on changes
  enqueued_at    timestamptz

-- the played game + result
matches
  id             uuid  PK
  match_group_id uuid  FK match_groups
  court_id       uuid  FK courts
  played_at      timestamptz
  status         text              -- pending_confirm | completed | disputed
  winning_team   smallint          -- 1 | 2

match_results
  match_id    uuid  FK matches
  profile_id  uuid  FK profiles
  team        smallint             -- 1 | 2
  result      text                 -- win | loss
  mmr_before  int
  mmr_after   int
  PK (match_id, profile_id)

-- every money event (entry fee + subscriptions + offline)
payments
  id               uuid  PK
  payer_profile_id uuid  FK profiles
  payee_court_id   uuid  FK courts
  kind             text            -- entry | subscription
  amount_cents     int
  currency         text
  status           text  default 'pending'  -- pending | paid | failed | refunded
  provider         text            -- mock | stripe | gcash | offline
  provider_ref     text
  collected_by_member_id uuid  FK court_members  -- for offline (staff-marked)
  created_at       timestamptz
```

### Key design choices
- **`court_members` not separate per-role tables.** One owner + N staff, with
  `can_accept_payment` flag — that's how staff "can accept payment" without a
  separate model.
- **`is_platform_admin` on profile**, not a separate admin table. Boolean + RLS.
- **`profiles.owner_profile_id` denormalized** on `courts` so owner-scoped RLS
  policies are fast (no join).
- **Money as cents + ISO currency** from day one — avoids float bugs and a
  painful migration.
- **`payments` is polymorphic by `kind`** (entry | subscription), with
  `collected_by_member_id` for offline (staff-marked) payments.

---

## 4. Role-by-role flows

### Player
1. Browse courts (map + list), see entry fee + live queue depth.
2. Pay entry → `payments` row (`kind=entry`, `payee_court_id`).
3. Choose **partner** (creates `matchmaking_requests` with
   `party_size_wanted=2`, `partner_profile_id` set, partner must accept) or
   **solo** (`party_size_wanted=1`).
4. See "searching…" → "Group formed" → "Position 2 in queue" → "You're on
   Court 2" (all via Realtime).
5. After match: one player enters score → opposing team confirms → Elo updates.

### Court Owner
1. Onboard: create court, set entry fee + number of courts, subscribe.
2. Dashboard: today's revenue, players today, active queue, subscription status.
3. Player list: everyone who's ever played, with visits + MMR.
4. Add staff (by username/email), grant `can_accept_payment`.
5. Open/close slots (e.g., end of night).

### Court Staff
- Court-scoped view of owner tools minus billing/subscription.
- Take in-person payment (cash/e-wallet) and mark player paid (offline
  `payments` row, `collected_by_member_id` = self).
- Operate the queue: call next group to a slot ("Court 2, next up").

### Admin
- All courts + subscription statuses.
- Platform revenue (sum of `payments` where `kind='subscription'`).
- Toggle a court's `status` (suspend/offboard) if needed.

---

## 5. The two hard parts

### 5a. Matchmaking — `pg_cron` sweep

A Postgres function `matchmake_sweep()` runs every ~5s via `pg_cron`. Pure SQL
on the server — no client triggers, no race conditions across players.

**Algorithm (intentionally simple, greedy):**
1. For each court with open `matchmaking_requests` (status=`open`):
2. Sort requests by wait time (oldest first).
3. **MMR band**: start at ±50, expand by +25 every 30s of wait, capped ±300.
   (Prevents new/stale players waiting forever while keeping games fair.)
4. Greedily pack into groups of 4:
   - A partner pair (`party_size_wanted=2`) counts as 2 and must stay together.
   - Fill remaining slots from solo (`party_size_wanted=1`) requests, nearest
     MMR first within the band.
5. When a group hits 4:
   - Create `match_groups` (status=`queued`).
   - Insert `match_group_members` for all 4 (initiator, partner, fillers).
   - Set the 4 `matchmaking_requests` → `status=matched`.
   - Insert `queue_entries` row (position recomputed).
6. Realtime broadcasts the group-formed event; each member's app, subscribed
   to its `profile_id` channel, updates.

```sql
-- Sketch
create or replace function matchmake_sweep() returns void as $$
declare
  c record;  -- court
begin
  for c in select id from courts where status = 'active' loop
    -- 1) try to assign any queued group to a free slot
    perform assign_free_slots(c.id);

    -- 2) form new groups from open requests using MMR band
    perform form_groups_for_court(c.id);
  end loop;
end;
$$ language plpgsql;

-- pg_cron schedule (Supabase: enable extension, then)
select cron.schedule('matchmake-sweep', '*/5 seconds', 'select matchmake_sweep()');
```

Tunable constants live at the top of the function (band start/step/cap, sweep
interval) so they're easy to dial post-launch.

### 5b. Queue → slot assignment

- Each physical court has N `court_slots` (`open` | `occupied` | `closed`).
- `assign_free_slots(court_id)`:
  - Find slots with `status=open`.
  - Pop the oldest `queue_entries` group for that court (position=1).
  - Set slot `status=occupied`, `current_group_id=<group>`, delete its
    `queue_entries` row, recompute remaining positions.
  - Set group `status=assigned`, `slot_label=<slot.label>`.
- Realtime on the `court_slots` + `match_groups` channels updates apps live:
  the queue list, each player's position, and the "you're up" call.

**Triggers for `assign_free_slots`:** (a) the sweep itself, every 5s;
(b) staff manually opening a slot or marking a match done; (c) a match
completing. Any of these can call the function.

---

## 6. Auth & RLS

**Auth:** Supabase Auth (email + password, Google OAuth; email+OTP remains for password reset only). JWT identity; RLS ties rows to
`auth.uid()`.

**RLS policies** (enforced in Postgres — even a malicious client can't bypass):

```sql
profiles
  -- self: full write of own (non-admin) fields
  -- everyone: read public fields (id, display_name, avatar_url, mmr)

courts
  -- everyone: read where status in (active)   -- browse/discovery
  -- owner (via court_members.role='owner'): insert/update own courts

court_members
  -- owner of court: insert/update
  -- members: read own court's members

payments
  -- payer: read own
  -- court_members (court = payee): read
  -- is_platform_admin: read all

subscriptions
  -- owner of court: read own
  -- is_platform_admin: read all

matchmaking_requests / match_groups / match_group_members / queue_entries
  -- participant: read own (where profile_id = auth.uid())
  -- court_members: read own court's
  -- writes happen ONLY via RPC (service-role bypasses RLS safely)

court_slots
  -- everyone: read (queue display)
  -- court_members: update (open/close, assign)

matches / match_results
  -- participants: read own
  -- court_members: read own court's
  -- writes ONLY via RPC (score entry → Elo)
```

**Principle:** client-initiated writes go through `supabase_flutter` only for
trivial self-service rows (e.g., creating a `matchmaking_requests`). Anything
involving matchmaking, queue, score, or money is an **RPC** so a service-role
key (server-side only) can enforce atomicity + invariants.

---

## 7. Payments (abstracted, stubbed)

One interface, one stub provider, swap later:

```dart
abstract class PaymentService {
  /// Player pays entry to a court.
  Future<Payment> createEntryPayment({
    required String courtId,
    required String playerId,
    required int amountCents,
    required String currency,
  });

  /// Owner subscribes (pays admin).
  Future<Subscription> createOwnerSubscription({
    required String courtId,
    required String plan, // monthly | yearly
  });

  /// Staff marks an offline (cash / e-wallet) payment as collected.
  Future<Payment> markPaidOffline({
    required String paymentId,
    required String collectedByMemberId,
  });
}

class MockPaymentService implements PaymentService { /* auto-succeeds */ }
```

- **MVP**: `MockPaymentService` auto-succeeds → full loop demoable end-to-end.
- **Real provider** is a one-class swap once the launch region is known:
  - US/global → **Stripe Connect** (marketplace payouts to owners).
  - Philippines → **GCash / Maya**.
  - Brazil → **Pix**.
  - etc.
- **Offline payments are first-class**: staff at the desk taking cash/e-wallet
  create a `payments` row with `provider='offline'`, `collected_by_member_id`
  set to themselves. This path must work from day one.

---

## 8. Repository structure

```
dinkSync/
├── app/                          # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart              # router + theme
│   │   ├── config/               # env (supabase url/keys)
│   │   ├── data/
│   │   │   ├── supabase_client.dart
│   │   │   └── models/           # generated/typed row classes
│   │   ├── features/
│   │   │   ├── auth/             # login, signup, OTP
│   │   │   ├── player/           # browse, pay, match, queue
│   │   │   ├── owner/            # dashboard, staff mgmt, players
│   │   │   ├── staff/            # payments, queue operator
│   │   │   ├── admin/            # courts, subs, revenue
│   │   │   └── shared/           # court card, mmr chip, etc.
│   │   ├── services/
│   │   │   ├── payment_service.dart      # abstract + mock impl
│   │   │   ├── matchmaking_service.dart  # calls rpc + realtime
│   │   │   └── push_service.dart         # FCM
│   │   └── widgets/
│   ├── test/
│   └── pubspec.yaml
│
├── supabase/                     # Supabase project (CLI)
│   ├── migrations/
│   │   ├── 0001_init_schema.sql
│   │   ├── 0002_rls_policies.sql
│   │   ├── 0003_matchmaking_rpc.sql      # matchmake_sweep(), assign_free_slots()
│   │   ├── 0004_oauth_metadata.sql       # updates handle_new_user() to use OAuth profile data
│   │   ├── 0005_elo_rpc.sql              # enter_score() → updates mmr
│   │   └── 0006_payment_rpc.sql
│   ├── functions/
│   │   ├── matchmake-tick/      # thin Edge Fn → rpc('matchmake_sweep')
│   │   ├── charge-entry/        # thin Edge Fn → PaymentService.createEntryPayment
│   │   └── charge-subscription/ # thin Edge Fn → owner subscription
│   ├── seed.sql                 # dev seed: 1 court, 4 players, open slots
│   └── config.toml
│
├── docs/
│   ├── PLAN.md → (this file, also at root)
│   └── DECISIONS.md             # ADR-style log of future choices
│
└── PLAN.md                      # this file
```

**Conventions:**
- Each migration is one numbered SQL file; Supabase CLI applies them in order.
- Edge Functions are **thin**: parse input → call one RPC with the service-role
  key → return JSON. All business logic lives in plpgsql RPCs (testable,
  atomic, no client duplication).
- `DECISIONS.md` captures future decisions (e.g., which real payment provider)
  as short ADR entries.

---

## 9. Build phases

Each phase is **independently demoable**. Don't move on until the current
phase's demo works.

### Phase 0 — Foundation (week 1)
- Supabase project + CLI initialized (`supabase init`, `supabase link`).
- `0001_init_schema.sql` (all tables) + `0002_rls_policies.sql`.
- Enable `pg_cron`, `pgjwt` extensions.
- Flutter scaffold: router, theme, auth screens (Sign In / Sign Up with email+password + Google OAuth), profile. Web platform wired up (passkey SDK in `web/index.html`).
- `MockPaymentService` skeleton.
- **Demo:** log in, see own profile, prove RLS blocks cross-user reads.

### Phase 1 — Owner + court setup (week 2)
- Owner onboarding: create court, set fee + `num_courts`.
- Owner dashboard (empty states wired), add staff, grant `can_accept_payment`.
- `0003_matchmaking_rpc.sql` stub (function exists, returns void).
- Admin view: list all courts, subscription status.
- `seed.sql`: 1 court, 1 owner, 2 staff, 8 players.
- **Demo:** owner creates a court, admin sees it, owner adds a staff member.

### Phase 2 — The core loop, single court (weeks 3–4) ← the bet
- Player: browse → pay (mock) → solo/partner request.
- `matchmake_sweep()` + `assign_free_slots()` fully implemented.
- `pg_cron` schedule enabled.
- Realtime: queue position, group formed, slot assigned.
- Staff: open/close slot, call next group.
- Score entry (`0004_elo_rpc.sql`): one player enters → opponent confirms →
  Elo updates.
- **Demo:** 4 phones/devices, full match lifecycle live, queue working.

### Phase 3 — Money & subscriptions (week 5)
- Real `PaymentService` once region decided (or keep Mock if still TBD).
- Owner subscription flow (`0005_payment_rpc.sql`): owner → admin.
- Owner revenue + player list (reads from `payments` + `match_results`).
- Staff offline payment marking.
- **Demo:** owner subscribes, players pay, revenue rolls up correctly.

### Phase 4 — Hardening (week 6)
- FCM push: "group formed", "you're on Court 2", "match ready to confirm".
- Deep links from push into the right screen.
- Matchmaking tuning (band constants, sweep interval) against real-ish load.
- Edge cases: cancellations, no-shows, expired requests, partner declines.
- Basic admin tooling (suspend court, refund).
- **Ship to one court as a pilot.**

---

## 10. Open decisions (flagged, not blocking)

1. **Match entry model** — per-match pay vs. day-pass/session. **MVP default:
   per-match** (simpler). Revisit in Phase 3.
2. **Score entry** — who enters it. **MVP default: a player enters, opposing
   team confirms** (honor system + confirmation).
3. **Partner invite** — friend-list vs. share-link/QR. **MVP default:
   share-link/QR** (no friends feature in MVP).
4. **Court slots** — fixed time windows vs. free-form "next available". **MVP
   default: free-form** (staff controls the slot); scheduling is a later
   feature.
5. **Payment region/provider** — drives the real `PaymentService` impl. The
   most important open question for Phase 3.

---

## 11. Non-goals & risks

**Non-goals (re-stated, for focus):** no tournaments, no scheduling, no social
feed, no real payments wiring (yet), no owner bank payouts, no Glicko-2.

**Top risks:**
- **Matchmaking under load** — greedy + MMR band is simple but may feel slow or
  unfair with few players. Mitigation: tunable constants, pilot at one court.
- **Cold-start problem** — a court with <4 active players has no matches.
  Mitigation: expose live queue depth so players know to wait; consider an
  "open play" fallback later.
- **Offline payment abuse** — staff marking cash payments is trust-based.
  Mitigation: audit log (`collected_by_member_id`, timestamps); owner sees all.
- **Supabase Realtime fan-out** — at scale, broadcasting every queue change to
  every player at a court could get noisy. Mitigation: filter channels by
  court, only subscribe to relevant rows; revisit in Phase 4.

---

## Next step

If this plan is approved, **Phase 0** is the first concrete chunk: stand up
the Supabase project, write `0001_init_schema.sql` + `0002_rls_policies.sql`,
enable `pg_cron`, and scaffold the Flutter app with auth + profile. This
de-risks the whole project (data model + auth + RLS) before any flashy
features.

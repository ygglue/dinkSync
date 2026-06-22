# Game Lobby + Court Booking — Design

**Date:** 2026-06-22
**Status:** Approved (design)

## Goal

Redesign `/play` from a court discovery list into a game lobby, and build the first
player action within it: **Book a Court** (private slot reservation with a
visual timeline). "Find Match" (matchmaking) is scaffolded but deferred.

## Scope

**In scope**

- Replace the `/play` shell tab with a `LobbyScreen`.
- Court picker: reuse `CourtListScreen` in picker mode (new optional `onSelect`
  callback); wrap in a new full-screen route `/play/courts`.
- **Book a Court** flow: `/play/custom` full-screen route — day strip, slot tabs,
  hour-block timeline, range selection, mock payment.
- DB: `courts.custom_fee_cents`, new `custom_bookings` table, `payments.kind`
  extended, `book_custom_slot` RPC.
- Owner can set `custom_fee_cents` — when null, "Book a Court" is disabled in the
  lobby (venue has not enabled private bookings).

**Out of scope (deferred)**

- "Find Match" matchmaking action (button visible but disabled).
- Partner invite by code (slot visible but non-functional).
- Operating hours configuration (timeline always shows 06:00–22:00).
- Cancelling or managing existing bookings.
- Linking `custom_bookings` to live `court_slots.status` (managed manually by staff).
- Owner `custom_fee_cents` configuration UI (set directly in DB for now).

## Architecture

### Routing changes

| Route | Navigator | Purpose |
|---|---|---|
| `/play` | Shell branch | `LobbyScreen` (body-only, replaces court list) |
| `/play/courts` | Root | `CourtPickerScreen` — full-screen, wraps `CourtListScreen` in picker mode |
| `/play/court/:id` | Root | `CourtDetailScreen` — unchanged |
| `/play/custom` | Root | `CourtBookingScreen` — new, receives `Court` via `extra` |

`/play/courts` and `/play/custom` use `parentNavigatorKey: _rootNavigatorKey`
(same pattern as `/manage/edit`).

### File layout

```
app/lib/
  data/
    court.dart                     # + customFeeCents field
  features/
    discovery/
      court_list_screen.dart       # + optional onSelect param
      court_picker_screen.dart     # NEW: Scaffold wrapper for picker mode
      discovery_repository.dart    # unchanged
      court_detail_screen.dart     # unchanged
    lobby/
      lobby_screen.dart            # NEW: /play body
      booking_repository.dart      # NEW: custom_bookings + slots provider
      court_booking_screen.dart    # NEW: /play/custom
  app/
    router.dart                    # + /play/courts, /play/custom routes; /play -> LobbyScreen
```

---

## Components

### `LobbyScreen` (`/play` body)

`ConsumerStatefulWidget`. Local state: `Court? _selectedCourt`.

**Layout (top to bottom):**

1. **Court selector row** — full-width `InkWell` card showing the selected court's
   name, or "Select a court" placeholder. Trailing `Icons.chevron_right`. Tapping
   calls:
   ```dart
   final court = await context.push<Court>('/play/courts');
   if (court != null) setState(() => _selectedCourt = court);
   ```

2. **Player slots row** — two equal-width cards side by side:
   - **You** — avatar placeholder + display name from Riverpod profile state.
   - **Partner** — `Icons.person_add_outlined` + "Invite partner" label, greyed
     out (`onSurfaceVariant` colour), non-tappable for now.

3. **Action row** — two buttons, full width split 2:1:
   - **Find Match** — `FilledButton`, always disabled (`onPressed: null`).
   - **Book a Court** — `OutlinedButton`, enabled only when `_selectedCourt != null`
     AND `_selectedCourt!.customFeeCents != null`. Tapping:
     ```dart
     context.push('/play/custom', extra: _selectedCourt);
     ```

### `CourtListScreen` update

Add optional parameter:
```dart
class CourtListScreen extends ConsumerStatefulWidget {
  const CourtListScreen({super.key, this.onSelect});
  final void Function(Court court)? onSelect;
}
```

When `onSelect` is non-null (picker mode):
- Card body tap → `onSelect!(court)` (no navigation to detail).
- An `IconButton(icon: Icon(Icons.info_outline))` appears in the top-right of
  each card. Tapping it pushes `/play/court/${court.id}` as usual.

When `onSelect` is null (normal mode): existing behaviour unchanged.

### `CourtPickerScreen` (`/play/courts`)

New file in `features/discovery/`. Full-screen `Scaffold`:
```dart
class CourtPickerScreen extends StatelessWidget {
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Select a court')),
    body: CourtListScreen(
      onSelect: (court) => context.pop(court),
    ),
  );
}
```

### `Court` model update

Add field:
```dart
final int? customFeeCents;
```

`fromMap`:
```dart
customFeeCents: m['custom_fee_cents'] as int?,
```

### `CourtBookingScreen` (`/play/custom`)

Full-screen `ConsumerStatefulWidget`. Receives `Court court` from `GoRouterState.extra`.

**State:**
- `DateTime _selectedDay` — defaults to today (UTC, date only).
- `String? _selectedSlotId` — which `court_slot` is being viewed.
- `int? _startHour`, `int? _endHour` — selection range (inclusive start, exclusive end).

**Layout:**

1. **AppBar** — title `'Book a Court'`, back button.

2. **Day strip** — horizontally scrollable `Row` of 8 tappable chips:
   today through today + 7 days. Selected chip uses `kBrandGreen` fill.
   Label format: `'Mon 23'`. Use a manual weekday list
   (`const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']`) indexed by
   `date.weekday - 1` — avoids adding the `intl` package.

3. **Slot tabs** — if the court has >1 slot, a `TabBar`-style row of slot labels
   ("Court 1", "Court 2"…). Fetched via `courtSlotsProvider(courtId)`. Defaults
   to first slot. Single-slot courts skip this row.

4. **Hour timeline** — `ListView` of 16 hour blocks (06:00–21:00, each block
   represents one hour starting at that hour). Each block is 64 px tall:
   - Left label: `'06:00'`, `'07:00'`…
   - Right area: full-width tappable block.
   - **Available** (not in any confirmed booking): neutral surface colour,
     tappable.
   - **Booked** (overlaps a confirmed `custom_booking`): muted fill,
     `'Booked'` label, not tappable.
   - **Selected range** (`_startHour <= hour < _endHour`): `kBrandGreen` fill.

   **Tap logic:**
   - If `_startHour == null`: set `_startHour = hour`, `_endHour = hour + 1`
     (one-block minimum).
   - If `_startHour != null && _endHour != null`:
     - Tap before `_startHour`: extend start backward.
     - Tap after or at `_endHour - 1`: extend end forward.
     - Tap on `_startHour` (the first selected block): clear selection.
   - Tapping a booked block: no-op.

5. **Booking summary** — shown only when a range is selected. Pinned above the
   button. Shows:
   `'{slotLabel} · {day} · {startTime}–{endTime} · {formatFee(total, currency)}'`
   where `total = customFeeCents * hours`.

6. **"Confirm booking" `FilledButton`** — enabled when a valid range is selected.
   Calls `book_custom_slot` RPC. On success: `context.pop()` + show snackbar
   `'Booked! See you on {slotLabel}.'`. On error: inline error text.

### `booking_repository.dart`

```dart
// Providers
final courtSlotsProvider = FutureProvider.family<List<CourtSlot>, String>(
  (ref, courtId) => ..., // select id, label from court_slots where court_id = courtId
);

final courtBookingsProvider = FutureProvider.family<List<CustomBooking>, CourtBookingQuery>(
  (ref, query) => ..., // select starts_at, ends_at from custom_bookings
                       // where court_slot_id = query.slotId
                       // and status = 'confirmed'
                       // and starts_at::date = query.date
);

// Models
class CourtSlot { final String id, label; }
class CustomBooking { final DateTime startsAt, endsAt; }

// Used as Riverpod family arg — must implement == and hashCode.
class CourtBookingQuery {
  const CourtBookingQuery({required this.slotId, required this.date});
  final String slotId;
  final DateTime date; // date-only (year/month/day); time part ignored
  @override bool operator ==(Object other) =>
      other is CourtBookingQuery && slotId == other.slotId && date == other.date;
  @override int get hashCode => Object.hash(slotId, date);
}
```

`SupabaseBookingRepository` implements the two queries and the `bookSlot` method
that calls the `book_custom_slot` RPC.

---

## Database

### Migration: `custom_fee_cents` on courts

```sql
alter table public.courts
  add column custom_fee_cents integer check (custom_fee_cents > 0);
```

Nullable. When null, "Book a Court" is disabled in the lobby.

### Migration: `payments.kind` extension

```sql
alter table public.payments
  drop constraint payments_kind_check,
  add constraint payments_kind_check
    check (kind in ('entry','subscription','custom'));
```

### Migration: `custom_bookings` table

```sql
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
```

**RLS:**
```sql
-- Players see their own bookings; court members + admin see all for their court.
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

-- All writes go through the RPC.
```

### RPC: `book_custom_slot`

```sql
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
  -- Load slot and court.
  select * into v_slot  from court_slots where id = p_court_slot_id;
  select * into v_court from courts       where id = v_slot.court_id;

  if v_court.custom_fee_cents is null then
    raise exception 'custom_bookings_disabled';
  end if;

  -- Overlap check: any confirmed booking on this slot that overlaps?
  if exists (
    select 1 from custom_bookings
    where court_slot_id = p_court_slot_id
      and status = 'confirmed'
      and starts_at < p_ends_at
      and ends_at   > p_starts_at
  ) then
    raise exception 'slot_not_available';
  end if;

  -- Calculate fee.
  v_hours  := extract(epoch from (p_ends_at - p_starts_at))::int / 3600;
  v_amount := v_court.custom_fee_cents * v_hours;

  -- Record payment (mock — immediately paid).
  insert into payments (payer_profile_id, payee_court_id, kind, amount_cents,
                        currency, status, provider)
  values (auth.uid(), v_court.id, 'custom', v_amount,
          v_court.currency, 'paid', 'mock')
  returning id into v_payment_id;

  -- Create booking.
  insert into custom_bookings (court_id, court_slot_id, booker_profile_id,
                               starts_at, ends_at, amount_cents, currency, payment_id)
  values (v_court.id, p_court_slot_id, auth.uid(),
          p_starts_at, p_ends_at, v_amount, v_court.currency, v_payment_id)
  returning id into v_booking_id;

  return v_booking_id;
end;
$$;
```

---

## Error Handling

- **Overlap conflict** (`slot_not_available`): inline error `'That time is no longer
  available. Please choose another slot.'` — the timeline refreshes.
- **Custom disabled** (`custom_bookings_disabled`): should not reach booking screen
  (button disabled in lobby), but surfaced as generic error if it does.
- **Network / unknown**: generic `'Booking failed. Please try again.'`

## Testing

**Repository / pure logic:**
- `CourtBookingQuery` equality (needed for `FutureProvider.family` cache key).
- Fee calculation: 2 hours at ₱500/hr → `amount_cents = 1000`.

**`LobbyScreen` widget tests:**
- "Book a Court" disabled when no court selected.
- "Book a Court" disabled when court has no `custom_fee_cents`.
- "Book a Court" enabled when court with `custom_fee_cents` is selected.
- Court selector pushes `/play/courts` and updates on return.

**`CourtListScreen` widget tests (picker mode):**
- Tapping card body calls `onSelect` (not navigation).
- Info button navigates to detail.
- Existing tests (normal mode) still pass.

**`CourtBookingScreen` widget tests:**
- Day strip renders today + 7 days.
- Tapping an available block sets start selection.
- Tapping a second block extends range; summary shows correct fee.
- Booked blocks are not tappable.
- Confirm button disabled with no selection.

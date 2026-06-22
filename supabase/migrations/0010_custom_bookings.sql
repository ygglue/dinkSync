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

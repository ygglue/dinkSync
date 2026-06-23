-- Allows a court member (owner/staff) or the booker themselves to cancel
-- a confirmed booking. Status-only update; no payment reversal yet.
create or replace function public.cancel_custom_booking(p_booking_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_booking custom_bookings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_booking from custom_bookings where id = p_booking_id;

  if not found then
    raise exception 'booking_not_found';
  end if;

  if v_booking.status != 'confirmed' then
    raise exception 'booking_not_cancellable';
  end if;

  -- Caller must be the booker OR a court member (owner/staff).
  if v_booking.booker_profile_id != auth.uid() and not exists (
    select 1 from court_members
    where court_id = v_booking.court_id
      and profile_id = auth.uid()
  ) then
    raise exception 'not_authorized';
  end if;

  update custom_bookings set status = 'canceled' where id = p_booking_id;
end;
$$;

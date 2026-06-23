-- 0011_create_court_custom_fee.sql
-- Extends create_court RPC to accept an optional private booking rate so
-- courts can enable "Book a Court" at creation time (not just via SQL).

create or replace function public.create_court(
  p_name             text,
  p_entry_fee_cents  int,
  p_currency         text,
  p_num_courts       int,
  p_address          text,
  p_custom_fee_cents int default null
) returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  uid          uuid := auth.uid();
  new_court_id uuid;
  i            int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'court name is required';
  end if;
  if p_num_courts is null or p_num_courts < 1 then
    raise exception 'num_courts must be >= 1';
  end if;
  if p_custom_fee_cents is not null and p_custom_fee_cents <= 0 then
    raise exception 'custom_fee_cents must be > 0';
  end if;

  insert into public.courts
    (owner_profile_id, name, entry_fee_cents, currency, num_courts,
     address, status, custom_fee_cents)
  values
    (uid, btrim(p_name),
     greatest(coalesce(p_entry_fee_cents, 0), 0),
     coalesce(nullif(p_currency, ''), 'PHP'),
     p_num_courts,
     nullif(btrim(coalesce(p_address, '')), ''),
     'suspended',
     p_custom_fee_cents)
  returning id into new_court_id;

  insert into public.court_members
    (court_id, profile_id, role, can_accept_payment, added_by)
  values
    (new_court_id, uid, 'owner', true, uid);

  for i in 1..p_num_courts loop
    insert into public.court_slots (court_id, label, status)
    values (new_court_id, 'Court ' || i, 'open');
  end loop;

  return new_court_id;
end;
$$;

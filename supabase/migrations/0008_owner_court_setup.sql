-- 0008_owner_court_setup.sql
-- Owner court setup: create_court + subscribe_court RPCs, and tighten court
-- visibility so only subscribed (active) courts are publicly discoverable.
-- Clients cannot insert the owner's own court_members row (is_court_owner
-- chicken-and-egg), court_slots (no insert policy), or subscriptions
-- (RPC-only) -- hence security definer functions. Dev/Phase-1 helper.

-- ---------------------------------------------------------------------------
-- create_court: venue (suspended) + owner membership + N slots, atomically.
-- ---------------------------------------------------------------------------
create or replace function public.create_court(
  p_name           text,
  p_entry_fee_cents int,
  p_currency       text,
  p_num_courts     int,
  p_address        text
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

  insert into public.courts
    (owner_profile_id, name, entry_fee_cents, currency, num_courts, address, status)
  values
    (uid, btrim(p_name), greatest(coalesce(p_entry_fee_cents, 0), 0),
     coalesce(nullif(p_currency, ''), 'PHP'), p_num_courts,
     nullif(btrim(coalesce(p_address, '')), ''), 'suspended')
  returning id into new_court_id;

  insert into public.court_members (court_id, profile_id, role, can_accept_payment, added_by)
  values (new_court_id, uid, 'owner', true, uid);

  for i in 1..p_num_courts loop
    insert into public.court_slots (court_id, label, status)
    values (new_court_id, 'Court ' || i, 'open');
  end loop;

  return new_court_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- subscribe_court: record a (mock) payment + activate the subscription and
-- the court. Prices are authoritative here; the client only sends the plan.
-- ---------------------------------------------------------------------------
create or replace function public.subscribe_court(
  p_court_id uuid,
  p_plan     text
) returns void
language plpgsql
security definer set search_path = public
as $$
declare
  uid      uuid := auth.uid();
  v_amount int;
  v_end    timestamptz;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (
    select 1 from public.courts c
    where c.id = p_court_id and c.owner_profile_id = uid
  ) then
    raise exception 'not the court owner';
  end if;

  if p_plan = 'monthly' then
    v_amount := 99900;
    v_end    := now() + interval '1 month';
  elsif p_plan = 'yearly' then
    v_amount := 999000;
    v_end    := now() + interval '1 year';
  else
    raise exception 'invalid plan: %', p_plan;
  end if;

  insert into public.payments
    (payer_profile_id, payee_court_id, kind, amount_cents, currency, status, provider)
  values
    (uid, p_court_id, 'subscription', v_amount, 'PHP', 'paid', 'mock');

  -- subscriptions has no unique constraint on court_id, so update-or-insert.
  update public.subscriptions
     set plan = p_plan, status = 'active', amount_cents = v_amount,
         currency = 'PHP', provider = 'mock', current_period_end = v_end
   where court_id = p_court_id;
  if not found then
    insert into public.subscriptions
      (court_id, plan, status, amount_cents, currency, provider, current_period_end)
    values
      (p_court_id, p_plan, 'active', v_amount, 'PHP', 'mock', v_end);
  end if;

  update public.courts set status = 'active' where id = p_court_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tighten court visibility: subscribed (active) => publicly visible; owner/
-- staff see their own at any status; admin sees all.
-- ---------------------------------------------------------------------------
drop policy if exists "courts_select" on public.courts;
create policy "courts_select"
  on public.courts for select
  using (
    status = 'active'
    or public.is_court_member(id)
    or public.is_platform_admin()
  );

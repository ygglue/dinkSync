-- seed.sql
-- Dev seed data. Re-applied on every `supabase db reset`.
--
-- NOTE: profiles rows are normally created by the on_auth_user_created trigger.
-- Here we insert auth.users + profiles directly so the app has test identities
-- without going through the email OTP flow each reset.
--
-- Test credentials (email + OTP):
--   For local dev with email confirmations OFF, you can sign up normally via
--   the app; OTP emails are caught by Inbucket at http://127.0.0.1:54324.
--   The rows below exist so SQL-level exploration has data.

begin;

-- Use fixed UUIDs so re-seeding is idempotent across resets.
do $$
declare
  owner_id   uuid := '11111111-1111-1111-1111-111111111111';
  staff_id   uuid := '22222222-2222-2222-2222-222222222222';
  p1_id      uuid := 'a1111111-1111-1111-1111-111111111111';
  p2_id      uuid := 'a2222222-2222-2222-2222-222222222222';
  p3_id      uuid := 'a3333333-3333-3333-3333-333333333333';
  p4_id      uuid := 'a4444444-4444-4444-4444-444444444444';
  court_id   uuid;
begin
  -- Helper to create an auth user + profile pair.
  perform public._seed_user(owner_id, 'owner@dinksync.dev',  'Court Owner', 1000, false);
  perform public._seed_user(staff_id, 'staff@dinksync.dev',  'Court Staff', 1000, false);
  perform public._seed_user(p1_id,    'p1@dinksync.dev',     'Player One',  1050, false);
  perform public._seed_user(p2_id,    'p2@dinksync.dev',     'Player Two',  1030, false);
  perform public._seed_user(p3_id,    'p3@dinksync.dev',     'Player Three',  980, false);
  perform public._seed_user(p4_id,    'p4@dinksync.dev',     'Player Four',  1010, false);

  -- One active court owned by owner_id.
  insert into public.courts (id, owner_profile_id, name, lat, lng, address,
                             entry_fee_cents, currency, num_courts, status)
  values (gen_random_uuid(), owner_id, 'Demo Pickleball Club',
          40.712776, -74.005974, 'New York, NY',
          1000, 'USD', 2, 'active')
  returning id into court_id;

  -- Owner is the court's owner member; staff added with payment rights.
  insert into public.court_members (court_id, profile_id, role, can_accept_payment, added_by)
  values (court_id, owner_id, 'owner', true, owner_id),
         (court_id, staff_id, 'staff', true, owner_id);

  -- Two physical slots (e.g. Court 1, Court 2), both open.
  insert into public.court_slots (court_id, label, status)
  values (court_id, 'Court 1', 'open'),
         (court_id, 'Court 2', 'open');
end $$;

commit;

-- 0002b_seed_helpers.sql
-- Helper used only by seed.sql to create auth.users + profiles rows together.
-- The on_auth_user_created trigger only fires for real signups, so for seeded
-- data we insert both rows explicitly. Marked SECURITY DEFINER so it can write
-- to auth.users; only intended to be called from seed.sql (not exposed via API).

create or replace function public._seed_user(
  uid        uuid,
  email_addr text,
  name       text,
  mmr        int,
  is_admin   boolean
) returns void
language plpgsql
security definer set search_path = auth, public
as $$
begin
  -- auth.users
  insert into auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  values (
    uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    email_addr,
    '',                          -- no password; OTP-only in dev
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', name)
  )
  on conflict (id) do nothing;

  -- identities (required row for the auth flow to consider the user valid)
  insert into auth.identities (id, user_id, provider, identity_data, created_at, updated_at)
  values (
    gen_random_uuid(),
    uid,
    'email',
    jsonb_build_object('sub', uid::text, 'email', email_addr),
    now(),
    now()
  )
  on conflict do nothing;

  -- profile
  insert into public.profiles (id, display_name, mmr, is_platform_admin)
  values (uid, name, mmr, is_admin)
  on conflict (id) do update
    set display_name = excluded.display_name,
        mmr = excluded.mmr,
        is_platform_admin = excluded.is_platform_admin;
end;
$$;

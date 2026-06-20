-- 0005_dev_seed_auth.sql
-- Give seeded dev users a real bcrypt password so the debug-only "dev login"
-- can sign in via signInWithPassword. Dev-only: seed.sql is never auto-applied
-- to production (db push does not run it). Password: 'dinkdev123'.

create extension if not exists pgcrypto;

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
  -- auth.users (now with a bcrypt password instead of an empty string)
  insert into auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  values (
    uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    email_addr,
    crypt('dinkdev123', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', name)
  )
  on conflict (id) do update
    set encrypted_password = excluded.encrypted_password,
        email_confirmed_at = excluded.email_confirmed_at;

  -- identities (required for the auth flow to consider the user valid)
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

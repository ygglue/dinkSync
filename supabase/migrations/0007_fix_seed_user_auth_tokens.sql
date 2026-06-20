-- 0007_fix_seed_user_auth_tokens.sql
-- Fix login for seeded dev users: GoTrue scans several auth.users token columns
-- as NON-nullable strings during sign-in. Our manual _seed_user insert never set
-- them, so they were NULL, producing "Database error querying schema" on login.
-- Confirmed NULL: confirmation_token, recovery_token, email_change,
-- email_change_token_new (the other token columns already default to '').
--
-- This migration (1) redefines _seed_user to set those columns to '' on insert,
-- and (2) backfills the already-seeded dev rows. Dev-only helper.

create or replace function public._seed_user(
  uid        uuid,
  email_addr text,
  name       text,
  mmr        int,
  is_admin   boolean
) returns void
language plpgsql
security definer set search_path = auth, public, extensions
as $$
begin
  -- auth.users. The empty-string token columns are required: GoTrue scans them
  -- as non-nullable strings at login, and NULL there breaks the auth query.
  insert into auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
                          confirmation_token, recovery_token,
                          email_change, email_change_token_new)
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
    jsonb_build_object('display_name', name),
    '', '', '', ''
  )
  on conflict (id) do update
    set encrypted_password = excluded.encrypted_password,
        email_confirmed_at = excluded.email_confirmed_at,
        confirmation_token = excluded.confirmation_token,
        recovery_token = excluded.recovery_token,
        email_change = excluded.email_change,
        email_change_token_new = excluded.email_change_token_new;

  -- identities (required for the auth flow to consider the user valid).
  -- provider_id is the user's sub (their id) for the email provider.
  insert into auth.identities (id, provider_id, user_id, provider,
                               identity_data, created_at, updated_at)
  values (
    gen_random_uuid(),
    uid::text,
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

-- Backfill the dev users already seeded with NULL token columns so they can
-- log in without re-running the seed.
update auth.users
set confirmation_token     = coalesce(confirmation_token, ''),
    recovery_token         = coalesce(recovery_token, ''),
    email_change           = coalesce(email_change, ''),
    email_change_token_new = coalesce(email_change_token_new, '')
where email like '%@dinksync.dev';

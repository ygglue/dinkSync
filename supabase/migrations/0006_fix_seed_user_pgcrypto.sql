-- 0006_fix_seed_user_pgcrypto.sql
-- Fixes for _seed_user discovered when first applying the dev seed to a hosted
-- Supabase project:
--   1. pgcrypto (crypt/gen_salt) lives in the `extensions` schema on Supabase,
--      not `public`. The function's restricted search_path (auth, public) could
--      not see gen_salt -> "function gen_salt(unknown) does not exist". Add
--      `extensions` to the search_path.
--   2. auth.identities.provider_id is NOT NULL on modern GoTrue; the original
--      insert omitted it. For the email provider, provider_id is the user's
--      sub (their auth.users id) as text.
-- Dev-only helper; seed.sql is never auto-applied to production.

create extension if not exists pgcrypto with schema extensions;

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
  -- auth.users (bcrypt password via pgcrypto in the extensions schema)
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

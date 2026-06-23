-- The original profiles_select policy used `using (true)`, which allowed any
-- authenticated user to read every row. Tighten it to self-only.
--
-- When cross-user reads are needed (social features, match history), add a
-- separate policy that exposes only public fields (display_name, mmr,
-- avatar_url) via a view or a narrower column-level policy.

drop policy if exists "profiles_select" on public.profiles;

create policy "profiles_select"
  on public.profiles for select
  using (id = auth.uid());

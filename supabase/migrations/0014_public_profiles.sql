-- 0014_public_profiles.sql
-- Public, read-only views for social features. The profiles table RLS stays
-- self-only (see 0012); these views expose ONLY safe columns and bypass that
-- RLS by virtue of being security-definer (default) views.
--
-- These are PLAIN views (saved queries) — NOT tables, NOT materialized views.
-- They store no rows and cannot drift; profiles/match_results/matches remain
-- the single source of truth. Do not convert them to materialized views.
--
-- The Supabase advisor will flag these as "Security Definer View". That is
-- intended here: switching to security_invoker would respect the self-only RLS
-- and re-break public reads.

-- Public profile fields (no is_platform_admin, no updated_at).
create view public.public_profiles as
  select id, display_name, avatar_url, mmr, created_at
  from public.profiles;

grant select on public.public_profiles to authenticated;

-- Per-player win/loss totals. Empty until Find Match writes match_results.
create view public.public_player_stats as
  select
    p.id as profile_id,
    count(mr.match_id) filter (where mr.result = 'win')  as wins,
    count(mr.match_id) filter (where mr.result = 'loss') as losses
  from public.profiles p
  left join public.match_results mr on mr.profile_id = p.id
  group by p.id;

grant select on public.public_player_stats to authenticated;

-- Per-player completed matches, newest-first applied by the client.
-- Empty until Find Match writes matches/match_results.
create view public.public_recent_matches as
  select
    mr.profile_id,
    m.id          as match_id,
    m.played_at,
    mr.result,
    mr.team,
    m.winning_team
  from public.match_results mr
  join public.matches m on m.id = mr.match_id
  where m.status = 'completed';

grant select on public.public_recent_matches to authenticated;

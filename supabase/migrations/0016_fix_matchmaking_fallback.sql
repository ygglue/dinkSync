-- =============================================================================
-- 0016_fix_matchmaking_fallback.sql
-- Replace form_groups_for_court with a fallback path:
--   1. Try to collect 4 players within the MMR band (fair matchmaking).
--   2. If fewer than 4 are in band, fall back to the 4 oldest open requests
--      at that court regardless of MMR (fills the game rather than letting
--      players wait forever).
-- =============================================================================

create or replace function public.form_groups_for_court(p_court_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seed       record;
  v_band       int;
  v_member_ids uuid[];
  v_group_id   uuid;
  v_next_pos   int;
begin
  loop
    -- Seed = oldest open solo request at this court
    select id, profile_id, mmr_at_request,
           extract(epoch from (now() - created_at))::int as wait_secs
    into v_seed
    from matchmaking_requests
    where court_id = p_court_id
      and status   = 'open'
      and party_size_wanted = 1
    order by created_at asc
    limit 1;

    exit when not found;

    -- MMR band: ±50 to start, +25 every 30 s waited, cap ±300
    v_band := least(50 + (v_seed.wait_secs / 30) * 25, 300);

    -- ── Pass 1: collect 4 players within the MMR band ──
    select array_agg(sub.profile_id order by sub.created_at asc)
    into v_member_ids
    from (
      select profile_id, created_at
      from matchmaking_requests
      where court_id = p_court_id
        and status   = 'open'
        and party_size_wanted = 1
        and abs(mmr_at_request - v_seed.mmr_at_request) <= v_band
      order by created_at asc
      limit 4
    ) sub;

    -- ── Pass 2: fallback — take any 4 oldest if band didn't fill ──
    if coalesce(array_length(v_member_ids, 1), 0) < 4 then
      select array_agg(sub.profile_id order by sub.created_at asc)
      into v_member_ids
      from (
        select profile_id, created_at
        from matchmaking_requests
        where court_id = p_court_id
          and status   = 'open'
          and party_size_wanted = 1
        order by created_at asc
        limit 4
      ) sub;
    end if;

    -- Fewer than 4 players at this court in total — nothing to form yet
    exit when coalesce(array_length(v_member_ids, 1), 0) < 4;

    -- Create the group
    insert into match_groups (court_id, status)
    values (p_court_id, 'queued')
    returning id into v_group_id;

    insert into match_group_members (match_group_id, profile_id, is_initiator, is_invited_partner)
    select v_group_id, unnest(v_member_ids), false, false;

    update match_group_members
    set is_initiator = true
    where match_group_id = v_group_id
      and profile_id = v_member_ids[1];

    update matchmaking_requests
    set status = 'matched'
    where court_id = p_court_id
      and profile_id = any(v_member_ids)
      and status = 'open';

    select coalesce(max(position), 0) + 1
    into v_next_pos
    from queue_entries
    where court_id = p_court_id;

    insert into queue_entries (match_group_id, court_id, position, enqueued_at)
    values (v_group_id, p_court_id, v_next_pos, now());

    perform public.assign_free_slots(p_court_id);

  end loop;
end;
$$;

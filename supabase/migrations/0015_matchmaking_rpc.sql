-- =============================================================================
-- 0015_matchmaking_rpc.sql
-- Matchmaking sweep: form groups of 4 by MMR, assign to open court slots.
-- All three functions run as security definer (service role) so they can
-- write to tables whose RLS only allows RPC writes.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- assign_free_slots(court_id)
-- For each open slot at the court, pop the oldest queued group and assign it.
-- Called by matchmake_sweep AND by staff when they open/close a slot manually.
-- ---------------------------------------------------------------------------
create or replace function public.assign_free_slots(p_court_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot   record;
  v_entry  record;
begin
  for v_slot in
    select id, label
    from court_slots
    where court_id = p_court_id
      and status = 'open'
    order by label asc
  loop
    select match_group_id
    into v_entry
    from queue_entries
    where court_id = p_court_id
    order by position asc
    limit 1;

    if not found then
      exit;
    end if;

    -- Assign slot
    update court_slots
    set status = 'occupied',
        current_group_id = v_entry.match_group_id
    where id = v_slot.id;

    -- Update group: assigned + store slot label for display
    update match_groups
    set status = 'assigned',
        slot_label = v_slot.label
    where id = v_entry.match_group_id;

    -- Remove from queue
    delete from queue_entries
    where match_group_id = v_entry.match_group_id;

    -- Resequence remaining positions
    with ranked as (
      select match_group_id,
             row_number() over (order by enqueued_at asc) as new_pos
      from queue_entries
      where court_id = p_court_id
    )
    update queue_entries qe
    set position = ranked.new_pos
    from ranked
    where qe.match_group_id = ranked.match_group_id;

  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- form_groups_for_court(court_id)
-- Greedy MMR-band grouping:
--   • Seed = oldest open solo request.
--   • Band = ±50 MMR, expanding +25 every 30 s of wait, capped at ±300.
--   • Pack 4 solos into a group; repeat until no seed has 4 eligible players.
-- Partner pairs (party_size_wanted=2) are skipped here (MVP: solo only).
-- ---------------------------------------------------------------------------
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
    -- Pick oldest open solo request as the seed for a new group
    select id, profile_id, mmr_at_request,
           extract(epoch from (now() - created_at))::int as wait_secs
    into v_seed
    from matchmaking_requests
    where court_id = p_court_id
      and status = 'open'
      and party_size_wanted = 1
    order by created_at asc
    limit 1;

    exit when not found;

    -- MMR band: start ±50, +25 per 30 s waited, cap ±300
    v_band := least(50 + (v_seed.wait_secs / 30) * 25, 300);

    -- Collect up to 4 requests within the band (oldest first)
    select array_agg(sub.profile_id order by sub.created_at asc)
    into v_member_ids
    from (
      select profile_id, created_at
      from matchmaking_requests
      where court_id = p_court_id
        and status = 'open'
        and party_size_wanted = 1
        and abs(mmr_at_request - v_seed.mmr_at_request) <= v_band
      order by created_at asc
      limit 4
    ) sub;

    -- Fewer than 4 eligible — nothing to form right now
    exit when array_length(v_member_ids, 1) < 4;

    -- Create the group (status=queued; slot assignment happens in assign_free_slots)
    insert into match_groups (court_id, status)
    values (p_court_id, 'queued')
    returning id into v_group_id;

    -- Add all 4 members (first in array is the seed/initiator)
    insert into match_group_members (match_group_id, profile_id, is_initiator, is_invited_partner)
    select v_group_id,
           unnest(v_member_ids),
           false,
           false;

    update match_group_members
    set is_initiator = true
    where match_group_id = v_group_id
      and profile_id = v_member_ids[1];

    -- Mark their requests matched
    update matchmaking_requests
    set status = 'matched'
    where court_id = p_court_id
      and profile_id = any(v_member_ids)
      and status = 'open';

    -- Enqueue the group
    select coalesce(max(position), 0) + 1
    into v_next_pos
    from queue_entries
    where court_id = p_court_id;

    insert into queue_entries (match_group_id, court_id, position, enqueued_at)
    values (v_group_id, p_court_id, v_next_pos, now());

    -- Try to immediately claim a free slot
    perform public.assign_free_slots(p_court_id);

  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- matchmake_sweep()
-- Called by pg_cron every minute. Iterates all active courts.
-- ---------------------------------------------------------------------------
create or replace function public.matchmake_sweep()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
begin
  for c in
    select id from courts where status = 'active'
  loop
    perform public.assign_free_slots(c.id);
    perform public.form_groups_for_court(c.id);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- pg_cron schedule — runs every minute.
-- The cron extension is enabled in 0000_extensions.sql.
-- We use 'select cron.unschedule(...)' first so re-applying the migration is
-- idempotent (no duplicate schedules).
-- ---------------------------------------------------------------------------
select cron.unschedule('matchmake-sweep') where exists (
  select 1 from cron.job where jobname = 'matchmake-sweep'
);

select cron.schedule(
  'matchmake-sweep',
  '* * * * *',
  'select public.matchmake_sweep()'
);

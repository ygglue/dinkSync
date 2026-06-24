-- Enable Realtime for tables the Flutter app needs to stream live updates from.
-- Without these, supabase_flutter .stream() gets the initial snapshot but never
-- receives change notifications when server-side RPCs update the rows.
alter publication supabase_realtime add table public.matchmaking_requests;
alter publication supabase_realtime add table public.match_groups;
alter publication supabase_realtime add table public.match_group_members;
alter publication supabase_realtime add table public.court_slots;
alter publication supabase_realtime add table public.queue_entries;

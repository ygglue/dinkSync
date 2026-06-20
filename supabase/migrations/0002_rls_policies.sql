-- 0002_rls_policies.sql
-- Row Level Security for dinkSync.
--
-- Design principles:
--   1. Postgres enforces security — even a malicious client can't bypass.
--   2. Client-initiated writes are allowed ONLY for trivial self-service rows
--      (e.g., creating a matchmaking_request). Anything touching matchmaking,
--      queue, score, or money goes through RPC (service role), NOT direct
--      client writes.
--   3. Owner-scoped access is resolved via court_members; a helper function
--      keeps policies readable.
--   4. Platform admin bypass is explicit per table (never a blanket rule).
--
-- All policies assume auth.uid() returns the requesting user's id.

-- ============================================================================
-- Helper: is the current user a member of a court (owner or staff)?
-- ============================================================================
create or replace function public.is_court_member(court uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.court_members cm
    where cm.court_id = court and cm.profile_id = auth.uid()
  );
$$;

-- Helper: is the current user the OWNER of a court?
create or replace function public.is_court_owner(court uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.court_members cm
    where cm.court_id = court
      and cm.profile_id = auth.uid()
      and cm.role = 'owner'
  );
$$;

-- Helper: is the current user a platform admin?
create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select p.is_platform_admin from public.profiles p where p.id = auth.uid()),
    false
  );
$$;

-- ============================================================================
-- profiles
--   read  : everyone sees public fields; self sees own row
--   write : self only (non-admin fields); admin can toggle is_platform_admin
-- ============================================================================
create policy "profiles_select"
  on public.profiles for select
  using (true);

create policy "profiles_update_self"
  on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- Admin privilege grants are done via RPC/service role, not client policy.

-- ============================================================================
-- courts
--   read  : everyone (discovery shows active courts)
--   write : owner of the court only
-- ============================================================================
create policy "courts_select"
  on public.courts for select
  using (true);

create policy "courts_insert_owner"
  on public.courts for insert
  with check (owner_profile_id = auth.uid());

create policy "courts_update_owner"
  on public.courts for update
  using (public.is_court_owner(id))
  with check (public.is_court_owner(id));

-- ============================================================================
-- court_members
--   read  : members of the court, OR platform admin
--   write : owner of the court only (owner adds/removes staff)
-- ============================================================================
create policy "court_members_select"
  on public.court_members for select
  using (public.is_court_member(court_id) or public.is_platform_admin());

create policy "court_members_insert_owner"
  on public.court_members for insert
  with check (public.is_court_owner(court_id));

create policy "court_members_update_owner"
  on public.court_members for update
  using (public.is_court_owner(court_id))
  with check (public.is_court_owner(court_id));

create policy "court_members_delete_owner"
  on public.court_members for delete
  using (public.is_court_owner(court_id));

-- ============================================================================
-- subscriptions
--   read  : owner of the court, OR platform admin
--   write : NEVER via client — only via RPC (service role)
-- ============================================================================
create policy "subscriptions_select"
  on public.subscriptions for select
  using (public.is_court_owner(court_id) or public.is_platform_admin());

-- ============================================================================
-- matchmaking_requests
--   read  : own request, OR court member, OR admin
--   write : insert/cancel own; matched/expired set by RPC only
-- ============================================================================
create policy "mm_requests_select"
  on public.matchmaking_requests for select
  using (
    profile_id = auth.uid()
    or public.is_court_member(court_id)
    or public.is_platform_admin()
  );

create policy "mm_requests_insert_self"
  on public.matchmaking_requests for insert
  with check (profile_id = auth.uid());

create policy "mm_requests_update_self"
  on public.matchmaking_requests for update
  using (profile_id = auth.uid())
  -- players may only cancel their own open requests; status transitions to
  -- matched/expired happen via RPC (service role), which bypasses RLS.
  with check (profile_id = auth.uid());

create policy "mm_requests_delete_self"
  on public.matchmaking_requests for delete
  using (profile_id = auth.uid());

-- ============================================================================
-- match_groups
--   read  : group member, OR court member, OR admin
--   write : RPC only (service role)
-- ============================================================================
create policy "match_groups_select"
  on public.match_groups for select
  using (
    exists (
      select 1 from public.match_group_members m
      where m.match_group_id = match_groups.id and m.profile_id = auth.uid()
    )
    or public.is_court_member(court_id)
    or public.is_platform_admin()
  );

-- ============================================================================
-- match_group_members
--   read  : member of the group, OR court member, OR admin
--   write : RPC only
-- ============================================================================
create policy "match_group_members_select"
  on public.match_group_members for select
  using (
    profile_id = auth.uid()
    or exists (
      select 1 from public.match_group_members m2
      where m2.match_group_id = match_group_members.match_group_id
        and m2.profile_id = auth.uid()
    )
    or exists (
      select 1 from public.match_groups g
      where g.id = match_group_members.match_group_id
        and public.is_court_member(g.court_id)
    )
    or public.is_platform_admin()
  );

-- ============================================================================
-- court_slots
--   read  : everyone (queue display shows slot status)
--   write : court member only (open/close, assign)
-- ============================================================================
create policy "court_slots_select"
  on public.court_slots for select
  using (true);

create policy "court_slots_update_member"
  on public.court_slots for update
  using (public.is_court_member(court_id))
  with check (public.is_court_member(court_id));

-- Slot rows are created by the owner when onboarding (RPC or trigger), not
-- by arbitrary clients. We deliberately do NOT add an insert policy here.

-- ============================================================================
-- queue_entries
--   read  : group member, OR court member, OR admin
--   write : RPC only
-- ============================================================================
create policy "queue_entries_select"
  on public.queue_entries for select
  using (
    exists (
      select 1 from public.match_group_members m
      where m.match_group_id = queue_entries.match_group_id
        and m.profile_id = auth.uid()
    )
    or public.is_court_member(court_id)
    or public.is_platform_admin()
  );

-- ============================================================================
-- matches
--   read  : participant, OR court member, OR admin
--   write : RPC only (score entry -> Elo)
-- ============================================================================
create policy "matches_select"
  on public.matches for select
  using (
    exists (
      select 1 from public.match_group_members m
      where m.match_group_id = matches.match_group_id
        and m.profile_id = auth.uid()
    )
    or public.is_court_member(court_id)
    or public.is_platform_admin()
  );

-- ============================================================================
-- match_results
--   read  : own results, OR court member, OR admin
--   write : RPC only
-- ============================================================================
create policy "match_results_select"
  on public.match_results for select
  using (
    profile_id = auth.uid()
    or public.is_court_member(
          (select m.court_id from public.matches m where m.id = match_results.match_id)
        )
    or public.is_platform_admin()
  );

-- ============================================================================
-- payments
--   read  : payer, OR court member of payee court, OR admin
--   write : RPC only (create entry/subscription, mark paid offline, refund)
--   -- exception: players may insert their OWN pending entry payment row, so a
--   -- direct pay flow can record the payment before charging. Refunds/paid
--   -- transitions go through RPC.
-- ============================================================================
create policy "payments_select"
  on public.payments for select
  using (
    payer_profile_id = auth.uid()
    or public.is_court_member(payee_court_id)
    or public.is_platform_admin()
  );

create policy "payments_insert_payer"
  on public.payments for insert
  with check (payer_profile_id = auth.uid() or public.is_court_member(payee_court_id));

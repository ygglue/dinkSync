-- 0001_init_schema.sql
-- Core data model for dinkSync.
--
-- Conventions:
--   - IDs are uuid PKs (gen_random_uuid()).
--   - Money is integer cents + ISO 4217 currency code (never floats).
--   - Timestamps are timestamptz (UTC).
--   - Every table has created_at/updated_at as relevant.
--   - RLS is enabled here but policies live in 0002_rls_policies.sql.
--   - Business logic (matchmaking, scoring, payments) lives in RPC functions
--     (migrations 0003+), not in triggers, so it stays easy to read and test.

-- ============================================================================
-- profiles : 1:1 with auth.users
-- ============================================================================
create table public.profiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  display_name     text not null,
  avatar_url       text,
  mmr              integer      not null default 1000,
  is_platform_admin boolean     not null default false,
  created_at       timestamptz  not null default now(),
  updated_at       timestamptz  not null default now()
);

-- Auto-create a profile row whenever a new auth user signs up.
-- Display name defaults to the email; user can edit it later.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- courts : a physical venue an owner runs
-- ============================================================================
create table public.courts (
  id               uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references public.profiles (id) on delete restrict,
  name             text not null,
  lat              numeric(9,6),
  lng              numeric(9,6),
  address          text,
  entry_fee_cents  integer not null default 0 check (entry_fee_cents >= 0),
  currency         text    not null default 'USD' check (length(currency) = 3),
  num_courts       integer not null default 1   check (num_courts > 0),
  status           text    not null default 'active'
                     check (status in ('active','suspended','offboarded')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index courts_owner_idx     on public.courts (owner_profile_id);
create index courts_status_idx    on public.courts (status);

-- ============================================================================
-- court_members : owner + staff of a court
-- ============================================================================
create table public.court_members (
  court_id          uuid    not null references public.courts (id) on delete cascade,
  profile_id        uuid    not null references public.profiles (id) on delete cascade,
  role              text    not null check (role in ('owner','staff')),
  can_accept_payment boolean not null default false,
  added_by          uuid    references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  primary key (court_id, profile_id)
);

create unique index court_members_one_owner_idx
  on public.court_members (court_id)
  where role = 'owner';

create index court_members_profile_idx on public.court_members (profile_id);

-- ============================================================================
-- subscriptions : owner pays admin to keep the court on the app
-- ============================================================================
create table public.subscriptions (
  id                 uuid primary key default gen_random_uuid(),
  court_id           uuid not null references public.courts (id) on delete cascade,
  plan               text not null check (plan in ('monthly','yearly')),
  status             text not null default 'active'
                       check (status in ('active','past_due','canceled')),
  current_period_end timestamptz,
  amount_cents       integer not null check (amount_cents >= 0),
  currency           text    not null default 'USD' check (length(currency) = 3),
  provider           text    not null default 'mock'
                       check (provider in ('mock','stripe','gcash','maya','offline')),
  provider_sub_id    text,
  created_at         timestamptz not null default now()
);

create index subscriptions_court_idx  on public.subscriptions (court_id);
create index subscriptions_status_idx on public.subscriptions (status);

-- ============================================================================
-- matchmaking_requests : a player wanting a game (matchmaking input)
-- ============================================================================
create table public.matchmaking_requests (
  id                 uuid primary key default gen_random_uuid(),
  court_id           uuid not null references public.courts (id) on delete cascade,
  profile_id         uuid not null references public.profiles (id) on delete cascade,
  party_size_wanted  smallint not null check (party_size_wanted in (1,2)),
  partner_profile_id uuid     references public.profiles (id) on delete set null,
  status             text not null default 'open'
                       check (status in ('open','matched','expired','canceled')),
  mmr_at_request     integer not null default 1000,
  created_at         timestamptz not null default now()
);

create index mmr_req_open_idx
  on public.matchmaking_requests (court_id, created_at)
  where status = 'open';
create index mmr_req_profile_idx on public.matchmaking_requests (profile_id);

-- ============================================================================
-- match_groups : the formed group of 4
-- ============================================================================
create table public.match_groups (
  id          uuid primary key default gen_random_uuid(),
  court_id    uuid not null references public.courts (id) on delete cascade,
  status      text not null default 'forming'
                check (status in ('forming','queued','assigned','playing','done')),
  slot_label  text,
  created_at  timestamptz not null default now()
);

create index match_groups_court_idx   on public.match_groups (court_id);
create index match_groups_status_idx  on public.match_groups (status);

-- ============================================================================
-- match_group_members : who's in a group
-- ============================================================================
create table public.match_group_members (
  match_group_id     uuid not null references public.match_groups (id) on delete cascade,
  profile_id         uuid not null references public.profiles (id) on delete cascade,
  is_initiator       boolean not null default false,
  is_invited_partner boolean not null default false,
  primary key (match_group_id, profile_id)
);

create index mgm_profile_idx on public.match_group_members (profile_id);

-- ============================================================================
-- court_slots : a physical court surface + its current state
-- ============================================================================
create table public.court_slots (
  id               uuid primary key default gen_random_uuid(),
  court_id         uuid not null references public.courts (id) on delete cascade,
  label            text not null,                       -- "Court 1", "Court 2"
  status           text not null default 'open'
                     check (status in ('open','occupied','closed')),
  current_group_id uuid references public.match_groups (id) on delete set null,
  updated_at       timestamptz not null default now()
);

create index court_slots_court_idx  on public.court_slots (court_id);

-- ============================================================================
-- queue_entries : a group waiting for a slot
-- ============================================================================
create table public.queue_entries (
  match_group_id uuid primary key references public.match_groups (id) on delete cascade,
  court_id       uuid not null references public.courts (id) on delete cascade,
  position       integer not null,
  enqueued_at    timestamptz not null default now()
);

create index queue_entries_court_idx on public.queue_entries (court_id, position);

-- ============================================================================
-- matches : the played game + result
-- ============================================================================
create table public.matches (
  id             uuid primary key default gen_random_uuid(),
  match_group_id uuid not null references public.match_groups (id) on delete cascade,
  court_id       uuid not null references public.courts (id) on delete cascade,
  played_at      timestamptz not null default now(),
  status         text not null default 'pending_confirm'
                   check (status in ('pending_confirm','completed','disputed')),
  winning_team   smallint check (winning_team in (1,2))
);

create index matches_court_idx on public.matches (court_id);
create index matches_status_idx on public.matches (status);

-- ============================================================================
-- match_results : per-player outcome for MMR (Elo)
-- ============================================================================
create table public.match_results (
  match_id    uuid not null references public.matches (id) on delete cascade,
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  team        smallint not null check (team in (1,2)),
  result      text not null check (result in ('win','loss')),
  mmr_before  integer not null,
  mmr_after   integer not null,
  primary key (match_id, profile_id)
);

create index match_results_profile_idx on public.match_results (profile_id);

-- ============================================================================
-- payments : every money event (entry | subscription | offline)
-- ============================================================================
create table public.payments (
  id                    uuid primary key default gen_random_uuid(),
  payer_profile_id      uuid references public.profiles (id) on delete set null,
  payee_court_id        uuid not null references public.courts (id) on delete cascade,
  kind                  text not null check (kind in ('entry','subscription')),
  amount_cents          integer not null check (amount_cents >= 0),
  currency              text not null default 'USD' check (length(currency) = 3),
  status                text not null default 'pending'
                          check (status in ('pending','paid','failed','refunded')),
  provider              text not null default 'mock'
                          check (provider in ('mock','stripe','gcash','maya','offline')),
  provider_ref          text,
  collected_by_member_id uuid,  -- references court_members(composite); enforced by app/RLS
  created_at            timestamptz not null default now()
);

create index payments_payer_idx   on public.payments (payer_profile_id);
create index payments_court_idx   on public.payments (payee_court_id);
create index payments_kind_idx    on public.payments (kind);
create index payments_status_idx  on public.payments (status);

-- ============================================================================
-- updated_at maintenance
-- ============================================================================
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch  before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger courts_touch    before update on public.courts
  for each row execute function public.touch_updated_at();
create trigger court_slots_touch before update on public.court_slots
  for each row execute function public.touch_updated_at();

-- ============================================================================
-- Enable RLS on every table. Policies are defined in 0002_rls_policies.sql.
-- ============================================================================
alter table public.profiles              enable row level security;
alter table public.courts                enable row level security;
alter table public.court_members         enable row level security;
alter table public.subscriptions         enable row level security;
alter table public.matchmaking_requests  enable row level security;
alter table public.match_groups          enable row level security;
alter table public.match_group_members   enable row level security;
alter table public.court_slots           enable row level security;
alter table public.queue_entries         enable row level security;
alter table public.matches               enable row level security;
alter table public.match_results         enable row level security;
alter table public.payments              enable row level security;

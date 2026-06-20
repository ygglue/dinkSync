-- 0000_extensions.sql
-- Extensions dinkSync depends on.
-- pg_cron : drives the matchmaking sweep schedule (see 0003_matchmaking_rpc.sql)
-- pgjwt   : token/url helpers (Supabase Auth uses this; harmless to enable)

create extension if not exists "pg_cron"            with schema extensions;
create extension if not exists "pgjwt"               with schema extensions;

-- pg_cron jobs run in the default database. The Supabase-managed extension
-- schema is `extensions`, so we reference it via the cron schema alias.
-- The actual schedule is created in 0003_matchmaking_rpc.sql once the
-- sweep function exists.

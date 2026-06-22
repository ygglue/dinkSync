-- 0009_court_image_url.sql
-- Adds an optional cover image URL to courts.
-- Owners set this via the dashboard (future); players see it on discovery cards.
alter table public.courts add column image_url text;

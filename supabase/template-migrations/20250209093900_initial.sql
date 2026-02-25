-- ============================================================
-- CondoLand — Initial Supabase Migration
-- ============================================================
-- Run this in your Supabase SQL editor (Dashboard > SQL Editor)
-- or via the Supabase CLI: supabase db push
-- ============================================================

-- ── Favorites Table ─────────────────────────────────────────

create table if not exists public.favorites (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  project_id int not null,
  project_name text,
  project_image_url text,
  floorplan_id int,
  floorplan_name text,
  floorplan_image_url text,
  favorite_type text not null check (favorite_type in ('project', 'floorplan')),
  created_at timestamptz default now() not null
);

-- Prevent duplicate favorites per user
create unique index if not exists favorites_unique_project
  on public.favorites (user_id, project_id)
  where favorite_type = 'project';

create unique index if not exists favorites_unique_floorplan
  on public.favorites (user_id, floorplan_id)
  where favorite_type = 'floorplan';

-- Fast lookup by user
create index if not exists favorites_user_id_idx
  on public.favorites (user_id);

-- Row Level Security
alter table public.favorites enable row level security;

-- Users can only see their own favorites
create policy "Users can view own favorites"
  on public.favorites for select
  using (auth.uid() = user_id);

-- Users can insert their own favorites
create policy "Users can insert own favorites"
  on public.favorites for insert
  with check (auth.uid() = user_id);

-- Users can delete their own favorites
create policy "Users can delete own favorites"
  on public.favorites for delete
  using (auth.uid() = user_id);


-- ── Likes Table ─────────────────────────────────────────────

create table if not exists public.likes (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  entity_id int not null,
  entity_type text not null check (entity_type in ('project', 'floorplan')),
  created_at timestamptz default now() not null
);

-- Prevent duplicate likes per user per entity
create unique index if not exists likes_unique_per_user
  on public.likes (user_id, entity_id, entity_type);

-- Fast lookup by user
create index if not exists likes_user_id_idx
  on public.likes (user_id);

-- Fast count lookups by entity
create index if not exists likes_entity_idx
  on public.likes (entity_type, entity_id);

-- Row Level Security
alter table public.likes enable row level security;

-- Users can see their own likes
create policy "Users can view own likes"
  on public.likes for select
  using (auth.uid() = user_id);

-- Users can insert their own likes
create policy "Users can insert own likes"
  on public.likes for insert
  with check (auth.uid() = user_id);

-- Users can delete their own likes
create policy "Users can delete own likes"
  on public.likes for delete
  using (auth.uid() = user_id);


-- ── Like Counts (Materialized View) ────────────────────────
-- Public-facing aggregated like counts.
-- Refresh periodically or after bulk operations.

create materialized view if not exists public.like_counts as
  select
    entity_id,
    entity_type,
    count(*)::int as count
  from public.likes
  group by entity_id, entity_type;

-- Index for fast lookups
create unique index if not exists like_counts_entity_idx
  on public.like_counts (entity_type, entity_id);

-- Grant public read access to like_counts (no auth required)
grant select on public.like_counts to anon, authenticated;

-- ── Refresh function for like_counts ────────────────────────
-- Call this after insert/delete on likes to keep counts fresh.
-- You can also set up a cron job via pg_cron extension.

create or replace function public.refresh_like_counts()
returns void as $$
begin
  refresh materialized view concurrently public.like_counts;
end;
$$ language plpgsql security definer;

-- Grant execute to authenticated users
grant execute on function public.refresh_like_counts() to authenticated;


-- ============================================================
-- Done! Your Supabase database is ready for CondoLand.
-- ============================================================

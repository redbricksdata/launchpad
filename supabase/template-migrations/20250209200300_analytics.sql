-- ============================================================
-- CondoLand — Analytics / Page View Tracking Migration
-- ============================================================
-- Run this in your Supabase SQL editor (Dashboard > SQL Editor)
-- or via the Supabase CLI: supabase db push
-- ============================================================

-- ── Page Views Table ────────────────────────────────────────
-- Append-only log of every project/floorplan page view.
-- Tracks both anonymous visitors (via cookie-based visitor_id)
-- and authenticated users (via user_id + email).

create table if not exists public.page_views (
  id uuid default gen_random_uuid() primary key,
  visitor_id text not null,
  user_id uuid references auth.users(id) on delete set null,
  user_email text,
  entity_type text not null check (entity_type in ('project', 'floorplan')),
  entity_id int not null,
  entity_name text not null,
  entity_meta jsonb default '{}',
  created_at timestamptz default now() not null
);

-- ── Indexes ─────────────────────────────────────────────────

-- Admin dashboard: recent views, sorted by time
create index if not exists page_views_created_at_idx
  on public.page_views (created_at desc);

-- Top projects / floorplans queries
create index if not exists page_views_entity_idx
  on public.page_views (entity_type, entity_id);

-- Per-visitor activity lookup
create index if not exists page_views_visitor_idx
  on public.page_views (visitor_id);

-- Per-user activity lookup (only rows with a user)
create index if not exists page_views_user_idx
  on public.page_views (user_id)
  where user_id is not null;

-- ── RLS Policies ────────────────────────────────────────────

alter table public.page_views enable row level security;

-- Anyone can insert (the /api/track endpoint writes via anon or authenticated)
create policy "Anyone can insert page views"
  on public.page_views for insert
  with check (true);

-- Only admins can read (for the analytics dashboard)
create policy "Admins can read page views"
  on public.page_views for select
  using (public.is_admin());

-- No update or delete — append-only log

-- ── Grants ──────────────────────────────────────────────────

grant insert on public.page_views to anon, authenticated;
grant select on public.page_views to authenticated;

-- ── Auto-Purge Function (optional) ─────────────────────────
-- Call this periodically to remove views older than 90 days.
-- You can set up a Supabase cron job or call it manually:
--   SELECT public.purge_old_page_views();

create or replace function public.purge_old_page_views()
returns void as $$
begin
  delete from public.page_views
  where created_at < now() - interval '90 days';
end;
$$ language plpgsql security definer;

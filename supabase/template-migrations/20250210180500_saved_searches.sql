-- ============================================================
-- CondoLand — Saved Searches
-- ============================================================
-- Users save filter criteria from the map or search page.
-- New project matches trigger email notifications.
-- ============================================================

-- ── saved_searches: user-saved filter criteria ──────────────
create table public.saved_searches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  filters jsonb not null,
  source text default 'map' check (source in ('map', 'search')),
  notify boolean default true,
  last_matched_at timestamptz,
  last_match_count int default 0,
  created_at timestamptz not null default now()
);

create index idx_saved_searches_user
  on public.saved_searches (user_id);

create index idx_saved_searches_notify
  on public.saved_searches (notify)
  where notify = true;

-- ── saved_search_matches: which projects each search has seen ──
create table public.saved_search_matches (
  id uuid primary key default gen_random_uuid(),
  search_id uuid references public.saved_searches(id) on delete cascade not null,
  project_id int not null,
  first_matched_at timestamptz not null default now()
);

create unique index idx_search_matches_unique
  on public.saved_search_matches (search_id, project_id);

-- ── RLS Policies ────────────────────────────────────────────

alter table public.saved_searches enable row level security;

create policy "Users can view own saved searches"
  on public.saved_searches for select
  using (auth.uid() = user_id);

create policy "Users can insert own saved searches"
  on public.saved_searches for insert
  with check (auth.uid() = user_id);

create policy "Users can update own saved searches"
  on public.saved_searches for update
  using (auth.uid() = user_id);

create policy "Users can delete own saved searches"
  on public.saved_searches for delete
  using (auth.uid() = user_id);

create policy "Service can read saved searches for matching"
  on public.saved_searches for select
  using (true);

alter table public.saved_search_matches enable row level security;

create policy "Service can insert matches"
  on public.saved_search_matches for insert
  with check (true);

create policy "Service can read matches"
  on public.saved_search_matches for select
  using (true);

create policy "Admins can read all saved searches"
  on public.saved_searches for select
  using (public.is_admin());

create policy "Admins can read all matches"
  on public.saved_search_matches for select
  using (public.is_admin());

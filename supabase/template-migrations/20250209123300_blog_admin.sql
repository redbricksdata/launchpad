-- ============================================================
-- CondoLand — Blog Admin CMS Migration
-- ============================================================
-- Run this in your Supabase SQL editor (Dashboard > SQL Editor)
-- or via the Supabase CLI: supabase db push
-- ============================================================

-- ── Admins Table ──────────────────────────────────────────────
-- Simple email-based admin lookup. Insert your email here to
-- become an admin.

create table if not exists public.admins (
  id uuid default gen_random_uuid() primary key,
  email text not null unique,
  created_at timestamptz default now() not null
);

-- ── is_admin() helper ─────────────────────────────────────────
-- Returns true when the current JWT email is in the admins table.
-- Used by RLS policies on blog_posts and admins.

create or replace function public.is_admin()
returns boolean as $$
begin
  return exists (
    select 1 from public.admins
    where email = (auth.jwt() ->> 'email')
  );
end;
$$ language plpgsql security definer;

-- RLS on admins — only admins can see/manage the admin list
alter table public.admins enable row level security;

create policy "Admins can view admin list"
  on public.admins for select
  using (public.is_admin());

create policy "Admins can insert admins"
  on public.admins for insert
  with check (public.is_admin());

create policy "Admins can delete admins"
  on public.admins for delete
  using (public.is_admin());


-- ── Blog Posts Table ──────────────────────────────────────────

create table if not exists public.blog_posts (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  slug text not null unique,
  description text not null default '',
  content text not null default '',
  author text not null default 'Team',
  image text,
  tags text[] default '{}',
  published boolean default false,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

-- Index for slug lookups
create index if not exists blog_posts_slug_idx
  on public.blog_posts (slug);

-- Index for listing published posts by date
create index if not exists blog_posts_published_idx
  on public.blog_posts (published, created_at desc);

-- Auto-update updated_at on row change
create or replace function public.update_blog_posts_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger blog_posts_updated_at
  before update on public.blog_posts
  for each row
  execute function public.update_blog_posts_updated_at();

-- RLS on blog_posts
alter table public.blog_posts enable row level security;

-- Anyone can read published posts; admins can read all
create policy "Public can read published posts"
  on public.blog_posts for select
  using (published = true or public.is_admin());

-- Only admins can insert
create policy "Admins can insert posts"
  on public.blog_posts for insert
  with check (public.is_admin());

-- Only admins can update
create policy "Admins can update posts"
  on public.blog_posts for update
  using (public.is_admin())
  with check (public.is_admin());

-- Only admins can delete
create policy "Admins can delete posts"
  on public.blog_posts for delete
  using (public.is_admin());

-- Grant anon + authenticated read access to blog_posts
grant select on public.blog_posts to anon, authenticated;
grant all on public.blog_posts to authenticated;
grant select on public.admins to authenticated;


-- ============================================================
-- IMPORTANT: After running this migration, insert your admin
-- email into the admins table using the Supabase SQL editor:
--
--   INSERT INTO public.admins (email) VALUES ('your@email.com');
--
-- This is a one-time setup step done directly in the database.
-- ============================================================

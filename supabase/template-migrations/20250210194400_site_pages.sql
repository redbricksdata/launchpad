-- ============================================================
-- Site Pages — Editable standard pages + custom pages CMS
-- ============================================================

create table public.site_pages (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  subtitle text,
  content_type text not null check (content_type in (
    'rich_text', 'sectioned', 'team', 'contact'
  )),
  content_json jsonb not null default '{}',
  published boolean default true,
  is_builtin boolean default false,
  show_in_nav boolean default false,
  sort_order int default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_site_pages_slug on public.site_pages (slug);
create index idx_site_pages_sort on public.site_pages (sort_order);

-- RLS
alter table public.site_pages enable row level security;

-- Public can read published pages
create policy "Public can read published pages"
  on public.site_pages for select
  using (published = true or public.is_admin());

-- Admins can insert pages
create policy "Admins can insert pages"
  on public.site_pages for insert
  with check (public.is_admin());

-- Admins can update pages
create policy "Admins can update pages"
  on public.site_pages for update
  using (public.is_admin())
  with check (public.is_admin());

-- Admins can delete pages
create policy "Admins can delete pages"
  on public.site_pages for delete
  using (public.is_admin());

-- Seed built-in pages with empty content (falls back to TypeScript defaults)
insert into public.site_pages (slug, title, subtitle, content_type, content_json, is_builtin, sort_order) values
  ('about', 'About Us', 'Your trusted source for pre-construction real estate listings.', 'rich_text', '{"paragraphs":[],"stats":[]}', true, 1),
  ('team', 'Our Team', 'Meet the people behind the platform.', 'team', '{"members":[]}', true, 2),
  ('contact', 'Contact Us', 'Have a question or need help? We''d love to hear from you.', 'contact', '{"email":"","phone":"","address":""}', true, 3),
  ('privacy', 'Privacy Policy', null, 'sectioned', '{"lastUpdated":"","sections":[]}', true, 4),
  ('terms', 'Terms of Service', null, 'sectioned', '{"lastUpdated":"","sections":[]}', true, 5);

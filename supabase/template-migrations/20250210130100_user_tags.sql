-- ============================================================
-- CondoLand — User Tags Migration
-- ============================================================
-- Allows admins to tag users/visitors for organization and grouping.
-- Tags are freeform text, with autocomplete from previously used tags.
-- ============================================================

create table if not exists public.user_tags (
  id uuid primary key default gen_random_uuid(),
  -- The subject: either a user_id (UUID) or visitor_id (string)
  subject_identifier text not null,
  tag text not null,
  admin_email text not null,
  created_at timestamptz default now() not null,
  -- Prevent duplicate tags on the same user
  unique (subject_identifier, tag)
);

-- ── Indexes ───────────────────────────────────────────────────
create index if not exists idx_user_tags_subject
  on public.user_tags (subject_identifier);

create index if not exists idx_user_tags_tag
  on public.user_tags (tag);

create index if not exists idx_user_tags_created
  on public.user_tags (created_at desc);

-- ── RLS ───────────────────────────────────────────────────────
alter table public.user_tags enable row level security;

create policy "Admins can insert tags"
  on public.user_tags for insert
  with check (public.is_admin());

create policy "Admins can read tags"
  on public.user_tags for select
  using (public.is_admin());

create policy "Admins can delete tags"
  on public.user_tags for delete
  using (public.is_admin());

-- ── Grants ────────────────────────────────────────────────────
grant insert, select, delete on public.user_tags to authenticated;

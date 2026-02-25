-- ============================================================
-- CondoLand — Admin Notes Migration
-- ============================================================
-- Allows admins to add timestamped notes to user/visitor profiles.
-- ============================================================

create table if not exists public.admin_notes (
  id uuid primary key default gen_random_uuid(),
  -- The subject of the note: either a user_id (UUID) or visitor_id (string)
  subject_identifier text not null,
  -- The admin who wrote the note
  admin_email text not null,
  content text not null,
  created_at timestamptz default now() not null
);

-- ── Indexes ───────────────────────────────────────────────────
create index if not exists idx_admin_notes_subject
  on public.admin_notes (subject_identifier);

create index if not exists idx_admin_notes_created
  on public.admin_notes (created_at desc);

-- ── RLS ───────────────────────────────────────────────────────
alter table public.admin_notes enable row level security;

-- Only admins can insert
create policy "Admins can insert notes"
  on public.admin_notes for insert
  with check (public.is_admin());

-- Only admins can read
create policy "Admins can read notes"
  on public.admin_notes for select
  using (public.is_admin());

-- Only admins can delete their own notes
create policy "Admins can delete own notes"
  on public.admin_notes for delete
  using (public.is_admin());

-- ── Grants ────────────────────────────────────────────────────
grant insert, select, delete on public.admin_notes to authenticated;

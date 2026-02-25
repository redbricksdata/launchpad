-- ============================================================
-- CondoLand — Appointments Migration
-- ============================================================
-- Adds an appointments table for booking consultations.
-- ============================================================

-- ── Appointments Table ────────────────────────────────────────
create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  visitor_id text not null,
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  email text not null,
  phone text,
  project_id int,
  project_name text,
  floorplan_name text,
  appointment_type text not null check (appointment_type in ('phone', 'in_person')),
  preferred_date date not null,
  preferred_time text not null check (preferred_time in ('morning', 'afternoon', 'evening')),
  notes text,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'completed', 'cancelled')),
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

-- ── Indexes ───────────────────────────────────────────────────
create index if not exists idx_appointments_status
  on public.appointments (status);

create index if not exists idx_appointments_created
  on public.appointments (created_at desc);

create index if not exists idx_appointments_user
  on public.appointments (user_id)
  where user_id is not null;

create index if not exists idx_appointments_visitor
  on public.appointments (visitor_id);

-- ── RLS ───────────────────────────────────────────────────────
alter table public.appointments enable row level security;

-- Anyone can insert (public booking form)
create policy "Anyone can insert appointments"
  on public.appointments for insert
  with check (true);

-- Only admins can read
create policy "Admins can read appointments"
  on public.appointments for select
  using (public.is_admin());

-- Only admins can update (status changes)
create policy "Admins can update appointments"
  on public.appointments for update
  using (public.is_admin());

-- ── Grants ────────────────────────────────────────────────────
grant insert on public.appointments to anon, authenticated;
grant select, update on public.appointments to authenticated;

-- ── Expand page_views entity_type ─────────────────────────────
alter table public.page_views drop constraint if exists page_views_entity_type_check;
alter table public.page_views add constraint page_views_entity_type_check
  check (entity_type in ('project', 'floorplan', 'contact_request', 'share', 'appointment'));

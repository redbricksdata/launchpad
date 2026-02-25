-- ============================================================
-- CondoLand — Drip Sequences / Automated Follow-ups
-- ============================================================
-- Admin-configured email sequences triggered by user actions.
-- Emails send automatically on a schedule via cron processor.
-- ============================================================

-- ── drip_sequences: automation sequences configured by admin ─
create table public.drip_sequences (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  trigger_type text not null check (trigger_type in (
    'appointment_booked', 'contact_request', 'project_favorited', 'high_engagement'
  )),
  trigger_config jsonb default '{}',
  enabled boolean default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ── drip_steps: individual emails within a sequence ─────────
create table public.drip_steps (
  id uuid primary key default gen_random_uuid(),
  sequence_id uuid references public.drip_sequences(id) on delete cascade not null,
  step_order int not null,
  delay_hours int not null default 24,
  subject text not null,
  body_html text not null,
  enabled boolean default true,
  created_at timestamptz not null default now()
);

create index idx_drip_steps_sequence
  on public.drip_steps (sequence_id, step_order);

-- ── drip_enrollments: users enrolled in a sequence ──────────
create table public.drip_enrollments (
  id uuid primary key default gen_random_uuid(),
  sequence_id uuid references public.drip_sequences(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade,
  visitor_id text,
  email text not null,
  name text,
  trigger_data jsonb default '{}',
  current_step int default 0,
  status text default 'active' check (status in ('active', 'completed', 'paused', 'cancelled')),
  enrolled_at timestamptz not null default now(),
  next_send_at timestamptz,
  completed_at timestamptz
);

create index idx_enrollments_next_send
  on public.drip_enrollments (next_send_at)
  where status = 'active';

create index idx_enrollments_sequence
  on public.drip_enrollments (sequence_id, status);

-- Prevent double-enrollment in same sequence
create unique index idx_enrollments_unique
  on public.drip_enrollments (sequence_id, email);

-- ── drip_sends: log of every email sent ─────────────────────
create table public.drip_sends (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid references public.drip_enrollments(id) on delete cascade not null,
  step_id uuid references public.drip_steps(id),
  email text not null,
  subject text not null,
  status text default 'sent' check (status in ('sent', 'failed', 'opened', 'clicked')),
  sent_at timestamptz not null default now()
);

create index idx_drip_sends_enrollment
  on public.drip_sends (enrollment_id, sent_at desc);

-- ── RLS Policies ────────────────────────────────────────────

alter table public.drip_sequences enable row level security;

create policy "Admins can manage drip sequences"
  on public.drip_sequences for all
  using (public.is_admin());

create policy "Service can read drip sequences"
  on public.drip_sequences for select
  using (true);

alter table public.drip_steps enable row level security;

create policy "Admins can manage drip steps"
  on public.drip_steps for all
  using (public.is_admin());

create policy "Service can read drip steps"
  on public.drip_steps for select
  using (true);

alter table public.drip_enrollments enable row level security;

create policy "Admins can manage enrollments"
  on public.drip_enrollments for all
  using (public.is_admin());

create policy "Service can manage enrollments"
  on public.drip_enrollments for all
  using (true);

alter table public.drip_sends enable row level security;

create policy "Admins can read drip sends"
  on public.drip_sends for select
  using (public.is_admin());

create policy "Service can insert drip sends"
  on public.drip_sends for insert
  with check (true);

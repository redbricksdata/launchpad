-- ============================================================
-- CondoLand — Project Alerts & Webhook Infrastructure
-- ============================================================
-- Stores incoming webhook events, detected project changes,
-- user email preferences, and alert send logs.
-- ============================================================

-- ── webhook_events: raw log of every webhook received ───────
-- Serves as audit trail and enables replay if processing fails.
create table public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'redbricks',
  event_type text not null,
  payload jsonb not null default '{}',
  project_id int,
  processed boolean default false,
  created_at timestamptz not null default now()
);

create index idx_webhook_events_type
  on public.webhook_events (event_type, created_at desc);

create index idx_webhook_events_project
  on public.webhook_events (project_id)
  where project_id is not null;

-- ── project_alert_log: meaningful detected changes ──────────
create table public.project_alert_log (
  id uuid primary key default gen_random_uuid(),
  webhook_event_id uuid references public.webhook_events(id),
  project_id int not null,
  project_name text not null,
  change_type text not null check (change_type in (
    'price_drop', 'price_increase', 'status_change',
    'new_floorplans', 'floorplan_updated', 'new_project'
  )),
  old_value text,
  new_value text,
  notified_count int default 0,
  created_at timestamptz not null default now()
);

create index idx_alert_log_project
  on public.project_alert_log (project_id, created_at desc);

-- ── email_preferences: user opt-in/out for alert types ──────
create table public.email_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  favorite_alerts boolean default true,
  saved_search_alerts boolean default true,
  drip_emails boolean default true,
  alert_frequency text default 'instant' check (
    alert_frequency in ('instant', 'daily', 'weekly', 'off')
  ),
  unsubscribe_token text default encode(gen_random_bytes(32), 'hex'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index idx_email_prefs_user
  on public.email_preferences (user_id);

create unique index idx_email_prefs_token
  on public.email_preferences (unsubscribe_token);

-- ── alert_sends: log of individual emails sent ──────────────
-- Prevents duplicate sends and provides audit trail.
create table public.alert_sends (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  alert_log_id uuid references public.project_alert_log(id),
  email_type text not null,
  project_id int,
  sent_at timestamptz not null default now()
);

create index idx_alert_sends_user
  on public.alert_sends (user_id, email_type, sent_at desc);

-- ── RLS Policies ────────────────────────────────────────────

-- webhook_events: admin-only read, service-role insert
alter table public.webhook_events enable row level security;

create policy "Admins can read webhook events"
  on public.webhook_events for select
  using (public.is_admin());

create policy "Service can insert webhook events"
  on public.webhook_events for insert
  with check (true);

create policy "Service can update webhook events"
  on public.webhook_events for update
  using (true);

-- project_alert_log: admin-only read, service-role insert
alter table public.project_alert_log enable row level security;

create policy "Admins can read alert log"
  on public.project_alert_log for select
  using (public.is_admin());

create policy "Service can insert alert log"
  on public.project_alert_log for insert
  with check (true);

create policy "Service can update alert log"
  on public.project_alert_log for update
  using (true);

-- email_preferences: users own, admins read all
alter table public.email_preferences enable row level security;

create policy "Users can view own preferences"
  on public.email_preferences for select
  using (auth.uid() = user_id);

create policy "Users can insert own preferences"
  on public.email_preferences for insert
  with check (auth.uid() = user_id);

create policy "Users can update own preferences"
  on public.email_preferences for update
  using (auth.uid() = user_id);

create policy "Admins can read all preferences"
  on public.email_preferences for select
  using (public.is_admin());

create policy "Service can read preferences for alerts"
  on public.email_preferences for select
  using (true);

-- alert_sends: admin-only read, service insert
alter table public.alert_sends enable row level security;

create policy "Admins can read alert sends"
  on public.alert_sends for select
  using (public.is_admin());

create policy "Service can insert alert sends"
  on public.alert_sends for insert
  with check (true);

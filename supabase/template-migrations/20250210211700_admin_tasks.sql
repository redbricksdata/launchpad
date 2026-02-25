-- Migration 019: Admin Tasks / Reminders
-- Task list tied to user profiles for agent follow-ups and reminders.

CREATE TABLE public.admin_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_identifier text,          -- user_id or visitor_id (nullable for general tasks)
  subject_name text,                -- display name for quick reference
  admin_email text NOT NULL,
  title text NOT NULL,
  description text,
  due_date date,
  due_time time,
  priority text DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'completed')),
  completed_at timestamptz,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX idx_admin_tasks_status_due ON public.admin_tasks(status, due_date);
CREATE INDEX idx_admin_tasks_subject ON public.admin_tasks(subject_identifier) WHERE subject_identifier IS NOT NULL;

ALTER TABLE public.admin_tasks ENABLE ROW LEVEL SECURITY;

-- Admin-only: full access
CREATE POLICY "Admins can manage tasks"
  ON public.admin_tasks
  FOR ALL
  USING (public.is_admin());

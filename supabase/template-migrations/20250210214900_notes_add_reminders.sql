-- ============================================================
-- 021: Add Reminder fields to Admin Notes
-- Merges the standalone tasks system into notes.
-- Any note can optionally become a reminder with a due date.
-- ============================================================

-- Add reminder columns to admin_notes
ALTER TABLE public.admin_notes
  ADD COLUMN IF NOT EXISTS reminder_date date,
  ADD COLUMN IF NOT EXISTS reminder_time time,
  ADD COLUMN IF NOT EXISTS reminder_priority text DEFAULT 'normal'
    CHECK (reminder_priority IN ('low','normal','high','urgent')),
  ADD COLUMN IF NOT EXISTS reminder_completed boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS reminder_completed_at timestamptz;

-- Index for the reminders view (pending reminders ordered by date)
CREATE INDEX IF NOT EXISTS idx_admin_notes_reminders
  ON public.admin_notes(reminder_date, reminder_completed)
  WHERE reminder_date IS NOT NULL;

-- Drop the standalone tasks table (no longer needed)
DROP TABLE IF EXISTS public.admin_tasks;

-- ============================================================
-- In-App Notifications Table
-- Stores user-facing notifications for the notification center
-- (bell icon dropdown in the header).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,

  -- Notification content
  type text NOT NULL CHECK (type IN (
    'price_drop', 'price_increase', 'status_change',
    'new_floorplans', 'floorplan_updated', 'new_project',
    'saved_search_match', 'chat_reply', 'appointment_reminder',
    'welcome', 'general'
  )),
  title text NOT NULL,
  body text,
  icon text,           -- emoji or icon identifier
  href text,           -- link to navigate to on click

  -- Related entities
  project_id int,
  project_name text,

  -- State
  is_read boolean DEFAULT false,
  read_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for fast user queries
CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON public.notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON public.notifications (user_id, is_read)
  WHERE is_read = false;

-- RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own notifications"
  ON public.notifications
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update own notifications"
  ON public.notifications
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Service role can insert (from API routes)
CREATE POLICY "Service role can insert notifications"
  ON public.notifications
  FOR INSERT
  WITH CHECK (true);

-- Auto-cleanup: delete notifications older than 90 days
-- (run via a scheduled function or manual cleanup)

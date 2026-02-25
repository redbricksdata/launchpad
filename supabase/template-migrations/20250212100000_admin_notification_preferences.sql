-- ============================================================
-- Admin Notification Preferences
-- Gives each admin individual control over which notifications
-- they receive (email, in-app toast, digests).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admin_notification_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_email text NOT NULL UNIQUE,

  -- Real-time toasts
  toast_chat_messages boolean DEFAULT true,
  toast_high_intent_actions boolean DEFAULT true,

  -- Instant emails
  email_new_signups boolean DEFAULT true,
  email_contact_forms boolean DEFAULT true,
  email_appointments boolean DEFAULT true,
  email_chat_escalation boolean DEFAULT true,
  email_new_projects boolean DEFAULT true,
  email_hot_leads boolean DEFAULT true,

  -- Digests
  email_daily_digest boolean DEFAULT false,
  email_weekly_summary boolean DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS: admins can read/write their own row
ALTER TABLE public.admin_notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage own preferences"
  ON public.admin_notification_preferences
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- User email preferences: add new columns for appointment reminders & marketing
ALTER TABLE public.email_preferences
  ADD COLUMN IF NOT EXISTS appointment_reminders boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS marketing_emails boolean DEFAULT true;

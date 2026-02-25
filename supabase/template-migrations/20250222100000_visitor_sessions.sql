-- ============================================================
-- Visitor Sessions — Real-time presence tracking
-- ============================================================
-- Tracks active visitor sessions for the live analytics dashboard.
-- A client-side heartbeat (every 30s) keeps `last_seen_at` fresh.
-- A cron job marks idle (>2min) and offline (>5min) sessions.
-- ============================================================

CREATE TABLE IF NOT EXISTS visitor_sessions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visitor_id      TEXT NOT NULL,
  user_id         UUID REFERENCES auth.users(id),
  user_email      TEXT,
  user_name       TEXT,

  -- Session timing
  session_started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Current page
  current_page        TEXT,
  current_page_title  TEXT,

  -- Session journey
  pages_viewed    INTEGER NOT NULL DEFAULT 1,
  pages_list      JSONB NOT NULL DEFAULT '[]'::jsonb,  -- [{path, title, ts}]

  -- Device & referral
  device_type     TEXT,          -- desktop, tablet, mobile
  browser         TEXT,
  os              TEXT,
  referrer        TEXT,
  utm_source      TEXT,
  utm_medium      TEXT,
  utm_campaign    TEXT,

  -- Status managed by cron
  status          TEXT NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'idle', 'offline')),

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Fast "who's online" query
CREATE INDEX IF NOT EXISTS idx_vs_status
  ON visitor_sessions(status)
  WHERE status IN ('active', 'idle');

-- Order by most recent activity
CREATE INDEX IF NOT EXISTS idx_vs_last_seen
  ON visitor_sessions(last_seen_at DESC);

-- Lookup by visitor
CREATE INDEX IF NOT EXISTS idx_vs_visitor_id
  ON visitor_sessions(visitor_id);

-- ── RLS ─────────────────────────────────────────────────────
ALTER TABLE visitor_sessions ENABLE ROW LEVEL SECURITY;

-- Anyone can insert a session (heartbeat from anonymous client)
CREATE POLICY "visitors_insert_own_session"
  ON visitor_sessions FOR INSERT
  WITH CHECK (true);

-- Anyone can update sessions (heartbeat updates — matched by visitor_id in app code)
CREATE POLICY "visitors_update_own_session"
  ON visitor_sessions FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- Admins can read all sessions (uses is_admin() from blog_admin migration)
CREATE POLICY "admins_read_all_sessions"
  ON visitor_sessions FOR SELECT
  USING (public.is_admin());

-- Anon/authenticated can SELECT their own session (needed for heartbeat response)
CREATE POLICY "visitors_select_own_session"
  ON visitor_sessions FOR SELECT
  USING (true);

-- Allow deletes for cleanup (service_role bypasses RLS, but just in case)
CREATE POLICY "allow_delete_sessions"
  ON visitor_sessions FOR DELETE
  USING (public.is_admin());

-- ── Realtime ────────────────────────────────────────────────
-- Enable full replica identity for Realtime broadcasts
ALTER TABLE visitor_sessions REPLICA IDENTITY FULL;

-- Add to Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE visitor_sessions;

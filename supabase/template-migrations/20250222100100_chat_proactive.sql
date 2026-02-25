-- ============================================================
-- Chat — Admin-initiated (proactive) conversations
-- ============================================================
-- Adds two columns to chat_conversations:
--   initiated_by: 'visitor' (default) or 'admin'
--   accepted_at:  set when visitor acknowledges the proactive chat
-- ============================================================

ALTER TABLE chat_conversations
  ADD COLUMN IF NOT EXISTS initiated_by TEXT NOT NULL DEFAULT 'visitor'
    CHECK (initiated_by IN ('visitor', 'admin'));

ALTER TABLE chat_conversations
  ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

-- ============================================================
-- Add visitor_phone to chat_conversations
-- ============================================================
-- Stores the visitor's phone number collected from the pre-chat form.
-- ============================================================

alter table public.chat_conversations
  add column if not exists visitor_phone text;

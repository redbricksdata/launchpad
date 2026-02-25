-- ============================================================
-- Add telegram_topic_id to chat_conversations
-- ============================================================
-- Stores the Telegram Forum Topic thread ID for each conversation.
-- When Topics are enabled in the Telegram group, each website chat
-- conversation gets its own topic thread for a clean UX.
-- ============================================================

alter table public.chat_conversations
  add column if not exists telegram_topic_id integer;

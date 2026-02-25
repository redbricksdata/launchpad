-- ============================================================
-- Add current_page tracking to chat_conversations
-- ============================================================
-- Allows real-time display of which page a visitor is browsing
-- while chatting, giving admins more context.
-- ============================================================

-- Add current_page column (the page the visitor is currently on)
alter table public.chat_conversations
  add column if not exists current_page text;

-- Allow anon/visitors to update their own conversation's current_page
create policy "Visitors can update own conversation current_page"
  on chat_conversations for update
  using (true)
  with check (true);

-- Grant update permission to anon role
grant update on chat_conversations to anon;

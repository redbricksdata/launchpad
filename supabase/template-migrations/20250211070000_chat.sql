-- ============================================================
-- Live Chat System — Database Migration
-- ============================================================
-- Tables: chat_conversations, chat_messages, chat_settings
-- Features: RLS, auto-update trigger, Supabase Realtime
-- ============================================================

-- ── Chat Conversations ──────────────────────────────────────

create table if not exists public.chat_conversations (
  id uuid primary key default gen_random_uuid(),

  -- Link to visitor/user (same dual-identity pattern as page_views, appointments)
  visitor_id text not null,
  user_id uuid references auth.users(id) on delete set null,

  -- Denormalized display info
  visitor_name text,
  visitor_email text,

  -- Conversation state
  status text not null default 'open'
    check (status in ('open', 'closed', 'archived')),

  -- Which admin is handling this conversation (nullable = unassigned)
  assigned_admin_email text,

  -- Denormalized counters for efficient listing
  unread_count int not null default 0,
  last_message_text text,
  last_message_at timestamptz,

  -- Page the visitor was on when they started the chat
  started_on_page text,

  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

create index idx_chat_conversations_visitor
  on chat_conversations (visitor_id);

create index idx_chat_conversations_user
  on chat_conversations (user_id)
  where user_id is not null;

create index idx_chat_conversations_status
  on chat_conversations (status);

create index idx_chat_conversations_last_msg
  on chat_conversations (last_message_at desc nulls last);

-- ── Chat Messages ───────────────────────────────────────────

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references chat_conversations(id) on delete cascade,

  -- Who sent the message
  sender_type text not null
    check (sender_type in ('visitor', 'admin', 'system')),
  sender_id text,
  sender_name text,

  -- Message content
  content text not null,

  -- Read status
  is_read boolean not null default false,

  -- Source of message (web, telegram, email, system)
  source text not null default 'web'
    check (source in ('web', 'telegram', 'email', 'system')),

  -- Extra data (e.g. Telegram message_id for reply correlation)
  metadata jsonb default '{}',

  created_at timestamptz default now() not null
);

create index idx_chat_messages_conversation
  on chat_messages (conversation_id, created_at asc);

create index idx_chat_messages_unread
  on chat_messages (conversation_id, is_read)
  where is_read = false;

-- ── Chat Settings ───────────────────────────────────────────

create table if not exists public.chat_settings (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  value text not null,
  updated_at timestamptz default now() not null
);

-- Seed default settings
insert into chat_settings (key, value) values
  ('chat_greeting', 'Hi there! How can we help you today?'),
  ('chat_offline_message', 'We''re currently offline. Leave a message and we''ll get back to you soon!'),
  ('email_fallback_minutes', '5')
on conflict (key) do nothing;


-- ── Auto-update conversation on new message ─────────────────

create or replace function public.update_conversation_on_new_message()
returns trigger as $$
begin
  update chat_conversations
  set
    last_message_text = left(new.content, 100),
    last_message_at = new.created_at,
    updated_at = now(),
    unread_count = case
      when new.sender_type = 'visitor' then unread_count + 1
      else unread_count
    end
  where id = new.conversation_id;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_chat_message_inserted
  after insert on chat_messages
  for each row
  execute function update_conversation_on_new_message();


-- ── RLS: chat_conversations ─────────────────────────────────

alter table chat_conversations enable row level security;

-- Admins can do everything
create policy "Admins full access to chat_conversations"
  on chat_conversations for all
  using (public.is_admin());

-- Anyone can start a conversation
create policy "Anyone can insert chat_conversations"
  on chat_conversations for insert
  with check (true);

-- Anyone can read conversations (visitor filtering done by API layer)
create policy "Anyone can read chat_conversations"
  on chat_conversations for select
  using (true);

-- ── RLS: chat_messages ──────────────────────────────────────

alter table chat_messages enable row level security;

-- Admins can do everything
create policy "Admins full access to chat_messages"
  on chat_messages for all
  using (public.is_admin());

-- Anyone can send messages
create policy "Anyone can insert chat_messages"
  on chat_messages for insert
  with check (true);

-- Anyone can read messages (scoped by conversation_id they know)
create policy "Anyone can read chat_messages"
  on chat_messages for select
  using (true);

-- ── RLS: chat_settings ──────────────────────────────────────

alter table chat_settings enable row level security;

-- Only admins can manage settings
create policy "Admins can manage chat_settings"
  on chat_settings for all
  using (public.is_admin());

-- Allow authenticated users to read settings (for greeting message)
create policy "Authenticated can read chat_settings"
  on chat_settings for select
  using (true);

-- ── Grants ──────────────────────────────────────────────────

grant select, insert on chat_conversations to anon, authenticated;
grant all on chat_conversations to authenticated;

grant select, insert on chat_messages to anon, authenticated;
grant all on chat_messages to authenticated;

grant select on chat_settings to anon, authenticated;
grant all on chat_settings to authenticated;

-- ── Enable Supabase Realtime ────────────────────────────────

alter publication supabase_realtime add table chat_messages;
alter publication supabase_realtime add table chat_conversations;

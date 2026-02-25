-- Site-wide API key storage for AI providers (Gemini, OpenAI) and Email providers (Resend, SMTP)
-- Replaces per-user user_ai_keys table with admin-configured site-wide keys

-- 1. Create the site_api_keys table
create table public.site_api_keys (
  id uuid primary key default gen_random_uuid(),
  provider text not null unique,       -- 'gemini', 'openai', 'resend', 'smtp'
  encrypted_key text not null,         -- AES-256-GCM encrypted API key (or SMTP password)
  key_hint text,                       -- last 4 chars for display (e.g., "...ab1c")
  config jsonb default '{}',           -- non-secret config (SMTP: host, port, user, secure)
  is_active boolean default true,
  created_by text not null,            -- admin email who saved it
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- RLS: only admins can access
alter table public.site_api_keys enable row level security;

create policy "Admins manage site keys"
  on public.site_api_keys for all
  using (public.is_admin())
  with check (public.is_admin());

grant select, insert, update, delete on public.site_api_keys to authenticated;

-- 2. Drop the per-user BYOK table (just created, no production data)
drop table if exists public.user_ai_keys;

-- 3. Telegram cleanup: remove telegram_topic_id column from chat_conversations
alter table public.chat_conversations drop column if exists telegram_topic_id;

-- 4. Remove Telegram-specific settings from chat_settings
delete from public.chat_settings where key in ('telegram_bot_token', 'telegram_chat_id');

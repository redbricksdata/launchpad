-- User AI API keys for BYOK (Bring Your Own Key)
-- Keys are encrypted at rest with AES-256-GCM via the application layer.
-- The `encrypted_key` column stores the IV + ciphertext + auth tag, never plaintext.

create table public.user_ai_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  provider text not null check (provider in ('gemini', 'openai')),
  encrypted_key text not null,
  key_hint text,           -- last 4 chars of the key for display (e.g. "...ab1c")
  is_default boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (user_id, provider)
);

alter table public.user_ai_keys enable row level security;

-- Users can only manage their own keys
create policy "Users manage own keys"
  on public.user_ai_keys for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.user_ai_keys to authenticated;

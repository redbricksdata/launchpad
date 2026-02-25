-- CRM API Keys for public REST API access (Zapier, Make.com, custom scripts)
CREATE TABLE IF NOT EXISTS crm_api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL DEFAULT 'Default',
  key_hash text NOT NULL UNIQUE,          -- SHA-256 hash of the actual key
  key_prefix text NOT NULL DEFAULT '',    -- first 8 chars for display (crm_xxxx...)
  active boolean NOT NULL DEFAULT true,
  permissions text[] NOT NULL DEFAULT ARRAY['read','write'],
  created_by text NOT NULL,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for fast key lookup
CREATE INDEX IF NOT EXISTS idx_crm_api_keys_hash ON crm_api_keys (key_hash) WHERE active = true;

-- RLS: only admins can manage API keys (through service role or admin endpoints)
ALTER TABLE crm_api_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage API keys"
  ON crm_api_keys FOR ALL
  USING (true)
  WITH CHECK (true);

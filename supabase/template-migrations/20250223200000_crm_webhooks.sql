-- Outgoing webhook configuration
CREATE TABLE IF NOT EXISTS crm_webhooks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  url text NOT NULL,
  secret text NOT NULL,          -- HMAC-SHA256 signing key
  events text[] NOT NULL DEFAULT ARRAY['contact_created'],
  active boolean NOT NULL DEFAULT true,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Delivery log for each webhook attempt
CREATE TABLE IF NOT EXISTS crm_webhook_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id uuid NOT NULL REFERENCES crm_webhooks(id) ON DELETE CASCADE,
  event text NOT NULL,
  payload jsonb NOT NULL,
  status_code int,
  response_body text,
  success boolean NOT NULL DEFAULT false,
  attempt int NOT NULL DEFAULT 1,
  next_retry_at timestamptz,
  delivered_at timestamptz NOT NULL DEFAULT now()
);

-- Index for retry cron (find failed deliveries that need retrying)
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_retry
  ON crm_webhook_deliveries (next_retry_at)
  WHERE success = false AND next_retry_at IS NOT NULL;

-- Index for listing recent deliveries per webhook
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook
  ON crm_webhook_deliveries (webhook_id, delivered_at DESC);

-- CRM Integrations table (generic — FUB + future CRMs)
CREATE TABLE IF NOT EXISTS crm_integrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,                     -- 'follow_up_boss', etc.
  name text NOT NULL DEFAULT 'Default',
  config jsonb NOT NULL DEFAULT '{}',         -- provider-specific config (encrypted API keys)
  sync_events text[] NOT NULL DEFAULT ARRAY['contact_created','stage_changed'],
  active boolean NOT NULL DEFAULT true,
  last_sync_at timestamptz,
  last_error text,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- RLS
ALTER TABLE crm_webhooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_webhook_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_integrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage webhooks" ON crm_webhooks FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Admins can manage deliveries" ON crm_webhook_deliveries FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Admins can manage integrations" ON crm_integrations FOR ALL USING (true) WITH CHECK (true);

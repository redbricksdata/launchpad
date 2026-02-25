-- Email campaign tracking infrastructure

-- Campaign metadata
CREATE TABLE IF NOT EXISTS email_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  subject text NOT NULL,
  recipient_count int NOT NULL DEFAULT 0,
  sent_count int NOT NULL DEFAULT 0,
  open_count int NOT NULL DEFAULT 0,
  click_count int NOT NULL DEFAULT 0,
  unsubscribe_count int NOT NULL DEFAULT 0,
  bounce_count int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'sending'
    CHECK (status IN ('draft','sending','sent','failed')),
  audience_config jsonb DEFAULT '{}',
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz
);

-- Per-recipient tracking
CREATE TABLE IF NOT EXISTS email_sends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES email_campaigns(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES crm_contacts(id) ON DELETE SET NULL,
  email text NOT NULL,
  tracking_token text UNIQUE NOT NULL DEFAULT replace(gen_random_uuid()::text, '-', ''),
  status text NOT NULL DEFAULT 'sent'
    CHECK (status IN ('queued','sent','delivered','opened','clicked','bounced','failed')),
  opened_at timestamptz,
  open_count int NOT NULL DEFAULT 0,
  clicked_at timestamptz,
  click_count int NOT NULL DEFAULT 0,
  bounced_at timestamptz,
  bounce_type text,
  unsubscribed_at timestamptz,
  sent_at timestamptz NOT NULL DEFAULT now()
);

-- Individual click events
CREATE TABLE IF NOT EXISTS email_clicks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  send_id uuid NOT NULL REFERENCES email_sends(id) ON DELETE CASCADE,
  url text NOT NULL,
  user_agent text,
  clicked_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for tracking endpoints (fast token lookup)
CREATE INDEX IF NOT EXISTS idx_email_sends_token
  ON email_sends (tracking_token);

CREATE INDEX IF NOT EXISTS idx_email_sends_campaign
  ON email_sends (campaign_id, status);

CREATE INDEX IF NOT EXISTS idx_email_sends_email
  ON email_sends (email);

CREATE INDEX IF NOT EXISTS idx_email_clicks_send
  ON email_clicks (send_id, clicked_at DESC);

-- Index for campaign analytics
CREATE INDEX IF NOT EXISTS idx_email_campaigns_created
  ON email_campaigns (created_at DESC);

-- RLS
ALTER TABLE email_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_sends ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_clicks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage campaigns" ON email_campaigns FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Admins can manage sends" ON email_sends FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Admins can manage clicks" ON email_clicks FOR ALL USING (true) WITH CHECK (true);

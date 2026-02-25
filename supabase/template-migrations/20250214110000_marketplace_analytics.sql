-- ════════════════════════════════════════════════════════════
-- Widget Usage Analytics & Webhook System
-- ════════════════════════════════════════════════════════════

-- ── 1. Widget Usage Events ──────────────────────────────────
-- Tracks every widget load / interaction per API key.
-- Aggregated for dashboard views.

CREATE TABLE IF NOT EXISTS public.widget_usage_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  api_key_id  uuid REFERENCES public.api_keys(id) ON DELETE SET NULL,
  widget_slug text NOT NULL,
  event_type  text NOT NULL DEFAULT 'widget_load',  -- widget_load, widget_interact, widget_error
  referrer    text,                                  -- hostname of the embedding site
  metadata    jsonb DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_wue_apikey   ON public.widget_usage_events(api_key_id);
CREATE INDEX idx_wue_slug     ON public.widget_usage_events(widget_slug);
CREATE INDEX idx_wue_created  ON public.widget_usage_events(created_at);
CREATE INDEX idx_wue_event    ON public.widget_usage_events(event_type);

ALTER TABLE public.widget_usage_events ENABLE ROW LEVEL SECURITY;

-- Users can see events for their own API keys
CREATE POLICY "Users can read own usage events"
  ON public.widget_usage_events FOR SELECT
  USING (
    api_key_id IN (SELECT id FROM public.api_keys WHERE user_id = auth.uid())
  );

-- Service role inserts events (from API route)
CREATE POLICY "Service role can insert events"
  ON public.widget_usage_events FOR INSERT
  WITH CHECK (true);

-- Admins can read all events
CREATE POLICY "Admins can read all usage events"
  ON public.widget_usage_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admins WHERE email = (
        SELECT email FROM auth.users WHERE id = auth.uid()
      )
    )
  );


-- ── 2. Daily Aggregates (materialized for performance) ──────
CREATE TABLE IF NOT EXISTS public.widget_usage_daily (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  api_key_id    uuid REFERENCES public.api_keys(id) ON DELETE CASCADE,
  widget_slug   text NOT NULL,
  event_date    date NOT NULL,
  load_count    integer NOT NULL DEFAULT 0,
  unique_hosts  integer NOT NULL DEFAULT 0,
  UNIQUE(api_key_id, widget_slug, event_date)
);

CREATE INDEX idx_wud_apikey ON public.widget_usage_daily(api_key_id);
CREATE INDEX idx_wud_date   ON public.widget_usage_daily(event_date);

ALTER TABLE public.widget_usage_daily ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own daily aggregates"
  ON public.widget_usage_daily FOR SELECT
  USING (
    api_key_id IN (SELECT id FROM public.api_keys WHERE user_id = auth.uid())
  );

CREATE POLICY "Service role can manage daily aggregates"
  ON public.widget_usage_daily FOR ALL
  USING (true);


-- ── 3. Webhook Subscriptions ────────────────────────────────
-- Developers can subscribe to events on their marketplace widgets.

CREATE TABLE IF NOT EXISTS public.webhook_subscriptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  url           text NOT NULL,                           -- https://your-site.com/webhooks/rb
  secret        text NOT NULL,                           -- signing secret for HMAC
  events        text[] NOT NULL DEFAULT ARRAY['widget.installed', 'widget.review', 'submission.approved'],
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_triggered timestamptz
);

CREATE INDEX idx_ws_user ON public.webhook_subscriptions(user_id);

ALTER TABLE public.webhook_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own webhooks"
  ON public.webhook_subscriptions FOR ALL
  USING (auth.uid() = user_id);


-- ── 4. Webhook Delivery Log ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.webhook_deliveries (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id  uuid NOT NULL REFERENCES public.webhook_subscriptions(id) ON DELETE CASCADE,
  event_type       text NOT NULL,
  payload          jsonb NOT NULL,
  status_code      integer,
  response_body    text,
  success          boolean NOT NULL DEFAULT false,
  attempted_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_wd_sub     ON public.webhook_deliveries(subscription_id);
CREATE INDEX idx_wd_created ON public.webhook_deliveries(attempted_at);

ALTER TABLE public.webhook_deliveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own webhook deliveries"
  ON public.webhook_deliveries FOR SELECT
  USING (
    subscription_id IN (
      SELECT id FROM public.webhook_subscriptions WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Service role can manage webhook deliveries"
  ON public.webhook_deliveries FOR ALL
  USING (true);


-- ── 5. Stripe Integration Columns (on marketplace_widgets) ──
ALTER TABLE public.marketplace_widgets
  ADD COLUMN IF NOT EXISTS stripe_price_id text,
  ADD COLUMN IF NOT EXISTS stripe_product_id text;

-- ── 6. Widget Purchases ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.widget_purchases (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  marketplace_widget_id uuid NOT NULL REFERENCES public.marketplace_widgets(id) ON DELETE CASCADE,
  stripe_payment_id  text,
  amount_cents       integer NOT NULL DEFAULT 0,
  status             text NOT NULL DEFAULT 'completed',  -- completed, refunded
  purchased_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, marketplace_widget_id)
);

CREATE INDEX idx_wp_user ON public.widget_purchases(user_id);

ALTER TABLE public.widget_purchases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own purchases"
  ON public.widget_purchases FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage purchases"
  ON public.widget_purchases FOR ALL
  USING (true);

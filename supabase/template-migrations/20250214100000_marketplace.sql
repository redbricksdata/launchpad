-- ════════════════════════════════════════════════════════════
-- Global Widget Marketplace — API Keys, Installations, Submissions
-- ════════════════════════════════════════════════════════════

-- ── 1. API Keys ─────────────────────────────────────────────
-- Every user (agent, brokerage, developer) gets one or more
-- API keys that scope widget access to their external site.

CREATE TABLE IF NOT EXISTS public.api_keys (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name        text NOT NULL DEFAULT 'Default',          -- friendly label
  key         text NOT NULL UNIQUE,                     -- rb_live_xxxxxxxx
  domain      text,                                     -- allowed origin (nullable = any)
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  last_used   timestamptz
);

CREATE INDEX idx_api_keys_user  ON public.api_keys(user_id);
CREATE INDEX idx_api_keys_key   ON public.api_keys(key);

-- Anyone can validate a key; only the owner manages theirs
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own keys"
  ON public.api_keys FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create own keys"
  ON public.api_keys FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own keys"
  ON public.api_keys FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own keys"
  ON public.api_keys FOR DELETE
  USING (auth.uid() = user_id);

-- Service-role can validate any key (used by embed API)
CREATE POLICY "Service role can read all keys"
  ON public.api_keys FOR SELECT
  USING (auth.role() = 'service_role');


-- ── 2. Widget Installations ─────────────────────────────────
-- Tracks which widgets a user has installed (enabled) on their
-- API key / site. Replaces the flat feature-flag approach for
-- API-key-based access.

CREATE TABLE IF NOT EXISTS public.widget_installations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  api_key_id    uuid REFERENCES public.api_keys(id) ON DELETE SET NULL,
  widget_slug   text NOT NULL,           -- references kit-registry slug
  enabled       boolean NOT NULL DEFAULT true,
  config        jsonb DEFAULT '{}',      -- widget-specific settings
  installed_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, widget_slug)           -- one install per widget per user
);

CREATE INDEX idx_widget_inst_user   ON public.widget_installations(user_id);
CREATE INDEX idx_widget_inst_slug   ON public.widget_installations(widget_slug);
CREATE INDEX idx_widget_inst_apikey ON public.widget_installations(api_key_id);

ALTER TABLE public.widget_installations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own installations"
  ON public.widget_installations FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create own installations"
  ON public.widget_installations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own installations"
  ON public.widget_installations FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own installations"
  ON public.widget_installations FOR DELETE
  USING (auth.uid() = user_id);

CREATE POLICY "Service role can read all installations"
  ON public.widget_installations FOR SELECT
  USING (auth.role() = 'service_role');


-- ── 3. Marketplace Widget Submissions ───────────────────────
-- Third-party developers submit widgets for review.
-- Approved widgets appear in the global store alongside built-in ones.

CREATE TYPE widget_submission_status AS ENUM (
  'draft', 'pending_review', 'approved', 'rejected', 'suspended'
);

CREATE TABLE IF NOT EXISTS public.marketplace_widgets (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  developer_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  slug            text NOT NULL UNIQUE,
  name            text NOT NULL,
  tagline         text NOT NULL,
  description     text NOT NULL,
  category        text NOT NULL,          -- engagement | discovery | content | listings | analytics
  icon            text NOT NULL DEFAULT '🧩',
  version         text NOT NULL DEFAULT '1.0.0',

  -- Technical
  embed_url       text,                   -- hosted widget URL for iframe embed
  script_url      text,                   -- hosted JS bundle URL for script embed
  components      jsonb DEFAULT '[]',     -- ComponentInfo[] shape
  highlights      jsonb DEFAULT '[]',     -- string[]
  how_it_works    jsonb DEFAULT '[]',     -- string[]
  screenshot_url  text,

  -- Marketplace
  price           integer DEFAULT 0,      -- cents (0 = free)
  status          widget_submission_status NOT NULL DEFAULT 'draft',
  review_notes    text,                   -- admin feedback on rejection
  downloads       integer DEFAULT 0,
  rating_sum      integer DEFAULT 0,
  rating_count    integer DEFAULT 0,

  -- Metadata
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  published_at    timestamptz
);

CREATE INDEX idx_mw_developer ON public.marketplace_widgets(developer_id);
CREATE INDEX idx_mw_status    ON public.marketplace_widgets(status);
CREATE INDEX idx_mw_category  ON public.marketplace_widgets(category);

ALTER TABLE public.marketplace_widgets ENABLE ROW LEVEL SECURITY;

-- Anyone can browse approved widgets
CREATE POLICY "Public can read approved widgets"
  ON public.marketplace_widgets FOR SELECT
  USING (status = 'approved');

-- Developers manage their own
CREATE POLICY "Developers can read own widgets"
  ON public.marketplace_widgets FOR SELECT
  USING (auth.uid() = developer_id);

CREATE POLICY "Developers can create own widgets"
  ON public.marketplace_widgets FOR INSERT
  WITH CHECK (auth.uid() = developer_id);

CREATE POLICY "Developers can update own widgets"
  ON public.marketplace_widgets FOR UPDATE
  USING (auth.uid() = developer_id);

-- Admins manage all (via is_admin function from earlier migration)
CREATE POLICY "Admins can manage all marketplace widgets"
  ON public.marketplace_widgets FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admins WHERE email = (
        SELECT email FROM auth.users WHERE id = auth.uid()
      )
    )
  );


-- ── 4. Widget Reviews ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.widget_reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  widget_id   uuid NOT NULL REFERENCES public.marketplace_widgets(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rating      integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE(widget_id, user_id)  -- one review per user per widget
);

ALTER TABLE public.widget_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read reviews"
  ON public.widget_reviews FOR SELECT
  USING (true);

CREATE POLICY "Users can create own reviews"
  ON public.widget_reviews FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own reviews"
  ON public.widget_reviews FOR UPDATE
  USING (auth.uid() = user_id);


-- ── 5. Helper: update rating aggregates on review change ────
CREATE OR REPLACE FUNCTION update_widget_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.marketplace_widgets
  SET
    rating_sum   = COALESCE((SELECT SUM(rating) FROM public.widget_reviews WHERE widget_id = COALESCE(NEW.widget_id, OLD.widget_id)), 0),
    rating_count = COALESCE((SELECT COUNT(*)     FROM public.widget_reviews WHERE widget_id = COALESCE(NEW.widget_id, OLD.widget_id)), 0),
    updated_at   = now()
  WHERE id = COALESCE(NEW.widget_id, OLD.widget_id);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_widget_review_agg
  AFTER INSERT OR UPDATE OR DELETE ON public.widget_reviews
  FOR EACH ROW
  EXECUTE FUNCTION update_widget_rating();

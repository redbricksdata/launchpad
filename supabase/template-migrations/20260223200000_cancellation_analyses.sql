-- ============================================================
-- CondoLand — Cancellation Intelligence
-- ============================================================
-- AI-powered classification of project cancellations.
-- Stores web-search-sourced analysis of WHY a project was
-- cancelled (strategic pivot, market conditions, financial
-- distress, bad faith, etc.) to enable severity-weighted
-- developer scoring and buyer-facing transparency.
-- ============================================================

CREATE TABLE public.cancellation_analyses (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id       integer NOT NULL,
  project_name     text NOT NULL,
  developer_name   text NOT NULL,
  category         text NOT NULL CHECK (category IN (
    'STRATEGIC_PIVOT', 'MARKET_CONDITIONS', 'REGULATORY',
    'FINANCIAL_DISTRESS', 'BAD_FAITH', 'UNKNOWN'
  )),
  severity         text NOT NULL CHECK (severity IN (
    'low', 'medium', 'high', 'severe'
  )),
  score_multiplier numeric(3,2) NOT NULL DEFAULT 0.80,
  summary          text NOT NULL,                -- 2-3 sentence AI explanation
  sources          jsonb NOT NULL DEFAULT '[]',  -- [{url, title, snippet}]
  ai_provider      text,                         -- 'gemini' | 'openai'
  search_queries   jsonb NOT NULL DEFAULT '[]',  -- Tavily queries used
  raw_ai_response  jsonb,                        -- Full AI output for audit
  analyzed_at      timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- One analysis per project (upsert-friendly)
CREATE UNIQUE INDEX idx_cancellation_project
  ON public.cancellation_analyses (project_id);

-- Fast lookup by developer (for score breakdown UI)
CREATE INDEX idx_cancellation_developer
  ON public.cancellation_analyses (developer_name);

-- ── RLS Policies ────────────────────────────────────────────

ALTER TABLE public.cancellation_analyses ENABLE ROW LEVEL SECURITY;

-- Public can read summaries (shown on project pages + developer pages)
CREATE POLICY "Public can read cancellation analyses"
  ON public.cancellation_analyses FOR SELECT
  USING (true);

-- Service role inserts/updates (from webhook + backfill routes)
CREATE POLICY "Service can insert cancellation analyses"
  ON public.cancellation_analyses FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Service can update cancellation analyses"
  ON public.cancellation_analyses FOR UPDATE
  USING (true);

-- ============================================================
-- Tiered Hot Lead Alerts
-- ============================================================
-- Replaces the 1-hour cooldown with permanent tier-based
-- deduplication. Max 3 emails per visitor: warm, hot, on_fire.
-- ============================================================

-- 1. Add threshold_tier column to alert_sends
ALTER TABLE public.alert_sends
  ADD COLUMN IF NOT EXISTS threshold_tier TEXT
  CHECK (threshold_tier IN ('warm', 'hot', 'on_fire'));

-- 2. Partial index for fast tier-based dedup lookups
--    Covers: "Has visitor X ever been sent a hot_lead alert at tier Y?"
CREATE INDEX IF NOT EXISTS idx_alert_sends_hot_lead_tier
  ON public.alert_sends (user_id, email_type, threshold_tier)
  WHERE email_type = 'hot_lead' AND threshold_tier IS NOT NULL;

-- 3. Backfill existing hot_lead rows as 'hot' tier
--    Prevents re-alerting previously notified visitors at the hot level.
--    They may still receive 'warm' or 'on_fire' if they cross those thresholds.
UPDATE public.alert_sends
  SET threshold_tier = 'hot'
  WHERE email_type = 'hot_lead' AND threshold_tier IS NULL;

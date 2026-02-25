-- ================================================================
-- Remove Engagement from developer score formula
-- ================================================================
-- Changes:
--   1. Remove engagement_score (2%) from overall formula
--   2. Redistribute to Google Reviews (10% → 12%)
--   3. New formula: TR 48%, MP 25%, Google 12%, Pricing 10%, Online 5%
--   4. Fallback divisor: 0.83 (internal = 48+25+10 = 83%)
-- ================================================================

CREATE OR REPLACE FUNCTION public.recalculate_developer_overall_scores()
RETURNS integer AS $$
DECLARE
  row_count integer;
BEGIN
  UPDATE developer_scores ds SET
    overall_score = round(
      CASE
        -- Full formula (with external data)
        WHEN ds.external_fetched_at IS NOT NULL THEN
          ds.track_record_score     * 0.48
          + ds.market_presence_score * 0.25
          + GREATEST(coalesce(ds.google_score, 50), 30) * 0.12
          + ds.pricing_score         * 0.10
          + coalesce(ds.online_presence_score, 0) * 0.05

        -- Fallback: only internal signals (83% of weight)
        ELSE
          (
            ds.track_record_score     * 0.48
            + ds.market_presence_score * 0.25
            + ds.pricing_score         * 0.10
          ) / 0.83
      END
    , 1),

    score_breakdown = jsonb_build_object(
      'track_record',    ds.track_record_score,
      'market_presence', ds.market_presence_score,
      'google_reviews',  ds.google_score,
      'pricing',         ds.pricing_score,
      'online_presence', ds.online_presence_score,
      'has_external',    ds.external_fetched_at IS NOT NULL,
      'total_completed', ds.total_completed,
      'total_cancelled', ds.total_cancelled
    )
  WHERE ds.total_projects >= 2;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ================================================================
-- Add "Units Delivered" to Track Record score
-- ================================================================
-- Changes:
--   1. New column: total_units_delivered on developer_scores
--   2. Track Record rebalanced: projects 20%, units_delivered 15%,
--      years 15%, active 15%, completion 15%, cancel_low 20%
--   3. score_breakdown JSONB now includes total_units_delivered
-- ================================================================


-- ── Schema change ─────────────────────────────────────────────

ALTER TABLE developer_scores
  ADD COLUMN IF NOT EXISTS total_units_delivered integer DEFAULT 0;


-- ── RPC 1: Compute internal developer scores (v3 — units delivered) ──

CREATE OR REPLACE FUNCTION public.compute_developer_scores()
RETURNS integer AS $$
DECLARE
  row_count integer;
BEGIN
  WITH dev_raw AS (
    SELECT
      COALESCE(dev_elem->>'name', pc.developer) AS developer_name,

      -- ── Counts ───────────────────────────────────────────
      count(*)                                                AS total_projects,
      count(*) FILTER (WHERE pc.sales_status ILIKE '%Selling%')  AS active_selling,
      count(*) FILTER (WHERE pc.sales_status = 'Cancelled')      AS cancelled,

      -- Completed = Sold Out (sales) OR Complete (construction)
      count(*) FILTER (
        WHERE pc.sales_status ILIKE '%Sold Out%'
           OR pc.data->>'status' = 'Complete'
      ) AS completed,

      coalesce(sum((pc.data->>'suites')::integer), 0)            AS total_units,

      -- Units delivered = sum of suites for completed projects only
      coalesce(sum((pc.data->>'suites')::integer) FILTER (
        WHERE pc.sales_status ILIKE '%Sold Out%'
           OR pc.data->>'status' = 'Complete'
      ), 0) AS units_delivered,

      -- ── Years active (earliest occupancy year to latest) ─
      coalesce(
        (regexp_match(max(pc.occupancy_date), '(\d{4})'))[1]::integer
        - (regexp_match(min(pc.occupancy_date), '(\d{4})'))[1]::integer
        + 1,
        1
      ) AS years_active,

      -- ── Geographic spread (distinct cities) ──────────────
      count(DISTINCT pc.city)          AS city_count,

      -- ── Building type diversity ──────────────────────────
      count(DISTINCT pc.building_type) AS type_count,

      -- ── Pricing consistency (coefficient of variation) ───
      CASE
        WHEN avg(NULLIF((pc.data->>'price_per_sqft')::numeric, 0)) > 0
        THEN stddev_samp(NULLIF((pc.data->>'price_per_sqft')::numeric, 0))
             / avg(NULLIF((pc.data->>'price_per_sqft')::numeric, 0))
        ELSE NULL
      END AS psf_cv

    FROM project_cache pc
    LEFT JOIN LATERAL jsonb_array_elements(
      CASE
        WHEN jsonb_array_length(COALESCE(pc.data->'developers', '[]'::jsonb)) > 0
        THEN pc.data->'developers'
        ELSE NULL
      END
    ) AS dev_elem ON true
    WHERE pc.developer IS NOT NULL
      AND pc.developer <> ''
    GROUP BY COALESCE(dev_elem->>'name', pc.developer)
    HAVING count(*) >= 2  -- need at least 2 projects to score
  ),

  -- ── Percent-rank each signal ─────────────────────────────
  dev_ranked AS (
    SELECT
      dr.*,

      -- Track Record sub-components (each 0–1)
      percent_rank() OVER (ORDER BY dr.total_projects)       AS pr_projects,
      percent_rank() OVER (ORDER BY dr.units_delivered)      AS pr_units_delivered,
      percent_rank() OVER (ORDER BY dr.years_active)         AS pr_years,
      percent_rank() OVER (ORDER BY dr.active_selling)       AS pr_active,

      -- Completion ratio: completed / total
      percent_rank() OVER (
        ORDER BY dr.completed::numeric / NULLIF(dr.total_projects, 0)
      ) AS pr_completion,

      -- Lower cancellation rate = better → rank descending
      percent_rank() OVER (
        ORDER BY dr.cancelled::numeric / NULLIF(dr.total_projects, 0) DESC
      ) AS pr_cancel_low,

      -- Market Presence sub-components
      percent_rank() OVER (ORDER BY dr.total_units)          AS pr_units,
      percent_rank() OVER (ORDER BY dr.city_count)           AS pr_cities,
      percent_rank() OVER (ORDER BY dr.type_count)           AS pr_types,

      -- Pricing Consistency: lower CV = better → rank descending
      percent_rank() OVER (ORDER BY dr.psf_cv DESC)          AS pr_pricing

    FROM dev_raw dr
  )

  -- ── UPSERT into developer_scores ─────────────────────────
  INSERT INTO developer_scores (
    developer_name,
    track_record_score,
    sell_through_score,
    market_presence_score,
    pricing_score,
    total_projects,
    total_completed,
    total_cancelled,
    total_sold_out,
    total_units_delivered,
    years_active,
    computed_at
  )
  SELECT
    dr.developer_name,

    -- Track Record (projects 20%, units_delivered 15%, years 15%,
    --               active 15%, completion 15%, cancel_low 20%)
    round(
      ((dr.pr_projects * 0.20
        + dr.pr_units_delivered * 0.15
        + dr.pr_years * 0.15
        + dr.pr_active * 0.15
        + dr.pr_completion * 0.15
        + dr.pr_cancel_low * 0.20) * 100)::numeric
    , 1),

    -- Sell-Through Rate (deprecated — set to 0)
    0,

    -- Market Presence (weighted: units 55%, cities 25%, types 20%)
    round(
      ((dr.pr_units * 0.55 + dr.pr_cities * 0.25 + dr.pr_types * 0.20) * 100)::numeric
    , 1),

    -- Pricing Consistency
    round((coalesce(dr.pr_pricing, 0.5) * 100)::numeric, 1),

    dr.total_projects::integer,
    dr.completed::integer,
    dr.cancelled::integer,
    dr.completed::integer,  -- keep total_sold_out in sync for backward compat
    dr.units_delivered::integer,
    dr.years_active::integer,
    now()

  FROM dev_ranked dr
  ON CONFLICT (developer_name) DO UPDATE SET
    track_record_score     = EXCLUDED.track_record_score,
    sell_through_score     = EXCLUDED.sell_through_score,
    market_presence_score  = EXCLUDED.market_presence_score,
    pricing_score          = EXCLUDED.pricing_score,
    total_projects         = EXCLUDED.total_projects,
    total_completed        = EXCLUDED.total_completed,
    total_cancelled        = EXCLUDED.total_cancelled,
    total_sold_out         = EXCLUDED.total_sold_out,
    total_units_delivered   = EXCLUDED.total_units_delivered,
    years_active           = EXCLUDED.years_active,
    computed_at            = now();

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── RPC 2: Recalculate overall scores (includes units_delivered in breakdown) ──

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
      'track_record',          ds.track_record_score,
      'market_presence',       ds.market_presence_score,
      'google_reviews',        ds.google_score,
      'pricing',               ds.pricing_score,
      'online_presence',       ds.online_presence_score,
      'has_external',          ds.external_fetched_at IS NOT NULL,
      'total_completed',       ds.total_completed,
      'total_cancelled',       ds.total_cancelled,
      'total_units_delivered',  ds.total_units_delivered
    )
  WHERE ds.total_projects >= 2;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

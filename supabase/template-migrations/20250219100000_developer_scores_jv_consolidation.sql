-- ================================================================
-- Developer Scores — JV Consolidation
-- ================================================================
-- Previously, JV projects like "CentreCourt, SmartCentres" were
-- scored as a single composite developer entry. This migration
-- rewrites the scoring RPCs to unnest the `data->'developers'`
-- JSONB array, attributing each project to ALL its individual
-- developers. CentreCourt's 16 solo + 8 JV projects now all
-- count toward one "CentreCourt" score entry.
--
-- Affected RPCs:
--   1. compute_developer_scores() — unnest developers array
--   2. compute_developer_engagement_scores() — same unnesting
--   3. recalculate_developer_overall_scores() — NO changes
--
-- Also cleans up 113 stale JV entries from developer_scores.
-- ================================================================


-- ── Step 1: Delete stale JV entries ──────────────────────────────
-- These will be replaced by individual developer entries on next
-- cron run. External data (Google, BBB) fetched for composite names
-- like "CentreCourt, SmartCentres" yielded poor results anyway.
-- ──────────────────────────────────────────────────────────────────

DELETE FROM developer_scores
WHERE developer_name LIKE '%,%';


-- ── RPC 1: Compute internal developer scores (JV-aware) ─────────
-- Unnests data->'developers' JSONB array so each project is
-- attributed to ALL its individual developers. Falls back to
-- pc.developer (concatenated string) for rows missing the array.
-- ──────────────────────────────────────────────────────────────────

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
      count(*) FILTER (WHERE pc.sales_status ILIKE '%Sold Out%') AS sold_out,
      coalesce(sum((pc.data->>'suites')::integer), 0)            AS total_units,

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
      percent_rank() OVER (ORDER BY dr.years_active)         AS pr_years,
      percent_rank() OVER (ORDER BY dr.active_selling)       AS pr_active,
      -- Lower cancellation rate = better → rank descending
      percent_rank() OVER (
        ORDER BY dr.cancelled::numeric / NULLIF(dr.total_projects, 0) DESC
      ) AS pr_cancel_low,

      -- Sell-Through: sold_out / total_projects ratio
      percent_rank() OVER (
        ORDER BY dr.sold_out::numeric / NULLIF(dr.total_projects, 0)
      ) AS pr_sell_through,

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
    total_sold_out,
    years_active,
    computed_at
  )
  SELECT
    dr.developer_name,

    -- Track Record (weighted: projects 35%, years 30%, active 20%, low-cancel 15%)
    round(
      ((dr.pr_projects * 0.35 + dr.pr_years * 0.30 + dr.pr_active * 0.20 + dr.pr_cancel_low * 0.15) * 100)::numeric
    , 1),

    -- Sell-Through Rate
    round((dr.pr_sell_through * 100)::numeric, 1),

    -- Market Presence (weighted: units 55%, cities 25%, types 20%)
    round(
      ((dr.pr_units * 0.55 + dr.pr_cities * 0.25 + dr.pr_types * 0.20) * 100)::numeric
    , 1),

    -- Pricing Consistency
    round((coalesce(dr.pr_pricing, 0.5) * 100)::numeric, 1),

    dr.total_projects::integer,
    dr.sold_out::integer,
    dr.years_active::integer,
    now()

  FROM dev_ranked dr
  ON CONFLICT (developer_name) DO UPDATE SET
    track_record_score    = EXCLUDED.track_record_score,
    sell_through_score    = EXCLUDED.sell_through_score,
    market_presence_score = EXCLUDED.market_presence_score,
    pricing_score         = EXCLUDED.pricing_score,
    total_projects        = EXCLUDED.total_projects,
    total_sold_out        = EXCLUDED.total_sold_out,
    years_active          = EXCLUDED.years_active,
    computed_at           = now();

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── RPC 2: Compute engagement scores (JV-aware) ─────────────────
-- Same unnesting pattern applied to page_views aggregation.
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.compute_developer_engagement_scores(
  window_days integer DEFAULT 90
)
RETURNS integer AS $$
DECLARE
  row_count integer;
BEGIN
  WITH cutoff AS (
    SELECT now() - (window_days || ' days')::interval AS since
  ),

  -- Aggregate page views by individual developer via project_cache
  dev_engagement AS (
    SELECT
      COALESCE(dev_elem->>'name', pc.developer) AS developer_name,
      sum(
        exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
      ) AS raw_score,
      count(*) AS total_views
    FROM page_views pv
    JOIN project_cache pc ON pc.id = pv.entity_id
    LEFT JOIN LATERAL jsonb_array_elements(
      CASE
        WHEN jsonb_array_length(COALESCE(pc.data->'developers', '[]'::jsonb)) > 0
        THEN pc.data->'developers'
        ELSE NULL
      END
    ) AS dev_elem ON true
    CROSS JOIN cutoff c
    WHERE pv.entity_type = 'project'
      AND pv.entity_id IS NOT NULL
      AND pv.created_at >= c.since
      AND pc.developer IS NOT NULL
    GROUP BY COALESCE(dev_elem->>'name', pc.developer)
  ),

  -- Percent-rank the engagement
  dev_ranked AS (
    SELECT
      de.developer_name,
      round((percent_rank() OVER (ORDER BY de.raw_score) * 100)::numeric, 1) AS engagement_score
    FROM dev_engagement de
  )

  UPDATE developer_scores ds
  SET engagement_score = dr.engagement_score,
      computed_at = now()
  FROM dev_ranked dr
  WHERE ds.developer_name = dr.developer_name;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

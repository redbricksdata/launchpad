-- Phase 2: Signal Aggregation Schema
-- Pre-computes anonymized daily rollups from page_views for Market Intelligence.
-- No PII stored — only bucketed counts and dimension values.

-- ── Table ────────────────────────────────────────────────────────────
CREATE TABLE signal_aggregates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_date     DATE NOT NULL,
  signal_type     TEXT NOT NULL,
  metric_key      TEXT NOT NULL,
  dimensions      JSONB NOT NULL DEFAULT '{}',
  event_count     INTEGER NOT NULL DEFAULT 0,
  visitor_count   INTEGER NOT NULL DEFAULT 0,
  synced_at       TIMESTAMPTZ,          -- Phase 3: when pushed to Laravel
  sync_batch_id   UUID,                 -- Phase 3: batch ID for push
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(signal_date, signal_type, metric_key, dimensions)
);

-- ── Indexes ──────────────────────────────────────────────────────────
CREATE INDEX idx_signal_aggregates_date ON signal_aggregates (signal_date DESC);
CREATE INDEX idx_signal_aggregates_type ON signal_aggregates (signal_type, metric_key);
CREATE INDEX idx_signal_aggregates_unsynced ON signal_aggregates (synced_at) WHERE synced_at IS NULL;

-- ── RLS ──────────────────────────────────────────────────────────────
ALTER TABLE signal_aggregates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can read signal_aggregates"
  ON signal_aggregates FOR SELECT
  USING (is_admin());

CREATE POLICY "Service role can insert signal_aggregates"
  ON signal_aggregates FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Service role can update signal_aggregates"
  ON signal_aggregates FOR UPDATE
  USING (true);


-- ── Helper: format price bucket ──────────────────────────────────────
-- Converts a raw numeric price (e.g. 500000) to a display bucket (e.g. '500K', '1.2M')
CREATE OR REPLACE FUNCTION format_price_bucket(val NUMERIC)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN val IS NULL THEN NULL
    WHEN val >= 1000000 THEN
      CASE WHEN val % 1000000 = 0
        THEN (val / 1000000)::int::text || 'M'
        ELSE ROUND(val / 1000000.0, 1)::text || 'M'
      END
    ELSE (val / 1000)::int::text || 'K'
  END;
$$;


-- ── RPC: aggregate_daily_signals ─────────────────────────────────────
-- Idempotent: safe to re-run for the same date (UPSERT pattern).
-- Call via: SELECT aggregate_daily_signals('2026-02-21'::date);

CREATE OR REPLACE FUNCTION aggregate_daily_signals(target_date DATE)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  day_start TIMESTAMPTZ := target_date::timestamptz;
  day_end   TIMESTAMPTZ := (target_date + INTERVAL '1 day')::timestamptz;
  total_rows INTEGER := 0;
  section_rows INTEGER;
BEGIN

  -- ================================================================
  -- 1. map_filter → price_demand
  --    Buckets priceMin from entity_meta->'filters'->>'priceMin'
  -- ================================================================
  WITH src AS (
    SELECT
      FLOOR((entity_meta->'filters'->>'priceMin')::numeric / 100000) * 100000 AS bucket_val,
      visitor_id
    FROM page_views
    WHERE entity_type = 'map_filter'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->'filters'->>'priceMin' IS NOT NULL
      AND (entity_meta->'filters'->>'priceMin')::numeric > 0
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'map_filter',
    'price_demand',
    jsonb_build_object('price_bucket', format_price_bucket(bucket_val)),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY bucket_val
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 2. map_filter → bedroom_demand
  -- ================================================================
  WITH src AS (
    SELECT
      entity_meta->'filters'->>'beds' AS beds,
      visitor_id
    FROM page_views
    WHERE entity_type = 'map_filter'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->'filters'->>'beds' IS NOT NULL
      AND entity_meta->'filters'->>'beds' != ''
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'map_filter',
    'bedroom_demand',
    jsonb_build_object('beds', beds),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY beds
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 3. map_filter → building_type_demand
  -- ================================================================
  WITH src AS (
    SELECT
      entity_meta->'filters'->>'buildingType' AS building_type,
      visitor_id
    FROM page_views
    WHERE entity_type = 'map_filter'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->'filters'->>'buildingType' IS NOT NULL
      AND entity_meta->'filters'->>'buildingType' != ''
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'map_filter',
    'building_type_demand',
    jsonb_build_object('building_type', building_type),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY building_type
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 4. map_filter → neighbourhood_demand
  -- ================================================================
  WITH src AS (
    SELECT
      entity_meta->'filters'->>'neighbourhood' AS neighbourhood,
      visitor_id
    FROM page_views
    WHERE entity_type = 'map_filter'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->'filters'->>'neighbourhood' IS NOT NULL
      AND entity_meta->'filters'->>'neighbourhood' != ''
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'map_filter',
    'neighbourhood_demand',
    jsonb_build_object('neighbourhood', neighbourhood),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY neighbourhood
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 5. map_filter → drawn_boundary
  -- ================================================================
  WITH src AS (
    SELECT visitor_id
    FROM page_views
    WHERE entity_type = 'map_filter'
      AND created_at >= day_start AND created_at < day_end
      AND (entity_meta->>'has_drawn_boundary')::boolean = true
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'map_filter',
    'drawn_boundary',
    jsonb_build_object('has_drawn_boundary', true),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  HAVING COUNT(*) > 0
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 6. search_filter → price_demand
  -- ================================================================
  WITH src AS (
    SELECT
      FLOOR((entity_meta->'filters'->>'priceMin')::numeric / 100000) * 100000 AS bucket_val,
      visitor_id
    FROM page_views
    WHERE entity_type = 'search_filter'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->'filters'->>'priceMin' IS NOT NULL
      AND (entity_meta->'filters'->>'priceMin')::numeric > 0
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'search_filter',
    'price_demand',
    jsonb_build_object('price_bucket', format_price_bucket(bucket_val)),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY bucket_val
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 7. search_filter → bedroom_demand
  -- ================================================================
  WITH src AS (
    SELECT
      entity_meta->'filters'->>'beds' AS beds,
      visitor_id
    FROM page_views
    WHERE entity_type = 'search_filter'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->'filters'->>'beds' IS NOT NULL
      AND entity_meta->'filters'->>'beds' != ''
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'search_filter',
    'bedroom_demand',
    jsonb_build_object('beds', beds),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY beds
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 8. search_filter → city_demand
  -- ================================================================
  WITH src AS (
    SELECT
      entity_meta->'filters'->>'city' AS city,
      visitor_id
    FROM page_views
    WHERE entity_type = 'search_filter'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->'filters'->>'city' IS NOT NULL
      AND entity_meta->'filters'->>'city' != ''
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'search_filter',
    'city_demand',
    jsonb_build_object('city', city),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY city
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 9. calculator → price_bucket
  -- ================================================================
  WITH src AS (
    SELECT
      FLOOR((entity_meta->>'user_price')::numeric / 100000) * 100000 AS bucket_val,
      visitor_id
    FROM page_views
    WHERE entity_type = 'calculator'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->>'user_price' IS NOT NULL
      AND (entity_meta->>'user_price')::numeric > 0
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'calculator',
    'price_bucket',
    jsonb_build_object('price_bucket', format_price_bucket(bucket_val)),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY bucket_val
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 10. calculator → down_payment
  -- ================================================================
  WITH src AS (
    SELECT
      CASE
        WHEN (entity_meta->>'down_payment_pct')::numeric >= 20 THEN '20+'
        WHEN (entity_meta->>'down_payment_pct')::numeric >= 15 THEN '15-19'
        WHEN (entity_meta->>'down_payment_pct')::numeric >= 10 THEN '10-14'
        ELSE '5-9'
      END AS dp_bucket,
      visitor_id
    FROM page_views
    WHERE entity_type = 'calculator'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->>'down_payment_pct' IS NOT NULL
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'calculator',
    'down_payment',
    jsonb_build_object('dp_bucket', dp_bucket),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY dp_bucket
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 11. calculator → amortization
  -- ================================================================
  WITH src AS (
    SELECT
      (entity_meta->>'amortization')::int AS amort,
      visitor_id
    FROM page_views
    WHERE entity_type = 'calculator'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->>'amortization' IS NOT NULL
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'calculator',
    'amortization',
    jsonb_build_object('amortization', amort),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY amort
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 12. compare_view → project_pair
  --     Each page_view has entity_meta->'project_pairs' as a JSON array
  --     e.g. ["100-200", "100-300", "200-300"]
  --     We unnest and count each pair individually.
  -- ================================================================
  WITH pairs AS (
    SELECT
      jsonb_array_elements_text(entity_meta->'project_pairs') AS pair,
      visitor_id
    FROM page_views
    WHERE entity_type = 'compare_view'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->'project_pairs' IS NOT NULL
      AND jsonb_typeof(entity_meta->'project_pairs') = 'array'
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'compare_view',
    'project_pair',
    jsonb_build_object('pair', pair),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM pairs
  GROUP BY pair
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  -- ================================================================
  -- 13. map_layer → layer_activation
  -- ================================================================
  WITH src AS (
    SELECT
      entity_meta->>'layer' AS layer,
      visitor_id
    FROM page_views
    WHERE entity_type = 'map_layer'
      AND created_at >= day_start AND created_at < day_end
      AND entity_meta->>'layer' IS NOT NULL
      AND entity_meta->>'layer' != ''
  )
  INSERT INTO signal_aggregates (signal_date, signal_type, metric_key, dimensions, event_count, visitor_count)
  SELECT
    target_date,
    'map_layer',
    'layer_activation',
    jsonb_build_object('layer', layer),
    COUNT(*)::int,
    COUNT(DISTINCT visitor_id)::int
  FROM src
  GROUP BY layer
  ON CONFLICT (signal_date, signal_type, metric_key, dimensions)
  DO UPDATE SET event_count = EXCLUDED.event_count, visitor_count = EXCLUDED.visitor_count;

  GET DIAGNOSTICS section_rows = ROW_COUNT;
  total_rows := total_rows + section_rows;

  RETURN total_rows;
END;
$$;

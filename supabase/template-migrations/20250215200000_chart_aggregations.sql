-- ================================================================
-- Chart Aggregation Functions & Saved Configs
-- Powers the Chart Builder widget using project_cache data.
-- Zero external API calls — all aggregation runs in Supabase.
-- ================================================================

-- ── RPC 1: Units / projects by occupancy year ─────────────────
CREATE OR REPLACE FUNCTION public.chart_units_by_year(
  year_from integer DEFAULT 2016,
  year_to integer DEFAULT 2031
)
RETURNS TABLE (
  year integer,
  project_count bigint,
  total_units bigint,
  building_type text
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    (regexp_match(pc.occupancy_date, '(\d{4})'))[1]::integer AS year,
    count(*) AS project_count,
    coalesce(sum((pc.data->>'suites')::integer), 0) AS total_units,
    pc.building_type
  FROM project_cache pc
  WHERE pc.occupancy_date IS NOT NULL
    AND (regexp_match(pc.occupancy_date, '(\d{4})'))[1] IS NOT NULL
    AND (regexp_match(pc.occupancy_date, '(\d{4})'))[1]::integer BETWEEN year_from AND year_to
  GROUP BY year, pc.building_type
  ORDER BY year;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ── RPC 2: Average PSF by sales status, grouped by year ───────
CREATE OR REPLACE FUNCTION public.chart_avg_psf_by_status(
  target_status text DEFAULT 'Selling'
)
RETURNS TABLE (
  year integer,
  avg_psf numeric,
  project_count bigint,
  city text
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    (regexp_match(pc.occupancy_date, '(\d{4})'))[1]::integer AS year,
    round(avg((pc.data->>'price_per_sqft')::numeric), 2) AS avg_psf,
    count(*) AS project_count,
    pc.city
  FROM project_cache pc
  WHERE pc.sales_status ILIKE '%' || target_status || '%'
    AND (pc.data->>'price_per_sqft') IS NOT NULL
    AND (pc.data->>'price_per_sqft')::numeric > 0
    AND pc.occupancy_date IS NOT NULL
    AND (regexp_match(pc.occupancy_date, '(\d{4})'))[1] IS NOT NULL
  GROUP BY year, pc.city
  ORDER BY year;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ── RPC 3: Average price by bedroom type ──────────────────────
CREATE OR REPLACE FUNCTION public.chart_avg_price_by_bedroom(
  filter_city text DEFAULT NULL,
  filter_neighbourhood text DEFAULT NULL
)
RETURNS TABLE (
  bedroom_type text,
  avg_price numeric,
  avg_psf numeric,
  avg_size numeric,
  unit_count bigint
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    bed.key AS bedroom_type,
    round(avg((bed.value->'prices'->>'average')::numeric), 0) AS avg_price,
    round(avg((bed.value->>'psf')::numeric), 2) AS avg_psf,
    round(avg((bed.value->'sizes'->>'average')::numeric), 0) AS avg_size,
    sum((bed.value->>'count')::bigint) AS unit_count
  FROM project_cache pc,
    jsonb_each(pc.data->'bedrooms_info') AS bed(key, value)
  WHERE pc.data->'bedrooms_info' IS NOT NULL
    AND pc.sales_status ILIKE '%Selling%'
    AND (filter_city IS NULL OR pc.city = filter_city)
    AND (filter_neighbourhood IS NULL OR pc.neighbourhood = filter_neighbourhood)
    AND (bed.value->>'count')::integer > 0
  GROUP BY bed.key
  ORDER BY
    CASE bed.key
      WHEN '0' THEN 0
      WHEN '1' THEN 1
      WHEN '2' THEN 2
      WHEN '3' THEN 3
      WHEN '3+' THEN 4
      ELSE 5
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ── RPC 4: Developer performance ──────────────────────────────
CREATE OR REPLACE FUNCTION public.chart_developer_performance(
  min_projects integer DEFAULT 3,
  result_limit integer DEFAULT 50
)
RETURNS TABLE (
  developer_name text,
  total_projects bigint,
  active_selling bigint,
  cancelled bigint,
  sold_out bigint,
  total_units bigint,
  avg_psf numeric
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pc.developer AS developer_name,
    count(*) AS total_projects,
    count(*) FILTER (WHERE pc.sales_status ILIKE '%Selling%') AS active_selling,
    count(*) FILTER (WHERE pc.sales_status = 'Cancelled') AS cancelled,
    count(*) FILTER (WHERE pc.sales_status ILIKE '%Sold Out%') AS sold_out,
    coalesce(sum((pc.data->>'suites')::integer), 0) AS total_units,
    round(avg(NULLIF((pc.data->>'price_per_sqft')::numeric, 0)), 2) AS avg_psf
  FROM project_cache pc
  WHERE pc.developer IS NOT NULL
  GROUP BY pc.developer
  HAVING count(*) >= min_projects
  ORDER BY count(*) DESC
  LIMIT result_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ── RPC 5: Generic aggregate for the builder ──────────────────
CREATE OR REPLACE FUNCTION public.chart_generic_aggregate(
  group_by_field text,
  measure text,
  filter_city text DEFAULT NULL,
  filter_neighbourhood text DEFAULT NULL,
  filter_status text DEFAULT NULL,
  filter_building_type text DEFAULT NULL,
  result_limit integer DEFAULT 100
)
RETURNS TABLE (
  dimension text,
  value numeric
) AS $$
BEGIN
  RETURN QUERY EXECUTE format(
    'SELECT %s AS dimension, %s AS value
     FROM project_cache pc
     WHERE 1=1
       %s %s %s %s
     GROUP BY dimension
     HAVING %s IS NOT NULL
     ORDER BY value DESC
     LIMIT %s',
    -- dimension column
    CASE group_by_field
      WHEN 'city' THEN 'pc.city'
      WHEN 'neighbourhood' THEN 'pc.neighbourhood'
      WHEN 'developer' THEN 'pc.developer'
      WHEN 'building_type' THEN 'pc.building_type'
      WHEN 'occupancy_year' THEN '(regexp_match(pc.occupancy_date, ''(\d{4})''))[1]'
      WHEN 'sales_status' THEN 'pc.sales_status'
      ELSE 'pc.city'
    END,
    -- measure expression
    CASE measure
      WHEN 'count' THEN 'count(*)::numeric'
      WHEN 'avg_psf' THEN 'round(avg(NULLIF((pc.data->>''price_per_sqft'')::numeric, 0)), 2)'
      WHEN 'avg_price_from' THEN 'round(avg(NULLIF((pc.data->>''current_price_from'')::numeric, 0)), 0)'
      WHEN 'total_units' THEN 'coalesce(sum((pc.data->>''suites'')::integer), 0)::numeric'
      ELSE 'count(*)::numeric'
    END,
    -- filters
    CASE WHEN filter_city IS NOT NULL THEN format(' AND pc.city = %L', filter_city) ELSE '' END,
    CASE WHEN filter_neighbourhood IS NOT NULL THEN format(' AND pc.neighbourhood = %L', filter_neighbourhood) ELSE '' END,
    CASE WHEN filter_status IS NOT NULL THEN format(' AND pc.sales_status ILIKE ''%%%s%%''', filter_status) ELSE '' END,
    CASE WHEN filter_building_type IS NOT NULL THEN format(' AND pc.building_type = %L', filter_building_type) ELSE '' END,
    -- having clause
    CASE group_by_field
      WHEN 'occupancy_year' THEN '(regexp_match(pc.occupancy_date, ''(\d{4})''))[1]'
      ELSE '1'
    END,
    result_limit
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ── Grants ────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.chart_units_by_year(integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chart_avg_psf_by_status(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chart_avg_price_by_bedroom(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chart_developer_performance(integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chart_generic_aggregate(text, text, text, text, text, text, integer) TO anon, authenticated;

-- ── Saved chart configurations table ──────────────────────────
CREATE TABLE IF NOT EXISTS public.chart_configs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name        text NOT NULL,
  chart_type  text NOT NULL,
  config      jsonb NOT NULL DEFAULT '{}',
  is_template boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chart_configs_user ON public.chart_configs(user_id);
CREATE INDEX IF NOT EXISTS idx_chart_configs_template ON public.chart_configs(is_template) WHERE is_template = true;

ALTER TABLE public.chart_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own chart configs"
  ON public.chart_configs FOR ALL
  USING (auth.uid() = user_id);

CREATE POLICY "Anyone can read template charts"
  ON public.chart_configs FOR SELECT
  USING (is_template = true);

CREATE POLICY "Service role full access on chart_configs"
  ON public.chart_configs FOR ALL
  USING (auth.role() = 'service_role');

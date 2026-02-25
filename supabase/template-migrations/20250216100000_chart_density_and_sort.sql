-- ================================================================
-- Chart Builder Upgrade: Data Density + Sort Controls
-- Adds exclude_zeros, sort_field, sort_direction to generic aggregate.
-- All new params have defaults — backward compatible with existing calls.
-- Uses positional refs (1=dimension, 2=value) for GROUP BY / ORDER BY
-- since column aliases are not visible in dynamic SQL EXECUTE.
-- ================================================================

-- Drop ALL possible old signatures to avoid overloading conflicts
DROP FUNCTION IF EXISTS public.chart_generic_aggregate(text, text, text, text, text, text, integer);
DROP FUNCTION IF EXISTS public.chart_generic_aggregate(text, text, text, text, text, text, integer, boolean, text, text);

CREATE OR REPLACE FUNCTION public.chart_generic_aggregate(
  group_by_field text,
  measure text,
  filter_city text DEFAULT NULL,
  filter_neighbourhood text DEFAULT NULL,
  filter_status text DEFAULT NULL,
  filter_building_type text DEFAULT NULL,
  result_limit integer DEFAULT 100,
  exclude_zeros boolean DEFAULT false,
  sort_field text DEFAULT 'value',
  sort_direction text DEFAULT 'desc'
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
     GROUP BY 1
     HAVING %s IS NOT NULL %s
     ORDER BY %s %s
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
    -- having: dimension not null (use the raw expression, not alias)
    CASE group_by_field
      WHEN 'occupancy_year' THEN '(regexp_match(pc.occupancy_date, ''(\d{4})''))[1]'
      ELSE '1'
    END,
    -- having: exclude zeros (use positional ref 2 = value column)
    CASE WHEN exclude_zeros THEN ' AND 2 > 0' ELSE '' END,
    -- order by field (positional: 1=dimension, 2=value)
    CASE sort_field
      WHEN 'dimension' THEN '1'
      ELSE '2'
    END,
    -- order by direction
    CASE WHEN sort_direction = 'asc' THEN 'ASC' ELSE 'DESC' END,
    -- limit
    result_limit
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Re-grant with new signature
GRANT EXECUTE ON FUNCTION public.chart_generic_aggregate(
  text, text, text, text, text, text, integer, boolean, text, text
) TO anon, authenticated;

-- ============================================================
-- Map Projects RPC — Slim projection for fast map loading
-- ============================================================
-- Returns only the fields the map needs from project_cache,
-- avoiding full JSONB transfer. ~200 bytes/project vs ~2KB.
-- Uses the indexed has_location column for fast filtering.

CREATE OR REPLACE FUNCTION get_map_projects()
RETURNS TABLE (
  id          integer,
  name        text,
  lat         double precision,
  lng         double precision,
  current_sales_status  text,
  current_price_from    text,
  current_price_to      text,
  price_per_sqft        double precision,
  building_type         text,
  city_name             text,
  neighbourhood_name    text,
  developer_name        text,
  address               text,
  bedrooms_info         jsonb,
  media                 jsonb
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pc.id,
    pc.name,
    (pc.data->'location'->'coordinates'->>1)::double precision  AS lat,
    (pc.data->'location'->'coordinates'->>0)::double precision  AS lng,
    pc.sales_status                                             AS current_sales_status,
    pc.data->>'current_price_from'                              AS current_price_from,
    pc.data->>'current_price_to'                                AS current_price_to,
    (pc.data->>'price_per_sqft')::double precision              AS price_per_sqft,
    pc.building_type,
    pc.city                                                     AS city_name,
    pc.neighbourhood                                            AS neighbourhood_name,
    pc.developer                                                AS developer_name,
    pc.data->>'address'                                         AS address,
    pc.data->'bedrooms_info'                                    AS bedrooms_info,
    CASE
      WHEN jsonb_array_length(COALESCE(pc.data->'media', '[]'::jsonb)) > 0
      THEN jsonb_build_array(pc.data->'media'->0)
      ELSE '[]'::jsonb
    END                                                         AS media
  FROM project_cache pc
  WHERE pc.has_location = true
    AND pc.sales_status IS NOT NULL
    AND LOWER(pc.sales_status) NOT IN ('cancelled', 'sold out', 'on hold');
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_map_projects() IS
  'Returns slim project data for the map view (~200 bytes/row vs 2KB+ for full JSONB). Uses indexed has_location column.';

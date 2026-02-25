-- ================================================================
-- 022: Project Cache — local Supabase cache of Red Bricks API data
-- Optional feature: enable with ENABLE_PROJECT_CACHE=true env var.
-- Replaces 300+ API calls per page with single Supabase queries.
-- ================================================================

CREATE TABLE IF NOT EXISTS project_cache (
  id              integer PRIMARY KEY,           -- Red Bricks project ID
  data            jsonb NOT NULL,                -- Full project JSON from API

  -- Generated columns for indexed queries (extracted at write time, not query time)
  name            text GENERATED ALWAYS AS (data->>'name') STORED,
  sales_status    text GENERATED ALWAYS AS (data->>'current_sales_status') STORED,
  city            text GENERATED ALWAYS AS (data->>'city_name') STORED,
  neighbourhood   text GENERATED ALWAYS AS (data->>'neighbourhood_name') STORED,
  developer       text GENERATED ALWAYS AS (data->>'developer_name') STORED,
  building_type   text GENERATED ALWAYS AS (data->>'building_type') STORED,
  occupancy_date  text GENERATED ALWAYS AS (data->>'occupancy_date') STORED,
  has_location    boolean GENERATED ALWAYS AS (
    data->'location'->'coordinates' IS NOT NULL
  ) STORED,
  has_media       boolean GENERATED ALWAYS AS (
    jsonb_array_length(COALESCE(data->'media', '[]'::jsonb)) > 0
  ) STORED,
  synced_at       timestamptz NOT NULL DEFAULT now()
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_pc_sales_status ON project_cache (sales_status);
CREATE INDEX IF NOT EXISTS idx_pc_city ON project_cache (city);
CREATE INDEX IF NOT EXISTS idx_pc_neighbourhood ON project_cache (neighbourhood);
CREATE INDEX IF NOT EXISTS idx_pc_developer ON project_cache (developer);
CREATE INDEX IF NOT EXISTS idx_pc_building_type ON project_cache (building_type);
CREATE INDEX IF NOT EXISTS idx_pc_occupancy_date ON project_cache (occupancy_date);
CREATE INDEX IF NOT EXISTS idx_pc_has_location ON project_cache (has_location) WHERE has_location = true;
CREATE INDEX IF NOT EXISTS idx_pc_synced_at ON project_cache (synced_at);

-- Full-text search index
CREATE INDEX IF NOT EXISTS idx_pc_fts ON project_cache USING gin (
  to_tsvector('english',
    COALESCE(data->>'name', '') || ' ' ||
    COALESCE(data->>'developer_name', '') || ' ' ||
    COALESCE(data->>'architect_name', '') || ' ' ||
    COALESCE(data->>'city_name', '') || ' ' ||
    COALESCE(data->>'neighbourhood_name', '')
  )
);

-- RLS: public read, service role write
ALTER TABLE project_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read access" ON project_cache
  FOR SELECT USING (true);

CREATE POLICY "Service role write" ON project_cache
  FOR ALL USING (auth.role() = 'service_role');

-- Full-text search RPC function
CREATE OR REPLACE FUNCTION search_project_cache(
  search_query text,
  result_limit integer DEFAULT 10
)
RETURNS SETOF jsonb
LANGUAGE sql STABLE
AS $$
  SELECT data
  FROM project_cache
  WHERE to_tsvector('english',
    COALESCE(data->>'name', '') || ' ' ||
    COALESCE(data->>'developer_name', '') || ' ' ||
    COALESCE(data->>'architect_name', '') || ' ' ||
    COALESCE(data->>'city_name', '') || ' ' ||
    COALESCE(data->>'neighbourhood_name', '')
  ) @@ plainto_tsquery('english', search_query)
  ORDER BY ts_rank(
    to_tsvector('english',
      COALESCE(data->>'name', '') || ' ' ||
      COALESCE(data->>'developer_name', '') || ' ' ||
      COALESCE(data->>'city_name', '')
    ),
    plainto_tsquery('english', search_query)
  ) DESC
  LIMIT result_limit;
$$;

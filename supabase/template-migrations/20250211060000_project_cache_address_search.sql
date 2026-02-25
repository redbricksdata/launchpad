-- ================================================================
-- 023: Add address to project cache full-text search
-- Enables searching by street address (e.g. "123 King St")
-- ================================================================

-- Drop and recreate full-text search index with address included
DROP INDEX IF EXISTS idx_pc_fts;
CREATE INDEX idx_pc_fts ON project_cache USING gin (
  to_tsvector('english',
    COALESCE(data->>'name', '') || ' ' ||
    COALESCE(data->>'developer_name', '') || ' ' ||
    COALESCE(data->>'architect_name', '') || ' ' ||
    COALESCE(data->>'city_name', '') || ' ' ||
    COALESCE(data->>'neighbourhood_name', '') || ' ' ||
    COALESCE(data->>'address', '')
  )
);

-- Update search RPC to include address in matching and ranking
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
    COALESCE(data->>'neighbourhood_name', '') || ' ' ||
    COALESCE(data->>'address', '')
  ) @@ plainto_tsquery('english', search_query)
  ORDER BY ts_rank(
    to_tsvector('english',
      COALESCE(data->>'name', '') || ' ' ||
      COALESCE(data->>'address', '') || ' ' ||
      COALESCE(data->>'developer_name', '') || ' ' ||
      COALESCE(data->>'city_name', '')
    ),
    plainto_tsquery('english', search_query)
  ) DESC
  LIMIT result_limit;
$$;

-- ================================================================
-- 024: Enable prefix (autocomplete) matching in project cache search
--
-- Previously used plainto_tsquery() which requires complete words:
--   "kar" would NOT match "Karma Condos"
--
-- Now uses to_tsquery() with :* prefix operator on the last word:
--   "kar" → 'kar':* → matches "Karma Condos" ✓
--   "karma con" → 'karma' & 'con':* → matches "Karma Condos" ✓
--
-- Also adds ILIKE fallback for queries that produce no tsquery results
-- (e.g. single special characters or very short queries).
-- ================================================================

CREATE OR REPLACE FUNCTION search_project_cache(
  search_query text,
  result_limit integer DEFAULT 10
)
RETURNS SETOF jsonb
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  sanitized text;
  words text[];
  prefix_query tsquery;
  search_doc_sql text;
BEGIN
  -- Sanitize: keep only alphanumeric and spaces
  sanitized := regexp_replace(trim(search_query), '[^a-zA-Z0-9\s]', '', 'g');

  -- If nothing left after sanitizing, return empty
  IF sanitized = '' THEN
    RETURN;
  END IF;

  -- Split into words
  words := regexp_split_to_array(sanitized, '\s+');

  -- Build tsquery: all words joined with & (AND), last word gets :* (prefix)
  -- e.g. "karma con" → 'karma' & 'con':*
  IF array_length(words, 1) = 1 THEN
    prefix_query := to_tsquery('english', words[1] || ':*');
  ELSE
    prefix_query := to_tsquery('english',
      array_to_string(words[1:array_length(words,1)-1], ' & ') ||
      ' & ' ||
      words[array_length(words,1)] || ':*'
    );
  END IF;

  -- Try full-text search with prefix matching first
  RETURN QUERY
    SELECT data
    FROM project_cache
    WHERE to_tsvector('english',
      COALESCE(data->>'name', '') || ' ' ||
      COALESCE(data->>'developer_name', '') || ' ' ||
      COALESCE(data->>'architect_name', '') || ' ' ||
      COALESCE(data->>'city_name', '') || ' ' ||
      COALESCE(data->>'neighbourhood_name', '') || ' ' ||
      COALESCE(data->>'address', '')
    ) @@ prefix_query
    ORDER BY ts_rank(
      to_tsvector('english',
        COALESCE(data->>'name', '') || ' ' ||
        COALESCE(data->>'address', '') || ' ' ||
        COALESCE(data->>'developer_name', '') || ' ' ||
        COALESCE(data->>'city_name', '')
      ),
      prefix_query
    ) DESC
    LIMIT result_limit;

EXCEPTION WHEN OTHERS THEN
  -- If tsquery parsing fails (e.g. stop words only), fall back to ILIKE
  RETURN QUERY
    SELECT data
    FROM project_cache
    WHERE
      data->>'name' ILIKE '%' || sanitized || '%' OR
      data->>'developer_name' ILIKE '%' || sanitized || '%' OR
      data->>'city_name' ILIKE '%' || sanitized || '%' OR
      data->>'neighbourhood_name' ILIKE '%' || sanitized || '%' OR
      data->>'address' ILIKE '%' || sanitized || '%'
    LIMIT result_limit;
END;
$$;

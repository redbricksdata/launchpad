-- ============================================================
-- Market Intelligence — Enhanced Signal Tracking
-- ============================================================
-- Adds 4 new entity types to page_views for market intelligence:
--   map_filter      — map filter interactions (price, beds, neighbourhood, etc.)
--   search_filter   — search page filter changes
--   compare_view    — actual comparison page views (not just "add to compare")
--   map_layer       — map layer activations (transit, heatmap, 3D)
-- ============================================================

-- ── Update CHECK constraint to allow new entity types ─────────
DO $$
BEGIN
  -- Drop existing constraint
  BEGIN
    ALTER TABLE page_views DROP CONSTRAINT IF EXISTS page_views_entity_type_check;
  EXCEPTION WHEN undefined_object THEN NULL;
  END;
  -- Also try unnamed check constraints
  BEGIN
    EXECUTE (
      SELECT 'ALTER TABLE page_views DROP CONSTRAINT ' || quote_ident(conname)
      FROM pg_constraint
      WHERE conrelid = 'page_views'::regclass
        AND contype = 'c'
        AND pg_get_constraintdef(oid) LIKE '%entity_type%'
      LIMIT 1
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $$;

ALTER TABLE page_views ADD CONSTRAINT page_views_entity_type_check
  CHECK (entity_type IN (
    'project', 'floorplan', 'contact_request', 'share', 'appointment',
    'search', 'calculator', 'pdf', 'compare', 'chat',
    'map_filter', 'search_filter', 'compare_view', 'map_layer'
  ));

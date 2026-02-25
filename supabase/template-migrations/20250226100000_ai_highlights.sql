-- Add AI highlights columns to project_cache for on-demand generation
-- Highlights are generated via Gemini 2.0 Flash when a project page
-- is visited and no highlights exist yet.

ALTER TABLE project_cache
  ADD COLUMN IF NOT EXISTS ai_highlights text,
  ADD COLUMN IF NOT EXISTS ai_highlights_generated_at timestamptz;

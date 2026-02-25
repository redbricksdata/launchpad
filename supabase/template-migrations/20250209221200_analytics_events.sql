-- Migration 004: Expand analytics tracking
-- Adds support for contact_request and share event types
-- Adds admin read policies on likes and favorites tables

-- 1. Expand entity_type CHECK constraint to include new event types
ALTER TABLE public.page_views DROP CONSTRAINT IF EXISTS page_views_entity_type_check;
ALTER TABLE public.page_views ADD CONSTRAINT page_views_entity_type_check
  CHECK (entity_type IN ('project', 'floorplan', 'contact_request', 'share'));

-- 2. Make entity_id nullable (contact requests / shares without a specific entity)
ALTER TABLE public.page_views ALTER COLUMN entity_id DROP NOT NULL;

-- 3. Index on user_email for user profile lookups
CREATE INDEX IF NOT EXISTS page_views_user_email_idx
  ON public.page_views (user_email) WHERE user_email IS NOT NULL;

-- 4. Admin read access on likes and favorites for analytics dashboard
CREATE POLICY "Admins can read all likes"
  ON public.likes FOR SELECT
  USING (public.is_admin());

CREATE POLICY "Admins can read all favorites"
  ON public.favorites FOR SELECT
  USING (public.is_admin());

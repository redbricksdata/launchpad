-- ============================================================
-- 020: Neighbourhood Content Pages
-- SEO-rich neighbourhood pages with admin-editable content
-- ============================================================

CREATE TABLE public.neighbourhood_content (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  neighbourhood_slug text UNIQUE NOT NULL,
  neighbourhood_name text NOT NULL,
  description text,              -- AI-generated or hand-written HTML content
  highlights text[],             -- e.g. ["Great transit", "Vibrant nightlife"]
  meta_description text,         -- SEO meta description
  hero_image text,               -- URL
  published boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE public.neighbourhood_content ENABLE ROW LEVEL SECURITY;

-- Public can read published content
CREATE POLICY "Anyone can read published neighbourhood content"
  ON public.neighbourhood_content FOR SELECT
  USING (published = true);

-- Admins can do everything
CREATE POLICY "Admins can manage neighbourhood content"
  ON public.neighbourhood_content FOR ALL
  USING (public.is_admin());

-- Helper function (safe to re-create if it already exists)
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Auto-update updated_at
CREATE TRIGGER set_neighbourhood_content_updated_at
  BEFORE UPDATE ON public.neighbourhood_content
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at();

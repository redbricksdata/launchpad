-- Site Configuration Table
-- Stores all runtime-configurable site settings (branding, theme, layout, features).
-- Same key-value pattern as chat_settings.

CREATE TABLE IF NOT EXISTS public.site_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  value jsonb NOT NULL DEFAULT '{}',
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Auto-update timestamp trigger (reuse existing function if available)
CREATE OR REPLACE TRIGGER update_site_config_updated_at
  BEFORE UPDATE ON public.site_config
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE public.site_config ENABLE ROW LEVEL SECURITY;

-- Anyone can read site config (needed for public pages to load theme/branding)
CREATE POLICY "Anyone can read site_config"
  ON public.site_config FOR SELECT
  USING (true);

-- Only admins can modify site config
CREATE POLICY "Admins can insert site_config"
  ON public.site_config FOR INSERT
  WITH CHECK (is_admin());

CREATE POLICY "Admins can update site_config"
  ON public.site_config FOR UPDATE
  USING (is_admin());

CREATE POLICY "Admins can delete site_config"
  ON public.site_config FOR DELETE
  USING (is_admin());

-- Seed with defaults matching the current hardcoded values
INSERT INTO public.site_config (key, value) VALUES
  ('branding', '{
    "siteName": "Red Bricks",
    "logoUrl": null,
    "faviconUrl": null
  }'::jsonb),

  ('theme', '{
    "preset": "luxury-blue",
    "colors": {
      "primary": {
        "50": "#f0f4f8", "100": "#d9e2ec", "200": "#bcccdc", "300": "#9fb3c8",
        "400": "#829ab1", "500": "#627d98", "600": "#486581", "700": "#334e68",
        "800": "#243b53", "900": "#102a43"
      },
      "accent": {
        "50": "#fff8f0", "100": "#feebc8", "200": "#fbd38d", "300": "#f6ad55",
        "400": "#ed8936", "500": "#dd6b20", "600": "#c05621", "700": "#9c4221",
        "800": "#7b341e", "900": "#652b19"
      },
      "surface": "#ffffff",
      "surfaceSecondary": "#f8f9fa",
      "surfaceTertiary": "#f1f3f5",
      "border": "#e9ecef",
      "borderStrong": "#dee2e6",
      "textPrimary": "#1a1a2e",
      "textSecondary": "#495057",
      "textMuted": "#868e96",
      "statusSelling": "#38a169",
      "statusPlatinum": "#805ad5",
      "statusLaunching": "#3182ce",
      "statusSoldOut": "#e53e3e",
      "statusConstruction": "#d69e2e"
    },
    "fonts": {
      "heading": "Google Sans Flex",
      "body": "Inter"
    },
    "borderRadius": "0.75rem"
  }'::jsonb),

  ('hero', '{
    "heading": "Discover Pre-Construction Living",
    "subheading": "Explore pre-construction condos, townhouses, and homes across Canada",
    "backgroundImage": "/hero-bg.svg",
    "showSearch": true,
    "showTrending": true
  }'::jsonb),

  ('homepage_sections', '[
    { "type": "recently_viewed", "enabled": true, "title": "Recently Viewed", "description": "" },
    { "type": "recently_viewed_floorplans", "enabled": true, "title": "Recently Viewed Floorplans", "description": "" },
    { "type": "recommended", "enabled": true, "title": "Recommended For You", "description": "" },
    { "type": "platinum_high_rise", "enabled": true, "title": "Platinum Access \u2014 High Rise", "description": "Exclusive early access to high-rise condo developments" },
    { "type": "platinum_low_rise", "enabled": true, "title": "Platinum Access \u2014 Low Rise", "description": "Exclusive early access to townhomes and single family homes" },
    { "type": "launching_soon", "enabled": true, "title": "Launching Soon", "description": "New developments about to hit the market" },
    { "type": "closing_this_year", "enabled": true, "title": "Closing This Year", "description": "Projects with occupancy scheduled for this year" }
  ]'::jsonb),

  ('navigation', '{
    "items": [
      { "label": "Home", "href": "/", "enabled": true },
      { "label": "Explore", "href": "/search", "enabled": true },
      { "label": "Map", "href": "/map", "enabled": true },
      { "label": "Blog", "href": "/blog", "enabled": true }
    ]
  }'::jsonb),

  ('features', '{
    "chat": true,
    "compare": true,
    "favorites": true,
    "likes": true,
    "appointments": true,
    "blog": true,
    "map": true,
    "search": true,
    "floorplans": true,
    "notifications": true
  }'::jsonb)
ON CONFLICT (key) DO NOTHING;
